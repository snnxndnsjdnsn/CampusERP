#!/usr/bin/env python3
"""Create a new test administrator on the Supabase project.

Usage:
    python tools/create_test_admin.py [--apply] [--email EMAIL] [--password SECRET]
                                      [--generate] [--role ROLE] [--json]

Without `--apply` the tool only prints the plan: which role would be assigned,
what the account would look like and what the password would be.  It never
writes to the database in that mode.  `--apply` is the only way to make it
write, and it is deliberately explicit.

Why this tool exists
--------------------
`tools/create_admin.mjs` uses the Supabase **Admin API**, which needs the
project's `SUPABASE_SERVICE_ROLE_KEY`.  That key is not available in this
environment, so the account is created with a direct database connection
instead.  The rows it writes are exactly the rows the Admin API would write:

    auth.users                      the credential (bcrypt hash, email confirmed)
    auth.identities                 the email provider identity
    public.user_account             the SIMS account (ACTIVE)
    sims_private.auth_identity_map  the link between the two
    public.user_role_assignment     the role, at the role's own scope level

Everything runs in **one** transaction.  When a step fails, the transaction is
rolled back and the project keeps the state it had before.

The role assignment is written with `scope_type` taken from `role.role_level`,
because the trigger `trg_user_role_assignment_scope_bi` refuses any other
combination.  `SUPER_ADMIN` therefore gets `GLOBAL`.

After the write the tool proves the account works: it signs in through the
Auth REST endpoint with the project's publishable key and then resolves
`public.my_context()` for the new user.

Connection settings (the environment wins over the defaults):

    SUPABASE_DB_HOST      aws-0-ap-southeast-1.pooler.supabase.com
    SUPABASE_DB_PORT      5432
    SUPABASE_DB_NAME      postgres
    SUPABASE_DB_USER      postgres.khqqfgqvwdxlqkncwtmh
    SUPABASE_DB_PASSWORD  <the project password>
    SUPABASE_DB_SSLMODE   require

`SIMS_DB_*` is accepted as an alias for `SUPABASE_DB_*`.  The password is
never stored in the repository.

Exit code 0 means "the plan is clean" or "the account was created", 1 means
"the creation failed" and 2 means "the tool was not configured correctly".
"""
from __future__ import annotations

import argparse
import json
import os
import secrets
import string
import sys
import urllib.error
import urllib.request
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

try:
    import psycopg2
except ImportError:  # pragma: no cover - the dependency is documented
    print("psycopg2 is required: pip install psycopg2-binary", file=sys.stderr)
    raise

from apply_migrations import connect, dsn  # noqa: E402

DEFAULT_URL = "https://khqqfgqvwdxlqkncwtmh.supabase.co"
DEFAULT_KEY = "sb_publishable_nm1TFKGC35SxKWUjbVeSWg_uZC8JtHQ"
DEFAULT_ROLE = "SUPER_ADMIN"
DEFAULT_EMAIL = "sims.test.admin@gmail.com"

#: The alphabet is deliberately free of characters that need escaping in SQL,
#: in a URL or in a shell.
ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"


def pick(names, fallback: str = "") -> str:
    """The first environment variable that is set wins."""
    for name in names:
        value = os.environ.get(name)
        if value:
            return value
    return fallback


def generate_password() -> str:
    """A password that is long enough and has no characters that need escaping."""
    raw = "".join(secrets.choice(ALPHABET) for _ in range(24))
    return f"{raw[0:4]}-{raw[4:10]}-{raw[10:16]}-{raw[16:24]}"


def bcrypt_hash(cur, password: str) -> str:
    """The bcrypt hash of the password, in the format GoTrue expects."""
    cur.execute("SELECT extensions.crypt(%s, extensions.gen_salt('bf', 10))", (password,))
    digest = cur.fetchone()[0]
    if not digest or not digest.startswith("$2a$10$"):
        raise RuntimeError(f"unexpected bcrypt hash: {digest!r}")
    return digest


def role_of(cur, role_code: str) -> dict:
    """The role the account will be given."""
    cur.execute(
        "SELECT role_id, role_code, role_name, role_level, is_active FROM public.role WHERE role_code = %s",
        (role_code,),
    )
    row = cur.fetchone()
    if row is None:
        raise RuntimeError(f"there is no role {role_code}")
    if not row[4]:
        raise RuntimeError(f"the role {role_code} is not active")
    cur.execute("SELECT count(*) FROM public.role_permission WHERE role_id = %s", (row[0],))
    permissions = cur.fetchone()[0]
    return {
        "role_id": row[0],
        "role_code": row[1],
        "role_name": row[2],
        "role_level": row[3],
        "permissions": permissions,
    }


def existing_accounts(cur) -> list[dict]:
    """Every account that is already there."""
    cur.execute(
        """
        SELECT u.email, m.user_id, ua.account_status,
               (SELECT string_agg(r.role_code, ', ' ORDER BY r.role_code)
                  FROM public.user_role_assignment ura
                  JOIN public.role r ON r.role_id = ura.role_id
                 WHERE ura.user_id = m.user_id) AS roles
          FROM auth.users u
          LEFT JOIN sims_private.auth_identity_map m ON m.auth_user_id = u.id
          LEFT JOIN public.user_account ua ON ua.user_id = m.user_id
         ORDER BY u.created_at
        """
    )
    return [
        {"email": r[0], "user_id": r[1], "account_status": r[2], "roles": r[3]}
        for r in cur.fetchall()
    ]


def verify_login(url: str, key: str, email: str, password: str) -> tuple[bool, str]:
    """Try to sign in with the new password and report what happened."""
    body = json.dumps({"email": email, "password": password}).encode("utf-8")
    request = urllib.request.Request(
        f"{url.rstrip('/')}/auth/v1/token?grant_type=password",
        data=body,
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.loads(response.read().decode("utf-8"))
            return bool(payload.get("access_token")), "signed in successfully"
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8")[:200]
        return False, f"HTTP {exc.code}: {detail}"
    except Exception as exc:  # noqa: BLE001
        return False, str(exc)


def verify_context(cur, auth_user_id: str) -> tuple[bool, str]:
    """Resolve `public.my_context()` for the new user.

    `my_context()` returns `jsonb`, so the payload is read as a JSON document.
    The call runs as `authenticated` with the new user's subject in the JWT
    claims, which is exactly what the Data API does.
    """
    cur.execute("SELECT set_config('request.jwt.claim.sub', %s, false)", (auth_user_id,))
    cur.execute(
        "SELECT set_config('request.jwt.claims', %s, false)",
        (json.dumps({"sub": auth_user_id, "role": "authenticated"}),),
    )
    cur.execute("SET ROLE authenticated")
    try:
        cur.execute("SELECT public.my_context()")
        row = cur.fetchone()
    except Exception as exc:  # noqa: BLE001
        return False, str(exc).strip().splitlines()[0]
    finally:
        cur.execute("RESET ROLE")
        cur.execute("RESET request.jwt.claim.sub")
        cur.execute("RESET request.jwt.claims")
    if row is None or row[0] is None:
        return False, "my_context() returned nothing"
    payload = row[0] if isinstance(row[0], dict) else json.loads(row[0])
    return True, (
        f"user_id={payload.get('user_id')} roles={payload.get('roles')} "
        f"modules={len(payload.get('readable_modules') or [])} "
        f"permissions={len(payload.get('permissions') or [])}"
    )


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument(
        "--apply",
        action="store_true",
        help="create the account (without it the tool only prints the plan)",
    )
    ap.add_argument("--dry-run", action="store_true", help="print the plan and stop (the default)")
    ap.add_argument("--email", default="", help=f"the email address (default {DEFAULT_EMAIL})")
    ap.add_argument("--password", default="", help="the password (generated when it is missing)")
    ap.add_argument(
        "--generate",
        action="store_true",
        help="always generate a new password, even when --password is given",
    )
    ap.add_argument("--role", default="", help=f"the role to assign (default {DEFAULT_ROLE})")
    ap.add_argument(
        "--verify",
        action="store_true",
        help="do not create anything: check an existing account instead",
    )
    ap.add_argument("--json", action="store_true", help="machine readable report")
    args = ap.parse_args()

    url = pick(["SUPABASE_URL", "NEXT_PUBLIC_SUPABASE_URL"], DEFAULT_URL)
    key = pick(
        ["SUPABASE_PUBLISHABLE_KEY", "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", "SUPABASE_ANON_KEY"],
        DEFAULT_KEY,
    )

    email = args.email or pick(["SUPABASE_ADMIN_EMAIL", "ADMIN_EMAIL"]) or DEFAULT_EMAIL
    role_code = args.role or pick(["SUPABASE_ADMIN_ROLE", "ADMIN_ROLE"]) or DEFAULT_ROLE
    password = args.password or pick(["SUPABASE_ADMIN_PASSWORD", "ADMIN_PASSWORD"])
    if args.generate:
        password = ""
    generated = not password
    if not password:
        password = generate_password()
    if len(password) < 8:
        print("the password must be at least 8 characters long", file=sys.stderr)
        return 2

    # --- the plan ------------------------------------------------------------
    conn = connect(readonly=True)
    try:
        cur = conn.cursor()
        role = role_of(cur, role_code)
        accounts = existing_accounts(cur)
        clash = next((a for a in accounts if a["email"].lower() == email.lower()), None)
    finally:
        conn.close()

    if clash and not args.verify:
        print(f"there is already an account for {email} (user_id {clash['user_id']})", file=sys.stderr)
        print("use tools/reset_admin_password.py to give it a known password", file=sys.stderr)
        return 2

    if args.verify:
        # --- verify an existing account --------------------------------------
        conn = connect(readonly=True)
        try:
            cur = conn.cursor()
            cur.execute(
                "SELECT auth_user_id FROM sims_private.auth_identity_map WHERE user_id = %s",
                (clash["user_id"],),
            )
            row = cur.fetchone()
            if row is None:
                print(f"the account {email} is not linked to a SIMS user", file=sys.stderr)
                return 2
            auth_user_id = str(row[0])
            ok_context, detail_context = verify_context(cur, auth_user_id)
        finally:
            conn.close()

        ok_login, detail_login = verify_login(url, key, email, password)
        report = {
            "mode": "verify",
            "email": email,
            "auth_user_id": auth_user_id,
            "user_id": clash["user_id"],
            "roles": clash["roles"],
            "login_verified": ok_login,
            "login_detail": detail_login,
            "context_verified": ok_context,
            "context_detail": detail_context,
        }
        if args.json:
            print(json.dumps(report, indent=1))
        else:
            print(f"account   : {email}  (user_id {clash['user_id']}, roles {clash['roles']})")
            print(f"login     : {'OK - ' + detail_login if ok_login else 'FAILED - ' + detail_login}")
            print(f"my_context: {'OK - ' + detail_context if ok_context else 'FAILED - ' + detail_context}")
        return 0 if (ok_login and ok_context) else 1

    if not args.apply:
        if args.json:
            print(
                json.dumps(
                    {
                        "mode": "dry-run",
                        "email": email,
                        "password": password,
                        "generated": generated,
                        "role": role,
                        "existing_accounts": accounts,
                    },
                    indent=1,
                )
            )
            return 0
        print(f"database : {dsn()['dbname']} on {dsn()['host']}")
        print(f"email    : {email}")
        print(f"password : {password}" + ("  (generated)" if generated else ""))
        print(
            f"role     : {role['role_code']} ({role['role_name']}) at {role['role_level']} scope, "
            f"{role['permissions']} permissions"
        )
        print("")
        print("dry run: nothing was written. Use --apply to create the account.")
        return 0

    # --- apply ---------------------------------------------------------------
    auth_user_id = str(uuid.uuid4())
    conn = connect(readonly=False)
    try:
        cur = conn.cursor()
        digest = bcrypt_hash(cur, password)

        # 1. the credential
        #    `confirmed_at` is a generated column on the live project, so it is
        #    not written here - it follows `email_confirmed_at`.
        cur.execute(
            """
            INSERT INTO auth.users (
                instance_id, id, aud, role, email, encrypted_password,
                email_confirmed_at, confirmation_token, recovery_token,
                email_change_token_new, email_change, phone_change,
                phone_change_token, reauthentication_token,
                email_change_token_current, email_change_confirm_status,
                raw_app_meta_data, raw_user_meta_data, is_super_admin,
                created_at, updated_at, is_sso_user, is_anonymous
            ) VALUES (
                '00000000-0000-0000-0000-000000000000', %s, 'authenticated', 'authenticated',
                %s, %s, now(), '', '', '', '', '', '', '', '', 0,
                '{"provider":"email","providers":["email"]}'::jsonb,
                '{"email_verified": true}'::jsonb, false,
                now(), now(), false, false
            )
            """,
            (auth_user_id, email, digest),
        )

        # 2. the email provider identity
        #    `auth.identities.email` is a generated column
        #    (`lower(identity_data ->> 'email')`), so it is not written here.
        cur.execute(
            """
            INSERT INTO auth.identities (
                provider_id, user_id, identity_data, provider, last_sign_in_at,
                created_at, updated_at
            ) VALUES (
                %s, %s, %s::jsonb, 'email', now(), now(), now()
            )
            """,
            (
                auth_user_id,
                auth_user_id,
                json.dumps(
                    {
                        "sub": auth_user_id,
                        "email": email,
                        "email_verified": True,
                        "phone_verified": False,
                    }
                ),
            ),
        )

        # 3. the SIMS account
        cur.execute(
            """
            INSERT INTO public.user_account (
                username, password_hash, email, account_status, must_change_password,
                multi_factor_enabled, failed_login_count, password_changed_at,
                last_login_at, created_at, updated_at
            ) VALUES (%s, '!supabase-auth', %s, 'ACTIVE', false, false, 0, now(), now(), now(), now())
            RETURNING user_id
            """,
            (email, email),
        )
        user_id = cur.fetchone()[0]

        # 4. the link between the two
        cur.execute(
            "SELECT sims_private.link_auth_user(%s, %s, %s)",
            (auth_user_id, user_id, "tools/create_test_admin.py"),
        )

        # 5. the role
        cur.execute(
            """
            INSERT INTO public.user_role_assignment (
                user_id, role_id, scope_type, valid_from, assignment_status,
                is_primary, assignment_reason
            ) VALUES (%s, %s, %s, now(), 'ACTIVE', false, %s)
            """,
            (user_id, role["role_id"], role["role_level"], "Created by tools/create_test_admin.py"),
        )

        conn.commit()
    except Exception as exc:
        conn.rollback()
        print(f"the account could not be created, the transaction was rolled back:\n  {exc}", file=sys.stderr)
        return 1
    finally:
        conn.close()

    ok_login, detail_login = verify_login(url, key, email, password)

    conn = connect(readonly=True)
    try:
        cur = conn.cursor()
        ok_context, detail_context = verify_context(cur, auth_user_id)
    finally:
        conn.close()

    report = {
        "mode": "apply",
        "email": email,
        "password": password,
        "generated": generated,
        "auth_user_id": auth_user_id,
        "user_id": user_id,
        "role": role,
        "login_verified": ok_login,
        "login_detail": detail_login,
        "context_verified": ok_context,
        "context_detail": detail_context,
    }

    if args.json:
        print(json.dumps(report, indent=1))
        return 0 if (ok_login and ok_context) else 1

    print(f"account created for {email}")
    print(f"  auth_user_id : {auth_user_id}")
    print(f"  user_id      : {user_id}")
    print(f"  role         : {role['role_code']} at {role['role_level']} scope")
    print(f"  password     : {password}" + ("  (generated)" if generated else ""))
    print(f"  login        : {'OK - ' + detail_login if ok_login else 'FAILED - ' + detail_login}")
    print(f"  my_context() : {'OK - ' + detail_context if ok_context else 'FAILED - ' + detail_context}")
    return 0 if (ok_login and ok_context) else 1


if __name__ == "__main__":
    raise SystemExit(main())
