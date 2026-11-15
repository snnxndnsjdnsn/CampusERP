-- =============================================================================================
-- 071. property_document_uploads
-- ---------------------------------------------------------------------------------------------
-- Hand written.
--
-- The storage half of the property hierarchy's documents.
--
-- 068 gave the hierarchy its documents: `land_document` and `building_document`
-- record the sale deed, survey record or completion certificate of a parcel or
-- a building, with a `file_object_id` pointing at the file behind it. The
-- pointer had nothing to point at - there was no way to put a file in the
-- bucket from a form. The storage policies of 070 open `student/...`,
-- `employee/...` and `announcement/...` keys, and `file_object` carries no
-- INSERT policy at all, so neither the browser nor an RPC acting for it could
-- create the row that names the file.
--
-- This migration opens `land/<id>/...` and `building/<id>/...` keys the way 070
-- opened the others: by the key, to whoever may write the document table
-- itself - `can_campus(INSTITUTION.ALL....)` on the campus the parcel or
-- building belongs to, the very call the tables' own row level policies make.
-- The register RPCs then verify what the policy cannot know (the type, the
-- size, that the name matches the type, that the blob is really there) and
-- create the `file_object` row, which has no insert policy of its own; the
-- `land_document` / `building_document` row itself keeps being written by
-- `admin_table_save`, with the returned id in its `file_object_id`. The
-- download RPCs say where an attached file lives, for a signed URL, and record
-- the DOWNLOAD.
--
-- The last policy closes the loop from the other side: whoever may read a land
-- or building document may read the name of the file it points at - which is
-- what the Manage panel's cell shows - even when they hold no DOCUMENT
-- permission of their own.
-- =============================================================================================

-- The key of a parcel's or a building's file: `land/12/deed.pdf` -> 12,
-- anything else -> NULL.
CREATE OR REPLACE FUNCTION sims_private.doc_land_id(p_name text)
 RETURNS bigint
 LANGUAGE sql
 IMMUTABLE
AS $function$ SELECT CASE WHEN length(p_name) <= 400 AND p_name ~ '^land/[0-9]{1,15}/[^/]+$' THEN split_part(p_name, '/', 2)::bigint END $function$;

CREATE OR REPLACE FUNCTION sims_private.doc_building_id(p_name text)
 RETURNS bigint
 LANGUAGE sql
 IMMUTABLE
AS $function$ SELECT CASE WHEN length(p_name) <= 400 AND p_name ~ '^building/[0-9]{1,15}/[^/]+$' THEN split_part(p_name, '/', 2)::bigint END $function$;

-- May this caller use a parcel's key? The write branch covers the two rights
-- the `land_document` row policies gate writing on - CREATE puts a document
-- there, DELETE clears one away - so either holder may put a file in or take
-- an orphan out; the read branch is the READ the select policy asks for. A key
-- whose parcel does not exist reads no row at all, and so is refused.
CREATE OR REPLACE FUNCTION sims_private.can_use_land_doc_path(p_name text, p_write boolean)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT COALESCE(
      sims_private.can_campus(
        CASE WHEN p_write THEN ARRAY['INSTITUTION.ALL.CREATE', 'INSTITUTION.ALL.DELETE']::text[]
             ELSE ARRAY['INSTITUTION.ALL.READ']::text[] END,
        l.campus_id),
      false)
    FROM public.land l
    WHERE l.land_id = sims_private.doc_land_id(p_name)
$function$;

CREATE OR REPLACE FUNCTION sims_private.can_use_building_doc_path(p_name text, p_write boolean)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT COALESCE(
      sims_private.can_campus(
        CASE WHEN p_write THEN ARRAY['INSTITUTION.ALL.CREATE', 'INSTITUTION.ALL.DELETE']::text[]
             ELSE ARRAY['INSTITUTION.ALL.READ']::text[] END,
        b.campus_id),
      false)
    FROM public.building b
    WHERE b.building_id = sims_private.doc_building_id(p_name)
$function$;

-- Putting a parcel's file in. The key is the decision, exactly as in 070: the
-- path helper asks for the campus permissions the `land_document` row policies
-- gate its rows on - CREATE or DELETE to write, READ to read. These sit
-- alongside 070's policies rather than inside them - policies on the same
-- command are ORed, so a key only has to satisfy the family it belongs to.
CREATE POLICY land_document_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'sims-documents'
    AND sims_private.can_use_land_doc_path(name, true)
  );

-- Reading one, which is how a signed URL is minted: the storage service
-- checks the caller can select the row before it will sign a URL for it.
CREATE POLICY land_document_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'sims-documents'
    AND sims_private.can_use_land_doc_path(name, false)
  );

-- Taking one away: the same right that puts the file there clears it out, so
-- an orphan blob from a half-finished form is not permanent.
CREATE POLICY land_document_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'sims-documents'
    AND sims_private.can_use_land_doc_path(name, true)
  );

-- The same three for a building's folder.
CREATE POLICY building_document_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'sims-documents'
    AND sims_private.can_use_building_doc_path(name, true)
  );

CREATE POLICY building_document_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'sims-documents'
    AND sims_private.can_use_building_doc_path(name, false)
  );

CREATE POLICY building_document_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'sims-documents'
    AND sims_private.can_use_building_doc_path(name, true)
  );

-- The name of the file a document points at. `file_object`'s own select policy
-- shows a row to its uploader or to whoever holds DOCUMENT.ALL.READ; the
-- Manage panel's cell shows the file's name to whoever may read the document
-- row itself, so the metadata of a file that a land or building document
-- points at belongs to that reader too - a SYSTEM_ADMIN reads the institution
-- structure and holds no DOCUMENT permission at all. This reads
-- `land_document` and `building_document`, which do not exist until 068, so -
-- like 068's own policies - it is kept out of the generated set (see
-- tools/hand_written.py).
CREATE POLICY file_object_property_document_select ON public.file_object
  AS PERMISSIVE FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.land_document d
      JOIN public.land l ON l.land_id = d.land_id
      WHERE d.file_object_id = file_object.file_object_id
        AND sims_private.can_campus(ARRAY['INSTITUTION.ALL.READ'::text], l.campus_id)
    )
    OR EXISTS (
      SELECT 1 FROM public.building_document d
      JOIN public.building b ON b.building_id = d.building_id
      WHERE d.file_object_id = file_object.file_object_id
        AND sims_private.can_campus(ARRAY['INSTITUTION.ALL.READ'::text], b.campus_id)
    )
  );

-- Registering a picked file as a parcel's document.
--
-- The blob is already in the bucket when this runs - the storage policy put
-- it there under this parcel's prefix - and `file_object` has no insert policy
-- of its own, so this SECURITY DEFINER function makes the row, after checking
-- everything the policy could not know: that the caller may write this
-- parcel's documents, that the key really is under this parcel, the type and
-- size of the file, and that the blob is there with the size claimed.
--
-- A file that is already registered is normally refused: one that a document
-- already points at is that document's file. One that no document points at,
-- though, is the residue of a save that failed after registering - the form
-- is being retried - and gets the same id back rather than a refusal for a
-- file the caller already uploaded.
CREATE OR REPLACE FUNCTION public.land_document_register(p_land_id bigint, p_storage_key text, p_file_name text, p_mime_type text, p_size bigint, p_checksum text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_file bigint; v_ext text; v_meta jsonb; v_campus bigint; v_held record;
BEGIN
    SELECT campus_id INTO v_campus FROM land WHERE land_id = p_land_id;
    IF v_campus IS NULL THEN RAISE EXCEPTION 'Unknown land' USING ERRCODE = '22023'; END IF;
    IF NOT sims_private.can_campus(ARRAY['INSTITUTION.ALL.CREATE'::text], v_campus) THEN RAISE EXCEPTION 'Not authorised (INSTITUTION.ALL.CREATE)' USING ERRCODE = '42501'; END IF;
    IF sims_private.doc_land_id(p_storage_key) IS DISTINCT FROM p_land_id THEN RAISE EXCEPTION 'The file is not stored under this land' USING ERRCODE = '22023'; END IF;
    IF p_file_name IS NULL OR btrim(p_file_name) = '' OR length(p_file_name) > 255 THEN RAISE EXCEPTION 'The file name is required (at most 255 characters)' USING ERRCODE = '22023'; END IF;
    IF p_mime_type NOT IN ('application/pdf', 'image/jpeg', 'image/png') THEN RAISE EXCEPTION 'Only PDF, JPEG and PNG files are accepted' USING ERRCODE = '22023'; END IF;
    v_ext := lower(substring(p_file_name FROM '\.([A-Za-z0-9]{1,10})$'));
    IF v_ext IS NULL OR NOT ((p_mime_type = 'application/pdf' AND v_ext = 'pdf') OR (p_mime_type = 'image/jpeg' AND v_ext IN ('jpg', 'jpeg')) OR (p_mime_type = 'image/png' AND v_ext = 'png')) THEN
        RAISE EXCEPTION 'The file name does not match its type' USING ERRCODE = '22023';
    END IF;
    IF p_size IS NULL OR p_size <= 0 OR p_size > 10485760 THEN RAISE EXCEPTION 'The file must be between 1 byte and 10 MB' USING ERRCODE = '22023'; END IF;
    IF p_checksum IS NOT NULL AND p_checksum !~ '^[0-9A-Fa-f]{64}$' THEN RAISE EXCEPTION 'Invalid checksum' USING ERRCODE = '22023'; END IF;
    SELECT metadata INTO v_meta FROM storage.objects WHERE bucket_id = 'sims-documents' AND name = p_storage_key;
    IF NOT FOUND THEN RAISE EXCEPTION 'The file has not been uploaded' USING ERRCODE = '22023'; END IF;
    IF v_meta ? 'size' AND (v_meta ->> 'size')::bigint <> p_size THEN RAISE EXCEPTION 'The uploaded file size does not match' USING ERRCODE = '22023'; END IF;
    SELECT file_object_id, file_size_bytes, mime_type, original_file_name, deleted_at INTO v_held
    FROM file_object WHERE storage_key = p_storage_key;
    IF FOUND THEN
        IF v_held.deleted_at IS NOT NULL
           OR v_held.file_size_bytes <> p_size OR v_held.mime_type <> p_mime_type
           OR v_held.original_file_name <> btrim(p_file_name)
           OR EXISTS (SELECT 1 FROM land_document WHERE file_object_id = v_held.file_object_id)
           OR EXISTS (SELECT 1 FROM building_document WHERE file_object_id = v_held.file_object_id) THEN
            RAISE EXCEPTION 'That file is already registered' USING ERRCODE = '23505';
        END IF;
        RETURN v_held.file_object_id;
    END IF;
    INSERT INTO file_object (storage_provider, storage_key, original_file_name, mime_type, file_size_bytes, checksum_sha256, stored_file_name, file_extension, confidentiality_level, uploaded_by_user_id)
    VALUES ('supabase-storage', p_storage_key, btrim(p_file_name), p_mime_type, p_size, lower(p_checksum), split_part(p_storage_key, '/', 3), v_ext, 'INTERNAL', sims_private.current_user_id()) RETURNING file_object_id INTO v_file;
    RETURN v_file;
END $function$;

-- The same for a building's documents: the building's campus decides, the key
-- must sit under `building/<id>/`, everything else is the same check in the
-- same order.
CREATE OR REPLACE FUNCTION public.building_document_register(p_building_id bigint, p_storage_key text, p_file_name text, p_mime_type text, p_size bigint, p_checksum text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_file bigint; v_ext text; v_meta jsonb; v_campus bigint; v_held record;
BEGIN
    SELECT campus_id INTO v_campus FROM building WHERE building_id = p_building_id;
    IF v_campus IS NULL THEN RAISE EXCEPTION 'Unknown building' USING ERRCODE = '22023'; END IF;
    IF NOT sims_private.can_campus(ARRAY['INSTITUTION.ALL.CREATE'::text], v_campus) THEN RAISE EXCEPTION 'Not authorised (INSTITUTION.ALL.CREATE)' USING ERRCODE = '42501'; END IF;
    IF sims_private.doc_building_id(p_storage_key) IS DISTINCT FROM p_building_id THEN RAISE EXCEPTION 'The file is not stored under this building' USING ERRCODE = '22023'; END IF;
    IF p_file_name IS NULL OR btrim(p_file_name) = '' OR length(p_file_name) > 255 THEN RAISE EXCEPTION 'The file name is required (at most 255 characters)' USING ERRCODE = '22023'; END IF;
    IF p_mime_type NOT IN ('application/pdf', 'image/jpeg', 'image/png') THEN RAISE EXCEPTION 'Only PDF, JPEG and PNG files are accepted' USING ERRCODE = '22023'; END IF;
    v_ext := lower(substring(p_file_name FROM '\.([A-Za-z0-9]{1,10})$'));
    IF v_ext IS NULL OR NOT ((p_mime_type = 'application/pdf' AND v_ext = 'pdf') OR (p_mime_type = 'image/jpeg' AND v_ext IN ('jpg', 'jpeg')) OR (p_mime_type = 'image/png' AND v_ext = 'png')) THEN
        RAISE EXCEPTION 'The file name does not match its type' USING ERRCODE = '22023';
    END IF;
    IF p_size IS NULL OR p_size <= 0 OR p_size > 10485760 THEN RAISE EXCEPTION 'The file must be between 1 byte and 10 MB' USING ERRCODE = '22023'; END IF;
    IF p_checksum IS NOT NULL AND p_checksum !~ '^[0-9A-Fa-f]{64}$' THEN RAISE EXCEPTION 'Invalid checksum' USING ERRCODE = '22023'; END IF;
    SELECT metadata INTO v_meta FROM storage.objects WHERE bucket_id = 'sims-documents' AND name = p_storage_key;
    IF NOT FOUND THEN RAISE EXCEPTION 'The file has not been uploaded' USING ERRCODE = '22023'; END IF;
    IF v_meta ? 'size' AND (v_meta ->> 'size')::bigint <> p_size THEN RAISE EXCEPTION 'The uploaded file size does not match' USING ERRCODE = '22023'; END IF;
    SELECT file_object_id, file_size_bytes, mime_type, original_file_name, deleted_at INTO v_held
    FROM file_object WHERE storage_key = p_storage_key;
    IF FOUND THEN
        IF v_held.deleted_at IS NOT NULL
           OR v_held.file_size_bytes <> p_size OR v_held.mime_type <> p_mime_type
           OR v_held.original_file_name <> btrim(p_file_name)
           OR EXISTS (SELECT 1 FROM land_document WHERE file_object_id = v_held.file_object_id)
           OR EXISTS (SELECT 1 FROM building_document WHERE file_object_id = v_held.file_object_id) THEN
            RAISE EXCEPTION 'That file is already registered' USING ERRCODE = '23505';
        END IF;
        RETURN v_held.file_object_id;
    END IF;
    INSERT INTO file_object (storage_provider, storage_key, original_file_name, mime_type, file_size_bytes, checksum_sha256, stored_file_name, file_extension, confidentiality_level, uploaded_by_user_id)
    VALUES ('supabase-storage', p_storage_key, btrim(p_file_name), p_mime_type, p_size, lower(p_checksum), split_part(p_storage_key, '/', 3), v_ext, 'INTERNAL', sims_private.current_user_id()) RETURNING file_object_id INTO v_file;
    RETURN v_file;
END $function$;

-- Opening a parcel's document: where the file lives, for a signed URL.
--
-- The URL itself is minted by the storage service, which checks the caller may
-- select the blob - the read branch of the path helper. This checks the caller
-- may read the document row, says so separately when the row simply has no
-- file, and records the DOWNLOAD the way every other document opener does.
CREATE OR REPLACE FUNCTION public.land_document_download_info(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE d record; f record;
BEGIN
    SELECT d0.land_document_id, d0.land_id, l.campus_id INTO d
    FROM land_document d0 JOIN land l ON l.land_id = d0.land_id
    WHERE d0.land_document_id = p_id;
    IF d.land_document_id IS NULL OR NOT sims_private.can_campus(ARRAY['INSTITUTION.ALL.READ'::text], d.campus_id) THEN
        RAISE EXCEPTION 'Not authorised (INSTITUTION.ALL.READ) or unknown document' USING ERRCODE = '42501';
    END IF;
    SELECT x.storage_key, x.original_file_name, x.mime_type INTO f
    FROM file_object x JOIN land_document d0 ON d0.file_object_id = x.file_object_id
    WHERE d0.land_document_id = p_id AND x.deleted_at IS NULL;
    IF f.storage_key IS NULL THEN RAISE EXCEPTION 'This document has no file attached' USING ERRCODE = '22023'; END IF;
    INSERT INTO activity_audit (user_id, module_code, action_code, entity_name, entity_id, details)
    VALUES (sims_private.current_user_id(), 'INSTITUTION', 'DOWNLOAD', 'land_document', p_id::text, jsonb_build_object('land_id', d.land_id));
    RETURN jsonb_build_object('storage_key', f.storage_key, 'file_name', f.original_file_name, 'mime_type', f.mime_type);
END $function$;

CREATE OR REPLACE FUNCTION public.building_document_download_info(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE d record; f record;
BEGIN
    SELECT d0.building_document_id, d0.building_id, b.campus_id INTO d
    FROM building_document d0 JOIN building b ON b.building_id = d0.building_id
    WHERE d0.building_document_id = p_id;
    IF d.building_document_id IS NULL OR NOT sims_private.can_campus(ARRAY['INSTITUTION.ALL.READ'::text], d.campus_id) THEN
        RAISE EXCEPTION 'Not authorised (INSTITUTION.ALL.READ) or unknown document' USING ERRCODE = '42501';
    END IF;
    SELECT x.storage_key, x.original_file_name, x.mime_type INTO f
    FROM file_object x JOIN building_document d0 ON d0.file_object_id = x.file_object_id
    WHERE d0.building_document_id = p_id AND x.deleted_at IS NULL;
    IF f.storage_key IS NULL THEN RAISE EXCEPTION 'This document has no file attached' USING ERRCODE = '22023'; END IF;
    INSERT INTO activity_audit (user_id, module_code, action_code, entity_name, entity_id, details)
    VALUES (sims_private.current_user_id(), 'INSTITUTION', 'DOWNLOAD', 'building_document', p_id::text, jsonb_build_object('building_id', d.building_id));
    RETURN jsonb_build_object('storage_key', f.storage_key, 'file_name', f.original_file_name, 'mime_type', f.mime_type);
END $function$;

-- Not callable by anonymous callers: the helpers exist for the policies and
-- the RPCs, the RPCs for the signed-in form - the same shape as 021's document
-- functions, revoked from PUBLIC and granted to the roles that sign in.
REVOKE EXECUTE ON FUNCTION public.building_document_download_info(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.building_document_register(p_building_id bigint, p_storage_key text, p_file_name text, p_mime_type text, p_size bigint, p_checksum text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.land_document_download_info(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.land_document_register(p_land_id bigint, p_storage_key text, p_file_name text, p_mime_type text, p_size bigint, p_checksum text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.can_use_building_doc_path(p_name text, p_write boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.can_use_land_doc_path(p_name text, p_write boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.doc_building_id(p_name text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.doc_land_id(p_name text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.building_document_download_info(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.building_document_download_info(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.building_document_download_info(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.building_document_register(p_building_id bigint, p_storage_key text, p_file_name text, p_mime_type text, p_size bigint, p_checksum text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.building_document_register(p_building_id bigint, p_storage_key text, p_file_name text, p_mime_type text, p_size bigint, p_checksum text) TO postgres;
GRANT EXECUTE ON FUNCTION public.building_document_register(p_building_id bigint, p_storage_key text, p_file_name text, p_mime_type text, p_size bigint, p_checksum text) TO service_role;
GRANT EXECUTE ON FUNCTION public.land_document_download_info(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.land_document_download_info(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.land_document_download_info(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.land_document_register(p_land_id bigint, p_storage_key text, p_file_name text, p_mime_type text, p_size bigint, p_checksum text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.land_document_register(p_land_id bigint, p_storage_key text, p_file_name text, p_mime_type text, p_size bigint, p_checksum text) TO postgres;
GRANT EXECUTE ON FUNCTION public.land_document_register(p_land_id bigint, p_storage_key text, p_file_name text, p_mime_type text, p_size bigint, p_checksum text) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.can_use_building_doc_path(p_name text, p_write boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.can_use_building_doc_path(p_name text, p_write boolean) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.can_use_land_doc_path(p_name text, p_write boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.can_use_land_doc_path(p_name text, p_write boolean) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.doc_building_id(p_name text) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.doc_building_id(p_name text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.doc_land_id(p_name text) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.doc_land_id(p_name text) TO postgres;
