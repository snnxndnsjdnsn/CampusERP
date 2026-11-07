'use client';

import { useCallback, useState } from 'react';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input, Select, Textarea } from '@/components/ui/input';
import { rpcCall, useRpcAction } from '@/features/shared/client-rpc';
import { formatDate } from '@/lib/format';
import type { Option, StructureDetail, StructureItem, StructureRow } from './types';
import { Field, FormError, Money, ReadError, today } from './ui';

/**
 * Fee structures: the priced templates the fee office publishes.
 *
 * Every write goes to a `fin_structure_*` function, and the browser never decides
 * whether a move is allowed — the database returns the permission errors.
 */

export function FeeStructureDesk({
  structures,
  institutions,
  campuses,
  programmes,
  years,
  categories,
  feeTypes,
  semesters,
  terms,
  lateFeeRules,
}: {
  structures: StructureRow[];
  institutions: Option[];
  campuses: Option[];
  programmes: Option[];
  years: Option[];
  categories: Option[];
  feeTypes: Option[];
  semesters: Option[];
  terms: Option[];
  lateFeeRules: Option[];
}) {
  const { run, busy, error } = useRpcAction();
  const [detail, setDetail] = useState<StructureDetail | null>(null);
  const [loading, setLoading] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);

  const open = useCallback(async (id: number) => {
    setLoading(true);
    setLoadError(null);
    const result = await rpcCall<StructureDetail>('fin_structure_get', { p_id: id });
    setLoading(false);
    if (!result.ok) {
      setLoadError(result.error);
      return;
    }
    setDetail(result.data);
    setCreating(false);
  }, []);

  async function act(fn: string, args: Record<string, unknown>, after?: (id: number) => void) {
    const result = await run<number>(fn, args);
    if (result.ok && detail) {
      if (after) after(result.data);
      else await open(detail.fee_structure_id);
    }
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-sm text-muted-foreground">
          {structures.length} fee structure{structures.length === 1 ? '' : 's'} visible to you.
        </p>
        <Button size="sm" onClick={() => setCreating((v) => !v)} disabled={busy}>
          {creating ? 'Close the form' : 'New fee structure'}
        </Button>
      </div>

      <ReadError message={error ?? loadError} />

      {creating ? (
        <div className="rounded-lg border border-border bg-card p-4">
          <h3 className="mb-3 text-sm font-semibold">New fee structure</h3>
          <StructureForm
            structure={null}
            institutions={institutions}
            campuses={campuses}
            programmes={programmes}
            years={years}
            categories={categories}
            onSaved={(id) => {
              setCreating(false);
              void open(id);
            }}
          />
        </div>
      ) : null}

      <div className="overflow-x-auto rounded-lg border border-border">
        <table className="w-full text-sm">
          <thead className="border-b bg-muted/40">
            <tr>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Code</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Name</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Programme</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Year</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Items</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Total</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Status</th>
              <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Actions</th>
            </tr>
          </thead>
          <tbody>
            {structures.length === 0 ? (
              <tr>
                <td colSpan={8} className="px-3 py-6 text-center text-sm text-muted-foreground">
                  No fee structures are visible to you yet.
                </td>
              </tr>
            ) : (
              structures.map((s) => (
                <tr key={s.fee_structure_id} className="border-b last:border-0 hover:bg-muted/40">
                  <td className="px-3 py-2 font-medium">{s.structure_code}</td>
                  <td className="px-3 py-2">
                    <div>{s.structure_name}</div>
                    <div className="text-xs text-muted-foreground">
                      {s.institution_name} · v{s.version_number}
                    </div>
                  </td>
                  <td className="px-3 py-2">{s.programme_name ?? 'All programmes'}</td>
                  <td className="px-3 py-2">{s.year_code}</td>
                  <td className="px-3 py-2 text-right tabular-nums">{s.item_count}</td>
                  <td className="px-3 py-2 text-right">
                    <Money value={s.total_amount} />
                  </td>
                  <td className="px-3 py-2">
                    <Badge variant={statusVariant(s.approval_status)}>{s.approval_status}</Badge>
                  </td>
                  <td className="px-3 py-2 text-right">
                    <Button size="sm" variant="outline" disabled={loading} onClick={() => void open(s.fee_structure_id)}>
                      Open
                    </Button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      {detail ? (
        <StructurePanel
          detail={detail}
          feeTypes={feeTypes}
          semesters={semesters}
          terms={terms}
          lateFeeRules={lateFeeRules}
          institutions={institutions}
          campuses={campuses}
          programmes={programmes}
          years={years}
          categories={categories}
          onChanged={() => void open(detail.fee_structure_id)}
          onClosed={() => setDetail(null)}
          onVersioned={(id) => void open(id)}
          onAct={act}
        />
      ) : null}
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Detail panel                                                        */
/* ------------------------------------------------------------------ */

function StructurePanel({
  detail,
  feeTypes,
  semesters,
  terms,
  lateFeeRules,
  institutions,
  campuses,
  programmes,
  years,
  categories,
  onChanged,
  onClosed,
  onVersioned,
  onAct,
}: {
  detail: StructureDetail;
  feeTypes: Option[];
  semesters: Option[];
  terms: Option[];
  lateFeeRules: Option[];
  institutions: Option[];
  campuses: Option[];
  programmes: Option[];
  years: Option[];
  categories: Option[];
  onChanged: () => void;
  onClosed: () => void;
  onVersioned: (id: number) => void;
  onAct: (fn: string, args: Record<string, unknown>, after?: (id: number) => void) => Promise<void>;
}) {
  const { run, busy, error } = useRpcAction();
  const [editing, setEditing] = useState(false);
  const [addingItem, setAddingItem] = useState(false);
  const [editingItem, setEditingItem] = useState<StructureItem | null>(null);
  const [remarks, setRemarks] = useState('');

  return (
    <section className="rounded-lg border border-border bg-card p-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h3 className="text-base font-semibold">
            {detail.structure_code} · {detail.structure_name}
          </h3>
          <p className="mt-1 text-sm text-muted-foreground">
            {detail.institution_name}
            {detail.programme_name ? ` · ${detail.programme_name}` : ''} · {detail.year_code} · v{detail.version_number}
          </p>
          <div className="mt-2 flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
            <Badge variant={statusVariant(detail.approval_status)}>{detail.approval_status}</Badge>
            <span>Effective {formatDate(detail.effective_from)}</span>
            {detail.effective_to ? <span>to {formatDate(detail.effective_to)}</span> : null}
          </div>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button size="sm" variant="ghost" onClick={onClosed}>
            Close
          </Button>
          {detail.can_edit ? (
            <Button size="sm" variant="outline" onClick={() => setEditing((v) => !v)}>
              {editing ? 'Stop editing' : 'Edit structure'}
            </Button>
          ) : null}
          {detail.can_submit ? (
            <Button size="sm" disabled={busy} onClick={() => void onAct('fin_structure_submit', { p_id: detail.fee_structure_id })}>
              Submit for approval
            </Button>
          ) : null}
          {detail.can_version ? (
            <Button
              size="sm"
              variant="outline"
              disabled={busy}
              onClick={() => void onAct('fin_structure_new_version', { p_id: detail.fee_structure_id }, onVersioned)}
            >
              New version
            </Button>
          ) : null}
          {detail.can_delete ? (
            <Button
              size="sm"
              variant="destructive"
              disabled={busy}
              onClick={() => void onAct('fin_structure_delete', { p_id: detail.fee_structure_id })}
            >
              Delete
            </Button>
          ) : null}
        </div>
      </div>

      <ReadError message={error} />

      {editing ? (
        <div className="mt-4 rounded-lg border border-border p-4">
          <h4 className="mb-3 text-sm font-semibold">Structure details</h4>
          <StructureForm
            structure={detail}
            institutions={institutions}
            campuses={campuses}
            programmes={programmes}
            years={years}
            categories={categories}
            onSaved={() => {
              setEditing(false);
              onChanged();
            }}
          />
        </div>
      ) : null}

      {detail.can_decide ? (
        <div className="mt-4 rounded-lg border border-border p-4">
          <h4 className="mb-2 text-sm font-semibold">Decision</h4>
          <div className="flex flex-wrap items-end gap-2">
            <div className="min-w-[16rem] flex-1">
              <Field label="Remarks" htmlFor="structure-decision-remarks">
                <Input
                  id="structure-decision-remarks"
                  value={remarks}
                  onChange={(e) => setRemarks(e.target.value)}
                  maxLength={500}
                  placeholder="Required when rejecting"
                />
              </Field>
            </div>
            <Button
              size="sm"
              disabled={busy}
              onClick={() =>
                void run('fin_structure_decide', {
                  p_id: detail.fee_structure_id,
                  p_approve: true,
                  p_remarks: remarks.trim() || null,
                }).then((r) => {
                  if (r.ok) {
                    setRemarks('');
                    onChanged();
                  }
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
                void run('fin_structure_decide', {
                  p_id: detail.fee_structure_id,
                  p_approve: false,
                  p_remarks: remarks.trim() || null,
                }).then((r) => {
                  if (r.ok) {
                    setRemarks('');
                    onChanged();
                  }
                })
              }
            >
              Reject
            </Button>
          </div>
        </div>
      ) : null}

      <div className="mt-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h4 className="text-sm font-semibold">Items ({detail.items.length})</h4>
          {detail.can_edit ? (
            <Button
              size="sm"
              variant="outline"
              onClick={() => {
                setEditingItem(null);
                setAddingItem((v) => !v);
              }}
            >
              {addingItem ? 'Close' : 'Add item'}
            </Button>
          ) : null}
        </div>

        {addingItem ? (
          <div className="mt-3 rounded-lg border border-border p-4">
            <StructureItemForm
              structureId={detail.fee_structure_id}
              item={null}
              feeTypes={feeTypes}
              semesters={semesters}
              terms={terms}
              lateFeeRules={lateFeeRules}
              onSaved={() => {
                setAddingItem(false);
                onChanged();
              }}
            />
          </div>
        ) : null}

        <div className="mt-3 overflow-x-auto rounded-lg border border-border">
          <table className="w-full text-sm">
            <thead className="border-b bg-muted/40">
              <tr>
                <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Fee</th>
                <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Amount</th>
                <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Due</th>
                <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Options</th>
                {detail.can_edit ? (
                  <th className="px-3 py-2 text-right text-xs font-medium uppercase tracking-wide text-muted-foreground">Actions</th>
                ) : null}
              </tr>
            </thead>
            <tbody>
              {detail.items.length === 0 ? (
                <tr>
                  <td colSpan={detail.can_edit ? 5 : 4} className="px-3 py-6 text-center text-sm text-muted-foreground">
                    This structure has no items yet.
                  </td>
                </tr>
              ) : (
                detail.items.map((item) => (
                  <tr key={item.id} className="border-b last:border-0">
                    <td className="px-3 py-2">
                      <div className="font-medium">{item.fee_type}</div>
                      {item.remarks ? <div className="text-xs text-muted-foreground">{item.remarks}</div> : null}
                    </td>
                    <td className="px-3 py-2 text-right">
                      <Money value={item.amount} />
                    </td>
                    <td className="px-3 py-2">
                      {item.due_date ? formatDate(item.due_date) : item.due_days !== null ? `${item.due_days} days` : '—'}
                    </td>
                    <td className="px-3 py-2 text-xs text-muted-foreground">
                      {item.installment_allowed ? 'Instalments' : ''}
                      {item.installment_allowed && item.waiver_allowed ? ' · ' : ''}
                      {item.waiver_allowed ? 'Waiver' : ''}
                    </td>
                    {detail.can_edit ? (
                      <td className="px-3 py-2 text-right">
                        <div className="flex justify-end gap-2">
                          <Button
                            size="sm"
                            variant="outline"
                            onClick={() => {
                              setAddingItem(false);
                              setEditingItem(item);
                            }}
                          >
                            Edit
                          </Button>
                          <Button
                            size="sm"
                            variant="ghost"
                            disabled={busy}
                            onClick={() =>
                              void run('fin_structure_item_delete', {
                                p_structure_id: detail.fee_structure_id,
                                p_item_id: item.id,
                              }).then((r) => {
                                if (r.ok) onChanged();
                              })
                            }
                          >
                            Remove
                          </Button>
                        </div>
                      </td>
                    ) : null}
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>

        {editingItem ? (
          <div className="mt-3 rounded-lg border border-border p-4">
            <h4 className="mb-3 text-sm font-semibold">Edit item</h4>
            <StructureItemForm
              structureId={detail.fee_structure_id}
              item={editingItem}
              feeTypes={feeTypes}
              semesters={semesters}
              terms={terms}
              lateFeeRules={lateFeeRules}
              onSaved={() => {
                setEditingItem(null);
                onChanged();
              }}
            />
          </div>
        ) : null}
      </div>
    </section>
  );
}

/* ------------------------------------------------------------------ */
/* Forms                                                               */
/* ------------------------------------------------------------------ */

function StructureForm({
  structure,
  institutions,
  campuses,
  programmes,
  years,
  categories,
  onSaved,
}: {
  structure: StructureDetail | null;
  institutions: Option[];
  campuses: Option[];
  programmes: Option[];
  years: Option[];
  categories: Option[];
  onSaved: (id: number) => void;
}) {
  const { run, busy, error } = useRpcAction();

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const str = (key: string) => String(form.get(key) ?? '').trim();
    const num = (key: string) => (str(key) ? Number(str(key)) : '');

    const payload: Record<string, unknown> = {
      structure_code: str('structure_code'),
      structure_name: str('structure_name'),
      institution_id: num('institution_id'),
      campus_id: num('campus_id'),
      programme_id: num('programme_id'),
      academic_year_id: num('academic_year_id'),
      admission_category_id: num('admission_category_id'),
      effective_from: str('effective_from'),
      effective_to: str('effective_to'),
      remarks: str('remarks'),
    };

    const result = await run<number>('fin_structure_save', {
      p_id: structure ? structure.fee_structure_id : null,
      p: payload,
    });
    if (result.ok) onSaved(result.data);
  }

  return (
    <form onSubmit={submit} className="space-y-4" noValidate>
      <div className="grid gap-4 md:grid-cols-2">
        <Field label="Structure code" htmlFor="structure_code">
          <Input
            id="structure_code"
            name="structure_code"
            required
            maxLength={50}
            defaultValue={structure?.structure_code ?? ''}
            placeholder="UG-2026-FEES"
          />
        </Field>
        <Field label="Structure name" htmlFor="structure_name">
          <Input
            id="structure_name"
            name="structure_name"
            required
            maxLength={200}
            defaultValue={structure?.structure_name ?? ''}
          />
        </Field>
        <Field label="Institution" htmlFor="institution_id">
          <Select id="institution_id" name="institution_id" required defaultValue={structure?.institution_id ?? ''}>
            <option value="">Select an institution</option>
            {institutions.map((o) => (
              <option key={o.id} value={o.id}>
                {o.label}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Campus" htmlFor="campus_id" hint="Optional — leave blank for every campus.">
          <Select id="campus_id" name="campus_id" defaultValue={structure?.campus_id ?? ''}>
            <option value="">All campuses</option>
            {campuses.map((o) => (
              <option key={o.id} value={o.id}>
                {o.label}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Programme" htmlFor="programme_id" hint="Optional — leave blank for every programme.">
          <Select id="programme_id" name="programme_id" defaultValue={structure?.programme_id ?? ''}>
            <option value="">All programmes</option>
            {programmes.map((o) => (
              <option key={o.id} value={o.id}>
                {o.label}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Academic year" htmlFor="academic_year_id">
          <Select id="academic_year_id" name="academic_year_id" required defaultValue={structure?.academic_year_id ?? ''}>
            <option value="">Select a year</option>
            {years.map((o) => (
              <option key={o.id} value={o.id}>
                {o.label}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Admission category" htmlFor="admission_category_id" hint="Optional.">
          <Select id="admission_category_id" name="admission_category_id" defaultValue={structure?.admission_category_id ?? ''}>
            <option value="">All categories</option>
            {categories.map((o) => (
              <option key={o.id} value={o.id}>
                {o.label}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Effective from" htmlFor="effective_from">
          <Input
            id="effective_from"
            name="effective_from"
            type="date"
            required
            defaultValue={structure?.effective_from ?? today()}
          />
        </Field>
        <Field label="Effective to" htmlFor="effective_to" hint="Optional.">
          <Input id="effective_to" name="effective_to" type="date" defaultValue={structure?.effective_to ?? ''} />
        </Field>
      </div>
      <Field label="Remarks" htmlFor="structure_remarks">
        <Textarea id="structure_remarks" name="remarks" rows={2} maxLength={500} defaultValue={structure?.remarks ?? ''} />
      </Field>
      <FormError message={error} />
      <Button type="submit" disabled={busy}>
        {busy ? 'Saving…' : structure ? 'Save structure' : 'Create structure'}
      </Button>
    </form>
  );
}

function StructureItemForm({
  structureId,
  item,
  feeTypes,
  semesters,
  terms,
  lateFeeRules,
  onSaved,
}: {
  structureId: number;
  item: StructureItem | null;
  feeTypes: Option[];
  semesters: Option[];
  terms: Option[];
  lateFeeRules: Option[];
  onSaved: () => void;
}) {
  const { run, busy, error } = useRpcAction();

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const str = (key: string) => String(form.get(key) ?? '').trim();
    const num = (key: string) => (str(key) ? Number(str(key)) : '');

    const payload: Record<string, unknown> = {
      fee_type_id: num('fee_type_id'),
      semester_id: num('semester_id'),
      academic_term_id: num('academic_term_id'),
      amount: str('amount'),
      due_date: str('due_date'),
      due_days_from_registration: num('due_days'),
      installment_allowed: form.get('installment_allowed') === 'on',
      waiver_allowed: form.get('waiver_allowed') === 'on',
      late_fee_rule_id: num('late_fee_rule_id'),
      display_order: num('display_order') || 0,
      remarks: str('remarks'),
    };

    const result = await run<number>('fin_structure_item_save', {
      p_structure_id: structureId,
      p_item_id: item ? item.id : null,
      p: payload,
    });
    if (result.ok) onSaved();
  }

  return (
    <form onSubmit={submit} className="space-y-4" noValidate>
      <div className="grid gap-4 md:grid-cols-3">
        <Field label="Fee type" htmlFor="item_fee_type_id">
          <Select id="item_fee_type_id" name="fee_type_id" required defaultValue={item?.fee_type_id ?? ''}>
            <option value="">Select a fee type</option>
            {feeTypes.map((o) => (
              <option key={o.id} value={o.id}>
                {o.label}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Amount" htmlFor="item_amount">
          <Input id="item_amount" name="amount" type="number" step="0.01" min="0" required defaultValue={item?.amount ?? ''} />
        </Field>
        <Field label="Display order" htmlFor="item_display_order">
          <Input
            id="item_display_order"
            name="display_order"
            type="number"
            min="0"
            defaultValue={item?.display_order ?? 0}
          />
        </Field>
        <Field label="Semester" htmlFor="item_semester_id" hint="Optional.">
          <Select id="item_semester_id" name="semester_id" defaultValue={item?.semester_id ?? ''}>
            <option value="">Every semester</option>
            {semesters.map((o) => (
              <option key={o.id} value={o.id}>
                {o.label}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Academic term" htmlFor="item_academic_term_id" hint="Optional.">
          <Select id="item_academic_term_id" name="academic_term_id" defaultValue={item?.academic_term_id ?? ''}>
            <option value="">Every term</option>
            {terms.map((o) => (
              <option key={o.id} value={o.id}>
                {o.label}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Late-fee rule" htmlFor="item_late_fee_rule_id" hint="Optional.">
          <Select id="item_late_fee_rule_id" name="late_fee_rule_id" defaultValue={item?.late_fee_rule_id ?? ''}>
            <option value="">No rule</option>
            {lateFeeRules.map((o) => (
              <option key={o.id} value={o.id}>
                {o.label}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Due date" htmlFor="item_due_date" hint="Optional.">
          <Input id="item_due_date" name="due_date" type="date" defaultValue={item?.due_date ?? ''} />
        </Field>
        <Field label="Days after registration" htmlFor="item_due_days" hint="Optional.">
          <Input
            id="item_due_days"
            name="due_days"
            type="number"
            min="0"
            max="3650"
            defaultValue={item?.due_days ?? ''}
          />
        </Field>
        <Field label="Options" htmlFor="item_options">
          <div className="flex items-center gap-4 pt-1">
            <label className="flex items-center gap-2 text-sm">
              <input
                id="item_installment_allowed"
                name="installment_allowed"
                type="checkbox"
                defaultChecked={item?.installment_allowed ?? false}
              />
              Instalments
            </label>
            <label className="flex items-center gap-2 text-sm">
              <input id="item_waiver_allowed" name="waiver_allowed" type="checkbox" defaultChecked={item?.waiver_allowed ?? false} />
              Waiver
            </label>
          </div>
        </Field>
      </div>
      <Field label="Remarks" htmlFor="item_remarks">
        <Textarea id="item_remarks" name="remarks" rows={2} maxLength={500} defaultValue={item?.remarks ?? ''} />
      </Field>
      <FormError message={error} />
      <Button type="submit" disabled={busy}>
        {busy ? 'Saving…' : item ? 'Save item' : 'Add item'}
      </Button>
    </form>
  );
}
