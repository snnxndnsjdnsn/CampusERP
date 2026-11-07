import { chromium } from '@playwright/test';
import fs from 'node:fs';
import path from 'node:path';

/**
 * Sign in once for the whole run.
 *
 * Supabase throttles the password grant endpoint, so a suite that signs in
 * once per test runs into `Request rate limit reached` after a few dozen
 * tests. The session is therefore created **once** here and handed to the
 * tests as a storage state - the same cookies and local storage the browser
 * would have after a real sign-in.
 *
 * The credentials come from the environment, never from the repository:
 *
 *     SIMS_TEST_EMAIL      the account to sign in with
 *     SIMS_TEST_PASSWORD   its password
 *
 * Without them nothing is written and the signed-in suite skips itself.
 *
 * The web server is already running when this runs: Playwright starts the
 * plugin tasks (the web server among them) before the global setup.
 */

export const EMAIL = process.env.SIMS_TEST_EMAIL ?? '';
export const PASSWORD = process.env.SIMS_TEST_PASSWORD ?? '';
export const STORAGE_STATE = path.join('playwright', '.auth', 'sims.json');

/** How many times to try before giving up, and how long to wait between tries. */
const ATTEMPTS = 5;
const BACKOFF_MS = 20_000;

export default async function globalSetup() {
  if (!EMAIL || !PASSWORD) return;

  const baseURL = process.env.PLAYWRIGHT_BASE_URL ?? 'http://127.0.0.1:3000';
  const browser = await chromium.launch();

  try {
    const context = await browser.newContext({ baseURL });
    const page = await context.newPage();

    for (let attempt = 1; attempt <= ATTEMPTS; attempt += 1) {
      await page.goto('/login');
      await page.getByLabel('Email').fill(EMAIL);
      await page.getByLabel('Password').fill(PASSWORD);
      await page.getByRole('button', { name: 'Sign in' }).click();

      try {
        await page.waitForURL(/\/dashboard/, { timeout: 30_000 });
        break;
      } catch {
        const alert = page.locator('[role="alert"]').first();
        const message = ((await alert.textContent().catch(() => '')) ?? '').trim();

        if (!/rate limit/i.test(message) || attempt === ATTEMPTS) {
          throw new Error(`sign in failed: ${message || 'the dashboard never opened'}`);
        }

        // The Auth endpoint is throttling us. Wait for the window to refill.
        process.stdout.write(
          `  auth rate limited, waiting ${BACKOFF_MS / 1000}s (attempt ${attempt}/${ATTEMPTS})\n`,
        );
        await page.waitForTimeout(BACKOFF_MS);
      }
    }

    fs.mkdirSync(path.dirname(STORAGE_STATE), { recursive: true });
    await context.storageState({ path: STORAGE_STATE });
    process.stdout.write(`  signed in, storage state written to ${STORAGE_STATE}\n`);
    await context.close();
  } finally {
    await browser.close();
  }
}
