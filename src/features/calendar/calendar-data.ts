import type { SupabaseClient } from '@supabase/supabase-js';
import { readTable } from '@/features/shared/reads';

/** Module 3 · Academic calendar row shapes (read through RLS). */

export type AcademicYear = {
  academic_year_id: number;
  year_code: string;
  start_date: string;
  end_date: string;
  status: string;
};

export type AcademicTerm = {
  academic_term_id: number;
  academic_year_id: number;
  term_code: string;
  term_name: string;
  term_type: string;
  start_date: string;
  end_date: string;
  registration_start_date: string | null;
  registration_end_date: string | null;
  status: string;
};

export type Semester = {
  semester_id: number;
  semester_number: number;
  semester_name: string;
};

export type TimeSlot = {
  time_slot_id: number;
  campus_id: number;
  slot_code: string;
  start_time: string;
  end_time: string;
  is_break: boolean;
  is_active: boolean;
};

export type Holiday = {
  holiday_id: number;
  holiday_date: string;
  holiday_name: string;
  holiday_type: string | null;
  is_optional: boolean | null;
};

export function loadAcademicYears(supabase: SupabaseClient) {
  return readTable<AcademicYear>(
    supabase,
    'academic_year',
    'academic_year_id, year_code, start_date, end_date, status',
    { order: { column: 'start_date', ascending: false } },
  );
}

export function loadAcademicTerms(supabase: SupabaseClient) {
  return readTable<AcademicTerm>(
    supabase,
    'academic_term',
    'academic_term_id, academic_year_id, term_code, term_name, term_type, start_date, end_date, registration_start_date, registration_end_date, status',
    { order: { column: 'start_date', ascending: false } },
  );
}

export function loadSemesters(supabase: SupabaseClient) {
  return readTable<Semester>(supabase, 'semester', 'semester_id, semester_number, semester_name', {
    order: { column: 'semester_number' },
  });
}

export function loadTimeSlots(supabase: SupabaseClient) {
  return readTable<TimeSlot>(
    supabase,
    'time_slot',
    'time_slot_id, campus_id, slot_code, start_time, end_time, is_break, is_active',
    { order: { column: 'slot_code' } },
  );
}

/**
 * The holiday list belongs to module 3 in the original design, but the live
 * schema does not carry a `holiday` table (module 3 ships academic_year,
 * academic_term, semester and time_slot). The read is kept behind a guard so
 * the page still renders and the list appears as soon as the table exists.
 */
export function loadHolidays(supabase: SupabaseClient) {
  return readTable<Holiday>(
    supabase,
    'holiday',
    'holiday_id, holiday_date, holiday_name, holiday_type, is_optional',
    { order: { column: 'holiday_date' } },
  );
}
