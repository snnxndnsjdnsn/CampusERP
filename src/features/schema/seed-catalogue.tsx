'use client';

import { useState } from 'react';
import { Badge } from '@/components/ui/badge';
import { EmptyState } from '@/components/ui/empty-state';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { cn } from '@/lib/utils';

/** One seeded lookup table, as it was read. */
export type SeedTableRead = {
  /** The table name, as the database spells it. */
  table: string;
  /** The columns that were read: the key first, then the labels. */
  columns: string[];
  /** The first rows of the table. */
  rows: Record<string, unknown>[];
  /** How many rows the table holds for this caller. */
  count: number;
  /** Why the table could not be read, if it could not. */
  error: string | null;
};

function cellValue(value: unknown): string {
  if (value === null || value === undefined) return '—';
  if (typeof value === 'boolean') return value ? 'yes' : 'no';
  return String(value);
}

/**
 * The seeded lookup vocabulary.
 *
 * The tables are shown one at a time, because twenty-seven little tables on
 * one page are unreadable. A table that could not be read keeps its place in
 * the list and says so, so a missing table is visible rather than silently
 * dropped.
 */
export function SeedCatalogue({ tables }: { tables: SeedTableRead[] }) {
  const firstReadable = tables.find((t) => !t.error)?.table ?? null;
  const [selected, setSelected] = useState<string | null>(firstReadable);
  const current = tables.find((t) => t.table === selected) ?? null;

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap gap-1.5" role="tablist" aria-label="Seeded lookup tables">
        {tables.map((t) => (
          <button
            key={t.table}
            type="button"
            role="tab"
            aria-selected={t.table === selected}
            onClick={() => setSelected(t.table)}
            className={cn(
              'rounded-md border px-2.5 py-1 text-xs font-medium',
              t.table === selected
                ? 'border-primary bg-primary text-primary-foreground'
                : 'border-border bg-background hover:bg-muted',
            )}
          >
            {t.table}
            {t.error ? <span className="ml-1 opacity-70">unreadable</span> : null}
          </button>
        ))}
      </div>

      {current === null ? (
        <EmptyState title="No table selected" description="Choose a seeded table above." />
      ) : current.error ? (
        <div className="space-y-2">
          <p className="text-sm font-medium">{current.table}</p>
          <p className="text-sm text-muted-foreground">This table could not be read: {current.error}</p>
        </div>
      ) : (
        <div className="space-y-3">
          <div className="flex flex-wrap items-center gap-2">
            <p className="text-sm font-medium">{current.table}</p>
            <Badge variant="muted">{current.count} rows</Badge>
          </div>

          {current.rows.length === 0 ? (
            <EmptyState title="No rows" description="This table is empty for you." />
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  {current.columns.map((column) => (
                    <TableHead key={column}>{column}</TableHead>
                  ))}
                </TableRow>
              </TableHeader>
              <TableBody>
                {current.rows.map((row, i) => (
                  <TableRow key={`${current.table}-${i}`}>
                    {current.columns.map((column) => (
                      <TableCell key={column} className="text-xs">
                        {cellValue(row[column])}
                      </TableCell>
                    ))}
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </div>
      )}
    </div>
  );
}
