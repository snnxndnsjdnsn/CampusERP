import Link from 'next/link';
import { notFound } from 'next/navigation';
import { PageHeader } from '@/components/page-header';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { DetailFields, DetailStack, DetailTable } from '@/features/detail/detail-ui';
import { safeSelectOne, safeSelectWhere } from '@/features/detail/detail-data';
import { formatDate, formatNumber } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

type Student = {
  student_id: number;
  student_number: string;
  university_seat_number: string | null;
  display_name: string;
  first_name: string;
  last_name: string | null;
  date_of_birth: string | null;
  primary_email: string | null;
  primary_phone: string | null;
  admission_date: string | null;
  student_status: string;
};

type Enrolment = {
  enrolment_id: number;
  programme_id: number;
  curriculum_scheme_id: number;
  admission_academic_year_id: number;
  admission_date: string;
  enrolment_status: string;
};

type TermRegistration = {
  term_registration_id: number;
  enrolment_id: number;
  programme_term_offering_id: number;
  roll_number: string | null;
  registration_date: string;
  registration_status: string;
};

type CourseRegistration = {
  course_registration_id: number;
  term_registration_id: number;
  course_offering_id: number;
  registration_type: string;
  registration_status: string;
};

type CourseResult = {
  student_course_result_id: number;
  course_registration_id: number;
  internal_marks: number | null;
  external_marks: number | null;
  total_marks: number | null;
  grade_letter: string | null;
  grade_point: number | null;
  credits_earned: number | null;
  result_status: string;
};

type TermResult = {
  student_term_result_id: number;
  term_registration_id: number;
  credits_registered: number | null;
  credits_earned: number | null;
  sgpa: number | null;
  cgpa: number | null;
  result_status: string;
  published_at: string | null;
};

/**
 * A student's academic record.
 *
 * Every table below is read through RLS, so the rows shown are exactly the rows
 * the database allows this caller to see. A student sees their own record; a
 * registrar sees the students in their scope.
 */
export default async function StudentRecordsPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { supabase } = await requireContext();

  const studentId = Number(id);
  if (!Number.isInteger(studentId) || studentId <= 0) notFound();

  const [studentRes, enrolmentRes] = await Promise.all([
    safeSelectOne<Student>(
      supabase,
      'student',
      'student_id',
      studentId,
      'student_id, student_number, university_seat_number, display_name, first_name, last_name, date_of_birth, primary_email, primary_phone, admission_date, student_status',
    ),
    safeSelectWhere<Enrolment>(
      supabase,
      'student_programme_enrolment',
      'student_id',
      studentId,
      'enrolment_id, programme_id, curriculum_scheme_id, admission_academic_year_id, admission_date, enrolment_status',
      { limit: 50 },
    ),
  ]);

  const student = studentRes.data;
  if (!student) notFound();

  const enrolments = enrolmentRes.rows;
  const enrolmentIds = new Set(enrolments.map((e) => e.enrolment_id));

  // The term registrations hang off the enrolments, so they are read per enrolment.
  const termRows = await Promise.all(
    [...enrolmentIds].map((eid) =>
      safeSelectWhere<TermRegistration>(
        supabase,
        'student_term_registration',
        'enrolment_id',
        eid,
        'term_registration_id, enrolment_id, programme_term_offering_id, roll_number, registration_date, registration_status',
        { limit: 100 },
      ),
    ),
  );
  const termRegs = termRows.flatMap((r) => r.rows);
  const termRegIds = new Set(termRegs.map((t) => t.term_registration_id));

  const courseRows = await Promise.all(
    [...termRegIds].map((tid) =>
      safeSelectWhere<CourseRegistration>(
        supabase,
        'student_course_registration',
        'term_registration_id',
        tid,
        'course_registration_id, term_registration_id, course_offering_id, registration_type, registration_status',
        { limit: 500 },
      ),
    ),
  );
  const courses = courseRows.flatMap((r) => r.rows);
  const courseRegIds = new Set(courses.map((c) => c.course_registration_id));

  const resultRows = await Promise.all(
    [...courseRegIds].map((cid) =>
      safeSelectWhere<CourseResult>(
        supabase,
        'student_course_result',
        'course_registration_id',
        cid,
        'student_course_result_id, course_registration_id, internal_marks, external_marks, total_marks, grade_letter, grade_point, credits_earned, result_status',
        { limit: 100 },
      ),
    ),
  );
  const results = resultRows.flatMap((r) => r.rows);

  const termResultRows = await Promise.all(
    [...termRegIds].map((tid) =>
      safeSelectWhere<TermResult>(
        supabase,
        'student_term_result',
        'term_registration_id',
        tid,
        'student_term_result_id, term_registration_id, credits_registered, credits_earned, sgpa, cgpa, result_status, published_at',
        { limit: 100 },
      ),
    ),
  );
  const termResults = termResultRows.flatMap((r) => r.rows);

  const errors = [studentRes.error, enrolmentRes.error, ...termRows.map((r) => r.error)]
    .concat(courseRows.map((r) => r.error))
    .concat(resultRows.map((r) => r.error))
    .concat(termResultRows.map((r) => r.error))
    .filter((e): e is string => Boolean(e));

  return (
    <>
      <PageHeader
        title={student.display_name}
        description={`Student ${student.student_number}`}
        actions={
          <Link href="/students">
            <Button variant="outline">Back to students</Button>
          </Link>
        }
      />

      <DetailStack>
        {errors.length > 0 && (
          <p className="rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800" role="alert">
            Some sections could not be read: {errors.join('; ')}
          </p>
        )}

        <DetailFields
          title="Personal"
          fields={[
            { label: 'Student number', value: student.student_number },
            { label: 'University seat number', value: student.university_seat_number ?? '—' },
            { label: 'Name', value: student.display_name },
            { label: 'Date of birth', value: formatDate(student.date_of_birth) },
            { label: 'Email', value: student.primary_email ?? '—' },
            { label: 'Phone', value: student.primary_phone ?? '—' },
            { label: 'Admission date', value: formatDate(student.admission_date) },
            {
              label: 'Status',
              value: <Badge variant={statusVariant(student.student_status)}>{student.student_status}</Badge>,
            },
          ]}
        />

        <DetailTable
          title="Programme enrolments"
          rows={enrolments}
          rowKey={(r) => String(r.enrolment_id)}
          emptyTitle="No enrolments"
          columns={[
            { key: 'id', header: 'Enrolment', render: (r) => `#${r.enrolment_id}` },
            { key: 'programme', header: 'Programme', render: (r) => `#${r.programme_id}` },
            { key: 'scheme', header: 'Scheme', render: (r) => `#${r.curriculum_scheme_id}` },
            { key: 'year', header: 'Admission year', render: (r) => `#${r.admission_academic_year_id}` },
            { key: 'date', header: 'Admitted', render: (r) => formatDate(r.admission_date) },
            {
              key: 'status',
              header: 'Status',
              render: (r) => <Badge variant={statusVariant(r.enrolment_status)}>{r.enrolment_status}</Badge>,
            },
          ]}
        />

        <DetailTable
          title="Term registrations"
          rows={termRegs}
          rowKey={(r) => String(r.term_registration_id)}
          emptyTitle="No term registrations"
          columns={[
            { key: 'id', header: 'Registration', render: (r) => `#${r.term_registration_id}` },
            { key: 'roll', header: 'Roll number', render: (r) => r.roll_number ?? '—' },
            { key: 'offering', header: 'Term offering', render: (r) => `#${r.programme_term_offering_id}` },
            { key: 'date', header: 'Registered', render: (r) => formatDate(r.registration_date) },
            {
              key: 'status',
              header: 'Status',
              render: (r) => <Badge variant={statusVariant(r.registration_status)}>{r.registration_status}</Badge>,
            },
          ]}
        />

        <DetailTable
          title="Course registrations"
          rows={courses}
          rowKey={(r) => String(r.course_registration_id)}
          emptyTitle="No course registrations"
          columns={[
            { key: 'id', header: 'Registration', render: (r) => `#${r.course_registration_id}` },
            { key: 'offering', header: 'Course offering', render: (r) => `#${r.course_offering_id}` },
            { key: 'type', header: 'Type', render: (r) => r.registration_type },
            {
              key: 'status',
              header: 'Status',
              render: (r) => <Badge variant={statusVariant(r.registration_status)}>{r.registration_status}</Badge>,
            },
          ]}
        />

        <DetailTable
          title="Course results"
          rows={results}
          rowKey={(r) => String(r.student_course_result_id)}
          emptyTitle="No results published"
          columns={[
            { key: 'reg', header: 'Registration', render: (r) => `#${r.course_registration_id}` },
            { key: 'internal', header: 'Internal', numeric: true, render: (r) => formatNumber(r.internal_marks) },
            { key: 'external', header: 'External', numeric: true, render: (r) => formatNumber(r.external_marks) },
            { key: 'total', header: 'Total', numeric: true, render: (r) => formatNumber(r.total_marks) },
            { key: 'grade', header: 'Grade', render: (r) => r.grade_letter ?? '—' },
            { key: 'point', header: 'Point', numeric: true, render: (r) => formatNumber(r.grade_point) },
            { key: 'credits', header: 'Credits', numeric: true, render: (r) => formatNumber(r.credits_earned) },
            {
              key: 'status',
              header: 'Result',
              render: (r) => <Badge variant={statusVariant(r.result_status)}>{r.result_status}</Badge>,
            },
          ]}
        />

        <DetailTable
          title="Term results"
          rows={termResults}
          rowKey={(r) => String(r.student_term_result_id)}
          emptyTitle="No term results"
          columns={[
            { key: 'reg', header: 'Registration', render: (r) => `#${r.term_registration_id}` },
            { key: 'cr', header: 'Credits registered', numeric: true, render: (r) => formatNumber(r.credits_registered) },
            { key: 'ce', header: 'Credits earned', numeric: true, render: (r) => formatNumber(r.credits_earned) },
            { key: 'sgpa', header: 'SGPA', numeric: true, render: (r) => formatNumber(r.sgpa) },
            { key: 'cgpa', header: 'CGPA', numeric: true, render: (r) => formatNumber(r.cgpa) },
            {
              key: 'status',
              header: 'Result',
              render: (r) => <Badge variant={statusVariant(r.result_status)}>{r.result_status}</Badge>,
            },
            { key: 'published', header: 'Published', render: (r) => formatDate(r.published_at) },
          ]}
        />
      </DetailStack>
    </>
  );
}
