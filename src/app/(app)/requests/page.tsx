import { PageHeader, StatTile } from '@/components/page-header';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { ErrorPanel } from '@/components/ui/empty-state';
import { ServiceRequestForm, ServiceRequestWorkspace, type ServiceRequest, type Term } from '@/features/requests/requests-client';
import { safeRows } from '@/features/shared/server-rpc';
import { formatNumber } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

export default async function RequestsPage() {
  const { ctx, supabase } = await requireContext();

  // The database decides which students' requests this caller may read.
  const requests = await safeRows<ServiceRequest>(supabase, 'svc_request_list');

  // The caller's own registered terms — a hall ticket needs one of them.
  const terms = ctx.student_id !== null ? await safeRows<Term>(supabase, 'svc_my_terms') : { rows: [], error: null };

  const submitted = requests.rows.filter((r) => r.request_status === 'SUBMITTED').length;
  const approved = requests.rows.filter((r) => r.request_status === 'APPROVED').length;
  const completed = requests.rows.filter((r) => r.request_status === 'COMPLETED').length;

  return (
    <>
      <PageHeader
        title="Hall ticket and graduation requests"
        description="Hall tickets, hostel check-out and graduation requests, and the decisions waiting on you."
      />

      <div className="grid gap-4 sm:grid-cols-3">
        <StatTile label="Awaiting a decision" value={formatNumber(submitted)} />
        <StatTile label="Approved" value={formatNumber(approved)} />
        <StatTile label="Completed" value={formatNumber(completed)} />
      </div>

      {ctx.student_id !== null ? (
        <section className="mt-6">
          <Card>
            <CardHeader>
              <CardTitle>New request</CardTitle>
            </CardHeader>
            <CardContent>
              {terms.error ? <ErrorPanel message={terms.error} /> : <ServiceRequestForm terms={terms.rows} />}
            </CardContent>
          </Card>
        </section>
      ) : null}

      <section className="mt-6">
        <Card>
          <CardHeader>
            <CardTitle>Requests</CardTitle>
          </CardHeader>
          <CardContent>
            {requests.error ? <ErrorPanel message={requests.error} /> : <ServiceRequestWorkspace rows={requests.rows} />}
          </CardContent>
        </Card>
      </section>
    </>
  );
}
