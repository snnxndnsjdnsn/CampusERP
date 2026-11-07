import Link from 'next/link';
import { PageHeader } from '@/components/page-header';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { DetailStack, DetailTable } from '@/features/detail/detail-ui';
import { safeRpc } from '@/features/shared/server-rpc';
import { formatDate, formatMoney } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

type StructureRow = {
  fee_structure_id: number;
  structure_code: string;
  structure_name: string;
  institution_name: string | null;
  programme_name: string | null;
  year_code: string | null;
  version_number: number;
  approval_status: string;
  effective_from: string | null;
  effective_to: string | null;
  item_count: number;
  total_amount: number;
  total_count: number;
};

/**
 * Fee structures.
 *
 * `fin_structure_list` is SECURITY DEFINER and returns the structures in the
 * caller's scope. Approval status is shown as a badge because a structure only
 * becomes usable once it has been approved.
 */
export default async function FinanceStructuresPage() {
  const { supabase } = await requireContext();

  const { data, error } = await safeRpc<StructureRow[]>(supabase, 'fin_structure_list', {
    p_limit: 50,
  });
  const rows = data ?? [];

  return (
    <>
      <PageHeader
        title="Fee structures"
        description="The fee heads, weights and totals that drive a student's assessment."
        actions={
          <Link href="/finance">
            <Button variant="outline">Back to fees</Button>
          </Link>
        }
      />

      <DetailStack>
        {error && (
          <p className="rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800" role="alert">
            {error}
          </p>
        )}

        <DetailTable
          title="Structures"
          rows={rows}
          rowKey={(r) => String(r.fee_structure_id)}
          emptyTitle="No fee structures"
          emptyDescription="Fee structures appear here once one has been created and submitted for approval."
          columns={[
            { key: 'code', header: 'Code', render: (r) => r.structure_code },
            { key: 'name', header: 'Name', render: (r) => r.structure_name },
            { key: 'institution', header: 'Institution', render: (r) => r.institution_name ?? '—' },
            { key: 'programme', header: 'Programme', render: (r) => r.programme_name ?? '—' },
            { key: 'year', header: 'Year', render: (r) => r.year_code ?? '—' },
            { key: 'version', header: 'Version', numeric: true, render: (r) => r.version_number },
            {
              key: 'status',
              header: 'Approval',
              render: (r) => <Badge variant={statusVariant(r.approval_status)}>{r.approval_status}</Badge>,
            },
            { key: 'from', header: 'Effective from', render: (r) => formatDate(r.effective_from) },
            { key: 'to', header: 'Effective to', render: (r) => formatDate(r.effective_to) },
            { key: 'items', header: 'Items', numeric: true, render: (r) => r.item_count },
            { key: 'total', header: 'Total', numeric: true, render: (r) => formatMoney(r.total_amount) },
          ]}
        />
      </DetailStack>
    </>
  );
}
