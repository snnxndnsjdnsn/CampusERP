# Module documentation

One section per application area: what it does, where it lives, the database objects behind it and what is not covered. Exact permissions and parameters would be in `API_DOCUMENTATION.md` and rules the source did not state in `KNOWN_ISSUES.md` — **neither file is present in this tree**. The per-role grants are in [ROLE_PERMISSION_MATRIX.md](ROLE_PERMISSION_MATRIX.md), the security model in [RLS_SECURITY_MODEL.md](RLS_SECURITY_MODEL.md), and status per requirement in [RTM.md](RTM.md).

> **Two module numberings.** The tables further down this document use a *screen
> grouping* numbered 1–29 that predates the rebuild. The database's own numbering
> is the numbered section headers of `SIMS-DatabaseWithoutLessonPlan.sql` (1–17,
> 17A, 18–40) and is authoritative. The two are reconciled in
> [Schema modules vs. screen groups](#schema-modules-vs-screen-groups) below, and
> the full schema-numbered matrix lives in [RTM.md](RTM.md).


## How every module is built
- **Screens** are server components that load data (`src/features/<module>-data.ts`) plus client forms (`<module>-forms.tsx`) validated with Zod (`src/lib/<module>-validation.ts`).
- **Writes** that matter go through one `SECURITY DEFINER` RPC = one transaction, which authorises the caller at the row's scope, validates, writes and audits. Where a module has no RPC the table's own row level security policy decides.
- **Authorisation** is `sims_private.can_global / can_institution / can_department / can_programme / can_student / can_employee` against permission codes such as `STUDENT.ALL.READ`. Owners (a student, an employee) act on their own records by identity because the seed gives them SELF-scope grants only.
- **Tests**: a database test per migration on embedded PostgreSQL, unit tests for validation and for "drift" between application tables and the migrations, Playwright for route protection.

## Platform and access
| Area | Screens | Database | Notes |
|---|---|---|---|
| Identity and access (module 2) | `/login`, `/forgot-password`, `/reset-password`, `/mfa`, `/settings`, `/admin/users`, `/admin/users/[id]`, `/no-access` | M006, M017-M020, M041, M045 | Users, role assignments with safeguards, TOTP two-step verification enforced by the database, own contact details |
| Reference data (module 1) | `/admin/reference`, `/admin/reference/[table]` | M001, M011, M046 | 32 maintainable lists |
| Audit and compliance (module 9) | `/audit`, `/audit/[id]`, `/audit/logins` | M006, M022, M041, M045 | Row-level audit triggers, manual audit rows for RPC actions, sign-in log |
| Notifications and search | header bell, `/notifications`, `/search` | M045 | Computed from live data under the caller's RLS |

## Institution and academics
| Module | Screens | Database | Notes |
|---|---|---|---|
| University and institution (3) | `/structure` | M025 | Tree of university, institution, campus, department, programme |
| Academic calendar (4) | `/calendar` | M024 | Years, terms, semesters |
| Curriculum and courses (5) | `/curriculum`, `/courses` | M026 | Schemes, courses, prerequisites |
| Admissions (11) | `/admissions` | M027 | Applications through to admit-to-student |
| Student registration (12) | `/registration` | M028-M030 | Term offerings, sections, course registration with capacity |
| Attendance (13), Timetable (14) | `/attendance`, `/timetable` | M031, M035 | Rosters, sessions, marking, corrections, clash-guarded timetable |
| Assessment and results (15) | `/assessment`, `/results/grades`, `/my-results` | M032, M033 | Marks, SGPA/CGPA, publication |
| Feedback (16), Mentoring (17), Grievance (20) | `/feedback`, `/mentoring`, `/grievances` | M037, M038, M039 | Anonymous feedback, confidential counselling, grievance workflow |

## People
| Module | Screens | Database | Notes |
|---|---|---|---|
| Students (6) | `/students`, `/students/[id]/records`, `/students/[id]/documents` | M022, M042, M046 | Registration, edit, status, sub-records, documents |
| Employees (7) | `/employees`, `/employees/[id]/records`, `/employees/[id]/hr`, `/my-hr` | M023, M046, M054, M063 | Registration, assignments, qualifications, previous employment; PAN, Aadhaar and bank accounts (encrypted, masked, reveal logged) and HR documents; employees see and correct their own until HR verifies |
| Student documents (8) | `/my-documents`, `/certificates` | M042, M060 | Private bucket, signed URLs, verification; certificate requests with approval and an issued PDF |
| Student activities and evidence (23) | `/activities` | M043 | Draft, evidence with versions, verification, approval, team |
| Staff profile and research (22) | `/staff-profile` | M044, M055 | 12 kinds of record through a catalogue-driven form, contributors, evidence; research supervision, project utilisation and journal / conference indexing on the record; journal metrics in the reference data |

## Communication and finance
| Module | Screens | Database | Notes |
|---|---|---|---|
| Communication (10) | `/announcements`, `/announcements/manage` | M040, M059 | Audiences, approval workflow, feed |
| Student finance (21) | `/finance`, `/finance/account/[id]`, `/finance/receipt/[id]` | M008, M014, M021, M034, M047, M052, M053, M061, M062, M063 | Assessments, payments, allocations, refunds, receipts, holds. Concessions, scholarships, sponsorships, adjustments, instalments, late fees and penalties (M052, M053); students see their own account; fee structures are drafted, approved and versioned on `/finance/structures`; holds block registration, results and certificates. |

## Dashboards
`/dashboard` shows the charts for the modules the caller can read (M036) plus personal cards (M048): a student's classes today, attendance per course and results; an employee's upcoming sessions and unmarked ones.

## Cross-cutting mechanisms worth knowing
- **Generic catalogue-driven forms** (`sims_private.describe_columns`, `form_columns`, `write_row`, `write_detail`): used for staff record details (M044), student and employee sub-records and reference data (M046). Only whitelisted tables are reachable, only catalogue columns can be written, keys, audit columns and user references are rejected, and constraint violations become readable messages.
- **Workflow lifecycle** (DRAFT -> SUBMITTED -> UNDER_REVIEW -> APPROVED / REJECTED, NEEDS_CORRECTION back to DRAFT, nobody reviews their own record): student activities (M043) and staff records (M044), sharing `workflow-actions.tsx` and `evidence-panel.tsx`.
- **Private Storage**: one bucket, `student/<id>/...` and `employee/<id>/...` prefixes, 60-second signed URLs after an RPC has authorised and logged the download. The rules live in `can_use_student_doc_path` and `can_use_employee_doc_path`; `STORAGE_DOCUMENTATION.md` is **not present in this tree**.

## Access control
Every default grant is listed in [ROLE_PERMISSION_MATRIX.md](ROLE_PERMISSION_MATRIX.md) (generated). Per-user exceptions are permission overrides on `/admin/users/[id]` (migration 057). Recovery codes for two-step verification are on `/settings` (migration 056).

## Student services
`/requests` (migration 063): hall ticket per term, hostel check-out and graduation requests, approved by `DOCUMENT.ALL.APPROVE`, blocked by the matching fee hold. `/certificates` (migration 060): certificate requests.

## The six schema screens (modules 18, 35, 36, 37, 38 and 39)

Six modules of the MySQL source describe the database itself rather than a business area. They have no table a user would "work in", but each one has real objects in the database, so each one now has a screen of its own and its own number in the sidebar.

| Module | Address | What it shows | Gate | Live numbers |
|---|---|---|---|---|
| 18 · Performance indexes & storage | `/schema/18` | The index catalogue of the public schema, and the file-storage metadata of `file_object` | `IAM` | 572 public indexes; 20 columns of `file_object` |
| 35 · Seed reference data | `/schema/35` | The seeded lookup vocabulary - publication types, journal types, indexing agencies, metric types, funding types, activity types and the rest | `IAM` **or** `STAFF_PROFILE` | 27 seeded lookup tables, all 27 readable by the administrator |
| 36 · Staff profile RBAC registration | `/schema/36` | The `STAFF_PROFILE` access module, its resources, its permissions and the roles that hold them | `IAM` | 1 access module, 5 access resources, 44 permissions, 144 role grants |
| 37 · Reporting & search views | `/reporting` | The ten reporting and search views, the live `global_search` and the two activity reports | `REPORTING` | 10 views, all 10 readable |
| 38 · Staff profile performance indexes | `/schema/38` | The index catalogue restricted to the staff-profile tables | `STAFF_PROFILE` **or** `IAM` | 146 indexes on the 55 tables that carry a `STAFF_PROFILE.*` policy; 146 of 146 readable |
| 39 · Data-integrity notes | `/schema/39` | The fourteen integrity rules the service layer enforces | `IAM` **or** `AUDIT` | 14 notes, transcribed from section 39 of `SIMS-DatabaseWithoutLessonPlan.sql` |

Modules 18, 35, 36, 38 and 39 are served by one dynamic route, `src/app/(app)/schema/[module]/page.tsx`; module 37 has a screen of its own at `src/app/(app)/reporting/page.tsx`, because it is a working screen rather than a catalogue.

**The gates are the point.** These six groups are the first ones whose visibility is not simply "the module that owns the screen". A faculty member sees 35, 37 and 38 but not 18, 36 or 39; a student sees none of them. The super administrator sees all six.

Each screen also carries a **page-level gate**. If the caller cannot read the module the sidebar gates on, the page renders "This screen is not open to your account" instead of the data. The database remains the security boundary - the RPCs return HTTP 403 / SQLSTATE 42501 - so the page gate is the door, not the lock.

### The index catalogue

`pg_indexes` lives in `pg_catalog`, so PostgREST cannot expose it and the browser cannot read it. Migration `065_schema_indexes.sql` adds one read-only function that is the only door to it:

```sql
public.schema_indexes(p_scope text DEFAULT NULL)
```

`p_scope` is `'all'` (every index in the public schema, needs `IAM.ALL.READ`) or `'staff'` (only the tables that carry a `STAFF_PROFILE.*` row-level-security policy, needs `STAFF_PROFILE.ALL.READ`). The function is `SECURITY DEFINER` because `pg_indexes` is not readable by the `authenticated` role; the permission check inside it is the gate. An unknown scope raises SQLSTATE 22023; an unauthorised caller gets SQLSTATE 42501.

---

# Schema modules vs. screen groups

The screen groups used above are a *presentation* grouping. The schema's numbered
sections are the *data* grouping. They do not line up one-to-one, and they are not
meant to:

| Screen group (this document) | Schema modules | Nav group |
|---|---|---|
| Reference data (1) | 1 | `reference` |
| Identity and access (2) | 15 | `iam` |
| University and institution (3) | 2 | `institution` |
| Academic calendar (4) | 3 | `calendar` |
| Curriculum and courses (5) | 4 | `curriculum` |
| Students (6) | 5, 40 | `people`, `activities` |
| Employees (7) | 5, 16 | `people`, `hr` |
| Student registration (12) | 7 | `registration` |
| Attendance (13), Timetable (14) | 9, 8 | `attendance`, `teaching` |
| Assessment and results (15) | 10 | `assessment` |
| Feedback (16), Mentoring (17), Grievance (20) | 11, 12 | `feedback`, `support` |
| Student documents (8) | 13 | `documents` |
| Student activities and evidence (23) | 40 | `activities` |
| Staff profile and research (22) | 19–34 | `staff` (20–34 are its children) |
| Communication (10) | 14 | `communication` |
| Student finance (21) | 17 | `finance` |
| Audit and compliance (9) | 15 | `iam` |
| Notifications and search (24) | 37 | `reporting` |
| Performance indexes and file storage (25) | 18 | `schema` |
| Seed reference data (26) | 35 | `seed` |
| Staff profile RBAC registration (27) | 36 | `rbac` |
| Staff profile performance indexes (28) | 38 | `staff-index` |
| Data-integrity notes (29) | 39 | `integrity` |

Schema module **17A** owns no tables and no screen: it is the cross-row
enforcement triggers. Modules **18**, **35**, **36**, **38** and **39** own no
tables either, but they have a screen of their own now - the index catalogue,
the seed vocabulary, the RBAC registration, the staff-scope index catalogue and
the integrity notes. Module **37** has a screen at `/reporting`. They are listed
in [RTM.md](RTM.md).

# Module-by-module reference

One row per numbered section of `SIMS-DatabaseWithoutLessonPlan.sql`. The object
lists are the key ones; [RTM.md](RTM.md) has the full table count per module.

| Schema module | Module | What it does | Key tables | Key RPCs | Access module | UI route |
|---|---|---|---|---|---|---|
| 1 | Common reference | The lookup lists every other module joins to: geography, demographics, categories and document types. | `country`, `state`, `gender`, `blood_group`, `religion`, `social_category`, `caste`, `sub_caste`, `admission_category`, `document_type` | `ref_list`, `ref_rows`, `ref_save`, `ref_delete`, `ref_schema` | IAM | `/admin/reference` |
| 2 | University and institution structure | The organisational tree everything else is scoped by: university → institution → campus → department → programme, plus buildings and rooms. | `university`, `institution`, `campus`, `department`, `programme`, `programme_specialization`, `building`, `room` | `institution_create`, `institution_update`, `record_sections`, `section_save`, `section_delete` | INSTITUTION | `/structure` |
| 3 | Academic calendar | Years, terms, semesters and the time slots that the timetable is built on. | `academic_year`, `academic_term`, `semester`, `time_slot` | — (RLS only) | ACADEMIC_CALENDAR | `/calendar` |
| 4 | Curriculum and course catalog | Schemes, the course catalogue, which courses sit in a scheme, and prerequisites. | `course_category`, `course_catalog`, `curriculum_scheme`, `curriculum_course`, `course_prerequisite` | — (RLS only) | CURRICULUM | `/curriculum`, `/courses` |
| 5 | Student and staff master | The two root entities and their immediate sub-records: a student with addresses, guardians, residence and prior education; an employee with designation, assignment and competencies. | `student`, `student_address`, `student_parent_guardian`, `student_residence`, `student_previous_education`, `student_entrance_exam`, `employee`, `employee_address`, `employee_assignment`, `employee_competency`, `staff_type`, `staff_category`, `employment_source`, `external_agency`, `designation` | `student_register`, `employee_register`, `employee_assign`, `emp_competency_save`, `emp_competency_list`, `emp_competency_delete` | STUDENT, EMPLOYEE | `/students`, `/employees` |
| 6 | Admission and enrolment | An application becomes an applicant, then an admitted student, then a programme enrolment, with the status history kept. | `admission_applicant`, `admission_application`, `student_programme_enrolment`, `enrolment_status_history` | `admission_apply`, `admission_update_applicant`, `admission_update_application`, `admission_set_status`, `admission_admit` | ADMISSION | `/admissions` |
| 7 | Term registration, section and course registration | What is being taught this term: offerings, sections, batches, and which student is registered for which course. | `programme_term_offering`, `class_section`, `class_batch`, `student_term_registration`, `course_offering`, `course_offering_section`, `student_course_registration`, `course_offering_section_student` | `registration_term_info`, `registration_candidates`, `registration_roster`, `offering_generate_courses`, `teaching_populate_roster` | REGISTRATION, TEACHING | `/registration` |
| 8 | Teaching allocation and timetable | Who teaches what, and when and where it happens. | `faculty_course_assignment`, `timetable_session` | `timetable_offerings`, `timetable_offering_info`, `timetable_sections`, `timetable_slots`, `timetable_rooms`, `timetable_entries`, `timetable_assignments`, `timetable_generate_sessions` | TEACHING, TIMETABLE | `/timetable` |
| 9 | Attendance and lesson plan | Sessions, the roster, marking, and the correction request workflow. | `class_session`, `attendance_status`, `student_attendance`, `attendance_correction_request` | `attendance_sheet`, `attendance_mark`, `attendance_summary`, `attendance_request_correction`, `attendance_decide_correction` | ATTENDANCE | `/attendance` |
| 10 | Continuous assessment and result | Assessment components and events, marks, the grade scale and rules, and the course/term results that are computed and published. | `assessment_component`, `assessment_event`, `student_assessment_mark`, `grade_scale`, `grade_rule`, `student_course_result`, `student_term_result` | `assessment_offerings`, `assessment_offering_info`, `assessment_sheet`, `assessment_enter_marks`, `result_compute_term`, `result_record_course`, `result_term_sheet`, `result_course_sheet`, `result_publish_term` | ASSESSMENT, RESULT | `/assessment`, `/results`, `/my-results` |
| 11 | Feedback | Questionnaires, cycles, responses and per-response answers. | `feedback_question_category`, `feedback_question`, `feedback_choice`, `feedback_questionnaire`, `feedback_questionnaire_item`, `feedback_cycle`, `feedback_response`, `feedback_response_item` | `feedback_cycle_offerings`, `feedback_form`, `feedback_my_tasks`, `feedback_submit`, `feedback_results` | FEEDBACK | `/feedback` |
| 12 | Mentoring, counselling and grievance | Mentor assignments and counselling sessions, plus the grievance workflow and its action trail. | `mentor_assignment`, `counselling_session`, `grievance_category`, `grievance`, `grievance_action` | `mentoring_assignments`, `mentoring_assign`, `mentoring_record_session`, `mentoring_sessions`, `mentoring_update_session`, `mentoring_end_assignment`, `grievance_submit`, `grievance_list`, `grievance_detail`, `grievance_act`, `grievance_my`, `grievance_student_respond` | MENTORING, GRIEVANCE | `/mentoring`, `/grievances` |
| 13 | Document, certificate and exit | The file registry, a student's documents, certificate requests and the exit record. | `file_object`, `student_document`, `certificate_type`, `certificate_request`, `student_exit` | `cert_request_create`, `cert_request_list`, `cert_request_decide`, `cert_request_issue`, `cert_request_cancel`, `cert_request_download_info`, `svc_my_terms`, `svc_request_create`, `svc_request_list`, `svc_request_decide`, `svc_request_cancel` | DOCUMENT | `/certificates`, `/requests`, `/my-documents` |
| 14 | Communication | Announcements with their audiences, attachments, and the per-user notification dismissals. | `announcement_type`, `announcement`, `announcement_attachment` | `announcements_feed`, `announcements_manage`, `announcement_save`, `announcement_submit`, `announcement_decide`, `announcement_archive`, `announcement_targets`, `announcement_detail`, `announcement_attachment_register`, `announcement_attachment_list`, `announcement_attachment_remove`, `announcement_attachment_download_info`, `notification_dismiss`, `notification_dismiss_all` | COMMUNICATION | `/announcements` |
| 15 | Identity, access control and audit | Accounts, the role/permission catalogue, assignments, delegations, per-user overrides, MFA state and the audit trail. | `user_account`, `student_user_account`, `employee_user_account`, `access_module`, `access_resource`, `access_action`, `permission`, `role`, `role_permission`, `user_role_assignment`, `user_permission_override`, `role_delegation`, `password_history`, `login_audit`, `activity_audit` | `iam_user_list`, `iam_user_detail`, `iam_roles`, `iam_assign_role`, `iam_revoke_role`, `iam_provision_user`, `iam_link_person`, `iam_link_auth_user`, `iam_set_account_status`, `iam_permission_options`, `iam_override_set`, `iam_override_list`, `iam_override_end`, `iam_mfa_policy_list`, `iam_mfa_policy_set`, `iam_mfa_policy_gaps`, `auth_login_record`, `auth_logout_record`, `auth_failure_record`, `mfa_sync`, `mfa_recovery_generate`, `mfa_recovery_status`, `mfa_recovery_use` | IAM, AUDIT | `/admin/users`, `/audit` |
| 16 | Employee HR, qualification, experience and secure evidence | The employee's own HR record: qualifications, previous employment, and the three high-sensitivity identifiers (PAN, Aadhaar, bank account) with their verification workflow, plus evidence documents with per-document access rules. | `qualification_level`, `study_mode`, `education_institution_type`, `awarding_body_type`, `education_institution`, `awarding_body`, `previous_organization_type`, `previous_organization`, `employee_qualification`, `employee_previous_employment`, `employee_bank_account`, `employee_pan`, `employee_aadhaar`, `employee_document_category`, `employee_document`, `employee_document_access_rule`, `employee_sensitive_access_audit` | `emp_pan_save`, `emp_aadhaar_save`, `emp_bank_save`, `emp_sensitive_list`, `emp_sensitive_reveal`, `emp_sensitive_review`, `emp_sensitive_delete`, `employee_document_register`, `employee_document_list`, `employee_document_review`, `employee_document_delete`, `employee_document_download_info`, `emp_doc_rule_set`, `emp_doc_rule_list`, `emp_doc_rule_end` | EMPLOYEE | `/my-hr`, `/employees/[id]/hr` |
| 17 | Student fees and financial management | The whole money path: fee structures and versions, assessments, payments and allocations, receipts, concessions, scholarships, sponsorships, instalments, late fees, penalties, refunds, adjustments, and the holds that block registration, results and certificates. | `fee_category`, `financial_ledger_account`, `fee_type`, `fee_structure`, `late_fee_rule`, `late_fee_slab`, `fee_structure_item`, `student_financial_account`, `student_fee_assessment`, `student_fee_assessment_item`, `fee_charge_source`, `concession_type`, `student_fee_concession`, `scholarship_scheme`, `student_scholarship`, `student_sponsorship`, `fee_assessment_benefit`, `installment_plan`, `student_installment_schedule`, `payment_mode`, `payment_transaction`, `admission_payment`, `payment_allocation`, `fee_receipt`, `fee_adjustment`, `refund_request`, `fee_refund`, `student_fee_penalty`, `service_fee_request`, `student_financial_hold`, `fee_activity_audit` | `fin_open_account`, `fin_accounts`, `fin_account_info`, `fin_record_payment`, `fin_allocate_payment`, `fin_issue_receipt`, `fin_receipt_get`, `fin_create_fee_assessment`, `fin_structure_save`, `fin_structure_submit`, `fin_structure_decide`, `fin_hold_place`, `fin_hold_release`, `fin_holds`, `fin_request_refund`, `fin_decide_refund`, `fin_process_refund`, `fin_benefit_create`, `fin_benefit_apply`, `fin_instalment_apply`, `fin_penalty_assess`, `fin_late_fee_suggest` | FEES | `/finance` |
| 17A | Enforcement triggers | Cross-row and cross-table rules that no single policy can express. 140 public triggers. | — | — | — | — |
| 18 | Performance indexes | The index catalogue of the live database: 572 indexes in the public schema, read through `public.schema_indexes('all')`. | — | `schema_indexes` | IAM | `/schema/18` |
| 18 | Extend existing file storage metadata | `ALTER` on `file_object` adding `encryption_key_reference`, `virus_scan_status`, `virus_scanned_at` - 20 columns in all, shown beside the index catalogue. | — | — | IAM | `/schema/18` |
| 19 | Staff profile reference / master data | The lookup vocabulary for the whole staff-profile area: publication and journal types, indexing agencies, metric types, funding, roles, statuses, evidence types, activity categories. | `publication_type`, `journal_type`, `indexing_agency`, `metric_type`, `organization_type`, `external_organization`, `organizer`, `publisher`, `funding_type`, `funding_agency`, `activity_type`, `participation_level`, `role_type`, `research_status`, `event_mode`, `evidence_type`, `verification_status`, `approval_status`, `training_program_type`, `conference_contribution_type`, `industry_sector`, `cocurricular_category`, `extracurricular_category`, `award_category`, `membership_type`, `professional_contribution_type`, `confidentiality_level` | `staff_lookup_options`, `staff_lookup_add`, `staff_lookup_schema`, `staff_detail_schema` | STAFF_PROFILE | `/staff-profile` |
| 20 | Staff activity supertype | The one record every staff activity hangs off, with its contributors. | `staff_activity`, `staff_activity_contributor` | `staff_activity_save`, `staff_activity_submit`, `staff_activity_list`, `staff_activity_get`, `staff_activity_review`, `staff_activity_delete`, `staff_activity_report`, `staff_contributor_add`, `staff_contributor_remove` | STAFF_PROFILE | `/staff-profile/activity` |
| 21 | Journals and journal publications | Journal entries, the publications in them, their indexing entries and the journal metrics. | `journal`, `journal_publication`, `journal_publication_indexing`, `journal_metric` | `staff_indexing_list`, `staff_indexing_save`, `staff_indexing_delete` | STAFF_PROFILE | `/staff-profile/publication` |
| 22 | Conferences, publications and presentations | Conference events, the activity that links a staff member to one, and its indexing. | `conference_event`, `conference_activity`, `conference_activity_indexing` | `staff_indexing_list`, `staff_indexing_save`, `staff_indexing_delete` | STAFF_PROFILE | `/staff-profile/conference` |
| 23 | Workshop / FDP / STTP / training / certification | Professional development activities. | `professional_development_activity` | `staff_activity_save`, `staff_activity_submit`, `staff_activity_review` | STAFF_PROFILE | `/staff-profile/development` |
| 24 | Industry / faculty internship | Internship placements. | `faculty_internship` | `staff_activity_save`, `staff_activity_submit`, `staff_activity_review` | STAFF_PROFILE | `/staff-profile/internship` |
| 25 | Research proposals | Proposals, with their own lifecycle. | `research_proposal` | `staff_activity_save`, `staff_activity_submit`, `staff_activity_review` | STAFF_PROFILE | `/staff-profile/research` |
| 26 | Funded research projects | Funded projects and their financial utilisation. | `funded_research_project`, `research_project_financial_utilization` | `staff_activity_save`, `staff_activity_submit`, `staff_activity_review` | STAFF_PROFILE | `/staff-profile/funded-research` |
| 27 | Consultancy / industry-sponsored project | Consultancy engagements. | `consultancy_project` | `staff_activity_save`, `staff_activity_submit`, `staff_activity_review` | STAFF_PROFILE | `/staff-profile/consultancy` |
| 28 | Co-curricular activities | Co-curricular activity records. | `cocurricular_activity` | `staff_activity_save`, `staff_activity_submit`, `staff_activity_review` | STAFF_PROFILE | `/staff-profile/co-curricular` |
| 29 | Extra-curricular activities | Extra-curricular activity records. | `extracurricular_activity` | `staff_activity_save`, `staff_activity_submit`, `staff_activity_review` | STAFF_PROFILE | `/staff-profile/extra-curricular` |
| 30 | Awards, honours and recognitions | Awards and recognitions. | `staff_award` | `staff_activity_save`, `staff_activity_submit`, `staff_activity_review` | STAFF_PROFILE | `/staff-profile/award` |
| 31 | Professional memberships and academic bodies | Memberships of professional bodies. | `staff_professional_membership` | `staff_activity_save`, `staff_activity_submit`, `staff_activity_review` | STAFF_PROFILE | `/staff-profile/membership` |
| 32 | Academic and professional contributions | Contributions, and the supervision of student research. | `staff_professional_contribution`, `research_supervision` | `staff_activity_save`, `staff_activity_submit`, `staff_activity_review` | STAFF_PROFILE | `/staff-profile/contribution` |
| 33 | Centralized evidence / document management | Evidence documents with versions, tags and their own audit trail — shared by every staff activity kind. | `evidence_document`, `evidence_document_version`, `evidence_tag`, `evidence_document_tag`, `evidence_document_audit` | `staff_evidence_add`, `staff_evidence_replace`, `staff_evidence_delete`, `staff_evidence_download_info` | STAFF_PROFILE | `/staff-profile/evidence` |
| 34 | Document/evidence requirement configuration | Which evidence each activity kind requires. | `activity_evidence_requirement` | `staff_activity_save`, `staff_activity_submit`, `staff_activity_review` | STAFF_PROFILE | `/staff-profile/evidence-requirements` |
| 35 | Seed reference data | Seed rows for the lookup tables: 27 seeded lookup tables, all 27 readable by the administrator. | — | — | IAM, STAFF_PROFILE | `/schema/35` |
| 36 | RBAC registration for staff profile and evidence | The `access_module`, `access_resource`, `permission` and `role_permission` rows that make the staff-profile area authorisable: 1 access module, 5 resources, 44 permissions and 144 role grants. | — | — | IAM | `/schema/36` |
| 37 | Reporting / search views | Cross-module search and dashboard aggregates: 10 reporting views, all 10 readable, plus the live `global_search` and the two activity reports. | — | `global_search`, `dash_applications`, `dash_employees`, `dash_enrolments`, `dash_fee_collection`, `dash_fee_outstanding`, `dash_registrations`, `dash_sessions`, `dash_term_results`, `my_dashboard` | REPORTING | `/reporting` |
| 38 | Performance indexes | A second index-only section: the 146 indexes carried by the 55 tables that have a `STAFF_PROFILE.*` row-level security policy. | — | `schema_indexes` | STAFF_PROFILE, IAM | `/schema/38` |
| 39 | Data-integrity notes | Rules the source asks the application or service layer to enforce: the 14 notes transcribed from section 39 of the source. | — | — | IAM, AUDIT | `/schema/39` |
| 40 | Student activity and evidence | The student-side mirror of the staff activity area: activities, teams, evidence with versions and an audit trail, and the evidence requirements per activity type. | `student_activity_type`, `student_activity`, `student_activity_team_member`, `student_activity_evidence`, `student_activity_evidence_version`, `student_activity_evidence_audit`, `student_activity_evidence_requirement` | `student_activity_save`, `student_activity_submit`, `student_activity_list`, `student_activity_get`, `student_activity_review`, `student_activity_delete`, `student_activity_report`, `student_activity_team_add`, `student_activity_team_remove`, `student_activity_evidence_add`, `student_activity_evidence_replace`, `student_activity_evidence_delete`, `student_activity_evidence_download_info` | STUDENT | `/activities` |

# Navigation is owned by `src/lib/nav.ts`

`src/lib/nav.ts` is the **single source of truth** for the sidebar. It holds
`NAV_GROUPS` (27 groups, 35 group routes and 15 staff sub-module children),
the `NavItem` / `NavGroup` types, the visibility helpers `visibleNavGroups()` /
`visibleNav()` and the breadcrumb fallback `NAV_PARENTS`.

Consequences for module work:

- **Group order is not a style choice.** The groups follow the schema's numbered
  module order — `1..19`, then `35..39`, then `40` — with `Overview` and
  `Account` as bookends. `tests/unit/nav-connectivity.test.ts` asserts the exact
  id sequence, so inserting or reordering a group fails the test.
- **A module gets a nav entry only if it has a screen.** Schema module 17A (the
  cross-row enforcement triggers) still has no group of its own. Modules 18, 35,
  36, 37, 38 and 39 have one each now — the six schema screens described
  above.
- **A module with no screen of its own can still be a child.** The research
  sub-modules 20–34 are reached through `/staff-profile`, and each one has its
  own address under it: `/staff-profile/publication`, `/staff-profile/research`,
  `/staff-profile/award` and so on. They are drawn indented under the
  `staff` group. See [NAVIGATION.md](NAVIGATION.md).
- **A new route needs a `page.tsx` first.** The test asserts that every nav href
  resolves to a `page.tsx`, following dynamic segments such as
  `staff-profile/[section]`.
- **Visibility is a convenience, not a gate.** `readable_modules` decides what is
  drawn; RLS and the RPC's own check decide what may be read. See
  [RLS_SECURITY_MODEL.md](RLS_SECURITY_MODEL.md).
- **An `access_module` code that no nav item uses must be allowlisted** in the
  test. The allowlist is `TEACHING`, `COMMUNICATION`. `REPORTING` was on that
  allowlist until module 37 got a screen; it is not any more.

Full rules: [NAVIGATION.md](NAVIGATION.md).

# Where the code lives

| Layer | Location | Rule |
|---|---|---|
| Route | `src/app/(app)/<route>/page.tsx` | Server Component. `requireContext()` first, then `rpcRows` / `rpcJson` / `rpcSafe` from `@/lib/api`. |
| Route (auth) | `src/app/(auth)/<route>/page.tsx` | Login, forgot password, reset password. |
| Feature code | `src/features/<area>/` | Data loaders (`data.ts`), client components (`*-client.tsx`, `*-forms.tsx`), types, and the shared helpers in `src/features/shared/`. |
| Shared helpers | `src/features/shared/` | `client-rpc.ts`, `server-rpc.ts`, `reads.ts`, `dynamic-form.tsx`, `filter.ts`, `pagination.tsx`, `search-form.tsx`, `use-rpc.ts`. |
| Navigation | `src/lib/nav.ts` | Do not edit without the lead; the group order is locked by a test. |
| Shell | `src/components/app-shell.tsx` | `ICONS` (one entry per nav href), the breadcrumb resolver, the sidebar renderer. |
| Identity | `src/lib/context.ts`, `src/lib/server-context.ts` | `SimsContext` comes from `public.my_context()` and nowhere else. |

The current feature folders are `academic`, `account`, `activities`, `admissions`,
`announcements`, `assessment`, `attendance`, `audit`, `calendar`, `certificates`,
`detail`, `finance`, `feedback`, `grievances`, `hr`, `iam`, `mentoring`,
`my-documents`, `reference`, `registration`, `reporting`, `requests`, `results`,
`schema`, `shared`, `staff-profile`, `structure`, `timetable`, plus the loose
`dashboard-stats.ts` and `students-lookups.ts`.

# Module gaps

The honest list. Each of these is a live fact, not a plan.

| Gap | Detail |
|---|---|
| `/staff-profile` and `/activities` had no page | **Closed.** `src/app/(app)/staff-profile/page.tsx` and `src/app/(app)/activities/page.tsx` now exist, backed by `src/features/staff-profile/` and `src/features/activities/`. The staff-profile screen was later split into `src/features/staff-profile/staff-profile-screen.tsx` so that the fifteen sub-module addresses under `/staff-profile/<section>` can serve it. Schema modules 19–34 and 40 are reachable from the UI and the `staff` and `activities` nav groups no longer render dead links. |
| Schema modules 18, 35, 36, 37, 38 and 39 had no screen | **Closed.** Modules 18, 35, 36, 38 and 39 are served by `src/app/(app)/schema/[module]/page.tsx` and module 37 by `src/app/(app)/reporting/page.tsx`. The sidebar carries six groups for them: `schema`, `seed`, `rbac`, `reporting`, `staff-index` and `integrity`. `supabase/migrations/065_schema_indexes.sql` adds `public.schema_indexes(p_scope text DEFAULT NULL)`, the only door to `pg_indexes`. |
| `REPORTING` is unenforced | 11 permissions, 0 RLS policies, 0 functions that check them. `global_search` is `LANGUAGE sql, STABLE` — not `SECURITY DEFINER` — and checks no permission code. Schema module 37 now has a screen at `/reporting`, and the ten reporting views are `security_invoker` views, so they inherit the RLS of their base tables — but `global_search` is still the hole. |
| `TEACHING` has no screen of its own | Its screens live inside the registration and attendance flows. The code is seeded and allowlisted in the nav test. |
| `COMMUNICATION` is ungated in the sidebar | Intentional: the announcement feed is visible to every signed-in user. The rows are still filtered by `announcement_visible`. |
| `docs:roles` cannot run | **Closed.** `tools/validate/role_matrix.mjs` is back in the tree (restored 23:48:38, reworked 00:11:14 to read the live project with `--source auto|live|rebuilt`). `node tools/validate/role_matrix.mjs --check` exits 0 with `OK - docs\ROLE_PERMISSION_MATRIX.md is up to date (source: live)` - the recovered matrix is byte-identical to what the generator produces from the live database. |
| `docs:schema` cannot run | **Closed.** `tools/validate/schema_doc.mjs` is in the tree (29,642 bytes, written 00:22:20) and renders `docs/SCHEMA.md` and `docs/SCHEMA_RECONCILIATION.md` from the live catalogue. `node tools/validate/schema_doc.mjs --check` exits 0 with both documents up to date. |
| `migrate:catalogue` cannot run as written | **Closed.** `tools/validate/catalogue.mjs` (27,874 bytes, 00:37:22) and `tools/compare_catalogue.py` (19,149 bytes, 00:30:12) are both present. `python tools/compare_catalogue.py` exits 0 with `OK - the live catalogue matches the expected catalogue`: 0 differences across counts, per-schema counts, seeded row counts, tables (222), columns (2140), functions (421), policies (594), triggers (140), grants (6227) and sequences (199). |
| `migrate:build` cannot run as written | **Closed.** `tools/translate.py` was restored at 23:54:54 and `npm run migrate:build` was run at 23:56:38, regenerating `supabase/migrations/001`–`063` from the MySQL source. |
| The regenerated migrations did not reproduce the live function ACLs | **Closed.** The 23:49:34 set was a catalogue regeneration and carried no `REVOKE` statement, so a rebuild left `PUBLIC` able to execute all 420 functions in `public` + `sims_private` (the count at the time). The 23:56:38 translation carries the 418 `REVOKE` statements and `tools/compare_catalogue.py` now reports 0 differences. Gaps G-9 and G-10 in [RTM.md](RTM.md), hole S-8 in [RLS_SECURITY_MODEL.md](RLS_SECURITY_MODEL.md). |
| The auth flows have never been exercised signed in | No Auth user existed at the time of writing; there is no bootstrap administrator. See [AUTHENTICATION_AND_RBAC.md](AUTHENTICATION_AND_RBAC.md). |

