'use client';

import Link from 'next/link';
import { useState } from 'react';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Input, Label, Select, Textarea } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { formatDateTime, humanise } from '@/lib/format';
import { useRpcAction } from '@/features/shared/client-rpc';

/* ------------------------------------------------------------------ types */

export type IamUser = {
  user_id: number;
  username: string;
  email: string | null;
  account_status: string;
  last_login_at: string | null;
  roles: string;
  linked_to: string;
  total_count: number;
};

export type IamRole = {
  role_id: number;
  role_code: string;
  role_name: string;
  role_level: string;
};

export type ScopeOption = { id: number; label: string };

export type ScopeEntities = {
  INSTITUTION: ScopeOption[];
  CAMPUS: ScopeOption[];
  DEPARTMENT: ScopeOption[];
  PROGRAMME: ScopeOption[];
};

export type Assignment = {
  assignment_id: number;
  role_name: string;
  role_code: string;
  scope_type: string;
  scope: string;
  status: string;
  valid_from: string;
  valid_to: string | null;
  reason: string | null;
};

export type UserDetail = {
  user_id: number;
  username: string;
  email: string | null;
  account_status: string;
  last_login_at: string | null;
  locked_until: string | null;
  is_self: boolean;
  can_update: boolean;
  assignments: Assignment[];
};

export type PermissionOverride = {
  id: number;
  permission: string;
  effect: string;
  scope_type: string;
  scope: string | null;
  valid_from: string;
  valid_to: string | null;
  active: boolean;
  justification: string;
  granted_by: string | null;
};

export type PermissionOption = {
  permission_code: string;
  permission_name: string;
  is_sensitive: boolean;
};

const SCOPES = ['GLOBAL', 'INSTITUTION', 'CAMPUS', 'DEPARTMENT', 'PROGRAMME', 'SELF'];
const ENTITY_SCOPES = ['INSTITUTION', 'CAMPUS', 'DEPARTMENT', 'PROGRAMME'];

/* ------------------------------------------------------------- user table */

export function IamUserTable({ rows }: { rows: IamUser[] }) {
  if (rows.length === 0) {
    return <EmptyState title="No users" description="No account matches this filter." />;
  }

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>User</TableHead>
          <TableHead>Status</TableHead>
          <TableHead>Roles</TableHead>
          <TableHead>Linked to</TableHead>
          <TableHead>Last sign-in</TableHead>
          <TableHead className="text-right">Open</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.map((u) => (
          <TableRow key={u.user_id}>
            <TableCell>
              <div className="font-medium">{u.username}</div>
              <div className="text-xs text-muted-foreground">{u.email ?? '—'}</div>
            </TableCell>
            <TableCell>
              <Badge variant={statusVariant(u.account_status)}>{humanise(u.account_status)}</Badge>
            </TableCell>
            <TableCell className="max-w-xs text-xs">{u.roles || '—'}</TableCell>
            <TableCell className="text-xs">{u.linked_to || '—'}</TableCell>
            <TableCell className="text-xs">{formatDateTime(u.last_login_at)}</TableCell>
            <TableCell className="text-right">
              <Link
                href={`/admin/users/${u.user_id}`}
                className="text-sm font-medium text-primary underline-offset-4 hover:underline"
              >
                Manage
              </Link>
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

/* -------------------------------------------------------- account status */

export function AccountStatusControl({ userId, status }: { userId: number; status: string }) {
  const { busy, error, notice, run } = useRpcAction();
  const [next, setNext] = useState('');
  const [reason, setReason] = useState('');

  async function apply() {
    await run<void>(
      'iam_set_account_status',
      { p_user_id: userId, p_status: next, p_reason: reason.trim() || null },
      { success: `The account is now ${humanise(next).toLowerCase()}.` },
    );
    setReason('');
  }

  const needsReason = next === 'DISABLED' || next === 'LOCKED';

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap items-end gap-2">
        <div className="min-w-[10rem] space-y-1">
          <Label htmlFor={`iam-status-${userId}`}>New status</Label>
          <Select id={`iam-status-${userId}`} value={next} onChange={(e) => setNext(e.target.value)}>
            <option value="">Choose…</option>
            {['ACTIVE', 'DISABLED', 'LOCKED'].map((s) => (
              <option key={s} value={s}>
                {humanise(s)}
              </option>
            ))}
          </Select>
        </div>
        <div className="min-w-[14rem] flex-1 space-y-1">
          <Label htmlFor={`iam-reason-${userId}`}>Reason {needsReason ? '(required)' : '(optional)'}</Label>
          <Input id={`iam-reason-${userId}`} value={reason} onChange={(e) => setReason(e.target.value)} maxLength={500} />
        </div>
        <Button onClick={apply} disabled={busy || !next || (needsReason && !reason.trim())}>
          {busy ? 'Applying…' : 'Apply'}
        </Button>
      </div>
      {error ? <ErrorPanel message={error} /> : null}
      {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
      <p className="text-xs text-muted-foreground">Current status: {humanise(status)}</p>
    </div>
  );
}

/* ------------------------------------------------------------ role grants */

export function AssignRoleForm({
  userId,
  roles,
  entities,
}: {
  userId: number;
  roles: IamRole[];
  entities: ScopeEntities;
}) {
  const { busy, error, notice, run } = useRpcAction();
  const [roleId, setRoleId] = useState('');
  const [entityId, setEntityId] = useState('');
  const [reason, setReason] = useState('');

  const role = roles.find((r) => String(r.role_id) === roleId);
  const scopeType = role?.role_level ?? '';
  const needsEntity = ENTITY_SCOPES.includes(scopeType);
  const options = needsEntity ? (entities[scopeType as keyof ScopeEntities] ?? []) : [];

  async function assign() {
    await run<number>(
      'iam_assign_role',
      {
        p_user_id: userId,
        p_role_id: Number(roleId),
        p_scope_type: scopeType,
        p_scope_entity_id: needsEntity ? (entityId === '' ? null : Number(entityId)) : null,
        p_reason: reason.trim() || null,
      },
      { success: 'The role has been assigned.' },
    );
    setRoleId('');
    setEntityId('');
    setReason('');
  }

  return (
    <div className="space-y-2">
      <div className="grid gap-2 sm:grid-cols-3">
        <div className="space-y-1">
          <Label htmlFor={`iam-role-${userId}`}>Role</Label>
          <Select id={`iam-role-${userId}`} value={roleId} onChange={(e) => setRoleId(e.target.value)}>
            <option value="">Choose a role</option>
            {roles.map((r) => (
              <option key={r.role_id} value={r.role_id}>
                {r.role_name} ({r.role_level})
              </option>
            ))}
          </Select>
        </div>
        {needsEntity ? (
          <div className="space-y-1">
            <Label htmlFor={`iam-scope-${userId}`}>Scope</Label>
            <Select id={`iam-scope-${userId}`} value={entityId} onChange={(e) => setEntityId(e.target.value)}>
              <option value="">Choose…</option>
              {options.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.label}
                </option>
              ))}
            </Select>
          </div>
        ) : null}
        <div className="space-y-1">
          <Label htmlFor={`iam-role-reason-${userId}`}>Reason</Label>
          <Input id={`iam-role-reason-${userId}`} value={reason} onChange={(e) => setReason(e.target.value)} maxLength={500} />
        </div>
      </div>
      {error ? <ErrorPanel message={error} /> : null}
      {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
      <Button onClick={assign} disabled={busy || !role || (needsEntity && entityId === '')}>
        {busy ? 'Assigning…' : 'Assign the role'}
      </Button>
    </div>
  );
}

export function RevokeRoleButton({ assignmentId }: { assignmentId: number }) {
  const { busy, error, notice, run } = useRpcAction();
  const [reason, setReason] = useState('');

  async function revoke() {
    await run<void>('iam_revoke_role', { p_assignment_id: assignmentId, p_reason: reason.trim() || null }, { success: 'The role has been revoked.' });
    setReason('');
  }

  return (
    <div className="space-y-2">
      <Input
        value={reason}
        onChange={(e) => setReason(e.target.value)}
        placeholder="Reason (optional)"
        maxLength={500}
        aria-label="Reason for revoking this role"
      />
      {error ? <ErrorPanel message={error} /> : null}
      {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
      <Button size="sm" variant="ghost" onClick={revoke} disabled={busy}>
        {busy ? 'Revoking…' : 'Revoke'}
      </Button>
    </div>
  );
}

/* ------------------------------------------------------------ link a person */

export function LinkPersonForm({ userId }: { userId: number }) {
  const { busy, error, notice, run } = useRpcAction();
  const [studentNumber, setStudentNumber] = useState('');
  const [employeeNumber, setEmployeeNumber] = useState('');

  async function link() {
    await run<void>(
      'iam_link_person',
      {
        p_user_id: userId,
        p_student_number: studentNumber.trim() || null,
        p_employee_number: employeeNumber.trim() || null,
      },
      { success: 'The account is now linked to that person.' },
    );
    setStudentNumber('');
    setEmployeeNumber('');
  }

  return (
    <div className="space-y-2">
      <div className="grid gap-2 sm:grid-cols-2">
        <div className="space-y-1">
          <Label htmlFor={`iam-student-${userId}`}>Student number</Label>
          <Input id={`iam-student-${userId}`} value={studentNumber} onChange={(e) => setStudentNumber(e.target.value)} maxLength={60} />
        </div>
        <div className="space-y-1">
          <Label htmlFor={`iam-employee-${userId}`}>Employee number</Label>
          <Input id={`iam-employee-${userId}`} value={employeeNumber} onChange={(e) => setEmployeeNumber(e.target.value)} maxLength={60} />
        </div>
      </div>
      {error ? <ErrorPanel message={error} /> : null}
      {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
      <Button onClick={link} disabled={busy || (studentNumber.trim() === '' && employeeNumber.trim() === '')}>
        {busy ? 'Linking…' : 'Link the account'}
      </Button>
      <p className="text-xs text-muted-foreground">Give a student number or an employee number, not both.</p>
    </div>
  );
}

/* --------------------------------------------------------- permission overrides */

export function OverrideForm({
  userId,
  permissions,
  entities,
}: {
  userId: number;
  permissions: PermissionOption[];
  entities: ScopeEntities;
}) {
  const { busy, error, notice, run } = useRpcAction();
  const [permissionCode, setPermissionCode] = useState('');
  const [effect, setEffect] = useState('ALLOW');
  const [scopeType, setScopeType] = useState('GLOBAL');
  const [entityId, setEntityId] = useState('');
  const [justification, setJustification] = useState('');
  const [validTo, setValidTo] = useState('');

  const needsEntity = ENTITY_SCOPES.includes(scopeType);
  const options = needsEntity ? (entities[scopeType as keyof ScopeEntities] ?? []) : [];

  async function save() {
    await run<number>(
      'iam_override_set',
      {
        p_user_id: userId,
        p_permission_code: permissionCode,
        p_effect: effect,
        p_scope_type: scopeType,
        p_scope_entity_id: needsEntity ? (entityId === '' ? null : Number(entityId)) : null,
        p_justification: justification.trim(),
        p_valid_to: validTo ? new Date(validTo).toISOString() : null,
      },
      { success: 'The permission override has been recorded.' },
    );
    setJustification('');
    setValidTo('');
  }

  const ready = permissionCode !== '' && justification.trim() !== '' && (!needsEntity || entityId !== '');

  return (
    <div className="space-y-2">
      <div className="grid gap-2 sm:grid-cols-2">
        <div className="space-y-1">
          <Label htmlFor={`iam-perm-${userId}`}>Permission</Label>
          <Select id={`iam-perm-${userId}`} value={permissionCode} onChange={(e) => setPermissionCode(e.target.value)}>
            <option value="">Choose a permission</option>
            {permissions.map((p) => (
              <option key={p.permission_code} value={p.permission_code}>
                {p.permission_code} — {p.permission_name}
                {p.is_sensitive ? ' (sensitive)' : ''}
              </option>
            ))}
          </Select>
        </div>
        <div className="space-y-1">
          <Label htmlFor={`iam-effect-${userId}`}>Effect</Label>
          <Select id={`iam-effect-${userId}`} value={effect} onChange={(e) => setEffect(e.target.value)}>
            <option value="ALLOW">Allow</option>
            <option value="DENY">Deny</option>
          </Select>
        </div>
      </div>

      <div className="grid gap-2 sm:grid-cols-3">
        <div className="space-y-1">
          <Label htmlFor={`iam-ov-scope-${userId}`}>Scope</Label>
          <Select id={`iam-ov-scope-${userId}`} value={scopeType} onChange={(e) => setScopeType(e.target.value)}>
            {SCOPES.map((s) => (
              <option key={s} value={s}>
                {humanise(s)}
              </option>
            ))}
          </Select>
        </div>
        {needsEntity ? (
          <div className="space-y-1">
            <Label htmlFor={`iam-ov-entity-${userId}`}>Scope entity</Label>
            <Select id={`iam-ov-entity-${userId}`} value={entityId} onChange={(e) => setEntityId(e.target.value)}>
              <option value="">Choose…</option>
              {options.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.label}
                </option>
              ))}
            </Select>
          </div>
        ) : null}
        <div className="space-y-1">
          <Label htmlFor={`iam-ov-until-${userId}`}>Valid until (optional)</Label>
          <Input id={`iam-ov-until-${userId}`} type="datetime-local" value={validTo} onChange={(e) => setValidTo(e.target.value)} />
        </div>
      </div>

      <div className="space-y-1">
        <Label htmlFor={`iam-ov-just-${userId}`}>Justification (required)</Label>
        <Textarea id={`iam-ov-just-${userId}`} value={justification} onChange={(e) => setJustification(e.target.value)} maxLength={500} />
      </div>

      {error ? <ErrorPanel message={error} /> : null}
      {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
      <Button onClick={save} disabled={busy || !ready}>
        {busy ? 'Saving…' : 'Record the override'}
      </Button>
    </div>
  );
}

export function OverrideList({ overrides }: { overrides: PermissionOverride[] }) {
  if (overrides.length === 0) {
    return <EmptyState title="No overrides" description="This account has no individual permission overrides." />;
  }

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Permission</TableHead>
          <TableHead>Effect</TableHead>
          <TableHead>Scope</TableHead>
          <TableHead>Valid</TableHead>
          <TableHead>Justification</TableHead>
          <TableHead>Granted by</TableHead>
          <TableHead>End</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {overrides.map((o) => (
          <OverrideRow key={o.id} override={o} />
        ))}
      </TableBody>
    </Table>
  );
}

function OverrideRow({ override }: { override: PermissionOverride }) {
  const { busy, error, notice, run } = useRpcAction();
  const [reason, setReason] = useState('');

  async function end() {
    await run<void>('iam_override_end', { p_override_id: override.id, p_reason: reason.trim() || null }, { success: 'The override has ended.' });
    setReason('');
  }

  return (
    <TableRow>
      <TableCell className="font-mono text-xs">{override.permission}</TableCell>
      <TableCell>
        <Badge variant={override.effect === 'ALLOW' ? 'success' : 'destructive'}>{humanise(override.effect)}</Badge>
      </TableCell>
      <TableCell className="text-xs">
        <div>{humanise(override.scope_type)}</div>
        {override.scope ? <div className="text-muted-foreground">{override.scope}</div> : null}
      </TableCell>
      <TableCell className="text-xs">
        <div>{formatDateTime(override.valid_from)}</div>
        <div className="text-muted-foreground">{override.valid_to ? `to ${formatDateTime(override.valid_to)}` : 'no end date'}</div>
        {!override.active ? <Badge variant="muted">Ended</Badge> : null}
      </TableCell>
      <TableCell className="max-w-xs text-xs">{override.justification}</TableCell>
      <TableCell className="text-xs">{override.granted_by ?? '—'}</TableCell>
      <TableCell>
        {override.active ? (
          <div className="space-y-2">
            <Input
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="Reason (optional)"
              maxLength={500}
              aria-label="Reason for ending this override"
            />
            {error ? <ErrorPanel message={error} /> : null}
            {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
            <Button size="sm" variant="ghost" onClick={end} disabled={busy}>
              {busy ? 'Ending…' : 'End override'}
            </Button>
          </div>
        ) : (
          <span className="text-xs text-muted-foreground">—</span>
        )}
      </TableCell>
    </TableRow>
  );
}

/* ------------------------------------------------------------- provisioning */

export function ProvisionUserForm() {
  const { busy, error, notice, run } = useRpcAction();
  const [email, setEmail] = useState('');
  const [studentNumber, setStudentNumber] = useState('');
  const [employeeNumber, setEmployeeNumber] = useState('');

  // `iam_link_auth_user` finds the sign-in account by email and provisions the
  // SIMS user for it; `iam_provision_user` needs the raw auth id, which the
  // browser never sees.
  async function provision() {
    await run<number>(
      'iam_link_auth_user',
      {
        p_email: email.trim(),
        p_student_number: studentNumber.trim() || null,
        p_employee_number: employeeNumber.trim() || null,
      },
      { success: 'The account has been provisioned.' },
    );
    setEmail('');
    setStudentNumber('');
    setEmployeeNumber('');
  }

  return (
    <div className="space-y-3">
      <div className="space-y-1">
        <Label htmlFor="iam-new-email">Email address</Label>
        <Input id="iam-new-email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} maxLength={254} />
      </div>
      <div className="grid gap-3 sm:grid-cols-2">
        <div className="space-y-1">
          <Label htmlFor="iam-new-student">Student number (optional)</Label>
          <Input id="iam-new-student" value={studentNumber} onChange={(e) => setStudentNumber(e.target.value)} maxLength={60} />
        </div>
        <div className="space-y-1">
          <Label htmlFor="iam-new-employee">Employee number (optional)</Label>
          <Input id="iam-new-employee" value={employeeNumber} onChange={(e) => setEmployeeNumber(e.target.value)} maxLength={60} />
        </div>
      </div>
      {error ? <ErrorPanel message={error} /> : null}
      {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
      <Button onClick={provision} disabled={busy || email.trim() === ''}>
        {busy ? 'Provisioning…' : 'Provision the account'}
      </Button>
      <p className="text-xs text-muted-foreground">
        The sign-in account must already exist in Supabase Authentication. Use the link form on a user page to attach an
        existing sign-in to a student or employee record.
      </p>
    </div>
  );
}

/* ------------------------------------------------------------ detail panel */

export function UserDetailPanel({
  detail,
  roles,
  entities,
  permissions,
  overrides,
}: {
  detail: UserDetail;
  roles: IamRole[];
  entities: ScopeEntities;
  permissions: PermissionOption[];
  overrides: PermissionOverride[];
}) {
  return (
    <div className="space-y-6">
      <Card>
        <CardHeader>
          <CardTitle>Account</CardTitle>
        </CardHeader>
        <CardContent>
          <dl className="grid gap-2 text-sm sm:grid-cols-2">
            <div>
              <dt className="text-xs text-muted-foreground">Username</dt>
              <dd className="font-medium">{detail.username}</dd>
            </div>
            <div>
              <dt className="text-xs text-muted-foreground">Email</dt>
              <dd>{detail.email ?? '—'}</dd>
            </div>
            <div>
              <dt className="text-xs text-muted-foreground">Status</dt>
              <dd>
                <Badge variant={statusVariant(detail.account_status)}>{humanise(detail.account_status)}</Badge>
              </dd>
            </div>
            <div>
              <dt className="text-xs text-muted-foreground">Last sign-in</dt>
              <dd>{formatDateTime(detail.last_login_at)}</dd>
            </div>
            {detail.locked_until ? (
              <div>
                <dt className="text-xs text-muted-foreground">Locked until</dt>
                <dd>{formatDateTime(detail.locked_until)}</dd>
              </div>
            ) : null}
          </dl>
          {detail.can_update && !detail.is_self ? (
            <div className="mt-4">
              <AccountStatusControl userId={detail.user_id} status={detail.account_status} />
            </div>
          ) : null}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Role assignments</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          {detail.assignments.length === 0 ? (
            <EmptyState title="No roles" description="This account holds no role assignment yet." />
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Role</TableHead>
                  <TableHead>Scope</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Valid</TableHead>
                  <TableHead>Reason</TableHead>
                  <TableHead>Revoke</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {detail.assignments.map((a) => (
                  <TableRow key={a.assignment_id}>
                    <TableCell>
                      <div className="font-medium">{a.role_name}</div>
                      <div className="font-mono text-xs text-muted-foreground">{a.role_code}</div>
                    </TableCell>
                    <TableCell className="text-xs">
                      <div>{humanise(a.scope_type)}</div>
                      {a.scope ? <div className="text-muted-foreground">{a.scope}</div> : null}
                    </TableCell>
                    <TableCell>
                      <Badge variant={statusVariant(a.status)}>{humanise(a.status)}</Badge>
                    </TableCell>
                    <TableCell className="text-xs">
                      <div>{formatDateTime(a.valid_from)}</div>
                      {a.valid_to ? <div className="text-muted-foreground">to {formatDateTime(a.valid_to)}</div> : null}
                    </TableCell>
                    <TableCell className="max-w-xs text-xs">{a.reason ?? '—'}</TableCell>
                    <TableCell>
                      {detail.can_update && !detail.is_self && a.status === 'ACTIVE' ? (
                        <RevokeRoleButton assignmentId={a.assignment_id} />
                      ) : (
                        <span className="text-xs text-muted-foreground">—</span>
                      )}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}

          {detail.can_update && !detail.is_self ? (
            <div className="space-y-2">
              <h3 className="text-sm font-semibold">Assign a role</h3>
              <AssignRoleForm userId={detail.user_id} roles={roles} entities={entities} />
            </div>
          ) : null}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Permission overrides</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <OverrideList overrides={overrides} />
          {detail.can_update && !detail.is_self ? (
            <div className="space-y-2">
              <h3 className="text-sm font-semibold">Record an override</h3>
              <OverrideForm userId={detail.user_id} permissions={permissions} entities={entities} />
            </div>
          ) : null}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Person link</CardTitle>
        </CardHeader>
        <CardContent>
          {detail.can_update && !detail.is_self ? (
            <LinkPersonForm userId={detail.user_id} />
          ) : (
            <p className="text-sm text-muted-foreground">You cannot change this account&apos;s person link.</p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
