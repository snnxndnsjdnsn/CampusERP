#!/usr/bin/env node
/**
 * One command that runs every check in the repository.
 *
 * Read-only by default: it never writes to the live Supabase project and never
 * touches git. The only thing it writes is the local build output.
 *
 *   node tools/verify.mjs            # everything
 *   node tools/verify.mjs --fast     # skip the production build
 *   node tools/verify.mjs --no-e2e   # skip the signed-in end-to-end suite
 *
 * Set SUPABASE_DB_PASSWORD before running if you want the live-database checks
 * (the nav/RBAC matrix and the catalogue diff) to run; they are skipped with a
 * clear message when it is missing.
 *
 * Set SIMS_TEST_EMAIL and SIMS_TEST_PASSWORD to run the signed-in end-to-end
 * suite. It needs a production build, so it is skipped in `--fast` mode and
 * when the credentials are missing.
 */

import { spawnSync } from 'node:child_process';
import process from 'node:process';

const FAST = process.argv.includes('--fast');
const NO_E2E = process.argv.includes('--no-e2e');

const results = [];

function run(label, command, args, opts = {}) {
  const started = Date.now();
  const res = spawnSync(command, args, {
    stdio: 'inherit',
    shell: process.platform === 'win32',
    cwd: process.cwd(),
    env: process.env,
    ...opts,
  });
  const code = res.status ?? 1;
  results.push({ label, code, ms: Date.now() - started });
  return code === 0;
}

function hasPassword() {
  return Boolean(process.env.SUPABASE_DB_PASSWORD);
}

function hasTestAccount() {
  return Boolean(process.env.SIMS_TEST_EMAIL && process.env.SIMS_TEST_PASSWORD);
}

const steps = [
  ['typecheck', 'npx', ['tsc', '--noEmit']],
  ['lint', 'npx', ['eslint', 'src', 'tests']],
  ['unit tests', 'npx', ['vitest', 'run', 'tests/unit']],
  ['database tests', 'npx', ['vitest', 'run', 'tests/db']],
];

if (!FAST) steps.push(['production build', 'npx', ['next', 'build']]);

let failed = 0;
for (const [label, cmd, args] of steps) {
  process.stdout.write(`\n=== ${label} ===\n`);
  if (!run(label, cmd, args)) failed++;
}

// --- live-database checks (read-only) ---------------------------------------
if (hasPassword()) {
  process.stdout.write('\n=== nav / RBAC connectivity (live, read-only) ===\n');
  if (!run('nav-rbac', 'python', ['tools/validate/nav_rbac_connectivity.py'])) failed++;

  process.stdout.write('\n=== seed column validation (live, read-only) ===\n');
  if (!run('seed-columns', 'python', ['tools/validate/seed_columns.py'])) failed++;
} else {
  console.log('\n[skip] live-database checks: SUPABASE_DB_PASSWORD is not set');
}

// --- documentation / catalogue checks ---------------------------------------
const local = [
  ['role matrix --check', 'node', ['tools/validate/role_matrix.mjs', '--check']],
  ['schema doc --check', 'node', ['tools/validate/schema_doc.mjs', '--check']],
  ['catalogue --check', 'node', ['tools/validate/catalogue.mjs', '--check']],
  ['catalogue contract', 'python', ['tools/compare_catalogue.py']],
  ['apply plan (dry run)', 'python', ['tools/apply_migrations.py']],
  ['demo seed plan (dry run)', 'python', ['tools/apply_demo_seed.py']],
];

for (const [label, cmd, args] of local) {
  process.stdout.write(`\n=== ${label} ===\n`);
  if (!run(label, cmd, args)) failed++;
}

// --- signed-in end-to-end suite ----------------------------------------------
// The suite opens every route with a real session. It needs a production
// build (the Playwright web server runs `next start`) and a test account, so
// it is opt-in: without the credentials it is skipped, not failed.
if (NO_E2E) {
  console.log('\n[skip] signed-in end-to-end suite: --no-e2e');
} else if (FAST) {
  console.log('\n[skip] signed-in end-to-end suite: --fast skips the production build');
} else if (!hasTestAccount()) {
  console.log(
    '\n[skip] signed-in end-to-end suite: SIMS_TEST_EMAIL and SIMS_TEST_PASSWORD are not set',
  );
} else {
  process.stdout.write('\n=== signed-in end-to-end suite ===\n');
  if (!run('e2e smoke', 'npx', ['playwright', 'test'])) failed++;
}

process.stdout.write('\n=== SUMMARY ===\n');
for (const r of results) {
  process.stdout.write(`${r.code === 0 ? 'PASS' : 'FAIL'}  ${r.label}  (${(r.ms / 1000).toFixed(1)}s)\n`);
}
process.stdout.write(failed === 0 ? '\nAll checks passed.\n' : `\n${failed} check(s) failed.\n`);
process.exit(failed === 0 ? 0 : 1);
