#!/usr/bin/env python3
"""Set the password of an existing Supabase Auth account.

Usage:
    python tools/reset_admin_password.py [--apply] [--email EMAIL] [--password SECRET]
                                         [--generate] [--json]

Without `--apply` the tool only prints the plan: which accounts exist, which one
would be changed and what the new password would be.  It never writes to the
database in that mode.  `--apply` is the only way to make it write, and it is
deliberately explicit.

Why this tool exists
--------------------
The password of a Supabase Auth user is a bcrypt hash in `auth.users`.
`public.user_account.password_hash` holds the literal string `!supabase-auth`,
a marker that says "the credential belongs to Supabase Auth, not to this
database".  The hash cannot be reversed, so an existing password can never be
recovered - only replaced.

This tool replaces it.  It writes the bcrypt hash straight into
`auth.users.encrypted_password`, which is exactly what the Supabase dashboard
does when an administrator resets a password.  It then proves the new password
works by calling the Auth REST endpoint with the project's publishable key.

The write is a single column update on a single row.  Nothing else in the
database is touched: the `public.user_account` row, the role assignment and
the `sims_private.auth_identity_map` link are all left alone.

Connection settings (the environment wins over the defaults):

    SUPABASE_DB_HOST      aws-0-ap-southeast-1.pooler.supabase.com
    SUPABASE_DB_PORT      5432
    SUPABASE_DB_NAME      postgres
    SUPABASE_DB_USER      postgres.khqqfgqvwdxlqkncwtmh
    SUPABASE_DB_PASSWORD  <the project password>
    SUPABASE_DB_SSLMODE   require

`SIMS_DB_*` is accepted as an alias for `SUPABASE_DB_*`.  The password is
never stored in the repository.

Exit code 0 means "the plan is clean" or "the password was changed", 1 means
"the change failed" and 2 means "the tool was not configured correctly".
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

#: The alphabet is deliberately free of characters that need escaping in SQL,
#: in a URL or in a shell.
ALPHABET = string.ascii_letters + string.digits


def pick(names, fallback: str = "") -> str:
    """The first environment variable that is set wins."""
    for name in names:
        value = os.environ.get(name)
        if value:
            return value
    return fallback


def generate_password() -> str:
    """A password that is long enough and has no characters that need escaping."""
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789"
    raw = "".join(secrets.choice(alphabet) for _ in range(24))
    return f"{raw[0:4]}-{raw[4:10]}-{raw[10:16]}-{raw[16:24]}"


def accounts(cur) -> list[dict]:
    """Every auth account, with the SIMS user it is linked to."""
    cur.execute(
        """
        SELECT u.id,
               u.email,
               u.email_confirmed_at,
               u.last_sign_in_at,
               m.user_id,
               ua.username,
               ua.account_status,
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
    rows = []
    for row in cur.fetchall():
        rows.append(
            {
                "auth_user_id": row[0],
                "email": row[1],
                "email_confirmed_at": row[2],
                "last_sign_in_at": row[3],
                "user_id": row[4],
                "username": row[5],
                "account_status": row[6],
                "roles": row[7],
            }
        )
    return rows


def bcrypt_hash(cur, password: str) -> str:
    """The bcrypt hash of the password, in the format GoTrue expects."""
    cur.execute("SELECT extensions.crypt(%s, extensions.gen_salt('bf', 10))", (password,))
    digest = cur.fetchone()[0]
    if not digest or not digest.startswith("$2a$10$"):
        raise RuntimeError(f"unexpected bcrypt hash: {digest!r}")
    return digest


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
            token = payload.get("access_token")
            return bool(token), "signed in successfully"
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8")[:200]
        return False, f"HTTP {exc.code}: {detail}"
    except Exception as exc:  # noqa: BLE001
        return False, str(exc)


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument(
        "--apply",
        action="store_true",
        help="change the password (without it the tool only prints the plan)",
    )
    ap.add_argument("--dry-run", action="store_true", help="print the plan and stop (the default)")
    ap.add_argument("--email", default="", help="the account to change")
    ap.add_argument("--password", default="", help="the new password (generated when it is missing)")
    ap.add_argument(
        "--generate",
        action="store_true",
        help="always generate a new password, even when --password is given",
    )
    ap.add_argument("--json", action="store_true", help="machine readable report")
    args = ap.parse_args()

    url = pick(["SUPABASE_URL", "NEXT_PUBLIC_SUPABASE_URL"], DEFAULT_URL)
    key = pick(
        ["SUPABASE_PUBLISHABLE_KEY", "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", "SUPABASE_ANON_KEY"],
        DEFAULT_KEY,
    )

    # --- the plan ------------------------------------------------------------
    conn = connect(readonly=True)
    try:
        cur = conn.cursor()
        found = accounts(cur)
    finally:
        conn.close()

    if not found:
        print("the project has no auth account", file=sys.stderr)
        return 2

    email = args.email or pick(["SUPABASE_ADMIN_EMAIL", "ADMIN_EMAIL"])
    if not email:
        if not args.apply:
            # The plan lists every account; the caller picks one.
            if args.json:
                print(json.dumps({"mode": "dry-run", "accounts": found}, indent=1))
                return 0
            print(f"database : {dsn()['dbname']} on {dsn()['host']}")
            print(f"{len(found)} auth account(s):")
            for account in found:
                print(
                    f"  {account['email']:40s} user_id={account['user_id']} "
                    f"roles={account['roles']} status={account['account_status']}"
                )
            print("")
            print("dry run: nothing was written. Use --apply --email EMAIL to set a password.")
            return 0
        print(
            "the account to change is missing: pass --email EMAIL or set SUPABASE_ADMIN_EMAIL",
            file=sys.stderr,
        )
        return 2

    target = next((a for a in found if a["email"].lower() == email.lower()), None)
    if target is None:
        print(f"there is no auth account for {email}", file=sys.stderr)
        for account in found:
            print(f"  {account['email']}", file=sys.stderr)
        return 2

    password = args.password or pick(["SUPABASE_ADMIN_PASSWORD", "ADMIN_PASSWORD"])
    if args.generate:
        password = ""
    if not password:
        password = generate_password()
        generated = True
    else:
        generated = False
    if len(password) < 8:
        print("the password must be at least 8 characters long", file=sys.stderr)
        return 2

    if not args.apply:
        if args.json:
            print(
                json.dumps(
                    {
                        "mode": "dry-run",
                        "account": target,
                        "password": password,
                        "generated": generated,
                    },
                    indent=1,
                )
            )
            return 0
        print(f"database : {dsn()['dbname']} on {dsn()['host']}")
        print(f"account  : {target['email']}  (auth_user_id {target['auth_user_id']})")
        print(f"sims user: {target['user_id']}  roles={target['roles']}")
        print(f"password : {password}" + ("  (generated)" if generated else ""))
        print("")
        print("dry run: nothing was written. Use --apply to change the password.")
        return 0

    # --- apply ---------------------------------------------------------------
    conn = connect(readonly=False)
    try:
        cur = conn.cursor()
        digest = bcrypt_hash(cur, password)
        cur.execute(
            "UPDATE auth.users SET encrypted_password = %s, updated_at = now() WHERE id = %s",
            (digest, target["auth_user_id"]),
        )
        changed = cur.rowcount
        if changed != 1:
            conn.rollback()
            print(f"the update touched {changed} rows, the transaction was rolled back", file=sys.stderr)
            return 1
        conn.commit()
    except Exception as exc:
        conn.rollback()
        print(f"the password could not be changed: {exc}", file=sys.stderr)
        return 1
    finally:
        conn.close()

    ok, detail = verify_login(url, key, target["email"], password)

    if args.json:
        print(
            json.dumps(
                {
                    "mode": "apply",
                    "account": target["email"],
                    "password": password,
                    "generated": generated,
                    "login_verified": ok,
                    "detail": detail,
                },
                indent=1,
            )
        )
        return 0 if ok else 1

    print(f"password changed for {target['email']}")
    print(f"password : {password}" + ("  (generated)" if generated else ""))
    print(f"login    : {'OK - ' + detail if ok else 'FAILED - ' + detail}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
