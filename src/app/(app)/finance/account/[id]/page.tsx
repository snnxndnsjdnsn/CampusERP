import Link from 'next/link';
import { notFound } from 'next/navigation';
import { PageHeader } from '@/components/page-header';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { DetailFields, DetailStack, DetailTable } from '@/features/detail/detail-ui';
import { safeRpc } from '@/features/shared/server-rpc';
import { formatDate, formatMoney } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

type AccountRow = {
  student_account_id: number;
  student_id: number;
  account_number: string;
  account_status: string;
  student_number: string;
  display_name: string;
  opening_balance: number;
  credit_balance: number;
  total_payable: number;
  total_paid: number;
  total_balance: number;
};

type Benefit = {
  kind: string;
  id: number;
  name: string;
  status: string;
  percentage: number | null;
  amount: number | null;
  applied: number;
  requested: string | null;
  remarks: string | null;
};

type Adjustment = {
  id: number;
  number: string;
  type: string;
  amount: number;
  status: string;
  reason: string | null;
  item_id: number | null;
  date: string | null;
};

type Instalment = {
  id: number;
  assessment_id: number;
  number: number;
  due: string | null;
  amount: number;
  paid: number;
  status: string;
};

type Penalty = {
  id: number;
  date: string | null;
  reason: string | null;
  amount: number;
  waived: number;
  net: number;
  status: string;
};

type Extras = {
  benefits?: Benefit[];
  adjustments?: Adjustment[];
  instalments?: Instalment[];
  penalties?: Penalty[];
};

/**
 * A student's financial account.
 *
 * `fin_account_info` and `fin_account_extras` are SECURITY DEFINER and both
 * check `FEES.*` permissions against the student the account belongs to, so
 * the page shows only the sections the caller may see.
 */
export default async function FinanceAccountPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { supabase } = await requireContext();

  const accountId = Number(id);
  if (!Number.isInteger(accountId) || accountId <= 0) notFound();

  const [infoRes, extrasRes] = await Promise.all([
    safeRpc<AccountRow[]>(supabase, 'fin_account_info', { p_student_account_id: accountId }),
    safeRpc<Extras>(supabase, 'fin_account_extras', { p_student_account_id: accountId }),
  ]);

  const account = infoRes.data?.[0];
  if (!account) notFound();

  const extras = extrasRes.data ?? {};
  const benefits = extras.benefits ?? [];
  const adjustments = extras.adjustments ?? [];
  const instalments = extras.instalments ?? [];
  const penalties = extras.penalties ?? [];

  return (
    <>
      <PageHeader
        title={account.display_name}
        description={`Account ${account.account_number}`}
        actions={
          <Link href="/finance">
            <Button variant="outline">Back to fees</Button>
          </Link>
        }
      />

      <DetailStack>
        {infoRes.error && (
          <p className="rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800" role="alert">
            {infoRes.error}
          </p>
        )}

        <DetailFields
          title="Account"
          fields={[
            { label: 'Account number', value: account.account_number },
            { label: 'Student number', value: account.student_number },
            { label: 'Student', value: account.display_name },
            {
              label: 'Status',
              value: <Badge variant={statusVariant(account.account_status)}>{account.account_status}</Badge>,
            },
            { label: 'Opening balance', value: formatMoney(account.opening_balance) },
            { label: 'Credit balance', value: formatMoney(account.credit_balance) },
            { label: 'Total payable', value: formatMoney(account.total_payable) },
            { label: 'Total paid', value: formatMoney(account.total_paid) },
            { label: 'Balance', value: formatMoney(account.total_balance) },
          ]}
        />

        <DetailTable
          title="Benefits and concessions"
          rows={benefits}
          rowKey={(r) => `${r.kind}-${r.id}`}
          emptyTitle="No benefits"
          emptyDescription="Concessions, scholarships and sponsorships appear here once they are applied for."
          columns={[
            { key: 'kind', header: 'Kind', render: (r) => r.kind },
            { key: 'name', header: 'Name', render: (r) => r.name },
            {
              key: 'status',
              header: 'Status',
              render: (r) => <Badge variant={statusVariant(r.status)}>{r.status}</Badge>,
            },
            { key: 'percentage', header: 'Percent', numeric: true, render: (r) => formatMoney(r.percentage) },
            { key: 'amount', header: 'Amount', numeric: true, render: (r) => formatMoney(r.amount) },
            { key: 'applied', header: 'Applied', numeric: true, render: (r) => formatMoney(r.applied) },
            { key: 'requested', header: 'Requested', render: (r) => formatDate(r.requested) },
            { key: 'remarks', header: 'Remarks', render: (r) => r.remarks ?? '—' },
          ]}
        />

        <DetailTable
          title="Adjustments"
          rows={adjustments}
          rowKey={(r) => String(r.id)}
          emptyTitle="No adjustments"
          columns={[
            { key: 'number', header: 'Number', render: (r) => r.number },
            { key: 'type', header: 'Type', render: (r) => r.type },
            { key: 'amount', header: 'Amount', numeric: true, render: (r) => formatMoney(r.amount) },
            {
              key: 'status',
              header: 'Status',
              render: (r) => <Badge variant={statusVariant(r.status)}>{r.status}</Badge>,
            },
            { key: 'reason', header: 'Reason', render: (r) => r.reason ?? '—' },
            { key: 'date', header: 'Date', render: (r) => formatDate(r.date) },
          ]}
        />

        <DetailTable
          title="Instalments"
          rows={instalments}
          rowKey={(r) => String(r.id)}
          emptyTitle="No instalment plan"
          columns={[
            { key: 'number', header: 'Instalment', render: (r) => `#${r.number}` },
            { key: 'assessment', header: 'Assessment', render: (r) => `#${r.assessment_id}` },
            { key: 'due', header: 'Due', render: (r) => formatDate(r.due) },
            { key: 'amount', header: 'Amount', numeric: true, render: (r) => formatMoney(r.amount) },
            { key: 'paid', header: 'Paid', numeric: true, render: (r) => formatMoney(r.paid) },
            {
              key: 'status',
              header: 'Status',
              render: (r) => <Badge variant={statusVariant(r.status)}>{r.status}</Badge>,
            },
          ]}
        />

        <DetailTable
          title="Penalties"
          rows={penalties}
          rowKey={(r) => String(r.id)}
          emptyTitle="No penalties"
          columns={[
            { key: 'date', header: 'Date', render: (r) => formatDate(r.date) },
            { key: 'reason', header: 'Reason', render: (r) => r.reason ?? '—' },
            { key: 'amount', header: 'Amount', numeric: true, render: (r) => formatMoney(r.amount) },
            { key: 'waived', header: 'Waived', numeric: true, render: (r) => formatMoney(r.waived) },
            { key: 'net', header: 'Net', numeric: true, render: (r) => formatMoney(r.net) },
            {
              key: 'status',
              header: 'Status',
              render: (r) => <Badge variant={statusVariant(r.status)}>{r.status}</Badge>,
            },
          ]}
        />
      </DetailStack>
    </>
  );
}
