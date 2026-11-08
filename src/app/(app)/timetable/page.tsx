import { PageHeader, StatTile } from '@/components/page-header';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { AdminTableEditor } from '@/features/admin/admin-table-editor';
import { DAY_LABELS, safeRpcRows, shortTime } from '@/features/academic/data';
import { GenerateSessionsButton, OfferingPicker, SectionAssignments } from '@/features/timetable/timetable-client';
import type {
  Room,
  TimeSlot,
  TimetableEntry,
  TimetableOffering,
  TimetableSection,
} from '@/features/timetable/types';
import { formatNumber } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

const DAYS = [1, 2, 3, 4, 5, 6, 7];

type OfferingInfo = {
  programme_term_offering_id: number;
  term_name: string;
  programme_name: string;
  semester_name: string;
};

function idParam(value: string | string[] | undefined): number | null {
  const raw = Array.isArray(value) ? value[0] : value;
  if (!raw || !/^\d+$/.test(raw)) return null;
  const n = Number(raw);
  return Number.isSafeInteger(n) ? n : null;
}

export default async function TimetablePage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { supabase } = await requireContext();
  const sp = await searchParams;
  const offeringId = idParam(sp.pto);

  const [offerings, slots, rooms] = await Promise.all([
    safeRpcRows<TimetableOffering>(supabase, 'timetable_offerings', { p_limit: 100, p_offset: 0 }),
    safeRpcRows<TimeSlot>(supabase, 'timetable_slots'),
    safeRpcRows<Room>(supabase, 'timetable_rooms'),
  ]);

  const [info, sections, entries] = await Promise.all([
    offeringId === null
      ? Promise.resolve({ data: [] as OfferingInfo[], error: null })
      : safeRpcRows<OfferingInfo>(supabase, 'timetable_offering_info', { p_pto: offeringId }),
    offeringId === null
      ? Promise.resolve({ data: [] as TimetableSection[], error: null })
      : safeRpcRows<TimetableSection>(supabase, 'timetable_sections', { p_pto: offeringId }),
    offeringId === null
      ? Promise.resolve({ data: [] as TimetableEntry[], error: null })
      : safeRpcRows<TimetableEntry>(supabase, 'timetable_entries', { p_pto: offeringId }),
  ]);

  const offering = info.data[0] ?? null;

  // Build the weekly grid: one row per time slot, one column per ISO weekday.
  const slotById = new Map<number, TimeSlot>();
  for (const s of slots.data) slotById.set(Number(s.time_slot_id), s);
  const slotIds = new Set<number>();
  for (const s of slots.data) slotIds.add(Number(s.time_slot_id));
  for (const e of entries.data) slotIds.add(Number(e.time_slot_id));

  const gridRows = [...slotIds]
    .map((id) => {
      const slot = slotById.get(id);
      const fallback = entries.data.find((e) => Number(e.time_slot_id) === id);
      return {
        time_slot_id: id,
        slot_code: slot?.slot_code ?? fallback?.slot_code ?? String(id),
        start_time: slot?.start_time ?? fallback?.start_time ?? '',
        end_time: slot?.end_time ?? fallback?.end_time ?? '',
        is_break: slot?.is_break ?? false,
      };
    })
    .sort((a, b) => a.start_time.localeCompare(b.start_time) || a.slot_code.localeCompare(b.slot_code));

  return (
    <>
      <PageHeader
        title="Timetable"
        description="The weekly teaching plan for each programme term offering."
      />

      <AdminTableEditor
        tables={['time_slot', 'room']}
        title="Manage the timetable"
        description="Add, edit and remove the teaching time slots and the rooms the weekly grid is built from. Every change is written through the database and audited."
      />

      <Card>
        <CardHeader>
          <CardTitle>Term offering</CardTitle>
          <CardDescription>Pick the offering whose weekly timetable you want to see.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <OfferingPicker offerings={offerings.data} selectedId={offeringId} />
          {offering && (
            <div className="flex flex-wrap items-center gap-3 text-sm">
              <span className="font-medium">{offering.term_name}</span>
              <span className="text-muted-foreground">
                {offering.programme_name} · {offering.semester_name}
              </span>
            </div>
          )}
          {offerings.error && <ErrorPanel message={`The timetable could not be read: ${offerings.error}`} />}
        </CardContent>
      </Card>

      {offeringId !== null && (
        <>
          <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <StatTile label="Teaching sections" value={formatNumber(sections.data.length)} />
            <StatTile label="Weekly entries" value={formatNumber(entries.data.length)} />
            <StatTile label="Time slots" value={formatNumber(gridRows.length)} />
            <StatTile label="Rooms" value={formatNumber(rooms.data.length)} />
          </div>

          {entries.error && (
            <div className="mt-6">
              <ErrorPanel message={`The weekly grid could not be read: ${entries.error}`} />
            </div>
          )}

          <Card className="mt-6">
            <CardHeader>
              <CardTitle>Weekly grid</CardTitle>
              <CardDescription>Slots across the top, days down the side.</CardDescription>
            </CardHeader>
            <CardContent>
              {entries.data.length === 0 ? (
                <EmptyState
                  title="No timetable entries"
                  description="Nothing has been scheduled for this offering yet."
                />
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead className="w-32">Slot</TableHead>
                      {DAYS.map((d) => (
                        <TableHead key={d} className="min-w-40">
                          {DAY_LABELS[d] ?? `Day ${d}`}
                        </TableHead>
                      ))}
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {gridRows.map((row) => (
                      <TableRow key={row.time_slot_id}>
                        <TableCell>
                          <div className="font-medium">{row.slot_code}</div>
                          <div className="text-xs text-muted-foreground">
                            {shortTime(row.start_time)} – {shortTime(row.end_time)}
                          </div>
                        </TableCell>
                        {DAYS.map((day) => {
                          const cell = entries.data.filter(
                            (e) => Number(e.day_of_week) === day && Number(e.time_slot_id) === row.time_slot_id,
                          );
                          return (
                            <TableCell key={day} className="align-top">
                              {cell.length === 0 ? (
                                <span className="text-xs text-muted-foreground">—</span>
                              ) : (
                                <ul className="space-y-2">
                                  {cell.map((e) => (
                                    <li key={e.timetable_session_id} className="rounded-md border border-border p-2">
                                      <div className="text-xs font-medium">{e.course_label}</div>
                                      <div className="text-xs text-muted-foreground">
                                        {e.section_code}
                                        {e.batch_code ? ` · ${e.batch_code}` : ''} · {e.session_type}
                                      </div>
                                      <div className="text-xs text-muted-foreground">
                                        {e.instructor_name ?? 'Unassigned'}
                                        {e.room_label ? ` · ${e.room_label}` : ''}
                                      </div>
                                    </li>
                                  ))}
                                </ul>
                              )}
                            </TableCell>
                          );
                        })}
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>

          <Card className="mt-6">
            <CardHeader>
              <CardTitle>Teaching sections</CardTitle>
              <CardDescription>Generate the class sessions each section runs from this timetable.</CardDescription>
            </CardHeader>
            <CardContent>
              {sections.data.length === 0 ? (
                <EmptyState title="No teaching sections" description="This offering has no sections yet." />
              ) : (
                <ul className="space-y-4">
                  {sections.data.map((s) => (
                    <li key={s.course_offering_section_id} className="rounded-lg border border-border p-4">
                      <div className="flex flex-wrap items-center justify-between gap-2">
                        <div>
                          <div className="text-sm font-medium">{s.course_label}</div>
                          <div className="text-xs text-muted-foreground">
                            {s.section_code}
                            {s.batch_code ? ` · ${s.batch_code}` : ''} · {s.session_type}
                          </div>
                        </div>
                        <Badge variant={statusVariant(s.session_type)}>{s.session_type}</Badge>
                      </div>
                      <div className="mt-3">
                        <GenerateSessionsButton sectionId={s.course_offering_section_id} label={s.section_code} />
                      </div>
                      <div className="mt-3">
                        <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Faculty</p>
                        <div className="mt-1">
                          <SectionAssignments sectionId={s.course_offering_section_id} />
                        </div>
                      </div>
                    </li>
                  ))}
                </ul>
              )}
            </CardContent>
          </Card>
        </>
      )}

      <div className="mt-6 grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Time slots</CardTitle>
            <CardDescription>The slots you may schedule into.</CardDescription>
          </CardHeader>
          <CardContent>
            {slots.data.length === 0 ? (
              <EmptyState title="No time slots" />
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Slot</TableHead>
                    <TableHead>Campus</TableHead>
                    <TableHead>Time</TableHead>
                    <TableHead>Break</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {slots.data.map((s) => (
                    <TableRow key={s.time_slot_id}>
                      <TableCell>{s.slot_code}</TableCell>
                      <TableCell>{s.campus_name}</TableCell>
                      <TableCell>
                        {shortTime(s.start_time)} – {shortTime(s.end_time)}
                      </TableCell>
                      <TableCell>{s.is_break ? 'Yes' : 'No'}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Rooms</CardTitle>
            <CardDescription>Rooms available for teaching.</CardDescription>
          </CardHeader>
          <CardContent>
            {rooms.data.length === 0 ? (
              <EmptyState title="No rooms" />
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Room</TableHead>
                    <TableHead>Campus</TableHead>
                    <TableHead>Type</TableHead>
                    <TableHead className="text-right">Capacity</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {rooms.data.map((r) => (
                    <TableRow key={r.room_id}>
                      <TableCell>{r.room_label}</TableCell>
                      <TableCell>{r.campus_name}</TableCell>
                      <TableCell>{r.room_type}</TableCell>
                      <TableCell className="text-right tabular-nums">{formatNumber(r.capacity)}</TableCell>
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
