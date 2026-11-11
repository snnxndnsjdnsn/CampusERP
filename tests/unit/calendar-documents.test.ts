import { describe, expect, it } from 'vitest';
import { buildCalendarExport, type CalendarExportInput } from '@/features/calendar/calendar-export';
import { pdfBlob, wordBlob } from '@/features/calendar/calendar-documents';
import type { GridCalendar, GridDay, GridHoliday, GridTermSchedule, GridWeek } from '@/features/calendar/calendar-grid';

/**
 * The two document builders run in the browser, but both libraries pack in
 * plain Node too - so the unit suite can assert the output really is a Word
 * file (a zipped OOXML package, magic `PK`) and a real PDF (magic `%PDF-`)
 * before the end-to-end suite ever starts a server.
 */

const CALENDAR: GridCalendar = {
  calendar_id: 1,
  calendar_type: 'ACADEMIC',
  academic_year_id: 1,
  title: 'B.Tech calendar 2026-27',
  description: 'Plotted weeks',
  start_date: '2026-08-01',
  end_date: '2027-07-31',
};

const TERM: GridCalendar = {
  calendar_id: 2,
  calendar_type: 'TERM',
  academic_year_id: 1,
  title: 'Odd term 2026-27',
  description: null,
  start_date: null,
  end_date: null,
};

const WEEK: GridWeek = {
  week_id: 20,
  calendar_id: 1,
  week_no: 1,
  month_label: 'August 2026',
  week_start_date: '2026-08-10',
  week_end_date: '2026-08-16',
  no_of_working_days: 6,
  events: 'Orientation week; Registration',
};

const DAYS: GridDay[] = [
  { week_day_id: 1, week_id: 20, day_index: 0, day_date: '2026-08-10', day_category: 'WORKING_DAY', holiday_id: null },
  { week_day_id: 2, week_id: 20, day_index: 1, day_date: '2026-08-11', day_category: 'WORKING_DAY', holiday_id: null },
  { week_day_id: 3, week_id: 20, day_index: 2, day_date: '2026-08-12', day_category: 'WORKING_DAY', holiday_id: null },
  { week_day_id: 4, week_id: 20, day_index: 3, day_date: '2026-08-13', day_category: 'WORKING_DAY', holiday_id: null },
  { week_day_id: 5, week_id: 20, day_index: 4, day_date: '2026-08-14', day_category: 'MAKEUP_EXAM', holiday_id: null },
  { week_day_id: 6, week_id: 20, day_index: 5, day_date: '2026-08-15', day_category: 'HOLIDAY', holiday_id: 7 },
  { week_day_id: 7, week_id: 20, day_index: 6, day_date: '2026-08-16', day_category: 'WORKING_DAY', holiday_id: null },
];

const HOLIDAY: GridHoliday = {
  holiday_id: 7,
  holiday_date: '2026-08-15',
  holiday_name: 'Independence Day',
  holiday_type: 'GAZETTED',
  is_optional: false,
};

const SCHEDULE: GridTermSchedule = {
  term_schedule_id: 5,
  calendar_id: 2,
  course_label: 'B.Tech',
  term_commencement_date: '2026-08-03',
  end_of_term_date: '2026-12-18',
  practical_exam_start: '2026-11-02',
  practical_exam_end: '2026-11-07',
  theory_exam_start: '2026-11-30',
  theory_exam_end: '2026-12-14',
};

const INPUT: CalendarExportInput = {
  calendars: [CALENDAR, TERM],
  weeks: [WEEK],
  days: DAYS,
  holidays: [HOLIDAY],
  termSchedules: [SCHEDULE],
  yearLabels: { 1: '2026-27' },
  generatedOn: new Date(2026, 10, 9, 9, 5),
};

describe('the calendar document builders', () => {
  it('packs the model into a real .docx (a zip archive)', async () => {
    const blob = await wordBlob(buildCalendarExport(INPUT));
    const bytes = Buffer.from(await blob.arrayBuffer());

    expect(bytes.subarray(0, 2).toString('latin1')).toBe('PK');
    expect(bytes.byteLength).toBeGreaterThan(1000);
  });

  it('packs the model into a real PDF', async () => {
    const blob = await pdfBlob(buildCalendarExport(INPUT));
    const bytes = Buffer.from(await blob.arrayBuffer());

    expect(bytes.subarray(0, 5).toString('latin1')).toBe('%PDF-');
    expect(bytes.byteLength).toBeGreaterThan(1000);
  });
});
