import Link from 'next/link';
import { PageHeader } from '@/components/page-header';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { DetailStack, DetailTable } from '@/features/detail/detail-ui';
import { safeRpc } from '@/features/shared/server-rpc';
import { formatDateTime } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

type ManagedAnnouncement = {
  announcement_id: number;
  title: string;
  type_name: string;
  department_name: string | null;
  audience_type: string;
  approval_status: string;
  publish_from: string;
  publish_to: string | null;
  is_mine: boolean;
  total_count: number;
};

/**
 * The announcement worklist.
 *
 * `announcements_manage` is SECURITY DEFINER and returns only the rows the
 * caller may act on, with an `is_mine` flag so the UI can tell "mine" from
 * "awaiting my decision".
 */
export default async function AnnouncementsManagePage() {
  const { supabase } = await requireContext();

  const { data, error } = await safeRpc<ManagedAnnouncement[]>(supabase, 'announcements_manage', {
    p_limit: 50,
  });
  const rows = data ?? [];

  return (
    <>
      <PageHeader
        title="Manage announcements"
        description="Announcements you raised, and announcements awaiting your decision."
        actions={
          <Link href="/announcements">
            <Button variant="outline">Back to the feed</Button>
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
          title="Worklist"
          rows={rows}
          rowKey={(r) => String(r.announcement_id)}
          emptyTitle="Nothing to manage"
          emptyDescription="Announcements you raise, and those awaiting your approval, appear here."
          columns={[
            { key: 'title', header: 'Title', render: (r) => r.title },
            { key: 'type', header: 'Type', render: (r) => r.type_name },
            { key: 'department', header: 'Department', render: (r) => r.department_name ?? '—' },
            { key: 'audience', header: 'Audience', render: (r) => r.audience_type },
            {
              key: 'status',
              header: 'Status',
              render: (r) => <Badge variant={statusVariant(r.approval_status)}>{r.approval_status}</Badge>,
            },
            {
              key: 'mine',
              header: 'Raised by me',
              render: (r) => (r.is_mine ? <Badge variant="info">Mine</Badge> : '—'),
            },
            { key: 'from', header: 'Publish from', render: (r) => formatDateTime(r.publish_from) },
            { key: 'to', header: 'Publish to', render: (r) => formatDateTime(r.publish_to) },
          ]}
        />
      </DetailStack>
    </>
  );
}
