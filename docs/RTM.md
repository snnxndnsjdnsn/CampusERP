# Requirements traceability matrix (RTM)

One row per database module. The module list is taken from the numbered section
headers of the authoritative source `SIMS-DatabaseWithoutLessonPlan.sql` — that is the
only module numbering in the project that is derived from the schema itself. The
older 1–23 numbering used by `docs/MODULE_DOCUMENTATION.md` is a *screen* grouping and
does not match the schema; both are reconciled in that document.

Everything in the tables below was read out of the live database
(`khqqfgqvwdxlqkncwtmh`, read-only) or out of `src/lib/nav.ts`. No object name in
this document is inferred.

## How to read this document

| Column | Meaning |
|---|---|
| **Module #** | The section number in `SIMS-DatabaseWithoutLessonPlan.sql`. Two headers are numbered `18`; both are listed. |
| **Module name** | The header text, verbatim. |
| **Key tables** | The tables that carry the module's contract. The bracketed number is the module's **total** table count. |
| **Key RPCs** | The `public.*` functions that implement the module's writes and reads. `—` means the module has no dedicated RPC and is authorised by table RLS alone. |
| **UI route(s)** | The routes in `src/lib/nav.ts` that expose the module. Detail routes that exist but are not sidebar entries are shown in brackets. |
| **Access module code** | The `access_module.module_code` value(s) that gate the module. `—` means the module owns no tables and has no code of its own. |
| **Status** | See the legend below. |

### Status legend

| Status | Meaning |
|---|---|
| **Complete** | Schema objects are live, authorisation is live (RLS policy or `SECURITY DEFINER` RPC), and the UI route exists with a `page.tsx`. |
| **DB complete; UI pending** | Schema and authorisation are live, but the route named in `nav.ts` has no `src/app/(app)<route>/page.tsx` yet. No module currently holds this status — `/staff-profile` and `/activities` were the last two and both now have a page. |
| **Schema only** | Tables are live with RLS; there is no dedicated RPC surface and no route of its own. |
| **Infrastructure** | The module owns no tables. It is triggers, indexes, seed data or notes that support other modules. |
| **Gap** | The module is declared in the access catalogue but nothing enforces it. |

## Module matrix

| Module # | Module name | Key tables | Key RPCs | UI route(s) | Access module code | Status |
|---|---|---|---|---|---|---|
| 1 | COMMON REFERENCE MODULE | `country`, `state`, `gender`, `blood_group`, `religion`, `social_category`, `caste`, `sub_caste`, `admission_category`, `document_type` [10] | `ref_list`, `ref_rows`, `ref_save`, `ref_delete`, `ref_schema` | `/admin/reference` | IAM | Complete |
| 2 | UNIVERSITY AND INSTITUTION STRUCTURE MODULE | `university`, `institution`, `campus`, `department`, `programme`, `programme_specialization`, `building`, `room` [8] | `institution_create`, `institution_update`, `record_sections`, `section_save`, `section_delete`, `section_rows`, `section_schema`, `section_lookup_options` | `/structure` | INSTITUTION | Complete |
| 3 | ACADEMIC CALENDAR MODULE | `academic_year`, `academic_term`, `semester`, `time_slot` [4] | — (RLS only) | `/calendar` | ACADEMIC_CALENDAR | Complete |
| 4 | CURRICULUM AND COURSE CATALOG MODULE | `course_category`, `course_catalog`, `curriculum_scheme`, `curriculum_course`, `course_prerequisite` [5] | — (RLS only) | `/curriculum`, `/courses` | CURRICULUM | Complete |
| 5 | STUDENT AND STAFF MASTER MODULES (INDEPENDENT ROOT ENTITIES) | `student`, `student_address`, `student_parent_guardian`, `student_residence`, `student_previous_education`, `student_entrance_exam`, `staff_type`, `staff_category`, `employment_source`, `external_agency`, `designation`, `employee`, `employee_address`, `employee_assignment`, `employee_competency` [15] | `student_register`, `employee_register`, `employee_assign`, `emp_competency_save`, `emp_competency_list`, `emp_competency_delete` | `/students`, `/employees` | STUDENT, EMPLOYEE | Complete |
| 6 | ADMISSION AND ENROLMENT TRANSACTION MODULE | `admission_applicant`, `admission_application`, `student_programme_enrolment`, `enrolment_status_history` [4] | `admission_apply`, `admission_update_applicant`, `admission_update_application`, `admission_set_status`, `admission_admit` | `/admissions` | ADMISSION | Complete |
| 7 | TERM REGISTRATION, SECTION AND COURSE REGISTRATION MODULE | `programme_term_offering`, `class_section`, `class_batch`, `student_term_registration`, `course_offering`, `course_offering_section`, `student_course_registration`, `course_offering_section_student` [8] | `registration_term_info`, `registration_candidates`, `registration_roster`, `offering_generate_courses`, `teaching_populate_roster` | `/registration` | REGISTRATION, TEACHING | Complete |
| 8 | TEACHING ALLOCATION AND TIMETABLE MODULE | `faculty_course_assignment`, `timetable_session` [2] | `timetable_offerings`, `timetable_offering_info`, `timetable_sections`, `timetable_slots`, `timetable_rooms`, `timetable_entries`, `timetable_assignments`, `timetable_generate_sessions` | `/timetable` | TEACHING, TIMETABLE | Complete |
| 9 | ATTENDANCE AND LESSON PLAN MODULE | `class_session`, `attendance_status`, `student_attendance`, `attendance_correction_request` [4] | `attendance_sheet`, `attendance_mark`, `attendance_summary`, `attendance_request_correction`, `attendance_decide_correction` | `/attendance` | ATTENDANCE | Complete |
| 10 | CONTINUOUS ASSESSMENT AND RESULT MODULE | `assessment_component`, `assessment_event`, `student_assessment_mark`, `grade_scale`, `grade_rule`, `student_course_result`, `student_term_result` [7] | `assessment_offerings`, `assessment_offering_info`, `assessment_sheet`, `assessment_enter_marks`, `result_compute_term`, `result_record_course`, `result_term_sheet`, `result_course_sheet`, `result_publish_term` | `/assessment`, `/results`, `/my-results` | ASSESSMENT, RESULT | Complete |
| 11 | FEEDBACK MODULE | `feedback_question_category`, `feedback_question`, `feedback_choice`, `feedback_questionnaire`, `feedback_questionnaire_item`, `feedback_cycle`, `feedback_response`, `feedback_response_item` [8] | `feedback_cycle_offerings`, `feedback_form`, `feedback_my_tasks`, `feedback_submit`, `feedback_results` | `/feedback` | FEEDBACK | Complete |
| 12 | MENTORING, COUNSELLING AND GRIEVANCE MODULE | `mentor_assignment`, `counselling_session`, `grievance_category`, `grievance`, `grievance_action` [5] | `mentoring_assignments`, `mentoring_assign`, `mentoring_assignment_info`, `mentoring_record_session`, `mentoring_sessions`, `mentoring_update_session`, `mentoring_end_assignment`, `grievance_submit`, `grievance_list`, `grievance_detail`, `grievance_act`, `grievance_my`, `grievance_student_respond` | `/mentoring`, `/grievances` | MENTORING, GRIEVANCE | Complete |
| 13 | DOCUMENT, CERTIFICATE AND EXIT MODULE | `file_object`, `student_document`, `certificate_type`, `certificate_request`, `student_exit` [5] | `cert_request_create`, `cert_request_list`, `cert_request_decide`, `cert_request_issue`, `cert_request_cancel`, `cert_request_download_info`, `svc_my_terms`, `svc_request_create`, `svc_request_list`, `svc_request_decide`, `svc_request_cancel` | `/certificates`, `/requests`, `/my-documents` | DOCUMENT | Complete |
| 14 | COMMUNICATION MODULE | `announcement_type`, `announcement`, `announcement_attachment` [3] | `announcements_feed`, `announcements_manage`, `announcement_save`, `announcement_submit`, `announcement_decide`, `announcement_archive`, `announcement_targets`, `announcement_detail`, `announcement_can_post_global`, `announcement_attachment_register`, `announcement_attachment_list`, `announcement_attachment_remove`, `announcement_attachment_download_info`, `notification_dismiss`, `notification_dismiss_all` | `/announcements` | COMMUNICATION | Complete |
| 15 | IDENTITY, ACCESS CONTROL (RBAC) AND AUDIT MODULE | `user_account`, `student_user_account`, `employee_user_account`, `access_module`, `access_resource`, `access_action`, `permission`, `role`, `role_permission`, `user_role_assignment`, `user_permission_override`, `role_delegation`, `password_history`, `login_audit`, `activity_audit` [15] | `iam_user_list`, `iam_user_detail`, `iam_roles`, `iam_assign_role`, `iam_revoke_role`, `iam_provision_user`, `iam_link_person`, `iam_link_auth_user`, `iam_set_account_status`, `iam_permission_options`, `iam_override_set`, `iam_override_list`, `iam_override_end`, `iam_mfa_policy_list`, `iam_mfa_policy_set`, `iam_mfa_policy_gaps`, `iam_can_provision`, `auth_login_record`, `auth_logout_record`, `auth_failure_record`, `mfa_sync`, `mfa_recovery_generate`, `mfa_recovery_status`, `mfa_recovery_use` | `/admin/users`, `/audit` | IAM, AUDIT | Complete |
| 16 | EMPLOYEE HR PROFILE, QUALIFICATION, EXPERIENCE AND SECURE EVIDENCE MODULE | `qualification_level`, `study_mode`, `education_institution_type`, `awarding_body_type`, `education_institution`, `awarding_body`, `previous_organization_type`, `previous_organization`, `employee_qualification`, `employee_previous_employment`, `employee_bank_account`, `employee_pan`, `employee_aadhaar`, `employee_document_category`, `employee_document`, `employee_document_access_rule`, `employee_sensitive_access_audit` [17] | `emp_pan_save`, `emp_aadhaar_save`, `emp_bank_save`, `emp_sensitive_list`, `emp_sensitive_reveal`, `emp_sensitive_review`, `emp_sensitive_delete`, `employee_document_register`, `employee_document_list`, `employee_document_review`, `employee_document_delete`, `employee_document_download_info`, `emp_doc_rule_set`, `emp_doc_rule_list`, `emp_doc_rule_end` | `/my-hr`, [`/employees/[id]/hr`] | EMPLOYEE | Complete |
| 17 | STUDENT FEES AND FINANCIAL MANAGEMENT MODULE | `fee_category`, `financial_ledger_account`, `fee_type`, `fee_structure`, `late_fee_rule`, `late_fee_slab`, `fee_structure_item`, `student_financial_account`, `student_fee_assessment`, `student_fee_assessment_item`, `fee_charge_source`, `concession_type`, `student_fee_concession`, `scholarship_scheme`, `student_scholarship`, `student_sponsorship`, `fee_assessment_benefit`, `installment_plan`, `student_installment_schedule`, `payment_mode`, `payment_transaction`, `admission_payment`, `payment_allocation`, `fee_receipt`, `fee_adjustment`, `refund_request`, `fee_refund`, `student_fee_penalty`, `service_fee_request`, `student_financial_hold`, `fee_activity_audit` [31] | `fin_open_account`, `fin_accounts`, `fin_account_info`, `fin_account_extras`, `fin_record_payment`, `fin_allocate_payment`, `fin_issue_receipt`, `fin_receipt_get`, `fin_payment_receipts`, `fin_cancel_receipt`, `fin_create_fee_assessment`, `fin_structure_save`, `fin_structure_submit`, `fin_structure_decide`, `fin_structure_new_version`, `fin_hold_place`, `fin_hold_release`, `fin_holds`, `fin_request_refund`, `fin_decide_refund`, `fin_process_refund`, `fin_adjustment_create`, `fin_adjustment_decide`, `fin_benefit_create`, `fin_benefit_apply`, `fin_benefit_decide`, `fin_instalment_apply`, `fin_instalment_refresh`, `fin_instalment_cancel`, `fin_late_fee_suggest`, `fin_penalty_assess`, `fin_penalty_waive`, `fin_academic_years` | `/finance`, [`/finance/account/[id]`, `/finance/receipt/[id]`, `/finance/structures`] | FEES | Complete |
| 17A | ENFORCEMENT TRIGGERS FOR CROSS-ROW / CROSS-TABLE RULES | — (no tables; 140 public triggers) | — | — | — | Infrastructure |
| 18 | PERFORMANCE INDEXES | — (no tables; indexes only) | — | — | — | Infrastructure |
| 18 | EXTEND EXISTING FILE STORAGE METADATA | — (no tables; `ALTER` on `file_object`) | — | — | — | Infrastructure |
| 19 | STAFF PROFILE REFERENCE / MASTER DATA | `publication_type`, `journal_type`, `indexing_agency`, `metric_type`, `organization_type`, `external_organization`, `external_organization_type`, `organizer`, `publisher`, `funding_type`, `funding_agency`, `activity_type`, `participation_level`, `role_type`, `research_status`, `event_mode`, `evidence_type`, `verification_status`, `approval_status`, `training_program_type`, `conference_contribution_type`, `industry_sector`, `cocurricular_category`, `extracurricular_category`, `award_category`, `membership_type`, `professional_contribution_type`, `confidentiality_level` [28] | `staff_lookup_options`, `staff_lookup_add`, `staff_lookup_schema`, `staff_detail_schema` | `/staff-profile` | STAFF_PROFILE | Complete |
| 20 | STAFF ACTIVITY SUPERTYPE | `staff_activity`, `staff_activity_contributor` [2] | `staff_activity_save`, `staff_activity_submit`, `staff_activity_list`, `staff_activity_get`, `staff_activity_review`, `staff_activity_delete`, `staff_activity_report`, `staff_contributor_add`, `staff_contributor_remove` | `/staff-profile/activity` | STAFF_PROFILE | Complete |
| 21 | JOURNALS AND JOURNAL PUBLICATIONS | `journal`, `journal_publication`, `journal_publication_indexing`, `journal_metric` [4] | `staff_indexing_list`, `staff_indexing_save`, `staff_indexing_delete` | `/staff-profile/publication` | STAFF_PROFILE | Complete |
| 22 | CONFERENCES, PUBLICATIONS AND PRESENTATIONS | `conference_event`, `conference_activity`, `conference_activity_indexing` [3] | `staff_indexing_list`, `staff_indexing_save`, `staff_indexing_delete` | `/staff-profile/conference` | STAFF_PROFILE | Complete |
| 23 | WORKSHOP / FDP / STTP / TRAINING / CERTIFICATION | `professional_development_activity` [1] | `staff_activity_save`, `staff_activity_submit`, `staff_activity_review` | `/staff-profile/development` | STAFF_PROFILE | Complete |
| 24 | INDUSTRY / FACULTY INTERNSHIP | `faculty_internship` [1] | `staff_activity_save`, `staff_activity_submit`, `staff_activity_review` | `/staff-profile/internship` | STAFF_PROFILE | Complete |
| 25 | RESEARCH PROPOSALS | `research_proposal` [1] | `staff_activity_save`, `staff_activity_submit`, `staff_activity_review` | `/staff-profile/research` | STAFF_PROFILE | Complete |
| 26 | FUNDED RESEARCH PROJECTS | `funded_research_project`, `research_project_financial_utilization` [2] | `staff_activity_save`, `staff_activity_submit`, `staff_activity_review` | `/staff-profile/funded-research` | STAFF_PROFILE | Complete |
| 27 | CONSULTANCY / INDUSTRY-SPONSORED PROJECT | `consultancy_project` [1] | `staff_activity_save`, `staff_activity_submit`, `staff_activity_review` | `/staff-profile/consultancy` | STAFF_PROFILE | Complete |
| 28 | CO-CURRICULAR ACTIVITIES | `cocurricular_activity` [1] | `staff_activity_save`, `staff_activity_submit`, `staff_activity_review` | `/staff-profile/co-curricular` | STAFF_PROFILE | Complete |
| 29 | EXTRA-CURRICULAR ACTIVITIES | `extracurricular_activity` [1] | `staff_activity_save`, `staff_activity_submit`, `staff_activity_review` | `/staff-profile/extra-curricular` | STAFF_PROFILE | Complete |
| 30 | AWARDS, HONOURS AND RECOGNITIONS | `staff_award` [1] | `staff_activity_save`, `staff_activity_submit`, `staff_activity_review` | `/staff-profile/award` | STAFF_PROFILE | Complete |
| 31 | PROFESSIONAL MEMBERSHIPS AND ACADEMIC BODIES | `staff_professional_membership` [1] | `staff_activity_save`, `staff_activity_submit`, `staff_activity_review` | `/staff-profile/membership` | STAFF_PROFILE | Complete |
| 32 | ACADEMIC AND PROFESSIONAL CONTRIBUTIONS | `staff_professional_contribution`, `research_supervision` [2] | `staff_activity_save`, `staff_activity_submit`, `staff_activity_review` | `/staff-profile/contribution` | STAFF_PROFILE | Complete |
| 33 | CENTRALIZED EVIDENCE / DOCUMENT MANAGEMENT | `evidence_document`, `evidence_document_version`, `evidence_tag`, `evidence_document_tag`, `evidence_document_audit` [5] | `staff_evidence_add`, `staff_evidence_replace`, `staff_evidence_delete`, `staff_evidence_download_info` | `/staff-profile/evidence` | STAFF_PROFILE | Complete |
| 34 | DOCUMENT/EVIDENCE REQUIREMENT CONFIGURATION | `activity_evidence_requirement` [1] | `staff_activity_save`, `staff_activity_submit`, `staff_activity_review` | `/staff-profile/evidence-requirements` | STAFF_PROFILE | Complete |
| 35 | SEED REFERENCE DATA | — (no tables; seed rows in the reference tables) | — | — | — | Infrastructure |
| 36 | RBAC REGISTRATION FOR STAFF PROFILE AND EVIDENCE | — (no tables; `access_module` / `permission` / `role_permission` rows) | — | — | STAFF_PROFILE | Infrastructure |
| 37 | REPORTING / SEARCH VIEWS | — (none; this module is functions only) | `global_search`, `dash_applications`, `dash_employees`, `dash_enrolments`, `dash_fee_collection`, `dash_fee_outstanding`, `dash_registrations`, `dash_sessions`, `dash_term_results`, `my_dashboard` | — (no dedicated route) | REPORTING | **Gap** |
| 38 | PERFORMANCE INDEXES | — (no tables; indexes only) | — | — | — | Infrastructure |
| 39 | DATA-INTEGRITY NOTES ENFORCED AT APPLICATION/SERVICE LAYER | — (no tables; rules enforced outside the database) | — | — | — | Infrastructure |
| 40 | STUDENT ACTIVITY & EVIDENCE MODULE | `student_activity_type`, `student_activity`, `student_activity_team_member`, `student_activity_evidence`, `student_activity_evidence_version`, `student_activity_evidence_audit`, `student_activity_evidence_requirement` [7] | `student_activity_save`, `student_activity_submit`, `student_activity_list`, `student_activity_get`, `student_activity_review`, `student_activity_delete`, `student_activity_report`, `student_activity_team_add`, `student_activity_team_remove`, `student_activity_evidence_add`, `student_activity_evidence_replace`, `student_activity_evidence_delete`, `student_activity_evidence_download_info` | `/activities` | STUDENT | Complete |

**Table count check:** the bracketed counts above sum to 213, which is the number of
base tables in the `public` schema on the live database. Every table has RLS enabled
and none has RLS disabled.

## Navigation rows

One row per `NAV_GROUPS` entry in `src/lib/nav.ts`. The order is locked by
`tests/unit/nav-connectivity.test.ts`; see [NAVIGATION.md](NAVIGATION.md) for the
full visibility rules.

| # | Group id | Label | Module(s) | Route(s) | Visibility rule | Enforcement |
|---|---|---|---|---|---|---|
| 1 | `overview` | Overview | — | `/dashboard` | ungated (any signed-in, provisioned user) | `my_dashboard` / `dash_*` |
| 2 | `reference` | 1 · Common reference | IAM | `/admin/reference` | `readable_modules` contains `IAM` | 25 tables via RLS; 16 RPCs check `IAM.*` |
| 3 | `institution` | 2 · Institution structure | INSTITUTION | `/structure` | `readable_modules` contains `INSTITUTION` | 7 tables via RLS; 2 RPCs check `INSTITUTION.*` |
| 4 | `calendar` | 3 · Academic calendar | ACADEMIC_CALENDAR | `/calendar` | `readable_modules` contains `ACADEMIC_CALENDAR` | 4 tables via RLS; 0 RPCs |
| 5 | `curriculum` | 4 · Curriculum & courses | CURRICULUM | `/curriculum`, `/courses` | `readable_modules` contains `CURRICULUM` | 5 tables via RLS; 0 RPCs |
| 6 | `people` | 5 · Students & staff | STUDENT, EMPLOYEE | `/students`, `/employees` | `readable_modules` contains `STUDENT` / `EMPLOYEE` | 13 + 26 tables via RLS; 16 + 6 RPCs |
| 7 | `admission` | 6 · Admissions | ADMISSION | `/admissions` | `readable_modules` contains `ADMISSION` | 3 tables via RLS; 3 RPCs |
| 8 | `registration` | 7 · Registration | REGISTRATION | `/registration` | `readable_modules` contains `REGISTRATION` | 6 tables via RLS; 5 RPCs |
| 9 | `teaching` | 8 · Teaching & timetable | TIMETABLE | `/timetable` | `readable_modules` contains `TIMETABLE` | 1 table via RLS; 3 RPCs |
| 10 | `attendance` | 9 · Attendance | ATTENDANCE | `/attendance` | `readable_modules` contains `ATTENDANCE` | 4 tables via RLS; 2 RPCs |
| 11 | `assessment` | 10 · Assessment & results | ASSESSMENT, RESULT | `/assessment`, `/results`, `/my-results` | `/assessment` needs `ASSESSMENT` **or** `RESULT`; `/results` needs `RESULT`; `/my-results` is `studentOnly` | 3 + 4 tables via RLS; 4 + 7 RPCs |
| 12 | `feedback` | 11 · Feedback | FEEDBACK | `/feedback` | `readable_modules` contains `FEEDBACK` | 8 tables via RLS; 2 RPCs |
| 13 | `support` | 12 · Mentoring & grievance | MENTORING, GRIEVANCE | `/mentoring`, `/grievances` | `/mentoring` needs `MENTORING`; `/grievances` needs `GRIEVANCE` **or** a linked student (`alsoStudent`) | 1 + 3 tables via RLS; 7 + 3 RPCs |
| 14 | `documents` | 13 · Documents & certificates | DOCUMENT | `/certificates`, `/requests`, `/my-documents` | `/certificates` and `/requests` need `DOCUMENT` **or** a linked student (`alsoStudent`); `/my-documents` is `studentOnly` | 5 tables via RLS; 17 RPCs |
| 15 | `communication` | 14 · Communication | — | `/announcements` | ungated (intentional) | `announcements_feed` and friends |
| 16 | `iam` | 15 · Access & audit | IAM, AUDIT | `/admin/users`, `/audit` | `/admin/users` needs `IAM`; `/audit` needs `AUDIT` | 25 + 0 tables via RLS; 16 + 4 RPCs |
| 17 | `hr` | 16 · Employee HR | — | `/my-hr` | `employeeOnly` (linked employee record) | `emp_*` / `employee_document_*` RPCs |
| 18 | `finance` | 17 · Fees & finance | FEES | `/finance` | `readable_modules` contains `FEES` | 23 tables via RLS; 7 RPCs |
| 19 | `staff` | 19 · Staff profile & research | STAFF_PROFILE | `/staff-profile` + 15 sub-module children (modules 20–34) | `readable_modules` contains `STAFF_PROFILE` | 55 tables via RLS; 20 RPCs |
| 20 | `activities` | 40 · Student activities | STUDENT | `/activities` | `readable_modules` contains `STUDENT` **or** a linked student (`alsoStudent`) | 13 tables via RLS; 16 RPCs |
| 21 | `account` | Account | — | `/settings` | ungated | own-account RPCs |

## Access module catalogue

The 22 `access_module` rows on the live database. `display_order` is the value the
seed uses; `FEES` (160) and `STAFF_PROFILE` (170) were added later and therefore
sort after the original twenty.

| `module_code` | `module_name` | `display_order` | Nav group |
|---|---|---|---|
| IAM | Identity and Access Management | 1 | `reference`, `iam` |
| INSTITUTION | Institution Structure | 2 | `institution` |
| ACADEMIC_CALENDAR | Academic Calendar | 3 | `calendar` |
| CURRICULUM | Curriculum and Course Catalog | 4 | `curriculum` |
| STUDENT | Student Records | 5 | `people`, `activities` |
| EMPLOYEE | Employee Records | 6 | `people` |
| ADMISSION | Admissions | 7 | `admission` |
| REGISTRATION | Registration and Enrolment | 8 | `registration` |
| TEACHING | Course Offering and Teaching | 9 | — (allowlisted; no screen of its own) |
| TIMETABLE | Timetable | 10 | `teaching` |
| ATTENDANCE | Attendance | 11 | `attendance` |
| ASSESSMENT | Continuous Assessment | 12 | `assessment` |
| RESULT | Examination and Results | 13 | `assessment` |
| FEEDBACK | Feedback | 14 | `feedback` |
| MENTORING | Mentoring and Counselling | 15 | `support` |
| GRIEVANCE | Grievance | 16 | `support` |
| DOCUMENT | Documents and Certificates | 17 | `documents` |
| COMMUNICATION | Announcements and Notifications | 18 | — (allowlisted; the feed is ungated) |
| REPORTING | Reports and Analytics | 19 | — (allowlisted; no screen yet) |
| AUDIT | Audit and Compliance | 20 | `iam` |
| FEES | Fees and Financial Management | 160 | `finance` |
| STAFF_PROFILE | Staff Academic and Professional Profile | 170 | `staff` |

## Open gaps

These are the facts that do not line up. They are stated here rather than hidden.
The register is kept whole: gaps that have since been closed are marked
**Resolved** and keep their original `G-n` number, so the history stays readable.

| # | Gap | Evidence | Effect | State |
|---|---|---|---|---|
| G-1 | `REPORTING` has 11 permissions but **no RLS policy and no function checks them**. | `tools/validate/nav_rbac_connectivity.py` reports `module REPORTING has permissions but no RLS policy and no function checks them`. | The module is declared but unenforced. `global_search` is `LANGUAGE sql, STABLE` (not `SECURITY DEFINER`) and checks no permission code. | Open |
| G-2 | `/staff-profile` had no `src/app/(app)/staff-profile/page.tsx`. | `src/app/(app)/staff-profile/page.tsx` now exists and calls `staff_activity_list`, `staff_activity_report` and `staff_detail_schema` through the shared screen `src/features/staff-profile/staff-profile-screen.tsx`. | The `staff` nav group no longer renders a dead link. Modules 19–34 are reachable from the UI; modules 20–34 each have their own address under `/staff-profile`. | **Resolved** |
| G-3 | `/activities` had no `src/app/(app)/activities/page.tsx`. | `src/app/(app)/activities/page.tsx` now exists (159 lines) and calls `student_activity_list`, `student_activity_report` and `student_activity_get`. | The `activities` nav group no longer renders a dead link. Module 40 is reachable from the UI. | **Resolved** |
| G-4 | `TEACHING` and `COMMUNICATION` are seeded `access_module` codes that no nav item names. | `tests/unit/nav-connectivity.test.ts` allowlists exactly `TEACHING`, `REPORTING`, `COMMUNICATION`. | Intentional and asserted, not an oversight. | By design |
| G-5 | `docs/ROLE_PERMISSION_MATRIX.md` is generated by `tools/validate/role_matrix.mjs`, which was **not present** in the tree. | `tools/validate/role_matrix.mjs` now exists (15,557 bytes; restored 23:48:38, reworked 00:11:14 to read the live project with `--source auto|live|rebuilt`). `node tools/validate/role_matrix.mjs --check` exits 0 with `OK - docs\ROLE_PERMISSION_MATRIX.md is up to date (source: live)`. | `npm run docs:roles` can regenerate the matrix, and the recovered file is byte-identical to what the generator produces from the live database. | **Resolved** |
| G-6 | `npm run docs:schema` points at `tools/validate/schema_doc.mjs`, which was **not present**. | `tools/validate/schema_doc.mjs` now exists (29,642 bytes, written 00:22:20) and renders `docs/SCHEMA.md` and `docs/SCHEMA_RECONCILIATION.md` from the **live** catalogue. `node tools/validate/schema_doc.mjs --check` exits 0 with both documents up to date. | `npm run docs:schema` works, and `--check` proves the two documents are in step with the database. | **Resolved** |
| G-7 | `npm run migrate:catalogue` pointed at `tools/validate/catalogue.mjs` and `tools/compare_catalogue.py`; neither was present. | Both now exist (`catalogue.mjs` 27,874 bytes, 00:37:22; `compare_catalogue.py` 19,149 bytes, 00:30:12). `python tools/compare_catalogue.py` exits 0 with `OK - the live catalogue matches the expected catalogue`. | The comparison can be re-run, and it is clean: 0 differences in counts, per-schema counts and the 42 seeded row counts, and 0 differences in tables (222), columns (2140), functions (420), policies (594), triggers (140), grants (6223) and sequences (199). | **Resolved** |
| G-8 | `npm run migrate:build` pointed at `tools/translate.py`, which was **not present**. `tools/build_migrations.py` was present. | `tools/translate.py` was restored at 23:54:54 and `npm run migrate:build` was run at 23:56:38, regenerating `supabase/migrations/001`–`063` from the MySQL source. | The MySQL → PostgreSQL translation step runs. The migrations on disk are now that translation, not the earlier catalogue regeneration. | **Resolved** |
| G-9 | The regenerated migration set did **not** reproduce the live function ACLs. | The live database has `PUBLIC EXECUTE` revoked on **418 of the 420** functions in `public` + `sims_private` (352 of them `SECURITY DEFINER`). The 23:49:34 regeneration contained **zero** `REVOKE` statements, so a PGlite rebuild left `PUBLIC` able to execute every function. | **Fixed at 23:56:38.** `supabase/migrations/021_finance_rpcs.sql` now carries 418 `REVOKE` statements and `tools/compare_catalogue.py` reports 0 grant differences. | **Resolved** |
| G-10 | One `CHECK` constraint differed in its validation state. | `public.research_project_financial_utilization.chk_project_utilization_balance` is `NOT VALID` on the live database (`convalidated = false`) and was validated in the rebuild. | **Fixed at 23:56:38.** The constraint is now emitted with `NOT VALID`; `tools/compare_catalogue.py` reports 0 table differences. | **Resolved** |
| G-11 | The live project grants `authenticated` **column level** SELECT, not relation level SELECT. The catalogue and the migration generator captured neither, so the rebuilt database refused **every** direct table read. | On the live database `has_table_privilege('authenticated', 'public.student', 'SELECT')` is **false**, but `has_column_privilege('authenticated', 'public.student', 'student_id', 'SELECT')` is **true**. `pg_attribute.attacl` carries **2086** column grants for `authenticated` across **212 of the 213** public tables. The migration set contained **0** `GRANT SELECT (col, ...) ON TABLE ...` statements. | Every direct table read failed with `permission denied for table X`; all 594 RLS policies were unreachable through the Data API. | **Resolved.** `tools/dump_catalogue.py`, `tools/validate/catalogue.mjs` and `tools/validate/pg_catalogue.mjs` now capture `attacl`; `tools/build_migrations.py` emits 212 column grants into migration 021; `tools/build_migrations.py` refuses to build from a catalogue without column privileges. `tests/db/rls.test.ts` asserts the grant shape and the `SELECT *` refusal. |
| G-12 | `my_context().permissions` drops SELF scoped grants while `readable_modules` keeps them. | `student1` comes back with **10 readable modules** and an **empty permission list** (`tests/db/rls.test.ts`, "returns a my_context() with an exact key set"). | The two fields disagree about the same permission set. A client that gates on `permissions` sees nothing; one that gates on `readable_modules` sees ten. | Open - pre-existing in the live database |
| G-13 | Six `sims_private` tables have no RLS enabled. | `mfa_recovery_attempt`, `mfa_recovery_code`, `mfa_required_role`, `notification_dismissal`, `receipt_counter`, `student_service_request` (9 tables in the schema, 3 with RLS). Reproduced identically in the live catalogue dump. | The schema is not exposed through the Data API (`api.schemas = ["public", "graphql_public"]`), so the exposure is limited, but the tables are not deny-by-default. | Open - pre-existing in the live database |
| G-14 | The RPC error contract is inconsistent. | `audit_get`, `ref_schema` and `ref_rows` raise `Not authorised (...)`; `audit_list`, `audit_modules` and `ref_list` silently return `[]` for the same unauthorised caller (`tests/db/rls.test.ts`, "authorises the SECURITY DEFINER RPCs inside the function"). | A caller cannot distinguish "not allowed" from "no data". | Open - pre-existing in the live database |

## Sources

| Fact | Source |
|---|---|
| Module numbers, names, table membership | `SIMS-DatabaseWithoutLessonPlan.sql` section headers, cross-checked against `tools/rls/table_module.json` (213 entries). |
| Live table / function / policy / permission counts | Read-only queries against the live Supabase project `khqqfgqvwdxlqkncwtmh`. |
| `access_module`, `access_action`, `access_resource`, `permission` rows | Same. |
| Nav groups, routes, visibility rules | `src/lib/nav.ts`. |
| Route existence | `src/app/(app)/**/page.tsx` on disk. |
| Enforcement counts per module | `tools/validate/nav_rbac_connectivity.py` (read-only) against the live database. |
| Group order lock, seeded-code allowlist | `tests/unit/nav-connectivity.test.ts`. |
| Migration set vs. live catalogue | `python tools/compare_catalogue.py` (offline: diffs `tools/catalogue/live_catalogue.json` against `tools/catalogue/expected_catalogue.json`). |
| Matrix generator agreement | `node tools/validate/role_matrix.mjs --check` (read-only; reads the live project by default, writes nothing). |
