# College ERP / SIMS

A Student Information System built with **Next.js 16.4.5** (App Router,
Turbopack), **React 19**, **TypeScript** and **Supabase** (PostgreSQL + RLS).

The database is the authority: 213 public tables, 433 functions, 594 row-level
security policies and a role/permission model with 39 roles. Every screen
reads through RPCs that the policies guard - there is no client-side trust.

## Run it

```bash
cd F:\sims\College-ERP

# development (hot reload) - http://localhost:3000
npm run dev

# production
npm run build
npm run start
```

The site runs **on your machine**; there is no hosted copy. If port 3000
refuses the connection, the server is not running.

`.env.local` holds the Supabase URL, the publishable key and the database
password. It is gitignored. `.env.example` lists the variables; a fresh
checkout needs `NEXT_PUBLIC_SUPABASE_URL` and
`NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` to serve the app.

Sign in with one of the three test personas:

| Email | Password | Role | Scope | Reads |
|---|---|---|---|---|
| `sims.test.admin@gmail.com` | `SimsTest@2026` | `SUPER_ADMIN` | GLOBAL | 22 modules, 349 permissions |
| `sims.test.employee@gmail.com` | `SimsTest@2026` | `FACULTY` | DEPARTMENT | 14 modules - linked to employee `DEMO-E001` |
| `sims.test.student@gmail.com` | `SimsTest@2026` | `STUDENT` | SELF | 10 modules - linked to student `DEMO-S001` |

The employee and the student are created by
`tools/create_test_personas.py --apply`. The tool is a dry run unless
`--apply` is passed, and it needs `SUPABASE_DB_PASSWORD` in the environment.

## Verify it

```bash
# everything: typecheck, lint, unit + database tests, production build,
# the live nav/RBAC matrix, the catalogue diff, the migration and seed
# dry runs, and the signed-in end-to-end suite
npm run verify
```

The live-database checks need `SUPABASE_DB_PASSWORD` in the environment. The
signed-in end-to-end suite additionally needs `SIMS_TEST_EMAIL` and
`SIMS_TEST_PASSWORD`; without them it is skipped, not failed.

## Layout

| Path | What it holds |
|---|---|
| `src/app` | the routes - 50 application pages plus the auth pages |
| `src/lib/nav.ts` | the sidebar contract: 27 numbered module groups, plus the 15 staff sub-modules (schema modules 20–34) drawn under the staff group |
| `src/features` | one folder per module, each with its client and data layer, plus `admin` for the Manage panel the six editable screens share |
| `supabase/migrations` | 66 migrations - `001`-`063` are generated, `064`, `065` and `066` are hand-written |
| `tools` | the migration, catalogue, seed and verification tooling |
| `tests` | unit, database and Playwright suites |
| `docs` | the full documentation set - start at `docs/README.md` |

## The six new screens

Schema modules 18, 35, 36, 37, 38 and 39 describe the database itself rather
than a business area, and each one now has a screen of its own and its own
number in the sidebar:

| Module | Route | Sidebar label | Gate |
|---|---|---|---|
| 18 | `/schema/18` | 18 · Performance indexes & storage | `IAM` |
| 35 | `/schema/35` | 35 · Seed reference data | `IAM` **or** `STAFF_PROFILE` |
| 36 | `/schema/36` | 36 · Staff profile RBAC registration | `IAM` |
| 37 | `/reporting` | 37 · Reporting & search views | `REPORTING` |
| 38 | `/schema/38` | 38 · Staff profile performance indexes | `STAFF_PROFILE` **or** `IAM` |
| 39 | `/schema/39` | 39 · Data-integrity notes | `IAM` **or** `AUDIT` |

The index catalogue behind modules 18 and 38 is read through
`public.schema_indexes(p_scope text)`, added by
`supabase/migrations/065_schema_indexes.sql`.

## The editable module screens

Six module screens used to show their rows and offer no way to change one. Each
of them now carries a collapsible **Manage** panel. Migration 067 grew the
catalogue from 15 tables to **127 tables across 17 modules**, so the panel now
reaches every module that has a writable table - **28 screens** in all:

| Nav group | Routes with the panel |
|---|---|
| `institution` (2) | `/structure` |
| `calendar` (3) | `/calendar` |
| `curriculum` (4) | `/curriculum`, `/courses` |
| `people` (5) | `/students`, `/students/[id]/records`, `/students/[id]/documents`, `/employees`, `/employees/[id]/records`, `/employees/[id]/hr` |
| `admission` (6) | `/admissions` |
| `registration` (7) | `/registration` |
| `teaching` (8) | `/timetable` |
| `attendance` (9) | `/attendance` |
| `assessment` (10) | `/assessment`, `/results/grades`, `/my-results` |
| `feedback` (11) | `/feedback` |
| `support` (12) | `/grievances` |
| `documents` (13) | `/certificates`, `/requests`, `/my-documents` |
| `communication` (14) | `/announcements`, `/announcements/manage` |
| `hr` (16) | `/my-hr` |
| `schema` (18), `seed` (35), `rbac` (36), `staff-index` (38), `integrity` (39) | `/schema/[module]` |
| `staff` (19) | `/staff-profile` |
| `activities` (40) | `/activities` |

The panel is one component - `src/features/admin/admin-table-editor.tsx` - and
the database owns it. `public.admin_table_list` returns only the tables the
signed-in user holds a write permission for, `admin_table_schema` describes the
columns, and `admin_table_save` / `admin_table_delete` do the write. All five
functions come from `supabase/migrations/066_admin_editing.sql`, reshaped by
`supabase/migrations/067_admin_editing_expansion.sql`.

The catalogue `sims_private.admin_table_def` was **derived from the live row
level policies** rather than written by hand, so the permission codes are the
policies' own, verbatim, and the panel and the policy cannot disagree.

The write functions are `SECURITY DEFINER`, so the row level policies do not run
for them; each one therefore makes the same decision the policy makes, checking
the row as it exists now *and* the row as it is afterwards. A scoped caller
therefore cannot move a row out of its own scope. Every change is audited
**exactly once**: by the table's own trigger where it has one (88 tables), and
by the write function itself where the table's own write path already audits
(39 tables).

## Documentation

[`docs/README.md`](docs/README.md) is the index. The most useful entry
points:

- [RTM.md](docs/RTM.md) - which database module maps to which table, RPC,
  route and access code, and what is still missing.
- [NAVIGATION.md](docs/NAVIGATION.md) - the sidebar contract.
- [RLS_SECURITY_MODEL.md](docs/RLS_SECURITY_MODEL.md) - how authorisation
  really works.
- [SCHEMA.md](docs/SCHEMA.md) - every table, column, function, policy and
  trigger of the live project.
- [RECOVERY.md](docs/RECOVERY.md) - how this tree came to exist and how much
  of it can be trusted as original.

## The database

The live project is `khqqfgqvwdxlqkncwtmh`. It carries the reference seeds,
the demo tenant, a test administrator and the two test personas. The migration
applier tracks what it has applied in `sims_private.schema_migration`; that
table is bookkeeping and is deliberately excluded from the catalogue and the
generated docs.

Every tool that writes is **dry run by default** - `--apply` is the only way
to change anything:

```bash
npm run migrate:apply    # plan only; --apply to write
npm run seed:apply       # plan only; --apply to write
npm run admin:create     # plan only; --apply to write
npm run admin:password   # plan only; --apply to write

python tools/create_test_personas.py   # plan only; --apply to write
```

The database password is read from the environment and is never stored in the
repository.
