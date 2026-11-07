'use client';

import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { humanise } from '@/lib/format';
import { useRpcAction } from '@/features/shared/client-rpc';

export type MfaPolicy = {
  role_code: string;
  role_name: string;
  required: boolean;
};

export type MfaGap = {
  user_id: number;
  username: string;
  role_code: string;
};

function MfaPolicyRow({ policy }: { policy: MfaPolicy }) {
  const { busy, error, notice, run } = useRpcAction();

  async function toggle(required: boolean) {
    await run<void>(
      'iam_mfa_policy_set',
      { p_role_code: policy.role_code, p_required: required },
      { success: required ? 'Multi-factor authentication is now required for this role.' : 'Multi-factor authentication is no longer required for this role.' },
    );
  }

  return (
    <TableRow>
      <TableCell>
        <div className="font-medium">{policy.role_name}</div>
        <div className="font-mono text-xs text-muted-foreground">{policy.role_code}</div>
      </TableCell>
      <TableCell>
        {policy.required ? <Badge variant="success">Required</Badge> : <Badge variant="muted">Not required</Badge>}
      </TableCell>
      <TableCell>
        <div className="space-y-2">
          {error ? <ErrorPanel message={error} /> : null}
          {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
          <Button size="sm" variant="outline" onClick={() => toggle(!policy.required)} disabled={busy}>
            {busy ? 'Saving…' : policy.required ? 'Make optional' : 'Make required'}
          </Button>
        </div>
      </TableCell>
    </TableRow>
  );
}

export function MfaPolicyTable({ rows }: { rows: MfaPolicy[] }) {
  if (rows.length === 0) {
    return <EmptyState title="No roles" description="No role is available to configure." />;
  }

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Role</TableHead>
          <TableHead>Multi-factor</TableHead>
          <TableHead>Change</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.map((p) => (
          <MfaPolicyRow key={p.role_code} policy={p} />
        ))}
      </TableBody>
    </Table>
  );
}

export function MfaGapTable({ rows }: { rows: MfaGap[] }) {
  if (rows.length === 0) {
    return <EmptyState title="No gaps" description="Every account that needs an authenticator has one." />;
  }

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>User</TableHead>
          <TableHead>Role</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.map((g) => (
          <TableRow key={`${g.user_id}-${g.role_code}`}>
            <TableCell className="font-medium">{g.username}</TableCell>
            <TableCell>{humanise(g.role_code)}</TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
