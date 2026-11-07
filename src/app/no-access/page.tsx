import Link from 'next/link';
import { Button } from '@/components/ui/button';

export const dynamic = 'force-dynamic';

/**
 * The account is authenticated with Supabase but has no `user_account` row,
 * so the database resolves no identity and every policy denies.
 */
export default function NoAccessPage() {
  return (
    <div className="flex min-h-screen items-center justify-center p-6">
      <div className="w-full max-w-md rounded-lg border border-border bg-card p-6 text-center shadow-sm">
        <h1 className="text-lg font-semibold tracking-tight">No SIMS account</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          You are signed in, but this sign-in is not linked to a SIMS user account. Ask an administrator to provision
          your account and assign your role.
        </p>
        <div className="mt-6 flex justify-center gap-2">
          <Link href="/login">
            <Button variant="outline">Use another account</Button>
          </Link>
        </div>
      </div>
    </div>
  );
}
