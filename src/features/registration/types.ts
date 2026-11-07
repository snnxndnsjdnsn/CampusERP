/** Shared row shapes for the registration module (schema module 7). */

/** A programme term offering, joined with its term, programme and semester. */
export type TermOffering = {
  programme_term_offering_id: number;
  academic_term_id: number;
  programme_id: number;
  semester_id: number;
  status: string;
  term_name: string;
  programme_name: string;
  semester_name: string;
};

/** One row of `registration_roster(p_offering_id)`. */
export type RosterRow = {
  term_registration_id: number;
  enrolment_id: number;
  student_id: number;
  student_number: string;
  display_name: string;
  roll_number: string | null;
  class_section_id: number | null;
  class_batch_id: number | null;
  registration_date: string;
  registration_status: string;
};

/** One row of `registration_candidates(p_offering_id, p_q)`. */
export type CandidateRow = {
  enrolment_id: number;
  student_id: number;
  student_number: string;
  display_name: string;
};

/** One row of `registration_term_info(p_term_registration_id)`. */
export type TermInfoRow = RosterRow & {
  programme_term_offering_id: number;
};

/** A row of the `student_course_registration` table. */
export type CourseRegistrationRow = {
  course_registration_id: number;
  term_registration_id: number;
  course_offering_id: number;
  registration_type: string;
  registration_date: string;
  registration_status: string;
  /** `course_offering.offering_code`, when the offering row is readable. */
  offering_code: string | null;
};
