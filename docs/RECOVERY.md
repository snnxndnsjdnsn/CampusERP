# Recovery record

This file is the honest account of how the current tree at `F:\sims\College-ERP` came
to exist. Part of it is a post-mortem; part of it is a provenance ledger. Read the
provenance section before treating any file in this repository as "original".

Everything below is sourced from the opencode session database
(`C:\Users\Samarth\.local\share\opencode\opencode.db`, 15,781,392,384 bytes) and from
read-only queries against the live Supabase project. Nothing here is inferred from
memory.

---

## 1. The incident

On **2026-11-07 at 22:39:11.216 local time** (epoch ms `1794071351216`), the agent
working in session `ses_e4986a3aaffeEDGP6MHQhRYfMA` ("SIMS schema module navigation",
project `F:/sims`, project id `adb3d0b37b308ea7f4e45e23bd8b6dbd58080577`) ran this
PowerShell command:

```powershell
Remove-Item -Recurse -Force 'F:\sims\College-ERP' -ErrorAction SilentlyContinue;
Write-Output ...; Test-Path 'F:\sims\College-ERP'
```

The command was issued as message `msg_1b6fc4fad001BRePuZsDwwLjuf` (seq 1234) in
session `ses_e4986a3aaffeEDGP6MHQhRYfMA`.

The intent was to clean up a stale scratch file. Two earlier attempts in the same
session had targeted that scratch file specifically and had failed with `PathNotFound`:

- 22:23:24 - `Remove-Item -Force 'F:\sims\College-ERP\tools\workinspect_seed_state.mjs'` (typo, no such path)
- 22:23:32 - `Remove-Item -Force 'F:\sims\College-ERP\tools\work\inspect_seed_statejs'` (typo, no such path)

The third attempt widened the target from one file to the project root and added
`-Recurse -Force`. It succeeded. `Test-Path` returned `False`.

The agent's own reaction, at 22:40:56 (message `msg_1b6fde960001d4vG9z8k7ZMg3j`):

> deleted the entire `F:\sims\College-ERP` directory! That's catastrophic. Let me check
> what happened.

`F:\sims` was left in place but empty. The project had no `.git` directory and no
configured remote, so there was no push target and no clone to pull from.

---

## 2. Recovery attempts, and why each one failed

Every one of these was tried in the same session immediately after the deletion. All
of them failed.

| Attempt | Command / location | Result |
|---|---|---|
| Recycle Bin | `F:\$RECYCLE.BIN` | `Remove-Item` bypasses the Recycle Bin. Only unrelated hidden/system entries present. |
| Volume shadow copies | `Get-CimInstance Win32_ShadowCopy` | No shadow copies exist on the host. |
| File History / System Restore | `F:` drive | Not enabled for this volume. |
| Git remote | `git remote -v` in the project | The project was not a git repository; `.git` was deleted with everything else. |
| `D:\Sims_2` | referenced by the session summary | Path does not exist. |
| `D:\hod sims` | referenced by the session summary | **Exists.** This is the only pre-incident source that survived. See section 3.3. |
| `winfr` (Windows File Recovery) | Microsoft Store app | Requires the Store app plus administrator rights; not usable in this environment. |

The practical conclusion was that the only recoverable material was (a) whatever the
agent's own session log had captured as tool output, and (b) the live database.

---

## 3. The three things that survived

### 3.1 The opencode session database

The v2 store in `opencode.db` is `session_message` (43,471 rows) plus `session_v2`
(632 rows); the legacy `part` table is empty and was never the right place to look.
The incident narrative and the file fragments both live in `session_message`.

`recover.py` mined the seven pre-deletion sessions into
`C:\Users\Samarth\AppData\Local\Temp\opencode\events.jsonl` (1,468,482 bytes,
317 tool events). `coverage_scan.py` then measured exactly how much file content the
log contains.

### 3.2 The live Supabase database

The database was never touched by the deletion. It is the authoritative source for
everything schema-shaped. Verified read-only on 2026-11-07 and re-verified on
2026-11-08:

| Object | Count |
|---|---|
| `public` tables | 213 |
| `public` tables with RLS enabled | 213 (0 disabled) |
| `public` views | 10 |
| `public` functions | 280 (236 `SECURITY DEFINER`) |
| `sims_private` tables | 10 (9 application tables plus the applier's `schema_migration`) |
| `sims_private` functions | 151 |
| `public` triggers | 142 |
| `public` policies | 594 |
| `public` indexes | 572 |
| `access_module` / `access_action` / `access_resource` | 22 / 12 / 40 |
| `role` rows | 39 |
| `role_permission` rows | 2,301 |
| Migrations applied | 66 (`001`–`066`, no gaps) |

The catalogue was regenerated from it into `tools/catalogue/live_catalogue.json`
(3,438,534 bytes) and `tools/catalogue/live_seed_data.json` (324,594 bytes).

### 3.3 The upstream MySQL source on `D:\hod sims`

| File | Size |
|---|---|
| `D:\hod sims\sims_v6.sql` | 883,351 bytes |
| `D:\hod sims\sims_v6 (1).sql` | 766,632 bytes |
| `D:\hod sims\ERP.zip` | 133,933,587 bytes |
| `D:\hod sims\SIMS_DJango_Project.zip` | 217,943,558 bytes |

`SIMS-DatabaseWithoutLessonPlan.sql` was recovered complete (324,503 bytes,
5,648 lines) and verified against these upstream dumps.

---

## 4. The recovery ceiling

This is the measured limit of what the session log contained. It is the single most
important number in this document: **everything else in the repository was rewritten
from scratch.**

`coverage_scan.py` output:

```
paths with any recovered line : 31
paths with >= 3 lines         : 31
paths with >= 10 lines        : 26
paths with >= 30 lines        : 24
paths with >= 100 lines       : 9
total recovered lines         : 3506
```

By area: `supabase` 8, `src` 5, `tools` 4, `docs` 4, `tests` 2, plus
`package.json`, `tsconfig.json`, `vitest.config.ts`, `AGENTS.md`, `.gitignore`,
`.env.example`, `SIMS-DatabaseWithoutLessonPlan.sql`, and one `node_modules` file.

Two reconstruction passes were then run over that material:

| Pass | Script | Files written |
|---|---|---|
| 1 | `rebuild.py` | 40 |
| 2 | `rebuild2.py` | 34 (2,954 core session lines; 26 core files / 2,554 lines; 8 scratch files; 3,141 lines total) |

### 4.1 The seven edit-replay failures

`rebuild2.py` reported 7 edits it could not re-apply:

```
('tools\work\dump_refs2.mjs', 115, 'nomatch')
('src\components\app-shell.tsx', 231, 'nomatch')
('src\components\app-shell.tsx', 232, 'nomatch')
('src\components\app-shell.tsx', 233, 'nomatch')
('src\components\app-shell.tsx', 234, 'nomatch')
('src\components\app-shell.tsx', 235, 'nomatch')
('src\components\app-shell.tsx', 236, 'nomatch')
```

These are **replay failures, not content loss**. The recovered snapshot of
`src/components/app-shell.tsx` was a 176-line read taken *after* those six edits had
already landed in the original session, so the pre-edit `oldString` no longer matched.
The current 176-line file already contains all six changes (the `BadgeCheck` /
`Contact` / `FileCheck2` icon imports, the `/results/grades` icon entry, the
`Breadcrumbs({ groups })` signature with the `NAV_PARENTS` fallback, the
`AppShell({ groups })` signature, the `<Breadcrumbs groups={groups} />` call site and
the `groups.flatMap(...)` mobile nav). `tools/work/dump_refs2.mjs` likewise already
contains the corrected `console.log('\n== FK ' + t);` line.

---

## 5. Provenance: what is original and what is reconstructed

Use this table before making a claim about a file's history.

### 5.1 Byte-exact survivors (recovered from a full `write` in the session log)

| File | Lines |
|---|---|
| `src/lib/nav.ts` | 192 |
| `src/app/(app)/results/page.tsx` | 6 |
| `supabase/migrations/064_required_reference_seeds.sql` | 168 |
| `tools/seed_demo.sql` | 221 |
| `tools/work/dump_checks.mjs` | 29 |
| `tools/work/dump_columns.mjs` | 35 |
| `tools/work/dump_fks.mjs` | 21 |
| `tools/work/dump_refs.mjs` | 28 |
| `tools/work/dump_refs2.mjs` | 41 |
| `tools/work/inspect_seed_state.mjs` | 43 |
| `.env.local` | 8 |

`tools/seed_demo.sql` was recovered byte-exact at 22:51:24 but has since been
**rewritten** by the rebuild (869 lines, 57,485 bytes, last written 00:16:30).
The byte-exact claim applies to the state at 22:51:24, not to the file on disk
now. `supabase/migrations/064_required_reference_seeds.sql` is still the
byte-exact 168-line file (10,287 bytes, last written 22:51:24).

### 5.2 Full-file survivors (recovered from a complete `read` in the session log)

| File | Lines |
|---|---|
| `docs/AUTHENTICATION_AND_RBAC.md` | 33 |
| `docs/DATABASE_MIGRATION.md` | 84 |
| `docs/ROLE_PERMISSION_MATRIX.md` | 145 |
| `package.json` | 60 |
| `tsconfig.json` | 44 |
| `vitest.config.ts` | 7 |
| `AGENTS.md` | 9 |
| `.gitignore` | 12 |
| `.env.example` | 5 |
| `src/app/(app)/layout.tsx` | 22 |
| `src/app/page.tsx` | 5 |
| `src/components/app-shell.tsx` | 176 |
| `src/features/students-lookups.ts` | 41 |
| `tests/db/world.ts` | 96 |
| `tools/validate/seed_counts.mjs` | 62 |

`docs/MODULE_DOCUMENTATION.md` was also recovered this way (58 lines) and has since
been extended; its original 58 lines are still the first section of the file.

`docs/ROLE_PERMISSION_MATRIX.md` carries an extra piece of evidence: the
generator `tools/validate/role_matrix.mjs` was restored at 23:48:38, and
`node tools/validate/role_matrix.mjs --check` reports that the recovered file is
**byte-identical** to what the generator produces from the current migration set.
The recovered copy is therefore not merely plausible - it is reproducible.

### 5.3 Partial survivors (only a prefix of the original was ever in the log)

| File | Recovered | Original |
|---|---|---|
| `supabase/migrations/001_common_reference_and_institution.sql` | 207 lines | 285,732 bytes now |
| `supabase/migrations/003_student_employee_admission_registration.sql` | 30 lines | 1,497 bytes now |
| `supabase/migrations/004_teaching_attendance_assessment_feedback.sql` | 150 lines | 1,464 bytes now |
| `supabase/migrations/006_identity_rbac_audit.sql` | 54 lines | 217,450 bytes now |
| `supabase/migrations/014_triggers_and_integrity.sql` | 110 lines | 1,143 bytes now |
| `supabase/migrations/031_attendance.sql` | 244 lines | 1,718 bytes now |
| `supabase/migrations/032_assessment_and_results.sql` | 424 lines | 1,737 bytes now |
| `supabase/migrations/047_finance_receipts_and_holds.sql` | 55 lines | 1,746 bytes now |
| `tests/unit/lib.test.ts` | 77 lines | 131 lines now |
| `tools/work/columns.txt` | 938 lines | 938 lines now |

### 5.4 Regenerated, not recovered

`supabase/migrations/001`–`063` were rewritten wholesale by
`tools/build_migrations.py` and `tools/build_rls.py` from the live catalogue.
The first regeneration was at 23:41:06; a second pass rewrote them again at
23:49:34, and the set was regenerated twice more after the translator was
restored - at 00:29:40 and finally at **00:34:52**, which is the state on disk
now. This overwrote the eight partially-recovered migration files listed in
5.3. The regenerated files are **verified against the live database**, but they
are not byte-identical to the files that existed before the deletion, and the
original per-file split of migrations 002–063 is not recoverable.

They were also not **semantically** identical in one respect, and this was found
by diffing the rebuilt catalogue against the live one (see section 8): the
23:49:34 set contained **no `REVOKE` statement at all**, so it did not reproduce
the live database's revocation of `PUBLIC EXECUTE` from 418 of the 420 functions
in `public` + `sims_private` (the counts at the time). A database rebuilt from it would have been **more
permissive** than the live project.

At **23:56:38** `npm run migrate:build` was re-run from the MySQL source
(`tools/translate.py`, restored at 23:54:54, then `tools/build_migrations.py`).
`supabase/migrations/021_finance_rpcs.sql` now carries the 418 `REVOKE`
statements, the `NOT VALID` flag on
`research_project_financial_utilization.chk_project_utilization_balance` is
reproduced, and `tools/compare_catalogue.py` reports **0 differences in every
category**. The migrations on disk are now a faithful translation of the MySQL
source, not a catalogue dump.

`supabase/migrations/064_required_reference_seeds.sql` is the exception: it was
recovered byte-exact and was **not** overwritten. It was applied to the live
database on 2026-11-08.
`supabase/migrations/065_schema_indexes.sql` is the second exception: it is
hand-written rather than generated, and `tools/build_migrations.py` refuses to
run if it is missing.
`supabase/migrations/066_admin_editing.sql` is the third exception: it is
hand-written as well. `tools/build_migrations.py` strips its objects from the
catalogue before it builds, so a rebuild never creates one of them twice.

Also regenerated rather than recovered: `tools/catalogue/*`, `tools/rls/table_module.json`,
`tools/validate/pg_catalogue.mjs`, `tools/validate/apply.mjs`,
`tools/validate/nav_rbac_connectivity.py`, `tools/validate/seed_columns.py`,
`tools/validate/role_matrix.mjs`, `tools/validate/catalogue.mjs`,
`tools/validate/schema_doc.mjs`, `tools/compare_catalogue.py`,
`tools/translate.py`, `tools/dump_catalogue.py`, `tools/build_migrations.py`,
`tools/build_rls.py`, `tools/apply_migrations.py`, `tools/create_admin.mjs`,
`tools/verify.mjs`, `docs/RLS_POLICY_MAP.md`.

### 5.5 Written from scratch after the incident

Everything else. In particular the whole Next.js application layer: the 50 route
pages under `src/app/(app)/`, the `src/features/**` clients, the `src/components/ui/**`
primitives, `src/lib/context.ts`, `src/lib/server-context.ts`, `src/lib/api.ts`,
`src/lib/env.ts`, `src/lib/format.ts`, `src/lib/utils.ts`, `src/lib/validation.ts`,
`src/lib/supabase/**`, `src/proxy.ts`, and the `tests/**` suite.

`tests/unit/nav-connectivity.test.ts` is a special case: it was recovered as a
94-line `write` and was then rewritten during the rebuild to the current 190 lines.

---

## 6. What is permanently lost

1. **The original application source.** About 150 Next.js files existed before the
   deletion. 26 of them survived in some form; the rest were rewritten. Any behaviour
   that was not re-derived from the live database or the upstream MySQL dump is gone.
2. **The original per-file migration split.** Migrations 002–063 were individual
   hand-authored SQL files. The current split is a regeneration. The SQL *content* is
   faithful to the live database, but the file boundaries, the comments, and the
   authoring order are not the originals.
3. **`.git` history.** There was no repository, so there is no commit history to
   recover and none was recreated. The tree is not under version control.
4. **Any file that was never read or written by a tool during the pre-deletion
   sessions.** The session log only contains what the agent actually touched.

---

## 7. How the current tree was rebuilt

| Time | Step |
|---|---|
| 22:39:11 | Deletion. |
| 22:41–22:50 | Recovery attempts (all failed); `recover.py` mines the session log. |
| 22:50:50 | `rebuild.py` writes 40 files. |
| 22:51:24 | `rebuild2.py` writes 34 files (the current state of the 26 core files). |
| 22:56:08 | `SIMS-DatabaseWithoutLessonPlan.sql` written complete (5,648 lines). |
| 23:02:56 onward | Application layer rebuilt from scratch: `src/lib/**`, `src/components/**`, `src/app/**`, `src/features/**`. |
| 23:14 onward | Feature clients and route pages written module by module. |
| 23:22:30 | `tools/rls/table_module.json` and `docs/RLS_POLICY_MAP.md` generated from the live catalogue. |
| 23:31:50 | `tests/unit/nav-connectivity.test.ts` rewritten. |
| 23:33:54 | `docs/RTM.md` written. |
| 23:34:28 | `docs/NAVIGATION.md` written. |
| 23:35:10 | `tools/catalogue/live_catalogue.json` regenerated. |
| 23:36:30 | `docs/RLS_SECURITY_MODEL.md` written. |
| 23:37:12 | `docs/MODULE_DOCUMENTATION.md` extended. |
| 23:41:06 | `supabase/migrations/001`–`063` regenerated from the live catalogue. |
| 23:44:34 | `docs/RECOVERY.md` written. |
| 23:46:18 | `docs/NAVIGATION.md` written. |
| 23:47:12 | `docs/README.md` written. |
| 23:47:54 | `docs/MODULE_DOCUMENTATION.md` extended. |
| 23:48:38 | `tools/validate/role_matrix.mjs` written - the matrix generator is restored. |
| 23:49:22 | `tools/validate/catalogue.mjs` written. |
| 23:49:34 | `supabase/migrations/001`–`063` regenerated a second time. |
| 23:49:46 | `tools/compare_catalogue.py` written. |
| 23:50:18 | `tools/catalogue/local_catalogue.json` regenerated from PGlite. |
| 23:51:04 | `tools/seed_demo.sql` rewritten (778 lines). |
| 23:54:54 | `tools/translate.py` restored - the MySQL → PostgreSQL translator. |
| 23:56:38 | `npm run migrate:build` re-run: `supabase/migrations/001`–`063` regenerated from the MySQL source, now carrying the 418 `REVOKE` statements. |
| 23:56:50 | `tools/catalogue/local_catalogue.json` regenerated from PGlite. |
| 23:57:14 | `tools/compare_catalogue.py` extended; `tools/verify.mjs` added. |
| 00:11:14 | `tools/validate/role_matrix.mjs` reworked: it reads the **live** project by default (`--source auto|live|rebuilt`). |
| 00:12:04 | `tools/apply_migrations.py` written - the migration applier, dry run unless `--apply`. |
| 00:13:32 | `tools/create_admin.mjs` written - the administrator bootstrap, dry run unless `--apply`. |
| 00:15:06 | `tools/dump_catalogue.py` reworked to capture `pg_attribute.attacl`. |
| 00:15:16 | `tools/validate/pg_catalogue.mjs` reworked to capture `attacl` as well. |
| 00:16:30 | `tools/seed_demo.sql` rewritten again (869 lines). |
| 00:20:08 | `tools/build_rls.py` reworked. |
| 00:20:28 | `tools/build_migrations.py` reworked: it emits the 212 column grants and refuses to build from a catalogue that carries none. |
| 00:21:22 | `tools/catalogue/live_catalogue.json` re-dumped; `docs/SCHEMA.md` and `docs/SCHEMA_RECONCILIATION.md` rendered. |
| 00:22:08 | `tools/validate/catalogue.mjs` reworked to dump the live catalogue read-only. |
| 00:22:20 | `tools/validate/schema_doc.mjs` written - the schema document generator. |
| 00:25:02 | `tools/validate/nav_rbac_connectivity.py` reworked. |
| 00:28:46 | `tools/translate.py` reworked. |
| 00:29:52 | `docs/README.md` rewritten against the tool surface. |
| 00:30:12 | `tools/compare_catalogue.py` reworked: it now diffs the live catalogue against an expected contract instead of a PGlite rebuild. |
| 00:31:30 | `tools/catalogue/expected_catalogue.json` written - the contract the live project has to satisfy. |
| 00:33:16 | `tools/verify.mjs` extended. |
| 00:34:52 | `tools/catalogue/mysql_reference.json` re-translated from the MySQL source; `supabase/migrations/001`–`063` regenerated a fourth time. `064` is still the byte-exact recovered file. |
| 00:36:04 | `package.json` gains the `verify` script. |
| 00:37:04 | `tools/dump_catalogue.py` reworked again. |
| 00:37:14 | `tools/apply_migrations.py` reworked. |
| 00:37:22 | `tools/validate/catalogue.mjs` reworked again. |
| 00:38:24 | `tools/create_admin.mjs` reworked. |
| 03:30:10 | `supabase/migrations/065_schema_indexes.sql` written - the `public.schema_indexes(p_scope text)` RPC, the only door to `pg_indexes`. |
| 03:30:10 | `src/lib/nav.ts` extended: six new groups (`schema`, `seed`, `rbac`, `reporting`, `staff-index`, `integrity`) and 27 groups in all. |
| 03:30:16 | `src/components/app-shell.tsx` extended with the icons for the six new routes. |
| 03:31:04 | `tests/unit/nav-connectivity.test.ts` extended: the group order lock now carries the six new ids, and a new assertion checks the six screens' numbers, addresses and gates. |
| 03:31:28 | `tests/e2e/smoke.spec.ts` extended: the six new routes join the route sweep, and a new test checks that the six groups are drawn with their module numbers. |
| 03:32:24 | `docs/NAVIGATION.md` rewritten for the 27 groups. |
| 03:34:28–03:35:14 | `src/features/schema/` written: the seed table list, the `file_object` columns, the index catalogue, the seed catalogue, the RBAC catalogue and the fourteen integrity notes. |
| 03:35:51 | `src/app/(app)/schema/[module]/page.tsx` written - the dynamic route behind modules 18, 35, 36, 38 and 39. |
| 03:36:00–03:37:30 | `src/features/reporting/` written: the ten reporting views and the live search and activity reports. |
| 03:37:20 | `tools/create_test_personas.py` written - the faculty and student personas the visibility rules need. |
| 03:54:02–03:54:14 | `src/features/schema/module-catalog.ts` and `schema-screen.tsx` written - the module catalogue and the shared screen. |
| 03:54:44 | `src/app/(app)/reporting/page.tsx` written - the screen behind module 37. |
| 03:56:40 | `src/features/schema/module-catalog.ts`, `schema-screen.tsx` and `src/app/(app)/reporting/page.tsx` given the page-level gate: a caller who may not read the module behind a screen is told so instead of being served the screen. |
| 04:09:04 | `playwright.config.ts` capped at four workers. Playwright's default of half the logical processors had the shared Supabase pooler queueing `my_context()` long enough for the database's two-minute statement timeout to cancel it, so the page answered 500 and the suite failed on a healthy application. |
| 06:00-06:15 | The six read-only screens diagnosed and the generic write surface designed. The academic calendar, curriculum, courses, students, registration and timetable had no write RPC at all, and the generic reference editors - `sims_private.ref_tables()` and `sims_private.section_def()` - do not list their tables either. The cause was a missing write surface, not a permission. |
| 06:15:59 | `supabase/migrations/066_admin_editing.sql` written and applied to the live project: the catalogue `sims_private.admin_table_def`, the helpers `admin_holds`, `admin_scope_value` and `admin_can`, the five public `admin_*` functions, and the two audit triggers that were missing - `trg_time_slot_audit` and `trg_room_audit`. |
| 06:16-06:20 | `src/features/admin/admin-table-editor.tsx` written - the Manage panel the six screens share - and the six screen pages wired to it. `tools/build_migrations.py` taught to strip the hand-written objects from the catalogue, so a rebuild never creates one of them twice. |
| 06:41:27 | The end-to-end round trip on the academic calendar exercised against the live project: add, a refused duplicate, edit and delete, each one audited exactly once. |
| 06:45:28 | The last verification write of the round. |
| 06:41 | The catalogue check taught to leave the append-only audit logs out of the row counts. Their count is a function of activity, not of the schema - the end-to-end suite alone adds three rows to `activity_audit` per run - so recording it made `catalogue.mjs --check` fail after every test run. The list lives in `tools/validate/pg_catalogue.mjs` and is used by all three dumpers. |
| 07:10-08:40 | The catalogue widened. The live row level policies were parsed instead of a hand-written list: 127 writable tables, their permission codes verbatim, their scope kind and scope path. Two scope kinds were added - `employee` and `institution` - and the scope was generalised to a path of foreign key hops. |
| 08:40-09:05 | `supabase/migrations/067_admin_editing_expansion.sql` written and applied to the live project: 127 catalogue rows, 70 foreign key lookups, the 48 missing audit triggers, and the write functions reshaped to take a JSON key so a composite key can address a row. |
| 09:05-09:30 | The 28 screens wired to the panel. Each one now passes its module code instead of a table list, and the panel offers the union of the catalogue tables of those modules. `src/features/admin/admin-table-editor.tsx` gained the `modules` prop and the composite-key handling. |
| 09:30-10:10 | The tests rewritten: `tests/db/admin-editing.test.ts` grew to 18 tests and `tests/e2e/admin-editing.spec.ts` to 30, and `tools/seed_demo.sql` grew from 51 to 79 seeded tables so that no screen is empty. |
| 10:10 | The catalogue contract re-blessed and the documents rewritten. |

The 00:30:12 row is the point at which the tooling stopped comparing the
migration set against a **rebuild** and started comparing it against a
**contract**: `tools/catalogue/expected_catalogue.json` is the live catalogue
re-blessed as the reference, so `tools/compare_catalogue.py` is now a pure
offline diff of two JSON files and no longer needs a database or an embedded
PostgreSQL to run.

This record was last reconciled against the tree at 04:09:04, when the
end-to-end suite's worker count was capped. The last write by the rebuild
tooling was at 00:38:24; the only later change to the tree before that round
was `.env.example` at 00:41:26. Everything after 23:56:38 is re-verified in
section 8, the round that added the six schema screens is recorded in
section 9, and the round that made the six module screens editable is
recorded in section 10.

---

## 8. Verification performed after the rebuild

- The live database was re-read with `SELECT`-only queries and the object counts in
  section 3.2 confirmed. The object counts did not move during the rebuild.
- **2026-11-08: the project was brought up to date.** Migration
  `064_required_reference_seeds.sql` was applied (17 statements, 1258 ms), the
  demo seed `tools/seed_demo.sql` was applied (58 statements, 151 rows into 51
  tables), and a test administrator was created. The project now carries
  `sims_private.schema_migration`, so the applier can tell what is applied:
  `python tools/apply_migrations.py` reported **64 migration file(s), 0 pending,
  0 changed** at that point. It reports 66 now that
  `066_admin_editing.sql` exists; see sections 9 and 10.

  The tracker did not exist when the applier was first run, so the files `001`
  to `063` were **baselined** - recorded as applied *without being executed*,
  because the project already carried that schema. The command is
  `python tools/apply_migrations.py --apply --baseline-before 064_required_reference_seeds.sql`.

  The tracker is the applier's own bookkeeping, not application schema, so it
  is excluded from the catalogue and from `docs/SCHEMA.md`. Without that
  exclusion the first run of the applier would have changed the schema
  contract, the migration set and every generated document.
- `tools/validate/nav_rbac_connectivity.py` was run against the live project. Every
  navigation module is authorised by at least one role permission except `REPORTING`,
  which has 11 permissions but 0 RLS-protected tables and 0 RPCs behind it.
- `tools/validate/seed_counts.mjs` was run to confirm the reference seed.
- `tests/unit/nav-connectivity.test.ts` asserts the nav-to-route and nav-to-RBAC
  wiring; see [NAVIGATION.md](NAVIGATION.md).
- **The application was exercised signed in against the live project.** The test
  administrator signs in through the real form, `public.my_context()` resolves
  22 readable modules and 349 permissions, and all 68 application routes render
  with zero console errors. `tests/e2e/smoke.spec.ts` repeats that as a test;
  the session is created once in `tests/e2e/global-setup.ts` because Supabase
  throttles the password grant endpoint.
- `node tools/validate/role_matrix.mjs --check` reads the RBAC tables from the
  **live** project (the session is switched to read-only), renders the matrix in
  memory and compares it with the committed file. It exits 0 with
  `OK - docs\ROLE_PERMISSION_MATRIX.md is up to date (source: live)`: the
  **recovered** `docs/ROLE_PERMISSION_MATRIX.md` is byte-identical to what the
  generator produces from the live database. That is the strongest available
  evidence that the recovered copy is faithful. `--source rebuilt` runs the same
  render against the migration set applied to a fresh embedded PostgreSQL, and
  `--source auto` (the default) falls back to that when the project cannot be
  reached.
- `python tools/compare_catalogue.py` diffs `tools/catalogue/live_catalogue.json`
  (the read-only dump of the live project) against
  `tools/catalogue/expected_catalogue.json` (the contract the project has to
  satisfy). It exits 0 with `OK - the live catalogue matches the expected
  catalogue`: **0 differences** in the headline counts, the per-schema counts,
  the 42 seeded row counts, and in tables (222), columns (2140), functions
  (421), policies (594), triggers (140), grants (6227) and sequences (199).

  It did not pass the first time. The 23:49:34 migration set was a regeneration
  from a catalogue dump, and a catalogue dump records the grants that exist, not
  the revocations that were applied - so the rebuilt database had `PUBLIC EXECUTE`
  on 418 functions that the live project had revoked, and one `CHECK` constraint
  had lost its `NOT VALID` flag. That was 437 differences. Re-running
  `npm run migrate:build` from the MySQL source at 23:56:38 fixed both.

  The row-count comparison covers the 42 reference and RBAC tables the contract
  carries (`access_module`, `access_action`, `access_resource`, `permission`,
  `role`, `role_permission`, `activity_type`, `document_type`, ...). Every one of
  them matches. The 18 tables that migration 064 seeds were deliberately absent
  from the contract while the live project had not applied 064; they are still
  absent, because the contract describes the **schema**, not the demo rows. The
  operational tables (`login_audit`, `user_account`, `user_role_assignment`,
  `sims_private.auth_identity_map`) are not seeded and are not counted either.

- The **column level** privileges were found and fixed. The live project grants
  `authenticated` SELECT on every *column* of 212 of the 213 public tables
  instead of granting SELECT on the relation, so the privilege lives in
  `pg_attribute.attacl` and not in `pg_class.relacl`. The catalogue recorded
  only `relacl`, which meant the migration set carried **zero**
  `GRANT SELECT (col, ...) ON TABLE ...` statements and a rebuilt database would
  have refused every direct table read - making all 594 RLS policies
  unreachable through the Data API.

  Both dumpers now capture `attacl`, `tools/build_migrations.py` emits the 212
  column grants into migration 021 and refuses to build from a catalogue that
  carries none, and `tests/db/rls.test.ts` asserts the grant shape and the
  `SELECT *` refusal. See S-11 in
  [RLS_SECURITY_MODEL.md](RLS_SECURITY_MODEL.md) and G-11 in
  [RTM.md](RTM.md).

- `node tools/verify.mjs` runs the whole suite in one command - typecheck, lint,
  unit tests, database tests, production build, the live nav/RBAC matrix, the
  seed column validation, the role matrix check, the schema document check, the
  catalogue check and the migration apply dry run. It exits 0.
- **The six new schema screens were checked against the live project.** The
  round that added them, and what it did and did not prove, is recorded in
  section 9.

---

## 9. The round that added the six schema screens

On 2026-11-08 the tree gained six screens for schema modules that had no route
of their own: modules 18, 35, 36, 37, 38 and 39. The round ran from 03:30:10
to 03:54:44; section 7 lists the steps in order.

| Group | Module | Route | Access code | What the screen shows |
|---|---|---|---|---|
| `schema` | 18 | `/schema/18` | `IAM` | The 572 public indexes and the 20 columns of `file_object`. |
| `seed` | 35 | `/schema/35` | `IAM` or `STAFF_PROFILE` | The 27 seeded lookup tables. |
| `rbac` | 36 | `/schema/36` | `IAM` | 1 access module, 5 resources, 44 permissions, 144 role grants. |
| `reporting` | 37 | `/reporting` | `REPORTING` | The 10 public reporting and search views. |
| `staff-index` | 38 | `/schema/38` | `STAFF_PROFILE` or `IAM` | The 146 staff-scope indexes over 55 tables. |
| `integrity` | 39 | `/schema/39` | `IAM` or `AUDIT` | The 14 integrity rules the service layer enforces. |

The round also added `supabase/migrations/065_schema_indexes.sql`, which
creates `public.schema_indexes(p_scope text DEFAULT NULL)` - the only door to
`pg_indexes` - and `tools/create_test_personas.py`, which creates the faculty
and student personas the visibility rules need.

### 9.1 What is verified

- The counts in the table above were read from the live project on 2026-11-08
  with `SELECT`-only queries. `public.schema_indexes('all')` returns 572 rows
  and `public.schema_indexes('staff')` returns 146 rows over 55 tables; an
  unknown scope raises SQLSTATE `22023` and an unauthorised caller raises
  `42501`.
- The three personas exist and were checked against the live project: the
  administrator holds 22 modules and 349 permissions, the employee
  (`FACULTY` / `DEPARTMENT`) holds 14 modules, and the student (`STUDENT` /
  `SELF`) holds 10 modules.
- The visibility rules were checked in a browser with a real session for each
  persona. The administrator sees every group except `16 · Employee HR` (that
  item is `employeeOnly`). The employee sees 16, 35, 37 and 38 and not 18, 36
  or 39. The student sees none of 16, 18, 35, 36, 37, 38 or 39.
- The six screens refuse a caller who may not read the module behind them.
  The student is told `This screen is not open to your account` on all six
  addresses, and the employee is refused on 18, 36 and 39 and served on 35, 37
  and 38. The database refuses the data itself in every case - `schema_indexes`
  answers `42501` to both the employee and the student - so the page gate is
  the door and the row-level security is the lock.
- All 27 seed tables are readable and all 10 reporting views are readable.
- The sidebar carries 27 groups and 50 routes.
  `tests/unit/nav-connectivity.test.ts` locks the group order and the six new
  ids, and `tests/e2e/smoke.spec.ts` sweeps 68 route assertions.
- The end-to-end suite opens all 68 addresses with a real session and asserts
  that each one answers 200, leaves the `Loading…` state and logs nothing to
  the console. It runs four browsers at a time: Playwright's default of half
  the logical processors puts eight pages on a sixteen-core machine, and the
  shared Supabase pooler then queues them long enough for the database's
  two-minute statement timeout to cancel `my_context()`. The page answers 500
  and the suite fails on a healthy application, so `playwright.config.ts` caps
  the workers at four.
- `python tools/apply_migrations.py` reported `65 migration file(s), 0 pending,
  0 changed` at that point. `tools/build_migrations.py` writes `001`-`063` only
  and refuses to run if `064_required_reference_seeds.sql` or
  `065_schema_indexes.sql` is missing.
- `tools/compare_catalogue.py` exited 0 with 421 functions and 6227 grants.

### 9.2 What is not verified

- `REPORTING` still has 0 RLS policies and 0 RPCs that check its permissions.
  The ten reporting views are `security_invoker` views, so they inherit the RLS
  of their base tables, but `global_search` is `LANGUAGE sql, STABLE` and
  checks no permission code. That hole is G-1 in [RTM.md](RTM.md) and it is
  still open.
- The employee and the student personas were exercised through the browser and
  the live database, not through the automated end-to-end suite. The suite
  signs in with one account - the administrator - because the password grant
  endpoint is throttled and one session has to serve the whole run.

---

## 10. The round that made the six module screens editable

On 2026-11-08 six module screens that had always been read-only gained a
**Manage** panel: the academic calendar, curriculum, courses, students,
registration and timetable. The round ran from about 06:00 to 06:45 local;
section 7 lists the steps in order.

The cause was not a permission. The screens showed their rows because the rows
were readable, but nothing could change them: none of the six screens had a
write RPC, and the generic reference editors - `sims_private.ref_tables()` and
`sims_private.section_def()` - do not list their tables either. The proof was
that impersonating the signed-in administrator's JWT and issuing
`INSERT academic_year`, `UPDATE academic_term` and `INSERT time_slot` against
PostgREST all succeeded.

| Screen | Editable tables | Permission prefix |
|---|---|---|
| `/calendar` | `academic_year`, `academic_term`, `semester`, `time_slot` | `ACADEMIC_CALENDAR` |
| `/curriculum` | `curriculum_scheme`, `curriculum_course` | `CURRICULUM` |
| `/courses` | `course_catalog`, `course_category` | `CURRICULUM` |
| `/students` | `student`, `student_programme_enrolment` | `STUDENT`, `ADMISSION` |
| `/registration` | `programme_term_offering`, `course_offering`, `class_section`, `student_term_registration` | `REGISTRATION`, `TEACHING` |
| `/timetable` | `time_slot`, `room` | `ACADEMIC_CALENDAR`, `INSTITUTION` |

Three tables carry a prefix that belongs to a different module, and that is
deliberate: `student_programme_enrolment` is written under `ADMISSION.ALL.*`,
`course_offering` under `TEACHING.ALL.*` and `room` under `INSTITUTION.ALL.*`
(scoped through `building_id -> building.campus_id`). The prefix is the one the
row level policy already uses, so the panel and the policy cannot disagree.

The round added `supabase/migrations/066_admin_editing.sql` - the catalogue
`sims_private.admin_table_def`, the helpers `admin_holds`, `admin_scope_value`
and `admin_can`, and the five public functions `admin_table_list`,
`admin_table_schema`, `admin_table_save`, `admin_table_delete` and
`admin_lookup_options`. It also added the two audit triggers that were missing:
`trg_time_slot_audit` (module `ACADEMIC_CALENDAR`) and `trg_room_audit`
(module `TIMETABLE`). Without them a change to a time slot or a room would have
gone unrecorded.

The write functions are `SECURITY DEFINER`, so the row level policies do not run
for them. Each one therefore makes the same decision the policy makes, in two
parts: the row that exists now (`USING`) and the row as it is afterwards
(`WITH CHECK`). The second part is what stops a scoped caller from moving a row
out of its own scope - a department cannot hand its course to another
department. A refusal raises, and the write and its audit row are rolled back
together.

### 10.1 What is verified

- The migration was applied to the live project at 06:15:59 local on 2026-11-08.
  `python tools/apply_migrations.py` reports `66 migration file(s), 0 pending,
  0 changed`.
- The catalogue was re-dumped and the contract re-blessed: 431 functions, 142
  triggers and 6253 grants. `tools/compare_catalogue.py` exits 0 with 0
  differences.
- The whole chain was exercised through PostgREST with a real signed-in
  session. `admin_table_list` returns 15 tables to the administrator, 9 to the
  faculty persona and 0 to the student. A create, update and delete round trip
  succeeded for `academic_year`, `course_catalog`, `student`, `time_slot` and
  `room`.
- The refusals are the ones the policy would produce: 403 `Not authorised to
  update courses (CURRICULUM.ALL.UPDATE)`, 403 `Not authorised to update
  courses outside your scope (CURRICULUM.ALL.UPDATE)`, 400 `This row is still
  in use and cannot be deleted` and 409 `That value is already recorded
  (uq_student_term_registration)`. A refused write left no trace.
- The audit trail holds exactly one row per change, with the uniform action
  codes `INSERT`, `UPDATE` and `DELETE`. Audit ids 132-153 are historical
  duplicates from the runs before the two missing triggers were added; the ids
  from 154 on are clean.
- `tests/db/admin-editing.test.ts` - 11 tests on embedded PostgreSQL - passes.
- `tests/e2e/admin-editing.spec.ts` - 7 tests - passes: the six screens offer
  the expected tables, and the academic calendar round trip adds a row, has a
  duplicate refused, edits the row and deletes it. The whole Playwright suite is
  90 tests.
- `tools/build_migrations.py --check` reports `OK - the 66 migration files are
  up to date`. The builder strips the hand-written objects from the catalogue
  before it builds, so a rebuild never creates one of them twice.
- `tools/validate/nav_rbac_connectivity.py` now counts the generic admin
  surface as a third tier of enforcement, because the permission code it checks
  comes from the catalogue and is not a literal in the function body.
- The catalogue check is repeatable. The append-only audit logs -
  `activity_audit` and five others - are left out of the dump's row counts,
  because their count is a function of activity rather than of the schema.
  `node tools/verify.mjs` now passes twice in a row, which it did not before:
  the end-to-end suite writes three audit rows per run, and the catalogue
  check ran before the suite.
- One leftover test row was found in the live project and removed: the course
  `FAC-1` from the round trip of an earlier verification run. It was deleted
  through `admin_table_delete`, so the removal is audited like any other
  change.

### 10.2 What is not verified

- The panel was exercised in a browser with the administrator's session only.
  The faculty and student personas were checked through the database - the
  table list and the refusals - but not through the browser, because the
  Playwright suite signs in with one account.
- The end-to-end round trip covers `academic_year` only. The other fourteen
  editable tables are covered by the database test and by the live database
  checks, not by a browser round trip.

---

## 11. The round that gave every module its Manage panel

On 2026-11-08 the round of section 10 was widened. The six screens of that
round were the first symptom; the real gap was that the **Employees** screen
and 25 further module screens had no editing surface at all, and that the
catalogue of migration 066 held only 15 tables.

### 11.1 How the catalogue was built

The catalogue was **not** written by hand. Every table on the live project that
carries a writable row level policy was parsed: the policy's own permission
codes were taken **verbatim** (`EMPLOYEE.AADHAAR.CREATE`,
`STAFF_PROFILE.STAFF_ACTIVITY.CREATE` and so on), and the scope was read off
the policy's `USING` / `WITH CHECK` expression. 127 writable tables out of 213,
parsed with zero problems.

Two scope kinds had no equivalent in the first round and were added:

| Kind | What it resolves |
|---|---|
| `employee` | The employee record's own institution, and the institution of its current assignment - `sims_private.can_employee(codes, id, true)` |
| `institution` | The row's own institution - `sims_private.can_institution(codes, id)` |

The scope is generalised to a **path**: the table's own column first, then
`table.column` foreign key hops, up to four. That is how a row three tables
away from its institution still resolves to the right scope.

### 11.2 What the round changed

| | Before | After |
|---|---|---|
| Catalogue | 15 tables | **127 tables across 17 modules** |
| Foreign key lookups | 24 | **70** - one for every FK target of the 127 tables |
| Audit triggers | 40 | **88** - the 48 tables that had none got one |
| Audit paths | trigger only | 88 `TRIGGER` + 39 `MANUAL`, exactly one per table |
| Write functions | `admin_table_save(text, bigint, jsonb)` | `admin_table_save(text, jsonb, jsonb)` - a JSON key, so a composite key can address a row |
| Screens with the panel | 6 | **28** |

Six tables have a **composite key**: `conference_activity_indexing`,
`course_prerequisite`, `employee_competency`, `evidence_document_tag`,
`external_organization_type` and `journal_publication_indexing`. Their key
columns stay in the form, because a new row has to be given its key, and
`sims_private.admin_key_where` refuses a partial key.

The 39 `MANUAL` tables are the ones whose own write path already calls
`sims_private.audit_manual`. The write function audits them itself, so a
change is still exactly one audit row - a trigger as well would have doubled
the trail. Their action code is `INSERT` / `UPDATE` / `DELETE`, the codes
`audit_manual` uses.

### 11.3 What is verified

- `supabase/migrations/067_admin_editing_expansion.sql` was applied to the live
  project: `applied 067_admin_editing_expansion.sql (133 statement(s), 8339 ms)`.
  The live database now carries 127 catalogue rows, 70 lookups and 88 audit
  triggers, with **0** tables marked `TRIGGER` that have no trigger and **0**
  marked `MANUAL` that have one.
- The whole chain was exercised through PostgREST with the signed-in
  administrator: `admin_table_list` returns 127 tables and 17 modules,
  `admin_table_schema('employee')` returns the key `employee_id` and 23
  columns, `admin_table_schema('course_prerequisite')` returns the composite
  key `['course_id', 'prerequisite_course_id']`, and a create / delete round
  trip on `gender` succeeded.
- `tests/db/admin-editing.test.ts` - **18 tests** on embedded PostgreSQL -
  passes. It covers the catalogue, the composite key, the employee and
  institution scope kinds, the audit path of every one of the 127 tables, and
  the refusal paths.
- `tests/e2e/admin-editing.spec.ts` - 30 tests - passes: all 28 screens offer
  the tables of their modules, the academic calendar round trip still works,
  and the Employees screen reaches the employee master.
- `tools/build_migrations.py --check` reports `OK - the 67 migration files are
  up to date`. The builder strips the hand-written objects from the catalogue
  before it builds, so a rebuild never creates one of them twice.
- The catalogue contract was re-blessed: 433 functions, 190 triggers and 6256
  grants. `tools/compare_catalogue.py` exits 0 with 0 differences.

### 11.4 What is not verified

- The browser round trip still covers `academic_year` only. The other 126
  tables are covered by the database test and by the live database checks.
- The three personas are still exercised through the database rather than
  through the browser, because the Playwright suite signs in with one account.

---

## 12. Rules that came out of this

1. **Never run `Remove-Item -Recurse -Force` on a path under `F:\sims`.** The
   original command used `-ErrorAction SilentlyContinue`, which suppressed the errors
   that would have shown it was about to delete the wrong thing.
2. **Delete one file at a time, with the literal full path**, and verify the path
   resolves to a file before deleting it.
3. **Keep the scratch area outside the project.** Recovery scripts live in
   `C:\Users\Samarth\AppData\Local\Temp\opencode\`, never in `F:\sims`.
4. **Put the project under version control.** There was no `.git` directory, which
   turned a recoverable mistake into a total loss.
5. **The live database is the source of truth.** It survived intact and was able to
   rebuild the entire schema layer.

---

## 13. Related documents

- [README.md](README.md) - index of the documentation set.
- [RTM.md](RTM.md) - module-by-module traceability, including the gaps.
- [NAVIGATION.md](NAVIGATION.md) - the sidebar contract and its enforcement test.
- [RLS_SECURITY_MODEL.md](RLS_SECURITY_MODEL.md) - the security model and its known holes.
- [MODULE_DOCUMENTATION.md](MODULE_DOCUMENTATION.md) - what each screen does.
- [DATABASE_MIGRATION.md](DATABASE_MIGRATION.md) - the MySQL to PostgreSQL translation record.
