import { describe, expect, it } from 'vitest';
import {
  EXPORT_LEGEND,
  MUTED_FILL,
  buildCalendarExport,
  type CalendarExportInput,
} from '@/features/calendar/calendar-export';
import type {
  GridCalendar,
  GridDay,
  GridHoliday,
  GridTermSchedule,
  GridWeek,
} from '@/features/calendar/calendar-grid';

/**
 * The downloads must carry exactly what the printed calendar shows: the same
 * weeks (in week order), the same seven cells per week with the same category
 * colours, the same working-day totals, the same events and the same term
 * dates. The fixtures below are shaped like the rows `calendar-data.ts` reads,
 * and every expectation mirrors a line of `calendar-grid.tsx`.
 */

const ACADEMIC: GridCalendar = {
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

/** Deliberately out of week order: the model must sort them. */
const WEEK_2: GridWeek = {
  week_id: 20,
  calendar_id: 1,
  week_no: 2,
  month_label: 'August 2026',
  week_start_date: '2026-08-10',
  week_end_date: '2026-08-16',
  no_of_working_days: 6,
  events: ' Orientation week ; Registration ',
};

const WEEK_1: GridWeek = {
  week_id: 10,
  calendar_id: 1,
  week_no: 1,
  month_label: 'August 2026',
  week_start_date: '2026-08-03',
  week_end_date: '2026-08-09',
  no_of_working_days: 5,
  events: null,
};

function day(
  weekId: number,
  index: number,
  date: string,
  category: string,
  holidayId: number | null = null,
): GridDay {
  return {
    week_day_id: weekId * 10 + index,
    week_id: weekId,
    day_index: index,
    day_date: date,
    day_category: category,
    holiday_id: holidayId,
  };
}

/** Week 2 plots every day; week 1 plots only its minor exam on Wednesday. */
const DAYS: GridDay[] = [
  day(10, 2, '2026-08-05', 'MINOR_EXAM'),
  day(20, 0, '2026-08-10', 'WORKING_DAY'),
  day(20, 1, '2026-08-11', 'MARKS_DISPLAY'),
  day(20, 2, '2026-08-12', 'WORKING_DAY'),
  day(20, 3, '2026-08-13', 'REMEDIAL_CLASS'),
  day(20, 4, '2026-08-14', 'MAKEUP_EXAM'),
  day(20, 5, '2026-08-15', 'HOLIDAY', 7),
  day(20, 6, '2026-08-16', 'WORKING_DAY'),
];

const HOLIDAY: GridHoliday = {
  holiday_id: 7,
  holiday_date: '2026-08-15',
  holiday_name: 'Independence Day',
  holiday_type: 'GAZETTED',
  is_optional: false,
};

const BTECH_SCHEDULE: GridTermSchedule = {
  term_schedule_id: 5,
  calendar_id: 2,
  course_label: 'B.Tech',
  term_commencement_date: '2026-08-03',
  end_of_term_date: '2026-12-18',
  practical_exam_start: '2026-11-02',
  practical_exam_end: '2026-11-07',
  theory_exam_start: '2026-11-30',
  theory_exam_end: null,
};

const MTECH_SCHEDULE: GridTermSchedule = {
  term_schedule_id: 6,
  calendar_id: 2,
  course_label: 'M.Tech',
  term_commencement_date: null,
  end_of_term_date: null,
  practical_exam_start: null,
  practical_exam_end: null,
  theory_exam_start: null,
  theory_exam_end: null,
};

function input(overrides: Partial<CalendarExportInput> = {}): CalendarExportInput {
  return {
    calendars: [ACADEMIC, TERM],
    weeks: [WEEK_2, WEEK_1],
    days: DAYS,
    holidays: [HOLIDAY],
    termSchedules: [BTECH_SCHEDULE, MTECH_SCHEDULE],
    yearLabels: { 1: '2026-27' },
    generatedOn: new Date(2026, 10, 9, 9, 5),
    ...overrides,
  };
}

describe('buildCalendarExport', () => {
  it('sorts the weeks and gives every week its seven day cells', () => {
    const model = buildCalendarExport(input());

    expect(model.title).toBe('Calendar of events');
    expect(model.grids).toHaveLength(1);

    const grid = model.grids[0]!;
    expect(grid.title).toBe('B.Tech calendar 2026-27');
    expect(grid.subtitle).toBe('Plotted weeks · Academic year 2026-27 · 01 Aug 2026 – 31 Jul 2027');
    expect(grid.weeks.map((w) => w.weekNo)).toEqual([1, 2]);

    // Week 1 plots Wednesday only - the other six cells print "—".
    const week1 = grid.weeks[0]!;
    expect(week1.cells).toHaveLength(7);
    expect(week1.cells.filter(Boolean)).toHaveLength(1);
    expect(week1.cells[0]).toBeNull();
    expect(week1.cells[2]).toMatchObject({
      dayIndex: 2,
      date: '2026-08-05',
      dayNumber: 5,
      category: 'MINOR_EXAM',
      holidayName: null,
    });

    // Week 2 plots all seven days.
    const week2 = grid.weeks[1]!;
    expect(week2.cells.filter(Boolean)).toHaveLength(7);
    expect(week2.cells[0]).toMatchObject({ date: '2026-08-10', dayNumber: 10 });
  });

  it('shades each cell with the colour the printed grid uses', () => {
    const grid = buildCalendarExport(input()).grids[0]!;
    const week1 = grid.weeks[0]!;
    const week2 = grid.weeks[1]!;

    // Mirrors dayCellClass: minor exam purple, holiday red, Sunday muted.
    expect(week1.cells[2]?.fill).toBe('#F3E8FF');
    expect(week2.cells.map((cell) => cell?.fill ?? null)).toEqual([
      null, // an ordinary Monday working day
      '#FEF3C7', // MARKS_DISPLAY - amber
      null, // Wednesday working day
      '#E0F2FE', // REMEDIAL_CLASS - sky
      '#D1FAE5', // MAKEUP_EXAM - emerald
      '#FEE2E2', // HOLIDAY - red, with the holiday's name
      MUTED_FILL, // Sunday counts as working, so it takes the muted fill
    ]);
    expect(week2.cells[5]?.category).toBe('HOLIDAY');
    expect(week2.cells[5]?.holidayName).toBe('Independence Day');
  });

  it('totals the working days like the printed footer row', () => {
    const grid = buildCalendarExport(input()).grids[0]!;

    // Only WORKING_DAY cells count: Mon and Wed of week 2, Sunday of week 2.
    expect(grid.columnTotals).toEqual([1, 0, 1, 0, 0, 0, 1]);
    // The grand total sums the weekly counts the page prints.
    expect(grid.grandTotal).toBe(11);
    expect(grid.weeks.map((w) => w.workingDays)).toEqual([5, 6]);
  });

  it('splits the events column on semicolons and trims each entry', () => {
    const grid = buildCalendarExport(input()).grids[0]!;

    expect(grid.weeks[0]?.events).toEqual([]);
    expect(grid.weeks[1]?.events).toEqual(['Orientation week', 'Registration']);
  });

  it('keeps the term calendars out of the grids and in their own tables', () => {
    const model = buildCalendarExport(input());

    expect(model.grids.map((g) => g.calendarId)).toEqual([1]);
    expect(model.termTables).toHaveLength(1);

    const table = model.termTables[0]!;
    expect(table.title).toBe('Important dates · Odd term 2026-27');
    expect(table.rows.map((r) => r.courseLabel)).toEqual(['B.Tech', 'M.Tech']);

    const btech = table.rows[0]!;
    expect(btech.commencement).toBe('03 Aug 2026');
    expect(btech.endOfTerm).toBe('18 Dec 2026');
    expect(btech.practical).toBe('02 Nov 2026 – 07 Nov 2026');
    expect(btech.theory).toBe('from 30 Nov 2026'); // open-ended range

    // An unpopulated schedule prints em dashes, not "null".
    expect(table.rows[1]).toEqual({
      courseLabel: 'M.Tech',
      commencement: '—',
      endOfTerm: '—',
      practical: '—',
      theory: '—',
    });
  });

  it('records when it was generated and carries the legend', () => {
    const model = buildCalendarExport(input());

    expect(model.generatedOn).toBe('09 Nov 2026, 09:05');
    expect(model.legend).toEqual(EXPORT_LEGEND);
    expect(model.legend.map((l) => l.label)).toEqual([
      'Holiday',
      'Marks / attendance display',
      'Remedial classes',
      'Make-up minor exam',
      'Minor exam',
      'Working day',
    ]);
    expect(model.legend.at(-1)?.fill).toBeNull();
  });

  it('leaves out a calendar that has no weeks plotted yet', () => {
    const model = buildCalendarExport(input({ weeks: [] }));

    expect(model.grids).toEqual([]);
    expect(model.termTables).toHaveLength(1);
  });

  it('omits a blank description from the subtitle', () => {
    const model = buildCalendarExport(
      input({
        calendars: [{ ...ACADEMIC, description: null }],
      }),
    );

    expect(model.grids[0]?.subtitle).toBe(
      'Academic year 2026-27 · 01 Aug 2026 – 31 Jul 2027',
    );
  });
});
