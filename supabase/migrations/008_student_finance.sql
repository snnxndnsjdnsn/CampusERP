-- =============================================================================================
-- 008. student_finance
-- ---------------------------------------------------------------------------------------------
-- GENERATED FILE - do not edit by hand.
-- Regenerate with: npm run migrate:build   (python tools/translate.py && python tools/build_migrations.py)
--
-- Source of truth: the live Supabase catalogue (tools/catalogue/live_catalogue.json),
-- dumped read-only from project khqqfgqvwdxlqkncwtmh by tools/dump_catalogue.py.
-- =============================================================================================

-- -----------------------------------------------------------------------------
-- Seed rows for the tables of module 'student finance'.
-- Only the rows the live database really contains are emitted; every
-- statement carries explicit primary keys and is idempotent.
-- -----------------------------------------------------------------------------
-- MySQL module 17: STUDENT FEES AND FINANCIAL MANAGEMENT MODULE

INSERT INTO public.fee_category (fee_category_id, category_code, category_name, description, display_order, is_refundable, is_active, created_at, updated_at) VALUES
  (1, 'ADMISSION', 'Admission Fees', NULL, 10, FALSE, TRUE, '2026-11-03T18:30:09.948365+00:00'::timestamptz, '2026-11-03T18:30:09.948365+00:00'::timestamptz),
  (2, 'ACADEMIC', 'Academic Fees', NULL, 20, FALSE, TRUE, '2026-11-03T18:30:09.948365+00:00'::timestamptz, '2026-11-03T18:30:09.948365+00:00'::timestamptz),
  (3, 'EXAMINATION', 'Examination Fees', NULL, 30, FALSE, TRUE, '2026-11-03T18:30:09.948365+00:00'::timestamptz, '2026-11-03T18:30:09.948365+00:00'::timestamptz),
  (4, 'HOSTEL', 'Hostel Fees', NULL, 40, TRUE, TRUE, '2026-11-03T18:30:09.948365+00:00'::timestamptz, '2026-11-03T18:30:09.948365+00:00'::timestamptz),
  (5, 'TRANSPORT', 'Transport Fees', NULL, 50, TRUE, TRUE, '2026-11-03T18:30:09.948365+00:00'::timestamptz, '2026-11-03T18:30:09.948365+00:00'::timestamptz),
  (6, 'LIBRARY', 'Library Fees and Penalties', NULL, 60, FALSE, TRUE, '2026-11-03T18:30:09.948365+00:00'::timestamptz, '2026-11-03T18:30:09.948365+00:00'::timestamptz),
  (7, 'CERTIFICATE', 'Certificate and Document Fees', NULL, 70, FALSE, TRUE, '2026-11-03T18:30:09.948365+00:00'::timestamptz, '2026-11-03T18:30:09.948365+00:00'::timestamptz),
  (8, 'PENALTY', 'Fines and Penalties', NULL, 80, FALSE, TRUE, '2026-11-03T18:30:09.948365+00:00'::timestamptz, '2026-11-03T18:30:09.948365+00:00'::timestamptz),
  (9, 'OTHER', 'Other Fees', NULL, 90, FALSE, TRUE, '2026-11-03T18:30:09.948365+00:00'::timestamptz, '2026-11-03T18:30:09.948365+00:00'::timestamptz)
ON CONFLICT DO NOTHING;
INSERT INTO public.payment_mode (payment_mode_id, mode_code, mode_name, requires_reference, is_online, is_active) VALUES
  (1, 'CASH', 'Cash', FALSE, FALSE, TRUE),
  (2, 'CARD', 'Card', TRUE, TRUE, TRUE),
  (3, 'UPI', 'UPI', TRUE, TRUE, TRUE),
  (4, 'NET_BANKING', 'Net Banking', TRUE, TRUE, TRUE),
  (5, 'BANK_TRANSFER', 'Bank Transfer', TRUE, FALSE, TRUE),
  (6, 'CHEQUE', 'Cheque', TRUE, FALSE, TRUE),
  (7, 'DEMAND_DRAFT', 'Demand Draft', TRUE, FALSE, TRUE),
  (8, 'PAYMENT_GATEWAY', 'Payment Gateway', TRUE, TRUE, TRUE),
  (9, 'SCHOLARSHIP', 'Scholarship Credit', TRUE, FALSE, TRUE),
  (10, 'SPONSOR', 'Sponsor Payment', TRUE, FALSE, TRUE),
  (11, 'ADJUSTMENT', 'Account Adjustment', TRUE, FALSE, TRUE)
ON CONFLICT DO NOTHING;
