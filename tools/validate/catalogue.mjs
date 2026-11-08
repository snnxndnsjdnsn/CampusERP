/**
 * Dump the live Supabase catalogue to JSON.
 *
 *   node tools/validate/catalogue.mjs [--out PATH] [--check] [--source live|rebuilt] [--json]
 *
 * The dump is the authoritative input for `tools/build_migrations.py` and
 * `tools/build_rls.py`: the project's `supabase/migrations/` directory was lost
 * and has to be reconstructed so that applying it to a fresh database
 * reproduces the live catalogue exactly.
 *
 * The JSON document has exactly the shape `tools/dump_catalogue.py` produces
 * (top level keys `source`, `server_version`, `schemas`, `domains`, `enums`,
 * `composites`, `sequences`, `tables`, `indexes`, `views`, `functions`,
 * `triggers`, `policies`, `grants`, `row_counts`, `counts`), so the two dumps
 * can be compared byte for byte.
 *
 * The connection is ALWAYS read-only: the session is switched to
 * `default_transaction_read_only = on` before the first query, so the script
 * cannot write to the remote project even by accident.
 *
 * `--out PATH` writes the dump somewhere else (the default is
 * `tools/catalogue/live_catalogue.json`).
 *
 * `--check` does not write: it dumps the catalogue, compares it with the file
 * on disk and exits non-zero when the two differ.  That makes the committed
 * catalogue a build artefact that cannot silently drift away from the
 * database.
 *
 * `--source rebuilt` applies the migration set to a fresh embedded PostgreSQL
 * (PGlite) and dumps that instead of the remote project; it is handy to see
 * what the migrations produce without touching the live database.
 */
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import pg from 'pg';
import { applyMigrations, dumpCatalogue, ACTIVITY_TABLES, ROOT } from './pg_catalogue.mjs';

export const DEFAULT_OUT = path.join(ROOT, 'tools', 'catalogue', 'live_catalogue.json');

/**
 * The dump of the rebuilt database.
 *
 * The live catalogue is the input of `tools/build_migrations.py`, so it must
 * never be overwritten by a dump of the rebuilt database.  `--source rebuilt`
 * therefore writes here unless `--out` says otherwise.
 */
export const REBUILT_OUT = path.join(ROOT, 'tools', 'catalogue', 'local_catalogue.json');
export const SCHEMAS = ['public', 'sims_private'];

/** The usage text of the tool. */
const USAGE = `Usage: node tools/validate/catalogue.mjs [options]

  --out PATH          write the dump somewhere else
  --check             do not write, exit non-zero when the dump is stale
  --source SOURCE     live (default) or rebuilt
  --json              machine readable report
  --help              this text
`;

const DEFAULTS = {
  host: 'aws-0-ap-southeast-1.pooler.supabase.com',
  port: 5432,
  database: 'postgres',
  user: 'postgres.khqqfgqvwdxlqkncwtmh',
  password: '',
  sslmode: 'require',
};

/** Connection settings: SUPABASE_DB_* wins over SIMS_DB_*, then the defaults. */
export function connectionOptions() {
  const env = process.env;
  const pick = (name, fallback) => {
    const supabase = env[`SUPABASE_DB_${name}`];
    const sims = env[`SIMS_DB_${name}`];
    if (supabase !== undefined && supabase !== '') return supabase;
    if (sims !== undefined && sims !== '') return sims;
    return fallback;
  };
  return {
    host: pick('HOST', DEFAULTS.host),
    port: Number(pick('PORT', DEFAULTS.port)),
    database: pick('NAME', DEFAULTS.database),
    user: pick('USER', DEFAULTS.user),
    password: pick('PASSWORD', DEFAULTS.password),
    sslmode: pick('SSLMODE', DEFAULTS.sslmode),
  };
}

/**
 * A number that must be written out with its exact digits.
 *
 * `pg` returns `bigint` columns as strings (that is the only lossless way to
 * carry a 64 bit counter through JSON), and JSON.stringify() would round
 * 9223372036854775807 to 9223372036854775808.  The marker keeps the exact
 * text so that the Node dump and the Python dump are byte identical.
 */
class RawNumber {
  constructor(text) {
    this.text = String(text);
  }
}

/** Wrap a numeric string so that it is serialised as a JSON number. */
function raw(value) {
  if (value === null || value === undefined) return null;
  if (typeof value === 'number') return new RawNumber(String(value));
  if (typeof value === 'bigint') return new RawNumber(value.toString());
  const text = String(value);
  if (!/^-?\d+$/.test(text)) return value;
  return new RawNumber(text);
}

/**
 * Serialise like python's `json.dumps(obj, indent=1, sort_keys=False)`.
 *
 * The differences to `JSON.stringify` that matter here: non-ASCII characters
 * are escaped (`ensure_ascii=True`) and 64 bit integers keep their exact
 * digits.
 */
export function toJson(value, indent = 1) {
  const pad = ' '.repeat(indent);
  const write = (node, depth) => {
    if (node === null || node === undefined) return 'null';
    if (node instanceof RawNumber) return node.text;
    if (typeof node === 'bigint') return node.toString();
    if (typeof node === 'number') {
      if (Number.isFinite(node)) return JSON.stringify(node);
      return 'null';
    }
    if (typeof node === 'boolean') return node ? 'true' : 'false';
    if (typeof node === 'string') return quote(node);
    if (Array.isArray(node)) {
      if (!node.length) return '[]';
      const inner = pad.repeat(depth + 1);
      const body = node.map((item) => inner + write(item, depth + 1)).join(',\n');
      return `[\n${body}\n${pad.repeat(depth)}]`;
    }
    if (typeof node === 'object') {
      const keys = Object.keys(node);
      if (!keys.length) return '{}';
      const inner = pad.repeat(depth + 1);
      const body = keys
        .map((key) => `${inner}${quote(key)}: ${write(node[key], depth + 1)}`)
        .join(',\n');
      return `{\n${body}\n${pad.repeat(depth)}}`;
    }
    return 'null';
  };
  return write(value, 0);
}

/** Escape a string the way python's json module does with ensure_ascii=True. */
function quote(text) {
  let out = '"';
  for (const ch of text) {
    const code = ch.codePointAt(0);
    if (ch === '"') out += '\\"';
    else if (ch === '\\') out += '\\\\';
    else if (ch === '\n') out += '\\n';
    else if (ch === '\r') out += '\\r';
    else if (ch === '\t') out += '\\t';
    else if (ch === '\b') out += '\\b';
    else if (ch === '\f') out += '\\f';
    else if (code < 0x20 || code > 0x7e) {
      if (code > 0xffff) {
        const high = Math.floor((code - 0x10000) / 0x400) + 0xd800;
        const low = ((code - 0x10000) % 0x400) + 0xdc00;
        out += `\\u${hex4(high)}\\u${hex4(low)}`;
      } else {
        out += `\\u${hex4(code)}`;
      }
    } else out += ch;
  }
  return out + '"';
}

function hex4(code) {
  return code.toString(16).padStart(4, '0');
}

/** python's tuple sort: byte order, not locale order. */
function byKey(a, b) {
  if (a === b) return 0;
  return a < b ? -1 : 1;
}

/**
 * The migration tracker is the applier's own bookkeeping, not application
 * schema. It is left out of the catalogue and of the schema document, so that
 * running `tools/apply_migrations.py` does not change the contract the project
 * is measured against.
 */
const TRACKING_SCHEMA = 'sims_private';
const TRACKING_TABLE = 'schema_migration';

/** True for the tracker table and for everything that belongs to it. */
function isTrackingObject(name) {
  return name === TRACKING_TABLE || name.startsWith(`${TRACKING_TABLE}_`);
}

/** Remove the migration tracker and its satellites from a catalogue. */
export function stripTracking(catalogue) {
  catalogue.tables = catalogue.tables.filter(
    (t) => !(t.schema === TRACKING_SCHEMA && isTrackingObject(t.name)),
  );
  catalogue.indexes = catalogue.indexes.filter(
    (i) => !(i.schema === TRACKING_SCHEMA && isTrackingObject(i.table)),
  );
  catalogue.sequences = catalogue.sequences.filter(
    (s) => !(s.schema === TRACKING_SCHEMA && isTrackingObject(s.name)),
  );
  catalogue.composites = catalogue.composites.filter(
    (c) => !(c.schema === TRACKING_SCHEMA && isTrackingObject(c.name)),
  );
  catalogue.grants = catalogue.grants.filter(
    (g) => !(g.schema === TRACKING_SCHEMA && isTrackingObject(g.object)),
  );
  delete catalogue.row_counts[`${TRACKING_SCHEMA}.${TRACKING_TABLE}`];
  return catalogue;
}

/** Connect to the remote project and switch the session to read-only. */
export async function connectLive() {
  const options = connectionOptions();
  if (!options.password) {
    throw new Error(
      'SUPABASE_DB_PASSWORD is not set (or SIMS_DB_PASSWORD). The password is ' +
        'never stored in the repository - put it into .env.local.',
    );
  }
  const client = new pg.Client({
    host: options.host,
    port: options.port,
    database: options.database,
    user: options.user,
    password: options.password,
    ssl: options.sslmode === 'disable' ? false : { rejectUnauthorized: false },
    application_name: 'sims_catalogue_dump',
  });
  await client.connect();
  await client.query('SET default_transaction_read_only = on');
  await client.query("SET statement_timeout = '120s'");
  return client;
}

/** Run a query and return its rows. */
async function rows(client, sql, params) {
  const res = await client.query(sql, params);
  return res.rows;
}

/**
 * Dump the catalogue of the connected database in the shape
 * `tools/dump_catalogue.py` produces.
 */
export async function dumpLiveCatalogue(client) {
  const schemas = SCHEMAS;
  const schemaList = `('${schemas.join("','")}')`;

  const domains = await rows(
    client,
    `
    SELECT n.nspname AS schema, t.typname AS name,
           format_type(t.typbasetype, t.typtypmod) AS base_type,
           t.typnotnull AS not_null,
           pg_get_expr(d.adbin, d.adrelid) AS default_expr,
           t.typdefault AS typdefault
      FROM pg_type t
      JOIN pg_namespace n ON n.oid = t.typnamespace
      LEFT JOIN pg_attrdef d ON d.adrelid = t.typrelid AND d.adnum = 1
     WHERE t.typtype = 'd' AND n.nspname IN ('public', 'sims_private')
     ORDER BY n.nspname, t.typname`,
  );
  const domainChecks = await rows(
    client,
    `
    SELECT n.nspname AS schema, t.typname AS name, con.conname AS check_name,
           pg_get_constraintdef(con.oid, true) AS definition
      FROM pg_type t
      JOIN pg_namespace n ON n.oid = t.typnamespace
      JOIN pg_constraint con ON con.contypid = t.oid
     WHERE t.typtype = 'd' AND n.nspname IN ('public', 'sims_private')
     ORDER BY n.nspname, t.typname, con.conname`,
  );

  const enumRows = await rows(
    client,
    `
    SELECT n.nspname AS schema, t.typname AS name, e.enumlabel AS label
      FROM pg_type t
      JOIN pg_namespace n ON n.oid = t.typnamespace
      JOIN pg_enum e ON e.enumtypid = t.oid
     WHERE n.nspname IN ('public', 'sims_private')
     ORDER BY n.nspname, t.typname, e.enumsortorder`,
  );

  const compositeRows = await rows(
    client,
    `
    SELECT n.nspname AS schema, t.typname AS name, a.attname AS attname,
           format_type(a.atttypid, a.atttypmod) AS att_type,
           a.attnotnull AS not_null,
           pg_get_expr(d.adbin, d.adrelid) AS default_expr,
           a.attnum AS position
      FROM pg_type t
      JOIN pg_namespace n ON n.oid = t.typnamespace
      JOIN pg_class c ON c.oid = t.typrelid
      JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
      LEFT JOIN pg_attrdef d ON d.adrelid = c.oid AND d.adnum = a.attnum
     WHERE t.typtype = 'c' AND n.nspname IN ('public', 'sims_private')
     ORDER BY n.nspname, t.typname, a.attnum`,
  );

  const sequenceRows = await rows(
    client,
    `
    SELECT n.nspname AS schema, c.relname AS name, format_type(s.seqtypid, NULL) AS seq_type,
           s.seqstart AS start, s.seqmin AS min, s.seqmax AS max, s.seqincrement AS increment,
           s.seqcycle AS cycle, s.seqcache AS cache,
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
     WHERE n.nspname IN ('public', 'sims_private') AND c.relkind = 'S'
     ORDER BY n.nspname, c.relname`,
  );

  const columnRows = await rows(
    client,
    `
    SELECT n.nspname AS schema, c.relname AS table_name, a.attname AS name,
           format_type(a.atttypid, a.atttypmod) AS col_type,
           a.attnotnull AS not_null,
           pg_get_expr(d.adbin, d.adrelid) AS default_expr,
           a.attidentity AS identity,
           a.attgenerated AS generated,
           a.attnum AS position
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
      LEFT JOIN pg_attrdef d ON d.adrelid = c.oid AND d.adnum = a.attnum
     WHERE n.nspname IN ('public', 'sims_private') AND c.relkind = 'r'
     ORDER BY n.nspname, c.relname, a.attnum`,
  );

  const constraintRows = await rows(
    client,
    `
    SELECT n.nspname AS schema, c.relname AS table_name, con.conname AS name,
           con.contype AS type, pg_get_constraintdef(con.oid, true) AS definition
      FROM pg_constraint con
      JOIN pg_class c ON c.oid = con.conrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname IN ('public', 'sims_private') AND c.relkind = 'r'
     ORDER BY n.nspname, c.relname, con.conname`,
  );

  // Column level privileges.  The live project grants `authenticated` SELECT on
  // every column of 212 of the 213 public tables instead of granting SELECT on
  // the relation, so `SELECT <column>` is allowed while `SELECT *` is refused.
  // Without these the rebuilt database would refuse every direct table read.
  const columnGrantRows = await rows(
    client,
    `
    SELECT n.nspname AS schema, c.relname AS table_name, a.attname AS name,
           CASE WHEN ae.grantee = 0 THEN 'PUBLIC' ELSE ae.grantee::regrole::text END AS grantee,
           ae.privilege_type AS privilege, ae.is_grantable AS grantable
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_attribute a ON a.attrelid = c.oid
      CROSS JOIN LATERAL aclexplode(a.attacl) ae
     WHERE n.nspname IN ('public', 'sims_private') AND c.relkind = 'r'
     ORDER BY n.nspname, c.relname, a.attnum, ae.privilege_type, 4`,
  );

  const flagRows = await rows(
    client,
    `
    SELECT n.nspname AS schema, c.relname AS table_name,
           c.relrowsecurity AS rls, c.relforcerowsecurity AS force_rls
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname IN ('public', 'sims_private') AND c.relkind = 'r'`,
  );

  const indexRows = await rows(
    client,
    `
    SELECT n.nspname AS schema, c.relname AS name, t.relname AS table_name,
           pg_get_indexdef(i.indexrelid) AS definition
      FROM pg_index i
      JOIN pg_class c ON c.oid = i.indexrelid
      JOIN pg_class t ON t.oid = i.indrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname IN ('public', 'sims_private') AND NOT i.indisprimary
     ORDER BY n.nspname, t.relname, c.relname`,
  );

  const viewRows = await rows(
    client,
    `
    SELECT n.nspname AS schema, c.relname AS name, c.relkind AS kind,
           pg_get_viewdef(c.oid, true) AS body, c.reloptions AS options
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname IN ('public', 'sims_private') AND c.relkind IN ('v', 'm')
     ORDER BY n.nspname, c.relname`,
  );

  const functionRows = await rows(
    client,
    `
    SELECT n.nspname AS schema, p.proname AS name,
           pg_get_function_identity_arguments(p.oid) AS args,
           pg_get_functiondef(p.oid) AS definition
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname IN ('public', 'sims_private')
     ORDER BY n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)`,
  );

  const triggerRows = await rows(
    client,
    `
    SELECT n.nspname AS schema, c.relname AS table_name, t.tgname AS name,
           pg_get_triggerdef(t.oid, true) AS definition
      FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname IN ('public', 'sims_private') AND NOT t.tgisinternal
     ORDER BY n.nspname, c.relname, t.tgname`,
  );

  const policyRows = await rows(
    client,
    `
    SELECT n.nspname AS schema, c.relname AS table_name, p.polname AS name,
           CASE p.polcmd WHEN 'r' THEN 'SELECT' WHEN 'a' THEN 'INSERT'
                         WHEN 'w' THEN 'UPDATE' WHEN 'd' THEN 'DELETE'
                         WHEN '*' THEN 'ALL' ELSE p.polcmd::text END AS command,
           p.polpermissive AS permissive,
           pg_get_expr(p.polqual, p.polrelid) AS using_expr,
           pg_get_expr(p.polwithcheck, p.polrelid) AS with_check,
           ARRAY(SELECT COALESCE(r.rolname, 'PUBLIC')
                   FROM unnest(p.polroles) g
                   LEFT JOIN pg_roles r ON r.oid = g)::text[] AS roles
      FROM pg_policy p
      JOIN pg_class c ON c.oid = p.polrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname IN ('public', 'sims_private')
     ORDER BY n.nspname, c.relname, p.polname`,
  );

  const aclRows = async (sql) => {
    const result = await rows(client, sql);
    return result.map((r) => ({
      schema: r.schema,
      object: r.object,
      grantee: r.grantee,
      privilege: r.privilege,
      grantable: r.grantable,
    }));
  };

  const grants = [];
  grants.push(
    ...(await aclRows(`
    SELECT n.nspname AS schema, c.relname AS object, COALESCE(r.rolname, 'PUBLIC') AS grantee,
           a.privilege_type AS privilege, a.is_grantable AS grantable
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      CROSS JOIN LATERAL aclexplode(c.relacl) a
      LEFT JOIN pg_roles r ON r.oid = a.grantee
     WHERE n.nspname IN ('public', 'sims_private') AND c.relkind IN ('r', 'v', 'm', 'S', 'p', 'f')`)),
  );
  grants.push(
    ...(await aclRows(`
    SELECT n.nspname AS schema,
           p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS object,
           COALESCE(r.rolname, 'PUBLIC') AS grantee,
           a.privilege_type AS privilege, a.is_grantable AS grantable
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      CROSS JOIN LATERAL aclexplode(p.proacl) a
      LEFT JOIN pg_roles r ON r.oid = a.grantee
     WHERE n.nspname IN ('public', 'sims_private')`)),
  );
  grants.push(
    ...(await aclRows(`
    SELECT n.nspname AS schema, t.typname AS object, COALESCE(r.rolname, 'PUBLIC') AS grantee,
           a.privilege_type AS privilege, a.is_grantable AS grantable
      FROM pg_type t
      JOIN pg_namespace n ON n.oid = t.typnamespace
      CROSS JOIN LATERAL aclexplode(t.typacl) a
      LEFT JOIN pg_roles r ON r.oid = a.grantee
     WHERE n.nspname IN ('public', 'sims_private') AND t.typtype IN ('d', 'e', 'c')`)),
  );
  grants.push(
    ...(await aclRows(`
    SELECT n.nspname AS schema, n.nspname AS object, COALESCE(r.rolname, 'PUBLIC') AS grantee,
           a.privilege_type AS privilege, a.is_grantable AS grantable
      FROM pg_namespace n
      CROSS JOIN LATERAL aclexplode(n.nspacl) a
      LEFT JOIN pg_roles r ON r.oid = a.grantee
     WHERE n.nspname IN ('public', 'sims_private')`)),
  );
  grants.sort(
    (a, b) =>
      byKey(a.schema, b.schema) ||
      byKey(a.object, b.object) ||
      byKey(a.grantee, b.grantee) ||
      byKey(a.privilege, b.privilege),
  );

  // --- assemble ------------------------------------------------------------
  const checksByDomain = new Map();
  for (const r of domainChecks) {
    const key = `${r.schema}.${r.name}`;
    if (!checksByDomain.has(key)) checksByDomain.set(key, []);
    checksByDomain.get(key).push({ name: r.check_name, definition: r.definition });
  }

  const domainList = domains.map((r) => {
    const key = `${r.schema}.${r.name}`;
    const checks = checksByDomain.get(key) || [];
    return {
      schema: r.schema,
      name: r.name,
      base_type: r.base_type,
      not_null: r.not_null,
      default: r.default_expr,
      typdefault: r.typdefault,
      check: checks.length ? checks[0].definition : null,
      check_name: checks.length ? checks[0].name : null,
      checks,
    };
  });

  const enumMap = new Map();
  for (const r of enumRows) {
    const key = `${r.schema}.${r.name}`;
    if (!enumMap.has(key)) enumMap.set(key, { schema: r.schema, name: r.name, labels: [] });
    enumMap.get(key).labels.push(r.label);
  }
  const enumList = [...enumMap.entries()]
    .sort((a, b) => byKey(a[0], b[0]))
    .map(([, value]) => value);

  const compositeMap = new Map();
  for (const r of compositeRows) {
    const key = `${r.schema}.${r.name}`;
    if (!compositeMap.has(key)) {
      compositeMap.set(key, { schema: r.schema, name: r.name, attributes: [] });
    }
    compositeMap.get(key).attributes.push({
      name: r.attname,
      type: r.att_type,
      not_null: r.not_null,
      default: r.default_expr,
      position: r.position,
    });
  }
  const compositeList = [...compositeMap.entries()]
    .sort((a, b) => byKey(a[0], b[0]))
    .map(([, value]) => value);

  const sequenceList = sequenceRows.map((r) => ({
    schema: r.schema,
    name: r.name,
    type: r.seq_type,
    start: raw(r.start),
    min: raw(r.min),
    max: raw(r.max),
    increment: raw(r.increment),
    cycle: r.cycle,
    cache: raw(r.cache),
    owned_by: r.owned_by,
  }));

  const tables = new Map();
  const tableKey = (schema, name) => `${schema}.${name}`;
  const ensureTable = (schema, name) => {
    const key = tableKey(schema, name);
    if (!tables.has(key)) {
      tables.set(key, {
        schema,
        name,
        rls: false,
        force_rls: false,
        columns: [],
        constraints: [],
      });
    }
    return tables.get(key);
  };
  for (const r of columnRows) {
    const table = ensureTable(r.schema, r.table_name);
    table.columns.push({
      name: r.name,
      type: r.col_type,
      not_null: r.not_null,
      default: r.default_expr,
      identity: r.identity,
      generated: r.generated,
      position: r.position,
      privileges: [],
    });
  }
  for (const g of columnGrantRows) {
    const table = tables.get(tableKey(g.schema, g.table_name));
    if (!table) continue;
    const col = table.columns.find((c) => c.name === g.name);
    if (!col) continue;
    col.privileges.push({ grantee: g.grantee, privilege: g.privilege, grantable: g.grantable });
  }
  for (const r of constraintRows) {
    const table = ensureTable(r.schema, r.table_name);
    table.constraints.push({
      name: r.name,
      type: r.type,
      definition: r.definition,
    });
  }
  for (const r of flagRows) {
    const table = ensureTable(r.schema, r.table_name);
    table.rls = r.rls;
    table.force_rls = r.force_rls;
  }
  const tableList = [...tables.entries()]
    .sort((a, b) => byKey(a[0], b[0]))
    .map(([, value]) => value);

  const indexList = indexRows.map((r) => ({
    schema: r.schema,
    name: r.name,
    table: r.table_name,
    definition: r.definition,
  }));

  const viewList = viewRows.map((r) => ({
    schema: r.schema,
    name: r.name,
    kind: r.kind,
    body: r.body,
    options: r.options,
  }));

  const functionList = functionRows.map((r) => ({
    schema: r.schema,
    name: r.name,
    args: r.args,
    definition: r.definition,
  }));

  const triggerList = triggerRows.map((r) => ({
    schema: r.schema,
    table: r.table_name,
    name: r.name,
    definition: r.definition,
  }));

  const policyList = policyRows.map((r) => ({
    schema: r.schema,
    table: r.table_name,
    name: r.name,
    command: r.command,
    permissive: r.permissive,
    using: r.using_expr,
    with_check: r.with_check,
    roles: r.roles,
  }));

  const rowCounts = {};
  for (const table of tableList) {
    // The append-only audit logs grow with use, not with the schema - see
    // ACTIVITY_TABLES.  Their count would make the dump stale after every
    // test run.
    if (ACTIVITY_TABLES.has(table.name)) continue;
    const res = await client.query(
      `SELECT count(*) FROM "${table.schema}"."${table.name}"`,
    );
    rowCounts[tableKey(table.schema, table.name)] = raw(res.rows[0].count);
  }

  const catalogue = {
    source: 'live',
    server_version: (await client.query('SHOW server_version')).rows[0].server_version,
    schemas,
    domains: domainList,
    enums: enumList,
    composites: compositeList,
    sequences: sequenceList,
    tables: tableList,
    indexes: indexList,
    views: viewList,
    functions: functionList,
    triggers: triggerList,
    policies: policyList,
    grants,
    row_counts: rowCounts,
  };
  stripTracking(catalogue);
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

/** The catalogue of the migration set applied to a fresh embedded PostgreSQL. */
export async function dumpRebuiltCatalogue() {
  const { db, files } = await applyMigrations();
  try {
    const catalogue = await dumpCatalogue(db);
    catalogue.source = 'rebuilt';
    return { catalogue, files: files.length };
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
  const sourceIndex = args.indexOf('--source');
  const source = sourceIndex === -1 ? 'live' : args[sourceIndex + 1];
  if (!['live', 'rebuilt'].includes(source)) {
    console.error(`unknown --source ${source} (expected live or rebuilt)`);
    process.exit(2);
  }
  // the live catalogue is the input of the migration builder; a dump of the
  // rebuilt database must not overwrite it
  const fallback = source === 'rebuilt' ? REBUILT_OUT : DEFAULT_OUT;
  const out = outIndex === -1 ? fallback : path.resolve(ROOT, args[outIndex + 1]);

  let catalogue;
  let files = 0;
  if (source === 'rebuilt') {
    const rebuilt = await dumpRebuiltCatalogue();
    catalogue = rebuilt.catalogue;
    files = rebuilt.files;
  } else {
    const client = await connectLive();
    try {
      catalogue = await dumpLiveCatalogue(client);
    } finally {
      await client.end();
    }
  }

  const text = toJson(catalogue);
  // `tools/dump_catalogue.py` writes the file through python's text mode, which
  // uses CRLF on Windows; the same line endings keep the two dumps byte
  // identical.
  const fileText = text.replace(/\n/g, '\r\n');
  const normalise = (value) => (value === null ? null : value.replace(/\r\n/g, '\n'));
  const existing = fs.existsSync(out) ? fs.readFileSync(out, 'utf8') : null;
  const unchanged = normalise(existing) === text;

  if (asJson) {
    console.log(
      JSON.stringify(
        {
          output: out,
          source,
          migration_files: files,
          unchanged,
          counts: catalogue.counts,
        },
        null,
        1,
      ),
    );
    process.exit(unchanged ? 0 : 1);
  }

  if (check) {
    if (unchanged) {
      console.log(`OK - ${path.relative(ROOT, out)} is up to date`);
      process.exit(0);
    }
    console.error(`DIFF - ${path.relative(ROOT, out)} is out of date`);
    if (existing === null) {
      console.error('the file does not exist');
    } else {
      const a = normalise(existing).split('\n');
      const b = text.split('\n');
      let shown = 0;
      for (let i = 0; i < Math.max(a.length, b.length) && shown < 20; i++) {
        if (a[i] !== b[i]) {
          console.error(`  line ${i + 1}: on disk ${JSON.stringify(a[i] ?? null)}`);
          console.error(`           live  ${JSON.stringify(b[i] ?? null)}`);
          shown += 1;
        }
      }
    }
    process.exit(1);
  }

  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, fileText, 'utf8');
  const c = catalogue.counts;
  console.log(`wrote ${path.relative(ROOT, out)} (${fs.statSync(out).size} bytes)`);
  console.log(
    `tables ${c.tables}, views ${c.views}, functions ${c.functions}, triggers ${c.triggers}, ` +
      `policies ${c.policies}, RLS on ${c.rls_tables}`,
  );
  console.log(
    `indexes ${c.indexes}, sequences ${c.sequences}, domains ${c.domains}, ` +
      `enums ${c.enums}, composites ${c.composites}, grants ${c.grants}`,
  );
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
