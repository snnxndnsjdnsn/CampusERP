import { PageHeader, StatTile } from '@/components/page-header';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { safeRpcRows, safeSelect, shortTime } from '@/features/academic/data';
import {
  AttendanceMarkForm,
  CorrectionDecision,
  CorrectionRequestForm,
  SessionPicker,
} from '@/features/attendance/attendance-client';
import type {
  AttendanceSheetRow,
  AttendanceStatus,
  AttendanceSummaryRow,
  ClassSessionRow,
  CorrectionRequestRow,
} from '@/features/attendance/types';
import { formatDate, formatDateTime, formatNumber, formatPercent } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

type SessionDbRow = {
  class_session_id: number;
  course_offering_section_id: number;
  session_date: string;
  start_time: string;
  end_time: string;
  room_id: number | null;
  session_type: string;
  session_status: string;
};
type SectionDbRow = {
  course_offering_section_id: number;
  course_offering_id: number;
  class_section_id: number;
  session_type: string;
};
type OfferingDbRow = { course_offering_id: number; course_id: number; offering_code: string };
type CatalogDbRow = { course_id: number; course_code: string; course_title: string };
type ClassSectionDbRow = { class_section_id: number; section_code: string };

function idParam(value: string | string[] | undefined): number | null {
  const raw = Array.isArray(value) ? value[0] : value;
  if (!raw || !/^\d+$/.test(raw)) return null;
  const n = Number(raw);
  return Number.isSafeInteger(n) ? n : null;
}

export default async function AttendancePage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { supabase } = await requireContext();
  const sp = await searchParams;
  const sessionId = idParam(sp.session);

  const [sessions, statuses, sections, offerings, catalog, classSections, corrections] = await Promise.all([
    safeSelect<SessionDbRow>(supabase, 'class_session', '*', {
      order: { column: 'session_date', ascending: false },
      limit: 200,
    }),
    safeSelect<AttendanceStatus>(supabase, 'attendance_status', '*', { limit: 100 }),
    safeSelect<SectionDbRow>(supabase, 'course_offering_section', '*', { limit: 1000 }),
    safeSelect<OfferingDbRow>(supabase, 'course_offering', '*', { limit: 1000 }),
    safeSelect<CatalogDbRow>(supabase, 'course_catalog', '*', { limit: 1000 }),
    safeSelect<ClassSectionDbRow>(supabase, 'class_section', '*', { limit: 1000 }),
    safeSelect<CorrectionRequestRow>(supabase, 'attendance_correction_request', '*', {
      order: { column: 'requested_at', ascending: false },
      limit: 200,
    }),
  ]);

  const catalogById = new Map(catalog.data.map((c) => [Number(c.course_id), `${c.course_code} — ${c.course_title}`]));
  const offeringById = new Map(offerings.data.map((o) => [Number(o.course_offering_id), o]));
  const classSectionById = new Map(classSections.data.map((s) => [Number(s.class_section_id), s.section_code]));

  const labelFor = (cosId: number): { course_label: string | null; section_code: string | null } => {
    const section = sections.data.find((s) => Number(s.course_offering_section_id) === cosId);
    if (!section) return { course_label: null, section_code: null };
    const offering = offeringById.get(Number(section.course_offering_id));
    const courseLabel = offering ? (catalogById.get(Number(offering.course_id)) ?? offering.offering_code) : null;
    return {
      course_label: courseLabel,
      section_code: classSectionById.get(Number(section.class_section_id)) ?? null,
    };
  };

  const sessionRows: ClassSessionRow[] = sessions.data.map((s) => {
    const label = labelFor(Number(s.course_offering_section_id));
    return {
      class_session_id: Number(s.class_session_id),
      course_offering_section_id: Number(s.course_offering_section_id),
      session_date: s.session_date,
      start_time: s.start_time,
      end_time: s.end_time,
      room_id: s.room_id,
      session_type: s.session_type,
      session_status: s.session_status,
      course_label: label.course_label,
      section_code: label.section_code,
    };
  });

  const selected = sessionId === null ? null : sessionRows.find((s) => s.class_session_id === sessionId) ?? null;

  const [sheet, summary] = await Promise.all([
    sessionId === null
      ? Promise.resolve({ data: [] as AttendanceSheetRow[], error: null })
      : safeRpcRows<AttendanceSheetRow>(supabase, 'attendance_sheet', { p_session_id: sessionId }),
    selected === null
      ? Promise.resolve({ data: [] as AttendanceSummaryRow[], error: null })
      : safeRpcRows<AttendanceSummaryRow>(supabase, 'attendance_summary', {
          p_cos_id: selected.course_offering_section_id,
        }),
  ]);

  const activeStatuses = statuses.data.filter((s) => s.is_active !== false);
  const statusName = (id: number | null): string => {
    if (id === null) return '—';
    return statuses.data.find((s) => s.attendance_status_id === id)?.status_name ?? `Status ${id}`;
  };
  const pendingCorrections = corrections.data.filter((c) => c.request_status === 'PENDING');

  return (
    <>
      <PageHeader
        title="Attendance"
        description="Mark the register for a class session, and decide correction requests."
      />

      <Card>
        <CardHeader>
          <CardTitle>Class session</CardTitle>
          <CardDescription>Pick the session whose register you want to mark.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <SessionPicker sessions={sessionRows} selectedId={sessionId} />
          {selected && (
            <div className="flex flex-wrap items-center gap-3 text-sm">
              <Badge variant={statusVariant(selected.session_status)}>{selected.session_status}</Badge>
              <span className="font-medium">{selected.course_label ?? `Section ${selected.course_offering_section_id}`}</span>
              <span className="text-muted-foreground">
                {formatDate(selected.session_date)} · {shortTime(selected.start_time)} – {shortTime(selected.end_time)} ·{' '}
                {selected.session_type}
                {selected.section_code ? ` · ${selected.section_code}` : ''}
              </span>
            </div>
          )}
          {sessions.error && <ErrorPanel message={`The sessions could not be read: ${sessions.error}`} />}
        </CardContent>
      </Card>

      {sessionId !== null && (
        <>
          <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <StatTile label="Students on the roster" value={formatNumber(sheet.data.length)} />
            <StatTile label="Marked" value={formatNumber(sheet.data.filter((r) => r.attendance_status_id !== null).length)} />
            <StatTile label="Sessions conducted" value={formatNumber(summary.data[0]?.conducted_sessions ?? 0)} />
            <StatTile label="Pending corrections" value={formatNumber(pendingCorrections.length)} tone="warning" />
          </div>

          {sheet.error && (
            <div className="mt-6">
              <ErrorPanel message={`The register could not be read: ${sheet.error}`} />
            </div>
          )}

          <Card className="mt-6">
            <CardHeader>
              <CardTitle>Mark attendance</CardTitle>
              <CardDescription>
                Saving the register moves a planned session to conducted.
              </CardDescription>
            </CardHeader>
            <CardContent>
              <AttendanceMarkForm sessionId={sessionId} rows={sheet.data} statuses={activeStatuses} />
            </CardContent>
          </Card>

          <Card className="mt-6">
            <CardHeader>
              <CardTitle>Request a correction</CardTitle>
              <CardDescription>A student asks for a marked status to be changed.</CardDescription>
            </CardHeader>
            <CardContent>
              <CorrectionRequestForm sessionId={sessionId} rows={sheet.data} statuses={activeStatuses} />
            </CardContent>
          </Card>

          <Card className="mt-6">
            <CardHeader>
              <CardTitle>Attendance summary</CardTitle>
              <CardDescription>How each student has fared in this teaching section.</CardDescription>
            </CardHeader>
            <CardContent>
              {summary.error && <ErrorPanel message={`The summary could not be read: ${summary.error}`} />}
              {summary.data.length === 0 && !summary.error ? (
                <EmptyState title="No summary yet" description="The summary appears once the section has sessions." />
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Student</TableHead>
                      <TableHead>Student number</TableHead>
                      <TableHead className="text-right">Conducted</TableHead>
                      <TableHead className="text-right">Present</TableHead>
                      <TableHead className="text-right">Percentage</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {summary.data.map((r) => (
                      <TableRow key={r.roster_id}>
                        <TableCell className="font-medium">{r.display_name}</TableCell>
                        <TableCell>{r.student_number}</TableCell>
                        <TableCell className="text-right tabular-nums">{formatNumber(r.conducted_sessions)}</TableCell>
                        <TableCell className="text-right tabular-nums">{formatNumber(r.present_sessions)}</TableCell>
                        <TableCell className="text-right tabular-nums">{formatPercent(r.percentage)}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>
        </>
      )}

      <Card className="mt-6">
        <CardHeader>
          <CardTitle>Correction requests</CardTitle>
          <CardDescription>Approve or reject a correction before it changes the register.</CardDescription>
        </CardHeader>
        <CardContent>
          {corrections.error && <ErrorPanel message={`The correction requests could not be read: ${corrections.error}`} />}
          {corrections.data.length === 0 ? (
            <EmptyState title="No correction requests" description="Nobody has asked for a correction." />
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Session</TableHead>
                  <TableHead>Student</TableHead>
                  <TableHead>Change</TableHead>
                  <TableHead>Reason</TableHead>
                  <TableHead>Requested</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="text-right">Decision</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {corrections.data.map((c) => {
                  const student = sheet.data.find((r) => r.roster_id === c.course_offering_section_student_id);
                  return (
                    <TableRow key={c.attendance_correction_id}>
                      <TableCell>{c.class_session_id}</TableCell>
                      <TableCell>{student?.display_name ?? `Roster ${c.course_offering_section_student_id}`}</TableCell>
                      <TableCell>
                        {statusName(c.old_status_id)} → {statusName(c.requested_status_id)}
                      </TableCell>
                      <TableCell className="max-w-xs truncate">{c.reason}</TableCell>
                      <TableCell>{formatDateTime(c.requested_at)}</TableCell>
                      <TableCell>
                        <Badge variant={statusVariant(c.request_status)}>{c.request_status}</Badge>
                      </TableCell>
                      <TableCell className="text-right">
                        {c.request_status === 'PENDING' ? (
                          <CorrectionDecision correctionId={c.attendance_correction_id} />
                        ) : (
                          <span className="text-xs text-muted-foreground">
                            {c.resolved_at ? formatDate(c.resolved_at) : '—'}
                          </span>
                        )}
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </>
  );
}
