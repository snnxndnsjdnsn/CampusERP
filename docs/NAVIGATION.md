# Navigation

`src/lib/nav.ts` is the **single source of truth** for the sidebar. It exports
`NAV_GROUPS` (27 groups, 35 group routes and 15 staff sub-module children),
`NAV_ITEMS` (the flat view, 50 routes), the visibility helpers and `NAV_PARENTS`.
Nothing else in the application may declare a route order or a group label.

The same file is the contract for page builders: a route may only appear in the
sidebar if `src/app/(app)<route>/page.tsx` exists, and a new group may only be
added if the schema's numbered module structure supports it.

## The groups

| # | Group id | Label | Module(s) | Route(s) | Visibility rule | Page exists |
|---|---|---|---|---|---|---|
| 1 | `overview` | Overview | — | `/dashboard` | ungated | yes |
| 2 | `reference` | 1 · Common reference | IAM | `/admin/reference` | module `IAM` | yes |
| 3 | `institution` | 2 · Institution structure | INSTITUTION | `/structure` | module `INSTITUTION` | yes |
| 4 | `calendar` | 3 · Academic calendar | ACADEMIC_CALENDAR | `/calendar` | module `ACADEMIC_CALENDAR` | yes |
| 5 | `curriculum` | 4 · Curriculum & courses | CURRICULUM | `/curriculum`, `/courses` | module `CURRICULUM` | yes |
| 6 | `people` | 5 · Students & staff | STUDENT, EMPLOYEE | `/students`, `/employees` | module `STUDENT` / module `EMPLOYEE` | yes |
| 7 | `admission` | 6 · Admissions | ADMISSION | `/admissions` | module `ADMISSION` | yes |
| 8 | `registration` | 7 · Registration | REGISTRATION | `/registration` | module `REGISTRATION` | yes |
| 9 | `teaching` | 8 · Teaching & timetable | TIMETABLE | `/timetable` | module `TIMETABLE` | yes |
| 10 | `attendance` | 9 · Attendance | ATTENDANCE | `/attendance` | module `ATTENDANCE` | yes |
| 11 | `assessment` | 10 · Assessment & results | ASSESSMENT, RESULT | `/assessment`, `/results`, `/my-results` | `/assessment` = module `ASSESSMENT` **or** `RESULT`; `/results` = module `RESULT`; `/my-results` = `studentOnly` | yes |
| 12 | `feedback` | 11 · Feedback | FEEDBACK | `/feedback` | module `FEEDBACK` | yes |
| 13 | `support` | 12 · Mentoring & grievance | MENTORING, GRIEVANCE | `/mentoring`, `/grievances` | `/mentoring` = module `MENTORING`; `/grievances` = module `GRIEVANCE` **or** `alsoStudent` | yes |
| 14 | `documents` | 13 · Documents & certificates | DOCUMENT | `/certificates`, `/requests`, `/my-documents` | `/certificates` = module `DOCUMENT` **or** `alsoStudent`; `/requests` = module `DOCUMENT` **or** `alsoStudent`; `/my-documents` = `studentOnly` | yes |
| 15 | `communication` | 14 · Communication | — | `/announcements` | ungated (intentional) | yes |
| 16 | `iam` | 15 · Access & audit | IAM, AUDIT | `/admin/users`, `/audit` | `/admin/users` = module `IAM`; `/audit` = module `AUDIT` | yes |
| 17 | `hr` | 16 · Employee HR | — | `/my-hr` | `employeeOnly` | yes |
| 18 | `finance` | 17 · Fees & finance | FEES | `/finance` | module `FEES` | yes |
| 19 | `schema` | 18 · Performance indexes & storage | IAM | `/schema/18` | module `IAM` | yes |
| 20 | `staff` | 19 · Staff profile & research | STAFF_PROFILE | `/staff-profile` + 15 sub-module children (modules 20–34) | module `STAFF_PROFILE` | yes |
| 21 | `seed` | 35 · Seed reference data | IAM, STAFF_PROFILE | `/schema/35` | module `IAM` **or** `STAFF_PROFILE` | yes |
| 22 | `rbac` | 36 · Staff profile RBAC registration | IAM | `/schema/36` | module `IAM` | yes |
| 23 | `reporting` | 37 · Reporting & search views | REPORTING | `/reporting` | module `REPORTING` | yes |
| 24 | `staff-index` | 38 · Staff profile performance indexes | STAFF_PROFILE, IAM | `/schema/38` | module `STAFF_PROFILE` **or** `IAM` | yes |
| 25 | `integrity` | 39 · Data-integrity notes | IAM, AUDIT | `/schema/39` | module `IAM` **or** `AUDIT` | yes |
| 26 | `activities` | 40 · Student activities | STUDENT | `/activities` | module `STUDENT` **or** `alsoStudent` | yes |
| 27 | `account` | Account | — | `/settings` | ungated | yes |

The group order is the schema's numbered module order — `1..19`, then `35..39`,
then `40` — with `Overview` and `Account` as bookends.

The MySQL source has **42 numbered sections covering 40 module numbers** (`17A`
is a sub-module of 17, and `18` appears twice). The other 16 sections are not
groups of their own:

| Bucket | Sections | Count | Where they are |
|---|---|---|---|
| Own a screen | 1–17, 18, 18, 19, 35, 36, 37, 38, 39, 40 | 26 | the numbered groups above |
| Staff-profile sub-modules | 20–34 | 15 | children of the `staff` group — see below |
| Infrastructure | 17A | 1 | the cross-row enforcement triggers; no screen |

26 + 15 + 1 = 42. Every module number from `1` to `40` is now reachable from
the sidebar.

## The staff sub-modules (20–34)

Schema modules 20 to 34 are the specialised forms of the staff activity
supertype. The MySQL source gives each of them its own tables (`journal`,
`conference_event`, `faculty_internship`, `research_proposal`,
`funded_research_project`, `consultancy_project`, `cocurricular_activity`,
`extracurricular_activity`, `staff_award`, `staff_professional_membership`,
`staff_professional_contribution`, `evidence_document`,
`activity_evidence_requirement` and the rest), but the application models them
as **one screen**: `staff_activity` is a supertype and `activity_type` says
which specialised child table a row belongs to.

So each sub-module is an **address inside** `/staff-profile`, not a screen of its
own. `src/lib/staff-sections.ts` is the canonical map — slug, module number,
title and the `activity_type.activity_group` to filter by:

| Module | Address | Filter group |
|---|---|---|
| 20 · Staff activity supertype | `/staff-profile/activity` | — |
| 21 · Journals and journal publications | `/staff-profile/publication` | `PUBLICATION` |
| 22 · Conferences, publications and presentations | `/staff-profile/conference` | `CONFERENCE` |
| 23 · Workshop / FDP / STTP / training / certification | `/staff-profile/development` | `PROFESSIONAL_DEVELOPMENT` |
| 24 · Industry / faculty internship | `/staff-profile/internship` | `INTERNSHIP` |
| 25 · Research proposals | `/staff-profile/research` | `RESEARCH` |
| 26 · Funded research projects | `/staff-profile/funded-research` | `RESEARCH` |
| 27 · Consultancy / industry-sponsored project | `/staff-profile/consultancy` | `CONSULTANCY` |
| 28 · Co-curricular activities | `/staff-profile/co-curricular` | `CO_CURRICULAR` |
| 29 · Extra-curricular activities | `/staff-profile/extra-curricular` | `EXTRA_CURRICULAR` |
| 30 · Awards, honours and recognitions | `/staff-profile/award` | `AWARD` |
| 31 · Professional memberships and academic bodies | `/staff-profile/membership` | `MEMBERSHIP` |
| 32 · Academic and professional contributions | `/staff-profile/contribution` | `ACADEMIC_PROFESSIONAL_CONTRIBUTION` |
| 33 · Centralized evidence / document management | `/staff-profile/evidence` | — |
| 34 · Document/evidence requirement configuration | `/staff-profile/evidence-requirements` | — |

All fifteen are served by one dynamic route,
`src/app/(app)/staff-profile/[section]/page.tsx`, which opens the shared screen
(`src/features/staff-profile/staff-profile-screen.tsx`) filtered to the
section's group. An unknown slug renders the not-found page.

Two pairs are coarser than the schema, because `staff_activity_list` filters by
`activity_group` and not by activity type:

- modules 25 and 26 share the `RESEARCH` group, so both open the same list;
- modules 33 and 34 are edited inside the activity form, so they open the
  screen unfiltered.

In both cases the screen's own **Group** filter is the finer instrument, and an
explicit `?group=` in the address bar overrides the section's default.

### How children are drawn

A group may carry `children?: NavItem[]`. They are rendered indented under the
group's own items, with a smaller icon, in both the desktop sidebar and the
mobile bar. Children are gated exactly like group items — all fifteen carry
`module: 'STAFF_PROFILE'`, so they appear and disappear together with their
parent screen.

The active state is **deepest-match-wins** (`activeItem()` in
`src/components/app-shell.tsx`): the longest matching href is the current one.
`/staff-profile/publication` therefore marks the sub-module, not
`/staff-profile`. The same rule fixes `/admin/users/new` versus
`/admin/users`.

## The infrastructure modules (18, 35–39)

Six modules of the MySQL source are infrastructure rather than business
screens. They have no table of their own that a user would "work in", but each
one has real objects in the database, so each one now has a screen of its own
and its own number in the sidebar.

| Module | Address | Screen | Gate |
|---|---|---|---|
| 18 · Performance indexes | `/schema/18` | the index catalogue of the public schema, and the file-storage metadata of `file_object` | `IAM` |
| 35 · Seed reference data | `/schema/35` | the seeded lookup vocabulary — publication types, journal types, indexing agencies, metric types, funding types, activity types and the rest | `IAM` **or** `STAFF_PROFILE` |
| 36 · Staff profile RBAC registration | `/schema/36` | the `STAFF_PROFILE` access module, its resources, its permissions and the roles that hold them | `IAM` |
| 37 · Reporting & search views | `/reporting` | the ten reporting and search views, the live `global_search` and the two activity reports | `REPORTING` |
| 38 · Staff profile performance indexes | `/schema/38` | the index catalogue restricted to the staff-profile tables | `STAFF_PROFILE` **or** `IAM` |
| 39 · Data-integrity notes | `/schema/39` | the fourteen integrity rules the service layer enforces | `IAM` **or** `AUDIT` |

Modules 18, 35, 36 and 39 are served by one dynamic route,
`src/app/(app)/schema/[module]/page.tsx`; module 37 has a screen of its own at
`/reporting`, because it is a working screen rather than a catalogue.

**The gates are the point.** These six groups are the first ones whose
visibility is not simply "the module that owns the screen". A faculty member
sees 35, 37 and 38 but not 18, 36 or 39; a head of department sees 39 as well,
because `AUDIT` is in their readable modules; a student sees none of them. The
super administrator sees all six.

Module 37 is the one that closes the old gap G-1: `REPORTING` was a seeded
`access_module` code that no navigation entry used, so the reporting module had
no screen at all. It has one now, and `REPORTING` is no longer on the unit
test's allowlist of seeded-but-unused codes.

### The index catalogue

`pg_indexes` lives in `pg_catalog`, so PostgREST cannot expose it and the
browser cannot read it. Migration `065_schema_indexes.sql` adds one read-only
function that is the only door to it:

```sql
public.schema_indexes(p_scope text DEFAULT NULL)
```

`p_scope` is `'all'` (every index in the public schema, needs `IAM.ALL.READ`)
or `'staff'` (only the tables that carry a `STAFF_PROFILE.*` row-level-security
policy, needs `STAFF_PROFILE.ALL.READ`). The function is `SECURITY DEFINER`
because `pg_indexes` is not readable by the `authenticated` role; the
permission check inside it is the gate.

## The editable screens

Six of the groups above lead to a screen that can be **edited**, not only read:
`calendar` (3), `curriculum` (4), `people` (5), `registration` (7) and
`teaching` (8). Each of those screens carries a collapsible **Manage** panel
that adds, edits and removes the rows behind it.

The panel adds **no group and no route**. The sidebar is unchanged - the same
27 groups and the same 50 routes. What changed is that a screen which used to
be a read-only report now offers a write surface.

The panel's contents are decided by the database, not by the sidebar.
`public.admin_table_list()` returns only the tables the signed-in user holds a
write permission for, so a caller who may read a module but not write it sees
no panel at all, and a caller who may write sees only the tables their scope
covers. The rows themselves are read through PostgREST, so the row level
policies decide what is visible. The table-by-table breakdown is in
[RTM.md](RTM.md) under "The editable module screens".

## Visibility rules

Visibility is a **convenience**. It decides what is drawn; it never decides what
may be read. The database is the authorisation boundary (see
[RLS_SECURITY_MODEL.md](RLS_SECURITY_MODEL.md)).

### `readable_modules`

`ctx.readable_modules` comes straight from `public.my_context()`:

```sql
SELECT jsonb_agg(DISTINCT split_part(v.permission_code, '.', 1))
  FROM public.v_effective_user_permission v
 WHERE v.user_id = me.uid
   AND v.permission_effect = 'ALLOW'
   AND v.permission_code LIKE '%.READ'
```

So it is the set of distinct **module segments** of the caller's effective
`*.READ` grants — `STUDENT`, `FEES`, `IAM`, and so on. A nav item whose
`module` is `'STUDENT'` is drawn when `readable_modules` contains `STUDENT`.

`my_context()` also returns `permissions`: every effective `MODULE.RESOURCE.ACTION`
grant with `scope_type <> 'SELF'`. That is what `can()` / `canAny()` in
`src/lib/context.ts` match against.

### The four gates on a `NavItem`

`itemVisible()` in `src/lib/nav.ts` evaluates the gates in a fixed order. The
**first** matching gate decides; later gates are not consulted.

| Order | Gate | Condition | Effect |
|---|---|---|---|
| 1 | `studentOnly` | `ctx.student_id !== null` | Drawn only for a signed-in account linked to a student record. Wins over every other gate. |
| 2 | `employeeOnly` | `ctx.employee_id !== null` | Drawn only for a signed-in account linked to an employee record. |
| 3 | `module` | `readable_modules` contains the code | Drawn when the caller can read that module. An **array** means *any one* of the codes is enough. |
| 4 | `alsoStudent` | `ctx.student_id !== null` | Fallback for gate 3 only: the feature authorises students by identity, so a linked student sees it even without the module grant. |

```ts
function itemVisible(i: NavItem, ctx: SimsContext, mods: ReadonlySet<string>): boolean {
  if (i.studentOnly) return ctx.student_id !== null;
  if (i.employeeOnly) return ctx.employee_id !== null;
  if (!i.module) return true;
  const readable = Array.isArray(i.module) ? i.module.some((m) => mods.has(m)) : mods.has(i.module);
  return readable || (i.alsoStudent === true && ctx.student_id !== null);
}
```

Consequences worth stating explicitly:

- **No `module` means always visible.** `/dashboard`, `/announcements` and
  `/settings` have no `module`, so they are drawn for every signed-in, provisioned
  user. The announcement feed is deliberately ungated; the code says so in a
  comment.
- **`studentOnly` short-circuits.** `/my-results` and `/my-documents` are drawn on
  the strength of the identity link alone. They are *not* gated on `RESULT` or
  `DOCUMENT` being in `readable_modules`.
- **`alsoStudent` is a fallback, not an override.** It only applies when the
  `module` gate failed. `/grievances` is drawn for a linked student even without
  `GRIEVANCE` in `readable_modules`; `/certificates` and `/requests` likewise for
  `DOCUMENT`.
- **An array is OR, not AND.** `/assessment` carries `module: ['ASSESSMENT', 'RESULT']`
  and is drawn if the caller can read either.
- **`studentOnly` beats `alsoStudent`.** A student who is also an employee still
  gets the student-only items; the employee-only item is a separate item and is
  evaluated on its own.

### Empty groups are dropped

`visibleNavGroups()` filters each group's items and its children, then keeps the
group only if at least one item survived:

```ts
for (const g of NAV_GROUPS) {
  const items = g.items.filter((i) => itemVisible(i, ctx, mods));
  const children = g.children?.filter((i) => itemVisible(i, ctx, mods));
  if (items.length > 0) out.push({ ...g, items, ...(children && children.length > 0 ? { children } : {}) });
}
```

So a user with no `FEES` grant does not see an empty "17 · Fees & finance"
heading. Item order inside a surviving group is preserved. `visibleNav()` is the
flat equivalent — it flattens items **and** children — and is used where a list
rather than groups is wanted.

`src/app/(app)/layout.tsx` calls `visibleNavGroups(ctx)` and passes the result to
the shell; `src/components/app-shell.tsx` renders it.

## Breadcrumbs and `NAV_PARENTS`

A route that is not a nav item still needs a breadcrumb. `app-shell.tsx` resolves
it in two steps:

1. **Prefix match, deepest wins.** The **longest** nav href that equals the
   pathname, or starts with `href + '/'`, is the current item. This is what gives
   `/finance/account/[id]` the "Fees" crumb, `/results/grades` the "Results"
   crumb, and `/staff-profile/publication` the "21 · Journals and journal
   publications" crumb rather than the plain "Staff profile" one.
2. **`NAV_PARENTS` fallback.** If no nav item matches, the shell looks the path up
   in `NAV_PARENTS`; failing an exact hit, it takes the longest key that prefixes
   the pathname.

```ts
export const NAV_PARENTS: Record<string, string> = { '/admin/mfa-policy': '/admin/users' };
```

`/admin/mfa-policy` has a `page.tsx` but is not a sidebar item, so it borrows the
"Users and roles" crumb. `NAV_PARENTS` currently has exactly one entry.

## How `tests/unit/nav-connectivity.test.ts` enforces the wiring

The unit test is the guard that keeps the sidebar honest. It has nine assertions.

| # | Assertion | What it proves | How |
|---|---|---|---|
| 1 | every nav href resolves to an existing app route | No dead links | For each `NAV_ITEMS` href, `routeExists()` walks the address under `src/app/(app)` and must land on a `page.tsx`. A literal folder that has no page of its own is followed, and a `[param]` folder is accepted when no literal one exists — so `/staff-profile/publication` resolves to `staff-profile/[section]/page.tsx`. The failure message lists every broken href. |
| 2 | every nav module is seeded as an `access_module` row | The sidebar's gate exists in the database | Parses every `supabase/migrations/*.sql` for `INSERT INTO access_module (...) VALUES (...);`, reads the `module_code` column by position (the schema qualifier and the column list are optional, tuples are split on top-level commas only), and requires every code used by the nav to be present. |
| 3 | every seeded `access_module` is used by navigation or explicitly allowlisted | No orphaned access codes | The reverse direction. The allowlist is exactly `TEACHING`, `COMMUNICATION`. `TEACHING` has no screen of its own (its screens live inside the registration and attendance flows), and `COMMUNICATION` is the intentionally ungated announcement feed. |
| 4 | every nav href has a sidebar icon | No blank icons | `ICONS` in `src/components/app-shell.tsx` must have an entry for every href. `ICONS` has 51 entries, covering all 50 nav hrefs plus `/results/grades`. |
| 5 | `NAV_GROUPS` stay in the canonical database module order | The sidebar keeps following the schema | The group id list is compared against a hard-coded array of the 27 ids in order. Adding, removing or reordering a group fails the test. |
| 6 | the staff group carries every research sub-module, 20 to 34 | The module numbering is complete | The `staff` group's `children` must be exactly the 15 addresses in `STAFF_SECTIONS`, their labels must start with the module numbers `20`…`34` in order, and every child must be gated by `STAFF_PROFILE`. |
| 7 | every staff sub-module address is a known section | No dead sub-module | Each child address must map to a section in `STAFF_SECTIONS`, so a typo cannot reach the sidebar. |
| 8 | an address that no route serves is rejected | The route check is not vacuous | `routeExists()` must answer `false` for an address no page serves and `true` for a real one, so a broken matcher cannot make assertion 1 pass. |
| 9 | the six new schema screens are wired into the sidebar | The modules that had no screen now have one | For each of modules 18, 35, 36, 37, 38 and 39 the group must exist, carry the module's number in its label, hold exactly one item, point at the right address and be gated on the right access_module code(s). |

The test also carries the two SQL helpers `splitTopLevelTuples` and
`splitTopLevel`, which split a `VALUES` body on commas that are not inside a
string literal — so a quoted module name containing a comma cannot shift the
columns.

### Current result

All nine assertions hold against the current tree.

| Assertion | Result |
|---|---|
| 1 - every nav href resolves | **50 / 50.** Every href in `NAV_ITEMS` resolves to a `page.tsx`; the 15 sub-module addresses share `staff-profile/[section]/page.tsx`. |
| 2 - every nav module is seeded | **Pass.** The migrations seed all 22 `access_module` codes, including `FEES` and `STAFF_PROFILE`, and every code the nav uses is among them. |
| 3 - every seeded code is used or allowlisted | **Pass.** The only seeded-but-unused codes are `TEACHING` and `COMMUNICATION`, which are the test's allowlist. `REPORTING` left that list when module 37 got its own screen. |
| 4 - every nav href has an icon | **Pass.** `ICONS` has 51 entries covering all 50 nav hrefs plus `/results/grades`. |
| 5 - the group order is locked | **Pass.** The 27 group ids are in the schema's module order. |
| 6 - the staff sub-modules are complete | **Pass.** 15 children, numbered 20 to 34 in order, all gated by `STAFF_PROFILE`. |
| 7 - every sub-module address is known | **Pass.** No child address falls outside `STAFF_SECTIONS`. |
| 8 - the route check is not vacuous | **Pass.** An address no page serves is rejected. |
| 9 - the six new screens are wired in | **Pass.** Modules 18, 35, 36, 37, 38 and 39 each have a group, a module number, one item, the right address and the right gate. |

`/staff-profile` and `/activities` were the last two routes to be written; both
`page.tsx` files now exist, so the `staff` and `activities` groups no longer render
dead links.

## Route inventory

### Nav items (50)

35 group routes:

`/dashboard`, `/admin/reference`, `/structure`, `/calendar`, `/curriculum`,
`/courses`, `/students`, `/employees`, `/admissions`, `/registration`,
`/timetable`, `/attendance`, `/assessment`, `/results`, `/my-results`,
`/feedback`, `/mentoring`, `/grievances`, `/certificates`, `/requests`,
`/my-documents`, `/announcements`, `/admin/users`, `/audit`, `/my-hr`,
`/finance`, `/schema/18`, `/staff-profile`, `/schema/35`, `/schema/36`,
`/reporting`, `/schema/38`, `/schema/39`, `/activities`, `/settings`.

plus the 15 staff sub-modules:

`/staff-profile/activity`, `/staff-profile/publication`,
`/staff-profile/conference`, `/staff-profile/development`,
`/staff-profile/internship`, `/staff-profile/research`,
`/staff-profile/funded-research`, `/staff-profile/consultancy`,
`/staff-profile/co-curricular`, `/staff-profile/extra-curricular`,
`/staff-profile/award`, `/staff-profile/membership`,
`/staff-profile/contribution`, `/staff-profile/evidence`,
`/staff-profile/evidence-requirements`.

### Detail routes that are not nav items (18)

`src/app/(app)` holds 50 `page.tsx` files. 32 of them back a nav item — the 35
group routes (five of which share `schema/[module]/page.tsx`), the one dynamic
route that serves all 15 sub-modules, and the rest one page each; the other 18
are detail pages. Most resolve their breadcrumb by prefix match;
`/admin/mfa-policy` uses `NAV_PARENTS`.

`/admin/reference/[table]`, `/admin/users/[id]`, `/admin/users/new`,
`/admin/mfa-policy`, `/audit/[id]`, `/audit/logins`, `/announcements/manage`,
`/employees/[id]/hr`, `/employees/[id]/records`, `/finance/account/[id]`,
`/finance/receipt/[id]`, `/finance/structures`, `/results/grades`,
`/students/[id]/documents`, `/students/[id]/records`, `/mfa`, `/notifications`,
`/search`.

## Related documents

- [RTM.md](RTM.md) — one row per database module, plus the navigation rows.
- [RLS_SECURITY_MODEL.md](RLS_SECURITY_MODEL.md) — why visibility is not authorisation.
- [MODULE_DOCUMENTATION.md](MODULE_DOCUMENTATION.md) — what each screen does.
