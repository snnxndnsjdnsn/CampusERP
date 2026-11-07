#!/usr/bin/env python3
"""Compare the live catalogue with the expected catalogue.

Usage:
    python tools/compare_catalogue.py [--live PATH] [--expected PATH] [--json]
                                      [--max-report N] [--update-expected]

The live side is `tools/catalogue/live_catalogue.json`, the dump that
`node tools/validate/catalogue.mjs` writes from the Supabase project
`khqqfgqvwdxlqkncwtmh`.  The expected side is
`tools/catalogue/expected_catalogue.json`, the contract the project has to
satisfy.

The contract has three parts:

* `counts`          - the headline number of every kind of object;
* `public` and      - the same numbers per schema;
  `sims_private`
* `row_counts`      - the number of rows every seeded reference table holds;
* `objects`         - the optional inventory of the objects themselves,
                      grouped by kind (`tables`, `columns`, `functions`,
                      `policies`, `triggers`, `grants`, `sequences`).  Every
                      entry carries the fields that identify the object and a
                      SHA-256 of its definition, so a changed function body or
                      a changed policy expression is a difference too.

The report is grouped by kind.  A kind the contract carries an inventory for is
compared object by object (added / removed / changed); a kind the contract only
carries a count for is compared by that count.

Exit code 0 means "no differences", 1 means "the catalogues differ".

`--update-expected` rewrites the `objects` section of the contract from the
live catalogue.  It is the way to re-bless the contract after an intentional
schema change; the counts and the row counts are never touched by it.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIVE_CATALOGUE = ROOT / "tools" / "catalogue" / "live_catalogue.json"
EXPECTED_CATALOGUE = ROOT / "tools" / "catalogue" / "expected_catalogue.json"

#: The kinds the report is grouped by.
KINDS = ("tables", "columns", "functions", "policies", "triggers", "grants", "sequences")

#: The count keys of the contract, in the order they are printed.
COUNT_KEYS = (
    "tables",
    "views",
    "functions",
    "triggers",
    "policies",
    "rls_tables",
    "indexes",
    "sequences",
    "domains",
    "enums",
    "composites",
    "grants",
)

#: The count keys of the per schema part of the contract.
SCHEMA_COUNT_KEYS = (
    "tables",
    "views",
    "functions",
    "triggers",
    "policies",
    "rls_tables",
    "indexes",
    "sequences",
    "domains",
    "enums",
    "composites",
)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def sha256(text) -> str:
    """The SHA-256 of a definition, so that bodies can be compared cheaply."""
    if text is None:
        return ""
    return hashlib.sha256(str(text).encode("utf-8")).hexdigest()


def normalise(value):
    """Make two contract values comparable."""
    if value is None:
        return None
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value
    if isinstance(value, str):
        text = value.strip()
        if text.lstrip("-").isdigit():
            return int(text)
        return text
    if isinstance(value, list):
        return [normalise(v) for v in value]
    if isinstance(value, dict):
        return {k: normalise(v) for k, v in value.items()}
    return value


def live_counts(catalogue: dict) -> dict:
    """The headline counts of a catalogue, recomputed from its objects."""
    tables = catalogue.get("tables", [])
    return {
        "tables": len(tables),
        "views": len(catalogue.get("views", [])),
        "functions": len(catalogue.get("functions", [])),
        "triggers": len(catalogue.get("triggers", [])),
        "policies": len(catalogue.get("policies", [])),
        "rls_tables": sum(1 for t in tables if t.get("rls")),
        "indexes": len(catalogue.get("indexes", [])),
        "sequences": len(catalogue.get("sequences", [])),
        "domains": len(catalogue.get("domains", [])),
        "enums": len(catalogue.get("enums", [])),
        "composites": len(catalogue.get("composites", [])),
        "grants": len(catalogue.get("grants", [])),
    }


def schema_counts(catalogue: dict, schema: str) -> dict:
    """The counts of one schema of a catalogue."""

    def rows(key):
        return [row for row in catalogue.get(key, []) if row.get("schema") == schema]

    return {
        "tables": len(rows("tables")),
        "views": len(rows("views")),
        "functions": len(rows("functions")),
        "triggers": len(rows("triggers")),
        "policies": len(rows("policies")),
        "rls_tables": sum(1 for t in rows("tables") if t.get("rls")),
        "indexes": len(rows("indexes")),
        "sequences": len(rows("sequences")),
        "domains": len(rows("domains")),
        "enums": len(rows("enums")),
        "composites": len(rows("composites")),
    }


# ---------------------------------------------------------------------------
# the inventory of the live catalogue
# ---------------------------------------------------------------------------
def inventory(catalogue: dict) -> dict:
    """The inventory of the live catalogue, grouped by kind.

    Every object becomes one entry: the key is its identity, the value the
    fields the contract compares.  Definitions (function bodies, policy
    expressions, trigger bodies) are stored as a SHA-256 so that the contract
    stays small while a changed body is still a difference.
    """
    tables: dict[str, dict] = {}
    columns: dict[str, dict] = {}

    for table in catalogue.get("tables", []):
        key = f"{table['schema']}.{table['name']}"
        tables[key] = {
            "rls": bool(table.get("rls")),
            "force_rls": bool(table.get("force_rls")),
            "columns": len(table.get("columns", [])),
            "constraints": len(table.get("constraints", [])),
        }
        for column in table.get("columns", []):
            column_key = f"{key}.{column['name']}"
            # The column level privileges live in `pg_attribute.attacl`, not in
            # `pg_class.relacl`, so they have to be compared separately.  The
            # live project grants `authenticated` SELECT per column; losing
            # that would make every direct table read fail.
            privileges = sorted(
                f"{p.get('grantee')}:{p.get('privilege')}:{bool(p.get('grantable'))}"
                for p in (column.get("privileges") or [])
            )
            columns[column_key] = {
                "type": column.get("type"),
                "not_null": bool(column.get("not_null")),
                "default": column.get("default"),
                "identity": column.get("identity") or "",
                "generated": column.get("generated") or "",
                "position": column.get("position"),
                "privileges": privileges,
            }

    functions = {
        f"{fn['schema']}.{fn['name']}({fn.get('args') or ''})": {
            "definition_sha256": sha256(fn.get("definition")),
        }
        for fn in catalogue.get("functions", [])
    }

    policies = {
        f"{p['schema']}.{p['table']}.{p['name']}": {
            "command": p.get("command"),
            "permissive": bool(p.get("permissive")),
            "roles": list(p.get("roles") or []),
            "using_sha256": sha256(p.get("using")),
            "with_check_sha256": sha256(p.get("with_check")),
        }
        for p in catalogue.get("policies", [])
    }

    triggers = {
        f"{t['schema']}.{t['table']}.{t['name']}": {
            "definition_sha256": sha256(t.get("definition")),
        }
        for t in catalogue.get("triggers", [])
    }

    grants = {
        f"{g['schema']}.{g['object']}.{g['grantee']}.{g['privilege']}": {
            "grantable": bool(g.get("grantable")),
        }
        for g in catalogue.get("grants", [])
    }

    sequences = {
        f"{s['schema']}.{s['name']}": {
            "type": s.get("type"),
            "start": s.get("start"),
            "min": s.get("min"),
            "max": s.get("max"),
            "increment": s.get("increment"),
            "cycle": bool(s.get("cycle")),
            "cache": s.get("cache"),
            "owned_by": s.get("owned_by"),
        }
        for s in catalogue.get("sequences", [])
    }

    return {
        "tables": tables,
        "columns": columns,
        "functions": functions,
        "policies": policies,
        "triggers": triggers,
        "grants": grants,
        "sequences": sequences,
    }


# ---------------------------------------------------------------------------
# the comparison
# ---------------------------------------------------------------------------
def diff_kind(kind: str, actual: dict, expected: dict) -> dict:
    """The differences of one kind.

    `added`   - the object is in the live catalogue but not in the contract;
    `removed` - the object is in the contract but not in the live catalogue;
    `changed` - the object is in both, but a field of it differs.
    """
    added = sorted(set(actual) - set(expected))
    removed = sorted(set(expected) - set(actual))
    changed = []
    for key in sorted(set(actual) & set(expected)):
        want = expected[key]
        have = actual[key]
        fields = []
        for field in sorted(want):
            if field not in have or normalise(have[field]) != normalise(want[field]):
                fields.append(field)
        if fields:
            changed.append(
                {
                    "key": key,
                    "fields": fields,
                    "expected": {f: want[f] for f in fields},
                    "actual": {f: have.get(f) for f in fields},
                }
            )
    return {"kind": kind, "added": added, "removed": removed, "changed": changed}


def compare(live: dict, expected: dict) -> dict:
    """Compare the two catalogues."""
    report: dict = {}

    # --- the headline counts ------------------------------------------------
    actual_counts = live_counts(live)
    count_diffs = []
    for key, want in expected.get("counts", {}).items():
        got = actual_counts.get(key)
        if got != want:
            count_diffs.append({"key": key, "expected": want, "actual": got})
    report["counts"] = count_diffs

    # --- the counts per schema ---------------------------------------------
    schema_diffs = []
    for schema, wanted in expected.items():
        if schema not in ("public", "sims_private") or not isinstance(wanted, dict):
            continue
        actual = schema_counts(live, schema)
        for key, want in wanted.items():
            got = actual.get(key)
            if got != want:
                schema_diffs.append(
                    {"schema": schema, "key": key, "expected": want, "actual": got}
                )
    report["schemas"] = schema_diffs

    # --- the row counts -----------------------------------------------------
    row_diffs = []
    actual_rows = live.get("row_counts", {})
    for table, want in expected.get("row_counts", {}).items():
        got = actual_rows.get(table)
        if got != want:
            row_diffs.append({"table": table, "expected": want, "actual": got})
    report["row_counts"] = row_diffs

    # --- the objects, grouped by kind ---------------------------------------
    actual_inventory = inventory(live)
    expected_objects = expected.get("objects", {}) or {}
    kinds = {}
    for kind in KINDS:
        actual = actual_inventory[kind]
        wanted = expected_objects.get(kind)
        if wanted is None:
            # The contract carries no inventory for this kind: compare the
            # count it does carry, if any.
            count = expected.get("counts", {}).get(kind)
            kinds[kind] = {
                "kind": kind,
                "mode": "count",
                "expected_count": count,
                "actual_count": len(actual),
                "added": [],
                "removed": [],
                "changed": [],
            }
            if count is not None and count != len(actual):
                kinds[kind]["count_mismatch"] = {"expected": count, "actual": len(actual)}
            continue
        if isinstance(wanted, list):
            wanted = {entry["key"]: entry for entry in wanted}
        diff = diff_kind(kind, actual, wanted)
        diff["mode"] = "objects"
        diff["expected_count"] = len(wanted)
        diff["actual_count"] = len(actual)
        kinds[kind] = diff
    report["kinds"] = kinds

    return report


def count_differences(report: dict) -> int:
    """The number of differences in the report."""
    total = len(report["counts"]) + len(report["schemas"]) + len(report["row_counts"])
    for kind in report["kinds"].values():
        total += len(kind["added"]) + len(kind["removed"]) + len(kind["changed"])
        if "count_mismatch" in kind:
            total += 1
    return total


# ---------------------------------------------------------------------------
# the report
# ---------------------------------------------------------------------------
def print_report(report: dict, live_path: Path, expected_path: Path, max_report: int) -> None:
    print(f"live catalogue    : {live_path}")
    print(f"expected catalogue: {expected_path}")
    print("")

    print("counts")
    if report["counts"]:
        for diff in report["counts"]:
            print(f"  DIFF {diff['key']}: expected {diff['expected']}, live {diff['actual']}")
    else:
        print("  OK   every count of the contract matches the live catalogue")
    print("")

    print("schemas")
    if report["schemas"]:
        for diff in report["schemas"]:
            print(
                f"  DIFF {diff['schema']}.{diff['key']}: "
                f"expected {diff['expected']}, live {diff['actual']}"
            )
    else:
        print("  OK   every per schema count of the contract matches the live catalogue")
    print("")

    print("row_counts")
    if report["row_counts"]:
        for diff in report["row_counts"]:
            print(
                f"  DIFF {diff['table']}: expected {diff['expected']} rows, "
                f"live {diff['actual']} rows"
            )
    else:
        print("  OK   every seeded table has the expected number of rows")
    print("")

    for kind in KINDS:
        entry = report["kinds"][kind]
        print(kind)
        if entry["mode"] == "count":
            if "count_mismatch" in entry:
                mismatch = entry["count_mismatch"]
                print(
                    f"  DIFF expected {mismatch['expected']} objects, "
                    f"live {mismatch['actual']} objects"
                )
            else:
                print(
                    f"  OK   {entry['actual_count']} object(s); "
                    "the contract carries a count for this kind only"
                )
            print("")
            continue
        differences = len(entry["added"]) + len(entry["removed"]) + len(entry["changed"])
        if not differences:
            print(f"  OK   {entry['actual_count']} object(s) match the contract")
            print("")
            continue
        print(f"  DIFF {differences} difference(s) in {entry['actual_count']} object(s)")
        for key in entry["added"][:max_report]:
            print(f"    added    {key}")
        for key in entry["removed"][:max_report]:
            print(f"    removed  {key}")
        for change in entry["changed"][:max_report]:
            print(f"    changed  {change['key']}: {', '.join(change['fields'])}")
            for field in change["fields"]:
                print(f"               expected {field} = {change['expected'][field]!r}")
                print(f"               live     {field} = {change['actual'][field]!r}")
        if len(entry["added"]) > max_report:
            print(f"    ... and {len(entry['added']) - max_report} more added")
        if len(entry["removed"]) > max_report:
            print(f"    ... and {len(entry['removed']) - max_report} more removed")
        if len(entry["changed"]) > max_report:
            print(f"    ... and {len(entry['changed']) - max_report} more changed")
        print("")


def update_expected(expected_path: Path, live: dict) -> int:
    """Refresh the `objects` section of the contract from the live catalogue."""
    expected = json.loads(expected_path.read_text(encoding="utf-8"))
    expected["objects"] = inventory(live)
    expected_path.write_text(
        json.dumps(expected, indent=1, ensure_ascii=True) + "\n", encoding="utf-8"
    )
    return sum(len(v) for v in expected["objects"].values())


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--live", default=str(LIVE_CATALOGUE), help="the live catalogue JSON")
    ap.add_argument("--expected", default=str(EXPECTED_CATALOGUE), help="the contract JSON")
    ap.add_argument("--json", action="store_true", help="machine readable report")
    ap.add_argument("--max-report", type=int, default=20, help="differences printed per kind")
    ap.add_argument(
        "--update-expected",
        action="store_true",
        help="rewrite the objects section of the contract from the live catalogue",
    )
    args = ap.parse_args()

    live_path = Path(args.live)
    expected_path = Path(args.expected)
    for path, what in ((live_path, "live catalogue"), (expected_path, "expected catalogue")):
        if not path.exists():
            print(f"{what} not found: {path}", file=sys.stderr)
            return 2

    live = json.loads(live_path.read_text(encoding="utf-8"))
    expected = json.loads(expected_path.read_text(encoding="utf-8"))

    if args.update_expected:
        written = update_expected(expected_path, live)
        print(
            f"updated the objects section of {expected_path} "
            f"({written} object(s) in {len(KINDS)} kind(s))"
        )
        if not args.json:
            print("run the comparison again to see the differences it now reports")
        return 0

    report = compare(live, expected)
    total = count_differences(report)

    if args.json:
        print(
            json.dumps(
                {
                    "live": str(live_path),
                    "expected": str(expected_path),
                    "differences": total,
                    "report": report,
                },
                indent=1,
            )
        )
        return 1 if total else 0

    print_report(report, live_path, expected_path, args.max_report)

    if total:
        print(f"FAILED - {total} difference(s) between the live and the expected catalogue")
        return 1
    print("OK - the live catalogue matches the expected catalogue")
    return 0


if __name__ == "__main__":
    sys.exit(main())
