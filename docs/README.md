# SIMS documentation

The documentation set for the College-ERP / SIMS project at `F:\sims\College-ERP`.

Everything here was written against the **live Supabase project**
(`khqqfgqvwdxlqkncwtmh`, read-only), the authoritative MySQL dump
`SIMS-DatabaseWithoutLessonPlan.sql`, and the source tree. No object name, route,
function or permission code in these documents is invented. Where something is
missing or broken, the document says so.

---

## The documents

| Document | What it answers | Kind |
|---|---|---|
| [RTM.md](RTM.md) | Which database module maps to which tables, RPCs, route and access code, and what is still missing. One row per module. | Hand-written from live data |
| [MODULE_DOCUMENTATION.md](MODULE_DOCUMENTATION.md) | What each screen actually does, which migration backs it, and how the screen groups relate to the schema's numbered modules. | Recovered, then extended |
| [NAVIGATION.md](NAVIGATION.md) | The sidebar contract: 21 groups, 29 routes, the four visibility gates, breadcrumb resolution, and the unit test that keeps it honest. | Hand-written from `src/lib/nav.ts` |
| [RLS_SECURITY_MODEL.md](RLS_SECURITY_MODEL.md) | How authorisation really works: identity, the permission grammar, scope containment, DENY-wins, SELF scope, the sensitive-resource rule, and nine open holes plus two that were found and fixed. | Hand-written from live policies |
| [AUTHENTICATION_AND_RBAC.md](AUTHENTICATION_AND_RBAC.md) | Identity mapping, effective permissions, the `sims_private` helpers, and what is not done yet. | Recovered verbatim |
| [ROLE_PERMISSION_MATRIX.md](ROLE_PERMISSION_MATRIX.md) | The per-role grant matrix. | Recovered verbatim; the generator was restored at 23:48:38 and reproduces the file byte for byte |
| [SCHEMA.md](SCHEMA.md) | Every table, column, function, policy and trigger of the live project. | Generated from the live catalogue |
| [SCHEMA_RECONCILIATION.md](SCHEMA_RECONCILIATION.md) | The MySQL source against the migration set, table by table. | Generated from the live catalogue and `tools/catalogue/mysql_reference.json` |
| [RLS_POLICY_MAP.md](RLS_POLICY_MAP.md) | The per-table policy to permission map, with totals. | Generated from the live catalogue |
| [DATABASE_MIGRATION.md](DATABASE_MIGRATION.md) | The MySQL 8 to PostgreSQL translation: what was executed, the equivalence report, deliberate divergences, and the source defects found. | Recovered verbatim |
| [RECOVERY.md](RECOVERY.md) | How this tree came to exist: the deletion incident, what survived, the recovery ceiling, and a file-by-file provenance ledger. | Hand-written from the session log |

### Suggested reading order

1. [MODULE_DOCUMENTATION.md](MODULE_DOCUMENTATION.md) - what the system is.
2. [RTM.md](RTM.md) - how it maps to the database.
3. [NAVIGATION.md](NAVIGATION.md) - how it is reached.
4. [RLS_SECURITY_MODEL.md](RLS_SECURITY_MODEL.md) - what is actually permitted.
5. [RECOVERY.md](RECOVERY.md) - how much of this you can trust as original.

---

## npm scripts and the tooling

`package.json` declares the data-related scripts. All of them run.

| Script | Command | Target | Runs? |
|---|---|---|---|
| `verify` | `node tools/verify.mjs` | `tools/verify.mjs` | Yes - runs every check below in one command and exits 0 only when all of them pass |
| `docs:roles` | `node tools/validate/role_matrix.mjs` | `tools/validate/role_matrix.mjs` | Yes - renders `docs/ROLE_PERMISSION_MATRIX.md` from the **live** project; `--check` compares without writing |
| `docs:schema` | `node tools/validate/schema_doc.mjs` | `tools/validate/schema_doc.mjs` | Yes - renders `docs/SCHEMA.md` and `docs/SCHEMA_RECONCILIATION.md` from the **live** catalogue; `--check` compares without writing |
| `migrate:catalogue` | `node tools/validate/catalogue.mjs && python tools/compare_catalogue.py` | both files present | Yes - dumps the **live** catalogue read-only and diffs it against the expected contract |
| `migrate:build` | `python tools/translate.py && python tools/build_migrations.py` | both files present | Yes - rewrites `supabase/migrations/` (64 files) |
| `migrate:apply` | `python tools/apply_migrations.py` | `tools/apply_migrations.py` | Yes - **dry run by default**; `--apply` is the only way to write |
| `seed:apply` | `python tools/apply_demo_seed.py` | `tools/apply_demo_seed.py` | Yes - **dry run by default**; `--apply` is the only way to write |
| `admin:create` | `node tools/create_admin.mjs` | `tools/create_admin.mjs` | Yes - **dry run by default**; `--apply` is the only way to write |
| `admin:password` | `python tools/reset_admin_password.py` | `tools/reset_admin_password.py` | Yes - **dry run by default**; `--apply` is the only way to write |
| `migrate:apply-check` | `node tools/validate/apply.mjs` | `tools/validate/apply.mjs` | Yes |
| `migrate:seed-check` | `node tools/validate/seed_counts.mjs` | `tools/validate/seed_counts.mjs` | Yes |
| `test:db` | `vitest run tests/db` | `tests/db/` | Yes |
| `test:unit` | `vitest run tests/unit` | `tests/unit/` | Yes |
| `test:e2e` | `playwright test` | `tests/e2e/` | Yes - needs a production build and, for the signed-in project, `SIMS_TEST_EMAIL` / `SIMS_TEST_PASSWORD` |
| `test:e2e:smoke` | `playwright test tests/e2e/smoke.spec.ts` | `tests/e2e/smoke.spec.ts` | Yes - the signed-in route sweep; skips itself without the credentials |

Every tool is **safe by default**. The four that can write to the remote project -
`migrate:apply`, `seed:apply`, `admin:create` and `admin:password` - print a
plan and exit without touching anything unless `--apply` is passed explicitly.

### How the catalogue tools work

`tools/validate/catalogue.mjs` dumps the **live** project. The session is
switched to `default_transaction_read_only = on` before the first query, so the
dump cannot write to the database even by accident. The result is written to
`tools/catalogue/live_catalogue.json`, which is the input of
`tools/build_migrations.py`.

`tools/compare_catalogue.py` then diffs that dump against
`tools/catalogue/expected_catalogue.json`, the contract the project has to
satisfy. The report is grouped by kind - `tables`, `columns`, `functions`,
`policies`, `triggers`, `grants`, `sequences` - plus the headline `counts`, the
per-schema counts and the seeded `row_counts`. The contract's optional
`objects` section carries a SHA-256 of every function, trigger and policy
definition, so a changed body is a difference too.

`tools/validate/schema_doc.mjs` renders `docs/SCHEMA.md` from the live
catalogue and `docs/SCHEMA_RECONCILIATION.md` from the comparison with
`tools/catalogue/mysql_reference.json`. `tools/validate/role_matrix.mjs`
renders `docs/ROLE_PERMISSION_MATRIX.md` from the live `role`,
`role_permission` and `permission` tables. Both support `--check`, so a stale
document is a non-zero exit code rather than a silent diff. When the project
cannot be reached they fall back differently: `schema_doc.mjs` reads the
committed dump `tools/catalogue/live_catalogue.json` (`--source file`),
`role_matrix.mjs` rebuilds the schema from the migration set in an embedded
PostgreSQL (`--source rebuilt`).

### The rest of the tool surface

| File | What it does |
|---|---|
| `tools/translate.py` | Translates the MySQL reference schema into `tools/catalogue/mysql_reference.json`. Never talks to a database. `--check` reports whether the document is current. Reached through `migrate:build`. |
| `tools/apply_migrations.py` | Applies `supabase/migrations/*.sql` to the project, one transaction per file, tracked in `sims_private.schema_migration`. Dry run unless `--apply`. `--baseline-before FILENAME` records the files that sort before `FILENAME` as applied **without running them**, which is how a database that already carries the schema but has no tracking table is adopted. |
| `tools/apply_demo_seed.py` | Writes `tools/seed_demo.sql` to the project in **one** transaction. Dry run unless `--apply`. Refuses any statement that would change more than the demo rows: `DELETE`, `TRUNCATE`, `DROP`, `ALTER TABLE`, or an `UPDATE` without a `DEMO-` key. |
| `tools/create_admin.mjs` | Creates the first administrator through the Supabase Admin API and links it to `public.user_account` with the `SUPER_ADMIN` role. Dry run unless `--apply`. |
| `tools/create_test_admin.py` | Creates a test administrator with a **direct database connection**, so it works without `SUPABASE_SERVICE_ROLE_KEY`. Writes `auth.users`, `auth.identities`, `public.user_account`, `sims_private.auth_identity_map` and `public.user_role_assignment` in one transaction, then proves the account works. `--verify` checks an existing account instead. Dry run unless `--apply`. |
| `tools/reset_admin_password.py` | Replaces the bcrypt hash of an existing Auth account and proves the new password through the Auth REST API. Dry run unless `--apply`. |
| `tools/compare_catalogue.py` | Compares the live catalogue with the expected contract. Reached through `migrate:catalogue`. |
| `tools/validate/pg_catalogue.mjs` | Shared helper: applies the migrations to PGlite and dumps the catalogue. Imported by `catalogue.mjs` and `role_matrix.mjs`. |
| `tools/validate/nav_rbac_connectivity.py` | Read-only verifier: every nav module against its RLS tables, RPCs and role permissions. |
| `tools/validate/seed_columns.py` | Checks the reference seed's columns against the live schema. |
| `tools/dump_catalogue.py` | Writes `tools/catalogue/live_catalogue.json` and `tools/catalogue/live_seed_data.json` from the **live** project. |
| `tools/build_migrations.py` | Regenerates `supabase/migrations/*.sql` from the catalogue and the MySQL reference. Reached through `migrate:build`. |
| `tools/build_rls.py` | Regenerates the RLS policy migration from the catalogue. |
| `tools/seed_demo.sql` | The demo reference seed. |
| `tools/verify.mjs` | Runs the whole suite in one command: typecheck, lint, unit tests, database tests, production build, the live nav/RBAC matrix, the seed column validation, the role matrix check, the schema document check, the catalogue check, the migration apply dry run, the demo seed dry run and - when `SIMS_TEST_EMAIL` / `SIMS_TEST_PASSWORD` are set - the signed-in end-to-end suite. Exits 0 only when every step passes. `--fast` skips the production build (and with it the end-to-end suite), `--no-e2e` skips the end-to-end suite alone. Reached through `verify`. |
| `tests/e2e/smoke.spec.ts` | The signed-in smoke test: every application route is opened with a real SUPER_ADMIN session and must leave the `Loading…` state, render content and log no console error. Credentials come from `SIMS_TEST_EMAIL` / `SIMS_TEST_PASSWORD`; without them the suite is skipped, not failed. Reached through `test:e2e:smoke`. |
| `tests/e2e/global-setup.ts` | Signs in **once** for the whole Playwright run and writes the session to `playwright/.auth/sims.json`. Supabase throttles the password grant endpoint, so a suite that signs in per test runs into `Request rate limit reached`. |
| `tests/e2e/signin.spec.ts` | The sign-in form itself: a valid password lands on the dashboard, a wrong one is refused. Runs anonymously. |
| `tools/work/run_seed.mjs`, `tools/work/run_seed_step.mjs` | Scratch runners for the seed. `tools/work/` is a scratch area, not a tool surface. |

### Consequences

- `docs/SCHEMA.md`, `docs/SCHEMA_RECONCILIATION.md` and
  `docs/ROLE_PERMISSION_MATRIX.md` are generated artefacts. `npm run docs:schema
  -- --check` and `npm run docs:roles -- --check` both exit 0, so all three are
  current against the live project.
- `tools/translate.py` is back (23:54:54) and `npm run migrate:build` runs the
  whole chain: the MySQL reference is translated, the builder cross-checks it
  against the live catalogue and regenerates the 64 migration files. The build
  is deterministic - two consecutive runs produce byte-identical files.
- `docs/RLS_POLICY_MAP.md` **was** generated from the live catalogue after the
  rebuild and is current.
- The live project grants `authenticated` SELECT on every **column** of 212 of
  the 213 public tables, not on the tables themselves. The catalogue captures
  that (`pg_attribute.attacl`), the migration set reproduces it (212 column
  grants in migration 021), and `tests/db/rls.test.ts` asserts it. A read that
  names a column is allowed; `SELECT *` is refused on the six tables that hide
  a column. See S-11 in
  [RLS_SECURITY_MODEL.md](RLS_SECURITY_MODEL.md).


---

## Verifying the claims in these documents

Everything below is read-only and safe to run. The four tools that can write -
`migrate:apply`, `seed:apply`, `admin:create` and `admin:password` - are listed
without `--apply`, so they print their plan and stop.

```bash
# everything, in one command
npm run verify

# every nav href resolves to a page, every nav module is seeded,
# every seeded code is used or allowlisted, every href has an icon,
# and the group order is locked
npm run test:unit

# the reference seed matches the live schema
npm run migrate:seed-check

# the migrations on disk match what is applied to the live database
npm run migrate:apply-check

# every nav module against its RLS tables, RPCs and role permissions
python tools/validate/nav_rbac_connectivity.py

# translate the MySQL reference and regenerate the migration set
npm run migrate:build

# dump the live catalogue and diff it against the expected contract
npm run migrate:catalogue

# render the schema documents and the role matrix in memory and compare
# them with the committed files
npm run docs:schema -- --check
npm run docs:roles -- --check

# the plan of the migration applier - writes nothing without --apply
npm run migrate:apply

# the plan of the demo seed applier - writes nothing without --apply
npm run seed:apply

# the plan of the administrator bootstrap - writes nothing without --apply
npm run admin:create

# the plan of the password reset - writes nothing without --apply
npm run admin:password

# every route, signed in, with a real session (needs the credentials)
$env:SIMS_TEST_EMAIL='...'
$env:SIMS_TEST_PASSWORD='...'
npm run test:e2e:smoke
```

The `nav_rbac_connectivity.py` and `migrate:catalogue` commands need
`SUPABASE_DB_PASSWORD` in the environment and a read-only database role.

**The database password is never stored in the repository.** All four tools that
open a direct connection - `tools/dump_catalogue.py`,
`tools/apply_migrations.py`, `tools/validate/catalogue.mjs` and
`tools/create_admin.mjs` - read it from `SUPABASE_DB_PASSWORD` (or
`SIMS_DB_PASSWORD`) and refuse to run with a clear message when it is missing.
Put it into `.env.local`, which is gitignored. `tools/create_admin.mjs`
additionally needs `SUPABASE_SERVICE_ROLE_KEY`, which is server-side only.

Current results:

- `nav_rbac_connectivity.py` has exactly one finding: `REPORTING` has permissions
  but no RLS policy and no function that checks them (gap G-1 in
  [RTM.md](RTM.md)). The tool reports it under `KNOWN GAPS` and exits 0, so a
  *new* problem still fails the run; `--strict` fails on the known gap too.
- `migrate:catalogue` reports **0 differences**: the live project agrees with
  the contract on the counts, the per-schema counts, the seeded row counts and
  every object of all seven kinds (222 tables, 2140 columns, 420 functions,
  594 policies, 140 triggers, 6223 grants, 199 sequences). The tool exits 0
  with `OK - the live catalogue matches the expected catalogue`.
- `docs:schema -- --check` and `docs:roles -- --check` both exit 0: the
  committed `docs/SCHEMA.md`, `docs/SCHEMA_RECONCILIATION.md` and
  `docs/ROLE_PERMISSION_MATRIX.md` are byte-identical to what the generators
  produce from the live project.
- `migrate:build` regenerates all 64 migration files and is deterministic: two
  consecutive runs produce byte-identical files.
- `migrate:apply` prints the plan for all 64 files and writes nothing.
- `seed:apply` prints the plan for the 58 statements of `tools/seed_demo.sql`
  and the row count of every one of the 51 tables it writes to, and writes
  nothing. The tool refuses to run a statement that would change more than the
  demo rows (`DELETE`, `TRUNCATE`, `DROP`, `ALTER TABLE`, or an `UPDATE`
  without a `DEMO-` key).
- `admin:create` refuses to run without `SUPABASE_SERVICE_ROLE_KEY` and exits
  2 with the reason.


---

## The demo data on the live project

The live project now carries data you can click through.

### The reference seeds

Migration `064_required_reference_seeds.sql` was applied on 2026-11-08. It
fills the lookup tables the application reads on every screen - `gender`,
`blood_group`, `religion`, `social_category`, `caste`, `sub_caste`, `country`,
`state`, `admission_category`, `fee_type`, `concession_type`,
`scholarship_scheme`, `grade_scale`, `attendance_status`, `announcement_type`
and `course_category` - with the rows the MySQL reference defines. Every
insert is `ON CONFLICT DO NOTHING`, so re-running it is harmless.

The migration tracker `sims_private.schema_migration` did not exist on the
project. The files `001` to `063` were therefore **baselined** - recorded as
applied without being executed, because the project already carried that
schema:

```bash
python tools/apply_migrations.py --apply --baseline-before 064_required_reference_seeds.sql
```

All 64 files are now tracked. `python tools/apply_migrations.py` reports
`64 migration file(s), 0 pending, 0 changed`.

### The demo tenant

`tools/seed_demo.sql` was applied with `npm run seed:apply -- --apply`. It
writes **151 rows into 51 tables** in one transaction, and it is idempotent:
every insert is guarded by `NOT EXISTS`, so a second run writes nothing.

| | |
|---|---|
| Institution | Demo Institute of Technology, one campus, two departments |
| Programmes | BSc Computer Science, MBA |
| Students | 3 - Asha Rao (`DEMO-S001`), Kabir Shah (`DEMO-S002`), Meera Iyer (`DEMO-S003`) |
| Staff | 2 - Anita Rao (`DEMO-E001`), Vikram Desai (`DEMO-E002`) |
| Teaching | 2 course offerings, 2 sections, 6 registrations, 3 class sessions |
| Attendance | 9 rows - 7 PRESENT, 1 LATE, 1 ABSENT |
| Assessment | 4 components, 4 events, 12 marks, 6 course results, 3 term results |
| Fees | gross 153000, concession 5000, net 148000, paid 50000, balance 98000, receipt `REC/2026-27/000001` |
| Communication | 2 announcements, 3 announcement types |
| Activities | 1 staff activity, 2 student activities |

The seed creates **no user accounts** - a SIMS user needs a Supabase Auth
identity, which cannot be created from SQL.

### Signing in

| Email | Password | Role |
|---|---|---|
| `sims.test.admin@gmail.com` | `SimsTest@2026` | `SUPER_ADMIN` (GLOBAL) - 22 modules, 349 permissions |

The password is **not** stored in the repository. It was set when the account
was created with `tools/create_test_admin.py --apply`, and it can be replaced
at any time with `npm run admin:password -- --apply --email sims.test.admin@gmail.com --generate`.

### The signed-in smoke test

```bash
# the whole suite: every route, signed in, with a real session
$env:SIMS_TEST_EMAIL='sims.test.admin@gmail.com'
$env:SIMS_TEST_PASSWORD='...'
npm run test:e2e:smoke
```

`tests/e2e/smoke.spec.ts` opens all 47 application routes and asserts three
things per route: the page leaves the `Loading…` state, `<main>` has real
content, and nothing was written to the browser console as an error. The
`/no-access` page gets its own assertion, because it lives outside the
application shell and has no `<main>`.

**One sign-in for the whole run.** Supabase throttles the password grant
endpoint, so a suite that signs in once per test runs into `Request rate
limit reached` after a few dozen tests. `tests/e2e/global-setup.ts` therefore
signs in **once**, through the real form, and writes the session to
`playwright/.auth/sims.json`; the tests read it as a Playwright storage state.
The file is gitignored and is rewritten on every run. The global setup retries
with a back-off when the Auth endpoint is throttling.

The suite is split into two projects so that the anonymous tests keep starting
without a session:

| Project | Tests | Session |
|---|---|---|
| `chromium` | `tests/e2e/auth.spec.ts` (route protection), `tests/e2e/signin.spec.ts` (the form) | none - except the sign-in test, which drives the form |
| `chromium-signed-in` | `tests/e2e/smoke.spec.ts` (every route) | the storage state |

Without `SIMS_TEST_EMAIL` / `SIMS_TEST_PASSWORD` the signed-in project is left
out and the tests that need it skip themselves, so a checkout without a test
account still has a green build.

**A note on the `Loading…` state.** Next.js streams the page: the shell and the
Suspense fallback arrive first, the resolved content follows in a later chunk.
The test therefore waits for the **content**, not for the fallback to vanish -
at the moment the document is parsed the fallback may not even be attached yet.
React then reveals the streamed boundary with `requestAnimationFrame`. A
browser that is not painting - a background tab, a headless run that never
composites - never fires that callback, so the boundary stays pending even
though the server sent the content. The page is not broken; the compositor
never ran. The test therefore flushes React's own reveal queue if the content
does not arrive in time, and the assertion stays about the application rather
than about the browser.


---

## Where the facts come from

| Fact | Source of truth |
|---|---|
| Module numbers and names | The section headers of `SIMS-DatabaseWithoutLessonPlan.sql` (42 headers, 213 tables). |
| Table, view, function, trigger and policy counts | The live database, read with `SELECT` only. |
| Permission codes and role grants | `public.permission`, `public.role_permission` on the live database. |
| Navigation | `src/lib/nav.ts` - the single source of truth. |
| Route existence | `src/app/**/page.tsx` on disk. |
| File provenance | The opencode session log; see [RECOVERY.md](RECOVERY.md). |

---

## A note on the two numberings

The schema numbers its modules `1..40` with two sections numbered `18` and one
numbered `17A`. `docs/MODULE_DOCUMENTATION.md` uses an older `1..23` *screen*
numbering. Both are real; they answer different questions. The reconciliation
table is in [MODULE_DOCUMENTATION.md](MODULE_DOCUMENTATION.md) under
"Schema modules vs. screen groups", and [RTM.md](RTM.md) uses the schema
numbering throughout.
