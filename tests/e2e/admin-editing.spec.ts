import { expect, test, type Locator, type Page } from '@playwright/test';
import { waitForContent } from './support/content';

/**
 * The editing surface of the module screens.
 *
 * Every screen renders the same `AdminTableEditor` panel.  The screen passes
 * its module code to the panel, and the panel offers every catalogue table
 * that belongs to one of those modules - and only the ones the signed-in user
 * actually holds a write permission for.
 *
 * The table lists below are the catalogue of migration 067, which was derived
 * from the live row level policies: 127 tables, each with the permission codes
 * its policies use and the screens it is edited on.
 */
const MODULE_TABLES: Record<string, string[]> = {
  ACADEMIC_CALENDAR: [
    'academic_term',
    'academic_year',
    'calendar',
    'calendar_term_schedule',
    'calendar_week',
    'calendar_week_day',
    'holiday',
    'semester',
    'time_slot'
  ],
  ADMISSION: [
    'enrolment_status_history',
    'student_programme_enrolment'
  ],
  ASSESSMENT: [
    'assessment_component',
    'assessment_event'
  ],
  ATTENDANCE: [
    'attendance_status',
    'class_section',
    'class_session'
  ],
  COMMUNICATION: [
    'announcement_type'
  ],
  CURRICULUM: [
    'course_catalog',
    'course_category',
    'course_prerequisite',
    'curriculum_course',
    'curriculum_scheme',
    'programme',
    'semester'
  ],
  DOCUMENT: [
    'certificate_request',
    'certificate_type',
    'student_document',
    'student_exit'
  ],
  EMPLOYEE: [
    'awarding_body',
    'awarding_body_type',
    'designation',
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
    'external_agency',
    'previous_organization',
    'previous_organization_type',
    'qualification_level',
    'staff_category',
    'staff_type',
    'study_mode'
  ],
  FEEDBACK: [
    'feedback_choice',
    'feedback_cycle',
    'feedback_question',
    'feedback_question_category',
    'feedback_questionnaire',
    'feedback_questionnaire_item'
  ],
  GRIEVANCE: [
    'grievance_category'
  ],
  IAM: [
    'admission_category',
    'blood_group',
    'caste',
    'country',
    'document_type',
    'gender',
    'religion',
    'social_category',
    'state',
    'sub_caste'
  ],
  INSTITUTION: [
    'building',
    'building_document',
    'campus',
    'department',
    'facility_type',
    'floor',
    'floor_facility',
    'land',
    'land_document',
    'programme',
    'programme_specialization',
    'room',
    'room_facility',
    'university'
  ],
  REGISTRATION: [
    'academic_term',
    'academic_year',
    'class_batch',
    'class_section',
    'course_offering',
    'course_offering_section',
    'course_offering_section_student',
    'curriculum_scheme',
    'programme',
    'programme_term_offering',
    'semester',
    'student_course_registration',
    'student_term_registration'
  ],
  RESULT: [
    'grade_rule',
    'grade_scale'
  ],
  STAFF_PROFILE: [
    'activity_evidence_requirement',
    'activity_type',
    'approval_status',
    'award_category',
    'cocurricular_category',
    'conference_activity_indexing',
    'conference_contribution_type',
    'conference_event',
    'confidentiality_level',
    'event_mode',
    'evidence_document_tag',
    'evidence_tag',
    'evidence_type',
    'external_organization',
    'external_organization_type',
    'extracurricular_category',
    'funding_agency',
    'funding_type',
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
    'professional_contribution_type',
    'publication_type',
    'publisher',
    'research_project_financial_utilization',
    'research_status',
    'research_supervision',
    'role_type',
    'training_program_type',
    'verification_status'
  ],
  STUDENT: [
    'student',
    'student_activity_evidence_requirement',
    'student_activity_type',
    'student_address',
    'student_course_registration',
    'student_entrance_exam',
    'student_parent_guardian',
    'student_previous_education',
    'student_programme_enrolment',
    'student_residence',
    'student_term_registration'
  ],
  TIMETABLE: [
    'course_offering',
    'course_offering_section',
    'faculty_course_assignment',
    'room',
    'time_slot',
    'timetable_session'
  ],
};

/**
 * The screens that carry the panel, and the module codes they pass to it.
 *
 * A screen with more than one module offers the tables of all of them.
 */
const SCREENS = [
  { route: '/structure', modules: ['INSTITUTION'] },
  { route: '/calendar', modules: ['ACADEMIC_CALENDAR'] },
  { route: '/curriculum', modules: ['CURRICULUM'] },
  { route: '/courses', modules: ['CURRICULUM'] },
  { route: '/students', modules: ['STUDENT'] },
  { route: '/students/1/records', modules: ['STUDENT'] },
  { route: '/students/1/documents', modules: ['STUDENT'] },
  { route: '/employees', modules: ['EMPLOYEE'] },
  { route: '/employees/1/records', modules: ['EMPLOYEE'] },
  { route: '/employees/1/hr', modules: ['EMPLOYEE'] },
  { route: '/admissions', modules: ['ADMISSION'] },
  { route: '/registration', modules: ['REGISTRATION'] },
  { route: '/timetable', modules: ['TIMETABLE'] },
  { route: '/attendance', modules: ['ATTENDANCE'] },
  { route: '/assessment', modules: ['ASSESSMENT', 'RESULT'] },
  { route: '/results/grades', modules: ['RESULT'] },
  { route: '/feedback', modules: ['FEEDBACK'] },
  { route: '/grievances', modules: ['GRIEVANCE'] },
  { route: '/certificates', modules: ['DOCUMENT'] },
  { route: '/requests', modules: ['DOCUMENT'] },
  { route: '/my-documents', modules: ['DOCUMENT'] },
  { route: '/announcements', modules: ['COMMUNICATION'] },
  { route: '/announcements/manage', modules: ['COMMUNICATION'] },
  { route: '/my-results', modules: ['RESULT'] },
  { route: '/my-hr', modules: ['EMPLOYEE'] },
  { route: '/activities', modules: ['STUDENT'] },
  { route: '/staff-profile', modules: ['STAFF_PROFILE'] },
  { route: '/schema/36', modules: ['IAM', 'STAFF_PROFILE'] },
];

/** The tables a screen offers: the union of the tables of its modules. */
function expectedTables(modules: string[]): string[] {
  return [...new Set(modules.flatMap((module) => MODULE_TABLES[module] ?? []))].sort();
}

/**
 * Open the Manage panel of a screen.
 *
 * The panel only draws a table picker when the screen offers more than one
 * table.  A module with a single table - `GRIEVANCE` and `COMMUNICATION` -
 * goes straight to that table, so the picker is optional here.
 */
async function openManagePanel(page: Page): Promise<Locator> {
  const editor = page.getByTestId('admin-editor');
  await expect(editor).toBeVisible();

  await editor.getByRole('button', { name: 'Open' }).click();
  return editor;
}

/**
 * The table names the panel offers.
 *
 * With a picker the options are the tables; without one the panel has exactly
 * one table and the picker is not drawn, so the table is read from the panel's
 * own caption instead.
 */
async function offeredTables(editor: Locator): Promise<string[]> {
  // The toolbar only appears once the table's shape has loaded.
  await expect(editor.getByRole('button', { name: 'Add row' })).toBeVisible();

  const picker = editor.locator('#admin-table');
  if ((await picker.count()) > 0) {
    const values = await picker
      .locator('option')
      .evaluateAll((options) => options.map((option) => (option as HTMLOptionElement).value));
    return values.sort();
  }

  const caption = await editor.locator('code').first().textContent();
  return caption ? [caption.trim()] : [];
}

/**
 * Narrow the table down to the rows that carry `code`.
 *
 * The table itself disappears when the filter matches nothing - the panel
 * shows an empty state instead - so the locator is returned without waiting
 * for it to be visible.
 */
async function filterTo(editor: Locator, code: string): Promise<Locator> {
  await editor.locator('#admin-filter').fill(code);
  return editor.getByTestId('admin-editor-table');
}

test.describe('admin editing', () => {
  // The panel reads the caller's permissions from the database and then loads
  // the rows through PostgREST, so a cold server needs a moment.
  test.describe.configure({ timeout: 60_000 });

  test.skip(
    !process.env.SIMS_TEST_EMAIL || !process.env.SIMS_TEST_PASSWORD,
    'set SIMS_TEST_EMAIL and SIMS_TEST_PASSWORD to run the admin editing test',
  );

  for (const screen of SCREENS) {
    test(`${screen.route} offers the Manage panel for ${screen.modules.join(', ')}`, async ({ page }) => {
      await page.goto(screen.route, { waitUntil: 'domcontentloaded' });
      await waitForContent(page);

      const editor = await openManagePanel(page);

      expect(await offeredTables(editor)).toEqual(expectedTables(screen.modules));
    });
  }

  /**
   * The whole round trip on the academic calendar.
   *
   * The panel is the only thing that writes: the form is generated from the
   * column description the database hands out, the payload goes to
   * `admin_table_save`, and the refusal of the database has to surface in the
   * panel instead of disappearing.
   */
  test('the Manage panel adds, edits and deletes an academic year', async ({ page }) => {
    // `academic_year.year_code` is `varchar(9)`, so the code is "E2E" plus six
    // digits. The second code differs in its last digit only.
    const stamp = Date.now().toString().slice(-6);
    const code = `E2E${stamp}`;
    const edited = `E2E${stamp.slice(0, 5)}${(Number(stamp[5]) + 1) % 10}`;

    await page.goto('/calendar', { waitUntil: 'domcontentloaded' });
    await waitForContent(page);

    const editor = await openManagePanel(page);
    await editor.locator('#admin-table').selectOption('academic_year');

    // --- add -------------------------------------------------------------------------------
    await editor.getByRole('button', { name: 'Add row' }).click();

    const form = editor.getByTestId('admin-editor-form');
    await expect(form).toBeVisible();

    await form.getByLabel('year code').fill(code);
    await form.getByLabel('start date').fill('2027-06-01');
    await form.getByLabel('end date').fill('2028-05-31');

    await form.getByRole('button', { name: 'Save row' }).click();
    await expect(editor.getByTestId('admin-editor-notice')).toHaveText('Row added.');

    // --- the database refuses a duplicate ----------------------------------------------------
    await editor.getByRole('button', { name: 'Add row' }).click();
    await form.getByLabel('year code').fill(code);
    await form.getByLabel('start date').fill('2027-06-01');
    await form.getByLabel('end date').fill('2028-05-31');
    await form.getByRole('button', { name: 'Save row' }).click();

    await expect(editor.getByRole('alert')).toContainText('already recorded');

    // The refusal leaves the form open so the row can be corrected.
    await form.getByRole('button', { name: 'Cancel' }).first().click();
    await expect(form).toBeHidden();

    // --- edit -------------------------------------------------------------------------------
    let table = await filterTo(editor, code);
    let row = table.locator('tbody tr').filter({ hasText: code });
    await expect(row).toHaveCount(1);

    await row.getByRole('button', { name: 'Edit' }).click();
    await expect(form).toBeVisible();

    await form.getByLabel('year code').fill(edited);
    await form.getByRole('button', { name: 'Save row' }).click();
    await expect(editor.getByTestId('admin-editor-notice')).toHaveText('Row updated.');

    // --- delete -----------------------------------------------------------------------------
    table = await filterTo(editor, edited);
    row = table.locator('tbody tr').filter({ hasText: edited });
    await expect(row).toHaveCount(1);

    await row.getByRole('button', { name: 'Delete' }).click();
    await expect(editor.getByTestId('admin-editor-notice')).toHaveText('Row deleted.');

    table = await filterTo(editor, edited);
    await expect(table.locator('tbody tr').filter({ hasText: edited })).toHaveCount(0);
  });

  /**
   * The Employees screen is the case that was missing: it has to offer the
   * employee master and the HR tables around it.
   */
  test('the Employees screen manages the employee master', async ({ page }) => {
    await page.goto('/employees', { waitUntil: 'domcontentloaded' });
    await waitForContent(page);

    const editor = await openManagePanel(page);

    const tables = await offeredTables(editor);
    expect(tables).toContain('employee');
    expect(tables).toContain('employee_qualification');
    expect(tables).toContain('employee_assignment');
    expect(tables).toContain('employee_document');

    // The employee master has to be reachable.
    await editor.locator('#admin-table').selectOption('employee');
    await expect(editor.getByTestId('admin-editor-table')).toBeVisible();
  });
});
