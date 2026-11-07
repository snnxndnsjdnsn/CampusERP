import { expect, test } from '@playwright/test';

/**
 * The sign-in form.
 *
 * This test runs in the **anonymous** project: it starts with no session and
 * drives the real form, exactly as a person would. The route sweep in
 * `smoke.spec.ts` then reuses that session through the storage state, so the
 * whole run needs only one password grant.
 *
 * The credentials come from the environment, never from the repository:
 *
 *     SIMS_TEST_EMAIL      the account to sign in with
 *     SIMS_TEST_PASSWORD   its password
 *
 * Without them the test is skipped rather than failed.
 */

const EMAIL = process.env.SIMS_TEST_EMAIL ?? '';
const PASSWORD = process.env.SIMS_TEST_PASSWORD ?? '';

test.describe('sign-in', () => {
  test.skip(
    !EMAIL || !PASSWORD,
    'set SIMS_TEST_EMAIL and SIMS_TEST_PASSWORD to run the signed-in tests',
  );

  test('the form signs in and lands on the dashboard', async ({ page }) => {
    await page.goto('/login');
    await page.getByLabel('Email').fill(EMAIL);
    await page.getByLabel('Password').fill(PASSWORD);
    await page.getByRole('button', { name: 'Sign in' }).click();

    await page.waitForURL(/\/dashboard/, { timeout: 60_000 });
    await expect(page.locator('main')).toContainText(/welcome/i);
  });

  test('a wrong password is refused', async ({ page }) => {
    await page.goto('/login');
    await page.getByLabel('Email').fill(EMAIL);
    await page.getByLabel('Password').fill('this-is-not-the-password');
    await page.getByRole('button', { name: 'Sign in' }).click();

    await expect(page.locator('[role="alert"]').first()).toBeVisible({ timeout: 30_000 });
    await expect(page).toHaveURL(/\/login/);
  });
});
