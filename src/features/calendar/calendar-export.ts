import { formatDate, formatDateTime } from '@/lib/format';
import type { GridCalendar, GridDay, GridHoliday, GridTermSchedule, GridWeek } from './calendar-grid';

/** Module 3 · the model behind the calendar of events' Word and PDF downloads.
 *
 * The model is plain serialisable data - one grid per ACADEMIC calendar (the
 * same weeks, cells and totals the page prints), the term schedule of every
 * TERM calendar and the legend. `calendar-documents.ts` renders it twice, and
 * `tests/unit/calendar-export.test.ts` asserts it against the printed grid so
 * the documents can never drift from what the screen shows.
 */

export const WEEKDAYS = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'] as const;

/** The background of each day category.
 *
 * The tailwind `*-100` shades `dayCellClass` paints the printed grid with, as
 * hex, so both documents carry exactly the colours the screen shows.
 */
const CATEGORY_FILL = {
  HOLIDAY: '#FEE2E2',
  MARKS_DISPLAY: '#FEF3C7',
  REMEDIAL_CLASS: '#E0F2FE',
  MAKEUP_EXAM: '#D1FAE5',
  MINOR_EXAM: '#F3E8FF',
} satisfies Record<string, string>;

/** What an empty ("—") cell and a Sunday working cell print with (`bg-muted/40`). */
export const MUTED_FILL = '#F3F4F6';

/** The legend of the printed grid, in order, as (label, background) pairs. */
export const EXPORT_LEGEND: { label: string; fill: string | null }[] = [
  { label: 'Holiday', fill: CATEGORY_FILL.HOLIDAY },
  { label: 'Marks / attendance display', fill: CATEGORY_FILL.MARKS_DISPLAY },
  { label: 'Remedial classes', fill: CATEGORY_FILL.REMEDIAL_CLASS },
  { label: 'Make-up minor exam', fill: CATEGORY_FILL.MAKEUP_EXAM },
  { label: 'Minor exam', fill: CATEGORY_FILL.MINOR_EXAM },
  { label: 'Working day', fill: null },
];

/** One day cell of the grid; `null` in a week means the cell prints "—". */
export type ExportDay = {
  dayIndex: number;
  /** The ISO date, `2026-08-15`. */
  date: string;
  /** The day number the printed calendar shows in the cell. */
  dayNumber: number;
  category: string;
  holidayName: string | null;
  /** The background as `#RRGGBB`; `null` for an ordinary working day. */
  fill: string | null;
};

export type ExportWeek = {
  weekNo: number;
  monthLabel: string;
  workingDays: number;
  /** The events column, split on `;` and trimmed. */
  events: string[];
  /** Always seven entries (MON..SUN); `null` where the printed cell shows "—". */
  cells: (ExportDay | null)[];
};

export type ExportGrid = {
  calendarId: number;
  title: string;
  subtitle: string;
  /** Sorted by week number, like the printed grid. */
  weeks: ExportWeek[];
  /** Working days per weekday column. */
  columnTotals: number[];
  grandTotal: number;
};

export type ExportTermRow = {
  courseLabel: string;
  commencement: string;
  endOfTerm: string;
  practical: string;
  theory: string;
};

export type ExportTermTable = {
  title: string;
  rows: ExportTermRow[];
};

export type CalendarExport = {
  title: string;
  generatedOn: string;
  grids: ExportGrid[];
  termTables: ExportTermTable[];
  legend: { label: string; fill: string | null }[];
};

export type CalendarExportInput = {
  calendars: GridCalendar[];
  weeks: GridWeek[];
  days: GridDay[];
  holidays: GridHoliday[];
  termSchedules: GridTermSchedule[];
  /** Academic-year id -> label (the page's `year_code`), serialisable. */
  yearLabels: Record<number, string>;
  /** Injected by the unit test; the buttons pass the download moment. */
  generatedOn?: Date;
};

/** The background of one day, mirroring `dayCellClass` in `calendar-grid.tsx`. */
function dayFill(day: GridDay): string | null {
  switch (day.day_category) {
    case 'HOLIDAY':
      return CATEGORY_FILL.HOLIDAY;
    case 'MARKS_DISPLAY':
      return CATEGORY_FILL.MARKS_DISPLAY;
    case 'REMEDIAL_CLASS':
      return CATEGORY_FILL.REMEDIAL_CLASS;
    case 'MAKEUP_EXAM':
      return CATEGORY_FILL.MAKEUP_EXAM;
    case 'MINOR_EXAM':
      return CATEGORY_FILL.MINOR_EXAM;
    case 'WORKING_DAY':
      // Sunday is shaded as soon as it counts as a working day.
      return day.day_index === 6 ? MUTED_FILL : null;
    default:
      return null;
  }
}

/** `2026-08-03` -> `3` - the day number the printed calendar shows. */
function dayNumber(iso: string): number {
  return Number(iso.slice(8, 10));
}

/** The important-dates cell wording, `01 Aug 2026 – 10 Aug 2026`. */
function dateRange(start: string | null, end: string | null): string {
  if (!start) return '—';
  return end ? `${formatDate(start)} – ${formatDate(end)}` : `from ${formatDate(start)}`;
}

/** Build the export model from exactly what the calendar page renders. */
export function buildCalendarExport({
  calendars,
  weeks,
  days,
  holidays,
  termSchedules,
  yearLabels,
  generatedOn,
}: CalendarExportInput): CalendarExport {
  const holidayById = new Map(holidays.map((h) => [h.holiday_id, h]));
  const academic = calendars.filter((c) => c.calendar_type === 'ACADEMIC');
  const term = calendars.filter((c) => c.calendar_type === 'TERM');

  const grids: ExportGrid[] = [];
  for (const calendar of academic) {
    const calendarWeeks = weeks
      .filter((w) => w.calendar_id === calendar.calendar_id)
      .sort((a, b) => a.week_no - b.week_no);

    // A calendar with no weeks plots the page's empty state, not a grid.
    if (calendarWeeks.length === 0) continue;

    const exportWeeks: ExportWeek[] = calendarWeeks.map((week) => {
      const weekDays = days.filter((d) => d.week_id === week.week_id);
      return {
        weekNo: week.week_no,
        monthLabel: week.month_label,
        workingDays: week.no_of_working_days,
        events: week.events
          ? week.events
              .split(';')
              .map((e) => e.trim())
              .filter(Boolean)
          : [],
        cells: WEEKDAYS.map((_, index) => {
          const day = weekDays.find((d) => d.day_index === index);
          if (!day) return null;
          const holiday = day.holiday_id !== null ? holidayById.get(day.holiday_id) : undefined;
          return {
            dayIndex: index,
            date: day.day_date,
            dayNumber: dayNumber(day.day_date),
            category: day.day_category,
            holidayName: holiday?.holiday_name ?? null,
            fill: dayFill(day),
          };
        }),
      };
    });

    // The printed calendar totals the working days of every weekday column;
    // the grand total is the sum of the weekly working days.
    const columnTotals = WEEKDAYS.map((_, index) =>
      calendarWeeks.reduce((sum, week) => {
        const day = days.find((d) => d.week_id === week.week_id && d.day_index === index);
        return sum + (day && day.day_category === 'WORKING_DAY' ? 1 : 0);
      }, 0),
    );
    const grandTotal = calendarWeeks.reduce((sum, w) => sum + (w.no_of_working_days || 0), 0);

    const subtitle = [
      calendar.description ?? '',
      `Academic year ${yearLabels[calendar.academic_year_id] ?? `#${calendar.academic_year_id}`}`,
      calendar.start_date && calendar.end_date
        ? `${formatDate(calendar.start_date)} – ${formatDate(calendar.end_date)}`
        : '',
    ]
      .filter(Boolean)
      .join(' · ');

    grids.push({
      calendarId: calendar.calendar_id,
      title: calendar.title,
      subtitle,
      weeks: exportWeeks,
      columnTotals,
      grandTotal,
    });
  }

  const termTables: ExportTermTable[] = term.map((calendar) => ({
    title: `Important dates · ${calendar.title}`,
    rows: termSchedules
      .filter((r) => r.calendar_id === calendar.calendar_id)
      .slice()
      .sort((a, b) => a.course_label.localeCompare(b.course_label))
      .map((row) => ({
        courseLabel: row.course_label,
        commencement: formatDate(row.term_commencement_date),
        endOfTerm: formatDate(row.end_of_term_date),
        practical: dateRange(row.practical_exam_start, row.practical_exam_end),
        theory: dateRange(row.theory_exam_start, row.theory_exam_end),
      })),
  }));

  return {
    title: 'Calendar of events',
    generatedOn: formatDateTime(generatedOn ?? new Date()),
    grids,
    termTables,
    legend: EXPORT_LEGEND,
  };
}
