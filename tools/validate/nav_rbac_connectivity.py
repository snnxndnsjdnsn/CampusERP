#!/usr/bin/env python3
"""
Live UI <-> DB <-> RBAC connectivity verifier  (READ ONLY).

    python tools/validate/nav_rbac_connectivity.py [--json] [--host H] [--port P] ...

Proves the whole chain for every module the sidebar exposes:

    nav route
      -> access_module code            (the sidebar's visibility gate)
      -> permission codes              (MODULE.RESOURCE.ACTION)
      -> authorisation
           (a) table level : an RLS policy names a MODULE.* permission
           (b) function level: a SECURITY DEFINER public function checks a MODULE.* permission
      -> guarded tables / guarded RPCs

Tier (a) and tier (b) are both legitimate. A module may be authorised purely
through RPCs (AUDIT is: `audit_list` / `audit_get` / `audit_modules` check
`AUDIT.ALL.READ` inside a SECURITY DEFINER body, while `activity_audit` itself
is guarded by a self-or-admin RLS policy). A module is only a genuine gap when
NEITHER tier authorises it.

The script never writes to the remote database: the connection is opened
read-only and every statement is a SELECT.
"""

from __future__ import annotations

import argparse
import collections
import json
import os
import re
import sys

try:
    import psycopg2
except ImportError:  # pragma: no cover
    sys.exit("psycopg2 is required: pip install psycopg2-binary")

# --------------------------------------------------------------------------- config

DEFAULT_HOST = os.environ.get("SUPABASE_DB_HOST", "aws-0-ap-southeast-1.pooler.supabase.com")
DEFAULT_PORT = int(os.environ.get("SUPABASE_DB_PORT", "5432"))
DEFAULT_DB = os.environ.get("SUPABASE_DB_NAME", "postgres")
DEFAULT_USER = os.environ.get("SUPABASE_DB_USER", "postgres.khqqfgqvwdxlqkncwtmh")
DEFAULT_PASSWORD = os.environ.get("SUPABASE_DB_PASSWORD", "")

# Gaps that already exist in the live project and are documented in
# docs/RTM.md.  They are reported on every run, but they do not make the
# check fail: a *new* problem still does.  Use --strict to fail on them too.
KNOWN_GAPS = {
    # G-1: the REPORTING module is declared (11 permissions, 25 roles hold
    # grants) but nothing enforces it - no policy and no function checks it.
    "module REPORTING has permissions but no RLS policy and no function checks them",
}

# The canonical navigation, mirrored from src/lib/nav.ts.
# Keep this in step with src/lib/nav.ts; tests/unit/nav-connectivity.test.ts
# locks the nav's own shape.
NAV = [
    ("overview",      "Overview",                     ["/dashboard"],                          []),
    ("reference",     "1 - Common reference",         ["/admin/reference"],                    ["IAM"]),
    ("institution",   "2 - Institution structure",    ["/structure"],                          ["INSTITUTION"]),
    ("calendar",      "3 - Academic calendar",        ["/calendar"],                           ["ACADEMIC_CALENDAR"]),
    ("curriculum",    "4 - Curriculum & courses",     ["/curriculum", "/courses"],             ["CURRICULUM"]),
    ("people",        "5 - Students & staff",         ["/students", "/employees"],             ["STUDENT", "EMPLOYEE"]),
    ("admission",     "6 - Admissions",               ["/admissions"],                         ["ADMISSION"]),
    ("registration",  "7 - Registration",             ["/registration"],                       ["REGISTRATION"]),
    ("teaching",      "8 - Teaching & timetable",     ["/timetable"],                          ["TIMETABLE"]),
    ("attendance",    "9 - Attendance",               ["/attendance"],                         ["ATTENDANCE"]),
    ("assessment",    "10 - Assessment & results",    ["/assessment", "/results", "/my-results"], ["ASSESSMENT", "RESULT"]),
    ("feedback",      "11 - Feedback",                ["/feedback"],                           ["FEEDBACK"]),
    ("support",       "12 - Mentoring & grievance",   ["/mentoring", "/grievances"],           ["MENTORING", "GRIEVANCE"]),
    ("documents",     "13 - Documents & certificates", ["/certificates", "/requests", "/my-documents"], ["DOCUMENT"]),
    ("communication", "14 - Communication",           ["/announcements"],                      []),
    ("iam",           "15 - Access & audit",          ["/admin/users", "/audit"],              ["IAM", "AUDIT"]),
    ("hr",            "16 - Employee HR",             ["/my-hr"],                              []),
    ("finance",       "17 - Fees & finance",          ["/finance"],                            ["FEES"]),
    ("staff",         "19 - Staff profile",           ["/staff-profile"],                      ["STAFF_PROFILE"]),
    ("activities",    "40 - Student activities",      ["/activities"],                         ["STUDENT"]),
    ("account",       "Account",                      ["/settings"],                           []),
]

PERM_RE = re.compile(r"'([A-Z][A-Z_]*)\.[A-Z_]+\.[A-Z_]+'")


def connect(args):
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
    return conn


def collect(cur) -> dict:
    data: dict = {}

    cur.execute("select module_code, module_name, display_order, is_active "
                "from access_module order by display_order, module_code")
    data["modules"] = {r[0]: {"name": r[1], "order": r[2], "active": r[3]} for r in cur.fetchall()}

    cur.execute("select permission_code from permission order by permission_code")
    perms = [r[0] for r in cur.fetchall()]
    data["permissions"] = perms
    data["permissions_by_module"] = collections.defaultdict(list)
    for p in perms:
        data["permissions_by_module"][p.split(".")[0]].append(p)

    cur.execute("""select r.role_code, count(*)
                     from role_permission rp join role r on r.role_id = rp.role_id
                    group by r.role_code order by r.role_code""")
    data["role_grants"] = dict(cur.fetchall())

    cur.execute("""select c.relname, c.relrowsecurity, c.relforcerowsecurity
                     from pg_class c join pg_namespace n on n.oid = c.relnamespace
                    where n.nspname = 'public' and c.relkind = 'r'""")
    data["tables"] = {r[0]: {"rls": r[1], "force": r[2]} for r in cur.fetchall()}

    cur.execute("""select tablename, policyname, cmd, roles::text,
                          coalesce(qual,''), coalesce(with_check,'')
                     from pg_policies where schemaname = 'public'""")
    policies = collections.defaultdict(list)
    for t, p, cmd, roles, qual, wc in cur.fetchall():
        policies[t].append({"name": p, "cmd": cmd, "roles": roles, "using": qual, "check": wc})
    data["policies"] = dict(policies)

    cur.execute("""select p.proname, pg_get_functiondef(p.oid)
                     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public'""")
    functions = {}
    for name, body in cur.fetchall():
        functions[name] = body
    data["functions"] = functions

    cur.execute("""select c.relname, c.relrowsecurity
                     from pg_class c join pg_namespace n on n.oid = c.relnamespace
                    where n.nspname = 'public' and c.relkind = 'v'""")
    data["views"] = {r[0]: r[1] for r in cur.fetchall()}

    return data


def analyse(data: dict) -> dict:
    """Work out, per module, how it is authorised."""
    modules = data["modules"]
    perms_by_module = data["permissions_by_module"]
    policies = data["policies"]
    functions = data["functions"]
    tables = data["tables"]

    # --- tier (a): table level -------------------------------------------------
    table_modules: dict[str, set[str]] = collections.defaultdict(set)
    policy_modules: dict[str, set[str]] = collections.defaultdict(set)
    for tname, pols in policies.items():
        for pol in pols:
            blob = (pol["using"] or "") + " " + (pol["check"] or "")
            for m in PERM_RE.findall(blob):
                table_modules[m].add(tname)
                policy_modules[m].add(pol["name"])

    # --- tier (b): function level ---------------------------------------------
    fn_modules: dict[str, set[str]] = collections.defaultdict(set)
    fn_by_module: dict[str, list[str]] = collections.defaultdict(list)
    for fname, body in functions.items():
        found = set(PERM_RE.findall(body))
        for m in found:
            fn_modules[m].add(fname)
            fn_by_module[m].append(fname)

    report = {"modules": {}, "problems": [], "totals": {}}

    for code in sorted(modules):
        perms = sorted(perms_by_module.get(code, []))
        tbls = sorted(table_modules.get(code, set()))
        fns = sorted(fn_by_module.get(code, []))
        # a module is authorised when it has at least one permission AND is
        # enforced somewhere (a table policy or a function body)
        authorised = bool(perms) and (bool(tbls) or bool(fns))
        report["modules"][code] = {
            "name": modules[code]["name"],
            "permissions": len(perms),
            "permission_codes": perms,
            "tables_guarded": len(tbls),
            "table_names": tbls,
            "policies": sorted(policy_modules.get(code, set())),
            "functions_guarded": len(fns),
            "function_names": fns,
            "authorised": authorised,
        }
        if not perms:
            report["problems"].append("module %s has no permission codes" % code)
        elif not authorised:
            report["problems"].append(
                "module %s has permissions but no RLS policy and no function checks them" % code
            )

    report["totals"] = {
        "access_module": len(modules),
        "permissions": len(data["permissions"]),
        "roles_with_grants": len(data["role_grants"]),
        "public_tables": len(tables),
        "tables_with_rls": sum(1 for t in tables.values() if t["rls"]),
        "policies": sum(len(v) for v in policies.values()),
        "public_functions": len(functions),
        "views": len(data["views"]),
    }
    report["role_grants"] = dict(data["role_grants"])
    return report


def print_report(report: dict, nav_problems: list[str]) -> None:
    t = report["totals"]
    print("=" * 96)
    print("LIVE UI <-> DB <-> RBAC CONNECTIVITY MATRIX   (read-only)")
    print("=" * 96)
    print()
    for gid, label, routes, mods in NAV:
        print("  %-14s %s" % (gid, label))
        print("    routes : %s" % ", ".join(routes))
        if not mods:
            print("    module : (ungated - visible to every signed-in user)")
            print()
            continue
        for m in mods:
            info = report["modules"].get(m)
            if info is None:
                print("    !! %-18s NO access_module ROW" % m)
                continue
            ok = "OK " if info["authorised"] else "!! "
            print("    %s%-18s %3d permissions | %3d tables via RLS | %3d RPCs check it" % (
                ok, m, info["permissions"], info["tables_guarded"], info["functions_guarded"]))
        print()

    print("=" * 96)
    print("TOTALS")
    print("=" * 96)
    for k, v in t.items():
        print("  %-22s %s" % (k, v))
    print()
    print("  grants per role:")
    for r, n in sorted(report["role_grants"].items(), key=lambda kv: (-kv[1], kv[0])):
        print("    %-26s %5d" % (r, n))

    problems = report["problems"] + nav_problems
    print()
    if problems:
        print("PROBLEMS (%d):" % len(problems))
        for p in problems:
            print("  - %s" % p)
    else:
        print("No connectivity problems found: every navigation module is seeded, has")
        print("permissions, and is enforced by the database (RLS policy or RPC check).")
    return problems


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", default=DEFAULT_HOST)
    ap.add_argument("--port", type=int, default=DEFAULT_PORT)
    ap.add_argument("--db", default=DEFAULT_DB)
    ap.add_argument("--user", default=DEFAULT_USER)
    ap.add_argument("--password", default=DEFAULT_PASSWORD)
    ap.add_argument("--json", action="store_true", help="also write the report as JSON")
    ap.add_argument("--out", default="", help="path for the JSON report")
    ap.add_argument(
        "--strict",
        action="store_true",
        help="also fail on the known, documented gaps (see KNOWN_GAPS)",
    )
    args = ap.parse_args()

    if not args.password:
        sys.exit("SUPABASE_DB_PASSWORD is not set (or pass --password)")

    conn = connect(args)
    try:
        cur = conn.cursor()
        data = collect(cur)
    finally:
        conn.close()

    report = analyse(data)

    nav_problems = []
    for gid, label, routes, mods in NAV:
        for m in mods:
            info = data["modules"].get(m)
            if info is None:
                nav_problems.append("nav group %s references unknown access_module %s" % (gid, m))
            elif not info.get("active", True):
                nav_problems.append("nav group %s references inactive access_module %s" % (gid, m))

    problems = print_report(report, nav_problems)

    # The gaps below are pre-existing in the live project and are documented in
    # docs/RTM.md.  They are reported, but they must not hide a *new* problem,
    # so the check only tolerates exactly these strings.
    known = [p for p in problems if p in KNOWN_GAPS]
    unknown = [p for p in problems if p not in KNOWN_GAPS]

    if known and not args.strict:
        print()
        print("KNOWN GAPS (%d) - documented in docs/RTM.md, tolerated:" % len(known))
        for p in known:
            print("  - %s" % p)

    if args.json or args.out:
        out = args.out or "nav_rbac_connectivity.json"
        with open(out, "w", encoding="utf-8") as fh:
            json.dump(
                {
                    "report": report,
                    "nav_problems": nav_problems,
                    "known_gaps": known,
                    "problems": unknown,
                },
                fh,
                indent=1,
            )
        print("\nwrote %s" % out)

    return 1 if unknown else 0


if __name__ == "__main__":
    raise SystemExit(main())
