'use client';

import { useMemo, useState } from 'react';
import { Badge } from '@/components/ui/badge';
import { EmptyState } from '@/components/ui/empty-state';
import { Input, Label } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';

/** One row of the `schema_indexes` catalogue. */
export type SchemaIndex = {
  index_name: string;
  table_name: string;
  index_columns: string[] | null;
  is_unique: boolean;
  is_primary: boolean;
  definition: string | null;
};

/** The columns the catalogue can be sorted by. */
type SortKey = 'index_name' | 'table_name' | 'columns';

type SortState = { key: SortKey; ascending: boolean };

function columnsOf(row: SchemaIndex): string[] {
  return Array.isArray(row.index_columns) ? row.index_columns : [];
}

function compare(a: SchemaIndex, b: SchemaIndex, key: SortKey): number {
  if (key === 'columns') return columnsOf(a).join(', ').localeCompare(columnsOf(b).join(', '));
  return String(a[key] ?? '').localeCompare(String(b[key] ?? ''));
}

/** A column header that sorts the table when it is clicked. */
function SortHead({
  label,
  sortKey,
  sort,
  onSort,
}: {
  label: string;
  sortKey: SortKey;
  sort: SortState;
  onSort: (key: SortKey) => void;
}) {
  const active = sort.key === sortKey;
  return (
    <TableHead aria-sort={active ? (sort.ascending ? 'ascending' : 'descending') : 'none'}>
      <button
        type="button"
        onClick={() => onSort(sortKey)}
        className="inline-flex items-center gap-1 text-xs font-medium uppercase tracking-wide text-muted-foreground hover:text-foreground"
      >
        {label}
        <span aria-hidden="true" className="text-[10px]">
          {active ? (sort.ascending ? '▲' : '▼') : '↕'}
        </span>
      </button>
    </TableHead>
  );
}

/**
 * The index catalogue of the live database.
 *
 * The rows come from `schema_indexes`, which reads `pg_catalog` on behalf of
 * the caller and refuses to return anything unless the caller holds the
 * matching permission. The table is filtered and sorted here, in the browser,
 * because the catalogue is a reading of the schema rather than a record.
 */
export function IndexCatalogue({ rows, scope }: { rows: SchemaIndex[]; scope: 'all' | 'staff' }) {
  const [query, setQuery] = useState('');
  const [uniqueOnly, setUniqueOnly] = useState(false);
  const [sort, setSort] = useState<SortState>({ key: 'table_name', ascending: true });

  const visible = useMemo(() => {
    const q = query.trim().toLowerCase();
    const matched = rows.filter((row) => {
      if (uniqueOnly && !row.is_unique) return false;
      if (!q) return true;
      return (
        row.index_name.toLowerCase().includes(q) ||
        row.table_name.toLowerCase().includes(q) ||
        columnsOf(row).join(' ').toLowerCase().includes(q)
      );
    });
    const direction = sort.ascending ? 1 : -1;
    return [...matched].sort((a, b) => direction * compare(a, b, sort.key));
  }, [rows, query, uniqueOnly, sort]);

  function toggleSort(key: SortKey) {
    setSort((current) => (current.key === key ? { key, ascending: !current.ascending } : { key, ascending: true }));
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end gap-4">
        <div className="min-w-[16rem] flex-1 space-y-1.5">
          <Label htmlFor="index-filter">Filter</Label>
          <Input
            id="index-filter"
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Index name, table or column"
          />
        </div>
        <label className="flex items-center gap-2 pb-2 text-sm">
          <input
            type="checkbox"
            checked={uniqueOnly}
            onChange={(e) => setUniqueOnly(e.target.checked)}
            className="h-4 w-4 rounded border-border"
          />
          Unique indexes only
        </label>
        <p className="pb-2 text-xs text-muted-foreground">
          {visible.length} of {rows.length} indexes
        </p>
      </div>

      <p className="text-xs text-muted-foreground">
        {scope === 'all'
          ? 'Scope: every index in the public schema.'
          : 'Scope: the tables that carry a STAFF_PROFILE.* row-level security policy.'}
      </p>

      {visible.length === 0 ? (
        <EmptyState title="No indexes" description="Nothing in the catalogue matches this filter." />
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <SortHead label="Index" sortKey="index_name" sort={sort} onSort={toggleSort} />
              <SortHead label="Table" sortKey="table_name" sort={sort} onSort={toggleSort} />
              <SortHead label="Columns" sortKey="columns" sort={sort} onSort={toggleSort} />
              <TableHead>Flags</TableHead>
              <TableHead>Definition</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {visible.map((row) => (
              <TableRow key={`${row.table_name}-${row.index_name}`}>
                <TableCell className="font-mono text-xs">{row.index_name}</TableCell>
                <TableCell className="text-xs">{row.table_name}</TableCell>
                <TableCell className="text-xs">{columnsOf(row).join(', ') || '—'}</TableCell>
                <TableCell>
                  <div className="flex flex-wrap gap-1">
                    {row.is_primary ? <Badge variant="info">Primary</Badge> : null}
                    {row.is_unique ? <Badge variant="success">Unique</Badge> : null}
                  </div>
                </TableCell>
                <TableCell>
                  <pre className="max-w-xl overflow-x-auto whitespace-pre-wrap font-mono text-xs text-muted-foreground">
                    {row.definition ?? '—'}
                  </pre>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}
    </div>
  );
}
