#!/usr/bin/env python3
"""Dump the live Supabase catalogue (read-only) to JSON.

The dump is the authoritative input for `tools/build_migrations.py` and
`tools/build_rls.py`: the project's `supabase/migrations/` directory was lost and
has to be reconstructed so that applying it to a fresh database reproduces the
live catalogue exactly.

The connection is ALWAYS opened read-only (`readonly=True`, `autocommit=True`).
Nothing in this script writes to the remote database.

Usage:
    python tools/dump_catalogue.py [--out tools/catalogue/live_catalogue.json]
                                   [--seed-out tools/catalogue/live_seed_data.json]
                                   [--data]        # also dump table rows
"""
from __future__ import annotations

import argparse
import datetime
import decimal
import json
import os
import sys
import uuid
from pathlib import Path

import psycopg2
import psycopg2.extras

ROOT = Path(__file__).resolve().parent.parent

DEFAULT_HOST = "aws-0-ap-southeast-1.pooler.supabase.com"
DEFAULT_PORT = 5432
DEFAULT_DB = "postgres"
DEFAULT_USER = "postgres.khqqfgqvwdxlqkncwtmh"
DEFAULT_PASSWORD = ""

# Schemas that the migration set owns. `auth`/`storage` come from the Supabase
# stub in tests/db/supabase-stub.ts and are therefore not part of the dump.
OWNED_SCHEMAS = ("public", "sims_private")

#: The migration tracker is the applier's own bookkeeping, not application
#: schema.  It is left out of the catalogue and of the schema document, so that
#: running `tools/apply_migrations.py` does not change the contract the project
#: is measured against.
TRACKING_SCHEMA = "sims_private"
TRACKING_TABLE = "schema_migration"


def is_tracking_object(name: str) -> bool:
    """True for the tracker table and for everything that belongs to it."""
    return name == TRACKING_TABLE or name.startswith(TRACKING_TABLE + "_")


def strip_tracking(cat: dict) -> dict:
    """Remove the migration tracker and its satellites from a catalogue.

    The tracker is created by the applier itself, with
    `CREATE TABLE IF NOT EXISTS`, and it is not part of the migration set. If
    it were part of the catalogue, the first run of the applier would change
    the schema contract and the migration set, and every generated document
    would have to be regenerated.
    """
    cat["tables"] = [
        t for t in cat["tables"]
        if not (t["schema"] == TRACKING_SCHEMA and is_tracking_object(t["name"]))
    ]
    cat["indexes"] = [
        i for i in cat["indexes"]
        if not (i["schema"] == TRACKING_SCHEMA and is_tracking_object(i["table"]))
    ]
    cat["sequences"] = [
        s for s in cat["sequences"]
        if not (s["schema"] == TRACKING_SCHEMA and is_tracking_object(s["name"]))
    ]
    cat["composites"] = [
        c for c in cat["composites"]
        if not (c["schema"] == TRACKING_SCHEMA and is_tracking_object(c["name"]))
    ]
    cat["grants"] = [
        g for g in cat["grants"]
        if not (g["schema"] == TRACKING_SCHEMA and is_tracking_object(g["object"]))
    ]
    cat["row_counts"].pop(f"{TRACKING_SCHEMA}.{TRACKING_TABLE}", None)
    return cat


def dsn() -> dict:
    """The connection settings.

    The password is never stored in the repository: it comes from
    `SUPABASE_DB_PASSWORD` or `SIMS_DB_PASSWORD`.
    """

    def pick(name: str, fallback: str) -> str:
        for prefix in ("SUPABASE_DB_", "SIMS_DB_"):
            value = os.environ.get(prefix + name)
            if value:
                return value
        return fallback

    return dict(
        host=pick("HOST", DEFAULT_HOST),
        port=int(pick("PORT", DEFAULT_PORT)),
        dbname=pick("NAME", DEFAULT_DB),
        user=pick("USER", DEFAULT_USER),
        password=pick("PASSWORD", DEFAULT_PASSWORD),
        sslmode=pick("SSLMODE", "require"),
    )


def connect():
    settings = dsn()
    if not settings["password"]:
        raise SystemExit(
            "SUPABASE_DB_PASSWORD is not set (or SIMS_DB_PASSWORD). The password "
            "is never stored in the repository - put it into .env.local."
        )
    conn = psycopg2.connect(**settings)
    conn.set_session(readonly=True, autocommit=True)
    return conn


def q(cur, sql, args=None):
    cur.execute(sql, args)
    return cur.fetchall()


def jsonable(value):
    if isinstance(value, (datetime.datetime, datetime.date, datetime.time)):
        return value.isoformat()
    if isinstance(value, datetime.timedelta):
        return value.total_seconds()
    if isinstance(value, decimal.Decimal):
        # keep the exact decimal text: JSON has no decimal type
        return {"__decimal__": str(value)}
    if isinstance(value, uuid.UUID):
        return str(value)
    if isinstance(value, (bytes, bytearray, memoryview)):
        return bytes(value).hex()
    if isinstance(value, dict):
        return {k: jsonable(v) for k, v in value.items()}
    if isinstance(value, (list, tuple)):
        return [jsonable(v) for v in value]
    return value


# ---------------------------------------------------------------------------
# catalogue sections
# ---------------------------------------------------------------------------
def dump_domains(cur):
    rows = q(cur, """
        SELECT n.nspname, t.typname,
               format_type(t.typbasetype, t.typtypmod),
               t.typnotnull,
               pg_get_expr(d.adbin, d.adrelid),
               t.typdefault
          FROM pg_type t
          JOIN pg_namespace n ON n.oid = t.typnamespace
          LEFT JOIN pg_attrdef d ON d.adrelid = t.typrelid AND d.adnum = 1
         WHERE t.typtype = 'd' AND n.nspname = ANY(%s)
         ORDER BY n.nspname, t.typname
    """, (list(OWNED_SCHEMAS),))
    # the range check of a domain lives in pg_constraint, not in pg_attrdef
    checks = q(cur, """
        SELECT n.nspname, t.typname, con.conname, pg_get_constraintdef(con.oid, true)
          FROM pg_type t
          JOIN pg_namespace n ON n.oid = t.typnamespace
          JOIN pg_constraint con ON con.contypid = t.oid
         WHERE t.typtype = 'd' AND n.nspname = ANY(%s)
         ORDER BY n.nspname, t.typname, con.conname
    """, (list(OWNED_SCHEMAS),))
    by_name = {(ns, name): [] for ns, name, *_ in rows}
    for ns, name, cname, cdef in checks:
        by_name.setdefault((ns, name), []).append((cname, cdef))
    out = []
    for ns, name, base, notnull, default, typdefault in rows:
        entries = by_name.get((ns, name), [])
        out.append({
            "schema": ns, "name": name, "base_type": base,
            "not_null": notnull, "default": default, "typdefault": typdefault,
            "check": entries[0][1] if entries else None,
            "check_name": entries[0][0] if entries else None,
            "checks": [{"name": c, "definition": d} for c, d in entries],
        })
    return out


def dump_enums(cur):
    rows = q(cur, """
        SELECT n.nspname, t.typname, e.enumlabel
          FROM pg_type t
          JOIN pg_namespace n ON n.oid = t.typnamespace
          JOIN pg_enum e ON e.enumtypid = t.oid
         WHERE n.nspname = ANY(%s)
         ORDER BY n.nspname, t.typname, e.enumsortorder
    """, (list(OWNED_SCHEMAS),))
    out: dict[tuple[str, str], list[str]] = {}
    for ns, name, label in rows:
        out.setdefault((ns, name), []).append(label)
    return [
        {"schema": ns, "name": name, "labels": labels}
        for (ns, name), labels in sorted(out.items())
    ]


def dump_composites(cur):
    rows = q(cur, """
        SELECT n.nspname, t.typname, a.attname,
               format_type(a.atttypid, a.atttypmod),
               a.attnotnull,
               pg_get_expr(d.adbin, d.adrelid),
               a.attnum
          FROM pg_type t
          JOIN pg_namespace n ON n.oid = t.typnamespace
          JOIN pg_class c ON c.oid = t.typrelid
          JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
          LEFT JOIN pg_attrdef d ON d.adrelid = c.oid AND d.adnum = a.attnum
         WHERE t.typtype = 'c' AND n.nspname = ANY(%s)
         ORDER BY n.nspname, t.typname, a.attnum
    """, (list(OWNED_SCHEMAS),))
    out: dict[tuple[str, str], list[dict]] = {}
    for ns, name, att, typ, notnull, default, attnum in rows:
        out.setdefault((ns, name), []).append({
            "name": att, "type": typ, "not_null": notnull,
            "default": default, "position": attnum,
        })
    return [
        {"schema": ns, "name": name, "attributes": attrs}
        for (ns, name), attrs in sorted(out.items())
    ]


def dump_sequences(cur):
    rows = q(cur, """
        SELECT n.nspname, c.relname, format_type(s.seqtypid, NULL),
               s.seqstart, s.seqmin, s.seqmax, s.seqincrement,
               s.seqcycle, s.seqcache,
               CASE WHEN d.refobjid IS NULL THEN NULL
                    ELSE dn.nspname || '.' || dc.relname || '.' || da.attname END
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          JOIN pg_sequence s ON s.seqrelid = c.oid
          LEFT JOIN pg_depend d ON d.classid = 'pg_class'::regclass AND d.objid = c.oid
                                AND d.refclassid = 'pg_class'::regclass
                                AND d.deptype IN ('a', 'i')
          LEFT JOIN pg_class dc ON dc.oid = d.refobjid
          LEFT JOIN pg_namespace dn ON dn.oid = dc.relnamespace
          LEFT JOIN pg_attribute da ON da.attrelid = d.refobjid AND da.attnum = d.refobjsubid
         WHERE n.nspname = ANY(%s) AND c.relkind = 'S'
         ORDER BY n.nspname, c.relname
    """, (list(OWNED_SCHEMAS),))
    return [
        {
            "schema": r[0], "name": r[1], "type": r[2], "start": r[3], "min": r[4],
            "max": r[5], "increment": r[6], "cycle": r[7], "cache": r[8], "owned_by": r[9],
        }
        for r in rows
    ]


def dump_tables(cur):
    cols = q(cur, """
        SELECT n.nspname, c.relname, a.attname,
               format_type(a.atttypid, a.atttypmod),
               a.attnotnull,
               pg_get_expr(d.adbin, d.adrelid),
               a.attidentity,
               a.attgenerated,
               a.attnum,
               a.atttypid = 0
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
          LEFT JOIN pg_attrdef d ON d.adrelid = c.oid AND d.adnum = a.attnum
         WHERE n.nspname = ANY(%s) AND c.relkind = 'r'
         ORDER BY n.nspname, c.relname, a.attnum
    """, (list(OWNED_SCHEMAS),))
    cons = q(cur, """
        SELECT n.nspname, c.relname, con.conname, con.contype,
               pg_get_constraintdef(con.oid, true)
          FROM pg_constraint con
          JOIN pg_class c ON c.oid = con.conrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = ANY(%s) AND c.relkind = 'r'
         ORDER BY n.nspname, c.relname, con.conname
    """, (list(OWNED_SCHEMAS),))
    flags = q(cur, """
        SELECT n.nspname, c.relname, c.relrowsecurity, c.relforcerowsecurity
          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = ANY(%s) AND c.relkind = 'r'
    """, (list(OWNED_SCHEMAS),))
    # Column level privileges.  The live project grants `authenticated` SELECT on
    # every column of 212 of the 213 public tables instead of granting SELECT on
    # the relation, so `SELECT *` is refused while `SELECT <column>` is allowed.
    # Without these the rebuilt database would refuse every direct table read.
    col_grants = q(cur, """
        SELECT n.nspname, c.relname, a.attname,
               CASE WHEN ae.grantee = 0 THEN 'PUBLIC'
                    ELSE ae.grantee::regrole::text END AS grantee,
               ae.privilege_type, ae.is_grantable
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          JOIN pg_attribute a ON a.attrelid = c.oid
          CROSS JOIN LATERAL aclexplode(a.attacl) ae
         WHERE n.nspname = ANY(%s) AND c.relkind = 'r'
         ORDER BY n.nspname, c.relname, a.attnum, ae.privilege_type, 4
    """, (list(OWNED_SCHEMAS),))

    tables: dict[tuple[str, str], dict] = {}
    for ns, rel, att, typ, notnull, default, identity, generated, attnum, dropped in cols:
        t = tables.setdefault((ns, rel), {
            "schema": ns, "name": rel, "rls": False, "force_rls": False,
            "columns": [], "constraints": [],
        })
        t["columns"].append({
            "name": att, "type": typ, "not_null": notnull, "default": default,
            "identity": identity, "generated": generated, "position": attnum,
            "privileges": [],
        })
    for ns, rel, att, grantee, privilege, grantable in col_grants:
        t = tables.get((ns, rel))
        if t is None:
            continue
        for col in t["columns"]:
            if col["name"] == att:
                col["privileges"].append({
                    "grantee": grantee, "privilege": privilege, "grantable": grantable,
                })
                break
    for ns, rel, name, contype, definition in cons:
        t = tables.setdefault((ns, rel), {
            "schema": ns, "name": rel, "rls": False, "force_rls": False,
            "columns": [], "constraints": [],
        })
        t["constraints"].append({
            "name": name, "type": contype, "definition": definition,
        })
    for ns, rel, rls, force in flags:
        t = tables.setdefault((ns, rel), {
            "schema": ns, "name": rel, "rls": False, "force_rls": False,
            "columns": [], "constraints": [],
        })
        t["rls"] = rls
        t["force_rls"] = force
    return [tables[k] for k in sorted(tables)]


def dump_indexes(cur):
    rows = q(cur, """
        SELECT n.nspname, c.relname, t.relname, pg_get_indexdef(i.indexrelid)
          FROM pg_index i
          JOIN pg_class c ON c.oid = i.indexrelid
          JOIN pg_class t ON t.oid = i.indrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = ANY(%s) AND NOT i.indisprimary
         ORDER BY n.nspname, t.relname, c.relname
    """, (list(OWNED_SCHEMAS),))
    return [
        {"schema": r[0], "name": r[1], "table": r[2], "definition": r[3]}
        for r in rows
    ]


def dump_views(cur):
    rows = q(cur, """
        SELECT n.nspname, c.relname, c.relkind, pg_get_viewdef(c.oid, true), c.reloptions
          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = ANY(%s) AND c.relkind IN ('v', 'm')
         ORDER BY n.nspname, c.relname
    """, (list(OWNED_SCHEMAS),))
    return [
        {"schema": r[0], "name": r[1], "kind": r[2], "body": r[3], "options": r[4]}
        for r in rows
    ]


def dump_functions(cur):
    rows = q(cur, """
        SELECT n.nspname, p.proname,
               pg_get_function_identity_arguments(p.oid),
               pg_get_functiondef(p.oid)
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = ANY(%s)
         ORDER BY n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)
    """, (list(OWNED_SCHEMAS),))
    return [
        {"schema": r[0], "name": r[1], "args": r[2], "definition": r[3]}
        for r in rows
    ]


def dump_triggers(cur):
    rows = q(cur, """
        SELECT n.nspname, c.relname, t.tgname, pg_get_triggerdef(t.oid, true)
          FROM pg_trigger t
          JOIN pg_class c ON c.oid = t.tgrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = ANY(%s) AND NOT t.tgisinternal
         ORDER BY n.nspname, c.relname, t.tgname
    """, (list(OWNED_SCHEMAS),))
    return [
        {"schema": r[0], "table": r[1], "name": r[2], "definition": r[3]}
        for r in rows
    ]


def dump_policies(cur):
    rows = q(cur, """
        SELECT n.nspname, c.relname, p.polname,
               CASE p.polcmd WHEN 'r' THEN 'SELECT' WHEN 'a' THEN 'INSERT'
                            WHEN 'w' THEN 'UPDATE' WHEN 'd' THEN 'DELETE'
                            WHEN '*' THEN 'ALL' ELSE p.polcmd::text END,
               p.polpermissive,
               pg_get_expr(p.polqual, p.polrelid),
               pg_get_expr(p.polwithcheck, p.polrelid),
               ARRAY(SELECT COALESCE(r.rolname, 'PUBLIC')
                       FROM unnest(p.polroles) g
                       LEFT JOIN pg_roles r ON r.oid = g)
          FROM pg_policy p
          JOIN pg_class c ON c.oid = p.polrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = ANY(%s)
         ORDER BY n.nspname, c.relname, p.polname
    """, (list(OWNED_SCHEMAS),))
    return [
        {
            "schema": r[0], "table": r[1], "name": r[2], "command": r[3],
            "permissive": r[4], "using": r[5], "with_check": r[6], "roles": r[7],
        }
        for r in rows
    ]


def _acl_rows(cur, sql):
    rows = q(cur, sql, (list(OWNED_SCHEMAS),))
    out = []
    for r in rows:
        out.append({
            "schema": r[0], "object": r[1], "grantee": r[2],
            "privilege": r[3], "grantable": r[4],
        })
    return out


def dump_grants(cur):
    grants = []
    grants += _acl_rows(cur, """
        SELECT n.nspname, c.relname, COALESCE(r.rolname, 'PUBLIC'),
               a.privilege_type, a.is_grantable
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          CROSS JOIN LATERAL aclexplode(c.relacl) a
          LEFT JOIN pg_roles r ON r.oid = a.grantee
         WHERE n.nspname = ANY(%s) AND c.relkind IN ('r', 'v', 'm', 'S', 'p', 'f')
    """)
    grants += _acl_rows(cur, """
        SELECT n.nspname, p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
               COALESCE(r.rolname, 'PUBLIC'), a.privilege_type, a.is_grantable
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
          CROSS JOIN LATERAL aclexplode(p.proacl) a
          LEFT JOIN pg_roles r ON r.oid = a.grantee
         WHERE n.nspname = ANY(%s)
    """)
    grants += _acl_rows(cur, """
        SELECT n.nspname, t.typname, COALESCE(r.rolname, 'PUBLIC'),
               a.privilege_type, a.is_grantable
          FROM pg_type t
          JOIN pg_namespace n ON n.oid = t.typnamespace
          CROSS JOIN LATERAL aclexplode(t.typacl) a
          LEFT JOIN pg_roles r ON r.oid = a.grantee
         WHERE n.nspname = ANY(%s) AND t.typtype IN ('d', 'e', 'c')
    """)
    grants += _acl_rows(cur, """
        SELECT n.nspname, n.nspname, COALESCE(r.rolname, 'PUBLIC'),
               a.privilege_type, a.is_grantable
          FROM pg_namespace n
          CROSS JOIN LATERAL aclexplode(n.nspacl) a
          LEFT JOIN pg_roles r ON r.oid = a.grantee
         WHERE n.nspname = ANY(%s)
    """)
    grants.sort(key=lambda g: (g["schema"], g["object"], g["grantee"], g["privilege"]))
    return grants


def dump_row_counts(cur):
    tables = q(cur, """
        SELECT n.nspname, c.relname FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
         WHERE n.nspname = ANY(%s) AND c.relkind = 'r'
         ORDER BY n.nspname, c.relname
    """, (list(OWNED_SCHEMAS),))
    counts = {}
    for ns, rel in tables:
        cur.execute(f'SELECT count(*) FROM "{ns}"."{rel}"')
        counts[f"{ns}.{rel}"] = cur.fetchone()[0]
    return counts


def dump_data(cur, tables):
    """Dump every row of every non-empty table (used to regenerate the seed INSERTs)."""
    out = {}
    for t in tables:
        ns, rel = t["schema"], t["name"]
        cols = [c["name"] for c in t["columns"]]
        cur.execute(
            f'SELECT {", ".join(chr(34) + c + chr(34) for c in cols)} FROM "{ns}"."{rel}"'
        )
        rows = cur.fetchall()
        if not rows:
            continue
        out[f"{ns}.{rel}"] = {
            "columns": cols,
            "rows": [[jsonable(v) for v in r] for r in rows],
        }
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out", default=str(ROOT / "tools" / "catalogue" / "live_catalogue.json"))
    ap.add_argument("--seed-out", default=str(ROOT / "tools" / "catalogue" / "live_seed_data.json"))
    ap.add_argument("--data", action="store_true", help="also dump table rows")
    args = ap.parse_args()

    conn = connect()
    try:
        cur = conn.cursor()
        cat = {
            "source": "live",
            "server_version": q(cur, "SHOW server_version")[0][0],
            "schemas": list(OWNED_SCHEMAS),
            "domains": dump_domains(cur),
            "enums": dump_enums(cur),
            "composites": dump_composites(cur),
            "sequences": dump_sequences(cur),
            "tables": dump_tables(cur),
            "indexes": dump_indexes(cur),
            "views": dump_views(cur),
            "functions": dump_functions(cur),
            "triggers": dump_triggers(cur),
            "policies": dump_policies(cur),
            "grants": dump_grants(cur),
            "row_counts": dump_row_counts(cur),
        }
        cat = strip_tracking(cat)
        cat["counts"] = {
            "tables": len(cat["tables"]),
            "views": len(cat["views"]),
            "functions": len(cat["functions"]),
            "triggers": len(cat["triggers"]),
            "policies": len(cat["policies"]),
            "rls_tables": sum(1 for t in cat["tables"] if t["rls"]),
            "indexes": len(cat["indexes"]),
            "sequences": len(cat["sequences"]),
            "domains": len(cat["domains"]),
            "enums": len(cat["enums"]),
            "composites": len(cat["composites"]),
            "grants": len(cat["grants"]),
        }
        out = Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(cat, indent=1, sort_keys=False), encoding="utf-8")
        print(f"wrote {out} ({out.stat().st_size} bytes)")
        print("counts:", json.dumps(cat["counts"]))

        if args.data:
            data = dump_data(cur, cat["tables"])
            sout = Path(args.seed_out)
            sout.parent.mkdir(parents=True, exist_ok=True)
            sout.write_text(json.dumps(data, indent=1), encoding="utf-8")
            print(f"wrote {sout} ({len(data)} tables, {sout.stat().st_size} bytes)")
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
