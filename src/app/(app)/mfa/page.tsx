import { PageHeader } from '@/components/page-header';
import { MfaPanel } from '@/components/account-panels';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

/**
 * Two-step verification.
 *
 * The enrolment itself happens in the browser through the Supabase Auth MFA
 * API; the database only learns the resulting factor through `auth.mfa_factors`,
 * which is what `mfa_setup_required` reads. This page has no nav entry of its
 * own - it is reached from the account settings screen.
 */
export default async function MfaPage() {
  const { ctx } = await requireContext();

  return (
    <>
      <PageHeader
        title="Two-step verification"
        description={
          ctx.mfa_setup_required
            ? 'Your role requires an authenticator app. Set it up before you continue.'
            : 'Enrol, verify or remove the authenticator app on this account.'
        }
      />
      <MfaPanel />
    </>
  );
}
