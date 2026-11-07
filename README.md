# College ERP / SIMS

A Student Information System built with **Next.js 16.4.5** (App Router,
Turbopack), **React 19**, **TypeScript** and **Supabase** (PostgreSQL + RLS).

The database is the authority: 213 public tables, 421 functions, 594 row-level
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
| `src/features` | one folder per module, each with its client and data layer |
| `supabase/migrations` | 65 migrations - `001`-`063` are generated, `064` and `065` are hand-written |
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
