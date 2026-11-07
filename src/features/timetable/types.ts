/** Shared row shapes for the teaching & timetable module (schema module 8). */

/** One row of `timetable_offerings(...)`. */
export type TimetableOffering = {
  programme_term_offering_id: number;
  term_name: string;
  programme_name: string;
  semester_name: string;
  section_count: number;
  entry_count: number;
  total_count: number;
};

/** One row of `timetable_entries(p_pto)`. */
export type TimetableEntry = {
  timetable_session_id: number;
  course_offering_section_id: number;
  course_label: string;
  section_code: string;
  batch_code: string | null;
  session_type: string;
  instructor_name: string | null;
  day_of_week: number;
  time_slot_id: number;
  slot_code: string;
  start_time: string;
  end_time: string;
  room_id: number | null;
  room_label: string | null;
  effective_from: string;
  effective_to: string | null;
};

/** One row of `timetable_slots()`. */
export type TimeSlot = {
  time_slot_id: number;
  campus_id: number;
  campus_name: string;
  slot_code: string;
  start_time: string;
  end_time: string;
  is_break: boolean;
  is_active: boolean;
};

/** One row of `timetable_rooms()`. */
export type Room = {
  room_id: number;
  campus_id: number;
  campus_name: string;
  room_label: string;
  room_type: string;
  capacity: number | null;
  is_active: boolean;
};

/** One row of `timetable_sections(p_pto)`. */
export type TimetableSection = {
  course_offering_section_id: number;
  course_label: string;
  section_code: string;
  batch_code: string | null;
  session_type: string;
};

/** One row of `timetable_assignments(p_cos_id)`. */
export type FacultyAssignment = {
  faculty_assignment_id: number;
  employee_name: string;
  assignment_role: string;
  assignment_status: string;
};
