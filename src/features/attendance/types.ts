/** Shared row shapes for the attendance module (schema module 9). */

/** A row of the `attendance_status` reference table. */
export type AttendanceStatus = {
  attendance_status_id: number;
  status_code: string;
  status_name: string;
  counts_as_present: boolean;
  is_active: boolean;
};

/** A row of the `class_session` table, with its teaching section label when readable. */
export type ClassSessionRow = {
  class_session_id: number;
  course_offering_section_id: number;
  session_date: string;
  start_time: string;
  end_time: string;
  room_id: number | null;
  session_type: string;
  session_status: string;
  course_label: string | null;
  section_code: string | null;
};

/** One row of `attendance_sheet(p_session_id)`. */
export type AttendanceSheetRow = {
  roster_id: number;
  student_id: number;
  student_number: string;
  display_name: string;
  attendance_status_id: number | null;
  remarks: string | null;
  marked_at: string | null;
};

/** One row of `attendance_summary(p_cos_id)`. */
export type AttendanceSummaryRow = {
  roster_id: number;
  student_id: number;
  student_number: string;
  display_name: string;
  conducted_sessions: number;
  present_sessions: number;
  percentage: number | null;
};

/** A row of the `attendance_correction_request` table. */
export type CorrectionRequestRow = {
  attendance_correction_id: number;
  class_session_id: number;
  course_offering_section_student_id: number;
  old_status_id: number;
  requested_status_id: number;
  reason: string;
  request_status: string;
  requested_at: string;
  resolved_at: string | null;
};
