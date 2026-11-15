import { beforeAll, describe, expect, it } from 'vitest';
import { asUser, createWorld, db, U } from './world';

/**
 * The storage half of the property hierarchy's documents (migration 071).
 *
 * `land_document` and `building_document` have always carried a
 * `file_object_id`, but nothing could put a file in the bucket under
 * `land/<id>` or `building/<id>`: 070's storage policies open the student,
 * employee and announcement families only, and `file_object` has no insert
 * policy at all. 071 opens the two property families the same way, adds the
 * register / download pair for each, and adds the policy that lets whoever
 * may read a document row also read the name of the file it points at.
 *
 * The fixture users are `tests/db/rls.test.ts`'s: student1 holds no
 * institution permission at all, registrar1 may read institution 1's
 * structure but holds no INSTITUTION write permission, superAdmin holds every
 * permission globally, and `unmapped` has no user_account. `SYSTEM1` and
 * `estate1` are created here: a SYSTEM_ADMIN - reads the institution
 * structure, holds no DOCUMENT permission - exactly the reader the metadata
 * policy is for, and a registrar granted INSTITUTION.ALL.CREATE for
 * institution 1, so a *scoped* writer proves the key policies without the
 * global-administrator fallback 070's student path gives.
 */

const TIMEOUT = 300_000;

/** A SYSTEM_ADMIN: institution structure yes, documents no. */
const SYSTEM1 = '00000000-0000-0000-0000-000000000050';

/** A registrar granted INSTITUTION.ALL.CREATE for institution 1 only. */
const ESTATE1 = '00000000-0000-0000-0000-000000000051';

/** The two parcels and the one building the tests file documents against. */
let land1 = 0;
let land2 = 0;
let building1 = 0;

/** The document rows: with a file, without one, and on the other campus. */
let docWithFile = 0;
let docNoFile = 0;
let docOtherCampus = 0;
let bldDocWithFile = 0;

/** One owner-level insert that hands back its id; the fixture uses no RLS. */
async function insertId(sql: string): Promise<number> {
  const rows = await db.query<{ id: number | string }>(sql);
  return Number(rows.rows[0]!.id);
}

/** A blob in the bucket, placed directly - the policies are exercised through `asUser`. */
async function putBlob(name: string, size = 10): Promise<void> {
  await db.query(
    `INSERT INTO storage.objects (bucket_id, name, owner, metadata)
     VALUES ('sims-documents', $1, null, $2::jsonb)`,
    [name, JSON.stringify({ size })],
  );
}

/** A register call, the way the form makes it. */
function register(
  sub: string | null,
  fn: 'land_document_register' | 'building_document_register',
  parentId: number,
  key: string,
  fileName: string,
  mime = 'application/pdf',
  size = 10,
) {
  return asUser<{ id: number | string }>(
    sub,
    `SELECT public.${fn}(${parentId}, '${key}', '${fileName}', '${mime}', ${size}) AS id`,
  );
}

/** A download call; the jsonb is cast to text so the test parses it itself. */
function download(sub: string | null, fn: 'land_document_download_info' | 'building_document_download_info', id: number) {
  return asUser<{ info: string }>(sub, `SELECT public.${fn}(${id})::text AS info`);
}

/** The file names one caller can see on `file_object` - what the Manage panel's cell would show. */
async function fileLabels(sub: string | null): Promise<string[]> {
  const rows = await asUser<{ label: string }>(sub, `SELECT label FROM public.admin_lookup_options('file_object')`);
  return rows.map((row) => String(row.label));
}

beforeAll(async () => {
  await createWorld();

  // The parcels, a building and a SYSTEM_ADMIN the shared world does not ship.
  land1 = await insertId(
    `INSERT INTO public.land (campus_id, land_name, survey_number)
     VALUES (1, 'Main Parcel', 'L-S1') RETURNING land_id AS id`,
  );
  land2 = await insertId(
    `INSERT INTO public.land (campus_id, land_name, survey_number)
     VALUES (2, 'Other Parcel', 'L-S2') RETURNING land_id AS id`,
  );
  building1 = await insertId(
    `INSERT INTO public.building (campus_id, building_code, building_name)
     VALUES (1, 'BLD1', 'Main Block') RETURNING building_id AS id`,
  );
  await db.exec(`
    INSERT INTO user_account (user_id, username, password_hash, account_status)
      VALUES (50, 'system1', 'x', 'ACTIVE'), (51, 'estate1', 'x', 'ACTIVE');
    INSERT INTO user_role_assignment (user_id, role_id, scope_type)
      VALUES (50, (select role_id from role where role_code = 'SYSTEM_ADMIN'), 'GLOBAL');
    INSERT INTO user_role_assignment (user_id, role_id, scope_type, institution_id)
      VALUES (51, (select role_id from role where role_code = 'REGISTRAR'), 'INSTITUTION', 1);
    INSERT INTO user_permission_override (user_id, permission_id, permission_effect, scope_type, scope_entity_id, justification)
      VALUES (51, (select permission_id from permission where permission_code = 'INSTITUTION.ALL.CREATE'),
              'ALLOW', 'INSTITUTION', 1, 'test estate writer');
    INSERT INTO auth.users (id) VALUES ('${SYSTEM1}'), ('${ESTATE1}');
    SELECT sims_private.link_auth_user('${SYSTEM1}', 50, 'test');
    SELECT sims_private.link_auth_user('${ESTATE1}', 51, 'test');
  `);

  // Four files: one attached to each table's document, one on the other
  // campus's document, and one no document points at - the orphan is the one
  // a reader without DOCUMENT permission must not be able to name.
  await putBlob(`land/${land1}/deed.pdf`);
  await putBlob(`land/${land2}/survey.pdf`);
  await putBlob(`building/${building1}/completion.pdf`);
  await putBlob(`land/${land1}/orphan.pdf`);
  await db.exec(`
    INSERT INTO public.file_object
      (file_object_id, storage_provider, storage_key, original_file_name, mime_type, file_size_bytes, uploaded_by_user_id)
    VALUES
      (7001, 'supabase-storage', 'land/${land1}/deed.pdf', 'deed.pdf', 'application/pdf', 10, 8),
      (7002, 'supabase-storage', 'land/${land2}/survey.pdf', 'survey.pdf', 'application/pdf', 10, 8),
      (7003, 'supabase-storage', 'building/${building1}/completion.pdf', 'completion.pdf', 'application/pdf', 10, 8),
      (7004, 'supabase-storage', 'land/${land1}/orphan.pdf', 'orphan.pdf', 'application/pdf', 10, 8);
  `);
  docWithFile = await insertId(
    `INSERT INTO public.land_document (land_id, document_type, document_name, file_object_id)
     VALUES (${land1}, 'SALE_DEED', 'Sale deed of the main parcel', 7001)
     RETURNING land_document_id AS id`,
  );
  docNoFile = await insertId(
    `INSERT INTO public.land_document (land_id, document_type, document_name)
     VALUES (${land1}, 'TAX_RECEIPT', 'Tax receipt with no file')
     RETURNING land_document_id AS id`,
  );
  docOtherCampus = await insertId(
    `INSERT INTO public.land_document (land_id, document_type, document_name, file_object_id)
     VALUES (${land2}, 'SURVEY_RECORD', 'Survey of the other parcel', 7002)
     RETURNING land_document_id AS id`,
  );
  bldDocWithFile = await insertId(
    `INSERT INTO public.building_document (building_id, document_type, document_name, file_object_id)
     VALUES (${building1}, 'COMPLETION_CERTIFICATE', 'Completion certificate', 7003)
     RETURNING building_document_id AS id`,
  );
}, TIMEOUT);

describe('property document paths (071)', () => {
  it('reads the parcel / building id out of a key', async () => {
    const parse = async (fn: 'doc_land_id' | 'doc_building_id', key: string) => {
      const rows = await db.query<{ v: number | null }>(`SELECT sims_private.${fn}($1) AS v`, [key]);
      return rows.rows[0]?.v ?? null;
    };

    expect(await parse('doc_land_id', `land/${land1}/deed.pdf`)).toBe(land1);
    expect(await parse('doc_land_id', 'land/12/sub/deed.pdf')).toBeNull();
    expect(await parse('doc_land_id', 'student/1/marksheet.pdf')).toBeNull();
    expect(await parse('doc_land_id', `land/1/${'x'.repeat(400)}`)).toBeNull();
    expect(await parse('doc_building_id', `building/${building1}/plan.pdf`)).toBe(building1);
    expect(await parse('doc_building_id', 'land/1/deed.pdf')).toBeNull();
  });

  it('opens a key for whoever may write or read the row itself', async () => {
    const can = async (sub: string | null, key: string, write: boolean) => {
      const rows = await asUser<{ ok: boolean | null }>(
        sub,
        `SELECT sims_private.can_use_land_doc_path('${key}', ${write}) AS ok`,
      );
      return rows[0]?.ok ?? null;
    };

    // superAdmin holds every permission globally: read and write.
    expect(await can(U.superAdmin, `land/${land1}/deed.pdf`, true)).toBe(true);
    expect(await can(U.superAdmin, `land/${land1}/deed.pdf`, false)).toBe(true);
    // A student holds no institution permission at all.
    expect(await can(U.student1, `land/${land1}/deed.pdf`, true)).toBe(false);
    expect(await can(U.student1, `land/${land1}/deed.pdf`, false)).toBe(false);
    // A registrar may read the structure, not write it.
    expect(await can(U.registrar1, `land/${land1}/deed.pdf`, false)).toBe(true);
    expect(await can(U.registrar1, `land/${land1}/deed.pdf`, true)).toBe(false);
    // A key whose parcel does not exist is refused, whoever asks.
    expect(await can(U.superAdmin, 'land/999999/notes.pdf', false)).toBeNull();
    expect(await can(U.superAdmin, 'land/999999/notes.pdf', true)).toBeNull();

    const buildingCan = async (sub: string | null, write: boolean) => {
      const rows = await asUser<{ ok: boolean | null }>(
        sub,
        `SELECT sims_private.can_use_building_doc_path('building/${building1}/plan.pdf', ${write}) AS ok`,
      );
      return rows[0]?.ok ?? null;
    };
    expect(await buildingCan(U.superAdmin, true)).toBe(true);
    expect(await buildingCan(U.student1, true)).toBe(false);
    expect(await buildingCan(U.student1, false)).toBe(false);
  }, TIMEOUT);
});

describe('the bucket (071)', () => {
  /** The same shape the 070 test uses: a row inserted as the signed-in user. */
  const upload = (sub: string | null, name: string) =>
    asUser(
      sub,
      `INSERT INTO storage.objects (bucket_id, name, owner, metadata)
       VALUES ('sims-documents', '${name}', null, '{"size":10}'::jsonb)
       RETURNING name`,
    );

  it('lets an administrator file a parcel and a building', async () => {
    const land = await upload(U.superAdmin, `land/${land1}/st-land.pdf`);
    expect(land.map((row) => String(row.name))).toEqual([`land/${land1}/st-land.pdf`]);
    const building = await upload(U.superAdmin, `building/${building1}/st-building.pdf`);
    expect(building.map((row) => String(row.name))).toEqual([`building/${building1}/st-building.pdf`]);
  });

  it('lets a writer scoped to the institution file its parcels', async () => {
    // A user whose write right comes from a scoped grant - the ordinary case
    // a global administrator would never exercise.
    const rows = await upload(ESTATE1, `land/${land1}/st-estate.pdf`);
    expect(rows.map((row) => String(row.name))).toEqual([`land/${land1}/st-estate.pdf`]);
  });

  it('keeps a student out of both families', async () => {
    await expect(upload(U.student1, `land/${land1}/attempt.pdf`)).rejects.toThrow(
      /row-level security policy/i,
    );
    await expect(upload(U.student1, `building/${building1}/attempt.pdf`)).rejects.toThrow(
      /row-level security policy/i,
    );
  });

  it('refuses a write to a structure reader who holds no write permission', async () => {
    // registrar1 may read institution 1, but INSTITUTION write permissions it
    // does not hold - the row policy and the key policy agree.
    await expect(upload(U.registrar1, `land/${land1}/attempt.pdf`)).rejects.toThrow(
      /row-level security policy/i,
    );
  });

  it('keeps a user with no SIMS mapping out of every prefix', async () => {
    await expect(upload(U.unmapped, `land/${land1}/attempt.pdf`)).rejects.toThrow(
      /row-level security policy/i,
    );
  });

  it('refuses a key whose parcel does not exist', async () => {
    // Asked by the scoped writer: their own policy finds no parcel behind the
    // key, and 070's families do not claim it either. (A global administrator
    // is not the judge here - 070's student path answers them true for any
    // key at all, which is that migration's own behavior.)
    await expect(upload(ESTATE1, 'land/999999/notes.pdf')).rejects.toThrow(
      /row-level security policy/i,
    );
  });

  it('refuses keys outside the property families', async () => {
    await expect(upload(ESTATE1, 'elsewhere/1/notes.pdf')).rejects.toThrow(
      /row-level security policy/i,
    );
  });

  it('lets a structure reader select a parcel file, and a student none', async () => {
    const key = `land/${land1}/deed.pdf`;
    const seen = await asUser<{ name: string }>(
      U.registrar1,
      `SELECT name FROM storage.objects WHERE name = '${key}'`,
    );
    expect(seen.map((row) => String(row.name))).toEqual([key]);

    const asStudent = await asUser<{ name: string }>(
      U.student1,
      `SELECT name FROM storage.objects WHERE name = '${key}'`,
    );
    expect(asStudent).toEqual([]);
  });
});

describe('register (071)', () => {
  it('verifies the blob and creates the file row', async () => {
    const key = `land/${land1}/reg-sale.pdf`;
    await putBlob(key);
    const rows = await register(U.superAdmin, 'land_document_register', land1, key, 'reg-sale.pdf');
    const fileId = Number(rows[0]!.id);
    expect(fileId).toBeGreaterThan(0);

    const stored = await db.query<{
      storage_key: string;
      original_file_name: string;
      mime_type: string;
      file_size_bytes: number | string;
      file_extension: string;
      uploaded_by_user_id: number | string;
      deleted_at: string | null;
    }>(
      `SELECT storage_key, original_file_name, mime_type, file_size_bytes, file_extension,
              uploaded_by_user_id, deleted_at
         FROM public.file_object WHERE storage_key = $1`,
      [key],
    );
    expect(stored.rows).toHaveLength(1);
    expect(stored.rows[0]!.original_file_name).toBe('reg-sale.pdf');
    expect(stored.rows[0]!.mime_type).toBe('application/pdf');
    expect(Number(stored.rows[0]!.file_size_bytes)).toBe(10);
    expect(stored.rows[0]!.file_extension).toBe('pdf');
    expect(Number(stored.rows[0]!.uploaded_by_user_id)).toBe(8);
    expect(stored.rows[0]!.deleted_at).toBeNull();
  });

  it('gives the same file back when the save is retried', async () => {
    const key = `land/${land1}/reg-sale.pdf`;
    const first = await register(U.superAdmin, 'land_document_register', land1, key, 'reg-sale.pdf');
    const second = await register(U.superAdmin, 'land_document_register', land1, key, 'reg-sale.pdf');
    expect(Number(second[0]!.id)).toBe(Number(first[0]!.id));
  });

  it('refuses the key again once a document points at it', async () => {
    const key = `land/${land1}/reg-sale.pdf`;
    const rows = await register(U.superAdmin, 'land_document_register', land1, key, 'reg-sale.pdf');
    const fileId = Number(rows[0]!.id);
    await db.exec(
      `INSERT INTO public.land_document (land_id, document_type, document_name, file_object_id)
       VALUES (${land1}, 'SALE_DEED', 'Sale deed registered from the form', ${fileId})`,
    );
    await expect(register(U.superAdmin, 'land_document_register', land1, key, 'reg-sale.pdf')).rejects.toThrow(
      /already registered/,
    );
  });

  it('refuses a file registered before under another name', async () => {
    const key = `land/${land1}/reg-survey.pdf`;
    await putBlob(key);
    await register(U.superAdmin, 'land_document_register', land1, key, 'reg-survey.pdf');
    await expect(
      register(U.superAdmin, 'land_document_register', land1, key, 'somebody-elses-name.pdf'),
    ).rejects.toThrow(/already registered/);
  });

  it('refuses a key stored under another parcel or an unknown one', async () => {
    await expect(
      register(U.superAdmin, 'land_document_register', land1, `land/${land2}/x.pdf`, 'x.pdf'),
    ).rejects.toThrow(/not stored under this land/);
    await expect(
      register(U.superAdmin, 'land_document_register', land1, 'land/999999/x.pdf', 'x.pdf'),
    ).rejects.toThrow(/not stored under this land/);
    await expect(
      register(U.superAdmin, 'land_document_register', 999999, 'land/999999/x.pdf', 'x.pdf'),
    ).rejects.toThrow(/Unknown land/);
  });

  it('refuses a caller who may read the structure but not write it', async () => {
    const key = `land/${land1}/reg-denied.pdf`;
    await expect(register(U.registrar1, 'land_document_register', land1, key, 'denied.pdf')).rejects.toThrow(
      /Not authorised \(INSTITUTION\.ALL\.CREATE\)/,
    );
    await expect(register(U.student1, 'land_document_register', land1, key, 'denied.pdf')).rejects.toThrow(
      /Not authorised \(INSTITUTION\.ALL\.CREATE\)/,
    );
  });

  it('refuses a file that was never uploaded', async () => {
    await expect(
      register(U.superAdmin, 'land_document_register', land1, `land/${land1}/ghost.pdf`, 'ghost.pdf'),
    ).rejects.toThrow(/has not been uploaded/);
  });

  it('refuses a name or type the blob does not match', async () => {
    const key = `land/${land1}/reg-bad.pdf`;
    await putBlob(key);
    // The name does not carry the type it claims.
    await expect(
      register(U.superAdmin, 'land_document_register', land1, key, 'reg-bad.txt'),
    ).rejects.toThrow(/does not match its type/);
    // A type outside the three the RPC accepts.
    await expect(
      register(U.superAdmin, 'land_document_register', land1, key, 'reg-bad.pdf', 'image/gif'),
    ).rejects.toThrow(/Only PDF, JPEG and PNG/);
    // A size the stored blob does not have.
    await expect(
      register(U.superAdmin, 'land_document_register', land1, key, 'reg-bad.pdf', 'application/pdf', 99),
    ).rejects.toThrow(/size does not match/);
  });

  it('registers a building file the same way', async () => {
    const key = `building/${building1}/reg-completion.pdf`;
    await putBlob(key);
    const rows = await register(
      U.superAdmin,
      'building_document_register',
      building1,
      key,
      'reg-completion.pdf',
    );
    const fileId = Number(rows[0]!.id);
    expect(fileId).toBeGreaterThan(0);
    const stored = await db.query<{ original_file_name: string }>(
      `SELECT original_file_name FROM public.file_object WHERE storage_key = $1`,
      [key],
    );
    expect(stored.rows[0]!.original_file_name).toBe('reg-completion.pdf');

    await expect(
      register(U.superAdmin, 'building_document_register', building1, 'building/999999/x.pdf', 'x.pdf'),
    ).rejects.toThrow(/not stored under this building/);
    await expect(
      register(U.superAdmin, 'building_document_register', 999999, 'building/999999/x.pdf', 'x.pdf'),
    ).rejects.toThrow(/Unknown building/);
    await expect(register(U.student1, 'building_document_register', building1, key, 'x.pdf')).rejects.toThrow(
      /Not authorised \(INSTITUTION\.ALL\.CREATE\)/,
    );
  }, TIMEOUT);
});

describe('open (071)', () => {
  it('tells an administrator where the file is, and records the download', async () => {
    const rows = await download(U.superAdmin, 'land_document_download_info', docWithFile);
    const info = JSON.parse(String(rows[0]!.info)) as Record<string, string>;
    expect(info.storage_key).toBe(`land/${land1}/deed.pdf`);
    expect(info.file_name).toBe('deed.pdf');
    expect(info.mime_type).toBe('application/pdf');

    const audit = await db.query<{ n: number }>(
      `SELECT count(*)::int AS n FROM public.activity_audit
        WHERE entity_name = 'land_document' AND entity_id = '${docWithFile}'
          AND action_code = 'DOWNLOAD' AND user_id = 8`,
    );
    expect(audit.rows[0]!.n).toBeGreaterThanOrEqual(1);
  });

  it('opens a building file and records that download too', async () => {
    const rows = await download(U.superAdmin, 'building_document_download_info', bldDocWithFile);
    const info = JSON.parse(String(rows[0]!.info)) as Record<string, string>;
    expect(info.storage_key).toBe(`building/${building1}/completion.pdf`);
    expect(info.file_name).toBe('completion.pdf');

    const audit = await db.query<{ n: number }>(
      `SELECT count(*)::int AS n FROM public.activity_audit
        WHERE entity_name = 'building_document' AND entity_id = '${bldDocWithFile}'
          AND action_code = 'DOWNLOAD' AND user_id = 8`,
    );
    expect(audit.rows[0]!.n).toBeGreaterThanOrEqual(1);
  });

  it('refuses a caller who may not read the institution structure', async () => {
    await expect(download(U.student1, 'land_document_download_info', docWithFile)).rejects.toThrow(
      /Not authorised \(INSTITUTION\.ALL\.READ\)/,
    );
    // A registrar scoped to institution 1: the other campus's parcel is not theirs.
    await expect(
      download(U.registrar1, 'land_document_download_info', docOtherCampus),
    ).rejects.toThrow(/Not authorised \(INSTITUTION\.ALL\.READ\)/);
  });

  it('says so separately when the document has no file', async () => {
    await expect(download(U.superAdmin, 'land_document_download_info', docNoFile)).rejects.toThrow(
      /has no file attached/,
    );
  });

  it('refuses an unknown document the same way', async () => {
    await expect(download(U.superAdmin, 'land_document_download_info', 999999)).rejects.toThrow(
      /Not authorised .* or unknown document/,
    );
  });
});

describe('the file behind a document (071)', () => {
  it('is exercised by a role that reads the structure but holds no DOCUMENT permission', async () => {
    const rows = await db.query<{ inst: boolean; doc: boolean }>(
      `SELECT bool_or(p.permission_code = 'INSTITUTION.ALL.READ' AND rp.permission_effect = 'ALLOW') AS inst,
              bool_or(p.permission_code = 'DOCUMENT.ALL.READ' AND rp.permission_effect = 'ALLOW') AS doc
         FROM public.role r
         JOIN public.role_permission rp ON rp.role_id = r.role_id
         JOIN public.permission p ON p.permission_id = rp.permission_id
        WHERE r.role_code = 'SYSTEM_ADMIN'
          AND p.permission_code IN ('INSTITUTION.ALL.READ', 'DOCUMENT.ALL.READ')`,
    );
    // The premise of the policy: structure yes, documents no.
    expect(rows.rows[0]!.inst).toBe(true);
    expect(rows.rows[0]!.doc).toBe(false);
  });

  it('lets that reader name the file a document points at, and only that', async () => {
    const labels = await fileLabels(SYSTEM1);
    // Attached to a document on a campus they may read: visible.
    expect(labels).toContain('deed.pdf');
    expect(labels).toContain('completion.pdf');
    // Registered but pointed at by nothing: not theirs to name.
    expect(labels).not.toContain('orphan.pdf');
    expect(labels).not.toContain('reg-survey.pdf');
  });

  it('shows a documentless user nothing, and a document reader everything', async () => {
    const unmapped = await fileLabels(U.unmapped);
    expect(unmapped).not.toContain('deed.pdf');

    // superAdmin holds DOCUMENT.ALL.READ, so the file's own policy answers -
    // attached or not.
    const admin = await fileLabels(U.superAdmin);
    expect(admin).toContain('deed.pdf');
    expect(admin).toContain('orphan.pdf');
  });
});
