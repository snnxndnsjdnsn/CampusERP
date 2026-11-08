import { beforeAll, describe, expect, it } from 'vitest';
import { asUser, createWorld, db, U } from './world';

/**
 * The admin editing surface.
 *
 * Everything runs against the embedded PGlite world built by `tests/db/world.ts`
 * (all migrations + the org/people/role fixture).  The live Supabase database is
 * never contacted.
 *
 * The fixture users are the ones `tests/db/rls.test.ts` describes:
 *
 *   student1   user 1  STUDENT role, SELF scope
 *   registrar1 user 2  REGISTRAR role, INSTITUTION 1
 *   facultyD1  user 3  FACULTY role, DEPARTMENT 1
 *   finance1   user 4  FINANCE_OFFICER role, INSTITUTION 1
 *   disabled   user 5  REGISTRAR role, INSTITUTION 1, account DISABLED
 *   unmapped   -      auth user without a user_account row
 *   superAdmin user 8  SUPER_ADMIN role, GLOBAL scope
 *   registrar2 user 9  REGISTRAR role, INSTITUTION 2
 *
 * Org topology: institution 1/2; campus 1 -> inst 1, campus 2 -> inst 2;
 * department 1,2 -> campus 1 and department 3 -> campus 2; programme 1/2/3 ->
 * department 1/2/3; student 1/2/3 -> programme 1/2/3; employee 1 -> inst 1 and
 * employee 2 -> inst 2.
 *
 * Two more users are created by this file, because the catalogue carries two
 * scope kinds that no other fixture exercises:
 *
 *   hrAdmin1   user 10  HR_ADMIN role, INSTITUTION 1
 *   sysAdmin1  user 11  REGISTRAR role, INSTITUTION 1, plus an explicit
 *                      INSTITUTION.ALL.UPDATE grant for institution 1
 */

const TIMEOUT = 300_000;

/** The 127 tables the catalogue offers, in the order the database returns them. */
const ALL_TABLES = [
  'academic_term',
  'academic_year',
  'activity_evidence_requirement',
  'activity_type',
  'admission_category',
  'announcement_type',
  'approval_status',
  'assessment_component',
  'assessment_event',
  'attendance_status',
  'award_category',
  'awarding_body',
  'awarding_body_type',
  'blood_group',
  'building',
  'campus',
  'caste',
  'certificate_request',
  'certificate_type',
  'class_batch',
  'class_section',
  'class_session',
  'cocurricular_category',
  'conference_activity_indexing',
  'conference_contribution_type',
  'conference_event',
  'confidentiality_level',
  'country',
  'course_catalog',
  'course_category',
  'course_offering',
  'course_offering_section',
  'course_offering_section_student',
  'course_prerequisite',
  'curriculum_course',
  'curriculum_scheme',
  'department',
  'designation',
  'document_type',
  'education_institution',
  'education_institution_type',
  'employee',
  'employee_aadhaar',
  'employee_address',
  'employee_assignment',
  'employee_bank_account',
  'employee_competency',
  'employee_document',
  'employee_document_access_rule',
  'employee_document_category',
  'employee_pan',
  'employee_previous_employment',
  'employee_qualification',
  'employment_source',
  'enrolment_status_history',
  'event_mode',
  'evidence_document_tag',
  'evidence_tag',
  'evidence_type',
  'external_agency',
  'external_organization',
  'external_organization_type',
  'extracurricular_category',
  'faculty_course_assignment',
  'feedback_choice',
  'feedback_cycle',
  'feedback_question',
  'feedback_question_category',
  'feedback_questionnaire',
  'feedback_questionnaire_item',
  'funding_agency',
  'funding_type',
  'gender',
  'grade_rule',
  'grade_scale',
  'grievance_category',
  'indexing_agency',
  'industry_sector',
  'journal',
  'journal_metric',
  'journal_publication_indexing',
  'journal_type',
  'membership_type',
  'metric_type',
  'organization_type',
  'organizer',
  'participation_level',
  'previous_organization',
  'previous_organization_type',
  'professional_contribution_type',
  'programme',
  'programme_specialization',
  'programme_term_offering',
  'publication_type',
  'publisher',
  'qualification_level',
  'religion',
  'research_project_financial_utilization',
  'research_status',
  'research_supervision',
  'role_type',
  'room',
  'semester',
  'social_category',
  'staff_category',
  'staff_type',
  'state',
  'student',
  'student_activity_evidence_requirement',
  'student_activity_type',
  'student_address',
  'student_course_registration',
  'student_document',
  'student_entrance_exam',
  'student_exit',
  'student_parent_guardian',
  'student_previous_education',
  'student_programme_enrolment',
  'student_residence',
  'student_term_registration',
  'study_mode',
  'sub_caste',
  'time_slot',
  'timetable_session',
  'training_program_type',
  'university',
  'verification_status',
];

/** What a REGISTRAR may write to. */
const REGISTRAR_TABLES = [
  'assessment_component',
  'assessment_event',
  'certificate_request',
  'class_batch',
  'class_section',
  'class_session',
  'course_catalog',
  'course_offering',
  'course_offering_section',
  'course_offering_section_student',
  'course_prerequisite',
  'curriculum_course',
  'curriculum_scheme',
  'faculty_course_assignment',
  'programme_term_offering',
  'student',
  'student_address',
  'student_course_registration',
  'student_document',
  'student_entrance_exam',
  'student_exit',
  'student_parent_guardian',
  'student_previous_education',
  'student_residence',
  'student_term_registration',
  'time_slot',
  'timetable_session',
];

/** What a FACULTY member may write to. */
const FACULTY_TABLES = [
  'assessment_component',
  'assessment_event',
  'class_batch',
  'class_section',
  'class_session',
  'conference_activity_indexing',
  'course_catalog',
  'course_offering',
  'course_offering_section',
  'course_offering_section_student',
  'course_prerequisite',
  'curriculum_course',
  'curriculum_scheme',
  'evidence_document_tag',
  'faculty_course_assignment',
  'journal_publication_indexing',
  'programme_term_offering',
  'research_project_financial_utilization',
  'research_supervision',
  'student',
  'student_address',
  'student_course_registration',
  'student_entrance_exam',
  'student_parent_guardian',
  'student_previous_education',
  'student_residence',
  'student_term_registration',
  'time_slot',
  'timetable_session',
];

/** The two extra users this file needs. */
const HR_ADMIN = '00000000-0000-0000-0000-000000000010';
const SYS_ADMIN = '00000000-0000-0000-0000-000000000011';

async function tableList(sub: string | null): Promise<string[]> {
  const rows = await asUser<{ tbl: string }>(sub, 'SELECT tbl FROM public.admin_table_list() ORDER BY tbl');
  return rows.map((r) => r.tbl);
}

beforeAll(async () => {
  await createWorld();

  // ---------------------------------------------------------------------------
  // Fixtures the world does not ship.  The world already has institution 1/2,
  // campus 1/2, department 1/2/3, programme 1/2/3, student 1/2/3, employee 1/2
  // and the programme enrolments that place them.
  // ---------------------------------------------------------------------------
  await db.exec(`
    INSERT INTO course_category (course_category_id, category_code, category_name)
      VALUES (9001, 'TSTCAT', 'Test Category');
    INSERT INTO course_catalog (course_id, owning_department_id, course_category_id, course_code, course_title, course_type, credits)
      VALUES (9001, 1, 9001, 'TST-D1', 'Test Course Dept 1', 'THEORY', 4),
             (9002, 2, 9001, 'TST-D2', 'Test Course Dept 2', 'THEORY', 4),
             (9003, 3, 9001, 'TST-D3', 'Test Course Dept 3', 'THEORY', 4);
    INSERT INTO academic_year (academic_year_id, year_code, start_date, end_date, status)
      VALUES (1, '2024-25', '2024-08-01', '2025-07-31', 'ACTIVE');
    INSERT INTO academic_term (academic_term_id, academic_year_id, term_code, term_name, term_type, start_date, end_date, status)
      VALUES (9001, 1, 'T1', 'Term 1', 'ODD', '2024-08-01', '2024-12-31', 'ACTIVE');
    INSERT INTO semester (semester_id, semester_number, semester_name)
      VALUES (1, 1, 'Semester 1');
    INSERT INTO curriculum_scheme (curriculum_scheme_id, programme_id, scheme_code, scheme_name, regulation_year, effective_from, status)
      VALUES (1, 1, 'SCH1', 'Scheme 1', 2024, '2024-08-01', 'ACTIVE');
    INSERT INTO curriculum_course (curriculum_course_id, curriculum_scheme_id, semester_id, course_id, course_category_id, is_mandatory)
      VALUES (9001, 1, 1, 9001, 9001, true);
    INSERT INTO building (building_id, campus_id, building_code, building_name)
      VALUES (9001, 1, 'B1', 'Building 1');
    INSERT INTO time_slot (time_slot_id, campus_id, slot_code, start_time, end_time, is_break, is_active)
      VALUES (9001, 1, 'S1', '09:00', '09:55', false, true);
    INSERT INTO room (room_id, building_id, room_code, room_name, room_type, capacity, is_active)
      VALUES (9001, 9001, 'R1', 'Room 1', 'CLASSROOM', 40, true);
    INSERT INTO programme_term_offering (programme_term_offering_id, academic_term_id, programme_id, curriculum_scheme_id, semester_id, status)
      VALUES (9001, 9001, 1, 1, 1, 'PLANNED');
    INSERT INTO course_offering (course_offering_id, programme_term_offering_id, course_id, offering_code, status)
      VALUES (9001, 9001, 9001, 'OFF1', 'PLANNED');
    INSERT INTO class_section (class_section_id, programme_term_offering_id, section_code, section_name, capacity, is_active)
      VALUES (9001, 9001, 'SEC1', 'Section 1', 60, true);

    -- The world already refers to academic_year 1, semester 1 and
    -- curriculum_scheme 1, so those three keep that id and their identity
    -- sequences have to move past it.  Every other fixture uses a high id, which
    -- the sequence will never reach.
    SELECT setval(pg_get_serial_sequence('public.academic_year', 'academic_year_id'), (SELECT max(academic_year_id) FROM public.academic_year));
    SELECT setval(pg_get_serial_sequence('public.semester', 'semester_id'), (SELECT max(semester_id) FROM public.semester));
    SELECT setval(pg_get_serial_sequence('public.curriculum_scheme', 'curriculum_scheme_id'), (SELECT max(curriculum_scheme_id) FROM public.curriculum_scheme));
  `);

  // ---------------------------------------------------------------------------
  // Two users with a scope of their own, for the two scope kinds that the
  // shared world does not exercise: `employee` and `institution`.
  // ---------------------------------------------------------------------------
  await db.exec(`
    INSERT INTO user_account (user_id, username, password_hash, account_status)
      VALUES (10, 'hradmin1', 'x', 'ACTIVE'), (11, 'sysadmin1', 'x', 'ACTIVE');
    INSERT INTO user_role_assignment (user_id, role_id, scope_type, institution_id)
      VALUES (10, (select role_id from role where role_code = 'HR_ADMIN'), 'INSTITUTION', 1),
             (11, (select role_id from role where role_code = 'REGISTRAR'), 'INSTITUTION', 1);
    -- No seeded role below the global one carries INSTITUTION.ALL.UPDATE, so
    -- the institution scope is exercised with an explicit grant.
    INSERT INTO user_permission_override (user_id, permission_id, permission_effect, scope_type, scope_entity_id, justification)
      VALUES (11, (select permission_id from permission where permission_code = 'INSTITUTION.ALL.UPDATE'),
              'ALLOW', 'INSTITUTION', 1, 'test institution scope');
    INSERT INTO auth.users (id) VALUES ('${HR_ADMIN}'), ('${SYS_ADMIN}');
    SELECT sims_private.link_auth_user('${HR_ADMIN}', 10, 'test');
    SELECT sims_private.link_auth_user('${SYS_ADMIN}', 11, 'test');
  `);
}, TIMEOUT);

describe('admin editing surface', () => {
  it('offers only the tables the caller may write to', async () => {
    // A global administrator gets all of them.
    expect(await tableList(U.superAdmin)).toEqual(ALL_TABLES);

    // A scoped user gets the tables their role carries a write permission for.
    expect(await tableList(U.registrar1)).toEqual(REGISTRAR_TABLES);
    expect(await tableList(U.registrar2)).toEqual(REGISTRAR_TABLES);
    expect(await tableList(U.facultyD1)).toEqual(FACULTY_TABLES);

    // A student holds the codes in SELF scope only, and a write is never
    // authorised by SELF scope, so a student is offered nothing.
    expect(await tableList(U.student1)).toEqual([]);

    // A role without any of the module permissions, a disabled account and an
    // auth user that is not linked to an account are all offered nothing.
    expect(await tableList(U.finance1)).toEqual([]);
    expect(await tableList(U.disabled)).toEqual([]);
    expect(await tableList(U.unmapped)).toEqual([]);
  }, TIMEOUT);

  it('tells the panel which screens a table belongs to', async () => {
    const rows = await asUser<{ tbl: string; module_codes: string[] }>(
      U.superAdmin,
      'SELECT tbl, module_codes FROM public.admin_table_list() ORDER BY tbl',
    );
    const byTable = new Map(rows.map((r) => [r.tbl, r.module_codes ?? []]));

    // The Employees screen is the headline case: the employee master and the
    // HR tables around it all belong to the EMPLOYEE module.
    expect(byTable.get('employee')).toEqual(['EMPLOYEE']);
    expect(byTable.get('employee_qualification')).toEqual(['EMPLOYEE']);
    expect(byTable.get('employee_competency')).toEqual(['EMPLOYEE']);

    // A table that is edited on more than one screen says so.
    expect(byTable.get('course_offering')).toEqual(['TIMETABLE', 'REGISTRATION']);
    expect(byTable.get('room')).toEqual(['INSTITUTION', 'TIMETABLE']);

    // Every table belongs to at least one screen.
    for (const row of rows) {
      expect((row.module_codes ?? []).length).toBeGreaterThan(0);
    }
  }, TIMEOUT);

  it('describes one table and refuses a table the caller may not write to', async () => {
    const rows = await asUser<{ schema: { table: string; pk: string; pk_cols: string[]; columns: { name: string }[] } }>(
      U.superAdmin,
      `SELECT public.admin_table_schema('academic_year') AS schema`,
    );
    expect(rows[0]!.schema.table).toBe('academic_year');
    expect(rows[0]!.schema.pk).toBe('academic_year_id');
    expect(rows[0]!.schema.pk_cols).toEqual(['academic_year_id']);
    expect(rows[0]!.schema.columns.map((c) => c.name)).toEqual(['year_code', 'start_date', 'end_date', 'status']);

    // The status column carries the choices of its CHECK constraint.
    const status = rows[0]!.schema.columns.find((c) => c.name === 'status');
    expect(status).toBeDefined();

    // A table with a composite key keeps its key columns in the form, because a
    // new row has to be given its key.
    const composite = await asUser<{ schema: { pk: string | null; pk_cols: string[]; columns: { name: string }[] } }>(
      U.superAdmin,
      `SELECT public.admin_table_schema('course_prerequisite') AS schema`,
    );
    expect(composite[0]!.schema.pk).toBeNull();
    expect(composite[0]!.schema.pk_cols).toEqual(['course_id', 'prerequisite_course_id']);
    expect(composite[0]!.schema.columns.map((c) => c.name)).toEqual([
      'course_id',
      'prerequisite_course_id',
      'minimum_grade',
    ]);

    // A registrar holds no ACADEMIC_CALENDAR.ALL.CONFIGURE permission.
    await expect(asUser(U.registrar1, `SELECT public.admin_table_schema('academic_year')`)).rejects.toThrow(
      'Not authorised',
    );

    // An unknown table is a bad request, not a permission problem.
    await expect(asUser(U.superAdmin, `SELECT public.admin_table_schema('nope')`)).rejects.toThrow('Unknown table');
  }, TIMEOUT);

  it('creates, updates and deletes a row', async () => {
    const before = await db.query<{ n: number }>('SELECT count(*)::int AS n FROM public.academic_year');
    expect(before.rows[0]!.n).toBe(1);

    const created = await asUser<{ id: number }>(
      U.superAdmin,
      `SELECT public.admin_table_save('academic_year', NULL,
         '{"year_code":"2026-27","start_date":"2026-08-01","end_date":"2027-07-31"}'::jsonb) AS id`,
    );
    const id = created[0]!.id;
    expect(id).toBeGreaterThan(0);

    const after = await db.query<{ n: number }>('SELECT count(*)::int AS n FROM public.academic_year');
    expect(after.rows[0]!.n).toBe(2);

    // An update only touches the columns it carries.
    await asUser(
      U.superAdmin,
      `SELECT public.admin_table_save('academic_year', '${id}'::jsonb, '{"status":"ACTIVE"}'::jsonb)`,
    );
    const row = await db.query<{ year_code: string; status: string; start_date: Date }>(
      'SELECT year_code, status, start_date FROM public.academic_year WHERE academic_year_id = $1',
      [id],
    );
    expect(row.rows[0]!.year_code).toBe('2026-27');
    expect(row.rows[0]!.status).toBe('ACTIVE');
    expect(row.rows[0]!.start_date.toISOString().slice(0, 10)).toBe('2026-08-01');

    await asUser(U.superAdmin, `SELECT public.admin_table_delete('academic_year', '${id}'::jsonb)`);
    const final = await db.query<{ n: number }>('SELECT count(*)::int AS n FROM public.academic_year');
    expect(final.rows[0]!.n).toBe(1);
  }, TIMEOUT);

  it('writes a row whose key the database generates', async () => {
    // `gender` has an identity column, so the key is not part of the payload.
    const created = await asUser<{ id: number }>(
      U.superAdmin,
      `SELECT public.admin_table_save('gender', NULL,
         '{"gender_code":"TST","gender_name":"Test Gender"}'::jsonb) AS id`,
    );
    const id = created[0]!.id;
    expect(id).toBeGreaterThan(0);

    const row = await db.query<{ gender_code: string }>(
      'SELECT gender_code FROM public.gender WHERE gender_id = $1',
      [id],
    );
    expect(row.rows[0]!.gender_code).toBe('TST');

    await asUser(U.superAdmin, `SELECT public.admin_table_delete('gender', '${id}'::jsonb)`);
  }, TIMEOUT);

  it('addresses a row with a composite key', async () => {
    // course_prerequisite is keyed by (course_id, prerequisite_course_id).
    await asUser(
      U.superAdmin,
      `SELECT public.admin_table_save('course_prerequisite', NULL,
         '{"course_id":9001,"prerequisite_course_id":9002,"minimum_grade":"B"}'::jsonb)`,
    );

    const row = await db.query<{ minimum_grade: string }>(
      'SELECT minimum_grade FROM public.course_prerequisite WHERE course_id = 9001 AND prerequisite_course_id = 9002',
    );
    expect(row.rows[0]!.minimum_grade).toBe('B');

    // An update is addressed by the whole key.
    await asUser(
      U.superAdmin,
      `SELECT public.admin_table_save('course_prerequisite',
         '{"course_id":9001,"prerequisite_course_id":9002}'::jsonb,
         '{"minimum_grade":"A"}'::jsonb)`,
    );
    const updated = await db.query<{ minimum_grade: string }>(
      'SELECT minimum_grade FROM public.course_prerequisite WHERE course_id = 9001 AND prerequisite_course_id = 9002',
    );
    expect(updated.rows[0]!.minimum_grade).toBe('A');

    // Half a key is not a row.
    await expect(
      asUser(
        U.superAdmin,
        `SELECT public.admin_table_save('course_prerequisite',
           '{"course_id":9001}'::jsonb, '{"minimum_grade":"C"}'::jsonb)`,
      ),
    ).rejects.toThrow('Unknown row');

    await asUser(
      U.superAdmin,
      `SELECT public.admin_table_delete('course_prerequisite',
         '{"course_id":9001,"prerequisite_course_id":9002}'::jsonb)`,
    );
    const gone = await db.query<{ n: number }>(
      'SELECT count(*)::int AS n FROM public.course_prerequisite WHERE course_id = 9001',
    );
    expect(gone.rows[0]!.n).toBe(0);
  }, TIMEOUT);

  it('records every change exactly once in the audit trail', async () => {
    const created = await asUser<{ id: number }>(
      U.superAdmin,
      `SELECT public.admin_table_save('time_slot', NULL,
         '{"campus_id":1,"slot_code":"TST-9","start_time":"15:00","end_time":"15:55","is_break":false,"is_active":true}'::jsonb) AS id`,
    );
    const id = created[0]!.id;

    await asUser(
      U.superAdmin,
      `SELECT public.admin_table_save('time_slot', '${id}'::jsonb, '{"slot_code":"TST-10"}'::jsonb)`,
    );
    await asUser(U.superAdmin, `SELECT public.admin_table_delete('time_slot', '${id}'::jsonb)`);

    const audit = await db.query<{ action_code: string; module_code: string }>(
      `SELECT action_code, module_code FROM public.activity_audit
        WHERE entity_name = 'time_slot' AND entity_id = $1 ORDER BY activity_audit_id`,
      [String(id)],
    );
    expect(audit.rows.map((r) => r.action_code)).toEqual(['INSERT', 'UPDATE', 'DELETE']);
    expect(audit.rows.every((r) => r.module_code === 'ACADEMIC_CALENDAR')).toBe(true);
  }, TIMEOUT);

  it('audits a table whose own write path already audits', async () => {
    // `gender` is a reference table: `ref_save` records the change itself, so
    // the generic write function has to record it too - but only once.
    const created = await asUser<{ id: number }>(
      U.superAdmin,
      `SELECT public.admin_table_save('gender', NULL,
         '{"gender_code":"TST2","gender_name":"Test Gender 2"}'::jsonb) AS id`,
    );
    const id = created[0]!.id;
    await asUser(U.superAdmin, `SELECT public.admin_table_delete('gender', '${id}'::jsonb)`);

    const audit = await db.query<{ action_code: string; module_code: string }>(
      `SELECT action_code, module_code FROM public.activity_audit
        WHERE entity_name = 'gender' AND entity_id = $1 ORDER BY activity_audit_id`,
      [String(id)],
    );
    expect(audit.rows.map((r) => r.action_code)).toEqual(['INSERT', 'DELETE']);
    // The reference tables are audited under the platform module, the same one
    // `ref_save` uses.
    expect(audit.rows.every((r) => r.module_code === 'PLATFORM')).toBe(true);
  }, TIMEOUT);

  it('gives every writable table exactly one audit path', async () => {
    // A table either carries an `audit_row` trigger, or its own write path
    // audits it and the catalogue says so.  Never both, never neither.
    const rows = await db.query<{ tbl: string; audit_mode: string; triggers: number }>(
      `SELECT d.tbl,
              d.audit_mode,
              (SELECT count(*)::int
                 FROM pg_trigger t
                 JOIN pg_class c ON c.oid = t.tgrelid
                 JOIN pg_proc p ON p.oid = t.tgfoid
                WHERE c.relname = d.tbl AND p.proname = 'audit_row' AND NOT t.tgisinternal) AS triggers
         FROM sims_private.admin_table_def(NULL) d
        ORDER BY d.tbl`,
    );
    expect(rows.rows.length).toBe(127);

    for (const row of rows.rows) {
      if (row.audit_mode === 'TRIGGER') {
        expect(row.triggers, `${row.tbl} should have an audit trigger`).toBe(1);
      } else {
        expect(row.audit_mode, `${row.tbl} should have a known audit mode`).toBe('MANUAL');
        expect(row.triggers, `${row.tbl} should not have an audit trigger`).toBe(0);
      }
    }
  }, TIMEOUT);

  it('keeps a scoped caller inside its own scope', async () => {
    // facultyD1 is in department 1.  Student 1 is in programme 1 -> department 1,
    // student 3 is in programme 3 -> department 3.
    await expect(
      asUser(U.facultyD1, `SELECT public.admin_table_save('student', '1'::jsonb, '{"notes":"mine"}'::jsonb)`),
    ).resolves.toBeTruthy();

    await expect(
      asUser(U.facultyD1, `SELECT public.admin_table_save('student', '3'::jsonb, '{"notes":"theirs"}'::jsonb)`),
    ).rejects.toThrow('Not authorised');

    // The same for a course: department 1 may write its own, not another one's.
    await expect(
      asUser(U.facultyD1, `SELECT public.admin_table_save('course_catalog', '9001'::jsonb, '{"course_title":"Mine"}'::jsonb)`),
    ).resolves.toBeTruthy();
    await expect(
      asUser(U.facultyD1, `SELECT public.admin_table_save('course_catalog', '9003'::jsonb, '{"course_title":"Theirs"}'::jsonb)`),
    ).rejects.toThrow('Not authorised');
  }, TIMEOUT);

  it('keeps an employee scoped caller inside its own institution', async () => {
    // hrAdmin1 is an HR administrator of institution 1 and employee 1.
    // Employee 1 belongs to institution 1, employee 2 to institution 2.
    expect(await tableList(HR_ADMIN)).toContain('employee');

    await expect(
      asUser(HR_ADMIN, `SELECT public.admin_table_save('employee', '1'::jsonb, '{"primary_phone":"999"}'::jsonb)`),
    ).resolves.toBeTruthy();

    await expect(
      asUser(HR_ADMIN, `SELECT public.admin_table_save('employee', '2'::jsonb, '{"primary_phone":"999"}'::jsonb)`),
    ).rejects.toThrow('Not authorised');

    // The row of the other institution is untouched.
    const row = await db.query<{ primary_phone: string | null }>(
      'SELECT primary_phone FROM public.employee WHERE employee_id = 2',
    );
    expect(row.rows[0]!.primary_phone).toBeNull();
  }, TIMEOUT);

  it('keeps an institution scoped caller inside its own institution', async () => {
    // sysAdmin1 is a system administrator of institution 1.  Campus 1 belongs
    // to institution 1, campus 2 to institution 2.
    expect(await tableList(SYS_ADMIN)).toContain('campus');

    await expect(
      asUser(SYS_ADMIN, `SELECT public.admin_table_save('campus', '1'::jsonb, '{"campus_name":"Campus One"}'::jsonb)`),
    ).resolves.toBeTruthy();

    await expect(
      asUser(SYS_ADMIN, `SELECT public.admin_table_save('campus', '2'::jsonb, '{"campus_name":"Campus Two"}'::jsonb)`),
    ).rejects.toThrow('Not authorised');

    const row = await db.query<{ campus_name: string }>(
      'SELECT campus_name FROM public.campus WHERE campus_id = 2',
    );
    expect(row.rows[0]!.campus_name).toBe('Campus 2');
  }, TIMEOUT);

  it('refuses to move a row out of the caller scope', async () => {
    // A department may change its own course, but it may not hand it to another
    // department - the row level policy's WITH CHECK clause forbids that, and the
    // write function has to make the same decision because it runs as the owner.
    await expect(
      asUser(
        U.facultyD1,
        `SELECT public.admin_table_save('course_catalog', '9001'::jsonb, '{"owning_department_id":3}'::jsonb)`,
      ),
    ).rejects.toThrow('outside your scope');

    // The row is untouched.
    const row = await db.query<{ owning_department_id: number }>(
      'SELECT owning_department_id FROM public.course_catalog WHERE course_id = 9001',
    );
    expect(row.rows[0]!.owning_department_id).toBe(1);
  }, TIMEOUT);

  it('refuses a caller without the permission', async () => {
    // A student may never write a student row - not even their own.
    await expect(
      asUser(U.student1, `SELECT public.admin_table_save('student', '1'::jsonb, '{"notes":"mine"}'::jsonb)`),
    ).rejects.toThrow('Not authorised');

    // A registrar holds no ACADEMIC_CALENDAR.ALL.CONFIGURE permission.
    await expect(
      asUser(
        U.registrar1,
        `SELECT public.admin_table_save('academic_year', NULL, '{"year_code":"X","start_date":"2026-01-01","end_date":"2026-12-31"}'::jsonb)`,
      ),
    ).rejects.toThrow('Not authorised');

    // An unknown table is a bad request.
    await expect(
      asUser(U.superAdmin, `SELECT public.admin_table_save('nope', NULL, '{}'::jsonb)`),
    ).rejects.toThrow('Unknown table');
  }, TIMEOUT);

  it('refuses to delete a row that is still in use', async () => {
    // academic_year 1 is referenced by academic_term 1.
    await expect(asUser(U.superAdmin, `SELECT public.admin_table_delete('academic_year', '1'::jsonb)`)).rejects.toThrow(
      'still in use',
    );

    // The row is still there.
    const row = await db.query<{ n: number }>('SELECT count(*)::int AS n FROM public.academic_year WHERE academic_year_id = 1');
    expect(row.rows[0]!.n).toBe(1);
  }, TIMEOUT);

  it('reports a duplicate value instead of writing it twice', async () => {
    await expect(
      asUser(
        U.superAdmin,
        `SELECT public.admin_table_save('academic_year', NULL, '{"year_code":"2024-25","start_date":"2024-08-01","end_date":"2025-07-31"}'::jsonb)`,
      ),
    ).rejects.toThrow('already recorded');
  }, TIMEOUT);

  it('offers only the foreign key rows the caller may see', async () => {
    // The lookup RPC is SECURITY INVOKER, so the referenced table's own row level
    // policies decide what a dropdown contains.
    const admin = await asUser<{ id: number }>(U.superAdmin, `SELECT id FROM public.admin_lookup_options('course_catalog')`);
    expect(admin.map((r) => r.id).sort((a, b) => a - b)).toEqual([9001, 9002, 9003]);

    const faculty = await asUser<{ id: number }>(
      U.facultyD1,
      `SELECT id FROM public.admin_lookup_options('course_catalog')`,
    );
    expect(faculty.map((r) => r.id)).toEqual([9001]);

    // A correlated label reads through one foreign key.
    const curriculum = await asUser<{ id: number; label: string }>(
      U.superAdmin,
      `SELECT id, label FROM public.admin_lookup_options('curriculum_course')`,
    );
    expect(curriculum.length).toBeGreaterThan(0);
    expect(curriculum[0]!.label).toContain(' - ');

    await expect(asUser(U.superAdmin, `SELECT * FROM public.admin_lookup_options('nope')`)).rejects.toThrow(
      'Unknown lookup table',
    );
  }, TIMEOUT);

  it('audits a room change under the timetable module', async () => {
    const created = await asUser<{ id: number }>(
      U.superAdmin,
      `SELECT public.admin_table_save('room', NULL,
         '{"building_id":9001,"room_code":"TST-R9","room_name":"Test Room","room_type":"CLASSROOM","capacity":30,"is_active":true}'::jsonb) AS id`,
    );
    const id = created[0]!.id;
    await asUser(U.superAdmin, `SELECT public.admin_table_delete('room', '${id}'::jsonb)`);

    const audit = await db.query<{ action_code: string; module_code: string }>(
      `SELECT action_code, module_code FROM public.activity_audit
        WHERE entity_name = 'room' AND entity_id = $1 ORDER BY activity_audit_id`,
      [String(id)],
    );
    expect(audit.rows.map((r) => r.action_code)).toEqual(['INSERT', 'DELETE']);
    expect(audit.rows.every((r) => r.module_code === 'TIMETABLE')).toBe(true);
  }, TIMEOUT);
});
