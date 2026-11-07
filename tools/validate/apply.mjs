/**
 * Apply check: rebuild the database from the migration set alone and compare the
 * result with the live Supabase catalogue.
 *
 *   node tools/validate/apply.mjs [--json] [--keep-going]
 *
 * The tool installs the Supabase stub (`tests/db/supabase-stub.ts`), applies every
 * file in `supabase/migrations/` in sorted order to a fresh embedded PostgreSQL
 * and then compares the object counts with `tools/catalogue/expected_catalogue.json`
 * (the numbers the live project `khqqfgqvwdxlqkncwtmh` has today).
 *
 * It exits non-zero when a migration fails to apply or when a count differs.
 */
import fs from 'node:fs';
import path from 'node:path';
import { applyMigrations, dumpCatalogue, ROOT } from './pg_catalogue.mjs';

const EXPECTED = path.join(ROOT, 'tools', 'catalogue', 'expected_catalogue.json');

/** Count the objects of one schema of a dumped catalogue. */
function schemaCounts(catalogue, schema) {
  const inSchema = (rows) => rows.filter((r) => r.schema === schema);
  return {
    tables: inSchema(catalogue.tables).length,
    views: inSchema(catalogue.views).length,
    functions: inSchema(catalogue.functions).length,
    triggers: inSchema(catalogue.triggers).length,
    policies: inSchema(catalogue.policies).length,
    rls_tables: inSchema(catalogue.tables).filter((t) => t.rls).length,
    indexes: inSchema(catalogue.indexes).length,
    sequences: inSchema(catalogue.sequences).length,
    domains: inSchema(catalogue.domains).length,
    enums: inSchema(catalogue.enums).length,
    composites: inSchema(catalogue.composites).length,
  };
}

/** Compare two count maps and return the keys that differ. */
function diff(expected, actual) {
  const out = [];
  for (const key of Object.keys(expected)) {
    if (actual[key] !== expected[key]) out.push({ key, expected: expected[key], actual: actual[key] });
  }
  return out;
}

async function main() {
  const asJson = process.argv.includes('--json');
  const keepGoing = process.argv.includes('--keep-going');
  const expected = JSON.parse(fs.readFileSync(EXPECTED, 'utf8'));

  const applied = [];
  let failure = null;
  let db = null;
  try {
    const result = await applyMigrations({
      onFile: (f) => {
        applied.push(f);
        if (!asJson) process.stdout.write(`  applying ${f}\n`);
      },
    });
    db = result.db;
  } catch (err) {
    failure = err;
  }

  if (failure) {
    const message = failure?.message ?? String(failure);
    console.error(`\nFAILED while applying ${applied[applied.length - 1] ?? '(stub)'}`);
    console.error(message);
    if (!asJson) {
      console.error('\nThe migration set does not apply cleanly to a fresh database.');
    }
    process.exit(1);
  }

  const catalogue = await dumpCatalogue(db);
  const actual = schemaCounts(catalogue, 'public');
  const actualPrivate = schemaCounts(catalogue, 'sims_private');

  const problems = [
    ...diff(expected.public, actual).map((d) => ({ scope: 'public', ...d })),
    ...diff(expected.sims_private, actualPrivate).map((d) => ({ scope: 'sims_private', ...d })),
  ];

  // The seeded reference rows have to be there as well.
  const rowProblems = [];
  for (const [key, n] of Object.entries(expected.row_counts)) {
    const got = catalogue.row_counts[key];
    if (got !== n) rowProblems.push({ table: key, expected: n, actual: got ?? null });
  }

  const summary = {
    applied_files: applied.length,
    counts: {
      public: actual,
      sims_private: actualPrivate,
      total: catalogue.counts,
    },
    problems,
    row_problems: rowProblems,
  };

  if (asJson) {
    console.log(JSON.stringify(summary, null, 1));
  } else {
    console.log('');
    console.log(
      `${actual.tables} tables, ${actual.views} views, ${actual.triggers} triggers, RLS on ${actual.rls_tables}`,
    );
    console.log(
      `sims_private: ${actualPrivate.tables} tables, ${actualPrivate.functions} functions, RLS on ${actualPrivate.rls_tables}`,
    );
    console.log(
      `functions ${catalogue.counts.functions}, policies ${catalogue.counts.policies}, ` +
        `indexes ${catalogue.counts.indexes}, sequences ${catalogue.counts.sequences}, ` +
        `domains ${catalogue.counts.domains}, composites ${catalogue.counts.composites}`,
    );
    console.log(`${applied.length} migration files applied to a fresh database`);
    for (const p of problems) {
      console.error(`DIFF ${p.scope}.${p.key}: expected ${p.expected}, got ${p.actual}`);
    }
    for (const p of rowProblems) {
      console.error(`DIFF ${p.table}: expected ${p.expected} rows, got ${p.actual}`);
    }
    if (!problems.length && !rowProblems.length) {
      console.log('OK - the rebuilt database matches the live catalogue');
    } else {
      console.error(
        `FAILED - ${problems.length} object count difference(s), ${rowProblems.length} row count difference(s)`,
      );
    }
  }

  await db.close();
  process.exit(problems.length || rowProblems.length ? 1 : 0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
