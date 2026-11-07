import { PageHeader, StatTile } from '@/components/page-header';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { ErrorPanel } from '@/components/ui/empty-state';
import { GrievanceDesk, GrievanceSubmitForm, MyGrievances, type Lookup, type MyGrievance } from '@/features/grievances/grievance-client';
import { safeRows, safeSelect } from '@/features/shared/server-rpc';
import { formatNumber } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

export default async function GrievancesPage() {
  const { ctx, supabase } = await requireContext();

  const isStudent = ctx.student_id !== null;
  const canReadDesk = ctx.readable_modules.includes('GRIEVANCE');

  const mine = isStudent ? await safeRows<MyGrievance>(supabase, 'grievance_my') : { rows: [], error: null };
  const desk = canReadDesk ? await safeRows<{ grievance_id: number; status: string; priority: string }>(supabase, 'grievance_list', { p_limit: 50 }) : { rows: [], error: null };

  const categories = await safeSelect<Record<string, unknown>>(
    supabase,
    'grievance_category',
    'grievance_category_id, category_name, is_active',
    { order: { column: 'category_name', ascending: true }, limit: 200 },
  );
  const departments = await safeSelect<Record<string, unknown>>(
    supabase,
    'department',
    'department_id, department_name, is_active',
    { order: { column: 'department_name', ascending: true }, limit: 300 },
  );

  const categoryOptions: Lookup[] = categories.rows
    .filter((c) => c.is_active !== false)
    .map((c) => ({ id: Number(c.grievance_category_id), label: String(c.category_name ?? '') }));
  const departmentOptions: Lookup[] = departments.rows
    .filter((d) => d.is_active !== false)
    .map((d) => ({ id: Number(d.department_id), label: String(d.department_name ?? '') }));

  const openCases = desk.rows.filter((g) => g.status !== 'CLOSED').length;
  const urgent = desk.rows.filter((g) => g.priority === 'URGENT').length;

  return (
    <>
      <PageHeader
        title="Grievances"
        description="Raise a grievance, follow its progress, and work the cases your role lets you see."
      />

      <div className="grid gap-4 sm:grid-cols-3">
        <StatTile label="Your open grievances" value={formatNumber(mine.rows.filter((g) => g.status !== 'CLOSED').length)} />
        <StatTile label="Open cases in the desk" value={formatNumber(openCases)} />
        <StatTile label="Urgent cases" value={formatNumber(urgent)} tone={urgent > 0 ? 'warning' : 'default'} />
      </div>

      {isStudent ? (
        <section className="mt-6 space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>Raise a grievance</CardTitle>
            </CardHeader>
            <CardContent>
              {categories.error ? <ErrorPanel message={categories.error} /> : <GrievanceSubmitForm categories={categoryOptions} departments={departmentOptions} />}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Your grievances</CardTitle>
            </CardHeader>
            <CardContent>
              {mine.error ? <ErrorPanel message={mine.error} /> : <MyGrievances rows={mine.rows} />}
            </CardContent>
          </Card>
        </section>
      ) : null}

      {canReadDesk ? (
        <section className="mt-6">
          <Card>
            <CardHeader>
              <CardTitle>Grievance desk</CardTitle>
            </CardHeader>
            <CardContent>
              {desk.error ? <ErrorPanel message={desk.error} /> : <GrievanceDesk />}
            </CardContent>
          </Card>
        </section>
      ) : null}
    </>
  );
}
