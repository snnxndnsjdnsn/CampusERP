import { beforeAll, describe, expect, it } from 'vitest';
import { asUser, createWorld, U } from './world';

/**
 * The storage half of a document (migration 070).
 *
 * The `*_register` RPCs have always verified the blob they record; what was
 * missing was the right to put the blob in the bucket in the first place.
 * These tests treat `storage.objects` the way a browser sees it: a row
 * inserted as the signed-in user, allowed or refused by the storage policies.
 *
 * The fixture users are the ones `tests/db/rls.test.ts` describes - student1
 * owns student 1, superAdmin holds every permission globally, `denied` has no
 * role at all.
 */

/** Put one blob in the private bucket, as a signed-in user would. */
const upload = (sub: string | null, name: string) =>
  asUser(
    sub,
    `INSERT INTO storage.objects (bucket_id, name, owner, metadata)
     VALUES ('sims-documents', '${name}', null, '{"size":10}'::jsonb)
     RETURNING name`,
  );

beforeAll(async () => {
  await createWorld();
});

describe('document uploads (070)', () => {
  it('lets a student file under their own prefix', async () => {
    const rows = await upload(U.student1, 'student/1/marksheet.pdf');
    expect(rows.map((row) => String(row.name))).toEqual(['student/1/marksheet.pdf']);
  });

  it("keeps a student out of another student's prefix", async () => {
    await expect(upload(U.student1, 'student/2/someone-elses.pdf')).rejects.toThrow(
      /row-level security policy/i,
    );
  });

  it('lets an administrator file on behalf of a student', async () => {
    const rows = await upload(U.superAdmin, 'student/3/report.pdf');
    expect(rows.map((row) => String(row.name))).toEqual(['student/3/report.pdf']);
  });

  it('keeps a user with no SIMS mapping out of every prefix', async () => {
    // `unmapped` signs in without a user_account, so no permission can be
    // derived for them at all.
    await expect(upload(U.unmapped, 'student/1/attempt.pdf')).rejects.toThrow(/row-level security policy/i);
  });

  it('refuses keys outside the document bucket', async () => {
    await expect(upload(U.student1, 'elsewhere/1/notes.pdf')).rejects.toThrow();
  });
});
