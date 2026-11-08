import { PageHeader, StatTile } from '@/components/page-header';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { AdminTableEditor } from '@/features/admin/admin-table-editor';
import { distinctValues, filterByQuery, labelFor } from '@/features/shared/filter';
import { readTable } from '@/features/shared/reads';
import { SearchForm } from '@/features/shared/search-form';
import { formatDate, formatNumber } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

type SearchParams = Promise<Record<string, string | string[] | undefined>>;

type Scheme = {
  curriculum_scheme_id: number;
  programme_id: number;
  specialization_id: number | null;
  scheme_code: string;
  scheme_name: string;
  regulation_year: number;
  total_credits: number | null;
  effective_from: string;
  effective_to: string | null;
  status: string;
};

type CurriculumCourse = {
  curriculum_course_id: number;
  curriculum_scheme_id: number;
  semester_id: number;
  course_id: number;
  course_category_id: number;
  is_mandatory: boolean;
  elective_group_code: string | null;
  display_order: number | null;
  internal_max_marks: number;
  external_max_marks: number;
  passing_marks: number | null;
  exam_duration_minutes: number | null;
};

type Programme = { programme_id: number; programme_name: string };
type Semester = { semester_id: number; semester_name: string };
type Course = { course_id: number; course_code: string; course_title: string };
type Category = { course_category_id: number; category_name: string };

function first(value: string | string[] | undefined): string {
  if (Array.isArray(value)) return value[0] ?? '';
  return value ?? '';
}

/**
 * Module 4 · Curriculum.
 *
 * A scheme is the programme-level plan; a curriculum course is one subject of
 * that plan in one semester. Both are read through RLS.
 */
export default async function CurriculumPage({ searchParams }: { searchParams: SearchParams }) {
  const { supabase } = await requireContext();
  const sp = await searchParams;
  const q = first(sp.q);
  const schemeFilter = first(sp.scheme);
  const status = first(sp.status).toUpperCase();

  const [schemes, courses, programmes, semesters, catalogue, categories] = await Promise.all([
    readTable<Scheme>(
      supabase,
      'curriculum_scheme',
      'curriculum_scheme_id, programme_id, specialization_id, scheme_code, scheme_name, regulation_year, total_credits, effective_from, effective_to, status',
      { order: { column: 'scheme_name' } },
    ),
    readTable<CurriculumCourse>(
      supabase,
      'curriculum_course',
      'curriculum_course_id, curriculum_scheme_id, semester_id, course_id, course_category_id, is_mandatory, elective_group_code, display_order, internal_max_marks, external_max_marks, passing_marks, exam_duration_minutes',
      { order: { column: 'curriculum_scheme_id' } },
    ),
    readTable<Programme>(supabase, 'programme', 'programme_id, programme_name', { order: { column: 'programme_name' } }),
    readTable<Semester>(supabase, 'semester', 'semester_id, semester_name', { order: { column: 'semester_id' } }),
    readTable<Course>(supabase, 'course_catalog', 'course_id, course_code, course_title', { order: { column: 'course_code' } }),
    readTable<Category>(supabase, 'course_category', 'course_category_id, category_name', {
      order: { column: 'category_name' },
    }),
  ]);

  const errors = [schemes, courses, programmes, semesters, catalogue, categories]
    .map((r) => r.error)
    .filter((e): e is string => Boolean(e));

  const programmeOptions = programmes.data.map((p) => ({ id: p.programme_id, label: p.programme_name }));
  const semesterOptions = semesters.data.map((s) => ({ id: s.semester_id, label: s.semester_name }));
  const categoryOptions = categories.data.map((c) => ({ id: c.course_category_id, label: c.category_name }));

  const courseLabel = (id: number) => {
    const hit = catalogue.data.find((c) => c.course_id === id);
    return hit ? `${hit.course_code} — ${hit.course_title}` : `#${id}`;
  };

  const schemeLabel = (id: number) => {
    const hit = schemes.data.find((s) => s.curriculum_scheme_id === id);
    return hit ? `${hit.scheme_code} — ${hit.scheme_name}` : `#${id}`;
  };

  const visibleSchemes = filterByQuery(
    schemes.data.filter(
      (s) =>
        (!status || s.status.toUpperCase() === status) &&
        (!schemeFilter || String(s.curriculum_scheme_id) === schemeFilter),
    ),
    q,
    (s) => [s.scheme_code, s.scheme_name, s.status, labelFor(programmeOptions, s.programme_id)],
  );

  const visibleCourses = filterByQuery(
    courses.data.filter((c) => !schemeFilter || String(c.curriculum_scheme_id) === schemeFilter),
    q,
    (c) => [
      schemeLabel(c.curriculum_scheme_id),
      labelFor(semesterOptions, c.semester_id),
      courseLabel(c.course_id),
      labelFor(categoryOptions, c.course_category_id),
      c.elective_group_code,
    ],
  );

  const schemeOptions = schemes.data.map((s) => ({
    value: String(s.curriculum_scheme_id),
    label: `${s.scheme_code} — ${s.scheme_name}`,
  }));
  const statusOptions = distinctValues(schemes.data, (s) => s.status).map((s) => ({ value: s, label: s }));

  const totalCredits = schemes.data.reduce((sum, s) => sum + (Number(s.total_credits) || 0), 0);
  const activeSchemes = schemes.data.filter((s) => s.status.toUpperCase() === 'ACTIVE').length;

  return (
    <>
      <PageHeader
        title="Curriculum"
        description="Programme-level curriculum schemes and the subjects each scheme places in each semester."
      />

      {errors.length > 0 ? <ErrorPanel message={errors.join(' · ')} /> : null}

      <AdminTableEditor
        modules={['CURRICULUM']}
        title="Manage the curriculum"
        description="Add, edit and remove the curriculum schemes and the subjects they place in each semester. Every change is written through the database and audited."
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatTile label="Schemes" value={formatNumber(schemes.data.length)} hint={`${activeSchemes} active`} />
        <StatTile label="Curriculum courses" value={formatNumber(courses.data.length)} />
        <StatTile label="Declared credits" value={formatNumber(totalCredits)} hint="sum of scheme credits" />
        <StatTile label="Programmes" value={formatNumber(programmes.data.length)} />
      </div>

      <div className="mb-6">
        <SearchForm
          action="/curriculum"
          query={q}
          placeholder="Scheme, course code, subject…"
          filters={[
            { name: 'scheme', label: 'Scheme', value: schemeFilter, options: schemeOptions },
            { name: 'status', label: 'Status', value: status, options: statusOptions },
          ]}
        />
      </div>

      <div className="space-y-4">
        <Card>
          <CardHeader>
            <CardTitle>Curriculum schemes</CardTitle>
            <CardDescription>{visibleSchemes.length} of {schemes.data.length} schemes</CardDescription>
          </CardHeader>
          <CardContent>
            {visibleSchemes.length === 0 ? (
              <EmptyState title="No curriculum schemes to show" description="Adjust the filters, or ask the academic office to publish a scheme." />
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Code</TableHead>
                    <TableHead>Scheme</TableHead>
                    <TableHead>Programme</TableHead>
                    <TableHead className="text-right">Regulation</TableHead>
                    <TableHead className="text-right">Credits</TableHead>
                    <TableHead>Effective</TableHead>
                    <TableHead>Status</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {visibleSchemes.map((s) => (
                    <TableRow key={s.curriculum_scheme_id}>
                      <TableCell className="font-medium">{s.scheme_code}</TableCell>
                      <TableCell>{s.scheme_name}</TableCell>
                      <TableCell>{labelFor(programmeOptions, s.programme_id)}</TableCell>
                      <TableCell className="text-right tabular-nums">{s.regulation_year}</TableCell>
                      <TableCell className="text-right tabular-nums">
                        {s.total_credits === null ? '—' : formatNumber(s.total_credits)}
                      </TableCell>
                      <TableCell>
                        {formatDate(s.effective_from)}
                        {s.effective_to ? ` – ${formatDate(s.effective_to)}` : ''}
                      </TableCell>
                      <TableCell>
                        <Badge variant={statusVariant(s.status)}>{s.status}</Badge>
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
            <CardTitle>Curriculum courses</CardTitle>
            <CardDescription>{visibleCourses.length} of {courses.data.length} subjects</CardDescription>
          </CardHeader>
          <CardContent>
            {visibleCourses.length === 0 ? (
              <EmptyState title="No curriculum courses to show" description="Pick another scheme or clear the search." />
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Scheme</TableHead>
                    <TableHead>Semester</TableHead>
                    <TableHead>Course</TableHead>
                    <TableHead>Category</TableHead>
                    <TableHead>Type</TableHead>
                    <TableHead className="text-right">Internal</TableHead>
                    <TableHead className="text-right">External</TableHead>
                    <TableHead className="text-right">Pass</TableHead>
                    <TableHead className="text-right">Minutes</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {visibleCourses.map((c) => (
                    <TableRow key={c.curriculum_course_id}>
                      <TableCell>{schemeLabel(c.curriculum_scheme_id)}</TableCell>
                      <TableCell>{labelFor(semesterOptions, c.semester_id)}</TableCell>
                      <TableCell className="font-medium">{courseLabel(c.course_id)}</TableCell>
                      <TableCell>{labelFor(categoryOptions, c.course_category_id)}</TableCell>
                      <TableCell>
                        <div className="flex gap-1">
                          <Badge variant={c.is_mandatory ? 'default' : 'muted'}>
                            {c.is_mandatory ? 'Mandatory' : 'Elective'}
                          </Badge>
                          {c.elective_group_code ? (
                            <Badge variant="outline">{c.elective_group_code}</Badge>
                          ) : null}
                        </div>
                      </TableCell>
                      <TableCell className="text-right tabular-nums">{formatNumber(c.internal_max_marks)}</TableCell>
                      <TableCell className="text-right tabular-nums">{formatNumber(c.external_max_marks)}</TableCell>
                      <TableCell className="text-right tabular-nums">
                        {c.passing_marks === null ? '—' : formatNumber(c.passing_marks)}
                      </TableCell>
                      <TableCell className="text-right tabular-nums">
                        {c.exam_duration_minutes === null ? '—' : formatNumber(c.exam_duration_minutes)}
                      </TableCell>
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
