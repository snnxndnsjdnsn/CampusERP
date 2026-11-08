import Link from 'next/link';
import { PageHeader, StatTile } from '@/components/page-header';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { AdminTableEditor } from '@/features/admin/admin-table-editor';
import { safeRpcRows, safeSelect } from '@/features/academic/data';
import { CandidateSearch, GenerateCoursesButton, OfferingPicker } from '@/features/registration/registration-client';
import type {
  CandidateRow,
  CourseRegistrationRow,
  RosterRow,
  TermInfoRow,
  TermOffering,
} from '@/features/registration/types';
import { formatDate, formatNumber } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

type OfferingRow = {
  programme_term_offering_id: number;
  academic_term_id: number;
  programme_id: number;
  semester_id: number;
  status: string;
};
type TermRow = { academic_term_id: number; term_name: string };
type ProgrammeRow = { programme_id: number; programme_name: string };
type SemesterRow = { semester_id: number; semester_name: string };
type TermRegistrationRow = {
  term_registration_id: number;
  enrolment_id: number;
  programme_term_offering_id: number;
  class_section_id: number | null;
  class_batch_id: number | null;
  roll_number: string | null;
  registration_date: string;
  registration_status: string;
};
type CourseRegistrationDbRow = {
  course_registration_id: number;
  term_registration_id: number;
  course_offering_id: number;
  registration_type: string;
  registration_date: string;
  registration_status: string;
};
type CourseOfferingRow = { course_offering_id: number; offering_code: string };

function idParam(value: string | string[] | undefined): number | null {
  const raw = Array.isArray(value) ? value[0] : value;
  if (!raw || !/^\d+$/.test(raw)) return null;
  const n = Number(raw);
  return Number.isSafeInteger(n) ? n : null;
}

export default async function RegistrationPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { supabase } = await requireContext();
  const sp = await searchParams;
  const offeringId = idParam(sp.pto);
  const registrationId = idParam(sp.tr);
  const query = (Array.isArray(sp.q) ? (sp.q[0] ?? '') : (sp.q ?? '')).slice(0, 80);

  const [offerings, terms, programmes, semesters] = await Promise.all([
    safeSelect<OfferingRow>(supabase, 'programme_term_offering', '*', { limit: 200 }),
    safeSelect<TermRow>(supabase, 'academic_term', 'academic_term_id, term_name', { limit: 200 }),
    safeSelect<ProgrammeRow>(supabase, 'programme', 'programme_id, programme_name', { limit: 500 }),
    safeSelect<SemesterRow>(supabase, 'semester', 'semester_id, semester_name', { limit: 100 }),
  ]);

  const termById = new Map(terms.data.map((t) => [Number(t.academic_term_id), t.term_name]));
  const programmeById = new Map(programmes.data.map((p) => [Number(p.programme_id), p.programme_name]));
  const semesterById = new Map(semesters.data.map((s) => [Number(s.semester_id), s.semester_name]));

  const offeringList: TermOffering[] = offerings.data.map((o) => ({
    programme_term_offering_id: Number(o.programme_term_offering_id),
    academic_term_id: Number(o.academic_term_id),
    programme_id: Number(o.programme_id),
    semester_id: Number(o.semester_id),
    status: o.status,
    term_name: termById.get(Number(o.academic_term_id)) ?? `Term ${o.academic_term_id}`,
    programme_name: programmeById.get(Number(o.programme_id)) ?? `Programme ${o.programme_id}`,
    semester_name: semesterById.get(Number(o.semester_id)) ?? `Semester ${o.semester_id}`,
  }));

  const selectedOffering = offeringId === null ? null : offeringList.find((o) => o.programme_term_offering_id === offeringId) ?? null;

  const [roster, candidates, termInfo, rawRegistrations, courseRegistrations, courseOfferings] = await Promise.all([
    offeringId === null
      ? Promise.resolve({ data: [] as RosterRow[], error: null })
      : safeRpcRows<RosterRow>(supabase, 'registration_roster', { p_offering_id: offeringId }),
    offeringId === null
      ? Promise.resolve({ data: [] as CandidateRow[], error: null })
      : safeRpcRows<CandidateRow>(supabase, 'registration_candidates', { p_offering_id: offeringId, p_q: query || null }),
    registrationId === null
      ? Promise.resolve({ data: [] as TermInfoRow[], error: null })
      : safeRpcRows<TermInfoRow>(supabase, 'registration_term_info', { p_term_registration_id: registrationId }),
    offeringId === null
      ? Promise.resolve({ data: [] as TermRegistrationRow[], error: null })
      : safeSelect<TermRegistrationRow>(supabase, 'student_term_registration', '*', {
          eq: { programme_term_offering_id: offeringId },
          limit: 500,
        }),
    offeringId === null
      ? Promise.resolve({ data: [] as CourseRegistrationDbRow[], error: null })
      : safeSelect<CourseRegistrationDbRow>(supabase, 'student_course_registration', '*', { limit: 1000 }),
    safeSelect<CourseOfferingRow>(supabase, 'course_offering', 'course_offering_id, offering_code', { limit: 1000 }),
  ]);

  const offeringCodeById = new Map(courseOfferings.data.map((c) => [Number(c.course_offering_id), c.offering_code]));
  const registrationIds = new Set(roster.data.map((r) => Number(r.term_registration_id)));
  const courseRows: CourseRegistrationRow[] = courseRegistrations.data
    .filter((c) => registrationIds.has(Number(c.term_registration_id)))
    .map((c) => ({
      course_registration_id: Number(c.course_registration_id),
      term_registration_id: Number(c.term_registration_id),
      course_offering_id: Number(c.course_offering_id),
      registration_type: c.registration_type,
      registration_date: c.registration_date,
      registration_status: c.registration_status,
      offering_code: offeringCodeById.get(Number(c.course_offering_id)) ?? null,
    }));

  const info = termInfo.data[0] ?? null;

  return (
    <>
      <PageHeader
        title="Registration"
        description="Term registrations, rosters and course registrations for each programme term offering."
      />

      <AdminTableEditor
        modules={['REGISTRATION']}
        title="Manage registration"
        description="Add, edit and remove the programme term offerings, the course offerings and class sections they carry, and the term registrations themselves. Every change is written through the database and audited."
      />

      <Card>
        <CardHeader>
          <CardTitle>Term offering</CardTitle>
          <CardDescription>Pick the offering whose roster you want to work with.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <OfferingPicker offerings={offeringList} selectedId={offeringId} />
          {selectedOffering && (
            <div className="flex flex-wrap items-center gap-3">
              <Badge variant={statusVariant(selectedOffering.status)}>{selectedOffering.status}</Badge>
              <span className="text-sm text-muted-foreground">
                {selectedOffering.term_name} · {selectedOffering.programme_name} · {selectedOffering.semester_name}
              </span>
              <GenerateCoursesButton offeringId={selectedOffering.programme_term_offering_id} />
            </div>
          )}
          {offerings.error && <ErrorPanel message={`Term offerings could not be read: ${offerings.error}`} />}
        </CardContent>
      </Card>

      {offeringId !== null && (
        <>
          <div className="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <StatTile label="Registered students" value={formatNumber(roster.data.length)} />
            <StatTile label="Registrations" value={formatNumber(rawRegistrations.data.length)} />
            <StatTile label="Course registrations" value={formatNumber(courseRows.length)} />
            <StatTile label="Candidates" value={formatNumber(candidates.data.length)} />
          </div>

          {roster.error && (
            <div className="mt-6">
              <ErrorPanel message={`The roster could not be read: ${roster.error}`} />
            </div>
          )}

          <Card className="mt-6">
            <CardHeader>
              <CardTitle>Roster</CardTitle>
              <CardDescription>Students registered for this offering.</CardDescription>
            </CardHeader>
            <CardContent>
              {roster.data.length === 0 ? (
                <EmptyState title="No registrations yet" description="Nobody is registered for this offering." />
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Student</TableHead>
                      <TableHead>Student number</TableHead>
                      <TableHead>Roll number</TableHead>
                      <TableHead>Section</TableHead>
                      <TableHead>Registered</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead className="text-right">Detail</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {roster.data.map((r) => (
                      <TableRow key={r.term_registration_id}>
                        <TableCell className="font-medium">{r.display_name}</TableCell>
                        <TableCell>{r.student_number}</TableCell>
                        <TableCell>{r.roll_number ?? '—'}</TableCell>
                        <TableCell>{r.class_section_id ?? '—'}</TableCell>
                        <TableCell>{formatDate(r.registration_date)}</TableCell>
                        <TableCell>
                          <Badge variant={statusVariant(r.registration_status)}>{r.registration_status}</Badge>
                        </TableCell>
                        <TableCell className="text-right">
                          <Link
                            href={`/registration?pto=${offeringId}&tr=${r.term_registration_id}`}
                            className="text-sm font-medium text-primary underline-offset-4 hover:underline"
                          >
                            Open
                          </Link>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>

          <Card className="mt-6">
            <CardHeader>
              <CardTitle>Registration detail</CardTitle>
              <CardDescription>The selected term registration.</CardDescription>
            </CardHeader>
            <CardContent>
              {termInfo.error && <ErrorPanel message={`The registration could not be read: ${termInfo.error}`} />}
              {!info ? (
                <EmptyState title="No registration selected" description="Open a roster row to see its detail." />
              ) : (
                <dl className="grid gap-x-6 gap-y-3 sm:grid-cols-2 lg:grid-cols-3">
                  <Detail label="Student" value={info.display_name} />
                  <Detail label="Student number" value={info.student_number} />
                  <Detail label="Roll number" value={info.roll_number ?? '—'} />
                  <Detail label="Enrolment" value={String(info.enrolment_id)} />
                  <Detail label="Class section" value={info.class_section_id === null ? '—' : String(info.class_section_id)} />
                  <Detail label="Class batch" value={info.class_batch_id === null ? '—' : String(info.class_batch_id)} />
                  <Detail label="Registration date" value={formatDate(info.registration_date)} />
                  <Detail label="Status" value={info.registration_status} />
                  <Detail label="Term registration" value={String(info.term_registration_id)} />
                </dl>
              )}
            </CardContent>
          </Card>

          <Card className="mt-6">
            <CardHeader>
              <CardTitle>Course registrations</CardTitle>
              <CardDescription>Courses each registered student is taking.</CardDescription>
            </CardHeader>
            <CardContent>
              {courseRows.length === 0 ? (
                <EmptyState title="No course registrations" description="No courses have been registered for this offering." />
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Course offering</TableHead>
                      <TableHead>Registration</TableHead>
                      <TableHead>Type</TableHead>
                      <TableHead>Date</TableHead>
                      <TableHead>Status</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {courseRows.map((c) => (
                      <TableRow key={c.course_registration_id}>
                        <TableCell>{c.offering_code ?? `Offering ${c.course_offering_id}`}</TableCell>
                        <TableCell>{c.course_registration_id}</TableCell>
                        <TableCell>{c.registration_type}</TableCell>
                        <TableCell>{formatDate(c.registration_date)}</TableCell>
                        <TableCell>
                          <Badge variant={statusVariant(c.registration_status)}>{c.registration_status}</Badge>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>

          <Card className="mt-6">
            <CardHeader>
              <CardTitle>Candidates</CardTitle>
              <CardDescription>Students of this programme who are not registered yet.</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <CandidateSearch offeringId={offeringId} query={query} />
              {candidates.error && <ErrorPanel message={`The candidates could not be read: ${candidates.error}`} />}
              {candidates.data.length === 0 && !candidates.error ? (
                <EmptyState title="No candidates" description="Every eligible student is already registered." />
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Student</TableHead>
                      <TableHead>Student number</TableHead>
                      <TableHead>Enrolment</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {candidates.data.map((c) => (
                      <TableRow key={c.enrolment_id}>
                        <TableCell className="font-medium">{c.display_name}</TableCell>
                        <TableCell>{c.student_number}</TableCell>
                        <TableCell>{c.enrolment_id}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>
        </>
      )}
    </>
  );
}

function Detail({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</dt>
      <dd className="mt-0.5 text-sm">{value}</dd>
    </div>
  );
}
