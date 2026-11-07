import { expect, test, type Page } from '@playwright/test';

/**
 * Signed-in smoke test.
 *
 * Every route of the application is opened with a real SUPER_ADMIN session and
 * three things are asserted:
 *
 *  1. the page leaves the `Loading…` state - the server streamed the shell but
 *     the page content never arrived;
 *  2. the page has real content in `<main>`;
 *  3. nothing was written to the browser console as an error.
 *
 * The session comes from the storage state that `tests/e2e/global-setup.ts`
 * writes: one password grant for the whole run, because Supabase throttles
 * the token endpoint and a suite that signs in per test runs into
 * `Request rate limit reached`.
 *
 * The credentials come from the environment, never from the repository:
 *
 *     SIMS_TEST_EMAIL      the account to sign in with
 *     SIMS_TEST_PASSWORD   its password
 *
 * Without them the suite is skipped rather than failed, so a checkout without
 * a test account still has a green build.
 */

/** Every route the sidebar can reach, plus the deep links. */
const ROUTES = [
  '/dashboard',
  '/students',
  '/employees',
  '/structure',
  '/calendar',
  '/curriculum',
  '/courses',
  '/admissions',
  '/registration',
  '/timetable',
  '/attendance',
  '/assessment',
  '/results',
  '/results/grades',
  '/feedback',
  '/mentoring',
  '/grievances',
  '/certificates',
  '/announcements',
  '/announcements/manage',
  '/admin/users',
  '/admin/reference',
  '/admin/reference/gender',
  '/audit',
  '/audit/logins',
  '/finance',
  '/finance/structures',
  '/schema/18',
  '/staff-profile',
  // Schema modules 20 to 34 - the staff-profile research sub-modules. Each is
  // an address inside the staff-profile screen.
  '/staff-profile/activity',
  '/staff-profile/publication',
  '/staff-profile/conference',
  '/staff-profile/development',
  '/staff-profile/internship',
  '/staff-profile/research',
  '/staff-profile/funded-research',
  '/staff-profile/consultancy',
  '/staff-profile/co-curricular',
  '/staff-profile/extra-curricular',
  '/staff-profile/award',
  '/staff-profile/membership',
  '/staff-profile/contribution',
  '/staff-profile/evidence',
  '/staff-profile/evidence-requirements',
  '/schema/35',
  '/schema/36',
  '/reporting',
  '/schema/38',
  '/schema/39',
  '/activities',
  '/my-results',
  '/my-hr',
  '/my-documents',
  '/notifications',
  '/requests',
  '/search',
  '/settings',
  '/mfa',
  '/admin/mfa-policy',
  '/admin/users/new',
  '/admin/users/3',
  '/students/1/records',
  '/students/1/documents',
  '/employees/1/hr',
  '/employees/1/records',
  '/audit/1',
  '/finance/account/1',
  '/finance/receipt/1',
];

/**
 * Wait until the page content has replaced the `Loading…` fallback.
 *
 * Next.js streams the page: the shell and the Suspense fallback arrive first,
 * the resolved content follows in a later chunk. So the test waits for the
 * **content** rather than for the fallback to disappear - at the moment the
 * document is parsed the fallback may not even be attached yet, and waiting
 * for it to vanish would pass on an empty page.
 *
 * React then reveals the streamed boundary with `requestAnimationFrame`. A
 * browser that is not painting - a background tab, a headless run that never
 * composites - never fires that callback, so the boundary stays pending even
 * though the server sent the content. When the content does not arrive in
 * time, the test flushes React's own reveal queue so the assertion stays
 * about the application and not about the compositor.
 */
async function waitForContent(page: Page): Promise<void> {
  const main = page.locator('main');

  const hasContent = async () => {
    const text = (await main.innerText().catch(() => '')).trim();
    return text.length > 20 && !text.startsWith('Loading…');
  };

  try {
    await expect.poll(hasContent, { timeout: 15_000, intervals: [200] }).toBe(true);
    return;
  } catch {
    // The frame never came: flush React's queued reveal and try again.
    await page.evaluate(() => {
      const w = window as unknown as {
        $RV?: (queue: unknown[]) => void;
        $RB?: unknown[];
      };
      if (typeof w.$RV === 'function' && w.$RB && w.$RB.length) w.$RV(w.$RB);
    });
    await expect.poll(hasContent, { timeout: 15_000, intervals: [200] }).toBe(true);
  }
}

test.describe('signed-in smoke test', () => {
  // The route sweep waits for the streamed content, which can take a while on
  // a cold server.
  test.describe.configure({ timeout: 60_000 });

  test.skip(
    !process.env.SIMS_TEST_EMAIL || !process.env.SIMS_TEST_PASSWORD,
    'set SIMS_TEST_EMAIL and SIMS_TEST_PASSWORD to run the signed-in smoke test',
  );

  for (const route of ROUTES) {
    test(`${route} renders for a signed-in administrator`, async ({ page }) => {
      const consoleErrors: string[] = [];
      page.on('console', (message) => {
        if (message.type() === 'error') consoleErrors.push(message.text());
      });
      page.on('pageerror', (error) => consoleErrors.push(error.message));

      const response = await page.goto(route, { waitUntil: 'domcontentloaded' });
      expect(response?.status(), `${route} must answer with 200`).toBe(200);

      await waitForContent(page);

      const main = page.locator('main');
      await expect(main).toBeVisible();
      const text = (await main.innerText()).trim();
      expect(text.length, `${route} must render content`).toBeGreaterThan(20);
      expect(text.startsWith('Loading…'), `${route} must not stay in the loading state`).toBe(false);

      expect(consoleErrors, `${route} must not log console errors`).toEqual([]);
    });
  }

  // `/no-access` lives outside the application shell, so it has no `<main>`.
  test('/no-access explains that the sign-in has no SIMS account', async ({ page }) => {
    const response = await page.goto('/no-access', { waitUntil: 'domcontentloaded' });
    expect(response?.status(), '/no-access must answer with 200').toBe(200);
    await expect(page.getByRole('heading', { name: 'No SIMS account' })).toBeVisible();
  });

  // An unknown staff sub-module is not a page.
  //
  // The **UI** is the assertion, not the status code. Next.js returns 404 only
  // when `notFound()` is thrown before streaming starts; this app streams the
  // shell first (the `(app)` segment has a `loading.tsx`), so the status is
  // already committed as 200 and the not-found page is rendered inside it.
  // That is the framework's documented behaviour and it is the same for every
  // route in the application.
  test('/staff-profile/<unknown> renders the not-found page', async ({ page }) => {
    await page.goto('/staff-profile/not-a-section', { waitUntil: 'domcontentloaded' });
    await expect(page.getByRole('heading', { name: 'Page not found' })).toBeVisible();
  });

  /**
   * The staff group carries schema modules 20 to 34 as sub-modules.
   *
   * They are drawn indented under the group, and the deepest match wins for
   * the active state: `/staff-profile/publication` marks the sub-module, not
   * `/staff-profile`.
   */
  test('the sidebar lists the staff sub-modules 20 to 34 and marks the deepest one active', async ({ page }) => {
    await page.goto('/staff-profile/publication', { waitUntil: 'domcontentloaded' });
    await waitForContent(page);

    const sidebar = page.locator('aside[aria-label="Primary"]');
    await expect(sidebar).toBeVisible();

    // Every sub-module is drawn, labelled with its schema module number.
    for (const number of ['20', '21', '22', '23', '24', '25', '26', '27', '28', '29', '30', '31', '32', '33', '34']) {
      await expect(
        sidebar.getByRole('link', { name: new RegExp(`^${number} · `) }),
        `the sidebar must show sub-module ${number}`,
      ).toHaveCount(1);
    }

    // The deepest match wins: the sub-module is current, the parent is not.
    const child = sidebar.getByRole('link', { name: /^21 · / });
    await expect(child).toHaveAttribute('aria-current', 'page');

    const parent = sidebar.getByRole('link', { name: 'Staff profile', exact: true });
    await expect(parent).not.toHaveAttribute('aria-current', 'page');

    // The breadcrumb names the sub-module too, not its parent.
    const crumb = page.locator('nav[aria-label="Breadcrumb"]');
    await expect(crumb).toContainText('21 · Journals and journal publications');
    await expect(crumb).not.toContainText('Staff profile');
  });

  /**
   * The six screens that were missing until now.
   *
   * Each of them is a schema module of its own, so the sidebar draws it as a
   * group labelled with the module number, and the screen that is open marks
   * its own item as the current one.
   */
  test('the sidebar lists the six new schema groups and marks the open one current', async ({ page }) => {
    await page.goto('/reporting', { waitUntil: 'domcontentloaded' });
    await waitForContent(page);

    const sidebar = page.locator('aside[aria-label="Primary"]');
    await expect(sidebar).toBeVisible();

    // Every new group is drawn, labelled with its schema module number.
    for (const label of [
      '18 · Performance indexes & storage',
      '35 · Seed reference data',
      '36 · Staff profile RBAC registration',
      '37 · Reporting & search views',
      '38 · Staff profile performance indexes',
      '39 · Data-integrity notes',
    ]) {
      await expect(
        sidebar.getByText(label, { exact: true }),
        `the sidebar must show the group ${label}`,
      ).toHaveCount(1);
    }

    // The open screen marks its own item as the current one.
    const current = sidebar.getByRole('link', { name: 'Reporting and search views', exact: true });
    await expect(current).toHaveAttribute('aria-current', 'page');
  });
});
