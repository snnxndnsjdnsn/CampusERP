import type { SupabaseClient } from '@supabase/supabase-js';
import { PageHeader, StatTile } from '@/components/page-header';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { ErrorPanel, EmptyState } from '@/components/ui/empty-state';
import { AdminTableEditor } from '@/features/admin/admin-table-editor';
import { FILE_OBJECT_COLUMNS, type FileObjectColumn } from '@/features/schema/file-object-columns';
import { IndexCatalogue, type SchemaIndex } from '@/features/schema/index-catalogue';
import { IntegrityNotes } from '@/features/schema/integrity-notes';
import type { SchemaModule } from '@/features/schema/module-catalog';
import {
  RbacCatalogue,
  type AccessModuleRow,
  type AccessResourceRow,
  type PermissionRow,
  type RoleGrant,
} from '@/features/schema/rbac-catalogue';
import { SeedCatalogue, type SeedTableRead } from '@/features/schema/seed-catalogue';
import { SEED_TABLES, type SeedTable } from '@/features/schema/seed-tables';
import { safeRows } from '@/features/shared/server-rpc';
import { canReadModule } from '@/lib/context';
import { formatNumber } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

/**
 * The screen behind `/schema/[module]`.
 *
 * Five modules of the schema describe the database itself rather than a
 * business area, so they share one route and one screen. The module decides
 * what is read: the index catalogue and the file storage metadata for module
 * 18, the seed vocabulary for module 35, the access registration for module
 * 36, the staff-scope index catalogue for module 38, and the integrity rules
 * for module 39.
 *
 * Every read is optional. A refusal is shown in the panel it belongs to
 * rather than taking the page down, because a screen that describes the
 * schema is still useful when one corner of it cannot be read.
 */
export async function SchemaScreen({ entry }: { entry: SchemaModule }) {
  const { ctx, supabase } = await requireContext();

  // The sidebar only offers the screen to a caller who can read one of the
  // modules behind it. The address has to agree with the sidebar, otherwise a
  // typed URL would open a screen the navigation deliberately hides. The
  // database still refuses the data itself - this is the door, not the lock.
  if (!entry.accessModules.some((module) => canReadModule(ctx, module))) {
    return (
      <>
        <PageHeader title={`${entry.module} · ${entry.title}`} description={entry.description} />
        <EmptyState
          title="This screen is not open to your account"
          description={`It belongs to the ${entry.accessModules.join(' or ')} module, and your account reads neither. The sidebar only offers it to the accounts that may use it.`}
        />
      </>
    );
  }

  return (
    <>
      <PageHeader title={`${entry.module} · ${entry.title}`} description={entry.description} />

      <AdminTableEditor
        modules={['IAM', 'STAFF_PROFILE']}
        title="Manage the schema records"
        description="Add, edit and remove the access and staff-profile records behind this screen. Every change is written through the database and audited."
      />

      <p className="mb-4 text-xs text-muted-foreground">
        Gated by the <span className="font-mono">{entry.accessModules.join(' or ')}</span> access module.
      </p>

      {entry.module === '18' ? (
        <>
          <IndexCatalogueScreen supabase={supabase} scope="all" />
          <FileStorageScreen supabase={supabase} />
        </>
      ) : null}
      {entry.module === '35' ? <SeedCatalogueScreen supabase={supabase} /> : null}
      {entry.module === '36' ? <RbacCatalogueScreen supabase={supabase} /> : null}
      {entry.module === '38' ? <IndexCatalogueScreen supabase={supabase} scope="staff" /> : null}
      {entry.module === '39' ? <IntegrityNotes /> : null}
    </>
  );
}

/* -------------------------------------------------------------- module 18 */

async function IndexCatalogueScreen({ supabase, scope }: { supabase: SupabaseClient; scope: 'all' | 'staff' }) {
  const indexes = await safeRows<SchemaIndex>(supabase, 'schema_indexes', { p_scope: scope });

  return (
    <Card>
      <CardHeader>
        <CardTitle>Index catalogue</CardTitle>
        <CardDescription>
          {scope === 'all'
            ? 'Every index in the public schema, read from the live catalogue.'
            : 'The indexes of the tables that carry a staff profile row-level security policy.'}
        </CardDescription>
      </CardHeader>
      <CardContent>
        {indexes.error ? <ErrorPanel message={indexes.error} /> : <IndexCatalogue rows={indexes.rows} scope={scope} />}
      </CardContent>
    </Card>
  );
}

/**
 * The file storage metadata of module 18.
 *
 * The shape of `file_object` is written down in the catalogue, because
 * PostgREST cannot see `information_schema`; the row count is read from the
 * table, so it is always the number of files this caller may see.
 */
async function FileStorageScreen({ supabase }: { supabase: SupabaseClient }) {
  const storage = await readFileObject(supabase);

  return (
    <Card className="mt-6">
      <CardHeader>
        <CardTitle>File storage metadata</CardTitle>
        <CardDescription>
          The columns module 18 added to the file storage table, and how many files it holds for you.
        </CardDescription>
      </CardHeader>
      <CardContent>
        {storage.error ? (
          <ErrorPanel message={storage.error} />
        ) : (
          <FileStorageDefinition columns={FILE_OBJECT_COLUMNS} count={storage.count} />
        )}
      </CardContent>
    </Card>
  );
}

function FileStorageDefinition({ columns, count }: { columns: FileObjectColumn[]; count: number | null }) {
  return (
    <div className="space-y-3">
      <p className="text-sm text-muted-foreground">
        {count === null ? 'The row count is not available.' : `${formatNumber(count)} rows visible to you.`}
      </p>
      <dl className="divide-y divide-border rounded-lg border border-border">
        {columns.map((column) => (
          <div
            key={column.name}
            className="grid gap-1 p-3 sm:grid-cols-[minmax(0,16rem)_minmax(0,1fr)_7rem] sm:items-baseline"
          >
            <dt className="font-mono text-xs font-medium">{column.name}</dt>
            <dd className="font-mono text-xs text-muted-foreground">{column.type}</dd>
            <dd className="text-xs text-muted-foreground sm:text-right">
              {column.nullable ? 'nullable' : 'not null'}
            </dd>
          </div>
        ))}
      </dl>
    </div>
  );
}

async function readFileObject(supabase: SupabaseClient): Promise<{ count: number | null; error: string | null }> {
  try {
    const { count, error } = await supabase.from('file_object').select('file_object_id', { count: 'exact', head: true });
    if (error) return { count: null, error: error.message };
    return { count: count ?? null, error: null };
  } catch (e) {
    return { count: null, error: e instanceof Error ? e.message : 'The file storage table could not be read.' };
  }
}

/* -------------------------------------------------------------- module 35 */

async function SeedCatalogueScreen({ supabase }: { supabase: SupabaseClient }) {
  const tables = await Promise.all(SEED_TABLES.map((t) => readSeedTable(supabase, t)));
  const readable = tables.filter((t) => !t.error).length;
  const missing = tables.length - readable;

  return (
    <>
      <div className="grid gap-4 sm:grid-cols-3">
        <StatTile label="Tables" value={formatNumber(tables.length)} />
        <StatTile label="Readable" value={formatNumber(readable)} tone="success" />
        <StatTile label="Not readable" value={formatNumber(missing)} tone={missing > 0 ? 'warning' : 'default'} />
      </div>

      <Card className="mt-6">
        <CardHeader>
          <CardTitle>Seeded lookup tables</CardTitle>
          <CardDescription>
            The vocabulary the staff profile screens pick their options from. A table this database does not carry is
            still listed, so a missing table is visible rather than silently dropped.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <SeedCatalogue tables={tables} />
        </CardContent>
      </Card>
    </>
  );
}

/**
 * Read one seeded lookup table.
 *
 * A table that does not exist is a refusal, not a failure: the error is
 * recorded against that table and the rest of the page carries on.
 */
async function readSeedTable(supabase: SupabaseClient, seed: SeedTable): Promise<SeedTableRead> {
  const columns = [seed.idColumn, ...seed.labelColumns];
  try {
    const { data, count, error } = await supabase
      .from(seed.table)
      .select(columns.join(', '), { count: 'exact' })
      .limit(5);
    if (error) return { table: seed.table, columns, rows: [], count: 0, error: error.message };
    return {
      table: seed.table,
      columns,
      rows: (data ?? []) as unknown as Record<string, unknown>[],
      count: count ?? 0,
      error: null,
    };
  } catch (e) {
    return {
      table: seed.table,
      columns,
      rows: [],
      count: 0,
      error: e instanceof Error ? e.message : 'The table could not be read.',
    };
  }
}

/* -------------------------------------------------------------- module 36 */

async function RbacCatalogueScreen({ supabase }: { supabase: SupabaseClient }) {
  const moduleRead = await readAccessModule(supabase);
  const [resources, permissions, grants] = await Promise.all([
    readAccessResources(supabase, moduleRead.row?.access_module_id ?? null),
    readPermissions(supabase),
    readRoleGrants(supabase),
  ]);

  const errors = [moduleRead.error, resources.error, permissions.error, grants.error].filter(
    (e): e is string => Boolean(e),
  );

  return (
    <RbacCatalogue
      module={moduleRead.row}
      resources={resources.rows}
      permissions={permissions.rows}
      grants={grants.rows}
      errors={errors}
    />
  );
}

async function readAccessModule(supabase: SupabaseClient): Promise<{ row: AccessModuleRow | null; error: string | null }> {
  try {
    const { data, error } = await supabase
      .from('access_module')
      .select('access_module_id, module_code, module_name, description, display_order')
      .eq('module_code', 'STAFF_PROFILE')
      .maybeSingle();
    if (error) return { row: null, error: error.message };
    return { row: (data as AccessModuleRow | null) ?? null, error: null };
  } catch (e) {
    return { row: null, error: e instanceof Error ? e.message : 'The access module could not be read.' };
  }
}

async function readAccessResources(
  supabase: SupabaseClient,
  moduleId: number | null,
): Promise<{ rows: AccessResourceRow[]; error: string | null }> {
  if (moduleId === null) return { rows: [], error: null };
  try {
    const { data, error } = await supabase
      .from('access_resource')
      .select('access_resource_id, resource_code, resource_name, description')
      .eq('access_module_id', moduleId)
      .order('resource_code', { ascending: true });
    if (error) return { rows: [], error: error.message };
    return { rows: (data ?? []) as AccessResourceRow[], error: null };
  } catch (e) {
    return { rows: [], error: e instanceof Error ? e.message : 'The access resources could not be read.' };
  }
}

async function readPermissions(supabase: SupabaseClient): Promise<{ rows: PermissionRow[]; error: string | null }> {
  try {
    const { data, error } = await supabase
      .from('permission')
      .select('permission_id, permission_code, permission_name, is_sensitive')
      .like('permission_code', 'STAFF_PROFILE.%')
      .order('permission_code', { ascending: true });
    if (error) return { rows: [], error: error.message };
    return { rows: (data ?? []) as PermissionRow[], error: null };
  } catch (e) {
    return { rows: [], error: e instanceof Error ? e.message : 'The permissions could not be read.' };
  }
}

/**
 * The roles that hold a staff-profile permission.
 *
 * The view's columns are discovered with a small query first, so the filter
 * uses the names the database actually has rather than an assumed set.
 */
async function readRoleGrants(supabase: SupabaseClient): Promise<{ rows: RoleGrant[]; error: string | null }> {
  try {
    const probe = await supabase.from('v_active_role_permission').select('*').limit(1);
    if (probe.error) return { rows: [], error: probe.error.message };

    const first = probe.data?.[0];
    if (!first) return { rows: [], error: null };

    const columns = Object.keys(first);
    const knowsCode = columns.includes('permission_code');
    const knowsRole = columns.includes('role_code');

    let query = supabase.from('v_active_role_permission').select('*');
    if (knowsCode) query = query.like('permission_code', 'STAFF_PROFILE.%');
    const { data, error } = await query.limit(5000);
    if (error) return { rows: [], error: error.message };

    const counts = new Map<string, number>();
    for (const row of (data ?? []) as Record<string, unknown>[]) {
      if (!knowsCode && !String(row.permission_code ?? '').startsWith('STAFF_PROFILE.')) continue;
      if (!knowsRole) continue;
      const role = String(row.role_code ?? '');
      if (!role) continue;
      counts.set(role, (counts.get(role) ?? 0) + 1);
    }

    const grants = [...counts.entries()]
      .map(([role_code, grants]) => ({ role_code, grants }))
      .sort((a, b) => b.grants - a.grants || a.role_code.localeCompare(b.role_code));
    return { rows: grants, error: null };
  } catch (e) {
    return { rows: [], error: e instanceof Error ? e.message : 'The role grants could not be read.' };
  }
}
