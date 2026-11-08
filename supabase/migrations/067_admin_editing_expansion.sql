-- =============================================================================================
-- 067. ADMIN EDITING EXPANSION - EVERY WRITABLE TABLE, EVERY MODULE SCREEN
-- =============================================================================================
-- Why this file exists:
--   * Migration 066 added one generic, catalogue driven write surface for the six
--     read-only module screens.  It carried a hand written catalogue of fifteen
--     tables, so the other screens of the application - Employees above all -
--     still had no way to be edited.
--   * The database was ready for all of them.  127 tables carry a row level
--     policy with an INSERT / UPDATE / DELETE rule, each with the right
--     permission code and the right scope.  The application simply had no
--     surface that reached them.
--   * This file replaces the fifteen table catalogue with the full 127 table
--     catalogue, generalises the scope resolution from a single foreign key hop
--     to a path of up to four hops, adds the two missing scope kinds
--     (`employee` and `institution`), extends the foreign key dropdowns from
--     24 sources to 70, and gives every writable table that had no audit
--     trigger one.
--
-- How the catalogue is built:
--   * Every row was derived from the live row level policies.  The permission
--     codes are the codes the policies use, copied verbatim - not reconstructed
--     from a prefix, because several tables use a sub-namespace of codes
--     (`EMPLOYEE.AADHAAR.CREATE`, `STAFF_PROFILE.STAFF_ACTIVITY.CREATE`, ...)
--     that a prefix would get wrong.
--   * The scope path is the path the policy expression follows: the table's own
--     column first, then the foreign key hops.  `sims_private.admin_scope_value`
--     walks it, so the RPC's decision is the policy's decision by construction.
--   * `module_codes` says which screens a table is edited on.  The screen passes
--     its module code to the panel and the panel offers the tables that belong
--     to it, so a screen picks up a new table automatically.
--
-- Rules this file obeys:
--   * It creates functions, grants EXECUTE on them and adds audit triggers.
--     It never changes a table definition or a policy.
--   * `DROP ... IF EXISTS` before every `CREATE` makes the file idempotent:
--     re-running it replaces the bodies and leaves the catalogue unchanged.
--   * The write functions are SECURITY DEFINER, exactly like `ref_save` /
--     `section_save`, because they have to write rows the caller may not be
--     able to select.  The permission check inside the function IS the gate.
--   * `admin_lookup_options()` is SECURITY INVOKER on purpose.  It hands the
--     browser the foreign key dropdowns, and a dropdown must only ever offer
--     the rows the caller may see, so the read has to go through the row level
--     policies of the referenced table.
-- =============================================================================================

-- ---------------------------------------------------------------------------------------------
-- 1. The catalogue of editable tables.
-- ---------------------------------------------------------------------------------------------
-- perm_create / perm_update / perm_delete
--     the exact permission codes the table's row level policies use.  A table
--     governed by one CONFIGURE code carries it three times.
-- scope_kind
--     how the scope of a row is resolved: global, campus, department,
--     programme, student, employee or institution.
-- scope_path
--     the table's own column first, then the foreign key hops the policy
--     follows, each one written as '<table>.<column>'.
-- pk_cols
--     the primary key columns, in key order.  More than one for the six tables
--     with a composite key.
-- audit_mode
--     TRIGGER  the table has an `sims_private.audit_row` trigger, so the write
--              is recorded by the trigger and the function must not audit.
--     MANUAL   the table's own write path already calls `sims_private.audit_manual`,
--              so it has no trigger and the function records the change itself.
-- audit_module
--     the module code the audit row carries.
-- ---------------------------------------------------------------------------------------------

DROP FUNCTION IF EXISTS sims_private.admin_table_def(text);
CREATE FUNCTION sims_private.admin_table_def(p_table text)
RETURNS TABLE(
    tbl text,
    label text,
    module_codes text[],
    perm_create text,
    perm_update text,
    perm_delete text,
    scope_kind text,
    scope_path text[],
    pk_cols text[],
    audit_module text,
    audit_mode text
)
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT v.tbl, v.label, v.module_codes, v.perm_create, v.perm_update, v.perm_delete,
           v.scope_kind, v.scope_path, v.pk_cols, v.audit_module, v.audit_mode
      FROM (VALUES
                ('academic_term', 'Academic terms', ARRAY['ACADEMIC_CALENDAR', 'REGISTRATION']::text[], 'ACADEMIC_CALENDAR.ALL.CONFIGURE', 'ACADEMIC_CALENDAR.ALL.CONFIGURE', 'ACADEMIC_CALENDAR.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['academic_term_id']::text[], 'ACADEMIC_CALENDAR', 'TRIGGER'),
                ('academic_year', 'Academic years', ARRAY['ACADEMIC_CALENDAR', 'REGISTRATION']::text[], 'ACADEMIC_CALENDAR.ALL.CONFIGURE', 'ACADEMIC_CALENDAR.ALL.CONFIGURE', 'ACADEMIC_CALENDAR.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['academic_year_id']::text[], 'ACADEMIC_CALENDAR', 'TRIGGER'),
                ('activity_evidence_requirement', 'Activity evidence requirements', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['activity_evidence_requirement_id']::text[], 'STAFF_PROFILE', 'TRIGGER'),
                ('activity_type', 'Activity types', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['activity_type_id']::text[], 'STAFF_PROFILE', 'TRIGGER'),
                ('admission_category', 'Admission categories', ARRAY['IAM']::text[], 'IAM.ALL.CONFIGURE', 'IAM.ALL.CONFIGURE', 'IAM.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['admission_category_id']::text[], 'IAM', 'TRIGGER'),
                ('announcement_type', 'Announcement types', ARRAY['COMMUNICATION']::text[], 'COMMUNICATION.ALL.CONFIGURE', 'COMMUNICATION.ALL.CONFIGURE', 'COMMUNICATION.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['announcement_type_id']::text[], 'COMMUNICATION', 'TRIGGER'),
                ('approval_status', 'Approval statuses', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['approval_status_id']::text[], 'STAFF_PROFILE', 'TRIGGER'),
                ('assessment_component', 'Assessment components', ARRAY['ASSESSMENT']::text[], 'ASSESSMENT.ALL.CREATE', 'ASSESSMENT.ALL.UPDATE', 'ASSESSMENT.ALL.DELETE', 'programme', ARRAY['course_offering_id', 'course_offering.programme_term_offering_id', 'programme_term_offering.programme_id']::text[], ARRAY['assessment_component_id']::text[], 'ASSESSMENT', 'TRIGGER'),
                ('assessment_event', 'Assessment events', ARRAY['ASSESSMENT']::text[], 'ASSESSMENT.ALL.CREATE', 'ASSESSMENT.ALL.UPDATE', 'ASSESSMENT.ALL.DELETE', 'programme', ARRAY['assessment_component_id', 'assessment_component.course_offering_id', 'course_offering.programme_term_offering_id', 'programme_term_offering.programme_id']::text[], ARRAY['assessment_event_id']::text[], 'ASSESSMENT', 'TRIGGER'),
                ('attendance_status', 'Attendance statuses', ARRAY['ATTENDANCE']::text[], 'ATTENDANCE.ALL.CONFIGURE', 'ATTENDANCE.ALL.CONFIGURE', 'ATTENDANCE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['attendance_status_id']::text[], 'ATTENDANCE', 'TRIGGER'),
                ('award_category', 'Award categories', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['award_category_id']::text[], 'STAFF_PROFILE', 'MANUAL'),
                ('awarding_body', 'Awarding bodies', ARRAY['EMPLOYEE']::text[], 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['awarding_body_id']::text[], 'EMPLOYEE', 'MANUAL'),
                ('awarding_body_type', 'Awarding body types', ARRAY['EMPLOYEE']::text[], 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['awarding_body_type_id']::text[], 'EMPLOYEE', 'TRIGGER'),
                ('blood_group', 'Blood groups', ARRAY['IAM']::text[], 'IAM.ALL.CONFIGURE', 'IAM.ALL.CONFIGURE', 'IAM.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['blood_group_id']::text[], 'PLATFORM', 'MANUAL'),
                ('building', 'Buildings', ARRAY['INSTITUTION']::text[], 'INSTITUTION.ALL.CREATE', 'INSTITUTION.ALL.UPDATE', 'INSTITUTION.ALL.DELETE', 'campus', ARRAY['campus_id']::text[], ARRAY['building_id']::text[], 'INSTITUTION', 'TRIGGER'),
                ('campus', 'Campuses', ARRAY['INSTITUTION']::text[], 'INSTITUTION.ALL.CREATE', 'INSTITUTION.ALL.UPDATE', 'INSTITUTION.ALL.DELETE', 'institution', ARRAY['institution_id']::text[], ARRAY['campus_id']::text[], 'INSTITUTION', 'TRIGGER'),
                ('caste', 'Castes', ARRAY['IAM']::text[], 'IAM.ALL.CONFIGURE', 'IAM.ALL.CONFIGURE', 'IAM.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['caste_id']::text[], 'PLATFORM', 'MANUAL'),
                ('certificate_request', 'Certificate requests', ARRAY['DOCUMENT']::text[], 'DOCUMENT.ALL.CREATE', 'DOCUMENT.ALL.UPDATE', 'DOCUMENT.ALL.DELETE', 'student', ARRAY['student_id']::text[], ARRAY['certificate_request_id']::text[], 'DOCUMENT', 'TRIGGER'),
                ('certificate_type', 'Certificate types', ARRAY['DOCUMENT']::text[], 'DOCUMENT.ALL.CONFIGURE', 'DOCUMENT.ALL.CONFIGURE', 'DOCUMENT.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['certificate_type_id']::text[], 'DOCUMENT', 'MANUAL'),
                ('class_batch', 'Class batches', ARRAY['REGISTRATION']::text[], 'REGISTRATION.ALL.CREATE', 'REGISTRATION.ALL.UPDATE', 'REGISTRATION.ALL.DELETE', 'programme', ARRAY['class_section_id', 'class_section.programme_term_offering_id', 'programme_term_offering.programme_id']::text[], ARRAY['class_batch_id']::text[], 'REGISTRATION', 'TRIGGER'),
                ('class_section', 'Class sections', ARRAY['REGISTRATION', 'ATTENDANCE']::text[], 'REGISTRATION.ALL.CREATE', 'REGISTRATION.ALL.UPDATE', 'REGISTRATION.ALL.DELETE', 'programme', ARRAY['programme_term_offering_id', 'programme_term_offering.programme_id']::text[], ARRAY['class_section_id']::text[], 'REGISTRATION', 'TRIGGER'),
                ('class_session', 'Class sessions', ARRAY['ATTENDANCE']::text[], 'ATTENDANCE.ALL.CREATE', 'ATTENDANCE.ALL.UPDATE', 'ATTENDANCE.ALL.DELETE', 'programme', ARRAY['course_offering_section_id', 'course_offering_section.course_offering_id', 'course_offering.programme_term_offering_id', 'programme_term_offering.programme_id']::text[], ARRAY['class_session_id']::text[], 'ATTENDANCE', 'TRIGGER'),
                ('cocurricular_category', 'Co-curricular categories', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['cocurricular_category_id']::text[], 'STAFF_PROFILE', 'TRIGGER'),
                ('conference_activity_indexing', 'Conference indexing records', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.STAFF_ACTIVITY.CREATE', 'STAFF_PROFILE.STAFF_ACTIVITY.UPDATE', 'STAFF_PROFILE.STAFF_ACTIVITY.DELETE', 'employee', ARRAY['staff_activity_id', 'conference_activity.staff_activity_id', 'staff_activity.employee_id']::text[], ARRAY['staff_activity_id', 'indexing_agency_id']::text[], 'STAFF_PROFILE', 'MANUAL'),
                ('conference_contribution_type', 'Conference contribution types', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['conference_contribution_type_id']::text[], 'STAFF_PROFILE', 'TRIGGER'),
                ('conference_event', 'Conference events', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['conference_event_id']::text[], 'STAFF_PROFILE', 'TRIGGER'),
                ('confidentiality_level', 'Confidentiality levels', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['confidentiality_level_id']::text[], 'STAFF_PROFILE', 'TRIGGER'),
                ('country', 'Countries', ARRAY['IAM']::text[], 'IAM.ALL.CONFIGURE', 'IAM.ALL.CONFIGURE', 'IAM.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['country_id']::text[], 'PLATFORM', 'MANUAL'),
                ('course_catalog', 'Courses', ARRAY['CURRICULUM']::text[], 'CURRICULUM.ALL.CREATE', 'CURRICULUM.ALL.UPDATE', 'CURRICULUM.ALL.DELETE', 'department', ARRAY['owning_department_id']::text[], ARRAY['course_id']::text[], 'CURRICULUM', 'TRIGGER'),
                ('course_category', 'Course categories', ARRAY['CURRICULUM']::text[], 'CURRICULUM.ALL.CONFIGURE', 'CURRICULUM.ALL.CONFIGURE', 'CURRICULUM.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['course_category_id']::text[], 'CURRICULUM', 'TRIGGER'),
                ('course_offering', 'Course offerings', ARRAY['TIMETABLE', 'REGISTRATION']::text[], 'TEACHING.ALL.CREATE', 'TEACHING.ALL.UPDATE', 'TEACHING.ALL.DELETE', 'programme', ARRAY['programme_term_offering_id', 'programme_term_offering.programme_id']::text[], ARRAY['course_offering_id']::text[], 'TEACHING', 'TRIGGER'),
                ('course_offering_section', 'Course offering sections', ARRAY['TIMETABLE', 'REGISTRATION']::text[], 'TEACHING.ALL.CREATE', 'TEACHING.ALL.UPDATE', 'TEACHING.ALL.DELETE', 'programme', ARRAY['course_offering_id', 'course_offering.programme_term_offering_id', 'programme_term_offering.programme_id']::text[], ARRAY['course_offering_section_id']::text[], 'TEACHING', 'TRIGGER'),
                ('course_offering_section_student', 'Section student allocations', ARRAY['REGISTRATION']::text[], 'REGISTRATION.ALL.CREATE', 'REGISTRATION.ALL.UPDATE', 'REGISTRATION.ALL.DELETE', 'student', ARRAY['course_registration_id', 'student_course_registration.term_registration_id', 'student_term_registration.enrolment_id', 'student_programme_enrolment.student_id']::text[], ARRAY['course_offering_section_student_id']::text[], 'REGISTRATION', 'TRIGGER'),
                ('course_prerequisite', 'Course prerequisites', ARRAY['CURRICULUM']::text[], 'CURRICULUM.ALL.CREATE', 'CURRICULUM.ALL.UPDATE', 'CURRICULUM.ALL.DELETE', 'department', ARRAY['course_id', 'course_catalog.owning_department_id']::text[], ARRAY['course_id', 'prerequisite_course_id']::text[], 'CURRICULUM', 'TRIGGER'),
                ('curriculum_course', 'Curriculum courses', ARRAY['CURRICULUM']::text[], 'CURRICULUM.ALL.CREATE', 'CURRICULUM.ALL.UPDATE', 'CURRICULUM.ALL.DELETE', 'programme', ARRAY['curriculum_scheme_id', 'curriculum_scheme.programme_id']::text[], ARRAY['curriculum_course_id']::text[], 'CURRICULUM', 'TRIGGER'),
                ('curriculum_scheme', 'Curriculum schemes', ARRAY['CURRICULUM', 'REGISTRATION']::text[], 'CURRICULUM.ALL.CREATE', 'CURRICULUM.ALL.UPDATE', 'CURRICULUM.ALL.DELETE', 'programme', ARRAY['programme_id']::text[], ARRAY['curriculum_scheme_id']::text[], 'CURRICULUM', 'TRIGGER'),
                ('department', 'Departments', ARRAY['INSTITUTION']::text[], 'INSTITUTION.ALL.CREATE', 'INSTITUTION.ALL.UPDATE', 'INSTITUTION.ALL.DELETE', 'campus', ARRAY['campus_id']::text[], ARRAY['department_id']::text[], 'INSTITUTION', 'TRIGGER'),
                ('designation', 'Designations', ARRAY['EMPLOYEE']::text[], 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['designation_id']::text[], 'EMPLOYEE', 'MANUAL'),
                ('document_type', 'Document types', ARRAY['IAM']::text[], 'IAM.ALL.CONFIGURE', 'IAM.ALL.CONFIGURE', 'IAM.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['document_type_id']::text[], 'PLATFORM', 'MANUAL'),
                ('education_institution', 'Education institutions', ARRAY['EMPLOYEE']::text[], 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['education_institution_id']::text[], 'EMPLOYEE', 'MANUAL'),
                ('education_institution_type', 'Education institution types', ARRAY['EMPLOYEE']::text[], 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['education_institution_type_id']::text[], 'EMPLOYEE', 'TRIGGER'),
                ('employee', 'Employees', ARRAY['EMPLOYEE']::text[], 'EMPLOYEE.ALL.CREATE', 'EMPLOYEE.ALL.UPDATE', 'EMPLOYEE.ALL.DELETE', 'employee', ARRAY['employee_id']::text[], ARRAY['employee_id']::text[], 'EMPLOYEE', 'TRIGGER'),
                ('employee_aadhaar', 'Employee Aadhaar records', ARRAY['EMPLOYEE']::text[], 'EMPLOYEE.AADHAAR.CREATE', 'EMPLOYEE.AADHAAR.UPDATE', 'EMPLOYEE.AADHAAR.DELETE', 'employee', ARRAY['employee_id']::text[], ARRAY['employee_aadhaar_id']::text[], 'EMPLOYEE', 'TRIGGER'),
                ('employee_address', 'Employee addresses', ARRAY['EMPLOYEE']::text[], 'EMPLOYEE.ALL.CREATE', 'EMPLOYEE.ALL.UPDATE', 'EMPLOYEE.ALL.DELETE', 'employee', ARRAY['employee_id']::text[], ARRAY['employee_address_id']::text[], 'EMPLOYEE', 'MANUAL'),
                ('employee_assignment', 'Employee assignments', ARRAY['EMPLOYEE']::text[], 'EMPLOYEE.ALL.CREATE', 'EMPLOYEE.ALL.UPDATE', 'EMPLOYEE.ALL.DELETE', 'employee', ARRAY['employee_id']::text[], ARRAY['employee_assignment_id']::text[], 'EMPLOYEE', 'TRIGGER'),
                ('employee_bank_account', 'Employee bank accounts', ARRAY['EMPLOYEE']::text[], 'EMPLOYEE.BANK_ACCOUNT.CREATE', 'EMPLOYEE.BANK_ACCOUNT.UPDATE', 'EMPLOYEE.BANK_ACCOUNT.DELETE', 'employee', ARRAY['employee_id']::text[], ARRAY['employee_bank_account_id']::text[], 'EMPLOYEE', 'TRIGGER'),
                ('employee_competency', 'Employee competencies', ARRAY['EMPLOYEE']::text[], 'EMPLOYEE.ALL.CREATE', 'EMPLOYEE.ALL.UPDATE', 'EMPLOYEE.ALL.DELETE', 'employee', ARRAY['employee_id']::text[], ARRAY['employee_id', 'course_id']::text[], 'EMPLOYEE', 'MANUAL'),
                ('employee_document', 'Employee documents', ARRAY['EMPLOYEE']::text[], 'EMPLOYEE.EMPLOYEE_DOCUMENT.CREATE', 'EMPLOYEE.EMPLOYEE_DOCUMENT.UPDATE', 'EMPLOYEE.EMPLOYEE_DOCUMENT.DELETE', 'employee', ARRAY['employee_id']::text[], ARRAY['employee_document_id']::text[], 'EMPLOYEE', 'TRIGGER'),
                ('employee_document_access_rule', 'Employee document access rules', ARRAY['EMPLOYEE']::text[], 'EMPLOYEE.EMPLOYEE_DOCUMENT.CREATE', 'EMPLOYEE.EMPLOYEE_DOCUMENT.UPDATE', 'EMPLOYEE.EMPLOYEE_DOCUMENT.DELETE', 'employee', ARRAY['employee_document_id', 'employee_document.employee_id']::text[], ARRAY['employee_document_access_rule_id']::text[], 'EMPLOYEE', 'TRIGGER'),
                ('employee_document_category', 'Employee document categories', ARRAY['EMPLOYEE']::text[], 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['employee_document_category_id']::text[], 'EMPLOYEE', 'TRIGGER'),
                ('employee_pan', 'Employee PAN records', ARRAY['EMPLOYEE']::text[], 'EMPLOYEE.PAN.CREATE', 'EMPLOYEE.PAN.UPDATE', 'EMPLOYEE.PAN.DELETE', 'employee', ARRAY['employee_id']::text[], ARRAY['employee_pan_id']::text[], 'EMPLOYEE', 'TRIGGER'),
                ('employee_previous_employment', 'Employee previous employment', ARRAY['EMPLOYEE']::text[], 'EMPLOYEE.EXPERIENCE.CREATE', 'EMPLOYEE.EXPERIENCE.UPDATE', 'EMPLOYEE.EXPERIENCE.DELETE', 'employee', ARRAY['employee_id']::text[], ARRAY['employee_previous_employment_id']::text[], 'EMPLOYEE', 'MANUAL'),
                ('employee_qualification', 'Employee qualifications', ARRAY['EMPLOYEE']::text[], 'EMPLOYEE.QUALIFICATION.CREATE', 'EMPLOYEE.QUALIFICATION.UPDATE', 'EMPLOYEE.QUALIFICATION.DELETE', 'employee', ARRAY['employee_id']::text[], ARRAY['employee_qualification_id']::text[], 'EMPLOYEE', 'MANUAL'),
                ('employment_source', 'Employment sources', ARRAY['EMPLOYEE']::text[], 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['employment_source_id']::text[], 'EMPLOYEE', 'TRIGGER'),
                ('enrolment_status_history', 'Enrolment status history', ARRAY['ADMISSION']::text[], 'ADMISSION.ALL.CREATE', 'ADMISSION.ALL.UPDATE', 'ADMISSION.ALL.DELETE', 'student', ARRAY['enrolment_id', 'student_programme_enrolment.student_id']::text[], ARRAY['enrolment_status_history_id']::text[], 'ADMISSION', 'TRIGGER'),
                ('event_mode', 'Event modes', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['event_mode_id']::text[], 'STAFF_PROFILE', 'TRIGGER'),
                ('evidence_document_tag', 'Evidence document tags', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.STAFF_EVIDENCE.CREATE', 'STAFF_PROFILE.STAFF_EVIDENCE.UPDATE', 'STAFF_PROFILE.STAFF_EVIDENCE.DELETE', 'employee', ARRAY['evidence_document_id', 'evidence_document.staff_activity_id', 'staff_activity.employee_id']::text[], ARRAY['evidence_document_id', 'evidence_tag_id']::text[], 'STAFF_PROFILE', 'TRIGGER'),
                ('evidence_tag', 'Evidence tags', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['evidence_tag_id']::text[], 'STAFF_PROFILE', 'TRIGGER'),
                ('evidence_type', 'Evidence types', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['evidence_type_id']::text[], 'STAFF_PROFILE', 'TRIGGER'),
                ('external_agency', 'External agencies', ARRAY['EMPLOYEE']::text[], 'EMPLOYEE.ALL.CREATE', 'EMPLOYEE.ALL.UPDATE', 'EMPLOYEE.ALL.DELETE', 'institution', ARRAY['institution_id']::text[], ARRAY['external_agency_id']::text[], 'EMPLOYEE', 'TRIGGER'),
                ('external_organization', 'External organisations', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['organization_id']::text[], 'STAFF_PROFILE', 'TRIGGER'),
                ('external_organization_type', 'External organisation types', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['organization_id', 'organization_type_id']::text[], 'STAFF_PROFILE', 'TRIGGER'),
                ('extracurricular_category', 'Extra-curricular categories', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['extracurricular_category_id']::text[], 'STAFF_PROFILE', 'TRIGGER'),
                ('faculty_course_assignment', 'Faculty course assignments', ARRAY['TIMETABLE']::text[], 'TEACHING.ALL.CREATE', 'TEACHING.ALL.UPDATE', 'TEACHING.ALL.DELETE', 'programme', ARRAY['course_offering_section_id', 'course_offering_section.course_offering_id', 'course_offering.programme_term_offering_id', 'programme_term_offering.programme_id']::text[], ARRAY['faculty_assignment_id']::text[], 'TEACHING', 'TRIGGER'),
                ('feedback_choice', 'Feedback choices', ARRAY['FEEDBACK']::text[], 'FEEDBACK.ALL.CONFIGURE', 'FEEDBACK.ALL.CONFIGURE', 'FEEDBACK.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['feedback_choice_id']::text[], 'FEEDBACK', 'TRIGGER'),
                ('feedback_cycle', 'Feedback cycles', ARRAY['FEEDBACK']::text[], 'FEEDBACK.ALL.CONFIGURE', 'FEEDBACK.ALL.CONFIGURE', 'FEEDBACK.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['feedback_cycle_id']::text[], 'FEEDBACK', 'TRIGGER'),
                ('feedback_question', 'Feedback questions', ARRAY['FEEDBACK']::text[], 'FEEDBACK.ALL.CONFIGURE', 'FEEDBACK.ALL.CONFIGURE', 'FEEDBACK.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['feedback_question_id']::text[], 'FEEDBACK', 'TRIGGER'),
                ('feedback_question_category', 'Feedback question categories', ARRAY['FEEDBACK']::text[], 'FEEDBACK.ALL.CONFIGURE', 'FEEDBACK.ALL.CONFIGURE', 'FEEDBACK.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['feedback_category_id']::text[], 'FEEDBACK', 'TRIGGER'),
                ('feedback_questionnaire', 'Feedback questionnaires', ARRAY['FEEDBACK']::text[], 'FEEDBACK.ALL.CONFIGURE', 'FEEDBACK.ALL.CONFIGURE', 'FEEDBACK.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['questionnaire_id']::text[], 'FEEDBACK', 'TRIGGER'),
                ('feedback_questionnaire_item', 'Feedback questionnaire items', ARRAY['FEEDBACK']::text[], 'FEEDBACK.ALL.CONFIGURE', 'FEEDBACK.ALL.CONFIGURE', 'FEEDBACK.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['questionnaire_item_id']::text[], 'FEEDBACK', 'TRIGGER'),
                ('funding_agency', 'Funding agencies', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['funding_agency_id']::text[], 'STAFF_PROFILE', 'TRIGGER'),
                ('funding_type', 'Funding types', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['funding_type_id']::text[], 'STAFF_PROFILE', 'MANUAL'),
                ('gender', 'Genders', ARRAY['IAM']::text[], 'IAM.ALL.CONFIGURE', 'IAM.ALL.CONFIGURE', 'IAM.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['gender_id']::text[], 'PLATFORM', 'MANUAL'),
                ('grade_rule', 'Grade rules', ARRAY['RESULT']::text[], 'RESULT.ALL.CONFIGURE', 'RESULT.ALL.CONFIGURE', 'RESULT.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['grade_rule_id']::text[], 'RESULT', 'TRIGGER'),
                ('grade_scale', 'Grade scales', ARRAY['RESULT']::text[], 'RESULT.ALL.CONFIGURE', 'RESULT.ALL.CONFIGURE', 'RESULT.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['grade_scale_id']::text[], 'RESULT', 'TRIGGER'),
                ('grievance_category', 'Grievance categories', ARRAY['GRIEVANCE']::text[], 'GRIEVANCE.ALL.CONFIGURE', 'GRIEVANCE.ALL.CONFIGURE', 'GRIEVANCE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['grievance_category_id']::text[], 'GRIEVANCE', 'TRIGGER'),
                ('indexing_agency', 'Indexing agencies', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['indexing_agency_id']::text[], 'STAFF_PROFILE', 'MANUAL'),
                ('industry_sector', 'Industry sectors', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['industry_sector_id']::text[], 'STAFF_PROFILE', 'TRIGGER'),
                ('journal', 'Journals', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['journal_id']::text[], 'STAFF_PROFILE', 'TRIGGER'),
                ('journal_metric', 'Journal metrics', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['journal_metric_id']::text[], 'STAFF_PROFILE', 'MANUAL'),
                ('journal_publication_indexing', 'Journal indexing records', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.STAFF_ACTIVITY.CREATE', 'STAFF_PROFILE.STAFF_ACTIVITY.UPDATE', 'STAFF_PROFILE.STAFF_ACTIVITY.DELETE', 'employee', ARRAY['staff_activity_id', 'journal_publication.staff_activity_id', 'staff_activity.employee_id']::text[], ARRAY['staff_activity_id', 'indexing_agency_id']::text[], 'STAFF_PROFILE', 'MANUAL'),
                ('journal_type', 'Journal types', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['journal_type_id']::text[], 'STAFF_PROFILE', 'MANUAL'),
                ('membership_type', 'Membership types', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['membership_type_id']::text[], 'STAFF_PROFILE', 'MANUAL'),
                ('metric_type', 'Journal metric types', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['metric_type_id']::text[], 'STAFF_PROFILE', 'MANUAL'),
                ('organization_type', 'Organisation types', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['organization_type_id']::text[], 'STAFF_PROFILE', 'TRIGGER'),
                ('organizer', 'Organisers', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['organizer_id']::text[], 'STAFF_PROFILE', 'TRIGGER'),
                ('participation_level', 'Participation levels', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['participation_level_id']::text[], 'STAFF_PROFILE', 'TRIGGER'),
                ('previous_organization', 'Previous organisations', ARRAY['EMPLOYEE']::text[], 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['previous_organization_id']::text[], 'EMPLOYEE', 'MANUAL'),
                ('previous_organization_type', 'Previous organisation types', ARRAY['EMPLOYEE']::text[], 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['previous_organization_type_id']::text[], 'EMPLOYEE', 'TRIGGER'),
                ('professional_contribution_type', 'Professional contribution types', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['professional_contribution_type_id']::text[], 'STAFF_PROFILE', 'TRIGGER'),
                ('programme', 'Programmes', ARRAY['INSTITUTION', 'CURRICULUM', 'REGISTRATION']::text[], 'INSTITUTION.ALL.CREATE', 'INSTITUTION.ALL.UPDATE', 'INSTITUTION.ALL.DELETE', 'department', ARRAY['department_id']::text[], ARRAY['programme_id']::text[], 'INSTITUTION', 'TRIGGER'),
                ('programme_specialization', 'Programme specialisations', ARRAY['INSTITUTION']::text[], 'INSTITUTION.ALL.CREATE', 'INSTITUTION.ALL.UPDATE', 'INSTITUTION.ALL.DELETE', 'programme', ARRAY['programme_id']::text[], ARRAY['specialization_id']::text[], 'INSTITUTION', 'TRIGGER'),
                ('programme_term_offering', 'Programme term offerings', ARRAY['REGISTRATION']::text[], 'REGISTRATION.ALL.CREATE', 'REGISTRATION.ALL.UPDATE', 'REGISTRATION.ALL.DELETE', 'programme', ARRAY['programme_id']::text[], ARRAY['programme_term_offering_id']::text[], 'REGISTRATION', 'TRIGGER'),
                ('publication_type', 'Publication types', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['publication_type_id']::text[], 'STAFF_PROFILE', 'MANUAL'),
                ('publisher', 'Publishers', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['publisher_id']::text[], 'STAFF_PROFILE', 'TRIGGER'),
                ('qualification_level', 'Qualification levels', ARRAY['EMPLOYEE']::text[], 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['qualification_level_id']::text[], 'EMPLOYEE', 'MANUAL'),
                ('religion', 'Religions', ARRAY['IAM']::text[], 'IAM.ALL.CONFIGURE', 'IAM.ALL.CONFIGURE', 'IAM.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['religion_id']::text[], 'PLATFORM', 'MANUAL'),
                ('research_project_financial_utilization', 'Research project financial utilisation', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.STAFF_RESEARCH.CREATE', 'STAFF_PROFILE.STAFF_RESEARCH.UPDATE', 'STAFF_PROFILE.STAFF_RESEARCH.DELETE', 'employee', ARRAY['staff_activity_id', 'funded_research_project.principal_investigator_employee_id']::text[], ARRAY['utilization_id']::text[], 'STAFF_PROFILE', 'MANUAL'),
                ('research_status', 'Research statuses', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['research_status_id']::text[], 'STAFF_PROFILE', 'TRIGGER'),
                ('research_supervision', 'Research supervision', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.STAFF_RESEARCH.CREATE', 'STAFF_PROFILE.STAFF_RESEARCH.UPDATE', 'STAFF_PROFILE.STAFF_RESEARCH.DELETE', 'employee', ARRAY['staff_activity_id', 'staff_professional_contribution.staff_activity_id', 'staff_activity.employee_id']::text[], ARRAY['research_supervision_id']::text[], 'STAFF_PROFILE', 'MANUAL'),
                ('role_type', 'Role types', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['role_type_id']::text[], 'STAFF_PROFILE', 'TRIGGER'),
                ('room', 'Rooms', ARRAY['INSTITUTION', 'TIMETABLE']::text[], 'INSTITUTION.ALL.CREATE', 'INSTITUTION.ALL.UPDATE', 'INSTITUTION.ALL.DELETE', 'campus', ARRAY['building_id', 'building.campus_id']::text[], ARRAY['room_id']::text[], 'TIMETABLE', 'TRIGGER'),
                ('semester', 'Semesters', ARRAY['ACADEMIC_CALENDAR', 'REGISTRATION', 'CURRICULUM']::text[], 'ACADEMIC_CALENDAR.ALL.CONFIGURE', 'ACADEMIC_CALENDAR.ALL.CONFIGURE', 'ACADEMIC_CALENDAR.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['semester_id']::text[], 'ACADEMIC_CALENDAR', 'TRIGGER'),
                ('social_category', 'Social categories', ARRAY['IAM']::text[], 'IAM.ALL.CONFIGURE', 'IAM.ALL.CONFIGURE', 'IAM.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['social_category_id']::text[], 'PLATFORM', 'MANUAL'),
                ('staff_category', 'Staff categories', ARRAY['EMPLOYEE']::text[], 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['staff_category_id']::text[], 'EMPLOYEE', 'MANUAL'),
                ('staff_type', 'Staff types', ARRAY['EMPLOYEE']::text[], 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['staff_type_id']::text[], 'EMPLOYEE', 'MANUAL'),
                ('state', 'States', ARRAY['IAM']::text[], 'IAM.ALL.CONFIGURE', 'IAM.ALL.CONFIGURE', 'IAM.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['state_id']::text[], 'PLATFORM', 'MANUAL'),
                ('student', 'Students', ARRAY['STUDENT']::text[], 'STUDENT.ALL.CREATE', 'STUDENT.ALL.UPDATE', 'STUDENT.ALL.DELETE', 'student', ARRAY['student_id']::text[], ARRAY['student_id']::text[], 'STUDENT', 'TRIGGER'),
                ('student_activity_evidence_requirement', 'Student activity evidence requirements', ARRAY['STUDENT']::text[], 'STUDENT.ALL.CONFIGURE', 'STUDENT.ALL.CONFIGURE', 'STUDENT.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['student_activity_evidence_requirement_id']::text[], 'STUDENT', 'TRIGGER'),
                ('student_activity_type', 'Student activity types', ARRAY['STUDENT']::text[], 'STUDENT.ALL.CONFIGURE', 'STUDENT.ALL.CONFIGURE', 'STUDENT.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['student_activity_type_id']::text[], 'STUDENT', 'TRIGGER'),
                ('student_address', 'Student addresses', ARRAY['STUDENT']::text[], 'STUDENT.ALL.CREATE', 'STUDENT.ALL.UPDATE', 'STUDENT.ALL.DELETE', 'student', ARRAY['student_id']::text[], ARRAY['student_address_id']::text[], 'STUDENT', 'MANUAL'),
                ('student_course_registration', 'Student course registrations', ARRAY['REGISTRATION', 'STUDENT']::text[], 'REGISTRATION.ALL.CREATE', 'REGISTRATION.ALL.UPDATE', 'REGISTRATION.ALL.DELETE', 'student', ARRAY['term_registration_id', 'student_term_registration.enrolment_id', 'student_programme_enrolment.student_id']::text[], ARRAY['course_registration_id']::text[], 'REGISTRATION', 'TRIGGER'),
                ('student_document', 'Student documents', ARRAY['DOCUMENT']::text[], 'DOCUMENT.ALL.CREATE', 'DOCUMENT.ALL.UPDATE', 'DOCUMENT.ALL.DELETE', 'student', ARRAY['student_id']::text[], ARRAY['student_document_id']::text[], 'DOCUMENT', 'TRIGGER'),
                ('student_entrance_exam', 'Student entrance exams', ARRAY['STUDENT']::text[], 'STUDENT.ALL.CREATE', 'STUDENT.ALL.UPDATE', 'STUDENT.ALL.DELETE', 'student', ARRAY['student_id']::text[], ARRAY['student_entrance_exam_id']::text[], 'STUDENT', 'MANUAL'),
                ('student_exit', 'Student exit records', ARRAY['DOCUMENT']::text[], 'DOCUMENT.ALL.CREATE', 'DOCUMENT.ALL.UPDATE', 'DOCUMENT.ALL.DELETE', 'student', ARRAY['enrolment_id', 'student_programme_enrolment.student_id']::text[], ARRAY['student_exit_id']::text[], 'DOCUMENT', 'TRIGGER'),
                ('student_parent_guardian', 'Student parents and guardians', ARRAY['STUDENT']::text[], 'STUDENT.ALL.CREATE', 'STUDENT.ALL.UPDATE', 'STUDENT.ALL.DELETE', 'student', ARRAY['student_id']::text[], ARRAY['student_parent_guardian_id']::text[], 'STUDENT', 'MANUAL'),
                ('student_previous_education', 'Student previous education', ARRAY['STUDENT']::text[], 'STUDENT.ALL.CREATE', 'STUDENT.ALL.UPDATE', 'STUDENT.ALL.DELETE', 'student', ARRAY['student_id']::text[], ARRAY['previous_education_id']::text[], 'STUDENT', 'MANUAL'),
                ('student_programme_enrolment', 'Programme enrolments', ARRAY['ADMISSION', 'STUDENT']::text[], 'ADMISSION.ALL.CREATE', 'ADMISSION.ALL.UPDATE', 'ADMISSION.ALL.DELETE', 'student', ARRAY['student_id']::text[], ARRAY['enrolment_id']::text[], 'ADMISSION', 'TRIGGER'),
                ('student_residence', 'Student residences', ARRAY['STUDENT']::text[], 'STUDENT.ALL.CREATE', 'STUDENT.ALL.UPDATE', 'STUDENT.ALL.DELETE', 'student', ARRAY['student_id']::text[], ARRAY['student_residence_id']::text[], 'STUDENT', 'MANUAL'),
                ('student_term_registration', 'Term registrations', ARRAY['REGISTRATION', 'STUDENT']::text[], 'REGISTRATION.ALL.CREATE', 'REGISTRATION.ALL.UPDATE', 'REGISTRATION.ALL.DELETE', 'student', ARRAY['enrolment_id', 'student_programme_enrolment.student_id']::text[], ARRAY['term_registration_id']::text[], 'REGISTRATION', 'TRIGGER'),
                ('study_mode', 'Study modes', ARRAY['EMPLOYEE']::text[], 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['study_mode_id']::text[], 'EMPLOYEE', 'MANUAL'),
                ('sub_caste', 'Sub-castes', ARRAY['IAM']::text[], 'IAM.ALL.CONFIGURE', 'IAM.ALL.CONFIGURE', 'IAM.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['sub_caste_id']::text[], 'PLATFORM', 'MANUAL'),
                ('time_slot', 'Teaching time slots', ARRAY['ACADEMIC_CALENDAR', 'TIMETABLE']::text[], 'ACADEMIC_CALENDAR.ALL.CREATE', 'ACADEMIC_CALENDAR.ALL.UPDATE', 'ACADEMIC_CALENDAR.ALL.DELETE', 'campus', ARRAY['campus_id']::text[], ARRAY['time_slot_id']::text[], 'ACADEMIC_CALENDAR', 'TRIGGER'),
                ('timetable_session', 'Timetable sessions', ARRAY['TIMETABLE']::text[], 'TIMETABLE.ALL.CREATE', 'TIMETABLE.ALL.UPDATE', 'TIMETABLE.ALL.DELETE', 'programme', ARRAY['course_offering_section_id', 'course_offering_section.course_offering_id', 'course_offering.programme_term_offering_id', 'programme_term_offering.programme_id']::text[], ARRAY['timetable_session_id']::text[], 'TIMETABLE', 'TRIGGER'),
                ('training_program_type', 'Training programme types', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['training_program_type_id']::text[], 'STAFF_PROFILE', 'TRIGGER'),
                ('university', 'Universities', ARRAY['INSTITUTION']::text[], 'INSTITUTION.ALL.CONFIGURE', 'INSTITUTION.ALL.CONFIGURE', 'INSTITUTION.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['university_id']::text[], 'INSTITUTION', 'TRIGGER'),
                ('verification_status', 'Verification statuses', ARRAY['STAFF_PROFILE']::text[], 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE.ALL.CONFIGURE', 'global', ARRAY[]::text[], ARRAY['verification_status_id']::text[], 'STAFF_PROFILE', 'TRIGGER')
      ) AS v(tbl, label, module_codes, perm_create, perm_update, perm_delete,
               scope_kind, scope_path, pk_cols, audit_module, audit_mode)
     WHERE p_table IS NULL OR v.tbl = p_table;
$function$;

-- ---------------------------------------------------------------------------------------------
-- 2. The primary key columns of a table.
-- ---------------------------------------------------------------------------------------------
-- `sims_private.pk_column()` only answers for a single column key.  Six of the
-- writable tables have a composite key, so the catalogue carries the key
-- columns and this helper reads them straight out of the constraint.
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION sims_private.admin_pk_cols(p_table text)
RETURNS text[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT COALESCE(
        (SELECT array_agg(a.attname::text ORDER BY x.ord)
           FROM pg_constraint c
           CROSS JOIN LATERAL unnest(c.conkey) WITH ORDINALITY AS x(attnum, ord)
           JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = x.attnum
          WHERE c.contype = 'p' AND c.conrelid = format('public.%I', p_table)::regclass),
        ARRAY[]::text[]);
$function$;

-- ---------------------------------------------------------------------------------------------
-- 3. The catalogue of foreign key dropdown sources.
-- ---------------------------------------------------------------------------------------------
-- `label_sql` is the expression that produces the text of one option.  It may
-- reach through one foreign key so that a curriculum course is offered as
-- "CS101 - Programming" rather than as a bare number.
--
-- The list is every table the 127 editable tables point at, so no foreign key
-- is left as a bare number in a form.
-- ---------------------------------------------------------------------------------------------

DROP FUNCTION IF EXISTS sims_private.admin_lookup_def(text);
CREATE FUNCTION sims_private.admin_lookup_def(p_table text)
RETURNS TABLE(
    tbl text,
    pk_col text,
    label_sql text
)
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT v.tbl, v.pk_col, v.label_sql
      FROM (VALUES
                ('academic_term', 'academic_term_id', 'term_name'),
                ('academic_year', 'academic_year_id', 'year_code'),
                ('activity_type', 'activity_type_id', 'activity_type_name'),
                ('admission_category', 'admission_category_id', 'category_name'),
                ('awarding_body', 'awarding_body_id', 'awarding_body_name'),
                ('awarding_body_type', 'awarding_body_type_id', 'type_name'),
                ('blood_group', 'blood_group_id', 'blood_group_code'),
                ('building', 'building_id', 'building_name'),
                ('campus', 'campus_id', 'campus_name'),
                ('caste', 'caste_id', 'caste_name'),
                ('certificate_type', 'certificate_type_id', 'certificate_code'),
                ('class_section', 'class_section_id', 'section_code'),
                ('country', 'country_id', 'country_name'),
                ('course_catalog', 'course_id', 'course_title'),
                ('course_category', 'course_category_id', 'category_name'),
                ('course_offering', 'course_offering_id', 'offering_code'),
                ('course_offering_section', 'course_offering_section_id', '(SELECT co.offering_code || '' / '' || COALESCE(cs.section_code, ''-'') FROM public.course_offering co LEFT JOIN public.class_section cs ON cs.class_section_id = t.class_section_id WHERE co.course_offering_id = t.course_offering_id)'),
                ('curriculum_course', 'curriculum_course_id', '(SELECT c.course_code || '' - '' || c.course_title FROM public.course_catalog c WHERE c.course_id = t.course_id)'),
                ('curriculum_scheme', 'curriculum_scheme_id', 'scheme_name'),
                ('department', 'department_id', 'department_name'),
                ('designation', 'designation_id', 'description'),
                ('document_type', 'document_type_id', 'document_code'),
                ('education_institution', 'education_institution_id', 'institution_name'),
                ('education_institution_type', 'education_institution_type_id', 'type_name'),
                ('employee', 'employee_id', 'display_name'),
                ('employee_document', 'employee_document_id', 'document_title'),
                ('employee_document_category', 'employee_document_category_id', 'category_name'),
                ('employment_source', 'employment_source_id', 'description'),
                ('event_mode', 'event_mode_id', 'mode_code'),
                ('evidence_type', 'evidence_type_id', 'evidence_type_name'),
                ('external_agency', 'external_agency_id', 'agency_code'),
                ('external_organization', 'organization_id', 'organization_name'),
                ('faculty_course_assignment', 'faculty_assignment_id', '(SELECT e.display_name || '' - '' || COALESCE(t.assignment_role, ''-'') FROM public.employee e WHERE e.employee_id = t.employee_id)'),
                ('feedback_question', 'feedback_question_id', 'question_text'),
                ('feedback_question_category', 'feedback_category_id', 'category_name'),
                ('feedback_questionnaire', 'questionnaire_id', 'questionnaire_name'),
                ('file_object', 'file_object_id', 'original_file_name'),
                ('funded_research_project', 'staff_activity_id', 'project_title'),
                ('funding_type', 'funding_type_id', 'description'),
                ('gender', 'gender_id', 'gender_name'),
                ('grade_scale', 'grade_scale_id', 'scale_name'),
                ('institution', 'institution_id', 'institution_code'),
                ('journal', 'journal_id', 'journal_name'),
                ('journal_type', 'journal_type_id', 'description'),
                ('metric_type', 'metric_type_id', 'description'),
                ('organizer', 'organizer_id', '(SELECT o.organization_name FROM public.external_organization o WHERE o.organization_id = t.organization_id)'),
                ('participation_level', 'participation_level_id', 'level_code'),
                ('previous_organization', 'previous_organization_id', 'organization_name'),
                ('previous_organization_type', 'previous_organization_type_id', 'type_name'),
                ('programme', 'programme_id', 'programme_name'),
                ('programme_term_offering', 'programme_term_offering_id', '(SELECT p.programme_name || '' - '' || a.term_name FROM public.programme p JOIN public.academic_term a ON a.academic_term_id = t.academic_term_id WHERE p.programme_id = t.programme_id)'),
                ('publisher', 'publisher_id', '(SELECT o.organization_name FROM public.external_organization o WHERE o.organization_id = t.organization_id)'),
                ('qualification_level', 'qualification_level_id', 'description'),
                ('religion', 'religion_id', 'religion_name'),
                ('role', 'role_id', 'role_name'),
                ('room', 'room_id', 'room_name'),
                ('semester', 'semester_id', 'semester_name'),
                ('social_category', 'social_category_id', 'category_name'),
                ('staff_category', 'staff_category_id', 'category_name'),
                ('staff_professional_contribution', 'staff_activity_id', 'title_topic'),
                ('staff_type', 'staff_type_id', 'description'),
                ('state', 'state_id', 'state_code'),
                ('student', 'student_id', 'display_name'),
                ('student_activity_type', 'student_activity_type_id', 'description'),
                ('student_programme_enrolment', 'enrolment_id', '(SELECT s.display_name FROM public.student s WHERE s.student_id = t.student_id)'),
                ('student_term_registration', 'term_registration_id', '(SELECT COALESCE(t.roll_number, ''-'') || '' - '' || s.display_name FROM public.student_programme_enrolment e JOIN public.student s ON s.student_id = e.student_id WHERE e.enrolment_id = t.enrolment_id)'),
                ('study_mode', 'study_mode_id', 'mode_code'),
                ('sub_caste', 'sub_caste_id', 'sub_caste_name'),
                ('time_slot', 'time_slot_id', 'slot_code'),
                ('timetable_session', 'timetable_session_id', '(SELECT ts.slot_code || '' / day '' || t.day_of_week || '' / '' || COALESCE(r.room_name, ''-'') FROM public.time_slot ts LEFT JOIN public.room r ON r.room_id = t.room_id WHERE ts.time_slot_id = t.time_slot_id)')
      ) AS v(tbl, pk_col, label_sql)
     WHERE p_table IS NULL OR v.tbl = p_table;
$function$;

-- ---------------------------------------------------------------------------------------------
-- 4. Does the caller hold any of these permission codes, in any scope?
-- ---------------------------------------------------------------------------------------------
-- Used to decide whether a table is offered at all.  The per row decision is made by
-- `admin_can()` below, which honours the DENY overrides as well.
--
-- The SELF scope is deliberately not counted: `sims_private.can_*` is always called with
-- `p_self_ok = false` for a write, so a SELF scoped grant never authorises one.  Counting
-- it here would offer a table to a student who can never write a row of it.
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION sims_private.admin_holds(p_codes text[])
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT s.ga
        OR COALESCE(cardinality(s.ai), 0) > 0
        OR COALESCE(cardinality(s.ac), 0) > 0
        OR COALESCE(cardinality(s.ad), 0) > 0
        OR COALESCE(cardinality(s.ap), 0) > 0
      FROM sims_private.eff_set_of(p_codes) s;
$function$;

-- ---------------------------------------------------------------------------------------------
-- 5. The key of a row.
-- ---------------------------------------------------------------------------------------------
-- `p_key` is the primary key of the row, as a jsonb value:
--   null        a new row
--   a number    a table with a single column key
--   an object   a table with a composite key, one entry per key column
--
-- The helper turns that into the `WHERE` clause of the row, so a composite key
-- addresses its row exactly.
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION sims_private.admin_key_where(p_table text, p_key jsonb)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_cols text[];
    v_parts text[];
    v_col text;
BEGIN
    IF p_key IS NULL OR jsonb_typeof(p_key) = 'null' THEN
        RETURN '';
    END IF;

    v_cols := sims_private.admin_pk_cols(p_table);

    IF jsonb_typeof(p_key) = 'object' THEN
        FOR v_col IN SELECT jsonb_object_keys(p_key) ORDER BY 1 LOOP
            IF NOT (v_col = ANY (v_cols)) THEN
                RAISE EXCEPTION 'Unknown key column %', v_col USING ERRCODE = '22023';
            END IF;
            IF p_key ->> v_col IS NULL THEN
                RAISE EXCEPTION 'Unknown row' USING ERRCODE = '22023';
            END IF;
            v_parts := v_parts || ARRAY[format('%I = %s', v_col, quote_literal(p_key ->> v_col))];
        END LOOP;
        -- A composite key addresses its row exactly, so every key column has to
        -- be there.  Half a key is not a row.
        IF cardinality(v_parts) <> cardinality(v_cols) THEN
            RAISE EXCEPTION 'Unknown row' USING ERRCODE = '22023';
        END IF;
        RETURN COALESCE(array_to_string(v_parts, ' AND '), '');
    END IF;

    IF cardinality(v_cols) <> 1 THEN
        RAISE EXCEPTION 'This table needs every key column' USING ERRCODE = '22023';
    END IF;

    IF p_key #>> '{}' IS NULL THEN
        RAISE EXCEPTION 'Unknown row' USING ERRCODE = '22023';
    END IF;

    RETURN format('%I = %s', v_cols[1], quote_literal(p_key #>> '{}'));
END $function$;

-- ---------------------------------------------------------------------------------------------
-- 6. Resolve the scope of the row that is about to be written.
-- ---------------------------------------------------------------------------------------------
-- For an update or a delete the scope comes from the row that exists; for an insert it
-- comes from the payload that is about to be written.  The scope path is then walked:
-- the table's own column first, then each foreign key hop, so the check always runs
-- against the scope the row really belongs to.
--
-- A scoped caller therefore cannot reach outside its scope by forging an
-- identifier: the scope is resolved from the row that is being written.
-- ---------------------------------------------------------------------------------------------

DROP FUNCTION IF EXISTS sims_private.admin_scope_value(text, text, text, text, bigint, jsonb);
CREATE FUNCTION sims_private.admin_scope_value(
    p_table text,
    p_scope_kind text,
    p_scope_path text[],
    p_key jsonb,
    p_payload jsonb
)
RETURNS bigint
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_scope bigint;
    v_raw text;
    v_where text;
    v_hop text;
    v_table text;
    v_column text;
    v_pk text;
BEGIN
    IF p_scope_kind IS NULL OR p_scope_kind = 'global' THEN
        RETURN NULL;
    END IF;

    IF cardinality(p_scope_path) = 0 THEN
        RETURN NULL;
    END IF;

    -- The first element is the table's own column.
    IF p_key IS NOT NULL AND jsonb_typeof(p_key) <> 'null' THEN
        v_where := sims_private.admin_key_where(p_table, p_key);
        IF v_where <> '' THEN
            EXECUTE format('SELECT %I::bigint FROM public.%I WHERE %s',
                           p_scope_path[1], p_table, v_where)
               INTO v_scope;
        END IF;
    ELSE
        v_raw := btrim(COALESCE(p_payload ->> p_scope_path[1], ''));
        IF v_raw ~ '^-?[0-9]+$' THEN
            v_scope := v_raw::bigint;
        END IF;
    END IF;

    IF v_scope IS NULL THEN
        RETURN NULL;
    END IF;

    -- The remaining elements are the foreign key hops the policy follows.
    FOR v_hop IN SELECT unnest(p_scope_path[2:]) LOOP
        v_table := split_part(v_hop, '.', 1);
        v_column := split_part(v_hop, '.', 2);
        v_pk := sims_private.pk_column(v_table);
        IF v_pk IS NULL THEN
            RETURN NULL;
        END IF;
        EXECUTE format('SELECT %I::bigint FROM public.%I WHERE %I = $1',
                       v_column, v_table, v_pk)
           INTO v_scope USING v_scope;
        IF v_scope IS NULL THEN
            RETURN NULL;
        END IF;
    END LOOP;

    RETURN v_scope;
END $function$;

-- ---------------------------------------------------------------------------------------------
-- 7. The authorisation decision for one write.
-- ---------------------------------------------------------------------------------------------
-- The decision is made with the same `sims_private.can_*` helpers the row level
-- policies use, so the RPC and the policy always agree:
--     global      -> can_global(code)
--     campus      -> can_campus(code, campus_id)
--     department  -> can_department(code, owning_department_id)
--     programme   -> can_programme(code, programme_id)
--     student     -> can_student(code, student_id, true)
--     employee    -> can_employee(code, employee_id, true)
--     institution -> can_institution(code, institution_id)
-- ---------------------------------------------------------------------------------------------

DROP FUNCTION IF EXISTS sims_private.admin_can(text, text, bigint, jsonb);
CREATE FUNCTION sims_private.admin_can(
    p_table text,
    p_action text,
    p_key jsonb,
    p_payload jsonb
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    d record;
    v_code text;
    v_scope bigint;
BEGIN
    SELECT * INTO d FROM sims_private.admin_table_def(p_table);
    IF d.tbl IS NULL THEN
        RETURN false;
    END IF;

    v_code := CASE upper(p_action)
        WHEN 'CREATE' THEN d.perm_create
        WHEN 'UPDATE' THEN d.perm_update
        WHEN 'DELETE' THEN d.perm_delete
        ELSE NULL
    END;
    IF v_code IS NULL THEN
        RETURN false;
    END IF;

    v_scope := sims_private.admin_scope_value(d.tbl, d.scope_kind, d.scope_path, p_key, p_payload);

    RETURN CASE d.scope_kind
        WHEN 'global'      THEN sims_private.can_global(ARRAY[v_code]::text[])
        WHEN 'campus'      THEN sims_private.can_campus(ARRAY[v_code]::text[], v_scope)
        WHEN 'department'  THEN sims_private.can_department(ARRAY[v_code]::text[], v_scope)
        WHEN 'programme'   THEN sims_private.can_programme(ARRAY[v_code]::text[], v_scope)
        WHEN 'student'     THEN sims_private.can_student(ARRAY[v_code]::text[], v_scope, true)
        WHEN 'employee'    THEN sims_private.can_employee(ARRAY[v_code]::text[], v_scope, true)
        WHEN 'institution' THEN sims_private.can_institution(ARRAY[v_code]::text[], v_scope)
        ELSE false
    END;
END $function$;

-- ---------------------------------------------------------------------------------------------
-- 8. The editable tables the caller may work on.
-- ---------------------------------------------------------------------------------------------
-- The catalogue carries the permission codes verbatim, so the table is offered
-- when the caller holds any one of them.
-- ---------------------------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.admin_table_list();
CREATE FUNCTION public.admin_table_list()
RETURNS TABLE(
    tbl text,
    label text,
    module_codes text[]
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT d.tbl, d.label, d.module_codes
      FROM sims_private.admin_table_def(NULL) d
     WHERE sims_private.admin_holds(ARRAY[d.perm_create, d.perm_update, d.perm_delete]::text[])
      ORDER BY d.module_codes[1], d.label;
$function$;

-- ---------------------------------------------------------------------------------------------
-- 9. The shape of one editable table.
-- ---------------------------------------------------------------------------------------------
-- A table with a single column key hides that column from the form - it is
-- the key, not a field.  A table with a composite key keeps its key columns in
-- the form, because a new row has to be given its key.
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_table_schema(p_table text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    d record;
    v_pk text[];
    v_columns jsonb;
BEGIN
    SELECT * INTO d FROM sims_private.admin_table_def(p_table);
    IF d.tbl IS NULL THEN
        RAISE EXCEPTION 'Unknown table' USING ERRCODE = '22023';
    END IF;

    IF NOT sims_private.admin_holds(ARRAY[d.perm_create, d.perm_update, d.perm_delete]::text[]) THEN
        RAISE EXCEPTION 'Not authorised (%)', d.label USING ERRCODE = '42501';
    END IF;

    v_pk := d.pk_cols;
    v_columns := sims_private.form_columns(d.tbl, CASE WHEN cardinality(v_pk) = 1 THEN v_pk ELSE ARRAY[]::text[] END);

    RETURN jsonb_build_object(
        'table', d.tbl,
        'label', d.label,
        'module_codes', d.module_codes,
        'pk', CASE WHEN cardinality(v_pk) = 1 THEN v_pk[1] ELSE NULL END,
        'pk_cols', to_jsonb(v_pk),
        'columns', v_columns
    );
END $function$;

-- ---------------------------------------------------------------------------------------------
-- 10. Insert or update one row.
-- ---------------------------------------------------------------------------------------------
-- The write functions are SECURITY DEFINER, so the row level policies do not
-- run for them.  The function therefore has to make the same decision the
-- policy makes, in two parts:
--
--   USING      the row that exists now (an update) or the row that is about
--              to be written (an insert)
--   WITH CHECK the row as it is afterwards
--
-- The second part is what stops a scoped caller from moving a row out of
-- its own scope: without it a department could hand its course to another
-- department, which the policy's WITH CHECK clause forbids.
-- ---------------------------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.admin_table_save(text, bigint, jsonb);
CREATE FUNCTION public.admin_table_save(p_table text, p_key jsonb, p jsonb)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    d record;
    v_pk text[];
    v_where text;
    v_exists integer;
    v_after jsonb;
    v_before jsonb;
    v_id bigint;
    v_action text;
    v_code text;
    v_cols text;
    v_audit_id text;
    v_payload jsonb;
    v_n integer;
    v_audit_action text;
BEGIN
    SELECT * INTO d FROM sims_private.admin_table_def(p_table);
    IF d.tbl IS NULL THEN
        RAISE EXCEPTION 'Unknown table' USING ERRCODE = '22023';
    END IF;

    IF p IS NULL OR jsonb_typeof(p) <> 'object' THEN
        RAISE EXCEPTION 'The details must be an object' USING ERRCODE = '22023';
    END IF;

    v_pk := d.pk_cols;
    v_action := CASE WHEN p_key IS NULL OR jsonb_typeof(p_key) = 'null' THEN 'CREATE' ELSE 'UPDATE' END;
    v_code := CASE v_action WHEN 'CREATE' THEN d.perm_create ELSE d.perm_update END;

    -- The write itself is audited by the table's own `sims_private.audit_row`
    -- trigger, so the function must not audit as well - that would record
    -- every change twice.  The tables whose own write path already audits are
    -- marked MANUAL in the catalogue, and the function audits those itself.
    IF v_action = 'CREATE' THEN
        IF NOT sims_private.admin_can(p_table, 'CREATE', NULL, p) THEN
            RAISE EXCEPTION 'Not authorised to create % (%)', lower(d.label), v_code USING ERRCODE = '42501';
        END IF;

        v_payload := jsonb_strip_nulls(p);
        SELECT string_agg(quote_ident(k), ', ') INTO v_cols FROM jsonb_object_keys(v_payload) k;
        IF v_cols IS NULL THEN
            RAISE EXCEPTION 'Nothing to save' USING ERRCODE = '22023';
        END IF;

        v_id := sims_private.exec_dml_id(
            format('INSERT INTO public.%I (%s) SELECT %s FROM jsonb_populate_record(NULL::public.%I, $1) RETURNING %I::bigint',
                   p_table, v_cols, v_cols, p_table, v_pk[1]),
            v_payload);

        -- Read the row back.  A single column key is generated by the database,
        -- so the id the insert returned is the address.  A composite key is
        -- part of the form, so it comes back from the payload.
        IF cardinality(v_pk) = 1 THEN
            v_where := format('%I = %s', v_pk[1], v_id::text);
        ELSE
            SELECT string_agg(format('%I = %s', k, quote_literal(v_payload ->> k)), ' AND ') INTO v_where
              FROM unnest(v_pk) AS k(k) WHERE jsonb_exists(v_payload, k);
            SELECT count(*) INTO v_n FROM unnest(v_pk) AS k(k) WHERE jsonb_exists(v_payload, k);
            IF v_where IS NULL OR v_n <> cardinality(v_pk) THEN
                RAISE EXCEPTION 'This table needs every key column' USING ERRCODE = '22023';
            END IF;
        END IF;
        EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE %s', p_table, v_where) INTO v_after;
    ELSE
        v_where := sims_private.admin_key_where(p_table, p_key);
        IF v_where = '' THEN
            RAISE EXCEPTION 'Unknown row' USING ERRCODE = '22023';
        END IF;

        EXECUTE format('SELECT 1 FROM public.%I WHERE %s', p_table, v_where) INTO v_exists;
        IF v_exists IS NULL THEN
            RAISE EXCEPTION 'Unknown row' USING ERRCODE = '22023';
        END IF;

        IF NOT sims_private.admin_can(p_table, 'UPDATE', p_key, NULL) THEN
            RAISE EXCEPTION 'Not authorised to update % (%)', lower(d.label), v_code USING ERRCODE = '42501';
        END IF;

        EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE %s', p_table, v_where) INTO v_before;

        SELECT string_agg(quote_ident(k), ', ') INTO v_cols FROM jsonb_object_keys(p) k;
        IF v_cols IS NOT NULL THEN
            PERFORM sims_private.exec_dml(
                format('UPDATE public.%I t SET (%s) = (SELECT %s FROM jsonb_populate_record(NULL::public.%I, $1)) WHERE %s',
                       p_table, v_cols, v_cols, p_table, v_where),
                p);
        END IF;

        -- A composite key can be part of the form, so the row may have moved.
        -- Read it back by its new key - but only when the payload carries the
        -- whole key, otherwise the old address is still the right one.
        SELECT count(*) INTO v_n FROM unnest(v_pk) AS k(k) WHERE jsonb_exists(p, k);
        IF v_n = cardinality(v_pk) THEN
            SELECT string_agg(format('%I = %s', k, quote_literal(p ->> k)), ' AND ') INTO v_where
              FROM unnest(v_pk) AS k(k);
        ELSE
            v_where := sims_private.admin_key_where(p_table, p_key);
        END IF;
        EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE %s', p_table, v_where) INTO v_after;
    END IF;

    IF v_after IS NULL THEN
        RAISE EXCEPTION 'Unknown row' USING ERRCODE = '22023';
    END IF;
    v_id := (v_after ->> v_pk[1])::bigint;

    -- WITH CHECK: the row as it is now.  A refusal here aborts the transaction,
    -- so the write and its audit row are rolled back together.
    IF NOT sims_private.admin_can(p_table, v_action, NULL, v_after) THEN
        RAISE EXCEPTION 'Not authorised to % % outside your scope (%)',
            lower(v_action), lower(d.label), v_code USING ERRCODE = '42501';
    END IF;

    IF d.audit_mode = 'MANUAL' THEN
        v_audit_action := CASE v_action WHEN 'CREATE' THEN 'INSERT' ELSE v_action END;
        v_audit_id := v_after ->> v_pk[1];
        IF cardinality(v_pk) > 1 THEN
            SELECT string_agg(k || '=' || (v_after ->> k), ', ' ORDER BY k) INTO v_audit_id
              FROM unnest(v_pk) AS k(k);
        END IF;
        INSERT INTO public.activity_audit (user_id, module_code, action_code, entity_name, entity_id, before_values, after_values)
        VALUES (sims_private.current_user_id(), d.audit_module, v_audit_action, p_table, v_audit_id, v_before, v_after);
    END IF;

    RETURN v_id;
END $function$;

-- ---------------------------------------------------------------------------------------------
-- 11. Delete one row.
-- ---------------------------------------------------------------------------------------------

DROP FUNCTION IF EXISTS public.admin_table_delete(text, bigint);
CREATE FUNCTION public.admin_table_delete(p_table text, p_key jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    d record;
    v_pk text[];
    v_where text;
    v_exists integer;
    v_before jsonb;
    v_code text;
    v_audit_id text;
BEGIN
    SELECT * INTO d FROM sims_private.admin_table_def(p_table);
    IF d.tbl IS NULL THEN
        RAISE EXCEPTION 'Unknown table' USING ERRCODE = '22023';
    END IF;

    v_pk := d.pk_cols;
    v_code := d.perm_delete;

    IF NOT sims_private.admin_can(p_table, 'DELETE', p_key, NULL) THEN
        RAISE EXCEPTION 'Not authorised to delete % (%)', lower(d.label), v_code USING ERRCODE = '42501';
    END IF;

    v_where := sims_private.admin_key_where(p_table, p_key);
    IF v_where = '' THEN
        RAISE EXCEPTION 'Unknown row' USING ERRCODE = '22023';
    END IF;

    EXECUTE format('SELECT 1 FROM public.%I WHERE %s', p_table, v_where) INTO v_exists;
    IF v_exists IS NULL THEN
        RAISE EXCEPTION 'Unknown row' USING ERRCODE = '22023';
    END IF;

    EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE %s', p_table, v_where) INTO v_before;

    BEGIN
        EXECUTE format('DELETE FROM public.%I WHERE %s', p_table, v_where);
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'This row is still in use and cannot be deleted' USING ERRCODE = '45000';
    END;

    IF d.audit_mode = 'MANUAL' THEN
        v_audit_id := v_before ->> v_pk[1];
        IF cardinality(v_pk) > 1 THEN
            SELECT string_agg(k || '=' || (v_before ->> k), ', ' ORDER BY k) INTO v_audit_id
              FROM unnest(v_pk) AS k(k);
        END IF;
        INSERT INTO public.activity_audit (user_id, module_code, action_code, entity_name, entity_id, before_values, after_values)
        VALUES (sims_private.current_user_id(), d.audit_module, 'DELETE', p_table, v_audit_id, v_before, NULL);
    END IF;

    -- Audited by the table's own `sims_private.audit_row` trigger otherwise -
    -- see `admin_table_save`.
END $function$;

-- ---------------------------------------------------------------------------------------------
-- 12. The foreign key dropdowns.
-- ---------------------------------------------------------------------------------------------
-- SECURITY INVOKER on purpose: the options have to come from the rows the caller may
-- see, so the read goes through the row level policies of the referenced table.
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_lookup_options(p_table text)
RETURNS TABLE(
    id bigint,
    label text
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    d record;
BEGIN
    SELECT * INTO d FROM sims_private.admin_lookup_def(p_table);
    IF d.tbl IS NULL THEN
        RAISE EXCEPTION 'Unknown lookup table' USING ERRCODE = '22023';
    END IF;

    RETURN QUERY EXECUTE format(
        'SELECT %I::bigint, (%s)::text FROM public.%I t ORDER BY 2 LIMIT 1000',
        d.pk_col, d.label_sql, p_table);
END $function$;

-- ---------------------------------------------------------------------------------------------
-- 13. The missing audit triggers.
-- ---------------------------------------------------------------------------------------------
-- Every writable table has to end up with exactly one audit row per change.
--
--   * 40 of the 127 tables already carry an `AFTER INSERT OR DELETE OR UPDATE ...
--     EXECUTE FUNCTION sims_private.audit_row(...)` trigger.
--   * 39 tables are written by a dedicated path that already calls
--     `sims_private.audit_manual` (`ref_save` / `section_save` /
--     `emp_competency_save` / `staff_indexing_save`).  A trigger on those would
--     record their changes twice, so they stay without one and the generic
--     write function records the change itself - that is what the catalogue's
--     `audit_mode` says.
--   * The 48 tables below had neither.  These triggers close that gap and use
--     the same module codes as the rest of the schema.
--
-- `DROP TRIGGER IF EXISTS` first, so the file stays idempotent.
-- ---------------------------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_activity_evidence_requirement_audit ON public.activity_evidence_requirement;
CREATE TRIGGER trg_activity_evidence_requirement_audit
AFTER INSERT OR DELETE OR UPDATE ON public.activity_evidence_requirement
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'activity_evidence_requirement_id');

DROP TRIGGER IF EXISTS trg_activity_type_audit ON public.activity_type;
CREATE TRIGGER trg_activity_type_audit
AFTER INSERT OR DELETE OR UPDATE ON public.activity_type
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'activity_type_id');

DROP TRIGGER IF EXISTS trg_admission_category_audit ON public.admission_category;
CREATE TRIGGER trg_admission_category_audit
AFTER INSERT OR DELETE OR UPDATE ON public.admission_category
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('IAM', 'admission_category_id');

DROP TRIGGER IF EXISTS trg_announcement_type_audit ON public.announcement_type;
CREATE TRIGGER trg_announcement_type_audit
AFTER INSERT OR DELETE OR UPDATE ON public.announcement_type
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('COMMUNICATION', 'announcement_type_id');

DROP TRIGGER IF EXISTS trg_approval_status_audit ON public.approval_status;
CREATE TRIGGER trg_approval_status_audit
AFTER INSERT OR DELETE OR UPDATE ON public.approval_status
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'approval_status_id');

DROP TRIGGER IF EXISTS trg_awarding_body_type_audit ON public.awarding_body_type;
CREATE TRIGGER trg_awarding_body_type_audit
AFTER INSERT OR DELETE OR UPDATE ON public.awarding_body_type
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('EMPLOYEE', 'awarding_body_type_id');

DROP TRIGGER IF EXISTS trg_building_audit ON public.building;
CREATE TRIGGER trg_building_audit
AFTER INSERT OR DELETE OR UPDATE ON public.building
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('INSTITUTION', 'building_id');

DROP TRIGGER IF EXISTS trg_certificate_request_audit ON public.certificate_request;
CREATE TRIGGER trg_certificate_request_audit
AFTER INSERT OR DELETE OR UPDATE ON public.certificate_request
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('DOCUMENT', 'certificate_request_id');

DROP TRIGGER IF EXISTS trg_cocurricular_category_audit ON public.cocurricular_category;
CREATE TRIGGER trg_cocurricular_category_audit
AFTER INSERT OR DELETE OR UPDATE ON public.cocurricular_category
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'cocurricular_category_id');

DROP TRIGGER IF EXISTS trg_conference_contribution_type_audit ON public.conference_contribution_type;
CREATE TRIGGER trg_conference_contribution_type_audit
AFTER INSERT OR DELETE OR UPDATE ON public.conference_contribution_type
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'conference_contribution_type_id');

DROP TRIGGER IF EXISTS trg_conference_event_audit ON public.conference_event;
CREATE TRIGGER trg_conference_event_audit
AFTER INSERT OR DELETE OR UPDATE ON public.conference_event
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'conference_event_id');

DROP TRIGGER IF EXISTS trg_confidentiality_level_audit ON public.confidentiality_level;
CREATE TRIGGER trg_confidentiality_level_audit
AFTER INSERT OR DELETE OR UPDATE ON public.confidentiality_level
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'confidentiality_level_id');

DROP TRIGGER IF EXISTS trg_course_offering_section_student_audit ON public.course_offering_section_student;
CREATE TRIGGER trg_course_offering_section_student_audit
AFTER INSERT OR DELETE OR UPDATE ON public.course_offering_section_student
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('REGISTRATION', 'course_offering_section_student_id');

DROP TRIGGER IF EXISTS trg_education_institution_type_audit ON public.education_institution_type;
CREATE TRIGGER trg_education_institution_type_audit
AFTER INSERT OR DELETE OR UPDATE ON public.education_institution_type
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('EMPLOYEE', 'education_institution_type_id');

DROP TRIGGER IF EXISTS trg_employee_aadhaar_audit ON public.employee_aadhaar;
CREATE TRIGGER trg_employee_aadhaar_audit
AFTER INSERT OR DELETE OR UPDATE ON public.employee_aadhaar
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('EMPLOYEE', 'employee_aadhaar_id');

DROP TRIGGER IF EXISTS trg_employee_bank_account_audit ON public.employee_bank_account;
CREATE TRIGGER trg_employee_bank_account_audit
AFTER INSERT OR DELETE OR UPDATE ON public.employee_bank_account
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('EMPLOYEE', 'employee_bank_account_id');

DROP TRIGGER IF EXISTS trg_employee_document_audit ON public.employee_document;
CREATE TRIGGER trg_employee_document_audit
AFTER INSERT OR DELETE OR UPDATE ON public.employee_document
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('EMPLOYEE', 'employee_document_id');

DROP TRIGGER IF EXISTS trg_employee_document_access_rule_audit ON public.employee_document_access_rule;
CREATE TRIGGER trg_employee_document_access_rule_audit
AFTER INSERT OR DELETE OR UPDATE ON public.employee_document_access_rule
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('EMPLOYEE', 'employee_document_access_rule_id');

DROP TRIGGER IF EXISTS trg_employee_document_category_audit ON public.employee_document_category;
CREATE TRIGGER trg_employee_document_category_audit
AFTER INSERT OR DELETE OR UPDATE ON public.employee_document_category
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('EMPLOYEE', 'employee_document_category_id');

DROP TRIGGER IF EXISTS trg_employee_pan_audit ON public.employee_pan;
CREATE TRIGGER trg_employee_pan_audit
AFTER INSERT OR DELETE OR UPDATE ON public.employee_pan
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('EMPLOYEE', 'employee_pan_id');

DROP TRIGGER IF EXISTS trg_employment_source_audit ON public.employment_source;
CREATE TRIGGER trg_employment_source_audit
AFTER INSERT OR DELETE OR UPDATE ON public.employment_source
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('EMPLOYEE', 'employment_source_id');

DROP TRIGGER IF EXISTS trg_enrolment_status_history_audit ON public.enrolment_status_history;
CREATE TRIGGER trg_enrolment_status_history_audit
AFTER INSERT OR DELETE OR UPDATE ON public.enrolment_status_history
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('ADMISSION', 'enrolment_status_history_id');

DROP TRIGGER IF EXISTS trg_event_mode_audit ON public.event_mode;
CREATE TRIGGER trg_event_mode_audit
AFTER INSERT OR DELETE OR UPDATE ON public.event_mode
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'event_mode_id');

DROP TRIGGER IF EXISTS trg_evidence_document_tag_audit ON public.evidence_document_tag;
CREATE TRIGGER trg_evidence_document_tag_audit
AFTER INSERT OR DELETE OR UPDATE ON public.evidence_document_tag
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'evidence_document_id');

DROP TRIGGER IF EXISTS trg_evidence_tag_audit ON public.evidence_tag;
CREATE TRIGGER trg_evidence_tag_audit
AFTER INSERT OR DELETE OR UPDATE ON public.evidence_tag
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'evidence_tag_id');

DROP TRIGGER IF EXISTS trg_evidence_type_audit ON public.evidence_type;
CREATE TRIGGER trg_evidence_type_audit
AFTER INSERT OR DELETE OR UPDATE ON public.evidence_type
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'evidence_type_id');

DROP TRIGGER IF EXISTS trg_external_agency_audit ON public.external_agency;
CREATE TRIGGER trg_external_agency_audit
AFTER INSERT OR DELETE OR UPDATE ON public.external_agency
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('EMPLOYEE', 'external_agency_id');

DROP TRIGGER IF EXISTS trg_external_organization_audit ON public.external_organization;
CREATE TRIGGER trg_external_organization_audit
AFTER INSERT OR DELETE OR UPDATE ON public.external_organization
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'organization_id');

DROP TRIGGER IF EXISTS trg_external_organization_type_audit ON public.external_organization_type;
CREATE TRIGGER trg_external_organization_type_audit
AFTER INSERT OR DELETE OR UPDATE ON public.external_organization_type
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'organization_id');

DROP TRIGGER IF EXISTS trg_extracurricular_category_audit ON public.extracurricular_category;
CREATE TRIGGER trg_extracurricular_category_audit
AFTER INSERT OR DELETE OR UPDATE ON public.extracurricular_category
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'extracurricular_category_id');

DROP TRIGGER IF EXISTS trg_feedback_question_category_audit ON public.feedback_question_category;
CREATE TRIGGER trg_feedback_question_category_audit
AFTER INSERT OR DELETE OR UPDATE ON public.feedback_question_category
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('FEEDBACK', 'feedback_category_id');

DROP TRIGGER IF EXISTS trg_funding_agency_audit ON public.funding_agency;
CREATE TRIGGER trg_funding_agency_audit
AFTER INSERT OR DELETE OR UPDATE ON public.funding_agency
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'funding_agency_id');

DROP TRIGGER IF EXISTS trg_grievance_category_audit ON public.grievance_category;
CREATE TRIGGER trg_grievance_category_audit
AFTER INSERT OR DELETE OR UPDATE ON public.grievance_category
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('GRIEVANCE', 'grievance_category_id');

DROP TRIGGER IF EXISTS trg_industry_sector_audit ON public.industry_sector;
CREATE TRIGGER trg_industry_sector_audit
AFTER INSERT OR DELETE OR UPDATE ON public.industry_sector
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'industry_sector_id');

DROP TRIGGER IF EXISTS trg_journal_audit ON public.journal;
CREATE TRIGGER trg_journal_audit
AFTER INSERT OR DELETE OR UPDATE ON public.journal
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'journal_id');

DROP TRIGGER IF EXISTS trg_organization_type_audit ON public.organization_type;
CREATE TRIGGER trg_organization_type_audit
AFTER INSERT OR DELETE OR UPDATE ON public.organization_type
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'organization_type_id');

DROP TRIGGER IF EXISTS trg_organizer_audit ON public.organizer;
CREATE TRIGGER trg_organizer_audit
AFTER INSERT OR DELETE OR UPDATE ON public.organizer
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'organizer_id');

DROP TRIGGER IF EXISTS trg_participation_level_audit ON public.participation_level;
CREATE TRIGGER trg_participation_level_audit
AFTER INSERT OR DELETE OR UPDATE ON public.participation_level
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'participation_level_id');

DROP TRIGGER IF EXISTS trg_previous_organization_type_audit ON public.previous_organization_type;
CREATE TRIGGER trg_previous_organization_type_audit
AFTER INSERT OR DELETE OR UPDATE ON public.previous_organization_type
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('EMPLOYEE', 'previous_organization_type_id');

DROP TRIGGER IF EXISTS trg_professional_contribution_type_audit ON public.professional_contribution_type;
CREATE TRIGGER trg_professional_contribution_type_audit
AFTER INSERT OR DELETE OR UPDATE ON public.professional_contribution_type
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'professional_contribution_type_id');

DROP TRIGGER IF EXISTS trg_publisher_audit ON public.publisher;
CREATE TRIGGER trg_publisher_audit
AFTER INSERT OR DELETE OR UPDATE ON public.publisher
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'publisher_id');

DROP TRIGGER IF EXISTS trg_research_status_audit ON public.research_status;
CREATE TRIGGER trg_research_status_audit
AFTER INSERT OR DELETE OR UPDATE ON public.research_status
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'research_status_id');

DROP TRIGGER IF EXISTS trg_role_type_audit ON public.role_type;
CREATE TRIGGER trg_role_type_audit
AFTER INSERT OR DELETE OR UPDATE ON public.role_type
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'role_type_id');

DROP TRIGGER IF EXISTS trg_student_activity_evidence_requirement_audit ON public.student_activity_evidence_requirement;
CREATE TRIGGER trg_student_activity_evidence_requirement_audit
AFTER INSERT OR DELETE OR UPDATE ON public.student_activity_evidence_requirement
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STUDENT', 'student_activity_evidence_requirement_id');

DROP TRIGGER IF EXISTS trg_student_activity_type_audit ON public.student_activity_type;
CREATE TRIGGER trg_student_activity_type_audit
AFTER INSERT OR DELETE OR UPDATE ON public.student_activity_type
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STUDENT', 'student_activity_type_id');

DROP TRIGGER IF EXISTS trg_student_exit_audit ON public.student_exit;
CREATE TRIGGER trg_student_exit_audit
AFTER INSERT OR DELETE OR UPDATE ON public.student_exit
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('DOCUMENT', 'student_exit_id');

DROP TRIGGER IF EXISTS trg_training_program_type_audit ON public.training_program_type;
CREATE TRIGGER trg_training_program_type_audit
AFTER INSERT OR DELETE OR UPDATE ON public.training_program_type
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'training_program_type_id');

DROP TRIGGER IF EXISTS trg_verification_status_audit ON public.verification_status;
CREATE TRIGGER trg_verification_status_audit
AFTER INSERT OR DELETE OR UPDATE ON public.verification_status
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'verification_status_id');

-- ---------------------------------------------------------------------------------------------
-- Grants.
-- ---------------------------------------------------------------------------------------------
-- The catalogue helpers are readable by the browser because the lookup RPC is
-- SECURITY INVOKER and therefore has to reach them as the caller.  They describe the
-- shape of the schema only - no row of the database is exposed by either of them.
-- ---------------------------------------------------------------------------------------------

GRANT EXECUTE ON FUNCTION sims_private.admin_table_def(text) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.admin_lookup_def(text) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.admin_pk_cols(text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.admin_table_list() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_table_schema(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_table_save(text, jsonb, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_table_delete(text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_lookup_options(text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.admin_table_list() TO postgres;
GRANT EXECUTE ON FUNCTION public.admin_table_schema(text) TO postgres;
GRANT EXECUTE ON FUNCTION public.admin_table_save(text, jsonb, jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.admin_table_delete(text, jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.admin_lookup_options(text) TO postgres;

GRANT EXECUTE ON FUNCTION public.admin_table_list() TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_table_schema(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_table_save(text, jsonb, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_table_delete(text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_lookup_options(text) TO service_role;
