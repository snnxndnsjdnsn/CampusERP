import * as React from 'react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState } from '@/components/ui/empty-state';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';

/**
 * Shared building blocks for the detail screens.
 *
 * These pages all show the same shape of thing: a heading, a few labelled
 * values, and a table of related rows. Keeping the shape in one place means a
 * student record, an audit entry and a fee receipt all read the same way.
 */

/** A labelled value. `value` may be empty; empty values render as an em dash. */
export type Field = { label: string; value: React.ReactNode };

/** A titled block of fields. */
export function DetailFields({ title, fields }: { title?: string; fields: Field[] }) {
  const body = (
    <dl className="grid gap-x-6 gap-y-2 sm:grid-cols-2">
      {fields.map((f) => (
        <div key={f.label} className="min-w-0">
          <dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{f.label}</dt>
          <dd className="mt-0.5 break-words text-sm">{f.value ?? '—'}</dd>
        </div>
      ))}
    </dl>
  );
  if (!title) return body;
  return (
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
      </CardHeader>
      <CardContent>{body}</CardContent>
    </Card>
  );
}

/** A table of rows with a column definition. */
export type Column<T> = {
  key: string;
  header: string;
  /** Right-aligned numeric columns. */
  numeric?: boolean;
  render: (row: T) => React.ReactNode;
};

/** A titled table section that renders an empty state instead of an empty table. */
export function DetailTable<T>({
  title,
  columns,
  rows,
  emptyTitle = 'Nothing to show',
  emptyDescription,
  rowKey,
}: {
  title?: string;
  columns: Column<T>[];
  rows: T[];
  emptyTitle?: string;
  emptyDescription?: string;
  rowKey: (row: T, index: number) => string;
}) {
  const table = rows.length === 0 ? (
    <EmptyState title={emptyTitle} description={emptyDescription} />
  ) : (
    <Table>
      <TableHeader>
        <TableRow>
          {columns.map((c) => (
            <TableHead key={c.key} className={c.numeric ? 'text-right' : undefined}>
              {c.header}
            </TableHead>
          ))}
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.map((row, i) => (
          <TableRow key={rowKey(row, i)}>
            {columns.map((c) => (
              <TableCell key={c.key} className={c.numeric ? 'text-right tabular-nums' : undefined}>
                {c.render(row)}
              </TableCell>
            ))}
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );

  if (!title) return table;
  return (
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
      </CardHeader>
      <CardContent>{table}</CardContent>
    </Card>
  );
}

/** A stack of sections with a consistent gap. */
export function DetailStack({ children }: { children: React.ReactNode }) {
  return <div className="space-y-4">{children}</div>;
}

/**
 * Render an arbitrary JSON value in a readable way.
 *
 * Audit rows and receipts carry `jsonb` payloads; showing them as compact JSON
 * keeps the page honest without pretending the shape is known.
 */
export function JsonBlock({ value }: { value: unknown }) {
  if (value === null || value === undefined) return <span className="text-muted-foreground">—</span>;
  const text = typeof value === 'string' ? value : JSON.stringify(value, null, 2);
  if (!text) return <span className="text-muted-foreground">—</span>;
  return (
    <pre className="max-h-96 overflow-auto rounded-md border border-border bg-muted/40 p-3 text-xs">
      {text}
    </pre>
  );
}
