#!/usr/bin/env python3
"""Generate the RLS policy migration and the policy map.

`tools/rls/table_module.json` records, for every public table, the
`access_module` code that governs it.  The module is derived from the live
policies: a table belongs to the module of the permission its policy checks
(`ACADEMIC_CALENDAR.ALL.CONFIGURE` -> `ACADEMIC_CALENDAR`).  Tables whose
policy only checks `sims_private.is_active_member()` are resolved through the
body of the helper the policy calls, and the remaining lookup tables are
resolved by the explicit overrides below.

Usage:
    python tools/build_rls.py                 # rewrite 018 + docs/RLS_POLICY_MAP.md
    python tools/build_rls.py --write-map     # also rewrite tools/rls/table_module.json
    python tools/build_rls.py --check         # only report differences
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MIGRATIONS = ROOT / "supabase" / "migrations"
CATALOGUE = ROOT / "tools" / "catalogue" / "live_catalogue.json"
TABLE_MAP = ROOT / "tools" / "rls" / "table_module.json"
POLICY_MAP_DOC = ROOT / "docs" / "RLS_POLICY_MAP.md"

PERMISSION_RE = re.compile(r"'([A-Z][A-Z0-9_]*(?:\.[A-Z0-9_]+)+)'")

# Tables whose policy does not name a permission code.  The module is taken
# from the domain the table belongs to.
MODULE_OVERRIDES = {
    "concession_type": "FEES",
    "counselling_session": "MENTORING",
    "fee_category": "FEES",
    "fee_type": "FEES",
    "installment_plan": "FEES",
    "institution": "INSTITUTION",
    "late_fee_rule": "FEES",
    "late_fee_slab": "FEES",
    "payment_mode": "FEES",
    "scholarship_scheme": "FEES",
}


def load_catalogue(path: Path = CATALOGUE) -> dict:
    if not path.exists():
        raise SystemExit(
            f"catalogue not found: {path}\n"
            "Run `python tools/dump_catalogue.py --data` against the live project first."
        )
    return json.loads(path.read_text(encoding="utf-8"))


def permission_codes(text: str) -> set[str]:
    return {m.group(1) for m in PERMISSION_RE.finditer(text or "")}


def derive_table_modules(cat: dict) -> dict[str, str]:
    """table -> access_module code, derived from the live policies."""
    helpers = {f["name"]: f["definition"] for f in cat["functions"]}
    modules: dict[str, str] = {}
    for p in cat["policies"]:
        if p["schema"] != "public":
            continue
        expr = f"{p['using'] or ''} {p['with_check'] or ''}"
        codes = permission_codes(expr)
        if codes:
            mods = {c.split(".")[0] for c in codes}
            if len(mods) > 1:
                raise SystemExit(
                    f"table {p['table']} is governed by more than one module: {sorted(mods)}"
                )
            modules.setdefault(p["table"], mods.pop())
            continue
        # no permission code in the policy itself: look at the helper it calls
        for m in re.finditer(r"sims_private\.([a-z_][a-z0-9_]*)\s*\(", expr):
            body = helpers.get(m.group(1), "")
            hmods = {c.split(".")[0] for c in permission_codes(body)}
            if len(hmods) == 1:
                modules.setdefault(p["table"], hmods.pop())
                break
    for table, module in MODULE_OVERRIDES.items():
        modules.setdefault(table, module)
    # every public table must end up with a module
    for t in cat["tables"]:
        if t["schema"] == "public" and t["name"] not in modules:
            raise SystemExit(f"no access module could be derived for table {t['name']}")
    return dict(sorted(modules.items()))


def load_table_map(path: Path = TABLE_MAP) -> dict[str, str]:
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    return data.get("tables", data)


def render_policies(cat: dict, table_map: dict[str, str] | None = None) -> list[str]:
    """Render every policy of the catalogue as a CREATE POLICY statement."""
    if table_map is None:
        table_map = load_table_map()
    out: list[str] = []
    for p in cat["policies"]:
        # PostgreSQL wants a plain comma separated role list: `TO a, b`.
        roles = ", ".join(p["roles"]) if p["roles"] else "PUBLIC"
        permissive = "PERMISSIVE" if p.get("permissive", True) else "RESTRICTIVE"
        stmt = (
            f"CREATE POLICY {p['name']} ON {p['schema']}.{p['table']} "
            f"AS {permissive} FOR {p['command']} TO {roles}"
        )
        if p.get("using") is not None:
            stmt += f" USING ({p['using']})"
        if p.get("with_check") is not None:
            stmt += f" WITH CHECK ({p['with_check']})"
        out.append(stmt + ";")
    return out


def policy_requirements(cat: dict) -> dict[str, list[dict]]:
    """table -> [{policy, command, permissions, using, with_check}]"""
    helpers = {f["name"]: f["definition"] for f in cat["functions"]}
    out: dict[str, list[dict]] = {}
    for p in cat["policies"]:
        expr = f"{p['using'] or ''} {p['with_check'] or ''}"
        codes = set(permission_codes(expr))
        if not codes:
            for m in re.finditer(r"sims_private\.([a-z_][a-z0-9_]*)\s*\(", expr):
                codes |= permission_codes(helpers.get(m.group(1), ""))
        out.setdefault(p["table"], []).append({
            "policy": p["name"],
            "command": p["command"],
            "permissions": sorted(codes),
            "using": p["using"],
            "with_check": p["with_check"],
        })
    return out


def render_policy_map(cat: dict, table_map: dict[str, str]) -> str:
    reqs = policy_requirements(cat)
    lines: list[str] = []
    lines.append("# RLS policy map")
    lines.append("")
    lines.append("<!-- GENERATED FILE - do not edit by hand. Regenerate with `python tools/build_rls.py`. -->")
    lines.append("")
    lines.append(
        "Every public table, the policies that guard it and the permission code each "
        "policy requires.  A policy without a permission code only checks that the "
        "caller is an active member of the institution."
    )
    lines.append("")
    lines.append("| Table | Module | Policy | Command | Permission required |")
    lines.append("|---|---|---|---|---|")
    for t in cat["tables"]:
        if t["schema"] != "public":
            continue
        name = t["name"]
        module = table_map.get(name, "")
        policies = reqs.get(name, [])
        if not policies:
            lines.append(f"| `{name}` | {module} | - | - | - |")
            continue
        for i, p in enumerate(policies):
            perms = ", ".join(f"`{c}`" for c in p["permissions"]) or "_membership only_"
            table_cell = f"`{name}`" if i == 0 else ""
            module_cell = module if i == 0 else ""
            lines.append(
                f"| {table_cell} | {module_cell} | `{p['policy']}` | {p['command']} | {perms} |"
            )
    lines.append("")
    lines.append("## Totals")
    lines.append("")
    lines.append(f"- public tables: {sum(1 for t in cat['tables'] if t['schema'] == 'public')}")
    lines.append(f"- policies: {len(cat['policies'])}")
    lines.append(f"- modules referenced: {len({m for m in table_map.values() if m})}")
    lines.append("")
    return "\n".join(lines)


def render_policy_migration(cat: dict, table_map: dict[str, str]) -> str:
    header = """-- =============================================================================================
-- 018. rls_policies
-- ---------------------------------------------------------------------------------------------
-- GENERATED FILE - do not edit by hand.
-- Regenerate with: npm run migrate:build   (python tools/translate.py && python tools/build_migrations.py)
--
-- Source of truth: the live Supabase catalogue (tools/catalogue/live_catalogue.json),
-- dumped read-only from project khqqfgqvwdxlqkncwtmh by tools/dump_catalogue.py.
--
-- Every RLS policy of the live catalogue.
--
-- Generated by tools/build_rls.py from tools/rls/table_module.json and the
-- live catalogue.  Each policy names the permission code it requires, so the
-- policy file and the access matrix cannot drift apart.
-- =============================================================================================

"""
    body = "\n".join(render_policies(cat, table_map))
    return header + body + "\n"


def write_policy_migration(cat: dict, table_map: dict[str, str]) -> Path:
    path = MIGRATIONS / "018_rls_policies.sql"
    path.write_text(render_policy_migration(cat, table_map), encoding="utf-8", newline="\n")
    return path


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--catalogue", default=str(CATALOGUE))
    ap.add_argument("--map", default=str(TABLE_MAP))
    ap.add_argument("--write-map", action="store_true")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    cat = load_catalogue(Path(args.catalogue))
    derived = derive_table_modules(cat)
    stored = load_table_map(Path(args.map))

    if args.write_map:
        Path(args.map).parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "_comment": (
                "table -> access_module mapping. The module is the one of the permission "
                "the table's RLS policy checks; see tools/build_rls.py for the derivation."
            ),
            "tables": derived,
        }
        Path(args.map).write_text(
            json.dumps(payload, indent=1, sort_keys=False) + "\n", encoding="utf-8", newline="\n"
        )
        print(f"wrote {args.map} ({len(derived)} tables)")
        stored = derived

    drift = {k: (stored.get(k), derived[k]) for k in derived if stored.get(k) != derived[k]}
    if drift:
        print("table_module.json is out of date:")
        for k, (old, new) in sorted(drift.items()):
            print(f"  {k}: {old!r} -> {new!r}")
        if not args.write_map:
            return 1

    migration_path = MIGRATIONS / "018_rls_policies.sql"
    expected_migration = render_policy_migration(cat, derived)
    expected_doc = render_policy_map(cat, derived)

    if args.check:
        stale = []
        for path, expected in ((migration_path, expected_migration), (POLICY_MAP_DOC, expected_doc)):
            if not path.exists():
                stale.append(f"{path} is missing")
                continue
            actual = path.read_text(encoding="utf-8")
            if actual != expected:
                stale.append(f"{path} differs from the generated content")
        if stale:
            print("generated RLS artefacts are out of date:")
            for line in stale:
                print(f"  {line}")
            return 1
        print(f"OK - {migration_path.name} and {POLICY_MAP_DOC.name} match the live catalogue")
    else:
        write_policy_migration(cat, derived)
        POLICY_MAP_DOC.parent.mkdir(parents=True, exist_ok=True)
        POLICY_MAP_DOC.write_text(expected_doc, encoding="utf-8", newline="\n")
        print(f"wrote {migration_path}")
        print(f"wrote {POLICY_MAP_DOC}")
    print(f"{len(derived)} public tables mapped to {len(set(derived.values()))} access modules")
    return 0


if __name__ == "__main__":
    sys.exit(main())
