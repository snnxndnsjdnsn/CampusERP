import { PageHeader, StatTile } from '@/components/page-header';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { ErrorPanel } from '@/components/ui/empty-state';
import { MentoringWorkspace, type MentoringAssignment } from '@/features/mentoring/mentoring-client';
import { safeRows } from '@/features/shared/server-rpc';
import { formatNumber } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

export default async function MentoringPage() {
  const { supabase } = await requireContext();

  // The database decides which assignments this caller may read.
  const assignments = await safeRows<MentoringAssignment>(supabase, 'mentoring_assignments', { p_limit: 50 });

  const active = assignments.rows.filter((a) => a.assignment_status === 'ACTIVE').length;
  const mine = assignments.rows.filter((a) => a.is_mine).length;
  const sessions = assignments.rows.reduce((sum, a) => sum + Number(a.session_count ?? 0), 0);

  return (
    <>
      <PageHeader
        title="Mentoring"
        description="Mentor assignments, counselling sessions and their confidentiality levels."
      />

      <div className="grid gap-4 sm:grid-cols-3">
        <StatTile label="Assignments" value={formatNumber(assignments.rows.length)} hint={`${active} active`} />
        <StatTile label="Your assignments" value={formatNumber(mine)} />
        <StatTile label="Sessions recorded" value={formatNumber(sessions)} />
      </div>

      <section className="mt-6">
        <Card>
          <CardHeader>
            <CardTitle>Assignments</CardTitle>
          </CardHeader>
          <CardContent>
            {assignments.error ? <ErrorPanel message={assignments.error} /> : <MentoringWorkspace assignments={assignments.rows} />}
          </CardContent>
        </Card>
      </section>
    </>
  );
}
