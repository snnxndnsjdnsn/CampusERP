# Authentication and RBAC

Status 2026-11-08: **database layer implemented, tested on embedded Postgres, and applied to the live project.** The Next.js auth flows (login, forgot/reset password, sessions, protected routes) are built **and have been exercised signed in against the live project**: a test administrator signs in through the real form, every route renders, and `public.my_context()` resolves 22 readable modules and 349 permissions.

## Signing in

The live project has **three** Supabase Auth accounts. All are linked to a
`SUPER_ADMIN` role at `GLOBAL` scope:

| Auth user | `user_account.user_id` | Roles | Status | Password |
|---|---|---|---|---|
| `ayushchugani@gmail.com` | 1 | `SUPER_ADMIN` (GLOBAL) | ACTIVE | **not recoverable** |
| `12vsatish1@gmail.com` | 2 | `SUPER_ADMIN` (GLOBAL) | ACTIVE | **not recoverable** |
| `sims.test.admin@gmail.com` | 3 | `SUPER_ADMIN` (GLOBAL) | ACTIVE | known - set when the account was created |

**The passwords of the first two accounts are not recoverable.**
`auth.users.encrypted_password` holds a bcrypt hash, which cannot be reversed,
and `public.user_account.password_hash` holds the literal marker
`!supabase-auth` - "the credential belongs to Supabase Auth, not to this
database". The script that created them (`bootstrap_admin.py`) is gone, and no
password was ever written down.

A password can therefore only be **replaced**, never looked up. The tool for
that is `tools/reset_admin_password.py` (`npm run admin:password`):

```bash
# the plan - lists the accounts, writes nothing
npm run admin:password

# set a known password for one account and prove it works
python tools/reset_admin_password.py --apply --email ayushchugani@gmail.com --generate
```

It writes the bcrypt hash straight into `auth.users.encrypted_password` - the
same single-column update the Supabase dashboard performs - and then signs in
through the Auth REST endpoint with the project's publishable key to prove the
new password works. It touches nothing else: the `public.user_account` row, the
role assignment and the `sims_private.auth_identity_map` link are left alone.

### The test administrator

`tools/create_test_admin.py` creates a new administrator **without** the
`SUPABASE_SERVICE_ROLE_KEY` that the Admin API would need. It writes exactly
the rows the Admin API would write - `auth.users`, `auth.identities`,
`public.user_account`, `sims_private.auth_identity_map` and
`public.user_role_assignment` - in **one** transaction, and then proves the
account works by signing in through the Auth REST endpoint and resolving
`public.my_context()` for it.

```bash
# the plan - writes nothing
python tools/create_test_admin.py --email sims.test.admin@gmail.com --password '...'

# create it
python tools/create_test_admin.py --apply --email sims.test.admin@gmail.com --password '...'

# check an existing account
python tools/create_test_admin.py --verify --email sims.test.admin@gmail.com --password '...'
```

The role assignment takes its `scope_type` from `role.role_level`, because the
trigger `trg_user_role_assignment_scope_bi` refuses any other combination -
`SUPER_ADMIN` therefore gets `GLOBAL`.

The demo seed (`tools/seed_demo.sql`) deliberately creates **no** user
accounts: a SIMS user needs a Supabase Auth identity, which cannot be created
from SQL. Create the accounts in the dashboard (or with
`tools/create_admin.mjs`, which needs `SUPABASE_SERVICE_ROLE_KEY`), then link
them with `public.iam_link_auth_user(email, student_number, employee_number)`.

## Identity mapping
```
Supabase auth.users.id (uuid, from the verified JWT)
   └─ sims_private.auth_identity_map(auth_user_id PK, user_id UNIQUE)      -- no client privileges
        └─ public.user_account(user_id)  [must be account_status='ACTIVE' and not locked]
             ├─ student_user_account(student_id, user_id)                  -- source table
             └─ employee_user_account(employee_id, user_id)                -- source table
```
- An Auth user id is **never** assumed to equal a student/employee/user id.
- The map is written only by `sims_private.link_auth_user()` (granted to `service_role` only; also usable by a DB admin). `authenticated` cannot read or write the map or call the function (tested).
- `user_metadata` / `app_metadata` are never read. The only client-influenced input is `auth.uid()` from the signed JWT.
- `user_account.password_hash` is a leftover of the MySQL design. Supabase Auth owns credentials. Provisioned users should store a non-usable placeholder; the column is not client-readable (column-level privilege).
- Disabled / locked / pending accounts resolve to **no identity**, so every policy denies (tested).

## Effective permissions
Resolved by `sims_private.eff()` from the source view `v_effective_user_permission` (active role assignments incl. delegations + active overrides; **DENY wins at the same scope**). Added by this layer:
- **Scope containment**: a grant at GLOBAL / INSTITUTION / CAMPUS / DEPARTMENT / PROGRAMME covers rows below it in the hierarchy institution → campus → department → programme. (The source view returns exact-scope rows only; containment is implemented in `sims_private.covers()`.)
- **DENY at any covering scope overrides ALLOW** (decision, stricter than "exact scope only"; flagged for owner confirmation).
- **SELF** scope matches only rows that belong to the caller and is **read-only** through direct table access.
- Permission codes are `MODULE.RESOURCE.ACTION`. A module-wide grant `MODULE.ALL.ACTION` covers ordinary tables; **sensitive resources require their specific grant** (e.g. `EMPLOYEE.BANK_ACCOUNT.READ`, `FEES.FEE_PAYMENT.READ`), `ALL` is not enough.

## Helpers (schema `sims_private`, SECURITY DEFINER, `search_path` pinned, not exposed by the Data API)
`current_user_id/student_id/employee_id`, `eff`, `covers`, `can_global/institution/campus/department/programme`, `can_student/employee/user`, `is_active_member`, `link_auth_user`.

## Not done yet
- Login, logout, forgot / reset password, protected routes and session-expiry handling are built and **have been exercised signed in** against the live project: the test administrator signs in through the real form, lands on `/dashboard`, and all 47 application routes render with zero console errors (`tests/e2e/smoke.spec.ts`). The **forgot-password** flow reaches the Supabase `recover` endpoint but has not been driven all the way to a reset link, because that needs a mailbox.
- The Playwright suite signs in **once** for the whole run (`tests/e2e/global-setup.ts`) and reuses the session as a storage state. Supabase throttles the password grant endpoint, so a suite that signs in per test runs into `Request rate limit reached` after a few dozen tests.
- **Bootstrap**: done on the live project - three accounts, three `user_account` rows, three `SUPER_ADMIN` assignments and three identity links. The first two were created by a `bootstrap_admin.py` that no longer exists; the third by `tools/create_test_admin.py`. `tools/create_admin.mjs` covers the same ground through the Admin API but needs `SUPABASE_SERVICE_ROLE_KEY`.
- Role assignment, revocation and account activation / deactivation are built (migration 041, `/admin/users`). Permission overrides have RPCs and a card on `/admin/users/[id]` (migration 057); user creation with a linked person is `/admin/users/new` (M049). Still missing: linking an Auth user that already exists to a student or employee (KI-68). The full list of default grants is `ROLE_PERMISSION_MATRIX.md`.
- MFA is built (migration 045): the database consults `multi_factor_enabled` and demands an aal2 session; see KI-57 for what is not covered (a policy that forces MFA for privileged roles, a real-project run). Recovery codes are built (migration 056, KI-66).
