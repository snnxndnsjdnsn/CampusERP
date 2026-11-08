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
import { PropertyHierarchy } from '@/features/structure/property-hierarchy';
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
type LandRow = { land_id: number; land_name: string; survey_number: string };
type BuildingRow = { building_id: number; building_code: string; building_name: string; land_id: number | null; total_floors: number | null };
type FloorRow = { floor_id: number; building_id: number; floor_number: number; floor_name: string | null };
type RoomRow = { room_id: number; building_id: number; room_code: string };

/**
 * Module 2 · Institution structure.
 *
 * The institution register is written through `institution_create` /
 * `institution_update`; the child records of a student, an employee or a staff
 * activity are written through the generic `section_*` family.
 */
export default async function StructurePage() {
  const { supabase } = await requireContext();

  const [institutions, universities, campuses, departments, programmes, students, employees, activities, lands, buildings, floors, rooms] =
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
      readTable<LandRow>(supabase, 'land', 'land_id, land_name, survey_number', {
        order: { column: 'land_name' },
      }),
      readTable<BuildingRow>(
        supabase,
        'building',
        'building_id, building_code, building_name, land_id, total_floors',
        { order: { column: 'building_name' } },
      ),
      readTable<FloorRow>(supabase, 'floor', 'floor_id, building_id, floor_number, floor_name', {
        order: { column: 'floor_number' },
      }),
      readTable<RoomRow>(supabase, 'room', 'room_id, building_id, room_code'),
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
        description="Add, edit and remove the universities, campuses, departments, programmes, specialisations, land parcels, buildings, floors, rooms, their facilities and documents behind this screen. Every change is written through the database and audited."
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatTile label="Institutions" value={formatNumber(institutions.data.length)} />
        <StatTile label="Campuses" value={formatNumber(campuses.data.length)} />
        <StatTile label="Departments" value={formatNumber(departments.data.length)} />
        <StatTile label="Programmes" value={formatNumber(programmes.data.length)} />
        <StatTile label="Land parcels" value={formatNumber(lands.data.length)} />
        <StatTile label="Buildings" value={formatNumber(buildings.data.length)} />
        <StatTile label="Floors" value={formatNumber(floors.data.length)} />
        <StatTile label="Rooms" value={formatNumber(rooms.data.length)} />
      </div>

      <PropertyHierarchy
        lands={lands.data}
        buildings={buildings.data}
        floors={floors.data}
        rooms={rooms.data}
      />

      <StructureEditor
        institutions={institutions.data}
        universities={universityOptions}
        parents={parents}
      />
    </>
  );
}
