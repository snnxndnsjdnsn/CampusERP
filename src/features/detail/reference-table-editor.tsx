'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState } from '@/components/ui/empty-state';
import { Input, Label } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Alert, Notice } from '@/features/shared/feedback';
import { RecordForm } from '@/features/shared/record-form';
import { recordNoun, recordNounTitle } from '@/features/shared/record-noun';
import { RowActions } from '@/features/shared/row-actions';
import {
  DynamicForm,
  buildPayload,
  isBoolean,
  isDate,
  isNumeric,
  isTimestamp,
  valuesFromRow,
  type FormColumn,
  type FormValues,
  type LookupMap,
  type LookupOption,
} from '@/features/shared/dynamic-form';
import { formatDate, formatDateTime, formatNumber } from '@/lib/format';
import { createClient } from '@/lib/supabase/client';

/**
 * The editor for one reference table.
 *
 * The database owns the catalogue of editable tables (`ref_list`), the shape of
 * each table (`ref_schema`) and the rows themselves (`ref_rows`). Writes go
 * through `ref_save` / `ref_delete`, which check the caller's permission and
 * write an audit entry.
 */

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
  return String(raw);
}

export function ReferenceTableEditor({ table }: { table: string }) {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);

  const [schema, setSchema] = useState<RefSchema | null>(null);
  const [rows, setRows] = useState<Row[]>([]);
  const [lookups, setLookups] = useState<LookupMap>({});
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [filter, setFilter] = useState('');
  const [saving, setSaving] = useState(false);
  const [editing, setEditing] = useState<{ id: number | null; values: FormValues; original: FormValues | null } | null>(
    null,
  );

  const load = useCallback(
    async (name: string) => {
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
        setError(e instanceof Error ? e.message : 'The table could not be read.');
      } finally {
        setLoading(false);
      }
    },
    [supabase],
  );

  useEffect(() => {
    void (async () => {
      setEditing(null);
      setNotice(null);
      await load(table);
    })();
  }, [table, load]);

  // Foreign-key dropdowns come from the database, so only the tables it allows
  // are offered.
  useEffect(() => {
    if (!schema) return;
    const refs = [...new Set(schema.columns.map((c) => c.ref_table).filter((t): t is string => Boolean(t)))];
    if (refs.length === 0) return;
    let cancelled = false;
    void (async () => {
      const next: LookupMap = {};
      for (const ref of refs) {
        const { data } = await supabase.rpc('section_lookup_options', { p_table: ref });
        if (Array.isArray(data)) next[ref] = data as LookupOption[];
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
      setNotice(`${recordNounTitle(schema.label)} ${editing.id === null ? 'added' : 'updated'}.`);
      await load(schema.table);
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The row could not be saved.');
    } finally {
      setSaving(false);
    }
  }

  async function remove(id: number) {
    setError(null);
    const { error: deleteError } = await supabase.rpc('ref_delete', { p_table: table, p_id: id });
    if (deleteError) {
      setError(deleteError.message);
      return;
    }
    setNotice(`${recordNounTitle(schema?.label ?? 'record')} deleted.`);
    await load(table);
    router.refresh();
  }

  if (!loading && !schema) {
    return (
      <EmptyState
        title="This reference table is not available"
        description="Either the table name is wrong, or your role does not grant the permission the database requires for it."
      />
    );
  }

  // Every control that talks about one record of this table uses this name:
  // "Add academic year", never "Add row".
  const noun = schema ? recordNoun(schema.label) : 'row';

  return (
    <div className="space-y-4">
      {error ? <Alert message={error} /> : null}
      {notice ? <Notice>{notice}</Notice> : null}

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
                <Label htmlFor="ref-table-filter" className="sr-only">
                  Filter rows
                </Label>
                <Input
                  id="ref-table-filter"
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
                Add {noun}
              </Button>
            </div>
          </CardHeader>
          <CardContent className="space-y-4">
            {/* Above the table: a form below it is a long scroll from the button. */}
            {editing ? (
              <RecordForm
                title={`${editing.id === null ? 'New' : 'Edit'} ${noun}`}
                isNew={editing.id === null}
                saving={saving}
                onCancel={() => setEditing(null)}
                onSave={() => void save()}
              >
                <DynamicForm
                  columns={schema.columns}
                  values={editing.values}
                  lookups={lookups}
                  idPrefix={`ref-${editing.id ?? 'new'}`}
                  onChange={(name, value) =>
                    setEditing((prev) => (prev ? { ...prev, values: { ...prev.values, [name]: value } } : prev))
                  }
                />
              </RecordForm>
            ) : null}

            {loading ? (
              <p className="text-sm text-muted-foreground">Loading…</p>
            ) : visibleRows.length === 0 ? (
              <EmptyState
                title="No rows to show"
                description={
                  rows.length === 0
                    ? `This reference table is empty. Use “Add ${noun}” to create the first entry.`
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
                          <RowActions
                            onEdit={() => {
                              const values = valuesFromRow(schema.columns, row);
                              setEditing({ id, values, original: values });
                              setError(null);
                            }}
                            onDelete={() => void remove(id)}
                          />
                        </TableCell>
                      </TableRow>
                    );
                  })}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>
      ) : null}
    </div>
  );
}
