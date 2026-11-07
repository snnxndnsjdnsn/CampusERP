import Link from 'next/link';
import { notFound } from 'next/navigation';
import { PageHeader } from '@/components/page-header';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { ErrorPanel } from '@/components/ui/empty-state';
import { DetailFields, DetailStack, JsonBlock } from '@/features/detail/detail-ui';
import { safeRpc } from '@/features/shared/server-rpc';
import { formatDateTime } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

type AuditEntry = {
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

/**
 * One audit entry.
 *
 * The row is fetched through `audit_get()`, which is SECURITY DEFINER and
 * refuses anyone without `AUDIT.ALL.READ`. The page therefore never has to
 * decide who may see it.
 */
export default async function AuditEntryPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { supabase } = await requireContext();

  const numericId = Number(id);
  if (!Number.isInteger(numericId) || numericId <= 0) notFound();

  const { data, error } = await safeRpc<AuditEntry>(supabase, 'audit_get', { p_id: numericId });

  if (error) {
    return (
      <>
        <PageHeader title="Audit entry" description={`Entry #${numericId}`} />
        <ErrorPanel message={error} />
        <div className="mt-4">
          <Link href="/audit">
            <Button variant="outline">Back to the audit log</Button>
          </Link>
        </div>
      </>
    );
  }

  if (!data) notFound();

  return (
    <>
      <PageHeader
        title={data.entity_name ?? `Audit entry #${data.activity_audit_id}`}
        description={`${data.module_code} · ${data.action_code}`}
        actions={
          <Link href="/audit">
            <Button variant="outline">Back to the audit log</Button>
          </Link>
        }
      />

      <DetailStack>
        <DetailFields
          title="Entry"
          fields={[
            { label: 'Activity ID', value: data.activity_audit_id },
            { label: 'When', value: formatDateTime(data.activity_at) },
            { label: 'User', value: data.username ?? '—' },
            { label: 'Module', value: <Badge variant="outline">{data.module_code}</Badge> },
            { label: 'Action', value: <Badge variant={statusVariant(data.action_code)}>{data.action_code}</Badge> },
            { label: 'Entity', value: data.entity_name ?? '—' },
            { label: 'Entity ID', value: data.entity_id ?? '—' },
          ]}
        />

        <Card>
          <CardHeader>
            <CardTitle>Before</CardTitle>
          </CardHeader>
          <CardContent>
            <JsonBlock value={data.before_values} />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>After</CardTitle>
          </CardHeader>
          <CardContent>
            <JsonBlock value={data.after_values} />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Details</CardTitle>
          </CardHeader>
          <CardContent>
            <JsonBlock value={data.details} />
          </CardContent>
        </Card>
      </DetailStack>
    </>
  );
}
