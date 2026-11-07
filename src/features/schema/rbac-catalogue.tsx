'use client';

import { StatTile } from '@/components/page-header';
import { Badge } from '@/components/ui/badge';
import { EmptyState } from '@/components/ui/empty-state';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { formatNumber } from '@/lib/format';

/** The `access_module` row registered for the staff profile. */
export type AccessModuleRow = {
  access_module_id: number;
  module_code: string;
  module_name: string;
  description: string | null;
  display_order: number;
};

/** One resource registered under the access module. */
export type AccessResourceRow = {
  access_resource_id: number;
  resource_code: string;
  resource_name: string;
  description: string | null;
};

/** One permission registered under the module's resources. */
export type PermissionRow = {
  permission_id: number;
  permission_code: string;
  permission_name: string;
  is_sensitive: boolean;
};

/** How many staff-profile permissions one role holds. */
export type RoleGrant = {
  /** The role code. */
  role_code: string;
  /** How many grants that role holds. */
  grants: number;
};

export type RbacCatalogueProps = {
  /** The access module row, if it could be read. */
  module: AccessModuleRow | null;
  /** The resources registered under the module. */
  resources: AccessResourceRow[];
  /** The permissions registered under the `STAFF_PROFILE.` prefix. */
  permissions: PermissionRow[];
  /** The roles that hold those permissions, with their grant counts. */
  grants: RoleGrant[];
  /** The reads that failed, shown as a note rather than a crash. */
  errors: string[];
};

/**
 * The RBAC registration of the staff profile.
 *
 * Module 36 registers one access module, the resources under it, the
 * permissions those resources carry and the roles that hold them. The screen
 * reads the registration as it stands, so it shows what the database actually
 * grants rather than what the schema source intended.
 */
export function RbacCatalogue({ module, resources, permissions, grants, errors }: RbacCatalogueProps) {
  const totalGrants = grants.reduce((sum, g) => sum + g.grants, 0);

  return (
    <div className="space-y-6">
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatTile label="Access modules" value={formatNumber(module ? 1 : 0)} />
        <StatTile label="Resources" value={formatNumber(resources.length)} />
        <StatTile label="Permissions" value={formatNumber(permissions.length)} />
        <StatTile label="Role grants" value={formatNumber(totalGrants)} />
      </div>

      {errors.length > 0 ? (
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-4 text-sm text-amber-900" role="status">
          Some parts of the registration could not be read: {errors.join('; ')}
        </div>
      ) : null}

      <section>
        <h3 className="mb-2 text-sm font-semibold uppercase tracking-wide text-muted-foreground">Access module</h3>
        {module === null ? (
          <EmptyState title="No access module" description="The STAFF_PROFILE access module could not be read." />
        ) : (
          <dl className="grid gap-x-6 gap-y-2 rounded-lg border border-border bg-card p-4 text-sm sm:grid-cols-[10rem_1fr]">
            <dt className="text-muted-foreground">Module code</dt>
            <dd className="font-mono">{module.module_code}</dd>
            <dt className="text-muted-foreground">Module name</dt>
            <dd>{module.module_name}</dd>
            <dt className="text-muted-foreground">Description</dt>
            <dd>{module.description ?? '—'}</dd>
            <dt className="text-muted-foreground">Display order</dt>
            <dd>{formatNumber(module.display_order)}</dd>
          </dl>
        )}
      </section>

      <section>
        <h3 className="mb-2 text-sm font-semibold uppercase tracking-wide text-muted-foreground">Access resources</h3>
        {resources.length === 0 ? (
          <EmptyState title="No resources" description="No resource is registered under this module." />
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Resource code</TableHead>
                <TableHead>Resource name</TableHead>
                <TableHead>Description</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {resources.map((r) => (
                <TableRow key={r.access_resource_id}>
                  <TableCell className="font-mono text-xs">{r.resource_code}</TableCell>
                  <TableCell className="text-sm font-medium">{r.resource_name}</TableCell>
                  <TableCell className="text-xs text-muted-foreground">{r.description ?? '—'}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </section>

      <section>
        <h3 className="mb-2 text-sm font-semibold uppercase tracking-wide text-muted-foreground">Permissions</h3>
        {permissions.length === 0 ? (
          <EmptyState title="No permissions" description="No permission carries the STAFF_PROFILE. prefix." />
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Permission code</TableHead>
                <TableHead>Permission name</TableHead>
                <TableHead>Sensitive</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {permissions.map((p) => (
                <TableRow key={p.permission_id}>
                  <TableCell className="font-mono text-xs">{p.permission_code}</TableCell>
                  <TableCell className="text-sm">{p.permission_name}</TableCell>
                  <TableCell>
                    {p.is_sensitive ? <Badge variant="warning">Sensitive</Badge> : <Badge variant="muted">No</Badge>}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </section>

      <section>
        <h3 className="mb-2 text-sm font-semibold uppercase tracking-wide text-muted-foreground">Roles holding them</h3>
        {grants.length === 0 ? (
          <EmptyState title="No grants" description="No active role assignment holds a staff-profile permission." />
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Role</TableHead>
                <TableHead className="text-right">Grants</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {grants.map((g) => (
                <TableRow key={g.role_code}>
                  <TableCell className="font-mono text-xs">{g.role_code}</TableCell>
                  <TableCell className="text-right tabular-nums">{formatNumber(g.grants)}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </section>
    </div>
  );
}
