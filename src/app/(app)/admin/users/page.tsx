import Link from 'next/link';
import { PageHeader, StatTile } from '@/components/page-header';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { ErrorPanel } from '@/components/ui/empty-state';
import { IamUserTable, type IamUser } from '@/features/iam/iam-client';
import { Pagination } from '@/features/shared/pagination';
import { SearchForm } from '@/features/shared/search-form';
import { safeRows } from '@/features/shared/server-rpc';
import { formatNumber } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

const LIMIT = 20;

export default async function AdminUsersPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; status?: string; offset?: string }>;
}) {
  const { q, status, offset } = await searchParams;
  const { supabase } = await requireContext();

  const search = (q ?? '').trim();
  const statusFilter = (status ?? '').trim();
  const pageOffset = Math.max(Number.parseInt(offset ?? '0', 10) || 0, 0);

  // The database decides which accounts this caller may see and filters them.
  const users = await safeRows<IamUser>(supabase, 'iam_user_list', {
    p_search: search === '' ? null : search,
    p_status: statusFilter === '' ? null : statusFilter,
    p_limit: LIMIT,
    p_offset: pageOffset,
  });

  const total = users.rows[0]?.total_count ?? 0;
  const active = users.rows.filter((u) => u.account_status === 'ACTIVE').length;

  return (
    <>
      <PageHeader
        title="Users and roles"
        description="Every SIMS account, the roles it holds and the person it is linked to."
        actions={
          <Link href="/admin/users/new">
            <Button>Provision a user</Button>
          </Link>
        }
      />

      <div className="grid gap-4 sm:grid-cols-3">
        <StatTile label="Accounts" value={formatNumber(total)} />
        <StatTile label="Active on this page" value={formatNumber(active)} tone="success" />
        <StatTile label="Showing from" value={formatNumber(pageOffset + 1)} />
      </div>

      <Card className="mt-6">
        <CardContent>
          <SearchForm
            action="/admin/users"
            query={search}
            placeholder="Username or email"
            label="Find a user"
            filters={[
              {
                name: 'status',
                label: 'Status',
                value: statusFilter,
                options: [
                  { value: 'ACTIVE', label: 'Active' },
                  { value: 'DISABLED', label: 'Disabled' },
                  { value: 'LOCKED', label: 'Locked' },
                ],
              },
            ]}
          />
        </CardContent>
      </Card>

      <div className="mt-4">
        {users.error ? (
          <ErrorPanel message={users.error} />
        ) : (
          <>
            <IamUserTable rows={users.rows} />
            <Pagination
              basePath="/admin/users"
              filters={{ q: search, status: statusFilter }}
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
