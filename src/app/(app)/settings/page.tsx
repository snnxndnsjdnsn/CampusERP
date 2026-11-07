import { MfaPanel } from '@/components/account-panels';
import { PageHeader } from '@/components/page-header';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { ProfileForm } from '@/features/account/profile-form';
import { rpcSafe } from '@/lib/api';
import { formatDateTime } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

type Profile = {
  kind: string;
  name?: string | null;
  number?: string | null;
  primary_email?: string | null;
  primary_phone?: string | null;
};

type LoginRow = {
  login_at: string;
  logout_at: string | null;
  was_successful: boolean;
  failure_reason: string | null;
  ip_address: string | null;
};

export default async function SettingsPage() {
  const { ctx, supabase } = await requireContext();

  // Keep the database's `multi_factor_enabled` flag in step with Supabase Auth.
  // It is idempotent and a failure must never break the page.
  await rpcSafe(supabase, 'mfa_sync');

  const [profileResult, loginsResult] = await Promise.all([
    rpcSafe<Profile>(supabase, 'my_profile'),
    rpcSafe<LoginRow[]>(supabase, 'my_recent_logins', { p_limit: 10 }),
  ]);

  const profile = profileResult.data;
  const logins = loginsResult.data ?? [];

  return (
    <>
      <PageHeader
        title="Settings"
        description="Your account, contact details and sign-in security. Every change is recorded by the database."
      />

      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Profile</CardTitle>
            <CardDescription>
              {profile && profile.kind !== 'none'
                ? `Your ${profile.kind === 'student' ? 'student' : 'employee'} record.`
                : 'Your record in the institution.'}
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-4">
            {profileResult.error && <ErrorPanel message={profileResult.error} />}
            {profile && profile.kind !== 'none' ? (
              <>
                <dl className="grid gap-3 text-sm sm:grid-cols-2">
                  <div>
                    <dt className="text-xs uppercase tracking-wide text-muted-foreground">Name</dt>
                    <dd className="font-medium">{profile.name ?? '—'}</dd>
                  </div>
                  <div>
                    <dt className="text-xs uppercase tracking-wide text-muted-foreground">
                      {profile.kind === 'student' ? 'Student number' : 'Employee number'}
                    </dt>
                    <dd className="font-medium">{profile.number ?? '—'}</dd>
                  </div>
                  <div>
                    <dt className="text-xs uppercase tracking-wide text-muted-foreground">Sign-in name</dt>
                    <dd className="font-medium">{ctx.username}</dd>
                  </div>
                  <div>
                    <dt className="text-xs uppercase tracking-wide text-muted-foreground">Account type</dt>
                    <dd>
                      <Badge variant={statusVariant(profile.kind === 'student' ? 'ACTIVE' : 'ACTIVE')}>
                        {profile.kind === 'student' ? 'Student' : profile.kind === 'employee' ? 'Employee' : 'User'}
                      </Badge>
                    </dd>
                  </div>
                </dl>

                <div className="border-t border-border pt-4">
                  <h3 className="mb-3 text-sm font-medium">Contact details</h3>
                  <ProfileForm initialEmail={profile.primary_email ?? null} initialPhone={profile.primary_phone ?? null} />
                </div>
              </>
            ) : (
              !profileResult.error && (
                <EmptyState
                  title="No linked record"
                  description="This account is not linked to a student or employee record, so there are no contact details to edit."
                />
              )
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Recent sign-ins</CardTitle>
            <CardDescription>The last ten authentication attempts recorded for your account.</CardDescription>
          </CardHeader>
          <CardContent>
            {loginsResult.error ? (
              <ErrorPanel message={loginsResult.error} />
            ) : logins.length === 0 ? (
              <EmptyState title="No sign-ins recorded yet" description="Your sign-in history will appear here." />
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>When</TableHead>
                    <TableHead>Result</TableHead>
                    <TableHead>IP address</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {logins.map((l, i) => (
                    <TableRow key={`${l.login_at}-${i}`}>
                      <TableCell>
                        <div className="font-medium">{formatDateTime(l.login_at)}</div>
                        {l.logout_at && (
                          <div className="text-xs text-muted-foreground">Signed out {formatDateTime(l.logout_at)}</div>
                        )}
                      </TableCell>
                      <TableCell>
                        <Badge variant={statusVariant(l.was_successful ? 'SUCCESS' : 'FAILED')}>
                          {l.was_successful ? 'Successful' : 'Failed'}
                        </Badge>
                        {l.failure_reason && (
                          <div className="mt-1 text-xs text-muted-foreground">{l.failure_reason}</div>
                        )}
                      </TableCell>
                      <TableCell className="font-mono text-xs">{l.ip_address ?? '—'}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>
      </div>

      <div className="mt-4">
        <MfaPanel />
      </div>
    </>
  );
}
