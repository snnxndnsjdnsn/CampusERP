'use client';

import { useState } from 'react';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input, Select, Textarea } from '@/components/ui/input';
import { rpcCall, useRpcAction } from '@/features/shared/client-rpc';
import { formatDate, formatDateTime } from '@/lib/format';
import type {
  AccountInfo,
  AssessmentItemRow,
  AssessmentRow,
  Option,
  PaymentRow,
  ReceiptDetail,
} from './types';
import { Field, FormError, Money, ReadError, today } from './ui';

/**
 * Assessments and payments.
 *
 * Assessments are priced with `fin_create_fee_assessment`; payments are recorded
 * with `fin_record_payment` and then allocated to the fee items they settle.
 */

const ASSESSMENT_TYPES = [
  'ADMISSION',
  'ACADEMIC',
  'EXAMINATION',
  'HOSTEL',
  'TRANSPORT',
  'LIBRARY',
  'CERTIFICATE',
  'PENALTY',
  'SERVICE',
  'OTHER',
];

type DraftItem = {
  fee_type_id: string;
  original_amount: string;
  concession_amount: string;
  scholarship_amount: string;
  adjustment_amount: string;
  description: string;
  due_date: string;
};

function emptyDraft(): DraftItem {
  return {
    fee_type_id: '',
    original_amount: '',
    concession_amount: '',
    scholarship_amount: '',
    adjustment_amount: '',
    description: '',
    due_date: '',
  };
}

function num(value: string): number | null {
  const trimmed = value.trim();
  if (!trimmed) return null;
  const n = Number(trimmed);
  return Number.isFinite(n) ? n : null;
}

/* ------------------------------------------------------------------ */
/* Assessments                                                         */
/* ------------------------------------------------------------------ */

export function AssessmentPanel({
  account,
  assessments,
  items,
  feeTypes,
  years,
  lateFeeRules,
  readError,
}: {
  account: AccountInfo;
  assessments: AssessmentRow[];
  items: AssessmentItemRow[];
  feeTypes: Option[];
  years: Option[];
  lateFeeRules: Option[];
  readError: string | null;
}) {
  const [creating, setCreating] = useState(false);

  return (
    <div className="space-y-4">
      <ReadError message={readError} />

      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-sm text-muted-foreground">
          {assessments.length} assessment{assessments.length === 1 ? '' : 's'} on this account.
        </p>
        <Button size="sm" onClick={() => setCreating((v) => !v)}>
          {creating ? 'Close the form' : 'New assessment'}
        </Button>
      </div>

      {creating ? (
        <div className="rounded-lg border border-border bg-card p-4">
          <h3 className="mb-3 text-sm font-semibold">Create an assessment</h3>
          <AssessmentForm
            account={account}
            feeTypes={feeTypes}
            years={years}
            onSaved={() => setCreating(false)}
          />
        </div>
      ) : null}

      <div className="overflow-x-auto rounded-lg border border-border">
        <table className="w-full text-sm">
          <thead className="border-b bg-muted/40">
            <tr>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Assessment</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Type</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Due</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Net</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Paid</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Balance</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Status</th>
            </tr>
          </thead>
          <tbody>
            {assessments.length === 0 ? (
              <tr>
                <td colSpan={7} className="px-3 py-6 text-center text-sm text-muted-foreground">
                  This account has no assessments yet.
                </td>
              </tr>
            ) : (
              assessments.map((a) => (
                <tr key={a.fee_assessment_id} className="border-b last:border-0">
                  <td className="px-3 py-2">
                    <div className="font-medium">{a.assessment_number}</div>
                    <div className="text-xs text-muted-foreground">{formatDate(a.assessment_date)}</div>
                  </td>
                  <td className="px-3 py-2">{a.assessment_type}</td>
                  <td className="px-3 py-2">{a.due_date ? formatDate(a.due_date) : '—'}</td>
                  <td className="px-3 py-2 text-right">
                    <Money value={a.net_payable_amount} />
                  </td>
                  <td className="px-3 py-2 text-right">
                    <Money value={a.amount_paid} />
                  </td>
                  <td className="px-3 py-2 text-right">
                    <Money value={a.balance_amount} />
                  </td>
                  <td className="px-3 py-2">
                    <Badge variant={statusVariant(a.assessment_status)}>{a.assessment_status}</Badge>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      <AssessmentItems assessments={assessments} items={items} />

      <div className="grid gap-4 lg:grid-cols-2">
        <PenaltyForm account={account} feeTypes={feeTypes} years={years} />
        <LateFeePanel assessments={assessments} lateFeeRules={lateFeeRules} />
      </div>
    </div>
  );
}

function AssessmentItems({ assessments, items }: { assessments: AssessmentRow[]; items: AssessmentItemRow[] }) {
  if (assessments.length === 0) return null;

  return (
    <div className="overflow-x-auto rounded-lg border border-border">
      <table className="w-full text-sm">
        <thead className="border-b bg-muted/40">
          <tr>
            <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Item</th>
            <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Assessment</th>
            <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Original</th>
            <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Concession</th>
            <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Scholarship</th>
            <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Balance</th>
            <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Status</th>
          </tr>
        </thead>
        <tbody>
          {items.length === 0 ? (
            <tr>
              <td colSpan={7} className="px-3 py-6 text-center text-sm text-muted-foreground">
                No fee items are visible on this account.
              </td>
            </tr>
          ) : (
            items.map((item) => {
              const parent = assessments.find((a) => a.fee_assessment_id === item.fee_assessment_id);
              return (
                <tr key={item.assessment_item_id} className="border-b last:border-0">
                  <td className="px-3 py-2">
                    <div className="font-medium">#{item.assessment_item_id}</div>
                    {item.description ? <div className="text-xs text-muted-foreground">{item.description}</div> : null}
                  </td>
                  <td className="px-3 py-2">{parent?.assessment_number ?? `#${item.fee_assessment_id}`}</td>
                  <td className="px-3 py-2 text-right">
                    <Money value={item.original_amount} />
                  </td>
                  <td className="px-3 py-2 text-right">
                    <Money value={item.concession_amount} />
                  </td>
                  <td className="px-3 py-2 text-right">
                    <Money value={item.scholarship_amount} />
                  </td>
                  <td className="px-3 py-2 text-right">
                    <Money value={item.balance_amount} />
                  </td>
                  <td className="px-3 py-2">
                    <Badge variant={statusVariant(item.item_status)}>{item.item_status}</Badge>
                  </td>
                </tr>
              );
            })
          )}
        </tbody>
      </table>
    </div>
  );
}

function AssessmentForm({
  account,
  feeTypes,
  years,
  onSaved,
}: {
  account: AccountInfo;
  feeTypes: Option[];
  years: Option[];
  onSaved: () => void;
}) {
  const { run, busy, error } = useRpcAction();
  const [drafts, setDrafts] = useState<DraftItem[]>([emptyDraft()]);

  function update(index: number, key: keyof DraftItem, value: string) {
    setDrafts((current) => current.map((d, i) => (i === index ? { ...d, [key]: value } : d)));
  }

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const str = (key: string) => String(form.get(key) ?? '').trim();

    const p_items = drafts
      .filter((d) => d.fee_type_id && num(d.original_amount) !== null)
      .map((d) => {
        const item: Record<string, unknown> = {
          fee_type_id: Number(d.fee_type_id),
          original_amount: num(d.original_amount),
          concession_amount: num(d.concession_amount) ?? 0,
          scholarship_amount: num(d.scholarship_amount) ?? 0,
          adjustment_amount: num(d.adjustment_amount) ?? 0,
        };
        if (d.description.trim()) item.description = d.description.trim();
        if (d.due_date) item.due_date = d.due_date;
        return item;
      });

    if (p_items.length === 0) {
      return;
    }

    const result = await run<number>('fin_create_fee_assessment', {
      p_assessment_number: str('assessment_number'),
      p_student_account_id: account.student_account_id,
      p_academic_year_id: Number(str('academic_year_id')),
      p_assessment_type: str('assessment_type'),
      p_assessment_date: str('assessment_date'),
      p_due_date: str('due_date') || null,
      p_items,
    });
    if (result.ok) onSaved();
  }

  return (
    <form onSubmit={submit} className="space-y-4" noValidate>
      <div className="grid gap-4 md:grid-cols-3">
        <Field label="Assessment number" htmlFor="assessment_number" hint="The idempotency key.">
          <Input id="assessment_number" name="assessment_number" required maxLength={50} placeholder="ASS-2026-0001" />
        </Field>
        <Field label="Academic year" htmlFor="assessment_year">
          <Select id="assessment_year" name="academic_year_id" required defaultValue="">
            <option value="">Select a year</option>
            {years.map((o) => (
              <option key={o.id} value={o.id}>
                {o.label}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Assessment type" htmlFor="assessment_type">
          <Select id="assessment_type" name="assessment_type" required defaultValue="ACADEMIC">
            {ASSESSMENT_TYPES.map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Assessment date" htmlFor="assessment_date">
          <Input id="assessment_date" name="assessment_date" type="date" required defaultValue={today()} />
        </Field>
        <Field label="Due date" htmlFor="assessment_due_date" hint="Optional.">
          <Input id="assessment_due_date" name="due_date" type="date" />
        </Field>
      </div>

      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <h4 className="text-sm font-semibold">Fee items</h4>
          <Button size="sm" variant="outline" type="button" onClick={() => setDrafts((d) => [...d, emptyDraft()])}>
            Add item
          </Button>
        </div>
        {drafts.map((draft, index) => (
          <div key={index} className="grid gap-3 rounded-lg border border-border p-3 md:grid-cols-4">
            <Field label="Fee type" htmlFor={`draft_fee_type_${index}`}>
              <Select
                id={`draft_fee_type_${index}`}
                value={draft.fee_type_id}
                onChange={(e) => update(index, 'fee_type_id', e.target.value)}
                required
              >
                <option value="">Select a fee type</option>
                {feeTypes.map((o) => (
                  <option key={o.id} value={o.id}>
                    {o.label}
                  </option>
                ))}
              </Select>
            </Field>
            <Field label="Amount" htmlFor={`draft_amount_${index}`}>
              <Input
                id={`draft_amount_${index}`}
                type="number"
                step="0.01"
                min="0"
                value={draft.original_amount}
                onChange={(e) => update(index, 'original_amount', e.target.value)}
                required
              />
            </Field>
            <Field label="Concession" htmlFor={`draft_concession_${index}`}>
              <Input
                id={`draft_concession_${index}`}
                type="number"
                step="0.01"
                min="0"
                value={draft.concession_amount}
                onChange={(e) => update(index, 'concession_amount', e.target.value)}
              />
            </Field>
            <Field label="Scholarship" htmlFor={`draft_scholarship_${index}`}>
              <Input
                id={`draft_scholarship_${index}`}
                type="number"
                step="0.01"
                min="0"
                value={draft.scholarship_amount}
                onChange={(e) => update(index, 'scholarship_amount', e.target.value)}
              />
            </Field>
            <Field label="Adjustment" htmlFor={`draft_adjustment_${index}`}>
              <Input
                id={`draft_adjustment_${index}`}
                type="number"
                step="0.01"
                value={draft.adjustment_amount}
                onChange={(e) => update(index, 'adjustment_amount', e.target.value)}
              />
            </Field>
            <Field label="Description" htmlFor={`draft_description_${index}`}>
              <Input
                id={`draft_description_${index}`}
                maxLength={250}
                value={draft.description}
                onChange={(e) => update(index, 'description', e.target.value)}
              />
            </Field>
            <Field label="Due date" htmlFor={`draft_due_${index}`}>
              <Input
                id={`draft_due_${index}`}
                type="date"
                value={draft.due_date}
                onChange={(e) => update(index, 'due_date', e.target.value)}
              />
            </Field>
            <div className="flex items-end">
              <Button
                type="button"
                size="sm"
                variant="ghost"
                disabled={drafts.length === 1}
                onClick={() => setDrafts((d) => d.filter((_, i) => i !== index))}
              >
                Remove
              </Button>
            </div>
          </div>
        ))}
      </div>

      <FormError message={error} />
      <Button type="submit" disabled={busy}>
        {busy ? 'Creating…' : 'Create assessment'}
      </Button>
    </form>
  );
}

function PenaltyForm({
  account,
  feeTypes,
  years,
}: {
  account: AccountInfo;
  feeTypes: Option[];
  years: Option[];
}) {
  const { run, busy, error } = useRpcAction();

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const str = (key: string) => String(form.get(key) ?? '').trim();
    const result = await run<number>('fin_penalty_assess', {
      p_student_account_id: account.student_account_id,
      p_fee_type_id: Number(str('fee_type_id')),
      p_amount: Number(str('amount')),
      p_reason: str('reason'),
      p_academic_year_id: Number(str('academic_year_id')),
      p_due_date: str('due_date') || null,
    });
    if (result.ok) event.currentTarget.reset();
  }

  return (
    <form onSubmit={submit} className="space-y-3 rounded-lg border border-border bg-card p-4" noValidate>
      <h3 className="text-sm font-semibold">Assess a penalty</h3>
      <div className="grid gap-3 md:grid-cols-2">
        <Field label="Fee type" htmlFor="penalty_fee_type">
          <Select id="penalty_fee_type" name="fee_type_id" required defaultValue="">
            <option value="">Select a fee type</option>
            {feeTypes.map((o) => (
              <option key={o.id} value={o.id}>
                {o.label}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Amount" htmlFor="penalty_amount">
          <Input id="penalty_amount" name="amount" type="number" step="0.01" min="0" required />
        </Field>
        <Field label="Academic year" htmlFor="penalty_year">
          <Select id="penalty_year" name="academic_year_id" required defaultValue="">
            <option value="">Select a year</option>
            {years.map((o) => (
              <option key={o.id} value={o.id}>
                {o.label}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Due date" htmlFor="penalty_due_date">
          <Input id="penalty_due_date" name="due_date" type="date" />
        </Field>
      </div>
      <Field label="Reason" htmlFor="penalty_reason">
        <Textarea id="penalty_reason" name="reason" rows={2} maxLength={500} required />
      </Field>
      <FormError message={error} />
      <Button type="submit" disabled={busy}>
        {busy ? 'Assessing…' : 'Assess penalty'}
      </Button>
    </form>
  );
}

function LateFeePanel({
  assessments,
  lateFeeRules,
}: {
  assessments: AssessmentRow[];
  lateFeeRules: Option[];
}) {
  const [assessmentId, setAssessmentId] = useState('');
  const [ruleId, setRuleId] = useState('');
  const [asOf, setAsOf] = useState(today());
  const [amount, setAmount] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function suggest() {
    if (!assessmentId || !ruleId) return;
    setBusy(true);
    setError(null);
    setAmount(null);
    const result = await rpcCall<number>('fin_late_fee_suggest', {
      p_assessment_id: Number(assessmentId),
      p_rule_id: Number(ruleId),
      p_as_of: asOf,
    });
    setBusy(false);
    if (!result.ok) {
      setError(result.error);
      return;
    }
    setAmount(String(result.data ?? 0));
  }

  return (
    <div className="space-y-3 rounded-lg border border-border bg-card p-4">
      <h3 className="text-sm font-semibold">Late-fee suggestion</h3>
      <p className="text-sm text-muted-foreground">
        The database prices the rule against the assessment; nothing is calculated in the browser.
      </p>
      <div className="grid gap-3 md:grid-cols-3">
        <Field label="Assessment" htmlFor="late_assessment">
          <Select id="late_assessment" value={assessmentId} onChange={(e) => setAssessmentId(e.target.value)}>
            <option value="">Select an assessment</option>
            {assessments.map((a) => (
              <option key={a.fee_assessment_id} value={a.fee_assessment_id}>
                {a.assessment_number}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Late-fee rule" htmlFor="late_rule">
          <Select id="late_rule" value={ruleId} onChange={(e) => setRuleId(e.target.value)}>
            <option value="">Select a rule</option>
            {lateFeeRules.map((o) => (
              <option key={o.id} value={o.id}>
                {o.label}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="As of" htmlFor="late_as_of">
          <Input id="late_as_of" type="date" value={asOf} onChange={(e) => setAsOf(e.target.value)} />
        </Field>
      </div>
      <FormError message={error} />
      <div className="flex items-center gap-3">
        <Button size="sm" variant="outline" disabled={busy || !assessmentId || !ruleId} onClick={() => void suggest()}>
          {busy ? 'Calculating…' : 'Suggest late fee'}
        </Button>
        {amount !== null ? (
          <span className="text-sm font-medium tabular-nums">
            Suggested late fee: <Money value={amount} />
          </span>
        ) : null}
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Payments and receipts                                               */
/* ------------------------------------------------------------------ */

export function PaymentPanel({
  account,
  payments,
  items,
  paymentModes,
  readError,
}: {
  account: AccountInfo;
  payments: PaymentRow[];
  items: AssessmentItemRow[];
  paymentModes: Option[];
  readError: string | null;
}) {
  return (
    <div className="space-y-4">
      <ReadError message={readError} />

      <div className="grid gap-4 lg:grid-cols-2">
        <RecordPaymentForm account={account} paymentModes={paymentModes} />
        <AllocatePaymentForm payments={payments} items={items} />
      </div>

      <div className="overflow-x-auto rounded-lg border border-border">
        <table className="w-full text-sm">
          <thead className="border-b bg-muted/40">
            <tr>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Transaction</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Date</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Mode</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Amount</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Payment</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Receipt</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Actions</th>
            </tr>
          </thead>
          <tbody>
            {payments.length === 0 ? (
              <tr>
                <td colSpan={7} className="px-3 py-6 text-center text-sm text-muted-foreground">
                  No payments have been recorded on this account.
                </td>
              </tr>
            ) : (
              payments.map((p) => (
                <PaymentRowView key={p.payment_transaction_id} payment={p} />
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function PaymentRowView({ payment }: { payment: PaymentRow }) {
  const { run, busy, error } = useRpcAction();
  const [receipt, setReceipt] = useState<ReceiptDetail | null>(null);
  const [reason, setReason] = useState('');

  async function viewReceipt() {
    if (!payment.fee_receipt_id) return;
    const result = await rpcCall<ReceiptDetail>('fin_receipt_get', { p_receipt_id: payment.fee_receipt_id });
    if (result.ok) setReceipt(result.data);
  }

  return (
    <>
      <tr className="border-b last:border-0 hover:bg-muted/40">
        <td className="px-3 py-2 font-medium">{payment.transaction_number}</td>
        <td className="px-3 py-2">{formatDateTime(payment.transaction_date)}</td>
        <td className="px-3 py-2">{payment.mode_name}</td>
        <td className="px-3 py-2 text-right">
          <Money value={payment.amount} />
        </td>
        <td className="px-3 py-2">
          <Badge variant={statusVariant(payment.payment_status)}>{payment.payment_status}</Badge>
        </td>
        <td className="px-3 py-2">
          {payment.receipt_number ? (
            <div>
              <div className="font-medium">{payment.receipt_number}</div>
              {payment.receipt_status ? (
                <Badge variant={statusVariant(payment.receipt_status)}>{payment.receipt_status}</Badge>
              ) : null}
            </div>
          ) : (
            <span className="text-muted-foreground">—</span>
          )}
        </td>
        <td className="px-3 py-2 text-right">
          <div className="flex flex-wrap justify-end gap-2">
            {payment.receipt_status === 'ISSUED' ? (
              <Button size="sm" variant="outline" disabled={busy} onClick={() => void viewReceipt()}>
                Receipt
              </Button>
            ) : null}
            {payment.payment_status === 'SUCCESS' && !payment.fee_receipt_id ? (
              <Button
                size="sm"
                variant="outline"
                disabled={busy}
                onClick={() => void run('fin_issue_receipt', { p_payment_transaction_id: payment.payment_transaction_id })}
              >
                Issue receipt
              </Button>
            ) : null}
          </div>
        </td>
      </tr>
      {payment.receipt_status === 'ISSUED' ? (
        <tr className="border-b bg-muted/20 last:border-0">
          <td colSpan={7} className="px-3 py-2">
            <ReadError message={error} />
            <div className="flex flex-wrap items-end gap-2">
              <div className="min-w-[16rem] flex-1">
                <Field label="Cancellation reason" htmlFor={`cancel_reason_${payment.fee_receipt_id}`}>
                  <Input
                    id={`cancel_reason_${payment.fee_receipt_id}`}
                    value={reason}
                    onChange={(e) => setReason(e.target.value)}
                    maxLength={500}
                    placeholder="Required to cancel a receipt"
                  />
                </Field>
              </div>
              <Button
                size="sm"
                variant="destructive"
                disabled={busy || !reason.trim()}
                onClick={() =>
                  void run('fin_cancel_receipt', {
                    p_receipt_id: payment.fee_receipt_id,
                    p_reason: reason.trim(),
                    p_replace: false,
                  }).then((r) => {
                    if (r.ok) setReason('');
                  })
                }
              >
                Cancel receipt
              </Button>
              <Button
                size="sm"
                variant="outline"
                disabled={busy || !reason.trim()}
                onClick={() =>
                  void run('fin_cancel_receipt', {
                    p_receipt_id: payment.fee_receipt_id,
                    p_reason: reason.trim(),
                    p_replace: true,
                  }).then((r) => {
                    if (r.ok) setReason('');
                  })
                }
              >
                Cancel and replace
              </Button>
            </div>
          </td>
        </tr>
      ) : null}
      {receipt ? (
        <tr className="border-b bg-muted/20 last:border-0">
          <td colSpan={7} className="px-3 py-3">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <p className="text-sm font-semibold">Receipt {receipt.receipt_number}</p>
                <p className="text-xs text-muted-foreground">
                  {receipt.student_name} · {receipt.student_number} · {receipt.account_number}
                </p>
                <p className="text-xs text-muted-foreground">
                  {receipt.payment_mode}
                  {receipt.bank_reference ? ` · ${receipt.bank_reference}` : ''}
                  {receipt.payer_name ? ` · ${receipt.payer_name}` : ''}
                </p>
                <ul className="mt-2 space-y-1 text-xs">
                  {receipt.allocations.map((a, i) => (
                    <li key={i} className="flex justify-between gap-6">
                      <span>{a.fee}</span>
                      <span className="tabular-nums">
                        <Money value={a.amount} />
                      </span>
                    </li>
                  ))}
                </ul>
              </div>
              <div className="text-right">
                <div className="text-xs uppercase tracking-wide text-muted-foreground">Amount</div>
                <div className="text-lg font-semibold tabular-nums">
                  <Money value={receipt.receipt_amount} />
                </div>
                <Button size="sm" variant="ghost" className="mt-2" onClick={() => setReceipt(null)}>
                  Close
                </Button>
              </div>
            </div>
          </td>
        </tr>
      ) : null}
    </>
  );
}

function RecordPaymentForm({ account, paymentModes }: { account: AccountInfo; paymentModes: Option[] }) {
  const { run, busy, error } = useRpcAction();

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const str = (key: string) => String(form.get(key) ?? '').trim();
    const result = await run<number>('fin_record_payment', {
      p_transaction_number: str('transaction_number'),
      p_student_account_id: account.student_account_id,
      p_payment_mode_id: Number(str('payment_mode_id')),
      p_amount: Number(str('amount')),
      p_bank_reference: str('bank_reference') || null,
      p_payer_name: str('payer_name') || null,
      p_remarks: str('remarks') || null,
    });
    if (result.ok) event.currentTarget.reset();
  }

  return (
    <form onSubmit={submit} className="space-y-3 rounded-lg border border-border bg-card p-4" noValidate>
      <h3 className="text-sm font-semibold">Record a payment</h3>
      <div className="grid gap-3 md:grid-cols-2">
        <Field label="Transaction number" htmlFor="transaction_number" hint="The idempotency key.">
          <Input id="transaction_number" name="transaction_number" required maxLength={60} placeholder="PAY-2026-0001" />
        </Field>
        <Field label="Payment mode" htmlFor="payment_mode_id">
          <Select id="payment_mode_id" name="payment_mode_id" required defaultValue="">
            <option value="">Select a mode</option>
            {paymentModes.map((o) => (
              <option key={o.id} value={o.id}>
                {o.label}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Amount" htmlFor="payment_amount">
          <Input id="payment_amount" name="amount" type="number" step="0.01" min="0" required />
        </Field>
        <Field label="Bank reference" htmlFor="bank_reference" hint="Required by some modes.">
          <Input id="bank_reference" name="bank_reference" maxLength={100} />
        </Field>
        <Field label="Payer name" htmlFor="payer_name">
          <Input id="payer_name" name="payer_name" maxLength={200} />
        </Field>
        <Field label="Remarks" htmlFor="payment_remarks">
          <Input id="payment_remarks" name="remarks" maxLength={500} />
        </Field>
      </div>
      <FormError message={error} />
      <Button type="submit" disabled={busy}>
        {busy ? 'Recording…' : 'Record payment'}
      </Button>
    </form>
  );
}

function AllocatePaymentForm({
  payments,
  items,
}: {
  payments: PaymentRow[];
  items: AssessmentItemRow[];
}) {
  const { run, busy, error } = useRpcAction();
  const [paymentId, setPaymentId] = useState('');
  const [itemId, setItemId] = useState('');
  const [amount, setAmount] = useState('');

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!paymentId || !itemId) return;
    const result = await run<number>('fin_allocate_payment', {
      p_payment_transaction_id: Number(paymentId),
      p_assessment_item_id: Number(itemId),
      p_amount: Number(amount),
    });
    if (result.ok) {
      setAmount('');
      setItemId('');
    }
  }

  return (
    <form onSubmit={submit} className="space-y-3 rounded-lg border border-border bg-card p-4" noValidate>
      <h3 className="text-sm font-semibold">Allocate a payment to a fee item</h3>
      <div className="grid gap-3 md:grid-cols-2">
        <Field label="Payment" htmlFor="allocate_payment">
          <Select id="allocate_payment" value={paymentId} onChange={(e) => setPaymentId(e.target.value)} required>
            <option value="">Select a payment</option>
            {payments.map((p) => (
              <option key={p.payment_transaction_id} value={p.payment_transaction_id}>
                {p.transaction_number} — {p.amount}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Fee item" htmlFor="allocate_item">
          <Select id="allocate_item" value={itemId} onChange={(e) => setItemId(e.target.value)} required>
            <option value="">Select a fee item</option>
            {items.map((i) => (
              <option key={i.assessment_item_id} value={i.assessment_item_id}>
                #{i.assessment_item_id} — balance {i.balance_amount}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Amount" htmlFor="allocate_amount">
          <Input
            id="allocate_amount"
            type="number"
            step="0.01"
            min="0"
            value={amount}
            onChange={(e) => setAmount(e.target.value)}
            required
          />
        </Field>
      </div>
      <FormError message={error} />
      <Button type="submit" disabled={busy || !paymentId || !itemId}>
        {busy ? 'Allocating…' : 'Allocate'}
      </Button>
    </form>
  );
}
