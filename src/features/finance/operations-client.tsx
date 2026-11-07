'use client';

import { useState } from 'react';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input, Select, Textarea } from '@/components/ui/input';
import { useRpcAction } from '@/features/shared/client-rpc';
import { formatDate } from '@/lib/format';
import type {
  AccountExtras,
  AccountInfo,
  AssessmentItemRow,
  AssessmentRow,
  HoldRow,
  Option,
  PaymentRow,
  RefundRow,
} from './types';
import { Field, FormError, Money, ReadError, today } from './ui';

/**
 * Holds, benefits, refunds and instalments.
 *
 * Each panel maps onto one family of `fin_*` functions. The database owns the
 * workflow: the browser only sends the move and shows the refusal.
 */

const HOLD_TYPES = [
  'REGISTRATION',
  'EXAMINATION',
  'HALL_TICKET',
  'RESULT',
  'CERTIFICATE',
  'HOSTEL_CHECKOUT',
  'GRADUATION',
  'OTHER',
];

const BENEFIT_KINDS = ['CONCESSION', 'SCHOLARSHIP', 'SPONSORSHIP'];
const ADJUSTMENT_TYPES = ['CREDIT', 'DEBIT', 'WAIVER', 'WRITE_OFF'];

/* ------------------------------------------------------------------ */
/* Holds                                                               */
/* ------------------------------------------------------------------ */

export function HoldPanel({
  account,
  holds,
  readError,
}: {
  account: AccountInfo;
  holds: HoldRow[];
  readError: string | null;
}) {
  const { run, busy, error } = useRpcAction();
  const [reasons, setReasons] = useState<Record<number, string>>({});

  async function place(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const str = (key: string) => String(form.get(key) ?? '').trim();
    const result = await run<number>('fin_hold_place', {
      p_student_account_id: account.student_account_id,
      p_hold_type: str('hold_type'),
      p_reason: str('reason'),
    });
    if (result.ok) event.currentTarget.reset();
  }

  return (
    <div className="space-y-4">
      <ReadError message={readError ?? error} />

      <form onSubmit={place} className="rounded-lg border border-border bg-card p-4" noValidate>
        <h3 className="text-sm font-semibold">Place a hold</h3>
        <p className="mt-1 text-sm text-muted-foreground">
          A hold blocks the services it names until it is released.
        </p>
        <div className="mt-3 grid gap-3 md:grid-cols-3">
          <Field label="Hold type" htmlFor="hold_type">
            <Select id="hold_type" name="hold_type" required defaultValue="">
              <option value="">Select a type</option>
              {HOLD_TYPES.map((t) => (
                <option key={t} value={t}>
                  {t}
                </option>
              ))}
            </Select>
          </Field>
          <div className="md:col-span-2">
            <Field label="Reason" htmlFor="hold_reason">
              <Textarea id="hold_reason" name="reason" rows={2} maxLength={500} required />
            </Field>
          </div>
        </div>
        <div className="mt-3">
          <Button type="submit" disabled={busy}>
            {busy ? 'Placing…' : 'Place hold'}
          </Button>
        </div>
      </form>

      <div className="overflow-x-auto rounded-lg border border-border">
        <table className="w-full text-sm">
          <thead className="border-b bg-muted/40">
            <tr>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Type</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Reason</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Placed</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Status</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Actions</th>
            </tr>
          </thead>
          <tbody>
            {holds.length === 0 ? (
              <tr>
                <td colSpan={5} className="px-3 py-6 text-center text-sm text-muted-foreground">
                  No holds are recorded on this account.
                </td>
              </tr>
            ) : (
              holds.map((h) => (
                <tr key={h.financial_hold_id} className="border-b last:border-0">
                  <td className="px-3 py-2 font-medium">{h.hold_type}</td>
                  <td className="px-3 py-2">{h.hold_reason}</td>
                  <td className="px-3 py-2">{formatDate(h.placed_at)}</td>
                  <td className="px-3 py-2">
                    <Badge variant={statusVariant(h.hold_status)}>{h.hold_status}</Badge>
                  </td>
                  <td className="px-3 py-2 text-right">
                    {h.hold_status === 'ACTIVE' ? (
                      <div className="flex flex-wrap items-center justify-end gap-2">
                        <Input
                          value={reasons[h.financial_hold_id] ?? ''}
                          onChange={(e) => setReasons((r) => ({ ...r, [h.financial_hold_id]: e.target.value }))}
                          maxLength={500}
                          placeholder="Release reason"
                          className="h-8 w-48 text-xs"
                          aria-label={`Release reason for hold ${h.financial_hold_id}`}
                        />
                        <Button
                          size="sm"
                          variant="outline"
                          disabled={busy || !(reasons[h.financial_hold_id] ?? '').trim()}
                          onClick={() =>
                            void run('fin_hold_release', {
                              p_hold_id: h.financial_hold_id,
                              p_reason: (reasons[h.financial_hold_id] ?? '').trim(),
                            }).then((r) => {
                              if (r.ok) setReasons((current) => ({ ...current, [h.financial_hold_id]: '' }));
                            })
                          }
                        >
                          Release
                        </Button>
                      </div>
                    ) : (
                      <span className="text-xs text-muted-foreground">{h.release_reason ?? '—'}</span>
                    )}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Benefits, adjustments and penalties                                 */
/* ------------------------------------------------------------------ */

export function BenefitPanel({
  account,
  extras,
  items,
  concessionTypes,
  scholarshipSchemes,
  years,
  readError,
}: {
  account: AccountInfo;
  extras: AccountExtras;
  items: AssessmentItemRow[];
  concessionTypes: Option[];
  scholarshipSchemes: Option[];
  years: Option[];
  readError: string | null;
}) {
  return (
    <div className="space-y-6">
      <ReadError message={readError} />

      <section className="space-y-3">
        <h3 className="text-sm font-semibold">Benefits and concessions</h3>
        <BenefitCreateForm
          account={account}
          concessionTypes={concessionTypes}
          scholarshipSchemes={scholarshipSchemes}
          years={years}
        />
        <BenefitTable extras={extras} items={items} />
      </section>

      <section className="space-y-3">
        <h3 className="text-sm font-semibold">Adjustments</h3>
        <AdjustmentCreateForm account={account} items={items} />
        <AdjustmentTable extras={extras} />
      </section>

      <section className="space-y-3">
        <h3 className="text-sm font-semibold">Penalties</h3>
        <PenaltyTable extras={extras} />
      </section>
    </div>
  );
}

function BenefitCreateForm({
  account,
  concessionTypes,
  scholarshipSchemes,
  years,
}: {
  account: AccountInfo;
  concessionTypes: Option[];
  scholarshipSchemes: Option[];
  years: Option[];
}) {
  const { run, busy, error } = useRpcAction();
  const [kind, setKind] = useState('CONCESSION');

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const str = (key: string) => String(form.get(key) ?? '').trim();
    const amount = str('amount');
    const percentage = str('percentage');
    const result = await run<number>('fin_benefit_create', {
      p_kind: kind,
      p_student_id: account.student_id,
      p_academic_year_id: Number(str('academic_year_id')),
      p_type_id: Number(str('type_id')),
      p_amount: amount ? Number(amount) : null,
      p_percentage: percentage ? Number(percentage) : null,
      p_reference: str('reference') || null,
      p_authority: str('authority') || null,
      p_remarks: str('remarks') || null,
    });
    if (result.ok) event.currentTarget.reset();
  }

  return (
    <form onSubmit={submit} className="space-y-3 rounded-lg border border-border bg-card p-4" noValidate>
      <h4 className="text-sm font-semibold">Request a benefit</h4>
      <div className="grid gap-3 md:grid-cols-3">
        <Field label="Kind" htmlFor="benefit_kind">
          <Select id="benefit_kind" value={kind} onChange={(e) => setKind(e.target.value)}>
            {BENEFIT_KINDS.map((k) => (
              <option key={k} value={k}>
                {k}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Academic year" htmlFor="benefit_year">
          <Select id="benefit_year" name="academic_year_id" required defaultValue="">
            <option value="">Select a year</option>
            {years.map((o) => (
              <option key={o.id} value={o.id}>
                {o.label}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Type" htmlFor="benefit_type_id">
          {kind === 'SCHOLARSHIP' ? (
            <Select id="benefit_type_id" name="type_id" required defaultValue="">
              <option value="">Select a scheme</option>
              {scholarshipSchemes.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.label}
                </option>
              ))}
            </Select>
          ) : kind === 'CONCESSION' ? (
            <Select id="benefit_type_id" name="type_id" required defaultValue="">
              <option value="">Select a concession type</option>
              {concessionTypes.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.label}
                </option>
              ))}
            </Select>
          ) : (
            <Input id="benefit_type_id" name="type_id" type="number" hidden readOnly value={0} />
          )}
        </Field>
        <Field label="Amount" htmlFor="benefit_amount" hint="Required for scholarships and sponsorships.">
          <Input id="benefit_amount" name="amount" type="number" step="0.01" min="0" />
        </Field>
        <Field label="Percentage" htmlFor="benefit_percentage" hint="For percentage-based concessions.">
          <Input id="benefit_percentage" name="percentage" type="number" step="0.01" min="0" max="100" />
        </Field>
        <Field label="Reference" htmlFor="benefit_reference" hint="Required for sponsorships.">
          <Input id="benefit_reference" name="reference" maxLength={100} />
        </Field>
        <Field label="Authority" htmlFor="benefit_authority" hint="Required for sponsorships.">
          <Input id="benefit_authority" name="authority" maxLength={200} />
        </Field>
        <div className="md:col-span-3">
          <Field label="Remarks" htmlFor="benefit_remarks">
            <Input id="benefit_remarks" name="remarks" maxLength={500} />
          </Field>
        </div>
      </div>
      <FormError message={error} />
      <Button type="submit" disabled={busy}>
        {busy ? 'Requesting…' : 'Request benefit'}
      </Button>
    </form>
  );
}

function BenefitTable({ extras, items }: { extras: AccountExtras; items: AssessmentItemRow[] }) {
  const { run, busy, error } = useRpcAction();
  const [remarks, setRemarks] = useState<Record<string, string>>({});
  const [applyItem, setApplyItem] = useState<Record<string, string>>({});
  const [applyAmount, setApplyAmount] = useState<Record<string, string>>({});

  return (
    <div className="space-y-2">
      <ReadError message={error} />
      <div className="overflow-x-auto rounded-lg border border-border">
        <table className="w-full text-sm">
          <thead className="border-b bg-muted/40">
            <tr>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Benefit</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Kind</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Value</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Applied</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Status</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Actions</th>
            </tr>
          </thead>
          <tbody>
            {extras.benefits.length === 0 ? (
              <tr>
                <td colSpan={6} className="px-3 py-6 text-center text-sm text-muted-foreground">
                  No benefits are recorded on this account.
                </td>
              </tr>
            ) : (
              extras.benefits.map((b) => {
                const key = `${b.kind}-${b.id}`;
                return (
                  <tr key={key} className="border-b last:border-0">
                    <td className="px-3 py-2 font-medium">{b.name}</td>
                    <td className="px-3 py-2">{b.kind}</td>
                    <td className="px-3 py-2 text-right">
                      {b.percentage !== null ? `${b.percentage}%` : <Money value={b.amount} />}
                    </td>
                    <td className="px-3 py-2 text-right">
                      <Money value={b.applied} />
                    </td>
                    <td className="px-3 py-2">
                      <Badge variant={statusVariant(b.status)}>{b.status}</Badge>
                    </td>
                    <td className="px-3 py-2 text-right">
                      <div className="flex flex-wrap items-center justify-end gap-2">
                        <Input
                          value={remarks[key] ?? ''}
                          onChange={(e) => setRemarks((r) => ({ ...r, [key]: e.target.value }))}
                          maxLength={500}
                          placeholder="Remarks"
                          className="h-8 w-36 text-xs"
                          aria-label={`Remarks for benefit ${key}`}
                        />
                        <Button
                          size="sm"
                          disabled={busy}
                          onClick={() =>
                            void run('fin_benefit_decide', {
                              p_kind: b.kind,
                              p_id: b.id,
                              p_approve: true,
                              p_amount: b.amount,
                              p_percentage: b.percentage,
                              p_remarks: (remarks[key] ?? '').trim() || null,
                            })
                          }
                        >
                          Approve
                        </Button>
                        <Button
                          size="sm"
                          variant="destructive"
                          disabled={busy || !(remarks[key] ?? '').trim()}
                          onClick={() =>
                            void run('fin_benefit_decide', {
                              p_kind: b.kind,
                              p_id: b.id,
                              p_approve: false,
                              p_amount: null,
                              p_percentage: null,
                              p_remarks: (remarks[key] ?? '').trim(),
                            })
                          }
                        >
                          Reject
                        </Button>
                      </div>
                      <div className="mt-2 flex flex-wrap items-center justify-end gap-2">
                        <Select
                          value={applyItem[key] ?? ''}
                          onChange={(e) => setApplyItem((s) => ({ ...s, [key]: e.target.value }))}
                          className="h-8 w-48 text-xs"
                          aria-label={`Fee item for benefit ${key}`}
                        >
                          <option value="">Apply to a fee item…</option>
                          {items.map((i) => (
                            <option key={i.assessment_item_id} value={i.assessment_item_id}>
                              #{i.assessment_item_id} — balance {i.balance_amount}
                            </option>
                          ))}
                        </Select>
                        <Input
                          type="number"
                          step="0.01"
                          min="0"
                          value={applyAmount[key] ?? ''}
                          onChange={(e) => setApplyAmount((s) => ({ ...s, [key]: e.target.value }))}
                          placeholder="Amount"
                          className="h-8 w-28 text-xs"
                          aria-label={`Amount to apply for benefit ${key}`}
                        />
                        <Button
                          size="sm"
                          variant="outline"
                          disabled={busy || !(applyItem[key] ?? '')}
                          onClick={() =>
                            void run('fin_benefit_apply', {
                              p_kind: b.kind,
                              p_benefit_id: b.id,
                              p_assessment_item_id: Number(applyItem[key]),
                              p_amount: (applyAmount[key] ?? '').trim() ? Number(applyAmount[key]) : null,
                            })
                          }
                        >
                          Apply
                        </Button>
                      </div>
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function AdjustmentCreateForm({ account, items }: { account: AccountInfo; items: AssessmentItemRow[] }) {
  const { run, busy, error } = useRpcAction();

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const str = (key: string) => String(form.get(key) ?? '').trim();
    const result = await run<number>('fin_adjustment_create', {
      p_number: str('number'),
      p_student_account_id: account.student_account_id,
      p_assessment_item_id: Number(str('assessment_item_id')),
      p_type: str('type'),
      p_amount: Number(str('amount')),
      p_reason: str('reason'),
    });
    if (result.ok) event.currentTarget.reset();
  }

  return (
    <form onSubmit={submit} className="space-y-3 rounded-lg border border-border bg-card p-4" noValidate>
      <h4 className="text-sm font-semibold">Request an adjustment</h4>
      <div className="grid gap-3 md:grid-cols-2">
        <Field label="Adjustment number" htmlFor="adjustment_number">
          <Input id="adjustment_number" name="number" required maxLength={60} placeholder="ADJ-2026-0001" />
        </Field>
        <Field label="Fee item" htmlFor="adjustment_item">
          <Select id="adjustment_item" name="assessment_item_id" required defaultValue="">
            <option value="">Select a fee item</option>
            {items.map((i) => (
              <option key={i.assessment_item_id} value={i.assessment_item_id}>
                #{i.assessment_item_id} — balance {i.balance_amount}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Type" htmlFor="adjustment_type">
          <Select id="adjustment_type" name="type" required defaultValue="">
            <option value="">Select a type</option>
            {ADJUSTMENT_TYPES.map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Amount" htmlFor="adjustment_amount">
          <Input id="adjustment_amount" name="amount" type="number" step="0.01" min="0" required />
        </Field>
        <div className="md:col-span-2">
          <Field label="Reason" htmlFor="adjustment_reason">
            <Textarea id="adjustment_reason" name="reason" rows={2} maxLength={500} required />
          </Field>
        </div>
      </div>
      <FormError message={error} />
      <Button type="submit" disabled={busy}>
        {busy ? 'Requesting…' : 'Request adjustment'}
      </Button>
    </form>
  );
}

function AdjustmentTable({ extras }: { extras: AccountExtras }) {
  const { run, busy, error } = useRpcAction();
  const [remarks, setRemarks] = useState<Record<number, string>>({});

  return (
    <div className="space-y-2">
      <ReadError message={error} />
      <div className="overflow-x-auto rounded-lg border border-border">
        <table className="w-full text-sm">
          <thead className="border-b bg-muted/40">
            <tr>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Number</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Type</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Amount</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Reason</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Status</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Actions</th>
            </tr>
          </thead>
          <tbody>
            {extras.adjustments.length === 0 ? (
              <tr>
                <td colSpan={6} className="px-3 py-6 text-center text-sm text-muted-foreground">
                  No adjustments are recorded on this account.
                </td>
              </tr>
            ) : (
              extras.adjustments.map((a) => (
                <tr key={a.id} className="border-b last:border-0">
                  <td className="px-3 py-2 font-medium">{a.number}</td>
                  <td className="px-3 py-2">{a.type}</td>
                  <td className="px-3 py-2 text-right">
                    <Money value={a.amount} />
                  </td>
                  <td className="px-3 py-2">{a.reason}</td>
                  <td className="px-3 py-2">
                    <Badge variant={statusVariant(a.status)}>{a.status}</Badge>
                  </td>
                  <td className="px-3 py-2 text-right">
                    <div className="flex flex-wrap items-center justify-end gap-2">
                      <Input
                        value={remarks[a.id] ?? ''}
                        onChange={(e) => setRemarks((r) => ({ ...r, [a.id]: e.target.value }))}
                        maxLength={500}
                        placeholder="Remarks"
                        className="h-8 w-36 text-xs"
                        aria-label={`Remarks for adjustment ${a.id}`}
                      />
                      <Button
                        size="sm"
                        disabled={busy}
                        onClick={() =>
                          void run('fin_adjustment_decide', {
                            p_adjustment_id: a.id,
                            p_approve: true,
                            p_remarks: (remarks[a.id] ?? '').trim() || null,
                          })
                        }
                      >
                        Approve
                      </Button>
                      <Button
                        size="sm"
                        variant="destructive"
                        disabled={busy || !(remarks[a.id] ?? '').trim()}
                        onClick={() =>
                          void run('fin_adjustment_decide', {
                            p_adjustment_id: a.id,
                            p_approve: false,
                            p_remarks: (remarks[a.id] ?? '').trim(),
                          })
                        }
                      >
                        Reject
                      </Button>
                    </div>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function PenaltyTable({ extras }: { extras: AccountExtras }) {
  const { run, busy, error } = useRpcAction();
  const [waivers, setWaivers] = useState<Record<number, { amount: string; reason: string }>>({});

  return (
    <div className="space-y-2">
      <ReadError message={error} />
      <div className="overflow-x-auto rounded-lg border border-border">
        <table className="w-full text-sm">
          <thead className="border-b bg-muted/40">
            <tr>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Date</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Reason</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Amount</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Waived</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Net</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Status</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Actions</th>
            </tr>
          </thead>
          <tbody>
            {extras.penalties.length === 0 ? (
              <tr>
                <td colSpan={7} className="px-3 py-6 text-center text-sm text-muted-foreground">
                  No penalties are recorded on this account.
                </td>
              </tr>
            ) : (
              extras.penalties.map((p) => {
                const waiver = waivers[p.id] ?? { amount: '', reason: '' };
                return (
                  <tr key={p.id} className="border-b last:border-0">
                    <td className="px-3 py-2">{formatDate(p.date)}</td>
                    <td className="px-3 py-2">{p.reason}</td>
                    <td className="px-3 py-2 text-right">
                      <Money value={p.amount} />
                    </td>
                    <td className="px-3 py-2 text-right">
                      <Money value={p.waived} />
                    </td>
                    <td className="px-3 py-2 text-right">
                      <Money value={p.net} />
                    </td>
                    <td className="px-3 py-2">
                      <Badge variant={statusVariant(p.status)}>{p.status}</Badge>
                    </td>
                    <td className="px-3 py-2 text-right">
                      <div className="flex flex-wrap items-center justify-end gap-2">
                        <Input
                          type="number"
                          step="0.01"
                          min="0"
                          value={waiver.amount}
                          onChange={(e) => setWaivers((w) => ({ ...w, [p.id]: { ...waiver, amount: e.target.value } }))}
                          placeholder="Amount"
                          className="h-8 w-24 text-xs"
                          aria-label={`Waiver amount for penalty ${p.id}`}
                        />
                        <Input
                          value={waiver.reason}
                          onChange={(e) => setWaivers((w) => ({ ...w, [p.id]: { ...waiver, reason: e.target.value } }))}
                          maxLength={500}
                          placeholder="Reason"
                          className="h-8 w-40 text-xs"
                          aria-label={`Waiver reason for penalty ${p.id}`}
                        />
                        <Button
                          size="sm"
                          variant="outline"
                          disabled={busy || !waiver.amount.trim() || !waiver.reason.trim()}
                          onClick={() =>
                            void run('fin_penalty_waive', {
                              p_penalty_id: p.id,
                              p_amount: Number(waiver.amount),
                              p_reason: waiver.reason.trim(),
                            })
                          }
                        >
                          Waive
                        </Button>
                      </div>
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Refunds                                                             */
/* ------------------------------------------------------------------ */

export function RefundPanel({
  account,
  refunds,
  payments,
  paymentModes,
  readError,
}: {
  account: AccountInfo;
  refunds: RefundRow[];
  payments: PaymentRow[];
  paymentModes: Option[];
  readError: string | null;
}) {
  return (
    <div className="space-y-4">
      <ReadError message={readError} />

      <RefundRequestForm account={account} payments={payments} />

      <div className="overflow-x-auto rounded-lg border border-border">
        <table className="w-full text-sm">
          <thead className="border-b bg-muted/40">
            <tr>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Request</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Date</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Requested</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Approved</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Status</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Actions</th>
            </tr>
          </thead>
          <tbody>
            {refunds.length === 0 ? (
              <tr>
                <td colSpan={6} className="px-3 py-6 text-center text-sm text-muted-foreground">
                  No refund requests are visible on this account.
                </td>
              </tr>
            ) : (
              refunds.map((r) => (
                <RefundRowView key={r.refund_request_id} refund={r} paymentModes={paymentModes} />
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function RefundRowView({ refund, paymentModes }: { refund: RefundRow; paymentModes: Option[] }) {
  const { run, busy, error } = useRpcAction();
  const [approvedAmount, setApprovedAmount] = useState(String(refund.requested_amount));
  const [transactionNumber, setTransactionNumber] = useState('');
  const [modeId, setModeId] = useState('');
  const [amount, setAmount] = useState(String(refund.approved_amount ?? refund.requested_amount));
  const [reference, setReference] = useState('');

  return (
    <>
      <tr className="border-b last:border-0">
        <td className="px-3 py-2">
          <div className="font-medium">{refund.refund_request_number}</div>
          <div className="text-xs text-muted-foreground">{refund.refund_reason}</div>
        </td>
        <td className="px-3 py-2">{formatDate(refund.request_date)}</td>
        <td className="px-3 py-2 text-right">
          <Money value={refund.requested_amount} />
        </td>
        <td className="px-3 py-2 text-right">
          <Money value={refund.approved_amount} />
        </td>
        <td className="px-3 py-2">
          <Badge variant={statusVariant(refund.request_status)}>{refund.request_status}</Badge>
        </td>
        <td className="px-3 py-2 text-right">
          {refund.request_status === 'SUBMITTED' || refund.request_status === 'UNDER_REVIEW' ? (
            <div className="flex flex-wrap items-center justify-end gap-2">
              <Input
                type="number"
                step="0.01"
                min="0"
                value={approvedAmount}
                onChange={(e) => setApprovedAmount(e.target.value)}
                className="h-8 w-28 text-xs"
                aria-label={`Approved amount for refund ${refund.refund_request_id}`}
              />
              <Button
                size="sm"
                disabled={busy}
                onClick={() =>
                  void run('fin_decide_refund', {
                    p_refund_request_id: refund.refund_request_id,
                    p_approve: true,
                    p_approved_amount: approvedAmount.trim() ? Number(approvedAmount) : null,
                  })
                }
              >
                Approve
              </Button>
              <Button
                size="sm"
                variant="destructive"
                disabled={busy}
                onClick={() =>
                  void run('fin_decide_refund', {
                    p_refund_request_id: refund.refund_request_id,
                    p_approve: false,
                    p_approved_amount: null,
                  })
                }
              >
                Reject
              </Button>
            </div>
          ) : (
            <span className="text-xs text-muted-foreground">—</span>
          )}
        </td>
      </tr>
      {refund.request_status === 'APPROVED' ? (
        <tr className="border-b bg-muted/20 last:border-0">
          <td colSpan={6} className="px-3 py-2">
            <ReadError message={error} />
            <div className="flex flex-wrap items-end gap-2">
              <div className="min-w-[12rem]">
                <Field label="Refund transaction number" htmlFor={`refund_txn_${refund.refund_request_id}`}>
                  <Input
                    id={`refund_txn_${refund.refund_request_id}`}
                    value={transactionNumber}
                    onChange={(e) => setTransactionNumber(e.target.value)}
                    maxLength={60}
                    placeholder="REF-2026-0001"
                  />
                </Field>
              </div>
              <div className="min-w-[10rem]">
                <Field label="Refund mode" htmlFor={`refund_mode_${refund.refund_request_id}`}>
                  <Select
                    id={`refund_mode_${refund.refund_request_id}`}
                    value={modeId}
                    onChange={(e) => setModeId(e.target.value)}
                  >
                    <option value="">Select a mode</option>
                    {paymentModes.map((o) => (
                      <option key={o.id} value={o.id}>
                        {o.label}
                      </option>
                    ))}
                  </Select>
                </Field>
              </div>
              <div className="min-w-[8rem]">
                <Field label="Amount" htmlFor={`refund_amount_${refund.refund_request_id}`}>
                  <Input
                    id={`refund_amount_${refund.refund_request_id}`}
                    type="number"
                    step="0.01"
                    min="0"
                    value={amount}
                    onChange={(e) => setAmount(e.target.value)}
                  />
                </Field>
              </div>
              <div className="min-w-[10rem]">
                <Field label="Bank reference" htmlFor={`refund_ref_${refund.refund_request_id}`}>
                  <Input
                    id={`refund_ref_${refund.refund_request_id}`}
                    value={reference}
                    onChange={(e) => setReference(e.target.value)}
                    maxLength={100}
                  />
                </Field>
              </div>
              <Button
                size="sm"
                disabled={busy || !transactionNumber.trim() || !modeId || !amount.trim()}
                onClick={() =>
                  void run('fin_process_refund', {
                    p_refund_transaction_number: transactionNumber.trim(),
                    p_refund_request_id: refund.refund_request_id,
                    p_refund_mode_id: Number(modeId),
                    p_amount: Number(amount),
                    p_bank_reference: reference.trim() || null,
                  })
                }
              >
                Process refund
              </Button>
            </div>
          </td>
        </tr>
      ) : null}
    </>
  );
}

function RefundRequestForm({ account, payments }: { account: AccountInfo; payments: PaymentRow[] }) {
  const { run, busy, error } = useRpcAction();

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const str = (key: string) => String(form.get(key) ?? '').trim();
    const result = await run<number>('fin_request_refund', {
      p_request_number: str('request_number'),
      p_student_account_id: account.student_account_id,
      p_payment_transaction_id: Number(str('payment_transaction_id')),
      p_amount: Number(str('amount')),
      p_reason: str('reason'),
    });
    if (result.ok) event.currentTarget.reset();
  }

  return (
    <form onSubmit={submit} className="space-y-3 rounded-lg border border-border bg-card p-4" noValidate>
      <h3 className="text-sm font-semibold">Request a refund</h3>
      <div className="grid gap-3 md:grid-cols-2">
        <Field label="Request number" htmlFor="refund_request_number" hint="The idempotency key.">
          <Input id="refund_request_number" name="request_number" required maxLength={60} placeholder="RFD-2026-0001" />
        </Field>
        <Field label="Payment" htmlFor="refund_payment">
          <Select id="refund_payment" name="payment_transaction_id" required defaultValue="">
            <option value="">Select a payment</option>
            {payments.map((p) => (
              <option key={p.payment_transaction_id} value={p.payment_transaction_id}>
                {p.transaction_number} — {p.amount}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Amount" htmlFor="refund_request_amount">
          <Input id="refund_request_amount" name="amount" type="number" step="0.01" min="0" required />
        </Field>
        <Field label="Reason" htmlFor="refund_request_reason">
          <Textarea id="refund_request_reason" name="reason" rows={2} maxLength={500} required />
        </Field>
      </div>
      <FormError message={error} />
      <Button type="submit" disabled={busy}>
        {busy ? 'Requesting…' : 'Request refund'}
      </Button>
    </form>
  );
}

/* ------------------------------------------------------------------ */
/* Instalments                                                         */
/* ------------------------------------------------------------------ */

export function InstalmentPanel({
  extras,
  assessments,
  plans,
  readError,
}: {
  extras: AccountExtras;
  assessments: AssessmentRow[];
  plans: Option[];
  readError: string | null;
}) {
  const { run, busy, error } = useRpcAction();
  const [assessmentId, setAssessmentId] = useState('');
  const [planId, setPlanId] = useState('');
  const [firstDue, setFirstDue] = useState(today());

  async function apply(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!assessmentId || !planId) return;
    const result = await run<number>('fin_instalment_apply', {
      p_assessment_id: Number(assessmentId),
      p_plan_id: Number(planId),
      p_first_due: firstDue,
    });
    if (result.ok) {
      setAssessmentId('');
      setPlanId('');
    }
  }

  return (
    <div className="space-y-4">
      <ReadError message={readError ?? error} />

      <form onSubmit={apply} className="space-y-3 rounded-lg border border-border bg-card p-4" noValidate>
        <h3 className="text-sm font-semibold">Spread an assessment over instalments</h3>
        <div className="grid gap-3 md:grid-cols-3">
          <Field label="Assessment" htmlFor="instalment_assessment">
            <Select
              id="instalment_assessment"
              value={assessmentId}
              onChange={(e) => setAssessmentId(e.target.value)}
              required
            >
              <option value="">Select an assessment</option>
              {assessments.map((a) => (
                <option key={a.fee_assessment_id} value={a.fee_assessment_id}>
                  {a.assessment_number} — balance {a.balance_amount}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="Plan" htmlFor="instalment_plan">
            <Select id="instalment_plan" value={planId} onChange={(e) => setPlanId(e.target.value)} required>
              <option value="">Select a plan</option>
              {plans.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.label}
                </option>
              ))}
            </Select>
          </Field>
          <Field label="First due date" htmlFor="instalment_first_due">
            <Input id="instalment_first_due" type="date" value={firstDue} onChange={(e) => setFirstDue(e.target.value)} required />
          </Field>
        </div>
        <Button type="submit" disabled={busy || !assessmentId || !planId}>
          {busy ? 'Applying…' : 'Apply instalments'}
        </Button>
      </form>

      <div className="overflow-x-auto rounded-lg border border-border">
        <table className="w-full text-sm">
          <thead className="border-b bg-muted/40">
            <tr>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Assessment</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">No.</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Due</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Amount</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Paid</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Status</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Actions</th>
            </tr>
          </thead>
          <tbody>
            {extras.instalments.length === 0 ? (
              <tr>
                <td colSpan={7} className="px-3 py-6 text-center text-sm text-muted-foreground">
                  No instalment schedules are visible on this account.
                </td>
              </tr>
            ) : (
              extras.instalments.map((i) => (
                <tr key={i.id} className="border-b last:border-0">
                  <td className="px-3 py-2 font-medium">#{i.assessment_id}</td>
                  <td className="px-3 py-2 text-right tabular-nums">{i.number}</td>
                  <td className="px-3 py-2">{formatDate(i.due)}</td>
                  <td className="px-3 py-2 text-right">
                    <Money value={i.amount} />
                  </td>
                  <td className="px-3 py-2 text-right">
                    <Money value={i.paid} />
                  </td>
                  <td className="px-3 py-2">
                    <Badge variant={statusVariant(i.status)}>{i.status}</Badge>
                  </td>
                  <td className="px-3 py-2 text-right">
                    <div className="flex justify-end gap-2">
                      <Button
                        size="sm"
                        variant="ghost"
                        disabled={busy}
                        onClick={() => void run('fin_instalment_refresh', { p_assessment_id: i.assessment_id })}
                      >
                        Refresh
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        disabled={busy}
                        onClick={() => void run('fin_instalment_cancel', { p_assessment_id: i.assessment_id })}
                      >
                        Cancel
                      </Button>
                    </div>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      <p className="text-sm text-muted-foreground">
        {extras.instalments.length} assessment{extras.instalments.length === 1 ? '' : 's'} carry an instalment
        schedule.
      </p>
    </div>
  );
}
