'use client';

import Link from 'next/link';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { ErrorPanel } from '@/components/ui/empty-state';
import { useRpc } from '@/features/shared/use-rpc';
import { formatDateTime } from '@/lib/format';

export type NotificationRow = {
  notif_key: string;
  kind: string;
  title: string;
  body: string | null;
  href: string | null;
  at: string | null;
};

/** The notification feed, with per-row and bulk dismissal. */
export function NotificationList({ rows }: { rows: NotificationRow[] }) {
  const { run, busy, error } = useRpc();

  if (rows.length === 0) {
    return (
      <p className="rounded-lg border border-dashed border-border p-8 text-center text-sm text-muted-foreground">
        You have no notifications.
      </p>
    );
  }

  return (
    <div className="space-y-3">
      {error && <ErrorPanel message={error} />}
      <div className="flex justify-end">
        <Button variant="outline" size="sm" disabled={busy} onClick={() => void run('notification_dismiss_all')}>
          Dismiss all
        </Button>
      </div>
      <ul className="space-y-2">
        {rows.map((n) => (
          <li key={n.notif_key} className="rounded-lg border border-border bg-card p-4">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div className="min-w-0">
                <div className="flex flex-wrap items-center gap-2">
                  <Badge variant={statusVariant(n.kind)}>{n.kind}</Badge>
                  <span className="text-xs text-muted-foreground">{formatDateTime(n.at)}</span>
                </div>
                <p className="mt-1 font-medium">{n.title}</p>
                {n.body && <p className="mt-1 text-sm text-muted-foreground">{n.body}</p>}
              </div>
              <div className="flex shrink-0 items-center gap-2">
                {n.href && (
                  <Link href={n.href} className="text-sm font-medium text-primary underline-offset-4 hover:underline">
                    Open
                  </Link>
                )}
                <Button
                  variant="ghost"
                  size="sm"
                  disabled={busy}
                  onClick={() => void run('notification_dismiss', { p_key: n.notif_key })}
                >
                  Dismiss
                </Button>
              </div>
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}

export default NotificationList;
