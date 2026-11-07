'use client';

import { useState } from 'react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { formatDateTime, humanise } from '@/lib/format';
import { asObject, rpcCall } from '@/features/shared/client-rpc';

/* ------------------------------------------------------------------ types */

/**
 * Pretty-print a JSON value, or return null when it cannot be serialised.
 *
 * The try/catch lives outside the component: React does not render a
 * component's output while it is being constructed, so a try/catch around
 * JSX would never catch a render-time error anyway.
 */
function stringifyJson(value: unknown): string | null {
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return null;
  }
}

export type AuditRow = {
  activity_audit_id: number;
  activity_at: string;
  username: string | null;
  module_code: string;
  action_code: string;
  entity_name: string | null;
  entity_id: string | null;
  total_count: number;
};

export type AuditDetail = {
  activity_audit_id: number;
  activity_at: string;
  username: string | null;
  module_code: string;
  action_code: string;
  entity_name: string | null;
  entity_id: string | null;
  before_values: unknown;
  after_values: unknown;
  details: unknown;
};

/** Render an arbitrary JSON payload without throwing on odd shapes. */
function JsonBlock({ value }: { value: unknown }) {
  if (value === null || value === undefined) {
    return <p className="text-xs text-muted-foreground">Nothing recorded.</p>;
  }
  if (typeof value === 'string') {
    return <pre className="overflow-x-auto text-xs">{value}</pre>;
  }
  const text = stringifyJson(value);
  if (text === null) {
    return <p className="text-xs text-muted-foreground">The payload could not be displayed.</p>;
  }
  return <pre className="overflow-x-auto text-xs">{text}</pre>;
}

/* ----------------------------------------------------------- detail panel */

function AuditDetailPanel({ id }: { id: number }) {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [detail, setDetail] = useState<AuditDetail | null>(null);

  async function load() {
    setLoading(true);
    setError(null);
    const res = await rpcCall<Record<string, unknown>>('audit_get', { p_id: id });
    if (!res.ok) {
      setError(res.error);
      setLoading(false);
      return;
    }
    setDetail(asObject(res.data) as unknown as AuditDetail);
    setLoading(false);
  }

  return (
    <div className="space-y-2 rounded-md border border-border bg-muted/40 p-3">
      {loading ? <p className="text-sm text-muted-foreground">Loading the entry…</p> : null}
      {error ? <ErrorPanel message={error} /> : null}
      {detail ? (
        <div className="grid gap-3 sm:grid-cols-3">
          <div>
            <h4 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Before</h4>
            <JsonBlock value={detail.before_values} />
          </div>
          <div>
            <h4 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">After</h4>
            <JsonBlock value={detail.after_values} />
          </div>
          <div>
            <h4 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">Details</h4>
            <JsonBlock value={detail.details} />
          </div>
        </div>
      ) : null}
      <Button size="sm" variant="ghost" onClick={load} disabled={loading}>
        {loading ? 'Loading…' : 'Reload'}
      </Button>
    </div>
  );
}

/* ------------------------------------------------------------------ table */

function AuditRowView({ row }: { row: AuditRow }) {
  const [open, setOpen] = useState(false);

  return (
    <>
      <TableRow>
        <TableCell className="text-xs">{formatDateTime(row.activity_at)}</TableCell>
        <TableCell className="text-xs">{row.username ?? '—'}</TableCell>
        <TableCell>
          <Badge variant="muted">{row.module_code}</Badge>
        </TableCell>
        <TableCell className="text-xs">{humanise(row.action_code)}</TableCell>
        <TableCell className="text-xs">
          <div>{row.entity_name ?? '—'}</div>
          {row.entity_id ? <div className="font-mono text-muted-foreground">{row.entity_id}</div> : null}
        </TableCell>
        <TableCell>
          <Button size="sm" variant="outline" onClick={() => setOpen((v) => !v)}>
            {open ? 'Close' : 'Inspect'}
          </Button>
        </TableCell>
      </TableRow>
      {open ? (
        <TableRow>
          <TableCell colSpan={6} className="p-0">
            <AuditDetailPanel id={row.activity_audit_id} />
          </TableCell>
        </TableRow>
      ) : null}
    </>
  );
}

export function AuditTable({ rows }: { rows: AuditRow[] }) {
  if (rows.length === 0) {
    return <EmptyState title="No audit entries" description="Nothing matches this filter." />;
  }

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>When</TableHead>
          <TableHead>User</TableHead>
          <TableHead>Module</TableHead>
          <TableHead>Action</TableHead>
          <TableHead>Entity</TableHead>
          <TableHead>Detail</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.map((r) => (
          <AuditRowView key={r.activity_audit_id} row={r} />
        ))}
      </TableBody>
    </Table>
  );
}
