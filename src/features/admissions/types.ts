/** Shared row shapes for the admissions module (schema module 6). */

export type AdmissionApplicant = {
  admission_applicant_id: number;
  first_name: string;
  middle_name: string | null;
  last_name: string | null;
  display_name: string;
  date_of_birth: string | null;
  gender_id: number | null;
  primary_email: string | null;
  primary_phone: string | null;
  nationality_country_id: number | null;
  social_category_id: number | null;
};

export type AdmissionApplication = {
  application_id: number;
  application_number: string;
  admission_applicant_id: number;
  admitted_student_id: number | null;
  programme_id: number;
  specialization_id: number | null;
  academic_year_id: number;
  admission_category_id: number | null;
  application_date: string;
  application_status: string;
  eligibility_status: string;
  remarks: string | null;
};

/** An application joined with its applicant and programme label. */
export type AdmissionRow = {
  application: AdmissionApplication;
  applicant: AdmissionApplicant | null;
  programme_name: string;
  applicant_name: string;
};

/** A simple `{ id, label }` option used by the admission forms. */
export type LookupOption = {
  id: number;
  label: string;
  /** Programme the option belongs to (curriculum schemes only). */
  programmeId?: number;
};

/**
 * The status moves the database accepts.
 *
 * This is a convenience for the UI only — `admission_set_status` re-checks the
 * transition and the caller's permission before anything is written.
 */
export const NEXT_STATUS: Record<string, string[]> = {
  DRAFT: ['SUBMITTED', 'CANCELLED'],
  SUBMITTED: ['UNDER_REVIEW', 'REJECTED', 'CANCELLED'],
  UNDER_REVIEW: ['ELIGIBLE', 'INELIGIBLE', 'REJECTED', 'CANCELLED'],
  ELIGIBLE: ['SELECTED', 'WAITLISTED', 'REJECTED', 'CANCELLED'],
  INELIGIBLE: ['REJECTED', 'CANCELLED'],
  WAITLISTED: ['SELECTED', 'REJECTED', 'CANCELLED'],
  SELECTED: ['REJECTED', 'CANCELLED'],
  ADMITTED: [],
  REJECTED: [],
  CANCELLED: [],
};
