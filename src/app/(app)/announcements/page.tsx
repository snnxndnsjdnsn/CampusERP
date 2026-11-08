import { PageHeader, StatTile } from '@/components/page-header';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { ErrorPanel } from '@/components/ui/empty-state';
import { AdminTableEditor } from '@/features/admin/admin-table-editor';
import {
  AnnouncementComposer,
  AnnouncementFeed,
  AnnouncementManageList,
  type AnnouncementFeedItem,
  type AnnouncementType,
  type DepartmentTarget,
  type ManagedAnnouncement,
} from '@/features/announcements/announcements-client';
import { safeRpc, safeRows, safeSelect } from '@/features/shared/server-rpc';
import { formatNumber } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

export default async function AnnouncementsPage() {
  const { supabase } = await requireContext();

  // The feed is visible to every signed-in user; the database filters it by audience.
  const feed = await safeRows<AnnouncementFeedItem>(supabase, 'announcements_feed', { p_limit: 20 });

  // The management list only returns what this caller may administer.
  const manage = await safeRows<ManagedAnnouncement>(supabase, 'announcements_manage', { p_limit: 20, p_offset: 0 });

  // Announcement types are reference data with an RLS-protected select policy.
  const types = await safeSelect<AnnouncementType>(
    supabase,
    'announcement_type',
    'announcement_type_id, type_code, type_name, is_active',
    { order: { column: 'type_name', ascending: true } },
  );

  // The departments this caller may announce to; the database decides.
  const targets = await safeRows<DepartmentTarget>(supabase, 'announcement_targets');

  const canPostGlobal = await safeRpc<boolean>(supabase, 'announcement_can_post_global');

  const mayPost = canPostGlobal.data === true || targets.rows.length > 0;
  const pending = manage.rows.filter((a) => a.approval_status === 'PENDING').length;
  const drafts = manage.rows.filter((a) => a.approval_status === 'DRAFT' || a.approval_status === 'REJECTED').length;

  return (
    <>
      <PageHeader
        title="Announcements"
        description="Everything the college has published for you, plus the announcements you may write or approve."
      />

      <AdminTableEditor
        modules={['COMMUNICATION']}
        title="Manage announcements"
        description="Add, edit and remove the announcement types behind this screen. Every change is written through the database and audited."
      />

      <div className="grid gap-4 sm:grid-cols-3">
        <StatTile label="Published for you" value={formatNumber(feed.rows.length)} />
        <StatTile label="Awaiting approval" value={formatNumber(pending)} tone="warning" />
        <StatTile label="Your drafts" value={formatNumber(drafts)} />
      </div>

      {mayPost ? (
        <section className="mt-6">
          <Card>
            <CardHeader>
              <CardTitle>Write an announcement</CardTitle>
            </CardHeader>
            <CardContent>
              {types.error ? <ErrorPanel message={types.error} /> : null}
              <AnnouncementComposer types={types.rows} targets={targets.rows} canPostGlobal={canPostGlobal.data === true} />
            </CardContent>
          </Card>
        </section>
      ) : null}

      <section className="mt-6">
        <Card>
          <CardHeader>
            <CardTitle>Announcements</CardTitle>
          </CardHeader>
          <CardContent>{feed.error ? <ErrorPanel message={feed.error} /> : <AnnouncementFeed rows={feed.rows} />}</CardContent>
        </Card>
      </section>

      <section className="mt-6">
        <Card>
          <CardHeader>
            <CardTitle>Manage announcements</CardTitle>
          </CardHeader>
          <CardContent>
            {manage.error ? (
              <ErrorPanel message={manage.error} />
            ) : (
              <AnnouncementManageList rows={manage.rows} types={types.rows} targets={targets.rows} />
            )}
          </CardContent>
        </Card>
      </section>
    </>
  );
}
