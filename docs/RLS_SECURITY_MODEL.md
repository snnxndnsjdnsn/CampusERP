# RLS and the security model

The database is the authorisation boundary. Every read and every write is decided
by a row-level security policy or by a `SECURITY DEFINER` function that checks a
permission code. The application never decides permissions; it only reads what it
is given.

This document describes the model as it exists on the live database. Every
function, view, table and policy named here was read out of the live catalogue
(read-only queries). Where the model has a known hole, the hole is stated.

For the identity story and the "not done yet" list see
[AUTHENTICATION_AND_RBAC.md](AUTHENTICATION_AND_RBAC.md). For the per-table
policy map see [RLS_POLICY_MAP.md](RLS_POLICY_MAP.md). For the sidebar see
[NAVIGATION.md](NAVIGATION.md).

## 1. Identity map

```
auth.uid()                                  -- from the signed JWT; the only client-supplied input
   └─ sims_private.auth_identity_map(auth_user_id PK, user_id UNIQUE)
        └─ public.user_account(user_id)     -- account_status='ACTIVE', not locked, MFA satisfied
             ├─ public.student_user_account(student_id, user_id)
             └─ public.employee_user_account(employee_id, user_id)
```

`sims_private.current_user_id()` is the single entry point:

```sql
SELECT m.user_id INTO v_id
  FROM sims_private.auth_identity_map m
  JOIN public.user_account u ON u.user_id = m.user_id
 WHERE m.auth_user_id = auth.uid()
   AND u.account_status = 'ACTIVE'
   AND (u.locked_until IS NULL OR u.locked_until <= now())
   AND (NOT u.multi_factor_enabled OR sims_private.jwt_aal() = 'aal2');
```

Four consequences, all of them fail-closed:

1. **An Auth user id is never assumed to equal a user, student or employee id.**
   The map is the only bridge.
2. **The map is written only by `sims_private.link_auth_user()`**, which is granted
   to `service_role` only. `authenticated` cannot read or write it. The nine
   `sims_private` tables are granted to `postgres` only.
3. **`user_metadata` / `app_metadata` are never read.** `auth.uid()` from the
   verified JWT is the only client-influenced input.
4. **A disabled, locked, pending or MFA-unproven account resolves to `NULL`**, and
   every policy that calls `current_user_id()` denies. `sims_private.is_active_member()`
   is simply `current_user_id() IS NOT NULL`.

`sims_private.current_student_id()` and `sims_private.current_employee_id()`
resolve the person links the same way, through `student_user_account` and
`employee_user_account`. They return `NULL` when the account is not linked.

## 2. The permission grammar

Every permission is `MODULE.RESOURCE.ACTION`.

| Segment | Source | Example |
|---|---|---|
| `MODULE` | `access_module.module_code` — 22 rows | `EMPLOYEE` |
| `RESOURCE` | `access_resource.resource_code` — 40 rows | `BANK_ACCOUNT`, or `ALL` |
| `ACTION` | `access_action.action_code` — 12 rows | `READ`, `UPDATE`, `VERIFY` |

The twelve actions are `APPROVE`, `ASSIGN`, `CONFIGURE`, `CREATE`, `DELETE`,
`DOWNLOAD`, `EXPORT`, `IMPERSONATE`, `PUBLISH`, `READ`, `UPDATE`, `VERIFY`.

`access_resource` holds 40 rows: **21 `ALL` rows** (one per module that has a
module-wide resource) and **19 specific rows**. The specific resources are:

| Module | Specific resources |
|---|---|
| EMPLOYEE | `QUALIFICATION`, `EXPERIENCE`, `BANK_ACCOUNT`, `PAN`, `AADHAAR`, `EMPLOYEE_DOCUMENT` |
| FEES | `FEE_STRUCTURE`, `FEE_ASSESSMENT`, `FEE_PAYMENT`, `FEE_BENEFIT`, `FEE_REFUND`, `FEE_REPORT` |
| STAFF_PROFILE | `STAFF_ACTIVITY`, `STAFF_EVIDENCE`, `STAFF_RESEARCH`, `STAFF_REPORT` |
| STUDENT | `STUDENT_ACTIVITY`, `STUDENT_ACTIVITY_EVIDENCE`, `STUDENT_ACTIVITY_REPORT` |

**`FEES` has no `ALL` resource at all** — only its six specific ones. That is
deliberate, and it is what makes the sensitive-resource rule below bite.

The catalogue holds 384 permissions: 257 ordinary and **127 sensitive**
(`permission.is_sensitive = true`).

## 3. Effective permissions

### The source view

`public.v_effective_user_permission` is the union of two sources, grouped so
that a DENY at the same `(user, permission, scope)` wins:

```sql
-- v_active_role_permission: role_permission joined to the caller's active
-- assignments, plus the same grants reached through role_delegation.
-- user_permission_override: per-user overrides, valid_from/valid_to checked.
SELECT user_id, permission_id, permission_code, scope_type, scope_entity_id,
       CASE WHEN max(is_deny) = 1 THEN 'DENY' ELSE 'ALLOW' END AS permission_effect
  FROM ( ... UNION ALL ... ) x
 GROUP BY user_id, permission_id, permission_code, scope_type, scope_entity_id;
```

The scope of a grant is one of `GLOBAL`, `INSTITUTION`, `CAMPUS`, `DEPARTMENT`,
`PROGRAMME`, `SELF`. `GLOBAL` and `SELF` carry `scope_entity_id = 0` or the user
id; the others carry the entity id.

### `sims_private.eff()`

`eff(p_codes text[])` is the raw accessor. It returns one row per effective grant
for the given permission codes:

```sql
CREATE OR REPLACE FUNCTION sims_private.eff(p_codes text[])
 RETURNS TABLE(scope_type text, scope_entity_id bigint, permission_effect text)
 LANGUAGE plpgsql STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE v_uid bigint := sims_private.current_user_id(); ...
BEGIN
    IF v_uid IS NULL THEN RETURN; END IF;         -- no identity -> no grants at all
    ...
    SELECT COALESCE(jsonb_agg(jsonb_build_array(v.scope_type, v.scope_entity_id, v.permission_effect)), '[]')
      INTO v_json
      FROM public.v_effective_user_permission v
     WHERE v.user_id = v_uid AND v.permission_code = ANY (p_codes);
    ...
END $$;
```

It is `STABLE`, `SECURITY DEFINER`, with `search_path` pinned to `public, pg_temp`,
and it caches its result in a transaction-local `current_setting` keyed on the
user id and the permission set.

`sims_private.eff_set_of(p_codes)` is the aggregated form. It returns a
composite `sims_private.eff_set` with twelve fields — one allow flag and one deny
flag per scope type, plus the id arrays:

| Field | Meaning |
|---|---|
| `ga`, `gd` | GLOBAL allow / deny |
| `sa`, `sd` | SELF allow / deny |
| `ai`, `di` | INSTITUTION allow / deny id arrays |
| `ac`, `dc` | CAMPUS allow / deny id arrays |
| `ad`, `dd` | DEPARTMENT allow / deny id arrays |
| `ap`, `dp` | PROGRAMME allow / deny id arrays |

## 4. Scope containment

A grant at a higher scope covers the rows below it in the hierarchy

```
institution → campus → department → programme
```

`sims_private.covers()` implements it:

```sql
CREATE OR REPLACE FUNCTION sims_private.covers(
    p_codes text[], p_inst bigint, p_campus bigint, p_dept bigint, p_prog bigint,
    p_self_ok boolean DEFAULT false)
 RETURNS boolean
 LANGUAGE plpgsql STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE s sims_private.eff_set := sims_private.eff_set_of(p_codes);
BEGIN
    RETURN (s.ga
         OR (p_self_ok AND s.sa)
         OR COALESCE(p_inst  = ANY (s.ai), false)
         OR COALESCE(p_campus = ANY (s.ac), false)
         OR COALESCE(p_dept = ANY (s.ad), false)
         OR COALESCE(p_prog = ANY (s.ap), false))
       AND NOT (s.gd
         OR (p_self_ok AND s.sd)
         OR COALESCE(p_inst  = ANY (s.di), false)
         OR COALESCE(p_campus = ANY (s.dc), false)
         OR COALESCE(p_dept = ANY (s.dd), false)
         OR COALESCE(p_prog = ANY (s.dp), false));
END $$;
```

So a `DEPARTMENT` grant covers the programmes inside that department; a `CAMPUS`
grant covers every department in that campus; an `INSTITUTION` grant covers
everything below it; `GLOBAL` covers everything.

Note that the source view returns **exact-scope rows only**. Containment is not
the view's job — it is `covers()`'s job, and it is applied at policy evaluation
time.

## 5. DENY wins

The `AND NOT (...)` clause above is the whole rule: **if any covering scope denies
the permission, the answer is no, regardless of how many other scopes allow it.**

- A DENY at `GLOBAL` beats an ALLOW at any scope.
- A DENY at `DEPARTMENT` beats an ALLOW at `PROGRAMME` inside that department.
- A DENY at `INSTITUTION` beats an ALLOW at `CAMPUS`, `DEPARTMENT` or `PROGRAMME`
  inside it.

The same rule is applied one level up, inside the view: when a role grant and a
user override land on the same `(user, permission, scope)`, `max(is_deny) = 1`
makes the effect `DENY`.

This is **stricter than "exact scope only"**. It is a deliberate decision and it
is flagged for owner confirmation in
[AUTHENTICATION_AND_RBAC.md](AUTHENTICATION_AND_RBAC.md).

One helper does **not** apply the deny rule: `sims_private.has_any_grant(p_codes)`
returns `s.ga OR s.sa OR cardinality(s.ai) + cardinality(s.ac) + cardinality(s.ad)
+ cardinality(s.ap) > 0` — it asks "does the caller hold this permission at all",
and ignores DENY. It is a coarse "is this feature available" probe, not an
authorisation decision. Do not use it where a DENY must be honoured.

## 6. SELF scope

`SELF` means "the caller's own record". It is used for the student and employee
self-service paths.

- `SELF` is honoured **only when the caller passes `p_self_ok = true`**, and only
  for reads.
- In `can_employee(p_codes, p_id, p_write)` the SELF branch is
  `IF NOT p_write AND p_id IS NOT NULL AND (s.ga OR s.sa) AND NOT (s.gd OR s.sd)
  AND p_id = sims_private.current_employee_id() THEN RETURN true;`
  — so a SELF grant lets an employee read their own row, and a GLOBAL DENY still
  overrides it.
- `can_student(p_codes, p_id, p_write)` has the mirror-image branch against
  `sims_private.current_student_id()`.
- `can_user(p_codes, p_id, p_write)` is `can_global(...) OR (NOT p_write AND p_id
  = current_user_id())`.

The seed gives the `STUDENT` role SELF-scope grants, which is why a student can
see their own attendance, marks and fee account without any institutional grant.

## 7. The `can_*` family

All of these live in `sims_private` (there are no `can_*` functions in `public`).
All of them are `SECURITY DEFINER`, `STABLE`, with `search_path` pinned.

| Function | Scope it resolves | How |
|---|---|---|
| `can_global(p_codes)` | global only | `covers(p_codes, NULL, NULL, NULL, NULL, false)` |
| `can_institution(p_codes, p_id)` | the institution of `p_id` | `covers(p_codes, p_id, NULL, NULL, NULL, false)` |
| `can_campus(p_codes, p_id)` | institution + campus of `p_id` | looks the campus up in `public.campus`, falls back to `can_global` |
| `can_department(p_codes, p_id)` | institution + campus + department | looks the department up and joins `public.campus` |
| `can_programme(p_codes, p_id)` | institution + campus + department + programme | joins `public.programme → public.department → public.campus` |
| `can_employee(p_codes, p_id, p_write)` | the employee's institution, plus the scopes of their **current** assignments | `public.employee` for the institution; `public.employee_assignment` where `end_date IS NULL` for campus and department |
| `can_student(p_codes, p_id, p_write)` | the scopes of the student's **enrolments** | `public.student_programme_enrolment → programme → department → campus` |
| `can_user(p_codes, p_id, p_write)` | global, or the caller's own user row | `can_global` + SELF read |

`can_employee` and `can_student` both short-circuit on a GLOBAL allow (unless
there is a GLOBAL deny), then try SELF, then walk the hierarchy. If the caller has
no scoped grant at all they return `false` without doing the lookups.

`sims_private.emp_can(p_emp, p_resource, p_action, p_write)` is the convenience
wrapper that builds the code string:
`can_employee(ARRAY['EMPLOYEE.' || p_resource || '.' || p_action], p_emp, p_write)`.
`emp_all_can(p_emp, p_action)` does the same with `EMPLOYEE.ALL.<action>`.

## 8. Sensitive resources need their own grant

**A module-wide `ALL` grant does not open a sensitive resource.** The sensitive
resource must be granted by name.

The rule is visible directly in the policies. These are the real policy
expressions on the live database:

| Table | Policy expression | Grant required |
|---|---|---|
| `employee_pan` | `sims_private.can_employee(ARRAY['EMPLOYEE.PAN.READ'], employee_id, false)` | `EMPLOYEE.PAN.READ` |
| `employee_aadhaar` | `sims_private.can_employee(ARRAY['EMPLOYEE.AADHAAR.READ'], employee_id, false)` | `EMPLOYEE.AADHAAR.READ` |
| `employee_bank_account` | `sims_private.can_employee(ARRAY['EMPLOYEE.BANK_ACCOUNT.READ'], employee_id, false)` | `EMPLOYEE.BANK_ACCOUNT.READ` |
| `fee_structure` | `sims_private.can_programme(ARRAY['FEES.FEE_STRUCTURE.READ'], programme_id)` | `FEES.FEE_STRUCTURE.READ` |
| `payment_transaction` | `sims_private.can_student(ARRAY['FEES.FEE_PAYMENT.READ'], …)` | `FEES.FEE_PAYMENT.READ` |
| `student_document` | `sims_private.can_student(ARRAY['DOCUMENT.ALL.READ'], student_id, false)` | `DOCUMENT.ALL.READ` |
| `role` | `sims_private.can_global(ARRAY['IAM.ALL.READ'])` | `IAM.ALL.READ` |
| `permission` | `sims_private.can_global(ARRAY['IAM.ALL.READ'])` | `IAM.ALL.READ` |
| `user_account` | `(user_id = sims_private.current_user_id()) OR sims_private.can_global(ARRAY['IAM.ALL.READ'])` | own row, or `IAM.ALL.READ` |

`employee_pan`, `employee_aadhaar` and `employee_bank_account` are **separate
tables**, not columns of `employee`. Their policies name the specific resource,
so `EMPLOYEE.ALL.READ` alone does not reveal them.

### The ciphertext is never directly readable

`authenticated` holds **no SELECT privilege** on `pan_number_ciphertext`,
`aadhaar_number_ciphertext` or `account_number_ciphertext` — only INSERT and
UPDATE. The plaintext reaches a caller only through
`public.emp_sensitive_reveal(p_kind, p_id, p_purpose)`, which:

1. checks ownership or `EMPLOYEE.<KIND>.EXPORT`;
2. requires a stated purpose of 5–500 characters when the caller is not the owner;
3. writes an audit row through `sims_private.emp_sensitive_log(...)`;
4. decrypts with `sims_private.pii_decrypt(...)`.

`public.emp_sensitive_list(p_employee_id)` returns only masked values
(`pan_number_masked`, `aadhaar_number_masked`, `'XXXXXX' || account_number_last4`)
and a `can` block describing what the caller may do, with each sensitive resource
checked separately.

### Write-side rules

`sims_private.emp_write_allowed(p_emp, p_resource, p_existing_status)` encodes
the lifecycle: an employee may edit their own record while it is `PENDING`,
`PENDING_VERIFICATION` or `REJECTED`; once it is verified, only HR may change it
(`RAISE EXCEPTION 'A verified record can only be changed by HR'`).

`sims_private.emp_doc_rule_ok(p_doc, p_need)` checks
`public.employee_document_access_rule` for a live, time-bounded rule whose
`can_view` / `can_download` **columns** grant the caller access directly
(`user_id`) or through one of their roles (`role_id`). `p_need` is `'download'`
or anything else; `'download'` requires `can_download`, every other need accepts
`can_view OR can_download`.

Storage paths are authorised too: `sims_private.can_use_employee_doc_path(p_name,
p_write)` and `sims_private.can_use_student_doc_path(p_name, p_write)` check the
owner link or the matching permission before a signed URL is issued.

## 9. RLS is enforcement, not the sidebar

The sidebar decides what is **drawn**. It never decides what may be **read**.

`public.my_context()` returns `readable_modules`, which is only the set of
module segments of the caller's effective `*.READ` grants:

```sql
'readable_modules', COALESCE((SELECT jsonb_agg(DISTINCT split_part(v.permission_code, '.', 1))
                 FROM public.v_effective_user_permission v
                WHERE v.user_id = me.uid AND v.permission_effect = 'ALLOW'
                  AND v.permission_code LIKE '%.READ'), '[]'::jsonb)
```

That list is a **convenience filter**. A user who navigates straight to a URL
they were not shown reaches the page, and the page's queries are still filtered by
RLS and by the RPC's own permission check. Conversely, a user who *is* shown a
link may still see fewer rows than the link implies, because the row-level scope
is narrower than the module.

Three specific consequences:

- **`/announcements` is ungated in the sidebar** and that is intentional — the
  feed is visible to every signed-in user. The rows it returns are still filtered
  by `announcement_visible` / `announcement_audience_ok`.
- **`/my-results` and `/my-documents` are `studentOnly`** — drawn on the strength
  of the identity link. The rows behind them are still filtered by
  `can_student(...)` with the SELF branch.
- **`/audit` is gated on `AUDIT`** in the sidebar, but the audit module has **no
  RLS-protected tables of its own** — it is authorised entirely inside
  `SECURITY DEFINER` functions (`audit_list`, `audit_get`, `audit_modules`) that
  check `AUDIT.ALL.READ`. A module may be authorised by tier (a) table policies
  or tier (b) function bodies; only the absence of both is a gap.

The live connectivity check (`tools/validate/nav_rbac_connectivity.py`) proves
this chain for every module the sidebar exposes:

```
nav route → access_module code → permission codes → authorisation
           (a) an RLS policy names a MODULE.* permission
           (b) a SECURITY DEFINER public function checks a MODULE.* permission
```

## 10. The live catalogue

Read-only counts against `khqqfgqvwdxlqkncwtmh`:

| Object | Count | Note |
|---|---|---|
| `public` base tables | 213 | RLS enabled on **213**, disabled on **0**. `relforcerowsecurity` is `false` on all of them. |
| `public` views | 10 | all `security_invoker = true` |
| `public` policies | 594 | 212 SELECT, 127 INSERT, 127 UPDATE, 127 DELETE, 1 ALL. Every policy applies to `{authenticated}` only. |
| `public` functions | 274 | 231 are `SECURITY DEFINER` |
| `sims_private` functions | 146 | |
| `sims_private` tables | 9 | granted to `postgres` only; 0 policies in the schema |
| `public` triggers | 140 | |
| `permission` rows | 384 | 127 sensitive |
| `role` rows | 39 | 38 hold at least one grant |
| `role_permission` rows | 2,301 | |
| `access_module` rows | 22 | |
| `access_action` rows | 12 | |
| `access_resource` rows | 40 | 21 `ALL`, 19 specific |

### Role grants

`authenticated` holds:

- **0** table-level SELECT on base tables. Instead it holds **column-level SELECT
  on 212 of the 213 base tables** — the single exception is `counselling_session`,
  which has no column-level SELECT at all. (The 222 distinct table names reported
  by `information_schema.column_privileges` are those 212 base tables plus the 10
  views.)
- table-level INSERT / UPDATE / DELETE on **127** tables.
- table-level SELECT on the **10** views.
- EXECUTE on **230 of 274** `public` functions and **66 of 146** `sims_private`
  functions.

`anon` holds **0** grants on `public` tables. Its 20 table grants are on
Supabase's own `realtime` and `storage` schemas, which are outside this model.

**`PUBLIC` cannot execute anything.** `PUBLIC EXECUTE` is revoked on **418 of the
420** functions in `public` + `sims_private`, 352 of which are `SECURITY DEFINER`.
The two exceptions are `sims_private.tt_can_read_pto` and
`sims_private.describe_columns`. `anon` holds `EXECUTE` on exactly one `public`
function, `auth_failure_record`, which has to be callable before sign-in.

> `supabase/migrations/021_finance_rpcs.sql` carries these 418 `REVOKE`
> statements, so a database rebuilt from the migration set has the same ACLs as
> the live project. `tools/compare_catalogue.py` confirms 0 grant differences
> against the expected contract.
> See S-8 below for how this was nearly missed.

## 11. Known holes

| # | Hole | Detail |
|---|---|---|
| S-1 | `REPORTING` is declared but unenforced | 11 permissions, 0 RLS policies, 0 functions that check them. `global_search` is `LANGUAGE sql, STABLE` — **not** `SECURITY DEFINER` — and checks no permission code. |
| S-2 | `has_any_grant()` ignores DENY | It answers "is this permission held at all", not "is it allowed here". Never use it as an authorisation decision. |
| S-3 | `relforcerowsecurity` is `false` on all 213 tables | The table owner (`postgres`) bypasses RLS. That is correct for a migration/ops role, but it means the live database's owner can read everything by design. |
| S-4 | `sims_private` has 0 policies | It is not exposed through the Data API and is granted to `postgres` only, so it relies on privilege separation rather than RLS. Six of its nine tables have no RLS enabled at all (`mfa_recovery_attempt`, `mfa_recovery_code`, `mfa_required_role`, `notification_dismissal`, `receipt_counter`, `student_service_request`). |
| S-5 | `user_account.password_hash` still exists | It is a leftover of the MySQL design. Supabase Auth owns credentials; the column is not client-readable. |
| S-6 | No bootstrap administrator | There is no first `SUPER_ADMIN` assignment in the live database. `tools/create_admin.mjs` can create one - it makes the sign-in account through the Supabase Admin API, provisions or links `public.user_account`, and assigns the role at GLOBAL scope. It prints the plan and writes nothing unless `--apply` is passed, and it has not been run. |
| S-7 | The auth flows have never been exercised signed in against the real project | No Auth user existed at the time of writing. |
| S-9 | `my_context().permissions` and `my_context().readable_modules` disagree | A student comes back with **10 readable modules** and an **empty permission list**. The SELF scoped grants are dropped from `permissions` but kept in `readable_modules`. A client that gates on the wrong field sees the wrong thing. |
| S-10 | The RPC error contract is inconsistent | `audit_get`, `ref_schema` and `ref_rows` raise `Not authorised (...)`; `audit_list`, `audit_modules` and `ref_list` silently return `[]` for the same unauthorised caller. A caller cannot distinguish "not allowed" from "no data". |

### S-8 (resolved) - the regenerated migrations did not reproduce the function ACLs

This was found while writing this document and has since been fixed.

The live database has `PUBLIC EXECUTE` revoked on **418 of the 420** functions in
`public` + `sims_private`, 352 of them `SECURITY DEFINER`. The migration set that
was on disk at the time (the 23:49:34 regeneration from the live catalogue)
contained **no `REVOKE` statement at all**, so a database rebuilt from it would
have left `PUBLIC` able to execute every function, including the
`SECURITY DEFINER` ones. The comparison then reported all 418 as missing
`PUBLIC EXECUTE`.

At 23:56:38 `npm run migrate:build` was re-run from the MySQL source.
`supabase/migrations/021_finance_rpcs.sql` now carries 418 `REVOKE` statements,
and `tools/compare_catalogue.py` reports **0** differences in grants and in every
other category. The hole is closed; it is recorded here because the failure mode
- a catalogue dump records the grants that exist, not the revocations that were
applied - is worth remembering.

### S-11 (resolved) - the catalogue dropped the column level privileges

The same failure mode bit a second time, and harder.

The live project does **not** grant `authenticated` SELECT on the public tables
as a relation. It grants SELECT on every **column** instead, so the privilege
lives in `pg_attribute.attacl` and not in `pg_class.relacl`:

| Object | Live fact |
|---|---|
| `has_table_privilege('authenticated', 'public.student', 'SELECT')` | **false** |
| `has_column_privilege('authenticated', 'public.student', 'student_id', 'SELECT')` | **true** |
| columns carrying an `authenticated` grant | **2086** |
| public tables carrying at least one such grant | **212 of 213** |
| the exception | `counselling_session` — no grant at all |

The catalogue recorded `pg_class.relacl` but never `pg_attribute.attacl`, so the
migration set contained **zero** `GRANT SELECT (col, ...) ON TABLE ...`
statements. A database rebuilt from it would have refused **every** direct table
read with `permission denied for table X`, which makes all 594 RLS policies
unreachable through the Data API.

The fix has four parts:

1. `tools/dump_catalogue.py`, `tools/validate/catalogue.mjs` and
   `tools/validate/pg_catalogue.mjs` now capture `attacl` per column. The two
   independent dumpers produce byte-identical JSON.
2. `tools/build_migrations.py` emits the grants into migration 021 — 212
   statements, one per table.
3. `tools/build_migrations.py` **refuses to build** from a catalogue that carries
   no column privileges, so a stale dump cannot silently produce a broken
   migration set again.
4. `tests/db/rls.test.ts` asserts the grant shape, asserts that the hidden
   columns stay hidden, and asserts that `SELECT *` is refused on a table that
   hides one while a named column is allowed.

The columns that are deliberately **not** readable by `authenticated`:

| Table | Hidden column |
|---|---|
| `user_account` | `password_hash` |
| `password_history` | `password_hash` |
| `employee_pan` | `pan_number_ciphertext` |
| `employee_aadhaar` | `aadhaar_number_ciphertext` |
| `employee_bank_account` | `account_number_ciphertext` |
| `counselling_session` | every column |

The application reads 33 tables directly. Every one of them has all of its
columns granted, so no application read is affected by the column model; the
sensitive tables are reached only through the SECURITY DEFINER RPCs that check
a permission first.

## 12. Related documents

- [AUTHENTICATION_AND_RBAC.md](AUTHENTICATION_AND_RBAC.md) — identity, effective permissions, what is not done.
- [RLS_POLICY_MAP.md](RLS_POLICY_MAP.md) — the per-table policy → permission map.
- [ROLE_PERMISSION_MATRIX.md](ROLE_PERMISSION_MATRIX.md) — the per-role grant matrix.
- [NAVIGATION.md](NAVIGATION.md) — the sidebar and why it is only a convenience.
- [RTM.md](RTM.md) — module-by-module traceability.
