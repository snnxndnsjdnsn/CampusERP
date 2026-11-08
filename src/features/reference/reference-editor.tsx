'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Input, Label } from '@/components/ui/input';
import { Check } from 'lucide-react';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import {
  DynamicForm,
  buildPayload,
  isBoolean,
  isDate,
  isNumeric,
  isTime,
  isTimestamp,
  valuesFromRow,
  type FormColumn,
  type FormValues,
  type LookupMap,
  type LookupOption,
} from '@/features/shared/dynamic-form';
import { errorMessage } from '@/features/shared/reads';
import { formatDate, formatDateTime, formatNumber } from '@/lib/format';
import { createClient } from '@/lib/supabase/client';
import { cn } from '@/lib/utils';

export type RefTable = { tbl: string; label: string; module_code: string };

export type RefSchema = {
  table: string;
  label: string;
  pk: string;
  columns: FormColumn[];
};

type Row = Record<string, unknown>;

function renderCell(column: FormColumn, raw: unknown) {
  if (raw === null || raw === undefined || raw === '') return '—';
  if (isBoolean(column.type)) return raw === true || raw === 'true' ? 'Yes' : 'No';
  if (isNumeric(column.type)) return formatNumber(Number(raw));
  if (isDate(column.type)) return formatDate(String(raw));
  if (isTimestamp(column.type)) return formatDateTime(String(raw));
  if (isTime(column.type)) return String(raw);
  return String(raw);
}

/**
 * The generic reference-data editor.
 *
 * The database owns the catalogue of editable tables (`ref_list`), the shape of
 * every table (`ref_schema`) and the rows themselves (`ref_rows`). Writes go
 * through `ref_save` / `ref_delete`, which enforce the caller's permissions.
 */
export function ReferenceEditor({ tables }: { tables: RefTable[] }) {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);

  const [table, setTable] = useState<string>(tables[0]?.tbl ?? '');
  const [schema, setSchema] = useState<RefSchema | null>(null);
  const [rows, setRows] = useState<Row[]>([]);
  const [lookups, setLookups] = useState<LookupMap>({});
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [filter, setFilter] = useState('');
  const [tableFilter, setTableFilter] = useState('');
  const [editing, setEditing] = useState<{ id: number | null; values: FormValues; original: FormValues | null } | null>(
    null,
  );
  const [saving, setSaving] = useState(false);

  const load = useCallback(
    async (name: string) => {
      if (!name) {
        setSchema(null);
        setRows([]);
        return;
      }
      setLoading(true);
      setError(null);
      try {
        const [schemaRes, rowsRes] = await Promise.all([
          supabase.rpc('ref_schema', { p_table: name }),
          supabase.rpc('ref_rows', { p_table: name }),
        ]);
        if (schemaRes.error) throw new Error(schemaRes.error.message);
        if (rowsRes.error) throw new Error(rowsRes.error.message);
        setSchema(schemaRes.data as RefSchema);
        setRows(Array.isArray(rowsRes.data) ? (rowsRes.data as Row[]) : []);
      } catch (e) {
        setSchema(null);
        setRows([]);
        setError(errorMessage(e));
      } finally {
        setLoading(false);
      }
    },
    [supabase],
  );

  useEffect(() => {
    void (async () => {
      setEditing(null);
      setFilter('');
      setNotice(null);
      await load(table);
    })();
  }, [table, load]);

  // Foreign-key dropdowns: `section_lookup_options` only serves the tables the
  // database allows, so anything else falls back to a plain id input.
  useEffect(() => {
    if (!schema) return;
    const refs = [...new Set(schema.columns.map((c) => c.ref_table).filter((t): t is string => Boolean(t)))];
    if (refs.length === 0) return;
    let cancelled = false;
    void (async () => {
      const next: LookupMap = {};
      for (const ref of refs) {
        if (lookups[ref]) continue;
        const { data, error: lookupError } = await supabase.rpc('section_lookup_options', { p_table: ref });
        if (!lookupError && Array.isArray(data)) next[ref] = data as LookupOption[];
      }
      if (!cancelled && Object.keys(next).length > 0) setLookups((prev) => ({ ...prev, ...next }));
    })();
    return () => {
      cancelled = true;
    };
  }, [schema, supabase, lookups]);

  const visibleRows = useMemo(() => {
    const q = filter.trim().toLowerCase();
    if (!q) return rows;
    return rows.filter((row) =>
      Object.values(row).some((value) => value !== null && value !== undefined && String(value).toLowerCase().includes(q)),
    );
  }, [rows, filter]);

  async function save() {
    if (!schema || !editing) return;
    setSaving(true);
    setError(null);
    try {
      const payload = buildPayload(schema.columns, editing.values, editing.original);
      const { error: saveError } = await supabase.rpc('ref_save', {
        p_table: schema.table,
        p_id: editing.id,
        p: payload,
      });
      if (saveError) throw new Error(saveError.message);
      setEditing(null);
      setNotice(editing.id === null ? 'Row added.' : 'Row updated.');
      await load(schema.table);
      router.refresh();
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setSaving(false);
    }
  }

  async function remove(id: number) {
    if (!schema) return;
    setError(null);
    const { error: deleteError } = await supabase.rpc('ref_delete', { p_table: schema.table, p_id: id });
    if (deleteError) {
      setError(deleteError.message);
      return;
    }
    setNotice('Row deleted.');
    await load(schema.table);
    router.refresh();
  }

  if (tables.length === 0) {
    return (
      <EmptyState
        title="No reference tables are available to you"
        description="Reference data is administered with the IAM.ALL.CONFIGURE permission. Ask an administrator to grant it."
      />
    );
  }

  // The picker lists every table the caller may write to, grouped by module.  A
  // search box narrows it down: thirty-five cards are a lot to scan by eye.
  const query = tableFilter.trim().toLowerCase();
  const matching = query
    ? tables.filter((t) => t.label.toLowerCase().includes(query) || t.tbl.toLowerCase().includes(query))
    : tables;

  const grouped = matching.reduce<Record<string, RefTable[]>>((acc, t) => {
    const key = t.module_code || 'OTHER';
    (acc[key] ??= []).push(t);
    return acc;
  }, {});

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader className="flex-row items-center justify-between gap-3 space-y-0">
          <div>
            <CardTitle>Reference tables</CardTitle>
            <CardDescription>
              Pick a table, then add, edit or delete its rows. Every change is written through the database and audited.
            </CardDescription>
          </div>
          <div className="w-56 shrink-0">
            <Label htmlFor="ref-table-filter" className="sr-only">
              Find a table
            </Label>
            <Input
              id="ref-table-filter"
              type="search"
              placeholder="Find a table"
              value={tableFilter}
              onChange={(e) => setTableFilter(e.target.value)}
            />
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          <p className="text-sm text-muted-foreground" aria-live="polite">
            {matching.length} of {tables.length} tables
          </p>

          {Object.entries(grouped).map(([module, list]) => (
            <div key={module} className="space-y-2">
              <p className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">{module}</p>
              <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
                {list.map((t) => {
                  const selected = t.tbl === table;
                  return (
                    <button
                      key={t.tbl}
                      type="button"
                      onClick={() => setTable(t.tbl)}
                      aria-pressed={selected}
                      className={cn(
                        'rounded-lg border p-3 text-left transition-colors',
                        selected
                          ? 'bg-muted font-medium text-primary ring-2 ring-primary'
                          : 'bg-card hover:bg-muted',
                      )}
                    >
                      <span className="flex items-start justify-between gap-2">
                        <span className="block truncate text-sm">{t.label}</span>
                        {selected ? <Check className="h-4 w-4 shrink-0" aria-hidden /> : null}
                      </span>
                      <span className="mt-0.5 block truncate font-mono text-xs text-muted-foreground">{t.tbl}</span>
                    </button>
                  );
                })}
              </div>
            </div>
          ))}

          {matching.length === 0 ? (
            <EmptyState
              title="No table matches"
              description="Clear the search box to see every reference table you may edit."
            />
          ) : null}

          {error ? <ErrorPanel message={error} /> : null}
          {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
        </CardContent>
      </Card>

      {schema ? (
        <Card>
          <CardHeader className="flex-row items-center justify-between gap-3 space-y-0">
            <div>
              <CardTitle>{schema.label}</CardTitle>
              <CardDescription>
                {visibleRows.length} of {rows.length} rows · table <code>{schema.table}</code>
              </CardDescription>
            </div>
            <div className="flex items-center gap-2">
              <div className="w-48">
                <Label htmlFor="ref-filter" className="sr-only">
                  Filter rows
                </Label>
                <Input
                  id="ref-filter"
                  type="search"
                  placeholder="Filter rows"
                  value={filter}
                  onChange={(e) => setFilter(e.target.value)}
                />
              </div>
              <Button
                onClick={() => {
                  setEditing({ id: null, values: valuesFromRow(schema.columns, null), original: null });
                  setError(null);
                }}
              >
                Add row
              </Button>
            </div>
          </CardHeader>
          <CardContent className="space-y-4">
            {loading ? (
              <p className="text-sm text-muted-foreground">Loading…</p>
            ) : visibleRows.length === 0 ? (
              <EmptyState
                title="No rows to show"
                description={
                  rows.length === 0
                    ? 'This reference table is empty. Use “Add row” to create the first entry.'
                    : 'No row matches the current filter.'
                }
              />
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>{schema.pk}</TableHead>
                    {schema.columns.map((c) => (
                      <TableHead key={c.name}>{c.name.replace(/_/g, ' ')}</TableHead>
                    ))}
                    <TableHead className="text-right">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {visibleRows.map((row) => {
                    const id = Number(row[schema.pk]);
                    return (
                      <TableRow key={id}>
                        <TableCell className="font-medium tabular-nums">{String(row[schema.pk] ?? '')}</TableCell>
                        {schema.columns.map((c) => (
                          <TableCell key={c.name}>{renderCell(c, row[c.name])}</TableCell>
                        ))}
                        <TableCell className="text-right">
                          <div className="flex justify-end gap-2">
                            <Button
                              size="sm"
                              variant="outline"
                              onClick={() => {
                                const values = valuesFromRow(schema.columns, row);
                                setEditing({ id, values, original: values });
                                setError(null);
                              }}
                            >
                              Edit
                            </Button>
                            <Button size="sm" variant="destructive" onClick={() => void remove(id)}>
                              Delete
                            </Button>
                          </div>
                        </TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            )}

            {editing ? (
              <div className="rounded-lg border border-border p-4">
                <div className="mb-3 flex items-center justify-between">
                  <h3 className="text-sm font-semibold">{editing.id === null ? 'New row' : `Edit row ${editing.id}`}</h3>
                  <Button size="sm" variant="ghost" onClick={() => setEditing(null)}>
                    Cancel
                  </Button>
                </div>
                <DynamicForm
                  columns={schema.columns}
                  values={editing.values}
                  lookups={lookups}
                  idPrefix={`ref-${editing.id ?? 'new'}`}
                  onChange={(name, value) =>
                    setEditing((prev) => (prev ? { ...prev, values: { ...prev.values, [name]: value } } : prev))
                  }
                />
                <div className="mt-4 flex justify-end gap-2">
                  <Button variant="outline" onClick={() => setEditing(null)}>
                    Cancel
                  </Button>
                  <Button disabled={saving} onClick={() => void save()}>
                    {saving ? 'Saving…' : 'Save row'}
                  </Button>
                </div>
              </div>
            ) : null}
          </CardContent>
        </Card>
      ) : null}
    </div>
  );
}
