import { PageHeader, StatTile } from '@/components/page-header';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { safeRpcRows, safeSelect, shortTime } from '@/features/academic/data';
import {
  EventPicker,
  MarksEntryForm,
  OfferingPicker,
  PublishEventButton,
} from '@/features/assessment/assessment-client';
import type {
  AssessmentEventRow,
  AssessmentOffering,
  AssessmentOfferingInfo,
  AssessmentSheetRow,
} from '@/features/assessment/types';
import { formatDate, formatNumber } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

function idParam(value: string | string[] | undefined): number | null {
  const raw = Array.isArray(value) ? value[0] : value;
  if (!raw || !/^\d+$/.test(raw)) return null;
  const n = Number(raw);
  return Number.isSafeInteger(n) ? n : null;
}

export default async function AssessmentPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { supabase } = await requireContext();
  const sp = await searchParams;
  const offeringId = idParam(sp.offering);
  const eventId = idParam(sp.event);

  const [offerings, info, events, sheet] = await Promise.all([
    safeRpcRows<AssessmentOffering>(supabase, 'assessment_offerings', { p_limit: 100, p_offset: 0 }),
    offeringId === null
      ? Promise.resolve({ data: [] as AssessmentOfferingInfo[], error: null })
      : safeRpcRows<AssessmentOfferingInfo>(supabase, 'assessment_offering_info', {
          p_course_offering_id: offeringId,
        }),
    offeringId === null
      ? Promise.resolve({ data: [] as AssessmentEventRow[], error: null })
      : safeSelect<AssessmentEventRow>(supabase, 'assessment_event', '*', {
          eq: { course_offering_id: offeringId },
          order: { column: 'assessment_date', ascending: false },
          limit: 200,
        }),
    eventId === null
      ? Promise.resolve({ data: [] as AssessmentSheetRow[], error: null })
      : safeRpcRows<AssessmentSheetRow>(supabase, 'assessment_sheet', { p_event_id: eventId }),
  ]);

  const offering = info.data[0] ?? null;
  const selectedEvent = eventId === null ? null : events.data.find((e) => e.assessment_event_id === eventId) ?? null;
  const markedCount = sheet.data.filter((r) => r.marks_obtained !== null || r.attendance_status !== null).length;

  return (
    <>
      <PageHeader
        title="Assessment"
        description="Enter the marks of a continuous assessment event, then publish it."
      />

      <Card>
        <CardHeader>
          <CardTitle>Course offering</CardTitle>
          <CardDescription>Pick the offering whose assessment events you want to mark.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <OfferingPicker offerings={offerings.data} selectedId={offeringId} />
          {offering && (
            <div className="flex flex-wrap items-center gap-3 text-sm">
              <span className="font-medium">
                {offering.course_code} — {offering.course_title}
              </span>
              <span className="text-muted-foreground">
                {offering.term_name} · {offering.programme_name} · {offering.semester_name}
              </span>
              <span className="text-muted-foreground">
                Internal {formatNumber(offering.internal_max_marks)} · External {formatNumber(offering.external_max_marks)} ·
                Pass {formatNumber(offering.passing_marks)}
              </span>
            </div>
          )}
          {offerings.error && <ErrorPanel message={`The offerings could not be read: ${offerings.error}`} />}
        </CardContent>
      </Card>

      {offeringId !== null && (
        <>
          <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <StatTile label="Assessment events" value={formatNumber(events.data.length)} />
            <StatTile label="Students registered" value={formatNumber(sheet.data.length)} />
            <StatTile label="Marks entered" value={formatNumber(markedCount)} />
            <StatTile
              label="Event status"
              value={selectedEvent ? selectedEvent.status : '—'}
              tone={selectedEvent?.status === 'PUBLISHED' ? 'success' : 'default'}
            />
          </div>

          <Card className="mt-6">
            <CardHeader>
              <CardTitle>Assessment event</CardTitle>
              <CardDescription>Choose the event whose sheet you want to mark.</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <EventPicker events={events.data} offeringId={offeringId} selectedId={eventId} />
              {events.error && <ErrorPanel message={`The events could not be read: ${events.error}`} />}
              {events.data.length === 0 && !events.error ? (
                <EmptyState title="No assessment events" description="This offering has no assessment events yet." />
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Event</TableHead>
                      <TableHead>Date</TableHead>
                      <TableHead>Time</TableHead>
                      <TableHead className="text-right">Maximum marks</TableHead>
                      <TableHead>Status</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {events.data.map((e) => (
                      <TableRow key={e.assessment_event_id}>
                        <TableCell className="font-medium">{e.event_title}</TableCell>
                        <TableCell>{formatDate(e.assessment_date)}</TableCell>
                        <TableCell>
                          {shortTime(e.start_time)} – {shortTime(e.end_time)}
                        </TableCell>
                        <TableCell className="text-right tabular-nums">{formatNumber(e.maximum_marks)}</TableCell>
                        <TableCell>
                          <Badge variant={statusVariant(e.status)}>{e.status}</Badge>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>

          {eventId !== null && selectedEvent && (
            <>
              <Card className="mt-6">
                <CardHeader>
                  <CardTitle>Marks · {selectedEvent.event_title}</CardTitle>
                  <CardDescription>
                    Maximum {formatNumber(selectedEvent.maximum_marks)} marks. A published event can no longer be changed.
                  </CardDescription>
                </CardHeader>
                <CardContent className="space-y-4">
                  {sheet.error && <ErrorPanel message={`The sheet could not be read: ${sheet.error}`} />}
                  <MarksEntryForm
                    eventId={eventId}
                    rows={sheet.data}
                    maximumMarks={Number(selectedEvent.maximum_marks)}
                    reducedMaximumMarks={
                      selectedEvent.reduced_maximum_marks === null ? null : Number(selectedEvent.reduced_maximum_marks)
                    }
                  />
                </CardContent>
              </Card>

              <Card className="mt-6">
                <CardHeader>
                  <CardTitle>Publish</CardTitle>
                  <CardDescription>
                    Publishing locks the marks: the database only allows a conducted event to be published.
                  </CardDescription>
                </CardHeader>
                <CardContent>
                  <PublishEventButton eventId={eventId} status={selectedEvent.status} />
                </CardContent>
              </Card>
            </>
          )}
        </>
      )}
    </>
  );
}
