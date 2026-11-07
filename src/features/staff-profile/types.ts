import type { FormColumn } from '@/features/shared/dynamic-form';

/**
 * Shapes returned by the `staff_*` functions.
 *
 * The database owns every field: the application reads what the functions hand
 * back and never derives a value the database did not supply.
 */

export type Option = { id: number; label: string };

export type ActivityTypeRow = {
  activity_type_id: number;
  activity_type_code: string;
  activity_type_name: string;
  activity_group: string;
  is_active: boolean;
};

export type StaffActivityRow = {
  staff_activity_id: number;
  employee_id: number;
  employee_number: string;
  staff_name: string;
  type_name: string;
  activity_group: string;
  activity_title: string;
  start_date: string | null;
  verification_status: string;
  approval_status: string;
  evidence_count: number;
  total_count: number;
};

export type StaffReportRow = {
  activity_group: string;
  approval_status: string;
  records: number;
  employees: number;
};

export type EmployeeOption = {
  employee_id: number;
  employee_number: string;
  display_name: string;
};

export type Contributor = {
  contributor_id: number;
  name: string;
  is_employee: boolean;
  role: string | null;
  affiliation: string | null;
  is_corresponding: boolean;
};

export type EvidenceRow = {
  evidence_id: number;
  title: string;
  evidence_type: string | null;
  version: number;
  file_name: string | null;
  size: number | null;
  issued: string | null;
  authority: string | null;
  certificate_number: string | null;
};

export type StaffActivityDetail = {
  staff_activity_id: number;
  employee_id: number;
  employee_number: string;
  staff_name: string;
  activity_type_id: number;
  type_name: string;
  activity_group: string;
  academic_year_id: number | null;
  participation_level_id: number | null;
  primary_role_type_id: number | null;
  activity_title: string;
  start_date: string | null;
  end_date: string | null;
  description: string | null;
  outcomes: string | null;
  verification_status: string;
  verification_remarks: string | null;
  approval_status: string;
  approval_remarks: string | null;
  rejection_reason: string | null;
  detail_table: string | null;
  detail: Record<string, unknown>;
  is_owner: boolean;
  can_edit: boolean;
  can_delete: boolean;
  can_verify: boolean;
  can_approve: boolean;
  contributors: Contributor[];
  evidence: EvidenceRow[];
};

/** The shape of `staff_detail_schema(p_activity_type_id)`. */
export type DetailSchema = {
  table: string | null;
  columns: FormColumn[];
};

export type IndexingRow = {
  agency_id: number;
  agency: string;
  status: string;
  url: string | null;
  remarks: string | null;
  year: number | null;
};

export type IndexingList = {
  rows: IndexingRow[];
  kind: string;
  can_edit: boolean;
};

/** The activity types whose publications carry an indexing claim. */
export const INDEXING_TYPE_CODES = ['JOURNAL_PUBLICATION', 'CONFERENCE_PUBLICATION', 'CONFERENCE_PRESENTATION'];
