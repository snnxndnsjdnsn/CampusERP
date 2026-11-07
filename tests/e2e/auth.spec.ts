import { expect, test } from '@playwright/test';

/**
 * Route protection.
 *
 * The proxy sends an anonymous visitor to `/login` and remembers where they were
 * going. These tests assert that behaviour without needing a real account.
 */

const PROTECTED = ['/dashboard', '/students', '/employees', '/finance', '/admin/users', '/settings'];

test.describe('route protection', () => {
  for (const path of PROTECTED) {
    test(`an anonymous visitor is redirected from ${path} to the sign-in page`, async ({ page }) => {
      await page.goto(path);
      await expect(page).toHaveURL(/\/login/);
    });
  }

  test('the sign-in page is reachable without a session', async ({ page }) => {
    await page.goto('/login');
    await expect(page).toHaveURL(/\/login/);
    await expect(page.getByRole('heading', { name: 'SIMS' })).toBeVisible();
  });

  test('the sign-in page remembers where the visitor was going', async ({ page }) => {
    await page.goto('/students');
    await expect(page).toHaveURL(/\/login\?next=%2Fstudents/);
  });

  test('the forgot-password page is reachable without a session', async ({ page }) => {
    await page.goto('/forgot-password');
    await expect(page).toHaveURL(/\/forgot-password/);
    await expect(page.getByRole('heading', { name: /reset your password/i })).toBeVisible();
  });
});
