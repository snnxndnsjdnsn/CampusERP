import { PageHeader } from '@/components/page-header';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { ProvisionUserForm } from '@/features/iam/iam-client';
import { safeRpc } from '@/features/shared/server-rpc';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

export default async function NewUserPage() {
  const { supabase } = await requireContext();

  // The database decides whether this caller may create accounts.
  const canProvision = await safeRpc<boolean>(supabase, 'iam_can_provision');

  return (
    <>
      <PageHeader title="Provision a user" description="Attach an existing sign-in account to a SIMS user." />

      {canProvision.error ? (
        <ErrorPanel message={canProvision.error} />
      ) : canProvision.data !== true ? (
        <EmptyState title="Not allowed" description="You do not have permission to provision accounts." />
      ) : (
        <Card>
          <CardHeader>
            <CardTitle>New account</CardTitle>
          </CardHeader>
          <CardContent>
            <ProvisionUserForm />
          </CardContent>
        </Card>
      )}
    </>
  );
}
