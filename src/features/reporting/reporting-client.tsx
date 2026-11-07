'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Input, Label } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { rpcCall } from '@/features/shared/client-rpc';
import { formatNumber, humanise } from '@/lib/format';

/** One row of the `global_search` result. */
export type SearchRow = {
  kind: string;
  id: number;
  title: string | null;
  subtitle: string | null;
};

/**
 * The live directory search.
 *
 * `global_search` only matches when the query is at least two characters
 * long, so the hint below the box says so rather than returning nothing and
 * leaving the reader guessing.
 */
export function GlobalSearch() {
  const [query, setQuery] = useState('');
  const [rows, setRows] = useState<SearchRow[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [searched, setSearched] = useState(false);

  async function search(event: React.FormEvent) {
    event.preventDefault();
    const q = query.trim();
    if (q.length < 2) {
      setRows([]);
      setError(null);
      setSearched(false);
      return;
    }

    setBusy(true);
    setError(null);
    const result = await rpcCall<SearchRow[]>('global_search', { p_q: q, p_limit: 20 });
    setBusy(false);
    setSearched(true);

    if (!result.ok) {
      setRows([]);
      setError(result.error);
      return;
    }
    setRows(result.data ?? []);
  }

  const tooShort = query.trim().length > 0 && query.trim().length < 2;

  return (
    <div className="space-y-4">
      <form onSubmit={search} role="search" className="flex flex-wrap items-end gap-3">
        <div className="min-w-[16rem] flex-1 space-y-1.5">
          <Label htmlFor="global-search">Search</Label>
          <Input
            id="global-search"
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Name, number or code"
            maxLength={80}
          />
        </div>
        <Button type="submit" disabled={busy}>
          {busy ? 'Searching…' : 'Search'}
        </Button>
      </form>

      {tooShort ? (
        <p className="text-xs text-muted-foreground">
          The database ignores queries shorter than two characters - type one more character to search.
        </p>
      ) : null}

      {error ? <ErrorPanel message={error} /> : null}

      {!error && searched && rows.length === 0 ? (
        <EmptyState title="No matches" description="Nothing visible to you matches that search." />
      ) : null}

      {rows.length > 0 ? (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Kind</TableHead>
              <TableHead>Title</TableHead>
              <TableHead>Reference</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((row) => (
              <TableRow key={`${row.kind}-${row.id}`}>
                <TableCell>
                  <Badge variant="muted">{row.kind}</Badge>
                </TableCell>
                <TableCell className="text-sm font-medium">{row.title ?? '—'}</TableCell>
                <TableCell className="font-mono text-xs text-muted-foreground">{row.subtitle ?? '—'}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      ) : null}
    </div>
  );
}

/** The columns the activity reports are read in, in the order they are shown. */
const REPORT_COLUMNS: { key: string; label: string }[] = [
  { key: 'activity_group', label: 'Group' },
  { key: 'type_name', label: 'Type' },
  { key: 'approval_status', label: 'Approval' },
  { key: 'records', label: 'Records' },
  { key: 'employees', label: 'Employees' },
  { key: 'activities', label: 'Activities' },
  { key: 'winners', label: 'Awards' },
];

function cellValue(value: unknown): string {
  if (value === null || value === undefined) return '—';
  if (typeof value === 'number') return formatNumber(value);
  return String(value);
}

/**
 * One of the live activity reports.
 *
 * The report functions check a permission before they aggregate, so a caller
 * without it is refused. The refusal is shown in the panel rather than
 * thrown, because the rest of the reporting screen is still worth reading.
 */
export function ActivityReport({
  fn,
  title,
  description,
}: {
  fn: string;
  title: string;
  description: string;
}) {
  const [rows, setRows] = useState<Record<string, unknown>[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(true);

  const fetchReport = useCallback(async (): Promise<{ rows: Record<string, unknown>[]; error: string | null }> => {
    const result = await rpcCall<Record<string, unknown>[]>(fn, { p_year: null });
    if (!result.ok) return { rows: [], error: result.error };
    return { rows: result.data ?? [], error: null };
  }, [fn]);

  const apply = useCallback((outcome: { rows: Record<string, unknown>[]; error: string | null }) => {
    setBusy(false);
    setRows(outcome.rows);
    setError(outcome.error);
  }, []);

  const reload = useCallback(async () => {
    setBusy(true);
    setError(null);
    apply(await fetchReport());
  }, [apply, fetchReport]);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const outcome = await fetchReport();
      if (cancelled) return;
      apply(outcome);
    })();
    return () => {
      cancelled = true;
    };
  }, [apply, fetchReport]);

  const columns = useMemo(() => {
    const present = new Set<string>();
    for (const row of rows) for (const key of Object.keys(row)) present.add(key);

    const ordered = REPORT_COLUMNS.filter((c) => present.has(c.key)).map((c) => c.key);
    for (const key of present) if (!ordered.includes(key)) ordered.push(key);
    return ordered;
  }, [rows]);

  return (
    <div className="space-y-3">
      <div>
        <p className="text-sm font-semibold">{title}</p>
        <p className="text-xs text-muted-foreground">{description}</p>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-sm text-muted-foreground">
          {busy ? 'Running the report…' : `${rows.length} rows`}
        </p>
        <Button size="sm" variant="outline" onClick={() => void reload()} disabled={busy}>
          {busy ? 'Running…' : 'Run again'}
        </Button>
      </div>
      {error ? <ErrorPanel message={error} /> : null}

      {!busy && !error && rows.length === 0 ? (
        <EmptyState title="Nothing to report" description="The report returned no rows for you." />
      ) : null}

      {rows.length > 0 ? (
        <Table>
          <TableHeader>
            <TableRow>
              {columns.map((key) => (
                <TableHead key={key}>{REPORT_COLUMNS.find((c) => c.key === key)?.label ?? humanise(key)}</TableHead>
              ))}
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.map((row, i) => (
              <TableRow key={i}>
                {columns.map((key) => (
                  <TableCell key={key} className="text-xs">
                    {cellValue(row[key])}
                  </TableCell>
                ))}
              </TableRow>
            ))}
          </TableBody>
        </Table>
      ) : null}
    </div>
  );
}
