import Link from 'next/link';
import { notFound } from 'next/navigation';
import { PageHeader } from '@/components/page-header';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { DetailFields, DetailStack, DetailTable } from '@/features/detail/detail-ui';
import { safeSelectOne, safeSelectWhere } from '@/features/detail/detail-data';
import { formatDate } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

type Employee = {
  employee_id: number;
  employee_number: string;
  display_name: string;
  first_name: string;
  last_name: string | null;
  date_of_birth: string | null;
  primary_email: string | null;
  primary_phone: string | null;
  joining_date: string;
  employment_type: string;
  employment_status: string;
};

type Assignment = {
  employee_assignment_id: number;
  campus_id: number;
  department_id: number | null;
  designation_id: number;
  start_date: string;
  end_date: string | null;
  is_primary: boolean;
};

/**
 * An employee's service record.
 *
 * The row comes from the `employee` table through RLS, so the caller sees the
 * employee only if their role and scope allow it.
 */
export default async function EmployeeRecordsPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { supabase } = await requireContext();

  const employeeId = Number(id);
  if (!Number.isInteger(employeeId) || employeeId <= 0) notFound();

  const [employeeRes, assignmentRes] = await Promise.all([
    safeSelectOne<Employee>(
      supabase,
      'employee',
      'employee_id',
      employeeId,
      'employee_id, employee_number, display_name, first_name, last_name, date_of_birth, primary_email, primary_phone, joining_date, employment_type, employment_status',
    ),
    safeSelectWhere<Assignment>(
      supabase,
      'employee_assignment',
      'employee_id',
      employeeId,
      'employee_assignment_id, campus_id, department_id, designation_id, start_date, end_date, is_primary',
      { limit: 50 },
    ),
  ]);

  const employee = employeeRes.data;
  if (!employee) notFound();

  return (
    <>
      <PageHeader
        title={employee.display_name}
        description={`Employee ${employee.employee_number}`}
        actions={
          <Link href="/employees">
            <Button variant="outline">Back to employees</Button>
          </Link>
        }
      />

      <DetailStack>
        {employeeRes.error && (
          <p className="rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800" role="alert">
            {employeeRes.error}
          </p>
        )}

        <DetailFields
          title="Personal"
          fields={[
            { label: 'Employee number', value: employee.employee_number },
            { label: 'Name', value: employee.display_name },
            { label: 'Date of birth', value: formatDate(employee.date_of_birth) },
            { label: 'Email', value: employee.primary_email ?? '—' },
            { label: 'Phone', value: employee.primary_phone ?? '—' },
            { label: 'Joining date', value: formatDate(employee.joining_date) },
            { label: 'Employment type', value: employee.employment_type },
            {
              label: 'Employment status',
              value: <Badge variant={statusVariant(employee.employment_status)}>{employee.employment_status}</Badge>,
            },
          ]}
        />

        <DetailTable
          title="Assignments"
          rows={assignmentRes.rows}
          rowKey={(r) => String(r.employee_assignment_id)}
          emptyTitle="No assignments"
          emptyDescription="An employee has no campus or department assignment yet."
          columns={[
            { key: 'id', header: 'Assignment', render: (r) => `#${r.employee_assignment_id}` },
            { key: 'campus', header: 'Campus', render: (r) => `#${r.campus_id}` },
            { key: 'department', header: 'Department', render: (r) => (r.department_id ? `#${r.department_id}` : '—') },
            { key: 'designation', header: 'Designation', render: (r) => `#${r.designation_id}` },
            { key: 'from', header: 'From', render: (r) => formatDate(r.start_date) },
            { key: 'to', header: 'To', render: (r) => formatDate(r.end_date) },
            {
              key: 'primary',
              header: 'Primary',
              render: (r) => (r.is_primary ? <Badge variant="info">Primary</Badge> : '—'),
            },
          ]}
        />
      </DetailStack>
    </>
  );
}
