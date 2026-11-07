/** Shared row shapes for the results module (schema module 10). */

/** One row of `result_course_sheet(p_course_offering_id)`. */
export type ResultCourseSheetRow = {
  course_registration_id: number;
  student_id: number;
  student_number: string;
  display_name: string;
  internal_marks: number | null;
  external_marks: number | null;
  total_marks: number | null;
  grade_letter: string | null;
  grade_point: number | null;
  result_status: string | null;
  attempt_number: number | null;
  published: boolean;
};

/** One row of `result_term_sheet(p_offering_id)`. */
export type ResultTermSheetRow = {
  term_registration_id: number;
  student_id: number;
  student_number: string;
  display_name: string;
  credits_registered: number | null;
  credits_earned: number | null;
  sgpa: number | null;
  cgpa: number | null;
  result_status: string | null;
  published_at: string | null;
};

/** A row of the `grade_scale` table. */
export type GradeScaleRow = {
  grade_scale_id: number;
  scale_name: string;
  effective_from: string;
  effective_to: string | null;
  is_active: boolean;
};

/** A row of the `grade_rule` table. */
export type GradeRuleRow = {
  grade_rule_id: number;
  grade_scale_id: number;
  grade_letter: string;
  grade_point: number;
  minimum_percentage: number;
  maximum_percentage: number;
  result_status: string;
};

/** The explicit course-result statuses the database accepts. */
export const RESULT_STATUSES = ['ABSENT', 'WITHHELD', 'EXEMPTED', 'INCOMPLETE'] as const;
