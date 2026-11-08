import { PageHeader, StatTile } from '@/components/page-header';
import { ErrorPanel } from '@/components/ui/empty-state';
import { AdminTableEditor } from '@/features/admin/admin-table-editor';
import {
  StructureEditor,
  type InstitutionRow,
  type ParentOption,
  type ParentOptions,
  type UniversityOption,
} from '@/features/structure/structure-editor';
import { readTable } from '@/features/shared/reads';
import { formatNumber } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

type UniversityRow = { university_id: number; university_name: string };
type CampusRow = { campus_id: number };
type DepartmentRow = { department_id: number };
type ProgrammeRow = { programme_id: number };
type StudentRow = { student_id: number; student_number: string; display_name: string };
type EmployeeRow = { employee_id: number; employee_number: string; display_name: string };
type ActivityRow = { staff_activity_id: number; activity_title: string; employee_id: number };

/**
 * Module 2 · Institution structure.
 *
 * The institution register is written through `institution_create` /
 * `institution_update`; the child records of a student, an employee or a staff
 * activity are written through the generic `section_*` family.
 */
export default async function StructurePage() {
  const { supabase } = await requireContext();

  const [institutions, universities, campuses, departments, programmes, students, employees, activities] =
    await Promise.all([
      readTable<InstitutionRow>(
        supabase,
        'institution',
        'institution_id, university_id, institution_code, institution_name, legal_name, website_url, email, phone, is_active',
        { order: { column: 'institution_name' } },
      ),
      readTable<UniversityRow>(
        supabase,
        'university',
        'university_id, university_name',
        { order: { column: 'university_name' } },
      ),
      readTable<CampusRow>(supabase, 'campus', 'campus_id'),
      readTable<DepartmentRow>(supabase, 'department', 'department_id'),
      readTable<ProgrammeRow>(supabase, 'programme', 'programme_id'),
      readTable<StudentRow>(supabase, 'student', 'student_id, student_number, display_name', {
        order: { column: 'display_name' },
        limit: 500,
      }),
      readTable<EmployeeRow>(supabase, 'employee', 'employee_id, employee_number, display_name', {
        order: { column: 'display_name' },
        limit: 500,
      }),
      readTable<ActivityRow>(supabase, 'staff_activity', 'staff_activity_id, activity_title, employee_id', {
        order: { column: 'staff_activity_id', ascending: false },
        limit: 500,
      }),
    ]);

  const errors = [institutions, universities, campuses, departments, programmes, students, employees, activities]
    .map((r) => r.error)
    .filter((e): e is string => Boolean(e));

  const universityOptions: UniversityOption[] = universities.data.map((u) => ({
    id: Number(u.university_id),
    label: String(u.university_name),
  }));

  const parents: ParentOptions = {
    student: students.data.map<ParentOption>((s) => ({
      id: Number(s.student_id),
      label: String(s.display_name),
      sub: String(s.student_number),
    })),
    employee: employees.data.map<ParentOption>((e) => ({
      id: Number(e.employee_id),
      label: String(e.display_name),
      sub: String(e.employee_number),
    })),
    activity: activities.data.map<ParentOption>((a) => ({
      id: Number(a.staff_activity_id),
      label: String(a.activity_title),
      sub: `Employee #${a.employee_id}`,
    })),
  };

  return (
    <>
      <PageHeader
        title="Institution structure"
        description="Maintain the institution register and the child records that hang off a student, an employee or a staff research activity."
      />

      {errors.length > 0 ? <ErrorPanel message={errors.join(' · ')} /> : null}

      <AdminTableEditor
        modules={['INSTITUTION']}
        title="Manage the institution structure"
        description="Add, edit and remove the universities, campuses, departments, programmes, specialisations, buildings and rooms behind this screen. Every change is written through the database and audited."
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatTile label="Institutions" value={formatNumber(institutions.data.length)} />
        <StatTile label="Campuses" value={formatNumber(campuses.data.length)} />
        <StatTile label="Departments" value={formatNumber(departments.data.length)} />
        <StatTile label="Programmes" value={formatNumber(programmes.data.length)} />
      </div>

      <StructureEditor
        institutions={institutions.data}
        universities={universityOptions}
        parents={parents}
      />
    </>
  );
}
