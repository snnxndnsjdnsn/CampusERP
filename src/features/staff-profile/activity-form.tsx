'use client';

import { useEffect, useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input, Select, Textarea } from '@/components/ui/input';
import { rpcCall, useRpcAction } from '@/features/shared/client-rpc';
import {
  DynamicForm,
  buildPayload,
  valuesFromRow,
  type FormColumn,
  type FormValues,
  type LookupMap,
  type LookupOption,
} from '@/features/shared/dynamic-form';
import type { ActivityTypeRow, DetailSchema, EmployeeOption, Option, StaffActivityDetail } from './types';

/**
 * The staff activity editor.
 *
 * The per-type fields are not hard-coded: `staff_detail_schema` describes the
 * detail table for the chosen activity type, and the form is built from that
 * description. The detail payload therefore only ever carries the exact column
 * names the database knows about.
 */

/** Read a lookup list, preferring the staff tables and falling back to the shared ones. */
export async function fetchLookupOptions(table: string): Promise<LookupOption[]> {
  const staff = await rpcCall<{ id: number; label: string }[]>('staff_lookup_options', { p_table: table });
  if (staff.ok) {
    return staff.data.map((o) => ({ id: Number(o.id), label: String(o.label ?? '') }));
  }
  const section = await rpcCall<{ id: number; label: string }[]>('section_lookup_options', { p_table: table });
  if (section.ok) {
    return section.data.map((o) => ({ id: Number(o.id), label: String(o.label ?? '') }));
  }
  return [];
}

export function ActivityForm({
  activity,
  types,
  years,
  participationLevels,
  roleTypes,
  employees,
  onSaved,
  onCancel,
}: {
  activity: StaffActivityDetail | null;
  types: ActivityTypeRow[];
  years: Option[];
  participationLevels: Option[];
  roleTypes: Option[];
  employees: EmployeeOption[];
  onSaved: (id: number) => void;
  onCancel: () => void;
}) {
  const { run, busy, error } = useRpcAction();
  const [typeId, setTypeId] = useState(activity ? String(activity.activity_type_id) : '');
  const [columns, setColumns] = useState<FormColumn[]>([]);
  const [values, setValues] = useState<FormValues>({});
  const [lookups, setLookups] = useState<LookupMap>({});
  const [schemaError, setSchemaError] = useState<string | null>(null);
  const [schemaLoading, setSchemaLoading] = useState(false);

  // The detail row of the record being edited. It is captured once so that
  // changing the type does not reload it.
  const detailRow = useRef<Record<string, unknown> | null>(activity?.detail ?? null);

  useEffect(() => {
    let cancelled = false;

    async function load() {
      if (!typeId) {
        setColumns([]);
        setValues({});
        setLookups({});
        setSchemaError(null);
        return;
      }

      setSchemaLoading(true);
      const schema = await rpcCall<DetailSchema>('staff_detail_schema', {
        p_activity_type_id: Number(typeId),
      });
      if (cancelled) return;

      if (!schema.ok) {
        setSchemaError(schema.error);
        setColumns([]);
        setValues({});
        setLookups({});
        setSchemaLoading(false);
        return;
      }

      setSchemaError(null);
      const cols = schema.data.columns ?? [];
      setColumns(cols);
      setValues(valuesFromRow(cols, detailRow.current));
      setSchemaLoading(false);

      const map: LookupMap = {};
      for (const column of cols) {
        if (!column.ref_table || map[column.ref_table]) continue;
        map[column.ref_table] = await fetchLookupOptions(column.ref_table);
        if (cancelled) return;
      }
      setLookups(map);
    }

    void load();
    return () => {
      cancelled = true;
    };
  }, [typeId]);

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const str = (key: string) => String(form.get(key) ?? '').trim();
    const num = (key: string) => (str(key) ? Number(str(key)) : null);

    const payload: Record<string, unknown> = {
      activity_type_id: num('activity_type_id'),
      activity_title: str('activity_title'),
      academic_year_id: num('academic_year_id'),
      participation_level_id: num('participation_level_id'),
      primary_role_type_id: num('primary_role_type_id'),
      start_date: str('start_date'),
      end_date: str('end_date'),
      description: str('description'),
      outcomes: str('outcomes'),
    };

    const original = activity ? valuesFromRow(columns, activity.detail) : null;
    const detailPayload = buildPayload(columns, values, original);

    const result = await run<number>('staff_activity_save', {
      p_activity_id: activity ? activity.staff_activity_id : null,
      p_employee_id: num('employee_id'),
      p: payload,
      p_detail: detailPayload,
    });
    if (result.ok) onSaved(result.data);
  }

  const activeTypes = types.filter((t) => t.is_active !== false);

  return (
    <form onSubmit={submit} className="space-y-4" noValidate>
      {error ? <p className="rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800">{error}</p> : null}

      <div className="grid gap-3 md:grid-cols-3">
        {!activity ? (
          <div>
            <label htmlFor="staff-employee" className="mb-1 block text-sm font-medium leading-none">
              Employee
            </label>
            <Select id="staff-employee" name="employee_id" defaultValue="">
              <option value="">Yourself</option>
              {employees.map((e) => (
                <option key={e.employee_id} value={e.employee_id}>
                  {e.display_name} · {e.employee_number}
                </option>
              ))}
            </Select>
          </div>
        ) : null}

        <div>
          <label htmlFor="staff-type" className="mb-1 block text-sm font-medium leading-none">
            Activity type <span className="text-destructive">*</span>
          </label>
          <Select
            id="staff-type"
            name="activity_type_id"
            required
            value={typeId}
            onChange={(e) => setTypeId(e.target.value)}
          >
            <option value="">Select a type</option>
            {activeTypes.map((t) => (
              <option key={t.activity_type_id} value={t.activity_type_id}>
                {t.activity_type_name} · {t.activity_group}
              </option>
            ))}
          </Select>
        </div>

        <div>
          <label htmlFor="staff-title" className="mb-1 block text-sm font-medium leading-none">
            Title <span className="text-destructive">*</span>
          </label>
          <Input
            id="staff-title"
            name="activity_title"
            required
            maxLength={500}
            defaultValue={activity?.activity_title ?? ''}
            placeholder="A study on …"
          />
        </div>

        <div>
          <label htmlFor="staff-year" className="mb-1 block text-sm font-medium leading-none">
            Academic year
          </label>
          <Select id="staff-year" name="academic_year_id" defaultValue={activity?.academic_year_id ?? ''}>
            <option value="">Not stated</option>
            {years.map((y) => (
              <option key={y.id} value={y.id}>
                {y.label}
              </option>
            ))}
          </Select>
        </div>

        <div>
          <label htmlFor="staff-level" className="mb-1 block text-sm font-medium leading-none">
            Participation level
          </label>
          <Select
            id="staff-level"
            name="participation_level_id"
            defaultValue={activity?.participation_level_id ?? ''}
          >
            <option value="">Not stated</option>
            {participationLevels.map((o) => (
              <option key={o.id} value={o.id}>
                {o.label}
              </option>
            ))}
          </Select>
        </div>

        <div>
          <label htmlFor="staff-role" className="mb-1 block text-sm font-medium leading-none">
            Primary role
          </label>
          <Select id="staff-role" name="primary_role_type_id" defaultValue={activity?.primary_role_type_id ?? ''}>
            <option value="">Not stated</option>
            {roleTypes.map((o) => (
              <option key={o.id} value={o.id}>
                {o.label}
              </option>
            ))}
          </Select>
        </div>

        <div>
          <label htmlFor="staff-start" className="mb-1 block text-sm font-medium leading-none">
            Start date
          </label>
          <Input id="staff-start" name="start_date" type="date" defaultValue={activity?.start_date ?? ''} />
        </div>

        <div>
          <label htmlFor="staff-end" className="mb-1 block text-sm font-medium leading-none">
            End date
          </label>
          <Input id="staff-end" name="end_date" type="date" defaultValue={activity?.end_date ?? ''} />
        </div>

        <div className="md:col-span-3">
          <label htmlFor="staff-description" className="mb-1 block text-sm font-medium leading-none">
            Description
          </label>
          <Textarea
            id="staff-description"
            name="description"
            rows={3}
            maxLength={5000}
            defaultValue={activity?.description ?? ''}
          />
        </div>

        <div className="md:col-span-3">
          <label htmlFor="staff-outcomes" className="mb-1 block text-sm font-medium leading-none">
            Outcomes
          </label>
          <Textarea id="staff-outcomes" name="outcomes" rows={3} maxLength={5000} defaultValue={activity?.outcomes ?? ''} />
        </div>
      </div>

      {schemaError ? (
        <p className="rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800">{schemaError}</p>
      ) : null}

      {typeId ? (
        <section className="rounded-lg border border-border p-4">
          <h4 className="mb-3 text-sm font-semibold">
            {schemaLoading ? 'Loading the type details…' : 'Type details'}
          </h4>
          {columns.length === 0 && !schemaLoading ? (
            <p className="text-sm text-muted-foreground">This activity type has no extra fields.</p>
          ) : (
            <DynamicForm
              columns={columns}
              values={values}
              onChange={(name, value) => setValues((current) => ({ ...current, [name]: value }))}
              lookups={lookups}
              idPrefix="staff-detail"
            />
          )}
        </section>
      ) : null}

      <div className="flex flex-wrap gap-2">
        <Button type="submit" disabled={busy}>
          {busy ? 'Saving…' : activity ? 'Save changes' : 'Create activity'}
        </Button>
        <Button type="button" variant="outline" onClick={onCancel} disabled={busy}>
          Cancel
        </Button>
      </div>
    </form>
  );
}
