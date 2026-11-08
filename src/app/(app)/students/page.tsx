import { PageHeader, StatTile } from '@/components/page-header';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { AdminTableEditor } from '@/features/admin/admin-table-editor';
import { distinctValues, filterByQuery, labelFor } from '@/features/shared/filter';
import { readTable } from '@/features/shared/reads';
import { SearchForm } from '@/features/shared/search-form';
import { loadStudentLookups } from '@/features/students-lookups';
import { formatDate, formatNumber } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

type SearchParams = Promise<Record<string, string | string[] | undefined>>;

type Student = {
  student_id: number;
  student_number: string;
  university_seat_number: string | null;
  display_name: string;
  first_name: string;
  last_name: string | null;
  date_of_birth: string | null;
  gender_id: number | null;
  primary_email: string | null;
  primary_phone: string | null;
  nationality_country_id: number | null;
  religion_id: number | null;
  social_category_id: number | null;
  admission_date: string | null;
  student_status: string;
};

type Enrolment = {
  enrolment_id: number;
  student_id: number;
  programme_id: number;
  specialization_id: number | null;
  curriculum_scheme_id: number;
  admission_academic_year_id: number;
  admission_category_id: number | null;
  admission_date: string;
  admission_semester_id: number;
  expected_completion_date: string | null;
  enrolment_status: string;
};

function first(value: string | string[] | undefined): string {
  if (Array.isArray(value)) return value[0] ?? '';
  return value ?? '';
}

/**
 * Module 5 · Students.
 *
 * The student register and the programme enrolments that hang off it. The
 * reference dropdowns come from `loadStudentLookups`, which reads the same
 * RLS-protected tables the rest of the module uses.
 */
export default async function StudentsPage({ searchParams }: { searchParams: SearchParams }) {
  const { supabase } = await requireContext();
  const sp = await searchParams;
  const q = first(sp.q);
  const status = first(sp.status).toUpperCase();
  const programmeFilter = first(sp.programme);

  const [studentsResult, enrolmentsResult, lookups] = await Promise.all([
    readTable<Student>(
      supabase,
      'student',
      'student_id, student_number, university_seat_number, display_name, first_name, last_name, date_of_birth, gender_id, primary_email, primary_phone, nationality_country_id, religion_id, social_category_id, admission_date, student_status',
      { order: { column: 'display_name' }, limit: 1000 },
    ),
    readTable<Enrolment>(
      supabase,
      'student_programme_enrolment',
      'enrolment_id, student_id, programme_id, specialization_id, curriculum_scheme_id, admission_academic_year_id, admission_category_id, admission_date, admission_semester_id, expected_completion_date, enrolment_status',
      { order: { column: 'enrolment_id' }, limit: 1000 },
    ),
    loadStudentLookups(supabase),
  ]);

  const errors = [studentsResult, enrolmentsResult]
    .map((r) => r.error)
    .filter((e): e is string => Boolean(e));

  const programmeOptions = lookups.programmes;
  const schemeOptions = lookups.schemes.map((s) => ({ id: s.id, label: s.label }));
  const yearOptions = lookups.academicYears;
  const semesterOptions = lookups.semesters;
  const genderOptions = lookups.genders;

  const enrolmentsByStudent = new Map<number, Enrolment[]>();
  for (const e of enrolmentsResult.data) {
    const list = enrolmentsByStudent.get(e.student_id) ?? [];
    list.push(e);
    enrolmentsByStudent.set(e.student_id, list);
  }

  const visibleStudents = filterByQuery(
    studentsResult.data.filter((s) => !status || s.student_status.toUpperCase() === status),
    q,
    (s) => [
      s.student_number,
      s.university_seat_number,
      s.display_name,
      s.primary_email,
      s.primary_phone,
      s.student_status,
      (enrolmentsByStudent.get(s.student_id) ?? []).map((e) => labelFor(programmeOptions, e.programme_id)),
    ],
  );

  const visibleEnrolments = filterByQuery(
    enrolmentsResult.data.filter((e) => !programmeFilter || String(e.programme_id) === programmeFilter),
    q,
    (e) => {
      const student = studentsResult.data.find((s) => s.student_id === e.student_id);
      return [
        student?.student_number,
        student?.display_name,
        labelFor(programmeOptions, e.programme_id),
        labelFor(schemeOptions, e.curriculum_scheme_id),
        labelFor(yearOptions, e.admission_academic_year_id),
        labelFor(semesterOptions, e.admission_semester_id),
        e.enrolment_status,
      ];
    },
  );

  const statusOptions = distinctValues(studentsResult.data, (s) => s.student_status).map((s) => ({
    value: s,
    label: s,
  }));
  const programmeFilterOptions = programmeOptions.map((p) => ({ value: String(p.id), label: p.label }));

  const activeStudents = studentsResult.data.filter((s) => s.student_status.toUpperCase() === 'ACTIVE').length;
  const activeEnrolments = enrolmentsResult.data.filter((e) => e.enrolment_status.toUpperCase() === 'ACTIVE').length;

  return (
    <>
      <PageHeader
        title="Students"
        description="The student register and the programme enrolments that place each student on a curriculum."
      />

      {errors.length > 0 ? <ErrorPanel message={errors.join(' · ')} /> : null}

      <AdminTableEditor
        tables={['student', 'student_programme_enrolment']}
        title="Manage the register"
        description="Add, edit and remove student records and the programme enrolments that place them on a curriculum. Every change is written through the database and audited."
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatTile label="Students" value={formatNumber(studentsResult.data.length)} hint={`${activeStudents} active`} />
        <StatTile label="Enrolments" value={formatNumber(enrolmentsResult.data.length)} hint={`${activeEnrolments} active`} />
        <StatTile label="Programmes" value={formatNumber(programmeOptions.length)} />
        <StatTile label="Curriculum schemes" value={formatNumber(lookups.schemes.length)} />
      </div>

      <div className="mb-6">
        <SearchForm
          action="/students"
          query={q}
          placeholder="Student number, name, email…"
          filters={[
            { name: 'status', label: 'Student status', value: status, options: statusOptions },
            { name: 'programme', label: 'Programme', value: programmeFilter, options: programmeFilterOptions },
          ]}
        />
      </div>

      <div className="space-y-4">
        <Card>
          <CardHeader>
            <CardTitle>Student register</CardTitle>
            <CardDescription>{visibleStudents.length} of {studentsResult.data.length} students</CardDescription>
          </CardHeader>
          <CardContent>
            {visibleStudents.length === 0 ? (
              <EmptyState title="No students to show" description="Adjust the filters, or admit a student to populate the register." />
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Number</TableHead>
                    <TableHead>Name</TableHead>
                    <TableHead>Gender</TableHead>
                    <TableHead>Contact</TableHead>
                    <TableHead>Admitted</TableHead>
                    <TableHead>Programme</TableHead>
                    <TableHead>Status</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {visibleStudents.map((s) => {
                    const enrolments = enrolmentsByStudent.get(s.student_id) ?? [];
                    return (
                      <TableRow key={s.student_id}>
                        <TableCell className="font-medium">{s.student_number}</TableCell>
                        <TableCell>
                          <div>{s.display_name}</div>
                          {s.university_seat_number ? (
                            <div className="text-xs text-muted-foreground">Seat {s.university_seat_number}</div>
                          ) : null}
                        </TableCell>
                        <TableCell>{labelFor(genderOptions, s.gender_id)}</TableCell>
                        <TableCell>
                          <div>{s.primary_email ?? '—'}</div>
                          <div className="text-xs text-muted-foreground">{s.primary_phone ?? '—'}</div>
                        </TableCell>
                        <TableCell>{formatDate(s.admission_date)}</TableCell>
                        <TableCell>
                          {enrolments.length === 0 ? (
                            '—'
                          ) : (
                            <div className="flex flex-wrap gap-1">
                              {enrolments.map((e) => (
                                <Badge key={e.enrolment_id} variant="outline">
                                  {labelFor(programmeOptions, e.programme_id)}
                                </Badge>
                              ))}
                            </div>
                          )}
                        </TableCell>
                        <TableCell>
                          <Badge variant={statusVariant(s.student_status)}>{s.student_status}</Badge>
                        </TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Programme enrolments</CardTitle>
            <CardDescription>{visibleEnrolments.length} of {enrolmentsResult.data.length} enrolments</CardDescription>
          </CardHeader>
          <CardContent>
            {visibleEnrolments.length === 0 ? (
              <EmptyState title="No enrolments to show" description="Enrolments appear once a student is placed on a programme." />
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Student</TableHead>
                    <TableHead>Programme</TableHead>
                    <TableHead>Scheme</TableHead>
                    <TableHead>Year</TableHead>
                    <TableHead>Semester</TableHead>
                    <TableHead>Admitted</TableHead>
                    <TableHead>Expected completion</TableHead>
                    <TableHead>Status</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {visibleEnrolments.map((e) => {
                    const student = studentsResult.data.find((s) => s.student_id === e.student_id);
                    return (
                      <TableRow key={e.enrolment_id}>
                        <TableCell>
                          <div className="font-medium">{student?.student_number ?? `#${e.student_id}`}</div>
                          <div className="text-xs text-muted-foreground">{student?.display_name ?? '—'}</div>
                        </TableCell>
                        <TableCell>{labelFor(programmeOptions, e.programme_id)}</TableCell>
                        <TableCell>{labelFor(schemeOptions, e.curriculum_scheme_id)}</TableCell>
                        <TableCell>{labelFor(yearOptions, e.admission_academic_year_id)}</TableCell>
                        <TableCell>{labelFor(semesterOptions, e.admission_semester_id)}</TableCell>
                        <TableCell>{formatDate(e.admission_date)}</TableCell>
                        <TableCell>{formatDate(e.expected_completion_date)}</TableCell>
                        <TableCell>
                          <Badge variant={statusVariant(e.enrolment_status)}>{e.enrolment_status}</Badge>
                        </TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>
      </div>
    </>
  );
}
