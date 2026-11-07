/**
 * Role and permission matrix.
 *
 *   node tools/validate/role_matrix.mjs [--check] [--out PATH]
 *                                      [--source auto|live|rebuilt] [--json]
 *
 * Reads the RBAC tables (`role`, `role_permission`, `permission`,
 * `access_resource`, `access_module`, `access_action` and
 * `user_role_assignment`) and renders `docs/ROLE_PERMISSION_MATRIX.md` from
 * them.
 *
 * The data comes from the live Supabase project (`--source live`, the session
 * is switched to read-only) or from the migration set applied to a fresh
 * embedded PostgreSQL (`--source rebuilt`).  `--source auto` (the default)
 * asks the database first and falls back to the rebuilt database when the
 * project cannot be reached, so the tool also works offline.
 *
 * The document lists the scope types a role can be assigned at (global,
 * institution, campus, department, programme, self), the roles themselves and
 * the actions every role is granted in every access module.
 *
 * `--check` does not write: it renders the document in memory and compares it
 * with the file on disk, exiting non-zero when the two differ.  That makes the
 * document a build artefact that cannot silently drift away from the schema.
 */
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { applyMigrations, ROOT } from './pg_catalogue.mjs';
import { connectLive } from './catalogue.mjs';

const DEFAULT_OUT = path.join(ROOT, 'docs', 'ROLE_PERMISSION_MATRIX.md');

/**
 * The eight actions a matrix cell can show.  PUBLISH, ASSIGN, IMPERSONATE and
 * DOWNLOAD exist in `access_action` but are not part of the documented grant
 * vocabulary, so they are left out of the cells.
 */
const CELL_ACTIONS = [
  ['CREATE', 'C'],
  ['READ', 'R'],
  ['UPDATE', 'U'],
  ['DELETE', 'D'],
  ['APPROVE', 'A'],
  ['VERIFY', 'V'],
  ['EXPORT', 'E'],
  ['CONFIGURE', 'G'],
];

/** Roles that are technical rather than business roles. */
const TECHNICAL_ROLES = new Set(['DATABASE_ADMIN']);

const CATEGORY_ORDER = [
  'ACADEMIC',
  'ADMINISTRATIVE',
  'AUDIT',
  'FACULTY',
  'GOVERNANCE',
  'PARENT',
  'STUDENT',
  'SYSTEM',
];

/** What a scope type means, and in which order the scopes are listed. */
const SCOPES = [
  ['GLOBAL', 'the whole installation'],
  ['INSTITUTION', 'one institution'],
  ['CAMPUS', 'one campus'],
  ['DEPARTMENT', 'one department'],
  ['PROGRAMME', 'one programme'],
  ['SELF', 'the user itself'],
];

/** The usage text of the tool. */
const USAGE = `Usage: node tools/validate/role_matrix.mjs [options]

  --check             do not write, exit non-zero when the document is stale
  --out PATH          write the document somewhere else
  --source SOURCE     auto (default), live or rebuilt
  --json              machine readable report
  --help              this text
`;

/** Read the RBAC tables out of a database. */
async function readRbac(query) {
  const run = async (sql) => (await query(sql)).rows;
  const roles = await run(
    'SELECT role_id, role_code, role_name, role_category, role_level, ' +
      'is_active, is_assignable, is_system_role FROM public.role ORDER BY role_id',
  );
  const rolePermissions = await run(
    'SELECT role_id, permission_id, permission_effect FROM public.role_permission',
  );
  const permissions = await run(
    'SELECT permission_id, access_resource_id, access_action_id, permission_code, ' +
      'is_active, is_sensitive FROM public.permission',
  );
  const resources = await run(
    'SELECT access_resource_id, access_module_id, resource_code, is_active ' +
      'FROM public.access_resource',
  );
  const modules = await run(
    'SELECT access_module_id, module_code, module_name, is_active FROM public.access_module',
  );
  const actions = await run(
    'SELECT access_action_id, action_code, action_name, is_active FROM public.access_action',
  );
  const assignments = await run(
    'SELECT role_id, scope_type, assignment_status FROM public.user_role_assignment',
  );
  return { roles, rolePermissions, permissions, resources, modules, actions, assignments };
}

/**
 * Turn the raw RBAC rows into
 *   role code -> module code -> Set(action code)
 * only counting grants that are actually in force: an ALLOW effect on an
 * active permission, on an active resource, for an active action.
 */
function buildCells(rbac) {
  const permissionById = new Map(rbac.permissions.map((p) => [p.permission_id, p]));
  const resourceById = new Map(rbac.resources.map((r) => [r.access_resource_id, r]));
  const moduleById = new Map(rbac.modules.map((m) => [m.access_module_id, m]));
  const actionById = new Map(rbac.actions.map((a) => [a.access_action_id, a]));

  const cells = new Map();
  const grants = new Map();
  for (const grant of rbac.rolePermissions) {
    if (grant.permission_effect !== 'ALLOW') continue;
    const permission = permissionById.get(grant.permission_id);
    if (!permission || !permission.is_active) continue;
    const resource = resourceById.get(permission.access_resource_id);
    if (!resource || !resource.is_active) continue;
    const action = actionById.get(permission.access_action_id);
    if (!action || !action.is_active) continue;
    const module = moduleById.get(resource.access_module_id);
    if (!module) continue;
    if (!cells.has(grant.role_id)) cells.set(grant.role_id, new Map());
    const byModule = cells.get(grant.role_id);
    if (!byModule.has(module.module_code)) byModule.set(module.module_code, new Set());
    byModule.get(module.module_code).add(action.action_code);
    grants.set(grant.role_id, (grants.get(grant.role_id) || 0) + 1);
  }
  return { cells, grants };
}

/** The documented cell letters, in the order they are printed. */
function cellText(actions) {
  if (!actions || actions.size === 0) return '';
  return CELL_ACTIONS.filter(([code]) => actions.has(code))
    .map(([, letter]) => letter)
    .join('');
}

/** Roles in the order the document lists them: by category, then by code. */
function orderedRoles(roles) {
  return [...roles].sort((a, b) => {
    const ca = CATEGORY_ORDER.indexOf(a.role_category);
    const cb = CATEGORY_ORDER.indexOf(b.role_category);
    const ka = ca === -1 ? CATEGORY_ORDER.length : ca;
    const kb = cb === -1 ? CATEGORY_ORDER.length : cb;
    if (ka !== kb) return ka - kb;
    if (a.role_code !== b.role_code) return a.role_code < b.role_code ? -1 : 1;
    return a.role_id - b.role_id;
  });
}

/** The modules the document shows, alphabetically. */
function moduleCodes(modules) {
  return [...new Set(modules.map((m) => m.module_code))].sort();
}

/**
 * The per-resource breakdown of the FEES module.  FEES has no `ALL` resource,
 * so the matrix cell alone cannot tell which fee resource a role may touch.
 */
function feesRows(rbac) {
  const permissionById = new Map(rbac.permissions.map((p) => [p.permission_id, p]));
  const resourceById = new Map(rbac.resources.map((r) => [r.access_resource_id, r]));
  const moduleById = new Map(rbac.modules.map((m) => [m.access_module_id, m]));
  const actionById = new Map(rbac.actions.map((a) => [a.access_action_id, a]));

  const feesModule = rbac.modules.find((m) => m.module_code === 'FEES');
  if (!feesModule) return [];

  const byRole = new Map();
  for (const grant of rbac.rolePermissions) {
    if (grant.permission_effect !== 'ALLOW') continue;
    const permission = permissionById.get(grant.permission_id);
    if (!permission || !permission.is_active) continue;
    const resource = resourceById.get(permission.access_resource_id);
    if (!resource || !resource.is_active) continue;
    if (resource.access_module_id !== feesModule.access_module_id) continue;
    const action = actionById.get(permission.access_action_id);
    if (!action || !action.is_active) continue;
    if (!byRole.has(grant.role_id)) byRole.set(grant.role_id, new Map());
    const byResource = byRole.get(grant.role_id);
    if (!byResource.has(resource.resource_code)) byResource.set(resource.resource_code, new Set());
    byResource.get(resource.resource_code).add(action.action_code);
  }

  const out = [];
  for (const role of orderedRoles(rbac.roles)) {
    const byResource = byRole.get(role.role_id);
    if (!byResource) continue;
    for (const resourceCode of [...byResource.keys()].sort()) {
      out.push({
        role: role.role_code,
        resource: resourceCode,
        actions: cellText(byResource.get(resourceCode)),
      });
    }
  }
  return out;
}

/** Render the whole document. */
export function render(rbac, source) {
  const { cells, grants } = buildCells(rbac);
  const roles = orderedRoles(rbac.roles);
  const modules = moduleCodes(rbac.modules);
  const lines = [];

  lines.push('# Role and permission matrix');
  lines.push('');
  lines.push(
    `Generated by \`node tools/validate/role_matrix.mjs\` from the ${source} database. ` +
      'Do not edit by hand.',
  );
  lines.push('');
  lines.push(
    'A cell lists the actions the role is granted anywhere in that access module: ' +
      '**C**reate, **R**ead, **U**pdate, **D**elete, **A**pprove, **V**erify, **E**xport, ' +
      'confi**G**ure. A grant applies at the scope of the user\'s role assignment ' +
      '(self, programme, department, campus, institution or global); some resources ' +
      'inside a module (for example `FEES.FEE_REFUND`) are granted separately, see the ' +
      'per-role list in the database. Sensitive resources need their specific grant: ' +
      '`ALL` is not enough.',
  );
  lines.push('');

  // --- scope types ---------------------------------------------------------
  lines.push('## Scope types');
  lines.push('');
  lines.push(
    'A role is assigned at one scope type.  The scope of the assignment decides how ' +
      'far a grant reaches.',
  );
  lines.push('');
  lines.push('| Scope | Meaning | Roles | Active assignments |');
  lines.push('|---|---|---|---|');
  for (const [scope, meaning] of SCOPES) {
    const roleCount = rbac.roles.filter((r) => r.role_level === scope).length;
    const assignmentCount = rbac.assignments.filter(
      (a) => a.scope_type === scope && a.assignment_status === 'ACTIVE',
    ).length;
    lines.push(`| \`${scope}\` | ${meaning} | ${roleCount} | ${assignmentCount} |`);
  }
  lines.push('');

  // --- roles ----------------------------------------------------------------
  lines.push('## Roles');
  lines.push('');
  lines.push('| Role | Scope | Category | Modules | Permissions |');
  lines.push('|---|---|---|---|---|');
  for (const role of roles) {
    const byModule = cells.get(role.role_id) || new Map();
    let moduleCount = 0;
    for (const actions of byModule.values()) {
      if (CELL_ACTIONS.some(([code]) => actions.has(code))) moduleCount += 1;
    }
    const count = TECHNICAL_ROLES.has(role.role_code)
      ? 'none (technical role)'
      : String(moduleCount);
    lines.push(
      `| \`${role.role_code}\` | ${role.role_level} | ${role.role_category} | ` +
        `${count} | ${grants.get(role.role_id) || 0} |`,
    );
  }
  lines.push('');

  // --- matrix ---------------------------------------------------------------
  lines.push('## Matrix');
  lines.push('');
  lines.push(`| Role | ${modules.join(' | ')} |`);
  lines.push(`|---|${modules.map(() => '---').join('|')}|`);
  for (const role of roles) {
    const byModule = cells.get(role.role_id) || new Map();
    const row = modules.map((m) => cellText(byModule.get(m)));
    lines.push(`| \`${role.role_code}\` | ${row.join(' | ')} |`);
  }
  lines.push('');

  // --- fees -----------------------------------------------------------------
  lines.push('## Fees in detail');
  lines.push('');
  lines.push('| Role | Resource | Actions |');
  lines.push('|---|---|---|');
  for (const row of feesRows(rbac)) {
    lines.push(`| \`${row.role}\` | \`${row.resource}\` | ${row.actions} |`);
  }
  lines.push('');
  lines.push(
    'Not in the matrix because they are decided by identity, not by a grant: a student ' +
      'or employee acting on their own record (profile, documents, grievances, feedback, ' +
      'HR records, activities).',
  );
  lines.push('');
  return lines.join('\n');
}

/** Read the RBAC tables from the live project (read-only). */
async function readLive() {
  const client = await connectLive();
  try {
    return { rbac: await readRbac((sql) => client.query(sql)), source: 'live' };
  } finally {
    await client.end();
  }
}

/** Read the RBAC tables from the migration set applied to a fresh database. */
async function readRebuilt() {
  const { db } = await applyMigrations();
  try {
    return { rbac: await readRbac((sql) => db.query(sql)), source: 'rebuilt' };
  } finally {
    await db.close();
  }
}

async function main() {
  const args = process.argv.slice(2);
  if (args.includes('--help') || args.includes('-h')) {
    console.log(USAGE);
    process.exit(0);
  }
  const asJson = args.includes('--json');
  const check = args.includes('--check');
  const outIndex = args.indexOf('--out');
  const out = outIndex === -1 ? DEFAULT_OUT : path.resolve(ROOT, args[outIndex + 1]);
  const sourceIndex = args.indexOf('--source');
  const source = sourceIndex === -1 ? 'auto' : args[sourceIndex + 1];
  if (!['auto', 'live', 'rebuilt'].includes(source)) {
    console.error(`unknown --source ${source} (expected auto, live or rebuilt)`);
    process.exit(2);
  }

  let loaded;
  if (source === 'rebuilt') {
    loaded = await readRebuilt();
  } else if (source === 'live') {
    loaded = await readLive();
  } else {
    try {
      loaded = await readLive();
    } catch (err) {
      console.error(`the live project is not reachable (${err.message}), using the rebuilt database`);
      loaded = await readRebuilt();
    }
  }

  const text = render(loaded.rbac, loaded.source);
  const existing = fs.existsSync(out) ? fs.readFileSync(out, 'utf8') : null;
  const unchanged = existing === text;

  if (asJson) {
    console.log(
      JSON.stringify(
        {
          output: out,
          source: loaded.source,
          unchanged,
          roles: loaded.rbac.roles.length,
          grants: loaded.rbac.rolePermissions.length,
        },
        null,
        1,
      ),
    );
    process.exit(unchanged ? 0 : 1);
  }

  if (check) {
    if (unchanged) {
      console.log(`OK - ${path.relative(ROOT, out)} is up to date (source: ${loaded.source})`);
      process.exit(0);
    }
    console.error(`DIFF - ${path.relative(ROOT, out)} is out of date (source: ${loaded.source})`);
    if (existing === null) {
      console.error('the file does not exist');
    } else {
      const a = existing.split('\n');
      const b = text.split('\n');
      let shown = 0;
      for (let i = 0; i < Math.max(a.length, b.length) && shown < 20; i++) {
        if (a[i] !== b[i]) {
          console.error(`  line ${i + 1}: on disk ${JSON.stringify(a[i] ?? null)}`);
          console.error(`           rendered ${JSON.stringify(b[i] ?? null)}`);
          shown += 1;
        }
      }
    }
    process.exit(1);
  }

  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, text, 'utf8');
  console.log(
    `wrote ${path.relative(ROOT, out)} (${fs.statSync(out).size} bytes, source: ${loaded.source})`,
  );
  console.log(
    `${loaded.rbac.roles.length} roles, ${loaded.rbac.rolePermissions.length} role grants, ` +
      `${loaded.rbac.modules.length} access modules`,
  );
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
