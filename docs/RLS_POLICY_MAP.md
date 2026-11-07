# RLS policy map

<!-- GENERATED FILE - do not edit by hand. Regenerate with `python tools/build_rls.py`. -->

Every public table, the policies that guard it and the permission code each policy requires.  A policy without a permission code only checks that the caller is an active member of the institution.

| Table | Module | Policy | Command | Permission required |
|---|---|---|---|---|
| `academic_term` | ACADEMIC_CALENDAR | `academic_term_delete` | DELETE | `ACADEMIC_CALENDAR.ALL.CONFIGURE` |
|  |  | `academic_term_insert` | INSERT | `ACADEMIC_CALENDAR.ALL.CONFIGURE` |
|  |  | `academic_term_select` | SELECT | _membership only_ |
|  |  | `academic_term_update` | UPDATE | `ACADEMIC_CALENDAR.ALL.CONFIGURE` |
| `academic_year` | ACADEMIC_CALENDAR | `academic_year_delete` | DELETE | `ACADEMIC_CALENDAR.ALL.CONFIGURE` |
|  |  | `academic_year_insert` | INSERT | `ACADEMIC_CALENDAR.ALL.CONFIGURE` |
|  |  | `academic_year_select` | SELECT | _membership only_ |
|  |  | `academic_year_update` | UPDATE | `ACADEMIC_CALENDAR.ALL.CONFIGURE` |
| `access_action` | IAM | `access_action_select` | SELECT | `IAM.ALL.READ` |
| `access_module` | IAM | `access_module_select` | SELECT | `IAM.ALL.READ` |
| `access_resource` | IAM | `access_resource_select` | SELECT | `IAM.ALL.READ` |
| `activity_audit` | IAM | `activity_audit_select` | SELECT | `IAM.ALL.READ` |
| `activity_evidence_requirement` | STAFF_PROFILE | `activity_evidence_requirement_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `activity_evidence_requirement_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `activity_evidence_requirement_select` | SELECT | _membership only_ |
|  |  | `activity_evidence_requirement_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `activity_type` | STAFF_PROFILE | `activity_type_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `activity_type_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `activity_type_select` | SELECT | _membership only_ |
|  |  | `activity_type_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `admission_applicant` | ADMISSION | `admission_applicant_select` | SELECT | `ADMISSION.ALL.READ` |
| `admission_application` | ADMISSION | `admission_application_select` | SELECT | `ADMISSION.ALL.READ` |
| `admission_category` | IAM | `admission_category_delete` | DELETE | `IAM.ALL.CONFIGURE` |
|  |  | `admission_category_insert` | INSERT | `IAM.ALL.CONFIGURE` |
|  |  | `admission_category_select` | SELECT | _membership only_ |
|  |  | `admission_category_update` | UPDATE | `IAM.ALL.CONFIGURE` |
| `admission_payment` | FEES | `admission_payment_select` | SELECT | `FEES.FEE_PAYMENT.READ` |
| `announcement` | COMMUNICATION | `announcement_select` | SELECT | `COMMUNICATION.ALL.READ` |
| `announcement_attachment` | COMMUNICATION | `announcement_attachment_select` | SELECT | `COMMUNICATION.ALL.READ` |
| `announcement_type` | COMMUNICATION | `announcement_type_delete` | DELETE | `COMMUNICATION.ALL.CONFIGURE` |
|  |  | `announcement_type_insert` | INSERT | `COMMUNICATION.ALL.CONFIGURE` |
|  |  | `announcement_type_select` | SELECT | _membership only_ |
|  |  | `announcement_type_update` | UPDATE | `COMMUNICATION.ALL.CONFIGURE` |
| `approval_status` | STAFF_PROFILE | `approval_status_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `approval_status_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `approval_status_select` | SELECT | _membership only_ |
|  |  | `approval_status_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `assessment_component` | ASSESSMENT | `assessment_component_delete` | DELETE | `ASSESSMENT.ALL.DELETE` |
|  |  | `assessment_component_insert` | INSERT | `ASSESSMENT.ALL.CREATE` |
|  |  | `assessment_component_select` | SELECT | `ASSESSMENT.ALL.READ` |
|  |  | `assessment_component_update` | UPDATE | `ASSESSMENT.ALL.UPDATE` |
| `assessment_event` | ASSESSMENT | `assessment_event_delete` | DELETE | `ASSESSMENT.ALL.DELETE` |
|  |  | `assessment_event_insert` | INSERT | `ASSESSMENT.ALL.CREATE` |
|  |  | `assessment_event_select` | SELECT | `ASSESSMENT.ALL.READ` |
|  |  | `assessment_event_update` | UPDATE | `ASSESSMENT.ALL.UPDATE` |
| `attendance_correction_request` | ATTENDANCE | `attendance_correction_request_select` | SELECT | `ATTENDANCE.ALL.READ` |
| `attendance_status` | ATTENDANCE | `attendance_status_delete` | DELETE | `ATTENDANCE.ALL.CONFIGURE` |
|  |  | `attendance_status_insert` | INSERT | `ATTENDANCE.ALL.CONFIGURE` |
|  |  | `attendance_status_select` | SELECT | _membership only_ |
|  |  | `attendance_status_update` | UPDATE | `ATTENDANCE.ALL.CONFIGURE` |
| `award_category` | STAFF_PROFILE | `award_category_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `award_category_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `award_category_select` | SELECT | _membership only_ |
|  |  | `award_category_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `awarding_body` | EMPLOYEE | `awarding_body_delete` | DELETE | `EMPLOYEE.ALL.CONFIGURE` |
|  |  | `awarding_body_insert` | INSERT | `EMPLOYEE.ALL.CONFIGURE` |
|  |  | `awarding_body_select` | SELECT | _membership only_ |
|  |  | `awarding_body_update` | UPDATE | `EMPLOYEE.ALL.CONFIGURE` |
| `awarding_body_type` | EMPLOYEE | `awarding_body_type_delete` | DELETE | `EMPLOYEE.ALL.CONFIGURE` |
|  |  | `awarding_body_type_insert` | INSERT | `EMPLOYEE.ALL.CONFIGURE` |
|  |  | `awarding_body_type_select` | SELECT | _membership only_ |
|  |  | `awarding_body_type_update` | UPDATE | `EMPLOYEE.ALL.CONFIGURE` |
| `blood_group` | IAM | `blood_group_delete` | DELETE | `IAM.ALL.CONFIGURE` |
|  |  | `blood_group_insert` | INSERT | `IAM.ALL.CONFIGURE` |
|  |  | `blood_group_select` | SELECT | _membership only_ |
|  |  | `blood_group_update` | UPDATE | `IAM.ALL.CONFIGURE` |
| `building` | INSTITUTION | `building_delete` | DELETE | `INSTITUTION.ALL.DELETE` |
|  |  | `building_insert` | INSERT | `INSTITUTION.ALL.CREATE` |
|  |  | `building_select` | SELECT | `INSTITUTION.ALL.READ` |
|  |  | `building_update` | UPDATE | `INSTITUTION.ALL.UPDATE` |
| `campus` | INSTITUTION | `campus_delete` | DELETE | `INSTITUTION.ALL.DELETE` |
|  |  | `campus_insert` | INSERT | `INSTITUTION.ALL.CREATE` |
|  |  | `campus_select` | SELECT | _membership only_ |
|  |  | `campus_update` | UPDATE | `INSTITUTION.ALL.UPDATE` |
| `caste` | IAM | `caste_delete` | DELETE | `IAM.ALL.CONFIGURE` |
|  |  | `caste_insert` | INSERT | `IAM.ALL.CONFIGURE` |
|  |  | `caste_select` | SELECT | _membership only_ |
|  |  | `caste_update` | UPDATE | `IAM.ALL.CONFIGURE` |
| `certificate_request` | DOCUMENT | `certificate_request_delete` | DELETE | `DOCUMENT.ALL.DELETE` |
|  |  | `certificate_request_insert` | INSERT | `DOCUMENT.ALL.CREATE` |
|  |  | `certificate_request_select` | SELECT | `DOCUMENT.ALL.READ` |
|  |  | `certificate_request_update` | UPDATE | `DOCUMENT.ALL.UPDATE` |
| `certificate_type` | DOCUMENT | `certificate_type_delete` | DELETE | `DOCUMENT.ALL.CONFIGURE` |
|  |  | `certificate_type_insert` | INSERT | `DOCUMENT.ALL.CONFIGURE` |
|  |  | `certificate_type_select` | SELECT | _membership only_ |
|  |  | `certificate_type_update` | UPDATE | `DOCUMENT.ALL.CONFIGURE` |
| `class_batch` | REGISTRATION | `class_batch_delete` | DELETE | `REGISTRATION.ALL.DELETE` |
|  |  | `class_batch_insert` | INSERT | `REGISTRATION.ALL.CREATE` |
|  |  | `class_batch_select` | SELECT | `REGISTRATION.ALL.READ` |
|  |  | `class_batch_update` | UPDATE | `REGISTRATION.ALL.UPDATE` |
| `class_section` | REGISTRATION | `class_section_delete` | DELETE | `REGISTRATION.ALL.DELETE` |
|  |  | `class_section_insert` | INSERT | `REGISTRATION.ALL.CREATE` |
|  |  | `class_section_select` | SELECT | `REGISTRATION.ALL.READ` |
|  |  | `class_section_update` | UPDATE | `REGISTRATION.ALL.UPDATE` |
| `class_session` | ATTENDANCE | `class_session_delete` | DELETE | `ATTENDANCE.ALL.DELETE` |
|  |  | `class_session_insert` | INSERT | `ATTENDANCE.ALL.CREATE` |
|  |  | `class_session_select` | SELECT | `ATTENDANCE.ALL.READ` |
|  |  | `class_session_update` | UPDATE | `ATTENDANCE.ALL.UPDATE` |
| `cocurricular_activity` | STAFF_PROFILE | `cocurricular_activity_select` | SELECT | `STAFF_PROFILE.STAFF_ACTIVITY.READ` |
| `cocurricular_category` | STAFF_PROFILE | `cocurricular_category_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `cocurricular_category_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `cocurricular_category_select` | SELECT | _membership only_ |
|  |  | `cocurricular_category_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `concession_type` | FEES | `concession_type_select` | SELECT | _membership only_ |
| `conference_activity` | STAFF_PROFILE | `conference_activity_select` | SELECT | `STAFF_PROFILE.STAFF_ACTIVITY.READ` |
| `conference_activity_indexing` | STAFF_PROFILE | `conference_activity_indexing_delete` | DELETE | `STAFF_PROFILE.STAFF_ACTIVITY.DELETE` |
|  |  | `conference_activity_indexing_insert` | INSERT | `STAFF_PROFILE.STAFF_ACTIVITY.CREATE` |
|  |  | `conference_activity_indexing_select` | SELECT | `STAFF_PROFILE.STAFF_ACTIVITY.READ` |
|  |  | `conference_activity_indexing_update` | UPDATE | `STAFF_PROFILE.STAFF_ACTIVITY.UPDATE` |
| `conference_contribution_type` | STAFF_PROFILE | `conference_contribution_type_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `conference_contribution_type_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `conference_contribution_type_select` | SELECT | _membership only_ |
|  |  | `conference_contribution_type_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `conference_event` | STAFF_PROFILE | `conference_event_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `conference_event_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `conference_event_select` | SELECT | _membership only_ |
|  |  | `conference_event_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `confidentiality_level` | STAFF_PROFILE | `confidentiality_level_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `confidentiality_level_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `confidentiality_level_select` | SELECT | _membership only_ |
|  |  | `confidentiality_level_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `consultancy_project` | STAFF_PROFILE | `consultancy_project_select` | SELECT | `STAFF_PROFILE.STAFF_RESEARCH.READ` |
| `counselling_session` | MENTORING | `counselling_session_no_client_access` | ALL | _membership only_ |
| `country` | IAM | `country_delete` | DELETE | `IAM.ALL.CONFIGURE` |
|  |  | `country_insert` | INSERT | `IAM.ALL.CONFIGURE` |
|  |  | `country_select` | SELECT | _membership only_ |
|  |  | `country_update` | UPDATE | `IAM.ALL.CONFIGURE` |
| `course_catalog` | CURRICULUM | `course_catalog_delete` | DELETE | `CURRICULUM.ALL.DELETE` |
|  |  | `course_catalog_insert` | INSERT | `CURRICULUM.ALL.CREATE` |
|  |  | `course_catalog_select` | SELECT | `CURRICULUM.ALL.READ` |
|  |  | `course_catalog_update` | UPDATE | `CURRICULUM.ALL.UPDATE` |
| `course_category` | CURRICULUM | `course_category_delete` | DELETE | `CURRICULUM.ALL.CONFIGURE` |
|  |  | `course_category_insert` | INSERT | `CURRICULUM.ALL.CONFIGURE` |
|  |  | `course_category_select` | SELECT | _membership only_ |
|  |  | `course_category_update` | UPDATE | `CURRICULUM.ALL.CONFIGURE` |
| `course_offering` | TEACHING | `course_offering_delete` | DELETE | `TEACHING.ALL.DELETE` |
|  |  | `course_offering_insert` | INSERT | `TEACHING.ALL.CREATE` |
|  |  | `course_offering_select` | SELECT | `TEACHING.ALL.READ` |
|  |  | `course_offering_update` | UPDATE | `TEACHING.ALL.UPDATE` |
| `course_offering_section` | TEACHING | `course_offering_section_delete` | DELETE | `TEACHING.ALL.DELETE` |
|  |  | `course_offering_section_insert` | INSERT | `TEACHING.ALL.CREATE` |
|  |  | `course_offering_section_select` | SELECT | `TEACHING.ALL.READ` |
|  |  | `course_offering_section_update` | UPDATE | `TEACHING.ALL.UPDATE` |
| `course_offering_section_student` | REGISTRATION | `course_offering_section_student_delete` | DELETE | `REGISTRATION.ALL.DELETE` |
|  |  | `course_offering_section_student_insert` | INSERT | `REGISTRATION.ALL.CREATE` |
|  |  | `course_offering_section_student_select` | SELECT | `REGISTRATION.ALL.READ` |
|  |  | `course_offering_section_student_update` | UPDATE | `REGISTRATION.ALL.UPDATE` |
| `course_prerequisite` | CURRICULUM | `course_prerequisite_delete` | DELETE | `CURRICULUM.ALL.DELETE` |
|  |  | `course_prerequisite_insert` | INSERT | `CURRICULUM.ALL.CREATE` |
|  |  | `course_prerequisite_select` | SELECT | `CURRICULUM.ALL.READ` |
|  |  | `course_prerequisite_update` | UPDATE | `CURRICULUM.ALL.UPDATE` |
| `curriculum_course` | CURRICULUM | `curriculum_course_delete` | DELETE | `CURRICULUM.ALL.DELETE` |
|  |  | `curriculum_course_insert` | INSERT | `CURRICULUM.ALL.CREATE` |
|  |  | `curriculum_course_select` | SELECT | `CURRICULUM.ALL.READ` |
|  |  | `curriculum_course_update` | UPDATE | `CURRICULUM.ALL.UPDATE` |
| `curriculum_scheme` | CURRICULUM | `curriculum_scheme_delete` | DELETE | `CURRICULUM.ALL.DELETE` |
|  |  | `curriculum_scheme_insert` | INSERT | `CURRICULUM.ALL.CREATE` |
|  |  | `curriculum_scheme_select` | SELECT | `CURRICULUM.ALL.READ` |
|  |  | `curriculum_scheme_update` | UPDATE | `CURRICULUM.ALL.UPDATE` |
| `department` | INSTITUTION | `department_delete` | DELETE | `INSTITUTION.ALL.DELETE` |
|  |  | `department_insert` | INSERT | `INSTITUTION.ALL.CREATE` |
|  |  | `department_select` | SELECT | _membership only_ |
|  |  | `department_update` | UPDATE | `INSTITUTION.ALL.UPDATE` |
| `designation` | EMPLOYEE | `designation_delete` | DELETE | `EMPLOYEE.ALL.CONFIGURE` |
|  |  | `designation_insert` | INSERT | `EMPLOYEE.ALL.CONFIGURE` |
|  |  | `designation_select` | SELECT | _membership only_ |
|  |  | `designation_update` | UPDATE | `EMPLOYEE.ALL.CONFIGURE` |
| `document_type` | IAM | `document_type_delete` | DELETE | `IAM.ALL.CONFIGURE` |
|  |  | `document_type_insert` | INSERT | `IAM.ALL.CONFIGURE` |
|  |  | `document_type_select` | SELECT | _membership only_ |
|  |  | `document_type_update` | UPDATE | `IAM.ALL.CONFIGURE` |
| `education_institution` | EMPLOYEE | `education_institution_delete` | DELETE | `EMPLOYEE.ALL.CONFIGURE` |
|  |  | `education_institution_insert` | INSERT | `EMPLOYEE.ALL.CONFIGURE` |
|  |  | `education_institution_select` | SELECT | _membership only_ |
|  |  | `education_institution_update` | UPDATE | `EMPLOYEE.ALL.CONFIGURE` |
| `education_institution_type` | EMPLOYEE | `education_institution_type_delete` | DELETE | `EMPLOYEE.ALL.CONFIGURE` |
|  |  | `education_institution_type_insert` | INSERT | `EMPLOYEE.ALL.CONFIGURE` |
|  |  | `education_institution_type_select` | SELECT | _membership only_ |
|  |  | `education_institution_type_update` | UPDATE | `EMPLOYEE.ALL.CONFIGURE` |
| `employee` | EMPLOYEE | `employee_delete` | DELETE | `EMPLOYEE.ALL.DELETE` |
|  |  | `employee_insert` | INSERT | `EMPLOYEE.ALL.CREATE` |
|  |  | `employee_select` | SELECT | `EMPLOYEE.ALL.READ` |
|  |  | `employee_update` | UPDATE | `EMPLOYEE.ALL.UPDATE` |
| `employee_aadhaar` | EMPLOYEE | `employee_aadhaar_delete` | DELETE | `EMPLOYEE.AADHAAR.DELETE` |
|  |  | `employee_aadhaar_insert` | INSERT | `EMPLOYEE.AADHAAR.CREATE` |
|  |  | `employee_aadhaar_select` | SELECT | `EMPLOYEE.AADHAAR.READ` |
|  |  | `employee_aadhaar_update` | UPDATE | `EMPLOYEE.AADHAAR.UPDATE` |
| `employee_address` | EMPLOYEE | `employee_address_delete` | DELETE | `EMPLOYEE.ALL.DELETE` |
|  |  | `employee_address_insert` | INSERT | `EMPLOYEE.ALL.CREATE` |
|  |  | `employee_address_select` | SELECT | `EMPLOYEE.ALL.READ` |
|  |  | `employee_address_update` | UPDATE | `EMPLOYEE.ALL.UPDATE` |
| `employee_assignment` | EMPLOYEE | `employee_assignment_delete` | DELETE | `EMPLOYEE.ALL.DELETE` |
|  |  | `employee_assignment_insert` | INSERT | `EMPLOYEE.ALL.CREATE` |
|  |  | `employee_assignment_select` | SELECT | `EMPLOYEE.ALL.READ` |
|  |  | `employee_assignment_update` | UPDATE | `EMPLOYEE.ALL.UPDATE` |
| `employee_bank_account` | EMPLOYEE | `employee_bank_account_delete` | DELETE | `EMPLOYEE.BANK_ACCOUNT.DELETE` |
|  |  | `employee_bank_account_insert` | INSERT | `EMPLOYEE.BANK_ACCOUNT.CREATE` |
|  |  | `employee_bank_account_select` | SELECT | `EMPLOYEE.BANK_ACCOUNT.READ` |
|  |  | `employee_bank_account_update` | UPDATE | `EMPLOYEE.BANK_ACCOUNT.UPDATE` |
| `employee_competency` | EMPLOYEE | `employee_competency_delete` | DELETE | `EMPLOYEE.ALL.DELETE` |
|  |  | `employee_competency_insert` | INSERT | `EMPLOYEE.ALL.CREATE` |
|  |  | `employee_competency_select` | SELECT | `EMPLOYEE.ALL.READ` |
|  |  | `employee_competency_update` | UPDATE | `EMPLOYEE.ALL.UPDATE` |
| `employee_document` | EMPLOYEE | `employee_document_delete` | DELETE | `EMPLOYEE.EMPLOYEE_DOCUMENT.DELETE` |
|  |  | `employee_document_insert` | INSERT | `EMPLOYEE.EMPLOYEE_DOCUMENT.CREATE` |
|  |  | `employee_document_select` | SELECT | `EMPLOYEE.EMPLOYEE_DOCUMENT.READ` |
|  |  | `employee_document_update` | UPDATE | `EMPLOYEE.EMPLOYEE_DOCUMENT.UPDATE` |
| `employee_document_access_rule` | EMPLOYEE | `employee_document_access_rule_delete` | DELETE | `EMPLOYEE.EMPLOYEE_DOCUMENT.DELETE` |
|  |  | `employee_document_access_rule_insert` | INSERT | `EMPLOYEE.EMPLOYEE_DOCUMENT.CREATE` |
|  |  | `employee_document_access_rule_select` | SELECT | `EMPLOYEE.EMPLOYEE_DOCUMENT.READ` |
|  |  | `employee_document_access_rule_update` | UPDATE | `EMPLOYEE.EMPLOYEE_DOCUMENT.UPDATE` |
| `employee_document_category` | EMPLOYEE | `employee_document_category_delete` | DELETE | `EMPLOYEE.ALL.CONFIGURE` |
|  |  | `employee_document_category_insert` | INSERT | `EMPLOYEE.ALL.CONFIGURE` |
|  |  | `employee_document_category_select` | SELECT | _membership only_ |
|  |  | `employee_document_category_update` | UPDATE | `EMPLOYEE.ALL.CONFIGURE` |
| `employee_pan` | EMPLOYEE | `employee_pan_delete` | DELETE | `EMPLOYEE.PAN.DELETE` |
|  |  | `employee_pan_insert` | INSERT | `EMPLOYEE.PAN.CREATE` |
|  |  | `employee_pan_select` | SELECT | `EMPLOYEE.PAN.READ` |
|  |  | `employee_pan_update` | UPDATE | `EMPLOYEE.PAN.UPDATE` |
| `employee_previous_employment` | EMPLOYEE | `employee_previous_employment_delete` | DELETE | `EMPLOYEE.EXPERIENCE.DELETE` |
|  |  | `employee_previous_employment_insert` | INSERT | `EMPLOYEE.EXPERIENCE.CREATE` |
|  |  | `employee_previous_employment_select` | SELECT | `EMPLOYEE.EXPERIENCE.READ` |
|  |  | `employee_previous_employment_update` | UPDATE | `EMPLOYEE.EXPERIENCE.UPDATE` |
| `employee_qualification` | EMPLOYEE | `employee_qualification_delete` | DELETE | `EMPLOYEE.QUALIFICATION.DELETE` |
|  |  | `employee_qualification_insert` | INSERT | `EMPLOYEE.QUALIFICATION.CREATE` |
|  |  | `employee_qualification_select` | SELECT | `EMPLOYEE.QUALIFICATION.READ` |
|  |  | `employee_qualification_update` | UPDATE | `EMPLOYEE.QUALIFICATION.UPDATE` |
| `employee_sensitive_access_audit` | EMPLOYEE | `employee_sensitive_access_audit_select` | SELECT | `EMPLOYEE.EMPLOYEE_DOCUMENT.READ` |
| `employee_user_account` | IAM | `employee_user_account_select` | SELECT | `IAM.ALL.READ` |
| `employment_source` | EMPLOYEE | `employment_source_delete` | DELETE | `EMPLOYEE.ALL.CONFIGURE` |
|  |  | `employment_source_insert` | INSERT | `EMPLOYEE.ALL.CONFIGURE` |
|  |  | `employment_source_select` | SELECT | _membership only_ |
|  |  | `employment_source_update` | UPDATE | `EMPLOYEE.ALL.CONFIGURE` |
| `enrolment_status_history` | ADMISSION | `enrolment_status_history_delete` | DELETE | `ADMISSION.ALL.DELETE` |
|  |  | `enrolment_status_history_insert` | INSERT | `ADMISSION.ALL.CREATE` |
|  |  | `enrolment_status_history_select` | SELECT | `ADMISSION.ALL.READ` |
|  |  | `enrolment_status_history_update` | UPDATE | `ADMISSION.ALL.UPDATE` |
| `event_mode` | STAFF_PROFILE | `event_mode_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `event_mode_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `event_mode_select` | SELECT | _membership only_ |
|  |  | `event_mode_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `evidence_document` | STAFF_PROFILE | `evidence_document_select` | SELECT | `STAFF_PROFILE.STAFF_EVIDENCE.READ` |
| `evidence_document_audit` | STAFF_PROFILE | `evidence_document_audit_select` | SELECT | `STAFF_PROFILE.STAFF_EVIDENCE.READ` |
| `evidence_document_tag` | STAFF_PROFILE | `evidence_document_tag_delete` | DELETE | `STAFF_PROFILE.STAFF_EVIDENCE.DELETE` |
|  |  | `evidence_document_tag_insert` | INSERT | `STAFF_PROFILE.STAFF_EVIDENCE.CREATE` |
|  |  | `evidence_document_tag_select` | SELECT | `STAFF_PROFILE.STAFF_EVIDENCE.READ` |
|  |  | `evidence_document_tag_update` | UPDATE | `STAFF_PROFILE.STAFF_EVIDENCE.UPDATE` |
| `evidence_document_version` | STAFF_PROFILE | `evidence_document_version_select` | SELECT | `STAFF_PROFILE.STAFF_EVIDENCE.READ` |
| `evidence_tag` | STAFF_PROFILE | `evidence_tag_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `evidence_tag_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `evidence_tag_select` | SELECT | _membership only_ |
|  |  | `evidence_tag_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `evidence_type` | STAFF_PROFILE | `evidence_type_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `evidence_type_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `evidence_type_select` | SELECT | _membership only_ |
|  |  | `evidence_type_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `external_agency` | EMPLOYEE | `external_agency_delete` | DELETE | `EMPLOYEE.ALL.DELETE` |
|  |  | `external_agency_insert` | INSERT | `EMPLOYEE.ALL.CREATE` |
|  |  | `external_agency_select` | SELECT | `EMPLOYEE.ALL.READ` |
|  |  | `external_agency_update` | UPDATE | `EMPLOYEE.ALL.UPDATE` |
| `external_organization` | STAFF_PROFILE | `external_organization_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `external_organization_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `external_organization_select` | SELECT | _membership only_ |
|  |  | `external_organization_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `external_organization_type` | STAFF_PROFILE | `external_organization_type_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `external_organization_type_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `external_organization_type_select` | SELECT | _membership only_ |
|  |  | `external_organization_type_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `extracurricular_activity` | STAFF_PROFILE | `extracurricular_activity_select` | SELECT | `STAFF_PROFILE.STAFF_ACTIVITY.READ` |
| `extracurricular_category` | STAFF_PROFILE | `extracurricular_category_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `extracurricular_category_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `extracurricular_category_select` | SELECT | _membership only_ |
|  |  | `extracurricular_category_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `faculty_course_assignment` | TEACHING | `faculty_course_assignment_delete` | DELETE | `TEACHING.ALL.DELETE` |
|  |  | `faculty_course_assignment_insert` | INSERT | `TEACHING.ALL.CREATE` |
|  |  | `faculty_course_assignment_select` | SELECT | `TEACHING.ALL.READ` |
|  |  | `faculty_course_assignment_update` | UPDATE | `TEACHING.ALL.UPDATE` |
| `faculty_internship` | STAFF_PROFILE | `faculty_internship_select` | SELECT | `STAFF_PROFILE.STAFF_ACTIVITY.READ` |
| `fee_activity_audit` | FEES | `fee_activity_audit_select` | SELECT | `FEES.FEE_REPORT.READ` |
| `fee_adjustment` | FEES | `fee_adjustment_select` | SELECT | `FEES.FEE_ASSESSMENT.READ` |
| `fee_assessment_benefit` | FEES | `fee_assessment_benefit_select` | SELECT | `FEES.FEE_BENEFIT.READ` |
| `fee_category` | FEES | `fee_category_select` | SELECT | _membership only_ |
| `fee_charge_source` | FEES | `fee_charge_source_select` | SELECT | `FEES.FEE_ASSESSMENT.READ` |
| `fee_receipt` | FEES | `fee_receipt_select` | SELECT | `FEES.FEE_PAYMENT.READ` |
| `fee_refund` | FEES | `fee_refund_select` | SELECT | `FEES.FEE_REFUND.READ` |
| `fee_structure` | FEES | `fee_structure_select` | SELECT | `FEES.FEE_STRUCTURE.READ` |
| `fee_structure_item` | FEES | `fee_structure_item_select` | SELECT | `FEES.FEE_STRUCTURE.READ` |
| `fee_type` | FEES | `fee_type_select` | SELECT | _membership only_ |
| `feedback_choice` | FEEDBACK | `feedback_choice_delete` | DELETE | `FEEDBACK.ALL.CONFIGURE` |
|  |  | `feedback_choice_insert` | INSERT | `FEEDBACK.ALL.CONFIGURE` |
|  |  | `feedback_choice_select` | SELECT | _membership only_ |
|  |  | `feedback_choice_update` | UPDATE | `FEEDBACK.ALL.CONFIGURE` |
| `feedback_cycle` | FEEDBACK | `feedback_cycle_delete` | DELETE | `FEEDBACK.ALL.CONFIGURE` |
|  |  | `feedback_cycle_insert` | INSERT | `FEEDBACK.ALL.CONFIGURE` |
|  |  | `feedback_cycle_select` | SELECT | _membership only_ |
|  |  | `feedback_cycle_update` | UPDATE | `FEEDBACK.ALL.CONFIGURE` |
| `feedback_question` | FEEDBACK | `feedback_question_delete` | DELETE | `FEEDBACK.ALL.CONFIGURE` |
|  |  | `feedback_question_insert` | INSERT | `FEEDBACK.ALL.CONFIGURE` |
|  |  | `feedback_question_select` | SELECT | _membership only_ |
|  |  | `feedback_question_update` | UPDATE | `FEEDBACK.ALL.CONFIGURE` |
| `feedback_question_category` | FEEDBACK | `feedback_question_category_delete` | DELETE | `FEEDBACK.ALL.CONFIGURE` |
|  |  | `feedback_question_category_insert` | INSERT | `FEEDBACK.ALL.CONFIGURE` |
|  |  | `feedback_question_category_select` | SELECT | _membership only_ |
|  |  | `feedback_question_category_update` | UPDATE | `FEEDBACK.ALL.CONFIGURE` |
| `feedback_questionnaire` | FEEDBACK | `feedback_questionnaire_delete` | DELETE | `FEEDBACK.ALL.CONFIGURE` |
|  |  | `feedback_questionnaire_insert` | INSERT | `FEEDBACK.ALL.CONFIGURE` |
|  |  | `feedback_questionnaire_select` | SELECT | _membership only_ |
|  |  | `feedback_questionnaire_update` | UPDATE | `FEEDBACK.ALL.CONFIGURE` |
| `feedback_questionnaire_item` | FEEDBACK | `feedback_questionnaire_item_delete` | DELETE | `FEEDBACK.ALL.CONFIGURE` |
|  |  | `feedback_questionnaire_item_insert` | INSERT | `FEEDBACK.ALL.CONFIGURE` |
|  |  | `feedback_questionnaire_item_select` | SELECT | _membership only_ |
|  |  | `feedback_questionnaire_item_update` | UPDATE | `FEEDBACK.ALL.CONFIGURE` |
| `feedback_response` | FEEDBACK | `feedback_response_select` | SELECT | `FEEDBACK.ALL.READ` |
| `feedback_response_item` | FEEDBACK | `feedback_response_item_select` | SELECT | `FEEDBACK.ALL.READ` |
| `file_object` | DOCUMENT | `file_object_select` | SELECT | `DOCUMENT.ALL.READ` |
| `financial_ledger_account` | FEES | `financial_ledger_account_select` | SELECT | `FEES.FEE_REPORT.READ` |
| `funded_research_project` | STAFF_PROFILE | `funded_research_project_select` | SELECT | `STAFF_PROFILE.STAFF_RESEARCH.READ` |
| `funding_agency` | STAFF_PROFILE | `funding_agency_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `funding_agency_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `funding_agency_select` | SELECT | _membership only_ |
|  |  | `funding_agency_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `funding_type` | STAFF_PROFILE | `funding_type_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `funding_type_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `funding_type_select` | SELECT | _membership only_ |
|  |  | `funding_type_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `gender` | IAM | `gender_delete` | DELETE | `IAM.ALL.CONFIGURE` |
|  |  | `gender_insert` | INSERT | `IAM.ALL.CONFIGURE` |
|  |  | `gender_select` | SELECT | _membership only_ |
|  |  | `gender_update` | UPDATE | `IAM.ALL.CONFIGURE` |
| `grade_rule` | RESULT | `grade_rule_delete` | DELETE | `RESULT.ALL.CONFIGURE` |
|  |  | `grade_rule_insert` | INSERT | `RESULT.ALL.CONFIGURE` |
|  |  | `grade_rule_select` | SELECT | _membership only_ |
|  |  | `grade_rule_update` | UPDATE | `RESULT.ALL.CONFIGURE` |
| `grade_scale` | RESULT | `grade_scale_delete` | DELETE | `RESULT.ALL.CONFIGURE` |
|  |  | `grade_scale_insert` | INSERT | `RESULT.ALL.CONFIGURE` |
|  |  | `grade_scale_select` | SELECT | _membership only_ |
|  |  | `grade_scale_update` | UPDATE | `RESULT.ALL.CONFIGURE` |
| `grievance` | GRIEVANCE | `grievance_select` | SELECT | `GRIEVANCE.ALL.READ` |
| `grievance_action` | GRIEVANCE | `grievance_action_select` | SELECT | `GRIEVANCE.ALL.READ` |
| `grievance_category` | GRIEVANCE | `grievance_category_delete` | DELETE | `GRIEVANCE.ALL.CONFIGURE` |
|  |  | `grievance_category_insert` | INSERT | `GRIEVANCE.ALL.CONFIGURE` |
|  |  | `grievance_category_select` | SELECT | _membership only_ |
|  |  | `grievance_category_update` | UPDATE | `GRIEVANCE.ALL.CONFIGURE` |
| `indexing_agency` | STAFF_PROFILE | `indexing_agency_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `indexing_agency_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `indexing_agency_select` | SELECT | _membership only_ |
|  |  | `indexing_agency_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `industry_sector` | STAFF_PROFILE | `industry_sector_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `industry_sector_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `industry_sector_select` | SELECT | _membership only_ |
|  |  | `industry_sector_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `installment_plan` | FEES | `installment_plan_select` | SELECT | _membership only_ |
| `institution` | INSTITUTION | `institution_select` | SELECT | _membership only_ |
| `journal` | STAFF_PROFILE | `journal_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `journal_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `journal_select` | SELECT | _membership only_ |
|  |  | `journal_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `journal_metric` | STAFF_PROFILE | `journal_metric_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `journal_metric_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `journal_metric_select` | SELECT | _membership only_ |
|  |  | `journal_metric_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `journal_publication` | STAFF_PROFILE | `journal_publication_select` | SELECT | `STAFF_PROFILE.STAFF_ACTIVITY.READ` |
| `journal_publication_indexing` | STAFF_PROFILE | `journal_publication_indexing_delete` | DELETE | `STAFF_PROFILE.STAFF_ACTIVITY.DELETE` |
|  |  | `journal_publication_indexing_insert` | INSERT | `STAFF_PROFILE.STAFF_ACTIVITY.CREATE` |
|  |  | `journal_publication_indexing_select` | SELECT | `STAFF_PROFILE.STAFF_ACTIVITY.READ` |
|  |  | `journal_publication_indexing_update` | UPDATE | `STAFF_PROFILE.STAFF_ACTIVITY.UPDATE` |
| `journal_type` | STAFF_PROFILE | `journal_type_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `journal_type_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `journal_type_select` | SELECT | _membership only_ |
|  |  | `journal_type_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `late_fee_rule` | FEES | `late_fee_rule_select` | SELECT | _membership only_ |
| `late_fee_slab` | FEES | `late_fee_slab_select` | SELECT | _membership only_ |
| `login_audit` | IAM | `login_audit_select` | SELECT | `IAM.ALL.READ` |
| `membership_type` | STAFF_PROFILE | `membership_type_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `membership_type_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `membership_type_select` | SELECT | _membership only_ |
|  |  | `membership_type_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `mentor_assignment` | MENTORING | `mentor_assignment_select` | SELECT | `MENTORING.ALL.READ` |
| `metric_type` | STAFF_PROFILE | `metric_type_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `metric_type_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `metric_type_select` | SELECT | _membership only_ |
|  |  | `metric_type_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `organization_type` | STAFF_PROFILE | `organization_type_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `organization_type_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `organization_type_select` | SELECT | _membership only_ |
|  |  | `organization_type_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `organizer` | STAFF_PROFILE | `organizer_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `organizer_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `organizer_select` | SELECT | _membership only_ |
|  |  | `organizer_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `participation_level` | STAFF_PROFILE | `participation_level_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `participation_level_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `participation_level_select` | SELECT | _membership only_ |
|  |  | `participation_level_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `password_history` | IAM | `password_history_select` | SELECT | `IAM.ALL.READ` |
| `payment_allocation` | FEES | `payment_allocation_select` | SELECT | `FEES.FEE_PAYMENT.READ` |
| `payment_mode` | FEES | `payment_mode_select` | SELECT | _membership only_ |
| `payment_transaction` | FEES | `payment_transaction_select` | SELECT | `FEES.FEE_PAYMENT.READ` |
| `permission` | IAM | `permission_select` | SELECT | `IAM.ALL.READ` |
| `previous_organization` | EMPLOYEE | `previous_organization_delete` | DELETE | `EMPLOYEE.ALL.CONFIGURE` |
|  |  | `previous_organization_insert` | INSERT | `EMPLOYEE.ALL.CONFIGURE` |
|  |  | `previous_organization_select` | SELECT | _membership only_ |
|  |  | `previous_organization_update` | UPDATE | `EMPLOYEE.ALL.CONFIGURE` |
| `previous_organization_type` | EMPLOYEE | `previous_organization_type_delete` | DELETE | `EMPLOYEE.ALL.CONFIGURE` |
|  |  | `previous_organization_type_insert` | INSERT | `EMPLOYEE.ALL.CONFIGURE` |
|  |  | `previous_organization_type_select` | SELECT | _membership only_ |
|  |  | `previous_organization_type_update` | UPDATE | `EMPLOYEE.ALL.CONFIGURE` |
| `professional_contribution_type` | STAFF_PROFILE | `professional_contribution_type_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `professional_contribution_type_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `professional_contribution_type_select` | SELECT | _membership only_ |
|  |  | `professional_contribution_type_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `professional_development_activity` | STAFF_PROFILE | `professional_development_activity_select` | SELECT | `STAFF_PROFILE.STAFF_ACTIVITY.READ` |
| `programme` | INSTITUTION | `programme_delete` | DELETE | `INSTITUTION.ALL.DELETE` |
|  |  | `programme_insert` | INSERT | `INSTITUTION.ALL.CREATE` |
|  |  | `programme_select` | SELECT | _membership only_ |
|  |  | `programme_update` | UPDATE | `INSTITUTION.ALL.UPDATE` |
| `programme_specialization` | INSTITUTION | `programme_specialization_delete` | DELETE | `INSTITUTION.ALL.DELETE` |
|  |  | `programme_specialization_insert` | INSERT | `INSTITUTION.ALL.CREATE` |
|  |  | `programme_specialization_select` | SELECT | `INSTITUTION.ALL.READ` |
|  |  | `programme_specialization_update` | UPDATE | `INSTITUTION.ALL.UPDATE` |
| `programme_term_offering` | REGISTRATION | `programme_term_offering_delete` | DELETE | `REGISTRATION.ALL.DELETE` |
|  |  | `programme_term_offering_insert` | INSERT | `REGISTRATION.ALL.CREATE` |
|  |  | `programme_term_offering_select` | SELECT | `REGISTRATION.ALL.READ` |
|  |  | `programme_term_offering_update` | UPDATE | `REGISTRATION.ALL.UPDATE` |
| `publication_type` | STAFF_PROFILE | `publication_type_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `publication_type_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `publication_type_select` | SELECT | _membership only_ |
|  |  | `publication_type_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `publisher` | STAFF_PROFILE | `publisher_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `publisher_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `publisher_select` | SELECT | _membership only_ |
|  |  | `publisher_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `qualification_level` | EMPLOYEE | `qualification_level_delete` | DELETE | `EMPLOYEE.ALL.CONFIGURE` |
|  |  | `qualification_level_insert` | INSERT | `EMPLOYEE.ALL.CONFIGURE` |
|  |  | `qualification_level_select` | SELECT | _membership only_ |
|  |  | `qualification_level_update` | UPDATE | `EMPLOYEE.ALL.CONFIGURE` |
| `refund_request` | FEES | `refund_request_select` | SELECT | `FEES.FEE_REFUND.READ` |
| `religion` | IAM | `religion_delete` | DELETE | `IAM.ALL.CONFIGURE` |
|  |  | `religion_insert` | INSERT | `IAM.ALL.CONFIGURE` |
|  |  | `religion_select` | SELECT | _membership only_ |
|  |  | `religion_update` | UPDATE | `IAM.ALL.CONFIGURE` |
| `research_project_financial_utilization` | STAFF_PROFILE | `research_project_financial_utilization_delete` | DELETE | `STAFF_PROFILE.STAFF_RESEARCH.DELETE` |
|  |  | `research_project_financial_utilization_insert` | INSERT | `STAFF_PROFILE.STAFF_RESEARCH.CREATE` |
|  |  | `research_project_financial_utilization_select` | SELECT | `STAFF_PROFILE.STAFF_RESEARCH.READ` |
|  |  | `research_project_financial_utilization_update` | UPDATE | `STAFF_PROFILE.STAFF_RESEARCH.UPDATE` |
| `research_proposal` | STAFF_PROFILE | `research_proposal_select` | SELECT | `STAFF_PROFILE.STAFF_RESEARCH.READ` |
| `research_status` | STAFF_PROFILE | `research_status_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `research_status_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `research_status_select` | SELECT | _membership only_ |
|  |  | `research_status_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `research_supervision` | STAFF_PROFILE | `research_supervision_delete` | DELETE | `STAFF_PROFILE.STAFF_RESEARCH.DELETE` |
|  |  | `research_supervision_insert` | INSERT | `STAFF_PROFILE.STAFF_RESEARCH.CREATE` |
|  |  | `research_supervision_select` | SELECT | `STAFF_PROFILE.STAFF_RESEARCH.READ` |
|  |  | `research_supervision_update` | UPDATE | `STAFF_PROFILE.STAFF_RESEARCH.UPDATE` |
| `role` | IAM | `role_select` | SELECT | `IAM.ALL.READ` |
| `role_delegation` | IAM | `role_delegation_select` | SELECT | `IAM.ALL.READ` |
| `role_permission` | IAM | `role_permission_select` | SELECT | `IAM.ALL.READ` |
| `role_type` | STAFF_PROFILE | `role_type_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `role_type_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `role_type_select` | SELECT | _membership only_ |
|  |  | `role_type_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `room` | INSTITUTION | `room_delete` | DELETE | `INSTITUTION.ALL.DELETE` |
|  |  | `room_insert` | INSERT | `INSTITUTION.ALL.CREATE` |
|  |  | `room_select` | SELECT | `INSTITUTION.ALL.READ` |
|  |  | `room_update` | UPDATE | `INSTITUTION.ALL.UPDATE` |
| `scholarship_scheme` | FEES | `scholarship_scheme_select` | SELECT | _membership only_ |
| `semester` | ACADEMIC_CALENDAR | `semester_delete` | DELETE | `ACADEMIC_CALENDAR.ALL.CONFIGURE` |
|  |  | `semester_insert` | INSERT | `ACADEMIC_CALENDAR.ALL.CONFIGURE` |
|  |  | `semester_select` | SELECT | _membership only_ |
|  |  | `semester_update` | UPDATE | `ACADEMIC_CALENDAR.ALL.CONFIGURE` |
| `service_fee_request` | FEES | `service_fee_request_select` | SELECT | `FEES.FEE_ASSESSMENT.READ` |
| `social_category` | IAM | `social_category_delete` | DELETE | `IAM.ALL.CONFIGURE` |
|  |  | `social_category_insert` | INSERT | `IAM.ALL.CONFIGURE` |
|  |  | `social_category_select` | SELECT | _membership only_ |
|  |  | `social_category_update` | UPDATE | `IAM.ALL.CONFIGURE` |
| `staff_activity` | STAFF_PROFILE | `staff_activity_select` | SELECT | `STAFF_PROFILE.STAFF_ACTIVITY.READ` |
| `staff_activity_contributor` | STAFF_PROFILE | `staff_activity_contributor_select` | SELECT | `STAFF_PROFILE.STAFF_ACTIVITY.READ` |
| `staff_award` | STAFF_PROFILE | `staff_award_select` | SELECT | `STAFF_PROFILE.STAFF_ACTIVITY.READ` |
| `staff_category` | EMPLOYEE | `staff_category_delete` | DELETE | `EMPLOYEE.ALL.CONFIGURE` |
|  |  | `staff_category_insert` | INSERT | `EMPLOYEE.ALL.CONFIGURE` |
|  |  | `staff_category_select` | SELECT | _membership only_ |
|  |  | `staff_category_update` | UPDATE | `EMPLOYEE.ALL.CONFIGURE` |
| `staff_professional_contribution` | STAFF_PROFILE | `staff_professional_contribution_select` | SELECT | `STAFF_PROFILE.STAFF_ACTIVITY.READ` |
| `staff_professional_membership` | STAFF_PROFILE | `staff_professional_membership_select` | SELECT | `STAFF_PROFILE.STAFF_ACTIVITY.READ` |
| `staff_type` | EMPLOYEE | `staff_type_delete` | DELETE | `EMPLOYEE.ALL.CONFIGURE` |
|  |  | `staff_type_insert` | INSERT | `EMPLOYEE.ALL.CONFIGURE` |
|  |  | `staff_type_select` | SELECT | _membership only_ |
|  |  | `staff_type_update` | UPDATE | `EMPLOYEE.ALL.CONFIGURE` |
| `state` | IAM | `state_delete` | DELETE | `IAM.ALL.CONFIGURE` |
|  |  | `state_insert` | INSERT | `IAM.ALL.CONFIGURE` |
|  |  | `state_select` | SELECT | _membership only_ |
|  |  | `state_update` | UPDATE | `IAM.ALL.CONFIGURE` |
| `student` | STUDENT | `student_delete` | DELETE | `STUDENT.ALL.DELETE` |
|  |  | `student_insert` | INSERT | `STUDENT.ALL.CREATE` |
|  |  | `student_select` | SELECT | `STUDENT.ALL.READ` |
|  |  | `student_update` | UPDATE | `STUDENT.ALL.UPDATE` |
| `student_activity` | STUDENT | `student_activity_select` | SELECT | `STUDENT.STUDENT_ACTIVITY.READ` |
| `student_activity_evidence` | STUDENT | `student_activity_evidence_select` | SELECT | `STUDENT.STUDENT_ACTIVITY_EVIDENCE.READ` |
| `student_activity_evidence_audit` | STUDENT | `student_activity_evidence_audit_select` | SELECT | `STUDENT.STUDENT_ACTIVITY_EVIDENCE.READ` |
| `student_activity_evidence_requirement` | STUDENT | `student_activity_evidence_requirement_delete` | DELETE | `STUDENT.ALL.CONFIGURE` |
|  |  | `student_activity_evidence_requirement_insert` | INSERT | `STUDENT.ALL.CONFIGURE` |
|  |  | `student_activity_evidence_requirement_select` | SELECT | _membership only_ |
|  |  | `student_activity_evidence_requirement_update` | UPDATE | `STUDENT.ALL.CONFIGURE` |
| `student_activity_evidence_version` | STUDENT | `student_activity_evidence_version_select` | SELECT | `STUDENT.STUDENT_ACTIVITY_EVIDENCE.READ` |
| `student_activity_team_member` | STUDENT | `student_activity_team_member_select` | SELECT | `STUDENT.STUDENT_ACTIVITY.READ` |
| `student_activity_type` | STUDENT | `student_activity_type_delete` | DELETE | `STUDENT.ALL.CONFIGURE` |
|  |  | `student_activity_type_insert` | INSERT | `STUDENT.ALL.CONFIGURE` |
|  |  | `student_activity_type_select` | SELECT | _membership only_ |
|  |  | `student_activity_type_update` | UPDATE | `STUDENT.ALL.CONFIGURE` |
| `student_address` | STUDENT | `student_address_delete` | DELETE | `STUDENT.ALL.DELETE` |
|  |  | `student_address_insert` | INSERT | `STUDENT.ALL.CREATE` |
|  |  | `student_address_select` | SELECT | `STUDENT.ALL.READ` |
|  |  | `student_address_update` | UPDATE | `STUDENT.ALL.UPDATE` |
| `student_assessment_mark` | ASSESSMENT | `student_assessment_mark_select` | SELECT | `ASSESSMENT.ALL.READ` |
| `student_attendance` | ATTENDANCE | `student_attendance_select` | SELECT | `ATTENDANCE.ALL.READ` |
| `student_course_registration` | REGISTRATION | `student_course_registration_delete` | DELETE | `REGISTRATION.ALL.DELETE` |
|  |  | `student_course_registration_insert` | INSERT | `REGISTRATION.ALL.CREATE` |
|  |  | `student_course_registration_select` | SELECT | `REGISTRATION.ALL.READ` |
|  |  | `student_course_registration_update` | UPDATE | `REGISTRATION.ALL.UPDATE` |
| `student_course_result` | RESULT | `student_course_result_select` | SELECT | `RESULT.ALL.READ` |
| `student_document` | DOCUMENT | `student_document_delete` | DELETE | `DOCUMENT.ALL.DELETE` |
|  |  | `student_document_insert` | INSERT | `DOCUMENT.ALL.CREATE` |
|  |  | `student_document_select` | SELECT | `DOCUMENT.ALL.READ` |
|  |  | `student_document_update` | UPDATE | `DOCUMENT.ALL.UPDATE` |
| `student_entrance_exam` | STUDENT | `student_entrance_exam_delete` | DELETE | `STUDENT.ALL.DELETE` |
|  |  | `student_entrance_exam_insert` | INSERT | `STUDENT.ALL.CREATE` |
|  |  | `student_entrance_exam_select` | SELECT | `STUDENT.ALL.READ` |
|  |  | `student_entrance_exam_update` | UPDATE | `STUDENT.ALL.UPDATE` |
| `student_exit` | DOCUMENT | `student_exit_delete` | DELETE | `DOCUMENT.ALL.DELETE` |
|  |  | `student_exit_insert` | INSERT | `DOCUMENT.ALL.CREATE` |
|  |  | `student_exit_select` | SELECT | `DOCUMENT.ALL.READ` |
|  |  | `student_exit_update` | UPDATE | `DOCUMENT.ALL.UPDATE` |
| `student_fee_assessment` | FEES | `student_fee_assessment_select` | SELECT | `FEES.FEE_ASSESSMENT.READ` |
| `student_fee_assessment_item` | FEES | `student_fee_assessment_item_select` | SELECT | `FEES.FEE_ASSESSMENT.READ` |
| `student_fee_concession` | FEES | `student_fee_concession_select` | SELECT | `FEES.FEE_BENEFIT.READ` |
| `student_fee_penalty` | FEES | `student_fee_penalty_select` | SELECT | `FEES.FEE_ASSESSMENT.READ` |
| `student_financial_account` | FEES | `student_financial_account_select` | SELECT | `FEES.FEE_ASSESSMENT.READ` |
| `student_financial_hold` | FEES | `student_financial_hold_select` | SELECT | `FEES.FEE_ASSESSMENT.READ` |
| `student_installment_schedule` | FEES | `student_installment_schedule_select` | SELECT | `FEES.FEE_ASSESSMENT.READ` |
| `student_parent_guardian` | STUDENT | `student_parent_guardian_delete` | DELETE | `STUDENT.ALL.DELETE` |
|  |  | `student_parent_guardian_insert` | INSERT | `STUDENT.ALL.CREATE` |
|  |  | `student_parent_guardian_select` | SELECT | `STUDENT.ALL.READ` |
|  |  | `student_parent_guardian_update` | UPDATE | `STUDENT.ALL.UPDATE` |
| `student_previous_education` | STUDENT | `student_previous_education_delete` | DELETE | `STUDENT.ALL.DELETE` |
|  |  | `student_previous_education_insert` | INSERT | `STUDENT.ALL.CREATE` |
|  |  | `student_previous_education_select` | SELECT | `STUDENT.ALL.READ` |
|  |  | `student_previous_education_update` | UPDATE | `STUDENT.ALL.UPDATE` |
| `student_programme_enrolment` | ADMISSION | `student_programme_enrolment_delete` | DELETE | `ADMISSION.ALL.DELETE` |
|  |  | `student_programme_enrolment_insert` | INSERT | `ADMISSION.ALL.CREATE` |
|  |  | `student_programme_enrolment_select` | SELECT | `ADMISSION.ALL.READ` |
|  |  | `student_programme_enrolment_update` | UPDATE | `ADMISSION.ALL.UPDATE` |
| `student_residence` | STUDENT | `student_residence_delete` | DELETE | `STUDENT.ALL.DELETE` |
|  |  | `student_residence_insert` | INSERT | `STUDENT.ALL.CREATE` |
|  |  | `student_residence_select` | SELECT | `STUDENT.ALL.READ` |
|  |  | `student_residence_update` | UPDATE | `STUDENT.ALL.UPDATE` |
| `student_scholarship` | FEES | `student_scholarship_select` | SELECT | `FEES.FEE_BENEFIT.READ` |
| `student_sponsorship` | FEES | `student_sponsorship_select` | SELECT | `FEES.FEE_BENEFIT.READ` |
| `student_term_registration` | REGISTRATION | `student_term_registration_delete` | DELETE | `REGISTRATION.ALL.DELETE` |
|  |  | `student_term_registration_insert` | INSERT | `REGISTRATION.ALL.CREATE` |
|  |  | `student_term_registration_select` | SELECT | `REGISTRATION.ALL.READ` |
|  |  | `student_term_registration_update` | UPDATE | `REGISTRATION.ALL.UPDATE` |
| `student_term_result` | RESULT | `student_term_result_select` | SELECT | `RESULT.ALL.READ` |
| `student_user_account` | IAM | `student_user_account_select` | SELECT | `IAM.ALL.READ` |
| `study_mode` | EMPLOYEE | `study_mode_delete` | DELETE | `EMPLOYEE.ALL.CONFIGURE` |
|  |  | `study_mode_insert` | INSERT | `EMPLOYEE.ALL.CONFIGURE` |
|  |  | `study_mode_select` | SELECT | _membership only_ |
|  |  | `study_mode_update` | UPDATE | `EMPLOYEE.ALL.CONFIGURE` |
| `sub_caste` | IAM | `sub_caste_delete` | DELETE | `IAM.ALL.CONFIGURE` |
|  |  | `sub_caste_insert` | INSERT | `IAM.ALL.CONFIGURE` |
|  |  | `sub_caste_select` | SELECT | _membership only_ |
|  |  | `sub_caste_update` | UPDATE | `IAM.ALL.CONFIGURE` |
| `time_slot` | ACADEMIC_CALENDAR | `time_slot_delete` | DELETE | `ACADEMIC_CALENDAR.ALL.DELETE` |
|  |  | `time_slot_insert` | INSERT | `ACADEMIC_CALENDAR.ALL.CREATE` |
|  |  | `time_slot_select` | SELECT | `ACADEMIC_CALENDAR.ALL.READ` |
|  |  | `time_slot_update` | UPDATE | `ACADEMIC_CALENDAR.ALL.UPDATE` |
| `timetable_session` | TIMETABLE | `timetable_session_delete` | DELETE | `TIMETABLE.ALL.DELETE` |
|  |  | `timetable_session_insert` | INSERT | `TIMETABLE.ALL.CREATE` |
|  |  | `timetable_session_select` | SELECT | `TIMETABLE.ALL.READ` |
|  |  | `timetable_session_update` | UPDATE | `TIMETABLE.ALL.UPDATE` |
| `training_program_type` | STAFF_PROFILE | `training_program_type_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `training_program_type_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `training_program_type_select` | SELECT | _membership only_ |
|  |  | `training_program_type_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |
| `university` | INSTITUTION | `university_delete` | DELETE | `INSTITUTION.ALL.CONFIGURE` |
|  |  | `university_insert` | INSERT | `INSTITUTION.ALL.CONFIGURE` |
|  |  | `university_select` | SELECT | _membership only_ |
|  |  | `university_update` | UPDATE | `INSTITUTION.ALL.CONFIGURE` |
| `user_account` | IAM | `user_account_select` | SELECT | `IAM.ALL.READ` |
| `user_permission_override` | IAM | `user_permission_override_select` | SELECT | `IAM.ALL.READ` |
| `user_role_assignment` | IAM | `user_role_assignment_select` | SELECT | `IAM.ALL.READ` |
| `verification_status` | STAFF_PROFILE | `verification_status_delete` | DELETE | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `verification_status_insert` | INSERT | `STAFF_PROFILE.ALL.CONFIGURE` |
|  |  | `verification_status_select` | SELECT | _membership only_ |
|  |  | `verification_status_update` | UPDATE | `STAFF_PROFILE.ALL.CONFIGURE` |

## Totals

- public tables: 213
- policies: 594
- modules referenced: 20
