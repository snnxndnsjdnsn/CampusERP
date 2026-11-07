import Link from 'next/link';
import { notFound } from 'next/navigation';
import { PageHeader } from '@/components/page-header';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { DetailFields, DetailStack, DetailTable } from '@/features/detail/detail-ui';
import { safeRpc } from '@/features/shared/server-rpc';
import { formatDate, formatMoney } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

type Allocation = { fee: string; amount: number };

type Receipt = {
  fee_receipt_id: number;
  receipt_number: string;
  receipt_date: string;
  receipt_amount: number;
  receipt_status: string;
  cancellation_reason: string | null;
  original_receipt_id: number | null;
  transaction_number: string;
  transaction_date: string;
  payment_mode: string;
  bank_reference: string | null;
  payer_name: string | null;
  account_number: string;
  student_account_id: number;
  student_number: string;
  student_name: string;
  allocations: Allocation[];
  can_cancel: boolean;
};

/**
 * A fee receipt.
 *
 * `fin_receipt_get` is SECURITY DEFINER and checks `FEES.FEE_PAYMENT.READ`
 * against the student the receipt belongs to.
 */
export default async function FinanceReceiptPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { supabase } = await requireContext();

  const receiptId = Number(id);
  if (!Number.isInteger(receiptId) || receiptId <= 0) notFound();

  const { data, error } = await safeRpc<Receipt>(supabase, 'fin_receipt_get', { p_receipt_id: receiptId });
  const receipt = data;

  if (!receipt) {
    return (
      <>
        <PageHeader title="Receipt" description={`Receipt #${receiptId}`} />
        <p className="rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800" role="alert">
          {error ?? 'This receipt does not exist or is not visible to you.'}
        </p>
        <div className="mt-4">
          <Link href="/finance">
            <Button variant="outline">Back to fees</Button>
          </Link>
        </div>
      </>
    );
  }

  return (
    <>
      <PageHeader
        title={receipt.receipt_number}
        description={`Receipt for ${receipt.student_name}`}
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

        <DetailFields
          title="Receipt"
          fields={[
            { label: 'Receipt number', value: receipt.receipt_number },
            { label: 'Receipt date', value: formatDate(receipt.receipt_date) },
            { label: 'Amount', value: formatMoney(receipt.receipt_amount) },
            {
              label: 'Status',
              value: <Badge variant={statusVariant(receipt.receipt_status)}>{receipt.receipt_status}</Badge>,
            },
            { label: 'Transaction', value: receipt.transaction_number },
            { label: 'Transaction date', value: formatDate(receipt.transaction_date) },
            { label: 'Payment mode', value: receipt.payment_mode },
            { label: 'Bank reference', value: receipt.bank_reference ?? '—' },
            { label: 'Payer', value: receipt.payer_name ?? '—' },
            { label: 'Student number', value: receipt.student_number },
            { label: 'Student', value: receipt.student_name },
            { label: 'Account', value: receipt.account_number },
            { label: 'Cancellation reason', value: receipt.cancellation_reason ?? '—' },
            { label: 'Replaces receipt', value: receipt.original_receipt_id ?? '—' },
          ]}
        />

        <Card>
          <CardHeader>
            <CardTitle>Allocations</CardTitle>
          </CardHeader>
          <CardContent>
            <DetailTable
              rows={receipt.allocations ?? []}
              rowKey={(r, i) => `${r.fee}-${i}`}
              emptyTitle="No allocations"
              emptyDescription="The payment was not split across any fee items."
              columns={[
                { key: 'fee', header: 'Fee', render: (r) => r.fee },
                { key: 'amount', header: 'Amount', numeric: true, render: (r) => formatMoney(r.amount) },
              ]}
            />
          </CardContent>
        </Card>
      </DetailStack>
    </>
  );
}
