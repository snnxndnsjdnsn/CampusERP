/**
 * Shapes returned by the `fin_*` functions and by the RLS-protected fee tables.
 *
 * The database is the source of truth for every field here: the application only
 * reads what the functions hand back and never derives a value the database did
 * not supply.
 */

export type Option = { id: number; label: string };

/* ------------------------------------------------------------------ */
/* Fee structures                                                      */
/* ------------------------------------------------------------------ */

export type StructureRow = {
  fee_structure_id: number;
  structure_code: string;
  structure_name: string;
  institution_name: string;
  programme_name: string | null;
  year_code: string;
  version_number: number;
  approval_status: string;
  effective_from: string | null;
  effective_to: string | null;
  item_count: number;
  total_amount: number;
  total_count: number;
};

export type StructureItem = {
  id: number;
  fee_type_id: number;
  fee_type: string;
  semester_id: number | null;
  academic_term_id: number | null;
  amount: number;
  due_date: string | null;
  due_days: number | null;
  installment_allowed: boolean;
  waiver_allowed: boolean;
  late_fee_rule_id: number | null;
  display_order: number;
  remarks: string | null;
};

export type StructureDetail = {
  fee_structure_id: number;
  structure_code: string;
  structure_name: string;
  institution_id: number;
  institution_name: string;
  campus_id: number | null;
  programme_id: number | null;
  programme_name: string | null;
  academic_year_id: number;
  year_code: string;
  admission_category_id: number | null;
  version_number: number;
  effective_from: string | null;
  effective_to: string | null;
  approval_status: string;
  remarks: string | null;
  approved_at: string | null;
  can_edit: boolean;
  can_submit: boolean;
  can_decide: boolean;
  can_version: boolean;
  can_delete: boolean;
  items: StructureItem[];
};

/* ------------------------------------------------------------------ */
/* Student accounts                                                    */
/* ------------------------------------------------------------------ */

export type AccountRow = {
  student_account_id: number;
  student_id: number;
  account_number: string;
  account_status: string;
  student_number: string;
  display_name: string;
  total_payable: number;
  total_paid: number;
  total_balance: number;
  total_count: number;
};

export type AccountInfo = {
  student_account_id: number;
  student_id: number;
  account_number: string;
  account_status: string;
  student_number: string;
  display_name: string;
  opening_balance: number;
  credit_balance: number;
  total_payable: number;
  total_paid: number;
  total_balance: number;
};

/* ------------------------------------------------------------------ */
/* Assessments                                                         */
/* ------------------------------------------------------------------ */

export type AssessmentRow = {
  fee_assessment_id: number;
  assessment_number: string;
  student_account_id: number;
  academic_year_id: number;
  assessment_type: string;
  assessment_date: string;
  due_date: string | null;
  gross_amount: number;
  concession_amount: number;
  scholarship_amount: number;
  adjustment_amount: number;
  net_payable_amount: number;
  amount_paid: number;
  balance_amount: number;
  assessment_status: string;
};

export type AssessmentItemRow = {
  assessment_item_id: number;
  fee_assessment_id: number;
  fee_type_id: number;
  description: string | null;
  original_amount: number;
  concession_amount: number;
  scholarship_amount: number;
  adjustment_amount: number;
  net_amount: number;
  amount_paid: number;
  balance_amount: number;
  due_date: string | null;
  item_status: string;
};

/* ------------------------------------------------------------------ */
/* Payments, receipts and holds                                        */
/* ------------------------------------------------------------------ */

export type PaymentRow = {
  payment_transaction_id: number;
  transaction_number: string;
  transaction_date: string;
  amount: number;
  payment_status: string;
  mode_name: string;
  fee_receipt_id: number | null;
  receipt_number: string | null;
  receipt_status: string | null;
};

export type HoldRow = {
  financial_hold_id: number;
  hold_type: string;
  hold_reason: string;
  hold_status: string;
  placed_at: string;
  released_at: string | null;
  release_reason: string | null;
};

export type ReceiptDetail = {
  fee_receipt_id: number;
  receipt_number: string;
  receipt_date: string;
  receipt_amount: number;
  receipt_status: string;
  cancellation_reason: string | null;
  transaction_number: string;
  transaction_date: string;
  payment_mode: string;
  bank_reference: string | null;
  payer_name: string | null;
  account_number: string;
  student_number: string;
  student_name: string;
  allocations: { fee: string; amount: number }[];
  can_cancel: boolean;
};

/* ------------------------------------------------------------------ */
/* Benefits, adjustments, penalties, refunds, instalments              */
/* ------------------------------------------------------------------ */

export type BenefitRow = {
  kind: string;
  id: number;
  name: string;
  status: string;
  percentage: number | null;
  amount: number | null;
  applied: number;
  requested: string | null;
  remarks: string | null;
};

export type AdjustmentRow = {
  id: number;
  number: string;
  type: string;
  amount: number;
  status: string;
  reason: string;
  item_id: number | null;
  date: string;
};

export type PenaltyRow = {
  id: number;
  date: string;
  reason: string;
  amount: number;
  waived: number;
  net: number;
  status: string;
};

export type InstalmentRow = {
  id: number;
  assessment_id: number;
  number: number;
  due: string;
  amount: number;
  paid: number;
  status: string;
};

export type RefundRow = {
  refund_request_id: number;
  refund_request_number: string;
  student_account_id: number;
  payment_transaction_id: number | null;
  request_date: string;
  refund_reason: string;
  requested_amount: number;
  approved_amount: number | null;
  request_status: string;
};

export type AccountExtras = {
  benefits: BenefitRow[];
  adjustments: AdjustmentRow[];
  instalments: InstalmentRow[];
  penalties: PenaltyRow[];
  can: {
    benefit_create: boolean;
    benefit_approve: boolean;
    benefit_apply: boolean;
    adjust_create: boolean;
    adjust_approve: boolean;
    assess_create: boolean;
    assess_update: boolean;
  };
};

/** The `fin_account_extras` payload, with missing sections tolerated. */
export function emptyExtras(): AccountExtras {
  return {
    benefits: [],
    adjustments: [],
    instalments: [],
    penalties: [],
    can: {
      benefit_create: false,
      benefit_approve: false,
      benefit_apply: false,
      adjust_create: false,
      adjust_approve: false,
      assess_create: false,
      assess_update: false,
    },
  };
}
