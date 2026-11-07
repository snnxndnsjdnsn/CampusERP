-- =============================================================================================
-- 007. employee_hr_profile
-- ---------------------------------------------------------------------------------------------
-- GENERATED FILE - do not edit by hand.
-- Regenerate with: npm run migrate:build   (python tools/translate.py && python tools/build_migrations.py)
--
-- Source of truth: the live Supabase catalogue (tools/catalogue/live_catalogue.json),
-- dumped read-only from project khqqfgqvwdxlqkncwtmh by tools/dump_catalogue.py.
-- =============================================================================================

-- -----------------------------------------------------------------------------
-- Seed rows for the tables of module 'employee hr profile'.
-- Only the rows the live database really contains are emitted; every
-- statement carries explicit primary keys and is idempotent.
-- -----------------------------------------------------------------------------
-- MySQL module 5: STUDENT AND STAFF MASTER MODULES (INDEPENDENT ROOT ENTITIES)
-- MySQL module 16: EMPLOYEE HR PROFILE, QUALIFICATION, EXPERIENCE AND SECURE EVIDENCE MODULE
-- MySQL module 19: STAFF PROFILE REFERENCE / MASTER DATA

INSERT INTO public.staff_type (staff_type_id, type_code, type_name, description, is_active, created_at, updated_at) VALUES
  (1, 'TEACHING', 'Teaching', 'Academic and teaching personnel', TRUE, '2026-11-03T18:30:07.667768+00:00'::timestamptz, '2026-11-03T18:30:07.667768+00:00'::timestamptz),
  (2, 'NON_TEACHING', 'Non-Teaching', 'Administrative, technical, support and service personnel', TRUE, '2026-11-03T18:30:07.667768+00:00'::timestamptz, '2026-11-03T18:30:07.667768+00:00'::timestamptz)
ON CONFLICT DO NOTHING;
INSERT INTO public.staff_category (staff_category_id, staff_type_id, category_code, category_name, description, is_active, created_at, updated_at) VALUES
  (1, 1, 'TEACHING_STAFF', 'Teaching Staff', 'Faculty and other personnel engaged in teaching', TRUE, '2026-11-03T18:30:07.667768+00:00'::timestamptz, '2026-11-03T18:30:07.667768+00:00'::timestamptz),
  (2, 2, 'OFFICE_STAFF', 'Office Staff', 'Administrative and office personnel', TRUE, '2026-11-03T18:30:07.667768+00:00'::timestamptz, '2026-11-03T18:30:07.667768+00:00'::timestamptz),
  (3, 2, 'EXAM_SECTION_STAFF', 'Examination Section Staff', 'Personnel working in the examination section', TRUE, '2026-11-03T18:30:07.667768+00:00'::timestamptz, '2026-11-03T18:30:07.667768+00:00'::timestamptz),
  (4, 2, 'LIBRARY_STAFF', 'Library Staff', 'Library professional and support personnel', TRUE, '2026-11-03T18:30:07.667768+00:00'::timestamptz, '2026-11-03T18:30:07.667768+00:00'::timestamptz),
  (5, 2, 'MENIAL_STAFF', 'Menial Staff', 'Institutional support and menial personnel', TRUE, '2026-11-03T18:30:07.667768+00:00'::timestamptz, '2026-11-03T18:30:07.667768+00:00'::timestamptz),
  (6, 2, 'INTERNAL_SECURITY', 'Internal Security Staff', 'Security personnel directly engaged by the institution', TRUE, '2026-11-03T18:30:07.667768+00:00'::timestamptz, '2026-11-03T18:30:07.667768+00:00'::timestamptz),
  (7, 2, 'AGENCY_SECURITY', 'Security Staff - External Agency', 'Security personnel supplied by an external agency', TRUE, '2026-11-03T18:30:07.667768+00:00'::timestamptz, '2026-11-03T18:30:07.667768+00:00'::timestamptz),
  (8, 2, 'AGENCY_HOUSEKEEPING', 'Housekeeping Staff - External Agency', 'Housekeeping personnel supplied by an external agency', TRUE, '2026-11-03T18:30:07.667768+00:00'::timestamptz, '2026-11-03T18:30:07.667768+00:00'::timestamptz)
ON CONFLICT DO NOTHING;
INSERT INTO public.employment_source (employment_source_id, source_code, source_name, is_external, description, is_active, created_at, updated_at) VALUES
  (1, 'INSTITUTION', 'Institution Employee', FALSE, 'Person directly engaged by the institution', TRUE, '2026-11-03T18:30:07.667768+00:00'::timestamptz, '2026-11-03T18:30:07.667768+00:00'::timestamptz),
  (2, 'EXTERNAL_AGENCY', 'External Agency', TRUE, 'Person supplied by a contracted external agency', TRUE, '2026-11-03T18:30:07.667768+00:00'::timestamptz, '2026-11-03T18:30:07.667768+00:00'::timestamptz)
ON CONFLICT DO NOTHING;
INSERT INTO public.designation (designation_id, staff_category_id, designation_code, designation_name, description, is_active) VALUES
  (1, 1, 'PROFESSOR', 'Professor', NULL, TRUE),
  (2, 1, 'ASSOC_PROFESSOR', 'Associate Professor', NULL, TRUE),
  (3, 1, 'ASST_PROFESSOR', 'Assistant Professor', NULL, TRUE),
  (4, 2, 'OFFICE_SUPERINTENDENT', 'Office Superintendent', NULL, TRUE),
  (5, 2, 'OFFICE_ASSISTANT', 'Office Assistant', NULL, TRUE),
  (6, 3, 'EXAM_SUPERINTENDENT', 'Examination Superintendent', NULL, TRUE),
  (7, 3, 'EXAM_ASSISTANT', 'Examination Assistant', NULL, TRUE),
  (8, 4, 'LIBRARIAN', 'Librarian', NULL, TRUE),
  (9, 4, 'ASST_LIBRARIAN', 'Assistant Librarian', NULL, TRUE),
  (10, 5, 'ATTENDER', 'Attender', NULL, TRUE),
  (11, 6, 'INTERNAL_SECURITY_GUARD', 'Security Guard', NULL, TRUE),
  (12, 7, 'AGENCY_SECURITY_GUARD', 'Security Guard', NULL, TRUE),
  (13, 8, 'HOUSEKEEPING_STAFF', 'Housekeeping Staff', NULL, TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO public.qualification_level (qualification_level_id, level_code, level_name, display_order, is_terminal_degree, description, is_active, created_at, updated_at) VALUES
  (1, 'SSLC_10', 'SSLC / 10th', 10, FALSE, NULL, TRUE, '2026-11-03T18:30:09.487772+00:00'::timestamptz, '2026-11-03T18:30:09.487772+00:00'::timestamptz),
  (2, 'PUC_12', 'PUC / 12th', 20, FALSE, NULL, TRUE, '2026-11-03T18:30:09.487772+00:00'::timestamptz, '2026-11-03T18:30:09.487772+00:00'::timestamptz),
  (3, 'DIPLOMA', 'Diploma', 30, FALSE, NULL, TRUE, '2026-11-03T18:30:09.487772+00:00'::timestamptz, '2026-11-03T18:30:09.487772+00:00'::timestamptz),
  (4, 'UNDERGRADUATE', 'Undergraduate', 40, FALSE, NULL, TRUE, '2026-11-03T18:30:09.487772+00:00'::timestamptz, '2026-11-03T18:30:09.487772+00:00'::timestamptz),
  (5, 'POSTGRADUATE', 'Postgraduate', 50, FALSE, NULL, TRUE, '2026-11-03T18:30:09.487772+00:00'::timestamptz, '2026-11-03T18:30:09.487772+00:00'::timestamptz),
  (6, 'MPHIL', 'M.Phil.', 60, FALSE, NULL, TRUE, '2026-11-03T18:30:09.487772+00:00'::timestamptz, '2026-11-03T18:30:09.487772+00:00'::timestamptz),
  (7, 'PHD', 'Ph.D.', 70, TRUE, NULL, TRUE, '2026-11-03T18:30:09.487772+00:00'::timestamptz, '2026-11-03T18:30:09.487772+00:00'::timestamptz),
  (8, 'POSTDOCTORAL', 'Postdoctoral Qualification', 80, TRUE, NULL, TRUE, '2026-11-03T18:30:09.487772+00:00'::timestamptz, '2026-11-03T18:30:09.487772+00:00'::timestamptz),
  (9, 'PROFESSIONAL_CERTIFICATION', 'Professional Certification', 90, FALSE, NULL, TRUE, '2026-11-03T18:30:09.487772+00:00'::timestamptz, '2026-11-03T18:30:09.487772+00:00'::timestamptz),
  (10, 'OTHER', 'Other Qualification', 100, FALSE, NULL, TRUE, '2026-11-03T18:30:09.487772+00:00'::timestamptz, '2026-11-03T18:30:09.487772+00:00'::timestamptz)
ON CONFLICT DO NOTHING;
INSERT INTO public.employee_document_category (employee_document_category_id, category_code, category_name, default_confidentiality, requires_verification, requires_approval, is_active) VALUES
  (1, 'QUALIFICATION', 'Qualification Evidence', 'CONFIDENTIAL', TRUE, FALSE, TRUE),
  (2, 'EXPERIENCE', 'Previous Employment Evidence', 'CONFIDENTIAL', TRUE, FALSE, TRUE),
  (3, 'BANK', 'Bank Account Evidence', 'HIGHLY_RESTRICTED', TRUE, TRUE, TRUE),
  (4, 'PAN', 'PAN Evidence', 'HIGHLY_RESTRICTED', TRUE, TRUE, TRUE),
  (5, 'AADHAAR', 'Aadhaar Evidence', 'HIGHLY_RESTRICTED', TRUE, TRUE, TRUE),
  (6, 'GENERAL', 'Other Employee Document', 'CONFIDENTIAL', TRUE, FALSE, TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO public.awarding_body_type (awarding_body_type_id, type_code, type_name, is_active) VALUES
  (1, 'BOARD', 'Board', TRUE),
  (2, 'UNIVERSITY', 'University', TRUE),
  (3, 'AUTONOMOUS_BODY', 'Autonomous Body', TRUE),
  (4, 'PROFESSIONAL_BODY', 'Professional Body', TRUE),
  (5, 'OTHER', 'Other', TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO public.previous_organization_type (previous_organization_type_id, type_code, type_name, classification, is_active) VALUES
  (1, 'ACADEMIC_INSTITUTION', 'Academic Institution', 'ACADEMIC', TRUE),
  (2, 'GOVERNMENT_DEPARTMENT', 'Government Department', 'GOVERNMENT', TRUE),
  (3, 'PRIVATE_COMPANY', 'Private Company', 'PRIVATE', TRUE),
  (4, 'PUBLIC_SECTOR', 'Public Sector Undertaking', 'PUBLIC_SECTOR', TRUE),
  (5, 'INDUSTRY', 'Industry', 'INDUSTRY', TRUE),
  (6, 'NGO', 'NGO / Non-Profit', 'NGO', TRUE),
  (7, 'SELF_EMPLOYED', 'Self Employed', 'SELF_EMPLOYED', TRUE),
  (8, 'OTHER', 'Other Organization', 'OTHER', TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO public.education_institution_type (education_institution_type_id, type_code, type_name, is_active) VALUES
  (1, 'SCHOOL', 'School', TRUE),
  (2, 'PU_COLLEGE', 'PU / Higher Secondary College', TRUE),
  (3, 'COLLEGE', 'College', TRUE),
  (4, 'UNIVERSITY', 'University', TRUE),
  (5, 'TRAINING_INSTITUTE', 'Training Institute', TRUE),
  (6, 'OTHER', 'Other', TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO public.study_mode (study_mode_id, mode_code, mode_name, is_active) VALUES
  (1, 'REGULAR', 'Regular', TRUE),
  (2, 'FULL_TIME', 'Full-time', TRUE),
  (3, 'PART_TIME', 'Part-time', TRUE),
  (4, 'DISTANCE', 'Distance Education', TRUE),
  (5, 'ONLINE', 'Online', TRUE),
  (6, 'HYBRID', 'Hybrid', TRUE),
  (7, 'OTHER', 'Other', TRUE)
ON CONFLICT DO NOTHING;
