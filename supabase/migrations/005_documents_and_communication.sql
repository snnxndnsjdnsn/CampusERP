-- =============================================================================================
-- 005. documents_and_communication
-- ---------------------------------------------------------------------------------------------
-- GENERATED FILE - do not edit by hand.
-- Regenerate with: npm run migrate:build   (python tools/translate.py && python tools/build_migrations.py)
--
-- Source of truth: the live Supabase catalogue (tools/catalogue/live_catalogue.json),
-- dumped read-only from project khqqfgqvwdxlqkncwtmh by tools/dump_catalogue.py.
-- =============================================================================================

-- -----------------------------------------------------------------------------
-- Seed rows for the tables of module 'documents and communication'.
-- Only the rows the live database really contains are emitted; every
-- statement carries explicit primary keys and is idempotent.
-- -----------------------------------------------------------------------------
-- MySQL module 1: COMMON REFERENCE MODULE
-- MySQL module 14: COMMUNICATION MODULE
-- MySQL module 13: DOCUMENT, CERTIFICATE AND EXIT MODULE
-- MySQL module 33: CENTRALIZED EVIDENCE / DOCUMENT MANAGEMENT

INSERT INTO public.document_type (document_type_id, document_code, document_name, requires_verification, is_active) VALUES
  (1, 'MARKS_CARD', 'Marks Card', TRUE, TRUE),
  (2, 'DEGREE_CERT', 'Degree Certificate', TRUE, TRUE),
  (3, 'PROVISIONAL_DEGREE', 'Provisional Degree Certificate', TRUE, TRUE),
  (4, 'CONVOCATION_CERT', 'Convocation Certificate', TRUE, TRUE),
  (5, 'CONSOLIDATED_MARKS', 'Consolidated Marks Card', TRUE, TRUE),
  (6, 'TRANSCRIPT', 'Academic Transcript', TRUE, TRUE),
  (7, 'MIGRATION_CERT', 'Migration Certificate', TRUE, TRUE),
  (8, 'ELIGIBILITY_CERT', 'Eligibility Certificate', TRUE, TRUE),
  (9, 'PHD_AWARD_CERT', 'Ph.D. Award Certificate', TRUE, TRUE),
  (10, 'PROF_CERT', 'Professional Certification', TRUE, TRUE),
  (11, 'EXPERIENCE_CERT', 'Experience Certificate', TRUE, TRUE),
  (12, 'RELIEVING_LETTER', 'Relieving Letter', TRUE, TRUE),
  (13, 'APPOINTMENT_LETTER', 'Appointment Letter', TRUE, TRUE),
  (14, 'JOINING_LETTER', 'Joining Letter', TRUE, TRUE),
  (15, 'SERVICE_CERT', 'Service Certificate', TRUE, TRUE),
  (16, 'SALARY_CERT', 'Salary Certificate', TRUE, TRUE),
  (17, 'PAY_SLIP', 'Pay Slip', TRUE, TRUE),
  (18, 'PROMOTION_ORDER', 'Promotion Order', TRUE, TRUE),
  (19, 'BANK_PASSBOOK_FRONT', 'Bank Passbook Front Page', TRUE, TRUE),
  (20, 'CANCELLED_CHEQUE', 'Cancelled Cheque', TRUE, TRUE),
  (21, 'BANK_STATEMENT', 'Bank Statement', TRUE, TRUE),
  (22, 'BANK_CONFIRMATION', 'Bank Account Confirmation', TRUE, TRUE),
  (23, 'PAN_CARD', 'PAN Card', TRUE, TRUE),
  (24, 'PAN_VERIFICATION', 'PAN Verification Document', TRUE, TRUE),
  (25, 'AADHAAR_FRONT', 'Aadhaar Front', TRUE, TRUE),
  (26, 'AADHAAR_BACK', 'Aadhaar Back', TRUE, TRUE),
  (27, 'E_AADHAAR', 'e-Aadhaar / Aadhaar PDF', TRUE, TRUE),
  (28, 'OTHER_EMPLOYEE_DOC', 'Other Employee Supporting Document', TRUE, TRUE)
ON CONFLICT DO NOTHING;
