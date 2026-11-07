-- 064. REQUIRED REFERENCE SEEDS
-- =============================================================================================
-- Closes the reference-data gaps that block the application screens:
--   KI-18  lookup tables were empty (gender, blood group, religion, social category, caste,
--          sub-caste, country, state, admission category, fee types, ledger accounts,
--          concessions, scholarships, instalment plans) -> the register / employee / fee forms
--          showed empty dropdowns.
--   KI-36  attendance_status had no rows at all -> attendance could not be marked.
--   KI-39  no grade scale existed -> results could not be graded.
--
-- Rules this file obeys:
--   * It NEVER inserts into a table that the MySQL source seeds (access_*, role, role_permission,
--     permission, fee_category, payment_mode, designation, staff_type, staff_category,
--     employment_source, qualification_level, document_type, student_activity_type,
--     activity_type, approval_status, verification_status, ...). Those tables are seeded by
--     migrations 001-013 and "npm run migrate:seed-check" compares their row counts EXACTLY
--     against the source, so an extra row there would fail that check.
--   * Explicit ids start at 101 so that test fixtures (which use ids 1..n) never collide.
--   * Every statement is idempotent: re-running the file inserts nothing new.
--   * Attendance status names are distinct from the short codes used by the attendance test
--     fixtures ('P'/'Present', 'A'/'Absent', 'L'/'Late') so both can coexist in one database.
-- =============================================================================================

-- ---------------------------------------------------------------------------------------------
-- 1. Module 1 - common reference: demographics
-- ---------------------------------------------------------------------------------------------
INSERT INTO gender (gender_id, gender_code, gender_name) VALUES
  (101, 'M', 'Male'), (102, 'F', 'Female'), (103, 'O', 'Other')
ON CONFLICT DO NOTHING;

INSERT INTO blood_group (blood_group_id, blood_group_code) VALUES
  (101, 'A+'), (102, 'A-'), (103, 'B+'), (104, 'B-'),
  (105, 'O+'), (106, 'O-'), (107, 'AB+'), (108, 'AB-')
ON CONFLICT DO NOTHING;

INSERT INTO religion (religion_id, religion_code, religion_name) VALUES
  (101, 'HIN', 'Hindu'), (102, 'MUS', 'Muslim'), (103, 'CHR', 'Christian'), (104, 'SIK', 'Sikh'),
  (105, 'BUD', 'Buddhist'), (106, 'JAI', 'Jain'), (107, 'PAR', 'Parsi'), (108, 'OTH', 'Other')
ON CONFLICT DO NOTHING;

INSERT INTO social_category (social_category_id, category_code, category_name) VALUES
  (101, 'GENERAL', 'General'), (102, 'OBC', 'Other Backward Class'), (103, 'SC', 'Scheduled Caste'),
  (104, 'ST', 'Scheduled Tribe'), (105, 'EWS', 'Economically Weaker Section')
ON CONFLICT DO NOTHING;

INSERT INTO caste (caste_id, social_category_id, caste_code, caste_name) VALUES
  (101, 101, 'GEN', 'General'), (102, 102, 'OBC', 'Other Backward Class'),
  (103, 103, 'SC', 'Scheduled Caste'), (104, 104, 'ST', 'Scheduled Tribe')
ON CONFLICT DO NOTHING;

INSERT INTO sub_caste (sub_caste_id, caste_id, sub_caste_code, sub_caste_name) VALUES
  (101, 101, 'BR', 'Brahmin'), (102, 102, 'MA', 'Maratha'),
  (103, 103, 'VK', 'Vankata'), (104, 104, 'BH', 'Bhaura')
ON CONFLICT DO NOTHING;

INSERT INTO country (country_id, iso_code, country_name) VALUES
  (101, 'IN', 'India'), (102, 'US', 'United States'), (103, 'GB', 'United Kingdom'),
  (104, 'AU', 'Australia'), (105, 'CA', 'Canada'), (106, 'SG', 'Singapore'),
  (107, 'AE', 'United Arab Emirates')
ON CONFLICT DO NOTHING;

INSERT INTO state (state_id, country_id, state_code, state_name)
SELECT v.state_id, c.country_id, v.state_code, v.state_name
FROM (VALUES
  (101, 'KA', 'Karnataka'), (102, 'MH', 'Maharashtra'), (103, 'TN', 'Tamil Nadu'),
  (104, 'KL', 'Kerala'), (105, 'GJ', 'Gujarat'), (106, 'DL', 'Delhi'),
  (107, 'TG', 'Telangana'), (108, 'AP', 'Andhra Pradesh'), (109, 'WB', 'West Bengal'),
  (110, 'UP', 'Uttar Pradesh'), (111, 'RJ', 'Rajasthan'), (112, 'PB', 'Punjab'),
  (113, 'HR', 'Haryana'), (114, 'OD', 'Odisha'), (115, 'GA', 'Goa'),
  (116, 'BR', 'Bihar'), (117, 'MP', 'Madhya Pradesh'), (118, 'JH', 'Jharkhand'),
  (119, 'UK', 'Uttarakhand'), (120, 'AS', 'Assam')
) AS v(state_id, state_code, state_name)
JOIN country c ON c.iso_code = 'IN'
ON CONFLICT DO NOTHING;

INSERT INTO admission_category (admission_category_id, category_code, category_name, description) VALUES
  (101, 'GENERAL', 'General', 'Open merit'),
  (102, 'OBC', 'Other Backward Class', 'Backward class reservation'),
  (103, 'SC', 'Scheduled Caste', 'SC reservation'),
  (104, 'ST', 'Scheduled Tribe', 'ST reservation'),
  (105, 'EWS', 'Economically Weaker Section', 'EWS reservation'),
  (106, 'NRI', 'Non Resident Indian', 'NRI quota'),
  (107, 'FOREIGN', 'Foreign Student', 'International quota'),
  (108, 'INSTITUTIONAL', 'Institutional Quota', 'Management / institutional quota')
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------------------------
-- 2. Module 17 - fees and finance: the reference lists the fee screens need
-- ---------------------------------------------------------------------------------------------
INSERT INTO financial_ledger_account (ledger_account_id, account_code, account_name, account_type) VALUES
  (101, 'FEE_TUITION', 'Tuition Fee Income', 'REVENUE'),
  (102, 'FEE_ADMISSION', 'Admission Fee Income', 'REVENUE'),
  (103, 'FEE_EXAM', 'Examination Fee Income', 'REVENUE'),
  (104, 'FEE_HOSTEL', 'Hostel Fee Income', 'REVENUE'),
  (105, 'FEE_LIBRARY', 'Library Fee Income', 'REVENUE'),
  (106, 'FEE_MISC', 'Miscellaneous Fee Income', 'REVENUE')
ON CONFLICT DO NOTHING;

INSERT INTO fee_type (fee_type_id, fee_category_id, fee_code, fee_name, charge_frequency, ledger_account_id, is_mandatory, is_refundable)
SELECT v.fee_type_id, c.fee_category_id, v.fee_code, v.fee_name, v.charge_frequency, v.ledger_account_id, v.is_mandatory, v.is_refundable
FROM (VALUES
  (101, 'ACADEMIC', 'TUITION_FEE', 'Tuition Fee', 'ANNUAL', 101, true, false),
  (102, 'ACADEMIC', 'LAB_FEE', 'Laboratory Fee', 'ANNUAL', 101, false, false),
  (103, 'ACADEMIC', 'LIBRARY_FEE', 'Library Fee', 'ANNUAL', 105, false, false),
  (104, 'ADMISSION', 'ADMISSION_FEE', 'Admission Fee', 'ONE_TIME', 102, true, false),
  (105, 'EXAMINATION', 'EXAM_FEE', 'Examination Fee', 'PER_EXAM', 103, true, false),
  (106, 'HOSTEL', 'HOSTEL_FEE', 'Hostel Fee', 'ANNUAL', 104, false, true),
  (107, 'TRANSPORT', 'TRANSPORT_FEE', 'Transport Fee', 'ANNUAL', 106, false, true),
  (108, 'CERTIFICATE', 'CERTIFICATE_FEE', 'Certificate Fee', 'PER_SERVICE', 106, false, false),
  (109, 'PENALTY', 'LATE_FINE', 'Late Payment Fine', 'OTHER', 106, false, false),
  (110, 'OTHER', 'MISC_FEE', 'Miscellaneous Fee', 'OTHER', 106, false, false)
) AS v(fee_type_id, cat_code, fee_code, fee_name, charge_frequency, ledger_account_id, is_mandatory, is_refundable)
JOIN fee_category c ON c.category_code = v.cat_code
ON CONFLICT DO NOTHING;

INSERT INTO concession_type (concession_type_id, concession_code, concession_name, concession_basis, maximum_percentage, maximum_amount, approval_required) VALUES
  (101, 'MERIT', 'Merit Scholarship', 'PERCENTAGE', 50, NULL, true),
  (102, 'SAHITY', 'Sahitya Academy', 'FIXED_AMOUNT', NULL, 5000, true),
  (103, 'GOVERNMENT', 'Government Aid', 'PERCENTAGE', 100, NULL, true),
  (104, 'STAFF_WAIVER', 'Staff / Ward Concession', 'PERCENTAGE', 25, NULL, false)
ON CONFLICT DO NOTHING;

INSERT INTO scholarship_scheme (scholarship_scheme_id, scheme_code, scheme_name, sponsoring_authority, scheme_type, maximum_amount, is_reimbursable) VALUES
  (101, 'GOV_MERIT', 'Government Merit Scholarship', 'State Government', 'GOVERNMENT', 50000, false),
  (102, 'INST_MERIT', 'Institutional Merit Scholarship', 'Institute', 'INSTITUTIONAL', 25000, false),
  (103, 'CSR_EDU', 'CSR Education Support', 'Demo CSR Trust', 'CSR', 40000, true),
  (104, 'PRIVATE_SAHOG', 'Private Trust Scholarship', 'Demo Trust', 'PRIVATE', 20000, false)
ON CONFLICT DO NOTHING;

INSERT INTO installment_plan (installment_plan_id, plan_code, plan_name, number_of_installments, minimum_initial_percentage, approval_required) VALUES
  (101, 'ONE_TIME', 'Single Payment', 1, 100, false),
  (102, 'TWO_SPLIT', 'Two Instalments', 2, 50, false),
  (103, 'THREE_SPLIT', 'Three Instalments', 3, 40, true),
  (104, 'FOUR_SPLIT', 'Four Instalments', 4, 25, true)
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------------------------
-- 3. Module 9 - attendance statuses (KI-36)
-- ---------------------------------------------------------------------------------------------
INSERT INTO attendance_status (attendance_status_id, status_code, status_name, counts_as_present) VALUES
  (101, 'PRESENT', 'Present (Default)', true),
  (102, 'ABSENT', 'Absent (Default)', false),
  (103, 'LATE', 'Late (Default)', true),
  (104, 'EXCUSED', 'Excused', false),
  (105, 'ON_LEAVE', 'On Leave', false)
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------------------------
-- 4. Module 10 - grading scale (KI-39)
--    The result RPC picks the active scale with the latest effective_from and then the rule
--    whose [minimum_percentage, maximum_percentage] band covers the computed percentage.
-- ---------------------------------------------------------------------------------------------
INSERT INTO grade_scale (grade_scale_id, scale_name, effective_from, is_active)
VALUES (101, 'PERCENTAGE_10_POINT', '2020-01-01', true)
ON CONFLICT DO NOTHING;

INSERT INTO grade_rule (grade_scale_id, grade_letter, grade_point, minimum_percentage, maximum_percentage, result_status)
SELECT 101, v.grade_letter, v.grade_point, v.minimum_percentage, v.maximum_percentage, v.result_status
FROM (VALUES
  ('O',  10.00, 90.00, 100.00, 'PASS'),
  ('A+',  9.00, 80.00,  89.99, 'PASS'),
  ('A',   8.00, 70.00,  79.99, 'PASS'),
  ('B+',  7.00, 60.00,  69.99, 'PASS'),
  ('B',   6.00, 50.00,  59.99, 'PASS'),
  ('C',   5.00, 40.00,  49.99, 'PASS'),
  ('F',   0.00,  0.00,  39.99, 'FAIL')
) AS v(grade_letter, grade_point, minimum_percentage, maximum_percentage, result_status)
ON CONFLICT DO NOTHING;
