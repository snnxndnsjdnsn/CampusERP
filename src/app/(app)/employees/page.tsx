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

type Employee = {
  employee_id: number;
  institution_id: number;
  employment_source_id: number;
  employee_number: string;
  display_name: string;
  first_name: string;
  last_name: string | null;
  date_of_birth: string | null;
  gender_id: number | null;
  primary_email: string | null;
  primary_phone: string | null;
  joining_date: string;
  employment_type: string;
  employment_status: string;
};

type Assignment = {
  employee_assignment_id: number;
  employee_id: number;
  campus_id: number;
  department_id: number | null;
  designation_id: number;
  start_date: string;
  end_date: string | null;
  is_primary: boolean;
};

type Campus = { campus_id: number; campus_name: string };
type Department = { department_id: number; department_name: string };
type Designation = { designation_id: number; designation_name: string };
type Gender = { gender_id: number; gender_name: string };
type EmploymentSource = { employment_source_id: number; source_name: string };

function first(value: string | string[] | undefined): string {
  if (Array.isArray(value)) return value[0] ?? '';
  return value ?? '';
}

/**
 * Module 5 · Employees.
 *
 * The staff register and the assignments that place each member of staff in a
 * campus, a department and a designation.
 */
export default async function EmployeesPage({ searchParams }: { searchParams: SearchParams }) {
  const { supabase } = await requireContext();
  const sp = await searchParams;
  const q = first(sp.q);
  const status = first(sp.status).toUpperCase();
  const type = first(sp.type).toUpperCase();

  const [employeesResult, assignmentsResult, campuses, departments, designations, genders, sources] =
    await Promise.all([
      readTable<Employee>(
        supabase,
        'employee',
        'employee_id, institution_id, employment_source_id, employee_number, display_name, first_name, last_name, date_of_birth, gender_id, primary_email, primary_phone, joining_date, employment_type, employment_status',
        { order: { column: 'display_name' }, limit: 1000 },
      ),
      readTable<Assignment>(
        supabase,
        'employee_assignment',
        'employee_assignment_id, employee_id, campus_id, department_id, designation_id, start_date, end_date, is_primary',
        { order: { column: 'employee_assignment_id' }, limit: 1000 },
      ),
      readTable<Campus>(supabase, 'campus', 'campus_id, campus_name', { order: { column: 'campus_name' } }),
      readTable<Department>(supabase, 'department', 'department_id, department_name', {
        order: { column: 'department_name' },
      }),
      readTable<Designation>(supabase, 'designation', 'designation_id, designation_name', {
        order: { column: 'designation_name' },
      }),
      readTable<Gender>(supabase, 'gender', 'gender_id, gender_name', { order: { column: 'gender_name' } }),
      readTable<EmploymentSource>(supabase, 'employment_source', 'employment_source_id, source_name', {
        order: { column: 'source_name' },
      }),
    ]);

  const errors = [employeesResult, assignmentsResult, campuses, departments, designations, genders, sources]
    .map((r) => r.error)
    .filter((e): e is string => Boolean(e));

  const campusOptions = campuses.data.map((c) => ({ id: c.campus_id, label: c.campus_name }));
  const departmentOptions = departments.data.map((d) => ({ id: d.department_id, label: d.department_name }));
  const designationOptions = designations.data.map((d) => ({ id: d.designation_id, label: d.designation_name }));
  const genderOptions = genders.data.map((g) => ({ id: g.gender_id, label: g.gender_name }));
  const sourceOptions = sources.data.map((s) => ({ id: s.employment_source_id, label: s.source_name }));

  const assignmentsByEmployee = new Map<number, Assignment[]>();
  for (const a of assignmentsResult.data) {
    const list = assignmentsByEmployee.get(a.employee_id) ?? [];
    list.push(a);
    assignmentsByEmployee.set(a.employee_id, list);
  }

  const primaryAssignment = (employeeId: number) => {
    const list = assignmentsByEmployee.get(employeeId) ?? [];
    return list.find((a) => a.is_primary && a.end_date === null) ?? list[0] ?? null;
  };

  const visibleEmployees = filterByQuery(
    employeesResult.data.filter(
      (e) =>
        (!status || e.employment_status.toUpperCase() === status) && (!type || e.employment_type.toUpperCase() === type),
    ),
    q,
    (e) => [
      e.employee_number,
      e.display_name,
      e.primary_email,
      e.primary_phone,
      e.employment_type,
      e.employment_status,
      labelFor(sourceOptions, e.employment_source_id),
    ],
  );

  const visibleAssignments = filterByQuery(
    assignmentsResult.data,
    q,
    (a) => {
      const employee = employeesResult.data.find((e) => e.employee_id === a.employee_id);
      return [
        employee?.employee_number,
        employee?.display_name,
        labelFor(campusOptions, a.campus_id),
        labelFor(departmentOptions, a.department_id),
        labelFor(designationOptions, a.designation_id),
      ];
    },
  );

  const statusOptions = distinctValues(employeesResult.data, (e) => e.employment_status).map((s) => ({
    value: s,
    label: s,
  }));
  const typeOptions = distinctValues(employeesResult.data, (e) => e.employment_type).map((t) => ({
    value: t,
    label: t,
  }));

  const activeEmployees = employeesResult.data.filter((e) => e.employment_status.toUpperCase() === 'ACTIVE').length;
  const onLeave = employeesResult.data.filter((e) => e.employment_status.toUpperCase() === 'ON_LEAVE').length;

  return (
    <>
      <PageHeader
        title="Employees"
        description="The staff register and the assignments that place each member of staff in a campus, a department and a designation."
      />

      {errors.length > 0 ? <ErrorPanel message={errors.join(' · ')} /> : null}

      <AdminTableEditor
        modules={['EMPLOYEE']}
        title="Manage the staff register"
        description="Add, edit and remove the employee records, their assignments and the HR details behind this screen. Every change is written through the database and audited."
      />

      <div className="mb-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatTile label="Employees" value={formatNumber(employeesResult.data.length)} hint={`${activeEmployees} active`} />
        <StatTile label="On leave" value={formatNumber(onLeave)} />
        <StatTile label="Assignments" value={formatNumber(assignmentsResult.data.length)} />
        <StatTile label="Designations" value={formatNumber(designations.data.length)} />
      </div>

      <div className="mb-6">
        <SearchForm
          action="/employees"
          query={q}
          placeholder="Employee number, name, email…"
          filters={[
            { name: 'status', label: 'Employment status', value: status, options: statusOptions },
            { name: 'type', label: 'Employment type', value: type, options: typeOptions },
          ]}
        />
      </div>

      <div className="space-y-4">
        <Card>
          <CardHeader>
            <CardTitle>Staff register</CardTitle>
            <CardDescription>{visibleEmployees.length} of {employeesResult.data.length} employees</CardDescription>
          </CardHeader>
          <CardContent>
            {visibleEmployees.length === 0 ? (
              <EmptyState title="No employees to show" description="Adjust the filters, or register a member of staff." />
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Number</TableHead>
                    <TableHead>Name</TableHead>
                    <TableHead>Gender</TableHead>
                    <TableHead>Contact</TableHead>
                    <TableHead>Joined</TableHead>
                    <TableHead>Type</TableHead>
                    <TableHead>Current posting</TableHead>
                    <TableHead>Status</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {visibleEmployees.map((e) => {
                    const assignment = primaryAssignment(e.employee_id);
                    return (
                      <TableRow key={e.employee_id}>
                        <TableCell className="font-medium">{e.employee_number}</TableCell>
                        <TableCell>
                          <div>{e.display_name}</div>
                          <div className="text-xs text-muted-foreground">{labelFor(sourceOptions, e.employment_source_id)}</div>
                        </TableCell>
                        <TableCell>{labelFor(genderOptions, e.gender_id)}</TableCell>
                        <TableCell>
                          <div>{e.primary_email ?? '—'}</div>
                          <div className="text-xs text-muted-foreground">{e.primary_phone ?? '—'}</div>
                        </TableCell>
                        <TableCell>{formatDate(e.joining_date)}</TableCell>
                        <TableCell>
                          <Badge variant="outline">{e.employment_type}</Badge>
                        </TableCell>
                        <TableCell>
                          {assignment ? (
                            <div>
                              <div>{labelFor(designationOptions, assignment.designation_id)}</div>
                              <div className="text-xs text-muted-foreground">
                                {labelFor(campusOptions, assignment.campus_id)}
                                {assignment.department_id ? ` · ${labelFor(departmentOptions, assignment.department_id)}` : ''}
                              </div>
                            </div>
                          ) : (
                            '—'
                          )}
                        </TableCell>
                        <TableCell>
                          <Badge variant={statusVariant(e.employment_status)}>{e.employment_status}</Badge>
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
            <CardTitle>Assignments</CardTitle>
            <CardDescription>{visibleAssignments.length} of {assignmentsResult.data.length} assignments</CardDescription>
          </CardHeader>
          <CardContent>
            {visibleAssignments.length === 0 ? (
              <EmptyState title="No assignments to show" description="Assign a member of staff to a campus and a designation." />
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Employee</TableHead>
                    <TableHead>Campus</TableHead>
                    <TableHead>Department</TableHead>
                    <TableHead>Designation</TableHead>
                    <TableHead>From</TableHead>
                    <TableHead>To</TableHead>
                    <TableHead>Primary</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {visibleAssignments.map((a) => {
                    const employee = employeesResult.data.find((e) => e.employee_id === a.employee_id);
                    return (
                      <TableRow key={a.employee_assignment_id}>
                        <TableCell>
                          <div className="font-medium">{employee?.employee_number ?? `#${a.employee_id}`}</div>
                          <div className="text-xs text-muted-foreground">{employee?.display_name ?? '—'}</div>
                        </TableCell>
                        <TableCell>{labelFor(campusOptions, a.campus_id)}</TableCell>
                        <TableCell>{labelFor(departmentOptions, a.department_id)}</TableCell>
                        <TableCell>{labelFor(designationOptions, a.designation_id)}</TableCell>
                        <TableCell>{formatDate(a.start_date)}</TableCell>
                        <TableCell>{formatDate(a.end_date)}</TableCell>
                        <TableCell>
                          <Badge variant={a.is_primary ? statusVariant('ACTIVE') : 'muted'}>
                            {a.is_primary ? 'PRIMARY' : 'SECONDARY'}
                          </Badge>
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
