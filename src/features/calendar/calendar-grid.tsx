import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState } from '@/components/ui/empty-state';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { cn } from '@/lib/utils';
import { formatDate } from '@/lib/format';

export type GridCalendar = {
  calendar_id: number;
  calendar_type: string;
  academic_year_id: number;
  title: string;
  description: string | null;
  start_date: string | null;
  end_date: string | null;
};

export type GridWeek = {
  week_id: number;
  calendar_id: number;
  week_no: number;
  month_label: string;
  week_start_date: string;
  week_end_date: string;
  no_of_working_days: number;
  events: string | null;
};

export type GridDay = {
  week_day_id: number;
  week_id: number;
  day_index: number;
  day_date: string;
  day_category: string;
  holiday_id: number | null;
};

export type GridHoliday = {
  holiday_id: number;
  holiday_date: string;
  holiday_name: string;
  holiday_type: string | null;
  is_optional: boolean | null;
};

export type GridTermSchedule = {
  term_schedule_id: number;
  calendar_id: number;
  course_label: string;
  term_commencement_date: string | null;
  end_of_term_date: string | null;
  practical_exam_start: string | null;
  practical_exam_end: string | null;
  theory_exam_start: string | null;
  theory_exam_end: string | null;
};

const WEEKDAYS = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'] as const;

/** The colour of a day cell, mirroring the printed calendar of events. */
function dayCellClass(category: string): string {
  switch (category) {
    case 'HOLIDAY':
      return 'bg-red-100 text-red-800';
    case 'MARKS_DISPLAY':
      return 'bg-amber-100 text-amber-900';
    case 'REMEDIAL_CLASS':
      return 'bg-sky-100 text-sky-900';
    case 'MAKEUP_EXAM':
      return 'bg-emerald-100 text-emerald-900';
    case 'MINOR_EXAM':
      return 'bg-purple-100 text-purple-900';
    default:
      return '';
  }
}

const LEGEND: { label: string; className: string }[] = [
  { label: 'Holiday', className: 'bg-red-100 text-red-800' },
  { label: 'Marks / attendance display', className: 'bg-amber-100 text-amber-900' },
  { label: 'Remedial classes', className: 'bg-sky-100 text-sky-900' },
  { label: 'Make-up minor exam', className: 'bg-emerald-100 text-emerald-900' },
  { label: 'Minor exam', className: 'bg-purple-100 text-purple-900' },
  { label: 'Working day', className: '' },
];

/** `2026-08-03` -> `3` - the day number the printed calendar shows in each cell. */
function dayNumber(iso: string): number {
  return Number(iso.slice(8, 10));
}

function range(start: string | null, end: string | null): string {
  if (!start) return '—';
  return end ? `${formatDate(start)} – ${formatDate(end)}` : `from ${formatDate(start)}`;
}

function Legend() {
  return (
    <div className="flex flex-wrap items-center gap-2">
      {LEGEND.map((l) => (
        <span
          key={l.label}
          className={cn(
            'inline-flex items-center rounded-full border border-transparent px-2 py-0.5 text-xs font-medium',
            l.className || 'border-border text-muted-foreground',
          )}
        >
          {l.label}
        </span>
      ))}
    </div>
  );
}

function CalendarGrid({
  calendar,
  weeks,
  days,
  holidays,
  yearLabel,
}: {
  calendar: GridCalendar;
  weeks: GridWeek[];
  days: GridDay[];
  holidays: Map<number, GridHoliday>;
  yearLabel: string;
}) {
  const calendarWeeks = weeks
    .filter((w) => w.calendar_id === calendar.calendar_id)
    .sort((a, b) => a.week_no - b.week_no);

  if (calendarWeeks.length === 0) {
    return (
      <EmptyState
        title="No weeks plotted yet"
        description="Add the weeks of the calendar of events through the Manage panel above."
      />
    );
  }

  // The printed calendar totals the working days of every weekday column; the
  // grand total is the sum of the weekly working days.
  const columnTotals = WEEKDAYS.map((_, index) =>
    calendarWeeks.reduce((sum, week) => {
      const day = days.find((d) => d.week_id === week.week_id && d.day_index === index);
      return sum + (day && day.day_category === 'WORKING_DAY' ? 1 : 0);
    }, 0),
  );
  const grandTotal = calendarWeeks.reduce((sum, w) => sum + (w.no_of_working_days || 0), 0);

  return (
    <div className="space-y-3">
      <div>
        <h3 className="text-center text-base font-semibold tracking-tight">{calendar.title}</h3>
        <p className="text-center text-xs text-muted-foreground">
          {calendar.description ?? ''} · Academic year {yearLabel}
          {calendar.start_date && calendar.end_date ? ` · ${formatDate(calendar.start_date)} – ${formatDate(calendar.end_date)}` : ''}
        </p>
      </div>

      <div className="overflow-x-auto">
        <Table className="min-w-[980px] border border-border text-xs">
          <TableHeader>
            <TableRow>
              <TableHead className="border border-border text-center">Week No.</TableHead>
              <TableHead className="border border-border text-center">Month</TableHead>
              {WEEKDAYS.map((d) => (
                <TableHead
                  key={d}
                  className={cn('border border-border text-center', d === 'SUN' && 'bg-muted text-muted-foreground')}
                >
                  {d}
                </TableHead>
              ))}
              <TableHead className="border border-border text-center">No of Working days</TableHead>
              <TableHead className="border border-border text-left">Events</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {calendarWeeks.map((week) => {
              const weekDays = days
                .filter((d) => d.week_id === week.week_id)
                .sort((a, b) => a.day_index - b.day_index);
              return (
                <TableRow key={week.week_id}>
                  <TableCell className="border border-border text-center align-middle font-semibold tabular-nums">
                    {week.week_no}
                  </TableCell>
                  <TableCell className="border border-border text-center align-middle">
                    {week.month_label}
                  </TableCell>
                  {WEEKDAYS.map((_, index) => {
                    const day = weekDays.find((d) => d.day_index === index);
                    if (!day) {
                      return (
                        <TableCell key={index} className="border border-border bg-muted/40 text-center">
                          —
                        </TableCell>
                      );
                    }
                    const holiday = day.holiday_id !== null ? holidays.get(day.holiday_id) : undefined;
                    const name = holiday?.holiday_name ?? '';
                    return (
                      <TableCell
                        key={index}
                        className={cn(
                          'border border-border px-1 py-1 text-center align-top',
                          dayCellClass(day.day_category),
                          index === 6 && day.day_category === 'WORKING_DAY' && 'bg-muted/40',
                        )}
                      >
                        <span className="block font-semibold tabular-nums">{dayNumber(day.day_date)}</span>
                        {name ? <span className="block text-[10px] leading-tight">{name}</span> : null}
                      </TableCell>
                    );
                  })}
                  <TableCell className="border border-border text-center align-middle tabular-nums">
                    {week.no_of_working_days}
                  </TableCell>
                  <TableCell className="border border-border align-top">
                    {week.events ? (
                      <span className="block whitespace-normal">
                        {week.events.split(';').map((e, i) => (
                          <span key={i} className="block">
                            {e.trim()}
                          </span>
                        ))}
                      </span>
                    ) : (
                      <span className="text-muted-foreground">—</span>
                    )}
                  </TableCell>
                </TableRow>
              );
            })}
            <TableRow>
              <TableCell colSpan={2} className="border border-border text-center align-middle font-semibold">
                No of working days
              </TableCell>
              {columnTotals.map((total, index) => (
                <TableCell
                  key={index}
                  className={cn('border border-border text-center font-semibold tabular-nums', index === 6 && 'bg-muted/40')}
                >
                  {total}
                </TableCell>
              ))}
              <TableCell className="border border-border text-center font-semibold tabular-nums">
                {grandTotal}
              </TableCell>
              <TableCell className="border border-border" />
            </TableRow>
          </TableBody>
        </Table>
      </div>

      <Legend />
    </div>
  );
}

function TermSchedule({
  calendar,
  rows,
}: {
  calendar: GridCalendar;
  rows: GridTermSchedule[];
}) {
  return (
    <div className="space-y-3">
      <h3 className="text-center text-base font-semibold tracking-tight">Important dates · {calendar.title}</h3>
      <div className="overflow-x-auto">
        <Table className="min-w-[760px] border border-border text-xs">
          <TableHeader>
            <TableRow>
              <TableHead className="border border-border">Courses</TableHead>
              <TableHead className="border border-border text-center">Term Commencement</TableHead>
              <TableHead className="border border-border text-center">End of term</TableHead>
              <TableHead className="border border-border text-center">Practical Exams</TableHead>
              <TableHead className="border border-border text-center">Theory Exams</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows
              .slice()
              .sort((a, b) => a.course_label.localeCompare(b.course_label))
              .map((row) => (
                <TableRow key={row.term_schedule_id}>
                  <TableCell className="border border-border font-medium">{row.course_label}</TableCell>
                  <TableCell className="border border-border text-center">
                    {row.term_commencement_date ? formatDate(row.term_commencement_date) : '—'}
                  </TableCell>
                  <TableCell className="border border-border text-center">
                    {row.end_of_term_date ? formatDate(row.end_of_term_date) : '—'}
                  </TableCell>
                  <TableCell className="border border-border text-center">
                    {range(row.practical_exam_start, row.practical_exam_end)}
                  </TableCell>
                  <TableCell className="border border-border text-center">
                    {range(row.theory_exam_start, row.theory_exam_end)}
                  </TableCell>
                </TableRow>
              ))}
          </TableBody>
        </Table>
      </div>
    </div>
  );
}

/**
 * The calendar of events, plotted.
 *
 * One grid per ACADEMIC calendar - weeks as rows, the seven weekdays as
 * columns, every day cell coloured by its category and named with its holiday
 * - plus the term schedule of every TERM calendar underneath, mirroring the
 * printed calendar the registrar publishes.
 */
export function CalendarOfEvents({
  calendars,
  weeks,
  days,
  holidays,
  termSchedules,
  yearLabel,
}: {
  calendars: GridCalendar[];
  weeks: GridWeek[];
  days: GridDay[];
  holidays: GridHoliday[];
  termSchedules: GridTermSchedule[];
  yearLabel: (id: number) => string;
}) {
  const holidayById = new Map(holidays.map((h) => [h.holiday_id, h]));
  const academic = calendars.filter((c) => c.calendar_type === 'ACADEMIC');
  const term = calendars.filter((c) => c.calendar_type === 'TERM');

  if (academic.length === 0 && term.length === 0) return null;

  return (
    <Card className="mb-6">
      <CardHeader>
        <CardTitle>Calendar of events</CardTitle>
        <CardDescription>
          Weeks as rows, weekdays as columns, every day coloured by what it is. Edited through the Manage panel
          above.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-8">
        {academic.map((calendar) => (
          <CalendarGrid
            key={calendar.calendar_id}
            calendar={calendar}
            weeks={weeks}
            days={days}
            holidays={holidayById}
            yearLabel={yearLabel(calendar.academic_year_id)}
          />
        ))}

        {academic.length === 0 ? (
          <EmptyState
            title="No academic calendar yet"
            description="Create an ACADEMIC calendar through the Manage panel above, then plot its weeks."
          />
        ) : null}

        {term.map((calendar) => (
          <TermSchedule
            key={calendar.calendar_id}
            calendar={calendar}
            rows={termSchedules.filter((r) => r.calendar_id === calendar.calendar_id)}
          />
        ))}

        {term.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            The term schedule (term commencement, end of term and examination dates per course) appears here once a
            TERM calendar exists.
          </p>
        ) : null}

        <p className="text-xs text-muted-foreground">
          Every date cell carries its category as a badge:{' '}
          <Badge variant="destructive">Holiday</Badge> <Badge variant="warning">Marks display</Badge>{' '}
          <Badge variant="info">Remedial</Badge> <Badge variant="success">Make-up exam</Badge> and the minor exam
          days are shaded purple.
        </p>
      </CardContent>
    </Card>
  );
}
