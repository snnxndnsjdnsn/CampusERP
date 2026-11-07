import Link from 'next/link';
import { PageHeader } from '@/components/page-header';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { DetailTable, DetailStack } from '@/features/detail/detail-ui';
import { safeSelect } from '@/features/shared/server-rpc';
import { formatDateTime } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

type LoginRow = {
  login_audit_id: number;
  user_id: number | null;
  username_attempted: string;
  login_at: string;
  logout_at: string | null;
  ip_address: string | null;
  user_agent: string | null;
  was_successful: boolean;
  failure_reason: string | null;
};

/**
 * Sign-in history.
 *
 * `login_audit` is protected by a self-or-admin RLS policy: a user sees their
 * own sign-ins, and anyone holding `IAM.ALL.READ` sees every row. The page
 * therefore shows whatever the database allows and nothing more.
 */
export default async function AuditLoginsPage() {
  const { supabase } = await requireContext();

  const { rows, error } = await safeSelect<LoginRow>(
    supabase,
    'login_audit',
    'login_audit_id, user_id, username_attempted, login_at, logout_at, ip_address, user_agent, was_successful, failure_reason',
    { order: { column: 'login_at', ascending: false }, limit: 200 },
  );

  return (
    <>
      <PageHeader
        title="Sign-in history"
        description="Authentication events recorded by the platform."
        actions={
          <Link href="/audit">
            <Button variant="outline">Back to the audit log</Button>
          </Link>
        }
      />

      <DetailStack>
        {error && (
          <p className="rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800" role="alert">
            {error}
          </p>
        )}

        <DetailTable
          title="Recent sign-ins"
          rows={rows}
          rowKey={(r) => String(r.login_audit_id)}
          emptyTitle="No sign-ins recorded"
          emptyDescription="Sign-in events appear here once the platform starts recording them."
          columns={[
            {
              key: 'when',
              header: 'When',
              render: (r) => formatDateTime(r.login_at),
            },
            {
              key: 'who',
              header: 'User',
              render: (r) => r.username_attempted,
            },
            {
              key: 'result',
              header: 'Result',
              render: (r) => (
                <Badge variant={r.was_successful ? 'success' : 'destructive'}>
                  {r.was_successful ? 'SUCCESS' : 'FAILED'}
                </Badge>
              ),
            },
            {
              key: 'reason',
              header: 'Reason',
              render: (r) => r.failure_reason ?? '—',
            },
            {
              key: 'ip',
              header: 'IP address',
              render: (r) => r.ip_address ?? '—',
            },
            {
              key: 'logout',
              header: 'Signed out',
              render: (r) => (r.logout_at ? formatDateTime(r.logout_at) : '—'),
            },
          ]}
        />
      </DetailStack>
    </>
  );
}
