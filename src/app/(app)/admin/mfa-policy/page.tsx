import { PageHeader, StatTile } from '@/components/page-header';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { ErrorPanel } from '@/components/ui/empty-state';
import { MfaGapTable, MfaPolicyTable, type MfaGap, type MfaPolicy } from '@/features/iam/mfa-client';
import { safeRows } from '@/features/shared/server-rpc';
import { formatNumber } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

export default async function MfaPolicyPage() {
  const { supabase } = await requireContext();

  // Both reads require IAM.ALL.READ; a refusal is shown rather than thrown.
  const policies = await safeRows<MfaPolicy>(supabase, 'iam_mfa_policy_list');
  const gaps = await safeRows<MfaGap>(supabase, 'iam_mfa_policy_gaps');

  const required = policies.rows.filter((p) => p.required).length;

  return (
    <>
      <PageHeader
        title="Multi-factor policy"
        description="Decide which roles must set up an authenticator app, and see who has not done so yet."
      />

      <div className="grid gap-4 sm:grid-cols-3">
        <StatTile label="Roles" value={formatNumber(policies.rows.length)} />
        <StatTile label="Require MFA" value={formatNumber(required)} tone="warning" />
        <StatTile label="Accounts to fix" value={formatNumber(gaps.rows.length)} tone="destructive" />
      </div>

      <section className="mt-6">
        <Card>
          <CardHeader>
            <CardTitle>Policy by role</CardTitle>
          </CardHeader>
          <CardContent>{policies.error ? <ErrorPanel message={policies.error} /> : <MfaPolicyTable rows={policies.rows} />}</CardContent>
        </Card>
      </section>

      <section className="mt-6">
        <Card>
          <CardHeader>
            <CardTitle>Accounts without an authenticator</CardTitle>
          </CardHeader>
          <CardContent>{gaps.error ? <ErrorPanel message={gaps.error} /> : <MfaGapTable rows={gaps.rows} />}</CardContent>
        </Card>
      </section>
    </>
  );
}
