import { beforeAll, describe, expect, it } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import { asUser, createWorld, db, U } from './world';

/**
 * Demo / test data integration tests.
 *
 * `tools/seed_demo.sql` is the file that gives every screen of SIMS something to show.  It is
 * only useful if the rows really hang together: an admitted applicant has to be the student
 * that registers for a term, the term has to run classes, the classes have to be attended,
 * the assessments have to be published, the marks have to become a result, and the result has
 * to be paid for.  A demo that only fills tables with unrelated rows is worse than no demo,
 * because every screen then has to cope with data that cannot happen.
 *
 * These tests therefore apply the whole file to the embedded PGlite world built by
 * `tests/db/world.ts` (all migrations + the org/people/role fixture) and then follow the
 * foreign keys from one module to the next.  The live Supabase database is never contacted.
 *
 * The file also has to survive a replay, so it is applied twice and the row counts are
 * compared.  Finally the row-level-security policies of migration 018 are exercised with a
 * demo student that is linked to an auth identity, because the demo seed deliberately creates
 * no users of its own.
 *
 * The demo tenant is deliberately self-contained: its own university, institution, campus,
 * department and programme.  The fixture users of the world (registrar1, student1, ...) are
 * scoped to the fixture organisation and therefore see none of the demo rows; only the
 * SUPER_ADMIN and a demo student linked to the demo tenant see them.
 */

const TIMEOUT = 300_000;

const SEED_PATH = path.resolve(__dirname, '../../tools/seed_demo.sql');
const SOURCE_PATH = path.resolve(__dirname, '../../SIMS-DatabaseWithoutLessonPlan.sql');

/** The auth identity of the demo student that the RLS part of this file links. */
const DEMO_SUB = '00000000-0000-0000-0000-00000000d001';

/** Tables the demo seed is allowed to write into. `activity_audit` is filled by a trigger. */
const AUDIT_TABLE = 'activity_audit';

/** Lookups the demo seed may extend with its own DEMO-* rows. */
const EXTENDABLE_LOOKUPS = new Set(['announcement_type', 'course_category']);

const q = async <T = Record<string, unknown>>(sql: string): Promise<T[]> => (await db.query<T>(sql)).rows;
const n = async (sql: string): Promise<number> => Number((await q<{ n: number }>(sql))[0]!.n);
const asN = async (sub: string, sql: string): Promise<number> => Number((await asUser<{ n: number }>(sub, sql))[0]!.n);

/** Row count of every table of the public schema. */
async function tableCounts(): Promise<Record<string, number>> {
  const names = (
    await q<{ t: string }>(`
      SELECT c.relname AS t FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'public' AND c.relkind = 'r' ORDER BY 1`)
  ).map((r) => r.t);
  const out: Record<string, number> = {};
  for (const t of names) out[t] = await n(`select count(*)::int n from public."${t}"`);
  return out;
}

/** The tables a SQL file writes into, comments and string literals removed. */
function writtenTables(sql: string): Set<string> {
  const stripped = sql
    .replace(/--[^\n]*/g, ' ')
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/'(?:[^']|'')*'/g, "''");
  const out = new Set<string>();
  for (const m of stripped.matchAll(/\b(?:insert\s+into|update|delete\s+from)\s+(?:public\.)?"?([a-z_][a-z0-9_]*)"?/gi)) {
    out.add(m[1]!.toLowerCase());
  }
  return out;
}

/** The tables the MySQL source seeds with reference data. The demo seed must not touch them. */
function sourceSeededTables(): Set<string> {
  const source = fs.readFileSync(SOURCE_PATH, 'utf8');
  const out = new Set<string>();
  for (const m of source.matchAll(/INSERT\s+(?:IGNORE\s+)?INTO\s+`?(\w+)`?\s*(?:\([^)]*\))?\s*(VALUES|SELECT)/gi)) {
    out.add(m[1]!.toLowerCase());
  }
  return out;
}

/** The identity and generated columns of every table, which the seed may never write into. */
async function protectedColumns(): Promise<Map<string, Set<string>>> {
  const rows = await q<{ table_name: string; column_name: string }>(`
    SELECT c.relname AS table_name, a.attname AS column_name
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
     WHERE n.nspname = 'public' AND (a.attidentity <> '' OR a.attgenerated <> '')`);
  const map = new Map<string, Set<string>>();
  for (const r of rows) {
    if (!map.has(r.table_name)) map.set(r.table_name, new Set());
    map.get(r.table_name)!.add(r.column_name);
  }
  return map;
}

let countsBeforeSeed: Record<string, number>;
let countsAfterSeed: Record<string, number>;
let seedTables: Set<string>;
let sourceTables: Set<string>;
let generatedColumns: Map<string, Set<string>>;

beforeAll(async () => {
  await createWorld();

  const seed = fs.readFileSync(SEED_PATH, 'utf8');
  seedTables = writtenTables(seed);
  sourceTables = sourceSeededTables();
  generatedColumns = await protectedColumns();

  countsBeforeSeed = await tableCounts();

  // The whole file is one script: it must apply in a single call, exactly as it is applied
  // with `psql -f tools/seed_demo.sql`.
  await db.exec(seed);

  countsAfterSeed = await tableCounts();

  // ---------------------------------------------------------------------------
  // No local grant workaround is needed any more.  The live project grants
  // `authenticated` SELECT on every column of 212 of the 213 public tables
  // (migration 021 reproduces that exactly), so the direct table reads below
  // are allowed and the RLS row filters of migration 018 are reachable.
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // The demo seed creates no auth users on purpose: a SIMS user needs a Supabase Auth
  // identity, which cannot be created from SQL.  For the RLS part of this file one demo
  // student is given a user account and an auth identity here.
  // ---------------------------------------------------------------------------
  await db.exec(`INSERT INTO user_account (username, password_hash, account_status) VALUES ('demo_student1', 'x', 'ACTIVE');`);
  const userId = Number(
    (await q<{ user_id: number }>(`select user_id from user_account where username = 'demo_student1'`))[0]!.user_id,
  );
  await db.exec(`
    INSERT INTO student_user_account (student_id, user_id)
      SELECT s.student_id, ${userId} FROM student s WHERE s.student_number = 'DEMO-S001';
    INSERT INTO user_role_assignment (user_id, role_id, scope_type)
      VALUES (${userId}, (select role_id from role where role_code = 'STUDENT'), 'SELF');
    INSERT INTO auth.users (id) VALUES ('${DEMO_SUB}');
    SELECT sims_private.link_auth_user('${DEMO_SUB}', ${userId}, 'test');
  `);
}, TIMEOUT);

describe('demo seed: the reference data of the demo tenant', () => {
  it('builds the university, institution, campus, department and programme tree', async () => {
    expect(await n(`select count(*)::int n from university where university_code = 'DEMO-UNIV'`)).toBe(1);
    expect(
      await n(`
        select count(*)::int n from institution i
          join university u on u.university_id = i.university_id
         where i.institution_code = 'DEMO-INST' and u.university_code = 'DEMO-UNIV'`),
    ).toBe(1);
    expect(
      await n(`
        select count(*)::int n from campus c
          join institution i on i.institution_id = c.institution_id
         where c.campus_code = 'DEMO-CAMPUS' and i.institution_code = 'DEMO-INST'`),
    ).toBe(1);
    expect(await n(`select count(*)::int n from department where department_code in ('DEMO-CSE','DEMO-MGT')`)).toBe(2);
    expect(await n(`select count(*)::int n from programme where programme_code in ('DEMO-BSC-CS','DEMO-MBA')`)).toBe(2);
    expect(
      await n(`
        select count(*)::int n from programme_specialization sp
          join programme p on p.programme_id = sp.programme_id
         where sp.specialization_code = 'DEMO-CS-DS' and p.programme_code = 'DEMO-BSC-CS'`),
    ).toBe(1);
  });

  it('builds the academic calendar of the odd semester 2025-26', async () => {
    expect(await n(`select count(*)::int n from academic_year where year_code = '2025-26'`)).toBe(1);
    expect(
      await n(`
        select count(*)::int n from academic_term t
          join academic_year y on y.academic_year_id = t.academic_year_id
         where t.term_code = '2025-26-ODD' and y.year_code = '2025-26'`),
    ).toBe(1);
    expect(await n(`select count(*)::int n from time_slot where slot_code like 'DEMO-T%'`)).toBe(5);
  });

  it('builds the curriculum of the programme', async () => {
    expect(
      await n(`
        select count(*)::int n from curriculum_scheme cs
          join programme p on p.programme_id = cs.programme_id
         where cs.scheme_code = 'DEMO-UGCS-2025' and p.programme_code = 'DEMO-BSC-CS'`),
    ).toBe(1);
    expect(
      await n(`
        select count(*)::int n from curriculum_course cc
          join curriculum_scheme cs on cs.curriculum_scheme_id = cc.curriculum_scheme_id
          join course_catalog c on c.course_id = cc.course_id
         where cs.scheme_code = 'DEMO-UGCS-2025' and c.course_code in ('DEMO-CS101','DEMO-CS102','DEMO-CS103')`),
    ).toBe(3);
  });

  it('creates the three demo students and the two demo employees', async () => {
    expect(await n(`select count(*)::int n from student where student_number in ('DEMO-S001','DEMO-S002','DEMO-S003')`)).toBe(3);
    expect(await n(`select count(*)::int n from student_address where student_id in (select student_id from student where student_number like 'DEMO-%')`)).toBe(3);
    expect(
      await n(`
        select count(*)::int n from student_programme_enrolment e
          join student s on s.student_id = e.student_id
          join programme p on p.programme_id = e.programme_id
         where s.student_number like 'DEMO-%' and p.programme_code = 'DEMO-BSC-CS'`),
    ).toBe(3);
    expect(await n(`select count(*)::int n from employee where employee_number in ('DEMO-E001','DEMO-E002')`)).toBe(2);
    expect(
      await n(`
        select count(*)::int n from employee_assignment a
          join employee e on e.employee_id = a.employee_id
         where e.employee_number in ('DEMO-E001','DEMO-E002') and a.is_primary`),
    ).toBe(2);
  });
});

describe('demo seed: chunk 2 - admission to result', () => {
  it('admits the applicant and keeps the second application under review', async () => {
    const apps = await q<{
      application_number: string;
      application_status: string;
      eligibility_status: string;
      admitted_student_number: string | null;
    }>(`
      select a.application_number, a.application_status, a.eligibility_status, s.student_number as admitted_student_number
        from admission_application a
        left join student s on s.student_id = a.admitted_student_id
       where a.application_number in ('DEMO-APPLICATION-001','DEMO-APPLICATION-002')
       order by a.application_number`);
    expect(apps).toEqual([
      {
        application_number: 'DEMO-APPLICATION-001',
        application_status: 'ADMITTED',
        eligibility_status: 'ELIGIBLE',
        admitted_student_number: 'DEMO-S003',
      },
      {
        application_number: 'DEMO-APPLICATION-002',
        application_status: 'UNDER_REVIEW',
        eligibility_status: 'PENDING',
        admitted_student_number: null,
      },
    ]);
    expect(await n(`select count(*)::int n from admission_applicant`)).toBe(2);
  });

  it('registers the three students for the term, the section and the batch', async () => {
    const regs = await q<{ roll_number: string; student_number: string; section_code: string; batch_code: string; term_code: string }>(`
      select tr.roll_number, s.student_number, cs.section_code, cb.batch_code, t.term_code
        from student_term_registration tr
        join student_programme_enrolment e on e.enrolment_id = tr.enrolment_id
        join student s on s.student_id = e.student_id
        join programme_term_offering pto on pto.programme_term_offering_id = tr.programme_term_offering_id
        join academic_term t on t.academic_term_id = pto.academic_term_id
        join class_section cs on cs.class_section_id = tr.class_section_id
        join class_batch cb on cb.class_batch_id = tr.class_batch_id
       where tr.roll_number in ('DEMO-R001','DEMO-R002','DEMO-R003')
       order by tr.roll_number`);
    expect(regs).toEqual([
      { roll_number: 'DEMO-R001', student_number: 'DEMO-S001', section_code: 'DEMO-A', batch_code: 'DEMO-B1', term_code: '2025-26-ODD' },
      { roll_number: 'DEMO-R002', student_number: 'DEMO-S002', section_code: 'DEMO-A', batch_code: 'DEMO-B1', term_code: '2025-26-ODD' },
      { roll_number: 'DEMO-R003', student_number: 'DEMO-S003', section_code: 'DEMO-A', batch_code: 'DEMO-B1', term_code: '2025-26-ODD' },
    ]);
    expect(await n(`select count(*)::int n from student_term_registration where registration_status = 'REGISTERED'`)).toBe(3);
  });

  it('allocates the two offerings to the two instructors and rosters the students', async () => {
    const teaching = await q<{ offering_code: string; employee_number: string; assignment_role: string; session_type: string }>(`
      select co.offering_code, e.employee_number, fca.assignment_role, cos.session_type
        from faculty_course_assignment fca
        join course_offering_section cos on cos.course_offering_section_id = fca.course_offering_section_id
        join course_offering co on co.course_offering_id = cos.course_offering_id
        join employee e on e.employee_id = fca.employee_id
       where co.offering_code in ('DEMO-CS101','DEMO-CS103')
       order by co.offering_code`);
    expect(teaching).toEqual([
      { offering_code: 'DEMO-CS101', employee_number: 'DEMO-E001', assignment_role: 'PRIMARY_INSTRUCTOR', session_type: 'LECTURE' },
      { offering_code: 'DEMO-CS103', employee_number: 'DEMO-E002', assignment_role: 'LAB_INSTRUCTOR', session_type: 'PRACTICAL' },
    ]);

    // Every student of the section is registered for both offerings and is on the roster.
    expect(
      await n(`
        select count(*)::int n from student_course_registration cr
          join course_offering co on co.course_offering_id = cr.course_offering_id
         where co.offering_code in ('DEMO-CS101','DEMO-CS103') and cr.registration_status = 'REGISTERED'`),
    ).toBe(6);
    expect(
      await n(`
        select count(*)::int n from course_offering_section_student r
          join course_offering co on co.course_offering_id = r.course_offering_id
         where co.offering_code in ('DEMO-CS101','DEMO-CS103') and r.roster_status = 'ACTIVE'`),
    ).toBe(6);
  });

  it('marks the attendance of every session and joins it to the class it belongs to', async () => {
    const attendance = await q<{ student_number: string; offering_code: string; session_date: string; status_code: string; status_name: string }>(`
      select s.student_number, co.offering_code, cs.session_date::text as session_date, ast.status_code, ast.status_name
        from student_attendance sa
        join attendance_status ast on ast.attendance_status_id = sa.attendance_status_id
        join class_session cs on cs.class_session_id = sa.class_session_id
        join course_offering_section cos on cos.course_offering_section_id = cs.course_offering_section_id
        join course_offering co on co.course_offering_id = cos.course_offering_id
        join course_offering_section_student r on r.course_offering_section_student_id = sa.course_offering_section_student_id
        join student_course_registration cr on cr.course_registration_id = r.course_registration_id
        join student_term_registration tr on tr.term_registration_id = cr.term_registration_id
        join student_programme_enrolment e on e.enrolment_id = tr.enrolment_id
        join student s on s.student_id = e.student_id
       order by s.student_number, cs.session_date`);
    expect(attendance).toHaveLength(9);
    expect(attendance.map((r) => r.status_code).sort()).toEqual([
      'ABSENT',
      'LATE',
      'PRESENT',
      'PRESENT',
      'PRESENT',
      'PRESENT',
      'PRESENT',
      'PRESENT',
      'PRESENT',
    ]);
    expect(attendance.find((r) => r.status_code === 'ABSENT')).toMatchObject({
      student_number: 'DEMO-S003',
      offering_code: 'DEMO-CS103',
      session_date: '2025-08-08',
    });
    expect(attendance.find((r) => r.status_code === 'LATE')).toMatchObject({
      student_number: 'DEMO-S002',
      offering_code: 'DEMO-CS101',
      session_date: '2025-08-06',
    });
    // The seeded attendance statuses are the ones of migration 064.
    expect(attendance.find((r) => r.status_code === 'ABSENT')!.status_name).toBe('Absent (Default)');
  });

  it('publishes every assessment event and enters the marks of the registered students', async () => {
    const events = await q<{ offering_code: string; component_code: string; component_type: string; maximum_marks: string; weightage_percent: string; status: string }>(`
      select co.offering_code, ac.component_code, ac.component_type, ac.maximum_marks::text, ac.weightage_percent::text, ae.status
        from assessment_event ae
        join assessment_component ac on ac.assessment_component_id = ae.assessment_component_id
        join course_offering co on co.course_offering_id = ac.course_offering_id
       where co.offering_code in ('DEMO-CS101','DEMO-CS103')
       order by co.offering_code, ac.component_code`);
    expect(events).toEqual([
      { offering_code: 'DEMO-CS101', component_code: 'END', component_type: 'OTHER', maximum_marks: '70.00', weightage_percent: '60.00', status: 'PUBLISHED' },
      { offering_code: 'DEMO-CS101', component_code: 'IA1', component_type: 'INTERNAL_TEST', maximum_marks: '30.00', weightage_percent: '40.00', status: 'PUBLISHED' },
      { offering_code: 'DEMO-CS103', component_code: 'END', component_type: 'OTHER', maximum_marks: '70.00', weightage_percent: '60.00', status: 'PUBLISHED' },
      { offering_code: 'DEMO-CS103', component_code: 'IA1', component_type: 'INTERNAL_TEST', maximum_marks: '30.00', weightage_percent: '40.00', status: 'PUBLISHED' },
    ]);

    // Every mark belongs to a student that is registered for the offering of the event.
    expect(
      await n(`
        select count(*)::int n from student_assessment_mark m
          join assessment_event ae on ae.assessment_event_id = m.assessment_event_id
          join course_offering co on co.course_offering_id = ae.course_offering_id
          join student_course_registration cr on cr.course_registration_id = m.course_registration_id
         where co.offering_code in ('DEMO-CS101','DEMO-CS103') and cr.course_offering_id = co.course_offering_id`),
    ).toBe(12);
  });

  it('leaves the absent student without marks', async () => {
    const absent = await q<{ attendance_status: string; marks_obtained: string | null; remarks: string | null }>(`
      select m.attendance_status, m.marks_obtained::text, m.remarks
        from student_assessment_mark m
        join assessment_event ae on ae.assessment_event_id = m.assessment_event_id
        join assessment_component ac on ac.assessment_component_id = ae.assessment_component_id
        join course_offering co on co.course_offering_id = ac.course_offering_id
        join student_course_registration cr on cr.course_registration_id = m.course_registration_id
        join student_term_registration tr on tr.term_registration_id = cr.term_registration_id
        join student_programme_enrolment e on e.enrolment_id = tr.enrolment_id
        join student s on s.student_id = e.student_id
       where s.student_number = 'DEMO-S003' and co.offering_code = 'DEMO-CS103' and ac.component_code = 'IA1'`);
    expect(absent).toHaveLength(1);
    expect(absent[0]!.attendance_status).toBe('ABSENT');
    expect(absent[0]!.marks_obtained).toBeNull();
  });

  it('turns the marks into a course result and the course results into a published term result', async () => {
    expect(
      await n(`
        select count(*)::int n from student_course_result r
          join student_course_registration cr on cr.course_registration_id = r.course_registration_id
          join student_term_registration tr on tr.term_registration_id = cr.term_registration_id
          join student_programme_enrolment e on e.enrolment_id = tr.enrolment_id
          join student s on s.student_id = e.student_id
         where s.student_number like 'DEMO-%'`),
    ).toBe(6);
    // The total of every course result is the sum of its two marks.
    expect(await n(`select count(*)::int n from student_course_result where total_marks is distinct from internal_marks + external_marks`)).toBe(0);
    // The grade of every course result is the grade the seeded grading scale gives for its percentage.
    expect(
      await n(`
        select count(*)::int n
          from student_course_result r
          join student_course_registration cr on cr.course_registration_id = r.course_registration_id
          join course_offering co on co.course_offering_id = cr.course_offering_id
          join lateral (
            select sum(ac.maximum_marks) as max_total from assessment_component ac
             where ac.course_offering_id = co.course_offering_id
          ) m on true
         where not exists (
           select 1 from grade_scale gs join grade_rule gr on gr.grade_scale_id = gs.grade_scale_id
            where gs.is_active
              and (r.total_marks / m.max_total) * 100 between gr.minimum_percentage and gr.maximum_percentage
              and gr.grade_letter = r.grade_letter
              and gr.grade_point = r.grade_point
         )`),
    ).toBe(0);

    const terms = await q<{ student_number: string; sgpa: string; credits_registered: string; credits_earned: string; published: boolean }>(`
      select s.student_number, tr.sgpa::text, tr.credits_registered::text, tr.credits_earned::text, tr.published_at is not null as published
        from student_term_result tr
        join student_term_registration sr on sr.term_registration_id = tr.term_registration_id
        join student_programme_enrolment e on e.enrolment_id = sr.enrolment_id
        join student s on s.student_id = e.student_id
       order by s.student_number`);
    expect(terms).toEqual([
      { student_number: 'DEMO-S001', sgpa: '9.67', credits_registered: '6.0', credits_earned: '6.0', published: true },
      { student_number: 'DEMO-S002', sgpa: '8.33', credits_registered: '6.0', credits_earned: '6.0', published: true },
      { student_number: 'DEMO-S003', sgpa: '6.67', credits_registered: '6.0', credits_earned: '6.0', published: true },
    ]);

    // The SGPA of the term result is the weighted average of the grade points of its course results.
    const computed = await q<{ student_number: string; computed_sgpa: string; earned: string }>(`
      select s.student_number,
             round(sum(r.grade_point * r.credits_earned) / sum(r.credits_earned), 2)::text as computed_sgpa,
             sum(r.credits_earned)::text as earned
        from student_course_result r
        join student_course_registration cr on cr.course_registration_id = r.course_registration_id
        join student_term_registration tr on tr.term_registration_id = cr.term_registration_id
        join student_programme_enrolment e on e.enrolment_id = tr.enrolment_id
        join student s on s.student_id = e.student_id
       group by s.student_number
       order by s.student_number`);
    expect(computed).toEqual([
      { student_number: 'DEMO-S001', computed_sgpa: '9.67', earned: '6.0' },
      { student_number: 'DEMO-S002', computed_sgpa: '8.33', earned: '6.0' },
      { student_number: 'DEMO-S003', computed_sgpa: '6.67', earned: '6.0' },
    ]);
  });
});

describe('demo seed: chunk 3 - finance, communication and activity', () => {
  it('prices the fee structure of the programme', async () => {
    expect(await n(`select count(*)::int n from fee_structure where structure_code = 'DEMO-FS-UGCS-2025' and approval_status = 'APPROVED'`)).toBe(1);
    const items = await q<{ fee_code: string; amount: string }>(`
      select ft.fee_code, fsi.amount::text
        from fee_structure_item fsi
        join fee_structure fs on fs.fee_structure_id = fsi.fee_structure_id
        join fee_type ft on ft.fee_type_id = fsi.fee_type_id
       where fs.structure_code = 'DEMO-FS-UGCS-2025'
       order by fsi.display_order`);
    expect(items).toEqual([
      { fee_code: 'TUITION_FEE', amount: '120000.00' },
      { fee_code: 'LAB_FEE', amount: '25000.00' },
      { fee_code: 'LIBRARY_FEE', amount: '5000.00' },
      { fee_code: 'EXAM_FEE', amount: '3000.00' },
    ]);
    expect(
      await n(`
        select sum(fsi.amount)::int as n from fee_structure_item fsi
          join fee_structure fs on fs.fee_structure_id = fsi.fee_structure_id
         where fs.structure_code = 'DEMO-FS-UGCS-2025'`),
    ).toBe(153000);
  });

  it('assesses the fee of every student and keeps the header in step with its items', async () => {
    expect(await n(`select count(*)::int n from student_financial_account where account_number in ('DEMO-FIN-001','DEMO-FIN-002','DEMO-FIN-003')`)).toBe(3);
    expect(await n(`select count(*)::int n from student_fee_assessment where assessment_number in ('DEMO-FEA-001','DEMO-FEA-002','DEMO-FEA-003')`)).toBe(3);
    expect(
      await n(`
        select count(*)::int n from student_fee_assessment_item i
          join student_fee_assessment a on a.fee_assessment_id = i.fee_assessment_id
         where a.assessment_number like 'DEMO-%'`),
    ).toBe(12);

    // The header of an assessment is the sum of its items.
    expect(
      await n(`
        select count(*)::int n from student_fee_assessment a
         where a.assessment_number like 'DEMO-%'
           and (a.gross_amount is distinct from (select sum(i.original_amount) from student_fee_assessment_item i where i.fee_assessment_id = a.fee_assessment_id)
             or a.concession_amount is distinct from (select sum(i.concession_amount) from student_fee_assessment_item i where i.fee_assessment_id = a.fee_assessment_id)
             or a.net_payable_amount is distinct from (select sum(i.net_amount) from student_fee_assessment_item i where i.fee_assessment_id = a.fee_assessment_id)
             or a.amount_paid is distinct from (select sum(i.amount_paid) from student_fee_assessment_item i where i.fee_assessment_id = a.fee_assessment_id)
             or a.balance_amount is distinct from (select sum(i.balance_amount) from student_fee_assessment_item i where i.fee_assessment_id = a.fee_assessment_id))`),
    ).toBe(0);

    const assessments = await q<{ assessment_number: string; gross_amount: string; concession_amount: string; net_payable_amount: string; amount_paid: string; balance_amount: string; assessment_status: string }>(`
      select assessment_number, gross_amount::text, concession_amount::text, net_payable_amount::text, amount_paid::text, balance_amount::text, assessment_status
        from student_fee_assessment where assessment_number like 'DEMO-%' order by assessment_number`);
    expect(assessments).toEqual([
      { assessment_number: 'DEMO-FEA-001', gross_amount: '153000.00', concession_amount: '0.00', net_payable_amount: '153000.00', amount_paid: '0.00', balance_amount: '153000.00', assessment_status: 'ASSESSED' },
      { assessment_number: 'DEMO-FEA-002', gross_amount: '153000.00', concession_amount: '0.00', net_payable_amount: '153000.00', amount_paid: '0.00', balance_amount: '153000.00', assessment_status: 'ASSESSED' },
      { assessment_number: 'DEMO-FEA-003', gross_amount: '153000.00', concession_amount: '5000.00', net_payable_amount: '143000.00', amount_paid: '50000.00', balance_amount: '93000.00', assessment_status: 'PARTIALLY_PAID' },
    ]);

    // The concession of 5000 sits on the tuition fee of DEMO-FEA-003.
    const concession = await q<{ fee_code: string; concession_amount: string; net_amount: string; item_status: string }>(`
      select ft.fee_code, i.concession_amount::text, i.net_amount::text, i.item_status
        from student_fee_assessment_item i
        join student_fee_assessment a on a.fee_assessment_id = i.fee_assessment_id
        join fee_type ft on ft.fee_type_id = i.fee_type_id
       where a.assessment_number = 'DEMO-FEA-003' and i.concession_amount <> 0`);
    expect(concession).toEqual([{ fee_code: 'TUITION_FEE', concession_amount: '5000.00', net_amount: '115000.00', item_status: 'PARTIALLY_PAID' }]);
  });

  it('records the benefits, the adjustments, the penalty and the instalment plan of the demo accounts', async () => {
    // Every applied benefit is mirrored in the fee item it was applied to.
    const benefits = await q<{
      assessment_number: string;
      fee_code: string;
      benefit_type: string;
      benefit_amount: string;
      concession_amount: string;
      scholarship_amount: string;
    }>(`
      select a.assessment_number, ft.fee_code, b.benefit_type, b.benefit_amount::text,
             i.concession_amount::text, i.scholarship_amount::text
        from fee_assessment_benefit b
        join student_fee_assessment_item i on i.assessment_item_id = b.assessment_item_id
        join student_fee_assessment a on a.fee_assessment_id = i.fee_assessment_id
        join fee_type ft on ft.fee_type_id = i.fee_type_id
       order by a.assessment_number, ft.fee_code`);
    expect(benefits).toEqual([
      {
        assessment_number: 'DEMO-FEA-003',
        fee_code: 'LAB_FEE',
        benefit_type: 'SPONSORSHIP',
        benefit_amount: '5000.00',
        concession_amount: '0.00',
        scholarship_amount: '5000.00',
      },
      {
        assessment_number: 'DEMO-FEA-003',
        fee_code: 'TUITION_FEE',
        benefit_type: 'CONCESSION',
        benefit_amount: '5000.00',
        concession_amount: '5000.00',
        scholarship_amount: '0.00',
      },
    ]);

    // The scholarship is still waiting for a decision, the sponsorship is only partly applied.
    expect(await n(`select count(*)::int n from student_scholarship where application_status = 'SUBMITTED'`)).toBe(1);
    expect(await n(`select count(*)::int n from student_sponsorship where approval_status = 'APPROVED'`)).toBe(1);

    // Both adjustments are submitted, so the super administrator can still decide them.
    const adjustments = await q<{
      adjustment_number: string;
      adjustment_type: string;
      adjustment_amount: string;
      approval_status: string;
    }>(`
      select adjustment_number, adjustment_type, adjustment_amount::text, approval_status
        from fee_adjustment order by adjustment_number`);
    expect(adjustments).toEqual([
      { adjustment_number: 'DEMO-ADJ-001', adjustment_type: 'CREDIT', adjustment_amount: '1000.00', approval_status: 'SUBMITTED' },
      { adjustment_number: 'DEMO-ADJ-002', adjustment_type: 'WAIVER', adjustment_amount: '500.00', approval_status: 'SUBMITTED' },
    ]);

    // The penalty is assessed but not waived.
    expect(await n(`select count(*)::int n from student_fee_penalty where penalty_status = 'ASSESSED' and waived_amount = 0`)).toBe(1);

    // The instalment plan of DEMO-S002 is the one the three way split produces.
    const instalments = await q<{
      installment_number: number;
      installment_amount: string;
      balance_amount: string;
      installment_status: string;
    }>(`
      select s.installment_number, s.installment_amount::text, s.balance_amount::text, s.installment_status
        from student_installment_schedule s
        join student_fee_assessment a on a.fee_assessment_id = s.fee_assessment_id
       where a.assessment_number = 'DEMO-FEA-002'
       order by s.installment_number`);
    expect(instalments).toEqual([
      { installment_number: 1, installment_amount: '61200.00', balance_amount: '61200.00', installment_status: 'PENDING' },
      { installment_number: 2, installment_amount: '45900.00', balance_amount: '45900.00', installment_status: 'PENDING' },
      { installment_number: 3, installment_amount: '45900.00', balance_amount: '45900.00', installment_status: 'PENDING' },
    ]);

    // The refund has been processed, so the payment it was refunded from is no longer a success.
    expect(await n(`select count(*)::int n from refund_request where request_status = 'PROCESSED'`)).toBe(1);
    expect(await n(`select count(*)::int n from fee_refund where refund_status = 'SUCCESS'`)).toBe(1);
  });

  it('allocates the payment to the tuition fee and issues the receipt', async () => {
    const payment = await q<{ transaction_number: string; mode_code: string; amount: string; payment_status: string }>(`
      select p.transaction_number, pm.mode_code, p.amount::text, p.payment_status
        from payment_transaction p join payment_mode pm on pm.payment_mode_id = p.payment_mode_id
       where p.transaction_number = 'DEMO-PAY-001'`);
    expect(payment).toEqual([{ transaction_number: 'DEMO-PAY-001', mode_code: 'UPI', amount: '50000.00', payment_status: 'PARTIALLY_REFUNDED' }]);

    const allocation = await q<{ assessment_number: string; fee_code: string; allocated_amount: string }>(`
      select a.assessment_number, ft.fee_code, al.allocated_amount::text
        from payment_allocation al
        join payment_transaction p on p.payment_transaction_id = al.payment_transaction_id
        join student_fee_assessment_item i on i.assessment_item_id = al.assessment_item_id
        join student_fee_assessment a on a.fee_assessment_id = i.fee_assessment_id
        join fee_type ft on ft.fee_type_id = i.fee_type_id
       where p.transaction_number = 'DEMO-PAY-001'`);
    expect(allocation).toEqual([{ assessment_number: 'DEMO-FEA-003', fee_code: 'TUITION_FEE', allocated_amount: '50000.00' }]);

    // The allocation reduced the balance of the item it was paid against.
    expect(
      await n(`
        select count(*)::int n from student_fee_assessment_item i
          join student_fee_assessment a on a.fee_assessment_id = i.fee_assessment_id
          join fee_type ft on ft.fee_type_id = i.fee_type_id
         where a.assessment_number = 'DEMO-FEA-003' and ft.fee_code = 'TUITION_FEE'
           and i.amount_paid = 50000 and i.balance_amount = 65000`),
    ).toBe(1);

    const receipt = await q<{ receipt_number: string; receipt_amount: string; receipt_status: string }>(`
      select r.receipt_number, r.receipt_amount::text, r.receipt_status
        from fee_receipt r join payment_transaction p on p.payment_transaction_id = r.payment_transaction_id
       where p.transaction_number = 'DEMO-PAY-001'`);
    expect(receipt).toHaveLength(1);
    expect(receipt[0]!.receipt_status).toBe('ISSUED');
    expect(receipt[0]!.receipt_amount).toBe('50000.00');
    // The receipt number carries the academic year of the day it was issued.
    expect(receipt[0]!.receipt_number).toMatch(/^REC\/\d{4}-\d{2}\/000001$/);
  });

  it('publishes the announcements of the demo tenant', async () => {
    expect(await n(`select count(*)::int n from announcement_type where type_code in ('DEMO-GENERAL','DEMO-ACADEMIC','DEMO-EXAM')`)).toBe(3);
    const announcements = await q<{ type_code: string; title: string; approval_status: string; audience_type: string; department_code: string | null }>(`
      select t.type_code, a.title, a.approval_status, a.audience_type, d.department_code
        from announcement a
        join announcement_type t on t.announcement_type_id = a.announcement_type_id
        left join department d on d.department_id = a.department_id
       where t.type_code in ('DEMO-GENERAL','DEMO-ACADEMIC')
       order by t.type_code`);
    expect(announcements).toEqual([
      { type_code: 'DEMO-ACADEMIC', title: 'Mid semester study leave', approval_status: 'APPROVED', audience_type: 'STUDENTS', department_code: 'DEMO-CSE' },
      { type_code: 'DEMO-GENERAL', title: 'Demo University orientation', approval_status: 'APPROVED', audience_type: 'ALL', department_code: null },
    ]);
  });

  it('records the staff activity and the student activities', async () => {
    const staff = await q<{ employee_number: string; activity_type_code: string; activity_title: string }>(`
      select e.employee_number, at.activity_type_code, sa.activity_title
        from staff_activity sa
        join employee e on e.employee_id = sa.employee_id
        join activity_type at on at.activity_type_id = sa.activity_type_id
       where e.employee_number = 'DEMO-E001'`);
    expect(staff).toEqual([
      {
        employee_number: 'DEMO-E001',
        activity_type_code: 'JOURNAL_PUBLICATION',
        activity_title: 'Attendance analytics of the first year programming laboratory',
      },
    ]);

    const students = await q<{ student_number: string; type_code: string; activity_title: string; achievement_type: string; position_rank: number | null; mode_code: string }>(`
      select s.student_number, sat.type_code, sa.activity_title, sa.achievement_type, sa.position_rank, em.mode_code
        from student_activity sa
        join student s on s.student_id = sa.student_id
        join student_activity_type sat on sat.student_activity_type_id = sa.student_activity_type_id
        join event_mode em on em.event_mode_id = sa.event_mode_id
       where s.student_number in ('DEMO-S001','DEMO-S002')
       order by s.student_number`);
    expect(students).toEqual([
      { student_number: 'DEMO-S001', type_code: 'SPORTS', activity_title: 'Inter-college athletics meet', achievement_type: 'WINNER', position_rank: 1, mode_code: 'OFFLINE' },
      { student_number: 'DEMO-S002', type_code: 'HACKATHON', activity_title: 'Smart India Hackathon', achievement_type: 'PARTICIPATION', position_rank: null, mode_code: 'OFFLINE' },
    ]);
  });
});

describe('demo seed: it stays inside its own tenant', () => {
  it('writes only into the tables the seed names', () => {
    const changed = Object.keys(countsAfterSeed).filter((t) => countsBeforeSeed[t] !== countsAfterSeed[t]);
    const unexpected = changed.filter((t) => !seedTables.has(t) && t !== AUDIT_TABLE);
    expect(unexpected).toEqual([]);
    // The seed really did write something.
    expect(changed).toEqual(
      expect.arrayContaining([
        'student',
        'student_attendance',
        'student_course_result',
        'student_term_result',
        'student_fee_assessment',
        'payment_transaction',
        'announcement',
        'staff_activity',
        'student_activity',
      ]),
    );
  });

  it('never writes an identity or a generated column', () => {
    const stripped = fs
      .readFileSync(SEED_PATH, 'utf8')
      .replace(/--[^\n]*/g, ' ')
      .replace(/'(?:[^']|'')*'/g, "''");
    const offenders: string[] = [];
    for (const m of stripped.matchAll(/insert\s+into\s+(?:public\.)?"?([a-z_][a-z0-9_]*)"?\s*\(([^)]*)\)/gi)) {
      const table = m[1]!.toLowerCase();
      const protectedCols = generatedColumns.get(table);
      if (!protectedCols) continue;
      for (const col of m[2]!.split(',').map((c) => c.trim().toLowerCase()).filter(Boolean)) {
        if (protectedCols.has(col)) offenders.push(`${table}.${col}`);
      }
    }
    expect(offenders).toEqual([]);
  });

  it('does not touch a single table that the source seeds', () => {
    const changed = Object.keys(countsAfterSeed).filter((t) => countsBeforeSeed[t] !== countsAfterSeed[t]);
    const touched = changed.filter((t) => sourceTables.has(t) && !EXTENDABLE_LOOKUPS.has(t));
    expect(touched).toEqual([]);
    expect(sourceTables.size).toBeGreaterThan(30);
  });
});

describe('demo seed: it can be replayed', () => {
  it('changes nothing when it is applied a second time', async () => {
    const before = await tableCounts();
    await db.exec(fs.readFileSync(SEED_PATH, 'utf8'));
    const after = await tableCounts();
    const changed = Object.keys(before).filter((t) => before[t] !== after[t]);
    expect(changed).toEqual([]);
    // The receipt number is not burnt a second time.
    expect(await n(`select count(*)::int n from fee_receipt`)).toBe(1);
    expect(await n(`select count(*)::int n from payment_allocation`)).toBe(1);
  }, TIMEOUT);
});

describe('demo seed: row level security', () => {
  it('lets the linked demo student read their own rows and nothing else', async () => {
    const visible: Record<string, number> = {
      student: 1,
      student_attendance: 3,
      student_activity: 1,
      student_fee_assessment: 1,
      student_course_result: 2,
      student_term_result: 1,
      student_assessment_mark: 4,
      student_term_registration: 1,
      announcement: 0,
      class_session: 0,
      course_offering: 0,
      payment_transaction: 0,
      fee_receipt: 0,
      staff_activity: 0,
    };
    for (const [table, expected] of Object.entries(visible)) {
      expect(await asN(DEMO_SUB, `select count(*)::int n from public.${table}`), table).toBe(expected);
    }
    // The rows that are visible are the rows of DEMO-S001.
    const own = await asUser<{ student_number: string }>(DEMO_SUB, `select student_number from student`);
    expect(own).toEqual([{ student_number: 'DEMO-S001' }]);
    const attendance = await asUser<{ student_number: string }>(
      DEMO_SUB,
      `select distinct s.student_number
         from student_attendance sa
         join course_offering_section_student r on r.course_offering_section_student_id = sa.course_offering_section_student_id
         join student_course_registration cr on cr.course_registration_id = r.course_registration_id
         join student_term_registration tr on tr.term_registration_id = cr.term_registration_id
         join student_programme_enrolment e on e.enrolment_id = tr.enrolment_id
         join student s on s.student_id = e.student_id`,
    );
    expect(attendance).toEqual([{ student_number: 'DEMO-S001' }]);
  });

  it('delivers the announcement of the demo tenant to the demo student', async () => {
    const feed = await asUser<{ title: string; type_name: string }>(DEMO_SUB, `select title, type_name from public.announcements_feed(30)`);
    expect(feed).toEqual([{ title: 'Demo University orientation', type_name: 'Demo General' }]);
  });

  it('lets the super administrator read the whole demo tenant', async () => {
    const visible: Record<string, number> = {
      student_attendance: 9,
      student_activity: 2,
      student_fee_assessment: 3,
      student_course_result: 6,
      student_term_result: 3,
      student_assessment_mark: 12,
      student_term_registration: 3,
      announcement: 2,
      class_session: 3,
      course_offering: 2,
      // DEMO-PAY-001 is the tuition payment of DEMO-S003, DEMO-PAY-002 the admission fee
      // of the same student.  Only DEMO-PAY-001 has an allocation and a receipt.
      payment_transaction: 2,
      fee_receipt: 1,
      // One journal publication for DEMO-E001, three research records and eight profile
      // activities (internship, proposal, consultancy, co-curricular, extra-curricular,
      // award, membership, FDP) for DEMO-E002.
      staff_activity: 12,
      admission_application: 2,
    };
    for (const [table, expected] of Object.entries(visible)) {
      expect(await asN(U.superAdmin, `select count(*)::int n from public.${table}`), table).toBe(expected);
    }
    expect(await asN(U.superAdmin, `select count(*)::int n from student where student_number like 'DEMO-%'`)).toBe(3);
  });

  it('hides the demo tenant from the users of the other organisation', async () => {
    for (const sub of [U.registrar1, U.student1, U.finance1]) {
      expect(await asN(sub, `select count(*)::int n from student where student_number like 'DEMO-%'`), sub).toBe(0);
      expect(await asN(sub, `select count(*)::int n from student_attendance`), sub).toBe(0);
      expect(await asN(sub, `select count(*)::int n from student_course_result`), sub).toBe(0);
      expect(await asN(sub, `select count(*)::int n from student_term_result`), sub).toBe(0);
      expect(await asN(sub, `select count(*)::int n from student_fee_assessment`), sub).toBe(0);
      expect(await asN(sub, `select count(*)::int n from student_activity`), sub).toBe(0);
      expect(await asN(sub, `select count(*)::int n from staff_activity`), sub).toBe(0);
      expect(await asN(sub, `select count(*)::int n from announcement`), sub).toBe(0);
    }
  });
});
