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

type Course = {
  course_id: number;
  owning_department_id: number;
  course_category_id: number;
  course_code: string;
  course_title: string;
  short_title: string | null;
  course_type: string;
  lecture_hours: number;
  tutorial_hours: number;
  practical_hours: number;
  self_study_hours: number;
  credits: number;
  effective_from: string | null;
  effective_to: string | null;
  is_active: boolean;
};

type Category = {
  course_category_id: number;
  category_code: string;
  category_name: string;
  is_graded: boolean;
  contributes_to_gpa: boolean;
  is_active: boolean;
};

type Department = { department_id: number; department_name: string };

function first(value: string | string[] | undefined): string {
  if (Array.isArray(value)) return value[0] ?? '';
  return value ?? '';
}

/**
 * Module 4 · Course catalogue.
 *
 * A course is the unit of teaching; a category decides how it is graded and
 * whether it counts towards the GPA.
 */
export default async function CoursesPage({ searchParams }: { searchParams: SearchParams }) {
  const { supabase } = await requireContext();
  const sp = await searchParams;
  const q = first(sp.q);
  const categoryFilter = first(sp.category);
  const typeFilter = first(sp.type).toUpperCase();

  const [courses, categories, departments] = await Promise.all([
    readTable<Course>(
      supabase,
      'course_catalog',
      'course_id, owning_department_id, course_category_id, course_code, course_title, short_title, course_type, lecture_hours, tutorial_hours, practical_hours, self_study_hours, credits, effective_from, effective_to, is_active',
      { order: { column: 'course_code' } },
    ),
    readTable<Category>(
      supabase,
      'course_category',
      'course_category_id, category_code, category_name, is_graded, contributes_to_gpa, is_active',
      { order: { column: 'category_name' } },
    ),
    readTable<Department>(supabase, 'department', 'department_id, department_name', {
      order: { column: 'department_name' },
    }),
  ]);

  const errors = [courses, categories, departments].map((r) => r.error).filter((e): e is string => Boolean(e));

  const categoryOptions = categories.data.map((c) => ({ id: c.course_category_id, label: c.category_name }));
  const departmentOptions = departments.data.map((d) => ({ id: d.department_id, label: d.department_name }));

  const visibleCourses = filterByQuery(
    courses.data.filter(
      (c) =>
        (!categoryFilter || String(c.course_category_id) === categoryFilter) &&
        (!typeFilter || c.course_type.toUpperCase() === typeFilter),
    ),
    q,
    (c) => [
      c.course_code,
      c.course_title,
      c.short_title,
      c.course_type,
      labelFor(categoryOptions, c.course_category_id),
      labelFor(departmentOptions, c.owning_department_id),
    ],
  );

  const visibleCategories = filterByQuery(categories.data, q, (c) => [c.category_code, c.category_name]);

  const categoryFilterOptions = categories.data.map((c) => ({
    value: String(c.course_category_id),
    label: c.category_name,
  }));
  const typeOptions = distinctValues(courses.data, (c) => c.course_type).map((t) => ({ value: t, label: t }));

  const activeCourses = courses.data.filter((c) => c.is_active).length;
  const totalCredits = courses.data.reduce((sum, c) => sum + (Number(c.credits) || 0), 0);

  return (
    <>
      <PageHeader
        title="Courses"
        description="The course catalogue: what is taught, how many hours it carries and how it is graded."
      />

      {errors.length > 0 ? <ErrorPanel message={errors.join(' · ')} /> : null}

      <AdminTableEditor
        modules={['CURRICULUM']}
        title="Manage the catalogue"
        description="Add, edit and remove the courses and the categories they belong to. Every change is written through the database and audited."
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatTile label="Courses" value={formatNumber(courses.data.length)} hint={`${activeCourses} active`} />
        <StatTile label="Categories" value={formatNumber(categories.data.length)} />
        <StatTile label="Credits on offer" value={formatNumber(totalCredits)} hint="sum of course credits" />
        <StatTile label="Departments" value={formatNumber(departments.data.length)} />
      </div>

      <div className="mb-6">
        <SearchForm
          action="/courses"
          query={q}
          placeholder="Course code, title, department…"
          filters={[
            { name: 'category', label: 'Category', value: categoryFilter, options: categoryFilterOptions },
            { name: 'type', label: 'Type', value: typeFilter, options: typeOptions },
          ]}
        />
      </div>

      <div className="space-y-4">
        <Card>
          <CardHeader>
            <CardTitle>Catalogue</CardTitle>
            <CardDescription>{visibleCourses.length} of {courses.data.length} courses</CardDescription>
          </CardHeader>
          <CardContent>
            {visibleCourses.length === 0 ? (
              <EmptyState title="No courses to show" description="Adjust the filters, or add a course to the catalogue." />
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Code</TableHead>
                    <TableHead>Title</TableHead>
                    <TableHead>Category</TableHead>
                    <TableHead>Type</TableHead>
                    <TableHead>Department</TableHead>
                    <TableHead className="text-right">Credits</TableHead>
                    <TableHead className="text-right">Hours (L/T/P/S)</TableHead>
                    <TableHead>Effective</TableHead>
                    <TableHead>Status</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {visibleCourses.map((c) => (
                    <TableRow key={c.course_id}>
                      <TableCell className="font-medium">{c.course_code}</TableCell>
                      <TableCell>
                        <div>{c.course_title}</div>
                        {c.short_title ? <div className="text-xs text-muted-foreground">{c.short_title}</div> : null}
                      </TableCell>
                      <TableCell>{labelFor(categoryOptions, c.course_category_id)}</TableCell>
                      <TableCell>
                        <Badge variant="outline">{c.course_type}</Badge>
                      </TableCell>
                      <TableCell>{labelFor(departmentOptions, c.owning_department_id)}</TableCell>
                      <TableCell className="text-right tabular-nums">{formatNumber(c.credits)}</TableCell>
                      <TableCell className="text-right tabular-nums">
                        {formatNumber(c.lecture_hours)} / {formatNumber(c.tutorial_hours)} / {formatNumber(c.practical_hours)}{' '}
                        / {formatNumber(c.self_study_hours)}
                      </TableCell>
                      <TableCell>
                        {c.effective_from ? formatDate(c.effective_from) : '—'}
                        {c.effective_to ? ` – ${formatDate(c.effective_to)}` : ''}
                      </TableCell>
                      <TableCell>
                        <Badge variant={c.is_active ? statusVariant('ACTIVE') : statusVariant('INACTIVE')}>
                          {c.is_active ? 'ACTIVE' : 'INACTIVE'}
                        </Badge>
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
            <CardTitle>Course categories</CardTitle>
            <CardDescription>{visibleCategories.length} of {categories.data.length} categories</CardDescription>
          </CardHeader>
          <CardContent>
            {visibleCategories.length === 0 ? (
              <EmptyState title="No categories to show" />
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Code</TableHead>
                    <TableHead>Category</TableHead>
                    <TableHead>Graded</TableHead>
                    <TableHead>Counts towards GPA</TableHead>
                    <TableHead>Status</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {visibleCategories.map((c) => (
                    <TableRow key={c.course_category_id}>
                      <TableCell className="font-medium">{c.category_code}</TableCell>
                      <TableCell>{c.category_name}</TableCell>
                      <TableCell>{c.is_graded ? 'Yes' : 'No'}</TableCell>
                      <TableCell>{c.contributes_to_gpa ? 'Yes' : 'No'}</TableCell>
                      <TableCell>
                        <Badge variant={c.is_active ? statusVariant('ACTIVE') : statusVariant('INACTIVE')}>
                          {c.is_active ? 'ACTIVE' : 'INACTIVE'}
                        </Badge>
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
