# College ERP / SIMS

A Student Information System built with **Next.js 16.4.5** (App Router,
Turbopack), **React 19**, **TypeScript** and **Supabase** (PostgreSQL + RLS).

The database is the authority: 213 public tables, 420 functions, 594 row-level
security policies and a role/permission model with 38 roles. Every screen
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

Sign in with the test administrator:

| Email | Password |
|---|---|
| `sims.test.admin@gmail.com` | `SimsTest@2026` |

It is a `SUPER_ADMIN` with 349 permissions across 22 modules.

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
| `src/app` | the routes - 48 application pages plus the auth pages |
| `src/lib/nav.ts` | the sidebar contract: 21 numbered module groups, plus the 15 staff sub-modules (schema modules 20–34) drawn under the staff group |
| `src/features` | one folder per module, each with its client and data layer |
| `supabase/migrations` | 64 migrations, generated from the live catalogue |
| `tools` | the migration, catalogue, seed and verification tooling |
| `tests` | unit, database and Playwright suites |
| `docs` | the full documentation set - start at `docs/README.md` |

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
the demo tenant and a test administrator. The migration applier tracks what it
has applied in `sims_private.schema_migration`; that table is bookkeeping and
is deliberately excluded from the catalogue and the generated docs.

Every tool that writes is **dry run by default** - `--apply` is the only way
to change anything:

```bash
npm run migrate:apply    # plan only; --apply to write
npm run seed:apply       # plan only; --apply to write
npm run admin:create     # plan only; --apply to write
npm run admin:password   # plan only; --apply to write
```

The database password is read from the environment and is never stored in the
repository.
