import Link from 'next/link';
import { PageHeader, StatTile } from '@/components/page-header';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { ErrorPanel } from '@/components/ui/empty-state';
import { Input, Label, Select } from '@/components/ui/input';
import { AuditTable, type AuditRow } from '@/features/audit/audit-client';
import { Pagination } from '@/features/shared/pagination';
import { safeRows } from '@/features/shared/server-rpc';
import { formatNumber } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

const LIMIT = 25;

export default async function AuditPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; module?: string; action?: string; from?: string; to?: string; offset?: string }>;
}) {
  const { q, module: moduleCode, action, from, to, offset } = await searchParams;
  const { supabase } = await requireContext();

  const search = (q ?? '').trim();
  const moduleFilter = (moduleCode ?? '').trim();
  const actionFilter = (action ?? '').trim();
  const fromFilter = (from ?? '').trim();
  const toFilter = (to ?? '').trim();
  const pageOffset = Math.max(Number.parseInt(offset ?? '0', 10) || 0, 0);

  // The database decides which entries this caller may read and filters them.
  const entries = await safeRows<AuditRow>(supabase, 'audit_list', {
    p_module: moduleFilter === '' ? null : moduleFilter,
    p_action: actionFilter === '' ? null : actionFilter,
    p_search: search === '' ? null : search,
    p_from: fromFilter === '' ? null : new Date(fromFilter).toISOString(),
    p_to: toFilter === '' ? null : new Date(toFilter).toISOString(),
    p_limit: LIMIT,
    p_offset: pageOffset,
  });

  // The module codes that actually appear in the log.
  const modules = await safeRows<{ module_code: string }>(supabase, 'audit_modules');

  const total = entries.rows[0]?.total_count ?? 0;
  const active = search !== '' || moduleFilter !== '' || actionFilter !== '' || fromFilter !== '' || toFilter !== '';

  return (
    <>
      <PageHeader title="Audit log" description="Every recorded change to the SIMS data, with the values before and after." />

      <div className="grid gap-4 sm:grid-cols-3">
        <StatTile label="Entries" value={formatNumber(total)} />
        <StatTile label="On this page" value={formatNumber(entries.rows.length)} />
        <StatTile label="Modules seen" value={formatNumber(modules.rows.length)} />
      </div>

      <Card className="mt-6">
        <CardContent>
          <form action="/audit" method="get" role="search" className="flex flex-wrap items-end gap-3">
            <div className="min-w-[13rem] flex-1 space-y-1.5">
              <Label htmlFor="audit-q">Search</Label>
              <Input id="audit-q" name="q" type="search" defaultValue={search} placeholder="Entity, id or user" maxLength={120} />
            </div>
            <div className="min-w-[10rem] space-y-1.5">
              <Label htmlFor="audit-module">Module</Label>
              <Select id="audit-module" name="module" defaultValue={moduleFilter}>
                <option value="">All</option>
                {modules.rows.map((m) => (
                  <option key={m.module_code} value={m.module_code}>
                    {m.module_code}
                  </option>
                ))}
              </Select>
            </div>
            <div className="min-w-[10rem] space-y-1.5">
              <Label htmlFor="audit-action">Action</Label>
              <Input id="audit-action" name="action" defaultValue={actionFilter} placeholder="UPDATE" maxLength={60} />
            </div>
            <div className="min-w-[9rem] space-y-1.5">
              <Label htmlFor="audit-from">From</Label>
              <Input id="audit-from" name="from" type="date" defaultValue={fromFilter} />
            </div>
            <div className="min-w-[9rem] space-y-1.5">
              <Label htmlFor="audit-to">To</Label>
              <Input id="audit-to" name="to" type="date" defaultValue={toFilter} />
            </div>
            <Button type="submit" variant="outline">
              Apply
            </Button>
            {active ? (
              <Link href="/audit" className="pb-2 text-sm font-medium text-primary underline-offset-4 hover:underline">
                Clear
              </Link>
            ) : null}
          </form>
        </CardContent>
      </Card>

      <div className="mt-4">
        {entries.error ? (
          <ErrorPanel message={entries.error} />
        ) : (
          <>
            <AuditTable rows={entries.rows} />
            <Pagination
              basePath="/audit"
              filters={{ q: search, module: moduleFilter, action: actionFilter, from: fromFilter, to: toFilter }}
              offset={pageOffset}
              limit={LIMIT}
              total={total}
            />
          </>
        )}
      </div>
    </>
  );
}
