-- =============================================================================================
-- 020. workflow_guards
-- ---------------------------------------------------------------------------------------------
-- GENERATED FILE - do not edit by hand.
-- Regenerate with: npm run migrate:build   (python tools/translate.py && python tools/build_migrations.py)
--
-- Source of truth: the live Supabase catalogue (tools/catalogue/live_catalogue.json),
-- dumped read-only from project khqqfgqvwdxlqkncwtmh by tools/dump_catalogue.py.
-- =============================================================================================

-- -----------------------------------------------------------------------------
-- Every trigger of the live catalogue.
--
-- Audit triggers, workflow guards, `updated_at` touchers and the integrity
-- triggers.  They are emitted verbatim from `pg_get_triggerdef()`.
-- -----------------------------------------------------------------------------
CREATE TRIGGER trg_academic_term_audit AFTER INSERT OR DELETE OR UPDATE ON academic_term FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('ACADEMIC_CALENDAR', 'academic_term_id');
CREATE TRIGGER trg_academic_year_audit AFTER INSERT OR DELETE OR UPDATE ON academic_year FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('ACADEMIC_CALENDAR', 'academic_year_id');
CREATE TRIGGER trg_admission_applicant_audit AFTER INSERT OR DELETE OR UPDATE ON admission_applicant FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('ADMISSION', 'admission_applicant_id');
CREATE TRIGGER trg_admission_applicant_touch_updated_at BEFORE UPDATE ON admission_applicant FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_admission_application_audit AFTER INSERT OR DELETE OR UPDATE ON admission_application FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('ADMISSION', 'application_id');
CREATE TRIGGER trg_admission_application_touch_updated_at BEFORE UPDATE ON admission_application FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_announcement_audit AFTER INSERT OR DELETE OR UPDATE ON announcement FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('COMMUNICATION', 'announcement_id');
CREATE TRIGGER trg_announcement_workflow_guard BEFORE INSERT OR UPDATE ON announcement FOR EACH ROW EXECUTE FUNCTION sims_guard_announcement();
CREATE TRIGGER trg_assessment_component_audit AFTER INSERT OR DELETE OR UPDATE ON assessment_component FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('ASSESSMENT', 'assessment_component_id');
CREATE TRIGGER trg_assessment_event_audit AFTER INSERT OR DELETE OR UPDATE ON assessment_event FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('ASSESSMENT', 'assessment_event_id');
CREATE TRIGGER trg_assessment_event_guard BEFORE UPDATE ON assessment_event FOR EACH ROW EXECUTE FUNCTION sims_assessment_event_guard();
CREATE TRIGGER trg_assessment_event_workflow_guard BEFORE INSERT OR UPDATE ON assessment_event FOR EACH ROW EXECUTE FUNCTION sims_guard_assessment_event();
CREATE TRIGGER trg_attendance_correction_audit AFTER INSERT OR DELETE OR UPDATE ON attendance_correction_request FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('ATTENDANCE', 'attendance_correction_id');
CREATE TRIGGER trg_attendance_correction_request_workflow_guard BEFORE INSERT OR UPDATE ON attendance_correction_request FOR EACH ROW EXECUTE FUNCTION sims_guard_attendance_correction_request();
CREATE TRIGGER trg_attendance_status_audit AFTER INSERT OR DELETE OR UPDATE ON attendance_status FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('ATTENDANCE', 'attendance_status_id');
CREATE TRIGGER trg_awarding_body_touch_updated_at BEFORE UPDATE ON awarding_body FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_campus_audit AFTER INSERT OR DELETE OR UPDATE ON campus FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('INSTITUTION', 'campus_id');
CREATE TRIGGER trg_a_certificate_request_fee_hold BEFORE UPDATE ON certificate_request FOR EACH ROW EXECUTE FUNCTION sims_guard_certificate_hold();
CREATE TRIGGER trg_certificate_request_workflow_guard BEFORE INSERT OR UPDATE ON certificate_request FOR EACH ROW EXECUTE FUNCTION sims_guard_certificate_request();
CREATE TRIGGER trg_class_batch_audit AFTER INSERT OR DELETE OR UPDATE ON class_batch FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('REGISTRATION', 'class_batch_id');
CREATE TRIGGER trg_class_section_audit AFTER INSERT OR DELETE OR UPDATE ON class_section FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('REGISTRATION', 'class_section_id');
CREATE TRIGGER trg_class_session_audit AFTER INSERT OR DELETE OR UPDATE ON class_session FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('ATTENDANCE', 'class_session_id');
CREATE TRIGGER trg_class_session_guard BEFORE INSERT OR UPDATE ON class_session FOR EACH ROW EXECUTE FUNCTION sims_attendance_session_guard();
CREATE TRIGGER trg_conference_activity_indexing_workflow_guard BEFORE INSERT OR UPDATE ON conference_activity_indexing FOR EACH ROW EXECUTE FUNCTION sims_guard_conference_activity_indexing();
CREATE TRIGGER trg_conference_event_touch_updated_at BEFORE UPDATE ON conference_event FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_consultancy_project_workflow_guard BEFORE INSERT OR UPDATE ON consultancy_project FOR EACH ROW EXECUTE FUNCTION sims_guard_consultancy_project();
CREATE TRIGGER trg_course_catalog_audit AFTER INSERT OR DELETE OR UPDATE ON course_catalog FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('CURRICULUM', 'course_id');
CREATE TRIGGER trg_course_category_audit AFTER INSERT OR DELETE OR UPDATE ON course_category FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('CURRICULUM', 'course_category_id');
CREATE TRIGGER trg_course_offering_audit AFTER INSERT OR DELETE OR UPDATE ON course_offering FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('TEACHING', 'course_offering_id');
CREATE TRIGGER trg_course_offering_section_audit AFTER INSERT OR DELETE OR UPDATE ON course_offering_section FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('TEACHING', 'course_offering_section_id');
CREATE TRIGGER trg_course_prerequisite_audit AFTER INSERT OR DELETE OR UPDATE ON course_prerequisite FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('CURRICULUM', 'course_id');
CREATE TRIGGER trg_curriculum_course_audit AFTER INSERT OR DELETE OR UPDATE ON curriculum_course FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('CURRICULUM', 'curriculum_course_id');
CREATE TRIGGER trg_curriculum_scheme_audit AFTER INSERT OR DELETE OR UPDATE ON curriculum_scheme FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('CURRICULUM', 'curriculum_scheme_id');
CREATE TRIGGER trg_department_audit AFTER INSERT OR DELETE OR UPDATE ON department FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('INSTITUTION', 'department_id');
CREATE TRIGGER trg_education_institution_touch_updated_at BEFORE UPDATE ON education_institution FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_employee_audit AFTER INSERT OR DELETE OR UPDATE ON employee FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('EMPLOYEE', 'employee_id');
CREATE TRIGGER trg_employee_institution_immutable BEFORE UPDATE ON employee FOR EACH ROW EXECUTE FUNCTION sims_private.employee_institution_immutable();
CREATE TRIGGER trg_employee_touch_updated_at BEFORE UPDATE ON employee FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_employee_aadhaar_touch_updated_at BEFORE UPDATE ON employee_aadhaar FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_employee_aadhaar_workflow_guard BEFORE INSERT OR UPDATE ON employee_aadhaar FOR EACH ROW EXECUTE FUNCTION sims_guard_employee_aadhaar();
CREATE TRIGGER trg_employee_assignment_audit AFTER INSERT OR DELETE OR UPDATE ON employee_assignment FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('EMPLOYEE', 'employee_assignment_id');
CREATE TRIGGER trg_employee_bank_account_touch_updated_at BEFORE UPDATE ON employee_bank_account FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_employee_bank_account_workflow_guard BEFORE INSERT OR UPDATE ON employee_bank_account FOR EACH ROW EXECUTE FUNCTION sims_guard_employee_bank_account();
CREATE TRIGGER trg_employee_document_touch_updated_at BEFORE UPDATE ON employee_document FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_employee_document_workflow_guard BEFORE INSERT OR UPDATE ON employee_document FOR EACH ROW EXECUTE FUNCTION sims_guard_employee_document();
CREATE TRIGGER trg_employee_pan_touch_updated_at BEFORE UPDATE ON employee_pan FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_employee_pan_workflow_guard BEFORE INSERT OR UPDATE ON employee_pan FOR EACH ROW EXECUTE FUNCTION sims_guard_employee_pan();
CREATE TRIGGER trg_employee_previous_employment_touch_updated_at BEFORE UPDATE ON employee_previous_employment FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_employee_qualification_touch_updated_at BEFORE UPDATE ON employee_qualification FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_employment_source_touch_updated_at BEFORE UPDATE ON employment_source FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_evidence_document_touch_updated_at BEFORE UPDATE ON evidence_document FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_evidence_document_workflow_guard BEFORE INSERT OR UPDATE ON evidence_document FOR EACH ROW EXECUTE FUNCTION sims_guard_evidence_document();
CREATE TRIGGER trg_external_agency_touch_updated_at BEFORE UPDATE ON external_agency FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_external_organization_touch_updated_at BEFORE UPDATE ON external_organization FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_faculty_course_assignment_audit AFTER INSERT OR DELETE OR UPDATE ON faculty_course_assignment FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('TEACHING', 'faculty_assignment_id');
CREATE TRIGGER trg_fee_benefit_bi BEFORE INSERT ON fee_assessment_benefit FOR EACH ROW EXECUTE FUNCTION sims_fee_benefit_guard();
CREATE TRIGGER trg_fee_benefit_bu BEFORE UPDATE ON fee_assessment_benefit FOR EACH ROW EXECUTE FUNCTION sims_fee_benefit_guard();
CREATE TRIGGER trg_fee_category_touch_updated_at BEFORE UPDATE ON fee_category FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_fee_refund_bi BEFORE INSERT ON fee_refund FOR EACH ROW EXECUTE FUNCTION sims_fee_refund_guard();
CREATE TRIGGER trg_fee_refund_bu BEFORE UPDATE ON fee_refund FOR EACH ROW EXECUTE FUNCTION sims_fee_refund_guard();
CREATE TRIGGER trg_fee_structure_touch_updated_at BEFORE UPDATE ON fee_structure FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_fee_type_touch_updated_at BEFORE UPDATE ON fee_type FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_feedback_choice_audit AFTER INSERT OR DELETE OR UPDATE ON feedback_choice FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('FEEDBACK', 'feedback_choice_id');
CREATE TRIGGER trg_feedback_cycle_audit AFTER INSERT OR DELETE OR UPDATE ON feedback_cycle FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('FEEDBACK', 'feedback_cycle_id');
CREATE TRIGGER trg_feedback_cycle_guard BEFORE INSERT OR UPDATE ON feedback_cycle FOR EACH ROW EXECUTE FUNCTION sims_feedback_cycle_guard();
CREATE TRIGGER trg_feedback_question_audit AFTER INSERT OR DELETE OR UPDATE ON feedback_question FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('FEEDBACK', 'feedback_question_id');
CREATE TRIGGER trg_feedback_questionnaire_audit AFTER INSERT OR DELETE OR UPDATE ON feedback_questionnaire FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('FEEDBACK', 'questionnaire_id');
CREATE TRIGGER trg_feedback_questionnaire_guard BEFORE UPDATE ON feedback_questionnaire FOR EACH ROW EXECUTE FUNCTION sims_feedback_questionnaire_guard();
CREATE TRIGGER trg_feedback_item_guard BEFORE INSERT OR DELETE OR UPDATE ON feedback_questionnaire_item FOR EACH ROW EXECUTE FUNCTION sims_feedback_item_guard();
CREATE TRIGGER trg_feedback_questionnaire_item_audit AFTER INSERT OR DELETE OR UPDATE ON feedback_questionnaire_item FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('FEEDBACK', 'questionnaire_item_id');
CREATE TRIGGER trg_file_object_audit AFTER INSERT OR DELETE OR UPDATE ON file_object FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('DOCUMENT', 'file_object_id');
CREATE TRIGGER trg_file_object_touch_updated_at BEFORE UPDATE ON file_object FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_grade_rule_audit AFTER INSERT OR DELETE OR UPDATE ON grade_rule FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('RESULT', 'grade_rule_id');
CREATE TRIGGER trg_grade_scale_audit AFTER INSERT OR DELETE OR UPDATE ON grade_scale FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('RESULT', 'grade_scale_id');
CREATE TRIGGER trg_grievance_audit AFTER INSERT OR DELETE OR UPDATE ON grievance FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('GRIEVANCE', 'grievance_id');
CREATE TRIGGER trg_institution_audit AFTER INSERT OR DELETE OR UPDATE ON institution FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('INSTITUTION', 'institution_id');
CREATE TRIGGER trg_institution_touch_updated_at BEFORE UPDATE ON institution FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_journal_touch_updated_at BEFORE UPDATE ON journal FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_journal_metric_workflow_guard BEFORE INSERT OR UPDATE ON journal_metric FOR EACH ROW EXECUTE FUNCTION sims_guard_journal_metric();
CREATE TRIGGER trg_journal_publication_indexing_workflow_guard BEFORE INSERT OR UPDATE ON journal_publication_indexing FOR EACH ROW EXECUTE FUNCTION sims_guard_journal_publication_indexing();
CREATE TRIGGER trg_mentor_assignment_audit AFTER INSERT OR DELETE OR UPDATE ON mentor_assignment FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('MENTORING', 'mentor_assignment_id');
CREATE TRIGGER trg_payment_allocation_ad AFTER DELETE ON payment_allocation FOR EACH ROW EXECUTE FUNCTION sims_payment_allocation_sync();
CREATE TRIGGER trg_payment_allocation_ai AFTER INSERT ON payment_allocation FOR EACH ROW EXECUTE FUNCTION sims_payment_allocation_sync();
CREATE TRIGGER trg_payment_allocation_au AFTER UPDATE ON payment_allocation FOR EACH ROW EXECUTE FUNCTION sims_payment_allocation_sync();
CREATE TRIGGER trg_payment_allocation_bi BEFORE INSERT ON payment_allocation FOR EACH ROW EXECUTE FUNCTION sims_payment_allocation_guard();
CREATE TRIGGER trg_payment_allocation_bu BEFORE UPDATE ON payment_allocation FOR EACH ROW EXECUTE FUNCTION sims_payment_allocation_guard();
CREATE TRIGGER trg_previous_organization_touch_updated_at BEFORE UPDATE ON previous_organization FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_programme_audit AFTER INSERT OR DELETE OR UPDATE ON programme FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('INSTITUTION', 'programme_id');
CREATE TRIGGER trg_programme_specialization_audit AFTER INSERT OR DELETE OR UPDATE ON programme_specialization FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('INSTITUTION', 'specialization_id');
CREATE TRIGGER trg_programme_term_offering_audit AFTER INSERT OR DELETE OR UPDATE ON programme_term_offering FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('REGISTRATION', 'programme_term_offering_id');
CREATE TRIGGER trg_publication_type_touch_updated_at BEFORE UPDATE ON publication_type FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_qualification_level_touch_updated_at BEFORE UPDATE ON qualification_level FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_role_touch_updated_at BEFORE UPDATE ON role FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_semester_audit AFTER INSERT OR DELETE OR UPDATE ON semester FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('ACADEMIC_CALENDAR', 'semester_id');
CREATE TRIGGER trg_staff_activity_audit AFTER INSERT OR DELETE OR UPDATE ON staff_activity FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STAFF_PROFILE', 'staff_activity_id');
CREATE TRIGGER trg_staff_activity_touch_updated_at BEFORE UPDATE ON staff_activity FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_staff_activity_workflow_guard BEFORE INSERT OR UPDATE ON staff_activity FOR EACH ROW EXECUTE FUNCTION sims_guard_staff_activity();
CREATE TRIGGER trg_staff_category_touch_updated_at BEFORE UPDATE ON staff_category FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_staff_type_touch_updated_at BEFORE UPDATE ON staff_type FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_student_audit AFTER INSERT OR DELETE OR UPDATE ON student FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STUDENT', 'student_id');
CREATE TRIGGER trg_student_touch_updated_at BEFORE UPDATE ON student FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_student_activity_audit AFTER INSERT OR DELETE OR UPDATE ON student_activity FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('STUDENT', 'student_activity_id');
CREATE TRIGGER trg_student_activity_touch_updated_at BEFORE UPDATE ON student_activity FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_student_activity_workflow_guard BEFORE INSERT OR UPDATE ON student_activity FOR EACH ROW EXECUTE FUNCTION sims_guard_student_activity();
CREATE TRIGGER trg_student_activity_evidence_touch_updated_at BEFORE UPDATE ON student_activity_evidence FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_student_activity_evidence_workflow_guard BEFORE INSERT OR UPDATE ON student_activity_evidence FOR EACH ROW EXECUTE FUNCTION sims_guard_student_activity_evidence();
CREATE TRIGGER trg_student_activity_type_touch_updated_at BEFORE UPDATE ON student_activity_type FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_student_assessment_mark_audit AFTER INSERT OR DELETE OR UPDATE ON student_assessment_mark FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('ASSESSMENT', 'student_assessment_mark_id');
CREATE TRIGGER trg_student_assessment_mark_guard BEFORE INSERT OR DELETE OR UPDATE ON student_assessment_mark FOR EACH ROW EXECUTE FUNCTION sims_assessment_mark_guard();
CREATE TRIGGER trg_course_registration_guard BEFORE INSERT OR UPDATE ON student_course_registration FOR EACH ROW EXECUTE FUNCTION sims_registration_course_guard();
CREATE TRIGGER trg_student_course_registration_audit AFTER INSERT OR DELETE OR UPDATE ON student_course_registration FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('REGISTRATION', 'course_registration_id');
CREATE TRIGGER trg_student_course_registration_workflow_guard BEFORE INSERT OR UPDATE ON student_course_registration FOR EACH ROW EXECUTE FUNCTION sims_guard_student_course_registration();
CREATE TRIGGER trg_student_course_result_audit AFTER INSERT OR DELETE OR UPDATE ON student_course_result FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('RESULT', 'student_course_result_id');
CREATE TRIGGER trg_student_course_result_lock BEFORE INSERT OR DELETE OR UPDATE ON student_course_result FOR EACH ROW EXECUTE FUNCTION sims_course_result_lock();
CREATE TRIGGER trg_student_document_audit AFTER INSERT OR DELETE OR UPDATE ON student_document FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('DOCUMENT', 'student_document_id');
CREATE TRIGGER trg_student_document_workflow_guard BEFORE INSERT OR UPDATE ON student_document FOR EACH ROW EXECUTE FUNCTION sims_guard_student_document();
CREATE TRIGGER trg_student_fee_assessment_touch_updated_at BEFORE UPDATE ON student_fee_assessment FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_fee_item_ad AFTER DELETE ON student_fee_assessment_item FOR EACH ROW EXECUTE FUNCTION sims_fee_item_sync();
CREATE TRIGGER trg_fee_item_ai AFTER INSERT ON student_fee_assessment_item FOR EACH ROW EXECUTE FUNCTION sims_fee_item_sync();
CREATE TRIGGER trg_fee_item_au AFTER UPDATE ON student_fee_assessment_item FOR EACH ROW EXECUTE FUNCTION sims_fee_item_sync();
CREATE TRIGGER trg_student_financial_account_touch_updated_at BEFORE UPDATE ON student_financial_account FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_student_programme_enrolment_audit AFTER INSERT OR DELETE OR UPDATE ON student_programme_enrolment FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('ADMISSION', 'enrolment_id');
CREATE TRIGGER trg_a_term_registration_fee_hold BEFORE INSERT ON student_term_registration FOR EACH ROW EXECUTE FUNCTION sims_guard_term_registration_hold();
CREATE TRIGGER trg_student_term_registration_audit AFTER INSERT OR DELETE OR UPDATE ON student_term_registration FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('REGISTRATION', 'term_registration_id');
CREATE TRIGGER trg_student_term_registration_workflow_guard BEFORE INSERT OR UPDATE ON student_term_registration FOR EACH ROW EXECUTE FUNCTION sims_guard_student_term_registration();
CREATE TRIGGER trg_term_registration_guard BEFORE INSERT OR UPDATE ON student_term_registration FOR EACH ROW EXECUTE FUNCTION sims_registration_term_guard();
CREATE TRIGGER trg_student_term_result_audit AFTER INSERT OR DELETE OR UPDATE ON student_term_result FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('RESULT', 'student_term_result_id');
CREATE TRIGGER trg_student_term_result_lock BEFORE INSERT OR DELETE OR UPDATE ON student_term_result FOR EACH ROW EXECUTE FUNCTION sims_term_result_lock();
CREATE TRIGGER trg_student_term_result_workflow_guard BEFORE INSERT OR UPDATE ON student_term_result FOR EACH ROW EXECUTE FUNCTION sims_guard_student_term_result();
CREATE TRIGGER trg_timetable_session_audit AFTER INSERT OR DELETE OR UPDATE ON timetable_session FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('TIMETABLE', 'timetable_session_id');
CREATE TRIGGER trg_timetable_session_guard BEFORE INSERT OR UPDATE ON timetable_session FOR EACH ROW EXECUTE FUNCTION sims_timetable_guard();
CREATE TRIGGER trg_university_audit AFTER INSERT OR DELETE OR UPDATE ON university FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('INSTITUTION', 'university_id');
CREATE TRIGGER trg_university_touch_updated_at BEFORE UPDATE ON university FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_user_account_touch_updated_at BEFORE UPDATE ON user_account FOR EACH ROW EXECUTE FUNCTION sims_touch_updated_at();
CREATE TRIGGER trg_user_permission_override_audit AFTER INSERT OR DELETE OR UPDATE ON user_permission_override FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('IAM', 'user_permission_override_id');
CREATE TRIGGER trg_user_permission_override_scope_bi BEFORE INSERT ON user_permission_override FOR EACH ROW EXECUTE FUNCTION sims_user_permission_override_scope();
CREATE TRIGGER trg_user_permission_override_scope_bu BEFORE UPDATE ON user_permission_override FOR EACH ROW EXECUTE FUNCTION sims_user_permission_override_scope();
CREATE TRIGGER trg_user_role_assignment_audit AFTER INSERT OR DELETE OR UPDATE ON user_role_assignment FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('IAM', 'user_role_assignment_id');
CREATE TRIGGER trg_user_role_assignment_scope_bi BEFORE INSERT ON user_role_assignment FOR EACH ROW EXECUTE FUNCTION sims_user_role_assignment_scope();
CREATE TRIGGER trg_user_role_assignment_scope_bu BEFORE UPDATE ON user_role_assignment FOR EACH ROW EXECUTE FUNCTION sims_user_role_assignment_scope();
