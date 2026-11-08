'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Input, Label, Select } from '@/components/ui/input';
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

/**
 * The editing surface for the module screens that used to be read-only.
 *
 * The database owns everything:
 *
 *   admin_table_list()      the tables the caller may write to
 *   admin_table_schema()    the columns of one of them
 *   admin_table_save()      insert / update one row
 *   admin_table_delete()    delete one row
 *   admin_lookup_options()  the foreign key dropdowns
 *
 * The rows themselves are read with a plain PostgREST select, so the row level
 * policies decide which rows the caller sees - exactly like the rest of the
 * application. The browser never decides whether an action is allowed; the
 * permission check inside the write function is the gate, and its refusal is
 * shown in the panel.
 */

type Row = Record<string, unknown>;

/** One entry of the catalogue: a table the caller may write to. */
export type AdminTable = { tbl: string; label: string; module_codes: string[] };

export type AdminSchema = {
  table: string;
  label: string;
  module_codes: string[];
  /** the single primary key column, or null when the table has a composite key */
  pk: string | null;
  /** every primary key column, in key order */
  pk_cols: string[];
  columns: FormColumn[];
};

/** How many rows the panel shows at once. */
const ROW_LIMIT = 500;

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
 * A collapsible "Manage" panel for one screen.
 *
 * The panel offers the tables behind the screen.  There are two ways to say
 * which ones those are:
 *
 *   `modules`  the module code(s) of the screen.  Every catalogue table that
 *              belongs to one of them is offered, so a screen picks up a new
 *              table automatically when the database adds one.
 *   `tables`   an explicit list of table names, for the rare table that lives
 *              outside the screen's own module.
 *
 * Either way the panel only offers the tables the signed-in user actually
 * holds a write permission for, so a student (or a user without the module
 * permission) sees nothing at all.
 */
export function AdminTableEditor({
  tables,
  modules,
  title = 'Manage',
  description = 'Add, edit and remove the rows behind this screen. Every change is written through the database and audited.',
}: {
  tables?: string[];
  modules?: string[];
  title?: string;
  description?: string;
}) {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);

  const [available, setAvailable] = useState<AdminTable[]>([]);
  const [table, setTable] = useState('');
  const [schema, setSchema] = useState<AdminSchema | null>(null);
  const [rows, setRows] = useState<Row[]>([]);
  const [lookups, setLookups] = useState<LookupMap>({});
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [filter, setFilter] = useState('');
  const [open, setOpen] = useState(false);
  const [saving, setSaving] = useState(false);
  const [editing, setEditing] = useState<{
    key: unknown;
    values: FormValues;
    original: FormValues | null;
  } | null>(null);

  // The props are arrays, so they are compared by value - otherwise a parent
  // that builds the array inline would restart the effect on every render.
  const wanted = `${(tables ?? []).join(',')}|${(modules ?? []).join(',')}`;

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
          supabase.rpc('admin_table_schema', { p_table: name }),
          supabase.from(name).select('*').limit(ROW_LIMIT),
        ]);
        if (schemaRes.error) throw new Error(schemaRes.error.message);
        if (rowsRes.error) throw new Error(rowsRes.error.message);
        setSchema(schemaRes.data as AdminSchema);
        setRows((rowsRes.data ?? []) as Row[]);
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

  // Which of this screen's tables may the caller write to?
  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const [tableNames = '', moduleNames = ''] = wanted.split('|');
      const names = tableNames.split(',').filter(Boolean);
      const mods = moduleNames.split(',').filter(Boolean);
      if (names.length === 0 && mods.length === 0) return;
      const { data, error: listError } = await supabase.rpc('admin_table_list');
      if (cancelled) return;
      if (listError) {
        setError(listError.message);
        return;
      }
      const catalogue = (data ?? []) as AdminTable[];
      const mine = catalogue.filter(
        (entry) =>
          names.includes(entry.tbl) ||
          (entry.module_codes ?? []).some((code) => mods.includes(code)),
      );
      setAvailable(mine);
      setTable((prev) => (prev && mine.some((entry) => entry.tbl === prev) ? prev : (mine[0]?.tbl ?? '')));
    })();
    return () => {
      cancelled = true;
    };
  }, [supabase, wanted]);

  // Load the selected table: its shape and its rows.
  useEffect(() => {
    void (async () => {
      setEditing(null);
      setFilter('');
      setNotice(null);
      await load(table);
    })();
  }, [table, load]);

  // Foreign key dropdowns. `admin_lookup_options` is SECURITY INVOKER, so it
  // only ever returns the rows the caller may see.
  useEffect(() => {
    if (!schema) return;
    const refs = [...new Set(schema.columns.map((c) => c.ref_table).filter((t): t is string => Boolean(t)))];
    if (refs.length === 0) return;
    let cancelled = false;
    void (async () => {
      const next: LookupMap = {};
      for (const ref of refs) {
        const { data, error: lookupError } = await supabase.rpc('admin_lookup_options', { p_table: ref });
        if (!lookupError && Array.isArray(data)) next[ref] = data as LookupOption[];
      }
      if (!cancelled && Object.keys(next).length > 0) setLookups((prev) => ({ ...prev, ...next }));
    })();
    return () => {
      cancelled = true;
    };
  }, [schema, supabase]);

  const visibleRows = useMemo(() => {
    const q = filter.trim().toLowerCase();
    if (!q) return rows;
    return rows.filter((row) =>
      Object.values(row).some(
        (value) => value !== null && value !== undefined && String(value).toLowerCase().includes(q),
      ),
    );
  }, [rows, filter]);

  /**
   * The key of a row.  A table with a single primary key uses the value of
   * that column; a table with a composite key uses an object of its key
   * columns, so the row is addressed exactly.
   */
  function keyOf(row: Row): unknown {
    if (!schema) return null;
    const first = schema.pk_cols[0];
    if (schema.pk_cols.length === 1) return first === undefined ? null : (row[first] ?? null);
    const key: Record<string, unknown> = {};
    for (const col of schema.pk_cols) key[col] = row[col] ?? null;
    return key;
  }

  async function save() {
    if (!schema || !editing) return;
    setSaving(true);
    setError(null);
    try {
      const payload = buildPayload(schema.columns, editing.values, editing.original);
      const { error: saveError } = await supabase.rpc('admin_table_save', {
        p_table: schema.table,
        p_key: editing.key,
        p: payload,
      });
      if (saveError) throw new Error(saveError.message);
      setEditing(null);
      setNotice(editing.key === null ? 'Row added.' : 'Row updated.');
      await load(schema.table);
      router.refresh();
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setSaving(false);
    }
  }

  async function remove(key: unknown) {
    if (!schema) return;
    setError(null);
    const { error: deleteError } = await supabase.rpc('admin_table_delete', {
      p_table: schema.table,
      p_key: key,
    });
    if (deleteError) {
      setError(deleteError.message);
      return;
    }
    setNotice('Row deleted.');
    await load(schema.table);
    router.refresh();
  }

  // Nothing to offer: the caller holds no write permission on this screen.
  if (available.length === 0) return null;

  return (
    <Card className="mb-6" data-testid="admin-editor">
      <CardHeader>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <CardTitle>{title}</CardTitle>
            <CardDescription>{description}</CardDescription>
          </div>
          <Button variant="outline" size="sm" onClick={() => setOpen((prev) => !prev)}>
            {open ? 'Close' : 'Open'}
          </Button>
        </div>
      </CardHeader>

      {open ? (
        <CardContent className="space-y-4">
          {error ? <ErrorPanel message={error} /> : null}
          {notice ? (
            <p className="text-sm text-emerald-700" data-testid="admin-editor-notice">
              {notice}
            </p>
          ) : null}

          {available.length > 1 ? (
            <div className="max-w-md">
              <Label htmlFor="admin-table" className="mb-1 block">
                Table
              </Label>
              <Select id="admin-table" value={table} onChange={(e) => setTable(e.target.value)}>
                {available.map((entry) => (
                  <option key={entry.tbl} value={entry.tbl}>
                    {entry.label}
                  </option>
                ))}
              </Select>
            </div>
          ) : null}

          {loading ? (
            <p className="text-sm text-muted-foreground">Loading…</p>
          ) : !schema ? null : (
            <>
              {/*
                The toolbar stays on screen even when the table is empty or the
                filter matches nothing: the filter is the only way back from an
                empty result, and "Add row" is the only way to fill an empty
                table.
              */}
              <div className="flex flex-wrap items-center justify-between gap-3">
                <p className="text-sm text-muted-foreground">
                  {visibleRows.length} of {rows.length} rows · table <code>{schema.table}</code>
                  {rows.length >= ROW_LIMIT ? ` (first ${ROW_LIMIT})` : ''}
                </p>
                <div className="flex items-center gap-2">
                  <div className="w-48">
                    <Label htmlFor="admin-filter" className="sr-only">
                      Filter rows
                    </Label>
                    <Input
                      id="admin-filter"
                      type="search"
                      placeholder="Filter rows"
                      value={filter}
                      onChange={(e) => setFilter(e.target.value)}
                    />
                  </div>
                  <Button
                    onClick={() => {
                      setEditing({ key: null, values: valuesFromRow(schema.columns, null), original: null });
                      setError(null);
                    }}
                  >
                    Add row
                  </Button>
                </div>
              </div>

              {visibleRows.length === 0 ? (
                <EmptyState
                  title="No rows to show"
                  description={
                    rows.length === 0
                      ? 'This table is empty. Use “Add row” to create the first entry.'
                      : 'No row matches the current filter.'
                  }
                />
              ) : (
                <Table data-testid="admin-editor-table">
                  <TableHeader>
                    <TableRow>
                      <TableHead>{schema.pk_cols.join(' / ')}</TableHead>
                      {schema.columns.map((c) => (
                        <TableHead key={c.name}>{c.name.replace(/_/g, ' ')}</TableHead>
                      ))}
                      <TableHead className="text-right">Actions</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {visibleRows.map((row) => {
                      const key = keyOf(row);
                      const keyText = schema.pk_cols.map((c) => String(row[c] ?? '')).join(' / ');
                      return (
                        <TableRow key={keyText}>
                          <TableCell className="font-medium tabular-nums">{keyText}</TableCell>
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
                                  setEditing({ key, values, original: values });
                                  setError(null);
                                }}
                              >
                                Edit
                              </Button>
                              <Button size="sm" variant="destructive" onClick={() => void remove(key)}>
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
            </>
          )}

          {editing && schema ? (
            <div className="rounded-lg border border-border p-4" data-testid="admin-editor-form">
              <div className="mb-3 flex items-center justify-between">
                <h3 className="text-sm font-semibold">
                  {editing.key === null ? 'New row' : 'Edit row'}
                </h3>
                <Button size="sm" variant="ghost" onClick={() => setEditing(null)}>
                  Cancel
                </Button>
              </div>
              <DynamicForm
                columns={schema.columns}
                values={editing.values}
                lookups={lookups}
                idPrefix={`admin-${editing.key === null ? 'new' : 'row'}`}
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
      ) : null}
    </Card>
  );
}
