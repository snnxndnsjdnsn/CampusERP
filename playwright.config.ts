import { defineConfig, devices } from '@playwright/test';
import path from 'node:path';

const baseURL = process.env.PLAYWRIGHT_BASE_URL ?? 'http://127.0.0.1:3000';

const EMAIL = process.env.SIMS_TEST_EMAIL ?? '';
const PASSWORD = process.env.SIMS_TEST_PASSWORD ?? '';

/**
 * The signed-in suite only exists when a test account is configured.
 *
 * Without `SIMS_TEST_EMAIL` / `SIMS_TEST_PASSWORD` there is nothing to sign
 * in with, so the signed-in project is left out entirely and the tests that
 * need it skip themselves.
 */
const signedIn = Boolean(EMAIL && PASSWORD);

/** Written by `tests/e2e/global-setup.ts` - one password grant for the run. */
const STORAGE_STATE = path.join('playwright', '.auth', 'sims.json');

/**
 * How many browsers may open a page at the same time.
 *
 * Every page load reads the caller's context from the database before it
 * renders anything, and the shared Supabase project answers those reads through
 * a pooler with a limited number of backends. Playwright's default - half the
 * logical processors - puts eight pages on a sixteen-core machine, and the
 * pooler then queues them long enough for the database's two-minute statement
 * timeout to cancel the read. The page answers 500 and the suite fails on a
 * healthy application.
 *
 * Four workers keep the suite inside the pooler's capacity and still finish in
 * about half a minute. `PLAYWRIGHT_WORKERS` overrides it; CI runs one worker
 * because it is shared with everything else.
 */
const WORKERS = Number(process.env.PLAYWRIGHT_WORKERS ?? 4);

/**
 * End-to-end tests.
 *
 * The suite covers route protection: an anonymous visitor must be sent to the
 * sign-in page, and the `next` parameter must survive the redirect so the user
 * lands on the page they asked for after signing in.
 *
 * It also covers the signed-in application: `smoke.spec.ts` opens every route
 * with a real session. That session is created **once** in the global setup
 * and handed to the tests as a storage state, because Supabase throttles the
 * password grant endpoint and a suite that signs in per test runs into
 * `Request rate limit reached`.
 */
export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : WORKERS,
  reporter: process.env.CI ? 'github' : 'list',
  globalSetup: signedIn ? './tests/e2e/global-setup.ts' : undefined,
  use: {
    baseURL,
    trace: 'on-first-retry',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
      // The route sweep runs in its own project so that the anonymous tests
      // keep starting without a session.
      testIgnore: signedIn ? '**/smoke.spec.ts' : undefined,
    },
    ...(signedIn
      ? [
          {
            name: 'chromium-signed-in',
            use: { ...devices['Desktop Chrome'], storageState: STORAGE_STATE },
            testMatch: '**/smoke.spec.ts',
          },
        ]
      : []),
  ],
  webServer: process.env.PLAYWRIGHT_SKIP_WEBSERVER
    ? undefined
    : {
        command: 'npm run start',
        url: baseURL,
        reuseExistingServer: !process.env.CI,
        timeout: 120_000,
      },
});
