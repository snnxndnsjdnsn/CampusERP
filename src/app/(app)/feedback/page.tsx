import { PageHeader, StatTile } from '@/components/page-header';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { ErrorPanel } from '@/components/ui/empty-state';
import { FeedbackResultsExplorer, FeedbackTaskList, type FeedbackCycleOption, type FeedbackTask } from '@/features/feedback/feedback-client';
import { safeRows, safeSelect } from '@/features/shared/server-rpc';
import { formatNumber } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

export default async function FeedbackPage() {
  const { ctx, supabase } = await requireContext();

  // `feedback_my_tasks` is the student's own work list; it returns nothing for staff.
  const tasks = await safeRows<FeedbackTask>(supabase, 'feedback_my_tasks');

  // The cycle list is reference data every signed-in member may read; the RPCs
  // below still decide which responses each caller may see.
  const cycles = await safeSelect<Record<string, unknown>>(
    supabase,
    'feedback_cycle',
    'feedback_cycle_id, cycle_name, status, start_at, end_at, result_visibility',
    { order: { column: 'start_at', ascending: false }, limit: 50 },
  );

  const cycleOptions: FeedbackCycleOption[] = cycles.rows.map((c) => ({
    feedback_cycle_id: Number(c.feedback_cycle_id),
    cycle_name: String(c.cycle_name ?? ''),
    status: String(c.status ?? ''),
    start_at: String(c.start_at ?? ''),
    end_at: String(c.end_at ?? ''),
    result_visibility: String(c.result_visibility ?? ''),
  }));

  const pending = tasks.rows.filter((t) => !t.submitted).length;
  const submitted = tasks.rows.length - pending;
  const canReadResults = ctx.readable_modules.includes('FEEDBACK');

  return (
    <>
      <PageHeader
        title="Feedback"
        description="Feedback cycles you can respond to, and the results your role lets you see."
      />

      <div className="grid gap-4 sm:grid-cols-3">
        <StatTile label="Awaiting your response" value={formatNumber(pending)} />
        <StatTile label="Responses submitted" value={formatNumber(submitted)} />
        <StatTile label="Feedback cycles" value={formatNumber(cycleOptions.length)} />
      </div>

      {ctx.student_id !== null ? (
        <section className="mt-6">
          <Card>
            <CardHeader>
              <CardTitle>Your feedback</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {tasks.error ? <ErrorPanel message={tasks.error} /> : <FeedbackTaskList tasks={tasks.rows} />}
            </CardContent>
          </Card>
        </section>
      ) : null}

      {canReadResults ? (
        <section className="mt-6">
          <Card>
            <CardHeader>
              <CardTitle>Results</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {cycles.error ? <ErrorPanel message={cycles.error} /> : <FeedbackResultsExplorer cycles={cycleOptions} />}
            </CardContent>
          </Card>
        </section>
      ) : null}
    </>
  );
}
