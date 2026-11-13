-- =============================================================================================
-- 070. document_uploads
-- ---------------------------------------------------------------------------------------------
-- Hand written.
--
-- The storage half of every document in SIMS.
--
-- The schema has always had the data half: a `file_object` row per file, the
-- `sims-documents` bucket it lives in, and a family of `*_register` RPCs that
-- verify the blob before recording it. What it never had was the right to put
-- a blob in the bucket in the first place - `storage.objects` carried no row
-- level security policy at all, so no signed-in user could upload, download
-- or remove anything, and every document form asked the caller to type the
-- storage key of a file somebody had uploaded by hand.
--
-- This migration grants that right, scoped by the key the same way the
-- register RPCs already scope it. A key reads `student/12/marksheet.pdf` or
-- `employee/3/contract.pdf`, and `sims_private.can_use_student_doc_path`
-- decides who may use one: its owner, or whoever holds the document
-- permission for that student or employee. `sims_private.can_use_announcement_path`
-- does the same for `announcement/…` keys. The register RPCs re-check
-- everything the policy cannot know - the file type, the size, that the name
-- matches the type, that the blob is really there - so a path the policy
-- lets through still cannot become a document unless the RPC accepts it.
-- =============================================================================================

-- The bucket the browser uploads into. It is private: nothing in it is
-- reachable without a signed URL, and every URL below is minted for one
-- caller and expires.
INSERT INTO storage.buckets (id, name, public)
VALUES ('sims-documents', 'sims-documents', false)
ON CONFLICT (id) DO NOTHING;

-- Supabase enables this when it installs the storage service, and owns the
-- table while it does - a migration here cannot alter it, and does not need
-- to. The test fixture, which builds a bare `storage` schema, does need it,
-- so the attempt is made and a refusal is read as "already taken care of".
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'storage' AND c.relname = 'objects' AND c.relrowsecurity
  ) THEN
    BEGIN
      ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
    EXCEPTION WHEN insufficient_privilege THEN
      NULL;
    END;
  END IF;
END $$;

-- The storage service grants `authenticated` every right on the table and
-- lets the policies below decide; the grant is stated for the fixture, where
-- nothing grants it, and is read as a refusal where the service manages it.
DO $$
BEGIN
  BEGIN
    GRANT SELECT, INSERT, UPDATE, DELETE ON storage.objects TO authenticated;
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
END $$;

-- Putting a file in. The key is the decision: a user may write under their
-- own student or employee prefix, or under one they hold the document
-- permission for.
CREATE POLICY documents_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'sims-documents'
    AND (
      sims_private.can_use_student_doc_path(name, true)
      OR sims_private.can_use_announcement_path(name, true)
    )
  );

-- Reading one, which is how a signed URL is minted: the storage service
-- checks the caller can select the row before it will sign a URL for it.
-- Reading uses the read branch of the path helpers, so an employee document
-- that an access rule keeps quiet about stays quiet.
CREATE POLICY documents_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'sims-documents'
    AND (
      sims_private.can_use_student_doc_path(name, false)
      OR sims_private.can_use_announcement_path(name, false)
    )
  );

-- Taking one away. The same right that lets a file be put there lets it be
-- cleared out: `deleteStoredFile` runs after the row is gone, so this is
-- what stops an orphan blob from being permanent.
CREATE POLICY documents_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'sims-documents'
    AND (
      sims_private.can_use_student_doc_path(name, true)
      OR sims_private.can_use_announcement_path(name, true)
    )
  );
