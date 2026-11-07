/**
 * Create the first administrator of the SIMS project.
 *
 *   node tools/create_admin.mjs [--apply] [--email EMAIL] [--password PASSWORD]
 *                               [--role ROLE] [--json]
 *
 * The tool does three things, in this order:
 *
 *   1. it creates the sign-in account with the Supabase Admin API
 *      (`POST /auth/v1/admin/users`, the service role key is required);
 *   2. it provisions the SIMS account with `public.iam_provision_user()`, which
 *      inserts the row in `public.user_account` and links it to the sign-in
 *      account in `sims_private.auth_identity_map`;
 *   3. it assigns the role (SUPER_ADMIN by default) at GLOBAL scope with a
 *      row in `public.user_role_assignment`.
 *
 * When the sign-in account already exists it is reused instead of created
 * again, and when the SIMS account already exists it is linked with
 * `sims_private.link_auth_user()` instead of being provisioned twice.
 *
 * Without `--apply` the tool only prints the plan.  It never writes to the
 * database and never calls the Admin API without `--apply`.
 *
 * Settings (the environment wins over the defaults):
 *
 *   SUPABASE_SERVICE_ROLE_KEY  the service role key of the project (required)
 *   NEXT_PUBLIC_SUPABASE_URL   the project URL
 *   SUPABASE_ADMIN_EMAIL       the email address of the administrator
 *   SUPABASE_ADMIN_PASSWORD    the password of the administrator
 *
 * Exit code 0 means "the plan is clean" or "the administrator was created",
 * 1 means "the administrator could not be created" and 2 means "the tool was
 * not configured correctly".
 */
import crypto from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..');

const DEFAULT_URL = 'https://khqqfgqvwdxlqkncwtmh.supabase.co';
const DEFAULT_ROLE = 'SUPER_ADMIN';

const DEFAULTS = {
  host: 'aws-0-ap-southeast-1.pooler.supabase.com',
  port: 5432,
  database: 'postgres',
  user: 'postgres.khqqfgqvwdxlqkncwtmh',
  password: '',
  sslmode: 'require',
};

const USAGE = `Usage: node tools/create_admin.mjs [options]

  --apply             create the administrator (without it the tool only prints the plan)
  --email EMAIL       the email address of the administrator
  --password SECRET   the password of the administrator (generated when it is missing)
  --role ROLE         the role to assign (${DEFAULT_ROLE} by default)
  --json              machine readable report
  --help              this text
`;

/** The first environment variable that is set wins. */
function pick(names, fallback = '') {
  for (const name of names) {
    const value = process.env[name];
    if (value !== undefined && value !== '') return value;
  }
  return fallback;
}

/** The connection settings of the project. */
function connectionOptions() {
  const pickOne = (name, fallback) => pick([`SUPABASE_DB_${name}`, `SIMS_DB_${name}`], fallback);
  return {
    host: pickOne('HOST', DEFAULTS.host),
    port: Number(pickOne('PORT', DEFAULTS.port)),
    database: pickOne('NAME', DEFAULTS.database),
    user: pickOne('USER', DEFAULTS.user),
    password: pickOne('PASSWORD', DEFAULTS.password),
    sslmode: pickOne('SSLMODE', DEFAULTS.sslmode),
  };
}

/** A password that is long enough and has no characters that need escaping. */
function generatePassword() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
  const bytes = crypto.randomBytes(24);
  let out = '';
  for (const byte of bytes) out += alphabet[byte % alphabet.length];
  return `${out.slice(0, 4)}-${out.slice(4, 10)}-${out.slice(10, 16)}-${out.slice(16, 22)}`;
}

/** The value of an option, or the first environment variable that is set. */
function option(args, name, envNames) {
  const index = args.indexOf(name);
  if (index !== -1 && args[index + 1]) return args[index + 1];
  return pick(envNames, '');
}

/**
 * Create the sign-in account with the Admin API.
 *
 * Returns the id of the auth user, or null when the account already exists
 * (the caller then looks the id up in `auth.users`).
 */
async function createAuthUser(url, serviceKey, email, password) {
  const response = await fetch(`${url}/auth/v1/admin/users`, {
    method: 'POST',
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      email,
      password,
      email_confirm: true,
      user_metadata: { provisioned_by: 'tools/create_admin.mjs' },
    }),
  });
  const text = await response.text();
  let body = null;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = { raw: text };
  }
  if (response.ok) return { id: body.id, created: true, body };
  const code = body?.error_code || body?.msg || body?.message || body?.raw || response.statusText;
  const alreadyExists = response.status === 422 && /already|registered|exists/i.test(String(code));
  return { id: null, created: false, alreadyExists, error: code, status: response.status };
}

async function main() {
  const args = process.argv.slice(2);
  if (args.includes('--help') || args.includes('-h')) {
    console.log(USAGE);
    process.exit(0);
  }
  const asJson = args.includes('--json');
  const apply = args.includes('--apply');

  const serviceKey = pick(['SUPABASE_SERVICE_ROLE_KEY']);
  const url = pick(['NEXT_PUBLIC_SUPABASE_URL', 'SUPABASE_URL'], DEFAULT_URL).replace(/\/+$/, '');
  const email = option(args, '--email', ['SUPABASE_ADMIN_EMAIL', 'ADMIN_EMAIL', 'SIMS_ADMIN_EMAIL']);
  const role = option(args, '--role', ['SUPABASE_ADMIN_ROLE']) || DEFAULT_ROLE;
  let password = option(args, '--password', [
    'SUPABASE_ADMIN_PASSWORD',
    'ADMIN_PASSWORD',
    'SIMS_ADMIN_PASSWORD',
  ]);

  // --- the configuration has to be complete --------------------------------
  const problems = [];
  if (!serviceKey) {
    problems.push(
      'SUPABASE_SERVICE_ROLE_KEY is not set: the Admin API refuses every request without it. ' +
        'Put the service role key of the project into .env.local (it is server side only).',
    );
  }
  if (!email) {
    problems.push(
      'the email address of the administrator is missing: pass --email or set ' +
        'SUPABASE_ADMIN_EMAIL.',
    );
  }
  if (problems.length) {
    for (const problem of problems) console.error(`ERROR ${problem}`);
    if (!asJson) console.error('\nNothing was written.');
    process.exit(2);
  }

  const generated = !password;
  if (!password) password = generatePassword();

  // --- the plan ------------------------------------------------------------
  const plan = [
    `create the sign-in account ${email} with the Supabase Admin API`,
    `provision the SIMS account with public.iam_provision_user()`,
    `assign the role ${role} at GLOBAL scope`,
  ];
  if (!apply) {
    if (asJson) {
      console.log(JSON.stringify({ mode: 'dry-run', email, role, plan }, null, 1));
      process.exit(0);
    }
    console.log(`project  : ${url}`);
    console.log(`email    : ${email}`);
    console.log(`role     : ${role}`);
    console.log(`password : ${generated ? '(generated when --apply runs)' : '(given)'}`);
    console.log('');
    for (const step of plan) console.log(`  ${step}`);
    console.log('');
    console.log('dry run: nothing was written. Use --apply to create the administrator.');
    process.exit(0);
  }

  // --- create the sign-in account -----------------------------------------
  const created = await createAuthUser(url, serviceKey, email, password);
  if (!created.id && !created.alreadyExists) {
    console.error(`ERROR the Admin API refused to create the sign-in account: ${created.error}`);
    process.exit(1);
  }

  const options = connectionOptions();
  if (!options.password) {
    console.error(
      'ERROR SUPABASE_DB_PASSWORD is not set (or SIMS_DB_PASSWORD). The password is ' +
        'never stored in the repository - put it into .env.local.',
    );
    process.exit(1);
  }
  const client = new pg.Client({
    host: options.host,
    port: options.port,
    database: options.database,
    user: options.user,
    password: options.password,
    ssl: options.sslmode === 'disable' ? false : { rejectUnauthorized: false },
    application_name: 'sims_create_admin',
  });
  await client.connect();

  const report = {
    mode: 'apply',
    email,
    role,
    auth_user_created: created.created,
    auth_user_id: created.id,
    user_id: null,
    provisioned: false,
    linked: false,
    role_assigned: false,
    password_generated: generated,
  };

  try {
    // The id of the sign-in account, when it already existed.
    if (!created.id) {
      const found = await client.query('SELECT id::text FROM auth.users WHERE lower(email) = lower($1)', [
        email,
      ]);
      if (!found.rows.length) {
        console.error(
          `ERROR the sign-in account ${email} already exists but was not found in auth.users`,
        );
        process.exit(1);
      }
      report.auth_user_id = found.rows[0].id;
    }

    const authId = report.auth_user_id;

    // Is the sign-in account already linked to a SIMS account?
    const linked = await client.query(
      'SELECT user_id::text FROM sims_private.auth_identity_map WHERE auth_user_id = $1::uuid',
      [authId],
    );
    let userId = linked.rows.length ? linked.rows[0].user_id : null;

    if (!userId) {
      // Provision the SIMS account.
      try {
        const provisioned = await client.query(
          'SELECT public.iam_provision_user($1::uuid, $2::text, NULL::text, NULL::text, NULL::bigint)::text',
          [authId, email],
        );
        userId = provisioned.rows[0].iam_provision_user;
        report.provisioned = true;
      } catch (err) {
        // The account exists already: link the sign-in account to it instead.
        if (err.code !== '23505' && !/already exists/i.test(err.message)) throw err;
        const existing = await client.query(
          'SELECT user_id::text FROM public.user_account WHERE lower(email) = lower($1)',
          [email],
        );
        if (!existing.rows.length) throw err;
        userId = existing.rows[0].user_id;
        await client.query(
          "SELECT sims_private.link_auth_user($1::uuid, $2::bigint, 'tools/create_admin.mjs')",
          [authId, userId],
        );
        report.linked = true;
      }
    } else {
      report.linked = true;
    }

    report.user_id = userId;

    // Assign the role at GLOBAL scope.
    const assignment = await client.query(
      `INSERT INTO public.user_role_assignment
         (user_id, role_id, scope_type, assignment_status, is_primary, assignment_reason)
       SELECT $1::bigint, r.role_id, 'GLOBAL', 'ACTIVE', true, 'created by tools/create_admin.mjs'
         FROM public.role r
        WHERE r.role_code = $2
       ON CONFLICT DO NOTHING
       RETURNING user_role_assignment_id::text`,
      [userId, role],
    );
    report.role_assigned = assignment.rows.length > 0;
    if (!report.role_assigned) {
      const current = await client.query(
        `SELECT a.user_role_assignment_id::text, a.scope_type, a.assignment_status
           FROM public.user_role_assignment a JOIN public.role r ON r.role_id = a.role_id
          WHERE a.user_id = $1::bigint AND r.role_code = $2`,
        [userId, role],
      );
      report.existing_assignment = current.rows[0] || null;
    }
  } finally {
    await client.end();
  }

  if (asJson) {
    console.log(JSON.stringify(report, null, 1));
  } else {
    console.log(`sign-in account : ${email} (${report.auth_user_created ? 'created' : 'already existed'})`);
    console.log(`auth user id    : ${report.auth_user_id}`);
    console.log(`SIMS user id    : ${report.user_id}`);
    console.log(`SIMS account    : ${report.provisioned ? 'provisioned' : report.linked ? 'linked' : 'unchanged'}`);
    console.log(`role ${role.padEnd(13)}: ${report.role_assigned ? 'assigned at GLOBAL scope' : 'already assigned'}`);
    if (generated) {
      console.log('');
      console.log(`password        : ${password}`);
      console.log('store it now, it is not written anywhere.');
    }
  }
  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
