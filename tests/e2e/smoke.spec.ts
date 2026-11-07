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
  '/staff-profile',
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
});
