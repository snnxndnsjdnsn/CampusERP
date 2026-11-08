import { PageHeader, StatTile } from '@/components/page-header';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { AdminTableEditor } from '@/features/admin/admin-table-editor';
import {
  loadAcademicTerms,
  loadAcademicYears,
  loadHolidays,
  loadSemesters,
  loadTimeSlots,
} from '@/features/calendar/calendar-data';
import { distinctValues, filterByQuery } from '@/features/shared/filter';
import { readTable } from '@/features/shared/reads';
import { SearchForm } from '@/features/shared/search-form';
import { formatDate, formatNumber } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

type SearchParams = Promise<Record<string, string | string[] | undefined>>;

type CampusRow = { campus_id: number; campus_name: string };

function first(value: string | string[] | undefined): string {
  if (Array.isArray(value)) return value[0] ?? '';
  return value ?? '';
}

/**
 * Module 3 · Academic calendar.
 *
 * Every table here is read straight from the database through RLS, so a caller
 * only ever sees the years, terms and slots their role allows.
 */
export default async function CalendarPage({ searchParams }: { searchParams: SearchParams }) {
  const { supabase } = await requireContext();
  const sp = await searchParams;
  const q = first(sp.q);
  const status = first(sp.status).toUpperCase();

  const [years, terms, semesters, slots, holidays, campuses] = await Promise.all([
    loadAcademicYears(supabase),
    loadAcademicTerms(supabase),
    loadSemesters(supabase),
    loadTimeSlots(supabase),
    loadHolidays(supabase),
    readTable<CampusRow>(supabase, 'campus', 'campus_id, campus_name', { order: { column: 'campus_name' } }),
  ]);

  const errors = [years, terms, semesters, slots, campuses].map((r) => r.error).filter((e): e is string => Boolean(e));

  const yearLabel = (id: number) => years.data.find((y) => y.academic_year_id === id)?.year_code ?? `#${id}`;
  const campusLabel = (id: number) => campuses.data.find((c) => c.campus_id === id)?.campus_name ?? `#${id}`;

  const visibleYears = filterByQuery(
    years.data.filter((y) => !status || y.status.toUpperCase() === status),
    q,
    (y) => [y.year_code, y.status],
  );
  const visibleTerms = filterByQuery(
    terms.data.filter((t) => !status || t.status.toUpperCase() === status),
    q,
    (t) => [t.term_code, t.term_name, t.term_type, t.status, yearLabel(t.academic_year_id)],
  );
  const visibleSemesters = filterByQuery(semesters.data, q, (s) => [s.semester_name, s.semester_number]);
  const visibleSlots = filterByQuery(slots.data, q, (s) => [s.slot_code, campusLabel(s.campus_id)]);
  const visibleHolidays = filterByQuery(holidays.data, q, (h) => [h.holiday_name, h.holiday_date, h.holiday_type]);

  const statusOptions = distinctValues([...years.data, ...terms.data], (r) => r.status).map((s) => ({
    value: s,
    label: s,
  }));

  return (
    <>
      <PageHeader
        title="Academic calendar"
        description="Academic years, terms, semesters and the daily teaching slots that the timetable is built from."
      />

      {errors.length > 0 ? <ErrorPanel message={errors.join(' · ')} /> : null}

      <AdminTableEditor
        tables={['academic_year', 'academic_term', 'semester', 'time_slot']}
        title="Manage the calendar"
        description="Add, edit and remove the academic years, terms, semesters and teaching slots behind this screen. Every change is written through the database and audited."
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatTile label="Academic years" value={formatNumber(years.data.length)} />
        <StatTile label="Terms" value={formatNumber(terms.data.length)} />
        <StatTile label="Semesters" value={formatNumber(semesters.data.length)} />
        <StatTile label="Teaching slots" value={formatNumber(slots.data.length)} />
      </div>

      <div className="mb-6">
        <SearchForm
          action="/calendar"
          query={q}
          placeholder="Year code, term name, slot…"
          filters={[{ name: 'status', label: 'Status', value: status, options: statusOptions }]}
        />
      </div>

      <div className="space-y-4">
        <Card>
          <CardHeader>
            <CardTitle>Academic years</CardTitle>
            <CardDescription>{visibleYears.length} of {years.data.length} years</CardDescription>
          </CardHeader>
          <CardContent>
            {visibleYears.length === 0 ? (
              <EmptyState title="No academic years to show" description="Adjust the filters, or ask the academic office to publish a year." />
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Year code</TableHead>
                    <TableHead>Starts</TableHead>
                    <TableHead>Ends</TableHead>
                    <TableHead>Status</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {visibleYears.map((y) => (
                    <TableRow key={y.academic_year_id}>
                      <TableCell className="font-medium">{y.year_code}</TableCell>
                      <TableCell>{formatDate(y.start_date)}</TableCell>
                      <TableCell>{formatDate(y.end_date)}</TableCell>
                      <TableCell>
                        <Badge variant={statusVariant(y.status)}>{y.status}</Badge>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Terms</CardTitle>
            <CardDescription>{visibleTerms.length} of {terms.data.length} terms</CardDescription>
          </CardHeader>
          <CardContent>
            {visibleTerms.length === 0 ? (
              <EmptyState title="No terms to show" description="Terms appear here once the academic office schedules them." />
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Term</TableHead>
                    <TableHead>Year</TableHead>
                    <TableHead>Type</TableHead>
                    <TableHead>Runs</TableHead>
                    <TableHead>Registration</TableHead>
                    <TableHead>Status</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {visibleTerms.map((t) => (
                    <TableRow key={t.academic_term_id}>
                      <TableCell>
                        <div className="font-medium">{t.term_name}</div>
                        <div className="text-xs text-muted-foreground">{t.term_code}</div>
                      </TableCell>
                      <TableCell>{yearLabel(t.academic_year_id)}</TableCell>
                      <TableCell>{t.term_type}</TableCell>
                      <TableCell>
                        {formatDate(t.start_date)} – {formatDate(t.end_date)}
                      </TableCell>
                      <TableCell>
                        {t.registration_start_date || t.registration_end_date
                          ? `${formatDate(t.registration_start_date)}${
                              t.registration_end_date ? ` – ${formatDate(t.registration_end_date)}` : ''
                            }`
                          : '—'}
                      </TableCell>
                      <TableCell>
                        <Badge variant={statusVariant(t.status)}>{t.status}</Badge>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>

        <div className="grid gap-4 lg:grid-cols-2">
          <Card>
            <CardHeader>
              <CardTitle>Semesters</CardTitle>
              <CardDescription>{visibleSemesters.length} of {semesters.data.length} semesters</CardDescription>
            </CardHeader>
            <CardContent>
              {visibleSemesters.length === 0 ? (
                <EmptyState title="No semesters to show" />
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead className="text-right">Number</TableHead>
                      <TableHead>Name</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {visibleSemesters.map((s) => (
                      <TableRow key={s.semester_id}>
                        <TableCell className="text-right tabular-nums">{s.semester_number}</TableCell>
                        <TableCell>{s.semester_name}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Teaching time slots</CardTitle>
              <CardDescription>{visibleSlots.length} of {slots.data.length} slots</CardDescription>
            </CardHeader>
            <CardContent>
              {visibleSlots.length === 0 ? (
                <EmptyState title="No time slots to show" description="Slots are defined per campus." />
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Slot</TableHead>
                      <TableHead>Campus</TableHead>
                      <TableHead>Time</TableHead>
                      <TableHead>Kind</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {visibleSlots.map((s) => (
                      <TableRow key={s.time_slot_id}>
                        <TableCell className="font-medium">{s.slot_code}</TableCell>
                        <TableCell>{campusLabel(s.campus_id)}</TableCell>
                        <TableCell>
                          {String(s.start_time).slice(0, 5)} – {String(s.end_time).slice(0, 5)}
                        </TableCell>
                        <TableCell>
                          <div className="flex gap-1">
                            {s.is_break ? <Badge variant="warning">Break</Badge> : null}
                            <Badge variant={s.is_active ? statusVariant('ACTIVE') : statusVariant('INACTIVE')}>
                              {s.is_active ? 'ACTIVE' : 'INACTIVE'}
                            </Badge>
                          </div>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Holidays</CardTitle>
            <CardDescription>
              {holidays.error
                ? 'The holiday calendar is not published in this deployment.'
                : `${visibleHolidays.length} of ${holidays.data.length} holidays`}
            </CardDescription>
          </CardHeader>
          <CardContent>
            {holidays.error ? (
              <p className="text-sm text-muted-foreground">
                This deployment has no holiday table, so no holiday list can be shown. The academic years, terms, semesters and
                teaching slots above are the complete module 3 calendar.
              </p>
            ) : visibleHolidays.length === 0 ? (
              <EmptyState title="No holidays to show" description="Publish a holiday list to see it here." />
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Date</TableHead>
                    <TableHead>Holiday</TableHead>
                    <TableHead>Type</TableHead>
                    <TableHead>Optional</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {visibleHolidays.map((h) => (
                    <TableRow key={h.holiday_id}>
                      <TableCell>{formatDate(h.holiday_date)}</TableCell>
                      <TableCell className="font-medium">{h.holiday_name}</TableCell>
                      <TableCell>{h.holiday_type ?? '—'}</TableCell>
                      <TableCell>{h.is_optional === null ? '—' : h.is_optional ? 'Yes' : 'No'}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>
      </div>
    </>
  );
}
