import { beforeAll, describe, expect, it } from 'vitest';
import { as, asUser, createWorld, db, ids, role, U } from './world';

/**
 * Row-level-security / RBAC integration tests.
 *
 * Everything runs against the embedded PGlite world built by `tests/db/world.ts`
 * (all migrations + the org/people/role fixture).  The live Supabase database is
 * never contacted.
 *
 * The fixture users are:
 *
 *   student1   user 1  STUDENT role, SELF scope            -> student 1
 *   registrar1 user 2  REGISTRAR role, INSTITUTION 1       -> students 1,2 / employee 1
 *   facultyD1  user 3  FACULTY role, DEPARTMENT 1         -> student 1 / employee 1 (owner)
 *   finance1   user 4  FINANCE_OFFICER role, INSTITUTION 1
 *   disabled   user 5  REGISTRAR role, INSTITUTION 1, account DISABLED
 *   unmapped   -      auth user without a user_account row
 *   denied     user 7  REGISTRAR role, INSTITUTION 1 + DENY on STUDENT.ALL.READ
 *   superAdmin user 8  SUPER_ADMIN role, GLOBAL scope
 *   registrar2 user 9  REGISTRAR role, INSTITUTION 2       -> student 3 / employee 2
 *
 * Org topology: institution 1/2; campus 1 -> inst 1, campus 2 -> inst 2;
 * department 1,2 -> campus 1 and department 3 -> campus 2; programme 1/2/3 ->
 * department 1/2/3; student 1/2/3 -> programme 1/2/3; employee 1 -> inst 1,
 * employee 2 -> inst 2.
 */

const TIMEOUT = 300_000;

beforeAll(async () => {
  await createWorld();

  // ---------------------------------------------------------------------------
  // No local grant workaround is needed any more.  The live project grants
  // `authenticated` SELECT on every *column* of 212 of the 213 public tables
  // (migration 021 reproduces that exactly), so a column list such as
  // `SELECT student_id FROM student` is allowed while `SELECT *` is refused on
  // the tables that hide a column (`user_account.password_hash`, the encrypted
  // PII columns, `counselling_session`).  `anon` has no table privileges at
  // all, so the RLS row filters are reachable for `authenticated` and closed
  // for `anon` -- exactly as on the live project.
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // Extra fixtures the world does not ship (tests/db/world.ts is off limits).
  //   * course_category: the FK target of course_catalog (empty in the world).
  //   * course_catalog: one row per department, to observe the DEPARTMENT
  //     scope of the course_catalog_select policy.
  //   * vault secret sims_pii_key: the key sims_private.pii_key() reads.
  //   * employee_pan: the encrypted PAN that emp_sensitive_reveal decrypts.
  // ---------------------------------------------------------------------------
  await db.exec(`
    INSERT INTO course_category (course_category_id, category_code, category_name)
      VALUES (9001, 'TSTCAT', 'Test Category');
    INSERT INTO course_catalog (course_id, owning_department_id, course_category_id, course_code, course_title, course_type, credits)
      VALUES (9001, 1, 9001, 'TST-D1', 'Test Course Dept 1', 'THEORY', 4),
             (9002, 2, 9001, 'TST-D2', 'Test Course Dept 2', 'THEORY', 4),
             (9003, 3, 9001, 'TST-D3', 'Test Course Dept 3', 'THEORY', 4);
    INSERT INTO vault.secrets (name, secret) VALUES ('sims_pii_key', 'test-pii-key');
    INSERT INTO employee_pan (employee_id, pan_number_ciphertext, pan_number_fingerprint, pan_number_masked, name_as_per_pan)
      VALUES (1,
              extensions.pgp_sym_encrypt('ABCDE1234F', 'test-pii-key'),
              encode(extensions.hmac('ABCDE1234F', 'test-pii-key', 'sha256'), 'hex'),
              'XXXXX1234F',
              'Emp One');
  `);
}, TIMEOUT);

describe('row level security', () => {
  // `ids()` reads a column literally named `id`, so every query below aliases
  // its key column as `id`.
  it('enables RLS and at least one policy on every public table', async () => {
    const { rows } = await db.query<{
      tables: number;
      with_rls: number;
      with_policy: number;
      policies: number;
      anon_policies: number;
    }>(`
      SELECT
        (SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'public' AND c.relkind = 'r') AS tables,
        (SELECT count(*)::int FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relrowsecurity) AS with_rls,
        (SELECT count(DISTINCT tablename)::int FROM pg_policies WHERE schemaname = 'public') AS with_policy,
        (SELECT count(*)::int FROM pg_policies WHERE schemaname = 'public') AS policies,
        (SELECT count(*)::int FROM pg_policies WHERE schemaname = 'public' AND 'anon' = ANY (roles)) AS anon_policies
    `);
    const c = rows[0]!;

    // Observed against the live catalogue dump as well: public: 213, policies: 594.
    expect(c.tables).toBe(213);
    expect(c.with_rls).toBe(c.tables);
    expect(c.with_policy).toBe(c.tables);
    expect(c.policies).toBe(594);
    expect(c.anon_policies).toBe(0);

    // No public table may be left without RLS, and none may be left without a policy.
    const missingRls = await db.query<{ relname: string }>(
      `SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind = 'r' AND NOT c.relrowsecurity ORDER BY 1`,
    );
    expect(missingRls.rows).toEqual([]);
    const missingPolicy = await db.query<{ tablename: string }>(
      `SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind = 'r'
          AND NOT EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname = 'public' AND p.tablename = c.relname)
        ORDER BY 1`,
    );
    expect(missingPolicy.rows).toEqual([]);

    // Every policy targets `authenticated` only -- the anon role has no way in.
    const roles = await db.query<{ roles: string[] }>(
      `SELECT DISTINCT roles FROM pg_policies WHERE schemaname = 'public'`,
    );
    expect(roles.rows.map((r) => r.roles)).toEqual([['authenticated']]);
  }, TIMEOUT);

  it('denies anonymous and unlinked authenticated callers by default', async () => {
    // anon has no table privileges at all (the live project grants `anon`
    // nothing in schema public), so the read is refused by the access control
    // layer before the row filters are even reached.  Both layers deny; the
    // ACL simply answers first.
    await expect(as('anon', null, 'SELECT student_id FROM student ORDER BY 1')).rejects.toThrow(
      'permission denied for table student',
    );
    await expect(as('anon', null, 'SELECT employee_id FROM employee ORDER BY 1')).rejects.toThrow(
      'permission denied for table employee',
    );
    await expect(as('anon', null, 'SELECT user_id FROM user_account ORDER BY 1')).rejects.toThrow(
      'permission denied for table user_account',
    );
    await expect(as('anon', null, 'SELECT institution_id FROM institution ORDER BY 1')).rejects.toThrow(
      'permission denied for table institution',
    );

    // authenticated without a JWT subject: the column grants apply, but no
    // policy matches, so the row filters return nothing.
    expect(await asUser(null, 'SELECT student_id FROM student ORDER BY 1')).toEqual([]);
    expect(await asUser(null, 'SELECT user_id FROM user_account ORDER BY 1')).toEqual([]);

    // authenticated whose auth user is not linked to an active user_account.
    expect(await asUser(U.unmapped, 'SELECT student_id FROM student ORDER BY 1')).toEqual([]);
    expect(await asUser(U.unmapped, 'SELECT employee_id FROM employee ORDER BY 1')).toEqual([]);
    expect(await asUser(U.unmapped, 'SELECT user_id FROM user_account ORDER BY 1')).toEqual([]);

    // The RPCs agree: no identity, no context.  The anon role is not even
    // granted EXECUTE on the public RPCs (only auth_failure_record is), so the
    // refusal happens one layer earlier than for an unlinked authenticated user.
    await expect(as('anon', null, 'SELECT public.my_context() AS ctx')).rejects.toThrow(
      'permission denied for function my_context',
    );
    const noSubCtx = await asUser<{ ctx: unknown }>(null, 'SELECT public.my_context() AS ctx');
    expect(noSubCtx[0]!.ctx).toBeNull();
    const unmappedCtx = await asUser<{ ctx: unknown }>(U.unmapped, 'SELECT public.my_context() AS ctx');
    expect(unmappedCtx[0]!.ctx).toBeNull();
  }, TIMEOUT);

  it('scopes a student to their own records (SELF scope)', async () => {
    expect(await ids(U.student1, 'SELECT student_id AS id FROM student')).toEqual([1]);
    expect(await ids(U.student1, 'SELECT enrolment_id AS id FROM student_programme_enrolment')).toEqual([1]);
    expect(await ids(U.student1, 'SELECT user_id AS id FROM student_user_account')).toEqual([1]);
    expect(await ids(U.student1, 'SELECT user_id AS id FROM user_account')).toEqual([1]);

    // A sibling student is invisible even though the row exists.
    expect(await ids(U.student1, 'SELECT student_id AS id FROM student WHERE student_id = 2')).toEqual([]);
    expect(await ids(U.student1, 'SELECT user_id AS id FROM user_account WHERE user_id = 2')).toEqual([]);
  }, TIMEOUT);

  it('scopes a registrar to their institution', async () => {
    // registrar1 holds REGISTRAR at institution 1, registrar2 at institution 2.
    expect(await ids(U.registrar1, 'SELECT student_id AS id FROM student')).toEqual([1, 2]);
    expect(await ids(U.registrar2, 'SELECT student_id AS id FROM student')).toEqual([3]);

    expect(await ids(U.registrar1, 'SELECT employee_id AS id FROM employee')).toEqual([1]);
    expect(await ids(U.registrar2, 'SELECT employee_id AS id FROM employee')).toEqual([2]);

    // The scope is per institution, not per user: registrar1 cannot see user 9.
    expect(await ids(U.registrar1, 'SELECT user_id AS id FROM user_account')).toEqual([2]);
    expect(await ids(U.registrar2, 'SELECT user_id AS id FROM user_account')).toEqual([9]);
  }, TIMEOUT);

  it('scopes faculty to their department', async () => {
    // facultyD1 holds FACULTY at department 1 (campus 1, institution 1).
    expect(await ids(U.facultyD1, 'SELECT student_id AS id FROM student')).toEqual([1]);
    // FACULTY carries no ADMISSION.* permission, and the enrolment rows are
    // gated on ADMISSION.ALL.READ, so they stay hidden from the faculty member.
    expect(await ids(U.facultyD1, 'SELECT enrolment_id AS id FROM student_programme_enrolment')).toEqual([]);

    // course_catalog_select uses can_department(CURRICULUM.ALL.READ, owning_department_id).
    expect(await ids(U.facultyD1, 'SELECT course_id AS id FROM course_catalog')).toEqual([9001]);
    expect(await ids(U.registrar1, 'SELECT course_id AS id FROM course_catalog')).toEqual([9001, 9002]);
    expect(await ids(U.registrar2, 'SELECT course_id AS id FROM course_catalog')).toEqual([9003]);
    expect(await ids(U.superAdmin, 'SELECT course_id AS id FROM course_catalog')).toEqual([9001, 9002, 9003]);

    // Department 2 belongs to the same campus/institution as department 1, so a
    // registrar at institution 1 sees both, while faculty of department 1 does not.
    expect(await ids(U.facultyD1, 'SELECT course_id AS id FROM course_catalog WHERE owning_department_id = 2')).toEqual([]);
  }, TIMEOUT);

  it('honours a user_permission_override DENY', async () => {
    // The override denies STUDENT.ALL.READ for user 7 at institution 1.
    const override = await db.query<{
      user_id: number;
      permission_code: string;
      permission_effect: string;
      scope_type: string;
      scope_entity_id: number;
    }>(`
      SELECT o.user_id, p.permission_code, o.permission_effect, o.scope_type, o.scope_entity_id
        FROM user_permission_override o
        JOIN permission p ON p.permission_id = o.permission_id
       WHERE o.user_id = 7 AND p.permission_code = 'STUDENT.ALL.READ'
    `);
    expect(override.rows).toEqual([
      {
        user_id: 7,
        permission_code: 'STUDENT.ALL.READ',
        permission_effect: 'DENY',
        scope_type: 'INSTITUTION',
        scope_entity_id: 1,
      },
    ]);

    // The denied permission really is part of the REGISTRAR role, so the DENY
    // takes it away rather than merely being redundant.
    const viaRole = await db.query<{ n: number }>(`
      SELECT count(*)::int AS n FROM role_permission rp
       WHERE rp.role_id = ${role('REGISTRAR')}
         AND rp.permission_id = (SELECT permission_id FROM permission WHERE permission_code = 'STUDENT.ALL.READ')
    `);
    expect(viaRole.rows[0]!.n).toBe(1);

    // DENY wins over the role grant: the effective permission is DENY ...
    const effective = await db.query<{ permission_effect: string }>(`
      SELECT permission_effect FROM v_effective_user_permission
       WHERE user_id = 7 AND permission_code = 'STUDENT.ALL.READ'
         AND scope_type = 'INSTITUTION' AND scope_entity_id = 1
    `);
    expect(effective.rows.map((r) => r.permission_effect)).toEqual(['DENY']);

    // ... and the row filter therefore hides every student of institution 1.
    expect(await ids(U.denied, 'SELECT student_id AS id FROM student')).toEqual([]);
    // The DENY is scoped to one permission: the enrolment rows are gated on
    // ADMISSION.ALL.READ, which the override does not touch.
    expect(await ids(U.denied, 'SELECT enrolment_id AS id FROM student_programme_enrolment')).toEqual([1, 2]);

    // Other permissions of the same role are untouched.
    expect(await ids(U.denied, 'SELECT employee_id AS id FROM employee')).toEqual([1]);
    expect(await ids(U.denied, 'SELECT user_id AS id FROM user_account')).toEqual([7]);
  }, TIMEOUT);

  it('treats a disabled account as having no access at all', async () => {
    expect(await ids(U.disabled, 'SELECT student_id AS id FROM student')).toEqual([]);
    expect(await ids(U.disabled, 'SELECT employee_id AS id FROM employee')).toEqual([]);
    expect(await ids(U.disabled, 'SELECT user_id AS id FROM user_account')).toEqual([]);
    expect(await ids(U.disabled, 'SELECT institution_id AS id FROM institution')).toEqual([]);

    // The account is linked to an auth user, but the account_status is DISABLED,
    // so sims_private.current_user_id() yields NULL and the context is empty.
    const ctx = await asUser<{ ctx: unknown }>(U.disabled, 'SELECT public.my_context() AS ctx');
    expect(ctx[0]!.ctx).toBeNull();

    // The role assignment is still there -- it is the account status that stops it.
    const assignments = await db.query<{ n: number }>(
      `SELECT count(*)::int AS n FROM user_role_assignment WHERE user_id = 5`,
    );
    expect(assignments.rows[0]!.n).toBe(1);
  }, TIMEOUT);

  it('lets a super admin read across every scope', async () => {
    expect(await ids(U.superAdmin, 'SELECT student_id AS id FROM student')).toEqual([1, 2, 3]);
    expect(await ids(U.superAdmin, 'SELECT enrolment_id AS id FROM student_programme_enrolment')).toEqual([1, 2, 3]);
    expect(await ids(U.superAdmin, 'SELECT employee_id AS id FROM employee')).toEqual([1, 2]);
    expect(await ids(U.superAdmin, 'SELECT institution_id AS id FROM institution')).toEqual([1, 2]);
    expect(await ids(U.superAdmin, 'SELECT campus_id AS id FROM campus')).toEqual([1, 2]);
    expect(await ids(U.superAdmin, 'SELECT course_id AS id FROM course_catalog')).toEqual([9001, 9002, 9003]);
    expect(await ids(U.superAdmin, 'SELECT user_id AS id FROM user_account')).toEqual([1, 2, 3, 4, 5, 7, 8, 9]);
    expect(await ids(U.superAdmin, 'SELECT user_id AS id FROM student_user_account')).toEqual([1]);
    expect(await ids(U.superAdmin, 'SELECT employee_id AS id FROM employee_user_account')).toEqual([1]);
  }, TIMEOUT);

  it('returns a my_context() with an exact key set and derived readable_modules', async () => {
    const expectedKeys = [
      'user_id',
      'username',
      'email',
      'student_id',
      'employee_id',
      'mfa_setup_required',
      'roles',
      'readable_modules',
      'permissions',
    ];

    const derive = async (userId: number) => {
      const { rows } = await db.query<{ permission_code: string; scope_type: string; permission_effect: string }>(
        `SELECT permission_code, scope_type, permission_effect
           FROM v_effective_user_permission WHERE user_id = $1`,
        [userId],
      );
      const allow = rows.filter((r) => r.permission_effect === 'ALLOW');
      return {
        modules: [
          ...new Set(
            allow
              .filter((r) => r.permission_code.endsWith('.READ'))
              .map((r) => r.permission_code.split('.')[0]!),
          ),
        ].sort(),
        permissions: [...new Set(allow.filter((r) => r.scope_type !== 'SELF').map((r) => r.permission_code))].sort(),
      };
    };

    for (const [sub, userId] of [
      [U.student1, 1],
      [U.registrar1, 2],
      [U.facultyD1, 3],
      [U.denied, 7],
      [U.superAdmin, 8],
    ] as const) {
      const rows = await asUser<{ ctx: Record<string, unknown> | null }>(
        sub,
        'SELECT public.my_context() AS ctx',
      );
      const ctx = rows[0]!.ctx!;

      // Exact key set -- no more, no less.
      expect(Object.keys(ctx).sort()).toEqual([...expectedKeys].sort());

      // readable_modules is derived from the ALLOW permissions ending in .READ,
      // taking the module part in front of the first dot.
      const want = await derive(userId);
      expect([...(ctx.readable_modules as string[])].sort()).toEqual(want.modules);
      // NOTE (known inconsistency, reported not fixed): `permissions` drops the
      // SELF-scoped grants while `readable_modules` keeps them, so student1
      // comes back with 10 readable modules but an empty permission list.
      expect([...(ctx.permissions as string[])].sort()).toEqual(want.permissions);
    }

    // The identity fields are the ones the caller is linked to.
    const student = await asUser<{ ctx: Record<string, unknown> }>(
      U.student1,
      'SELECT public.my_context() AS ctx',
    );
    expect(student[0]!.ctx.user_id).toBe(1);
    expect(student[0]!.ctx.username).toBe('student1');
    expect(student[0]!.ctx.student_id).toBe(1);
    expect(student[0]!.ctx.employee_id).toBeNull();
    expect(student[0]!.ctx.roles).toEqual([
      {
        role_code: 'STUDENT',
        role_name: 'Student',
        scope_type: 'SELF',
        institution_id: null,
        campus_id: null,
        department_id: null,
        programme_id: null,
      },
    ]);

    const registrar = await asUser<{ ctx: Record<string, unknown> }>(
      U.registrar1,
      'SELECT public.my_context() AS ctx',
    );
    expect(registrar[0]!.ctx.user_id).toBe(2);
    expect(registrar[0]!.ctx.student_id).toBeNull();
    expect(registrar[0]!.ctx.employee_id).toBeNull();
    expect(registrar[0]!.ctx.roles).toEqual([
      {
        role_code: 'REGISTRAR',
        role_name: 'Registrar',
        scope_type: 'INSTITUTION',
        institution_id: 1,
        campus_id: null,
        department_id: null,
        programme_id: null,
      },
    ]);

    // The faculty member is an employee, so the employee id is filled in.
    const faculty = await asUser<{ ctx: Record<string, unknown> }>(
      U.facultyD1,
      'SELECT public.my_context() AS ctx',
    );
    expect(faculty[0]!.ctx.employee_id).toBe(1);
    expect(faculty[0]!.ctx.student_id).toBeNull();
  }, TIMEOUT);
});

describe('function level authorisation', () => {
  it('authorises the SECURITY DEFINER RPCs inside the function', async () => {
    // --- audit_get: raises for everyone without a global AUDIT.ALL.READ ------
    await expect(asUser(U.registrar1, 'SELECT public.audit_get(1)')).rejects.toThrow(
      'Not authorised (AUDIT.ALL.READ)',
    );
    await expect(asUser(U.student1, 'SELECT public.audit_get(1)')).rejects.toThrow(
      'Not authorised (AUDIT.ALL.READ)',
    );
    await expect(asUser(U.facultyD1, 'SELECT public.audit_get(1)')).rejects.toThrow(
      'Not authorised (AUDIT.ALL.READ)',
    );
    const auditGet = await asUser<{ a: Record<string, unknown> | null }>(
      U.superAdmin,
      'SELECT public.audit_get(1) AS a',
    );
    expect(auditGet[0]!.a).toBeTruthy();
    expect(auditGet[0]!.a!.activity_audit_id).toBe(1);

    // --- audit_list / audit_modules: filtered to nothing, not an error -------
    expect(await asUser(U.registrar1, 'SELECT * FROM public.audit_list()')).toEqual([]);
    expect(await asUser(U.registrar1, 'SELECT * FROM public.audit_modules()')).toEqual([]);
    expect(await asUser(U.student1, 'SELECT * FROM public.audit_list()')).toEqual([]);

    const auditList = await asUser<{ module_code: string; total_count: number }>(
      U.superAdmin,
      'SELECT module_code, total_count FROM public.audit_list(p_limit => 200)',
    );
    expect(auditList.length).toBeGreaterThan(0);
    expect(auditList[0]!.total_count).toBeGreaterThan(0);

    const auditModules = await asUser<{ module_code: string }>(
      U.superAdmin,
      'SELECT module_code FROM public.audit_modules()',
    );
    expect(auditModules.map((m) => m.module_code)).toContain('IAM');

    // --- ref_schema / ref_rows: IAM.ALL.CONFIGURE is required ---------------
    await expect(asUser(U.registrar1, "SELECT public.ref_schema('gender')")).rejects.toThrow(
      'Not authorised (IAM.ALL.CONFIGURE)',
    );
    await expect(asUser(U.registrar1, "SELECT public.ref_rows('gender')")).rejects.toThrow(
      'Not authorised (IAM.ALL.CONFIGURE)',
    );
    await expect(asUser(U.student1, "SELECT public.ref_rows('gender')")).rejects.toThrow(
      'Not authorised (IAM.ALL.CONFIGURE)',
    );

    const refSchema = await asUser<{ s: Record<string, unknown> }>(
      U.superAdmin,
      "SELECT public.ref_schema('gender') AS s",
    );
    expect(refSchema[0]!.s.table).toBe('gender');
    expect(refSchema[0]!.s.pk).toBe('gender_id');
    expect((refSchema[0]!.s.columns as { name: string }[]).map((c) => c.name)).toEqual([
      'gender_code',
      'gender_name',
      'is_active',
    ]);

    const refRows = await asUser<{ r: unknown }>(U.superAdmin, "SELECT public.ref_rows('gender') AS r");
    expect(Array.isArray(refRows[0]!.r)).toBe(true);
    expect((refRows[0]!.r as unknown[]).length).toBeGreaterThan(0);

    // --- ref_list: filtered to nothing for everybody but a global admin ------
    expect(await asUser(U.registrar1, 'SELECT * FROM public.ref_list()')).toEqual([]);
    expect(await asUser(U.facultyD1, 'SELECT * FROM public.ref_list()')).toEqual([]);
    const refList = await asUser<{ tbl: string }>(U.superAdmin, 'SELECT tbl FROM public.ref_list()');
    expect(refList.map((r) => r.tbl)).toContain('gender');
    expect(refList.length).toBeGreaterThan(0);

    // --- emp_sensitive_reveal: authorisation, then the purpose check ---------
    await expect(
      asUser(U.registrar1, "SELECT public.emp_sensitive_reveal('PAN', 1, 'Payroll verification for FY26')"),
    ).rejects.toThrow('Not authorised (EMPLOYEE.PAN.EXPORT) or unknown record');
    await expect(
      asUser(U.student1, "SELECT public.emp_sensitive_reveal('PAN', 1, 'Payroll verification for FY26')"),
    ).rejects.toThrow('Not authorised (EMPLOYEE.PAN.EXPORT) or unknown record');

    // A global admin still has to state a purpose of 5..500 characters.
    await expect(
      asUser(U.superAdmin, "SELECT public.emp_sensitive_reveal('PAN', 1, 'abc')"),
    ).rejects.toThrow('State the purpose of viewing the full number (5 to 500 characters)');
    await expect(
      asUser(U.superAdmin, "SELECT public.emp_sensitive_reveal('PAN', 1, NULL)"),
    ).rejects.toThrow('State the purpose of viewing the full number (5 to 500 characters)');

    const revealed = await asUser<{ v: string }>(
      U.superAdmin,
      "SELECT public.emp_sensitive_reveal('PAN', 1, 'Payroll verification for FY26') AS v",
    );
    expect(revealed[0]!.v).toBe('ABCDE1234F');

    // The owner of the record may reveal their own number without a purpose.
    const owner = await asUser<{ v: string }>(
      U.facultyD1,
      "SELECT public.emp_sensitive_reveal('PAN', 1, NULL) AS v",
    );
    expect(owner[0]!.v).toBe('ABCDE1234F');
  }, TIMEOUT);

  it('writes a sensitive reveal to the audit table', async () => {
    const purpose = 'Quarterly audit sample for FY26';
    const ownerPurpose = 'Owner self service check';

    const revealed = await asUser<{ v: string }>(
      U.superAdmin,
      `SELECT public.emp_sensitive_reveal('PAN', 1, '${purpose}') AS v`,
    );
    expect(revealed[0]!.v).toBe('ABCDE1234F');

    const audit = await asUser<{
      user_id: number;
      employee_id: number;
      action_code: string;
      entity_type: string;
      entity_id: number;
      access_purpose: string;
    }>(
      U.superAdmin,
      `SELECT user_id, employee_id, action_code, entity_type, entity_id, access_purpose
         FROM employee_sensitive_access_audit WHERE access_purpose = '${purpose}'`,
    );
    expect(audit).toHaveLength(1);
    expect(audit[0]).toMatchObject({
      user_id: 8,
      employee_id: 1,
      action_code: 'DECRYPT',
      entity_type: 'PAN',
      entity_id: 1,
      access_purpose: purpose,
    });

    // The audit trail itself is protected: a registrar has no
    // EMPLOYEE.EMPLOYEE_DOCUMENT.READ, so the row is invisible to them.
    expect(
      await asUser(U.registrar1, 'SELECT employee_sensitive_access_audit_id FROM employee_sensitive_access_audit'),
    ).toEqual([]);
    expect(
      await asUser(U.facultyD1, 'SELECT employee_sensitive_access_audit_id FROM employee_sensitive_access_audit'),
    ).toEqual([]);

    // The owner reveal is audited as well, with the acting user recorded.
    const ownerRevealed = await asUser<{ v: string }>(
      U.facultyD1,
      `SELECT public.emp_sensitive_reveal('PAN', 1, '${ownerPurpose}') AS v`,
    );
    expect(ownerRevealed[0]!.v).toBe('ABCDE1234F');

    const ownerAudit = await asUser<{
      user_id: number;
      employee_id: number;
      action_code: string;
      entity_type: string;
      entity_id: number;
      access_purpose: string;
    }>(
      U.superAdmin,
      `SELECT user_id, employee_id, action_code, entity_type, entity_id, access_purpose
         FROM employee_sensitive_access_audit WHERE access_purpose = '${ownerPurpose}'`,
    );
    expect(ownerAudit).toHaveLength(1);
    expect(ownerAudit[0]).toMatchObject({
      user_id: 3,
      employee_id: 1,
      action_code: 'DECRYPT',
      entity_type: 'PAN',
      entity_id: 1,
      access_purpose: ownerPurpose,
    });
  }, TIMEOUT);
});

describe('column level privileges', () => {
  it('grants `authenticated` SELECT per column, not per relation', async () => {
    // The live project does not grant SELECT on the public tables as a
    // relation.  It grants SELECT on every column instead, so a read that
    // names a column is allowed while a read that asks for every column is
    // refused on the tables that hide one.
    const { rows } = await db.query<{
      columns_with_grant: number;
      tables_with_grant: number;
      other_grantees: number;
    }>(`
      SELECT
        (SELECT count(*)::int
           FROM pg_class c
           JOIN pg_namespace n ON n.oid = c.relnamespace
           JOIN pg_attribute a ON a.attrelid = c.oid
          WHERE n.nspname = 'public' AND c.relkind = 'r'
            AND a.attacl::text LIKE '%authenticated=r%') AS columns_with_grant,
        (SELECT count(DISTINCT c.oid)::int
           FROM pg_class c
           JOIN pg_namespace n ON n.oid = c.relnamespace
           JOIN pg_attribute a ON a.attrelid = c.oid
          WHERE n.nspname = 'public' AND c.relkind = 'r'
            AND a.attacl::text LIKE '%authenticated=r%') AS tables_with_grant,
        (SELECT count(*)::int
           FROM pg_class c
           JOIN pg_namespace n ON n.oid = c.relnamespace
           JOIN pg_attribute a ON a.attrelid = c.oid
          WHERE n.nspname = 'public' AND c.relkind = 'r'
            AND a.attacl IS NOT NULL
            AND a.attacl::text NOT LIKE '%authenticated=r%') AS other_grantees
    `);

    // 2086 columns across 212 of the 213 public tables.  `counselling_session`
    // is the one table the authenticated role cannot read at all.
    expect(rows[0]!.columns_with_grant).toBe(2086);
    expect(rows[0]!.tables_with_grant).toBe(212);
    // No other role receives a column grant, and `anon` receives none.
    expect(rows[0]!.other_grantees).toBe(0);

    // The relation level privilege really is absent.
    const relation = await db.query<{ rel: string; sel: boolean }>(
      `SELECT c.relname AS rel, has_table_privilege('authenticated', c.oid, 'SELECT') AS sel
         FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind = 'r' AND c.relname = 'student'`,
    );
    expect(relation.rows[0]!.sel).toBe(false);

    // The column level privilege is present.
    const column = await db.query<{ sel: boolean }>(
      `SELECT has_column_privilege('authenticated', 'public.student'::regclass, 'student_id', 'SELECT') AS sel`,
    );
    expect(column.rows[0]!.sel).toBe(true);
  }, TIMEOUT);

  it('hides the sensitive columns from `authenticated`', async () => {
    // The password hash and the encrypted PII are the reason the project uses
    // column grants at all: they must not be readable, not even by a global
    // administrator.
    for (const [table, column] of [
      ['user_account', 'password_hash'],
      ['password_history', 'password_hash'],
      ['employee_pan', 'pan_number_ciphertext'],
      ['employee_aadhaar', 'aadhaar_number_ciphertext'],
      ['employee_bank_account', 'account_number_ciphertext'],
    ]) {
      const { rows } = await db.query<{ sel: boolean }>(
        `SELECT has_column_privilege('authenticated', 'public.${table}'::regclass, '${column}', 'SELECT') AS sel`,
      );
      expect(rows[0]!.sel, `${table}.${column}`).toBe(false);
    }

    // `counselling_session` is closed completely.
    const { rows } = await db.query<{ n: number }>(
      `SELECT count(*)::int AS n
         FROM pg_class c
         JOIN pg_namespace n ON n.oid = c.relnamespace
         JOIN pg_attribute a ON a.attrelid = c.oid
        WHERE n.nspname = 'public' AND c.relname = 'counselling_session'
          AND a.attacl::text LIKE '%authenticated=r%'`,
    );
    expect(rows[0]!.n).toBe(0);
  }, TIMEOUT);

  it('allows a named column and refuses `SELECT *` on a table with a hidden column', async () => {
    // A named column is allowed ...
    const named = await asUser<{ username: string }>(
      U.registrar1,
      'SELECT username FROM user_account ORDER BY 1',
    );
    expect(named.map((r) => r.username)).toEqual(['registrar1']);

    // ... while `SELECT *` is refused, because it asks for the hidden
    // `password_hash` as well.
    await expect(asUser(U.registrar1, 'SELECT * FROM user_account')).rejects.toThrow(
      'permission denied for table user_account',
    );

    // On a table where every column is granted, `SELECT *` works.
    const star = await asUser<{ student_number: string }>(
      U.registrar1,
      'SELECT * FROM student ORDER BY 1',
    );
    expect(star.map((r) => r.student_number)).toEqual(['S1', 'S1B']);
  }, TIMEOUT);

  it('gives `anon` no table privilege at all', async () => {
    const { rows } = await db.query<{ n: number }>(
      `SELECT count(*)::int AS n
         FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind = 'r'
          AND has_table_privilege('anon', c.oid, 'SELECT')`,
    );
    expect(rows[0]!.n).toBe(0);
  }, TIMEOUT);
});
