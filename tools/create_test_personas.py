#!/usr/bin/env python3
"""Create the test personas the sidebar's visibility rules need.

    python tools/create_test_personas.py [--apply] [--json]

Without `--apply` the tool only prints the plan.  `--apply` is the only way to
make it write, and it is deliberately explicit.

Why the personas exist
----------------------

The sidebar draws a group only when the signed-in user can read the module
behind it.  The demo seed deliberately creates **no** user accounts - a SIMS
user needs a Supabase Auth identity, which cannot be invented from SQL.  That
left one account in the project: the test administrator, who holds every
module and therefore sees every group.

That proves nothing about the visibility rules.  A student must not see the
reporting screen; a faculty member must see the staff-profile modules; the
employee's own HR records belong to an account that is actually linked to an
employee record.  This tool creates the two accounts that make those rules
observable:

    sims.test.employee@gmail.com   employee DEMO-E001 (Anita Rao), FACULTY
                                   at DEPARTMENT scope - sees the staff-profile
                                   and reporting groups, and "My HR records"
                                   because the account is linked to an employee.

    sims.test.student@gmail.com    student DEMO-S001 (Asha Rao), STUDENT at
                                   SELF scope - sees the student groups and
                                   none of the staff or reporting groups.

How an account is created
-------------------------

1.  The sign-in identity is created with the **publishable** key against the
    public sign-up endpoint, so no service-role key is needed.  That endpoint
    sends a confirmation mail and the project rate limits that mail, so when
    it refuses the request the identity is written straight into `auth.users`
    instead - the same row, with the same bcrypt hash format.
2.  The address is confirmed, because the project requires a confirmed address
    before the password grant works.
3.  The SIMS side is created with the database's own RPCs -
    `public.iam_provision_user()` and `public.iam_assign_role()` - so the
    audit trail, the identity map and the role assignment all come from the
    same code path the application uses.  The actor is the test administrator,
    because `iam_assign_role()` checks `IAM.ALL.UPDATE` against the caller.

The tool is idempotent: an account that already exists is left alone and only
reported.

Connection settings (the environment wins over the defaults):

    NEXT_PUBLIC_SUPABASE_URL           the project URL
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY  the publishable key
    SUPABASE_DB_PASSWORD               the database password

The database password is never stored in the repository - the tool refuses to
run when it is missing.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
import uuid
from dataclasses import dataclass

try:
    import psycopg2
except ImportError:  # pragma: no cover - the dependency is documented
    print("psycopg2 is required: pip install psycopg2-binary", file=sys.stderr)
    raise

DEFAULT_URL = "https://khqqfgqvwdxlqkncwtmh.supabase.co"
DEFAULT_PUBLISHABLE_KEY = "sb_publishable_nm1TFKGC35SxKWUjbVeSWg_uZC8JtHQ"

DEFAULT_HOST = "aws-0-ap-southeast-1.pooler.supabase.com"
DEFAULT_PORT = 5432
DEFAULT_NAME = "postgres"
DEFAULT_USER = "postgres.khqqfgqvwdxlqkncwtmh"
DEFAULT_SSLMODE = "require"

#: The account that acts for the personas.  It has to hold `IAM.ALL.UPDATE`,
#: because `iam_assign_role()` checks the caller.
ACTOR_EMAIL = "sims.test.admin@gmail.com"

#: The password every test account uses.  It is a test password for a test
#: project, and it is printed in the README next to the administrator's.
TEST_PASSWORD = "SimsTest@2026"

AUTH_USER_INSERT = """
INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, confirmation_token, recovery_token,
    email_change_token_new, email_change, phone_change_token,
    reauthentication_token, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, is_sso_user, is_anonymous
) VALUES (
    '00000000-0000-0000-0000-000000000000', %(id)s::uuid, 'authenticated',
    'authenticated', %(email)s, %(hash)s, now(),
    '', '', '', '', '', '',
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object(
        'sub', %(id)s::text,
        'email', %(email)s,
        'email_verified', true,
        'phone_verified', false
    ),
    now(), now(), false, false
)
"""

#: GoTrue keeps the provider identity in a second table.  The sign-up endpoint
#: writes it; a direct write has to write it too, or the password grant finds
#: no identity and fails with a 500.
AUTH_IDENTITY_INSERT = """
INSERT INTO auth.identities (
    id, provider_id, user_id, identity_data, provider, created_at, updated_at
) VALUES (
    gen_random_uuid(), %(id)s::text, %(id)s::uuid,
    jsonb_build_object(
        'sub', %(id)s::text,
        'email', %(email)s,
        'email_verified', true,
        'phone_verified', false
    ),
    'email', now(), now()
)
"""


@dataclass(frozen=True)
class Persona:
    """One account to create."""

    email: str
    role_code: str
    scope_type: str
    #: The employee or student number the account is linked to.  Exactly one of
    #: the two is set.
    employee_number: str = ""
    student_number: str = ""
    #: The scope entity: a department id for DEPARTMENT scope, nothing for SELF.
    scope_entity_id: int | None = None
    note: str = ""


PERSONAS = (
    Persona(
        email="sims.test.employee@gmail.com",
        role_code="FACULTY",
        scope_type="DEPARTMENT",
        employee_number="DEMO-E001",
        scope_entity_id=1,
        note="a faculty member: sees the staff-profile and reporting groups, "
        "and 'My HR records' because the account is linked to an employee",
    ),
    Persona(
        email="sims.test.student@gmail.com",
        role_code="STUDENT",
        scope_type="SELF",
        student_number="DEMO-S001",
        note="a student: sees the student groups and none of the staff, "
        "reporting or administration groups",
    ),
)


def env(*names: str, default: str = "") -> str:
    for name in names:
        value = os.environ.get(name, "")
        if value:
            return value
    return default


def connect():
    """Open the direct database connection."""
    password = env("SUPABASE_DB_PASSWORD", "SIMS_DB_PASSWORD")
    if not password:
        print(
            "SUPABASE_DB_PASSWORD is not set: the tool needs it to confirm the "
            "address and to call the provisioning RPCs.",
            file=sys.stderr,
        )
        raise SystemExit(2)
    return psycopg2.connect(
        host=env("SUPABASE_DB_HOST", "SIMS_DB_HOST", default=DEFAULT_HOST),
        port=int(env("SUPABASE_DB_PORT", "SIMS_DB_PORT", default=str(DEFAULT_PORT))),
        dbname=env("SUPABASE_DB_NAME", "SIMS_DB_NAME", default=DEFAULT_NAME),
        user=env("SUPABASE_DB_USER", "SIMS_DB_USER", default=DEFAULT_USER),
        password=password,
        sslmode=env("SUPABASE_DB_SSLMODE", "SIMS_DB_SSLMODE", default=DEFAULT_SSLMODE),
    )


def signup(url: str, key: str, email: str, password: str) -> tuple[bool, str]:
    """Create the sign-in identity with the public sign-up endpoint.

    The publishable key is enough - the Admin API and its service-role key are
    not needed, and the tool refuses to ask for one.
    """
    body = json.dumps({"email": email, "password": password}).encode("utf-8")
    request = urllib.request.Request(
        f"{url}/auth/v1/signup",
        data=body,
        headers={"apikey": key, "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.loads(response.read().decode("utf-8"))
            return bool(payload.get("id")), payload.get("id", "")
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8")[:200]
        return False, f"HTTP {exc.code}: {detail}"
    except Exception as exc:  # noqa: BLE001
        return False, str(exc)


def create_auth_user_directly(cur, email: str, password: str) -> tuple[bool, str]:
    """Create the sign-in identity without the sign-up endpoint.

    The sign-up endpoint sends a confirmation mail and the project rate limits
    that mail.  A test account cannot read its mail, so the identity is
    written straight into `auth.users` instead - the same row the endpoint
    would have written, with the same bcrypt hash format.

    `bcrypt` is only needed for this path.
    """
    try:
        import bcrypt
    except ImportError:  # pragma: no cover - the dependency is documented
        return False, "bcrypt is required for the direct path: pip install bcrypt"

    user_id = str(uuid.uuid4())
    hashed = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt(rounds=10)).decode("utf-8")
    try:
        cur.execute(
            AUTH_USER_INSERT,
            {"id": user_id, "email": email, "hash": hashed},
        )
        cur.execute(
            AUTH_IDENTITY_INSERT,
            {"id": user_id, "email": email},
        )
    except Exception as exc:  # noqa: BLE001
        return False, str(exc).strip().splitlines()[0]
    return True, user_id


def confirm_address(cur, email: str) -> None:
    """Confirm the address so the password grant works.

    The project sends a confirmation mail, and a test account cannot read it.
    The confirmation is a single column on `auth.users`.
    """
    cur.execute(
        "UPDATE auth.users SET email_confirmed_at = now() "
        "WHERE email = %s AND email_confirmed_at IS NULL",
        (email,),
    )


def actor_identity(cur) -> tuple[str, int]:
    """The actor's auth uuid and user id.

    The actor has to be a real signed-in identity, because `iam_assign_role()`
    checks `IAM.ALL.UPDATE` against the caller and refuses self-assignment.
    """
    cur.execute(
        """
        SELECT m.auth_user_id::text, m.user_id
          FROM sims_private.auth_identity_map m
          JOIN public.user_account u ON u.user_id = m.user_id
         WHERE lower(u.email) = lower(%s)
        """,
        (ACTOR_EMAIL,),
    )
    row = cur.fetchone()
    if row is None:
        raise RuntimeError(
            f"the actor {ACTOR_EMAIL} is not provisioned - run tools/create_test_admin.py first"
        )
    return row[0], row[1]


def set_identity(cur, auth_user_id: str) -> None:
    """Make the next statements run as `authenticated` with this subject."""
    cur.execute("SELECT set_config('request.jwt.claim.sub', %s, false)", (auth_user_id,))
    cur.execute(
        "SELECT set_config('request.jwt.claims', %s, false)",
        (json.dumps({"sub": auth_user_id, "role": "authenticated"}),),
    )


def clear_identity(cur) -> None:
    cur.execute("RESET request.jwt.claim.sub")
    cur.execute("RESET request.jwt.claims")


def role_id(cur, role_code: str) -> int:
    cur.execute(
        "SELECT role_id FROM public.role WHERE role_code = %s AND is_active AND is_assignable",
        (role_code,),
    )
    row = cur.fetchone()
    if row is None:
        raise RuntimeError(f"the role {role_code} is missing or not assignable")
    return row[0]


def existing_user(cur, email: str) -> tuple[int, str] | None:
    """The SIMS user behind an address, if there is one."""
    cur.execute(
        """
        SELECT u.user_id, m.auth_user_id::text
          FROM public.user_account u
          LEFT JOIN sims_private.auth_identity_map m ON m.user_id = u.user_id
         WHERE lower(u.email) = lower(%s)
        """,
        (email,),
    )
    row = cur.fetchone()
    return (row[0], row[1] or "") if row else None


def ensure_identity(cur, auth_user_id: str, email: str) -> None:
    """Make sure GoTrue can read the account.

    Two things are needed and both are easy to miss:

    * a provider identity in `auth.identities` - the sign-up endpoint writes
      one, an account written straight into `auth.users` has none, and the
      password grant then fails with a 500;
    * empty strings in the token columns - GoTrue reads them into Go strings,
      and a NULL there makes the same query fail with a 500.
    """
    cur.execute(
        """
        UPDATE auth.users
           SET confirmation_token = '', recovery_token = '',
               email_change_token_new = '', email_change = '',
               phone_change_token = '', reauthentication_token = ''
         WHERE id = %s::uuid
           AND (confirmation_token IS NULL OR recovery_token IS NULL
                OR email_change_token_new IS NULL OR email_change IS NULL
                OR phone_change_token IS NULL OR reauthentication_token IS NULL)
        """,
        (auth_user_id,),
    )
    cur.execute(
        "SELECT 1 FROM auth.identities WHERE user_id = %s::uuid AND provider = 'email'",
        (auth_user_id,),
    )
    if cur.fetchone() is not None:
        return
    cur.execute(
        AUTH_IDENTITY_INSERT,
        {"id": auth_user_id, "email": email},
    )


def readable_modules(cur, auth_user_id: str) -> list[str]:
    """The modules the account can read, through the database's own answer."""
    set_identity(cur, auth_user_id)
    try:
        cur.execute("SELECT public.my_context()")
        row = cur.fetchone()
    finally:
        clear_identity(cur)
    if row is None or row[0] is None:
        return []
    payload = row[0] if isinstance(row[0], dict) else json.loads(row[0])
    return sorted(payload.get("readable_modules") or [])


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="create the accounts (without it the tool only prints the plan)",
    )
    parser.add_argument("--dry-run", action="store_true", help="print the plan and stop (the default)")
    parser.add_argument("--json", action="store_true", help="machine readable report")
    args = parser.parse_args()

    url = env("NEXT_PUBLIC_SUPABASE_URL", "SUPABASE_URL", default=DEFAULT_URL).rstrip("/")
    key = env("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", default=DEFAULT_PUBLISHABLE_KEY)

    connection = connect()
    connection.autocommit = True
    cur = connection.cursor()

    report: list[dict] = []
    try:
        actor_auth, actor_user = actor_identity(cur)

        for persona in PERSONAS:
            entry: dict = {
                "email": persona.email,
                "role": persona.role_code,
                "scope": persona.scope_type,
                "person": persona.employee_number or persona.student_number,
                "action": "none",
            }

            found = existing_user(cur, persona.email)
            if found is not None:
                entry["action"] = "already provisioned"
                entry["user_id"] = found[0]
                if found[1]:
                    if args.apply:
                        ensure_identity(cur, found[1], persona.email)
                    entry["readable_modules"] = readable_modules(cur, found[1])
                report.append(entry)
                continue

            entry["action"] = "would create"
            if args.apply:
                ok, detail = signup(url, key, persona.email, TEST_PASSWORD)
                if not ok:
                    # The sign-up endpoint sends a confirmation mail and the
                    # project rate limits that mail.  The identity is written
                    # directly instead.
                    ok, detail = create_auth_user_directly(cur, persona.email, TEST_PASSWORD)
                if not ok:
                    entry["action"] = "failed"
                    entry["error"] = detail
                    report.append(entry)
                    continue

                cur.execute(
                    "SELECT id::text FROM auth.users WHERE lower(email) = lower(%s)",
                    (persona.email,),
                )
                row = cur.fetchone()
                if row is None:
                    entry["action"] = "failed"
                    entry["error"] = "the sign-up did not create an auth user"
                    report.append(entry)
                    continue
                auth_user_id = row[0]
                confirm_address(cur, persona.email)

                set_identity(cur, actor_auth)
                try:
                    cur.execute(
                        "SELECT public.iam_provision_user(%s::uuid, %s, %s, %s, %s)",
                        (
                            auth_user_id,
                            persona.email,
                            persona.student_number or None,
                            persona.employee_number or None,
                            actor_user,
                        ),
                    )
                    user_id = cur.fetchone()[0]
                    cur.execute(
                        "SELECT public.iam_assign_role(%s, %s, %s, %s, %s)",
                        (
                            user_id,
                            role_id(cur, persona.role_code),
                            persona.scope_type,
                            persona.scope_entity_id,
                            "test persona created by tools/create_test_personas.py",
                        ),
                    )
                finally:
                    clear_identity(cur)

                # `iam_provision_user()` marks a real account for a password
                # change.  A test persona has a published password, so the flag
                # is cleared the same way the administrator's account has it.
                cur.execute(
                    "UPDATE public.user_account SET must_change_password = false "
                    "WHERE user_id = %s",
                    (user_id,),
                )

                entry["action"] = "created"
                entry["user_id"] = user_id
                entry["readable_modules"] = readable_modules(cur, auth_user_id)

            report.append(entry)

        cur.execute(
            """
            SELECT u.email, u.account_status, u.must_change_password,
                   COALESCE(string_agg(r.role_code, ', ' ORDER BY r.role_code), '')
              FROM public.user_account u
              LEFT JOIN public.user_role_assignment a
                     ON a.user_id = u.user_id AND a.assignment_status = 'ACTIVE'
              LEFT JOIN public.role r ON r.role_id = a.role_id
             WHERE lower(u.email) IN (%s, %s, %s)
             GROUP BY u.user_id, u.email, u.account_status, u.must_change_password
             ORDER BY u.email
            """,
            (ACTOR_EMAIL, PERSONAS[0].email, PERSONAS[1].email),
        )
        accounts = [
            {
                "email": row[0],
                "status": row[1],
                "must_change_password": row[2],
                "roles": row[3],
            }
            for row in cur.fetchall()
        ]
    finally:
        cur.close()
        connection.close()

    if args.json:
        print(json.dumps({"personas": report, "accounts": accounts}, indent=2))
        return 0

    print()
    print("=== the test personas ===")
    for entry in report:
        print(f"  {entry['email']:<34} {entry['role']:<10} {entry['action']}")
        if entry.get("error"):
            print(f"      error: {entry['error']}")
        if entry.get("readable_modules"):
            print(f"      readable modules: {', '.join(entry['readable_modules'])}")
    print()
    print("=== the accounts in the database ===")
    for account in accounts:
        print(
            f"  {account['email']:<34} {account['status']:<8} "
            f"roles={account['roles'] or '(none)'}"
        )
    print()
    if args.apply:
        print("the personas are ready. Sign in with the password " + TEST_PASSWORD)
    else:
        print("dry run: nothing was written. Use --apply to create the accounts.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
