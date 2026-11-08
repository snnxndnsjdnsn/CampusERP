#!/usr/bin/env python3
"""Regenerate `supabase/migrations/*.sql` from the live Supabase catalogue.

The project's migration directory was lost.  The live database is the
authoritative source of truth, so this script turns the catalogue dump
(`tools/catalogue/live_catalogue.json`, produced by `tools/dump_catalogue.py`)
back into the 64 migration files that the remote project has applied
(001..063) plus the already existing `064_required_reference_seeds.sql`
and `065_schema_indexes.sql`.

What is reconstructed and what is not
--------------------------------------
* 001  domains, composite types, every table (FK dependency order), every
       index and every view.
* 002..014  the seeded reference rows, split by theme.  Only the rows that
       the live database really contains are emitted, with explicit primary
       keys and `ON CONFLICT DO NOTHING`.
* 015  identity/sequence resync to `max(id) + 1`.
* 016  `ENABLE ROW LEVEL SECURITY` for every table that has it in the live
       catalogue.
* 017  the `sims_private` schema and the helper functions.
* 018  every RLS policy (delegated to `tools/build_rls.py`).
* 019  `my_context()` and the public read RPCs.
* 020  every trigger.
* 021  every grant plus the remaining public functions.
* 022..063  version placeholders: the original per-feature split cannot be
       recovered from a catalogue dump, so the content was consolidated into
       017/018/019/020/021 while the file names were kept so that the
       already-applied remote migration history stays aligned.

The MySQL reference
-------------------
`tools/translate.py` parses `SIMS-DatabaseWithoutLessonPlan.sql` and writes
the normalised description of the functional specification to
`tools/catalogue/mysql_reference.json`.  This script consumes that document:
it checks that every table and every column of the MySQL source exists in the
live catalogue (the build fails when they drift apart) and it names the MySQL
module section a migration belongs to in the header of the file.

The script is idempotent: running it twice produces byte-identical files.

Usage:
    python tools/build_migrations.py [--catalogue PATH] [--seed PATH]
                                     [--reference PATH] [--check]
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
SEED_DATA = ROOT / "tools" / "catalogue" / "live_seed_data.json"
# The normalised MySQL reference document.  It is produced by
# tools/translate.py and describes the functional specification the live
# PostgreSQL database implements.
REFERENCE = ROOT / "tools" / "catalogue" / "mysql_reference.json"

# ---------------------------------------------------------------------------
# the migration file names the remote project has applied (001..063).
# 064_required_reference_seeds.sql and 065_schema_indexes.sql are hand
# written and are never touched.
# ---------------------------------------------------------------------------
SEED_FILES = {
    "002": "academic_calendar_and_curriculum",
    "003": "student_employee_admission_registration",
    "004": "teaching_attendance_assessment_feedback",
    "005": "documents_and_communication",
    "006": "identity_rbac_audit",
    "007": "employee_hr_profile",
    "008": "student_finance",
    "009": "indexes_and_file_metadata",
    "010": "staff_profile_and_research",
    "011": "evidence_and_seed_data",
    "012": "staff_views_and_indexes",
    "013": "student_activity_and_evidence",
    "014": "triggers_and_integrity",
}

# ---------------------------------------------------------------------------
# the objects the hand written migrations own
# ---------------------------------------------------------------------------
# 065 creates `public.schema_indexes` and 066 creates the admin editing surface.
# The catalogue is a dump of the live database, so it carries those objects as
# well - and a build from the catalogue would copy them into the generated
# files, where the hand written migration creates them a second time.  They are
# therefore removed from the catalogue before the build reads it.
#
# Keep this list in step with the hand written migrations: every function and
# every trigger they create belongs here, otherwise the migration set creates
# the same object twice.
HAND_WRITTEN_FUNCTIONS = {
    ("public", "schema_indexes"),  # 065_schema_indexes.sql
    ("sims_private", "admin_table_def"),  # 066_admin_editing.sql
    ("sims_private", "admin_lookup_def"),
    ("sims_private", "admin_holds"),
    ("sims_private", "admin_scope_value"),
    ("sims_private", "admin_can"),
    ("public", "admin_table_list"),
    ("public", "admin_table_schema"),
    ("public", "admin_table_save"),
    ("public", "admin_table_delete"),
    ("public", "admin_lookup_options"),
}

HAND_WRITTEN_TRIGGERS = {
    ("public", "trg_time_slot_audit"),  # 066_admin_editing.sql
    ("public", "trg_room_audit"),
}

CONSOLIDATED_FILES = {
    "022": "admissions",
    "023": "employee_registration",
    "024": "academic_setup_audit",
    "025": "institution_structure",
    "026": "course_catalogue_audit",
    "027": "admissions",
    "028": "registration_integrity",
    "029": "definer_anchor_lookups",
    "030": "registration_read_rpcs",
    "031": "attendance",
    "032": "assessment_and_results",
    "033": "assessment_read_helpers",
    "034": "finance_read_helpers",
    "035": "timetable",
    "036": "dashboard_metrics",
    "037": "feedback",
    "038": "mentoring",
    "039": "grievance",
    "040": "communication",
    "041": "iam_admin_and_audit_viewer",
    "042": "student_documents",
    "043": "student_activities",
    "044": "staff_profile",
    "045": "account_features",
    "046": "record_sections_and_reference_data",
    "047": "finance_receipts_and_holds",
    "048": "my_dashboard",
    "049": "user_provisioning",
    "050": "revoke_trigger_function_execute",
    "051": "permission_memo",
    "052": "role_access_and_receipt_format",
    "053": "finance_benefits_adjustments",
    "054": "employee_sensitive_and_documents",
    "055": "research_leftovers",
    "056": "mfa_recovery_codes",
    "057": "permission_overrides_admin",
    "058": "link_users_and_mfa_policy",
    "059": "announcement_attachments",
    "060": "certificate_requests",
    "061": "fee_structures",
    "062": "hold_enforcement",
    "063": "competencies_doc_rules_service_requests",
}

# Which seeded table belongs to which seed migration.  Only tables that the
# live database actually contains are listed; every other table stays empty
# (the live database has no rows for it).
SEED_TABLE_MAP = {
    "002": [
        "academic_year", "academic_term", "semester", "curriculum_scheme",
        "curriculum_course", "course_catalog", "course_category",
        "course_prerequisite", "programme", "programme_specialization",
    ],
    "003": [
        "student", "student_programme_enrolment", "student_user_account",
        "employee", "employee_assignment", "employee_user_account",
        "user_account", "user_role_assignment", "user_permission_override",
        "admission_applicant", "admission_application", "admission_category",
        "admission_payment",
    ],
    "004": [
        "course_offering", "course_offering_section",
        "course_offering_section_student", "faculty_course_assignment",
        "class_session", "student_attendance", "attendance_correction_request",
        "attendance_status", "assessment_component", "assessment_event",
        "student_assessment_mark", "feedback_cycle", "feedback_questionnaire",
        "feedback_question", "feedback_response",
    ],
    "005": [
        "document_type", "announcement_type", "announcement",
        "announcement_attachment", "file_object", "evidence_document",
        "evidence_document_version", "evidence_tag",
    ],
    "006": [
        "access_module", "access_resource", "access_action", "permission",
        "role", "role_permission", "role_type", "role_delegation",
        "activity_audit", "login_audit",
    ],
    "007": [
        "staff_type", "staff_category", "employment_source", "designation",
        "qualification_level", "employee_document_category",
        "awarding_body_type", "previous_organization_type",
        "education_institution_type", "study_mode", "external_organization_type",
        "organization_type", "industry_sector",
    ],
    "008": [
        "fee_category", "payment_mode", "fee_type", "concession_type",
        "scholarship_scheme", "installment_plan", "financial_ledger_account",
    ],
    "009": [],
    "010": [
        "publication_type", "journal_type", "indexing_agency", "metric_type",
        "funding_type", "research_status", "training_program_type",
        "membership_type", "award_category", "conference_contribution_type",
        "professional_contribution_type", "participation_level",
    ],
    "011": [
        "evidence_type", "activity_type", "approval_status",
        "verification_status", "confidentiality_level", "event_mode",
        "activity_evidence_requirement",
    ],
    "012": [],
    "013": [
        "student_activity_type", "cocurricular_category",
        "extracurricular_category", "certificate_type",
    ],
    "014": [],
}

# The MySQL module section every consolidated migration belongs to.  The
# numbers are the module sections of `SIMS-DatabaseWithoutLessonPlan.sql`;
# `tools/build_migrations.py` checks them against the reference document that
# `tools/translate.py` produces, so a renamed module breaks the build.
CONSOLIDATED_MODULE = {
    "022": ["6"],
    "023": ["5"],
    "024": ["3", "4"],
    "025": ["2"],
    "026": ["4"],
    "027": ["6"],
    "028": ["7"],
    "029": ["39"],
    "030": ["7"],
    "031": ["9"],
    "032": ["10"],
    "033": ["10"],
    "034": ["17"],
    "035": ["8"],
    "036": ["37"],
    "037": ["11"],
    "038": ["12"],
    "039": ["12"],
    "040": ["14"],
    "041": ["15"],
    "042": ["13"],
    "043": ["40"],
    "044": ["19"],
    "045": ["15"],
    "046": ["35"],
    "047": ["17"],
    "048": ["37"],
    "049": ["15"],
    "050": ["39"],
    "051": ["36"],
    "052": ["15"],
    "053": ["17"],
    "054": ["16"],
    "055": ["19"],
    "056": ["15"],
    "057": ["15"],
    "058": ["15"],
    "059": ["14"],
    "060": ["13"],
    "061": ["17"],
    "062": ["17A"],
    "063": ["34", "40"],
}

# Tables whose rows are operational data (created by the bootstrap script and
# by real logins), not reference seed data.  They are deliberately not seeded.
RUNTIME_TABLES = {
    "activity_audit", "login_audit", "user_account", "user_role_assignment",
    "user_permission_override", "auth_identity_map", "student", "employee",
    "announcement_author", "notification_dismissal", "receipt_counter",
    "mfa_recovery_attempt", "mfa_recovery_code", "mfa_required_role",
    "feedback_submission", "student_service_request",
}

BANNER = """-- =============================================================================================
-- {num}. {title}
-- ---------------------------------------------------------------------------------------------
-- GENERATED FILE - do not edit by hand.
-- Regenerate with: npm run migrate:build   (python tools/translate.py && python tools/build_migrations.py)
--
-- Source of truth: the live Supabase catalogue (tools/catalogue/live_catalogue.json),
-- dumped read-only from project khqqfgqvwdxlqkncwtmh by tools/dump_catalogue.py.
-- =============================================================================================
"""


# ---------------------------------------------------------------------------
# SQL literal helpers
# ---------------------------------------------------------------------------
def ident(name: str) -> str:
    if re.fullmatch(r"[a-z_][a-z0-9_]*", name or ""):
        return name
    return '"' + name.replace('"', '""') + '"'


def terminate(statement: str) -> str:
    """End a catalogue statement with exactly one semicolon.

    `pg_get_functiondef()` and `pg_get_triggerdef()` return the statement
    without its terminating semicolon, so every emitted definition has to add
    it back - otherwise the next `CREATE` is parsed as part of the previous
    statement and the whole file fails to load.
    """
    text = statement.rstrip()
    if not text:
        return ""
    return text if text.endswith(";") else text + ";"


def literal(value, coltype: str = "text") -> str:
    """Render a python value as a PostgreSQL literal for a column of `coltype`."""
    if value is None:
        return "NULL"
    if isinstance(value, dict) and set(value) == {"__decimal__"}:
        return value["__decimal__"]
    if isinstance(value, bool):
        return "TRUE" if value else "FALSE"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return repr(value)
    if isinstance(value, (dict, list)):
        # jsonb / json
        return "'" + json.dumps(value, sort_keys=False).replace("'", "''") + "'::jsonb"
    text = str(value)
    if coltype.endswith("[]"):
        return "'" + text.replace("'", "''") + "'::" + coltype
    if coltype == "jsonb" or coltype == "json":
        return "'" + text.replace("'", "''") + "'::jsonb"
    escaped = text.replace("'", "''")
    if coltype in ("uuid",):
        return "'" + escaped + "'::uuid"
    if coltype in ("date",):
        return "'" + escaped + "'::date"
    if coltype in ("timestamp with time zone", "timestamptz"):
        return "'" + escaped + "'::timestamptz"
    if coltype in ("timestamp without time zone", "timestamp"):
        return "'" + escaped + "'::timestamp"
    if coltype in ("time with time zone", "time"):
        return "'" + escaped + "'::time"
    return "'" + escaped + "'"


# ---------------------------------------------------------------------------
# catalogue helpers
# ---------------------------------------------------------------------------
def load_reference(path: Path) -> dict:
    """The normalised MySQL reference document of `tools/translate.py`."""
    if not path.exists():
        raise SystemExit(
            f"{path} is missing - run `python tools/translate.py` first"
        )
    return json.loads(path.read_text(encoding="utf-8"))


def cross_check_reference(cat: dict, ref: dict) -> dict:
    """Compare the live catalogue with the MySQL reference document.

    The migration set reconstructs the live PostgreSQL database; the MySQL
    file is the functional specification that database implements.  Both have
    to describe the same tables with the same columns, otherwise the rebuild
    has drifted away from the specification.  The build fails when they do.
    """
    live_tables = {t["name"]: t for t in cat["tables"] if t["schema"] == "public"}
    missing_tables: list[str] = []
    missing_columns: list[str] = []
    for table in ref["tables"]:
        live = live_tables.get(table["name"])
        if live is None:
            missing_tables.append(table["name"])
            continue
        live_columns = {c["name"] for c in live["columns"]}
        for column in table["columns"]:
            if column["name"] not in live_columns:
                missing_columns.append(f"{table['name']}.{column['name']}")
    return {
        "source": ref["source"],
        "tables": len(ref["tables"]),
        "columns": sum(len(t["columns"]) for t in ref["tables"]),
        "missing_tables": missing_tables,
        "missing_columns": missing_columns,
    }


def module_titles(ref: dict) -> dict[str, list[str]]:
    """The titles of the MySQL module sections, keyed by their number."""
    titles: dict[str, list[str]] = {}
    for module in ref["modules"]:
        titles.setdefault(module["number"], []).append(module["title"])
    return titles


def module_note(ref: dict, numbers: list[str]) -> list[str]:
    """The header lines that name the MySQL module sections.

    The numbers come from the reference document, so a module that does not
    exist there stops the build instead of producing a wrong header.
    """
    titles = module_titles(ref)
    lines: list[str] = []
    for number in numbers:
        if number not in titles:
            raise SystemExit(
                f"MySQL module {number} does not exist in the reference document"
            )
        for title in titles[number]:
            lines.append(f"-- MySQL module {number}: {title}")
    return lines


def seed_modules(ref: dict, tables: list[str]) -> list[str]:
    """The MySQL module sections the tables of a seed migration belong to."""
    module_of = {t["name"]: t.get("module") for t in ref["tables"]}
    numbers: list[str] = []
    for table in tables:
        number = module_of.get(table)
        if number and number not in numbers:
            numbers.append(number)
    return numbers


def load_catalogue(path: Path) -> dict:
    if not path.exists():
        raise SystemExit(
            f"catalogue not found: {path}\n"
            "Run `python tools/dump_catalogue.py --data` against the live project first."
        )
    return json.loads(path.read_text(encoding="utf-8"))


def strip_hand_written(cat: dict) -> dict:
    """Remove the objects the hand written migrations own from the catalogue.

    The catalogue is a dump of the live database, so it carries the functions
    and the triggers that 065 and 066 create.  A build that copied them into
    the generated files would create every one of them twice when the set is
    applied to a fresh database - once by the hand written migration and once
    by the generated one.  The functions are dropped, the triggers are dropped
    and the grants that belong to the dropped functions are dropped with them.
    """
    fn_names = {name for _schema, name in HAND_WRITTEN_FUNCTIONS}

    cat["functions"] = [
        f for f in cat["functions"]
        if (f["schema"], f["name"]) not in HAND_WRITTEN_FUNCTIONS
    ]
    cat["triggers"] = [
        t for t in cat["triggers"]
        if (t["schema"], t["name"]) not in HAND_WRITTEN_TRIGGERS
    ]
    cat["grants"] = [
        g for g in cat["grants"]
        if not (
            "(" in g["object"]
            and g["object"].split("(", 1)[0] in fn_names
        )
    ]
    return cat


def table_map(cat: dict) -> dict[tuple[str, str], dict]:
    return {(t["schema"], t["name"]): t for t in cat["tables"]}


def fk_target(constraint: dict) -> tuple[str, str] | None:
    m = re.search(r"REFERENCES\s+([\w\".]+)\s*\(", constraint["definition"])
    if not m:
        return None
    ref = m.group(1)
    if "." in ref:
        schema, name = ref.split(".", 1)
        return schema.strip('"'), name.strip('"')
    return ("public", ref.strip('"'))


def order_tables(cat: dict) -> list[dict]:
    """Topologically order the tables by their foreign-key dependencies."""
    tables = cat["tables"]
    by_key = {(t["schema"], t["name"]): t for t in tables}
    deps: dict[tuple[str, str], set[tuple[str, str]]] = {k: set() for k in by_key}
    for t in tables:
        key = (t["schema"], t["name"])
        for c in t["constraints"]:
            if c["type"] != "f":
                continue
            target = fk_target(c)
            if target is None or target not in by_key or target == key:
                continue
            deps[key].add(target)
    ordered: list[dict] = []
    done: set[tuple[str, str]] = set()
    remaining = sorted(by_key)
    while remaining:
        ready = [k for k in remaining if deps[k] <= done]
        if not ready:
            # a cycle: break it deterministically
            ready = [remaining[0]]
        for key in ready:
            ordered.append(by_key[key])
            done.add(key)
            remaining.remove(key)
    return ordered


def function_key(fn: dict) -> str:
    return f"{fn['schema']}.{fn['name']}"


def function_callees(cat: dict) -> dict[str, set[str]]:
    """Map every function to the functions it calls (by schema.name)."""
    names = {function_key(f) for f in cat["functions"]}
    # also index by bare name so unqualified calls resolve
    bare: dict[str, set[str]] = {}
    for f in cat["functions"]:
        bare.setdefault(f["name"], set()).add(function_key(f))
    out: dict[str, set[str]] = {}
    for f in cat["functions"]:
        body = f["definition"]
        calls: set[str] = set()
        for m in re.finditer(r"\b([a-z_][a-z0-9_]*)\s*\(", body):
            name = m.group(1)
            if name in ("if", "for", "while", "case", "return", "select", "insert",
                        "update", "delete", "values", "exists", "coalesce", "nullif",
                        "greatest", "least", "array", "row", "cast", "count", "sum",
                        "max", "min", "avg", "now", "current_timestamp", "current_date",
                        "extract", "date_trunc", "substring", "length", "trim",
                        "upper", "lower", "round", "abs", "concat", "format",
                        "jsonb_build_object", "jsonb_array_elements", "jsonb_each",
                        "jsonb_to_record", "jsonb_set", "jsonb_strip_nulls",
                        "to_char", "to_number", "to_date", "to_timestamp",
                        "make_date", "date_part", "age", "generate_series",
                        "unnest", "filter", "over", "partition", "coalesce"):
                continue
            if name in bare:
                calls |= bare[name]
        # The function's own name appears in its CREATE header, so it always
        # "calls" itself.  A self-dependency would make the topological sort
        # believe every function is part of a cycle.
        out[function_key(f)] = calls - {function_key(f)}
    return out


def is_write_function(fn: dict) -> bool:
    body = re.sub(r"/\*.*?\*/", " ", fn["definition"], flags=re.S)
    body = re.sub(r"--[^\n]*", " ", body)
    return bool(
        re.search(r"\bINSERT\s+INTO\b", body, re.I)
        or re.search(r"\bUPDATE\s+[\w\".]+\s+SET\b", body, re.I)
        or re.search(r"\bDELETE\s+FROM\b", body, re.I)
    )


def split_functions(cat: dict) -> dict[str, list[dict]]:
    """Assign every function to migration 017 (helpers), 019 (read RPCs) or 021."""
    fns = cat["functions"]
    by_key = {function_key(f): f for f in fns}
    callees = function_callees(cat)

    trigger_fns: set[str] = set()
    for trg in cat["triggers"]:
        m = re.search(r"EXECUTE FUNCTION\s+([\w\".]+)\s*\(", trg["definition"])
        if m:
            key = m.group(1)
            if "." not in key:
                key = f"public.{key}"
            trigger_fns.add(key)

    # level 0: sims_private helpers + the public functions the triggers need
    early: set[str] = {k for k, f in by_key.items() if f["schema"] == "sims_private"}
    early |= trigger_fns & set(by_key)

    def closure(seed: set[str]) -> set[str]:
        out = set(seed)
        stack = list(seed)
        while stack:
            cur = stack.pop()
            for dep in callees.get(cur, ()):
                if dep in by_key and dep not in out:
                    out.add(dep)
                    stack.append(dep)
        return out

    early = closure(early)
    read = {k for k, f in by_key.items()
            if k not in early and f["schema"] == "public" and not is_write_function(f)}
    mid = closure(read) - early
    rest = set(by_key) - early - mid

    def ordered(keys: set[str]) -> list[dict]:
        subset = [by_key[k] for k in keys]
        return topo_functions(subset, callees)

    return {
        "017": ordered(early),
        "019": ordered(mid),
        "021": ordered(rest),
    }


def topo_functions(fns: list[dict], callees: dict[str, set[str]]) -> list[dict]:
    """Order functions so that every callee is created before its caller.

    `LANGUAGE sql` functions are parsed when they are created, so a function
    that calls another one cannot be created first.  Genuine cycles are broken
    by taking the function with the fewest unmet dependencies, which keeps the
    rest of the order stable.
    """
    keys = {function_key(f) for f in fns}
    deps = {k: (callees.get(k, set()) & keys) for k in keys}
    out: list[dict] = []
    done: set[str] = set()
    remaining = sorted(keys)
    by_key = {function_key(f): f for f in fns}
    while remaining:
        ready = [k for k in remaining if deps[k] <= done]
        if not ready:
            # a cycle: break it deterministically, preferring the function
            # whose dependencies are nearly satisfied
            ready = [min(remaining, key=lambda k: (len(deps[k] - done), k))]
        for k in ready:
            out.append(by_key[k])
            done.add(k)
            remaining.remove(k)
    return out


# ---------------------------------------------------------------------------
# emitters
# ---------------------------------------------------------------------------
def emit_domains(cat: dict) -> list[str]:
    out = []
    for d in cat["domains"]:
        check = d.get("check")
        suffix = f" CHECK ({check[len('CHECK '):]})" if check and check.startswith("CHECK ") else ""
        if not suffix and check:
            suffix = f" CHECK ({check})"
        out.append(f"CREATE DOMAIN {ident(d['schema'])}.{ident(d['name'])} AS {d['base_type']}{suffix};")
    return out


def emit_composite_types(cat: dict) -> list[str]:
    # A table and a view both create their own row type under the same name,
    # so the catalogue lists those row types as composites as well.  They come
    # along with the table / view and must not be created a second time.
    row_types = {(t["schema"], t["name"]) for t in cat["tables"]}
    row_types |= {(v["schema"], v["name"]) for v in cat["views"]}
    out = []
    for c in cat["composites"]:
        if (c["schema"], c["name"]) in row_types:
            continue  # the row type of a table / view is created with it
        attrs = []
        for a in c["attributes"]:
            piece = f"  {ident(a['name'])} {a['type']}"
            if a.get("not_null"):
                piece += " NOT NULL"
            if a.get("default"):
                piece += f" DEFAULT {a['default']}"
            attrs.append(piece)
        out.append(
            f"CREATE TYPE {ident(c['schema'])}.{ident(c['name'])} AS (\n"
            + ",\n".join(attrs)
            + "\n);"
        )
    return out


def column_sql(col: dict) -> str:
    parts = [ident(col["name"]), col["type"]]
    if col.get("generated") == "s":
        parts.append(f"GENERATED ALWAYS AS ({col['default']}) STORED")
    elif col.get("identity") == "a":
        parts.append("GENERATED ALWAYS AS IDENTITY")
    elif col.get("identity") == "d":
        parts.append("GENERATED BY DEFAULT AS IDENTITY")
    if col.get("not_null"):
        parts.append("NOT NULL")
    if col.get("default") is not None and not col.get("generated"):
        parts.append(f"DEFAULT {col['default']}")
    return " ".join(parts)


def emit_tables(cat: dict) -> tuple[list[str], list[str]]:
    creates: list[str] = []
    fks: list[str] = []
    for t in order_tables(cat):
        schema, name = t["schema"], t["name"]
        lines = []
        for col in t["columns"]:
            lines.append("  " + column_sql(col))
        for c in t["constraints"]:
            if c["type"] == "f":
                fks.append(
                    f"ALTER TABLE {ident(schema)}.{ident(name)} "
                    f"ADD CONSTRAINT {ident(c['name'])} {c['definition']};"
                )
                continue
            if c["definition"].rstrip().endswith("NOT VALID"):
                # A constraint that is NOT VALID cannot be part of CREATE TABLE:
                # PostgreSQL only accepts it in ALTER TABLE ... ADD CONSTRAINT.
                # (CREATE TABLE parses the keyword but silently validates the
                # constraint, which would not reproduce the live catalogue.)
                fks.append(
                    f"ALTER TABLE {ident(schema)}.{ident(name)} "
                    f"ADD CONSTRAINT {ident(c['name'])} {c['definition']};"
                )
                continue
            lines.append(f"  CONSTRAINT {ident(c['name'])} {c['definition']}")
        body = ",\n".join(lines)
        creates.append(
            f"CREATE TABLE {ident(schema)}.{ident(name)} (\n{body}\n);"
        )
    return creates, fks


def emit_indexes(cat: dict) -> list[str]:
    # A UNIQUE constraint creates its own index under the constraint name, so
    # the catalogue lists that index as well.  Re-creating it would fail with
    # "relation already exists"; the constraint already brings it along.
    backed = {
        (t["schema"], t["name"], c["name"])
        for t in cat["tables"]
        for c in t["constraints"]
        if c["type"] == "u"
    }
    out = []
    for idx in cat["indexes"]:
        if (idx["schema"], idx["table"], idx["name"]) in backed:
            continue
        out.append(idx["definition"].rstrip().rstrip(";") + ";")
    return out


def order_views(cat: dict) -> list[dict]:
    """Order the views so that a view is created after the views it selects from."""
    views = cat["views"]
    names = {v["name"] for v in views}
    deps: dict[str, set[str]] = {}
    for v in views:
        used = set()
        for other in names:
            if other == v["name"]:
                continue
            if re.search(r"\b" + re.escape(other) + r"\b", v["body"]):
                used.add(other)
        deps[v["name"]] = used
    by_name = {v["name"]: v for v in views}
    out: list[dict] = []
    done: set[str] = set()
    remaining = sorted(names)
    while remaining:
        ready = [n for n in remaining if deps[n] <= done]
        if not ready:
            ready = [remaining[0]]
        for n in ready:
            out.append(by_name[n])
            done.add(n)
            remaining.remove(n)
    return out


def emit_views(cat: dict) -> list[str]:
    out = []
    for v in order_views(cat):
        opts = v.get("options") or []
        with_clause = ""
        if opts:
            with_clause = " WITH (" + ", ".join(opts) + ")"
        body = v["body"].rstrip().rstrip(";")
        out.append(
            f"CREATE OR REPLACE VIEW {ident(v['schema'])}.{ident(v['name'])}"
            f"{with_clause} AS\n{body};"
        )
    return out


def emit_policies(cat: dict) -> list[str]:
    out = []
    for p in cat["policies"]:
        # PostgreSQL wants a plain comma separated role list: `TO a, b`.
        roles = ", ".join(p["roles"]) if p["roles"] else "PUBLIC"
        permissive = "PERMISSIVE" if p.get("permissive", True) else "RESTRICTIVE"
        stmt = (
            f"CREATE POLICY {ident(p['name'])} ON {ident(p['schema'])}.{ident(p['table'])} "
            f"AS {permissive} FOR {p['command']} TO {roles}"
        )
        if p.get("using") is not None:
            stmt += f" USING ({p['using']})"
        if p.get("with_check") is not None:
            stmt += f" WITH CHECK ({p['with_check']})"
        out.append(stmt + ";")
    return out


def emit_grants(cat: dict) -> list[str]:
    out: list[str] = []
    # A freshly created function carries the default privilege "EXECUTE for
    # PUBLIC".  The live project took that privilege away again for every
    # function that has an explicit ACL, so the migration set has to do the
    # same - otherwise the rebuilt database would expose 418 functions to
    # everybody that can reach the database.
    seen: set[tuple[str, str]] = set()
    for g in cat["grants"]:
        if "(" not in g["object"]:
            continue
        key = (g["schema"], g["object"])
        if key in seen:
            continue
        seen.add(key)
        out.append(
            f"REVOKE EXECUTE ON FUNCTION {ident(g['schema'])}.{g['object']} FROM PUBLIC;"
        )
    out.append("")
    for g in cat["grants"]:
        schema, obj, grantee, priv, grantable = (
            g["schema"], g["object"], g["grantee"], g["privilege"], g["grantable"]
        )
        if schema == obj:  # schema grant
            target = f"SCHEMA {ident(schema)}"
        elif "(" in obj:  # function grant
            target = f"FUNCTION {ident(schema)}.{obj}"
        else:
            target = f"TABLE {ident(schema)}.{ident(obj)}"
        stmt = f"GRANT {priv} ON {target} TO {grantee}"
        if grantable:
            stmt += " WITH GRANT OPTION"
        out.append(stmt + ";")
    out.extend(emit_column_grants(cat))
    return out


def emit_column_grants(cat: dict) -> list[str]:
    """Emit the column level privileges.

    The live project does **not** grant `authenticated` SELECT on the public
    tables as a relation.  It grants SELECT on every *column* instead, so
    `SELECT <column>` is allowed while `SELECT *` is refused.  The row level
    security policies then decide which rows a caller may see.

    Without these grants the rebuilt database would refuse every direct table
    read, because the relation level SELECT privilege is missing.
    """
    out: list[str] = []
    for t in cat["tables"]:
        # (grantee, privilege) -> the columns that carry it
        grouped: dict[tuple[str, str], list[str]] = {}
        for col in t["columns"]:
            for p in col.get("privileges") or []:
                key = (p["grantee"], p["privilege"])
                grouped.setdefault(key, []).append(col["name"])
        for (grantee, privilege), cols in sorted(grouped.items()):
            if not cols:
                continue
            column_list = ", ".join(ident(c) for c in cols)
            out.append(
                f"GRANT {privilege} ({column_list}) ON TABLE "
                f"{ident(t['schema'])}.{ident(t['name'])} TO {grantee};"
            )
    return out


def emit_standalone_sequences(cat: dict) -> list[str]:
    """Create the sequences that no identity column owns.

    Identity columns bring their own sequence along, but the live database also
    has a handful of plain sequences that the RPCs use with `nextval()` to
    build human readable document numbers (receipt, grievance, ...).
    """
    owned = set()
    for t in cat["tables"]:
        for col in t["columns"]:
            if col.get("identity"):
                owned.add((t["schema"], t["name"], col["name"]))
    out = []
    for s in cat["sequences"]:
        ob = s.get("owned_by")
        if ob:
            parts = ob.split(".")
            if len(parts) == 3 and (parts[0], parts[1], parts[2]) in owned:
                continue
        out.append(
            f"CREATE SEQUENCE {ident(s['schema'])}.{ident(s['name'])} "
            f"AS {s.get('type', 'bigint')} INCREMENT BY {s['increment']} "
            f"MINVALUE {s['min']} MAXVALUE {s['max']} "
            f"START WITH {s['start']} CACHE {s['cache']}"
            + (" CYCLE" if s["cycle"] else "")
            + ";"
        )
    return out


def emit_sequence_resync(cat: dict) -> list[str]:
    out = []
    for t in cat["tables"]:
        for col in t["columns"]:
            if not col.get("identity"):
                continue
            schema, tname, cname = t["schema"], t["name"], col["name"]
            out.append(
                "SELECT setval(pg_get_serial_sequence("
                f"'{schema}.{tname}', '{cname}'), "
                f"COALESCE((SELECT MAX({ident(cname)}) FROM {ident(schema)}.{ident(tname)}), 0) + 1, false);"
            )
    # standalone sequences (not owned by an identity column) keep their start value
    owned = set()
    for t in cat["tables"]:
        for col in t["columns"]:
            if col.get("identity"):
                owned.add((t["schema"], t["name"], col["name"]))
    for s in cat["sequences"]:
        if s.get("owned_by"):
            parts = s["owned_by"].split(".")
            if len(parts) == 3 and (parts[0], parts[1], parts[2]) in owned:
                continue
        out.append(
            f"SELECT setval('{s['schema']}.{s['name']}', {s['start']}, false);"
        )
    return out


def emit_seed_inserts(cat: dict, seed: dict, table_names: list[str]) -> list[str]:
    types = {(t["schema"], t["name"]): {c["name"]: c["type"] for c in t["columns"]}
             for t in cat["tables"]}
    out: list[str] = []
    for tname in table_names:
        key = f"public.{tname}"
        if key not in seed:
            continue
        block = seed[key]
        cols = block["columns"]
        coltypes = types[("public", tname)]
        values = []
        for row in block["rows"]:
            cells = []
            for cname, val in zip(cols, row):
                cells.append(literal(val, coltypes.get(cname, "text")))
            values.append("  (" + ", ".join(cells) + ")")
        if not values:
            continue
        out.append(
            f"INSERT INTO public.{ident(tname)} ({', '.join(ident(c) for c in cols)}) VALUES\n"
            + ",\n".join(values)
            + "\nON CONFLICT DO NOTHING;"
        )
    return out


# ---------------------------------------------------------------------------
# file writers
# ---------------------------------------------------------------------------
def write_migration(num: str, title: str, body: list[str], extra_header: str = "") -> Path:
    path = MIGRATIONS / f"{num}_{title}.sql"
    header = BANNER.format(num=num, title=title)
    if extra_header:
        header += extra_header
    text = header + "\n" + "\n".join(body).rstrip() + "\n"
    path.write_text(text, encoding="utf-8", newline="\n")
    return path


def build_001(cat: dict) -> Path:
    body: list[str] = []
    body.append("-- -----------------------------------------------------------------------------")
    body.append("-- Schemas")
    body.append("-- -----------------------------------------------------------------------------")
    body.append("CREATE SCHEMA IF NOT EXISTS sims_private;")
    body.append("")
    body.append("-- -----------------------------------------------------------------------------")
    body.append("-- Domains (MySQL UNSIGNED / YEAR ranges)")
    body.append("-- -----------------------------------------------------------------------------")
    body.extend(emit_domains(cat))
    body.append("")
    body.append("-- -----------------------------------------------------------------------------")
    body.append("-- Composite types")
    body.append("-- -----------------------------------------------------------------------------")
    composites = emit_composite_types(cat)
    body.extend(composites if composites else ["-- (none)"])
    body.append("")
    body.append("-- -----------------------------------------------------------------------------")
    body.append("-- Tables, in foreign-key dependency order")
    body.append("-- -----------------------------------------------------------------------------")
    creates, fks = emit_tables(cat)
    body.extend(creates)
    body.append("")
    body.append("-- -----------------------------------------------------------------------------")
    body.append("-- Foreign keys (added after every table exists so that the order above")
    body.append("-- stays a true topological order and self references still work)")
    body.append("-- -----------------------------------------------------------------------------")
    body.extend(fks)
    body.append("")
    body.append("-- -----------------------------------------------------------------------------")
    body.append("-- Standalone sequences (the identity columns bring their own sequence,")
    body.append("-- these are the document number counters the RPCs use with nextval())")
    body.append("-- -----------------------------------------------------------------------------")
    body.extend(emit_standalone_sequences(cat))
    body.append("")
    body.append("-- -----------------------------------------------------------------------------")
    body.append("-- Indexes")
    body.append("-- -----------------------------------------------------------------------------")
    body.extend(emit_indexes(cat))
    body.append("")
    body.append("-- -----------------------------------------------------------------------------")
    body.append("-- Views")
    body.append("-- -----------------------------------------------------------------------------")
    body.extend(emit_views(cat))
    return write_migration("001", "common_reference_and_institution", body)


def build_seed_files(cat: dict, seed: dict, ref: dict) -> list[Path]:
    paths = []
    for num, title in SEED_FILES.items():
        tables = [t for t in SEED_TABLE_MAP.get(num, []) if t not in RUNTIME_TABLES]
        body: list[str] = []
        body.append("-- -----------------------------------------------------------------------------")
        body.append(f"-- Seed rows for the tables of module '{title.replace('_', ' ')}'.")
        body.append("-- Only the rows the live database really contains are emitted; every")
        body.append("-- statement carries explicit primary keys and is idempotent.")
        body.append("-- -----------------------------------------------------------------------------")
        notes = module_note(ref, seed_modules(ref, tables))
        if notes:
            body.extend(notes)
            body.append("")
        inserts = emit_seed_inserts(cat, seed, tables)
        if inserts:
            body.extend(inserts)
        else:
            body.append("")
            body.append("-- The live database holds no rows for the tables of this module,")
            body.append("-- so this file seeds nothing.  The tables themselves are created in 001.")
        paths.append(write_migration(num, title, body))
    return paths


def build_015(cat: dict) -> Path:
    body = [
        "-- -----------------------------------------------------------------------------",
        "-- Identity / sequence resync.",
        "-- Every identity sequence is moved to max(id) + 1 over the rows that are",
        "-- actually in the table, so the next INSERT gets a free key and the seed",
        "-- data (which uses explicit ids) never collides.",
        "-- -----------------------------------------------------------------------------",
    ]
    body.extend(emit_sequence_resync(cat))
    return write_migration("015", "identity_sequence_resync", body)


def build_016(cat: dict) -> Path:
    body = [
        "-- -----------------------------------------------------------------------------",
        "-- Deny by default: every table that carries row level security in the live",
        "-- catalogue gets RLS enabled here.  Without a policy a table returns no",
        "-- rows at all, so the policies in 018 are what makes data visible.",
        "-- -----------------------------------------------------------------------------",
    ]
    for t in cat["tables"]:
        if t["rls"]:
            body.append(f"ALTER TABLE {ident(t['schema'])}.{ident(t['name'])} ENABLE ROW LEVEL SECURITY;")
    return write_migration("016", "rls_deny_by_default", body)


def build_017(cat: dict, groups: dict) -> Path:
    body = [
        "-- -----------------------------------------------------------------------------",
        "-- The `sims_private` schema and the helper functions.",
        "--",
        "-- `sims_private` holds the identity map, the MFA tables and the authorisation",
        "-- helpers (`can_global`, `can_programme`, `current_user_id`, ...).  It is NOT",
        "-- part of the Data API surface (see supabase/config.toml), but the RLS",
        "-- policies call into it, so `authenticated` needs USAGE on the schema and",
        "-- EXECUTE on the helpers - exactly as in the live database.",
        "--",
        "-- The public trigger helpers (`sims_guard_*`, `sims_touch_updated_at`, ...)",
        "-- live here as well because the triggers in 020 depend on them.",
        "-- -----------------------------------------------------------------------------",
        "CREATE SCHEMA IF NOT EXISTS sims_private;",
        "",
    ]
    for fn in groups["017"]:
        body.append(terminate(fn["definition"]))
        body.append("")
    return write_migration("017", "identity_map_and_rbac_helpers", body)


def build_019(cat: dict, groups: dict) -> Path:
    body = [
        "-- -----------------------------------------------------------------------------",
        "-- `my_context()` and the public read RPCs.",
        "--",
        "-- These are the functions the application calls through PostgREST.  They are",
        "-- SECURITY DEFINER with a pinned search_path, so they read the rows the",
        "-- caller is allowed to see without exposing the tables themselves.",
        "-- -----------------------------------------------------------------------------",
    ]
    for fn in groups["019"]:
        body.append(terminate(fn["definition"]))
        body.append("")
    return write_migration("019", "my_context_rpc", body)


def build_020(cat: dict) -> Path:
    body = [
        "-- -----------------------------------------------------------------------------",
        "-- Every trigger of the live catalogue.",
        "--",
        "-- Audit triggers, workflow guards, `updated_at` touchers and the integrity",
        "-- triggers.  They are emitted verbatim from `pg_get_triggerdef()`.",
        "-- -----------------------------------------------------------------------------",
    ]
    for trg in cat["triggers"]:
        body.append(terminate(trg["definition"]))
    return write_migration("020", "workflow_guards", body)


def build_021(cat: dict, groups: dict) -> Path:
    body = [
        "-- -----------------------------------------------------------------------------",
        "-- The remaining public functions and every grant.",
        "--",
        "-- The grants are emitted from the live ACLs: `authenticated` may call the",
        "-- public RPCs, `service_role` bypasses RLS, and `sims_private` stays out of",
        "-- the Data API (it is not listed in supabase/config.toml).",
        "-- -----------------------------------------------------------------------------",
    ]
    if groups["021"]:
        body.append("-- -----------------------------------------------------------------------------")
        body.append("-- Remaining public functions")
        body.append("-- -----------------------------------------------------------------------------")
        for fn in groups["021"]:
            body.append(terminate(fn["definition"]))
            body.append("")
    body.append("-- -----------------------------------------------------------------------------")
    body.append("-- Grants")
    body.append("--")
    body.append("-- The first block takes the default PUBLIC execute privilege away from")
    body.append("-- the functions again - a fresh function has it, the live project does")
    body.append("-- not.  The second block restores the live ACLs.")
    body.append("-- -----------------------------------------------------------------------------")
    body.extend(emit_grants(cat))
    body.append("")
    body.append("-- -----------------------------------------------------------------------------")
    body.append("-- Default privileges (the live project grants service_role the same")
    body.append("-- rights on objects that are created later)")
    body.append("-- -----------------------------------------------------------------------------")
    body.append("ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;")
    body.append("ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;")
    body.append("ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;")
    return write_migration("021", "finance_rpcs", body)


def build_consolidated(cat: dict, ref: dict) -> list[Path]:
    paths = []
    for num, title in CONSOLIDATED_FILES.items():
        body = [
            "-- -----------------------------------------------------------------------------",
            "-- This migration was consolidated.",
            "--",
            "-- The original per-feature file cannot be reconstructed from a catalogue",
            "-- dump: a dump records the objects that exist, not the file that created",
            "-- them.  The content that this version number used to carry therefore",
            "-- lives in the consolidated files:",
            "--",
            "--   017  the `sims_private` schema and every helper function",
            "--   018  every RLS policy",
            "--   019  `my_context()` and the public read RPCs",
            "--   020  every trigger",
            "--   021  every grant and the remaining public functions",
            "--",
            "-- The version number is kept so that the migration history of the remote",
            "-- project (001..063 already applied) stays aligned: the file name, the",
            "-- ordering and the applied version are unchanged, only the payload moved.",
            "-- -----------------------------------------------------------------------------",
        ]
        notes = module_note(ref, CONSOLIDATED_MODULE.get(num, []))
        if notes:
            body.append("--")
            body.extend(notes)
            body.append("--")
        body.extend([
            "DO $consolidated$",
            "BEGIN",
            "  -- intentionally empty: the payload was consolidated into 017/018/019/020/021",
            "END",
            "$consolidated$;",
        ])
        paths.append(write_migration(num, title, body))
    return paths


def build_018(cat: dict) -> Path:
    """018 is produced by tools/build_rls.py so that the policy generator stays the
    single source of truth for the policy file.

    The whole file - banner included - is written by build_rls.py, so that running
    `python tools/build_rls.py` and `npm run migrate:build` cannot disagree."""
    import build_rls  # noqa: E402  (local module, tools/ is on sys.path when run as a script)

    return build_rls.write_policy_migration(cat, build_rls.load_table_map())


# ---------------------------------------------------------------------------
# the dry run
# ---------------------------------------------------------------------------
def check_only(cat: dict, seed: dict, ref: dict, groups: dict) -> int:
    """Build the migration set into a temporary directory and report what would
    change, without touching the real one.

    The `--check` flag used to be accepted and then ignored - the build wrote
    the generated files anyway.  That is not harmless: the catalogue carries the
    objects that the hand written migrations own (`public.schema_indexes` from
    065, the admin editing functions from 066), so a "dry run" copied them into
    the generated files and a fresh database would then create them twice.

    The build therefore runs against a temporary directory and the result is
    compared with the files on disk.
    """
    import tempfile

    real = MIGRATIONS
    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)
        try:
            globals()["MIGRATIONS"] = tmp_dir
            import build_rls

            build_rls.MIGRATIONS = tmp_dir
            build_001(cat)
            build_seed_files(cat, seed, ref)
            build_015(cat)
            build_016(cat)
            build_017(cat, groups)
            build_018(cat)
            build_019(cat, groups)
            build_020(cat)
            build_021(cat, groups)
            build_consolidated(cat, ref)
        finally:
            globals()["MIGRATIONS"] = real
            build_rls.MIGRATIONS = real

        changed: list[tuple[str, str]] = []
        for generated in sorted(tmp_dir.glob("*.sql")):
            current = real / generated.name
            if not current.exists():
                changed.append((generated.name, "missing on disk"))
            elif current.read_bytes() != generated.read_bytes():
                changed.append((generated.name, "different on disk"))

    if not changed:
        print(f"OK - the {len(list(real.glob('*.sql')))} migration files are up to date")
        return 0

    print("DIFF - the generated migration files are out of date")
    for name, why in changed:
        print(f"  {name}: {why}")
    return 1


# ---------------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--catalogue", default=str(CATALOGUE))
    ap.add_argument("--seed", default=str(SEED_DATA))
    ap.add_argument("--reference", default=str(REFERENCE),
                    help="the MySQL reference document of tools/translate.py")
    ap.add_argument("--check", action="store_true",
                    help="do not write, only report what would change")
    args = ap.parse_args()

    cat = strip_hand_written(load_catalogue(Path(args.catalogue)))
    seed_path = Path(args.seed)
    seed = json.loads(seed_path.read_text(encoding="utf-8")) if seed_path.exists() else {}

    # the MySQL reference document is the functional specification the live
    # database implements; the build refuses to run when the two disagree
    ref = load_reference(Path(args.reference))
    stats = cross_check_reference(cat, ref)
    if stats["missing_tables"] or stats["missing_columns"]:
        for name in stats["missing_tables"]:
            print(f"missing table: {name}", file=sys.stderr)
        for name in stats["missing_columns"]:
            print(f"missing column: {name}", file=sys.stderr)
        raise SystemExit(
            "the live catalogue and the MySQL reference disagree - the migration "
            "set would no longer reproduce the specification"
        )

    sys.path.insert(0, str(ROOT / "tools"))
    groups = split_functions(cat)

    # The live project grants `authenticated` SELECT on every *column* of 212
    # of the 213 public tables instead of granting SELECT on the relation.
    # A catalogue that carries no column level privileges at all was produced
    # by an outdated dumper, and the migration set it generates would refuse
    # every direct table read.  Refuse to build from such a catalogue.
    column_grants = sum(
        len(col.get("privileges") or [])
        for t in cat["tables"]
        for col in t["columns"]
    )
    if column_grants == 0:
        raise SystemExit(
            "the catalogue carries no column level privileges - it was dumped by "
            "an outdated dumper.  Re-dump it with `python tools/dump_catalogue.py` "
            "or `node tools/validate/catalogue.mjs` and try again."
        )

    # 064, 065 and 066 are hand written and must stay untouched
    for hand_written in (
        "064_required_reference_seeds.sql",
        "065_schema_indexes.sql",
        "066_admin_editing.sql",
    ):
        if not (MIGRATIONS / hand_written).exists():
            raise SystemExit(f"{hand_written} is missing - refusing to continue")

    if args.check:
        return check_only(cat, seed, ref, groups)

    MIGRATIONS.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    written.append(build_001(cat))
    written.extend(build_seed_files(cat, seed, ref))
    written.append(build_015(cat))
    written.append(build_016(cat))
    written.append(build_017(cat, groups))
    written.append(build_018(cat))
    written.append(build_019(cat, groups))
    written.append(build_020(cat))
    written.append(build_021(cat, groups))
    written.extend(build_consolidated(cat, ref))

    print(f"wrote {len(written)} migration files to {MIGRATIONS}")
    counts = cat["counts"]
    print(
        "catalogue: {tables} tables, {views} views, {functions} functions, "
        "{triggers} triggers, {policies} policies, RLS on {rls_tables}".format(**counts)
    )
    print(
        "function split: 017={} 019={} 021={}".format(
            len(groups["017"]), len(groups["019"]), len(groups["021"])
        )
    )
    print(
        "reference: {tables} tables, {columns} columns of {source} - all of them "
        "exist in the live catalogue".format(
            tables=stats["tables"], columns=stats["columns"], source=stats["source"]
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
