/** Shared row shapes for the assessment module (schema module 10). */

/** One row of `assessment_offerings(...)`. */
export type AssessmentOffering = {
  course_offering_id: number;
  programme_term_offering_id: number;
  offering_code: string;
  course_code: string;
  course_title: string;
  term_name: string;
  programme_name: string;
  semester_name: string;
  total_count: number;
};

/** One row of `assessment_offering_info(p_course_offering_id)`. */
export type AssessmentOfferingInfo = {
  course_offering_id: number;
  programme_term_offering_id: number;
  programme_id: number;
  offering_code: string;
  course_code: string;
  course_title: string;
  credits: number | null;
  term_name: string;
  programme_name: string;
  semester_name: string;
  internal_max_marks: number | null;
  external_max_marks: number | null;
  passing_marks: number | null;
};

/** A row of the `assessment_event` table. */
export type AssessmentEventRow = {
  assessment_event_id: number;
  assessment_component_id: number;
  course_offering_id: number;
  event_number: number | null;
  event_title: string;
  assessment_date: string;
  start_time: string | null;
  end_time: string | null;
  maximum_marks: number;
  reduced_maximum_marks: number | null;
  details: string | null;
  status: string;
};

/** One row of `assessment_sheet(p_event_id)`. */
export type AssessmentSheetRow = {
  course_registration_id: number;
  student_id: number;
  student_number: string;
  display_name: string;
  attendance_status: string | null;
  marks_obtained: number | null;
  reduced_marks: number | null;
  remarks: string | null;
};

/** The attendance states an assessment mark may carry. */
export const MARK_STATUSES = ['PRESENT', 'ABSENT', 'EXEMPTED', 'MALPRACTICE'] as const;
