/**
 * Shared helpers for the database validation tools.
 *
 * `dumpCatalogue()` reads the catalogue of a live PGlite instance and returns
 * it in exactly the same shape as `tools/dump_catalogue.py` produces for the
 * remote Supabase project, so that `tools/compare_catalogue.py` can diff the
 * two without any conversion step.
 *
 * `applyMigrations()` creates a fresh embedded PostgreSQL, installs the
 * Supabase stub and applies every migration in sorted filename order.
 */
import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const ROOT = path.resolve(HERE, '../..');
export const MIGRATIONS = path.join(ROOT, 'supabase', 'migrations');
export const STUB = path.join(ROOT, 'tests', 'db', 'supabase-stub.ts');

const SCHEMAS = "('public','sims_private')";

/** The SQL of the Supabase stub, extracted the same way seed_counts.mjs does it. */
export function stubSql() {
  return fs.readFileSync(STUB, 'utf8').split('`')[1];
}

/** Every migration file, in the order the Supabase CLI applies them. */
export function migrationFiles() {
  return fs
    .readdirSync(MIGRATIONS)
    .filter((f) => f.endsWith('.sql'))
    .sort();
}

/**
 * Create a fresh PGlite, install the Supabase stub and apply every migration.
 * Returns the database and the list of applied files.
 */
export async function applyMigrations({ onFile } = {}) {
  const db = new PGlite({ extensions: { pgcrypto } });
  await db.exec(stubSql());
  const files = migrationFiles();
  for (const f of files) {
    if (onFile) onFile(f);
    await db.exec(fs.readFileSync(path.join(MIGRATIONS, f), 'utf8'));
  }
  return { db, files };
}

async function rows(db, sql) {
  const res = await db.query(sql);
  return res.rows;
}

/** Dump the catalogue of a PGlite database in the shape compare_catalogue.py expects. */
export async function dumpCatalogue(db) {
  const domains = await rows(db, `
    SELECT n.nspname AS schema, t.typname AS name,
           format_type(t.typbasetype, t.typtypmod) AS base_type,
           t.typnotnull AS not_null,
           pg_get_expr(d.adbin, d.adrelid) AS default_expr,
           t.typdefault AS typdefault
      FROM pg_type t
      JOIN pg_namespace n ON n.oid = t.typnamespace
      LEFT JOIN pg_attrdef d ON d.adrelid = t.typrelid AND d.adnum = 1
     WHERE t.typtype = 'd' AND n.nspname IN ${SCHEMAS}
     ORDER BY n.nspname, t.typname`);

  const domainChecks = await rows(db, `
    SELECT n.nspname AS schema, t.typname AS name, con.conname AS check_name,
           pg_get_constraintdef(con.oid, true) AS definition
      FROM pg_type t
      JOIN pg_namespace n ON n.oid = t.typnamespace
      JOIN pg_constraint con ON con.contypid = t.oid
     WHERE t.typtype = 'd' AND n.nspname IN ${SCHEMAS}
     ORDER BY n.nspname, t.typname, con.conname`);

  const enums = await rows(db, `
    SELECT n.nspname AS schema, t.typname AS name, e.enumlabel AS label
      FROM pg_type t
      JOIN pg_namespace n ON n.oid = t.typnamespace
      JOIN pg_enum e ON e.enumtypid = t.oid
     WHERE n.nspname IN ${SCHEMAS}
     ORDER BY n.nspname, t.typname, e.enumsortorder`);

  const composites = await rows(db, `
    SELECT n.nspname AS schema, t.typname AS name, a.attname AS attname,
           format_type(a.atttypid, a.atttypmod) AS type,
           a.attnotnull AS not_null,
           pg_get_expr(d.adbin, d.adrelid) AS default_expr,
           a.attnum AS position
      FROM pg_type t
      JOIN pg_namespace n ON n.oid = t.typnamespace
      JOIN pg_class c ON c.oid = t.typrelid
      JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
      LEFT JOIN pg_attrdef d ON d.adrelid = c.oid AND d.adnum = a.attnum
     WHERE t.typtype = 'c' AND n.nspname IN ${SCHEMAS}
     ORDER BY n.nspname, t.typname, a.attnum`);

  const sequences = await rows(db, `
    SELECT n.nspname AS schema, c.relname AS name,
           format_type(s.seqtypid, NULL) AS type,
           s.seqstart AS start, s.seqmin AS min,
           s.seqmax AS max, s.seqincrement AS increment, s.seqcycle AS cycle,
           s.seqcache AS cache,
           CASE WHEN d.refobjid IS NULL THEN NULL
                ELSE dn.nspname || '.' || dc.relname || '.' || da.attname END AS owned_by
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_sequence s ON s.seqrelid = c.oid
      LEFT JOIN pg_depend d ON d.classid = 'pg_class'::regclass AND d.objid = c.oid
                            AND d.refclassid = 'pg_class'::regclass
                            AND d.deptype IN ('a', 'i')
      LEFT JOIN pg_class dc ON dc.oid = d.refobjid
      LEFT JOIN pg_namespace dn ON dn.oid = dc.relnamespace
      LEFT JOIN pg_attribute da ON da.attrelid = d.refobjid AND da.attnum = d.refobjsubid
     WHERE n.nspname IN ${SCHEMAS} AND c.relkind = 'S'
     ORDER BY n.nspname, c.relname`);

  const columns = await rows(db, `
    SELECT n.nspname AS schema, c.relname AS table_name, a.attname AS name,
           format_type(a.atttypid, a.atttypmod) AS type,
           a.attnotnull AS not_null,
           pg_get_expr(d.adbin, d.adrelid) AS default_expr,
           a.attidentity AS identity,
           a.attgenerated AS generated,
           a.attnum AS position
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
      LEFT JOIN pg_attrdef d ON d.adrelid = c.oid AND d.adnum = a.attnum
     WHERE n.nspname IN ${SCHEMAS} AND c.relkind = 'r'
     ORDER BY n.nspname, c.relname, a.attnum`);

  const constraints = await rows(db, `
    SELECT n.nspname AS schema, c.relname AS table_name, con.conname AS name,
           con.contype AS type, pg_get_constraintdef(con.oid, true) AS definition
      FROM pg_constraint con
      JOIN pg_class c ON c.oid = con.conrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname IN ${SCHEMAS} AND c.relkind = 'r'
       -- PostgreSQL 18 records NOT NULL as a constraint; the live project runs
       -- PostgreSQL 17, where the same information only lives in pg_attribute.
       -- The flag is already part of every column, so the constraint is noise.
       AND con.contype <> 'n'
     ORDER BY n.nspname, c.relname, con.conname`);

  // Column level privileges.  The live project grants `authenticated` SELECT on
  // every column of 212 of the 213 public tables instead of granting SELECT on
  // the relation, so `SELECT *` is refused while `SELECT <column>` is allowed.
  const columnGrants = await rows(db, `
    SELECT n.nspname AS schema, c.relname AS table_name, a.attname AS name,
           CASE WHEN ae.grantee = 0 THEN 'PUBLIC' ELSE ae.grantee::regrole::text END AS grantee,
           ae.privilege_type AS privilege, ae.is_grantable AS grantable
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_attribute a ON a.attrelid = c.oid
      CROSS JOIN LATERAL aclexplode(a.attacl) ae
     WHERE n.nspname IN ${SCHEMAS} AND c.relkind = 'r'
     ORDER BY n.nspname, c.relname, a.attnum, ae.privilege_type, 4`);

  const rls = await rows(db, `
    SELECT n.nspname AS schema, c.relname AS table_name,
           c.relrowsecurity AS rls, c.relforcerowsecurity AS force_rls
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname IN ${SCHEMAS} AND c.relkind = 'r'`);

  const indexes = await rows(db, `
    SELECT n.nspname AS schema, c.relname AS name, t.relname AS table_name,
           pg_get_indexdef(i.indexrelid) AS definition
      FROM pg_index i
      JOIN pg_class c ON c.oid = i.indexrelid
      JOIN pg_class t ON t.oid = i.indrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname IN ${SCHEMAS} AND NOT i.indisprimary
     ORDER BY n.nspname, t.relname, c.relname`);

  const views = await rows(db, `
    SELECT n.nspname AS schema, c.relname AS name, c.relkind AS kind,
           pg_get_viewdef(c.oid, true) AS body, c.reloptions AS options
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname IN ${SCHEMAS} AND c.relkind IN ('v','m')
     ORDER BY n.nspname, c.relname`);

  const functions = await rows(db, `
    SELECT n.nspname AS schema, p.proname AS name,
           pg_get_function_identity_arguments(p.oid) AS args,
           pg_get_functiondef(p.oid) AS definition
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname IN ${SCHEMAS}
     ORDER BY n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)`);

  const triggers = await rows(db, `
    SELECT n.nspname AS schema, c.relname AS table_name, t.tgname AS name,
           pg_get_triggerdef(t.oid, true) AS definition
      FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname IN ${SCHEMAS} AND NOT t.tgisinternal
     ORDER BY n.nspname, c.relname, t.tgname`);

  const policies = await rows(db, `
    SELECT n.nspname AS schema, c.relname AS table_name, p.polname AS name,
           CASE p.polcmd WHEN 'r' THEN 'SELECT' WHEN 'a' THEN 'INSERT'
                         WHEN 'w' THEN 'UPDATE' WHEN 'd' THEN 'DELETE'
                         WHEN '*' THEN 'ALL' ELSE p.polcmd::text END AS command,
           p.polpermissive AS permissive,
           pg_get_expr(p.polqual, p.polrelid) AS using_expr,
           pg_get_expr(p.polwithcheck, p.polrelid) AS with_check,
           ARRAY(SELECT COALESCE(r.rolname, 'PUBLIC')
                   FROM unnest(p.polroles) g
                   LEFT JOIN pg_roles r ON r.oid = g) AS roles
      FROM pg_policy p
      JOIN pg_class c ON c.oid = p.polrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname IN ${SCHEMAS}
     ORDER BY n.nspname, c.relname, p.polname`);

  const grantRows = await rows(db, `
    SELECT n.nspname AS schema, c.relname AS object, COALESCE(r.rolname, 'PUBLIC') AS grantee,
           a.privilege_type AS privilege, a.is_grantable AS grantable
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      CROSS JOIN LATERAL aclexplode(c.relacl) a
      LEFT JOIN pg_roles r ON r.oid = a.grantee
     WHERE n.nspname IN ${SCHEMAS} AND c.relkind IN ('r','v','m','S','p','f')`);
  const fnGrants = await rows(db, `
    SELECT n.nspname AS schema,
           p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS object,
           COALESCE(r.rolname, 'PUBLIC') AS grantee,
           a.privilege_type AS privilege, a.is_grantable AS grantable
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      CROSS JOIN LATERAL aclexplode(p.proacl) a
      LEFT JOIN pg_roles r ON r.oid = a.grantee
     WHERE n.nspname IN ${SCHEMAS}`);
  const schemaGrants = await rows(db, `
    SELECT n.nspname AS schema, n.nspname AS object, COALESCE(r.rolname, 'PUBLIC') AS grantee,
           a.privilege_type AS privilege, a.is_grantable AS grantable
      FROM pg_namespace n
      CROSS JOIN LATERAL aclexplode(n.nspacl) a
      LEFT JOIN pg_roles r ON r.oid = a.grantee
     WHERE n.nspname IN ${SCHEMAS}`);

  const typeGrants = await rows(db, `
    SELECT n.nspname AS schema, t.typname AS object, COALESCE(r.rolname, 'PUBLIC') AS grantee,
           a.privilege_type AS privilege, a.is_grantable AS grantable
      FROM pg_type t
      JOIN pg_namespace n ON n.oid = t.typnamespace
      CROSS JOIN LATERAL aclexplode(t.typacl) a
      LEFT JOIN pg_roles r ON r.oid = a.grantee
     WHERE n.nspname IN ${SCHEMAS} AND t.typtype IN ('d', 'e', 'c')`);

  const tableNames = [...new Set(columns.map((c) => `${c.schema}.${c.table_name}`))].sort();
  const rowCounts = {};
  for (const key of tableNames) {
    const [schema, table] = key.split('.');
    const res = await db.query(`SELECT count(*)::int AS n FROM "${schema}"."${table}"`);
    rowCounts[key] = res.rows[0].n;
  }

  const tableMap = new Map();
  for (const c of columns) {
    const key = `${c.schema}.${c.table_name}`;
    if (!tableMap.has(key)) {
      tableMap.set(key, {
        schema: c.schema,
        name: c.table_name,
        rls: false,
        force_rls: false,
        columns: [],
        constraints: [],
      });
    }
    tableMap.get(key).columns.push({
      name: c.name,
      type: c.type,
      not_null: c.not_null,
      default: c.default_expr,
      identity: c.identity,
      generated: c.generated,
      position: c.position,
      privileges: [],
    });
  }
  for (const g of columnGrants) {
    const key = `${g.schema}.${g.table_name}`;
    const table = tableMap.get(key);
    if (!table) continue;
    const col = table.columns.find((c) => c.name === g.name);
    if (!col) continue;
    col.privileges.push({ grantee: g.grantee, privilege: g.privilege, grantable: g.grantable });
  }
  for (const c of constraints) {
    const key = `${c.schema}.${c.table_name}`;
    if (!tableMap.has(key)) continue;
    tableMap.get(key).constraints.push({
      name: c.name,
      type: c.type,
      definition: c.definition,
    });
  }
  for (const r of rls) {
    const key = `${r.schema}.${r.table_name}`;
    if (!tableMap.has(key)) continue;
    tableMap.get(key).rls = r.rls;
    tableMap.get(key).force_rls = r.force_rls;
  }

  const tables = [...tableMap.values()].sort((a, b) =>
    a.schema === b.schema ? a.name.localeCompare(b.name) : a.schema.localeCompare(b.schema),
  );

  const enumMap = new Map();
  for (const e of enums) {
    const key = `${e.schema}.${e.name}`;
    if (!enumMap.has(key)) enumMap.set(key, { schema: e.schema, name: e.name, labels: [] });
    enumMap.get(key).labels.push(e.label);
  }

  const compositeMap = new Map();
  for (const c of composites) {
    const key = `${c.schema}.${c.name}`;
    if (!compositeMap.has(key)) compositeMap.set(key, { schema: c.schema, name: c.name, attributes: [] });
    compositeMap.get(key).attributes.push({
      name: c.attname,
      type: c.type,
      not_null: c.not_null,
      default: c.default_expr,
      position: c.position,
    });
  }

  const checkMap = new Map();
  for (const c of domainChecks) {
    const key = `${c.schema}.${c.name}`;
    if (!checkMap.has(key)) checkMap.set(key, []);
    checkMap.get(key).push({ name: c.check_name, definition: c.definition });
  }

  const catalogue = {
    source: 'local',
    server_version: (await db.query('SHOW server_version')).rows[0].server_version,
    schemas: ['public', 'sims_private'],
    domains: domains.map((d) => {
      const key = `${d.schema}.${d.name}`;
      const checks = checkMap.get(key) || [];
      return {
        schema: d.schema,
        name: d.name,
        base_type: d.base_type,
        not_null: d.not_null,
        default: d.default_expr,
        typdefault: d.typdefault,
        check: checks.length ? checks[0].definition : null,
        check_name: checks.length ? checks[0].name : null,
        checks,
      };
    }),
    enums: [...enumMap.values()],
    composites: [...compositeMap.values()],
    sequences: sequences.map((s) => ({
      schema: s.schema,
      name: s.name,
      type: s.type,
      start: s.start,
      min: s.min,
      max: s.max,
      increment: s.increment,
      cycle: s.cycle,
      cache: s.cache,
      owned_by: s.owned_by,
    })),
    tables,
    indexes: indexes.map((i) => ({
      schema: i.schema,
      name: i.name,
      table: i.table_name,
      definition: i.definition,
    })),
    views: views.map((v) => ({
      schema: v.schema,
      name: v.name,
      kind: v.kind,
      body: v.body,
      options: v.options,
    })),
    functions: functions.map((f) => ({
      schema: f.schema,
      name: f.name,
      args: f.args,
      definition: f.definition,
    })),
    triggers: triggers.map((t) => ({
      schema: t.schema,
      table: t.table_name,
      name: t.name,
      definition: t.definition,
    })),
    policies: policies.map((p) => ({
      schema: p.schema,
      table: p.table_name,
      name: p.name,
      command: p.command,
      permissive: p.permissive,
      using: p.using_expr,
      with_check: p.with_check,
      roles: p.roles,
    })),
    grants: [...grantRows, ...fnGrants, ...schemaGrants, ...typeGrants]
      .map((g) => ({
        schema: g.schema,
        object: g.object,
        grantee: g.grantee,
        privilege: g.privilege,
        grantable: g.grantable,
      }))
      .sort(
        (a, b) =>
          a.schema.localeCompare(b.schema) ||
          a.object.localeCompare(b.object) ||
          a.grantee.localeCompare(b.grantee) ||
          a.privilege.localeCompare(b.privilege),
      ),
    row_counts: rowCounts,
  };

  catalogue.counts = {
    tables: catalogue.tables.length,
    views: catalogue.views.length,
    functions: catalogue.functions.length,
    triggers: catalogue.triggers.length,
    policies: catalogue.policies.length,
    rls_tables: catalogue.tables.filter((t) => t.rls).length,
    indexes: catalogue.indexes.length,
    sequences: catalogue.sequences.length,
    domains: catalogue.domains.length,
    enums: catalogue.enums.length,
    composites: catalogue.composites.length,
    grants: catalogue.grants.length,
  };

  return catalogue;
}
