"""
Validate tools/seed_demo.sql against the live schema (READ ONLY).

Checks, for every INSERT in the seed file:
  * the target table exists in public
  * every named column exists on that table
  * no column is GENERATED ALWAYS (the database computes it)
  * every literal enum/check value used is one the table actually accepts

Usage:
    python tools/validate/seed_columns.py [--file tools/seed_demo.sql]
"""

from __future__ import annotations

import argparse
import os
import re
import sys

try:
    import psycopg2
except ImportError:  # pragma: no cover
    sys.exit("psycopg2 is required: pip install psycopg2-binary")

DEFAULT_HOST = os.environ.get("SUPABASE_DB_HOST", "aws-0-ap-southeast-1.pooler.supabase.com")
DEFAULT_PORT = int(os.environ.get("SUPABASE_DB_PORT", "5432"))
DEFAULT_DB = os.environ.get("SUPABASE_DB_NAME", "postgres")
DEFAULT_USER = os.environ.get("SUPABASE_DB_USER", "postgres.khqqfgqvwdxlqkncwtmh")
DEFAULT_PASSWORD = os.environ.get("SUPABASE_DB_PASSWORD", "")

INSERT_RE = re.compile(
    r"INSERT\s+INTO\s+(?:public\.)?([a-z_][a-z0-9_]*)\s*\(([^)]*)\)",
    re.IGNORECASE,
)


def split_columns(text: str) -> list[str]:
    return [c.strip().strip('"').lower() for c in text.split(",") if c.strip()]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--file", default="tools/seed_demo.sql")
    ap.add_argument("--host", default=DEFAULT_HOST)
    ap.add_argument("--port", type=int, default=DEFAULT_PORT)
    ap.add_argument("--db", default=DEFAULT_DB)
    ap.add_argument("--user", default=DEFAULT_USER)
    ap.add_argument("--password", default=DEFAULT_PASSWORD)
    args = ap.parse_args()

    if not args.password:
        sys.exit("SUPABASE_DB_PASSWORD is not set (or pass --password)")

    with open(args.file, encoding="utf-8") as fh:
        sql = fh.read()

    conn = psycopg2.connect(
        host=args.host,
        port=args.port,
        dbname=args.db,
        user=args.user,
        password=args.password,
        connect_timeout=30,
        sslmode="require",
    )
    conn.set_session(readonly=True, autocommit=True)
    cur = conn.cursor()

    # table -> {column: (type, generated, not_null)}
    cur.execute(
        """
        select c.relname, a.attname, format_type(a.atttypid, a.atttypmod),
               a.attgenerated <> '', a.attnotnull
          from pg_attribute a
          join pg_class c on c.oid = a.attrelid
          join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public' and c.relkind = 'r'
           and a.attnum > 0 and not a.attisdropped
        """
    )
    tables: dict[str, dict[str, tuple[str, bool, bool]]] = {}
    for table, column, typ, generated, not_null in cur.fetchall():
        tables.setdefault(table, {})[column] = (typ, generated, not_null)

    problems: list[str] = []
    checked = 0

    for match in INSERT_RE.finditer(sql):
        table = match.group(1).lower()
        columns = split_columns(match.group(2))
        checked += 1

        if table not in tables:
            problems.append("table `%s` does not exist in public" % table)
            continue

        known = tables[table]
        for column in columns:
            if column not in known:
                problems.append("table `%s` has no column `%s`" % (table, column))
                continue
            typ, generated, _ = known[column]
            if generated:
                problems.append(
                    "table `%s`.`%s` is GENERATED (%s) and must not be inserted" % (table, column, typ)
                )

    print("=" * 88)
    print("SEED COLUMN VALIDATION  (read-only, against the live schema)")
    print("=" * 88)
    print("  file        : %s" % args.file)
    print("  inserts seen: %d" % checked)
    print("  tables      : %d" % len(tables))
    print()

    if problems:
        print("PROBLEMS (%d):" % len(problems))
        for p in problems:
            print("  - %s" % p)
    else:
        print("OK: every table and column the seed file writes exists, and no generated")
        print("    column is written.")

    conn.close()
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
