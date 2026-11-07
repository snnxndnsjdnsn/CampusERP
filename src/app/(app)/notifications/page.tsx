import { PageHeader } from '@/components/page-header';
import { ErrorPanel } from '@/components/ui/empty-state';
import { NotificationList, type NotificationRow } from '@/features/account/notification-list';
import { rpcSafe } from '@/lib/api';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

export default async function NotificationsPage() {
  const { supabase } = await requireContext();

  const result = await rpcSafe<NotificationRow[]>(supabase, 'my_notifications', { p_limit: 50 });
  const rows = result.data ?? [];

  return (
    <>
      <PageHeader title="Notifications" description="Everything the system wants to tell you, newest first." />
      {result.error ? <ErrorPanel message={result.error} /> : <NotificationList rows={rows} />}
    </>
  );
}
