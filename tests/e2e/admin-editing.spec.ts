import { expect, test, type Locator, type Page } from '@playwright/test';
import { waitForContent } from './support/content';

/**
 * The six module screens that gained an editing surface.
 *
 * Every screen renders the same `AdminTableEditor` panel, and the panel only
 * offers the tables the signed-in user actually holds a write permission for.
 * The list below is what the panel has to offer a SUPER_ADMIN - the table
 * names are the ones the pages pass to the editor, the order is irrelevant.
 */
const SCREENS = [
  {
    route: '/calendar',
    tables: ['academic_year', 'academic_term', 'semester', 'time_slot'],
  },
  {
    route: '/curriculum',
    tables: ['curriculum_scheme', 'curriculum_course'],
  },
  {
    route: '/courses',
    tables: ['course_catalog', 'course_category'],
  },
  {
    route: '/students',
    tables: ['student', 'student_programme_enrolment'],
  },
  {
    route: '/registration',
    tables: [
      'programme_term_offering',
      'course_offering',
      'class_section',
      'student_term_registration',
    ],
  },
  {
    route: '/timetable',
    tables: ['time_slot', 'room'],
  },
];

/** Open the Manage panel of a screen and wait for its table picker. */
async function openManagePanel(page: Page): Promise<Locator> {
  const editor = page.getByTestId('admin-editor');
  await expect(editor).toBeVisible();

  await editor.getByRole('button', { name: 'Open' }).click();

  const picker = editor.locator('#admin-table');
  await expect(picker).toBeVisible();
  return editor;
}

/** The table names the picker offers. */
async function offeredTables(picker: Locator): Promise<string[]> {
  const values = await picker
    .locator('option')
    .evaluateAll((options) => options.map((option) => (option as HTMLOptionElement).value));
  return values.sort();
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
    test(`${screen.route} offers the Manage panel for ${screen.tables.join(', ')}`, async ({ page }) => {
      await page.goto(screen.route, { waitUntil: 'domcontentloaded' });
      await waitForContent(page);

      const editor = await openManagePanel(page);
      const picker = editor.locator('#admin-table');

      expect(await offeredTables(picker)).toEqual([...screen.tables].sort());
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
});
