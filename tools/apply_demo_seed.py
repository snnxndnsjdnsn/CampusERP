#!/usr/bin/env python3
"""Apply the demo seed to the Supabase project.

Usage:
    python tools/apply_demo_seed.py [--apply] [--dry-run] [--file PATH] [--json]

Without `--apply` the tool only prints the plan: which tables the seed writes
to, how many rows each of them holds right now and how many statements the
seed contains.  It never writes to the database in that mode.  `--apply` is the
only way to make it write, and it is deliberately explicit.

The seed (`tools/seed_demo.sql`) is idempotent: every insert is guarded by
`NOT EXISTS`, so a second run changes nothing.  The tool therefore refuses to
run twice in a row unless `--force` is given, and it always reports the row
count of every table before and after.

The whole seed runs in **one** transaction.  When a statement fails, the
transaction is rolled back and the database keeps the state it had before.

The seed writes to the demo tenant only.  It never touches the tables that
migration 064 seeds (the reference lookups), and it never writes an identity
or a generated column.

Connection settings (the environment wins over the defaults):

    SUPABASE_DB_HOST      aws-0-ap-southeast-1.pooler.supabase.com
    SUPABASE_DB_PORT      5432
    SUPABASE_DB_NAME      postgres
    SUPABASE_DB_USER      postgres.khqqfgqvwdxlqkncwtmh
    SUPABASE_DB_PASSWORD  <the project password>
    SUPABASE_DB_SSLMODE   require

`SIMS_DB_*` is accepted as an alias for `SUPABASE_DB_*`.  The password is
never stored in the repository.

Exit code 0 means "the plan is clean" or "the seed was applied", 1 means "a
statement failed" and 2 means "the tool was not configured correctly".
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

try:
    import psycopg2
except ImportError:  # pragma: no cover - the dependency is documented
    print("psycopg2 is required: pip install psycopg2-binary", file=sys.stderr)
    raise

from apply_migrations import connect, dsn, split_statements  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SEED = ROOT / "tools" / "seed_demo.sql"

#: `INSERT INTO <table> ...` - the seed only ever inserts.
INSERT_RE = re.compile(r"^\s*INSERT\s+INTO\s+(?:public\.)?([a-z_][a-z0-9_]*)", re.IGNORECASE)

#: Statements that would change the shape of the database.  The seed must not
#: contain any of them; the tool refuses to run if one slips in.
FORBIDDEN = (
    re.compile(r"^\s*DELETE\s+FROM", re.IGNORECASE),
    re.compile(r"^\s*TRUNCATE", re.IGNORECASE),
    re.compile(r"^\s*DROP\s+", re.IGNORECASE),
    re.compile(r"^\s*ALTER\s+TABLE", re.IGNORECASE),
)

#: An `UPDATE` is allowed, but only when it is scoped to the demo rows.  The
#: seed refreshes a handful of status columns that a trigger leaves alone, and
#: every one of those statements names a `DEMO-` key.
DEMO_MARKER = re.compile(r"'DEMO-[A-Z0-9-]+'")


def seed_statements(sql: str) -> list[str]:
    """The statements of the seed, with the comments stripped."""
    statements = []
    for statement in split_statements(sql):
        body = "\n".join(
            line for line in statement.splitlines() if not line.strip().startswith("--")
        ).strip()
        if not body:
            continue
        statements.append(body)
    return statements


def target_tables(statements: list[str]) -> list[str]:
    """The tables the seed inserts into, in the order they first appear."""
    seen: list[str] = []
    for statement in statements:
        match = INSERT_RE.match(statement)
        if match and match.group(1) not in seen:
            seen.append(match.group(1))
    return seen


def forbidden(statements: list[str]) -> list[str]:
    """The statements that would change more than the demo rows."""
    found = []
    for statement in statements:
        for pattern in FORBIDDEN:
            if pattern.match(statement):
                found.append(statement.splitlines()[0][:120])
                break
        else:
            if re.match(r"^\s*UPDATE\s+", statement, re.IGNORECASE) and not DEMO_MARKER.search(
                statement
            ):
                found.append(
                    "UPDATE without a demo key: " + statement.splitlines()[0][:100]
                )
    return found


def row_counts(cur, tables: list[str]) -> dict[str, int]:
    """The current row count of every table."""
    counts: dict[str, int] = {}
    for table in tables:
        cur.execute(f"SELECT count(*) FROM public.{table}")
        counts[table] = int(cur.fetchone()[0])
    return counts


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument(
        "--apply",
        action="store_true",
        help="write the seed (without it the tool only prints the plan)",
    )
    ap.add_argument("--dry-run", action="store_true", help="print the plan and stop (the default)")
    ap.add_argument("--file", default=str(SEED), help="the seed file")
    ap.add_argument(
        "--force",
        action="store_true",
        help="apply the seed even when the demo rows are already there",
    )
    ap.add_argument("--json", action="store_true", help="machine readable report")
    args = ap.parse_args()

    path = Path(args.file)
    if not path.is_file():
        print(f"the seed file does not exist: {path}", file=sys.stderr)
        return 2

    sql = path.read_text(encoding="utf-8")
    statements = seed_statements(sql)
    if not statements:
        print(f"the seed file contains no statement: {path}", file=sys.stderr)
        return 2

    unsafe = forbidden(statements)
    if unsafe:
        print("the seed contains a statement that changes more than rows:", file=sys.stderr)
        for line in unsafe:
            print(f"  {line}", file=sys.stderr)
        return 2

    tables = target_tables(statements)

    # --- the plan ------------------------------------------------------------
    connection_error = None
    before: dict[str, int] = {}
    try:
        conn = connect(readonly=True)
        try:
            cur = conn.cursor()
            before = row_counts(cur, tables)
        finally:
            conn.close()
    except SystemExit:
        raise
    except Exception as exc:  # the project cannot be reached
        connection_error = str(exc).strip().splitlines()[0]

    already = sum(1 for value in before.values() if value > 0)

    if not args.apply:
        if args.json:
            print(
                json.dumps(
                    {
                        "mode": "dry-run",
                        "database": dsn()["dbname"],
                        "file": path.name,
                        "statements": len(statements),
                        "tables": tables,
                        "row_counts": before,
                    },
                    indent=1,
                )
            )
            return 0
        print(f"seed file            : {path}")
        print(f"database             : {dsn()['dbname']} on {dsn()['host']}")
        if connection_error:
            print(f"the project is not reachable ({connection_error}), the plan is local only")
        print(f"{len(statements)} statement(s) into {len(tables)} table(s)")
        for table in tables:
            count = before.get(table)
            print(f"  {table:44s} {count if count is not None else '?'} row(s) now")
        print("")
        print("dry run: nothing was written. Use --apply to write the seed.")
        return 0

    # --- apply ---------------------------------------------------------------
    if already and not args.force:
        print(
            f"{already} of the {len(tables)} target tables already hold rows. The seed is "
            "idempotent, so a second run would change nothing - use --force if that is "
            "really what you want.",
            file=sys.stderr,
        )
        return 2

    conn = connect(readonly=False)
    inserted: dict[str, int] = {}
    try:
        cur = conn.cursor()
        for number, statement in enumerate(statements, start=1):
            try:
                cur.execute(statement)
            except Exception as exc:
                conn.rollback()
                print(
                    f"statement {number} failed, the transaction was rolled back:\n"
                    f"  {statement.splitlines()[0][:160]}\n"
                    f"  {str(exc).strip().splitlines()[0]}",
                    file=sys.stderr,
                )
                return 1
            match = INSERT_RE.match(statement)
            if match and cur.rowcount and cur.rowcount > 0:
                inserted[match.group(1)] = inserted.get(match.group(1), 0) + cur.rowcount
        conn.commit()

        after = row_counts(cur, tables)
    finally:
        conn.close()

    if args.json:
        print(
            json.dumps(
                {
                    "mode": "apply",
                    "database": dsn()["dbname"],
                    "file": path.name,
                    "statements": len(statements),
                    "inserted": inserted,
                    "before": before,
                    "after": after,
                },
                indent=1,
            )
        )
        return 0

    print(f"applied {len(statements)} statement(s) from {path.name}")
    print("")
    print(f"  {'table':44s} {'before':>8s} {'after':>8s} {'delta':>8s}")
    for table in tables:
        was = before.get(table, 0)
        now = after.get(table, 0)
        print(f"  {table:44s} {was:8d} {now:8d} {now - was:+8d}")
    print("")
    print(f"{sum(after.values()) - sum(before.values())} row(s) written.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
