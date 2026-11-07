-- =============================================================================================
-- 021. finance_rpcs
-- ---------------------------------------------------------------------------------------------
-- GENERATED FILE - do not edit by hand.
-- Regenerate with: npm run migrate:build   (python tools/translate.py && python tools/build_migrations.py)
--
-- Source of truth: the live Supabase catalogue (tools/catalogue/live_catalogue.json),
-- dumped read-only from project khqqfgqvwdxlqkncwtmh by tools/dump_catalogue.py.
-- =============================================================================================

-- -----------------------------------------------------------------------------
-- The remaining public functions and every grant.
--
-- The grants are emitted from the live ACLs: `authenticated` may call the
-- public RPCs, `service_role` bypasses RLS, and `sims_private` stays out of
-- the Data API (it is not listed in supabase/config.toml).
-- -----------------------------------------------------------------------------
-- -----------------------------------------------------------------------------
-- Remaining public functions
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admission_apply(p_applicant jsonb, p_application jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_prog integer := (p_application ->> 'programme_id')::integer;
    v_number text := NULLIF(btrim(p_application ->> 'application_number'), '');
    v_applicant bigint := NULLIF(p_application ->> 'admission_applicant_id', '')::bigint;
    v_first text := NULLIF(btrim(p_applicant ->> 'first_name'), '');
    v_mid text := NULLIF(btrim(p_applicant ->> 'middle_name'), '');
    v_last text := NULLIF(btrim(p_applicant ->> 'last_name'), '');
    v_email text := NULLIF(btrim(p_applicant ->> 'primary_email'), '');
    v_dob date := NULLIF(p_applicant ->> 'date_of_birth', '')::date;
    v_id bigint; v_constraint text;
BEGIN
    IF p_application IS NULL OR jsonb_typeof(p_application) <> 'object' OR v_prog IS NULL THEN
        RAISE EXCEPTION 'p_application with programme_id is required' USING ERRCODE = '22023';
    END IF;
    IF NOT sims_private.can_programme(ARRAY['ADMISSION.ALL.CREATE']::text[], v_prog) THEN
        RAISE EXCEPTION 'Not authorised to register applications for this programme' USING ERRCODE = '42501';
    END IF;
    IF v_number IS NULL OR (p_application ->> 'academic_year_id') IS NULL OR (p_application ->> 'application_date') IS NULL THEN
        RAISE EXCEPTION 'application_number, academic_year_id and application_date are required' USING ERRCODE = '22023';
    END IF;

    IF v_applicant IS NOT NULL THEN
        IF NOT sims_private.can_see_applicant(v_applicant) THEN
            RAISE EXCEPTION 'Not authorised to use this applicant, or it does not exist' USING ERRCODE = '42501';
        END IF;
    ELSE
        IF p_applicant IS NULL OR jsonb_typeof(p_applicant) <> 'object' OR v_first IS NULL THEN
            RAISE EXCEPTION 'first_name is required for a new applicant' USING ERRCODE = '22023';
        END IF;
        IF v_email IS NOT NULL AND v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN
            RAISE EXCEPTION 'primary_email is not a valid email address' USING ERRCODE = '22023';
        END IF;
        IF v_dob IS NOT NULL AND (v_dob >= current_date OR v_dob < DATE '1900-01-01') THEN
            RAISE EXCEPTION 'date_of_birth is not plausible' USING ERRCODE = '22023';
        END IF;
        INSERT INTO admission_applicant (first_name, middle_name, last_name, display_name, date_of_birth, gender_id, primary_email, primary_phone,
                                         nationality_country_id, social_category_id)
        VALUES (v_first, v_mid, v_last, btrim(concat_ws(' ', v_first, v_mid, v_last)), v_dob, NULLIF(p_applicant ->> 'gender_id', '')::smallint, v_email,
                NULLIF(btrim(p_applicant ->> 'primary_phone'), ''), NULLIF(p_applicant ->> 'nationality_country_id', '')::integer,
                NULLIF(p_applicant ->> 'social_category_id', '')::integer)
        RETURNING admission_applicant_id INTO v_applicant;
    END IF;

    BEGIN
        INSERT INTO admission_application (application_number, admission_applicant_id, programme_id, academic_year_id, admission_category_id, application_date, remarks)
        VALUES (v_number, v_applicant, v_prog, (p_application ->> 'academic_year_id')::integer, NULLIF(p_application ->> 'admission_category_id', '')::integer,
                (p_application ->> 'application_date')::date, NULLIF(btrim(p_application ->> 'remarks'), ''))
        RETURNING application_id INTO v_id;
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF v_constraint = 'admission_application_application_number_key' THEN
            RAISE EXCEPTION 'Application number is already in use' USING ERRCODE = '23505';
        END IF;
        RAISE;
    END;
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.admission_set_status(p_application_id bigint, p_new_status text, p_remarks text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_old text; v_action text := sims_private.admission_action_for(p_new_status);
BEGIN
    IF p_new_status = 'ADMITTED' THEN
        RAISE EXCEPTION 'Use admission_admit() to admit an applicant' USING ERRCODE = '45000';
    END IF;
    IF v_action IS NULL THEN RAISE EXCEPTION 'Unknown or unsupported target status %', p_new_status USING ERRCODE = '22023'; END IF;
    PERFORM sims_private.admission_authorize(p_application_id, v_action);
    SELECT application_status INTO v_old FROM admission_application WHERE application_id = p_application_id FOR UPDATE;
    IF v_old = p_new_status THEN RETURN; END IF;  -- idempotent replay
    IF NOT sims_private.admission_transition_ok(v_old, p_new_status) THEN
        RAISE EXCEPTION 'An application cannot move from % to %', v_old, p_new_status USING ERRCODE = '45000';
    END IF;
    UPDATE admission_application SET
        application_status = p_new_status,
        eligibility_status = CASE p_new_status WHEN 'ELIGIBLE' THEN 'ELIGIBLE' WHEN 'INELIGIBLE' THEN 'INELIGIBLE' ELSE eligibility_status END,
        remarks = COALESCE(NULLIF(btrim(p_remarks), ''), remarks)
    WHERE application_id = p_application_id;
END $function$;

CREATE OR REPLACE FUNCTION public.admission_update_applicant(p_applicant_id bigint, p jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_ok boolean; v_email text := NULLIF(btrim(p ->> 'primary_email'), ''); v_dob date := NULLIF(p ->> 'date_of_birth', '')::date;
BEGIN
    SELECT sims_private.can_global(ARRAY['ADMISSION.ALL.UPDATE']::text[])
        OR EXISTS (SELECT 1 FROM admission_application a WHERE a.admission_applicant_id = p_applicant_id
                   AND sims_private.can_programme(ARRAY['ADMISSION.ALL.UPDATE']::text[], a.programme_id)) INTO v_ok;
    IF NOT v_ok OR NOT EXISTS (SELECT 1 FROM admission_applicant WHERE admission_applicant_id = p_applicant_id) THEN
        RAISE EXCEPTION 'Not authorised to update this applicant, or it does not exist' USING ERRCODE = '42501';
    END IF;
    IF p ? 'first_name' AND NULLIF(btrim(p ->> 'first_name'), '') IS NULL THEN RAISE EXCEPTION 'first_name cannot be blank' USING ERRCODE = '22023'; END IF;
    IF v_email IS NOT NULL AND v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN RAISE EXCEPTION 'primary_email is not a valid email address' USING ERRCODE = '22023'; END IF;
    IF v_dob IS NOT NULL AND (v_dob >= current_date OR v_dob < DATE '1900-01-01') THEN RAISE EXCEPTION 'date_of_birth is not plausible' USING ERRCODE = '22023'; END IF;
    UPDATE admission_applicant SET
        first_name = CASE WHEN p ? 'first_name' THEN btrim(p ->> 'first_name') ELSE first_name END,
        middle_name = CASE WHEN p ? 'middle_name' THEN NULLIF(btrim(p ->> 'middle_name'), '') ELSE middle_name END,
        last_name = CASE WHEN p ? 'last_name' THEN NULLIF(btrim(p ->> 'last_name'), '') ELSE last_name END,
        date_of_birth = CASE WHEN p ? 'date_of_birth' THEN v_dob ELSE date_of_birth END,
        gender_id = CASE WHEN p ? 'gender_id' THEN NULLIF(p ->> 'gender_id', '')::smallint ELSE gender_id END,
        primary_email = CASE WHEN p ? 'primary_email' THEN v_email ELSE primary_email END,
        primary_phone = CASE WHEN p ? 'primary_phone' THEN NULLIF(btrim(p ->> 'primary_phone'), '') ELSE primary_phone END,
        nationality_country_id = CASE WHEN p ? 'nationality_country_id' THEN NULLIF(p ->> 'nationality_country_id', '')::integer ELSE nationality_country_id END,
        social_category_id = CASE WHEN p ? 'social_category_id' THEN NULLIF(p ->> 'social_category_id', '')::integer ELSE social_category_id END
    WHERE admission_applicant_id = p_applicant_id;
    UPDATE admission_applicant SET display_name = btrim(concat_ws(' ', first_name, middle_name, last_name)) WHERE admission_applicant_id = p_applicant_id;
END $function$;

CREATE OR REPLACE FUNCTION public.admission_update_application(p_application_id bigint, p jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_status text;
BEGIN
    PERFORM sims_private.admission_authorize(p_application_id, 'UPDATE');
    SELECT application_status INTO v_status FROM admission_application WHERE application_id = p_application_id FOR UPDATE;
    IF v_status IN ('ADMITTED', 'REJECTED', 'CANCELLED') THEN
        RAISE EXCEPTION 'A % application can no longer be edited', v_status USING ERRCODE = '45000';
    END IF;
    UPDATE admission_application SET
        remarks = CASE WHEN p ? 'remarks' THEN NULLIF(btrim(p ->> 'remarks'), '') ELSE remarks END,
        admission_category_id = CASE WHEN p ? 'admission_category_id' THEN NULLIF(p ->> 'admission_category_id', '')::integer ELSE admission_category_id END
    WHERE application_id = p_application_id;
END $function$;

CREATE OR REPLACE FUNCTION public.announcement_archive(p_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v record;
BEGIN
    SELECT a.department_id, a.approval_status, aa.user_id INTO v FROM announcement a LEFT JOIN sims_private.announcement_author aa ON aa.announcement_id = a.announcement_id WHERE a.announcement_id = p_id FOR UPDATE OF a;
    IF v IS NULL OR NOT (sims_private.announcement_can('UPDATE', v.department_id) OR (v.user_id IS NOT DISTINCT FROM sims_private.current_user_id() AND v.approval_status IN ('DRAFT', 'REJECTED'))) THEN
        RAISE EXCEPTION 'Not authorised (COMMUNICATION.ALL.UPDATE) or unknown announcement' USING ERRCODE = '42501';
    END IF;
    IF v.approval_status = 'ARCHIVED' THEN RETURN; END IF;
    IF v.approval_status = 'PENDING' THEN RAISE EXCEPTION 'Approve or reject the announcement before archiving it' USING ERRCODE = '45000'; END IF;
    UPDATE announcement SET approval_status = 'ARCHIVED' WHERE announcement_id = p_id;
END $function$;

CREATE OR REPLACE FUNCTION public.announcement_attachment_download_info(p_id bigint, p_file_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE f record;
BEGIN
    SELECT f0.storage_key, f0.original_file_name, f0.mime_type INTO f FROM announcement_attachment t JOIN file_object f0 ON f0.file_object_id = t.file_object_id
     WHERE t.announcement_id = p_id AND t.file_object_id = p_file_id AND f0.deleted_at IS NULL;
    IF f.storage_key IS NULL OR NOT sims_private.announcement_visible(p_id) THEN RAISE EXCEPTION 'Unknown announcement or file' USING ERRCODE = '42501'; END IF;
    INSERT INTO activity_audit (user_id, module_code, action_code, entity_name, entity_id, details)
    VALUES (sims_private.current_user_id(), 'COMMUNICATION', 'DOWNLOAD', 'announcement_attachment', p_id::text, jsonb_build_object('file_object_id', p_file_id));
    RETURN jsonb_build_object('storage_key', f.storage_key, 'file_name', f.original_file_name, 'mime_type', f.mime_type);
END $function$;

CREATE OR REPLACE FUNCTION public.announcement_attachment_register(p_id bigint, p_storage_key text, p_file_name text, p_mime_type text, p_size bigint, p_checksum text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_file bigint; v_ext text; v_meta jsonb; v_n integer;
BEGIN
    IF NOT sims_private.announcement_editable(p_id) THEN RAISE EXCEPTION 'Not authorised (COMMUNICATION.ALL.UPDATE) or the announcement can no longer be edited' USING ERRCODE = '42501'; END IF;
    IF sims_private.doc_announcement_id(p_storage_key) IS DISTINCT FROM p_id THEN RAISE EXCEPTION 'The file is not stored under this announcement' USING ERRCODE = '22023'; END IF;
    IF p_file_name IS NULL OR btrim(p_file_name) = '' OR length(p_file_name) > 255 THEN RAISE EXCEPTION 'The file name is required (at most 255 characters)' USING ERRCODE = '22023'; END IF;
    IF p_mime_type NOT IN ('application/pdf', 'image/jpeg', 'image/png') THEN RAISE EXCEPTION 'Only PDF, JPEG and PNG files are accepted' USING ERRCODE = '22023'; END IF;
    v_ext := lower(substring(p_file_name FROM '\.([A-Za-z0-9]{1,10})$'));
    IF v_ext IS NULL OR NOT ((p_mime_type = 'application/pdf' AND v_ext = 'pdf') OR (p_mime_type = 'image/jpeg' AND v_ext IN ('jpg', 'jpeg')) OR (p_mime_type = 'image/png' AND v_ext = 'png')) THEN RAISE EXCEPTION 'The file name does not match its type' USING ERRCODE = '22023'; END IF;
    IF p_size IS NULL OR p_size <= 0 OR p_size > 10485760 THEN RAISE EXCEPTION 'The file must be between 1 byte and 10 MB' USING ERRCODE = '22023'; END IF;
    IF p_checksum IS NOT NULL AND p_checksum !~ '^[0-9A-Fa-f]{64}$' THEN RAISE EXCEPTION 'Invalid checksum' USING ERRCODE = '22023'; END IF;
    SELECT count(*) INTO v_n FROM announcement_attachment WHERE announcement_id = p_id;
    IF v_n >= 10 THEN RAISE EXCEPTION 'An announcement can have at most 10 attachments' USING ERRCODE = '45000'; END IF;
    SELECT metadata INTO v_meta FROM storage.objects WHERE bucket_id = 'sims-documents' AND name = p_storage_key;
    IF NOT FOUND THEN RAISE EXCEPTION 'The file has not been uploaded' USING ERRCODE = '22023'; END IF;
    IF v_meta ? 'size' AND (v_meta ->> 'size')::bigint <> p_size THEN RAISE EXCEPTION 'The uploaded file size does not match' USING ERRCODE = '22023'; END IF;
    IF EXISTS (SELECT 1 FROM file_object WHERE storage_key = p_storage_key) THEN RAISE EXCEPTION 'That file is already registered' USING ERRCODE = '23505'; END IF;
    INSERT INTO file_object (storage_provider, storage_key, original_file_name, mime_type, file_size_bytes, checksum_sha256, stored_file_name, file_extension, confidentiality_level, uploaded_by_user_id)
    VALUES ('supabase-storage', p_storage_key, btrim(p_file_name), p_mime_type, p_size, lower(p_checksum), split_part(p_storage_key, '/', 3), v_ext, 'INTERNAL', sims_private.current_user_id()) RETURNING file_object_id INTO v_file;
    INSERT INTO announcement_attachment (announcement_id, file_object_id, display_order) VALUES (p_id, v_file, v_n + 1);
    RETURN v_file;
END $function$;

CREATE OR REPLACE FUNCTION public.announcement_attachment_remove(p_id bigint, p_file_id bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_key text;
BEGIN
    IF NOT sims_private.announcement_editable(p_id) THEN RAISE EXCEPTION 'Not authorised (COMMUNICATION.ALL.UPDATE) or the announcement can no longer be edited' USING ERRCODE = '42501'; END IF;
    SELECT f.storage_key INTO v_key FROM announcement_attachment t JOIN file_object f ON f.file_object_id = t.file_object_id WHERE t.announcement_id = p_id AND t.file_object_id = p_file_id;
    IF v_key IS NULL THEN RAISE EXCEPTION 'Unknown file' USING ERRCODE = '22023'; END IF;
    DELETE FROM announcement_attachment WHERE announcement_id = p_id AND file_object_id = p_file_id;
    DELETE FROM file_object WHERE file_object_id = p_file_id;
    RETURN v_key;
END $function$;

CREATE OR REPLACE FUNCTION public.announcement_decide(p_id bigint, p_approve boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v record; v_to text := CASE WHEN p_approve THEN 'APPROVED' ELSE 'REJECTED' END;
BEGIN
    SELECT a.department_id, a.approval_status, aa.user_id INTO v FROM announcement a LEFT JOIN sims_private.announcement_author aa ON aa.announcement_id = a.announcement_id WHERE a.announcement_id = p_id FOR UPDATE OF a;
    IF v IS NULL OR NOT sims_private.announcement_can('APPROVE', v.department_id) THEN RAISE EXCEPTION 'Not authorised (COMMUNICATION.ALL.APPROVE) or unknown announcement' USING ERRCODE = '42501'; END IF;
    IF v.user_id IS NOT DISTINCT FROM sims_private.current_user_id() AND NOT sims_private.can_global(ARRAY['COMMUNICATION.ALL.CONFIGURE']::text[]) THEN
        RAISE EXCEPTION 'You cannot approve or reject your own announcement' USING ERRCODE = '42501';
    END IF;
    IF v.approval_status = v_to THEN RETURN; END IF; -- idempotent replay
    IF v.approval_status <> 'PENDING' THEN RAISE EXCEPTION 'Only a PENDING announcement can be approved or rejected (this one is %)', v.approval_status USING ERRCODE = '45000'; END IF;
    UPDATE announcement SET approval_status = v_to WHERE announcement_id = p_id;
END $function$;

CREATE OR REPLACE FUNCTION public.announcement_save(p_id bigint, p_type_id integer, p_department_id integer, p_title text, p_description text, p_publish_from timestamp with time zone, p_publish_to timestamp with time zone, p_audience text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v record; v_id bigint; v_author bigint;
BEGIN
    PERFORM sims_private.announcement_check(p_type_id, p_department_id, p_title, p_description, p_publish_from, p_publish_to, p_audience);
    IF p_id IS NULL THEN
        IF NOT sims_private.announcement_can('CREATE', p_department_id) THEN RAISE EXCEPTION 'Not authorised (COMMUNICATION.ALL.CREATE) for this department' USING ERRCODE = '42501'; END IF;
        INSERT INTO announcement (announcement_type_id, department_id, title, description, publish_from, publish_to, approval_status, audience_type)
        VALUES (p_type_id, p_department_id, btrim(p_title), btrim(p_description), p_publish_from, p_publish_to, 'DRAFT', p_audience) RETURNING announcement_id INTO v_id;
        INSERT INTO sims_private.announcement_author (announcement_id, user_id) VALUES (v_id, sims_private.current_user_id());
        RETURN v_id;
    END IF;
    SELECT a.announcement_id, a.department_id, a.approval_status, aa.user_id INTO v FROM announcement a LEFT JOIN sims_private.announcement_author aa ON aa.announcement_id = a.announcement_id
    WHERE a.announcement_id = p_id FOR UPDATE OF a;
    IF v IS NULL OR NOT (v.user_id IS NOT DISTINCT FROM sims_private.current_user_id() OR sims_private.announcement_can('UPDATE', v.department_id)) THEN
        RAISE EXCEPTION 'Not authorised (COMMUNICATION.ALL.UPDATE) or unknown announcement' USING ERRCODE = '42501';
    END IF;
    IF v.approval_status NOT IN ('DRAFT', 'REJECTED') THEN RAISE EXCEPTION 'A % announcement cannot be edited', v.approval_status USING ERRCODE = '45000'; END IF;
    -- moving it to another department needs the right to create there
    IF p_department_id IS DISTINCT FROM v.department_id AND NOT sims_private.announcement_can('CREATE', p_department_id) THEN
        RAISE EXCEPTION 'Not authorised (COMMUNICATION.ALL.CREATE) for that department' USING ERRCODE = '42501';
    END IF;
    UPDATE announcement SET announcement_type_id = p_type_id, department_id = p_department_id, title = btrim(p_title), description = btrim(p_description), publish_from = p_publish_from,
        publish_to = p_publish_to, audience_type = p_audience, approval_status = 'DRAFT' WHERE announcement_id = p_id;
    RETURN p_id;
END $function$;

CREATE OR REPLACE FUNCTION public.announcement_submit(p_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v record;
BEGIN
    SELECT a.department_id, a.approval_status, aa.user_id INTO v FROM announcement a LEFT JOIN sims_private.announcement_author aa ON aa.announcement_id = a.announcement_id WHERE a.announcement_id = p_id FOR UPDATE OF a;
    IF v IS NULL OR NOT (v.user_id IS NOT DISTINCT FROM sims_private.current_user_id() OR sims_private.announcement_can('UPDATE', v.department_id)) THEN
        RAISE EXCEPTION 'Not authorised (COMMUNICATION.ALL.UPDATE) or unknown announcement' USING ERRCODE = '42501';
    END IF;
    IF v.approval_status = 'PENDING' THEN RETURN; END IF; -- idempotent replay
    IF v.approval_status NOT IN ('DRAFT', 'REJECTED') THEN RAISE EXCEPTION 'A % announcement cannot be submitted', v.approval_status USING ERRCODE = '45000'; END IF;
    UPDATE announcement SET approval_status = 'PENDING' WHERE announcement_id = p_id;
END $function$;

CREATE OR REPLACE FUNCTION public.assessment_enter_marks(p_event_id bigint, p_marks jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_ev record; v_prog integer; v_can_update boolean; m jsonb; v_reg bigint; v_att text; v_marks numeric; v_red numeric; v_seen bigint[] := '{}'; v_n integer := 0;
BEGIN
    SELECT assessment_event_id, course_offering_id, status INTO v_ev FROM assessment_event WHERE assessment_event_id = p_event_id FOR UPDATE;
    IF v_ev IS NULL THEN RAISE EXCEPTION 'Not authorised (ASSESSMENT.ALL.CREATE) or unknown event' USING ERRCODE = '42501'; END IF;
    v_prog := sims_private.asm_authorize(v_ev.course_offering_id, 'ASSESSMENT', 'CREATE');
    v_can_update := sims_private.can_programme(ARRAY['ASSESSMENT.ALL.UPDATE']::text[], v_prog);
    IF v_ev.status IN ('PUBLISHED', 'CANCELLED') THEN RAISE EXCEPTION 'Marks of a % event cannot be changed', v_ev.status USING ERRCODE = '45000'; END IF;
    IF p_marks IS NULL OR jsonb_typeof(p_marks) <> 'array' OR jsonb_array_length(p_marks) = 0 OR jsonb_array_length(p_marks) > 1000 THEN
        RAISE EXCEPTION 'p_marks must be a non-empty array of at most 1000 entries' USING ERRCODE = '22023';
    END IF;
    FOR m IN SELECT * FROM jsonb_array_elements(p_marks) LOOP
        v_reg := (m ->> 'course_registration_id')::bigint;
        v_att := COALESCE(NULLIF(m ->> 'attendance_status', ''), 'PRESENT');
        v_marks := NULLIF(m ->> 'marks_obtained', '')::numeric;
        v_red := NULLIF(m ->> 'reduced_marks', '')::numeric;
        IF v_reg IS NULL THEN RAISE EXCEPTION 'Each entry needs course_registration_id' USING ERRCODE = '22023'; END IF;
        IF v_reg = ANY (v_seen) THEN RAISE EXCEPTION 'Duplicate course registration % in the payload', v_reg USING ERRCODE = '22023'; END IF;
        v_seen := v_seen || v_reg;
        IF v_att NOT IN ('PRESENT', 'ABSENT', 'EXEMPTED', 'MALPRACTICE') THEN RAISE EXCEPTION 'Unknown attendance status %', v_att USING ERRCODE = '22023'; END IF;
        IF v_marks IS NOT NULL AND (v_marks < 0 OR v_marks <> round(v_marks, 2)) OR v_red IS NOT NULL AND (v_red < 0 OR v_red <> round(v_red, 2)) THEN
            RAISE EXCEPTION 'Marks must be non-negative with at most 2 decimals' USING ERRCODE = '22023';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM student_course_registration WHERE course_registration_id = v_reg AND course_offering_id = v_ev.course_offering_id
                       AND registration_status IN ('REGISTERED', 'APPROVED', 'COMPLETED')) THEN
            RAISE EXCEPTION 'Course registration % is not an active registration for this course offering', v_reg USING ERRCODE = '45000';
        END IF;
        IF NOT v_can_update AND EXISTS (SELECT 1 FROM student_assessment_mark WHERE assessment_event_id = p_event_id AND course_registration_id = v_reg) THEN
            RAISE EXCEPTION 'Not authorised (ASSESSMENT.ALL.UPDATE) to change marks that are already entered' USING ERRCODE = '42501';
        END IF;
        INSERT INTO student_assessment_mark (assessment_event_id, course_registration_id, course_offering_id, attendance_status, marks_obtained, reduced_marks, remarks, evaluated_at)
        VALUES (p_event_id, v_reg, v_ev.course_offering_id, v_att, v_marks, v_red, NULLIF(btrim(m ->> 'remarks'), ''), now())
        ON CONFLICT (assessment_event_id, course_registration_id)
        DO UPDATE SET attendance_status = EXCLUDED.attendance_status, marks_obtained = EXCLUDED.marks_obtained, reduced_marks = EXCLUDED.reduced_marks,
                      remarks = EXCLUDED.remarks, evaluated_at = now();
        v_n := v_n + 1;
    END LOOP;
    IF v_ev.status = 'PLANNED' THEN UPDATE assessment_event SET status = 'CONDUCTED' WHERE assessment_event_id = p_event_id; END IF;
    RETURN v_n;
END $function$;

CREATE OR REPLACE FUNCTION public.attendance_decide_correction(p_correction_id bigint, p_approve boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_c record; v_cos bigint; v_current integer;
BEGIN
    SELECT * INTO v_c FROM attendance_correction_request WHERE attendance_correction_id = p_correction_id FOR UPDATE;
    v_cos := CASE WHEN v_c IS NULL THEN NULL ELSE sims_private.att_session_cos(v_c.class_session_id) END;
    IF v_cos IS NULL THEN RAISE EXCEPTION 'Not authorised (ATTENDANCE.ALL.APPROVE) or unknown correction' USING ERRCODE = '42501'; END IF;
    PERFORM sims_private.att_authorize_cos(v_cos, 'ATTENDANCE', 'APPROVE');
    IF v_c.request_status = (CASE WHEN p_approve THEN 'APPROVED' ELSE 'REJECTED' END) THEN RETURN; END IF;  -- idempotent replay
    IF v_c.request_status <> 'PENDING' THEN RAISE EXCEPTION 'The correction is already %', v_c.request_status USING ERRCODE = '45000'; END IF;
    IF p_approve THEN
        SELECT attendance_status_id INTO v_current FROM student_attendance WHERE class_session_id = v_c.class_session_id AND course_offering_section_student_id = v_c.course_offering_section_student_id FOR UPDATE;
        IF v_current IS DISTINCT FROM v_c.old_status_id THEN
            RAISE EXCEPTION 'The attendance has changed since this correction was requested' USING ERRCODE = '45000';
        END IF;
        UPDATE student_attendance SET attendance_status_id = v_c.requested_status_id, marked_at = now(), marked_by_user_id = sims_private.current_user_id()
         WHERE class_session_id = v_c.class_session_id AND course_offering_section_student_id = v_c.course_offering_section_student_id;
    END IF;
    UPDATE attendance_correction_request SET request_status = CASE WHEN p_approve THEN 'APPROVED' ELSE 'REJECTED' END, resolved_at = now() WHERE attendance_correction_id = p_correction_id;
END $function$;

CREATE OR REPLACE FUNCTION public.attendance_mark(p_session_id bigint, p_marks jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_cos bigint := sims_private.att_session_cos(p_session_id);
    v_prog integer; v_status text; v_can_update boolean; m jsonb; v_roster bigint; v_st integer; v_seen bigint[] := '{}'; v_n integer := 0;
BEGIN
    IF v_cos IS NULL THEN RAISE EXCEPTION 'Not authorised (ATTENDANCE.ALL.CREATE) or unknown session' USING ERRCODE = '42501'; END IF;
    v_prog := sims_private.att_authorize_cos(v_cos, 'ATTENDANCE', 'CREATE');
    v_can_update := sims_private.can_programme(ARRAY['ATTENDANCE.ALL.UPDATE']::text[], v_prog);
    IF p_marks IS NULL OR jsonb_typeof(p_marks) <> 'array' OR jsonb_array_length(p_marks) = 0 OR jsonb_array_length(p_marks) > 1000 THEN
        RAISE EXCEPTION 'p_marks must be a non-empty array of at most 1000 entries' USING ERRCODE = '22023';
    END IF;
    SELECT session_status INTO v_status FROM class_session WHERE class_session_id = p_session_id FOR UPDATE;
    IF v_status IN ('CANCELLED', 'RESCHEDULED') THEN
        RAISE EXCEPTION 'Attendance cannot be marked for a % session', v_status USING ERRCODE = '45000';
    END IF;

    FOR m IN SELECT * FROM jsonb_array_elements(p_marks) LOOP
        v_roster := (m ->> 'roster_id')::bigint;
        v_st := (m ->> 'status_id')::integer;
        IF v_roster IS NULL OR v_st IS NULL THEN RAISE EXCEPTION 'Each mark needs roster_id and status_id' USING ERRCODE = '22023'; END IF;
        IF v_roster = ANY (v_seen) THEN RAISE EXCEPTION 'Duplicate roster entry % in the payload', v_roster USING ERRCODE = '22023'; END IF;
        v_seen := v_seen || v_roster;
        IF NOT EXISTS (SELECT 1 FROM course_offering_section_student WHERE course_offering_section_student_id = v_roster AND course_offering_section_id = v_cos AND roster_status = 'ACTIVE') THEN
            RAISE EXCEPTION 'Roster entry % is not an active member of this teaching section', v_roster USING ERRCODE = '45000';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM attendance_status WHERE attendance_status_id = v_st AND is_active) THEN
            RAISE EXCEPTION 'Unknown or inactive attendance status %', v_st USING ERRCODE = '22023';
        END IF;
        IF NOT v_can_update AND EXISTS (SELECT 1 FROM student_attendance WHERE class_session_id = p_session_id AND course_offering_section_student_id = v_roster) THEN
            RAISE EXCEPTION 'Not authorised (ATTENDANCE.ALL.UPDATE) to change attendance that is already marked' USING ERRCODE = '42501';
        END IF;
        INSERT INTO student_attendance (class_session_id, course_offering_section_student_id, course_offering_section_id, attendance_status_id, marked_by_user_id, remarks)
        VALUES (p_session_id, v_roster, v_cos, v_st, sims_private.current_user_id(), NULLIF(btrim(m ->> 'remarks'), ''))
        ON CONFLICT (class_session_id, course_offering_section_student_id)
        DO UPDATE SET attendance_status_id = EXCLUDED.attendance_status_id, marked_at = now(), marked_by_user_id = EXCLUDED.marked_by_user_id, remarks = EXCLUDED.remarks;
        v_n := v_n + 1;
    END LOOP;
    IF v_status = 'PLANNED' THEN UPDATE class_session SET session_status = 'CONDUCTED' WHERE class_session_id = p_session_id; END IF;
    RETURN v_n;
END $function$;

CREATE OR REPLACE FUNCTION public.attendance_request_correction(p_session_id bigint, p_roster_id bigint, p_requested_status_id integer, p_reason text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_cos bigint := sims_private.att_session_cos(p_session_id); v_old integer; v_id bigint; v_pending record;
BEGIN
    IF v_cos IS NULL THEN RAISE EXCEPTION 'Not authorised (ATTENDANCE.ALL.CREATE) or unknown session' USING ERRCODE = '42501'; END IF;
    PERFORM sims_private.att_authorize_cos(v_cos, 'ATTENDANCE', 'CREATE');
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN RAISE EXCEPTION 'A reason is required' USING ERRCODE = '22023'; END IF;
    IF NOT EXISTS (SELECT 1 FROM attendance_status WHERE attendance_status_id = p_requested_status_id AND is_active) THEN
        RAISE EXCEPTION 'Unknown or inactive attendance status' USING ERRCODE = '22023';
    END IF;
    SELECT attendance_status_id INTO v_old FROM student_attendance WHERE class_session_id = p_session_id AND course_offering_section_student_id = p_roster_id;
    IF v_old IS NULL THEN RAISE EXCEPTION 'No attendance has been marked for this student in this session' USING ERRCODE = '45000'; END IF;
    IF v_old = p_requested_status_id THEN RAISE EXCEPTION 'The requested status is the same as the current one' USING ERRCODE = '45000'; END IF;
    SELECT attendance_correction_id, requested_status_id INTO v_pending FROM attendance_correction_request
     WHERE class_session_id = p_session_id AND course_offering_section_student_id = p_roster_id AND request_status = 'PENDING';
    IF FOUND THEN
        IF v_pending.requested_status_id = p_requested_status_id THEN RETURN v_pending.attendance_correction_id; END IF;  -- idempotent replay
        RAISE EXCEPTION 'A different correction is already pending for this student and session' USING ERRCODE = '45000';
    END IF;
    INSERT INTO attendance_correction_request (class_session_id, course_offering_section_student_id, old_status_id, requested_status_id, reason)
    VALUES (p_session_id, p_roster_id, v_old, p_requested_status_id, btrim(p_reason)) RETURNING attendance_correction_id INTO v_id;
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.auth_failure_record(p_username text, p_reason text DEFAULT 'INVALID_CREDENTIALS'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_name text := left(btrim(regexp_replace(COALESCE(p_username, ''), '[[:cntrl:]]', '', 'g')), 100); v_reason text; v_uid bigint;
BEGIN
    IF v_name = '' THEN RETURN; END IF;
    v_reason := CASE WHEN p_reason IN ('INVALID_CREDENTIALS', 'EMAIL_NOT_CONFIRMED', 'MFA_FAILED') THEN p_reason ELSE 'OTHER' END;
    IF (SELECT count(*) FROM login_audit WHERE NOT was_successful AND login_at > now() - interval '1 hour') >= 5000 THEN RETURN; END IF;
    IF (SELECT count(*) FROM login_audit WHERE NOT was_successful AND lower(username_attempted) = lower(v_name) AND login_at > now() - interval '1 hour') >= 20 THEN RETURN; END IF;
    SELECT user_id INTO v_uid FROM user_account WHERE lower(email) = lower(v_name) OR lower(username) = lower(v_name) LIMIT 1;
    INSERT INTO login_audit (user_id, username_attempted, was_successful, failure_reason, ip_address, user_agent)
    VALUES (v_uid, v_name, false, v_reason, left(split_part(COALESCE(sims_private.request_header('x-forwarded-for'), ''), ',', 1), 45), left(sims_private.request_header('user-agent'), 500));
END $function$;

CREATE OR REPLACE FUNCTION public.auth_login_record()
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid bigint := sims_private.current_user_id(); v_name text; v_id bigint;
BEGIN
    IF v_uid IS NULL THEN RETURN NULL; END IF;
    SELECT username INTO v_name FROM user_account WHERE user_id = v_uid;
    INSERT INTO login_audit (user_id, username_attempted, was_successful, ip_address, user_agent)
    VALUES (v_uid, v_name, true, left(split_part(COALESCE(sims_private.request_header('x-forwarded-for'), ''), ',', 1), 45), left(sims_private.request_header('user-agent'), 500)) RETURNING login_audit_id INTO v_id;
    UPDATE user_account SET last_login_at = now(), failed_login_count = 0 WHERE user_id = v_uid;
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.auth_logout_record()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid bigint := sims_private.current_user_id();
BEGIN
    IF v_uid IS NULL THEN RETURN; END IF;
    UPDATE login_audit SET logout_at = now()
    WHERE login_audit_id = (SELECT max(login_audit_id) FROM login_audit WHERE user_id = v_uid AND was_successful AND logout_at IS NULL);
END $function$;

CREATE OR REPLACE FUNCTION public.cert_request_cancel(p_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE r record;
BEGIN
    SELECT certificate_request_id, student_id, request_status INTO r FROM certificate_request WHERE certificate_request_id = p_id FOR UPDATE;
    IF r.certificate_request_id IS NULL OR NOT (sims_private.is_me_student(r.student_id) OR sims_private.can_student(ARRAY['DOCUMENT.ALL.UPDATE']::text[], r.student_id, true)) THEN
        RAISE EXCEPTION 'Not authorised or unknown request' USING ERRCODE = '42501';
    END IF;
    IF r.request_status = 'CANCELLED' THEN RETURN; END IF;
    IF r.request_status <> 'SUBMITTED' THEN RAISE EXCEPTION 'Only a submitted request can be cancelled (status %)', r.request_status USING ERRCODE = '45000'; END IF;
    UPDATE certificate_request SET request_status = 'CANCELLED' WHERE certificate_request_id = p_id;
    INSERT INTO activity_audit (user_id, module_code, action_code, entity_name, entity_id, details) VALUES (sims_private.current_user_id(), 'DOCUMENT', 'CERT_CANCELLED', 'certificate_request', p_id::text, '{}'::jsonb);
END $function$;

CREATE OR REPLACE FUNCTION public.cert_request_create(p_type_id integer, p_purpose text, p_student_id bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_student bigint := COALESCE(p_student_id, sims_private.current_student_id()); v_id bigint;
BEGIN
    IF v_student IS NULL OR NOT (sims_private.is_me_student(v_student) OR sims_private.can_student(ARRAY['DOCUMENT.ALL.CREATE']::text[], v_student, true)) THEN
        RAISE EXCEPTION 'Not authorised (DOCUMENT.ALL.CREATE)' USING ERRCODE = '42501';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM certificate_type WHERE certificate_type_id = p_type_id AND is_active) THEN RAISE EXCEPTION 'Choose an active certificate type' USING ERRCODE = '22023'; END IF;
    IF p_purpose IS NULL OR length(btrim(p_purpose)) < 3 OR length(p_purpose) > 500 THEN RAISE EXCEPTION 'State the purpose (3 to 500 characters)' USING ERRCODE = '22023'; END IF;
    IF (SELECT count(*) FROM certificate_request WHERE student_id = v_student AND request_status IN ('SUBMITTED', 'APPROVED')) >= 5 THEN RAISE EXCEPTION 'There are already 5 open requests' USING ERRCODE = '45000'; END IF;
    INSERT INTO certificate_request (request_number, student_id, certificate_type_id, purpose, request_status)
    VALUES ('CR-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('sims_private.certificate_request_seq')::text, 6, '0'), v_student, p_type_id, btrim(p_purpose), 'SUBMITTED') RETURNING certificate_request_id INTO v_id;
    INSERT INTO activity_audit (user_id, module_code, action_code, entity_name, entity_id, details) VALUES (sims_private.current_user_id(), 'DOCUMENT', 'CERT_REQUESTED', 'certificate_request', v_id::text, jsonb_build_object('student_id', v_student));
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.cert_request_decide(p_id bigint, p_approve boolean, p_remarks text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE r record;
BEGIN
    SELECT certificate_request_id, student_id, request_status INTO r FROM certificate_request WHERE certificate_request_id = p_id FOR UPDATE;
    IF r.certificate_request_id IS NULL OR NOT sims_private.can_student(ARRAY['DOCUMENT.ALL.APPROVE']::text[], r.student_id, true) THEN RAISE EXCEPTION 'Not authorised (DOCUMENT.ALL.APPROVE) or unknown request' USING ERRCODE = '42501'; END IF;
    IF r.request_status <> 'SUBMITTED' THEN RAISE EXCEPTION 'Only a submitted request can be decided (status %)', r.request_status USING ERRCODE = '45000'; END IF;
    IF NOT p_approve AND (p_remarks IS NULL OR btrim(p_remarks) = '') THEN RAISE EXCEPTION 'A reason is required to reject' USING ERRCODE = '22023'; END IF;
    IF length(COALESCE(p_remarks, '')) > 500 THEN RAISE EXCEPTION 'Remarks are limited to 500 characters' USING ERRCODE = '22023'; END IF;
    UPDATE certificate_request SET request_status = CASE WHEN p_approve THEN 'APPROVED' ELSE 'REJECTED' END WHERE certificate_request_id = p_id;
    INSERT INTO activity_audit (user_id, module_code, action_code, entity_name, entity_id, details)
    VALUES (sims_private.current_user_id(), 'DOCUMENT', CASE WHEN p_approve THEN 'CERT_APPROVED' ELSE 'CERT_REJECTED' END, 'certificate_request', p_id::text, jsonb_build_object('remarks', p_remarks));
END $function$;

CREATE OR REPLACE FUNCTION public.cert_request_download_info(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE r record;
BEGIN
    SELECT c.certificate_request_id, c.student_id, c.request_status, f.storage_key, f.original_file_name INTO r FROM certificate_request c JOIN file_object f ON f.file_object_id = c.file_object_id WHERE c.certificate_request_id = p_id;
    IF r.certificate_request_id IS NULL OR r.request_status <> 'ISSUED' OR NOT (sims_private.is_me_student(r.student_id) OR sims_private.can_student(ARRAY['DOCUMENT.ALL.READ']::text[], r.student_id, false)) THEN
        RAISE EXCEPTION 'Not authorised (DOCUMENT.ALL.READ) or no issued certificate' USING ERRCODE = '42501';
    END IF;
    INSERT INTO activity_audit (user_id, module_code, action_code, entity_name, entity_id, details) VALUES (sims_private.current_user_id(), 'DOCUMENT', 'DOWNLOAD', 'certificate_request', p_id::text, jsonb_build_object('student_id', r.student_id));
    RETURN jsonb_build_object('storage_key', r.storage_key, 'file_name', r.original_file_name, 'mime_type', 'application/pdf');
END $function$;

CREATE OR REPLACE FUNCTION public.cert_request_issue(p_id bigint, p_certificate_number text, p_storage_key text, p_file_name text, p_size bigint, p_checksum text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE r record; v_file bigint; v_meta jsonb; v_num text := NULLIF(btrim(p_certificate_number), '');
BEGIN
    SELECT certificate_request_id, student_id, request_status INTO r FROM certificate_request WHERE certificate_request_id = p_id FOR UPDATE;
    IF r.certificate_request_id IS NULL OR NOT sims_private.can_student(ARRAY['DOCUMENT.ALL.CREATE']::text[], r.student_id, true) THEN RAISE EXCEPTION 'Not authorised (DOCUMENT.ALL.CREATE) or unknown request' USING ERRCODE = '42501'; END IF;
    IF r.request_status <> 'APPROVED' THEN RAISE EXCEPTION 'Only an approved request can be issued (status %)', r.request_status USING ERRCODE = '45000'; END IF;
    IF v_num IS NULL OR length(v_num) > 50 THEN RAISE EXCEPTION 'The certificate number is required (at most 50 characters)' USING ERRCODE = '22023'; END IF;
    IF EXISTS (SELECT 1 FROM certificate_request WHERE certificate_number = v_num) THEN RAISE EXCEPTION 'That certificate number is already used' USING ERRCODE = '23505'; END IF;
    IF sims_private.doc_student_id(p_storage_key) IS DISTINCT FROM r.student_id THEN RAISE EXCEPTION 'The file is not stored under this student' USING ERRCODE = '22023'; END IF;
    IF p_file_name IS NULL OR lower(p_file_name) !~ '\.pdf$' OR length(p_file_name) > 255 THEN RAISE EXCEPTION 'The issued certificate must be a PDF file' USING ERRCODE = '22023'; END IF;
    IF p_size IS NULL OR p_size <= 0 OR p_size > 10485760 THEN RAISE EXCEPTION 'The file must be between 1 byte and 10 MB' USING ERRCODE = '22023'; END IF;
    IF p_checksum IS NOT NULL AND p_checksum !~ '^[0-9A-Fa-f]{64}$' THEN RAISE EXCEPTION 'Invalid checksum' USING ERRCODE = '22023'; END IF;
    SELECT metadata INTO v_meta FROM storage.objects WHERE bucket_id = 'sims-documents' AND name = p_storage_key;
    IF NOT FOUND THEN RAISE EXCEPTION 'The file has not been uploaded' USING ERRCODE = '22023'; END IF;
    IF v_meta ? 'size' AND (v_meta ->> 'size')::bigint <> p_size THEN RAISE EXCEPTION 'The uploaded file size does not match' USING ERRCODE = '22023'; END IF;
    IF EXISTS (SELECT 1 FROM file_object WHERE storage_key = p_storage_key) THEN RAISE EXCEPTION 'That file is already registered' USING ERRCODE = '23505'; END IF;
    INSERT INTO file_object (storage_provider, storage_key, original_file_name, mime_type, file_size_bytes, checksum_sha256, stored_file_name, file_extension, confidentiality_level, uploaded_by_user_id)
    VALUES ('supabase-storage', p_storage_key, btrim(p_file_name), 'application/pdf', p_size, lower(p_checksum), split_part(p_storage_key, '/', 3), 'pdf', 'CONFIDENTIAL', sims_private.current_user_id()) RETURNING file_object_id INTO v_file;
    UPDATE certificate_request SET request_status = 'ISSUED', issued_at = now(), certificate_number = v_num, file_object_id = v_file WHERE certificate_request_id = p_id;
    INSERT INTO activity_audit (user_id, module_code, action_code, entity_name, entity_id, details) VALUES (sims_private.current_user_id(), 'DOCUMENT', 'CERT_ISSUED', 'certificate_request', p_id::text, jsonb_build_object('certificate_number', v_num));
END $function$;

CREATE OR REPLACE FUNCTION public.emp_aadhaar_save(p_employee_id bigint, p_aadhaar text, p_name text, p_purpose text, p_remarks text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v text := regexp_replace(COALESCE(p_aadhaar, ''), '[\s-]', '', 'g'); v_ex record; v_fp text; v_id bigint; v_other bigint;
BEGIN
    SELECT employee_aadhaar_id, verification_status, aadhaar_number_fingerprint INTO v_ex FROM employee_aadhaar WHERE employee_id = p_employee_id FOR UPDATE;
    PERFORM sims_private.emp_write_allowed(p_employee_id, 'AADHAAR', v_ex.verification_status);
    IF v !~ '^[2-9][0-9]{11}$' OR NOT sims_private.verhoeff_valid(v) THEN RAISE EXCEPTION 'Enter a valid 12-digit Aadhaar number' USING ERRCODE = '22023'; END IF;
    IF p_name IS NULL OR btrim(p_name) = '' OR length(p_name) > 200 THEN RAISE EXCEPTION 'The name as on the Aadhaar card is required' USING ERRCODE = '22023'; END IF;
    IF p_purpose IS NULL OR length(btrim(p_purpose)) < 5 OR length(p_purpose) > 500 THEN RAISE EXCEPTION 'State why the Aadhaar number is collected (5 to 500 characters)' USING ERRCODE = '22023'; END IF;
    IF length(COALESCE(p_remarks, '')) > 1000 THEN RAISE EXCEPTION 'Remarks are too long' USING ERRCODE = '22023'; END IF;
    v_fp := sims_private.pii_fingerprint(v);
    SELECT employee_id INTO v_other FROM employee_aadhaar WHERE aadhaar_number_fingerprint = v_fp AND employee_id <> p_employee_id;
    IF FOUND THEN RAISE EXCEPTION 'That Aadhaar number is already registered for another employee' USING ERRCODE = '23505'; END IF;
    IF v_ex.employee_aadhaar_id IS NULL THEN
        INSERT INTO employee_aadhaar (employee_id, aadhaar_number_ciphertext, aadhaar_number_fingerprint, aadhaar_number_last4, aadhaar_number_masked, name_as_per_aadhaar, format_validated, collection_purpose, remarks, created_by_user_id, updated_by_user_id)
        VALUES (p_employee_id, sims_private.pii_encrypt(v), v_fp, right(v, 4), 'XXXX XXXX ' || right(v, 4), btrim(p_name), true, btrim(p_purpose), p_remarks, sims_private.current_user_id(), sims_private.current_user_id())
        RETURNING employee_aadhaar_id INTO v_id;
        PERFORM sims_private.emp_sensitive_log(p_employee_id, 'CREATE', 'AADHAAR', v_id, p_purpose);
    ELSE
        v_id := v_ex.employee_aadhaar_id;
        UPDATE employee_aadhaar SET aadhaar_number_ciphertext = CASE WHEN v_fp <> v_ex.aadhaar_number_fingerprint THEN sims_private.pii_encrypt(v) ELSE aadhaar_number_ciphertext END, aadhaar_number_fingerprint = v_fp,
               aadhaar_number_last4 = right(v, 4), aadhaar_number_masked = 'XXXX XXXX ' || right(v, 4), name_as_per_aadhaar = btrim(p_name), collection_purpose = btrim(p_purpose), remarks = p_remarks, format_validated = true,
               verification_status = 'PENDING', verified_by_user_id = NULL, verified_at = NULL, verification_remarks = NULL, updated_by_user_id = sims_private.current_user_id()
         WHERE employee_aadhaar_id = v_id;
        PERFORM sims_private.emp_sensitive_log(p_employee_id, 'UPDATE', 'AADHAAR', v_id, p_purpose);
    END IF;
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.emp_bank_save(p_employee_id bigint, p_account_id bigint, p_holder text, p_bank text, p_branch text, p_account_number text, p_account_confirm text, p_ifsc text, p_type text DEFAULT 'SAVINGS'::text, p_upi text DEFAULT NULL::text, p_is_primary boolean DEFAULT false, p_is_salary boolean DEFAULT false)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_acc text := NULLIF(regexp_replace(COALESCE(p_account_number, ''), '\s', '', 'g'), ''); v_ifsc text := upper(btrim(COALESCE(p_ifsc, ''))); v_status text; v_fp text; v_id bigint; v_other bigint;
BEGIN
    IF p_account_id IS NOT NULL THEN
        SELECT account_status INTO v_status FROM employee_bank_account WHERE employee_bank_account_id = p_account_id AND employee_id = p_employee_id FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'Not authorised or unknown bank account' USING ERRCODE = '42501'; END IF;
    END IF;
    PERFORM sims_private.emp_write_allowed(p_employee_id, 'BANK_ACCOUNT', v_status);
    IF p_holder IS NULL OR btrim(p_holder) = '' OR length(p_holder) > 200 OR p_bank IS NULL OR btrim(p_bank) = '' OR length(p_bank) > 200 OR length(COALESCE(p_branch, '')) > 200 THEN RAISE EXCEPTION 'The account holder and the bank name are required' USING ERRCODE = '22023'; END IF;
    IF v_ifsc !~ '^[A-Z]{4}0[A-Z0-9]{6}$' THEN RAISE EXCEPTION 'Enter a valid IFSC code (for example SBIN0001234)' USING ERRCODE = '22023'; END IF;
    IF p_type NOT IN ('SAVINGS','CURRENT','SALARY','NRE','NRO','OTHER') THEN RAISE EXCEPTION 'Unknown account type' USING ERRCODE = '22023'; END IF;
    IF length(COALESCE(p_upi, '')) > 150 THEN RAISE EXCEPTION 'The UPI id is too long' USING ERRCODE = '22023'; END IF;
    IF p_account_id IS NULL OR v_acc IS NOT NULL THEN
        IF v_acc IS NULL OR v_acc !~ '^[0-9]{9,18}$' THEN RAISE EXCEPTION 'Enter the account number (9 to 18 digits)' USING ERRCODE = '22023'; END IF;
        IF v_acc IS DISTINCT FROM NULLIF(regexp_replace(COALESCE(p_account_confirm, ''), '\s', '', 'g'), '') THEN RAISE EXCEPTION 'The two account numbers do not match' USING ERRCODE = '22023'; END IF;
        v_fp := sims_private.pii_fingerprint(v_acc);
        SELECT employee_bank_account_id INTO v_other FROM employee_bank_account WHERE account_number_fingerprint = v_fp AND employee_bank_account_id IS DISTINCT FROM p_account_id;
        IF FOUND THEN RAISE EXCEPTION 'That account number is already registered' USING ERRCODE = '23505'; END IF;
    END IF;
    IF p_is_primary THEN UPDATE employee_bank_account SET is_primary = false WHERE employee_id = p_employee_id AND is_primary AND employee_bank_account_id IS DISTINCT FROM p_account_id; END IF;
    IF p_account_id IS NULL THEN
        INSERT INTO employee_bank_account (employee_id, account_holder_name, bank_name, branch_name, account_number_ciphertext, account_number_fingerprint, account_number_last4, account_number_confirmed, account_type, ifsc_code, upi_id,
                                           is_salary_account, is_primary, created_by_user_id, updated_by_user_id)
        VALUES (p_employee_id, btrim(p_holder), btrim(p_bank), NULLIF(btrim(p_branch), ''), sims_private.pii_encrypt(v_acc), v_fp, right(v_acc, 4), true, p_type, v_ifsc, NULLIF(btrim(p_upi), ''), p_is_salary, p_is_primary,
                sims_private.current_user_id(), sims_private.current_user_id())
        RETURNING employee_bank_account_id INTO v_id;
        PERFORM sims_private.emp_sensitive_log(p_employee_id, 'CREATE', 'BANK_ACCOUNT', v_id, NULL);
    ELSE
        v_id := p_account_id;
        UPDATE employee_bank_account SET account_holder_name = btrim(p_holder), bank_name = btrim(p_bank), branch_name = NULLIF(btrim(p_branch), ''), account_type = p_type, ifsc_code = v_ifsc, upi_id = NULLIF(btrim(p_upi), ''),
               is_salary_account = p_is_salary, is_primary = p_is_primary, updated_by_user_id = sims_private.current_user_id(),
               account_number_ciphertext = CASE WHEN v_acc IS NOT NULL THEN sims_private.pii_encrypt(v_acc) ELSE account_number_ciphertext END,
               account_number_fingerprint = COALESCE(v_fp, account_number_fingerprint), account_number_last4 = COALESCE(right(v_acc, 4), account_number_last4),
               account_status = 'PENDING_VERIFICATION', verification_status = 'PENDING', verified_by_user_id = NULL, verified_at = NULL, verification_remarks = NULL
         WHERE employee_bank_account_id = v_id;
        PERFORM sims_private.emp_sensitive_log(p_employee_id, 'UPDATE', 'BANK_ACCOUNT', v_id, NULL);
    END IF;
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.emp_competency_delete(p_employee_id bigint, p_course_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_before jsonb;
BEGIN
    IF NOT sims_private.emp_all_can(p_employee_id, 'DELETE') THEN RAISE EXCEPTION 'Not authorised (EMPLOYEE.ALL.DELETE) or unknown employee' USING ERRCODE = '42501'; END IF;
    SELECT to_jsonb(c) INTO v_before FROM employee_competency c WHERE employee_id = p_employee_id AND course_id = p_course_id;
    IF v_before IS NULL THEN RAISE EXCEPTION 'Unknown competency' USING ERRCODE = '22023'; END IF;
    DELETE FROM employee_competency WHERE employee_id = p_employee_id AND course_id = p_course_id;
    PERFORM sims_private.audit_manual('EMPLOYEE', 'DELETE', 'employee_competency', p_employee_id, v_before, NULL);
END $function$;

CREATE OR REPLACE FUNCTION public.emp_competency_save(p_employee_id bigint, p_course_id bigint, p_level text, p_valid_from date DEFAULT NULL::date, p_valid_to date DEFAULT NULL::date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_before jsonb; v_after jsonb; v_exists boolean;
BEGIN
    SELECT EXISTS (SELECT 1 FROM employee_competency WHERE employee_id = p_employee_id AND course_id = p_course_id) INTO v_exists;
    IF NOT sims_private.emp_all_can(p_employee_id, CASE WHEN v_exists THEN 'UPDATE' ELSE 'CREATE' END) THEN RAISE EXCEPTION 'Not authorised (EMPLOYEE.ALL.%) or unknown employee', CASE WHEN v_exists THEN 'UPDATE' ELSE 'CREATE' END USING ERRCODE = '42501'; END IF;
    IF NOT EXISTS (SELECT 1 FROM employee WHERE employee_id = p_employee_id) THEN RAISE EXCEPTION 'Unknown employee' USING ERRCODE = '22023'; END IF;
    IF NOT EXISTS (SELECT 1 FROM course_catalog WHERE course_id = p_course_id) THEN RAISE EXCEPTION 'Unknown course' USING ERRCODE = '22023'; END IF;
    IF p_level IS NULL OR p_level NOT IN ('BEGINNER', 'INTERMEDIATE', 'ADVANCED', 'EXPERT') THEN RAISE EXCEPTION 'Choose a level: beginner, intermediate, advanced or expert' USING ERRCODE = '22023'; END IF;
    IF p_valid_from IS NOT NULL AND p_valid_to IS NOT NULL AND p_valid_to < p_valid_from THEN RAISE EXCEPTION 'The end date cannot be before the start date' USING ERRCODE = '22023'; END IF;
    SELECT to_jsonb(c) INTO v_before FROM employee_competency c WHERE employee_id = p_employee_id AND course_id = p_course_id;
    INSERT INTO employee_competency (employee_id, course_id, competency_level, valid_from, valid_to) VALUES (p_employee_id, p_course_id, p_level, p_valid_from, p_valid_to)
    ON CONFLICT (employee_id, course_id) DO UPDATE SET competency_level = EXCLUDED.competency_level, valid_from = EXCLUDED.valid_from, valid_to = EXCLUDED.valid_to;
    SELECT to_jsonb(c) INTO v_after FROM employee_competency c WHERE employee_id = p_employee_id AND course_id = p_course_id;
    PERFORM sims_private.audit_manual('EMPLOYEE', CASE WHEN v_before IS NULL THEN 'INSERT' ELSE 'UPDATE' END, 'employee_competency', p_employee_id, v_before, v_after);
END $function$;

CREATE OR REPLACE FUNCTION public.emp_doc_rule_end(p_rule_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE r record; v_emp bigint;
BEGIN
    SELECT employee_document_access_rule_id, employee_document_id, valid_from, valid_to INTO r FROM employee_document_access_rule WHERE employee_document_access_rule_id = p_rule_id FOR UPDATE;
    SELECT employee_id INTO v_emp FROM employee_document WHERE employee_document_id = r.employee_document_id;
    IF v_emp IS NULL OR NOT sims_private.emp_can(v_emp, 'EMPLOYEE_DOCUMENT', 'UPDATE', true) THEN RAISE EXCEPTION 'Not authorised (EMPLOYEE.EMPLOYEE_DOCUMENT.UPDATE) or unknown rule' USING ERRCODE = '42501'; END IF;
    IF r.valid_to IS NOT NULL AND r.valid_to <= now() THEN RETURN; END IF;
    UPDATE employee_document_access_rule SET valid_to = CASE WHEN now() > valid_from THEN now() ELSE valid_from + interval '1 microsecond' END WHERE employee_document_access_rule_id = p_rule_id;
    PERFORM sims_private.emp_sensitive_log(v_emp, 'UPDATE', 'EMPLOYEE_DOCUMENT', r.employee_document_id, 'access rule ended', r.employee_document_id);
END $function$;

CREATE OR REPLACE FUNCTION public.emp_doc_rule_set(p_document_id bigint, p_role_code text, p_username text, p_can_view boolean, p_can_download boolean, p_valid_to timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_emp bigint; v_role integer; v_user bigint; v_id bigint;
BEGIN
    SELECT employee_id INTO v_emp FROM employee_document WHERE employee_document_id = p_document_id AND deleted_at IS NULL;
    IF v_emp IS NULL OR NOT sims_private.emp_can(v_emp, 'EMPLOYEE_DOCUMENT', 'UPDATE', true) THEN RAISE EXCEPTION 'Not authorised (EMPLOYEE.EMPLOYEE_DOCUMENT.UPDATE) or unknown document' USING ERRCODE = '42501'; END IF;
    IF (NULLIF(btrim(p_role_code), '') IS NULL) = (NULLIF(btrim(p_username), '') IS NULL) THEN RAISE EXCEPTION 'Name either a role or a user' USING ERRCODE = '22023'; END IF;
    IF NOT (COALESCE(p_can_view, false) OR COALESCE(p_can_download, false)) THEN RAISE EXCEPTION 'Allow viewing, downloading or both' USING ERRCODE = '22023'; END IF;
    IF p_valid_to IS NOT NULL AND p_valid_to <= now() THEN RAISE EXCEPTION 'The end of the rule must be in the future' USING ERRCODE = '22023'; END IF;
    IF NULLIF(btrim(p_role_code), '') IS NOT NULL THEN
        SELECT role_id INTO v_role FROM role WHERE role_code = btrim(p_role_code) AND is_active;
        IF v_role IS NULL THEN RAISE EXCEPTION 'Unknown role' USING ERRCODE = '22023'; END IF;
        IF btrim(p_role_code) IN ('STUDENT', 'APPLICANT', 'PARENT_GUARDIAN', 'ALUMNI') THEN RAISE EXCEPTION 'HR documents cannot be shared with that role' USING ERRCODE = '22023'; END IF;
    ELSE
        SELECT user_id INTO v_user FROM user_account WHERE lower(username) = lower(btrim(p_username)) AND account_status = 'ACTIVE';
        IF v_user IS NULL THEN RAISE EXCEPTION 'Unknown or inactive user' USING ERRCODE = '22023'; END IF;
        IF EXISTS (SELECT 1 FROM student_user_account WHERE user_id = v_user) THEN RAISE EXCEPTION 'HR documents cannot be shared with a student' USING ERRCODE = '22023'; END IF;
    END IF;
    INSERT INTO employee_document_access_rule (employee_document_id, role_id, user_id, can_view, can_download, can_update, can_verify, can_approve, valid_to, granted_by_user_id)
    VALUES (p_document_id, v_role, v_user, COALESCE(p_can_view, false) OR COALESCE(p_can_download, false), COALESCE(p_can_download, false), false, false, false, p_valid_to, sims_private.current_user_id())
    RETURNING employee_document_access_rule_id INTO v_id;
    PERFORM sims_private.emp_sensitive_log(v_emp, 'UPDATE', 'EMPLOYEE_DOCUMENT', p_document_id, 'access rule added', p_document_id);
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.emp_pan_save(p_employee_id bigint, p_pan text, p_name text, p_issue_date date DEFAULT NULL::date, p_remarks text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_pan text := upper(regexp_replace(COALESCE(p_pan, ''), '\s', '', 'g')); v_ex record; v_fp text; v_id bigint; v_other bigint;
BEGIN
    SELECT employee_pan_id, verification_status, pan_number_fingerprint INTO v_ex FROM employee_pan WHERE employee_id = p_employee_id FOR UPDATE;
    PERFORM sims_private.emp_write_allowed(p_employee_id, 'PAN', v_ex.verification_status);
    IF v_pan !~ '^[A-Z]{5}[0-9]{4}[A-Z]$' OR substr(v_pan, 4, 1) NOT IN ('P','C','H','F','A','T','B','L','J','G') THEN RAISE EXCEPTION 'Enter a valid PAN (for example ABCPE1234F)' USING ERRCODE = '22023'; END IF;
    IF p_name IS NULL OR btrim(p_name) = '' OR length(p_name) > 200 THEN RAISE EXCEPTION 'The name as on the PAN card is required' USING ERRCODE = '22023'; END IF;
    IF length(COALESCE(p_remarks, '')) > 1000 THEN RAISE EXCEPTION 'Remarks are too long' USING ERRCODE = '22023'; END IF;
    v_fp := sims_private.pii_fingerprint(v_pan);
    SELECT employee_id INTO v_other FROM employee_pan WHERE pan_number_fingerprint = v_fp AND employee_id <> p_employee_id;
    IF FOUND THEN RAISE EXCEPTION 'That PAN is already registered for another employee' USING ERRCODE = '23505'; END IF;
    IF v_ex.employee_pan_id IS NULL THEN
        INSERT INTO employee_pan (employee_id, pan_number_ciphertext, pan_number_fingerprint, pan_number_masked, name_as_per_pan, pan_issue_date, format_validated, remarks, created_by_user_id, updated_by_user_id)
        VALUES (p_employee_id, sims_private.pii_encrypt(v_pan), v_fp, 'XXXXX' || substr(v_pan, 6), btrim(p_name), p_issue_date, true, p_remarks, sims_private.current_user_id(), sims_private.current_user_id())
        RETURNING employee_pan_id INTO v_id;
        PERFORM sims_private.emp_sensitive_log(p_employee_id, 'CREATE', 'PAN', v_id, NULL);
    ELSE
        v_id := v_ex.employee_pan_id;
        UPDATE employee_pan SET pan_number_ciphertext = CASE WHEN v_fp <> v_ex.pan_number_fingerprint THEN sims_private.pii_encrypt(v_pan) ELSE pan_number_ciphertext END, pan_number_fingerprint = v_fp,
               pan_number_masked = 'XXXXX' || substr(v_pan, 6), name_as_per_pan = btrim(p_name), pan_issue_date = p_issue_date, remarks = p_remarks, format_validated = true,
               verification_status = 'PENDING', verified_by_user_id = NULL, verified_at = NULL, verification_remarks = NULL, updated_by_user_id = sims_private.current_user_id()
         WHERE employee_pan_id = v_id;
        PERFORM sims_private.emp_sensitive_log(p_employee_id, 'UPDATE', 'PAN', v_id, NULL);
    END IF;
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.emp_sensitive_delete(p_kind text, p_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE r record;
BEGIN
    SELECT * INTO r FROM sims_private.emp_sensitive_row(p_kind, p_id);
    IF r.employee_id IS NULL THEN RAISE EXCEPTION 'Not authorised (EMPLOYEE.%.DELETE) or unknown record', p_kind USING ERRCODE = '42501'; END IF;
    IF sims_private.emp_can(r.employee_id, p_kind, 'DELETE', true) THEN NULL;
    ELSIF sims_private.emp_is_owner(r.employee_id) AND r.status IN ('PENDING', 'REJECTED') THEN NULL;
    ELSE RAISE EXCEPTION 'Not authorised (EMPLOYEE.%.DELETE) or unknown record', p_kind USING ERRCODE = '42501'; END IF;
    IF EXISTS (SELECT 1 FROM employee_document WHERE (p_kind = 'PAN' AND employee_pan_id = p_id) OR (p_kind = 'AADHAAR' AND employee_aadhaar_id = p_id) OR (p_kind = 'BANK_ACCOUNT' AND employee_bank_account_id = p_id)) THEN
        RAISE EXCEPTION 'Documents are attached to this record; remove them first' USING ERRCODE = '45000';
    END IF;
    IF p_kind = 'PAN' THEN DELETE FROM employee_pan WHERE employee_pan_id = p_id;
    ELSIF p_kind = 'AADHAAR' THEN DELETE FROM employee_aadhaar WHERE employee_aadhaar_id = p_id;
    ELSE DELETE FROM employee_bank_account WHERE employee_bank_account_id = p_id; END IF;
    PERFORM sims_private.emp_sensitive_log(r.employee_id, 'DELETE', p_kind, p_id, NULL);
END $function$;

CREATE OR REPLACE FUNCTION public.emp_sensitive_review(p_kind text, p_id bigint, p_decision text, p_remarks text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE r record; v_rem text := NULLIF(btrim(p_remarks), '');
BEGIN
    SELECT * INTO r FROM sims_private.emp_sensitive_row(p_kind, p_id);
    IF r.employee_id IS NULL OR NOT sims_private.emp_can(r.employee_id, p_kind, 'VERIFY', true) THEN RAISE EXCEPTION 'Not authorised (EMPLOYEE.%.VERIFY) or unknown record', p_kind USING ERRCODE = '42501'; END IF;
    IF p_decision NOT IN ('VERIFIED', 'REJECTED') THEN RAISE EXCEPTION 'The decision must be VERIFIED or REJECTED' USING ERRCODE = '22023'; END IF;
    IF p_decision = 'REJECTED' AND v_rem IS NULL THEN RAISE EXCEPTION 'Remarks are required to reject' USING ERRCODE = '22023'; END IF;
    IF length(COALESCE(v_rem, '')) > 1000 THEN RAISE EXCEPTION 'Remarks are too long' USING ERRCODE = '22023'; END IF;
    IF r.status NOT IN ('PENDING') THEN RAISE EXCEPTION 'Only a pending record can be reviewed (status %)', r.status USING ERRCODE = '45000'; END IF;
    IF r.last_editor IS NOT DISTINCT FROM sims_private.current_user_id() THEN RAISE EXCEPTION 'You cannot verify a record that you entered or changed yourself' USING ERRCODE = '45000'; END IF;
    IF p_kind = 'PAN' THEN UPDATE employee_pan SET verification_status = p_decision, verified_by_user_id = sims_private.current_user_id(), verified_at = now(), verification_remarks = v_rem WHERE employee_pan_id = p_id;
    ELSIF p_kind = 'AADHAAR' THEN UPDATE employee_aadhaar SET verification_status = p_decision, verified_by_user_id = sims_private.current_user_id(), verified_at = now(), verification_remarks = v_rem WHERE employee_aadhaar_id = p_id;
    ELSE UPDATE employee_bank_account SET verification_status = p_decision, account_status = CASE WHEN p_decision = 'VERIFIED' THEN 'ACTIVE' ELSE 'REJECTED' END,
                verified_by_user_id = sims_private.current_user_id(), verified_at = now(), verification_remarks = v_rem WHERE employee_bank_account_id = p_id; END IF;
    PERFORM sims_private.emp_sensitive_log(r.employee_id, 'VERIFY', p_kind, p_id, p_decision);
END $function$;

CREATE OR REPLACE FUNCTION public.employee_assign(p_employee_id bigint, p_campus_id integer, p_department_id integer, p_designation_id integer, p_start_date date, p_is_primary boolean DEFAULT true, p_end_current boolean DEFAULT false)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_cur record; v_id bigint; v_codes text[] := ARRAY['EMPLOYEE.ALL.UPDATE']::text[];
BEGIN
    IF NOT sims_private.can_employee(v_codes, p_employee_id, true)
       OR NOT (CASE WHEN p_department_id IS NOT NULL THEN sims_private.can_department(v_codes, p_department_id)
                    ELSE sims_private.can_campus(v_codes, p_campus_id) END) THEN
        RAISE EXCEPTION 'Not authorised to change this employee''s assignments here, or unknown employee' USING ERRCODE = '42501';
    END IF;
    IF p_start_date IS NULL OR p_campus_id IS NULL OR p_designation_id IS NULL THEN
        RAISE EXCEPTION 'campus, designation and start date are required' USING ERRCODE = '22023';
    END IF;

    PERFORM 1 FROM employee WHERE employee_id = p_employee_id FOR UPDATE;  -- serialise concurrent assignment changes per employee
    IF p_is_primary THEN
        SELECT employee_assignment_id, start_date INTO v_cur FROM employee_assignment
         WHERE employee_id = p_employee_id AND is_primary AND end_date IS NULL;
        IF FOUND THEN
            IF NOT p_end_current THEN
                RAISE EXCEPTION 'The employee already has a current primary assignment; end it first' USING ERRCODE = '45000';
            END IF;
            IF p_start_date <= v_cur.start_date THEN
                RAISE EXCEPTION 'The new start date must be after the current assignment started' USING ERRCODE = '45000';
            END IF;
            UPDATE employee_assignment SET end_date = p_start_date - 1 WHERE employee_assignment_id = v_cur.employee_assignment_id;
        END IF;
    END IF;
    INSERT INTO employee_assignment (employee_id, campus_id, department_id, designation_id, start_date, is_primary)
    VALUES (p_employee_id, p_campus_id, p_department_id, p_designation_id, p_start_date, p_is_primary)
    RETURNING employee_assignment_id INTO v_id;
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.employee_document_delete(p_id bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE d record;
BEGIN
    SELECT d0.employee_document_id, d0.employee_id, d0.verification_status, d0.file_object_id, f.storage_key INTO d
    FROM employee_document d0 JOIN file_object f ON f.file_object_id = d0.file_object_id WHERE d0.employee_document_id = p_id FOR UPDATE OF d0;
    IF d.employee_document_id IS NULL OR NOT (sims_private.emp_is_owner(d.employee_id) OR sims_private.emp_can(d.employee_id, 'EMPLOYEE_DOCUMENT', 'DELETE', true)) THEN
        RAISE EXCEPTION 'Not authorised (EMPLOYEE.EMPLOYEE_DOCUMENT.DELETE) or unknown document' USING ERRCODE = '42501';
    END IF;
    IF d.verification_status = 'VERIFIED' THEN RAISE EXCEPTION 'A verified document cannot be deleted' USING ERRCODE = '45000'; END IF;
    PERFORM sims_private.emp_sensitive_log(d.employee_id, 'DELETE', 'EMPLOYEE_DOCUMENT', p_id, NULL, NULL);
    DELETE FROM employee_document_access_rule WHERE employee_document_id = p_id;
    UPDATE employee_sensitive_access_audit SET employee_document_id = NULL WHERE employee_document_id = p_id; -- keep the history (entity_id still names the document); only the FK link goes
    DELETE FROM employee_document WHERE employee_document_id = p_id;
    DELETE FROM file_object WHERE file_object_id = d.file_object_id;
    RETURN d.storage_key;
END $function$;

CREATE OR REPLACE FUNCTION public.employee_document_register(p_employee_id bigint, p_category_id integer, p_document_type_id integer, p_title text, p_storage_key text, p_file_name text, p_mime_type text, p_size bigint, p_checksum text, p_document_number text DEFAULT NULL::text, p_issue_date date DEFAULT NULL::date, p_expiry_date date DEFAULT NULL::date)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_file bigint; v_doc bigint; v_ext text; v_meta jsonb; v_cat record; v_number text := NULLIF(btrim(p_document_number), '');
BEGIN
    IF NOT (sims_private.emp_is_owner(p_employee_id) OR sims_private.emp_can(p_employee_id, 'EMPLOYEE_DOCUMENT', 'CREATE', true)) THEN RAISE EXCEPTION 'Not authorised (EMPLOYEE.EMPLOYEE_DOCUMENT.CREATE)' USING ERRCODE = '42501'; END IF;
    IF sims_private.doc_employee_id(p_storage_key) IS DISTINCT FROM p_employee_id THEN RAISE EXCEPTION 'The file is not stored under this employee' USING ERRCODE = '22023'; END IF;
    IF p_title IS NULL OR btrim(p_title) = '' OR length(p_title) > 250 THEN RAISE EXCEPTION 'A title is required (at most 250 characters)' USING ERRCODE = '22023'; END IF;
    IF p_file_name IS NULL OR btrim(p_file_name) = '' OR length(p_file_name) > 255 THEN RAISE EXCEPTION 'The file name is required (at most 255 characters)' USING ERRCODE = '22023'; END IF;
    IF p_mime_type NOT IN ('application/pdf', 'image/jpeg', 'image/png') THEN RAISE EXCEPTION 'Only PDF, JPEG and PNG files are accepted' USING ERRCODE = '22023'; END IF;
    v_ext := lower(substring(p_file_name FROM '\.([A-Za-z0-9]{1,10})$'));
    IF v_ext IS NULL OR NOT ((p_mime_type = 'application/pdf' AND v_ext = 'pdf') OR (p_mime_type = 'image/jpeg' AND v_ext IN ('jpg', 'jpeg')) OR (p_mime_type = 'image/png' AND v_ext = 'png')) THEN RAISE EXCEPTION 'The file name does not match its type' USING ERRCODE = '22023'; END IF;
    IF p_size IS NULL OR p_size <= 0 OR p_size > 10485760 THEN RAISE EXCEPTION 'The file must be between 1 byte and 10 MB' USING ERRCODE = '22023'; END IF;
    IF p_checksum IS NOT NULL AND p_checksum !~ '^[0-9A-Fa-f]{64}$' THEN RAISE EXCEPTION 'Invalid checksum' USING ERRCODE = '22023'; END IF;
    IF length(COALESCE(v_number, '')) > 100 THEN RAISE EXCEPTION 'The document number is limited to 100 characters' USING ERRCODE = '22023'; END IF;
    IF p_issue_date IS NOT NULL AND p_expiry_date IS NOT NULL AND p_expiry_date < p_issue_date THEN RAISE EXCEPTION 'The expiry date cannot be before the issue date' USING ERRCODE = '22023'; END IF;
    IF NOT EXISTS (SELECT 1 FROM employee WHERE employee_id = p_employee_id) THEN RAISE EXCEPTION 'Unknown employee' USING ERRCODE = '22023'; END IF;
    SELECT * INTO v_cat FROM employee_document_category WHERE employee_document_category_id = p_category_id AND is_active;
    IF NOT FOUND THEN RAISE EXCEPTION 'Choose an active category' USING ERRCODE = '22023'; END IF;
    IF NOT EXISTS (SELECT 1 FROM document_type WHERE document_type_id = p_document_type_id AND is_active) THEN RAISE EXCEPTION 'Choose an active document type' USING ERRCODE = '22023'; END IF;
    SELECT metadata INTO v_meta FROM storage.objects WHERE bucket_id = 'sims-documents' AND name = p_storage_key;
    IF NOT FOUND THEN RAISE EXCEPTION 'The file has not been uploaded' USING ERRCODE = '22023'; END IF;
    IF v_meta ? 'size' AND (v_meta ->> 'size')::bigint <> p_size THEN RAISE EXCEPTION 'The uploaded file size does not match' USING ERRCODE = '22023'; END IF;
    IF EXISTS (SELECT 1 FROM file_object WHERE storage_key = p_storage_key) THEN RAISE EXCEPTION 'That file is already registered' USING ERRCODE = '23505'; END IF;
    INSERT INTO file_object (storage_provider, storage_key, original_file_name, mime_type, file_size_bytes, checksum_sha256, stored_file_name, file_extension, confidentiality_level, uploaded_by_user_id)
    VALUES ('supabase-storage', p_storage_key, btrim(p_file_name), p_mime_type, p_size, lower(p_checksum), split_part(p_storage_key, '/', 3), v_ext, 'CONFIDENTIAL', sims_private.current_user_id()) RETURNING file_object_id INTO v_file;
    INSERT INTO employee_document (employee_id, document_scope, employee_document_category_id, document_type_id, file_object_id, document_title, document_number, issue_date, expiry_date,
                                   approval_status, confidentiality_level, created_by_user_id, updated_by_user_id)
    VALUES (p_employee_id, 'EMPLOYEE_GENERAL', p_category_id, p_document_type_id, v_file, btrim(p_title), v_number, p_issue_date, p_expiry_date,
            CASE WHEN v_cat.requires_approval THEN 'PENDING' ELSE 'NOT_REQUIRED' END, v_cat.default_confidentiality, sims_private.current_user_id(), sims_private.current_user_id())
    RETURNING employee_document_id INTO v_doc;
    PERFORM sims_private.emp_sensitive_log(p_employee_id, 'CREATE', 'EMPLOYEE_DOCUMENT', v_doc, NULL, v_doc);
    RETURN v_doc;
END $function$;

CREATE OR REPLACE FUNCTION public.employee_document_review(p_id bigint, p_decision text, p_remarks text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE d record; v_rem text := NULLIF(btrim(p_remarks), ''); v_needs_approval boolean;
BEGIN
    SELECT d0.employee_document_id, d0.employee_id, d0.verification_status, d0.created_by_user_id, c.requires_approval INTO d
    FROM employee_document d0 JOIN employee_document_category c ON c.employee_document_category_id = d0.employee_document_category_id WHERE d0.employee_document_id = p_id AND d0.deleted_at IS NULL FOR UPDATE OF d0;
    IF d.employee_document_id IS NULL OR NOT sims_private.emp_can(d.employee_id, 'EMPLOYEE_DOCUMENT', 'VERIFY', true) THEN RAISE EXCEPTION 'Not authorised (EMPLOYEE.EMPLOYEE_DOCUMENT.VERIFY) or unknown document' USING ERRCODE = '42501'; END IF;
    IF p_decision NOT IN ('VERIFIED', 'REJECTED') THEN RAISE EXCEPTION 'The decision must be VERIFIED or REJECTED' USING ERRCODE = '22023'; END IF;
    IF p_decision = 'REJECTED' AND v_rem IS NULL THEN RAISE EXCEPTION 'Remarks are required to reject a document' USING ERRCODE = '22023'; END IF;
    IF length(COALESCE(v_rem, '')) > 1000 THEN RAISE EXCEPTION 'Remarks are too long' USING ERRCODE = '22023'; END IF;
    IF d.verification_status <> 'PENDING' THEN RAISE EXCEPTION 'Only a pending document can be reviewed' USING ERRCODE = '45000'; END IF;
    IF d.created_by_user_id IS NOT DISTINCT FROM sims_private.current_user_id() THEN RAISE EXCEPTION 'You cannot review a document that you uploaded yourself' USING ERRCODE = '45000'; END IF;
    v_needs_approval := d.requires_approval;
    IF v_needs_approval AND p_decision = 'VERIFIED' AND NOT sims_private.emp_can(d.employee_id, 'EMPLOYEE_DOCUMENT', 'APPROVE', true) THEN
        RAISE EXCEPTION 'Not authorised (EMPLOYEE.EMPLOYEE_DOCUMENT.APPROVE): this category needs approval' USING ERRCODE = '42501';
    END IF;
    UPDATE employee_document SET verification_status = p_decision, verified_by_user_id = sims_private.current_user_id(), verified_at = now(), verification_remarks = v_rem, updated_by_user_id = sims_private.current_user_id(),
           approval_status = CASE WHEN v_needs_approval THEN CASE WHEN p_decision = 'VERIFIED' THEN 'APPROVED' ELSE 'REJECTED' END ELSE approval_status END,
           approved_by_user_id = CASE WHEN v_needs_approval THEN sims_private.current_user_id() ELSE approved_by_user_id END, approved_at = CASE WHEN v_needs_approval THEN now() ELSE approved_at END
     WHERE employee_document_id = p_id;
    PERFORM sims_private.emp_sensitive_log(d.employee_id, 'VERIFY', 'EMPLOYEE_DOCUMENT', p_id, p_decision, p_id);
END $function$;

CREATE OR REPLACE FUNCTION public.employee_register(p_employee jsonb, p_assignment jsonb DEFAULT NULL::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_inst integer := (p_employee ->> 'institution_id')::integer;
    v_number text := NULLIF(btrim(p_employee ->> 'employee_number'), '');
    v_first text := NULLIF(btrim(p_employee ->> 'first_name'), '');
    v_mid text := NULLIF(btrim(p_employee ->> 'middle_name'), '');
    v_last text := NULLIF(btrim(p_employee ->> 'last_name'), '');
    v_email text := NULLIF(btrim(p_employee ->> 'primary_email'), '');
    v_dob date := NULLIF(p_employee ->> 'date_of_birth', '')::date;
    v_join date := NULLIF(p_employee ->> 'joining_date', '')::date;
    v_campus integer; v_dept integer; v_campus_inst integer; v_id bigint; v_constraint text; v_ok boolean;
BEGIN
    IF p_employee IS NULL OR jsonb_typeof(p_employee) <> 'object' THEN
        RAISE EXCEPTION 'p_employee must be an object' USING ERRCODE = '22023';
    END IF;
    IF v_inst IS NULL THEN RAISE EXCEPTION 'institution_id is required' USING ERRCODE = '22023'; END IF;

    IF p_assignment IS NOT NULL THEN
        IF jsonb_typeof(p_assignment) <> 'object' THEN RAISE EXCEPTION 'p_assignment must be an object' USING ERRCODE = '22023'; END IF;
        v_campus := (p_assignment ->> 'campus_id')::integer;
        v_dept := NULLIF(p_assignment ->> 'department_id', '')::integer;
        IF v_campus IS NULL OR (p_assignment ->> 'designation_id') IS NULL THEN
            RAISE EXCEPTION 'campus_id and designation_id are required for an assignment' USING ERRCODE = '22023';
        END IF;
    END IF;

    -- institution-level grant, or (with an assignment) a grant covering the target department/campus
    v_ok := sims_private.can_institution(ARRAY['EMPLOYEE.ALL.CREATE']::text[], v_inst);
    IF NOT v_ok AND p_assignment IS NOT NULL THEN
        v_ok := CASE WHEN v_dept IS NOT NULL THEN sims_private.can_department(ARRAY['EMPLOYEE.ALL.CREATE']::text[], v_dept)
                     ELSE sims_private.can_campus(ARRAY['EMPLOYEE.ALL.CREATE']::text[], v_campus) END;
        IF v_ok THEN
            SELECT institution_id INTO v_campus_inst FROM campus WHERE campus_id = v_campus;
            IF v_campus_inst IS DISTINCT FROM v_inst THEN v_ok := false; END IF;  -- scoped staff may only add people to their own institution
        END IF;
    END IF;
    IF NOT v_ok THEN
        RAISE EXCEPTION 'Not authorised to register employees here' USING ERRCODE = '42501';
    END IF;

    IF v_number IS NULL OR v_first IS NULL OR v_join IS NULL OR (p_employee ->> 'employment_source_id') IS NULL
       OR (p_employee ->> 'employment_type') IS NULL THEN
        RAISE EXCEPTION 'employee_number, first_name, joining_date, employment_source_id and employment_type are required' USING ERRCODE = '22023';
    END IF;
    IF v_email IS NOT NULL AND v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN
        RAISE EXCEPTION 'primary_email is not a valid email address' USING ERRCODE = '22023';
    END IF;
    IF v_dob IS NOT NULL AND (v_dob >= current_date OR v_dob < DATE '1900-01-01') THEN
        RAISE EXCEPTION 'date_of_birth is not plausible' USING ERRCODE = '22023';
    END IF;

    BEGIN
        INSERT INTO employee (institution_id, employment_source_id, external_agency_id, employee_number, agency_employee_number, first_name, middle_name,
                              last_name, display_name, date_of_birth, gender_id, blood_group_id, primary_email, primary_phone, nationality_country_id,
                              religion_id, social_category_id, joining_date, employment_type)
        VALUES (v_inst, (p_employee ->> 'employment_source_id')::smallint, NULLIF(p_employee ->> 'external_agency_id', '')::bigint, v_number,
                NULLIF(btrim(p_employee ->> 'agency_employee_number'), ''), v_first, v_mid, v_last, btrim(concat_ws(' ', v_first, v_mid, v_last)), v_dob,
                NULLIF(p_employee ->> 'gender_id', '')::smallint, NULLIF(p_employee ->> 'blood_group_id', '')::smallint, v_email,
                NULLIF(btrim(p_employee ->> 'primary_phone'), ''), NULLIF(p_employee ->> 'nationality_country_id', '')::integer,
                NULLIF(p_employee ->> 'religion_id', '')::integer, NULLIF(p_employee ->> 'social_category_id', '')::integer, v_join,
                p_employee ->> 'employment_type')
        RETURNING employee_id INTO v_id;
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF v_constraint IN ('employee_employee_number_key', 'uq_employee_primary_email', 'uq_employee_agency_number') THEN
            RAISE EXCEPTION 'Employee number or email is already registered' USING ERRCODE = '23505';
        END IF;
        RAISE;
    END;

    IF p_assignment IS NOT NULL THEN
        INSERT INTO employee_assignment (employee_id, campus_id, department_id, designation_id, start_date, is_primary)
        VALUES (v_id, v_campus, v_dept, (p_assignment ->> 'designation_id')::integer,
                COALESCE(NULLIF(p_assignment ->> 'start_date', '')::date, v_join), COALESCE((p_assignment ->> 'is_primary')::boolean, true));
    END IF;
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.feedback_submit(p_cycle_id bigint, p_course_offering_id bigint, p_faculty_assignment_id bigint, p_answers jsonb)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_student bigint := sims_private.current_student_id(); v_cycle record; v_tr bigint; v_resp bigint; v_token text := gen_random_uuid()::text;
    v_item record; a jsonb; v_seen bigint[] := '{}'; v_id bigint; v_choice record; v_score numeric; v_text text; v_choice_id bigint; v_ids bigint[]; v_n integer;
BEGIN
    IF v_student IS NULL THEN RAISE EXCEPTION 'Only students can submit feedback' USING ERRCODE = '42501'; END IF;
    IF p_answers IS NULL OR jsonb_typeof(p_answers) <> 'array' OR jsonb_array_length(p_answers) > 200 THEN RAISE EXCEPTION 'p_answers must be an array of at most 200 answers' USING ERRCODE = '22023'; END IF;

    SELECT c.feedback_cycle_id, c.academic_term_id, c.status, c.start_at, c.end_at, q.questionnaire_id, q.questionnaire_type, q.is_anonymous, q.status AS q_status
    INTO v_cycle FROM feedback_cycle c JOIN feedback_questionnaire q ON q.questionnaire_id = c.questionnaire_id WHERE c.feedback_cycle_id = p_cycle_id;
    IF v_cycle IS NULL THEN RAISE EXCEPTION 'Unknown feedback cycle' USING ERRCODE = '45000'; END IF;
    IF v_cycle.status <> 'OPEN' OR now() < v_cycle.start_at OR now() > v_cycle.end_at OR v_cycle.q_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'This feedback cycle is not open for responses' USING ERRCODE = '45000';
    END IF;

    IF v_cycle.questionnaire_type IN ('COURSE', 'FACULTY') THEN
        IF p_course_offering_id IS NULL THEN RAISE EXCEPTION 'A course is required for this feedback' USING ERRCODE = '22023'; END IF;
        SELECT tr.term_registration_id INTO v_tr
        FROM student_course_registration cr
        JOIN student_term_registration tr ON tr.term_registration_id = cr.term_registration_id
        JOIN student_programme_enrolment e ON e.enrolment_id = tr.enrolment_id
        JOIN programme_term_offering pto ON pto.programme_term_offering_id = tr.programme_term_offering_id
        WHERE e.student_id = v_student AND cr.course_offering_id = p_course_offering_id AND pto.academic_term_id = v_cycle.academic_term_id
          AND cr.registration_status IN ('REGISTERED', 'APPROVED', 'COMPLETED') AND tr.registration_status IN ('REGISTERED', 'APPROVED', 'COMPLETED')
        ORDER BY tr.term_registration_id DESC LIMIT 1;
        IF v_tr IS NULL THEN RAISE EXCEPTION 'You are not registered for that course in this cycle''s term' USING ERRCODE = '45000'; END IF;
        IF v_cycle.questionnaire_type = 'FACULTY' THEN
            IF p_faculty_assignment_id IS NULL OR NOT EXISTS (
                SELECT 1 FROM faculty_course_assignment fa JOIN course_offering_section cos ON cos.course_offering_section_id = fa.course_offering_section_id
                WHERE fa.faculty_assignment_id = p_faculty_assignment_id AND cos.course_offering_id = p_course_offering_id AND fa.assignment_status IN ('ACTIVE', 'COMPLETED')) THEN
                RAISE EXCEPTION 'That instructor does not teach this course' USING ERRCODE = '45000';
            END IF;
        ELSIF p_faculty_assignment_id IS NOT NULL THEN
            RAISE EXCEPTION 'This feedback is not about an instructor' USING ERRCODE = '22023';
        END IF;
    ELSE
        IF p_course_offering_id IS NOT NULL OR p_faculty_assignment_id IS NOT NULL THEN RAISE EXCEPTION 'This feedback is not about a course or an instructor' USING ERRCODE = '22023'; END IF;
        SELECT tr.term_registration_id INTO v_tr
        FROM student_term_registration tr JOIN student_programme_enrolment e ON e.enrolment_id = tr.enrolment_id
        JOIN programme_term_offering pto ON pto.programme_term_offering_id = tr.programme_term_offering_id
        WHERE e.student_id = v_student AND pto.academic_term_id = v_cycle.academic_term_id AND tr.registration_status IN ('REGISTERED', 'APPROVED', 'COMPLETED')
        ORDER BY tr.term_registration_id DESC LIMIT 1;
        IF v_tr IS NULL THEN RAISE EXCEPTION 'You are not registered in this cycle''s term' USING ERRCODE = '45000'; END IF;
    END IF;

    -- One submission per (cycle, registration, course, instructor); the primary key is the arbiter under concurrency.
    BEGIN
        INSERT INTO sims_private.feedback_submission (feedback_cycle_id, term_registration_id, course_offering_id, faculty_assignment_id)
        VALUES (p_cycle_id, v_tr, COALESCE(p_course_offering_id, 0), COALESCE(p_faculty_assignment_id, 0));
    EXCEPTION WHEN unique_violation THEN
        RAISE EXCEPTION 'You have already submitted this feedback' USING ERRCODE = '45000';
    END;

    INSERT INTO feedback_response (feedback_cycle_id, term_registration_id, course_offering_id, faculty_assignment_id, submitted_at, response_token)
    VALUES (p_cycle_id, CASE WHEN v_cycle.is_anonymous THEN NULL ELSE v_tr END, p_course_offering_id, p_faculty_assignment_id,
            CASE WHEN v_cycle.is_anonymous THEN date_trunc('day', now()) ELSE now() END, v_token)
    RETURNING feedback_response_id INTO v_resp;

    FOR a IN SELECT * FROM jsonb_array_elements(p_answers) LOOP
        IF jsonb_typeof(a) <> 'object' OR (a ->> 'questionnaire_item_id') !~ '^[0-9]{1,15}$' THEN RAISE EXCEPTION 'Invalid answer: %', left(a::text, 100) USING ERRCODE = '22023'; END IF;
        v_id := (a ->> 'questionnaire_item_id')::bigint;
        IF v_id = ANY (v_seen) THEN RAISE EXCEPTION 'A question was answered twice' USING ERRCODE = '22023'; END IF;
        v_seen := v_seen || v_id;
        SELECT i.questionnaire_item_id, i.is_required, q.response_type, q.feedback_question_id INTO v_item
        FROM feedback_questionnaire_item i JOIN feedback_question q ON q.feedback_question_id = i.feedback_question_id
        WHERE i.questionnaire_item_id = v_id AND i.questionnaire_id = v_cycle.questionnaire_id;
        IF v_item IS NULL THEN RAISE EXCEPTION 'Question % is not part of this questionnaire', v_id USING ERRCODE = '22023'; END IF;

        v_score := NULL; v_text := NULL; v_choice_id := NULL;
        IF v_item.response_type = 'RATING' THEN
            IF (a ->> 'score') !~ '^[0-9]{1,2}$' OR (a ->> 'score')::int < 1 OR (a ->> 'score')::int > sims_private.feedback_rating_max() THEN
                RAISE EXCEPTION 'A rating must be a whole number from 1 to %', sims_private.feedback_rating_max() USING ERRCODE = '22023';
            END IF;
            v_score := (a ->> 'score')::numeric;
        ELSIF v_item.response_type = 'SINGLE_CHOICE' THEN
            IF (a ->> 'choice_id') !~ '^[0-9]{1,15}$' THEN RAISE EXCEPTION 'Choose an option for every answered choice question' USING ERRCODE = '22023'; END IF;
            SELECT feedback_choice_id, score INTO v_choice FROM feedback_choice WHERE feedback_choice_id = (a ->> 'choice_id')::bigint AND feedback_question_id = v_item.feedback_question_id AND is_active;
            IF v_choice IS NULL THEN RAISE EXCEPTION 'That option does not belong to the question' USING ERRCODE = '22023'; END IF;
            v_choice_id := v_choice.feedback_choice_id; v_score := v_choice.score;
        ELSIF v_item.response_type = 'MULTIPLE_CHOICE' THEN
            IF jsonb_typeof(a -> 'choice_ids') <> 'array' OR jsonb_array_length(a -> 'choice_ids') = 0 OR jsonb_array_length(a -> 'choice_ids') > 50 THEN RAISE EXCEPTION 'Choose at least one option' USING ERRCODE = '22023'; END IF;
            SELECT array_agg(DISTINCT x::bigint ORDER BY x::bigint) INTO v_ids FROM jsonb_array_elements_text(a -> 'choice_ids') x WHERE x ~ '^[0-9]{1,15}$';
            SELECT count(*) INTO v_n FROM feedback_choice WHERE feedback_choice_id = ANY (v_ids) AND feedback_question_id = v_item.feedback_question_id AND is_active;
            IF v_ids IS NULL OR v_n <> cardinality(v_ids) OR cardinality(v_ids) <> jsonb_array_length(a -> 'choice_ids') THEN RAISE EXCEPTION 'Some chosen options do not belong to the question' USING ERRCODE = '22023'; END IF;
            v_text := array_to_string(v_ids, ',');
        ELSE
            v_text := btrim(a ->> 'text');
            IF v_text IS NULL OR v_text = '' OR length(v_text) > 2000 THEN RAISE EXCEPTION 'A written answer must be 1 to 2000 characters' USING ERRCODE = '22023'; END IF;
        END IF;
        INSERT INTO feedback_response_item (feedback_response_id, questionnaire_item_id, feedback_choice_id, numeric_score, text_response)
        VALUES (v_resp, v_id, v_choice_id, v_score, v_text);
    END LOOP;

    IF EXISTS (SELECT 1 FROM feedback_questionnaire_item i WHERE i.questionnaire_id = v_cycle.questionnaire_id AND i.is_required AND NOT (i.questionnaire_item_id = ANY (v_seen))) THEN
        RAISE EXCEPTION 'Please answer every required question' USING ERRCODE = '22023';
    END IF;
    RETURN v_token;
END $function$;

CREATE OR REPLACE FUNCTION public.fin_adjustment_create(p_number text, p_student_account_id bigint, p_assessment_item_id bigint, p_type text, p_amount numeric, p_reason text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_id bigint; v_ex record; v_acc bigint;
BEGIN
    PERFORM sims_private.fin_authorize(p_student_account_id, 'FEE_REFUND', 'CREATE');
    IF p_number IS NULL OR btrim(p_number) = '' OR p_reason IS NULL OR btrim(p_reason) = '' OR length(p_reason) > 500 THEN RAISE EXCEPTION 'A number and a reason (at most 500 characters) are required' USING ERRCODE = '22023'; END IF;
    IF p_type NOT IN ('CREDIT', 'DEBIT', 'WAIVER', 'WRITE_OFF') THEN RAISE EXCEPTION 'Adjustment type % is not supported', p_type USING ERRCODE = '22023'; END IF;
    PERFORM sims_private.fin_check_amount(p_amount, 'amount');
    SELECT a.student_account_id INTO v_acc FROM student_fee_assessment_item i JOIN student_fee_assessment a ON a.fee_assessment_id = i.fee_assessment_id WHERE i.assessment_item_id = p_assessment_item_id;
    IF v_acc IS DISTINCT FROM p_student_account_id THEN RAISE EXCEPTION 'The fee item does not belong to this account' USING ERRCODE = '45000'; END IF;
    SELECT fee_adjustment_id, student_account_id, assessment_item_id, adjustment_type, adjustment_amount INTO v_ex FROM fee_adjustment WHERE adjustment_number = p_number;
    IF FOUND THEN
        IF v_ex.student_account_id = p_student_account_id AND v_ex.assessment_item_id = p_assessment_item_id AND v_ex.adjustment_type = p_type AND v_ex.adjustment_amount = p_amount THEN RETURN v_ex.fee_adjustment_id; END IF;
        RAISE EXCEPTION 'adjustment number already used with different details' USING ERRCODE = '23505';
    END IF;
    INSERT INTO fee_adjustment (adjustment_number, student_account_id, assessment_item_id, adjustment_type, adjustment_date, adjustment_amount, reason, approval_status)
    VALUES (p_number, p_student_account_id, p_assessment_item_id, p_type, current_date, p_amount, p_reason, 'SUBMITTED') RETURNING fee_adjustment_id INTO v_id;
    PERFORM sims_private.fin_audit('ADJUSTMENT_REQUESTED', 'fee_adjustment', v_id, NULL, jsonb_build_object('type', p_type, 'amount', p_amount, 'item_id', p_assessment_item_id));
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.fin_adjustment_decide(p_adjustment_id bigint, p_approve boolean, p_remarks text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a record; it record; v_sign integer;
BEGIN
    SELECT * INTO a FROM fee_adjustment WHERE fee_adjustment_id = p_adjustment_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Not authorised (FEES.FEE_REFUND.APPROVE) or unknown adjustment' USING ERRCODE = '42501'; END IF;
    PERFORM sims_private.fin_authorize(a.student_account_id, 'FEE_REFUND', 'APPROVE');
    IF a.approval_status <> 'SUBMITTED' THEN RAISE EXCEPTION 'Only a submitted adjustment can be decided (status %)', a.approval_status USING ERRCODE = '45000'; END IF;
    IF sims_private.fin_creator_is_caller('fee_adjustment', p_adjustment_id) THEN RAISE EXCEPTION 'You cannot decide an adjustment that you requested yourself' USING ERRCODE = '45000'; END IF;
    IF NOT p_approve THEN
        IF p_remarks IS NULL OR btrim(p_remarks) = '' THEN RAISE EXCEPTION 'A reason is required to reject' USING ERRCODE = '22023'; END IF;
        UPDATE fee_adjustment SET approval_status = 'REJECTED' WHERE fee_adjustment_id = p_adjustment_id;
        PERFORM sims_private.fin_audit('ADJUSTMENT_REJECTED', 'fee_adjustment', p_adjustment_id, NULL, jsonb_build_object('remarks', p_remarks));
        RETURN;
    END IF;
    SELECT * INTO it FROM sims_private.fin_editable_item(a.assessment_item_id);
    v_sign := CASE WHEN a.adjustment_type = 'DEBIT' THEN 1 ELSE -1 END;
    IF v_sign < 0 AND a.adjustment_amount > it.balance_amount THEN RAISE EXCEPTION 'The reduction exceeds the unpaid balance of the item (%)', it.balance_amount USING ERRCODE = '45000'; END IF;
    UPDATE student_fee_assessment_item
       SET adjustment_amount = adjustment_amount + v_sign * a.adjustment_amount, net_amount = net_amount + v_sign * a.adjustment_amount, balance_amount = balance_amount + v_sign * a.adjustment_amount
     WHERE assessment_item_id = a.assessment_item_id;
    PERFORM sims_private.fin_refresh_status(a.assessment_item_id);
    UPDATE fee_adjustment SET approval_status = 'APPROVED', approved_by = sims_private.current_user_id(), approved_at = now() WHERE fee_adjustment_id = p_adjustment_id;
    PERFORM sims_private.fin_audit('ADJUSTMENT_APPROVED', 'fee_adjustment', p_adjustment_id, NULL, jsonb_build_object('type', a.adjustment_type, 'amount', a.adjustment_amount, 'remarks', p_remarks));
END $function$;

CREATE OR REPLACE FUNCTION public.fin_allocate_payment(p_payment_transaction_id bigint, p_assessment_item_id bigint, p_amount numeric)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_account bigint; v_item record; v_alloc record; v_id bigint; v_fa bigint;
BEGIN
    SELECT student_account_id INTO v_account FROM payment_transaction WHERE payment_transaction_id = p_payment_transaction_id;
    IF v_account IS NULL THEN
        RAISE EXCEPTION 'Not authorised (FEES.FEE_PAYMENT.CREATE) or unknown payment, or not a student-account payment' USING ERRCODE = '42501';
    END IF;
    PERFORM sims_private.fin_authorize(v_account, 'FEE_PAYMENT', 'CREATE');
    PERFORM sims_private.fin_check_amount(p_amount, 'amount');

    PERFORM 1 FROM payment_transaction WHERE payment_transaction_id = p_payment_transaction_id FOR UPDATE;  -- lock order: payment, then item
    SELECT i.item_status, i.fee_assessment_id, a.student_account_id INTO v_item
      FROM student_fee_assessment_item i JOIN student_fee_assessment a ON a.fee_assessment_id = i.fee_assessment_id
     WHERE i.assessment_item_id = p_assessment_item_id FOR UPDATE OF i;
    IF NOT FOUND OR v_item.student_account_id IS DISTINCT FROM v_account THEN
        RAISE EXCEPTION 'Fee item does not belong to the payer account' USING ERRCODE = '45000';
    END IF;
    IF v_item.item_status IN ('CANCELLED', 'WAIVED') THEN
        RAISE EXCEPTION 'Fee item is %', v_item.item_status USING ERRCODE = '45000';
    END IF;

    SELECT payment_allocation_id, allocated_amount INTO v_alloc FROM payment_allocation
     WHERE payment_transaction_id = p_payment_transaction_id AND assessment_item_id = p_assessment_item_id;
    IF FOUND THEN
        IF v_alloc.allocated_amount = p_amount THEN RETURN v_alloc.payment_allocation_id; END IF;  -- idempotent replay
        RAISE EXCEPTION 'An allocation for this payment and item already exists with a different amount' USING ERRCODE = '23505';
    END IF;

    INSERT INTO payment_allocation (payment_transaction_id, assessment_item_id, allocated_amount, allocated_by)
    VALUES (p_payment_transaction_id, p_assessment_item_id, p_amount, sims_private.current_user_id())
    RETURNING payment_allocation_id INTO v_id;  -- guard + totals triggers run here

    UPDATE student_fee_assessment_item
       SET item_status = CASE WHEN balance_amount = 0 THEN 'PAID' WHEN amount_paid > 0 THEN 'PARTIALLY_PAID' ELSE item_status END
     WHERE assessment_item_id = p_assessment_item_id AND item_status IN ('ASSESSED', 'PARTIALLY_PAID', 'OVERDUE');
    v_fa := v_item.fee_assessment_id;
    UPDATE student_fee_assessment
       SET assessment_status = CASE WHEN balance_amount = 0 THEN 'PAID' WHEN amount_paid > 0 THEN 'PARTIALLY_PAID' ELSE assessment_status END
     WHERE fee_assessment_id = v_fa AND assessment_status IN ('ASSESSED', 'PARTIALLY_PAID', 'OVERDUE');
    PERFORM sims_private.fin_audit('PAYMENT_ALLOCATED', 'payment_allocation', v_id, NULL,
        jsonb_build_object('payment_transaction_id', p_payment_transaction_id, 'assessment_item_id', p_assessment_item_id, 'amount', p_amount));
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.fin_benefit_apply(p_kind text, p_benefit_id bigint, p_assessment_item_id bigint, p_amount numeric DEFAULT NULL::numeric)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE b record; it record; v_applied numeric; v_remaining numeric; v_amt numeric; v_id bigint;
BEGIN
    SELECT * INTO b FROM sims_private.fin_benefit_load(p_kind, p_benefit_id);
    IF b.student_id IS NULL THEN RAISE EXCEPTION 'Not authorised (FEES.FEE_BENEFIT.UPDATE) or unknown benefit' USING ERRCODE = '42501'; END IF;
    PERFORM sims_private.fin_authorize_student(b.student_id, 'FEE_BENEFIT', 'UPDATE');
    SELECT * INTO it FROM sims_private.fin_editable_item(p_assessment_item_id);
    IF it.student_id IS DISTINCT FROM b.student_id THEN RAISE EXCEPTION 'The benefit and the fee item belong to different students' USING ERRCODE = '45000'; END IF;
    IF b.status <> b.usable_status THEN RAISE EXCEPTION 'The benefit is not approved (status %)', b.status USING ERRCODE = '45000'; END IF;
    IF (b.valid_from IS NOT NULL AND current_date < b.valid_from) OR (b.valid_to IS NOT NULL AND current_date > b.valid_to) THEN RAISE EXCEPTION 'The benefit is not valid today' USING ERRCODE = '45000'; END IF;
    IF b.basis = 'PERCENTAGE' THEN
        SELECT COALESCE(sum(benefit_amount), 0) INTO v_applied FROM fee_assessment_benefit WHERE student_concession_id = p_benefit_id AND assessment_item_id = p_assessment_item_id;
        v_remaining := round(it.original_amount * b.pct / 100, 2) - v_applied;
    ELSE
        SELECT COALESCE(sum(benefit_amount), 0) INTO v_applied FROM fee_assessment_benefit
         WHERE (p_kind = 'CONCESSION' AND student_concession_id = p_benefit_id) OR (p_kind = 'SCHOLARSHIP' AND student_scholarship_id = p_benefit_id) OR (p_kind = 'SPONSORSHIP' AND student_sponsorship_id = p_benefit_id);
        v_remaining := b.amount - v_applied;
    END IF;
    v_amt := COALESCE(p_amount, v_remaining);
    PERFORM sims_private.fin_check_amount(v_amt, 'amount');
    IF v_amt > v_remaining THEN RAISE EXCEPTION 'The amount exceeds what is left of the benefit (%)', greatest(v_remaining, 0) USING ERRCODE = '45000'; END IF;
    IF v_amt > it.balance_amount THEN RAISE EXCEPTION 'The amount exceeds the unpaid balance of the item (%)', it.balance_amount USING ERRCODE = '45000'; END IF;
    INSERT INTO fee_assessment_benefit (assessment_item_id, benefit_type, student_concession_id, student_scholarship_id, student_sponsorship_id, benefit_amount, applied_date, approved_by)
    VALUES (p_assessment_item_id, p_kind, CASE WHEN p_kind = 'CONCESSION' THEN p_benefit_id END, CASE WHEN p_kind = 'SCHOLARSHIP' THEN p_benefit_id END,
            CASE WHEN p_kind = 'SPONSORSHIP' THEN p_benefit_id END, v_amt, current_date, sims_private.current_user_id())
    RETURNING assessment_benefit_id INTO v_id;
    UPDATE student_fee_assessment_item
       SET concession_amount = concession_amount + CASE WHEN p_kind = 'CONCESSION' THEN v_amt ELSE 0 END,
           scholarship_amount = scholarship_amount + CASE WHEN p_kind = 'CONCESSION' THEN 0 ELSE v_amt END,
           net_amount = net_amount - v_amt, balance_amount = balance_amount - v_amt
     WHERE assessment_item_id = p_assessment_item_id;
    PERFORM sims_private.fin_refresh_status(p_assessment_item_id);
    PERFORM sims_private.fin_audit('BENEFIT_APPLIED', 'fee_assessment_benefit', v_id, NULL, jsonb_build_object('kind', p_kind, 'benefit_id', p_benefit_id, 'item_id', p_assessment_item_id, 'amount', v_amt));
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.fin_benefit_create(p_kind text, p_student_id bigint, p_academic_year_id integer, p_type_id bigint, p_amount numeric, p_percentage numeric, p_reference text, p_authority text, p_remarks text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_id bigint; v_t record; v_s record;
BEGIN
    PERFORM sims_private.fin_authorize_student(p_student_id, 'FEE_BENEFIT', 'CREATE');
    IF p_kind NOT IN ('CONCESSION', 'SCHOLARSHIP', 'SPONSORSHIP') THEN RAISE EXCEPTION 'Unknown benefit kind' USING ERRCODE = '22023'; END IF;
    IF NOT EXISTS (SELECT 1 FROM academic_year WHERE academic_year_id = p_academic_year_id) THEN RAISE EXCEPTION 'Unknown academic year' USING ERRCODE = '22023'; END IF;
    IF p_remarks IS NOT NULL AND length(p_remarks) > 500 THEN RAISE EXCEPTION 'Remarks are too long' USING ERRCODE = '22023'; END IF;
    IF p_kind = 'CONCESSION' THEN
        SELECT * INTO v_t FROM concession_type WHERE concession_type_id = p_type_id AND is_active;
        IF NOT FOUND THEN RAISE EXCEPTION 'Unknown or inactive concession type' USING ERRCODE = '22023'; END IF;
        IF v_t.concession_basis = 'PERCENTAGE' THEN
            IF p_percentage IS NULL OR p_percentage <= 0 OR p_percentage > 100 OR p_percentage <> round(p_percentage, 2) THEN RAISE EXCEPTION 'A percentage between 0 and 100 is required' USING ERRCODE = '22023'; END IF;
            IF v_t.maximum_percentage IS NOT NULL AND p_percentage > v_t.maximum_percentage THEN RAISE EXCEPTION 'The percentage exceeds the maximum of % for this concession type', v_t.maximum_percentage USING ERRCODE = '45000'; END IF;
        ELSE
            PERFORM sims_private.fin_check_amount(p_amount, 'amount');
            IF v_t.maximum_amount IS NOT NULL AND p_amount > v_t.maximum_amount THEN RAISE EXCEPTION 'The amount exceeds the maximum of % for this concession type', v_t.maximum_amount USING ERRCODE = '45000'; END IF;
        END IF;
        INSERT INTO student_fee_concession (student_id, concession_type_id, academic_year_id, application_number, application_date, approved_percentage, approved_amount, approval_status, remarks)
        VALUES (p_student_id, p_type_id, p_academic_year_id, left(p_reference, 50), current_date,
                CASE WHEN v_t.concession_basis = 'PERCENTAGE' THEN p_percentage END, CASE WHEN v_t.concession_basis = 'FIXED_AMOUNT' THEN p_amount END, 'SUBMITTED', p_remarks)
        RETURNING student_concession_id INTO v_id;
        PERFORM sims_private.fin_audit('BENEFIT_REQUESTED', 'student_fee_concession', v_id, NULL, jsonb_build_object('student_id', p_student_id, 'type', p_type_id, 'amount', p_amount, 'percentage', p_percentage));
    ELSIF p_kind = 'SCHOLARSHIP' THEN
        SELECT * INTO v_s FROM scholarship_scheme WHERE scholarship_scheme_id = p_type_id AND is_active;
        IF NOT FOUND THEN RAISE EXCEPTION 'Unknown or inactive scholarship scheme' USING ERRCODE = '22023'; END IF;
        PERFORM sims_private.fin_check_amount(p_amount, 'amount');
        IF v_s.maximum_amount IS NOT NULL AND p_amount > v_s.maximum_amount THEN RAISE EXCEPTION 'The amount exceeds the maximum of % for this scheme', v_s.maximum_amount USING ERRCODE = '45000'; END IF;
        INSERT INTO student_scholarship (student_id, scholarship_scheme_id, academic_year_id, application_number, applied_amount, application_status, remarks)
        VALUES (p_student_id, p_type_id, p_academic_year_id, left(p_reference, 60), p_amount, 'SUBMITTED', p_remarks)
        RETURNING student_scholarship_id INTO v_id;
        PERFORM sims_private.fin_audit('BENEFIT_REQUESTED', 'student_scholarship', v_id, NULL, jsonb_build_object('student_id', p_student_id, 'scheme', p_type_id, 'amount', p_amount));
    ELSE
        PERFORM sims_private.fin_check_amount(p_amount, 'amount');
        IF p_authority IS NULL OR btrim(p_authority) = '' OR p_reference IS NULL OR btrim(p_reference) = '' THEN RAISE EXCEPTION 'The sponsoring authority and the sanction reference are required' USING ERRCODE = '22023'; END IF;
        INSERT INTO student_sponsorship (student_id, academic_year_id, sponsoring_authority, sanction_reference, sanctioned_amount, approval_status)
        VALUES (p_student_id, p_academic_year_id, left(p_authority, 200), left(p_reference, 100), p_amount, 'PENDING')
        RETURNING student_sponsorship_id INTO v_id;
        PERFORM sims_private.fin_audit('BENEFIT_REQUESTED', 'student_sponsorship', v_id, NULL, jsonb_build_object('student_id', p_student_id, 'amount', p_amount));
    END IF;
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.fin_benefit_decide(p_kind text, p_id bigint, p_approve boolean, p_amount numeric DEFAULT NULL::numeric, p_percentage numeric DEFAULT NULL::numeric, p_remarks text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE b record; v_pct numeric; v_amt numeric;
BEGIN
    SELECT * INTO b FROM sims_private.fin_benefit_load(p_kind, p_id);
    IF b.student_id IS NULL THEN RAISE EXCEPTION 'Not authorised (FEES.FEE_BENEFIT.APPROVE) or unknown benefit' USING ERRCODE = '42501'; END IF;
    PERFORM sims_private.fin_authorize_student(b.student_id, 'FEE_BENEFIT', 'APPROVE');
    IF b.status <> b.open_status THEN RAISE EXCEPTION 'Only a % request can be decided (status %)', lower(b.open_status), b.status USING ERRCODE = '45000'; END IF;
    IF sims_private.fin_creator_is_caller(CASE p_kind WHEN 'CONCESSION' THEN 'student_fee_concession' WHEN 'SCHOLARSHIP' THEN 'student_scholarship' ELSE 'student_sponsorship' END, p_id) THEN
        RAISE EXCEPTION 'You cannot decide a request that you made yourself' USING ERRCODE = '45000';
    END IF;
    IF NOT p_approve AND (p_remarks IS NULL OR btrim(p_remarks) = '') THEN RAISE EXCEPTION 'A reason is required to reject' USING ERRCODE = '22023'; END IF;
    IF p_remarks IS NOT NULL AND length(p_remarks) > 500 THEN RAISE EXCEPTION 'Remarks are too long' USING ERRCODE = '22023'; END IF;
    IF p_approve THEN
        v_pct := COALESCE(p_percentage, b.pct); v_amt := COALESCE(p_amount, b.amount);
        IF p_kind = 'CONCESSION' THEN
            IF b.basis = 'PERCENTAGE' THEN
                IF v_pct IS NULL OR v_pct <= 0 OR v_pct > 100 OR v_pct <> round(v_pct, 2) OR (b.max_pct IS NOT NULL AND v_pct > b.max_pct) THEN RAISE EXCEPTION 'The approved percentage is not allowed for this concession type' USING ERRCODE = '45000'; END IF;
                v_amt := NULL;
            ELSE
                PERFORM sims_private.fin_check_amount(v_amt, 'amount');
                IF b.max_amount IS NOT NULL AND v_amt > b.max_amount THEN RAISE EXCEPTION 'The approved amount exceeds the maximum for this concession type' USING ERRCODE = '45000'; END IF;
                v_pct := NULL;
            END IF;
            UPDATE student_fee_concession SET approval_status = 'APPROVED', approved_percentage = v_pct, approved_amount = v_amt, approved_by = sims_private.current_user_id(), approved_at = now(),
                   remarks = COALESCE(left(p_remarks, 500), remarks) WHERE student_concession_id = p_id;
        ELSIF p_kind = 'SCHOLARSHIP' THEN
            PERFORM sims_private.fin_check_amount(v_amt, 'amount');
            IF b.max_amount IS NOT NULL AND v_amt > b.max_amount THEN RAISE EXCEPTION 'The sanctioned amount exceeds the maximum for this scheme' USING ERRCODE = '45000'; END IF;
            UPDATE student_scholarship SET application_status = 'SANCTIONED', sanctioned_amount = v_amt, sanction_date = current_date, remarks = COALESCE(left(p_remarks, 500), remarks) WHERE student_scholarship_id = p_id;
        ELSE
            UPDATE student_sponsorship SET approval_status = 'APPROVED', approved_by = sims_private.current_user_id(), approved_at = now() WHERE student_sponsorship_id = p_id;
        END IF;
    ELSE
        IF p_kind = 'CONCESSION' THEN UPDATE student_fee_concession SET approval_status = 'REJECTED', remarks = left(p_remarks, 500) WHERE student_concession_id = p_id;
        ELSIF p_kind = 'SCHOLARSHIP' THEN UPDATE student_scholarship SET application_status = 'REJECTED', remarks = left(p_remarks, 500) WHERE student_scholarship_id = p_id;
        ELSE UPDATE student_sponsorship SET approval_status = 'REJECTED' WHERE student_sponsorship_id = p_id; END IF;
    END IF;
    PERFORM sims_private.fin_audit(CASE WHEN p_approve THEN 'BENEFIT_APPROVED' ELSE 'BENEFIT_REJECTED' END,
        CASE p_kind WHEN 'CONCESSION' THEN 'student_fee_concession' WHEN 'SCHOLARSHIP' THEN 'student_scholarship' ELSE 'student_sponsorship' END, p_id, NULL,
        jsonb_build_object('amount', v_amt, 'percentage', v_pct, 'remarks', p_remarks));
END $function$;

CREATE OR REPLACE FUNCTION public.fin_cancel_receipt(p_receipt_id bigint, p_reason text, p_replace boolean DEFAULT false)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE r record; v_acct bigint; v_reason text := NULLIF(btrim(p_reason), ''); v_new bigint;
BEGIN
    SELECT f.fee_receipt_id, f.receipt_status, f.payment_transaction_id, f.receipt_amount, t.student_account_id INTO r
    FROM fee_receipt f JOIN payment_transaction t ON t.payment_transaction_id = f.payment_transaction_id WHERE f.fee_receipt_id = p_receipt_id FOR UPDATE OF f;
    IF r.fee_receipt_id IS NULL OR r.student_account_id IS NULL THEN RAISE EXCEPTION 'Not authorised (FEES.FEE_PAYMENT.UPDATE) or unknown receipt' USING ERRCODE = '42501'; END IF;
    v_acct := r.student_account_id;
    PERFORM sims_private.fin_authorize(v_acct, 'FEE_PAYMENT', 'UPDATE');
    IF v_reason IS NULL OR length(v_reason) > 500 THEN RAISE EXCEPTION 'A reason is required (at most 500 characters)' USING ERRCODE = '22023'; END IF;
    IF r.receipt_status <> 'ISSUED' THEN RAISE EXCEPTION 'Only an issued receipt can be cancelled or replaced' USING ERRCODE = '45000'; END IF;
    UPDATE fee_receipt SET receipt_status = CASE WHEN p_replace THEN 'REPLACED' ELSE 'CANCELLED' END, cancelled_by = sims_private.current_user_id(), cancelled_at = now(), cancellation_reason = v_reason WHERE fee_receipt_id = p_receipt_id;
    IF p_replace THEN
        INSERT INTO fee_receipt (receipt_number, payment_transaction_id, receipt_date, receipt_amount, issued_by, original_receipt_id)
        VALUES (sims_private.fin_next_receipt_number(), r.payment_transaction_id, now(), r.receipt_amount, sims_private.current_user_id(), p_receipt_id) RETURNING fee_receipt_id INTO v_new;
    END IF;
    PERFORM sims_private.fin_audit(CASE WHEN p_replace THEN 'REPLACE_RECEIPT' ELSE 'CANCEL_RECEIPT' END, 'fee_receipt', p_receipt_id, jsonb_build_object('status', r.receipt_status), jsonb_build_object('reason', v_reason, 'replacement', v_new));
    RETURN v_new;
END $function$;

CREATE OR REPLACE FUNCTION public.fin_create_fee_assessment(p_assessment_number text, p_student_account_id bigint, p_academic_year_id integer, p_assessment_type text, p_assessment_date date, p_due_date date, p_items jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_id bigint; v_status text; v_ex record; it jsonb;
    v_orig numeric; v_con numeric; v_sch numeric; v_adj numeric; v_net numeric;
BEGIN
    PERFORM sims_private.fin_authorize(p_student_account_id, 'FEE_ASSESSMENT', 'CREATE');
    IF p_assessment_number IS NULL OR btrim(p_assessment_number) = '' THEN
        RAISE EXCEPTION 'assessment_number is required (idempotency key)' USING ERRCODE = '22023';
    END IF;
    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'p_items must be a non-empty array' USING ERRCODE = '22023';
    END IF;
    SELECT account_status INTO v_status FROM student_financial_account WHERE student_account_id = p_student_account_id;
    IF v_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'Student account is not ACTIVE (%)', v_status USING ERRCODE = '45000';
    END IF;

    SELECT fee_assessment_id, student_account_id, academic_year_id INTO v_ex FROM student_fee_assessment WHERE assessment_number = p_assessment_number;
    IF FOUND THEN
        IF v_ex.student_account_id IS NOT DISTINCT FROM p_student_account_id AND v_ex.academic_year_id = p_academic_year_id THEN
            RETURN v_ex.fee_assessment_id;  -- idempotent replay
        END IF;
        RAISE EXCEPTION 'assessment_number already used for a different assessment' USING ERRCODE = '23505';
    END IF;

    FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_orig := (it ->> 'original_amount')::numeric;
        v_con := COALESCE((it ->> 'concession_amount')::numeric, 0);
        v_sch := COALESCE((it ->> 'scholarship_amount')::numeric, 0);
        v_adj := COALESCE((it ->> 'adjustment_amount')::numeric, 0);
        IF v_orig IS NULL OR v_orig < 0 OR v_con < 0 OR v_sch < 0
           OR v_orig <> round(v_orig, 2) OR v_con <> round(v_con, 2) OR v_sch <> round(v_sch, 2) OR v_adj <> round(v_adj, 2)
           OR (it ->> 'fee_type_id') IS NULL THEN
            RAISE EXCEPTION 'Invalid fee item: %', it USING ERRCODE = '22023';
        END IF;
        IF v_orig - v_con - v_sch + v_adj < 0 THEN
            RAISE EXCEPTION 'Fee item net amount cannot be negative: %', it USING ERRCODE = '22023';
        END IF;
    END LOOP;

    INSERT INTO student_fee_assessment (assessment_number, student_account_id, academic_year_id, assessment_type, assessment_date, due_date, assessment_status, created_by)
    VALUES (p_assessment_number, p_student_account_id, p_academic_year_id, p_assessment_type, p_assessment_date, p_due_date, 'DRAFT', sims_private.current_user_id())
    ON CONFLICT (assessment_number) DO NOTHING
    RETURNING fee_assessment_id INTO v_id;
    IF v_id IS NULL THEN  -- lost a race with an identical concurrent call
        SELECT fee_assessment_id INTO v_id FROM student_fee_assessment
         WHERE assessment_number = p_assessment_number AND student_account_id = p_student_account_id AND academic_year_id = p_academic_year_id;
        IF v_id IS NULL THEN
            RAISE EXCEPTION 'assessment_number already used for a different assessment' USING ERRCODE = '23505';
        END IF;
        RETURN v_id;
    END IF;

    FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
        v_orig := (it ->> 'original_amount')::numeric;
        v_con := COALESCE((it ->> 'concession_amount')::numeric, 0);
        v_sch := COALESCE((it ->> 'scholarship_amount')::numeric, 0);
        v_adj := COALESCE((it ->> 'adjustment_amount')::numeric, 0);
        v_net := v_orig - v_con - v_sch + v_adj;
        INSERT INTO student_fee_assessment_item (fee_assessment_id, fee_type_id, description, original_amount, concession_amount, scholarship_amount,
                                                 adjustment_amount, net_amount, amount_paid, balance_amount, due_date)
        VALUES (v_id, (it ->> 'fee_type_id')::bigint, it ->> 'description', v_orig, v_con, v_sch, v_adj, v_net, 0, v_net,
                COALESCE((it ->> 'due_date')::date, p_due_date));
    END LOOP;  -- item triggers keep the header totals in sync

    UPDATE student_fee_assessment SET assessment_status = 'ASSESSED' WHERE fee_assessment_id = v_id;
    PERFORM sims_private.fin_audit('ASSESSMENT_CREATED', 'student_fee_assessment', v_id, NULL,
        (SELECT to_jsonb(a) FROM student_fee_assessment a WHERE a.fee_assessment_id = v_id));
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.fin_decide_refund(p_refund_request_id bigint, p_approve boolean, p_approved_amount numeric DEFAULT NULL::numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_req record; v_amt numeric; v_pay_amount numeric;
BEGIN
    SELECT student_account_id INTO v_req FROM refund_request WHERE refund_request_id = p_refund_request_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Not authorised (FEES.FEE_REFUND.APPROVE) or unknown request' USING ERRCODE = '42501'; END IF;
    PERFORM sims_private.fin_authorize(v_req.student_account_id, 'FEE_REFUND', 'APPROVE');
    SELECT student_account_id, payment_transaction_id, requested_amount, request_status, approved_amount INTO v_req
      FROM refund_request WHERE refund_request_id = p_refund_request_id FOR UPDATE;
    IF p_approve THEN
        IF v_req.request_status = 'APPROVED' THEN RETURN; END IF;  -- idempotent replay
        IF v_req.request_status NOT IN ('SUBMITTED', 'UNDER_REVIEW') THEN
            RAISE EXCEPTION 'Request is % and cannot be approved', v_req.request_status USING ERRCODE = '45000';
        END IF;
        v_amt := COALESCE(p_approved_amount, v_req.requested_amount);
        PERFORM sims_private.fin_check_amount(v_amt, 'approved amount');
        IF v_amt > v_req.requested_amount THEN
            RAISE EXCEPTION 'Approved amount cannot exceed the requested amount' USING ERRCODE = '45000';
        END IF;
        IF v_req.payment_transaction_id IS NOT NULL THEN
            SELECT amount INTO v_pay_amount FROM payment_transaction WHERE payment_transaction_id = v_req.payment_transaction_id FOR UPDATE;
            IF v_amt > v_pay_amount - sims_private.fin_refunded_on_payment(v_req.payment_transaction_id) THEN
                RAISE EXCEPTION 'Approved amount exceeds the refundable balance of the payment' USING ERRCODE = '45000';
            END IF;
        END IF;
        UPDATE refund_request SET request_status = 'APPROVED', approved_amount = v_amt, approved_by = sims_private.current_user_id(), approved_at = now()
         WHERE refund_request_id = p_refund_request_id;
        PERFORM sims_private.fin_audit('REFUND_APPROVED', 'refund_request', p_refund_request_id, NULL, jsonb_build_object('approved_amount', v_amt));
    ELSE
        IF v_req.request_status = 'REJECTED' THEN RETURN; END IF;
        IF v_req.request_status NOT IN ('SUBMITTED', 'UNDER_REVIEW') THEN
            RAISE EXCEPTION 'Request is % and cannot be rejected', v_req.request_status USING ERRCODE = '45000';
        END IF;
        UPDATE refund_request SET request_status = 'REJECTED', approved_by = sims_private.current_user_id(), approved_at = now()
         WHERE refund_request_id = p_refund_request_id;
        PERFORM sims_private.fin_audit('REFUND_REJECTED', 'refund_request', p_refund_request_id, NULL, NULL);
    END IF;
END $function$;

CREATE OR REPLACE FUNCTION public.fin_hold_place(p_student_account_id bigint, p_hold_type text, p_reason text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_reason text := NULLIF(btrim(p_reason), ''); v_id bigint; v_status text;
BEGIN
    PERFORM sims_private.fin_authorize(p_student_account_id, 'FEE_ASSESSMENT', 'UPDATE');
    IF p_hold_type NOT IN ('REGISTRATION', 'EXAMINATION', 'HALL_TICKET', 'RESULT', 'CERTIFICATE', 'HOSTEL_CHECKOUT', 'GRADUATION', 'OTHER') THEN RAISE EXCEPTION 'Invalid hold type' USING ERRCODE = '22023'; END IF;
    IF v_reason IS NULL OR length(v_reason) > 500 THEN RAISE EXCEPTION 'A reason is required (at most 500 characters)' USING ERRCODE = '22023'; END IF;
    SELECT account_status INTO v_status FROM student_financial_account WHERE student_account_id = p_student_account_id FOR UPDATE;
    IF v_status = 'CLOSED' THEN RAISE EXCEPTION 'Student account is CLOSED' USING ERRCODE = '45000'; END IF;
    SELECT financial_hold_id INTO v_id FROM student_financial_hold WHERE student_account_id = p_student_account_id AND hold_type = p_hold_type AND hold_status = 'ACTIVE';
    IF v_id IS NOT NULL THEN RETURN v_id; END IF; -- idempotent: one active hold per type
    INSERT INTO student_financial_hold (student_account_id, hold_type, hold_reason, placed_by) VALUES (p_student_account_id, p_hold_type, v_reason, sims_private.current_user_id()) RETURNING financial_hold_id INTO v_id;
    UPDATE student_financial_account SET account_status = 'ON_HOLD', updated_at = now() WHERE student_account_id = p_student_account_id AND account_status = 'ACTIVE';
    PERFORM sims_private.fin_audit('PLACE_HOLD', 'student_financial_hold', v_id, NULL, jsonb_build_object('type', p_hold_type, 'reason', v_reason));
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.fin_hold_release(p_hold_id bigint, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE h record; v_reason text := NULLIF(btrim(p_reason), '');
BEGIN
    SELECT financial_hold_id, student_account_id, hold_status INTO h FROM student_financial_hold WHERE financial_hold_id = p_hold_id FOR UPDATE;
    IF h.financial_hold_id IS NULL THEN RAISE EXCEPTION 'Not authorised (FEES.FEE_ASSESSMENT.UPDATE) or unknown hold' USING ERRCODE = '42501'; END IF;
    PERFORM sims_private.fin_authorize(h.student_account_id, 'FEE_ASSESSMENT', 'UPDATE');
    IF v_reason IS NULL OR length(v_reason) > 500 THEN RAISE EXCEPTION 'A reason is required (at most 500 characters)' USING ERRCODE = '22023'; END IF;
    IF h.hold_status <> 'ACTIVE' THEN RETURN; END IF; -- idempotent replay
    UPDATE student_financial_hold SET hold_status = 'RELEASED', released_at = now(), released_by = sims_private.current_user_id(), release_reason = v_reason WHERE financial_hold_id = p_hold_id;
    IF NOT EXISTS (SELECT 1 FROM student_financial_hold WHERE student_account_id = h.student_account_id AND hold_status = 'ACTIVE') THEN
        UPDATE student_financial_account SET account_status = 'ACTIVE', updated_at = now() WHERE student_account_id = h.student_account_id AND account_status = 'ON_HOLD';
    END IF;
    PERFORM sims_private.fin_audit('RELEASE_HOLD', 'student_financial_hold', p_hold_id, jsonb_build_object('status', 'ACTIVE'), jsonb_build_object('status', 'RELEASED', 'reason', v_reason));
END $function$;

CREATE OR REPLACE FUNCTION public.fin_instalment_cancel(p_assessment_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    PERFORM sims_private.fin_authorize_student(sims_private.fin_assessment_student(p_assessment_id), 'FEE_ASSESSMENT', 'UPDATE');
    UPDATE student_installment_schedule SET installment_status = 'CANCELLED' WHERE fee_assessment_id = p_assessment_id AND installment_status <> 'CANCELLED';
    IF NOT FOUND THEN RAISE EXCEPTION 'The assessment has no active instalment schedule' USING ERRCODE = '45000'; END IF;
    PERFORM sims_private.fin_audit('INSTALMENTS_CANCELLED', 'student_fee_assessment', p_assessment_id, NULL, NULL);
END $function$;

CREATE OR REPLACE FUNCTION public.fin_instalment_refresh(p_assessment_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_stu bigint; v_paid numeric; s record; v_part numeric;
BEGIN
    v_stu := sims_private.fin_assessment_student(p_assessment_id);
    PERFORM sims_private.fin_authorize_student(v_stu, 'FEE_ASSESSMENT', 'UPDATE');
    SELECT amount_paid INTO v_paid FROM student_fee_assessment WHERE fee_assessment_id = p_assessment_id;
    FOR s IN SELECT student_installment_id, installment_amount, due_date, installment_status FROM student_installment_schedule
              WHERE fee_assessment_id = p_assessment_id AND installment_status NOT IN ('CANCELLED', 'WAIVED') ORDER BY installment_number FOR UPDATE LOOP
        v_part := least(v_paid, s.installment_amount); v_paid := v_paid - v_part;
        UPDATE student_installment_schedule SET amount_paid = v_part, balance_amount = installment_amount - v_part,
               installment_status = CASE WHEN v_part >= installment_amount THEN 'PAID' WHEN due_date < current_date THEN 'OVERDUE' WHEN v_part > 0 THEN 'PARTIALLY_PAID' ELSE 'PENDING' END
         WHERE student_installment_id = s.student_installment_id;
    END LOOP;
END $function$;

CREATE OR REPLACE FUNCTION public.fin_issue_receipt(p_payment_transaction_id bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE p record; v_id bigint;
BEGIN
    SELECT payment_transaction_id, student_account_id, amount, payment_status INTO p FROM payment_transaction WHERE payment_transaction_id = p_payment_transaction_id FOR UPDATE;
    IF p.payment_transaction_id IS NULL OR p.student_account_id IS NULL THEN RAISE EXCEPTION 'Not authorised (FEES.FEE_PAYMENT.CREATE) or unknown payment' USING ERRCODE = '42501'; END IF;
    PERFORM sims_private.fin_authorize(p.student_account_id, 'FEE_PAYMENT', 'CREATE');
    IF p.payment_status NOT IN ('SUCCESS', 'PARTIALLY_REFUNDED') THEN RAISE EXCEPTION 'A receipt can only be issued for a successful payment' USING ERRCODE = '45000'; END IF;
    SELECT fee_receipt_id INTO v_id FROM fee_receipt WHERE payment_transaction_id = p.payment_transaction_id AND receipt_status = 'ISSUED';
    IF v_id IS NOT NULL THEN RETURN v_id; END IF; -- idempotent
    INSERT INTO fee_receipt (receipt_number, payment_transaction_id, receipt_date, receipt_amount, issued_by)
    VALUES (sims_private.fin_next_receipt_number(), p.payment_transaction_id, now(), p.amount, sims_private.current_user_id()) RETURNING fee_receipt_id INTO v_id;
    PERFORM sims_private.fin_audit('ISSUE_RECEIPT', 'fee_receipt', v_id, NULL, jsonb_build_object('payment_transaction_id', p.payment_transaction_id, 'amount', p.amount));
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.fin_open_account(p_student_number text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_student bigint; v_number text; v_id bigint;
BEGIN
    IF p_student_number IS NULL OR btrim(p_student_number) = '' THEN RAISE EXCEPTION 'student_number is required' USING ERRCODE = '22023'; END IF;
    SELECT s.student_id, s.student_number::text INTO v_student, v_number FROM student s WHERE s.student_number = btrim(p_student_number);
    -- Same error for "unknown" and "out of scope": no student enumeration.
    IF v_student IS NULL OR NOT sims_private.can_student(ARRAY['FEES.FEE_ASSESSMENT.CREATE']::text[], v_student, true) THEN
        RAISE EXCEPTION 'Not authorised (FEES.FEE_ASSESSMENT.CREATE) or unknown student' USING ERRCODE = '42501';
    END IF;
    SELECT student_account_id INTO v_id FROM student_financial_account WHERE account_number = 'ACC-' || v_number;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;
    INSERT INTO student_financial_account (student_id, account_number) VALUES (v_student, 'ACC-' || v_number) RETURNING student_account_id INTO v_id;
    PERFORM sims_private.fin_audit('ACCOUNT_OPENED', 'student_financial_account', v_id, NULL, jsonb_build_object('student_id', v_student, 'account_number', 'ACC-' || v_number));
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.fin_penalty_waive(p_penalty_id bigint, p_amount numeric, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE p record; it record;
BEGIN
    SELECT * INTO p FROM student_fee_penalty WHERE fee_penalty_id = p_penalty_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Not authorised (FEES.FEE_REFUND.APPROVE) or unknown penalty' USING ERRCODE = '42501'; END IF;
    PERFORM sims_private.fin_authorize(p.student_account_id, 'FEE_REFUND', 'APPROVE');
    IF p_reason IS NULL OR btrim(p_reason) = '' THEN RAISE EXCEPTION 'A reason is required' USING ERRCODE = '22023'; END IF;
    PERFORM sims_private.fin_check_amount(p_amount, 'amount');
    IF p.penalty_status NOT IN ('ASSESSED', 'PARTIALLY_PAID') THEN RAISE EXCEPTION 'The penalty is %', p.penalty_status USING ERRCODE = '45000'; END IF;
    IF p_amount > p.penalty_amount - p.waived_amount THEN RAISE EXCEPTION 'The amount exceeds what is left of the penalty' USING ERRCODE = '45000'; END IF;
    SELECT * INTO it FROM sims_private.fin_editable_item(p.assessment_item_id);
    IF p_amount > it.balance_amount THEN RAISE EXCEPTION 'The amount exceeds the unpaid balance (%)', it.balance_amount USING ERRCODE = '45000'; END IF;
    UPDATE student_fee_assessment_item SET adjustment_amount = adjustment_amount - p_amount, net_amount = net_amount - p_amount, balance_amount = balance_amount - p_amount WHERE assessment_item_id = p.assessment_item_id;
    PERFORM sims_private.fin_refresh_status(p.assessment_item_id);
    UPDATE student_fee_penalty SET waived_amount = waived_amount + p_amount, net_penalty_amount = net_penalty_amount - p_amount,
           penalty_status = CASE WHEN net_penalty_amount - p_amount = 0 THEN 'WAIVED' ELSE penalty_status END, approved_by = sims_private.current_user_id() WHERE fee_penalty_id = p_penalty_id;
    PERFORM sims_private.fin_audit('PENALTY_WAIVED', 'student_fee_penalty', p_penalty_id, NULL, jsonb_build_object('amount', p_amount, 'reason', p_reason));
END $function$;

CREATE OR REPLACE FUNCTION public.fin_process_refund(p_refund_transaction_number text, p_refund_request_id bigint, p_refund_mode_id integer, p_amount numeric, p_bank_reference text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_req record; v_mode record; v_ex record; v_id bigint; v_refunded numeric; v_pay_amount numeric; v_pay_total numeric;
BEGIN
    SELECT student_account_id INTO v_req FROM refund_request WHERE refund_request_id = p_refund_request_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Not authorised (FEES.FEE_REFUND.UPDATE) or unknown request' USING ERRCODE = '42501'; END IF;
    PERFORM sims_private.fin_authorize(v_req.student_account_id, 'FEE_REFUND', 'UPDATE');
    IF p_refund_transaction_number IS NULL OR btrim(p_refund_transaction_number) = '' THEN
        RAISE EXCEPTION 'refund transaction number is required (idempotency key)' USING ERRCODE = '22023';
    END IF;
    PERFORM sims_private.fin_check_amount(p_amount, 'amount');
    SELECT payment_transaction_id, approved_amount, request_status INTO v_req FROM refund_request WHERE refund_request_id = p_refund_request_id FOR UPDATE;
    IF v_req.payment_transaction_id IS NOT NULL THEN
        PERFORM 1 FROM payment_transaction WHERE payment_transaction_id = v_req.payment_transaction_id FOR UPDATE;
    END IF;

    SELECT fee_refund_id, refund_request_id, refund_amount INTO v_ex FROM fee_refund WHERE refund_transaction_number = p_refund_transaction_number;
    IF FOUND THEN
        IF v_ex.refund_request_id = p_refund_request_id AND v_ex.refund_amount = p_amount THEN RETURN v_ex.fee_refund_id; END IF;  -- idempotent replay
        RAISE EXCEPTION 'refund transaction number already used with different details' USING ERRCODE = '23505';
    END IF;
    IF v_req.request_status NOT IN ('APPROVED', 'PROCESSED') OR v_req.approved_amount IS NULL THEN
        RAISE EXCEPTION 'Refund request must be approved first' USING ERRCODE = '45000';
    END IF;
    SELECT requires_reference, is_active INTO v_mode FROM payment_mode WHERE payment_mode_id = p_refund_mode_id;
    IF NOT FOUND OR NOT v_mode.is_active THEN RAISE EXCEPTION 'Unknown or inactive refund mode' USING ERRCODE = '22023'; END IF;
    IF v_mode.requires_reference AND (p_bank_reference IS NULL OR btrim(p_bank_reference) = '') THEN
        RAISE EXCEPTION 'This refund mode requires a reference number' USING ERRCODE = '22023';
    END IF;

    INSERT INTO fee_refund (refund_request_id, refund_transaction_number, refund_date, refund_amount, refund_mode_id, bank_reference_number, processed_by, refund_status)
    VALUES (p_refund_request_id, p_refund_transaction_number, now(), p_amount, p_refund_mode_id, p_bank_reference, sims_private.current_user_id(), 'SUCCESS')
    RETURNING fee_refund_id INTO v_id;  -- approval and cumulative limits enforced by trg_fee_refund_bi

    SELECT COALESCE(SUM(refund_amount), 0) INTO v_refunded FROM fee_refund WHERE refund_request_id = p_refund_request_id AND refund_status = 'SUCCESS';
    IF v_refunded = v_req.approved_amount THEN
        UPDATE refund_request SET request_status = 'PROCESSED' WHERE refund_request_id = p_refund_request_id;
    END IF;
    IF v_req.payment_transaction_id IS NOT NULL THEN
        SELECT amount INTO v_pay_amount FROM payment_transaction WHERE payment_transaction_id = v_req.payment_transaction_id;
        v_pay_total := sims_private.fin_refunded_on_payment(v_req.payment_transaction_id);
        UPDATE payment_transaction SET payment_status = CASE WHEN v_pay_total >= v_pay_amount THEN 'REFUNDED' ELSE 'PARTIALLY_REFUNDED' END
         WHERE payment_transaction_id = v_req.payment_transaction_id AND payment_status IN ('SUCCESS', 'PARTIALLY_REFUNDED');
    END IF;
    PERFORM sims_private.fin_audit('REFUND_PROCESSED', 'fee_refund', v_id, NULL, jsonb_build_object('amount', p_amount, 'refund_request_id', p_refund_request_id));
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.fin_record_payment(p_transaction_number text, p_student_account_id bigint, p_payment_mode_id integer, p_amount numeric, p_bank_reference text DEFAULT NULL::text, p_payer_name text DEFAULT NULL::text, p_remarks text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_id bigint; v_mode record; v_ex record; v_acct_status text;
BEGIN
    PERFORM sims_private.fin_authorize(p_student_account_id, 'FEE_PAYMENT', 'CREATE');
    IF p_transaction_number IS NULL OR btrim(p_transaction_number) = '' THEN
        RAISE EXCEPTION 'transaction_number is required (idempotency key)' USING ERRCODE = '22023';
    END IF;
    PERFORM sims_private.fin_check_amount(p_amount, 'amount');
    SELECT account_status INTO v_acct_status FROM student_financial_account WHERE student_account_id = p_student_account_id;
    IF v_acct_status = 'CLOSED' THEN RAISE EXCEPTION 'Student account is CLOSED' USING ERRCODE = '45000'; END IF;
    SELECT requires_reference, is_online, is_active INTO v_mode FROM payment_mode WHERE payment_mode_id = p_payment_mode_id;
    IF NOT FOUND OR NOT v_mode.is_active THEN RAISE EXCEPTION 'Unknown or inactive payment mode' USING ERRCODE = '22023'; END IF;
    IF v_mode.is_online THEN
        RAISE EXCEPTION 'Online payments are confirmed by the payment-gateway integration, not recorded manually' USING ERRCODE = '45000';
    END IF;
    IF v_mode.requires_reference AND (p_bank_reference IS NULL OR btrim(p_bank_reference) = '') THEN
        RAISE EXCEPTION 'This payment mode requires a reference number' USING ERRCODE = '22023';
    END IF;

    INSERT INTO payment_transaction (transaction_number, student_account_id, transaction_date, payment_mode_id, amount, payment_status,
                                     bank_reference_number, payer_name, received_by, remarks)
    VALUES (p_transaction_number, p_student_account_id, now(), p_payment_mode_id, p_amount, 'SUCCESS',
            p_bank_reference, p_payer_name, sims_private.current_user_id(), p_remarks)
    ON CONFLICT (transaction_number) DO NOTHING
    RETURNING payment_transaction_id INTO v_id;
    IF v_id IS NULL THEN
        SELECT payment_transaction_id, student_account_id, payment_mode_id, amount INTO v_ex FROM payment_transaction WHERE transaction_number = p_transaction_number;
        IF v_ex.student_account_id IS NOT DISTINCT FROM p_student_account_id AND v_ex.payment_mode_id = p_payment_mode_id AND v_ex.amount = p_amount THEN
            RETURN v_ex.payment_transaction_id;  -- idempotent replay
        END IF;
        RAISE EXCEPTION 'transaction_number already used with different details' USING ERRCODE = '23505';
    END IF;
    PERFORM sims_private.fin_audit('PAYMENT_RECORDED', 'payment_transaction', v_id, NULL,
        jsonb_build_object('transaction_number', p_transaction_number, 'amount', p_amount, 'payment_mode_id', p_payment_mode_id));
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.fin_request_refund(p_request_number text, p_student_account_id bigint, p_payment_transaction_id bigint, p_amount numeric, p_reason text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_pay record; v_id bigint; v_ex record;
BEGIN
    PERFORM sims_private.fin_authorize(p_student_account_id, 'FEE_REFUND', 'CREATE');
    IF p_request_number IS NULL OR btrim(p_request_number) = '' OR p_reason IS NULL OR btrim(p_reason) = '' THEN
        RAISE EXCEPTION 'request number and reason are required' USING ERRCODE = '22023';
    END IF;
    PERFORM sims_private.fin_check_amount(p_amount, 'amount');
    SELECT payment_transaction_id, student_account_id, amount, payment_status INTO v_pay FROM payment_transaction
     WHERE payment_transaction_id = p_payment_transaction_id FOR UPDATE;
    IF NOT FOUND OR v_pay.student_account_id IS DISTINCT FROM p_student_account_id THEN
        RAISE EXCEPTION 'Payment does not belong to this account' USING ERRCODE = '45000';
    END IF;
    IF v_pay.payment_status NOT IN ('SUCCESS', 'PARTIALLY_REFUNDED') THEN
        RAISE EXCEPTION 'Only successful payments can be refunded (status %)', v_pay.payment_status USING ERRCODE = '45000';
    END IF;
    SELECT refund_request_id, student_account_id, payment_transaction_id, requested_amount INTO v_ex FROM refund_request WHERE refund_request_number = p_request_number;
    IF FOUND THEN
        IF v_ex.student_account_id = p_student_account_id AND v_ex.payment_transaction_id = p_payment_transaction_id AND v_ex.requested_amount = p_amount THEN
            RETURN v_ex.refund_request_id;  -- idempotent replay
        END IF;
        RAISE EXCEPTION 'request number already used with different details' USING ERRCODE = '23505';
    END IF;
    IF p_amount > v_pay.amount - sims_private.fin_refunded_on_payment(p_payment_transaction_id) THEN
        RAISE EXCEPTION 'Requested amount exceeds the refundable balance of the payment' USING ERRCODE = '45000';
    END IF;
    INSERT INTO refund_request (refund_request_number, student_account_id, payment_transaction_id, request_date, refund_reason, requested_amount, request_status)
    VALUES (p_request_number, p_student_account_id, p_payment_transaction_id, current_date, p_reason, p_amount, 'SUBMITTED')
    RETURNING refund_request_id INTO v_id;
    PERFORM sims_private.fin_audit('REFUND_REQUESTED', 'refund_request', v_id, NULL, jsonb_build_object('amount', p_amount, 'payment_transaction_id', p_payment_transaction_id));
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.fin_structure_decide(p_id bigint, p_approve boolean, p_remarks text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE s public.fee_structure%ROWTYPE; v_rem text := NULLIF(btrim(p_remarks), '');
BEGIN
    s := sims_private.fs_load(p_id, 'APPROVE');
    IF s.approval_status <> 'SUBMITTED' THEN RAISE EXCEPTION 'Only a submitted fee structure can be decided (status %)', s.approval_status USING ERRCODE = '45000'; END IF;
    IF EXISTS (SELECT 1 FROM fee_activity_audit WHERE entity_name = 'fee_structure' AND entity_id = p_id AND action_code = 'STRUCTURE_SUBMITTED' AND user_id = sims_private.current_user_id()) THEN
        RAISE EXCEPTION 'You cannot decide a fee structure that you submitted yourself' USING ERRCODE = '45000';
    END IF;
    IF NOT p_approve AND v_rem IS NULL THEN RAISE EXCEPTION 'A reason is required to reject' USING ERRCODE = '22023'; END IF;
    IF length(COALESCE(v_rem, '')) > 500 THEN RAISE EXCEPTION 'Remarks are limited to 500 characters' USING ERRCODE = '22023'; END IF;
    IF p_approve THEN
        UPDATE fee_structure SET approval_status = 'SUPERSEDED'
         WHERE fee_structure_id <> p_id AND approval_status = 'APPROVED' AND institution_id = s.institution_id AND campus_id IS NOT DISTINCT FROM s.campus_id AND programme_id IS NOT DISTINCT FROM s.programme_id
           AND specialization_id IS NOT DISTINCT FROM s.specialization_id AND academic_year_id = s.academic_year_id AND admission_category_id IS NOT DISTINCT FROM s.admission_category_id;
        UPDATE fee_structure SET approval_status = 'APPROVED', approved_by = sims_private.current_user_id(), approved_at = now(), remarks = COALESCE(v_rem, remarks) WHERE fee_structure_id = p_id;
    ELSE
        UPDATE fee_structure SET approval_status = 'REJECTED', remarks = v_rem WHERE fee_structure_id = p_id;
    END IF;
    PERFORM sims_private.fin_audit(CASE WHEN p_approve THEN 'STRUCTURE_APPROVED' ELSE 'STRUCTURE_REJECTED' END, 'fee_structure', p_id, NULL, jsonb_build_object('remarks', v_rem));
END $function$;

CREATE OR REPLACE FUNCTION public.fin_structure_delete(p_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE s public.fee_structure%ROWTYPE;
BEGIN
    s := sims_private.fs_load(p_id, 'DELETE');
    IF s.approval_status NOT IN ('DRAFT', 'REJECTED') THEN RAISE EXCEPTION 'A % fee structure cannot be deleted', s.approval_status USING ERRCODE = '45000'; END IF;
    IF EXISTS (SELECT 1 FROM student_fee_assessment WHERE fee_structure_id = p_id) THEN RAISE EXCEPTION 'Assessments already use this fee structure' USING ERRCODE = '45000'; END IF;
    DELETE FROM fee_structure_item WHERE fee_structure_id = p_id;
    DELETE FROM fee_structure WHERE fee_structure_id = p_id;
    PERFORM sims_private.fin_audit('STRUCTURE_DELETED', 'fee_structure', p_id, NULL, jsonb_build_object('code', s.structure_code));
END $function$;

CREATE OR REPLACE FUNCTION public.fin_structure_item_delete(p_structure_id bigint, p_item_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE s public.fee_structure%ROWTYPE;
BEGIN
    s := sims_private.fs_load(p_structure_id, 'UPDATE');
    IF s.approval_status NOT IN ('DRAFT', 'REJECTED') THEN RAISE EXCEPTION 'A % fee structure cannot be edited', s.approval_status USING ERRCODE = '45000'; END IF;
    BEGIN
        DELETE FROM fee_structure_item WHERE fee_structure_item_id = p_item_id AND fee_structure_id = p_structure_id;
    EXCEPTION WHEN foreign_key_violation THEN RAISE EXCEPTION 'Assessments already use this item' USING ERRCODE = '45000';
    END;
    IF NOT FOUND THEN RAISE EXCEPTION 'Unknown item' USING ERRCODE = '22023'; END IF;
    PERFORM sims_private.fin_audit('STRUCTURE_ITEM_DELETED', 'fee_structure_item', p_item_id, NULL, jsonb_build_object('structure_id', p_structure_id));
END $function$;

CREATE OR REPLACE FUNCTION public.fin_structure_item_save(p_structure_id bigint, p_item_id bigint, p jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    s public.fee_structure%ROWTYPE; v_id bigint; v_amt numeric := NULLIF(p ->> 'amount', '')::numeric;
    v_type integer := NULLIF(p ->> 'fee_type_id', '')::integer; v_sem integer := NULLIF(p ->> 'semester_id', '')::integer; v_term integer := NULLIF(p ->> 'academic_term_id', '')::integer;
    v_due date := NULLIF(p ->> 'due_date', '')::date; v_days integer := NULLIF(p ->> 'due_days_from_registration', '')::integer; v_late integer := NULLIF(p ->> 'late_fee_rule_id', '')::integer;
    v_inst boolean := COALESCE((p ->> 'installment_allowed')::boolean, false); v_waive boolean := COALESCE((p ->> 'waiver_allowed')::boolean, false);
    v_order integer := COALESCE(NULLIF(p ->> 'display_order', '')::integer, 0); v_rem text := NULLIF(btrim(p ->> 'remarks'), '');
BEGIN
    s := sims_private.fs_load(p_structure_id, 'UPDATE');
    IF s.approval_status NOT IN ('DRAFT', 'REJECTED') THEN RAISE EXCEPTION 'A % fee structure cannot be edited', s.approval_status USING ERRCODE = '45000'; END IF;
    IF v_type IS NULL OR NOT EXISTS (SELECT 1 FROM fee_type WHERE fee_type_id = v_type) THEN RAISE EXCEPTION 'Choose a fee type' USING ERRCODE = '22023'; END IF;
    PERFORM sims_private.fin_check_amount(v_amt, 'amount');
    IF v_sem IS NOT NULL AND NOT EXISTS (SELECT 1 FROM semester WHERE semester_id = v_sem) THEN RAISE EXCEPTION 'Unknown semester' USING ERRCODE = '22023'; END IF;
    IF v_term IS NOT NULL AND NOT EXISTS (SELECT 1 FROM academic_term WHERE academic_term_id = v_term) THEN RAISE EXCEPTION 'Unknown academic term' USING ERRCODE = '22023'; END IF;
    IF v_late IS NOT NULL AND NOT EXISTS (SELECT 1 FROM late_fee_rule WHERE late_fee_rule_id = v_late) THEN RAISE EXCEPTION 'Unknown late-fee rule' USING ERRCODE = '22023'; END IF;
    IF v_days IS NOT NULL AND (v_days < 0 OR v_days > 3650) THEN RAISE EXCEPTION 'Due days must be between 0 and 3650' USING ERRCODE = '22023'; END IF;
    IF length(COALESCE(v_rem, '')) > 500 THEN RAISE EXCEPTION 'Remarks are limited to 500 characters' USING ERRCODE = '22023'; END IF;
    BEGIN
        IF p_item_id IS NULL THEN
            INSERT INTO fee_structure_item (fee_structure_id, fee_type_id, semester_id, academic_term_id, amount, due_date, due_days_from_registration, installment_allowed, waiver_allowed, late_fee_rule_id, display_order, remarks)
            VALUES (p_structure_id, v_type, v_sem, v_term, v_amt, v_due, v_days, v_inst, v_waive, v_late, v_order, v_rem) RETURNING fee_structure_item_id INTO v_id;
        ELSE
            UPDATE fee_structure_item SET fee_type_id = v_type, semester_id = v_sem, academic_term_id = v_term, amount = v_amt, due_date = v_due, due_days_from_registration = v_days, installment_allowed = v_inst,
                   waiver_allowed = v_waive, late_fee_rule_id = v_late, display_order = v_order, remarks = v_rem WHERE fee_structure_item_id = p_item_id AND fee_structure_id = p_structure_id RETURNING fee_structure_item_id INTO v_id;
            IF v_id IS NULL THEN RAISE EXCEPTION 'Unknown item' USING ERRCODE = '22023'; END IF;
        END IF;
    EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'That fee type already has an item for the same semester and term' USING ERRCODE = '23505';
    END;
    UPDATE fee_structure SET approval_status = 'DRAFT' WHERE fee_structure_id = p_structure_id AND approval_status = 'REJECTED';
    PERFORM sims_private.fin_audit('STRUCTURE_ITEM_SAVED', 'fee_structure_item', v_id, NULL, jsonb_build_object('structure_id', p_structure_id, 'amount', v_amt));
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.fin_structure_new_version(p_id bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE s public.fee_structure%ROWTYPE; v_new bigint; v_ver integer; v_base text;
BEGIN
    s := sims_private.fs_load(p_id, 'CREATE');
    IF s.approval_status NOT IN ('APPROVED', 'SUPERSEDED') THEN RAISE EXCEPTION 'Only an approved or superseded fee structure can be versioned (status %)', s.approval_status USING ERRCODE = '45000'; END IF;
    v_ver := s.version_number + 1;
    v_base := regexp_replace(s.structure_code, '-V[0-9]+$', '');
    WHILE EXISTS (SELECT 1 FROM fee_structure WHERE structure_code = left(v_base, 45) || '-V' || v_ver) LOOP v_ver := v_ver + 1; END LOOP;
    INSERT INTO fee_structure (structure_code, structure_name, institution_id, campus_id, programme_id, specialization_id, academic_year_id, admission_category_id, version_number, effective_from, effective_to, approval_status, remarks)
    VALUES (left(v_base, 45) || '-V' || v_ver, s.structure_name, s.institution_id, s.campus_id, s.programme_id, s.specialization_id, s.academic_year_id, s.admission_category_id, v_ver, s.effective_from, s.effective_to, 'DRAFT', 'Copied from ' || s.structure_code)
    RETURNING fee_structure_id INTO v_new;
    INSERT INTO fee_structure_item (fee_structure_id, fee_type_id, semester_id, academic_term_id, amount, due_date, due_days_from_registration, installment_allowed, waiver_allowed, late_fee_rule_id, display_order, remarks)
    SELECT v_new, fee_type_id, semester_id, academic_term_id, amount, due_date, due_days_from_registration, installment_allowed, waiver_allowed, late_fee_rule_id, display_order, remarks FROM fee_structure_item WHERE fee_structure_id = p_id;
    PERFORM sims_private.fin_audit('STRUCTURE_VERSIONED', 'fee_structure', v_new, NULL, jsonb_build_object('from', p_id));
    RETURN v_new;
END $function$;

CREATE OR REPLACE FUNCTION public.fin_structure_save(p_id bigint, p jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    s public.fee_structure%ROWTYPE; v_id bigint;
    v_code text := NULLIF(btrim(p ->> 'structure_code'), ''); v_name text := NULLIF(btrim(p ->> 'structure_name'), '');
    v_inst integer := NULLIF(p ->> 'institution_id', '')::integer; v_campus integer := NULLIF(p ->> 'campus_id', '')::integer; v_prog integer := NULLIF(p ->> 'programme_id', '')::integer;
    v_year integer := NULLIF(p ->> 'academic_year_id', '')::integer; v_cat integer := NULLIF(p ->> 'admission_category_id', '')::integer;
    v_from date := NULLIF(p ->> 'effective_from', '')::date; v_to date := NULLIF(p ->> 'effective_to', '')::date; v_rem text := NULLIF(btrim(p ->> 'remarks'), '');
BEGIN
    IF p IS NULL OR jsonb_typeof(p) <> 'object' THEN RAISE EXCEPTION 'p must be an object' USING ERRCODE = '22023'; END IF;
    IF p_id IS NOT NULL THEN
        s := sims_private.fs_load(p_id, 'UPDATE');
        IF s.approval_status NOT IN ('DRAFT', 'REJECTED') THEN RAISE EXCEPTION 'A % fee structure cannot be edited', s.approval_status USING ERRCODE = '45000'; END IF;
        v_code := COALESCE(v_code, s.structure_code);
    END IF;
    IF v_code IS NULL OR length(v_code) > 50 OR v_name IS NULL OR length(v_name) > 200 THEN RAISE EXCEPTION 'A code (at most 50 characters) and a name (at most 200) are required' USING ERRCODE = '22023'; END IF;
    IF v_inst IS NULL OR NOT EXISTS (SELECT 1 FROM institution WHERE institution_id = v_inst) THEN RAISE EXCEPTION 'Choose an institution' USING ERRCODE = '22023'; END IF;
    IF v_campus IS NOT NULL AND NOT EXISTS (SELECT 1 FROM campus WHERE campus_id = v_campus AND institution_id = v_inst) THEN RAISE EXCEPTION 'The campus does not belong to that institution' USING ERRCODE = '22023'; END IF;
    IF v_prog IS NOT NULL AND NOT EXISTS (SELECT 1 FROM programme pr JOIN department d ON d.department_id = pr.department_id JOIN campus c ON c.campus_id = d.campus_id WHERE pr.programme_id = v_prog AND c.institution_id = v_inst) THEN
        RAISE EXCEPTION 'The programme does not belong to that institution' USING ERRCODE = '22023';
    END IF;
    IF v_year IS NULL OR NOT EXISTS (SELECT 1 FROM academic_year WHERE academic_year_id = v_year) THEN RAISE EXCEPTION 'Choose an academic year' USING ERRCODE = '22023'; END IF;
    IF v_cat IS NOT NULL AND NOT EXISTS (SELECT 1 FROM admission_category WHERE admission_category_id = v_cat) THEN RAISE EXCEPTION 'Unknown admission category' USING ERRCODE = '22023'; END IF;
    IF v_from IS NULL THEN RAISE EXCEPTION 'The effective-from date is required' USING ERRCODE = '22023'; END IF;
    IF v_to IS NOT NULL AND v_to < v_from THEN RAISE EXCEPTION 'The effective-to date cannot be before the start' USING ERRCODE = '22023'; END IF;
    IF length(COALESCE(v_rem, '')) > 500 THEN RAISE EXCEPTION 'Remarks are limited to 500 characters' USING ERRCODE = '22023'; END IF;
    IF p_id IS NULL THEN
        IF NOT COALESCE(sims_private.fs_can(v_inst, v_prog, 'CREATE'), false) THEN RAISE EXCEPTION 'Not authorised (FEES.FEE_STRUCTURE.CREATE) for that scope' USING ERRCODE = '42501'; END IF;
        BEGIN
            INSERT INTO fee_structure (structure_code, structure_name, institution_id, campus_id, programme_id, academic_year_id, admission_category_id, effective_from, effective_to, approval_status, remarks)
            VALUES (v_code, v_name, v_inst, v_campus, v_prog, v_year, v_cat, v_from, v_to, 'DRAFT', v_rem) RETURNING fee_structure_id INTO v_id;
        EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'That structure code is already used' USING ERRCODE = '23505';
        END;
        PERFORM sims_private.fin_audit('STRUCTURE_CREATED', 'fee_structure', v_id, NULL, jsonb_build_object('code', v_code));
        RETURN v_id;
    END IF;
    IF (v_inst, v_prog) IS DISTINCT FROM (s.institution_id, s.programme_id) AND NOT COALESCE(sims_private.fs_can(v_inst, v_prog, 'CREATE'), false) THEN RAISE EXCEPTION 'Not authorised (FEES.FEE_STRUCTURE.CREATE) for that scope' USING ERRCODE = '42501'; END IF;
    BEGIN
        UPDATE fee_structure SET structure_code = v_code, structure_name = v_name, institution_id = v_inst, campus_id = v_campus, programme_id = v_prog, specialization_id = NULL, academic_year_id = v_year,
               admission_category_id = v_cat, effective_from = v_from, effective_to = v_to, remarks = v_rem, approval_status = 'DRAFT' WHERE fee_structure_id = p_id;
    EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'That structure code is already used' USING ERRCODE = '23505';
    END;
    PERFORM sims_private.fin_audit('STRUCTURE_UPDATED', 'fee_structure', p_id, NULL, jsonb_build_object('code', v_code));
    RETURN p_id;
END $function$;

CREATE OR REPLACE FUNCTION public.fin_structure_submit(p_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE s public.fee_structure%ROWTYPE;
BEGIN
    s := sims_private.fs_load(p_id, 'UPDATE');
    IF s.approval_status = 'SUBMITTED' THEN RETURN; END IF;
    IF s.approval_status NOT IN ('DRAFT', 'REJECTED') THEN RAISE EXCEPTION 'A % fee structure cannot be submitted', s.approval_status USING ERRCODE = '45000'; END IF;
    IF NOT EXISTS (SELECT 1 FROM fee_structure_item WHERE fee_structure_id = p_id) THEN RAISE EXCEPTION 'Add at least one item before submitting' USING ERRCODE = '45000'; END IF;
    UPDATE fee_structure SET approval_status = 'SUBMITTED' WHERE fee_structure_id = p_id;
    PERFORM sims_private.fin_audit('STRUCTURE_SUBMITTED', 'fee_structure', p_id, NULL, NULL);
END $function$;

CREATE OR REPLACE FUNCTION public.grievance_act(p_grievance_id bigint, p_action_type text, p_notes text DEFAULT NULL::text, p_new_status text DEFAULT NULL::text, p_resolution text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v record; v_notes text := NULLIF(btrim(p_notes), ''); v_res text := NULLIF(btrim(p_resolution), '');
BEGIN
    SELECT grievance_id, student_id, status, resolution INTO v FROM grievance WHERE grievance_id = p_grievance_id FOR UPDATE;
    IF v IS NULL OR NOT sims_private.can_student(ARRAY['GRIEVANCE.ALL.UPDATE']::text[], v.student_id, true) THEN
        RAISE EXCEPTION 'Not authorised (GRIEVANCE.ALL.UPDATE) or unknown grievance' USING ERRCODE = '42501';
    END IF;
    IF p_action_type NOT IN ('COMMENT', 'INTERNAL_NOTE', 'STATUS_CHANGE') THEN RAISE EXCEPTION 'Invalid action type' USING ERRCODE = '22023'; END IF;
    IF length(COALESCE(v_notes, '')) > 2000 OR length(COALESCE(v_res, '')) > 5000 THEN RAISE EXCEPTION 'Text is too long' USING ERRCODE = '22023'; END IF;
    IF p_action_type <> 'STATUS_CHANGE' THEN
        IF v_notes IS NULL THEN RAISE EXCEPTION 'A note is required' USING ERRCODE = '22023'; END IF;
        IF p_new_status IS NOT NULL THEN RAISE EXCEPTION 'Only a STATUS_CHANGE action changes the status' USING ERRCODE = '22023'; END IF;
        IF v.status = 'CLOSED' THEN RAISE EXCEPTION 'The grievance is CLOSED' USING ERRCODE = '45000'; END IF;
        INSERT INTO grievance_action (grievance_id, action_type, action_notes) VALUES (p_grievance_id, p_action_type, v_notes);
        RETURN;
    END IF;
    IF p_new_status IS NULL THEN RAISE EXCEPTION 'A new status is required' USING ERRCODE = '22023'; END IF;
    IF v.status = p_new_status THEN RETURN; END IF; -- idempotent replay
    IF NOT sims_private.grievance_transition_ok(v.status, p_new_status) THEN RAISE EXCEPTION 'A % grievance cannot become %', v.status, p_new_status USING ERRCODE = '45000'; END IF;
    IF p_new_status IN ('RESOLVED', 'REJECTED') AND v_res IS NULL THEN RAISE EXCEPTION 'A resolution text is required' USING ERRCODE = '22023'; END IF;
    UPDATE grievance SET status = p_new_status,
        resolved_at = CASE WHEN p_new_status IN ('RESOLVED', 'REJECTED') THEN now() WHEN p_new_status = 'UNDER_REVIEW' THEN NULL ELSE resolved_at END,
        resolution = CASE WHEN p_new_status IN ('RESOLVED', 'REJECTED') THEN v_res ELSE resolution END WHERE grievance_id = p_grievance_id;
    INSERT INTO grievance_action (grievance_id, action_type, action_notes, new_status) VALUES (p_grievance_id, 'STATUS_CHANGE', v_notes, p_new_status);
END $function$;

CREATE OR REPLACE FUNCTION public.grievance_student_respond(p_grievance_id bigint, p_response text, p_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v record; v_to text;
BEGIN
    SELECT grievance_id, student_id, status INTO v FROM grievance WHERE grievance_id = p_grievance_id FOR UPDATE;
    IF v IS NULL OR v.student_id IS DISTINCT FROM sims_private.current_student_id() THEN RAISE EXCEPTION 'Unknown grievance' USING ERRCODE = '42501'; END IF;
    IF p_response NOT IN ('CLOSE', 'REOPEN') THEN RAISE EXCEPTION 'The response must be CLOSE or REOPEN' USING ERRCODE = '22023'; END IF;
    IF length(COALESCE(p_notes, '')) > 2000 THEN RAISE EXCEPTION 'Notes are limited to 2000 characters' USING ERRCODE = '22023'; END IF;
    v_to := CASE p_response WHEN 'CLOSE' THEN 'CLOSED' ELSE 'UNDER_REVIEW' END;
    IF v.status = v_to AND p_response = 'CLOSE' THEN RETURN; END IF; -- idempotent close
    IF p_response = 'CLOSE' AND v.status NOT IN ('RESOLVED', 'REJECTED') THEN RAISE EXCEPTION 'Only a resolved or rejected grievance can be closed' USING ERRCODE = '45000'; END IF;
    IF p_response = 'REOPEN' AND v.status <> 'RESOLVED' THEN RAISE EXCEPTION 'Only a resolved grievance can be re-opened' USING ERRCODE = '45000'; END IF;
    UPDATE grievance SET status = v_to, resolved_at = CASE WHEN v_to = 'UNDER_REVIEW' THEN NULL ELSE resolved_at END WHERE grievance_id = p_grievance_id;
    INSERT INTO grievance_action (grievance_id, action_type, action_notes, new_status) VALUES (p_grievance_id, 'STUDENT_' || p_response, NULLIF(btrim(p_notes), ''), v_to);
END $function$;

CREATE OR REPLACE FUNCTION public.grievance_submit(p_category_id integer, p_department_id integer, p_subject text, p_description text, p_priority text DEFAULT 'NORMAL'::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_student bigint := sims_private.current_student_id(); v_inst integer; v_id bigint; v_number text; v_open integer;
BEGIN
    IF v_student IS NULL THEN RAISE EXCEPTION 'Only students can submit a grievance' USING ERRCODE = '42501'; END IF;
    IF p_subject IS NULL OR btrim(p_subject) = '' OR length(btrim(p_subject)) > 200 THEN RAISE EXCEPTION 'The subject is required (at most 200 characters)' USING ERRCODE = '22023'; END IF;
    IF p_description IS NULL OR btrim(p_description) = '' OR length(p_description) > 5000 THEN RAISE EXCEPTION 'The description is required (at most 5000 characters)' USING ERRCODE = '22023'; END IF;
    IF p_priority NOT IN ('LOW', 'NORMAL', 'HIGH', 'URGENT') THEN RAISE EXCEPTION 'Invalid priority' USING ERRCODE = '22023'; END IF;
    IF NOT EXISTS (SELECT 1 FROM grievance_category WHERE grievance_category_id = p_category_id AND is_active) THEN RAISE EXCEPTION 'Choose an active grievance category' USING ERRCODE = '22023'; END IF;
    IF p_department_id IS NOT NULL THEN
        SELECT c.institution_id INTO v_inst FROM department d JOIN campus c ON c.campus_id = d.campus_id WHERE d.department_id = p_department_id;
        IF v_inst IS NULL OR NOT EXISTS (SELECT 1 FROM student_programme_enrolment e WHERE e.student_id = v_student AND sims_private.programme_institution(e.programme_id) = v_inst) THEN
            RAISE EXCEPTION 'That department does not belong to your institution' USING ERRCODE = '22023';
        END IF;
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended('grievance:' || v_student, 0));
    SELECT count(*) INTO v_open FROM grievance WHERE student_id = v_student AND status <> 'CLOSED';
    IF v_open >= 10 THEN RAISE EXCEPTION 'You already have 10 open grievances; wait for them to be closed' USING ERRCODE = '45000'; END IF;
    v_number := 'GRV-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('sims_private.grievance_seq')::text, 6, '0');
    INSERT INTO grievance (grievance_number, student_id, grievance_category_id, department_id, subject, description, priority)
    VALUES (v_number, v_student, p_category_id, p_department_id, btrim(p_subject), btrim(p_description), p_priority) RETURNING grievance_id INTO v_id;
    INSERT INTO grievance_action (grievance_id, action_type, action_notes, new_status) VALUES (v_id, 'SUBMITTED', NULL, 'SUBMITTED');
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.iam_assign_role(p_user_id bigint, p_role_id integer, p_scope_type text, p_scope_entity_id integer DEFAULT NULL::integer, p_reason text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE r record; v_id bigint; v_reason text := NULLIF(btrim(p_reason), '');
BEGIN
    IF NOT sims_private.can_global(ARRAY['IAM.ALL.UPDATE']::text[]) THEN RAISE EXCEPTION 'Not authorised (IAM.ALL.UPDATE)' USING ERRCODE = '42501'; END IF;
    IF length(COALESCE(v_reason, '')) > 500 THEN RAISE EXCEPTION 'The reason is limited to 500 characters' USING ERRCODE = '22023'; END IF;
    IF NOT EXISTS (SELECT 1 FROM user_account WHERE user_id = p_user_id) THEN RAISE EXCEPTION 'Unknown user' USING ERRCODE = '22023'; END IF;
    IF p_user_id = sims_private.current_user_id() THEN RAISE EXCEPTION 'You cannot change your own roles' USING ERRCODE = '45000'; END IF;
    SELECT role_id, role_code, role_level, is_active, is_assignable INTO r FROM role WHERE role_id = p_role_id;
    IF r.role_id IS NULL OR NOT r.is_active OR NOT r.is_assignable THEN RAISE EXCEPTION 'Choose an active, assignable role' USING ERRCODE = '22023'; END IF;
    IF p_scope_type IS DISTINCT FROM r.role_level THEN RAISE EXCEPTION 'A % role must be assigned with % scope', r.role_code, r.role_level USING ERRCODE = '22023'; END IF;
    IF r.role_code = 'SUPER_ADMIN' AND NOT sims_private.caller_has_role('SUPER_ADMIN') THEN RAISE EXCEPTION 'Only a super administrator can grant the SUPER_ADMIN role' USING ERRCODE = '42501'; END IF;
    IF (p_scope_type IN ('GLOBAL', 'SELF')) <> (p_scope_entity_id IS NULL) THEN RAISE EXCEPTION 'The scope entity is required for % scope and not allowed otherwise', p_scope_type USING ERRCODE = '22023'; END IF;
    IF p_scope_type = 'INSTITUTION' AND NOT EXISTS (SELECT 1 FROM institution WHERE institution_id = p_scope_entity_id)
       OR p_scope_type = 'CAMPUS' AND NOT EXISTS (SELECT 1 FROM campus WHERE campus_id = p_scope_entity_id)
       OR p_scope_type = 'DEPARTMENT' AND NOT EXISTS (SELECT 1 FROM department WHERE department_id = p_scope_entity_id)
       OR p_scope_type = 'PROGRAMME' AND NOT EXISTS (SELECT 1 FROM programme WHERE programme_id = p_scope_entity_id) THEN
        RAISE EXCEPTION 'Unknown scope entity' USING ERRCODE = '22023';
    END IF;
    SELECT a.user_role_assignment_id INTO v_id FROM user_role_assignment a
    WHERE a.user_id = p_user_id AND a.role_id = p_role_id AND a.scope_type = p_scope_type AND a.scope_entity_id = CASE p_scope_type WHEN 'GLOBAL' THEN 0 WHEN 'SELF' THEN p_user_id ELSE p_scope_entity_id END
      AND a.assignment_status = 'ACTIVE' AND (a.valid_to IS NULL OR a.valid_to > now()) LIMIT 1;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF;
    INSERT INTO user_role_assignment (user_id, role_id, scope_type, institution_id, campus_id, department_id, programme_id, assigned_by_user_id, assignment_reason)
    VALUES (p_user_id, p_role_id, p_scope_type, CASE WHEN p_scope_type = 'INSTITUTION' THEN p_scope_entity_id END, CASE WHEN p_scope_type = 'CAMPUS' THEN p_scope_entity_id END,
            CASE WHEN p_scope_type = 'DEPARTMENT' THEN p_scope_entity_id END, CASE WHEN p_scope_type = 'PROGRAMME' THEN p_scope_entity_id END, sims_private.current_user_id(), v_reason)
    RETURNING user_role_assignment_id INTO v_id;
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.iam_link_person(p_user_id bigint, p_student_number text DEFAULT NULL::text, p_employee_number text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_student bigint; v_employee bigint;
BEGIN
    IF NOT sims_private.can_global(ARRAY['IAM.ALL.UPDATE']::text[]) THEN RAISE EXCEPTION 'Not authorised (IAM.ALL.UPDATE)' USING ERRCODE = '42501'; END IF;
    IF NOT EXISTS (SELECT 1 FROM user_account WHERE user_id = p_user_id) THEN RAISE EXCEPTION 'Unknown user' USING ERRCODE = '22023'; END IF;
    IF p_user_id = sims_private.current_user_id() THEN RAISE EXCEPTION 'You cannot change your own links' USING ERRCODE = '45000'; END IF;
    IF (NULLIF(btrim(p_student_number), '') IS NULL) = (NULLIF(btrim(p_employee_number), '') IS NULL) THEN RAISE EXCEPTION 'Give either a student number or an employee number' USING ERRCODE = '22023'; END IF;
    IF EXISTS (SELECT 1 FROM student_user_account WHERE user_id = p_user_id) OR EXISTS (SELECT 1 FROM employee_user_account WHERE user_id = p_user_id) THEN RAISE EXCEPTION 'That account is already linked to a person' USING ERRCODE = '23505'; END IF;
    IF NULLIF(btrim(p_student_number), '') IS NOT NULL THEN
        SELECT student_id INTO v_student FROM student WHERE student_number = btrim(p_student_number);
        IF v_student IS NULL THEN RAISE EXCEPTION 'Unknown student number' USING ERRCODE = '22023'; END IF;
        IF EXISTS (SELECT 1 FROM student_user_account WHERE student_id = v_student) THEN RAISE EXCEPTION 'That student already has an account' USING ERRCODE = '23505'; END IF;
        INSERT INTO student_user_account (student_id, user_id) VALUES (v_student, p_user_id);
    ELSE
        SELECT employee_id INTO v_employee FROM employee WHERE employee_number = btrim(p_employee_number);
        IF v_employee IS NULL THEN RAISE EXCEPTION 'Unknown employee number' USING ERRCODE = '22023'; END IF;
        IF EXISTS (SELECT 1 FROM employee_user_account WHERE employee_id = v_employee) THEN RAISE EXCEPTION 'That employee already has an account' USING ERRCODE = '23505'; END IF;
        INSERT INTO employee_user_account (employee_id, user_id) VALUES (v_employee, p_user_id);
    END IF;
    INSERT INTO activity_audit (user_id, module_code, action_code, entity_name, entity_id, after_values)
    VALUES (sims_private.current_user_id(), 'IAM', 'LINK_PERSON', 'user_account', p_user_id::text, jsonb_build_object('student_id', v_student, 'employee_id', v_employee));
END $function$;

CREATE OR REPLACE FUNCTION public.iam_mfa_policy_set(p_role_code text, p_required boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_role integer;
BEGIN
    IF NOT sims_private.can_global(ARRAY['IAM.ALL.CONFIGURE']::text[]) THEN RAISE EXCEPTION 'Not authorised (IAM.ALL.CONFIGURE)' USING ERRCODE = '42501'; END IF;
    SELECT role_id INTO v_role FROM role WHERE role_code = p_role_code AND is_active;
    IF v_role IS NULL THEN RAISE EXCEPTION 'Unknown role' USING ERRCODE = '22023'; END IF;
    IF p_required THEN
        INSERT INTO sims_private.mfa_required_role (role_id, set_by) VALUES (v_role, sims_private.current_user_id()) ON CONFLICT DO NOTHING;
    ELSE
        DELETE FROM sims_private.mfa_required_role WHERE role_id = v_role;
    END IF;
    INSERT INTO activity_audit (user_id, module_code, action_code, entity_name, entity_id, after_values)
    VALUES (sims_private.current_user_id(), 'IAM', 'MFA_POLICY', 'role', p_role_code, jsonb_build_object('required', p_required));
END $function$;

CREATE OR REPLACE FUNCTION public.iam_override_end(p_override_id bigint, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE o record; v_perm record;
BEGIN
    IF NOT sims_private.can_global(ARRAY['IAM.ALL.UPDATE']::text[]) THEN RAISE EXCEPTION 'Not authorised (IAM.ALL.UPDATE)' USING ERRCODE = '42501'; END IF;
    SELECT * INTO o FROM user_permission_override WHERE user_permission_override_id = p_override_id FOR UPDATE;
    IF o.user_permission_override_id IS NULL THEN RAISE EXCEPTION 'Unknown override' USING ERRCODE = '22023'; END IF;
    IF o.user_id = sims_private.current_user_id() THEN RAISE EXCEPTION 'You cannot change your own permissions' USING ERRCODE = '45000'; END IF;
    IF o.valid_to IS NOT NULL AND o.valid_to <= now() THEN RETURN; END IF; -- already ended
    SELECT permission_code, is_sensitive INTO v_perm FROM permission WHERE permission_id = o.permission_id;
    IF o.permission_effect = 'ALLOW' AND (v_perm.is_sensitive OR v_perm.permission_code LIKE 'IAM.%' OR v_perm.permission_code LIKE 'AUDIT.%') AND NOT sims_private.caller_has_role('SUPER_ADMIN') THEN
        RAISE EXCEPTION 'Only a super administrator can change a sensitive, IAM or AUDIT grant' USING ERRCODE = '42501';
    END IF;
    UPDATE user_permission_override SET valid_to = CASE WHEN now() > valid_from THEN now() ELSE valid_from + interval '1 microsecond' END, justification = left(justification || ' [ended: ' || COALESCE(NULLIF(btrim(p_reason), ''), 'no reason given') || ']', 500) WHERE user_permission_override_id = p_override_id;
END $function$;

CREATE OR REPLACE FUNCTION public.iam_override_set(p_user_id bigint, p_permission_code text, p_effect text, p_scope_type text, p_scope_entity_id integer, p_justification text, p_valid_to timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_perm record; v_id bigint; v_just text := NULLIF(btrim(p_justification), '');
BEGIN
    IF NOT sims_private.can_global(ARRAY['IAM.ALL.UPDATE']::text[]) THEN RAISE EXCEPTION 'Not authorised (IAM.ALL.UPDATE)' USING ERRCODE = '42501'; END IF;
    IF p_user_id IS NULL OR NOT EXISTS (SELECT 1 FROM user_account WHERE user_id = p_user_id) THEN RAISE EXCEPTION 'Unknown user' USING ERRCODE = '22023'; END IF;
    IF p_user_id = sims_private.current_user_id() THEN RAISE EXCEPTION 'You cannot change your own permissions' USING ERRCODE = '45000'; END IF;
    SELECT permission_id, permission_code, is_sensitive INTO v_perm FROM permission WHERE permission_code = p_permission_code;
    IF v_perm.permission_id IS NULL THEN RAISE EXCEPTION 'Unknown permission' USING ERRCODE = '22023'; END IF;
    IF p_effect NOT IN ('ALLOW', 'DENY') THEN RAISE EXCEPTION 'The effect must be ALLOW or DENY' USING ERRCODE = '22023'; END IF;
    IF p_scope_type NOT IN ('GLOBAL', 'INSTITUTION', 'CAMPUS', 'DEPARTMENT', 'PROGRAMME', 'SELF') THEN RAISE EXCEPTION 'Unknown scope' USING ERRCODE = '22023'; END IF;
    IF v_just IS NULL OR length(v_just) > 500 THEN RAISE EXCEPTION 'A justification is required (at most 500 characters)' USING ERRCODE = '22023'; END IF;
    IF p_valid_to IS NOT NULL AND p_valid_to <= now() THEN RAISE EXCEPTION 'The end of the override must be in the future' USING ERRCODE = '22023'; END IF;
    IF (p_scope_type IN ('GLOBAL', 'SELF')) <> (p_scope_entity_id IS NULL) THEN RAISE EXCEPTION 'The scope entity is required for % scope and not allowed otherwise', p_scope_type USING ERRCODE = '22023'; END IF;
    IF p_scope_type = 'INSTITUTION' AND NOT EXISTS (SELECT 1 FROM institution WHERE institution_id = p_scope_entity_id)
       OR p_scope_type = 'CAMPUS' AND NOT EXISTS (SELECT 1 FROM campus WHERE campus_id = p_scope_entity_id)
       OR p_scope_type = 'DEPARTMENT' AND NOT EXISTS (SELECT 1 FROM department WHERE department_id = p_scope_entity_id)
       OR p_scope_type = 'PROGRAMME' AND NOT EXISTS (SELECT 1 FROM programme WHERE programme_id = p_scope_entity_id) THEN RAISE EXCEPTION 'Unknown scope entity' USING ERRCODE = '22023'; END IF;
    IF p_effect = 'ALLOW' AND (v_perm.is_sensitive OR v_perm.permission_code LIKE 'IAM.%' OR v_perm.permission_code LIKE 'AUDIT.%') AND NOT sims_private.caller_has_role('SUPER_ADMIN') THEN
        RAISE EXCEPTION 'Only a super administrator can grant a sensitive, IAM or AUDIT permission' USING ERRCODE = '42501';
    END IF;
    SELECT user_permission_override_id INTO v_id FROM user_permission_override
     WHERE user_id = p_user_id AND permission_id = v_perm.permission_id AND scope_type = p_scope_type AND normalized_scope_entity_id = COALESCE(p_scope_entity_id, 0) AND permission_effect = p_effect
       AND (valid_to IS NULL OR valid_to > now()) LIMIT 1;
    IF v_id IS NOT NULL THEN RETURN v_id; END IF; -- idempotent: the same active override exists
    INSERT INTO user_permission_override (user_id, permission_id, permission_effect, scope_type, scope_entity_id, valid_to, granted_by_user_id, justification)
    VALUES (p_user_id, v_perm.permission_id, p_effect, p_scope_type, p_scope_entity_id, p_valid_to, sims_private.current_user_id(), v_just) RETURNING user_permission_override_id INTO v_id;
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.iam_revoke_role(p_assignment_id bigint, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a record; v_code text;
BEGIN
    IF NOT sims_private.can_global(ARRAY['IAM.ALL.UPDATE']::text[]) THEN RAISE EXCEPTION 'Not authorised (IAM.ALL.UPDATE)' USING ERRCODE = '42501'; END IF;
    SELECT user_role_assignment_id, user_id, role_id, assignment_status, valid_from INTO a FROM user_role_assignment WHERE user_role_assignment_id = p_assignment_id FOR UPDATE;
    IF a.user_role_assignment_id IS NULL THEN RAISE EXCEPTION 'Unknown assignment' USING ERRCODE = '22023'; END IF;
    IF a.user_id = sims_private.current_user_id() THEN RAISE EXCEPTION 'You cannot change your own roles' USING ERRCODE = '45000'; END IF;
    IF a.assignment_status = 'REVOKED' THEN RETURN; END IF; -- idempotent replay
    SELECT role_code INTO v_code FROM role WHERE role_id = a.role_id;
    IF v_code = 'SUPER_ADMIN' THEN
        IF NOT sims_private.caller_has_role('SUPER_ADMIN') THEN RAISE EXCEPTION 'Only a super administrator can revoke the SUPER_ADMIN role' USING ERRCODE = '42501'; END IF;
        IF sims_private.other_super_admins(a.user_id) = 0 THEN RAISE EXCEPTION 'This is the last active super administrator' USING ERRCODE = '45000'; END IF;
    END IF;
    UPDATE user_role_assignment SET assignment_status = 'REVOKED', valid_to = GREATEST(now(), a.valid_from + interval '1 second'),
        assignment_reason = COALESCE(NULLIF(btrim(p_reason), ''), assignment_reason) WHERE user_role_assignment_id = p_assignment_id;
END $function$;

CREATE OR REPLACE FUNCTION public.iam_set_account_status(p_user_id bigint, p_status text, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v record; v_reason text := NULLIF(btrim(p_reason), '');
BEGIN
    IF NOT sims_private.can_global(ARRAY['IAM.ALL.UPDATE']::text[]) THEN RAISE EXCEPTION 'Not authorised (IAM.ALL.UPDATE)' USING ERRCODE = '42501'; END IF;
    IF p_status NOT IN ('ACTIVE', 'DISABLED', 'LOCKED') THEN RAISE EXCEPTION 'The status must be ACTIVE, DISABLED or LOCKED' USING ERRCODE = '22023'; END IF;
    IF length(COALESCE(v_reason, '')) > 500 THEN RAISE EXCEPTION 'The reason is limited to 500 characters' USING ERRCODE = '22023'; END IF;
    IF p_status <> 'ACTIVE' AND v_reason IS NULL THEN RAISE EXCEPTION 'A reason is required to disable or lock an account' USING ERRCODE = '22023'; END IF;
    SELECT user_id, account_status INTO v FROM user_account WHERE user_id = p_user_id FOR UPDATE;
    IF v.user_id IS NULL THEN RAISE EXCEPTION 'Unknown user' USING ERRCODE = '22023'; END IF;
    IF v.user_id = sims_private.current_user_id() THEN RAISE EXCEPTION 'You cannot change your own account status' USING ERRCODE = '45000'; END IF;
    IF v.account_status = p_status THEN RETURN; END IF; -- idempotent replay
    IF p_status <> 'ACTIVE' AND sims_private.other_super_admins(p_user_id) = 0
       AND EXISTS (SELECT 1 FROM user_role_assignment a JOIN role r ON r.role_id = a.role_id WHERE a.user_id = p_user_id AND r.role_code = 'SUPER_ADMIN' AND a.assignment_status = 'ACTIVE') THEN
        RAISE EXCEPTION 'This is the last active super administrator' USING ERRCODE = '45000';
    END IF;
    UPDATE user_account SET account_status = p_status, failed_login_count = CASE WHEN p_status = 'ACTIVE' THEN 0 ELSE failed_login_count END,
        locked_until = CASE WHEN p_status = 'ACTIVE' THEN NULL ELSE locked_until END WHERE user_id = p_user_id;
    INSERT INTO activity_audit (user_id, module_code, action_code, entity_name, entity_id, before_values, after_values, details)
    VALUES (sims_private.current_user_id(), 'IAM', 'ACCOUNT_STATUS', 'user_account', p_user_id::text, jsonb_build_object('account_status', v.account_status), jsonb_build_object('account_status', p_status), jsonb_build_object('reason', v_reason));
END $function$;

CREATE OR REPLACE FUNCTION public.institution_create(p jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_id integer; v_constraint text;
BEGIN
    IF NOT sims_private.can_global(ARRAY['INSTITUTION.ALL.CREATE']::text[]) THEN
        RAISE EXCEPTION 'Not authorised to create institutions' USING ERRCODE = '42501';
    END IF;
    IF p IS NULL OR jsonb_typeof(p) <> 'object' THEN RAISE EXCEPTION 'payload must be an object' USING ERRCODE = '22023'; END IF;
    IF NULLIF(btrim(p ->> 'institution_code'), '') IS NULL OR NULLIF(btrim(p ->> 'institution_name'), '') IS NULL OR (p ->> 'university_id') IS NULL THEN
        RAISE EXCEPTION 'university_id, institution_code and institution_name are required' USING ERRCODE = '22023';
    END IF;
    PERFORM sims_private.check_institution_fields(p);
    BEGIN
        INSERT INTO institution (university_id, institution_code, institution_name, legal_name, website_url, email, phone, is_active)
        VALUES ((p ->> 'university_id')::integer, btrim(p ->> 'institution_code'), btrim(p ->> 'institution_name'), NULLIF(btrim(p ->> 'legal_name'), ''),
                NULLIF(btrim(p ->> 'website_url'), ''), NULLIF(btrim(p ->> 'email'), ''), NULLIF(btrim(p ->> 'phone'), ''), COALESCE((p ->> 'is_active')::boolean, true))
        RETURNING institution_id INTO v_id;
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF v_constraint = 'institution_institution_code_key' THEN
            RAISE EXCEPTION 'Institution code is already in use' USING ERRCODE = '23505';
        END IF;
        RAISE;
    END;
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.institution_update(p_id integer, p jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_constraint text;
BEGIN
    IF NOT sims_private.can_institution(ARRAY['INSTITUTION.ALL.UPDATE']::text[], p_id)
       OR NOT EXISTS (SELECT 1 FROM institution WHERE institution_id = p_id) THEN
        RAISE EXCEPTION 'Not authorised to update this institution, or it does not exist' USING ERRCODE = '42501';
    END IF;
    IF p IS NULL OR jsonb_typeof(p) <> 'object' THEN RAISE EXCEPTION 'payload must be an object' USING ERRCODE = '22023'; END IF;
    PERFORM sims_private.check_institution_fields(p);
    IF (p ? 'institution_code' AND NULLIF(btrim(p ->> 'institution_code'), '') IS NULL)
       OR (p ? 'institution_name' AND NULLIF(btrim(p ->> 'institution_name'), '') IS NULL) THEN
        RAISE EXCEPTION 'institution_code and institution_name cannot be blank' USING ERRCODE = '22023';
    END IF;
    BEGIN
        UPDATE institution SET
            institution_code = CASE WHEN p ? 'institution_code' THEN btrim(p ->> 'institution_code') ELSE institution_code END,
            institution_name = CASE WHEN p ? 'institution_name' THEN btrim(p ->> 'institution_name') ELSE institution_name END,
            legal_name = CASE WHEN p ? 'legal_name' THEN NULLIF(btrim(p ->> 'legal_name'), '') ELSE legal_name END,
            website_url = CASE WHEN p ? 'website_url' THEN NULLIF(btrim(p ->> 'website_url'), '') ELSE website_url END,
            email = CASE WHEN p ? 'email' THEN NULLIF(btrim(p ->> 'email'), '') ELSE email END,
            phone = CASE WHEN p ? 'phone' THEN NULLIF(btrim(p ->> 'phone'), '') ELSE phone END,
            is_active = CASE WHEN p ? 'is_active' THEN (p ->> 'is_active')::boolean ELSE is_active END
        WHERE institution_id = p_id;
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF v_constraint = 'institution_institution_code_key' THEN
            RAISE EXCEPTION 'Institution code is already in use' USING ERRCODE = '23505';
        END IF;
        RAISE;
    END;
END $function$;

CREATE OR REPLACE FUNCTION public.mentoring_assign(p_student_number text, p_employee_number text, p_start date DEFAULT CURRENT_DATE)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_student bigint; v_emp record; v_prog integer; v_id bigint;
BEGIN
    IF p_student_number IS NULL OR btrim(p_student_number) = '' OR p_employee_number IS NULL OR btrim(p_employee_number) = '' THEN
        RAISE EXCEPTION 'Student number and employee number are required' USING ERRCODE = '22023';
    END IF;
    SELECT student_id INTO v_student FROM student WHERE student_number = btrim(p_student_number);
    IF v_student IS NULL OR NOT sims_private.can_student(ARRAY['MENTORING.ALL.ASSIGN']::text[], v_student, true) THEN
        RAISE EXCEPTION 'Not authorised (MENTORING.ALL.ASSIGN) or unknown student' USING ERRCODE = '42501';
    END IF;
    SELECT e.programme_id INTO v_prog FROM student_programme_enrolment e WHERE e.student_id = v_student AND e.enrolment_status = 'ACTIVE' ORDER BY e.enrolment_id DESC LIMIT 1;
    IF v_prog IS NULL THEN RAISE EXCEPTION 'The student has no ACTIVE enrolment' USING ERRCODE = '45000'; END IF;
    SELECT employee_id, institution_id, employment_status INTO v_emp FROM employee WHERE employee_number = btrim(p_employee_number);
    IF v_emp IS NULL THEN RAISE EXCEPTION 'Unknown employee number' USING ERRCODE = '22023'; END IF;
    IF v_emp.employment_status <> 'ACTIVE' THEN RAISE EXCEPTION 'The employee is not ACTIVE' USING ERRCODE = '45000'; END IF;
    IF v_emp.institution_id <> sims_private.programme_institution(v_prog) THEN RAISE EXCEPTION 'The mentor belongs to a different institution from the student' USING ERRCODE = '45000'; END IF;

    SELECT mentor_assignment_id INTO v_id FROM mentor_assignment WHERE student_id = v_student AND employee_id = v_emp.employee_id AND assignment_status = 'ACTIVE';
    IF v_id IS NOT NULL THEN RETURN v_id; END IF; -- idempotent replay
    PERFORM pg_advisory_xact_lock(hashtextextended('mentor:' || v_student, 0));
    IF EXISTS (SELECT 1 FROM mentor_assignment WHERE student_id = v_student AND assignment_status = 'ACTIVE') THEN
        RAISE EXCEPTION 'The student already has an ACTIVE mentor; end that assignment first' USING ERRCODE = '45000';
    END IF;
    INSERT INTO mentor_assignment (student_id, employee_id, start_date) VALUES (v_student, v_emp.employee_id, COALESCE(p_start, current_date)) RETURNING mentor_assignment_id INTO v_id;
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.mentoring_end_assignment(p_assignment_id bigint, p_status text, p_end_date date DEFAULT CURRENT_DATE)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v record;
BEGIN
    SELECT student_id, start_date, assignment_status INTO v FROM mentor_assignment WHERE mentor_assignment_id = p_assignment_id FOR UPDATE;
    IF v IS NULL OR NOT sims_private.can_student(ARRAY['MENTORING.ALL.ASSIGN']::text[], v.student_id, true) THEN
        RAISE EXCEPTION 'Not authorised (MENTORING.ALL.ASSIGN) or unknown assignment' USING ERRCODE = '42501';
    END IF;
    IF p_status NOT IN ('COMPLETED', 'CANCELLED') THEN RAISE EXCEPTION 'The status must be COMPLETED or CANCELLED' USING ERRCODE = '22023'; END IF;
    IF v.assignment_status <> 'ACTIVE' THEN
        IF v.assignment_status = p_status THEN RETURN; END IF;
        RAISE EXCEPTION 'The assignment is already %', v.assignment_status USING ERRCODE = '45000';
    END IF;
    IF COALESCE(p_end_date, current_date) < v.start_date THEN RAISE EXCEPTION 'The end date cannot be before the start date' USING ERRCODE = '45000'; END IF;
    UPDATE mentor_assignment SET assignment_status = p_status, end_date = COALESCE(p_end_date, current_date) WHERE mentor_assignment_id = p_assignment_id;
END $function$;

CREATE OR REPLACE FUNCTION public.mentoring_record_session(p_assignment_id bigint, p_date timestamp with time zone, p_observations text, p_action_plan text, p_follow_up date, p_status text DEFAULT 'COMPLETED'::text, p_level text DEFAULT 'RESTRICTED'::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_status text; v_id bigint;
BEGIN
    IF NOT sims_private.mentoring_can_see(p_assignment_id) THEN RAISE EXCEPTION 'Not authorised (MENTORING.ALL.CREATE) or unknown assignment' USING ERRCODE = '42501'; END IF;
    IF NOT (sims_private.is_mentor_of(p_assignment_id) OR sims_private.can_global(ARRAY['MENTORING.ALL.CREATE']::text[])) THEN
        RAISE EXCEPTION 'Not authorised (MENTORING.ALL.CREATE): only the assigned mentor records sessions' USING ERRCODE = '42501';
    END IF;
    SELECT assignment_status INTO v_status FROM mentor_assignment WHERE mentor_assignment_id = p_assignment_id;
    IF v_status <> 'ACTIVE' THEN RAISE EXCEPTION 'The assignment is %; sessions can only be recorded while it is ACTIVE', v_status USING ERRCODE = '45000'; END IF;
    PERFORM sims_private.mentoring_check_session(p_date, p_observations, p_action_plan, p_follow_up, p_status, p_level);
    INSERT INTO counselling_session (mentor_assignment_id, session_date, observations, action_plan, follow_up_date, session_status, confidentiality_level)
    VALUES (p_assignment_id, p_date, NULLIF(btrim(p_observations), ''), NULLIF(btrim(p_action_plan), ''), p_follow_up, p_status, p_level) RETURNING counselling_session_id INTO v_id;
    PERFORM sims_private.mentoring_audit('INSERT', v_id, p_assignment_id);
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.mentoring_update_session(p_session_id bigint, p_date timestamp with time zone, p_observations text, p_action_plan text, p_follow_up date, p_status text, p_level text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_assignment bigint; v_status text;
BEGIN
    SELECT mentor_assignment_id INTO v_assignment FROM counselling_session WHERE counselling_session_id = p_session_id FOR UPDATE;
    IF v_assignment IS NULL OR NOT sims_private.mentoring_can_see(v_assignment)
       OR NOT (sims_private.is_mentor_of(v_assignment) OR sims_private.can_global(ARRAY['MENTORING.ALL.UPDATE']::text[])) THEN
        RAISE EXCEPTION 'Not authorised (MENTORING.ALL.UPDATE) or unknown session' USING ERRCODE = '42501';
    END IF;
    SELECT assignment_status INTO v_status FROM mentor_assignment WHERE mentor_assignment_id = v_assignment;
    IF v_status <> 'ACTIVE' THEN RAISE EXCEPTION 'The assignment is %; its sessions can no longer be changed', v_status USING ERRCODE = '45000'; END IF;
    PERFORM sims_private.mentoring_check_session(p_date, p_observations, p_action_plan, p_follow_up, p_status, p_level);
    UPDATE counselling_session SET session_date = p_date, observations = NULLIF(btrim(p_observations), ''), action_plan = NULLIF(btrim(p_action_plan), ''), follow_up_date = p_follow_up,
                                   session_status = p_status, confidentiality_level = p_level WHERE counselling_session_id = p_session_id;
    PERFORM sims_private.mentoring_audit('UPDATE', p_session_id, v_assignment);
END $function$;

CREATE OR REPLACE FUNCTION public.mfa_recovery_generate()
 RETURNS text[]
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_uid bigint := sims_private.current_user_id();
    v_alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    v_codes text[] := '{}'; v_code text; i integer; j integer; v_bytes bytea;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authorised' USING ERRCODE = '42501'; END IF;
    DELETE FROM sims_private.mfa_recovery_code WHERE user_id = v_uid;
    FOR i IN 1..10 LOOP
        v_bytes := extensions.gen_random_bytes(10);
        v_code := '';
        FOR j IN 0..9 LOOP v_code := v_code || substr(v_alphabet, (get_byte(v_bytes, j) % 31) + 1, 1); END LOOP;
        v_code := substr(v_code, 1, 5) || '-' || substr(v_code, 6, 5);
        INSERT INTO sims_private.mfa_recovery_code (user_id, code_hash) VALUES (v_uid, extensions.crypt(v_code, extensions.gen_salt('bf', 8)));
        v_codes := v_codes || v_code;
    END LOOP;
    INSERT INTO activity_audit (user_id, module_code, action_code, entity_name, entity_id, details) VALUES (v_uid, 'IAM', 'MFA_RECOVERY_CODES_GENERATED', 'user_account', v_uid::text, '{}'::jsonb);
    RETURN v_codes;
END $function$;

CREATE OR REPLACE FUNCTION public.mfa_recovery_use(p_code text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid bigint := sims_private.user_id_any_aal(); v_code text := upper(regexp_replace(COALESCE(p_code, ''), '[\s-]', '', 'g')); r record; v_ok boolean := false; v_norm text;
BEGIN
    IF v_uid IS NULL OR NOT EXISTS (SELECT 1 FROM user_account WHERE user_id = v_uid AND multi_factor_enabled) THEN RAISE EXCEPTION 'Not authorised' USING ERRCODE = '42501'; END IF;
    DELETE FROM sims_private.mfa_recovery_attempt WHERE attempted_at < now() - interval '1 day';
    IF (SELECT count(*) FROM sims_private.mfa_recovery_attempt WHERE user_id = v_uid AND attempted_at > now() - interval '15 minutes') >= 5 THEN
        RAISE EXCEPTION 'Too many wrong codes. Try again in 15 minutes.' USING ERRCODE = '45000';
    END IF;
    IF length(v_code) = 10 THEN
        v_norm := substr(v_code, 1, 5) || '-' || substr(v_code, 6, 5);
        FOR r IN SELECT code_id, code_hash FROM sims_private.mfa_recovery_code WHERE user_id = v_uid AND used_at IS NULL ORDER BY code_id FOR UPDATE LOOP
            IF r.code_hash = extensions.crypt(v_norm, r.code_hash) THEN
                UPDATE sims_private.mfa_recovery_code SET used_at = now() WHERE code_id = r.code_id;
                v_ok := true;
                EXIT;
            END IF;
        END LOOP;
    END IF;
    IF NOT v_ok THEN
        INSERT INTO sims_private.mfa_recovery_attempt (user_id) VALUES (v_uid);
        RETURN false; -- committed: the function returns normally so the attempt is recorded
    END IF;
    DELETE FROM auth.mfa_factors WHERE user_id = auth.uid();
    UPDATE user_account SET multi_factor_enabled = false WHERE user_id = v_uid;
    DELETE FROM sims_private.mfa_recovery_code WHERE user_id = v_uid;
    INSERT INTO activity_audit (user_id, module_code, action_code, entity_name, entity_id, details) VALUES (v_uid, 'IAM', 'MFA_RECOVERY_USED', 'user_account', v_uid::text, '{}'::jsonb);
    RETURN true;
END $function$;

CREATE OR REPLACE FUNCTION public.mfa_sync()
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid bigint := sims_private.current_user_id(); v_has boolean;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authorised' USING ERRCODE = '42501'; END IF;
    SELECT EXISTS (SELECT 1 FROM auth.mfa_factors f WHERE f.user_id = auth.uid() AND f.status = 'verified') INTO v_has;
    UPDATE user_account SET multi_factor_enabled = v_has WHERE user_id = v_uid AND multi_factor_enabled IS DISTINCT FROM v_has;
    RETURN v_has;
END $function$;

CREATE OR REPLACE FUNCTION public.my_profile_update(p jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_student bigint := sims_private.current_student_id(); v_employee bigint := sims_private.current_employee_id(); v_bad text;
        v_has_email boolean; v_has_phone boolean; v_email text; v_phone text;
BEGIN
    IF v_student IS NULL AND v_employee IS NULL THEN RAISE EXCEPTION 'Only students and employees have a profile to edit' USING ERRCODE = '42501'; END IF;
    IF p IS NULL OR jsonb_typeof(p) <> 'object' THEN RAISE EXCEPTION 'p must be an object' USING ERRCODE = '22023'; END IF;
    SELECT string_agg(k, ', ') INTO v_bad FROM jsonb_object_keys(p) k WHERE k NOT IN ('primary_email', 'primary_phone');
    IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'These fields cannot be changed here: %', v_bad USING ERRCODE = '22023'; END IF;
    v_has_email := p ? 'primary_email'; v_has_phone := p ? 'primary_phone';
    v_email := lower(NULLIF(btrim(p ->> 'primary_email'), '')); v_phone := NULLIF(btrim(p ->> 'primary_phone'), '');
    IF v_email IS NOT NULL AND (length(v_email) > 254 OR v_email !~ '^[^\s@]+@[^\s@]+\.[^\s@]+$') THEN RAISE EXCEPTION 'Enter a valid email address' USING ERRCODE = '22023'; END IF;
    IF v_phone IS NOT NULL AND v_phone !~ '^[0-9+() -]{6,25}$' THEN RAISE EXCEPTION 'Enter a valid phone number (digits, spaces, + ( ) - only)' USING ERRCODE = '22023'; END IF;
    BEGIN
        IF v_student IS NOT NULL THEN
            UPDATE student SET primary_email = CASE WHEN v_has_email THEN v_email ELSE primary_email END, primary_phone = CASE WHEN v_has_phone THEN v_phone ELSE primary_phone END WHERE student_id = v_student;
        ELSE
            UPDATE employee SET primary_email = CASE WHEN v_has_email THEN v_email ELSE primary_email END, primary_phone = CASE WHEN v_has_phone THEN v_phone ELSE primary_phone END WHERE employee_id = v_employee;
        END IF;
    EXCEPTION WHEN unique_violation THEN
        RAISE EXCEPTION 'That email address is already used by another record' USING ERRCODE = '23505';
    END;
END $function$;

CREATE OR REPLACE FUNCTION public.notification_dismiss(p_key text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid bigint := sims_private.current_user_id();
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authorised' USING ERRCODE = '42501'; END IF;
    IF p_key IS NULL OR btrim(p_key) = '' OR length(p_key) > 200 THEN RAISE EXCEPTION 'Invalid notification' USING ERRCODE = '22023'; END IF;
    INSERT INTO sims_private.notification_dismissal (user_id, notif_key) VALUES (v_uid, p_key) ON CONFLICT DO NOTHING;
END $function$;

CREATE OR REPLACE FUNCTION public.notification_dismiss_all()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid bigint := sims_private.current_user_id(); n integer;
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authorised' USING ERRCODE = '42501'; END IF;
    INSERT INTO sims_private.notification_dismissal (user_id, notif_key) SELECT v_uid, a.notif_key FROM sims_private.notifications_all() a ON CONFLICT DO NOTHING;
    GET DIAGNOSTICS n = ROW_COUNT;
    DELETE FROM sims_private.notification_dismissal WHERE user_id = v_uid AND dismissed_at < now() - interval '90 days';
    RETURN n;
END $function$;

CREATE OR REPLACE FUNCTION public.offering_generate_courses(p_programme_term_offering_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_pto record; v_n integer;
BEGIN
    SELECT programme_id, curriculum_scheme_id, semester_id, status INTO v_pto FROM programme_term_offering WHERE programme_term_offering_id = p_programme_term_offering_id;
    IF v_pto IS NULL OR NOT sims_private.can_programme(ARRAY['TEACHING.ALL.CREATE']::text[], v_pto.programme_id) THEN
        RAISE EXCEPTION 'Not authorised (TEACHING.ALL.CREATE) or unknown offering' USING ERRCODE = '42501';
    END IF;
    IF v_pto.status IN ('COMPLETED', 'CANCELLED') THEN
        RAISE EXCEPTION 'The offering is %', v_pto.status USING ERRCODE = '45000';
    END IF;
    INSERT INTO course_offering (programme_term_offering_id, curriculum_course_id, course_id, offering_code)
    SELECT p_programme_term_offering_id, cc.curriculum_course_id, cc.course_id, left(p_programme_term_offering_id || '-' || c.course_code, 50)
    FROM curriculum_course cc JOIN course_catalog c ON c.course_id = cc.course_id
    WHERE cc.curriculum_scheme_id = v_pto.curriculum_scheme_id AND cc.semester_id = v_pto.semester_id
    ON CONFLICT DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n;
END $function$;

CREATE OR REPLACE FUNCTION public.ref_delete(p_table text, p_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE d record; v_pk text; v_before jsonb;
BEGIN
    SELECT * INTO d FROM sims_private.ref_def(p_table);
    IF d.perm IS NULL THEN RAISE EXCEPTION 'Unknown reference table' USING ERRCODE = '22023'; END IF;
    IF NOT sims_private.can_global(ARRAY[d.perm]::text[]) THEN RAISE EXCEPTION 'Not authorised (%)', d.perm USING ERRCODE = '42501'; END IF;
    v_pk := sims_private.pk_column(p_table);
    EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE t.%I = $1', p_table, v_pk) INTO v_before USING p_id;
    IF v_before IS NULL THEN RAISE EXCEPTION 'Unknown row' USING ERRCODE = '22023'; END IF;
    BEGIN
        EXECUTE format('DELETE FROM public.%I WHERE %I = $1', p_table, v_pk) USING p_id;
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'This row is still in use and cannot be deleted' USING ERRCODE = '45000';
    END;
    PERFORM sims_private.audit_manual(d.module_code, 'DELETE', p_table, p_id, v_before, NULL);
END $function$;

CREATE OR REPLACE FUNCTION public.result_compute_term(p_term_registration_id bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_tr record; v_prog integer; v_registered numeric; v_earned numeric; v_sgpa numeric; v_cgpa numeric; v_status text; v_missing integer; v_withheld integer; v_failed integer; v_id bigint; v_n integer;
BEGIN
    SELECT tr.enrolment_id, o.programme_id INTO v_tr FROM student_term_registration tr JOIN programme_term_offering o ON o.programme_term_offering_id = tr.programme_term_offering_id
     WHERE tr.term_registration_id = p_term_registration_id;
    IF v_tr IS NULL THEN RAISE EXCEPTION 'Not authorised (RESULT.ALL.CREATE) or unknown registration' USING ERRCODE = '42501'; END IF;
    v_prog := v_tr.programme_id;
    IF NOT sims_private.can_programme(ARRAY['RESULT.ALL.CREATE']::text[], v_prog) THEN RAISE EXCEPTION 'Not authorised (RESULT.ALL.CREATE) or unknown registration' USING ERRCODE = '42501'; END IF;
    IF EXISTS (SELECT 1 FROM student_term_result WHERE term_registration_id = p_term_registration_id AND published_at IS NOT NULL) THEN
        RAISE EXCEPTION 'The term result is published; unpublish it before recomputing' USING ERRCODE = '45000';
    END IF;

    WITH regs AS (
        SELECT cr.course_registration_id, c.credits, r.result_status, r.credits_earned
        FROM student_course_registration cr
        JOIN course_offering co ON co.course_offering_id = cr.course_offering_id
        JOIN course_catalog c ON c.course_id = co.course_id
        LEFT JOIN LATERAL (SELECT x.result_status, x.credits_earned FROM student_course_result x WHERE x.course_registration_id = cr.course_registration_id ORDER BY x.attempt_number DESC LIMIT 1) r ON true
        WHERE cr.term_registration_id = p_term_registration_id AND cr.registration_status IN ('REGISTERED', 'APPROVED', 'COMPLETED')
    )
    SELECT count(*), COALESCE(sum(credits), 0), COALESCE(sum(CASE WHEN result_status = 'PASS' THEN credits_earned ELSE 0 END), 0),
           count(*) FILTER (WHERE result_status IS NULL OR result_status = 'INCOMPLETE'),
           count(*) FILTER (WHERE result_status = 'WITHHELD'),
           count(*) FILTER (WHERE result_status IN ('FAIL', 'ABSENT'))
    INTO v_n, v_registered, v_earned, v_missing, v_withheld, v_failed FROM regs;
    IF v_n = 0 THEN v_status := 'INCOMPLETE';
    ELSIF v_missing > 0 THEN v_status := 'INCOMPLETE';
    ELSIF v_withheld > 0 THEN v_status := 'WITHHELD';
    ELSIF v_failed > 0 THEN v_status := 'FAIL';
    ELSE v_status := 'PASS';
    END IF;

    -- SGPA: this term's latest results, graded courses of GPA-contributing categories, weighted by course credits
    SELECT round(sum(r.grade_point * c.credits) / NULLIF(sum(c.credits), 0), 2) INTO v_sgpa
    FROM student_course_registration cr
    JOIN course_offering co ON co.course_offering_id = cr.course_offering_id JOIN course_catalog c ON c.course_id = co.course_id
    LEFT JOIN curriculum_course cc ON cc.curriculum_course_id = co.curriculum_course_id
    JOIN course_category cat ON cat.course_category_id = COALESCE(cc.course_category_id, c.course_category_id)
    JOIN LATERAL (SELECT x.* FROM student_course_result x WHERE x.course_registration_id = cr.course_registration_id ORDER BY x.attempt_number DESC LIMIT 1) r ON true
    WHERE cr.term_registration_id = p_term_registration_id AND cr.registration_status IN ('REGISTERED', 'APPROVED', 'COMPLETED')
      AND cat.contributes_to_gpa AND cat.is_graded AND r.grade_point IS NOT NULL;

    -- CGPA: the latest result per course across the student's enrolment
    SELECT round(sum(t.grade_point * t.credits) / NULLIF(sum(t.credits), 0), 2) INTO v_cgpa FROM (
        SELECT DISTINCT ON (c.course_id) r.grade_point, c.credits
        FROM student_term_registration tr2
        JOIN student_course_registration cr ON cr.term_registration_id = tr2.term_registration_id AND cr.registration_status IN ('REGISTERED', 'APPROVED', 'COMPLETED')
        JOIN course_offering co ON co.course_offering_id = cr.course_offering_id JOIN course_catalog c ON c.course_id = co.course_id
        LEFT JOIN curriculum_course cc ON cc.curriculum_course_id = co.curriculum_course_id
        JOIN course_category cat ON cat.course_category_id = COALESCE(cc.course_category_id, c.course_category_id)
        JOIN LATERAL (SELECT x.* FROM student_course_result x WHERE x.course_registration_id = cr.course_registration_id ORDER BY x.attempt_number DESC LIMIT 1) r ON true
        WHERE tr2.enrolment_id = v_tr.enrolment_id AND cat.contributes_to_gpa AND cat.is_graded AND r.grade_point IS NOT NULL
        ORDER BY c.course_id, r.result_date DESC NULLS LAST, r.attempt_number DESC, r.student_course_result_id DESC
    ) t;

    INSERT INTO student_term_result (term_registration_id, credits_registered, credits_earned, sgpa, cgpa, result_status)
    VALUES (p_term_registration_id, v_registered, v_earned, v_sgpa, v_cgpa, v_status)
    ON CONFLICT (term_registration_id)
    DO UPDATE SET credits_registered = EXCLUDED.credits_registered, credits_earned = EXCLUDED.credits_earned, sgpa = EXCLUDED.sgpa, cgpa = EXCLUDED.cgpa, result_status = EXCLUDED.result_status
    RETURNING student_term_result_id INTO v_id;
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.result_publish_term(p_term_registration_id bigint, p_publish boolean DEFAULT true)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_prog integer; v_tr record;
BEGIN
    SELECT o.programme_id INTO v_prog FROM student_term_registration tr JOIN programme_term_offering o ON o.programme_term_offering_id = tr.programme_term_offering_id WHERE tr.term_registration_id = p_term_registration_id;
    IF v_prog IS NULL OR NOT sims_private.can_programme(ARRAY['RESULT.ALL.PUBLISH']::text[], v_prog) THEN
        RAISE EXCEPTION 'Not authorised (RESULT.ALL.PUBLISH) or unknown registration' USING ERRCODE = '42501';
    END IF;
    SELECT result_status, published_at INTO v_tr FROM student_term_result WHERE term_registration_id = p_term_registration_id FOR UPDATE;
    IF v_tr IS NULL THEN RAISE EXCEPTION 'No term result has been computed for this registration' USING ERRCODE = '45000'; END IF;
    IF p_publish THEN
        IF v_tr.published_at IS NOT NULL THEN RETURN; END IF;  -- idempotent replay
        IF v_tr.result_status IN ('INCOMPLETE', 'WITHHELD') THEN RAISE EXCEPTION 'A % term result cannot be published', v_tr.result_status USING ERRCODE = '45000'; END IF;
        UPDATE student_term_result SET published_at = now() WHERE term_registration_id = p_term_registration_id;
    ELSE
        UPDATE student_term_result SET published_at = NULL WHERE term_registration_id = p_term_registration_id;
    END IF;
END $function$;

CREATE OR REPLACE FUNCTION public.result_record_course(p_course_registration_id bigint, p_internal numeric DEFAULT NULL::numeric, p_external numeric DEFAULT NULL::numeric, p_attempt integer DEFAULT 1, p_status text DEFAULT NULL::text, p_remarks text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_reg record; v_cc record; v_credits numeric; v_scale bigint; v_rule record; v_total numeric; v_pct numeric; v_status text; v_letter text; v_point numeric;
    v_earned numeric := 0; v_existing bigint; v_id bigint;
BEGIN
    SELECT cr.course_offering_id, cr.registration_status, co.curriculum_course_id, co.course_id INTO v_reg
      FROM student_course_registration cr JOIN course_offering co ON co.course_offering_id = cr.course_offering_id WHERE cr.course_registration_id = p_course_registration_id;
    IF v_reg IS NULL THEN RAISE EXCEPTION 'Not authorised (RESULT.ALL.CREATE) or unknown registration' USING ERRCODE = '42501'; END IF;
    PERFORM sims_private.asm_authorize(v_reg.course_offering_id, 'RESULT', 'CREATE');
    SELECT student_course_result_id INTO v_existing FROM student_course_result WHERE course_registration_id = p_course_registration_id AND attempt_number = p_attempt;
    IF v_existing IS NOT NULL AND NOT sims_private.can_programme(ARRAY['RESULT.ALL.UPDATE']::text[], sims_private.programme_of_offering(v_reg.course_offering_id)) THEN
        RAISE EXCEPTION 'Not authorised (RESULT.ALL.UPDATE) to change a recorded result' USING ERRCODE = '42501';
    END IF;
    IF v_reg.registration_status NOT IN ('REGISTERED', 'APPROVED', 'COMPLETED') THEN
        RAISE EXCEPTION 'The course registration is %', v_reg.registration_status USING ERRCODE = '45000';
    END IF;
    IF p_attempt IS NULL OR p_attempt < 1 OR p_attempt > 255 THEN RAISE EXCEPTION 'attempt must be from 1 to 255' USING ERRCODE = '22023'; END IF;
    IF p_internal IS NOT NULL AND (p_internal < 0 OR p_internal <> round(p_internal, 2)) OR p_external IS NOT NULL AND (p_external < 0 OR p_external <> round(p_external, 2)) THEN
        RAISE EXCEPTION 'Marks must be non-negative with at most 2 decimals' USING ERRCODE = '22023';
    END IF;
    SELECT credits INTO v_credits FROM course_catalog WHERE course_id = v_reg.course_id;

    IF p_status IS NOT NULL THEN
        IF p_status NOT IN ('ABSENT', 'WITHHELD', 'EXEMPTED', 'INCOMPLETE') THEN
            RAISE EXCEPTION 'p_status may only be ABSENT, WITHHELD, EXEMPTED or INCOMPLETE (PASS/FAIL come from the marks)' USING ERRCODE = '22023';
        END IF;
        v_status := p_status; v_total := NULL; v_letter := NULL; v_point := NULL;
    ELSE
        IF p_internal IS NULL OR p_external IS NULL THEN RAISE EXCEPTION 'Internal and external marks are required (or give an explicit status)' USING ERRCODE = '22023'; END IF;
        IF v_reg.curriculum_course_id IS NULL THEN RAISE EXCEPTION 'This course offering is not linked to a curriculum course, so its maximum marks are unknown' USING ERRCODE = '45000'; END IF;
        SELECT internal_max_marks, external_max_marks, passing_marks INTO v_cc FROM curriculum_course WHERE curriculum_course_id = v_reg.curriculum_course_id;
        IF v_cc.internal_max_marks + v_cc.external_max_marks <= 0 THEN RAISE EXCEPTION 'The curriculum course has no maximum marks defined' USING ERRCODE = '45000'; END IF;
        IF p_internal > v_cc.internal_max_marks THEN RAISE EXCEPTION 'Internal marks (%) exceed the maximum (%)', p_internal, v_cc.internal_max_marks USING ERRCODE = '45000'; END IF;
        IF p_external > v_cc.external_max_marks THEN RAISE EXCEPTION 'External marks (%) exceed the maximum (%)', p_external, v_cc.external_max_marks USING ERRCODE = '45000'; END IF;
        v_total := p_internal + p_external;
        v_pct := round(100.0 * v_total / (v_cc.internal_max_marks + v_cc.external_max_marks), 2);
        SELECT grade_scale_id INTO v_scale FROM grade_scale WHERE is_active AND effective_from <= current_date AND (effective_to IS NULL OR effective_to >= current_date)
         ORDER BY effective_from DESC, grade_scale_id DESC LIMIT 1;
        IF v_scale IS NULL THEN RAISE EXCEPTION 'No active grade scale is defined' USING ERRCODE = '45000'; END IF;
        SELECT grade_letter, grade_point, result_status INTO v_rule FROM grade_rule WHERE grade_scale_id = v_scale AND v_pct >= minimum_percentage AND v_pct <= maximum_percentage
         ORDER BY minimum_percentage DESC LIMIT 1;
        IF v_rule IS NULL THEN RAISE EXCEPTION 'No grade rule in the active scale covers % percent', v_pct USING ERRCODE = '45000'; END IF;
        v_letter := v_rule.grade_letter; v_point := v_rule.grade_point; v_status := v_rule.result_status;
        IF v_cc.passing_marks IS NOT NULL AND v_total < v_cc.passing_marks THEN v_status := 'FAIL'; END IF;
        IF v_status = 'PASS' THEN v_earned := COALESCE(v_credits, 0); END IF;
    END IF;

    INSERT INTO student_course_result (course_registration_id, attempt_number, internal_marks, external_marks, total_marks, grade_letter, grade_point, credits_earned, result_status, result_date, remarks)
    VALUES (p_course_registration_id, p_attempt, CASE WHEN p_status IS NULL THEN p_internal END, CASE WHEN p_status IS NULL THEN p_external END, v_total, v_letter, v_point, v_earned, v_status, current_date, NULLIF(btrim(p_remarks), ''))
    ON CONFLICT (course_registration_id, attempt_number)
    DO UPDATE SET internal_marks = EXCLUDED.internal_marks, external_marks = EXCLUDED.external_marks, total_marks = EXCLUDED.total_marks, grade_letter = EXCLUDED.grade_letter,
                  grade_point = EXCLUDED.grade_point, credits_earned = EXCLUDED.credits_earned, result_status = EXCLUDED.result_status, result_date = EXCLUDED.result_date, remarks = EXCLUDED.remarks
    RETURNING student_course_result_id INTO v_id;
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.section_delete(p_kind text, p_parent_id bigint, p_section text, p_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE d record; v_before jsonb;
BEGIN
    SELECT * INTO d FROM sims_private.section_def(p_kind, p_section);
    IF d.tbl IS NULL THEN RAISE EXCEPTION 'Unknown section' USING ERRCODE = '22023'; END IF;
    IF NOT sims_private.section_can(p_kind, d.perm_prefix, 'DELETE', p_parent_id) THEN RAISE EXCEPTION 'Not authorised (%.DELETE)', d.perm_prefix USING ERRCODE = '42501'; END IF;
    EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE t.%I = $1 AND t.%I = $2', d.tbl, d.pk_col, d.parent_col) INTO v_before USING p_id, p_parent_id;
    IF v_before IS NULL THEN RAISE EXCEPTION 'Unknown row' USING ERRCODE = '22023'; END IF;
    BEGIN
        EXECUTE format('DELETE FROM public.%I WHERE %I = $1', d.tbl, d.pk_col) USING p_id;
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'This row is still in use and cannot be deleted' USING ERRCODE = '45000';
    END;
    PERFORM sims_private.audit_manual(d.module_code, 'DELETE', d.tbl, p_id, v_before, NULL);
END $function$;

CREATE OR REPLACE FUNCTION public.staff_activity_delete(p_activity_id bigint, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a staff_activity%ROWTYPE; v_reason text := NULLIF(btrim(p_reason), '');
BEGIN
    SELECT * INTO a FROM staff_activity WHERE staff_activity_id = p_activity_id AND deleted_at IS NULL FOR UPDATE;
    IF a.staff_activity_id IS NULL OR sims_private.staff_actor(a.employee_id, 'STAFF_PROFILE.STAFF_ACTIVITY.DELETE') IS NULL THEN RAISE EXCEPTION 'Not authorised (STAFF_PROFILE.STAFF_ACTIVITY.DELETE) or unknown record' USING ERRCODE = '42501'; END IF;
    IF a.approval_status_id NOT IN (sims_private.astatus('DRAFT'), sims_private.astatus('REJECTED')) THEN RAISE EXCEPTION 'Only a draft or rejected record can be deleted' USING ERRCODE = '45000'; END IF;
    IF length(COALESCE(v_reason, '')) > 1000 THEN RAISE EXCEPTION 'The reason is limited to 1000 characters' USING ERRCODE = '22023'; END IF;
    UPDATE staff_activity SET deleted_at = now(), deleted_by_user_id = sims_private.current_user_id(), deletion_reason = v_reason WHERE staff_activity_id = p_activity_id;
END $function$;

CREATE OR REPLACE FUNCTION public.staff_activity_review(p_activity_id bigint, p_step text, p_decision text, p_remarks text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a staff_activity%ROWTYPE; v_remarks text := NULLIF(btrim(p_remarks), ''); v_perm text;
BEGIN
    IF p_step NOT IN ('VERIFY', 'APPROVE') THEN RAISE EXCEPTION 'The step must be VERIFY or APPROVE' USING ERRCODE = '22023'; END IF;
    v_perm := 'STAFF_PROFILE.STAFF_ACTIVITY.' || p_step;
    SELECT * INTO a FROM staff_activity WHERE staff_activity_id = p_activity_id AND deleted_at IS NULL FOR UPDATE;
    IF a.staff_activity_id IS NULL OR NOT sims_private.can_employee(ARRAY[v_perm]::text[], a.employee_id, true) THEN RAISE EXCEPTION 'Not authorised (%) or unknown record', v_perm USING ERRCODE = '42501'; END IF;
    IF COALESCE(a.employee_id = sims_private.current_employee_id(), false) THEN RAISE EXCEPTION 'You cannot review your own record' USING ERRCODE = '45000'; END IF;
    IF length(COALESCE(v_remarks, '')) > 1000 THEN RAISE EXCEPTION 'Remarks are limited to 1000 characters' USING ERRCODE = '22023'; END IF;
    IF p_step = 'VERIFY' THEN
        IF p_decision NOT IN ('VERIFIED', 'NEEDS_CORRECTION', 'REJECTED') THEN RAISE EXCEPTION 'The decision must be VERIFIED, NEEDS_CORRECTION or REJECTED' USING ERRCODE = '22023'; END IF;
        IF p_decision <> 'VERIFIED' AND v_remarks IS NULL THEN RAISE EXCEPTION 'Remarks are required unless the record is verified' USING ERRCODE = '22023'; END IF;
        IF a.verification_status_id = sims_private.vstatus(p_decision) THEN RETURN; END IF; -- idempotent replay
        IF a.approval_status_id <> sims_private.astatus('SUBMITTED') OR a.verification_status_id <> sims_private.vstatus('PENDING') THEN RAISE EXCEPTION 'Only a submitted record awaiting verification can be verified' USING ERRCODE = '45000'; END IF;
        UPDATE staff_activity SET verification_status_id = sims_private.vstatus(p_decision), verified_by_user_id = sims_private.current_user_id(), verified_at = now(), verification_remarks = v_remarks,
            approval_status_id = CASE p_decision WHEN 'VERIFIED' THEN sims_private.astatus('UNDER_REVIEW') WHEN 'NEEDS_CORRECTION' THEN sims_private.astatus('DRAFT') ELSE sims_private.astatus('REJECTED') END,
            rejection_reason = CASE WHEN p_decision = 'REJECTED' THEN v_remarks END, updated_at = now() WHERE staff_activity_id = p_activity_id;
    ELSE
        IF p_decision NOT IN ('APPROVED', 'REJECTED') THEN RAISE EXCEPTION 'The decision must be APPROVED or REJECTED' USING ERRCODE = '22023'; END IF;
        IF p_decision = 'REJECTED' AND v_remarks IS NULL THEN RAISE EXCEPTION 'Remarks are required to reject a record' USING ERRCODE = '22023'; END IF;
        IF a.approval_status_id = sims_private.astatus(p_decision) THEN RETURN; END IF; -- idempotent replay
        IF a.approval_status_id <> sims_private.astatus('UNDER_REVIEW') OR a.verification_status_id <> sims_private.vstatus('VERIFIED') THEN RAISE EXCEPTION 'Only a verified record under review can be approved or rejected' USING ERRCODE = '45000'; END IF;
        UPDATE staff_activity SET approval_status_id = sims_private.astatus(p_decision), approved_by_user_id = sims_private.current_user_id(), approved_at = now(), approval_remarks = v_remarks,
            rejection_reason = CASE WHEN p_decision = 'REJECTED' THEN v_remarks END, updated_at = now() WHERE staff_activity_id = p_activity_id;
    END IF;
END $function$;

CREATE OR REPLACE FUNCTION public.staff_activity_save(p_activity_id bigint, p_employee_id bigint, p jsonb, p_detail jsonb DEFAULT NULL::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_employee bigint; a staff_activity%ROWTYPE; v_actor text; v_id bigint; v_emp record; v_code text; v_table text; v_old_table text; v_exists boolean;
    v_type integer := NULLIF(p ->> 'activity_type_id', '')::integer;
    v_title text := NULLIF(btrim(p ->> 'activity_title'), '');
    v_start date := NULLIF(p ->> 'start_date', '')::date; v_end date := NULLIF(p ->> 'end_date', '')::date;
BEGIN
    IF p IS NULL OR jsonb_typeof(p) <> 'object' THEN RAISE EXCEPTION 'p must be an object' USING ERRCODE = '22023'; END IF;
    IF p_activity_id IS NOT NULL THEN
        SELECT * INTO a FROM staff_activity WHERE staff_activity_id = p_activity_id AND deleted_at IS NULL FOR UPDATE;
        IF a.staff_activity_id IS NULL THEN RAISE EXCEPTION 'Not authorised (STAFF_PROFILE.STAFF_ACTIVITY.UPDATE) or unknown record' USING ERRCODE = '42501'; END IF;
        v_employee := a.employee_id;
        v_actor := sims_private.staff_actor(v_employee, 'STAFF_PROFILE.STAFF_ACTIVITY.UPDATE');
    ELSE
        v_employee := COALESCE(p_employee_id, sims_private.current_employee_id());
        v_actor := CASE WHEN v_employee IS NULL THEN NULL ELSE sims_private.staff_actor(v_employee, 'STAFF_PROFILE.STAFF_ACTIVITY.CREATE') END;
    END IF;
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Not authorised (STAFF_PROFILE.STAFF_ACTIVITY.CREATE / UPDATE) or unknown record' USING ERRCODE = '42501'; END IF;
    IF p_activity_id IS NOT NULL AND a.approval_status_id <> sims_private.astatus('DRAFT') THEN RAISE EXCEPTION 'Only a draft record can be edited' USING ERRCODE = '45000'; END IF;
    IF v_title IS NULL OR length(v_title) > 500 THEN RAISE EXCEPTION 'The title is required (at most 500 characters)' USING ERRCODE = '22023'; END IF;
    SELECT activity_type_code INTO v_code FROM activity_type WHERE activity_type_id = v_type AND is_active;
    IF v_code IS NULL THEN RAISE EXCEPTION 'Choose an active activity type' USING ERRCODE = '22023'; END IF;
    IF v_start IS NOT NULL AND v_end IS NOT NULL AND v_end < v_start THEN RAISE EXCEPTION 'The end date cannot be before the start date' USING ERRCODE = '22023'; END IF;
    IF NULLIF(p ->> 'academic_year_id', '') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM academic_year WHERE academic_year_id = (p ->> 'academic_year_id')::integer) THEN RAISE EXCEPTION 'Unknown academic year' USING ERRCODE = '22023'; END IF;
    IF length(COALESCE(p ->> 'description', '')) > 5000 OR length(COALESCE(p ->> 'outcomes', '')) > 5000 THEN RAISE EXCEPTION 'Text is too long' USING ERRCODE = '22023'; END IF;
    SELECT e.institution_id, (SELECT ea.campus_id FROM employee_assignment ea WHERE ea.employee_id = e.employee_id AND ea.end_date IS NULL ORDER BY ea.is_primary DESC, ea.employee_assignment_id LIMIT 1) AS campus_id,
           (SELECT ea.department_id FROM employee_assignment ea WHERE ea.employee_id = e.employee_id AND ea.end_date IS NULL ORDER BY ea.is_primary DESC, ea.employee_assignment_id LIMIT 1) AS department_id
      INTO v_emp FROM employee e WHERE e.employee_id = v_employee;
    IF v_emp.institution_id IS NULL THEN RAISE EXCEPTION 'Unknown employee' USING ERRCODE = '22023'; END IF;
    v_table := sims_private.staff_detail_table(v_code);

    IF p_activity_id IS NULL THEN
        INSERT INTO staff_activity (employee_id, activity_type_id, academic_year_id, institution_id, campus_id, department_id, participation_level_id, primary_role_type_id, activity_title, start_date, end_date,
                                    description, outcomes, verification_status_id, approval_status_id, created_by_user_id)
        VALUES (v_employee, v_type, NULLIF(p ->> 'academic_year_id', '')::integer, v_emp.institution_id, v_emp.campus_id, v_emp.department_id, NULLIF(p ->> 'participation_level_id', '')::integer,
                NULLIF(p ->> 'primary_role_type_id', '')::integer, v_title, v_start, v_end, NULLIF(btrim(p ->> 'description'), ''), NULLIF(btrim(p ->> 'outcomes'), ''),
                sims_private.vstatus('NOT_SUBMITTED'), sims_private.astatus('DRAFT'), sims_private.current_user_id()) RETURNING staff_activity_id INTO v_id;
        IF v_table IS NOT NULL THEN PERFORM sims_private.write_detail(v_table, 'staff_activity_id', v_id, COALESCE(p_detail, '{}'::jsonb), true); END IF;
        RETURN v_id;
    END IF;

    SELECT sims_private.staff_detail_table(t.activity_type_code) INTO v_old_table FROM activity_type t WHERE t.activity_type_id = a.activity_type_id;
    UPDATE staff_activity SET activity_type_id = v_type, academic_year_id = NULLIF(p ->> 'academic_year_id', '')::integer, participation_level_id = NULLIF(p ->> 'participation_level_id', '')::integer,
        primary_role_type_id = NULLIF(p ->> 'primary_role_type_id', '')::integer, activity_title = v_title, start_date = v_start, end_date = v_end, description = NULLIF(btrim(p ->> 'description'), ''),
        outcomes = NULLIF(btrim(p ->> 'outcomes'), ''), updated_by_user_id = sims_private.current_user_id(), updated_at = now() WHERE staff_activity_id = p_activity_id;
    IF v_old_table IS DISTINCT FROM v_table THEN
        IF v_old_table IS NOT NULL THEN EXECUTE format('DELETE FROM public.%I WHERE staff_activity_id = $1', v_old_table) USING p_activity_id; END IF;
        IF v_table IS NOT NULL THEN PERFORM sims_private.write_detail(v_table, 'staff_activity_id', p_activity_id, COALESCE(p_detail, '{}'::jsonb), true); END IF;
    ELSIF v_table IS NOT NULL AND p_detail IS NOT NULL THEN
        EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I WHERE staff_activity_id = $1)', v_table) INTO v_exists USING p_activity_id;
        PERFORM sims_private.write_detail(v_table, 'staff_activity_id', p_activity_id, p_detail, NOT v_exists);
    END IF;
    RETURN p_activity_id;
END $function$;

CREATE OR REPLACE FUNCTION public.staff_activity_submit(p_activity_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a staff_activity%ROWTYPE; r record; v_count integer;
BEGIN
    SELECT * INTO a FROM staff_activity WHERE staff_activity_id = p_activity_id AND deleted_at IS NULL FOR UPDATE;
    IF a.staff_activity_id IS NULL OR sims_private.staff_actor(a.employee_id, 'STAFF_PROFILE.STAFF_ACTIVITY.UPDATE') IS NULL THEN RAISE EXCEPTION 'Not authorised (STAFF_PROFILE.STAFF_ACTIVITY.UPDATE) or unknown record' USING ERRCODE = '42501'; END IF;
    IF a.approval_status_id = sims_private.astatus('SUBMITTED') THEN RETURN; END IF; -- idempotent replay
    IF a.approval_status_id <> sims_private.astatus('DRAFT') THEN RAISE EXCEPTION 'Only a draft record can be submitted' USING ERRCODE = '45000'; END IF;
    IF a.start_date IS NULL THEN RAISE EXCEPTION 'The start date is required before submitting' USING ERRCODE = '45000'; END IF;
    FOR r IN SELECT q.evidence_type_id, q.minimum_files, e.evidence_type_name FROM activity_evidence_requirement q JOIN evidence_type e ON e.evidence_type_id = q.evidence_type_id
             WHERE q.activity_type_id = a.activity_type_id AND q.is_active AND q.is_mandatory AND (q.valid_from IS NULL OR q.valid_from <= CURRENT_DATE) AND (q.valid_to IS NULL OR q.valid_to >= CURRENT_DATE) LOOP
        SELECT count(*) INTO v_count FROM evidence_document ev WHERE ev.staff_activity_id = p_activity_id AND ev.evidence_type_id = r.evidence_type_id AND ev.is_active AND ev.deleted_at IS NULL;
        IF v_count < GREATEST(r.minimum_files, 1) THEN RAISE EXCEPTION 'Evidence required: %', r.evidence_type_name USING ERRCODE = '45000'; END IF;
    END LOOP;
    UPDATE staff_activity SET approval_status_id = sims_private.astatus('SUBMITTED'), verification_status_id = sims_private.vstatus('PENDING'), rejection_reason = NULL, updated_at = now() WHERE staff_activity_id = p_activity_id;
END $function$;

CREATE OR REPLACE FUNCTION public.staff_contributor_add(p_activity_id bigint, p_employee_id bigint, p_external_name text, p_external_email text, p_affiliation text, p_role_type_id integer, p_is_corresponding boolean DEFAULT false, p_details text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a staff_activity%ROWTYPE; v_id bigint; v_name text := NULLIF(btrim(p_external_name), '');
BEGIN
    SELECT * INTO a FROM staff_activity WHERE staff_activity_id = p_activity_id AND deleted_at IS NULL FOR UPDATE;
    IF a.staff_activity_id IS NULL OR sims_private.staff_actor(a.employee_id, 'STAFF_PROFILE.STAFF_ACTIVITY.UPDATE') IS NULL THEN RAISE EXCEPTION 'Not authorised (STAFF_PROFILE.STAFF_ACTIVITY.UPDATE) or unknown record' USING ERRCODE = '42501'; END IF;
    IF a.approval_status_id <> sims_private.astatus('DRAFT') THEN RAISE EXCEPTION 'Only a draft record can be changed' USING ERRCODE = '45000'; END IF;
    IF (p_employee_id IS NULL) = (v_name IS NULL) THEN RAISE EXCEPTION 'Give either an employee or an external person' USING ERRCODE = '22023'; END IF;
    IF p_employee_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM employee WHERE employee_id = p_employee_id) THEN RAISE EXCEPTION 'Unknown employee' USING ERRCODE = '22023'; END IF;
    IF p_role_type_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM role_type WHERE role_type_id = p_role_type_id) THEN RAISE EXCEPTION 'Unknown role' USING ERRCODE = '22023'; END IF;
    IF length(COALESCE(v_name, '')) > 250 OR length(COALESCE(p_external_email, '')) > 254 OR length(COALESCE(p_affiliation, '')) > 500 OR length(COALESCE(p_details, '')) > 1000 THEN RAISE EXCEPTION 'Text is too long' USING ERRCODE = '22023'; END IF;
    IF p_employee_id IS NOT NULL AND EXISTS (SELECT 1 FROM staff_activity_contributor WHERE staff_activity_id = p_activity_id AND employee_id = p_employee_id AND role_type_id IS NOT DISTINCT FROM p_role_type_id) THEN
        RAISE EXCEPTION 'That employee is already listed with this role' USING ERRCODE = '23505';
    END IF;
    INSERT INTO staff_activity_contributor (staff_activity_id, employee_id, external_person_name, external_person_email, affiliation_text, role_type_id, is_corresponding_author, contribution_details, contributor_sequence)
    VALUES (p_activity_id, p_employee_id, v_name, NULLIF(btrim(p_external_email), ''), NULLIF(btrim(p_affiliation), ''), p_role_type_id, COALESCE(p_is_corresponding, false), NULLIF(btrim(p_details), ''),
            (SELECT COALESCE(max(contributor_sequence), 0) + 1 FROM staff_activity_contributor WHERE staff_activity_id = p_activity_id)) RETURNING staff_activity_contributor_id INTO v_id;
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.staff_contributor_remove(p_contributor_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a staff_activity%ROWTYPE; c record;
BEGIN
    SELECT * INTO c FROM staff_activity_contributor WHERE staff_activity_contributor_id = p_contributor_id;
    SELECT * INTO a FROM staff_activity WHERE staff_activity_id = c.staff_activity_id AND deleted_at IS NULL FOR UPDATE;
    IF a.staff_activity_id IS NULL OR sims_private.staff_actor(a.employee_id, 'STAFF_PROFILE.STAFF_ACTIVITY.UPDATE') IS NULL THEN RAISE EXCEPTION 'Not authorised (STAFF_PROFILE.STAFF_ACTIVITY.UPDATE) or unknown contributor' USING ERRCODE = '42501'; END IF;
    IF a.approval_status_id <> sims_private.astatus('DRAFT') THEN RAISE EXCEPTION 'Only a draft record can be changed' USING ERRCODE = '45000'; END IF;
    DELETE FROM staff_activity_contributor WHERE staff_activity_contributor_id = p_contributor_id;
END $function$;

CREATE OR REPLACE FUNCTION public.staff_evidence_add(p_activity_id bigint, p_document_type_id integer, p_evidence_type_id integer, p_title text, p_issue_date date, p_issuing_authority text, p_certificate_number text, p_storage_key text, p_file_name text, p_mime text, p_size bigint, p_checksum text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a staff_activity%ROWTYPE; v_ext text; v_file bigint; v_ev bigint; v_title text := NULLIF(btrim(p_title), '');
BEGIN
    SELECT * INTO a FROM staff_activity WHERE staff_activity_id = p_activity_id AND deleted_at IS NULL FOR UPDATE;
    IF a.staff_activity_id IS NULL OR sims_private.staff_actor(a.employee_id, 'STAFF_PROFILE.STAFF_EVIDENCE.CREATE') IS NULL THEN RAISE EXCEPTION 'Not authorised (STAFF_PROFILE.STAFF_EVIDENCE.CREATE) or unknown record' USING ERRCODE = '42501'; END IF;
    IF a.approval_status_id <> sims_private.astatus('DRAFT') THEN RAISE EXCEPTION 'Evidence can only be added to a draft record' USING ERRCODE = '45000'; END IF;
    IF v_title IS NULL OR length(v_title) > 500 THEN RAISE EXCEPTION 'The title is required (at most 500 characters)' USING ERRCODE = '22023'; END IF;
    IF NOT EXISTS (SELECT 1 FROM document_type WHERE document_type_id = p_document_type_id AND is_active) THEN RAISE EXCEPTION 'Choose an active document type' USING ERRCODE = '22023'; END IF;
    IF p_evidence_type_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM evidence_type WHERE evidence_type_id = p_evidence_type_id AND is_active) THEN RAISE EXCEPTION 'Choose an active evidence type' USING ERRCODE = '22023'; END IF;
    IF length(COALESCE(p_issuing_authority, '')) > 300 OR length(COALESCE(p_certificate_number, '')) > 150 THEN RAISE EXCEPTION 'Text is too long' USING ERRCODE = '22023'; END IF;
    v_ext := sims_private.check_employee_upload(a.employee_id, p_storage_key, p_file_name, p_mime, p_size, p_checksum);
    INSERT INTO file_object (storage_provider, storage_key, original_file_name, mime_type, file_size_bytes, checksum_sha256, stored_file_name, file_extension, confidentiality_level, uploaded_by_user_id)
    VALUES ('supabase-storage', p_storage_key, btrim(p_file_name), p_mime, p_size, lower(p_checksum), split_part(p_storage_key, '/', 3), v_ext, 'CONFIDENTIAL', sims_private.current_user_id()) RETURNING file_object_id INTO v_file;
    INSERT INTO evidence_document (staff_activity_id, document_type_id, evidence_type_id, confidentiality_level_id, document_title, document_issue_date, issuing_authority, certificate_document_number,
        verification_status_id, approval_status_id, created_by_user_id)
    VALUES (p_activity_id, p_document_type_id, p_evidence_type_id, (SELECT confidentiality_level_id FROM confidentiality_level WHERE level_code = 'CONFIDENTIAL'), v_title, p_issue_date, NULLIF(btrim(p_issuing_authority), ''),
            NULLIF(btrim(p_certificate_number), ''), sims_private.vstatus('PENDING'), sims_private.astatus('DRAFT'), sims_private.current_user_id()) RETURNING evidence_document_id INTO v_ev;
    INSERT INTO evidence_document_version (evidence_document_id, version_number, file_object_id, uploaded_by_user_id) VALUES (v_ev, 1, v_file, sims_private.current_user_id());
    INSERT INTO evidence_document_audit (evidence_document_id, action_code, performed_by_user_id, after_values) VALUES (v_ev, 'UPLOAD', sims_private.current_user_id(), jsonb_build_object('file_name', btrim(p_file_name), 'version', 1));
    RETURN v_ev;
END $function$;

CREATE OR REPLACE FUNCTION public.staff_evidence_delete(p_evidence_id bigint, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE ev evidence_document%ROWTYPE; a staff_activity%ROWTYPE;
BEGIN
    SELECT * INTO ev FROM evidence_document WHERE evidence_document_id = p_evidence_id AND deleted_at IS NULL FOR UPDATE;
    SELECT * INTO a FROM staff_activity WHERE staff_activity_id = ev.staff_activity_id AND deleted_at IS NULL;
    IF ev.evidence_document_id IS NULL OR a.staff_activity_id IS NULL OR sims_private.staff_actor(a.employee_id, 'STAFF_PROFILE.STAFF_EVIDENCE.DELETE') IS NULL THEN
        RAISE EXCEPTION 'Not authorised (STAFF_PROFILE.STAFF_EVIDENCE.DELETE) or unknown evidence' USING ERRCODE = '42501';
    END IF;
    IF a.approval_status_id <> sims_private.astatus('DRAFT') THEN RAISE EXCEPTION 'Evidence can only be removed from a draft record' USING ERRCODE = '45000'; END IF;
    UPDATE evidence_document SET deleted_at = now(), deleted_by_user_id = sims_private.current_user_id(), deletion_reason = NULLIF(btrim(p_reason), ''), is_active = false WHERE evidence_document_id = p_evidence_id;
    INSERT INTO evidence_document_audit (evidence_document_id, action_code, performed_by_user_id, remarks) VALUES (p_evidence_id, 'SOFT_DELETE', sims_private.current_user_id(), NULLIF(btrim(p_reason), ''));
END $function$;

CREATE OR REPLACE FUNCTION public.staff_evidence_download_info(p_evidence_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE d record;
BEGIN
    SELECT a.employee_id, f.storage_key, f.original_file_name, f.mime_type, v.evidence_document_version_id INTO d
    FROM evidence_document ev JOIN staff_activity a ON a.staff_activity_id = ev.staff_activity_id
    JOIN evidence_document_version v ON v.evidence_document_id = ev.evidence_document_id AND v.is_current JOIN file_object f ON f.file_object_id = v.file_object_id
    WHERE ev.evidence_document_id = p_evidence_id AND ev.deleted_at IS NULL AND a.deleted_at IS NULL;
    IF d.employee_id IS NULL OR NOT (COALESCE(d.employee_id = sims_private.current_employee_id(), false) OR sims_private.can_employee(ARRAY['STAFF_PROFILE.STAFF_EVIDENCE.READ']::text[], d.employee_id, false)) THEN
        RAISE EXCEPTION 'Not authorised (STAFF_PROFILE.STAFF_EVIDENCE.READ) or unknown evidence' USING ERRCODE = '42501';
    END IF;
    INSERT INTO evidence_document_audit (evidence_document_id, evidence_document_version_id, action_code, performed_by_user_id) VALUES (p_evidence_id, d.evidence_document_version_id, 'DOWNLOAD', sims_private.current_user_id());
    RETURN jsonb_build_object('storage_key', d.storage_key, 'file_name', d.original_file_name, 'mime_type', d.mime_type);
END $function$;

CREATE OR REPLACE FUNCTION public.staff_evidence_replace(p_evidence_id bigint, p_reason text, p_storage_key text, p_file_name text, p_mime text, p_size bigint, p_checksum text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE ev evidence_document%ROWTYPE; a staff_activity%ROWTYPE; v_ext text; v_file bigint; v_ver integer;
BEGIN
    SELECT * INTO ev FROM evidence_document WHERE evidence_document_id = p_evidence_id AND deleted_at IS NULL FOR UPDATE;
    SELECT * INTO a FROM staff_activity WHERE staff_activity_id = ev.staff_activity_id AND deleted_at IS NULL;
    IF ev.evidence_document_id IS NULL OR a.staff_activity_id IS NULL OR sims_private.staff_actor(a.employee_id, 'STAFF_PROFILE.STAFF_EVIDENCE.UPDATE') IS NULL THEN
        RAISE EXCEPTION 'Not authorised (STAFF_PROFILE.STAFF_EVIDENCE.UPDATE) or unknown evidence' USING ERRCODE = '42501';
    END IF;
    IF a.approval_status_id <> sims_private.astatus('DRAFT') THEN RAISE EXCEPTION 'Evidence can only be replaced on a draft record' USING ERRCODE = '45000'; END IF;
    IF length(COALESCE(p_reason, '')) > 1000 THEN RAISE EXCEPTION 'The reason is limited to 1000 characters' USING ERRCODE = '22023'; END IF;
    v_ext := sims_private.check_employee_upload(a.employee_id, p_storage_key, p_file_name, p_mime, p_size, p_checksum);
    INSERT INTO file_object (storage_provider, storage_key, original_file_name, mime_type, file_size_bytes, checksum_sha256, stored_file_name, file_extension, confidentiality_level, uploaded_by_user_id)
    VALUES ('supabase-storage', p_storage_key, btrim(p_file_name), p_mime, p_size, lower(p_checksum), split_part(p_storage_key, '/', 3), v_ext, 'CONFIDENTIAL', sims_private.current_user_id()) RETURNING file_object_id INTO v_file;
    v_ver := ev.current_version_number + 1;
    UPDATE evidence_document_version SET is_current = false WHERE evidence_document_id = p_evidence_id AND is_current;
    INSERT INTO evidence_document_version (evidence_document_id, version_number, file_object_id, change_reason, uploaded_by_user_id) VALUES (p_evidence_id, v_ver, v_file, NULLIF(btrim(p_reason), ''), sims_private.current_user_id());
    UPDATE evidence_document SET current_version_number = v_ver, updated_by_user_id = sims_private.current_user_id(), updated_at = now() WHERE evidence_document_id = p_evidence_id;
    INSERT INTO evidence_document_audit (evidence_document_id, action_code, performed_by_user_id, before_values, after_values, remarks)
    VALUES (p_evidence_id, 'REPLACE', sims_private.current_user_id(), jsonb_build_object('version', ev.current_version_number), jsonb_build_object('version', v_ver, 'file_name', btrim(p_file_name)), NULLIF(btrim(p_reason), ''));
    RETURN v_ver;
END $function$;

CREATE OR REPLACE FUNCTION public.staff_indexing_delete(p_activity_id bigint, p_agency_id integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_table text := sims_private.indexing_table(p_activity_id); v_before jsonb;
BEGIN
    IF v_table IS NULL OR NOT sims_private.activity_child_ok(p_activity_id, CASE v_table WHEN 'journal_publication_indexing' THEN 'journal_publication' ELSE 'conference_activity' END, 'STAFF_PROFILE.STAFF_ACTIVITY', 'UPDATE') THEN
        RAISE EXCEPTION 'Not authorised (STAFF_PROFILE.STAFF_ACTIVITY.UPDATE) or the record cannot be changed now' USING ERRCODE = '42501';
    END IF;
    EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE t.staff_activity_id = $1 AND t.indexing_agency_id = $2', v_table) INTO v_before USING p_activity_id, p_agency_id;
    IF v_before IS NULL THEN RAISE EXCEPTION 'Unknown row' USING ERRCODE = '22023'; END IF;
    EXECUTE format('DELETE FROM public.%I WHERE staff_activity_id = $1 AND indexing_agency_id = $2', v_table) USING p_activity_id, p_agency_id;
    PERFORM sims_private.audit_manual('STAFF_PROFILE', 'DELETE', v_table, p_activity_id, v_before, NULL);
END $function$;

CREATE OR REPLACE FUNCTION public.staff_indexing_save(p_activity_id bigint, p_agency_id integer, p_status text, p_year integer DEFAULT NULL::integer, p_url text DEFAULT NULL::text, p_remarks text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_table text := sims_private.indexing_table(p_activity_id); v_before jsonb; v_after jsonb; v_parent text;
BEGIN
    v_parent := CASE v_table WHEN 'journal_publication_indexing' THEN 'journal_publication' ELSE 'conference_activity' END;
    IF v_table IS NULL OR NOT sims_private.activity_child_ok(p_activity_id, v_parent, 'STAFF_PROFILE.STAFF_ACTIVITY', 'UPDATE') THEN
        RAISE EXCEPTION 'Not authorised (STAFF_PROFILE.STAFF_ACTIVITY.UPDATE) or the record cannot be changed now' USING ERRCODE = '42501';
    END IF;
    IF p_status NOT IN ('CLAIMED', 'VERIFIED', 'DISCONTINUED', 'NOT_INDEXED') THEN RAISE EXCEPTION 'Unknown indexing status' USING ERRCODE = '22023'; END IF;
    IF NOT EXISTS (SELECT 1 FROM indexing_agency WHERE indexing_agency_id = p_agency_id AND is_active) THEN RAISE EXCEPTION 'Choose an active indexing agency' USING ERRCODE = '22023'; END IF;
    IF p_year IS NOT NULL AND (p_year < 1900 OR p_year > extract(year FROM now())::integer + 1) THEN RAISE EXCEPTION 'Enter a valid year' USING ERRCODE = '22023'; END IF;
    IF length(COALESCE(p_url, '')) > 1000 OR (p_url IS NOT NULL AND p_url <> '' AND p_url !~* '^https?://') THEN RAISE EXCEPTION 'The link must start with http:// or https:// (at most 1000 characters)' USING ERRCODE = '22023'; END IF;
    IF length(COALESCE(p_remarks, '')) > 500 THEN RAISE EXCEPTION 'Remarks are limited to 500 characters' USING ERRCODE = '22023'; END IF;
    -- 'VERIFIED' is a claim checked by someone else: only staff (not the owner) may set it
    IF p_status = 'VERIFIED' AND sims_private.staff_actor((SELECT employee_id FROM staff_activity WHERE staff_activity_id = p_activity_id), 'STAFF_PROFILE.STAFF_ACTIVITY.VERIFY') IS DISTINCT FROM 'staff' THEN
        RAISE EXCEPTION 'Only a verifier can mark an indexing as verified' USING ERRCODE = '42501';
    END IF;
    EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE t.staff_activity_id = $1 AND t.indexing_agency_id = $2', v_table) INTO v_before USING p_activity_id, p_agency_id;
    IF v_table = 'journal_publication_indexing' THEN
        INSERT INTO journal_publication_indexing (staff_activity_id, indexing_agency_id, indexing_status, indexed_year, source_url, remarks) VALUES (p_activity_id, p_agency_id, p_status, p_year, NULLIF(p_url, ''), NULLIF(btrim(p_remarks), ''))
        ON CONFLICT (staff_activity_id, indexing_agency_id) DO UPDATE SET indexing_status = EXCLUDED.indexing_status, indexed_year = EXCLUDED.indexed_year, source_url = EXCLUDED.source_url, remarks = EXCLUDED.remarks;
    ELSE
        INSERT INTO conference_activity_indexing (staff_activity_id, indexing_agency_id, indexing_status, source_url, remarks) VALUES (p_activity_id, p_agency_id, p_status, NULLIF(p_url, ''), NULLIF(btrim(p_remarks), ''))
        ON CONFLICT (staff_activity_id, indexing_agency_id) DO UPDATE SET indexing_status = EXCLUDED.indexing_status, source_url = EXCLUDED.source_url, remarks = EXCLUDED.remarks;
    END IF;
    EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE t.staff_activity_id = $1 AND t.indexing_agency_id = $2', v_table) INTO v_after USING p_activity_id, p_agency_id;
    PERFORM sims_private.audit_manual('STAFF_PROFILE', CASE WHEN v_before IS NULL THEN 'INSERT' ELSE 'UPDATE' END, v_table, p_activity_id, v_before, v_after);
END $function$;

CREATE OR REPLACE FUNCTION public.staff_lookup_add(p_table text, p jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_pk text; v_id bigint;
BEGIN
    IF sims_private.current_employee_id() IS NULL AND NOT sims_private.can_global(ARRAY['STAFF_PROFILE.STAFF_ACTIVITY.CREATE']::text[]) THEN
        RAISE EXCEPTION 'Not authorised (STAFF_PROFILE.STAFF_ACTIVITY.CREATE)' USING ERRCODE = '42501';
    END IF;
    IF p_table <> ALL (sims_private.staff_lookup_tables()) THEN RAISE EXCEPTION 'That list cannot be extended here' USING ERRCODE = '22023'; END IF;
    SELECT at.attname INTO v_pk FROM pg_constraint cp JOIN pg_attribute at ON at.attrelid = cp.conrelid AND at.attnum = cp.conkey[1] WHERE cp.contype = 'p' AND cp.conrelid = format('public.%I', p_table)::regclass;
    IF p IS NULL OR jsonb_typeof(p) <> 'object' THEN RAISE EXCEPTION 'The details must be an object' USING ERRCODE = '22023'; END IF;
    p := jsonb_strip_nulls(p) - v_pk;
    IF p = '{}'::jsonb THEN RAISE EXCEPTION 'Nothing to add' USING ERRCODE = '22023'; END IF;
    IF EXISTS (SELECT 1 FROM jsonb_object_keys(p) k WHERE NOT EXISTS (SELECT 1 FROM pg_attribute at WHERE at.attrelid = format('public.%I', p_table)::regclass AND at.attname = k AND at.attnum > 0 AND NOT at.attisdropped AND at.attgenerated = '')) THEN
        RAISE EXCEPTION 'Unknown field' USING ERRCODE = '22023';
    END IF;
    PERFORM sims_private.exec_dml(format('INSERT INTO public.%I (%s) SELECT %s FROM jsonb_populate_record(NULL::public.%I, $1)', p_table, (SELECT string_agg(quote_ident(k), ', ') FROM jsonb_object_keys(p) k),
                                         (SELECT string_agg(quote_ident(k), ', ') FROM jsonb_object_keys(p) k), p_table), p);
    EXECUTE format('SELECT max(%I)::bigint FROM public.%I', v_pk, p_table) INTO v_id;
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.student_activity_delete(p_activity_id bigint, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a record; v_reason text := NULLIF(btrim(p_reason), '');
BEGIN
    SELECT * INTO a FROM student_activity WHERE student_activity_id = p_activity_id AND deleted_at IS NULL FOR UPDATE;
    IF a.student_activity_id IS NULL OR (sims_private.activity_actor(a.student_id, 'STUDENT.STUDENT_ACTIVITY.DELETE') IS NULL) THEN RAISE EXCEPTION 'Not authorised (STUDENT.STUDENT_ACTIVITY.DELETE) or unknown activity' USING ERRCODE = '42501'; END IF;
    IF a.approval_status_id NOT IN (sims_private.astatus('DRAFT'), sims_private.astatus('REJECTED')) THEN RAISE EXCEPTION 'Only a draft or rejected activity can be deleted' USING ERRCODE = '45000'; END IF;
    IF length(COALESCE(v_reason, '')) > 1000 THEN RAISE EXCEPTION 'The reason is limited to 1000 characters' USING ERRCODE = '22023'; END IF;
    UPDATE student_activity SET deleted_at = now(), deleted_by_user_id = sims_private.current_user_id(), deletion_reason = v_reason WHERE student_activity_id = p_activity_id;
END $function$;

CREATE OR REPLACE FUNCTION public.student_activity_evidence_add(p_activity_id bigint, p_document_type_id integer, p_evidence_type_id integer, p_title text, p_issue_date date, p_issuing_authority text, p_certificate_number text, p_storage_key text, p_file_name text, p_mime text, p_size bigint, p_checksum text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a record; v_ext text; v_file bigint; v_ev bigint; v_title text := NULLIF(btrim(p_title), '');
BEGIN
    SELECT * INTO a FROM student_activity WHERE student_activity_id = p_activity_id AND deleted_at IS NULL FOR UPDATE;
    IF a.student_activity_id IS NULL OR sims_private.activity_actor(a.student_id, 'STUDENT.STUDENT_ACTIVITY_EVIDENCE.CREATE') IS NULL THEN RAISE EXCEPTION 'Not authorised (STUDENT.STUDENT_ACTIVITY_EVIDENCE.CREATE) or unknown activity' USING ERRCODE = '42501'; END IF;
    IF a.approval_status_id <> sims_private.astatus('DRAFT') THEN RAISE EXCEPTION 'Evidence can only be added to a draft activity' USING ERRCODE = '45000'; END IF;
    IF v_title IS NULL OR length(v_title) > 500 THEN RAISE EXCEPTION 'The title is required (at most 500 characters)' USING ERRCODE = '22023'; END IF;
    IF NOT EXISTS (SELECT 1 FROM document_type WHERE document_type_id = p_document_type_id AND is_active) THEN RAISE EXCEPTION 'Choose an active document type' USING ERRCODE = '22023'; END IF;
    IF p_evidence_type_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM evidence_type WHERE evidence_type_id = p_evidence_type_id AND is_active) THEN RAISE EXCEPTION 'Choose an active evidence type' USING ERRCODE = '22023'; END IF;
    IF length(COALESCE(p_issuing_authority, '')) > 300 OR length(COALESCE(p_certificate_number, '')) > 150 THEN RAISE EXCEPTION 'Text is too long' USING ERRCODE = '22023'; END IF;
    v_ext := sims_private.check_student_upload(a.student_id, p_storage_key, p_file_name, p_mime, p_size, p_checksum);
    INSERT INTO file_object (storage_provider, storage_key, original_file_name, mime_type, file_size_bytes, checksum_sha256, stored_file_name, file_extension, confidentiality_level, uploaded_by_user_id)
    VALUES ('supabase-storage', p_storage_key, btrim(p_file_name), p_mime, p_size, lower(p_checksum), split_part(p_storage_key, '/', 3), v_ext, 'CONFIDENTIAL', sims_private.current_user_id()) RETURNING file_object_id INTO v_file;
    INSERT INTO student_activity_evidence (student_activity_id, document_type_id, evidence_type_id, confidentiality_level_id, document_title, document_issue_date, issuing_authority, certificate_document_number,
        verification_status_id, approval_status_id, created_by_user_id)
    VALUES (p_activity_id, p_document_type_id, p_evidence_type_id, (SELECT confidentiality_level_id FROM confidentiality_level WHERE level_code = 'CONFIDENTIAL'), v_title, p_issue_date, NULLIF(btrim(p_issuing_authority), ''),
        NULLIF(btrim(p_certificate_number), ''), sims_private.vstatus('PENDING'), sims_private.astatus('DRAFT'), sims_private.current_user_id()) RETURNING student_activity_evidence_id INTO v_ev;
    INSERT INTO student_activity_evidence_version (student_activity_evidence_id, version_number, file_object_id, uploaded_by_user_id) VALUES (v_ev, 1, v_file, sims_private.current_user_id());
    INSERT INTO student_activity_evidence_audit (student_activity_evidence_id, action_code, performed_by_user_id, after_values) VALUES (v_ev, 'UPLOAD', sims_private.current_user_id(), jsonb_build_object('file_name', btrim(p_file_name), 'version', 1));
    RETURN v_ev;
END $function$;

CREATE OR REPLACE FUNCTION public.student_activity_evidence_delete(p_evidence_id bigint, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE ev record; a record;
BEGIN
    SELECT * INTO ev FROM student_activity_evidence WHERE student_activity_evidence_id = p_evidence_id AND deleted_at IS NULL FOR UPDATE;
    SELECT * INTO a FROM student_activity WHERE student_activity_id = ev.student_activity_id AND deleted_at IS NULL;
    IF ev.student_activity_evidence_id IS NULL OR a.student_activity_id IS NULL OR sims_private.activity_actor(a.student_id, 'STUDENT.STUDENT_ACTIVITY_EVIDENCE.DELETE') IS NULL THEN
        RAISE EXCEPTION 'Not authorised (STUDENT.STUDENT_ACTIVITY_EVIDENCE.DELETE) or unknown evidence' USING ERRCODE = '42501';
    END IF;
    IF a.approval_status_id <> sims_private.astatus('DRAFT') THEN RAISE EXCEPTION 'Evidence can only be removed from a draft activity' USING ERRCODE = '45000'; END IF;
    UPDATE student_activity_evidence SET deleted_at = now(), deleted_by_user_id = sims_private.current_user_id(), deletion_reason = NULLIF(btrim(p_reason), ''), is_active = false WHERE student_activity_evidence_id = p_evidence_id;
    INSERT INTO student_activity_evidence_audit (student_activity_evidence_id, action_code, performed_by_user_id, remarks) VALUES (p_evidence_id, 'SOFT_DELETE', sims_private.current_user_id(), NULLIF(btrim(p_reason), ''));
END $function$;

CREATE OR REPLACE FUNCTION public.student_activity_evidence_download_info(p_evidence_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE d record;
BEGIN
    SELECT a.student_id, f.storage_key, f.original_file_name, f.mime_type, v.student_activity_evidence_version_id INTO d
    FROM student_activity_evidence ev JOIN student_activity a ON a.student_activity_id = ev.student_activity_id
    JOIN student_activity_evidence_version v ON v.student_activity_evidence_id = ev.student_activity_evidence_id AND v.is_current JOIN file_object f ON f.file_object_id = v.file_object_id
    WHERE ev.student_activity_evidence_id = p_evidence_id AND ev.deleted_at IS NULL AND a.deleted_at IS NULL;
    IF d.student_id IS NULL OR NOT (COALESCE(d.student_id = sims_private.current_student_id(), false) OR sims_private.can_student(ARRAY['STUDENT.STUDENT_ACTIVITY_EVIDENCE.READ']::text[], d.student_id, false)) THEN
        RAISE EXCEPTION 'Not authorised (STUDENT.STUDENT_ACTIVITY_EVIDENCE.READ) or unknown evidence' USING ERRCODE = '42501';
    END IF;
    INSERT INTO student_activity_evidence_audit (student_activity_evidence_id, student_activity_evidence_version_id, action_code, performed_by_user_id) VALUES (p_evidence_id, d.student_activity_evidence_version_id, 'DOWNLOAD', sims_private.current_user_id());
    RETURN jsonb_build_object('storage_key', d.storage_key, 'file_name', d.original_file_name, 'mime_type', d.mime_type);
END $function$;

CREATE OR REPLACE FUNCTION public.student_activity_evidence_replace(p_evidence_id bigint, p_reason text, p_storage_key text, p_file_name text, p_mime text, p_size bigint, p_checksum text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE ev record; a record; v_ext text; v_file bigint; v_ver integer;
BEGIN
    SELECT * INTO ev FROM student_activity_evidence WHERE student_activity_evidence_id = p_evidence_id AND deleted_at IS NULL FOR UPDATE;
    SELECT * INTO a FROM student_activity WHERE student_activity_id = ev.student_activity_id AND deleted_at IS NULL;
    IF ev.student_activity_evidence_id IS NULL OR a.student_activity_id IS NULL OR sims_private.activity_actor(a.student_id, 'STUDENT.STUDENT_ACTIVITY_EVIDENCE.UPDATE') IS NULL THEN
        RAISE EXCEPTION 'Not authorised (STUDENT.STUDENT_ACTIVITY_EVIDENCE.UPDATE) or unknown evidence' USING ERRCODE = '42501';
    END IF;
    IF a.approval_status_id <> sims_private.astatus('DRAFT') THEN RAISE EXCEPTION 'Evidence can only be replaced on a draft activity' USING ERRCODE = '45000'; END IF;
    IF length(COALESCE(p_reason, '')) > 1000 THEN RAISE EXCEPTION 'The reason is limited to 1000 characters' USING ERRCODE = '22023'; END IF;
    v_ext := sims_private.check_student_upload(a.student_id, p_storage_key, p_file_name, p_mime, p_size, p_checksum);
    INSERT INTO file_object (storage_provider, storage_key, original_file_name, mime_type, file_size_bytes, checksum_sha256, stored_file_name, file_extension, confidentiality_level, uploaded_by_user_id)
    VALUES ('supabase-storage', p_storage_key, btrim(p_file_name), p_mime, p_size, lower(p_checksum), split_part(p_storage_key, '/', 3), v_ext, 'CONFIDENTIAL', sims_private.current_user_id()) RETURNING file_object_id INTO v_file;
    v_ver := ev.current_version_number + 1;
    UPDATE student_activity_evidence_version SET is_current = false WHERE student_activity_evidence_id = p_evidence_id AND is_current;
    INSERT INTO student_activity_evidence_version (student_activity_evidence_id, version_number, file_object_id, change_reason, uploaded_by_user_id) VALUES (p_evidence_id, v_ver, v_file, NULLIF(btrim(p_reason), ''), sims_private.current_user_id());
    UPDATE student_activity_evidence SET current_version_number = v_ver, updated_by_user_id = sims_private.current_user_id(), updated_at = now() WHERE student_activity_evidence_id = p_evidence_id;
    INSERT INTO student_activity_evidence_audit (student_activity_evidence_id, action_code, performed_by_user_id, before_values, after_values, remarks)
    VALUES (p_evidence_id, 'REPLACE', sims_private.current_user_id(), jsonb_build_object('version', ev.current_version_number), jsonb_build_object('version', v_ver, 'file_name', btrim(p_file_name)), NULLIF(btrim(p_reason), ''));
    RETURN v_ver;
END $function$;

CREATE OR REPLACE FUNCTION public.student_activity_review(p_activity_id bigint, p_step text, p_decision text, p_remarks text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a record; v_remarks text := NULLIF(btrim(p_remarks), ''); v_perm text;
BEGIN
    IF p_step NOT IN ('VERIFY', 'APPROVE') THEN RAISE EXCEPTION 'The step must be VERIFY or APPROVE' USING ERRCODE = '22023'; END IF;
    v_perm := 'STUDENT.STUDENT_ACTIVITY.' || p_step;
    SELECT * INTO a FROM student_activity WHERE student_activity_id = p_activity_id AND deleted_at IS NULL FOR UPDATE;
    IF a.student_activity_id IS NULL OR NOT sims_private.can_student(ARRAY[v_perm]::text[], a.student_id, true) THEN RAISE EXCEPTION 'Not authorised (%) or unknown activity', v_perm USING ERRCODE = '42501'; END IF;
    IF length(COALESCE(v_remarks, '')) > 1000 THEN RAISE EXCEPTION 'Remarks are limited to 1000 characters' USING ERRCODE = '22023'; END IF;
    IF p_step = 'VERIFY' THEN
        IF p_decision NOT IN ('VERIFIED', 'NEEDS_CORRECTION', 'REJECTED') THEN RAISE EXCEPTION 'The decision must be VERIFIED, NEEDS_CORRECTION or REJECTED' USING ERRCODE = '22023'; END IF;
        IF p_decision <> 'VERIFIED' AND v_remarks IS NULL THEN RAISE EXCEPTION 'Remarks are required unless the activity is verified' USING ERRCODE = '22023'; END IF;
        IF a.verification_status_id = sims_private.vstatus(p_decision) THEN RETURN; END IF; -- idempotent replay
        IF a.approval_status_id <> sims_private.astatus('SUBMITTED') OR a.verification_status_id <> sims_private.vstatus('PENDING') THEN RAISE EXCEPTION 'Only a submitted activity awaiting verification can be verified' USING ERRCODE = '45000'; END IF;
        UPDATE student_activity SET verification_status_id = sims_private.vstatus(p_decision), verified_by_user_id = sims_private.current_user_id(), verified_at = now(), verification_remarks = v_remarks,
            approval_status_id = CASE p_decision WHEN 'VERIFIED' THEN sims_private.astatus('UNDER_REVIEW') WHEN 'NEEDS_CORRECTION' THEN sims_private.astatus('DRAFT') ELSE sims_private.astatus('REJECTED') END,
            rejection_reason = CASE WHEN p_decision = 'REJECTED' THEN v_remarks END, updated_at = now() WHERE student_activity_id = p_activity_id;
    ELSE
        IF p_decision NOT IN ('APPROVED', 'REJECTED') THEN RAISE EXCEPTION 'The decision must be APPROVED or REJECTED' USING ERRCODE = '22023'; END IF;
        IF p_decision = 'REJECTED' AND v_remarks IS NULL THEN RAISE EXCEPTION 'Remarks are required to reject an activity' USING ERRCODE = '22023'; END IF;
        IF a.approval_status_id = sims_private.astatus(p_decision) THEN RETURN; END IF; -- idempotent replay
        IF a.approval_status_id <> sims_private.astatus('UNDER_REVIEW') OR a.verification_status_id <> sims_private.vstatus('VERIFIED') THEN RAISE EXCEPTION 'Only a verified activity under review can be approved or rejected' USING ERRCODE = '45000'; END IF;
        UPDATE student_activity SET approval_status_id = sims_private.astatus(p_decision), approved_by_user_id = sims_private.current_user_id(), approved_at = now(), approval_remarks = v_remarks,
            rejection_reason = CASE WHEN p_decision = 'REJECTED' THEN v_remarks END, updated_at = now() WHERE student_activity_id = p_activity_id;
    END IF;
END $function$;

CREATE OR REPLACE FUNCTION public.student_activity_save(p_activity_id bigint, p_student_id bigint, p jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_student bigint; v_act student_activity%ROWTYPE; v_actor text; v_id bigint; v_enrol record;
    v_type integer := NULLIF(p ->> 'student_activity_type_id', '')::integer;
    v_title text := NULLIF(btrim(p ->> 'activity_title'), '');
    v_start date := NULLIF(p ->> 'start_date', '')::date; v_end date := NULLIF(p ->> 'end_date', '')::date;
    v_ach text := COALESCE(NULLIF(p ->> 'achievement_type', ''), 'PARTICIPATION'); v_rank integer := NULLIF(p ->> 'position_rank', '')::integer;
    v_url text := NULLIF(btrim(p ->> 'activity_url'), '');
BEGIN
    IF p IS NULL OR jsonb_typeof(p) <> 'object' THEN RAISE EXCEPTION 'p must be an object' USING ERRCODE = '22023'; END IF;
    IF p_activity_id IS NOT NULL THEN
        SELECT * INTO v_act FROM student_activity WHERE student_activity_id = p_activity_id AND deleted_at IS NULL FOR UPDATE;
        IF v_act.student_activity_id IS NULL THEN RAISE EXCEPTION 'Not authorised (STUDENT.STUDENT_ACTIVITY.UPDATE) or unknown activity' USING ERRCODE = '42501'; END IF;
        v_student := v_act.student_id;
        v_actor := sims_private.activity_actor(v_student, 'STUDENT.STUDENT_ACTIVITY.UPDATE');
    ELSE
        v_student := COALESCE(p_student_id, sims_private.current_student_id());
        v_actor := CASE WHEN v_student IS NULL THEN NULL ELSE sims_private.activity_actor(v_student, 'STUDENT.STUDENT_ACTIVITY.CREATE') END;
    END IF;
    IF v_actor IS NULL THEN RAISE EXCEPTION 'Not authorised (STUDENT.STUDENT_ACTIVITY.CREATE / UPDATE) or unknown activity' USING ERRCODE = '42501'; END IF;
    IF p_activity_id IS NOT NULL AND v_act.approval_status_id <> sims_private.astatus('DRAFT') THEN RAISE EXCEPTION 'Only a draft activity can be edited' USING ERRCODE = '45000'; END IF;
    IF v_title IS NULL OR length(v_title) > 500 THEN RAISE EXCEPTION 'The title is required (at most 500 characters)' USING ERRCODE = '22023'; END IF;
    IF NOT EXISTS (SELECT 1 FROM student_activity_type WHERE student_activity_type_id = v_type AND is_active) THEN RAISE EXCEPTION 'Choose an active activity type' USING ERRCODE = '22023'; END IF;
    IF v_start IS NOT NULL AND v_end IS NOT NULL AND v_end < v_start THEN RAISE EXCEPTION 'The end date cannot be before the start date' USING ERRCODE = '22023'; END IF;
    IF v_ach NOT IN ('PARTICIPATION','WINNER','RUNNER_UP','FIRST_PLACE','SECOND_PLACE','THIRD_PLACE','MERIT','SPECIAL_MENTION','QUALIFIED','FINALIST','MEDAL_GOLD','MEDAL_SILVER','MEDAL_BRONZE','RECOGNITION','OTHER') THEN
        RAISE EXCEPTION 'Invalid achievement type' USING ERRCODE = '22023';
    END IF;
    IF v_rank IS NOT NULL AND v_rank <= 0 THEN RAISE EXCEPTION 'The rank must be positive' USING ERRCODE = '22023'; END IF;
    IF v_url IS NOT NULL AND v_url !~* '^https?://[^\s]+$' THEN RAISE EXCEPTION 'The link must start with http:// or https://' USING ERRCODE = '22023'; END IF;
    IF NULLIF(p ->> 'academic_year_id', '') IS NOT NULL AND NOT EXISTS (SELECT 1 FROM academic_year WHERE academic_year_id = (p ->> 'academic_year_id')::integer) THEN RAISE EXCEPTION 'Unknown academic year' USING ERRCODE = '22023'; END IF;
    IF length(COALESCE(p ->> 'description', '')) > 5000 OR length(COALESCE(p ->> 'outcomes', '')) > 5000 THEN RAISE EXCEPTION 'Text is too long' USING ERRCODE = '22023'; END IF;

    SELECT p2.programme_id, d.department_id, c.campus_id, c.institution_id INTO v_enrol
    FROM student_programme_enrolment e JOIN programme p2 ON p2.programme_id = e.programme_id JOIN department d ON d.department_id = p2.department_id JOIN campus c ON c.campus_id = d.campus_id
    WHERE e.student_id = v_student ORDER BY e.enrolment_id DESC LIMIT 1;
    IF v_enrol.programme_id IS NULL THEN RAISE EXCEPTION 'The student has no programme enrolment' USING ERRCODE = '22023'; END IF;

    IF p_activity_id IS NULL THEN
        INSERT INTO student_activity (student_id, student_activity_type_id, academic_year_id, institution_id, campus_id, department_id, programme_id, participation_level_id, event_mode_id, organizer_name,
            activity_title, event_name, team_name, participation_role, start_date, end_date, venue_name, city, achievement_type, position_rank, award_name, activity_url, description, outcomes,
            verification_status_id, approval_status_id, created_by_user_id)
        VALUES (v_student, v_type, NULLIF(p ->> 'academic_year_id', '')::integer, v_enrol.institution_id, v_enrol.campus_id, v_enrol.department_id, v_enrol.programme_id,
            NULLIF(p ->> 'participation_level_id', '')::integer, NULLIF(p ->> 'event_mode_id', '')::integer, NULLIF(btrim(p ->> 'organizer_name'), ''),
            v_title, NULLIF(btrim(p ->> 'event_name'), ''), NULLIF(btrim(p ->> 'team_name'), ''), NULLIF(btrim(p ->> 'participation_role'), ''), v_start, v_end, NULLIF(btrim(p ->> 'venue_name'), ''),
            NULLIF(btrim(p ->> 'city'), ''), v_ach, v_rank, NULLIF(btrim(p ->> 'award_name'), ''), v_url, NULLIF(btrim(p ->> 'description'), ''), NULLIF(btrim(p ->> 'outcomes'), ''),
            sims_private.vstatus('NOT_SUBMITTED'), sims_private.astatus('DRAFT'), sims_private.current_user_id())
        RETURNING student_activity_id INTO v_id;
        RETURN v_id;
    END IF;
    UPDATE student_activity SET student_activity_type_id = v_type, academic_year_id = NULLIF(p ->> 'academic_year_id', '')::integer, participation_level_id = NULLIF(p ->> 'participation_level_id', '')::integer,
        event_mode_id = NULLIF(p ->> 'event_mode_id', '')::integer, organizer_name = NULLIF(btrim(p ->> 'organizer_name'), ''), activity_title = v_title, event_name = NULLIF(btrim(p ->> 'event_name'), ''),
        team_name = NULLIF(btrim(p ->> 'team_name'), ''), participation_role = NULLIF(btrim(p ->> 'participation_role'), ''), start_date = v_start, end_date = v_end, venue_name = NULLIF(btrim(p ->> 'venue_name'), ''),
        city = NULLIF(btrim(p ->> 'city'), ''), achievement_type = v_ach, position_rank = v_rank, award_name = NULLIF(btrim(p ->> 'award_name'), ''), activity_url = v_url,
        description = NULLIF(btrim(p ->> 'description'), ''), outcomes = NULLIF(btrim(p ->> 'outcomes'), ''), updated_by_user_id = sims_private.current_user_id(), updated_at = now()
    WHERE student_activity_id = p_activity_id;
    RETURN p_activity_id;
END $function$;

CREATE OR REPLACE FUNCTION public.student_activity_submit(p_activity_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a record; t record; r record; v_count integer;
BEGIN
    SELECT * INTO a FROM student_activity WHERE student_activity_id = p_activity_id AND deleted_at IS NULL FOR UPDATE;
    IF a.student_activity_id IS NULL OR sims_private.activity_actor(a.student_id, 'STUDENT.STUDENT_ACTIVITY.UPDATE') IS NULL THEN RAISE EXCEPTION 'Not authorised (STUDENT.STUDENT_ACTIVITY.UPDATE) or unknown activity' USING ERRCODE = '42501'; END IF;
    IF a.approval_status_id = sims_private.astatus('SUBMITTED') THEN RETURN; END IF; -- idempotent replay
    IF a.approval_status_id <> sims_private.astatus('DRAFT') THEN RAISE EXCEPTION 'Only a draft activity can be submitted' USING ERRCODE = '45000'; END IF;
    SELECT * INTO t FROM student_activity_type WHERE student_activity_type_id = a.student_activity_type_id;
    IF a.start_date IS NULL THEN RAISE EXCEPTION 'The start date is required before submitting' USING ERRCODE = '45000'; END IF;
    IF t.requires_team_details AND a.team_name IS NULL THEN RAISE EXCEPTION 'The team name is required for this type of activity' USING ERRCODE = '45000'; END IF;
    FOR r IN SELECT q.evidence_type_id, q.minimum_files, e.evidence_type_name FROM student_activity_evidence_requirement q JOIN evidence_type e ON e.evidence_type_id = q.evidence_type_id
             WHERE q.student_activity_type_id = a.student_activity_type_id AND q.is_active AND q.is_mandatory AND (q.valid_from IS NULL OR q.valid_from <= CURRENT_DATE) AND (q.valid_to IS NULL OR q.valid_to >= CURRENT_DATE) LOOP
        SELECT count(*) INTO v_count FROM student_activity_evidence ev WHERE ev.student_activity_id = p_activity_id AND ev.evidence_type_id = r.evidence_type_id AND ev.is_active AND ev.deleted_at IS NULL;
        IF v_count < GREATEST(r.minimum_files, 1) THEN RAISE EXCEPTION 'Evidence required: %', r.evidence_type_name USING ERRCODE = '45000'; END IF;
    END LOOP;
    UPDATE student_activity SET approval_status_id = sims_private.astatus('SUBMITTED'), verification_status_id = sims_private.vstatus('PENDING'), rejection_reason = NULL, updated_at = now() WHERE student_activity_id = p_activity_id;
END $function$;

CREATE OR REPLACE FUNCTION public.student_activity_team_add(p_activity_id bigint, p_student_id bigint, p_external_name text, p_external_email text, p_role text, p_is_lead boolean DEFAULT false)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a record; v_id bigint; v_name text := NULLIF(btrim(p_external_name), '');
BEGIN
    SELECT * INTO a FROM student_activity WHERE student_activity_id = p_activity_id AND deleted_at IS NULL FOR UPDATE;
    IF a.student_activity_id IS NULL OR sims_private.activity_actor(a.student_id, 'STUDENT.STUDENT_ACTIVITY.UPDATE') IS NULL THEN RAISE EXCEPTION 'Not authorised (STUDENT.STUDENT_ACTIVITY.UPDATE) or unknown activity' USING ERRCODE = '42501'; END IF;
    IF a.approval_status_id <> sims_private.astatus('DRAFT') THEN RAISE EXCEPTION 'Only a draft activity can be changed' USING ERRCODE = '45000'; END IF;
    IF (p_student_id IS NULL) = (v_name IS NULL) THEN RAISE EXCEPTION 'Give either a student or an external member name' USING ERRCODE = '22023'; END IF;
    IF p_student_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM student WHERE student_id = p_student_id) THEN RAISE EXCEPTION 'Unknown student' USING ERRCODE = '22023'; END IF;
    IF length(COALESCE(v_name, '')) > 250 OR length(COALESCE(p_external_email, '')) > 254 OR length(COALESCE(p_role, '')) > 150 THEN RAISE EXCEPTION 'Text is too long' USING ERRCODE = '22023'; END IF;
    IF p_student_id IS NOT NULL AND EXISTS (SELECT 1 FROM student_activity_team_member WHERE student_activity_id = p_activity_id AND student_id = p_student_id) THEN RAISE EXCEPTION 'That student is already a team member' USING ERRCODE = '23505'; END IF;
    INSERT INTO student_activity_team_member (student_activity_id, student_id, external_member_name, external_member_email, member_role, is_team_lead, member_sequence)
    VALUES (p_activity_id, p_student_id, v_name, NULLIF(btrim(p_external_email), ''), NULLIF(btrim(p_role), ''), COALESCE(p_is_lead, false),
            (SELECT COALESCE(max(member_sequence), 0) + 1 FROM student_activity_team_member WHERE student_activity_id = p_activity_id)) RETURNING student_activity_team_member_id INTO v_id;
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.student_activity_team_remove(p_member_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a record; m record;
BEGIN
    SELECT * INTO m FROM student_activity_team_member WHERE student_activity_team_member_id = p_member_id;
    SELECT * INTO a FROM student_activity WHERE student_activity_id = m.student_activity_id AND deleted_at IS NULL FOR UPDATE;
    IF a.student_activity_id IS NULL OR sims_private.activity_actor(a.student_id, 'STUDENT.STUDENT_ACTIVITY.UPDATE') IS NULL THEN RAISE EXCEPTION 'Not authorised (STUDENT.STUDENT_ACTIVITY.UPDATE) or unknown member' USING ERRCODE = '42501'; END IF;
    IF a.approval_status_id <> sims_private.astatus('DRAFT') THEN RAISE EXCEPTION 'Only a draft activity can be changed' USING ERRCODE = '45000'; END IF;
    DELETE FROM student_activity_team_member WHERE student_activity_team_member_id = p_member_id;
END $function$;

CREATE OR REPLACE FUNCTION public.student_document_delete(p_id bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE d record;
BEGIN
    SELECT d0.student_document_id, d0.student_id, d0.verification_status, d0.file_object_id, f.storage_key INTO d
    FROM student_document d0 JOIN file_object f ON f.file_object_id = d0.file_object_id WHERE d0.student_document_id = p_id FOR UPDATE OF d0;
    IF d.student_document_id IS NULL THEN RAISE EXCEPTION 'Not authorised (DOCUMENT.ALL.DELETE) or unknown document' USING ERRCODE = '42501'; END IF;
    IF COALESCE(d.student_id = sims_private.current_student_id(), false) THEN
        IF d.verification_status = 'VERIFIED' THEN RAISE EXCEPTION 'A verified document cannot be deleted' USING ERRCODE = '45000'; END IF;
    ELSIF sims_private.can_student(ARRAY['DOCUMENT.ALL.DELETE']::text[], d.student_id, true) THEN
        IF d.verification_status = 'VERIFIED' THEN RAISE EXCEPTION 'A verified document cannot be deleted' USING ERRCODE = '45000'; END IF;
    ELSE
        RAISE EXCEPTION 'Not authorised (DOCUMENT.ALL.DELETE) or unknown document' USING ERRCODE = '42501';
    END IF;
    DELETE FROM student_document WHERE student_document_id = p_id;
    DELETE FROM file_object WHERE file_object_id = d.file_object_id;
    RETURN d.storage_key;
END $function$;

CREATE OR REPLACE FUNCTION public.student_document_download_info(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE d record;
BEGIN
    SELECT d0.student_document_id, d0.student_id, f.storage_key, f.original_file_name, f.mime_type INTO d
    FROM student_document d0 JOIN file_object f ON f.file_object_id = d0.file_object_id WHERE d0.student_document_id = p_id AND f.deleted_at IS NULL;
    IF d.student_document_id IS NULL OR NOT (COALESCE(d.student_id = sims_private.current_student_id(), false) OR sims_private.can_student(ARRAY['DOCUMENT.ALL.READ']::text[], d.student_id, false)) THEN
        RAISE EXCEPTION 'Not authorised (DOCUMENT.ALL.READ) or unknown document' USING ERRCODE = '42501';
    END IF;
    INSERT INTO activity_audit (user_id, module_code, action_code, entity_name, entity_id, details)
    VALUES (sims_private.current_user_id(), 'DOCUMENT', 'DOWNLOAD', 'student_document', p_id::text, jsonb_build_object('student_id', d.student_id));
    RETURN jsonb_build_object('storage_key', d.storage_key, 'file_name', d.original_file_name, 'mime_type', d.mime_type);
END $function$;

CREATE OR REPLACE FUNCTION public.student_document_register(p_student_id bigint, p_document_type_id integer, p_storage_key text, p_file_name text, p_mime_type text, p_size bigint, p_checksum text, p_document_number text DEFAULT NULL::text, p_issue_date date DEFAULT NULL::date, p_expiry_date date DEFAULT NULL::date)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_file bigint; v_doc bigint; v_ext text; v_meta jsonb; v_number text := NULLIF(btrim(p_document_number), '');
BEGIN
    IF NOT (COALESCE(p_student_id = sims_private.current_student_id(), false) OR sims_private.can_student(ARRAY['DOCUMENT.ALL.CREATE']::text[], p_student_id, true)) THEN
        RAISE EXCEPTION 'Not authorised (DOCUMENT.ALL.CREATE)' USING ERRCODE = '42501';
    END IF;
    IF sims_private.doc_student_id(p_storage_key) IS DISTINCT FROM p_student_id THEN RAISE EXCEPTION 'The file is not stored under this student' USING ERRCODE = '22023'; END IF;
    IF p_file_name IS NULL OR btrim(p_file_name) = '' OR length(p_file_name) > 255 THEN RAISE EXCEPTION 'The file name is required (at most 255 characters)' USING ERRCODE = '22023'; END IF;
    IF p_mime_type NOT IN ('application/pdf', 'image/jpeg', 'image/png') THEN RAISE EXCEPTION 'Only PDF, JPEG and PNG files are accepted' USING ERRCODE = '22023'; END IF;
    v_ext := lower(substring(p_file_name FROM '\.([A-Za-z0-9]{1,10})$'));
    IF v_ext IS NULL OR NOT ((p_mime_type = 'application/pdf' AND v_ext = 'pdf') OR (p_mime_type = 'image/jpeg' AND v_ext IN ('jpg', 'jpeg')) OR (p_mime_type = 'image/png' AND v_ext = 'png')) THEN
        RAISE EXCEPTION 'The file name does not match its type' USING ERRCODE = '22023';
    END IF;
    IF p_size IS NULL OR p_size <= 0 OR p_size > 10485760 THEN RAISE EXCEPTION 'The file must be between 1 byte and 10 MB' USING ERRCODE = '22023'; END IF;
    IF p_checksum IS NOT NULL AND p_checksum !~ '^[0-9A-Fa-f]{64}$' THEN RAISE EXCEPTION 'Invalid checksum' USING ERRCODE = '22023'; END IF;
    IF length(COALESCE(v_number, '')) > 100 THEN RAISE EXCEPTION 'The document number is limited to 100 characters' USING ERRCODE = '22023'; END IF;
    IF p_issue_date IS NOT NULL AND p_expiry_date IS NOT NULL AND p_expiry_date < p_issue_date THEN RAISE EXCEPTION 'The expiry date cannot be before the issue date' USING ERRCODE = '22023'; END IF;
    IF NOT EXISTS (SELECT 1 FROM student WHERE student_id = p_student_id) THEN RAISE EXCEPTION 'Unknown student' USING ERRCODE = '22023'; END IF;
    IF NOT EXISTS (SELECT 1 FROM document_type WHERE document_type_id = p_document_type_id AND is_active) THEN RAISE EXCEPTION 'Choose an active document type' USING ERRCODE = '22023'; END IF;
    SELECT metadata INTO v_meta FROM storage.objects WHERE bucket_id = 'sims-documents' AND name = p_storage_key;
    IF NOT FOUND THEN RAISE EXCEPTION 'The file has not been uploaded' USING ERRCODE = '22023'; END IF;
    IF v_meta ? 'size' AND (v_meta ->> 'size')::bigint <> p_size THEN RAISE EXCEPTION 'The uploaded file size does not match' USING ERRCODE = '22023'; END IF;
    IF EXISTS (SELECT 1 FROM file_object WHERE storage_key = p_storage_key) THEN RAISE EXCEPTION 'That file is already registered' USING ERRCODE = '23505'; END IF;
    INSERT INTO file_object (storage_provider, storage_key, original_file_name, mime_type, file_size_bytes, checksum_sha256, stored_file_name, file_extension, confidentiality_level, uploaded_by_user_id)
    VALUES ('supabase-storage', p_storage_key, btrim(p_file_name), p_mime_type, p_size, lower(p_checksum), split_part(p_storage_key, '/', 3), v_ext, 'CONFIDENTIAL', sims_private.current_user_id())
    RETURNING file_object_id INTO v_file;
    INSERT INTO student_document (student_id, document_type_id, file_object_id, document_number, issue_date, expiry_date)
    VALUES (p_student_id, p_document_type_id, v_file, v_number, p_issue_date, p_expiry_date) RETURNING student_document_id INTO v_doc;
    RETURN v_doc;
END $function$;

CREATE OR REPLACE FUNCTION public.student_document_review(p_id bigint, p_decision text, p_remarks text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE d record; v_remarks text := NULLIF(btrim(p_remarks), '');
BEGIN
    SELECT student_document_id, student_id, verification_status INTO d FROM student_document WHERE student_document_id = p_id FOR UPDATE;
    IF d.student_document_id IS NULL OR NOT sims_private.can_student(ARRAY['DOCUMENT.ALL.VERIFY']::text[], d.student_id, true) THEN RAISE EXCEPTION 'Not authorised (DOCUMENT.ALL.VERIFY) or unknown document' USING ERRCODE = '42501'; END IF;
    IF p_decision NOT IN ('VERIFIED', 'REJECTED') THEN RAISE EXCEPTION 'The decision must be VERIFIED or REJECTED' USING ERRCODE = '22023'; END IF;
    IF length(COALESCE(v_remarks, '')) > 500 THEN RAISE EXCEPTION 'Remarks are limited to 500 characters' USING ERRCODE = '22023'; END IF;
    IF p_decision = 'REJECTED' AND v_remarks IS NULL THEN RAISE EXCEPTION 'Remarks are required to reject a document' USING ERRCODE = '22023'; END IF;
    IF d.verification_status = p_decision THEN RETURN; END IF; -- idempotent replay
    IF d.verification_status <> 'PENDING' THEN RAISE EXCEPTION 'Only a pending document can be reviewed' USING ERRCODE = '45000'; END IF;
    UPDATE student_document SET verification_status = p_decision, verified_at = now(), remarks = v_remarks WHERE student_document_id = p_id;
END $function$;

CREATE OR REPLACE FUNCTION public.svc_request_cancel(p_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE r record;
BEGIN
    SELECT * INTO r FROM sims_private.student_service_request WHERE service_request_id = p_id FOR UPDATE;
    IF r.service_request_id IS NULL OR NOT (sims_private.is_me_student(r.student_id) OR COALESCE(sims_private.can_student(ARRAY['DOCUMENT.ALL.UPDATE']::text[], r.student_id, true), false)) THEN RAISE EXCEPTION 'Not authorised or unknown request' USING ERRCODE = '42501'; END IF;
    IF r.request_status = 'CANCELLED' THEN RETURN; END IF;
    IF r.request_status <> 'SUBMITTED' THEN RAISE EXCEPTION 'Only a submitted request can be cancelled (status %)', r.request_status USING ERRCODE = '45000'; END IF;
    UPDATE sims_private.student_service_request SET request_status = 'CANCELLED' WHERE service_request_id = p_id;
    INSERT INTO activity_audit (user_id, module_code, action_code, entity_name, entity_id, details) VALUES (sims_private.current_user_id(), 'DOCUMENT', 'SERVICE_CANCELLED', 'student_service_request', p_id::text, '{}'::jsonb);
END $function$;

CREATE OR REPLACE FUNCTION public.svc_request_create(p_kind text, p_term_id bigint DEFAULT NULL::bigint, p_planned_date date DEFAULT NULL::date, p_detail text DEFAULT NULL::text, p_student_id bigint DEFAULT NULL::bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_student bigint := COALESCE(p_student_id, sims_private.current_student_id()); v_id bigint;
BEGIN
    IF v_student IS NULL OR NOT (sims_private.is_me_student(v_student) OR COALESCE(sims_private.can_student(ARRAY['DOCUMENT.ALL.CREATE']::text[], v_student, true), false)) THEN RAISE EXCEPTION 'Not authorised (DOCUMENT.ALL.CREATE)' USING ERRCODE = '42501'; END IF;
    IF p_kind NOT IN ('HALL_TICKET', 'HOSTEL_CHECKOUT', 'GRADUATION') THEN RAISE EXCEPTION 'Unknown request kind' USING ERRCODE = '22023'; END IF;
    IF length(COALESCE(p_detail, '')) > 500 THEN RAISE EXCEPTION 'The note is limited to 500 characters' USING ERRCODE = '22023'; END IF;
    IF p_kind = 'HALL_TICKET' THEN
        IF p_term_id IS NULL OR NOT EXISTS (SELECT 1 FROM student_term_registration tr JOIN student_programme_enrolment e ON e.enrolment_id = tr.enrolment_id JOIN programme_term_offering o ON o.programme_term_offering_id = tr.programme_term_offering_id
                                            WHERE e.student_id = v_student AND o.academic_term_id = p_term_id AND tr.registration_status IN ('REGISTERED', 'APPROVED')) THEN
            RAISE EXCEPTION 'A hall ticket needs a registration in that academic term' USING ERRCODE = '22023';
        END IF;
    ELSE
        p_term_id := NULL;
    END IF;
    IF p_kind = 'HOSTEL_CHECKOUT' AND (p_planned_date IS NULL OR p_planned_date < current_date) THEN RAISE EXCEPTION 'Give the planned check-out date (today or later)' USING ERRCODE = '22023'; END IF;
    IF p_kind <> 'HOSTEL_CHECKOUT' THEN p_planned_date := NULL; END IF;
    PERFORM sims_private.svc_hold_check(v_student, p_kind, 'request');
    BEGIN
        INSERT INTO sims_private.student_service_request (request_number, request_kind, student_id, academic_term_id, planned_date, detail)
        VALUES ('SR-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('sims_private.service_request_seq')::text, 6, '0'), p_kind, v_student, p_term_id, p_planned_date, NULLIF(btrim(p_detail), '')) RETURNING service_request_id INTO v_id;
    EXCEPTION WHEN unique_violation THEN RAISE EXCEPTION 'There is already an open request of this kind' USING ERRCODE = '45000';
    END;
    INSERT INTO activity_audit (user_id, module_code, action_code, entity_name, entity_id, details) VALUES (sims_private.current_user_id(), 'DOCUMENT', 'SERVICE_REQUESTED', 'student_service_request', v_id::text, jsonb_build_object('kind', p_kind, 'student_id', v_student));
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.svc_request_decide(p_id bigint, p_action text, p_remarks text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE r record; v_ref text; v_rem text := NULLIF(btrim(p_remarks), '');
BEGIN
    SELECT * INTO r FROM sims_private.student_service_request WHERE service_request_id = p_id FOR UPDATE;
    IF r.service_request_id IS NULL OR NOT COALESCE(sims_private.can_student(ARRAY['DOCUMENT.ALL.APPROVE']::text[], r.student_id, true), false) THEN RAISE EXCEPTION 'Not authorised (DOCUMENT.ALL.APPROVE) or unknown request' USING ERRCODE = '42501'; END IF;
    IF p_action NOT IN ('APPROVE', 'REJECT', 'COMPLETE') THEN RAISE EXCEPTION 'The action must be APPROVE, REJECT or COMPLETE' USING ERRCODE = '22023'; END IF;
    IF length(COALESCE(v_rem, '')) > 500 THEN RAISE EXCEPTION 'Remarks are limited to 500 characters' USING ERRCODE = '22023'; END IF;
    IF p_action = 'REJECT' AND v_rem IS NULL THEN RAISE EXCEPTION 'A reason is required to reject' USING ERRCODE = '22023'; END IF;
    IF p_action IN ('APPROVE', 'REJECT') AND r.request_status <> 'SUBMITTED' THEN RAISE EXCEPTION 'Only a submitted request can be approved or rejected (status %)', r.request_status USING ERRCODE = '45000'; END IF;
    IF p_action = 'COMPLETE' AND r.request_status <> 'APPROVED' THEN RAISE EXCEPTION 'Only an approved request can be completed (status %)', r.request_status USING ERRCODE = '45000'; END IF;
    IF p_action IN ('APPROVE', 'COMPLETE') THEN PERFORM sims_private.svc_hold_check(r.student_id, r.request_kind, 'decide'); END IF;
    IF p_action = 'REJECT' THEN
        UPDATE sims_private.student_service_request SET request_status = 'REJECTED', decision_remarks = v_rem, decided_by = sims_private.current_user_id(), decided_at = now() WHERE service_request_id = p_id;
    ELSIF p_action = 'APPROVE' THEN
        UPDATE sims_private.student_service_request SET request_status = 'APPROVED', decision_remarks = v_rem, decided_by = sims_private.current_user_id(), decided_at = now() WHERE service_request_id = p_id;
    ELSE
        v_ref := CASE r.request_kind WHEN 'HALL_TICKET' THEN 'HT-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('sims_private.hall_ticket_seq')::text, 6, '0')
                                      WHEN 'HOSTEL_CHECKOUT' THEN 'HC-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('sims_private.service_request_seq')::text, 6, '0')
                                      ELSE 'GR-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('sims_private.service_request_seq')::text, 6, '0') END;
        UPDATE sims_private.student_service_request SET request_status = 'COMPLETED', completed_at = now(), reference_number = v_ref WHERE service_request_id = p_id;
    END IF;
    INSERT INTO activity_audit (user_id, module_code, action_code, entity_name, entity_id, details)
    VALUES (sims_private.current_user_id(), 'DOCUMENT', 'SERVICE_' || p_action, 'student_service_request', p_id::text, jsonb_build_object('kind', r.request_kind, 'remarks', v_rem, 'reference', v_ref));
    RETURN v_ref;
END $function$;

CREATE OR REPLACE FUNCTION public.teaching_populate_roster(p_cos_id bigint)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_n integer;
BEGIN
    PERFORM sims_private.att_authorize_cos(p_cos_id, 'TEACHING', 'UPDATE');
    INSERT INTO course_offering_section_student (course_offering_section_id, course_registration_id, course_offering_id, effective_from)
    SELECT cos.course_offering_section_id, cr.course_registration_id, cr.course_offering_id, current_date
    FROM course_offering_section cos
    JOIN student_course_registration cr ON cr.course_offering_id = cos.course_offering_id AND cr.registration_status IN ('REGISTERED', 'APPROVED')
    JOIN student_term_registration tr ON tr.term_registration_id = cr.term_registration_id
         AND tr.registration_status IN ('REGISTERED', 'APPROVED')
         AND tr.class_section_id = cos.class_section_id
         AND (cos.class_batch_id IS NULL OR tr.class_batch_id = cos.class_batch_id)
    WHERE cos.course_offering_section_id = p_cos_id
    ON CONFLICT (course_offering_section_id, course_registration_id) DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n;
END $function$;

CREATE OR REPLACE FUNCTION public.timetable_generate_sessions(p_cos_id bigint, p_from date, p_to date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_n integer;
BEGIN
    PERFORM sims_private.att_authorize_cos(p_cos_id, 'ATTENDANCE', 'CREATE');
    PERFORM sims_private.att_authorize_cos(p_cos_id, 'TIMETABLE', 'READ');
    IF p_from IS NULL OR p_to IS NULL OR p_to < p_from THEN RAISE EXCEPTION 'Give a valid date range' USING ERRCODE = '22023'; END IF;
    IF p_to - p_from > 366 THEN RAISE EXCEPTION 'Generate at most 367 days at a time' USING ERRCODE = '22023'; END IF;

    INSERT INTO class_session (course_offering_section_id, faculty_assignment_id, timetable_session_id, session_date, start_time, end_time, room_id, session_type, session_status)
    SELECT t.course_offering_section_id, t.faculty_assignment_id, t.timetable_session_id, d::date, s.start_time, s.end_time, t.room_id, cos.session_type, 'PLANNED'
    FROM timetable_session t
    JOIN time_slot s ON s.time_slot_id = t.time_slot_id
    JOIN course_offering_section cos ON cos.course_offering_section_id = t.course_offering_section_id
    CROSS JOIN LATERAL generate_series(GREATEST(p_from, t.effective_from), LEAST(p_to, COALESCE(t.effective_to, p_to)), interval '1 day') d
    WHERE t.course_offering_section_id = p_cos_id AND extract(isodow FROM d)::int = t.day_of_week
    ON CONFLICT ON CONSTRAINT uq_class_session DO NOTHING;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN v_n;
END $function$;

CREATE OR REPLACE FUNCTION public.fin_instalment_apply(p_assessment_id bigint, p_plan_id integer, p_first_due date)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a record; p record; v_first numeric; v_rest numeric; v_amt numeric; k integer;
BEGIN
    SELECT fee_assessment_id, student_account_id, assessment_status, net_payable_amount, balance_amount INTO a FROM student_fee_assessment WHERE fee_assessment_id = p_assessment_id FOR UPDATE;
    IF a.fee_assessment_id IS NULL OR a.student_account_id IS NULL THEN RAISE EXCEPTION 'Not authorised (FEES.FEE_ASSESSMENT.UPDATE) or unknown assessment' USING ERRCODE = '42501'; END IF;
    PERFORM sims_private.fin_authorize(a.student_account_id, 'FEE_ASSESSMENT', 'UPDATE');
    IF a.assessment_status NOT IN ('ASSESSED', 'PARTIALLY_PAID', 'OVERDUE') OR a.balance_amount <= 0 THEN RAISE EXCEPTION 'Instalments need an open assessment with a balance' USING ERRCODE = '45000'; END IF;
    IF p_first_due IS NULL OR p_first_due < current_date THEN RAISE EXCEPTION 'The first due date must be today or later' USING ERRCODE = '22023'; END IF;
    SELECT * INTO p FROM installment_plan WHERE installment_plan_id = p_plan_id AND is_active;
    IF NOT FOUND THEN RAISE EXCEPTION 'Unknown or inactive instalment plan' USING ERRCODE = '22023'; END IF;
    IF EXISTS (SELECT 1 FROM student_installment_schedule WHERE fee_assessment_id = p_assessment_id AND installment_status <> 'CANCELLED') THEN RAISE EXCEPTION 'The assessment already has an instalment schedule' USING ERRCODE = '45000'; END IF;
    DELETE FROM student_installment_schedule WHERE fee_assessment_id = p_assessment_id; -- only cancelled rows remain
    IF p.number_of_installments < 1 THEN RAISE EXCEPTION 'The plan has no instalments' USING ERRCODE = '45000'; END IF;
    IF p.number_of_installments = 1 THEN
        v_first := a.net_payable_amount; v_rest := 0;
    ELSE
        v_first := greatest(round(a.net_payable_amount / p.number_of_installments, 2), round(a.net_payable_amount * COALESCE(p.minimum_initial_percentage, 0) / 100, 2));
        v_rest := round((a.net_payable_amount - v_first) / (p.number_of_installments - 1), 2);
    END IF;
    FOR k IN 1..p.number_of_installments LOOP
        v_amt := CASE WHEN k = 1 THEN v_first WHEN k < p.number_of_installments THEN v_rest ELSE a.net_payable_amount - v_first - v_rest * (p.number_of_installments - 2) END;
        IF p.number_of_installments = 1 THEN v_amt := a.net_payable_amount; END IF;
        INSERT INTO student_installment_schedule (fee_assessment_id, installment_plan_id, installment_number, due_date, installment_amount, amount_paid, balance_amount, installment_status)
        VALUES (p_assessment_id, p_plan_id, k, (p_first_due + make_interval(months => k - 1))::date, v_amt, 0, v_amt, 'PENDING');
    END LOOP;
    PERFORM public.fin_instalment_refresh(p_assessment_id);
    PERFORM sims_private.fin_audit('INSTALMENTS_CREATED', 'student_fee_assessment', p_assessment_id, NULL, jsonb_build_object('plan_id', p_plan_id, 'count', p.number_of_installments, 'first_due', p_first_due));
    RETURN p.number_of_installments;
END $function$;

CREATE OR REPLACE FUNCTION public.fin_penalty_assess(p_student_account_id bigint, p_fee_type_id bigint, p_amount numeric, p_reason text, p_academic_year_id integer, p_due_date date)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_fa bigint; v_item bigint; v_id bigint; v_num text;
BEGIN
    PERFORM sims_private.fin_authorize(p_student_account_id, 'FEE_ASSESSMENT', 'CREATE');
    IF p_reason IS NULL OR btrim(p_reason) = '' OR length(p_reason) > 500 THEN RAISE EXCEPTION 'A reason (at most 500 characters) is required' USING ERRCODE = '22023'; END IF;
    PERFORM sims_private.fin_check_amount(p_amount, 'amount');
    v_num := 'PEN-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('sims_private.fee_penalty_seq')::text, 6, '0');
    v_fa := public.fin_create_fee_assessment(v_num, p_student_account_id, p_academic_year_id, 'PENALTY', current_date, p_due_date,
              jsonb_build_array(jsonb_build_object('fee_type_id', p_fee_type_id, 'description', left(p_reason, 250), 'original_amount', p_amount)));
    SELECT assessment_item_id INTO v_item FROM student_fee_assessment_item WHERE fee_assessment_id = v_fa;
    INSERT INTO student_fee_penalty (student_account_id, assessment_item_id, fee_type_id, penalty_date, penalty_reason, penalty_amount, waived_amount, net_penalty_amount, penalty_status)
    VALUES (p_student_account_id, v_item, p_fee_type_id, current_date, p_reason, p_amount, 0, p_amount, 'ASSESSED') RETURNING fee_penalty_id INTO v_id;
    PERFORM sims_private.fin_audit('PENALTY_ASSESSED', 'student_fee_penalty', v_id, NULL, jsonb_build_object('amount', p_amount, 'assessment_id', v_fa));
    RETURN v_id;
END $function$;

-- -----------------------------------------------------------------------------
-- Grants
--
-- The first block takes the default PUBLIC execute privilege away from
-- the functions again - a fresh function has it, the live project does
-- not.  The second block restores the live ACLs.
-- -----------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.admission_admit(p_application_id bigint, p_student jsonb, p_enrolment jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admission_apply(p_applicant jsonb, p_application jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admission_set_status(p_application_id bigint, p_new_status text, p_remarks text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admission_update_applicant(p_applicant_id bigint, p jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.admission_update_application(p_application_id bigint, p jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.announcement_archive(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.announcement_attachment_download_info(p_id bigint, p_file_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.announcement_attachment_list(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.announcement_attachment_register(p_id bigint, p_storage_key text, p_file_name text, p_mime_type text, p_size bigint, p_checksum text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.announcement_attachment_remove(p_id bigint, p_file_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.announcement_can_post_global() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.announcement_decide(p_id bigint, p_approve boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.announcement_detail(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.announcement_save(p_id bigint, p_type_id integer, p_department_id integer, p_title text, p_description text, p_publish_from timestamp with time zone, p_publish_to timestamp with time zone, p_audience text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.announcement_submit(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.announcement_targets() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.announcements_feed(p_limit integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.announcements_manage(p_status text, p_search text, p_limit integer, p_offset integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.assessment_enter_marks(p_event_id bigint, p_marks jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.assessment_offering_info(p_course_offering_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.assessment_offerings(p_term bigint, p_programme integer, p_limit integer, p_offset integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.assessment_sheet(p_event_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.attendance_decide_correction(p_correction_id bigint, p_approve boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.attendance_mark(p_session_id bigint, p_marks jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.attendance_request_correction(p_session_id bigint, p_roster_id bigint, p_requested_status_id integer, p_reason text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.attendance_sheet(p_session_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.attendance_summary(p_cos_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.audit_get(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.audit_list(p_module text, p_action text, p_search text, p_from timestamp with time zone, p_to timestamp with time zone, p_limit integer, p_offset integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.audit_modules() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.auth_failure_record(p_username text, p_reason text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.auth_login_record() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.auth_logout_record() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cert_request_cancel(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cert_request_create(p_type_id integer, p_purpose text, p_student_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cert_request_decide(p_id bigint, p_approve boolean, p_remarks text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cert_request_download_info(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cert_request_issue(p_id bigint, p_certificate_number text, p_storage_key text, p_file_name text, p_size bigint, p_checksum text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cert_request_list(p_student_id bigint, p_status text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.dash_applications() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.dash_employees() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.dash_enrolments() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.dash_fee_collection(p_months integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.dash_fee_outstanding() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.dash_registrations() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.dash_sessions(p_days integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.dash_term_results() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.emp_aadhaar_save(p_employee_id bigint, p_aadhaar text, p_name text, p_purpose text, p_remarks text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.emp_bank_save(p_employee_id bigint, p_account_id bigint, p_holder text, p_bank text, p_branch text, p_account_number text, p_account_confirm text, p_ifsc text, p_type text, p_upi text, p_is_primary boolean, p_is_salary boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.emp_competency_delete(p_employee_id bigint, p_course_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.emp_competency_list(p_employee_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.emp_competency_save(p_employee_id bigint, p_course_id bigint, p_level text, p_valid_from date, p_valid_to date) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.emp_doc_rule_end(p_rule_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.emp_doc_rule_list(p_document_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.emp_doc_rule_set(p_document_id bigint, p_role_code text, p_username text, p_can_view boolean, p_can_download boolean, p_valid_to timestamp with time zone) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.emp_pan_save(p_employee_id bigint, p_pan text, p_name text, p_issue_date date, p_remarks text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.emp_sensitive_delete(p_kind text, p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.emp_sensitive_list(p_employee_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.emp_sensitive_reveal(p_kind text, p_id bigint, p_purpose text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.emp_sensitive_review(p_kind text, p_id bigint, p_decision text, p_remarks text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.employee_assign(p_employee_id bigint, p_campus_id integer, p_department_id integer, p_designation_id integer, p_start_date date, p_is_primary boolean, p_end_current boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.employee_document_delete(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.employee_document_download_info(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.employee_document_list(p_employee_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.employee_document_register(p_employee_id bigint, p_category_id integer, p_document_type_id integer, p_title text, p_storage_key text, p_file_name text, p_mime_type text, p_size bigint, p_checksum text, p_document_number text, p_issue_date date, p_expiry_date date) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.employee_document_review(p_id bigint, p_decision text, p_remarks text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.employee_register(p_employee jsonb, p_assignment jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.feedback_cycle_offerings(p_cycle_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.feedback_form(p_cycle_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.feedback_my_tasks() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.feedback_results(p_cycle_id bigint, p_course_offering_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.feedback_submit(p_cycle_id bigint, p_course_offering_id bigint, p_faculty_assignment_id bigint, p_answers jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_academic_years() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_account_extras(p_student_account_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_account_info(p_student_account_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_accounts(p_search text, p_status text, p_limit integer, p_offset integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_adjustment_create(p_number text, p_student_account_id bigint, p_assessment_item_id bigint, p_type text, p_amount numeric, p_reason text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_adjustment_decide(p_adjustment_id bigint, p_approve boolean, p_remarks text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_allocate_payment(p_payment_transaction_id bigint, p_assessment_item_id bigint, p_amount numeric) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_benefit_apply(p_kind text, p_benefit_id bigint, p_assessment_item_id bigint, p_amount numeric) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_benefit_create(p_kind text, p_student_id bigint, p_academic_year_id integer, p_type_id bigint, p_amount numeric, p_percentage numeric, p_reference text, p_authority text, p_remarks text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_benefit_decide(p_kind text, p_id bigint, p_approve boolean, p_amount numeric, p_percentage numeric, p_remarks text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_cancel_receipt(p_receipt_id bigint, p_reason text, p_replace boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_create_fee_assessment(p_assessment_number text, p_student_account_id bigint, p_academic_year_id integer, p_assessment_type text, p_assessment_date date, p_due_date date, p_items jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_decide_refund(p_refund_request_id bigint, p_approve boolean, p_approved_amount numeric) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_hold_place(p_student_account_id bigint, p_hold_type text, p_reason text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_hold_release(p_hold_id bigint, p_reason text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_holds(p_student_account_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_instalment_apply(p_assessment_id bigint, p_plan_id integer, p_first_due date) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_instalment_cancel(p_assessment_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_instalment_refresh(p_assessment_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_issue_receipt(p_payment_transaction_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_late_fee_suggest(p_assessment_id bigint, p_rule_id bigint, p_as_of date) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_open_account(p_student_number text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_payment_receipts(p_student_account_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_penalty_assess(p_student_account_id bigint, p_fee_type_id bigint, p_amount numeric, p_reason text, p_academic_year_id integer, p_due_date date) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_penalty_waive(p_penalty_id bigint, p_amount numeric, p_reason text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_process_refund(p_refund_transaction_number text, p_refund_request_id bigint, p_refund_mode_id integer, p_amount numeric, p_bank_reference text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_receipt_get(p_receipt_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_record_payment(p_transaction_number text, p_student_account_id bigint, p_payment_mode_id integer, p_amount numeric, p_bank_reference text, p_payer_name text, p_remarks text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_request_refund(p_request_number text, p_student_account_id bigint, p_payment_transaction_id bigint, p_amount numeric, p_reason text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_structure_decide(p_id bigint, p_approve boolean, p_remarks text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_structure_delete(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_structure_get(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_structure_item_delete(p_structure_id bigint, p_item_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_structure_item_save(p_structure_id bigint, p_item_id bigint, p jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_structure_list(p_search text, p_status text, p_limit integer, p_offset integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_structure_new_version(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_structure_save(p_id bigint, p jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.fin_structure_submit(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.global_search(p_q text, p_limit integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.grievance_act(p_grievance_id bigint, p_action_type text, p_notes text, p_new_status text, p_resolution text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.grievance_detail(p_grievance_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.grievance_list(p_search text, p_status text, p_priority text, p_limit integer, p_offset integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.grievance_my() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.grievance_student_respond(p_grievance_id bigint, p_response text, p_notes text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.grievance_submit(p_category_id integer, p_department_id integer, p_subject text, p_description text, p_priority text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.iam_assign_role(p_user_id bigint, p_role_id integer, p_scope_type text, p_scope_entity_id integer, p_reason text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.iam_can_provision() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.iam_link_auth_user(p_email text, p_student_number text, p_employee_number text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.iam_link_person(p_user_id bigint, p_student_number text, p_employee_number text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.iam_mfa_policy_gaps() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.iam_mfa_policy_list() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.iam_mfa_policy_set(p_role_code text, p_required boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.iam_override_end(p_override_id bigint, p_reason text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.iam_override_list(p_user_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.iam_override_set(p_user_id bigint, p_permission_code text, p_effect text, p_scope_type text, p_scope_entity_id integer, p_justification text, p_valid_to timestamp with time zone) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.iam_permission_options(p_search text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.iam_provision_user(p_auth_user uuid, p_email text, p_student_number text, p_employee_number text, p_actor_user_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.iam_revoke_role(p_assignment_id bigint, p_reason text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.iam_roles() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.iam_set_account_status(p_user_id bigint, p_status text, p_reason text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.iam_user_detail(p_user_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.iam_user_list(p_search text, p_status text, p_limit integer, p_offset integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.institution_create(p jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.institution_update(p_id integer, p jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.login_audit_list(p_search text, p_success boolean, p_from timestamp with time zone, p_to timestamp with time zone, p_limit integer, p_offset integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.mentoring_assign(p_student_number text, p_employee_number text, p_start date) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.mentoring_assignment_info(p_assignment_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.mentoring_assignments(p_search text, p_status text, p_limit integer, p_offset integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.mentoring_end_assignment(p_assignment_id bigint, p_status text, p_end_date date) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.mentoring_record_session(p_assignment_id bigint, p_date timestamp with time zone, p_observations text, p_action_plan text, p_follow_up date, p_status text, p_level text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.mentoring_sessions(p_assignment_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.mentoring_update_session(p_session_id bigint, p_date timestamp with time zone, p_observations text, p_action_plan text, p_follow_up date, p_status text, p_level text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.mfa_recovery_generate() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.mfa_recovery_status() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.mfa_recovery_use(p_code text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.mfa_sync() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.my_context() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.my_dashboard() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.my_notification_count() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.my_notifications(p_limit integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.my_profile() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.my_profile_update(p jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.my_recent_logins(p_limit integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.my_results() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.notification_dismiss(p_key text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.notification_dismiss_all() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.offering_generate_courses(p_programme_term_offering_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.record_sections(p_kind text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.ref_delete(p_table text, p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.ref_list() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.ref_rows(p_table text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.ref_save(p_table text, p_id bigint, p jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.ref_schema(p_table text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.registration_candidates(p_offering_id bigint, p_q text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.registration_roster(p_offering_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.registration_term_info(p_term_registration_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.result_compute_term(p_term_registration_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.result_course_sheet(p_course_offering_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.result_publish_term(p_term_registration_id bigint, p_publish boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.result_record_course(p_course_registration_id bigint, p_internal numeric, p_external numeric, p_attempt integer, p_status text, p_remarks text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.result_term_sheet(p_offering_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.section_delete(p_kind text, p_parent_id bigint, p_section text, p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.section_lookup_options(p_table text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.section_rows(p_kind text, p_parent_id bigint, p_section text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.section_save(p_kind text, p_parent_id bigint, p_section text, p_id bigint, p jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.section_schema(p_kind text, p_section text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_assessment_event_guard() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_assessment_mark_guard() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_attendance_session_guard() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_course_result_lock() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_fee_benefit_guard() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_fee_item_sync() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_fee_refund_guard() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_feedback_cycle_guard() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_feedback_item_guard() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_feedback_questionnaire_guard() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_guard_announcement() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_guard_assessment_event() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_guard_attendance_correction_request() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_guard_certificate_hold() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_guard_certificate_request() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_guard_conference_activity_indexing() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_guard_consultancy_project() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_guard_employee_aadhaar() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_guard_employee_bank_account() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_guard_employee_document() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_guard_employee_pan() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_guard_evidence_document() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_guard_journal_metric() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_guard_journal_publication_indexing() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_guard_staff_activity() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_guard_student_activity() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_guard_student_activity_evidence() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_guard_student_course_registration() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_guard_student_document() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_guard_student_term_registration() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_guard_student_term_result() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_guard_term_registration_hold() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_payment_allocation_guard() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_payment_allocation_sync() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_recalc_fee_item_paid(p_item_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_registration_course_guard() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_registration_term_guard() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_sync_fee_assessment_totals(p_assessment_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_term_result_lock() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_timetable_guard() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_touch_updated_at() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_user_permission_override_scope() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sims_user_role_assignment_scope() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.staff_activity_delete(p_activity_id bigint, p_reason text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.staff_activity_get(p_activity_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.staff_activity_list(p_employee_id bigint, p_search text, p_approval text, p_group text, p_limit integer, p_offset integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.staff_activity_report(p_year integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.staff_activity_review(p_activity_id bigint, p_step text, p_decision text, p_remarks text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.staff_activity_save(p_activity_id bigint, p_employee_id bigint, p jsonb, p_detail jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.staff_activity_submit(p_activity_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.staff_contributor_add(p_activity_id bigint, p_employee_id bigint, p_external_name text, p_external_email text, p_affiliation text, p_role_type_id integer, p_is_corresponding boolean, p_details text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.staff_contributor_remove(p_contributor_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.staff_detail_schema(p_activity_type_id integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.staff_evidence_add(p_activity_id bigint, p_document_type_id integer, p_evidence_type_id integer, p_title text, p_issue_date date, p_issuing_authority text, p_certificate_number text, p_storage_key text, p_file_name text, p_mime text, p_size bigint, p_checksum text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.staff_evidence_delete(p_evidence_id bigint, p_reason text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.staff_evidence_download_info(p_evidence_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.staff_evidence_replace(p_evidence_id bigint, p_reason text, p_storage_key text, p_file_name text, p_mime text, p_size bigint, p_checksum text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.staff_indexing_delete(p_activity_id bigint, p_agency_id integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.staff_indexing_list(p_activity_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.staff_indexing_save(p_activity_id bigint, p_agency_id integer, p_status text, p_year integer, p_url text, p_remarks text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.staff_lookup_add(p_table text, p jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.staff_lookup_options(p_table text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.staff_lookup_schema(p_table text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.student_activity_delete(p_activity_id bigint, p_reason text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.student_activity_evidence_add(p_activity_id bigint, p_document_type_id integer, p_evidence_type_id integer, p_title text, p_issue_date date, p_issuing_authority text, p_certificate_number text, p_storage_key text, p_file_name text, p_mime text, p_size bigint, p_checksum text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.student_activity_evidence_delete(p_evidence_id bigint, p_reason text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.student_activity_evidence_download_info(p_evidence_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.student_activity_evidence_replace(p_evidence_id bigint, p_reason text, p_storage_key text, p_file_name text, p_mime text, p_size bigint, p_checksum text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.student_activity_get(p_activity_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.student_activity_list(p_student_id bigint, p_search text, p_approval text, p_limit integer, p_offset integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.student_activity_report(p_year integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.student_activity_review(p_activity_id bigint, p_step text, p_decision text, p_remarks text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.student_activity_save(p_activity_id bigint, p_student_id bigint, p jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.student_activity_submit(p_activity_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.student_activity_team_add(p_activity_id bigint, p_student_id bigint, p_external_name text, p_external_email text, p_role text, p_is_lead boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.student_activity_team_remove(p_member_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.student_document_delete(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.student_document_download_info(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.student_document_list(p_student_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.student_document_register(p_student_id bigint, p_document_type_id integer, p_storage_key text, p_file_name text, p_mime_type text, p_size bigint, p_checksum text, p_document_number text, p_issue_date date, p_expiry_date date) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.student_document_review(p_id bigint, p_decision text, p_remarks text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.student_register(p_student jsonb, p_enrolment jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.svc_my_terms() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.svc_request_cancel(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.svc_request_create(p_kind text, p_term_id bigint, p_planned_date date, p_detail text, p_student_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.svc_request_decide(p_id bigint, p_action text, p_remarks text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.svc_request_list(p_kind text, p_status text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.teaching_populate_roster(p_cos_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.timetable_assignments(p_cos_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.timetable_entries(p_pto bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.timetable_generate_sessions(p_cos_id bigint, p_from date, p_to date) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.timetable_offering_info(p_pto bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.timetable_offerings(p_term bigint, p_programme integer, p_limit integer, p_offset integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.timetable_rooms() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.timetable_sections(p_pto bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.timetable_slots() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.activity_actor(p_student bigint, p_perm text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.activity_child_ok(p_activity_id bigint, p_detail_table text, p_perm_prefix text, p_action text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.admission_action_for(p_to text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.admission_authorize(p_application_id bigint, p_action text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.admission_transition_ok(p_from text, p_to text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.announcement_audience_ok(p_audience text, p_department integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.announcement_can(p_action text, p_department integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.announcement_check(p_type integer, p_department integer, p_title text, p_description text, p_from timestamp with time zone, p_to timestamp with time zone, p_audience text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.announcement_editable(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.announcement_visible(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.asm_authorize(p_course_offering_id bigint, p_module text, p_action text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.astatus(p_code text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.att_authorize_cos(p_cos_id bigint, p_module text, p_action text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.att_session_cos(p_session_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.audit_manual(p_module text, p_action text, p_table text, p_id bigint, p_before jsonb, p_after jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.audit_row() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.caller_has_role(p_role_code text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.can_campus(p_codes text[], p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.can_department(p_codes text[], p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.can_employee(p_codes text[], p_id bigint, p_write boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.can_global(p_codes text[]) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.can_institution(p_codes text[], p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.can_programme(p_codes text[], p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.can_see_applicant(p_applicant_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.can_student(p_codes text[], p_id bigint, p_write boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.can_use_announcement_path(p_name text, p_write boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.can_use_employee_doc_path(p_name text, p_write boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.can_use_student_doc_path(p_name text, p_write boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.can_user(p_codes text[], p_id bigint, p_write boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.check_employee_upload(p_employee bigint, p_key text, p_file_name text, p_mime text, p_size bigint, p_checksum text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.check_institution_fields(p jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.check_student_upload(p_student bigint, p_key text, p_file_name text, p_mime text, p_size bigint, p_checksum text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.course_result_published(p_course_registration_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.covers(p_codes text[], p_inst bigint, p_campus bigint, p_dept bigint, p_prog bigint, p_self_ok boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.current_employee_id() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.current_student_id() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.current_user_id() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.doc_announcement_id(p_name text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.doc_employee_id(p_name text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.doc_student_id(p_name text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.eff(p_codes text[]) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.eff_set_of(p_codes text[]) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.emp_all_can(p_emp bigint, p_action text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.emp_can(p_emp bigint, p_resource text, p_action text, p_write boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.emp_doc_rule_ok(p_doc bigint, p_need text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.emp_is_owner(p_emp bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.emp_sensitive_log(p_emp bigint, p_action text, p_entity text, p_id bigint, p_purpose text, p_doc bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.emp_sensitive_row(p_kind text, p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.emp_write_allowed(p_emp bigint, p_resource text, p_existing_status text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.employee_institution_immutable() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.event_published(p_event_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.exec_dml(p_sql text, p_json jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.exec_dml_id(p_sql text, p_json jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.feedback_min_responses() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.feedback_questionnaire_locked(p_questionnaire_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.feedback_rating_max() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.fin_assessment_student(p_assessment_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.fin_audit(p_action text, p_entity text, p_id bigint, p_old jsonb, p_new jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.fin_authorize(p_student_account_id bigint, p_resource text, p_action text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.fin_authorize_student(p_student_id bigint, p_resource text, p_action text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.fin_benefit_load(p_kind text, p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.fin_check_amount(p_amount numeric, p_what text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.fin_creator_is_caller(p_entity text, p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.fin_editable_item(p_item_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.fin_hold_active(p_student_id bigint, p_type text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.fin_next_receipt_number() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.fin_refresh_status(p_item_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.fin_refunded_on_payment(p_payment_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.form_columns(p_table text, p_exclude text[]) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.fs_can(p_institution bigint, p_programme bigint, p_action text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.fs_load(p_id bigint, p_action text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.grievance_transition_ok(p_from text, p_to text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.has_any_grant(p_codes text[]) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.indexing_table(p_activity_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.is_active_member() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.is_me_student(p_student bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.is_mentor_of(p_assignment_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.jwt_aal() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.link_auth_user(p_auth_user uuid, p_user_id bigint, p_actor text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.mentoring_audit(p_action text, p_session_id bigint, p_assignment_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.mentoring_can_see(p_assignment_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.mentoring_check_session(p_date timestamp with time zone, p_observations text, p_action_plan text, p_follow_up date, p_status text, p_level text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.mfa_setup_required(p_user bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.notifications_all() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_admission_application_application_id_admitted_student_id(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_announcement_announcement_id_department_id(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_assessment_component_assessment_component_id_c_556a8c03e6(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_building_building_id_campus_id(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_class_section_class_section_id_programme_term_offering_id(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_conference_activity_staff_activity_id_staff_activity_id(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_course_catalog_course_id_owning_department_id(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_course_offering_course_offering_id_programme_t_6af0a6bfe1(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_course_offering_section_course_offering_sectio_7deeb92c3b(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_course_offering_section_student_course_offerin_c13eb2db9e(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_curriculum_scheme_curriculum_scheme_id_programme_id(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_employee_document_employee_document_id_employee_id(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_evidence_document_evidence_document_id_staff_activity_id(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_fee_structure_fee_structure_id_programme_id(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_feedback_response_feedback_response_id_term_re_148ea414c7(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_funded_research_project_staff_activity_id_prin_85828402ed(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_grievance_grievance_id_student_id(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_journal_publication_staff_activity_id_staff_activity_id(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_mentor_assignment_mentor_assignment_id_student_id(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_payment_transaction_payment_transaction_id_stu_04cbabf9c9(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_programme_term_offering_programme_term_offerin_dd560b84f3(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_refund_request_refund_request_id_student_account_id(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_staff_activity_staff_activity_id_employee_id(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_staff_professional_contribution_staff_activity_a926f20bfe(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_student_activity_evidence_student_activity_evi_20620f7c4c(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_student_activity_student_activity_id_student_id(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_student_attendance_class_session_id_course_off_a5763429ec(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_student_course_registration_course_registratio_92ae207afd(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_student_fee_assessment_fee_assessment_id_stude_d877e246a8(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_student_fee_assessment_item_assessment_item_id_81c18f4ea9(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_student_fee_concession_student_concession_id_student_id(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_student_financial_account_student_account_id_student_id(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_student_programme_enrolment_enrolment_id_student_id(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.nx_student_term_registration_term_registration_id_7e00744235(p_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.other_super_admins(p_user_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.pii_decrypt(p bytea) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.pii_encrypt(p text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.pii_fingerprint(p text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.pii_key() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.pk_column(p_table text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.programme_institution(p_programme integer) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.programme_of_cos(p_cos_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.programme_of_offering(p_course_offering_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.ref_def(p_table text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.ref_tables() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.request_header(p_name text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.section_can(p_kind text, p_perm_prefix text, p_action text, p_parent_id bigint) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.section_def(p_kind text, p_section text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.section_option_tables() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.staff_actor(p_employee bigint, p_perm text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.staff_detail_table(p_type_code text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.staff_lookup_tables() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.staff_option_tables() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.storage_key_is_orphan(p_name text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.svc_hold_check(p_student bigint, p_kind text, p_step text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.user_id_any_aal() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.verhoeff_valid(p text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.vstatus(p_code text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.write_detail(p_table text, p_key_col text, p_id bigint, p_detail jsonb, p_insert boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION sims_private.write_row(p_table text, p_pk text, p_parent_col text, p_parent_id bigint, p_id bigint, p jsonb) FROM PUBLIC;

GRANT DELETE ON TABLE public.academic_term TO authenticated;
GRANT INSERT ON TABLE public.academic_term TO authenticated;
GRANT UPDATE ON TABLE public.academic_term TO authenticated;
GRANT DELETE ON TABLE public.academic_term TO postgres;
GRANT INSERT ON TABLE public.academic_term TO postgres;
GRANT MAINTAIN ON TABLE public.academic_term TO postgres;
GRANT REFERENCES ON TABLE public.academic_term TO postgres;
GRANT SELECT ON TABLE public.academic_term TO postgres;
GRANT TRIGGER ON TABLE public.academic_term TO postgres;
GRANT TRUNCATE ON TABLE public.academic_term TO postgres;
GRANT UPDATE ON TABLE public.academic_term TO postgres;
GRANT DELETE ON TABLE public.academic_term TO service_role;
GRANT INSERT ON TABLE public.academic_term TO service_role;
GRANT MAINTAIN ON TABLE public.academic_term TO service_role;
GRANT REFERENCES ON TABLE public.academic_term TO service_role;
GRANT SELECT ON TABLE public.academic_term TO service_role;
GRANT TRIGGER ON TABLE public.academic_term TO service_role;
GRANT TRUNCATE ON TABLE public.academic_term TO service_role;
GRANT UPDATE ON TABLE public.academic_term TO service_role;
GRANT SELECT ON TABLE public.academic_term_academic_term_id_seq TO postgres;
GRANT UPDATE ON TABLE public.academic_term_academic_term_id_seq TO postgres;
GRANT USAGE ON TABLE public.academic_term_academic_term_id_seq TO postgres;
GRANT SELECT ON TABLE public.academic_term_academic_term_id_seq TO service_role;
GRANT UPDATE ON TABLE public.academic_term_academic_term_id_seq TO service_role;
GRANT USAGE ON TABLE public.academic_term_academic_term_id_seq TO service_role;
GRANT DELETE ON TABLE public.academic_year TO authenticated;
GRANT INSERT ON TABLE public.academic_year TO authenticated;
GRANT UPDATE ON TABLE public.academic_year TO authenticated;
GRANT DELETE ON TABLE public.academic_year TO postgres;
GRANT INSERT ON TABLE public.academic_year TO postgres;
GRANT MAINTAIN ON TABLE public.academic_year TO postgres;
GRANT REFERENCES ON TABLE public.academic_year TO postgres;
GRANT SELECT ON TABLE public.academic_year TO postgres;
GRANT TRIGGER ON TABLE public.academic_year TO postgres;
GRANT TRUNCATE ON TABLE public.academic_year TO postgres;
GRANT UPDATE ON TABLE public.academic_year TO postgres;
GRANT DELETE ON TABLE public.academic_year TO service_role;
GRANT INSERT ON TABLE public.academic_year TO service_role;
GRANT MAINTAIN ON TABLE public.academic_year TO service_role;
GRANT REFERENCES ON TABLE public.academic_year TO service_role;
GRANT SELECT ON TABLE public.academic_year TO service_role;
GRANT TRIGGER ON TABLE public.academic_year TO service_role;
GRANT TRUNCATE ON TABLE public.academic_year TO service_role;
GRANT UPDATE ON TABLE public.academic_year TO service_role;
GRANT SELECT ON TABLE public.academic_year_academic_year_id_seq TO postgres;
GRANT UPDATE ON TABLE public.academic_year_academic_year_id_seq TO postgres;
GRANT USAGE ON TABLE public.academic_year_academic_year_id_seq TO postgres;
GRANT SELECT ON TABLE public.academic_year_academic_year_id_seq TO service_role;
GRANT UPDATE ON TABLE public.academic_year_academic_year_id_seq TO service_role;
GRANT USAGE ON TABLE public.academic_year_academic_year_id_seq TO service_role;
GRANT DELETE ON TABLE public.access_action TO postgres;
GRANT INSERT ON TABLE public.access_action TO postgres;
GRANT MAINTAIN ON TABLE public.access_action TO postgres;
GRANT REFERENCES ON TABLE public.access_action TO postgres;
GRANT SELECT ON TABLE public.access_action TO postgres;
GRANT TRIGGER ON TABLE public.access_action TO postgres;
GRANT TRUNCATE ON TABLE public.access_action TO postgres;
GRANT UPDATE ON TABLE public.access_action TO postgres;
GRANT DELETE ON TABLE public.access_action TO service_role;
GRANT INSERT ON TABLE public.access_action TO service_role;
GRANT MAINTAIN ON TABLE public.access_action TO service_role;
GRANT REFERENCES ON TABLE public.access_action TO service_role;
GRANT SELECT ON TABLE public.access_action TO service_role;
GRANT TRIGGER ON TABLE public.access_action TO service_role;
GRANT TRUNCATE ON TABLE public.access_action TO service_role;
GRANT UPDATE ON TABLE public.access_action TO service_role;
GRANT SELECT ON TABLE public.access_action_access_action_id_seq TO postgres;
GRANT UPDATE ON TABLE public.access_action_access_action_id_seq TO postgres;
GRANT USAGE ON TABLE public.access_action_access_action_id_seq TO postgres;
GRANT SELECT ON TABLE public.access_action_access_action_id_seq TO service_role;
GRANT UPDATE ON TABLE public.access_action_access_action_id_seq TO service_role;
GRANT USAGE ON TABLE public.access_action_access_action_id_seq TO service_role;
GRANT DELETE ON TABLE public.access_module TO postgres;
GRANT INSERT ON TABLE public.access_module TO postgres;
GRANT MAINTAIN ON TABLE public.access_module TO postgres;
GRANT REFERENCES ON TABLE public.access_module TO postgres;
GRANT SELECT ON TABLE public.access_module TO postgres;
GRANT TRIGGER ON TABLE public.access_module TO postgres;
GRANT TRUNCATE ON TABLE public.access_module TO postgres;
GRANT UPDATE ON TABLE public.access_module TO postgres;
GRANT DELETE ON TABLE public.access_module TO service_role;
GRANT INSERT ON TABLE public.access_module TO service_role;
GRANT MAINTAIN ON TABLE public.access_module TO service_role;
GRANT REFERENCES ON TABLE public.access_module TO service_role;
GRANT SELECT ON TABLE public.access_module TO service_role;
GRANT TRIGGER ON TABLE public.access_module TO service_role;
GRANT TRUNCATE ON TABLE public.access_module TO service_role;
GRANT UPDATE ON TABLE public.access_module TO service_role;
GRANT SELECT ON TABLE public.access_module_access_module_id_seq TO postgres;
GRANT UPDATE ON TABLE public.access_module_access_module_id_seq TO postgres;
GRANT USAGE ON TABLE public.access_module_access_module_id_seq TO postgres;
GRANT SELECT ON TABLE public.access_module_access_module_id_seq TO service_role;
GRANT UPDATE ON TABLE public.access_module_access_module_id_seq TO service_role;
GRANT USAGE ON TABLE public.access_module_access_module_id_seq TO service_role;
GRANT DELETE ON TABLE public.access_resource TO postgres;
GRANT INSERT ON TABLE public.access_resource TO postgres;
GRANT MAINTAIN ON TABLE public.access_resource TO postgres;
GRANT REFERENCES ON TABLE public.access_resource TO postgres;
GRANT SELECT ON TABLE public.access_resource TO postgres;
GRANT TRIGGER ON TABLE public.access_resource TO postgres;
GRANT TRUNCATE ON TABLE public.access_resource TO postgres;
GRANT UPDATE ON TABLE public.access_resource TO postgres;
GRANT DELETE ON TABLE public.access_resource TO service_role;
GRANT INSERT ON TABLE public.access_resource TO service_role;
GRANT MAINTAIN ON TABLE public.access_resource TO service_role;
GRANT REFERENCES ON TABLE public.access_resource TO service_role;
GRANT SELECT ON TABLE public.access_resource TO service_role;
GRANT TRIGGER ON TABLE public.access_resource TO service_role;
GRANT TRUNCATE ON TABLE public.access_resource TO service_role;
GRANT UPDATE ON TABLE public.access_resource TO service_role;
GRANT SELECT ON TABLE public.access_resource_access_resource_id_seq TO postgres;
GRANT UPDATE ON TABLE public.access_resource_access_resource_id_seq TO postgres;
GRANT USAGE ON TABLE public.access_resource_access_resource_id_seq TO postgres;
GRANT SELECT ON TABLE public.access_resource_access_resource_id_seq TO service_role;
GRANT UPDATE ON TABLE public.access_resource_access_resource_id_seq TO service_role;
GRANT USAGE ON TABLE public.access_resource_access_resource_id_seq TO service_role;
GRANT DELETE ON TABLE public.activity_audit TO postgres;
GRANT INSERT ON TABLE public.activity_audit TO postgres;
GRANT MAINTAIN ON TABLE public.activity_audit TO postgres;
GRANT REFERENCES ON TABLE public.activity_audit TO postgres;
GRANT SELECT ON TABLE public.activity_audit TO postgres;
GRANT TRIGGER ON TABLE public.activity_audit TO postgres;
GRANT TRUNCATE ON TABLE public.activity_audit TO postgres;
GRANT UPDATE ON TABLE public.activity_audit TO postgres;
GRANT DELETE ON TABLE public.activity_audit TO service_role;
GRANT INSERT ON TABLE public.activity_audit TO service_role;
GRANT MAINTAIN ON TABLE public.activity_audit TO service_role;
GRANT REFERENCES ON TABLE public.activity_audit TO service_role;
GRANT SELECT ON TABLE public.activity_audit TO service_role;
GRANT TRIGGER ON TABLE public.activity_audit TO service_role;
GRANT TRUNCATE ON TABLE public.activity_audit TO service_role;
GRANT UPDATE ON TABLE public.activity_audit TO service_role;
GRANT SELECT ON TABLE public.activity_audit_activity_audit_id_seq TO postgres;
GRANT UPDATE ON TABLE public.activity_audit_activity_audit_id_seq TO postgres;
GRANT USAGE ON TABLE public.activity_audit_activity_audit_id_seq TO postgres;
GRANT SELECT ON TABLE public.activity_audit_activity_audit_id_seq TO service_role;
GRANT UPDATE ON TABLE public.activity_audit_activity_audit_id_seq TO service_role;
GRANT USAGE ON TABLE public.activity_audit_activity_audit_id_seq TO service_role;
GRANT DELETE ON TABLE public.activity_evidence_requirement TO authenticated;
GRANT INSERT ON TABLE public.activity_evidence_requirement TO authenticated;
GRANT UPDATE ON TABLE public.activity_evidence_requirement TO authenticated;
GRANT DELETE ON TABLE public.activity_evidence_requirement TO postgres;
GRANT INSERT ON TABLE public.activity_evidence_requirement TO postgres;
GRANT MAINTAIN ON TABLE public.activity_evidence_requirement TO postgres;
GRANT REFERENCES ON TABLE public.activity_evidence_requirement TO postgres;
GRANT SELECT ON TABLE public.activity_evidence_requirement TO postgres;
GRANT TRIGGER ON TABLE public.activity_evidence_requirement TO postgres;
GRANT TRUNCATE ON TABLE public.activity_evidence_requirement TO postgres;
GRANT UPDATE ON TABLE public.activity_evidence_requirement TO postgres;
GRANT DELETE ON TABLE public.activity_evidence_requirement TO service_role;
GRANT INSERT ON TABLE public.activity_evidence_requirement TO service_role;
GRANT MAINTAIN ON TABLE public.activity_evidence_requirement TO service_role;
GRANT REFERENCES ON TABLE public.activity_evidence_requirement TO service_role;
GRANT SELECT ON TABLE public.activity_evidence_requirement TO service_role;
GRANT TRIGGER ON TABLE public.activity_evidence_requirement TO service_role;
GRANT TRUNCATE ON TABLE public.activity_evidence_requirement TO service_role;
GRANT UPDATE ON TABLE public.activity_evidence_requirement TO service_role;
GRANT SELECT ON TABLE public.activity_evidence_requirement_activity_evidence_requirement_seq TO postgres;
GRANT UPDATE ON TABLE public.activity_evidence_requirement_activity_evidence_requirement_seq TO postgres;
GRANT USAGE ON TABLE public.activity_evidence_requirement_activity_evidence_requirement_seq TO postgres;
GRANT SELECT ON TABLE public.activity_evidence_requirement_activity_evidence_requirement_seq TO service_role;
GRANT UPDATE ON TABLE public.activity_evidence_requirement_activity_evidence_requirement_seq TO service_role;
GRANT USAGE ON TABLE public.activity_evidence_requirement_activity_evidence_requirement_seq TO service_role;
GRANT DELETE ON TABLE public.activity_type TO authenticated;
GRANT INSERT ON TABLE public.activity_type TO authenticated;
GRANT UPDATE ON TABLE public.activity_type TO authenticated;
GRANT DELETE ON TABLE public.activity_type TO postgres;
GRANT INSERT ON TABLE public.activity_type TO postgres;
GRANT MAINTAIN ON TABLE public.activity_type TO postgres;
GRANT REFERENCES ON TABLE public.activity_type TO postgres;
GRANT SELECT ON TABLE public.activity_type TO postgres;
GRANT TRIGGER ON TABLE public.activity_type TO postgres;
GRANT TRUNCATE ON TABLE public.activity_type TO postgres;
GRANT UPDATE ON TABLE public.activity_type TO postgres;
GRANT DELETE ON TABLE public.activity_type TO service_role;
GRANT INSERT ON TABLE public.activity_type TO service_role;
GRANT MAINTAIN ON TABLE public.activity_type TO service_role;
GRANT REFERENCES ON TABLE public.activity_type TO service_role;
GRANT SELECT ON TABLE public.activity_type TO service_role;
GRANT TRIGGER ON TABLE public.activity_type TO service_role;
GRANT TRUNCATE ON TABLE public.activity_type TO service_role;
GRANT UPDATE ON TABLE public.activity_type TO service_role;
GRANT SELECT ON TABLE public.activity_type_activity_type_id_seq TO postgres;
GRANT UPDATE ON TABLE public.activity_type_activity_type_id_seq TO postgres;
GRANT USAGE ON TABLE public.activity_type_activity_type_id_seq TO postgres;
GRANT SELECT ON TABLE public.activity_type_activity_type_id_seq TO service_role;
GRANT UPDATE ON TABLE public.activity_type_activity_type_id_seq TO service_role;
GRANT USAGE ON TABLE public.activity_type_activity_type_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.admission_admit(p_application_id bigint, p_student jsonb, p_enrolment jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admission_admit(p_application_id bigint, p_student jsonb, p_enrolment jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.admission_admit(p_application_id bigint, p_student jsonb, p_enrolment jsonb) TO service_role;
GRANT DELETE ON TABLE public.admission_applicant TO postgres;
GRANT INSERT ON TABLE public.admission_applicant TO postgres;
GRANT MAINTAIN ON TABLE public.admission_applicant TO postgres;
GRANT REFERENCES ON TABLE public.admission_applicant TO postgres;
GRANT SELECT ON TABLE public.admission_applicant TO postgres;
GRANT TRIGGER ON TABLE public.admission_applicant TO postgres;
GRANT TRUNCATE ON TABLE public.admission_applicant TO postgres;
GRANT UPDATE ON TABLE public.admission_applicant TO postgres;
GRANT DELETE ON TABLE public.admission_applicant TO service_role;
GRANT INSERT ON TABLE public.admission_applicant TO service_role;
GRANT MAINTAIN ON TABLE public.admission_applicant TO service_role;
GRANT REFERENCES ON TABLE public.admission_applicant TO service_role;
GRANT SELECT ON TABLE public.admission_applicant TO service_role;
GRANT TRIGGER ON TABLE public.admission_applicant TO service_role;
GRANT TRUNCATE ON TABLE public.admission_applicant TO service_role;
GRANT UPDATE ON TABLE public.admission_applicant TO service_role;
GRANT SELECT ON TABLE public.admission_applicant_admission_applicant_id_seq TO postgres;
GRANT UPDATE ON TABLE public.admission_applicant_admission_applicant_id_seq TO postgres;
GRANT USAGE ON TABLE public.admission_applicant_admission_applicant_id_seq TO postgres;
GRANT SELECT ON TABLE public.admission_applicant_admission_applicant_id_seq TO service_role;
GRANT UPDATE ON TABLE public.admission_applicant_admission_applicant_id_seq TO service_role;
GRANT USAGE ON TABLE public.admission_applicant_admission_applicant_id_seq TO service_role;
GRANT DELETE ON TABLE public.admission_application TO postgres;
GRANT INSERT ON TABLE public.admission_application TO postgres;
GRANT MAINTAIN ON TABLE public.admission_application TO postgres;
GRANT REFERENCES ON TABLE public.admission_application TO postgres;
GRANT SELECT ON TABLE public.admission_application TO postgres;
GRANT TRIGGER ON TABLE public.admission_application TO postgres;
GRANT TRUNCATE ON TABLE public.admission_application TO postgres;
GRANT UPDATE ON TABLE public.admission_application TO postgres;
GRANT DELETE ON TABLE public.admission_application TO service_role;
GRANT INSERT ON TABLE public.admission_application TO service_role;
GRANT MAINTAIN ON TABLE public.admission_application TO service_role;
GRANT REFERENCES ON TABLE public.admission_application TO service_role;
GRANT SELECT ON TABLE public.admission_application TO service_role;
GRANT TRIGGER ON TABLE public.admission_application TO service_role;
GRANT TRUNCATE ON TABLE public.admission_application TO service_role;
GRANT UPDATE ON TABLE public.admission_application TO service_role;
GRANT SELECT ON TABLE public.admission_application_application_id_seq TO postgres;
GRANT UPDATE ON TABLE public.admission_application_application_id_seq TO postgres;
GRANT USAGE ON TABLE public.admission_application_application_id_seq TO postgres;
GRANT SELECT ON TABLE public.admission_application_application_id_seq TO service_role;
GRANT UPDATE ON TABLE public.admission_application_application_id_seq TO service_role;
GRANT USAGE ON TABLE public.admission_application_application_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.admission_apply(p_applicant jsonb, p_application jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admission_apply(p_applicant jsonb, p_application jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.admission_apply(p_applicant jsonb, p_application jsonb) TO service_role;
GRANT DELETE ON TABLE public.admission_category TO authenticated;
GRANT INSERT ON TABLE public.admission_category TO authenticated;
GRANT UPDATE ON TABLE public.admission_category TO authenticated;
GRANT DELETE ON TABLE public.admission_category TO postgres;
GRANT INSERT ON TABLE public.admission_category TO postgres;
GRANT MAINTAIN ON TABLE public.admission_category TO postgres;
GRANT REFERENCES ON TABLE public.admission_category TO postgres;
GRANT SELECT ON TABLE public.admission_category TO postgres;
GRANT TRIGGER ON TABLE public.admission_category TO postgres;
GRANT TRUNCATE ON TABLE public.admission_category TO postgres;
GRANT UPDATE ON TABLE public.admission_category TO postgres;
GRANT DELETE ON TABLE public.admission_category TO service_role;
GRANT INSERT ON TABLE public.admission_category TO service_role;
GRANT MAINTAIN ON TABLE public.admission_category TO service_role;
GRANT REFERENCES ON TABLE public.admission_category TO service_role;
GRANT SELECT ON TABLE public.admission_category TO service_role;
GRANT TRIGGER ON TABLE public.admission_category TO service_role;
GRANT TRUNCATE ON TABLE public.admission_category TO service_role;
GRANT UPDATE ON TABLE public.admission_category TO service_role;
GRANT SELECT ON TABLE public.admission_category_admission_category_id_seq TO postgres;
GRANT UPDATE ON TABLE public.admission_category_admission_category_id_seq TO postgres;
GRANT USAGE ON TABLE public.admission_category_admission_category_id_seq TO postgres;
GRANT SELECT ON TABLE public.admission_category_admission_category_id_seq TO service_role;
GRANT UPDATE ON TABLE public.admission_category_admission_category_id_seq TO service_role;
GRANT USAGE ON TABLE public.admission_category_admission_category_id_seq TO service_role;
GRANT DELETE ON TABLE public.admission_payment TO postgres;
GRANT INSERT ON TABLE public.admission_payment TO postgres;
GRANT MAINTAIN ON TABLE public.admission_payment TO postgres;
GRANT REFERENCES ON TABLE public.admission_payment TO postgres;
GRANT SELECT ON TABLE public.admission_payment TO postgres;
GRANT TRIGGER ON TABLE public.admission_payment TO postgres;
GRANT TRUNCATE ON TABLE public.admission_payment TO postgres;
GRANT UPDATE ON TABLE public.admission_payment TO postgres;
GRANT DELETE ON TABLE public.admission_payment TO service_role;
GRANT INSERT ON TABLE public.admission_payment TO service_role;
GRANT MAINTAIN ON TABLE public.admission_payment TO service_role;
GRANT REFERENCES ON TABLE public.admission_payment TO service_role;
GRANT SELECT ON TABLE public.admission_payment TO service_role;
GRANT TRIGGER ON TABLE public.admission_payment TO service_role;
GRANT TRUNCATE ON TABLE public.admission_payment TO service_role;
GRANT UPDATE ON TABLE public.admission_payment TO service_role;
GRANT SELECT ON TABLE public.admission_payment_admission_payment_id_seq TO postgres;
GRANT UPDATE ON TABLE public.admission_payment_admission_payment_id_seq TO postgres;
GRANT USAGE ON TABLE public.admission_payment_admission_payment_id_seq TO postgres;
GRANT SELECT ON TABLE public.admission_payment_admission_payment_id_seq TO service_role;
GRANT UPDATE ON TABLE public.admission_payment_admission_payment_id_seq TO service_role;
GRANT USAGE ON TABLE public.admission_payment_admission_payment_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.admission_set_status(p_application_id bigint, p_new_status text, p_remarks text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admission_set_status(p_application_id bigint, p_new_status text, p_remarks text) TO postgres;
GRANT EXECUTE ON FUNCTION public.admission_set_status(p_application_id bigint, p_new_status text, p_remarks text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admission_update_applicant(p_applicant_id bigint, p jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admission_update_applicant(p_applicant_id bigint, p jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.admission_update_applicant(p_applicant_id bigint, p jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.admission_update_application(p_application_id bigint, p jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admission_update_application(p_application_id bigint, p jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.admission_update_application(p_application_id bigint, p jsonb) TO service_role;
GRANT DELETE ON TABLE public.announcement TO postgres;
GRANT INSERT ON TABLE public.announcement TO postgres;
GRANT MAINTAIN ON TABLE public.announcement TO postgres;
GRANT REFERENCES ON TABLE public.announcement TO postgres;
GRANT SELECT ON TABLE public.announcement TO postgres;
GRANT TRIGGER ON TABLE public.announcement TO postgres;
GRANT TRUNCATE ON TABLE public.announcement TO postgres;
GRANT UPDATE ON TABLE public.announcement TO postgres;
GRANT DELETE ON TABLE public.announcement TO service_role;
GRANT INSERT ON TABLE public.announcement TO service_role;
GRANT MAINTAIN ON TABLE public.announcement TO service_role;
GRANT REFERENCES ON TABLE public.announcement TO service_role;
GRANT SELECT ON TABLE public.announcement TO service_role;
GRANT TRIGGER ON TABLE public.announcement TO service_role;
GRANT TRUNCATE ON TABLE public.announcement TO service_role;
GRANT UPDATE ON TABLE public.announcement TO service_role;
GRANT SELECT ON TABLE public.announcement_announcement_id_seq TO postgres;
GRANT UPDATE ON TABLE public.announcement_announcement_id_seq TO postgres;
GRANT USAGE ON TABLE public.announcement_announcement_id_seq TO postgres;
GRANT SELECT ON TABLE public.announcement_announcement_id_seq TO service_role;
GRANT UPDATE ON TABLE public.announcement_announcement_id_seq TO service_role;
GRANT USAGE ON TABLE public.announcement_announcement_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.announcement_archive(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.announcement_archive(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.announcement_archive(p_id bigint) TO service_role;
GRANT DELETE ON TABLE public.announcement_attachment TO postgres;
GRANT INSERT ON TABLE public.announcement_attachment TO postgres;
GRANT MAINTAIN ON TABLE public.announcement_attachment TO postgres;
GRANT REFERENCES ON TABLE public.announcement_attachment TO postgres;
GRANT SELECT ON TABLE public.announcement_attachment TO postgres;
GRANT TRIGGER ON TABLE public.announcement_attachment TO postgres;
GRANT TRUNCATE ON TABLE public.announcement_attachment TO postgres;
GRANT UPDATE ON TABLE public.announcement_attachment TO postgres;
GRANT DELETE ON TABLE public.announcement_attachment TO service_role;
GRANT INSERT ON TABLE public.announcement_attachment TO service_role;
GRANT MAINTAIN ON TABLE public.announcement_attachment TO service_role;
GRANT REFERENCES ON TABLE public.announcement_attachment TO service_role;
GRANT SELECT ON TABLE public.announcement_attachment TO service_role;
GRANT TRIGGER ON TABLE public.announcement_attachment TO service_role;
GRANT TRUNCATE ON TABLE public.announcement_attachment TO service_role;
GRANT UPDATE ON TABLE public.announcement_attachment TO service_role;
GRANT EXECUTE ON FUNCTION public.announcement_attachment_download_info(p_id bigint, p_file_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.announcement_attachment_download_info(p_id bigint, p_file_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.announcement_attachment_download_info(p_id bigint, p_file_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.announcement_attachment_list(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.announcement_attachment_list(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.announcement_attachment_list(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.announcement_attachment_register(p_id bigint, p_storage_key text, p_file_name text, p_mime_type text, p_size bigint, p_checksum text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.announcement_attachment_register(p_id bigint, p_storage_key text, p_file_name text, p_mime_type text, p_size bigint, p_checksum text) TO postgres;
GRANT EXECUTE ON FUNCTION public.announcement_attachment_register(p_id bigint, p_storage_key text, p_file_name text, p_mime_type text, p_size bigint, p_checksum text) TO service_role;
GRANT EXECUTE ON FUNCTION public.announcement_attachment_remove(p_id bigint, p_file_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.announcement_attachment_remove(p_id bigint, p_file_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.announcement_attachment_remove(p_id bigint, p_file_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.announcement_can_post_global() TO authenticated;
GRANT EXECUTE ON FUNCTION public.announcement_can_post_global() TO postgres;
GRANT EXECUTE ON FUNCTION public.announcement_can_post_global() TO service_role;
GRANT EXECUTE ON FUNCTION public.announcement_decide(p_id bigint, p_approve boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.announcement_decide(p_id bigint, p_approve boolean) TO postgres;
GRANT EXECUTE ON FUNCTION public.announcement_decide(p_id bigint, p_approve boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.announcement_detail(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.announcement_detail(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.announcement_detail(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.announcement_save(p_id bigint, p_type_id integer, p_department_id integer, p_title text, p_description text, p_publish_from timestamp with time zone, p_publish_to timestamp with time zone, p_audience text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.announcement_save(p_id bigint, p_type_id integer, p_department_id integer, p_title text, p_description text, p_publish_from timestamp with time zone, p_publish_to timestamp with time zone, p_audience text) TO postgres;
GRANT EXECUTE ON FUNCTION public.announcement_save(p_id bigint, p_type_id integer, p_department_id integer, p_title text, p_description text, p_publish_from timestamp with time zone, p_publish_to timestamp with time zone, p_audience text) TO service_role;
GRANT EXECUTE ON FUNCTION public.announcement_submit(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.announcement_submit(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.announcement_submit(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.announcement_targets() TO authenticated;
GRANT EXECUTE ON FUNCTION public.announcement_targets() TO postgres;
GRANT EXECUTE ON FUNCTION public.announcement_targets() TO service_role;
GRANT DELETE ON TABLE public.announcement_type TO authenticated;
GRANT INSERT ON TABLE public.announcement_type TO authenticated;
GRANT UPDATE ON TABLE public.announcement_type TO authenticated;
GRANT DELETE ON TABLE public.announcement_type TO postgres;
GRANT INSERT ON TABLE public.announcement_type TO postgres;
GRANT MAINTAIN ON TABLE public.announcement_type TO postgres;
GRANT REFERENCES ON TABLE public.announcement_type TO postgres;
GRANT SELECT ON TABLE public.announcement_type TO postgres;
GRANT TRIGGER ON TABLE public.announcement_type TO postgres;
GRANT TRUNCATE ON TABLE public.announcement_type TO postgres;
GRANT UPDATE ON TABLE public.announcement_type TO postgres;
GRANT DELETE ON TABLE public.announcement_type TO service_role;
GRANT INSERT ON TABLE public.announcement_type TO service_role;
GRANT MAINTAIN ON TABLE public.announcement_type TO service_role;
GRANT REFERENCES ON TABLE public.announcement_type TO service_role;
GRANT SELECT ON TABLE public.announcement_type TO service_role;
GRANT TRIGGER ON TABLE public.announcement_type TO service_role;
GRANT TRUNCATE ON TABLE public.announcement_type TO service_role;
GRANT UPDATE ON TABLE public.announcement_type TO service_role;
GRANT SELECT ON TABLE public.announcement_type_announcement_type_id_seq TO postgres;
GRANT UPDATE ON TABLE public.announcement_type_announcement_type_id_seq TO postgres;
GRANT USAGE ON TABLE public.announcement_type_announcement_type_id_seq TO postgres;
GRANT SELECT ON TABLE public.announcement_type_announcement_type_id_seq TO service_role;
GRANT UPDATE ON TABLE public.announcement_type_announcement_type_id_seq TO service_role;
GRANT USAGE ON TABLE public.announcement_type_announcement_type_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.announcements_feed(p_limit integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.announcements_feed(p_limit integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.announcements_feed(p_limit integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.announcements_manage(p_status text, p_search text, p_limit integer, p_offset integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.announcements_manage(p_status text, p_search text, p_limit integer, p_offset integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.announcements_manage(p_status text, p_search text, p_limit integer, p_offset integer) TO service_role;
GRANT DELETE ON TABLE public.approval_status TO authenticated;
GRANT INSERT ON TABLE public.approval_status TO authenticated;
GRANT UPDATE ON TABLE public.approval_status TO authenticated;
GRANT DELETE ON TABLE public.approval_status TO postgres;
GRANT INSERT ON TABLE public.approval_status TO postgres;
GRANT MAINTAIN ON TABLE public.approval_status TO postgres;
GRANT REFERENCES ON TABLE public.approval_status TO postgres;
GRANT SELECT ON TABLE public.approval_status TO postgres;
GRANT TRIGGER ON TABLE public.approval_status TO postgres;
GRANT TRUNCATE ON TABLE public.approval_status TO postgres;
GRANT UPDATE ON TABLE public.approval_status TO postgres;
GRANT DELETE ON TABLE public.approval_status TO service_role;
GRANT INSERT ON TABLE public.approval_status TO service_role;
GRANT MAINTAIN ON TABLE public.approval_status TO service_role;
GRANT REFERENCES ON TABLE public.approval_status TO service_role;
GRANT SELECT ON TABLE public.approval_status TO service_role;
GRANT TRIGGER ON TABLE public.approval_status TO service_role;
GRANT TRUNCATE ON TABLE public.approval_status TO service_role;
GRANT UPDATE ON TABLE public.approval_status TO service_role;
GRANT SELECT ON TABLE public.approval_status_approval_status_id_seq TO postgres;
GRANT UPDATE ON TABLE public.approval_status_approval_status_id_seq TO postgres;
GRANT USAGE ON TABLE public.approval_status_approval_status_id_seq TO postgres;
GRANT SELECT ON TABLE public.approval_status_approval_status_id_seq TO service_role;
GRANT UPDATE ON TABLE public.approval_status_approval_status_id_seq TO service_role;
GRANT USAGE ON TABLE public.approval_status_approval_status_id_seq TO service_role;
GRANT DELETE ON TABLE public.assessment_component TO authenticated;
GRANT INSERT ON TABLE public.assessment_component TO authenticated;
GRANT UPDATE ON TABLE public.assessment_component TO authenticated;
GRANT DELETE ON TABLE public.assessment_component TO postgres;
GRANT INSERT ON TABLE public.assessment_component TO postgres;
GRANT MAINTAIN ON TABLE public.assessment_component TO postgres;
GRANT REFERENCES ON TABLE public.assessment_component TO postgres;
GRANT SELECT ON TABLE public.assessment_component TO postgres;
GRANT TRIGGER ON TABLE public.assessment_component TO postgres;
GRANT TRUNCATE ON TABLE public.assessment_component TO postgres;
GRANT UPDATE ON TABLE public.assessment_component TO postgres;
GRANT DELETE ON TABLE public.assessment_component TO service_role;
GRANT INSERT ON TABLE public.assessment_component TO service_role;
GRANT MAINTAIN ON TABLE public.assessment_component TO service_role;
GRANT REFERENCES ON TABLE public.assessment_component TO service_role;
GRANT SELECT ON TABLE public.assessment_component TO service_role;
GRANT TRIGGER ON TABLE public.assessment_component TO service_role;
GRANT TRUNCATE ON TABLE public.assessment_component TO service_role;
GRANT UPDATE ON TABLE public.assessment_component TO service_role;
GRANT SELECT ON TABLE public.assessment_component_assessment_component_id_seq TO postgres;
GRANT UPDATE ON TABLE public.assessment_component_assessment_component_id_seq TO postgres;
GRANT USAGE ON TABLE public.assessment_component_assessment_component_id_seq TO postgres;
GRANT SELECT ON TABLE public.assessment_component_assessment_component_id_seq TO service_role;
GRANT UPDATE ON TABLE public.assessment_component_assessment_component_id_seq TO service_role;
GRANT USAGE ON TABLE public.assessment_component_assessment_component_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.assessment_enter_marks(p_event_id bigint, p_marks jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assessment_enter_marks(p_event_id bigint, p_marks jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.assessment_enter_marks(p_event_id bigint, p_marks jsonb) TO service_role;
GRANT DELETE ON TABLE public.assessment_event TO authenticated;
GRANT INSERT ON TABLE public.assessment_event TO authenticated;
GRANT UPDATE ON TABLE public.assessment_event TO authenticated;
GRANT DELETE ON TABLE public.assessment_event TO postgres;
GRANT INSERT ON TABLE public.assessment_event TO postgres;
GRANT MAINTAIN ON TABLE public.assessment_event TO postgres;
GRANT REFERENCES ON TABLE public.assessment_event TO postgres;
GRANT SELECT ON TABLE public.assessment_event TO postgres;
GRANT TRIGGER ON TABLE public.assessment_event TO postgres;
GRANT TRUNCATE ON TABLE public.assessment_event TO postgres;
GRANT UPDATE ON TABLE public.assessment_event TO postgres;
GRANT DELETE ON TABLE public.assessment_event TO service_role;
GRANT INSERT ON TABLE public.assessment_event TO service_role;
GRANT MAINTAIN ON TABLE public.assessment_event TO service_role;
GRANT REFERENCES ON TABLE public.assessment_event TO service_role;
GRANT SELECT ON TABLE public.assessment_event TO service_role;
GRANT TRIGGER ON TABLE public.assessment_event TO service_role;
GRANT TRUNCATE ON TABLE public.assessment_event TO service_role;
GRANT UPDATE ON TABLE public.assessment_event TO service_role;
GRANT SELECT ON TABLE public.assessment_event_assessment_event_id_seq TO postgres;
GRANT UPDATE ON TABLE public.assessment_event_assessment_event_id_seq TO postgres;
GRANT USAGE ON TABLE public.assessment_event_assessment_event_id_seq TO postgres;
GRANT SELECT ON TABLE public.assessment_event_assessment_event_id_seq TO service_role;
GRANT UPDATE ON TABLE public.assessment_event_assessment_event_id_seq TO service_role;
GRANT USAGE ON TABLE public.assessment_event_assessment_event_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.assessment_offering_info(p_course_offering_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assessment_offering_info(p_course_offering_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.assessment_offering_info(p_course_offering_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.assessment_offerings(p_term bigint, p_programme integer, p_limit integer, p_offset integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assessment_offerings(p_term bigint, p_programme integer, p_limit integer, p_offset integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.assessment_offerings(p_term bigint, p_programme integer, p_limit integer, p_offset integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.assessment_sheet(p_event_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.assessment_sheet(p_event_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.assessment_sheet(p_event_id bigint) TO service_role;
GRANT DELETE ON TABLE public.attendance_correction_request TO postgres;
GRANT INSERT ON TABLE public.attendance_correction_request TO postgres;
GRANT MAINTAIN ON TABLE public.attendance_correction_request TO postgres;
GRANT REFERENCES ON TABLE public.attendance_correction_request TO postgres;
GRANT SELECT ON TABLE public.attendance_correction_request TO postgres;
GRANT TRIGGER ON TABLE public.attendance_correction_request TO postgres;
GRANT TRUNCATE ON TABLE public.attendance_correction_request TO postgres;
GRANT UPDATE ON TABLE public.attendance_correction_request TO postgres;
GRANT DELETE ON TABLE public.attendance_correction_request TO service_role;
GRANT INSERT ON TABLE public.attendance_correction_request TO service_role;
GRANT MAINTAIN ON TABLE public.attendance_correction_request TO service_role;
GRANT REFERENCES ON TABLE public.attendance_correction_request TO service_role;
GRANT SELECT ON TABLE public.attendance_correction_request TO service_role;
GRANT TRIGGER ON TABLE public.attendance_correction_request TO service_role;
GRANT TRUNCATE ON TABLE public.attendance_correction_request TO service_role;
GRANT UPDATE ON TABLE public.attendance_correction_request TO service_role;
GRANT SELECT ON TABLE public.attendance_correction_request_attendance_correction_id_seq TO postgres;
GRANT UPDATE ON TABLE public.attendance_correction_request_attendance_correction_id_seq TO postgres;
GRANT USAGE ON TABLE public.attendance_correction_request_attendance_correction_id_seq TO postgres;
GRANT SELECT ON TABLE public.attendance_correction_request_attendance_correction_id_seq TO service_role;
GRANT UPDATE ON TABLE public.attendance_correction_request_attendance_correction_id_seq TO service_role;
GRANT USAGE ON TABLE public.attendance_correction_request_attendance_correction_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.attendance_decide_correction(p_correction_id bigint, p_approve boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.attendance_decide_correction(p_correction_id bigint, p_approve boolean) TO postgres;
GRANT EXECUTE ON FUNCTION public.attendance_decide_correction(p_correction_id bigint, p_approve boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.attendance_mark(p_session_id bigint, p_marks jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.attendance_mark(p_session_id bigint, p_marks jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.attendance_mark(p_session_id bigint, p_marks jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.attendance_request_correction(p_session_id bigint, p_roster_id bigint, p_requested_status_id integer, p_reason text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.attendance_request_correction(p_session_id bigint, p_roster_id bigint, p_requested_status_id integer, p_reason text) TO postgres;
GRANT EXECUTE ON FUNCTION public.attendance_request_correction(p_session_id bigint, p_roster_id bigint, p_requested_status_id integer, p_reason text) TO service_role;
GRANT EXECUTE ON FUNCTION public.attendance_sheet(p_session_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.attendance_sheet(p_session_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.attendance_sheet(p_session_id bigint) TO service_role;
GRANT DELETE ON TABLE public.attendance_status TO authenticated;
GRANT INSERT ON TABLE public.attendance_status TO authenticated;
GRANT UPDATE ON TABLE public.attendance_status TO authenticated;
GRANT DELETE ON TABLE public.attendance_status TO postgres;
GRANT INSERT ON TABLE public.attendance_status TO postgres;
GRANT MAINTAIN ON TABLE public.attendance_status TO postgres;
GRANT REFERENCES ON TABLE public.attendance_status TO postgres;
GRANT SELECT ON TABLE public.attendance_status TO postgres;
GRANT TRIGGER ON TABLE public.attendance_status TO postgres;
GRANT TRUNCATE ON TABLE public.attendance_status TO postgres;
GRANT UPDATE ON TABLE public.attendance_status TO postgres;
GRANT DELETE ON TABLE public.attendance_status TO service_role;
GRANT INSERT ON TABLE public.attendance_status TO service_role;
GRANT MAINTAIN ON TABLE public.attendance_status TO service_role;
GRANT REFERENCES ON TABLE public.attendance_status TO service_role;
GRANT SELECT ON TABLE public.attendance_status TO service_role;
GRANT TRIGGER ON TABLE public.attendance_status TO service_role;
GRANT TRUNCATE ON TABLE public.attendance_status TO service_role;
GRANT UPDATE ON TABLE public.attendance_status TO service_role;
GRANT SELECT ON TABLE public.attendance_status_attendance_status_id_seq TO postgres;
GRANT UPDATE ON TABLE public.attendance_status_attendance_status_id_seq TO postgres;
GRANT USAGE ON TABLE public.attendance_status_attendance_status_id_seq TO postgres;
GRANT SELECT ON TABLE public.attendance_status_attendance_status_id_seq TO service_role;
GRANT UPDATE ON TABLE public.attendance_status_attendance_status_id_seq TO service_role;
GRANT USAGE ON TABLE public.attendance_status_attendance_status_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.attendance_summary(p_cos_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.attendance_summary(p_cos_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.attendance_summary(p_cos_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.audit_get(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.audit_get(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.audit_get(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.audit_list(p_module text, p_action text, p_search text, p_from timestamp with time zone, p_to timestamp with time zone, p_limit integer, p_offset integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.audit_list(p_module text, p_action text, p_search text, p_from timestamp with time zone, p_to timestamp with time zone, p_limit integer, p_offset integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.audit_list(p_module text, p_action text, p_search text, p_from timestamp with time zone, p_to timestamp with time zone, p_limit integer, p_offset integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.audit_modules() TO authenticated;
GRANT EXECUTE ON FUNCTION public.audit_modules() TO postgres;
GRANT EXECUTE ON FUNCTION public.audit_modules() TO service_role;
GRANT EXECUTE ON FUNCTION public.auth_failure_record(p_username text, p_reason text) TO anon;
GRANT EXECUTE ON FUNCTION public.auth_failure_record(p_username text, p_reason text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.auth_failure_record(p_username text, p_reason text) TO postgres;
GRANT EXECUTE ON FUNCTION public.auth_failure_record(p_username text, p_reason text) TO service_role;
GRANT EXECUTE ON FUNCTION public.auth_login_record() TO authenticated;
GRANT EXECUTE ON FUNCTION public.auth_login_record() TO postgres;
GRANT EXECUTE ON FUNCTION public.auth_login_record() TO service_role;
GRANT EXECUTE ON FUNCTION public.auth_logout_record() TO authenticated;
GRANT EXECUTE ON FUNCTION public.auth_logout_record() TO postgres;
GRANT EXECUTE ON FUNCTION public.auth_logout_record() TO service_role;
GRANT DELETE ON TABLE public.award_category TO authenticated;
GRANT INSERT ON TABLE public.award_category TO authenticated;
GRANT UPDATE ON TABLE public.award_category TO authenticated;
GRANT DELETE ON TABLE public.award_category TO postgres;
GRANT INSERT ON TABLE public.award_category TO postgres;
GRANT MAINTAIN ON TABLE public.award_category TO postgres;
GRANT REFERENCES ON TABLE public.award_category TO postgres;
GRANT SELECT ON TABLE public.award_category TO postgres;
GRANT TRIGGER ON TABLE public.award_category TO postgres;
GRANT TRUNCATE ON TABLE public.award_category TO postgres;
GRANT UPDATE ON TABLE public.award_category TO postgres;
GRANT DELETE ON TABLE public.award_category TO service_role;
GRANT INSERT ON TABLE public.award_category TO service_role;
GRANT MAINTAIN ON TABLE public.award_category TO service_role;
GRANT REFERENCES ON TABLE public.award_category TO service_role;
GRANT SELECT ON TABLE public.award_category TO service_role;
GRANT TRIGGER ON TABLE public.award_category TO service_role;
GRANT TRUNCATE ON TABLE public.award_category TO service_role;
GRANT UPDATE ON TABLE public.award_category TO service_role;
GRANT SELECT ON TABLE public.award_category_award_category_id_seq TO postgres;
GRANT UPDATE ON TABLE public.award_category_award_category_id_seq TO postgres;
GRANT USAGE ON TABLE public.award_category_award_category_id_seq TO postgres;
GRANT SELECT ON TABLE public.award_category_award_category_id_seq TO service_role;
GRANT UPDATE ON TABLE public.award_category_award_category_id_seq TO service_role;
GRANT USAGE ON TABLE public.award_category_award_category_id_seq TO service_role;
GRANT DELETE ON TABLE public.awarding_body TO authenticated;
GRANT INSERT ON TABLE public.awarding_body TO authenticated;
GRANT UPDATE ON TABLE public.awarding_body TO authenticated;
GRANT DELETE ON TABLE public.awarding_body TO postgres;
GRANT INSERT ON TABLE public.awarding_body TO postgres;
GRANT MAINTAIN ON TABLE public.awarding_body TO postgres;
GRANT REFERENCES ON TABLE public.awarding_body TO postgres;
GRANT SELECT ON TABLE public.awarding_body TO postgres;
GRANT TRIGGER ON TABLE public.awarding_body TO postgres;
GRANT TRUNCATE ON TABLE public.awarding_body TO postgres;
GRANT UPDATE ON TABLE public.awarding_body TO postgres;
GRANT DELETE ON TABLE public.awarding_body TO service_role;
GRANT INSERT ON TABLE public.awarding_body TO service_role;
GRANT MAINTAIN ON TABLE public.awarding_body TO service_role;
GRANT REFERENCES ON TABLE public.awarding_body TO service_role;
GRANT SELECT ON TABLE public.awarding_body TO service_role;
GRANT TRIGGER ON TABLE public.awarding_body TO service_role;
GRANT TRUNCATE ON TABLE public.awarding_body TO service_role;
GRANT UPDATE ON TABLE public.awarding_body TO service_role;
GRANT SELECT ON TABLE public.awarding_body_awarding_body_id_seq TO postgres;
GRANT UPDATE ON TABLE public.awarding_body_awarding_body_id_seq TO postgres;
GRANT USAGE ON TABLE public.awarding_body_awarding_body_id_seq TO postgres;
GRANT SELECT ON TABLE public.awarding_body_awarding_body_id_seq TO service_role;
GRANT UPDATE ON TABLE public.awarding_body_awarding_body_id_seq TO service_role;
GRANT USAGE ON TABLE public.awarding_body_awarding_body_id_seq TO service_role;
GRANT DELETE ON TABLE public.awarding_body_type TO authenticated;
GRANT INSERT ON TABLE public.awarding_body_type TO authenticated;
GRANT UPDATE ON TABLE public.awarding_body_type TO authenticated;
GRANT DELETE ON TABLE public.awarding_body_type TO postgres;
GRANT INSERT ON TABLE public.awarding_body_type TO postgres;
GRANT MAINTAIN ON TABLE public.awarding_body_type TO postgres;
GRANT REFERENCES ON TABLE public.awarding_body_type TO postgres;
GRANT SELECT ON TABLE public.awarding_body_type TO postgres;
GRANT TRIGGER ON TABLE public.awarding_body_type TO postgres;
GRANT TRUNCATE ON TABLE public.awarding_body_type TO postgres;
GRANT UPDATE ON TABLE public.awarding_body_type TO postgres;
GRANT DELETE ON TABLE public.awarding_body_type TO service_role;
GRANT INSERT ON TABLE public.awarding_body_type TO service_role;
GRANT MAINTAIN ON TABLE public.awarding_body_type TO service_role;
GRANT REFERENCES ON TABLE public.awarding_body_type TO service_role;
GRANT SELECT ON TABLE public.awarding_body_type TO service_role;
GRANT TRIGGER ON TABLE public.awarding_body_type TO service_role;
GRANT TRUNCATE ON TABLE public.awarding_body_type TO service_role;
GRANT UPDATE ON TABLE public.awarding_body_type TO service_role;
GRANT SELECT ON TABLE public.awarding_body_type_awarding_body_type_id_seq TO postgres;
GRANT UPDATE ON TABLE public.awarding_body_type_awarding_body_type_id_seq TO postgres;
GRANT USAGE ON TABLE public.awarding_body_type_awarding_body_type_id_seq TO postgres;
GRANT SELECT ON TABLE public.awarding_body_type_awarding_body_type_id_seq TO service_role;
GRANT UPDATE ON TABLE public.awarding_body_type_awarding_body_type_id_seq TO service_role;
GRANT USAGE ON TABLE public.awarding_body_type_awarding_body_type_id_seq TO service_role;
GRANT DELETE ON TABLE public.blood_group TO authenticated;
GRANT INSERT ON TABLE public.blood_group TO authenticated;
GRANT UPDATE ON TABLE public.blood_group TO authenticated;
GRANT DELETE ON TABLE public.blood_group TO postgres;
GRANT INSERT ON TABLE public.blood_group TO postgres;
GRANT MAINTAIN ON TABLE public.blood_group TO postgres;
GRANT REFERENCES ON TABLE public.blood_group TO postgres;
GRANT SELECT ON TABLE public.blood_group TO postgres;
GRANT TRIGGER ON TABLE public.blood_group TO postgres;
GRANT TRUNCATE ON TABLE public.blood_group TO postgres;
GRANT UPDATE ON TABLE public.blood_group TO postgres;
GRANT DELETE ON TABLE public.blood_group TO service_role;
GRANT INSERT ON TABLE public.blood_group TO service_role;
GRANT MAINTAIN ON TABLE public.blood_group TO service_role;
GRANT REFERENCES ON TABLE public.blood_group TO service_role;
GRANT SELECT ON TABLE public.blood_group TO service_role;
GRANT TRIGGER ON TABLE public.blood_group TO service_role;
GRANT TRUNCATE ON TABLE public.blood_group TO service_role;
GRANT UPDATE ON TABLE public.blood_group TO service_role;
GRANT SELECT ON TABLE public.blood_group_blood_group_id_seq TO postgres;
GRANT UPDATE ON TABLE public.blood_group_blood_group_id_seq TO postgres;
GRANT USAGE ON TABLE public.blood_group_blood_group_id_seq TO postgres;
GRANT SELECT ON TABLE public.blood_group_blood_group_id_seq TO service_role;
GRANT UPDATE ON TABLE public.blood_group_blood_group_id_seq TO service_role;
GRANT USAGE ON TABLE public.blood_group_blood_group_id_seq TO service_role;
GRANT DELETE ON TABLE public.building TO authenticated;
GRANT INSERT ON TABLE public.building TO authenticated;
GRANT UPDATE ON TABLE public.building TO authenticated;
GRANT DELETE ON TABLE public.building TO postgres;
GRANT INSERT ON TABLE public.building TO postgres;
GRANT MAINTAIN ON TABLE public.building TO postgres;
GRANT REFERENCES ON TABLE public.building TO postgres;
GRANT SELECT ON TABLE public.building TO postgres;
GRANT TRIGGER ON TABLE public.building TO postgres;
GRANT TRUNCATE ON TABLE public.building TO postgres;
GRANT UPDATE ON TABLE public.building TO postgres;
GRANT DELETE ON TABLE public.building TO service_role;
GRANT INSERT ON TABLE public.building TO service_role;
GRANT MAINTAIN ON TABLE public.building TO service_role;
GRANT REFERENCES ON TABLE public.building TO service_role;
GRANT SELECT ON TABLE public.building TO service_role;
GRANT TRIGGER ON TABLE public.building TO service_role;
GRANT TRUNCATE ON TABLE public.building TO service_role;
GRANT UPDATE ON TABLE public.building TO service_role;
GRANT SELECT ON TABLE public.building_building_id_seq TO postgres;
GRANT UPDATE ON TABLE public.building_building_id_seq TO postgres;
GRANT USAGE ON TABLE public.building_building_id_seq TO postgres;
GRANT SELECT ON TABLE public.building_building_id_seq TO service_role;
GRANT UPDATE ON TABLE public.building_building_id_seq TO service_role;
GRANT USAGE ON TABLE public.building_building_id_seq TO service_role;
GRANT DELETE ON TABLE public.campus TO authenticated;
GRANT INSERT ON TABLE public.campus TO authenticated;
GRANT UPDATE ON TABLE public.campus TO authenticated;
GRANT DELETE ON TABLE public.campus TO postgres;
GRANT INSERT ON TABLE public.campus TO postgres;
GRANT MAINTAIN ON TABLE public.campus TO postgres;
GRANT REFERENCES ON TABLE public.campus TO postgres;
GRANT SELECT ON TABLE public.campus TO postgres;
GRANT TRIGGER ON TABLE public.campus TO postgres;
GRANT TRUNCATE ON TABLE public.campus TO postgres;
GRANT UPDATE ON TABLE public.campus TO postgres;
GRANT DELETE ON TABLE public.campus TO service_role;
GRANT INSERT ON TABLE public.campus TO service_role;
GRANT MAINTAIN ON TABLE public.campus TO service_role;
GRANT REFERENCES ON TABLE public.campus TO service_role;
GRANT SELECT ON TABLE public.campus TO service_role;
GRANT TRIGGER ON TABLE public.campus TO service_role;
GRANT TRUNCATE ON TABLE public.campus TO service_role;
GRANT UPDATE ON TABLE public.campus TO service_role;
GRANT SELECT ON TABLE public.campus_campus_id_seq TO postgres;
GRANT UPDATE ON TABLE public.campus_campus_id_seq TO postgres;
GRANT USAGE ON TABLE public.campus_campus_id_seq TO postgres;
GRANT SELECT ON TABLE public.campus_campus_id_seq TO service_role;
GRANT UPDATE ON TABLE public.campus_campus_id_seq TO service_role;
GRANT USAGE ON TABLE public.campus_campus_id_seq TO service_role;
GRANT DELETE ON TABLE public.caste TO authenticated;
GRANT INSERT ON TABLE public.caste TO authenticated;
GRANT UPDATE ON TABLE public.caste TO authenticated;
GRANT DELETE ON TABLE public.caste TO postgres;
GRANT INSERT ON TABLE public.caste TO postgres;
GRANT MAINTAIN ON TABLE public.caste TO postgres;
GRANT REFERENCES ON TABLE public.caste TO postgres;
GRANT SELECT ON TABLE public.caste TO postgres;
GRANT TRIGGER ON TABLE public.caste TO postgres;
GRANT TRUNCATE ON TABLE public.caste TO postgres;
GRANT UPDATE ON TABLE public.caste TO postgres;
GRANT DELETE ON TABLE public.caste TO service_role;
GRANT INSERT ON TABLE public.caste TO service_role;
GRANT MAINTAIN ON TABLE public.caste TO service_role;
GRANT REFERENCES ON TABLE public.caste TO service_role;
GRANT SELECT ON TABLE public.caste TO service_role;
GRANT TRIGGER ON TABLE public.caste TO service_role;
GRANT TRUNCATE ON TABLE public.caste TO service_role;
GRANT UPDATE ON TABLE public.caste TO service_role;
GRANT SELECT ON TABLE public.caste_caste_id_seq TO postgres;
GRANT UPDATE ON TABLE public.caste_caste_id_seq TO postgres;
GRANT USAGE ON TABLE public.caste_caste_id_seq TO postgres;
GRANT SELECT ON TABLE public.caste_caste_id_seq TO service_role;
GRANT UPDATE ON TABLE public.caste_caste_id_seq TO service_role;
GRANT USAGE ON TABLE public.caste_caste_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.cert_request_cancel(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cert_request_cancel(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.cert_request_cancel(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.cert_request_create(p_type_id integer, p_purpose text, p_student_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cert_request_create(p_type_id integer, p_purpose text, p_student_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.cert_request_create(p_type_id integer, p_purpose text, p_student_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.cert_request_decide(p_id bigint, p_approve boolean, p_remarks text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cert_request_decide(p_id bigint, p_approve boolean, p_remarks text) TO postgres;
GRANT EXECUTE ON FUNCTION public.cert_request_decide(p_id bigint, p_approve boolean, p_remarks text) TO service_role;
GRANT EXECUTE ON FUNCTION public.cert_request_download_info(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cert_request_download_info(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.cert_request_download_info(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.cert_request_issue(p_id bigint, p_certificate_number text, p_storage_key text, p_file_name text, p_size bigint, p_checksum text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cert_request_issue(p_id bigint, p_certificate_number text, p_storage_key text, p_file_name text, p_size bigint, p_checksum text) TO postgres;
GRANT EXECUTE ON FUNCTION public.cert_request_issue(p_id bigint, p_certificate_number text, p_storage_key text, p_file_name text, p_size bigint, p_checksum text) TO service_role;
GRANT EXECUTE ON FUNCTION public.cert_request_list(p_student_id bigint, p_status text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cert_request_list(p_student_id bigint, p_status text) TO postgres;
GRANT EXECUTE ON FUNCTION public.cert_request_list(p_student_id bigint, p_status text) TO service_role;
GRANT DELETE ON TABLE public.certificate_request TO authenticated;
GRANT INSERT ON TABLE public.certificate_request TO authenticated;
GRANT UPDATE ON TABLE public.certificate_request TO authenticated;
GRANT DELETE ON TABLE public.certificate_request TO postgres;
GRANT INSERT ON TABLE public.certificate_request TO postgres;
GRANT MAINTAIN ON TABLE public.certificate_request TO postgres;
GRANT REFERENCES ON TABLE public.certificate_request TO postgres;
GRANT SELECT ON TABLE public.certificate_request TO postgres;
GRANT TRIGGER ON TABLE public.certificate_request TO postgres;
GRANT TRUNCATE ON TABLE public.certificate_request TO postgres;
GRANT UPDATE ON TABLE public.certificate_request TO postgres;
GRANT DELETE ON TABLE public.certificate_request TO service_role;
GRANT INSERT ON TABLE public.certificate_request TO service_role;
GRANT MAINTAIN ON TABLE public.certificate_request TO service_role;
GRANT REFERENCES ON TABLE public.certificate_request TO service_role;
GRANT SELECT ON TABLE public.certificate_request TO service_role;
GRANT TRIGGER ON TABLE public.certificate_request TO service_role;
GRANT TRUNCATE ON TABLE public.certificate_request TO service_role;
GRANT UPDATE ON TABLE public.certificate_request TO service_role;
GRANT SELECT ON TABLE public.certificate_request_certificate_request_id_seq TO postgres;
GRANT UPDATE ON TABLE public.certificate_request_certificate_request_id_seq TO postgres;
GRANT USAGE ON TABLE public.certificate_request_certificate_request_id_seq TO postgres;
GRANT SELECT ON TABLE public.certificate_request_certificate_request_id_seq TO service_role;
GRANT UPDATE ON TABLE public.certificate_request_certificate_request_id_seq TO service_role;
GRANT USAGE ON TABLE public.certificate_request_certificate_request_id_seq TO service_role;
GRANT DELETE ON TABLE public.certificate_type TO authenticated;
GRANT INSERT ON TABLE public.certificate_type TO authenticated;
GRANT UPDATE ON TABLE public.certificate_type TO authenticated;
GRANT DELETE ON TABLE public.certificate_type TO postgres;
GRANT INSERT ON TABLE public.certificate_type TO postgres;
GRANT MAINTAIN ON TABLE public.certificate_type TO postgres;
GRANT REFERENCES ON TABLE public.certificate_type TO postgres;
GRANT SELECT ON TABLE public.certificate_type TO postgres;
GRANT TRIGGER ON TABLE public.certificate_type TO postgres;
GRANT TRUNCATE ON TABLE public.certificate_type TO postgres;
GRANT UPDATE ON TABLE public.certificate_type TO postgres;
GRANT DELETE ON TABLE public.certificate_type TO service_role;
GRANT INSERT ON TABLE public.certificate_type TO service_role;
GRANT MAINTAIN ON TABLE public.certificate_type TO service_role;
GRANT REFERENCES ON TABLE public.certificate_type TO service_role;
GRANT SELECT ON TABLE public.certificate_type TO service_role;
GRANT TRIGGER ON TABLE public.certificate_type TO service_role;
GRANT TRUNCATE ON TABLE public.certificate_type TO service_role;
GRANT UPDATE ON TABLE public.certificate_type TO service_role;
GRANT SELECT ON TABLE public.certificate_type_certificate_type_id_seq TO postgres;
GRANT UPDATE ON TABLE public.certificate_type_certificate_type_id_seq TO postgres;
GRANT USAGE ON TABLE public.certificate_type_certificate_type_id_seq TO postgres;
GRANT SELECT ON TABLE public.certificate_type_certificate_type_id_seq TO service_role;
GRANT UPDATE ON TABLE public.certificate_type_certificate_type_id_seq TO service_role;
GRANT USAGE ON TABLE public.certificate_type_certificate_type_id_seq TO service_role;
GRANT DELETE ON TABLE public.class_batch TO authenticated;
GRANT INSERT ON TABLE public.class_batch TO authenticated;
GRANT UPDATE ON TABLE public.class_batch TO authenticated;
GRANT DELETE ON TABLE public.class_batch TO postgres;
GRANT INSERT ON TABLE public.class_batch TO postgres;
GRANT MAINTAIN ON TABLE public.class_batch TO postgres;
GRANT REFERENCES ON TABLE public.class_batch TO postgres;
GRANT SELECT ON TABLE public.class_batch TO postgres;
GRANT TRIGGER ON TABLE public.class_batch TO postgres;
GRANT TRUNCATE ON TABLE public.class_batch TO postgres;
GRANT UPDATE ON TABLE public.class_batch TO postgres;
GRANT DELETE ON TABLE public.class_batch TO service_role;
GRANT INSERT ON TABLE public.class_batch TO service_role;
GRANT MAINTAIN ON TABLE public.class_batch TO service_role;
GRANT REFERENCES ON TABLE public.class_batch TO service_role;
GRANT SELECT ON TABLE public.class_batch TO service_role;
GRANT TRIGGER ON TABLE public.class_batch TO service_role;
GRANT TRUNCATE ON TABLE public.class_batch TO service_role;
GRANT UPDATE ON TABLE public.class_batch TO service_role;
GRANT SELECT ON TABLE public.class_batch_class_batch_id_seq TO postgres;
GRANT UPDATE ON TABLE public.class_batch_class_batch_id_seq TO postgres;
GRANT USAGE ON TABLE public.class_batch_class_batch_id_seq TO postgres;
GRANT SELECT ON TABLE public.class_batch_class_batch_id_seq TO service_role;
GRANT UPDATE ON TABLE public.class_batch_class_batch_id_seq TO service_role;
GRANT USAGE ON TABLE public.class_batch_class_batch_id_seq TO service_role;
GRANT DELETE ON TABLE public.class_section TO authenticated;
GRANT INSERT ON TABLE public.class_section TO authenticated;
GRANT UPDATE ON TABLE public.class_section TO authenticated;
GRANT DELETE ON TABLE public.class_section TO postgres;
GRANT INSERT ON TABLE public.class_section TO postgres;
GRANT MAINTAIN ON TABLE public.class_section TO postgres;
GRANT REFERENCES ON TABLE public.class_section TO postgres;
GRANT SELECT ON TABLE public.class_section TO postgres;
GRANT TRIGGER ON TABLE public.class_section TO postgres;
GRANT TRUNCATE ON TABLE public.class_section TO postgres;
GRANT UPDATE ON TABLE public.class_section TO postgres;
GRANT DELETE ON TABLE public.class_section TO service_role;
GRANT INSERT ON TABLE public.class_section TO service_role;
GRANT MAINTAIN ON TABLE public.class_section TO service_role;
GRANT REFERENCES ON TABLE public.class_section TO service_role;
GRANT SELECT ON TABLE public.class_section TO service_role;
GRANT TRIGGER ON TABLE public.class_section TO service_role;
GRANT TRUNCATE ON TABLE public.class_section TO service_role;
GRANT UPDATE ON TABLE public.class_section TO service_role;
GRANT SELECT ON TABLE public.class_section_class_section_id_seq TO postgres;
GRANT UPDATE ON TABLE public.class_section_class_section_id_seq TO postgres;
GRANT USAGE ON TABLE public.class_section_class_section_id_seq TO postgres;
GRANT SELECT ON TABLE public.class_section_class_section_id_seq TO service_role;
GRANT UPDATE ON TABLE public.class_section_class_section_id_seq TO service_role;
GRANT USAGE ON TABLE public.class_section_class_section_id_seq TO service_role;
GRANT DELETE ON TABLE public.class_session TO authenticated;
GRANT INSERT ON TABLE public.class_session TO authenticated;
GRANT UPDATE ON TABLE public.class_session TO authenticated;
GRANT DELETE ON TABLE public.class_session TO postgres;
GRANT INSERT ON TABLE public.class_session TO postgres;
GRANT MAINTAIN ON TABLE public.class_session TO postgres;
GRANT REFERENCES ON TABLE public.class_session TO postgres;
GRANT SELECT ON TABLE public.class_session TO postgres;
GRANT TRIGGER ON TABLE public.class_session TO postgres;
GRANT TRUNCATE ON TABLE public.class_session TO postgres;
GRANT UPDATE ON TABLE public.class_session TO postgres;
GRANT DELETE ON TABLE public.class_session TO service_role;
GRANT INSERT ON TABLE public.class_session TO service_role;
GRANT MAINTAIN ON TABLE public.class_session TO service_role;
GRANT REFERENCES ON TABLE public.class_session TO service_role;
GRANT SELECT ON TABLE public.class_session TO service_role;
GRANT TRIGGER ON TABLE public.class_session TO service_role;
GRANT TRUNCATE ON TABLE public.class_session TO service_role;
GRANT UPDATE ON TABLE public.class_session TO service_role;
GRANT SELECT ON TABLE public.class_session_class_session_id_seq TO postgres;
GRANT UPDATE ON TABLE public.class_session_class_session_id_seq TO postgres;
GRANT USAGE ON TABLE public.class_session_class_session_id_seq TO postgres;
GRANT SELECT ON TABLE public.class_session_class_session_id_seq TO service_role;
GRANT UPDATE ON TABLE public.class_session_class_session_id_seq TO service_role;
GRANT USAGE ON TABLE public.class_session_class_session_id_seq TO service_role;
GRANT DELETE ON TABLE public.cocurricular_activity TO postgres;
GRANT INSERT ON TABLE public.cocurricular_activity TO postgres;
GRANT MAINTAIN ON TABLE public.cocurricular_activity TO postgres;
GRANT REFERENCES ON TABLE public.cocurricular_activity TO postgres;
GRANT SELECT ON TABLE public.cocurricular_activity TO postgres;
GRANT TRIGGER ON TABLE public.cocurricular_activity TO postgres;
GRANT TRUNCATE ON TABLE public.cocurricular_activity TO postgres;
GRANT UPDATE ON TABLE public.cocurricular_activity TO postgres;
GRANT DELETE ON TABLE public.cocurricular_activity TO service_role;
GRANT INSERT ON TABLE public.cocurricular_activity TO service_role;
GRANT MAINTAIN ON TABLE public.cocurricular_activity TO service_role;
GRANT REFERENCES ON TABLE public.cocurricular_activity TO service_role;
GRANT SELECT ON TABLE public.cocurricular_activity TO service_role;
GRANT TRIGGER ON TABLE public.cocurricular_activity TO service_role;
GRANT TRUNCATE ON TABLE public.cocurricular_activity TO service_role;
GRANT UPDATE ON TABLE public.cocurricular_activity TO service_role;
GRANT DELETE ON TABLE public.cocurricular_category TO authenticated;
GRANT INSERT ON TABLE public.cocurricular_category TO authenticated;
GRANT UPDATE ON TABLE public.cocurricular_category TO authenticated;
GRANT DELETE ON TABLE public.cocurricular_category TO postgres;
GRANT INSERT ON TABLE public.cocurricular_category TO postgres;
GRANT MAINTAIN ON TABLE public.cocurricular_category TO postgres;
GRANT REFERENCES ON TABLE public.cocurricular_category TO postgres;
GRANT SELECT ON TABLE public.cocurricular_category TO postgres;
GRANT TRIGGER ON TABLE public.cocurricular_category TO postgres;
GRANT TRUNCATE ON TABLE public.cocurricular_category TO postgres;
GRANT UPDATE ON TABLE public.cocurricular_category TO postgres;
GRANT DELETE ON TABLE public.cocurricular_category TO service_role;
GRANT INSERT ON TABLE public.cocurricular_category TO service_role;
GRANT MAINTAIN ON TABLE public.cocurricular_category TO service_role;
GRANT REFERENCES ON TABLE public.cocurricular_category TO service_role;
GRANT SELECT ON TABLE public.cocurricular_category TO service_role;
GRANT TRIGGER ON TABLE public.cocurricular_category TO service_role;
GRANT TRUNCATE ON TABLE public.cocurricular_category TO service_role;
GRANT UPDATE ON TABLE public.cocurricular_category TO service_role;
GRANT SELECT ON TABLE public.cocurricular_category_cocurricular_category_id_seq TO postgres;
GRANT UPDATE ON TABLE public.cocurricular_category_cocurricular_category_id_seq TO postgres;
GRANT USAGE ON TABLE public.cocurricular_category_cocurricular_category_id_seq TO postgres;
GRANT SELECT ON TABLE public.cocurricular_category_cocurricular_category_id_seq TO service_role;
GRANT UPDATE ON TABLE public.cocurricular_category_cocurricular_category_id_seq TO service_role;
GRANT USAGE ON TABLE public.cocurricular_category_cocurricular_category_id_seq TO service_role;
GRANT DELETE ON TABLE public.concession_type TO postgres;
GRANT INSERT ON TABLE public.concession_type TO postgres;
GRANT MAINTAIN ON TABLE public.concession_type TO postgres;
GRANT REFERENCES ON TABLE public.concession_type TO postgres;
GRANT SELECT ON TABLE public.concession_type TO postgres;
GRANT TRIGGER ON TABLE public.concession_type TO postgres;
GRANT TRUNCATE ON TABLE public.concession_type TO postgres;
GRANT UPDATE ON TABLE public.concession_type TO postgres;
GRANT DELETE ON TABLE public.concession_type TO service_role;
GRANT INSERT ON TABLE public.concession_type TO service_role;
GRANT MAINTAIN ON TABLE public.concession_type TO service_role;
GRANT REFERENCES ON TABLE public.concession_type TO service_role;
GRANT SELECT ON TABLE public.concession_type TO service_role;
GRANT TRIGGER ON TABLE public.concession_type TO service_role;
GRANT TRUNCATE ON TABLE public.concession_type TO service_role;
GRANT UPDATE ON TABLE public.concession_type TO service_role;
GRANT SELECT ON TABLE public.concession_type_concession_type_id_seq TO postgres;
GRANT UPDATE ON TABLE public.concession_type_concession_type_id_seq TO postgres;
GRANT USAGE ON TABLE public.concession_type_concession_type_id_seq TO postgres;
GRANT SELECT ON TABLE public.concession_type_concession_type_id_seq TO service_role;
GRANT UPDATE ON TABLE public.concession_type_concession_type_id_seq TO service_role;
GRANT USAGE ON TABLE public.concession_type_concession_type_id_seq TO service_role;
GRANT DELETE ON TABLE public.conference_activity TO postgres;
GRANT INSERT ON TABLE public.conference_activity TO postgres;
GRANT MAINTAIN ON TABLE public.conference_activity TO postgres;
GRANT REFERENCES ON TABLE public.conference_activity TO postgres;
GRANT SELECT ON TABLE public.conference_activity TO postgres;
GRANT TRIGGER ON TABLE public.conference_activity TO postgres;
GRANT TRUNCATE ON TABLE public.conference_activity TO postgres;
GRANT UPDATE ON TABLE public.conference_activity TO postgres;
GRANT DELETE ON TABLE public.conference_activity TO service_role;
GRANT INSERT ON TABLE public.conference_activity TO service_role;
GRANT MAINTAIN ON TABLE public.conference_activity TO service_role;
GRANT REFERENCES ON TABLE public.conference_activity TO service_role;
GRANT SELECT ON TABLE public.conference_activity TO service_role;
GRANT TRIGGER ON TABLE public.conference_activity TO service_role;
GRANT TRUNCATE ON TABLE public.conference_activity TO service_role;
GRANT UPDATE ON TABLE public.conference_activity TO service_role;
GRANT DELETE ON TABLE public.conference_activity_indexing TO authenticated;
GRANT INSERT ON TABLE public.conference_activity_indexing TO authenticated;
GRANT UPDATE ON TABLE public.conference_activity_indexing TO authenticated;
GRANT DELETE ON TABLE public.conference_activity_indexing TO postgres;
GRANT INSERT ON TABLE public.conference_activity_indexing TO postgres;
GRANT MAINTAIN ON TABLE public.conference_activity_indexing TO postgres;
GRANT REFERENCES ON TABLE public.conference_activity_indexing TO postgres;
GRANT SELECT ON TABLE public.conference_activity_indexing TO postgres;
GRANT TRIGGER ON TABLE public.conference_activity_indexing TO postgres;
GRANT TRUNCATE ON TABLE public.conference_activity_indexing TO postgres;
GRANT UPDATE ON TABLE public.conference_activity_indexing TO postgres;
GRANT DELETE ON TABLE public.conference_activity_indexing TO service_role;
GRANT INSERT ON TABLE public.conference_activity_indexing TO service_role;
GRANT MAINTAIN ON TABLE public.conference_activity_indexing TO service_role;
GRANT REFERENCES ON TABLE public.conference_activity_indexing TO service_role;
GRANT SELECT ON TABLE public.conference_activity_indexing TO service_role;
GRANT TRIGGER ON TABLE public.conference_activity_indexing TO service_role;
GRANT TRUNCATE ON TABLE public.conference_activity_indexing TO service_role;
GRANT UPDATE ON TABLE public.conference_activity_indexing TO service_role;
GRANT DELETE ON TABLE public.conference_contribution_type TO authenticated;
GRANT INSERT ON TABLE public.conference_contribution_type TO authenticated;
GRANT UPDATE ON TABLE public.conference_contribution_type TO authenticated;
GRANT DELETE ON TABLE public.conference_contribution_type TO postgres;
GRANT INSERT ON TABLE public.conference_contribution_type TO postgres;
GRANT MAINTAIN ON TABLE public.conference_contribution_type TO postgres;
GRANT REFERENCES ON TABLE public.conference_contribution_type TO postgres;
GRANT SELECT ON TABLE public.conference_contribution_type TO postgres;
GRANT TRIGGER ON TABLE public.conference_contribution_type TO postgres;
GRANT TRUNCATE ON TABLE public.conference_contribution_type TO postgres;
GRANT UPDATE ON TABLE public.conference_contribution_type TO postgres;
GRANT DELETE ON TABLE public.conference_contribution_type TO service_role;
GRANT INSERT ON TABLE public.conference_contribution_type TO service_role;
GRANT MAINTAIN ON TABLE public.conference_contribution_type TO service_role;
GRANT REFERENCES ON TABLE public.conference_contribution_type TO service_role;
GRANT SELECT ON TABLE public.conference_contribution_type TO service_role;
GRANT TRIGGER ON TABLE public.conference_contribution_type TO service_role;
GRANT TRUNCATE ON TABLE public.conference_contribution_type TO service_role;
GRANT UPDATE ON TABLE public.conference_contribution_type TO service_role;
GRANT SELECT ON TABLE public.conference_contribution_type_conference_contribution_type_i_seq TO postgres;
GRANT UPDATE ON TABLE public.conference_contribution_type_conference_contribution_type_i_seq TO postgres;
GRANT USAGE ON TABLE public.conference_contribution_type_conference_contribution_type_i_seq TO postgres;
GRANT SELECT ON TABLE public.conference_contribution_type_conference_contribution_type_i_seq TO service_role;
GRANT UPDATE ON TABLE public.conference_contribution_type_conference_contribution_type_i_seq TO service_role;
GRANT USAGE ON TABLE public.conference_contribution_type_conference_contribution_type_i_seq TO service_role;
GRANT DELETE ON TABLE public.conference_event TO authenticated;
GRANT INSERT ON TABLE public.conference_event TO authenticated;
GRANT UPDATE ON TABLE public.conference_event TO authenticated;
GRANT DELETE ON TABLE public.conference_event TO postgres;
GRANT INSERT ON TABLE public.conference_event TO postgres;
GRANT MAINTAIN ON TABLE public.conference_event TO postgres;
GRANT REFERENCES ON TABLE public.conference_event TO postgres;
GRANT SELECT ON TABLE public.conference_event TO postgres;
GRANT TRIGGER ON TABLE public.conference_event TO postgres;
GRANT TRUNCATE ON TABLE public.conference_event TO postgres;
GRANT UPDATE ON TABLE public.conference_event TO postgres;
GRANT DELETE ON TABLE public.conference_event TO service_role;
GRANT INSERT ON TABLE public.conference_event TO service_role;
GRANT MAINTAIN ON TABLE public.conference_event TO service_role;
GRANT REFERENCES ON TABLE public.conference_event TO service_role;
GRANT SELECT ON TABLE public.conference_event TO service_role;
GRANT TRIGGER ON TABLE public.conference_event TO service_role;
GRANT TRUNCATE ON TABLE public.conference_event TO service_role;
GRANT UPDATE ON TABLE public.conference_event TO service_role;
GRANT SELECT ON TABLE public.conference_event_conference_event_id_seq TO postgres;
GRANT UPDATE ON TABLE public.conference_event_conference_event_id_seq TO postgres;
GRANT USAGE ON TABLE public.conference_event_conference_event_id_seq TO postgres;
GRANT SELECT ON TABLE public.conference_event_conference_event_id_seq TO service_role;
GRANT UPDATE ON TABLE public.conference_event_conference_event_id_seq TO service_role;
GRANT USAGE ON TABLE public.conference_event_conference_event_id_seq TO service_role;
GRANT DELETE ON TABLE public.confidentiality_level TO authenticated;
GRANT INSERT ON TABLE public.confidentiality_level TO authenticated;
GRANT UPDATE ON TABLE public.confidentiality_level TO authenticated;
GRANT DELETE ON TABLE public.confidentiality_level TO postgres;
GRANT INSERT ON TABLE public.confidentiality_level TO postgres;
GRANT MAINTAIN ON TABLE public.confidentiality_level TO postgres;
GRANT REFERENCES ON TABLE public.confidentiality_level TO postgres;
GRANT SELECT ON TABLE public.confidentiality_level TO postgres;
GRANT TRIGGER ON TABLE public.confidentiality_level TO postgres;
GRANT TRUNCATE ON TABLE public.confidentiality_level TO postgres;
GRANT UPDATE ON TABLE public.confidentiality_level TO postgres;
GRANT DELETE ON TABLE public.confidentiality_level TO service_role;
GRANT INSERT ON TABLE public.confidentiality_level TO service_role;
GRANT MAINTAIN ON TABLE public.confidentiality_level TO service_role;
GRANT REFERENCES ON TABLE public.confidentiality_level TO service_role;
GRANT SELECT ON TABLE public.confidentiality_level TO service_role;
GRANT TRIGGER ON TABLE public.confidentiality_level TO service_role;
GRANT TRUNCATE ON TABLE public.confidentiality_level TO service_role;
GRANT UPDATE ON TABLE public.confidentiality_level TO service_role;
GRANT SELECT ON TABLE public.confidentiality_level_confidentiality_level_id_seq TO postgres;
GRANT UPDATE ON TABLE public.confidentiality_level_confidentiality_level_id_seq TO postgres;
GRANT USAGE ON TABLE public.confidentiality_level_confidentiality_level_id_seq TO postgres;
GRANT SELECT ON TABLE public.confidentiality_level_confidentiality_level_id_seq TO service_role;
GRANT UPDATE ON TABLE public.confidentiality_level_confidentiality_level_id_seq TO service_role;
GRANT USAGE ON TABLE public.confidentiality_level_confidentiality_level_id_seq TO service_role;
GRANT DELETE ON TABLE public.consultancy_project TO postgres;
GRANT INSERT ON TABLE public.consultancy_project TO postgres;
GRANT MAINTAIN ON TABLE public.consultancy_project TO postgres;
GRANT REFERENCES ON TABLE public.consultancy_project TO postgres;
GRANT SELECT ON TABLE public.consultancy_project TO postgres;
GRANT TRIGGER ON TABLE public.consultancy_project TO postgres;
GRANT TRUNCATE ON TABLE public.consultancy_project TO postgres;
GRANT UPDATE ON TABLE public.consultancy_project TO postgres;
GRANT DELETE ON TABLE public.consultancy_project TO service_role;
GRANT INSERT ON TABLE public.consultancy_project TO service_role;
GRANT MAINTAIN ON TABLE public.consultancy_project TO service_role;
GRANT REFERENCES ON TABLE public.consultancy_project TO service_role;
GRANT SELECT ON TABLE public.consultancy_project TO service_role;
GRANT TRIGGER ON TABLE public.consultancy_project TO service_role;
GRANT TRUNCATE ON TABLE public.consultancy_project TO service_role;
GRANT UPDATE ON TABLE public.consultancy_project TO service_role;
GRANT DELETE ON TABLE public.counselling_session TO postgres;
GRANT INSERT ON TABLE public.counselling_session TO postgres;
GRANT MAINTAIN ON TABLE public.counselling_session TO postgres;
GRANT REFERENCES ON TABLE public.counselling_session TO postgres;
GRANT SELECT ON TABLE public.counselling_session TO postgres;
GRANT TRIGGER ON TABLE public.counselling_session TO postgres;
GRANT TRUNCATE ON TABLE public.counselling_session TO postgres;
GRANT UPDATE ON TABLE public.counselling_session TO postgres;
GRANT DELETE ON TABLE public.counselling_session TO service_role;
GRANT INSERT ON TABLE public.counselling_session TO service_role;
GRANT MAINTAIN ON TABLE public.counselling_session TO service_role;
GRANT REFERENCES ON TABLE public.counselling_session TO service_role;
GRANT SELECT ON TABLE public.counselling_session TO service_role;
GRANT TRIGGER ON TABLE public.counselling_session TO service_role;
GRANT TRUNCATE ON TABLE public.counselling_session TO service_role;
GRANT UPDATE ON TABLE public.counselling_session TO service_role;
GRANT SELECT ON TABLE public.counselling_session_counselling_session_id_seq TO postgres;
GRANT UPDATE ON TABLE public.counselling_session_counselling_session_id_seq TO postgres;
GRANT USAGE ON TABLE public.counselling_session_counselling_session_id_seq TO postgres;
GRANT SELECT ON TABLE public.counselling_session_counselling_session_id_seq TO service_role;
GRANT UPDATE ON TABLE public.counselling_session_counselling_session_id_seq TO service_role;
GRANT USAGE ON TABLE public.counselling_session_counselling_session_id_seq TO service_role;
GRANT DELETE ON TABLE public.country TO authenticated;
GRANT INSERT ON TABLE public.country TO authenticated;
GRANT UPDATE ON TABLE public.country TO authenticated;
GRANT DELETE ON TABLE public.country TO postgres;
GRANT INSERT ON TABLE public.country TO postgres;
GRANT MAINTAIN ON TABLE public.country TO postgres;
GRANT REFERENCES ON TABLE public.country TO postgres;
GRANT SELECT ON TABLE public.country TO postgres;
GRANT TRIGGER ON TABLE public.country TO postgres;
GRANT TRUNCATE ON TABLE public.country TO postgres;
GRANT UPDATE ON TABLE public.country TO postgres;
GRANT DELETE ON TABLE public.country TO service_role;
GRANT INSERT ON TABLE public.country TO service_role;
GRANT MAINTAIN ON TABLE public.country TO service_role;
GRANT REFERENCES ON TABLE public.country TO service_role;
GRANT SELECT ON TABLE public.country TO service_role;
GRANT TRIGGER ON TABLE public.country TO service_role;
GRANT TRUNCATE ON TABLE public.country TO service_role;
GRANT UPDATE ON TABLE public.country TO service_role;
GRANT SELECT ON TABLE public.country_country_id_seq TO postgres;
GRANT UPDATE ON TABLE public.country_country_id_seq TO postgres;
GRANT USAGE ON TABLE public.country_country_id_seq TO postgres;
GRANT SELECT ON TABLE public.country_country_id_seq TO service_role;
GRANT UPDATE ON TABLE public.country_country_id_seq TO service_role;
GRANT USAGE ON TABLE public.country_country_id_seq TO service_role;
GRANT DELETE ON TABLE public.course_catalog TO authenticated;
GRANT INSERT ON TABLE public.course_catalog TO authenticated;
GRANT UPDATE ON TABLE public.course_catalog TO authenticated;
GRANT DELETE ON TABLE public.course_catalog TO postgres;
GRANT INSERT ON TABLE public.course_catalog TO postgres;
GRANT MAINTAIN ON TABLE public.course_catalog TO postgres;
GRANT REFERENCES ON TABLE public.course_catalog TO postgres;
GRANT SELECT ON TABLE public.course_catalog TO postgres;
GRANT TRIGGER ON TABLE public.course_catalog TO postgres;
GRANT TRUNCATE ON TABLE public.course_catalog TO postgres;
GRANT UPDATE ON TABLE public.course_catalog TO postgres;
GRANT DELETE ON TABLE public.course_catalog TO service_role;
GRANT INSERT ON TABLE public.course_catalog TO service_role;
GRANT MAINTAIN ON TABLE public.course_catalog TO service_role;
GRANT REFERENCES ON TABLE public.course_catalog TO service_role;
GRANT SELECT ON TABLE public.course_catalog TO service_role;
GRANT TRIGGER ON TABLE public.course_catalog TO service_role;
GRANT TRUNCATE ON TABLE public.course_catalog TO service_role;
GRANT UPDATE ON TABLE public.course_catalog TO service_role;
GRANT SELECT ON TABLE public.course_catalog_course_id_seq TO postgres;
GRANT UPDATE ON TABLE public.course_catalog_course_id_seq TO postgres;
GRANT USAGE ON TABLE public.course_catalog_course_id_seq TO postgres;
GRANT SELECT ON TABLE public.course_catalog_course_id_seq TO service_role;
GRANT UPDATE ON TABLE public.course_catalog_course_id_seq TO service_role;
GRANT USAGE ON TABLE public.course_catalog_course_id_seq TO service_role;
GRANT DELETE ON TABLE public.course_category TO authenticated;
GRANT INSERT ON TABLE public.course_category TO authenticated;
GRANT UPDATE ON TABLE public.course_category TO authenticated;
GRANT DELETE ON TABLE public.course_category TO postgres;
GRANT INSERT ON TABLE public.course_category TO postgres;
GRANT MAINTAIN ON TABLE public.course_category TO postgres;
GRANT REFERENCES ON TABLE public.course_category TO postgres;
GRANT SELECT ON TABLE public.course_category TO postgres;
GRANT TRIGGER ON TABLE public.course_category TO postgres;
GRANT TRUNCATE ON TABLE public.course_category TO postgres;
GRANT UPDATE ON TABLE public.course_category TO postgres;
GRANT DELETE ON TABLE public.course_category TO service_role;
GRANT INSERT ON TABLE public.course_category TO service_role;
GRANT MAINTAIN ON TABLE public.course_category TO service_role;
GRANT REFERENCES ON TABLE public.course_category TO service_role;
GRANT SELECT ON TABLE public.course_category TO service_role;
GRANT TRIGGER ON TABLE public.course_category TO service_role;
GRANT TRUNCATE ON TABLE public.course_category TO service_role;
GRANT UPDATE ON TABLE public.course_category TO service_role;
GRANT SELECT ON TABLE public.course_category_course_category_id_seq TO postgres;
GRANT UPDATE ON TABLE public.course_category_course_category_id_seq TO postgres;
GRANT USAGE ON TABLE public.course_category_course_category_id_seq TO postgres;
GRANT SELECT ON TABLE public.course_category_course_category_id_seq TO service_role;
GRANT UPDATE ON TABLE public.course_category_course_category_id_seq TO service_role;
GRANT USAGE ON TABLE public.course_category_course_category_id_seq TO service_role;
GRANT DELETE ON TABLE public.course_offering TO authenticated;
GRANT INSERT ON TABLE public.course_offering TO authenticated;
GRANT UPDATE ON TABLE public.course_offering TO authenticated;
GRANT DELETE ON TABLE public.course_offering TO postgres;
GRANT INSERT ON TABLE public.course_offering TO postgres;
GRANT MAINTAIN ON TABLE public.course_offering TO postgres;
GRANT REFERENCES ON TABLE public.course_offering TO postgres;
GRANT SELECT ON TABLE public.course_offering TO postgres;
GRANT TRIGGER ON TABLE public.course_offering TO postgres;
GRANT TRUNCATE ON TABLE public.course_offering TO postgres;
GRANT UPDATE ON TABLE public.course_offering TO postgres;
GRANT DELETE ON TABLE public.course_offering TO service_role;
GRANT INSERT ON TABLE public.course_offering TO service_role;
GRANT MAINTAIN ON TABLE public.course_offering TO service_role;
GRANT REFERENCES ON TABLE public.course_offering TO service_role;
GRANT SELECT ON TABLE public.course_offering TO service_role;
GRANT TRIGGER ON TABLE public.course_offering TO service_role;
GRANT TRUNCATE ON TABLE public.course_offering TO service_role;
GRANT UPDATE ON TABLE public.course_offering TO service_role;
GRANT SELECT ON TABLE public.course_offering_course_offering_id_seq TO postgres;
GRANT UPDATE ON TABLE public.course_offering_course_offering_id_seq TO postgres;
GRANT USAGE ON TABLE public.course_offering_course_offering_id_seq TO postgres;
GRANT SELECT ON TABLE public.course_offering_course_offering_id_seq TO service_role;
GRANT UPDATE ON TABLE public.course_offering_course_offering_id_seq TO service_role;
GRANT USAGE ON TABLE public.course_offering_course_offering_id_seq TO service_role;
GRANT DELETE ON TABLE public.course_offering_section TO authenticated;
GRANT INSERT ON TABLE public.course_offering_section TO authenticated;
GRANT UPDATE ON TABLE public.course_offering_section TO authenticated;
GRANT DELETE ON TABLE public.course_offering_section TO postgres;
GRANT INSERT ON TABLE public.course_offering_section TO postgres;
GRANT MAINTAIN ON TABLE public.course_offering_section TO postgres;
GRANT REFERENCES ON TABLE public.course_offering_section TO postgres;
GRANT SELECT ON TABLE public.course_offering_section TO postgres;
GRANT TRIGGER ON TABLE public.course_offering_section TO postgres;
GRANT TRUNCATE ON TABLE public.course_offering_section TO postgres;
GRANT UPDATE ON TABLE public.course_offering_section TO postgres;
GRANT DELETE ON TABLE public.course_offering_section TO service_role;
GRANT INSERT ON TABLE public.course_offering_section TO service_role;
GRANT MAINTAIN ON TABLE public.course_offering_section TO service_role;
GRANT REFERENCES ON TABLE public.course_offering_section TO service_role;
GRANT SELECT ON TABLE public.course_offering_section TO service_role;
GRANT TRIGGER ON TABLE public.course_offering_section TO service_role;
GRANT TRUNCATE ON TABLE public.course_offering_section TO service_role;
GRANT UPDATE ON TABLE public.course_offering_section TO service_role;
GRANT SELECT ON TABLE public.course_offering_section_course_offering_section_id_seq TO postgres;
GRANT UPDATE ON TABLE public.course_offering_section_course_offering_section_id_seq TO postgres;
GRANT USAGE ON TABLE public.course_offering_section_course_offering_section_id_seq TO postgres;
GRANT SELECT ON TABLE public.course_offering_section_course_offering_section_id_seq TO service_role;
GRANT UPDATE ON TABLE public.course_offering_section_course_offering_section_id_seq TO service_role;
GRANT USAGE ON TABLE public.course_offering_section_course_offering_section_id_seq TO service_role;
GRANT SELECT ON TABLE public.course_offering_section_stude_course_offering_section_stude_seq TO postgres;
GRANT UPDATE ON TABLE public.course_offering_section_stude_course_offering_section_stude_seq TO postgres;
GRANT USAGE ON TABLE public.course_offering_section_stude_course_offering_section_stude_seq TO postgres;
GRANT SELECT ON TABLE public.course_offering_section_stude_course_offering_section_stude_seq TO service_role;
GRANT UPDATE ON TABLE public.course_offering_section_stude_course_offering_section_stude_seq TO service_role;
GRANT USAGE ON TABLE public.course_offering_section_stude_course_offering_section_stude_seq TO service_role;
GRANT DELETE ON TABLE public.course_offering_section_student TO authenticated;
GRANT INSERT ON TABLE public.course_offering_section_student TO authenticated;
GRANT UPDATE ON TABLE public.course_offering_section_student TO authenticated;
GRANT DELETE ON TABLE public.course_offering_section_student TO postgres;
GRANT INSERT ON TABLE public.course_offering_section_student TO postgres;
GRANT MAINTAIN ON TABLE public.course_offering_section_student TO postgres;
GRANT REFERENCES ON TABLE public.course_offering_section_student TO postgres;
GRANT SELECT ON TABLE public.course_offering_section_student TO postgres;
GRANT TRIGGER ON TABLE public.course_offering_section_student TO postgres;
GRANT TRUNCATE ON TABLE public.course_offering_section_student TO postgres;
GRANT UPDATE ON TABLE public.course_offering_section_student TO postgres;
GRANT DELETE ON TABLE public.course_offering_section_student TO service_role;
GRANT INSERT ON TABLE public.course_offering_section_student TO service_role;
GRANT MAINTAIN ON TABLE public.course_offering_section_student TO service_role;
GRANT REFERENCES ON TABLE public.course_offering_section_student TO service_role;
GRANT SELECT ON TABLE public.course_offering_section_student TO service_role;
GRANT TRIGGER ON TABLE public.course_offering_section_student TO service_role;
GRANT TRUNCATE ON TABLE public.course_offering_section_student TO service_role;
GRANT UPDATE ON TABLE public.course_offering_section_student TO service_role;
GRANT DELETE ON TABLE public.course_prerequisite TO authenticated;
GRANT INSERT ON TABLE public.course_prerequisite TO authenticated;
GRANT UPDATE ON TABLE public.course_prerequisite TO authenticated;
GRANT DELETE ON TABLE public.course_prerequisite TO postgres;
GRANT INSERT ON TABLE public.course_prerequisite TO postgres;
GRANT MAINTAIN ON TABLE public.course_prerequisite TO postgres;
GRANT REFERENCES ON TABLE public.course_prerequisite TO postgres;
GRANT SELECT ON TABLE public.course_prerequisite TO postgres;
GRANT TRIGGER ON TABLE public.course_prerequisite TO postgres;
GRANT TRUNCATE ON TABLE public.course_prerequisite TO postgres;
GRANT UPDATE ON TABLE public.course_prerequisite TO postgres;
GRANT DELETE ON TABLE public.course_prerequisite TO service_role;
GRANT INSERT ON TABLE public.course_prerequisite TO service_role;
GRANT MAINTAIN ON TABLE public.course_prerequisite TO service_role;
GRANT REFERENCES ON TABLE public.course_prerequisite TO service_role;
GRANT SELECT ON TABLE public.course_prerequisite TO service_role;
GRANT TRIGGER ON TABLE public.course_prerequisite TO service_role;
GRANT TRUNCATE ON TABLE public.course_prerequisite TO service_role;
GRANT UPDATE ON TABLE public.course_prerequisite TO service_role;
GRANT DELETE ON TABLE public.curriculum_course TO authenticated;
GRANT INSERT ON TABLE public.curriculum_course TO authenticated;
GRANT UPDATE ON TABLE public.curriculum_course TO authenticated;
GRANT DELETE ON TABLE public.curriculum_course TO postgres;
GRANT INSERT ON TABLE public.curriculum_course TO postgres;
GRANT MAINTAIN ON TABLE public.curriculum_course TO postgres;
GRANT REFERENCES ON TABLE public.curriculum_course TO postgres;
GRANT SELECT ON TABLE public.curriculum_course TO postgres;
GRANT TRIGGER ON TABLE public.curriculum_course TO postgres;
GRANT TRUNCATE ON TABLE public.curriculum_course TO postgres;
GRANT UPDATE ON TABLE public.curriculum_course TO postgres;
GRANT DELETE ON TABLE public.curriculum_course TO service_role;
GRANT INSERT ON TABLE public.curriculum_course TO service_role;
GRANT MAINTAIN ON TABLE public.curriculum_course TO service_role;
GRANT REFERENCES ON TABLE public.curriculum_course TO service_role;
GRANT SELECT ON TABLE public.curriculum_course TO service_role;
GRANT TRIGGER ON TABLE public.curriculum_course TO service_role;
GRANT TRUNCATE ON TABLE public.curriculum_course TO service_role;
GRANT UPDATE ON TABLE public.curriculum_course TO service_role;
GRANT SELECT ON TABLE public.curriculum_course_curriculum_course_id_seq TO postgres;
GRANT UPDATE ON TABLE public.curriculum_course_curriculum_course_id_seq TO postgres;
GRANT USAGE ON TABLE public.curriculum_course_curriculum_course_id_seq TO postgres;
GRANT SELECT ON TABLE public.curriculum_course_curriculum_course_id_seq TO service_role;
GRANT UPDATE ON TABLE public.curriculum_course_curriculum_course_id_seq TO service_role;
GRANT USAGE ON TABLE public.curriculum_course_curriculum_course_id_seq TO service_role;
GRANT DELETE ON TABLE public.curriculum_scheme TO authenticated;
GRANT INSERT ON TABLE public.curriculum_scheme TO authenticated;
GRANT UPDATE ON TABLE public.curriculum_scheme TO authenticated;
GRANT DELETE ON TABLE public.curriculum_scheme TO postgres;
GRANT INSERT ON TABLE public.curriculum_scheme TO postgres;
GRANT MAINTAIN ON TABLE public.curriculum_scheme TO postgres;
GRANT REFERENCES ON TABLE public.curriculum_scheme TO postgres;
GRANT SELECT ON TABLE public.curriculum_scheme TO postgres;
GRANT TRIGGER ON TABLE public.curriculum_scheme TO postgres;
GRANT TRUNCATE ON TABLE public.curriculum_scheme TO postgres;
GRANT UPDATE ON TABLE public.curriculum_scheme TO postgres;
GRANT DELETE ON TABLE public.curriculum_scheme TO service_role;
GRANT INSERT ON TABLE public.curriculum_scheme TO service_role;
GRANT MAINTAIN ON TABLE public.curriculum_scheme TO service_role;
GRANT REFERENCES ON TABLE public.curriculum_scheme TO service_role;
GRANT SELECT ON TABLE public.curriculum_scheme TO service_role;
GRANT TRIGGER ON TABLE public.curriculum_scheme TO service_role;
GRANT TRUNCATE ON TABLE public.curriculum_scheme TO service_role;
GRANT UPDATE ON TABLE public.curriculum_scheme TO service_role;
GRANT SELECT ON TABLE public.curriculum_scheme_curriculum_scheme_id_seq TO postgres;
GRANT UPDATE ON TABLE public.curriculum_scheme_curriculum_scheme_id_seq TO postgres;
GRANT USAGE ON TABLE public.curriculum_scheme_curriculum_scheme_id_seq TO postgres;
GRANT SELECT ON TABLE public.curriculum_scheme_curriculum_scheme_id_seq TO service_role;
GRANT UPDATE ON TABLE public.curriculum_scheme_curriculum_scheme_id_seq TO service_role;
GRANT USAGE ON TABLE public.curriculum_scheme_curriculum_scheme_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.dash_applications() TO authenticated;
GRANT EXECUTE ON FUNCTION public.dash_applications() TO postgres;
GRANT EXECUTE ON FUNCTION public.dash_applications() TO service_role;
GRANT EXECUTE ON FUNCTION public.dash_employees() TO authenticated;
GRANT EXECUTE ON FUNCTION public.dash_employees() TO postgres;
GRANT EXECUTE ON FUNCTION public.dash_employees() TO service_role;
GRANT EXECUTE ON FUNCTION public.dash_enrolments() TO authenticated;
GRANT EXECUTE ON FUNCTION public.dash_enrolments() TO postgres;
GRANT EXECUTE ON FUNCTION public.dash_enrolments() TO service_role;
GRANT EXECUTE ON FUNCTION public.dash_fee_collection(p_months integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dash_fee_collection(p_months integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.dash_fee_collection(p_months integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.dash_fee_outstanding() TO authenticated;
GRANT EXECUTE ON FUNCTION public.dash_fee_outstanding() TO postgres;
GRANT EXECUTE ON FUNCTION public.dash_fee_outstanding() TO service_role;
GRANT EXECUTE ON FUNCTION public.dash_registrations() TO authenticated;
GRANT EXECUTE ON FUNCTION public.dash_registrations() TO postgres;
GRANT EXECUTE ON FUNCTION public.dash_registrations() TO service_role;
GRANT EXECUTE ON FUNCTION public.dash_sessions(p_days integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dash_sessions(p_days integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.dash_sessions(p_days integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.dash_term_results() TO authenticated;
GRANT EXECUTE ON FUNCTION public.dash_term_results() TO postgres;
GRANT EXECUTE ON FUNCTION public.dash_term_results() TO service_role;
GRANT DELETE ON TABLE public.department TO authenticated;
GRANT INSERT ON TABLE public.department TO authenticated;
GRANT UPDATE ON TABLE public.department TO authenticated;
GRANT DELETE ON TABLE public.department TO postgres;
GRANT INSERT ON TABLE public.department TO postgres;
GRANT MAINTAIN ON TABLE public.department TO postgres;
GRANT REFERENCES ON TABLE public.department TO postgres;
GRANT SELECT ON TABLE public.department TO postgres;
GRANT TRIGGER ON TABLE public.department TO postgres;
GRANT TRUNCATE ON TABLE public.department TO postgres;
GRANT UPDATE ON TABLE public.department TO postgres;
GRANT DELETE ON TABLE public.department TO service_role;
GRANT INSERT ON TABLE public.department TO service_role;
GRANT MAINTAIN ON TABLE public.department TO service_role;
GRANT REFERENCES ON TABLE public.department TO service_role;
GRANT SELECT ON TABLE public.department TO service_role;
GRANT TRIGGER ON TABLE public.department TO service_role;
GRANT TRUNCATE ON TABLE public.department TO service_role;
GRANT UPDATE ON TABLE public.department TO service_role;
GRANT SELECT ON TABLE public.department_department_id_seq TO postgres;
GRANT UPDATE ON TABLE public.department_department_id_seq TO postgres;
GRANT USAGE ON TABLE public.department_department_id_seq TO postgres;
GRANT SELECT ON TABLE public.department_department_id_seq TO service_role;
GRANT UPDATE ON TABLE public.department_department_id_seq TO service_role;
GRANT USAGE ON TABLE public.department_department_id_seq TO service_role;
GRANT DELETE ON TABLE public.designation TO authenticated;
GRANT INSERT ON TABLE public.designation TO authenticated;
GRANT UPDATE ON TABLE public.designation TO authenticated;
GRANT DELETE ON TABLE public.designation TO postgres;
GRANT INSERT ON TABLE public.designation TO postgres;
GRANT MAINTAIN ON TABLE public.designation TO postgres;
GRANT REFERENCES ON TABLE public.designation TO postgres;
GRANT SELECT ON TABLE public.designation TO postgres;
GRANT TRIGGER ON TABLE public.designation TO postgres;
GRANT TRUNCATE ON TABLE public.designation TO postgres;
GRANT UPDATE ON TABLE public.designation TO postgres;
GRANT DELETE ON TABLE public.designation TO service_role;
GRANT INSERT ON TABLE public.designation TO service_role;
GRANT MAINTAIN ON TABLE public.designation TO service_role;
GRANT REFERENCES ON TABLE public.designation TO service_role;
GRANT SELECT ON TABLE public.designation TO service_role;
GRANT TRIGGER ON TABLE public.designation TO service_role;
GRANT TRUNCATE ON TABLE public.designation TO service_role;
GRANT UPDATE ON TABLE public.designation TO service_role;
GRANT SELECT ON TABLE public.designation_designation_id_seq TO postgres;
GRANT UPDATE ON TABLE public.designation_designation_id_seq TO postgres;
GRANT USAGE ON TABLE public.designation_designation_id_seq TO postgres;
GRANT SELECT ON TABLE public.designation_designation_id_seq TO service_role;
GRANT UPDATE ON TABLE public.designation_designation_id_seq TO service_role;
GRANT USAGE ON TABLE public.designation_designation_id_seq TO service_role;
GRANT DELETE ON TABLE public.document_type TO authenticated;
GRANT INSERT ON TABLE public.document_type TO authenticated;
GRANT UPDATE ON TABLE public.document_type TO authenticated;
GRANT DELETE ON TABLE public.document_type TO postgres;
GRANT INSERT ON TABLE public.document_type TO postgres;
GRANT MAINTAIN ON TABLE public.document_type TO postgres;
GRANT REFERENCES ON TABLE public.document_type TO postgres;
GRANT SELECT ON TABLE public.document_type TO postgres;
GRANT TRIGGER ON TABLE public.document_type TO postgres;
GRANT TRUNCATE ON TABLE public.document_type TO postgres;
GRANT UPDATE ON TABLE public.document_type TO postgres;
GRANT DELETE ON TABLE public.document_type TO service_role;
GRANT INSERT ON TABLE public.document_type TO service_role;
GRANT MAINTAIN ON TABLE public.document_type TO service_role;
GRANT REFERENCES ON TABLE public.document_type TO service_role;
GRANT SELECT ON TABLE public.document_type TO service_role;
GRANT TRIGGER ON TABLE public.document_type TO service_role;
GRANT TRUNCATE ON TABLE public.document_type TO service_role;
GRANT UPDATE ON TABLE public.document_type TO service_role;
GRANT SELECT ON TABLE public.document_type_document_type_id_seq TO postgres;
GRANT UPDATE ON TABLE public.document_type_document_type_id_seq TO postgres;
GRANT USAGE ON TABLE public.document_type_document_type_id_seq TO postgres;
GRANT SELECT ON TABLE public.document_type_document_type_id_seq TO service_role;
GRANT UPDATE ON TABLE public.document_type_document_type_id_seq TO service_role;
GRANT USAGE ON TABLE public.document_type_document_type_id_seq TO service_role;
GRANT DELETE ON TABLE public.education_institution TO authenticated;
GRANT INSERT ON TABLE public.education_institution TO authenticated;
GRANT UPDATE ON TABLE public.education_institution TO authenticated;
GRANT DELETE ON TABLE public.education_institution TO postgres;
GRANT INSERT ON TABLE public.education_institution TO postgres;
GRANT MAINTAIN ON TABLE public.education_institution TO postgres;
GRANT REFERENCES ON TABLE public.education_institution TO postgres;
GRANT SELECT ON TABLE public.education_institution TO postgres;
GRANT TRIGGER ON TABLE public.education_institution TO postgres;
GRANT TRUNCATE ON TABLE public.education_institution TO postgres;
GRANT UPDATE ON TABLE public.education_institution TO postgres;
GRANT DELETE ON TABLE public.education_institution TO service_role;
GRANT INSERT ON TABLE public.education_institution TO service_role;
GRANT MAINTAIN ON TABLE public.education_institution TO service_role;
GRANT REFERENCES ON TABLE public.education_institution TO service_role;
GRANT SELECT ON TABLE public.education_institution TO service_role;
GRANT TRIGGER ON TABLE public.education_institution TO service_role;
GRANT TRUNCATE ON TABLE public.education_institution TO service_role;
GRANT UPDATE ON TABLE public.education_institution TO service_role;
GRANT SELECT ON TABLE public.education_institution_education_institution_id_seq TO postgres;
GRANT UPDATE ON TABLE public.education_institution_education_institution_id_seq TO postgres;
GRANT USAGE ON TABLE public.education_institution_education_institution_id_seq TO postgres;
GRANT SELECT ON TABLE public.education_institution_education_institution_id_seq TO service_role;
GRANT UPDATE ON TABLE public.education_institution_education_institution_id_seq TO service_role;
GRANT USAGE ON TABLE public.education_institution_education_institution_id_seq TO service_role;
GRANT DELETE ON TABLE public.education_institution_type TO authenticated;
GRANT INSERT ON TABLE public.education_institution_type TO authenticated;
GRANT UPDATE ON TABLE public.education_institution_type TO authenticated;
GRANT DELETE ON TABLE public.education_institution_type TO postgres;
GRANT INSERT ON TABLE public.education_institution_type TO postgres;
GRANT MAINTAIN ON TABLE public.education_institution_type TO postgres;
GRANT REFERENCES ON TABLE public.education_institution_type TO postgres;
GRANT SELECT ON TABLE public.education_institution_type TO postgres;
GRANT TRIGGER ON TABLE public.education_institution_type TO postgres;
GRANT TRUNCATE ON TABLE public.education_institution_type TO postgres;
GRANT UPDATE ON TABLE public.education_institution_type TO postgres;
GRANT DELETE ON TABLE public.education_institution_type TO service_role;
GRANT INSERT ON TABLE public.education_institution_type TO service_role;
GRANT MAINTAIN ON TABLE public.education_institution_type TO service_role;
GRANT REFERENCES ON TABLE public.education_institution_type TO service_role;
GRANT SELECT ON TABLE public.education_institution_type TO service_role;
GRANT TRIGGER ON TABLE public.education_institution_type TO service_role;
GRANT TRUNCATE ON TABLE public.education_institution_type TO service_role;
GRANT UPDATE ON TABLE public.education_institution_type TO service_role;
GRANT SELECT ON TABLE public.education_institution_type_education_institution_type_id_seq TO postgres;
GRANT UPDATE ON TABLE public.education_institution_type_education_institution_type_id_seq TO postgres;
GRANT USAGE ON TABLE public.education_institution_type_education_institution_type_id_seq TO postgres;
GRANT SELECT ON TABLE public.education_institution_type_education_institution_type_id_seq TO service_role;
GRANT UPDATE ON TABLE public.education_institution_type_education_institution_type_id_seq TO service_role;
GRANT USAGE ON TABLE public.education_institution_type_education_institution_type_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.emp_aadhaar_save(p_employee_id bigint, p_aadhaar text, p_name text, p_purpose text, p_remarks text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.emp_aadhaar_save(p_employee_id bigint, p_aadhaar text, p_name text, p_purpose text, p_remarks text) TO postgres;
GRANT EXECUTE ON FUNCTION public.emp_aadhaar_save(p_employee_id bigint, p_aadhaar text, p_name text, p_purpose text, p_remarks text) TO service_role;
GRANT EXECUTE ON FUNCTION public.emp_bank_save(p_employee_id bigint, p_account_id bigint, p_holder text, p_bank text, p_branch text, p_account_number text, p_account_confirm text, p_ifsc text, p_type text, p_upi text, p_is_primary boolean, p_is_salary boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.emp_bank_save(p_employee_id bigint, p_account_id bigint, p_holder text, p_bank text, p_branch text, p_account_number text, p_account_confirm text, p_ifsc text, p_type text, p_upi text, p_is_primary boolean, p_is_salary boolean) TO postgres;
GRANT EXECUTE ON FUNCTION public.emp_bank_save(p_employee_id bigint, p_account_id bigint, p_holder text, p_bank text, p_branch text, p_account_number text, p_account_confirm text, p_ifsc text, p_type text, p_upi text, p_is_primary boolean, p_is_salary boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.emp_competency_delete(p_employee_id bigint, p_course_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.emp_competency_delete(p_employee_id bigint, p_course_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.emp_competency_delete(p_employee_id bigint, p_course_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.emp_competency_list(p_employee_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.emp_competency_list(p_employee_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.emp_competency_list(p_employee_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.emp_competency_save(p_employee_id bigint, p_course_id bigint, p_level text, p_valid_from date, p_valid_to date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.emp_competency_save(p_employee_id bigint, p_course_id bigint, p_level text, p_valid_from date, p_valid_to date) TO postgres;
GRANT EXECUTE ON FUNCTION public.emp_competency_save(p_employee_id bigint, p_course_id bigint, p_level text, p_valid_from date, p_valid_to date) TO service_role;
GRANT EXECUTE ON FUNCTION public.emp_doc_rule_end(p_rule_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.emp_doc_rule_end(p_rule_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.emp_doc_rule_end(p_rule_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.emp_doc_rule_list(p_document_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.emp_doc_rule_list(p_document_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.emp_doc_rule_list(p_document_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.emp_doc_rule_set(p_document_id bigint, p_role_code text, p_username text, p_can_view boolean, p_can_download boolean, p_valid_to timestamp with time zone) TO authenticated;
GRANT EXECUTE ON FUNCTION public.emp_doc_rule_set(p_document_id bigint, p_role_code text, p_username text, p_can_view boolean, p_can_download boolean, p_valid_to timestamp with time zone) TO postgres;
GRANT EXECUTE ON FUNCTION public.emp_doc_rule_set(p_document_id bigint, p_role_code text, p_username text, p_can_view boolean, p_can_download boolean, p_valid_to timestamp with time zone) TO service_role;
GRANT EXECUTE ON FUNCTION public.emp_pan_save(p_employee_id bigint, p_pan text, p_name text, p_issue_date date, p_remarks text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.emp_pan_save(p_employee_id bigint, p_pan text, p_name text, p_issue_date date, p_remarks text) TO postgres;
GRANT EXECUTE ON FUNCTION public.emp_pan_save(p_employee_id bigint, p_pan text, p_name text, p_issue_date date, p_remarks text) TO service_role;
GRANT EXECUTE ON FUNCTION public.emp_sensitive_delete(p_kind text, p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.emp_sensitive_delete(p_kind text, p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.emp_sensitive_delete(p_kind text, p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.emp_sensitive_list(p_employee_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.emp_sensitive_list(p_employee_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.emp_sensitive_list(p_employee_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.emp_sensitive_reveal(p_kind text, p_id bigint, p_purpose text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.emp_sensitive_reveal(p_kind text, p_id bigint, p_purpose text) TO postgres;
GRANT EXECUTE ON FUNCTION public.emp_sensitive_reveal(p_kind text, p_id bigint, p_purpose text) TO service_role;
GRANT EXECUTE ON FUNCTION public.emp_sensitive_review(p_kind text, p_id bigint, p_decision text, p_remarks text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.emp_sensitive_review(p_kind text, p_id bigint, p_decision text, p_remarks text) TO postgres;
GRANT EXECUTE ON FUNCTION public.emp_sensitive_review(p_kind text, p_id bigint, p_decision text, p_remarks text) TO service_role;
GRANT DELETE ON TABLE public.employee TO authenticated;
GRANT INSERT ON TABLE public.employee TO authenticated;
GRANT UPDATE ON TABLE public.employee TO authenticated;
GRANT DELETE ON TABLE public.employee TO postgres;
GRANT INSERT ON TABLE public.employee TO postgres;
GRANT MAINTAIN ON TABLE public.employee TO postgres;
GRANT REFERENCES ON TABLE public.employee TO postgres;
GRANT SELECT ON TABLE public.employee TO postgres;
GRANT TRIGGER ON TABLE public.employee TO postgres;
GRANT TRUNCATE ON TABLE public.employee TO postgres;
GRANT UPDATE ON TABLE public.employee TO postgres;
GRANT DELETE ON TABLE public.employee TO service_role;
GRANT INSERT ON TABLE public.employee TO service_role;
GRANT MAINTAIN ON TABLE public.employee TO service_role;
GRANT REFERENCES ON TABLE public.employee TO service_role;
GRANT SELECT ON TABLE public.employee TO service_role;
GRANT TRIGGER ON TABLE public.employee TO service_role;
GRANT TRUNCATE ON TABLE public.employee TO service_role;
GRANT UPDATE ON TABLE public.employee TO service_role;
GRANT DELETE ON TABLE public.employee_aadhaar TO authenticated;
GRANT INSERT ON TABLE public.employee_aadhaar TO authenticated;
GRANT UPDATE ON TABLE public.employee_aadhaar TO authenticated;
GRANT DELETE ON TABLE public.employee_aadhaar TO postgres;
GRANT INSERT ON TABLE public.employee_aadhaar TO postgres;
GRANT MAINTAIN ON TABLE public.employee_aadhaar TO postgres;
GRANT REFERENCES ON TABLE public.employee_aadhaar TO postgres;
GRANT SELECT ON TABLE public.employee_aadhaar TO postgres;
GRANT TRIGGER ON TABLE public.employee_aadhaar TO postgres;
GRANT TRUNCATE ON TABLE public.employee_aadhaar TO postgres;
GRANT UPDATE ON TABLE public.employee_aadhaar TO postgres;
GRANT DELETE ON TABLE public.employee_aadhaar TO service_role;
GRANT INSERT ON TABLE public.employee_aadhaar TO service_role;
GRANT MAINTAIN ON TABLE public.employee_aadhaar TO service_role;
GRANT REFERENCES ON TABLE public.employee_aadhaar TO service_role;
GRANT SELECT ON TABLE public.employee_aadhaar TO service_role;
GRANT TRIGGER ON TABLE public.employee_aadhaar TO service_role;
GRANT TRUNCATE ON TABLE public.employee_aadhaar TO service_role;
GRANT UPDATE ON TABLE public.employee_aadhaar TO service_role;
GRANT SELECT ON TABLE public.employee_aadhaar_employee_aadhaar_id_seq TO postgres;
GRANT UPDATE ON TABLE public.employee_aadhaar_employee_aadhaar_id_seq TO postgres;
GRANT USAGE ON TABLE public.employee_aadhaar_employee_aadhaar_id_seq TO postgres;
GRANT SELECT ON TABLE public.employee_aadhaar_employee_aadhaar_id_seq TO service_role;
GRANT UPDATE ON TABLE public.employee_aadhaar_employee_aadhaar_id_seq TO service_role;
GRANT USAGE ON TABLE public.employee_aadhaar_employee_aadhaar_id_seq TO service_role;
GRANT DELETE ON TABLE public.employee_address TO authenticated;
GRANT INSERT ON TABLE public.employee_address TO authenticated;
GRANT UPDATE ON TABLE public.employee_address TO authenticated;
GRANT DELETE ON TABLE public.employee_address TO postgres;
GRANT INSERT ON TABLE public.employee_address TO postgres;
GRANT MAINTAIN ON TABLE public.employee_address TO postgres;
GRANT REFERENCES ON TABLE public.employee_address TO postgres;
GRANT SELECT ON TABLE public.employee_address TO postgres;
GRANT TRIGGER ON TABLE public.employee_address TO postgres;
GRANT TRUNCATE ON TABLE public.employee_address TO postgres;
GRANT UPDATE ON TABLE public.employee_address TO postgres;
GRANT DELETE ON TABLE public.employee_address TO service_role;
GRANT INSERT ON TABLE public.employee_address TO service_role;
GRANT MAINTAIN ON TABLE public.employee_address TO service_role;
GRANT REFERENCES ON TABLE public.employee_address TO service_role;
GRANT SELECT ON TABLE public.employee_address TO service_role;
GRANT TRIGGER ON TABLE public.employee_address TO service_role;
GRANT TRUNCATE ON TABLE public.employee_address TO service_role;
GRANT UPDATE ON TABLE public.employee_address TO service_role;
GRANT SELECT ON TABLE public.employee_address_employee_address_id_seq TO postgres;
GRANT UPDATE ON TABLE public.employee_address_employee_address_id_seq TO postgres;
GRANT USAGE ON TABLE public.employee_address_employee_address_id_seq TO postgres;
GRANT SELECT ON TABLE public.employee_address_employee_address_id_seq TO service_role;
GRANT UPDATE ON TABLE public.employee_address_employee_address_id_seq TO service_role;
GRANT USAGE ON TABLE public.employee_address_employee_address_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.employee_assign(p_employee_id bigint, p_campus_id integer, p_department_id integer, p_designation_id integer, p_start_date date, p_is_primary boolean, p_end_current boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.employee_assign(p_employee_id bigint, p_campus_id integer, p_department_id integer, p_designation_id integer, p_start_date date, p_is_primary boolean, p_end_current boolean) TO postgres;
GRANT EXECUTE ON FUNCTION public.employee_assign(p_employee_id bigint, p_campus_id integer, p_department_id integer, p_designation_id integer, p_start_date date, p_is_primary boolean, p_end_current boolean) TO service_role;
GRANT DELETE ON TABLE public.employee_assignment TO authenticated;
GRANT INSERT ON TABLE public.employee_assignment TO authenticated;
GRANT UPDATE ON TABLE public.employee_assignment TO authenticated;
GRANT DELETE ON TABLE public.employee_assignment TO postgres;
GRANT INSERT ON TABLE public.employee_assignment TO postgres;
GRANT MAINTAIN ON TABLE public.employee_assignment TO postgres;
GRANT REFERENCES ON TABLE public.employee_assignment TO postgres;
GRANT SELECT ON TABLE public.employee_assignment TO postgres;
GRANT TRIGGER ON TABLE public.employee_assignment TO postgres;
GRANT TRUNCATE ON TABLE public.employee_assignment TO postgres;
GRANT UPDATE ON TABLE public.employee_assignment TO postgres;
GRANT DELETE ON TABLE public.employee_assignment TO service_role;
GRANT INSERT ON TABLE public.employee_assignment TO service_role;
GRANT MAINTAIN ON TABLE public.employee_assignment TO service_role;
GRANT REFERENCES ON TABLE public.employee_assignment TO service_role;
GRANT SELECT ON TABLE public.employee_assignment TO service_role;
GRANT TRIGGER ON TABLE public.employee_assignment TO service_role;
GRANT TRUNCATE ON TABLE public.employee_assignment TO service_role;
GRANT UPDATE ON TABLE public.employee_assignment TO service_role;
GRANT SELECT ON TABLE public.employee_assignment_employee_assignment_id_seq TO postgres;
GRANT UPDATE ON TABLE public.employee_assignment_employee_assignment_id_seq TO postgres;
GRANT USAGE ON TABLE public.employee_assignment_employee_assignment_id_seq TO postgres;
GRANT SELECT ON TABLE public.employee_assignment_employee_assignment_id_seq TO service_role;
GRANT UPDATE ON TABLE public.employee_assignment_employee_assignment_id_seq TO service_role;
GRANT USAGE ON TABLE public.employee_assignment_employee_assignment_id_seq TO service_role;
GRANT DELETE ON TABLE public.employee_bank_account TO authenticated;
GRANT INSERT ON TABLE public.employee_bank_account TO authenticated;
GRANT UPDATE ON TABLE public.employee_bank_account TO authenticated;
GRANT DELETE ON TABLE public.employee_bank_account TO postgres;
GRANT INSERT ON TABLE public.employee_bank_account TO postgres;
GRANT MAINTAIN ON TABLE public.employee_bank_account TO postgres;
GRANT REFERENCES ON TABLE public.employee_bank_account TO postgres;
GRANT SELECT ON TABLE public.employee_bank_account TO postgres;
GRANT TRIGGER ON TABLE public.employee_bank_account TO postgres;
GRANT TRUNCATE ON TABLE public.employee_bank_account TO postgres;
GRANT UPDATE ON TABLE public.employee_bank_account TO postgres;
GRANT DELETE ON TABLE public.employee_bank_account TO service_role;
GRANT INSERT ON TABLE public.employee_bank_account TO service_role;
GRANT MAINTAIN ON TABLE public.employee_bank_account TO service_role;
GRANT REFERENCES ON TABLE public.employee_bank_account TO service_role;
GRANT SELECT ON TABLE public.employee_bank_account TO service_role;
GRANT TRIGGER ON TABLE public.employee_bank_account TO service_role;
GRANT TRUNCATE ON TABLE public.employee_bank_account TO service_role;
GRANT UPDATE ON TABLE public.employee_bank_account TO service_role;
GRANT SELECT ON TABLE public.employee_bank_account_employee_bank_account_id_seq TO postgres;
GRANT UPDATE ON TABLE public.employee_bank_account_employee_bank_account_id_seq TO postgres;
GRANT USAGE ON TABLE public.employee_bank_account_employee_bank_account_id_seq TO postgres;
GRANT SELECT ON TABLE public.employee_bank_account_employee_bank_account_id_seq TO service_role;
GRANT UPDATE ON TABLE public.employee_bank_account_employee_bank_account_id_seq TO service_role;
GRANT USAGE ON TABLE public.employee_bank_account_employee_bank_account_id_seq TO service_role;
GRANT DELETE ON TABLE public.employee_competency TO authenticated;
GRANT INSERT ON TABLE public.employee_competency TO authenticated;
GRANT UPDATE ON TABLE public.employee_competency TO authenticated;
GRANT DELETE ON TABLE public.employee_competency TO postgres;
GRANT INSERT ON TABLE public.employee_competency TO postgres;
GRANT MAINTAIN ON TABLE public.employee_competency TO postgres;
GRANT REFERENCES ON TABLE public.employee_competency TO postgres;
GRANT SELECT ON TABLE public.employee_competency TO postgres;
GRANT TRIGGER ON TABLE public.employee_competency TO postgres;
GRANT TRUNCATE ON TABLE public.employee_competency TO postgres;
GRANT UPDATE ON TABLE public.employee_competency TO postgres;
GRANT DELETE ON TABLE public.employee_competency TO service_role;
GRANT INSERT ON TABLE public.employee_competency TO service_role;
GRANT MAINTAIN ON TABLE public.employee_competency TO service_role;
GRANT REFERENCES ON TABLE public.employee_competency TO service_role;
GRANT SELECT ON TABLE public.employee_competency TO service_role;
GRANT TRIGGER ON TABLE public.employee_competency TO service_role;
GRANT TRUNCATE ON TABLE public.employee_competency TO service_role;
GRANT UPDATE ON TABLE public.employee_competency TO service_role;
GRANT DELETE ON TABLE public.employee_document TO authenticated;
GRANT INSERT ON TABLE public.employee_document TO authenticated;
GRANT UPDATE ON TABLE public.employee_document TO authenticated;
GRANT DELETE ON TABLE public.employee_document TO postgres;
GRANT INSERT ON TABLE public.employee_document TO postgres;
GRANT MAINTAIN ON TABLE public.employee_document TO postgres;
GRANT REFERENCES ON TABLE public.employee_document TO postgres;
GRANT SELECT ON TABLE public.employee_document TO postgres;
GRANT TRIGGER ON TABLE public.employee_document TO postgres;
GRANT TRUNCATE ON TABLE public.employee_document TO postgres;
GRANT UPDATE ON TABLE public.employee_document TO postgres;
GRANT DELETE ON TABLE public.employee_document TO service_role;
GRANT INSERT ON TABLE public.employee_document TO service_role;
GRANT MAINTAIN ON TABLE public.employee_document TO service_role;
GRANT REFERENCES ON TABLE public.employee_document TO service_role;
GRANT SELECT ON TABLE public.employee_document TO service_role;
GRANT TRIGGER ON TABLE public.employee_document TO service_role;
GRANT TRUNCATE ON TABLE public.employee_document TO service_role;
GRANT UPDATE ON TABLE public.employee_document TO service_role;
GRANT DELETE ON TABLE public.employee_document_access_rule TO authenticated;
GRANT INSERT ON TABLE public.employee_document_access_rule TO authenticated;
GRANT UPDATE ON TABLE public.employee_document_access_rule TO authenticated;
GRANT DELETE ON TABLE public.employee_document_access_rule TO postgres;
GRANT INSERT ON TABLE public.employee_document_access_rule TO postgres;
GRANT MAINTAIN ON TABLE public.employee_document_access_rule TO postgres;
GRANT REFERENCES ON TABLE public.employee_document_access_rule TO postgres;
GRANT SELECT ON TABLE public.employee_document_access_rule TO postgres;
GRANT TRIGGER ON TABLE public.employee_document_access_rule TO postgres;
GRANT TRUNCATE ON TABLE public.employee_document_access_rule TO postgres;
GRANT UPDATE ON TABLE public.employee_document_access_rule TO postgres;
GRANT DELETE ON TABLE public.employee_document_access_rule TO service_role;
GRANT INSERT ON TABLE public.employee_document_access_rule TO service_role;
GRANT MAINTAIN ON TABLE public.employee_document_access_rule TO service_role;
GRANT REFERENCES ON TABLE public.employee_document_access_rule TO service_role;
GRANT SELECT ON TABLE public.employee_document_access_rule TO service_role;
GRANT TRIGGER ON TABLE public.employee_document_access_rule TO service_role;
GRANT TRUNCATE ON TABLE public.employee_document_access_rule TO service_role;
GRANT UPDATE ON TABLE public.employee_document_access_rule TO service_role;
GRANT SELECT ON TABLE public.employee_document_access_rule_employee_document_access_rule_seq TO postgres;
GRANT UPDATE ON TABLE public.employee_document_access_rule_employee_document_access_rule_seq TO postgres;
GRANT USAGE ON TABLE public.employee_document_access_rule_employee_document_access_rule_seq TO postgres;
GRANT SELECT ON TABLE public.employee_document_access_rule_employee_document_access_rule_seq TO service_role;
GRANT UPDATE ON TABLE public.employee_document_access_rule_employee_document_access_rule_seq TO service_role;
GRANT USAGE ON TABLE public.employee_document_access_rule_employee_document_access_rule_seq TO service_role;
GRANT DELETE ON TABLE public.employee_document_category TO authenticated;
GRANT INSERT ON TABLE public.employee_document_category TO authenticated;
GRANT UPDATE ON TABLE public.employee_document_category TO authenticated;
GRANT DELETE ON TABLE public.employee_document_category TO postgres;
GRANT INSERT ON TABLE public.employee_document_category TO postgres;
GRANT MAINTAIN ON TABLE public.employee_document_category TO postgres;
GRANT REFERENCES ON TABLE public.employee_document_category TO postgres;
GRANT SELECT ON TABLE public.employee_document_category TO postgres;
GRANT TRIGGER ON TABLE public.employee_document_category TO postgres;
GRANT TRUNCATE ON TABLE public.employee_document_category TO postgres;
GRANT UPDATE ON TABLE public.employee_document_category TO postgres;
GRANT DELETE ON TABLE public.employee_document_category TO service_role;
GRANT INSERT ON TABLE public.employee_document_category TO service_role;
GRANT MAINTAIN ON TABLE public.employee_document_category TO service_role;
GRANT REFERENCES ON TABLE public.employee_document_category TO service_role;
GRANT SELECT ON TABLE public.employee_document_category TO service_role;
GRANT TRIGGER ON TABLE public.employee_document_category TO service_role;
GRANT TRUNCATE ON TABLE public.employee_document_category TO service_role;
GRANT UPDATE ON TABLE public.employee_document_category TO service_role;
GRANT SELECT ON TABLE public.employee_document_category_employee_document_category_id_seq TO postgres;
GRANT UPDATE ON TABLE public.employee_document_category_employee_document_category_id_seq TO postgres;
GRANT USAGE ON TABLE public.employee_document_category_employee_document_category_id_seq TO postgres;
GRANT SELECT ON TABLE public.employee_document_category_employee_document_category_id_seq TO service_role;
GRANT UPDATE ON TABLE public.employee_document_category_employee_document_category_id_seq TO service_role;
GRANT USAGE ON TABLE public.employee_document_category_employee_document_category_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.employee_document_delete(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.employee_document_delete(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.employee_document_delete(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.employee_document_download_info(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.employee_document_download_info(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.employee_document_download_info(p_id bigint) TO service_role;
GRANT SELECT ON TABLE public.employee_document_employee_document_id_seq TO postgres;
GRANT UPDATE ON TABLE public.employee_document_employee_document_id_seq TO postgres;
GRANT USAGE ON TABLE public.employee_document_employee_document_id_seq TO postgres;
GRANT SELECT ON TABLE public.employee_document_employee_document_id_seq TO service_role;
GRANT UPDATE ON TABLE public.employee_document_employee_document_id_seq TO service_role;
GRANT USAGE ON TABLE public.employee_document_employee_document_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.employee_document_list(p_employee_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.employee_document_list(p_employee_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.employee_document_list(p_employee_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.employee_document_register(p_employee_id bigint, p_category_id integer, p_document_type_id integer, p_title text, p_storage_key text, p_file_name text, p_mime_type text, p_size bigint, p_checksum text, p_document_number text, p_issue_date date, p_expiry_date date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.employee_document_register(p_employee_id bigint, p_category_id integer, p_document_type_id integer, p_title text, p_storage_key text, p_file_name text, p_mime_type text, p_size bigint, p_checksum text, p_document_number text, p_issue_date date, p_expiry_date date) TO postgres;
GRANT EXECUTE ON FUNCTION public.employee_document_register(p_employee_id bigint, p_category_id integer, p_document_type_id integer, p_title text, p_storage_key text, p_file_name text, p_mime_type text, p_size bigint, p_checksum text, p_document_number text, p_issue_date date, p_expiry_date date) TO service_role;
GRANT EXECUTE ON FUNCTION public.employee_document_review(p_id bigint, p_decision text, p_remarks text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.employee_document_review(p_id bigint, p_decision text, p_remarks text) TO postgres;
GRANT EXECUTE ON FUNCTION public.employee_document_review(p_id bigint, p_decision text, p_remarks text) TO service_role;
GRANT SELECT ON TABLE public.employee_employee_id_seq TO postgres;
GRANT UPDATE ON TABLE public.employee_employee_id_seq TO postgres;
GRANT USAGE ON TABLE public.employee_employee_id_seq TO postgres;
GRANT SELECT ON TABLE public.employee_employee_id_seq TO service_role;
GRANT UPDATE ON TABLE public.employee_employee_id_seq TO service_role;
GRANT USAGE ON TABLE public.employee_employee_id_seq TO service_role;
GRANT DELETE ON TABLE public.employee_pan TO authenticated;
GRANT INSERT ON TABLE public.employee_pan TO authenticated;
GRANT UPDATE ON TABLE public.employee_pan TO authenticated;
GRANT DELETE ON TABLE public.employee_pan TO postgres;
GRANT INSERT ON TABLE public.employee_pan TO postgres;
GRANT MAINTAIN ON TABLE public.employee_pan TO postgres;
GRANT REFERENCES ON TABLE public.employee_pan TO postgres;
GRANT SELECT ON TABLE public.employee_pan TO postgres;
GRANT TRIGGER ON TABLE public.employee_pan TO postgres;
GRANT TRUNCATE ON TABLE public.employee_pan TO postgres;
GRANT UPDATE ON TABLE public.employee_pan TO postgres;
GRANT DELETE ON TABLE public.employee_pan TO service_role;
GRANT INSERT ON TABLE public.employee_pan TO service_role;
GRANT MAINTAIN ON TABLE public.employee_pan TO service_role;
GRANT REFERENCES ON TABLE public.employee_pan TO service_role;
GRANT SELECT ON TABLE public.employee_pan TO service_role;
GRANT TRIGGER ON TABLE public.employee_pan TO service_role;
GRANT TRUNCATE ON TABLE public.employee_pan TO service_role;
GRANT UPDATE ON TABLE public.employee_pan TO service_role;
GRANT SELECT ON TABLE public.employee_pan_employee_pan_id_seq TO postgres;
GRANT UPDATE ON TABLE public.employee_pan_employee_pan_id_seq TO postgres;
GRANT USAGE ON TABLE public.employee_pan_employee_pan_id_seq TO postgres;
GRANT SELECT ON TABLE public.employee_pan_employee_pan_id_seq TO service_role;
GRANT UPDATE ON TABLE public.employee_pan_employee_pan_id_seq TO service_role;
GRANT USAGE ON TABLE public.employee_pan_employee_pan_id_seq TO service_role;
GRANT DELETE ON TABLE public.employee_previous_employment TO authenticated;
GRANT INSERT ON TABLE public.employee_previous_employment TO authenticated;
GRANT UPDATE ON TABLE public.employee_previous_employment TO authenticated;
GRANT DELETE ON TABLE public.employee_previous_employment TO postgres;
GRANT INSERT ON TABLE public.employee_previous_employment TO postgres;
GRANT MAINTAIN ON TABLE public.employee_previous_employment TO postgres;
GRANT REFERENCES ON TABLE public.employee_previous_employment TO postgres;
GRANT SELECT ON TABLE public.employee_previous_employment TO postgres;
GRANT TRIGGER ON TABLE public.employee_previous_employment TO postgres;
GRANT TRUNCATE ON TABLE public.employee_previous_employment TO postgres;
GRANT UPDATE ON TABLE public.employee_previous_employment TO postgres;
GRANT DELETE ON TABLE public.employee_previous_employment TO service_role;
GRANT INSERT ON TABLE public.employee_previous_employment TO service_role;
GRANT MAINTAIN ON TABLE public.employee_previous_employment TO service_role;
GRANT REFERENCES ON TABLE public.employee_previous_employment TO service_role;
GRANT SELECT ON TABLE public.employee_previous_employment TO service_role;
GRANT TRIGGER ON TABLE public.employee_previous_employment TO service_role;
GRANT TRUNCATE ON TABLE public.employee_previous_employment TO service_role;
GRANT UPDATE ON TABLE public.employee_previous_employment TO service_role;
GRANT SELECT ON TABLE public.employee_previous_employment_employee_previous_employment_i_seq TO postgres;
GRANT UPDATE ON TABLE public.employee_previous_employment_employee_previous_employment_i_seq TO postgres;
GRANT USAGE ON TABLE public.employee_previous_employment_employee_previous_employment_i_seq TO postgres;
GRANT SELECT ON TABLE public.employee_previous_employment_employee_previous_employment_i_seq TO service_role;
GRANT UPDATE ON TABLE public.employee_previous_employment_employee_previous_employment_i_seq TO service_role;
GRANT USAGE ON TABLE public.employee_previous_employment_employee_previous_employment_i_seq TO service_role;
GRANT DELETE ON TABLE public.employee_qualification TO authenticated;
GRANT INSERT ON TABLE public.employee_qualification TO authenticated;
GRANT UPDATE ON TABLE public.employee_qualification TO authenticated;
GRANT DELETE ON TABLE public.employee_qualification TO postgres;
GRANT INSERT ON TABLE public.employee_qualification TO postgres;
GRANT MAINTAIN ON TABLE public.employee_qualification TO postgres;
GRANT REFERENCES ON TABLE public.employee_qualification TO postgres;
GRANT SELECT ON TABLE public.employee_qualification TO postgres;
GRANT TRIGGER ON TABLE public.employee_qualification TO postgres;
GRANT TRUNCATE ON TABLE public.employee_qualification TO postgres;
GRANT UPDATE ON TABLE public.employee_qualification TO postgres;
GRANT DELETE ON TABLE public.employee_qualification TO service_role;
GRANT INSERT ON TABLE public.employee_qualification TO service_role;
GRANT MAINTAIN ON TABLE public.employee_qualification TO service_role;
GRANT REFERENCES ON TABLE public.employee_qualification TO service_role;
GRANT SELECT ON TABLE public.employee_qualification TO service_role;
GRANT TRIGGER ON TABLE public.employee_qualification TO service_role;
GRANT TRUNCATE ON TABLE public.employee_qualification TO service_role;
GRANT UPDATE ON TABLE public.employee_qualification TO service_role;
GRANT SELECT ON TABLE public.employee_qualification_employee_qualification_id_seq TO postgres;
GRANT UPDATE ON TABLE public.employee_qualification_employee_qualification_id_seq TO postgres;
GRANT USAGE ON TABLE public.employee_qualification_employee_qualification_id_seq TO postgres;
GRANT SELECT ON TABLE public.employee_qualification_employee_qualification_id_seq TO service_role;
GRANT UPDATE ON TABLE public.employee_qualification_employee_qualification_id_seq TO service_role;
GRANT USAGE ON TABLE public.employee_qualification_employee_qualification_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.employee_register(p_employee jsonb, p_assignment jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.employee_register(p_employee jsonb, p_assignment jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.employee_register(p_employee jsonb, p_assignment jsonb) TO service_role;
GRANT SELECT ON TABLE public.employee_sensitive_access_aud_employee_sensitive_access_aud_seq TO postgres;
GRANT UPDATE ON TABLE public.employee_sensitive_access_aud_employee_sensitive_access_aud_seq TO postgres;
GRANT USAGE ON TABLE public.employee_sensitive_access_aud_employee_sensitive_access_aud_seq TO postgres;
GRANT SELECT ON TABLE public.employee_sensitive_access_aud_employee_sensitive_access_aud_seq TO service_role;
GRANT UPDATE ON TABLE public.employee_sensitive_access_aud_employee_sensitive_access_aud_seq TO service_role;
GRANT USAGE ON TABLE public.employee_sensitive_access_aud_employee_sensitive_access_aud_seq TO service_role;
GRANT DELETE ON TABLE public.employee_sensitive_access_audit TO postgres;
GRANT INSERT ON TABLE public.employee_sensitive_access_audit TO postgres;
GRANT MAINTAIN ON TABLE public.employee_sensitive_access_audit TO postgres;
GRANT REFERENCES ON TABLE public.employee_sensitive_access_audit TO postgres;
GRANT SELECT ON TABLE public.employee_sensitive_access_audit TO postgres;
GRANT TRIGGER ON TABLE public.employee_sensitive_access_audit TO postgres;
GRANT TRUNCATE ON TABLE public.employee_sensitive_access_audit TO postgres;
GRANT UPDATE ON TABLE public.employee_sensitive_access_audit TO postgres;
GRANT DELETE ON TABLE public.employee_sensitive_access_audit TO service_role;
GRANT INSERT ON TABLE public.employee_sensitive_access_audit TO service_role;
GRANT MAINTAIN ON TABLE public.employee_sensitive_access_audit TO service_role;
GRANT REFERENCES ON TABLE public.employee_sensitive_access_audit TO service_role;
GRANT SELECT ON TABLE public.employee_sensitive_access_audit TO service_role;
GRANT TRIGGER ON TABLE public.employee_sensitive_access_audit TO service_role;
GRANT TRUNCATE ON TABLE public.employee_sensitive_access_audit TO service_role;
GRANT UPDATE ON TABLE public.employee_sensitive_access_audit TO service_role;
GRANT DELETE ON TABLE public.employee_user_account TO postgres;
GRANT INSERT ON TABLE public.employee_user_account TO postgres;
GRANT MAINTAIN ON TABLE public.employee_user_account TO postgres;
GRANT REFERENCES ON TABLE public.employee_user_account TO postgres;
GRANT SELECT ON TABLE public.employee_user_account TO postgres;
GRANT TRIGGER ON TABLE public.employee_user_account TO postgres;
GRANT TRUNCATE ON TABLE public.employee_user_account TO postgres;
GRANT UPDATE ON TABLE public.employee_user_account TO postgres;
GRANT DELETE ON TABLE public.employee_user_account TO service_role;
GRANT INSERT ON TABLE public.employee_user_account TO service_role;
GRANT MAINTAIN ON TABLE public.employee_user_account TO service_role;
GRANT REFERENCES ON TABLE public.employee_user_account TO service_role;
GRANT SELECT ON TABLE public.employee_user_account TO service_role;
GRANT TRIGGER ON TABLE public.employee_user_account TO service_role;
GRANT TRUNCATE ON TABLE public.employee_user_account TO service_role;
GRANT UPDATE ON TABLE public.employee_user_account TO service_role;
GRANT DELETE ON TABLE public.employment_source TO authenticated;
GRANT INSERT ON TABLE public.employment_source TO authenticated;
GRANT UPDATE ON TABLE public.employment_source TO authenticated;
GRANT DELETE ON TABLE public.employment_source TO postgres;
GRANT INSERT ON TABLE public.employment_source TO postgres;
GRANT MAINTAIN ON TABLE public.employment_source TO postgres;
GRANT REFERENCES ON TABLE public.employment_source TO postgres;
GRANT SELECT ON TABLE public.employment_source TO postgres;
GRANT TRIGGER ON TABLE public.employment_source TO postgres;
GRANT TRUNCATE ON TABLE public.employment_source TO postgres;
GRANT UPDATE ON TABLE public.employment_source TO postgres;
GRANT DELETE ON TABLE public.employment_source TO service_role;
GRANT INSERT ON TABLE public.employment_source TO service_role;
GRANT MAINTAIN ON TABLE public.employment_source TO service_role;
GRANT REFERENCES ON TABLE public.employment_source TO service_role;
GRANT SELECT ON TABLE public.employment_source TO service_role;
GRANT TRIGGER ON TABLE public.employment_source TO service_role;
GRANT TRUNCATE ON TABLE public.employment_source TO service_role;
GRANT UPDATE ON TABLE public.employment_source TO service_role;
GRANT SELECT ON TABLE public.employment_source_employment_source_id_seq TO postgres;
GRANT UPDATE ON TABLE public.employment_source_employment_source_id_seq TO postgres;
GRANT USAGE ON TABLE public.employment_source_employment_source_id_seq TO postgres;
GRANT SELECT ON TABLE public.employment_source_employment_source_id_seq TO service_role;
GRANT UPDATE ON TABLE public.employment_source_employment_source_id_seq TO service_role;
GRANT USAGE ON TABLE public.employment_source_employment_source_id_seq TO service_role;
GRANT DELETE ON TABLE public.enrolment_status_history TO authenticated;
GRANT INSERT ON TABLE public.enrolment_status_history TO authenticated;
GRANT UPDATE ON TABLE public.enrolment_status_history TO authenticated;
GRANT DELETE ON TABLE public.enrolment_status_history TO postgres;
GRANT INSERT ON TABLE public.enrolment_status_history TO postgres;
GRANT MAINTAIN ON TABLE public.enrolment_status_history TO postgres;
GRANT REFERENCES ON TABLE public.enrolment_status_history TO postgres;
GRANT SELECT ON TABLE public.enrolment_status_history TO postgres;
GRANT TRIGGER ON TABLE public.enrolment_status_history TO postgres;
GRANT TRUNCATE ON TABLE public.enrolment_status_history TO postgres;
GRANT UPDATE ON TABLE public.enrolment_status_history TO postgres;
GRANT DELETE ON TABLE public.enrolment_status_history TO service_role;
GRANT INSERT ON TABLE public.enrolment_status_history TO service_role;
GRANT MAINTAIN ON TABLE public.enrolment_status_history TO service_role;
GRANT REFERENCES ON TABLE public.enrolment_status_history TO service_role;
GRANT SELECT ON TABLE public.enrolment_status_history TO service_role;
GRANT TRIGGER ON TABLE public.enrolment_status_history TO service_role;
GRANT TRUNCATE ON TABLE public.enrolment_status_history TO service_role;
GRANT UPDATE ON TABLE public.enrolment_status_history TO service_role;
GRANT SELECT ON TABLE public.enrolment_status_history_enrolment_status_history_id_seq TO postgres;
GRANT UPDATE ON TABLE public.enrolment_status_history_enrolment_status_history_id_seq TO postgres;
GRANT USAGE ON TABLE public.enrolment_status_history_enrolment_status_history_id_seq TO postgres;
GRANT SELECT ON TABLE public.enrolment_status_history_enrolment_status_history_id_seq TO service_role;
GRANT UPDATE ON TABLE public.enrolment_status_history_enrolment_status_history_id_seq TO service_role;
GRANT USAGE ON TABLE public.enrolment_status_history_enrolment_status_history_id_seq TO service_role;
GRANT DELETE ON TABLE public.event_mode TO authenticated;
GRANT INSERT ON TABLE public.event_mode TO authenticated;
GRANT UPDATE ON TABLE public.event_mode TO authenticated;
GRANT DELETE ON TABLE public.event_mode TO postgres;
GRANT INSERT ON TABLE public.event_mode TO postgres;
GRANT MAINTAIN ON TABLE public.event_mode TO postgres;
GRANT REFERENCES ON TABLE public.event_mode TO postgres;
GRANT SELECT ON TABLE public.event_mode TO postgres;
GRANT TRIGGER ON TABLE public.event_mode TO postgres;
GRANT TRUNCATE ON TABLE public.event_mode TO postgres;
GRANT UPDATE ON TABLE public.event_mode TO postgres;
GRANT DELETE ON TABLE public.event_mode TO service_role;
GRANT INSERT ON TABLE public.event_mode TO service_role;
GRANT MAINTAIN ON TABLE public.event_mode TO service_role;
GRANT REFERENCES ON TABLE public.event_mode TO service_role;
GRANT SELECT ON TABLE public.event_mode TO service_role;
GRANT TRIGGER ON TABLE public.event_mode TO service_role;
GRANT TRUNCATE ON TABLE public.event_mode TO service_role;
GRANT UPDATE ON TABLE public.event_mode TO service_role;
GRANT SELECT ON TABLE public.event_mode_event_mode_id_seq TO postgres;
GRANT UPDATE ON TABLE public.event_mode_event_mode_id_seq TO postgres;
GRANT USAGE ON TABLE public.event_mode_event_mode_id_seq TO postgres;
GRANT SELECT ON TABLE public.event_mode_event_mode_id_seq TO service_role;
GRANT UPDATE ON TABLE public.event_mode_event_mode_id_seq TO service_role;
GRANT USAGE ON TABLE public.event_mode_event_mode_id_seq TO service_role;
GRANT DELETE ON TABLE public.evidence_document TO postgres;
GRANT INSERT ON TABLE public.evidence_document TO postgres;
GRANT MAINTAIN ON TABLE public.evidence_document TO postgres;
GRANT REFERENCES ON TABLE public.evidence_document TO postgres;
GRANT SELECT ON TABLE public.evidence_document TO postgres;
GRANT TRIGGER ON TABLE public.evidence_document TO postgres;
GRANT TRUNCATE ON TABLE public.evidence_document TO postgres;
GRANT UPDATE ON TABLE public.evidence_document TO postgres;
GRANT DELETE ON TABLE public.evidence_document TO service_role;
GRANT INSERT ON TABLE public.evidence_document TO service_role;
GRANT MAINTAIN ON TABLE public.evidence_document TO service_role;
GRANT REFERENCES ON TABLE public.evidence_document TO service_role;
GRANT SELECT ON TABLE public.evidence_document TO service_role;
GRANT TRIGGER ON TABLE public.evidence_document TO service_role;
GRANT TRUNCATE ON TABLE public.evidence_document TO service_role;
GRANT UPDATE ON TABLE public.evidence_document TO service_role;
GRANT DELETE ON TABLE public.evidence_document_audit TO postgres;
GRANT INSERT ON TABLE public.evidence_document_audit TO postgres;
GRANT MAINTAIN ON TABLE public.evidence_document_audit TO postgres;
GRANT REFERENCES ON TABLE public.evidence_document_audit TO postgres;
GRANT SELECT ON TABLE public.evidence_document_audit TO postgres;
GRANT TRIGGER ON TABLE public.evidence_document_audit TO postgres;
GRANT TRUNCATE ON TABLE public.evidence_document_audit TO postgres;
GRANT UPDATE ON TABLE public.evidence_document_audit TO postgres;
GRANT DELETE ON TABLE public.evidence_document_audit TO service_role;
GRANT INSERT ON TABLE public.evidence_document_audit TO service_role;
GRANT MAINTAIN ON TABLE public.evidence_document_audit TO service_role;
GRANT REFERENCES ON TABLE public.evidence_document_audit TO service_role;
GRANT SELECT ON TABLE public.evidence_document_audit TO service_role;
GRANT TRIGGER ON TABLE public.evidence_document_audit TO service_role;
GRANT TRUNCATE ON TABLE public.evidence_document_audit TO service_role;
GRANT UPDATE ON TABLE public.evidence_document_audit TO service_role;
GRANT SELECT ON TABLE public.evidence_document_audit_evidence_document_audit_id_seq TO postgres;
GRANT UPDATE ON TABLE public.evidence_document_audit_evidence_document_audit_id_seq TO postgres;
GRANT USAGE ON TABLE public.evidence_document_audit_evidence_document_audit_id_seq TO postgres;
GRANT SELECT ON TABLE public.evidence_document_audit_evidence_document_audit_id_seq TO service_role;
GRANT UPDATE ON TABLE public.evidence_document_audit_evidence_document_audit_id_seq TO service_role;
GRANT USAGE ON TABLE public.evidence_document_audit_evidence_document_audit_id_seq TO service_role;
GRANT SELECT ON TABLE public.evidence_document_evidence_document_id_seq TO postgres;
GRANT UPDATE ON TABLE public.evidence_document_evidence_document_id_seq TO postgres;
GRANT USAGE ON TABLE public.evidence_document_evidence_document_id_seq TO postgres;
GRANT SELECT ON TABLE public.evidence_document_evidence_document_id_seq TO service_role;
GRANT UPDATE ON TABLE public.evidence_document_evidence_document_id_seq TO service_role;
GRANT USAGE ON TABLE public.evidence_document_evidence_document_id_seq TO service_role;
GRANT DELETE ON TABLE public.evidence_document_tag TO authenticated;
GRANT INSERT ON TABLE public.evidence_document_tag TO authenticated;
GRANT UPDATE ON TABLE public.evidence_document_tag TO authenticated;
GRANT DELETE ON TABLE public.evidence_document_tag TO postgres;
GRANT INSERT ON TABLE public.evidence_document_tag TO postgres;
GRANT MAINTAIN ON TABLE public.evidence_document_tag TO postgres;
GRANT REFERENCES ON TABLE public.evidence_document_tag TO postgres;
GRANT SELECT ON TABLE public.evidence_document_tag TO postgres;
GRANT TRIGGER ON TABLE public.evidence_document_tag TO postgres;
GRANT TRUNCATE ON TABLE public.evidence_document_tag TO postgres;
GRANT UPDATE ON TABLE public.evidence_document_tag TO postgres;
GRANT DELETE ON TABLE public.evidence_document_tag TO service_role;
GRANT INSERT ON TABLE public.evidence_document_tag TO service_role;
GRANT MAINTAIN ON TABLE public.evidence_document_tag TO service_role;
GRANT REFERENCES ON TABLE public.evidence_document_tag TO service_role;
GRANT SELECT ON TABLE public.evidence_document_tag TO service_role;
GRANT TRIGGER ON TABLE public.evidence_document_tag TO service_role;
GRANT TRUNCATE ON TABLE public.evidence_document_tag TO service_role;
GRANT UPDATE ON TABLE public.evidence_document_tag TO service_role;
GRANT DELETE ON TABLE public.evidence_document_version TO postgres;
GRANT INSERT ON TABLE public.evidence_document_version TO postgres;
GRANT MAINTAIN ON TABLE public.evidence_document_version TO postgres;
GRANT REFERENCES ON TABLE public.evidence_document_version TO postgres;
GRANT SELECT ON TABLE public.evidence_document_version TO postgres;
GRANT TRIGGER ON TABLE public.evidence_document_version TO postgres;
GRANT TRUNCATE ON TABLE public.evidence_document_version TO postgres;
GRANT UPDATE ON TABLE public.evidence_document_version TO postgres;
GRANT DELETE ON TABLE public.evidence_document_version TO service_role;
GRANT INSERT ON TABLE public.evidence_document_version TO service_role;
GRANT MAINTAIN ON TABLE public.evidence_document_version TO service_role;
GRANT REFERENCES ON TABLE public.evidence_document_version TO service_role;
GRANT SELECT ON TABLE public.evidence_document_version TO service_role;
GRANT TRIGGER ON TABLE public.evidence_document_version TO service_role;
GRANT TRUNCATE ON TABLE public.evidence_document_version TO service_role;
GRANT UPDATE ON TABLE public.evidence_document_version TO service_role;
GRANT SELECT ON TABLE public.evidence_document_version_evidence_document_version_id_seq TO postgres;
GRANT UPDATE ON TABLE public.evidence_document_version_evidence_document_version_id_seq TO postgres;
GRANT USAGE ON TABLE public.evidence_document_version_evidence_document_version_id_seq TO postgres;
GRANT SELECT ON TABLE public.evidence_document_version_evidence_document_version_id_seq TO service_role;
GRANT UPDATE ON TABLE public.evidence_document_version_evidence_document_version_id_seq TO service_role;
GRANT USAGE ON TABLE public.evidence_document_version_evidence_document_version_id_seq TO service_role;
GRANT DELETE ON TABLE public.evidence_tag TO authenticated;
GRANT INSERT ON TABLE public.evidence_tag TO authenticated;
GRANT UPDATE ON TABLE public.evidence_tag TO authenticated;
GRANT DELETE ON TABLE public.evidence_tag TO postgres;
GRANT INSERT ON TABLE public.evidence_tag TO postgres;
GRANT MAINTAIN ON TABLE public.evidence_tag TO postgres;
GRANT REFERENCES ON TABLE public.evidence_tag TO postgres;
GRANT SELECT ON TABLE public.evidence_tag TO postgres;
GRANT TRIGGER ON TABLE public.evidence_tag TO postgres;
GRANT TRUNCATE ON TABLE public.evidence_tag TO postgres;
GRANT UPDATE ON TABLE public.evidence_tag TO postgres;
GRANT DELETE ON TABLE public.evidence_tag TO service_role;
GRANT INSERT ON TABLE public.evidence_tag TO service_role;
GRANT MAINTAIN ON TABLE public.evidence_tag TO service_role;
GRANT REFERENCES ON TABLE public.evidence_tag TO service_role;
GRANT SELECT ON TABLE public.evidence_tag TO service_role;
GRANT TRIGGER ON TABLE public.evidence_tag TO service_role;
GRANT TRUNCATE ON TABLE public.evidence_tag TO service_role;
GRANT UPDATE ON TABLE public.evidence_tag TO service_role;
GRANT SELECT ON TABLE public.evidence_tag_evidence_tag_id_seq TO postgres;
GRANT UPDATE ON TABLE public.evidence_tag_evidence_tag_id_seq TO postgres;
GRANT USAGE ON TABLE public.evidence_tag_evidence_tag_id_seq TO postgres;
GRANT SELECT ON TABLE public.evidence_tag_evidence_tag_id_seq TO service_role;
GRANT UPDATE ON TABLE public.evidence_tag_evidence_tag_id_seq TO service_role;
GRANT USAGE ON TABLE public.evidence_tag_evidence_tag_id_seq TO service_role;
GRANT DELETE ON TABLE public.evidence_type TO authenticated;
GRANT INSERT ON TABLE public.evidence_type TO authenticated;
GRANT UPDATE ON TABLE public.evidence_type TO authenticated;
GRANT DELETE ON TABLE public.evidence_type TO postgres;
GRANT INSERT ON TABLE public.evidence_type TO postgres;
GRANT MAINTAIN ON TABLE public.evidence_type TO postgres;
GRANT REFERENCES ON TABLE public.evidence_type TO postgres;
GRANT SELECT ON TABLE public.evidence_type TO postgres;
GRANT TRIGGER ON TABLE public.evidence_type TO postgres;
GRANT TRUNCATE ON TABLE public.evidence_type TO postgres;
GRANT UPDATE ON TABLE public.evidence_type TO postgres;
GRANT DELETE ON TABLE public.evidence_type TO service_role;
GRANT INSERT ON TABLE public.evidence_type TO service_role;
GRANT MAINTAIN ON TABLE public.evidence_type TO service_role;
GRANT REFERENCES ON TABLE public.evidence_type TO service_role;
GRANT SELECT ON TABLE public.evidence_type TO service_role;
GRANT TRIGGER ON TABLE public.evidence_type TO service_role;
GRANT TRUNCATE ON TABLE public.evidence_type TO service_role;
GRANT UPDATE ON TABLE public.evidence_type TO service_role;
GRANT SELECT ON TABLE public.evidence_type_evidence_type_id_seq TO postgres;
GRANT UPDATE ON TABLE public.evidence_type_evidence_type_id_seq TO postgres;
GRANT USAGE ON TABLE public.evidence_type_evidence_type_id_seq TO postgres;
GRANT SELECT ON TABLE public.evidence_type_evidence_type_id_seq TO service_role;
GRANT UPDATE ON TABLE public.evidence_type_evidence_type_id_seq TO service_role;
GRANT USAGE ON TABLE public.evidence_type_evidence_type_id_seq TO service_role;
GRANT DELETE ON TABLE public.external_agency TO authenticated;
GRANT INSERT ON TABLE public.external_agency TO authenticated;
GRANT UPDATE ON TABLE public.external_agency TO authenticated;
GRANT DELETE ON TABLE public.external_agency TO postgres;
GRANT INSERT ON TABLE public.external_agency TO postgres;
GRANT MAINTAIN ON TABLE public.external_agency TO postgres;
GRANT REFERENCES ON TABLE public.external_agency TO postgres;
GRANT SELECT ON TABLE public.external_agency TO postgres;
GRANT TRIGGER ON TABLE public.external_agency TO postgres;
GRANT TRUNCATE ON TABLE public.external_agency TO postgres;
GRANT UPDATE ON TABLE public.external_agency TO postgres;
GRANT DELETE ON TABLE public.external_agency TO service_role;
GRANT INSERT ON TABLE public.external_agency TO service_role;
GRANT MAINTAIN ON TABLE public.external_agency TO service_role;
GRANT REFERENCES ON TABLE public.external_agency TO service_role;
GRANT SELECT ON TABLE public.external_agency TO service_role;
GRANT TRIGGER ON TABLE public.external_agency TO service_role;
GRANT TRUNCATE ON TABLE public.external_agency TO service_role;
GRANT UPDATE ON TABLE public.external_agency TO service_role;
GRANT SELECT ON TABLE public.external_agency_external_agency_id_seq TO postgres;
GRANT UPDATE ON TABLE public.external_agency_external_agency_id_seq TO postgres;
GRANT USAGE ON TABLE public.external_agency_external_agency_id_seq TO postgres;
GRANT SELECT ON TABLE public.external_agency_external_agency_id_seq TO service_role;
GRANT UPDATE ON TABLE public.external_agency_external_agency_id_seq TO service_role;
GRANT USAGE ON TABLE public.external_agency_external_agency_id_seq TO service_role;
GRANT DELETE ON TABLE public.external_organization TO authenticated;
GRANT INSERT ON TABLE public.external_organization TO authenticated;
GRANT UPDATE ON TABLE public.external_organization TO authenticated;
GRANT DELETE ON TABLE public.external_organization TO postgres;
GRANT INSERT ON TABLE public.external_organization TO postgres;
GRANT MAINTAIN ON TABLE public.external_organization TO postgres;
GRANT REFERENCES ON TABLE public.external_organization TO postgres;
GRANT SELECT ON TABLE public.external_organization TO postgres;
GRANT TRIGGER ON TABLE public.external_organization TO postgres;
GRANT TRUNCATE ON TABLE public.external_organization TO postgres;
GRANT UPDATE ON TABLE public.external_organization TO postgres;
GRANT DELETE ON TABLE public.external_organization TO service_role;
GRANT INSERT ON TABLE public.external_organization TO service_role;
GRANT MAINTAIN ON TABLE public.external_organization TO service_role;
GRANT REFERENCES ON TABLE public.external_organization TO service_role;
GRANT SELECT ON TABLE public.external_organization TO service_role;
GRANT TRIGGER ON TABLE public.external_organization TO service_role;
GRANT TRUNCATE ON TABLE public.external_organization TO service_role;
GRANT UPDATE ON TABLE public.external_organization TO service_role;
GRANT SELECT ON TABLE public.external_organization_organization_id_seq TO postgres;
GRANT UPDATE ON TABLE public.external_organization_organization_id_seq TO postgres;
GRANT USAGE ON TABLE public.external_organization_organization_id_seq TO postgres;
GRANT SELECT ON TABLE public.external_organization_organization_id_seq TO service_role;
GRANT UPDATE ON TABLE public.external_organization_organization_id_seq TO service_role;
GRANT USAGE ON TABLE public.external_organization_organization_id_seq TO service_role;
GRANT DELETE ON TABLE public.external_organization_type TO authenticated;
GRANT INSERT ON TABLE public.external_organization_type TO authenticated;
GRANT UPDATE ON TABLE public.external_organization_type TO authenticated;
GRANT DELETE ON TABLE public.external_organization_type TO postgres;
GRANT INSERT ON TABLE public.external_organization_type TO postgres;
GRANT MAINTAIN ON TABLE public.external_organization_type TO postgres;
GRANT REFERENCES ON TABLE public.external_organization_type TO postgres;
GRANT SELECT ON TABLE public.external_organization_type TO postgres;
GRANT TRIGGER ON TABLE public.external_organization_type TO postgres;
GRANT TRUNCATE ON TABLE public.external_organization_type TO postgres;
GRANT UPDATE ON TABLE public.external_organization_type TO postgres;
GRANT DELETE ON TABLE public.external_organization_type TO service_role;
GRANT INSERT ON TABLE public.external_organization_type TO service_role;
GRANT MAINTAIN ON TABLE public.external_organization_type TO service_role;
GRANT REFERENCES ON TABLE public.external_organization_type TO service_role;
GRANT SELECT ON TABLE public.external_organization_type TO service_role;
GRANT TRIGGER ON TABLE public.external_organization_type TO service_role;
GRANT TRUNCATE ON TABLE public.external_organization_type TO service_role;
GRANT UPDATE ON TABLE public.external_organization_type TO service_role;
GRANT DELETE ON TABLE public.extracurricular_activity TO postgres;
GRANT INSERT ON TABLE public.extracurricular_activity TO postgres;
GRANT MAINTAIN ON TABLE public.extracurricular_activity TO postgres;
GRANT REFERENCES ON TABLE public.extracurricular_activity TO postgres;
GRANT SELECT ON TABLE public.extracurricular_activity TO postgres;
GRANT TRIGGER ON TABLE public.extracurricular_activity TO postgres;
GRANT TRUNCATE ON TABLE public.extracurricular_activity TO postgres;
GRANT UPDATE ON TABLE public.extracurricular_activity TO postgres;
GRANT DELETE ON TABLE public.extracurricular_activity TO service_role;
GRANT INSERT ON TABLE public.extracurricular_activity TO service_role;
GRANT MAINTAIN ON TABLE public.extracurricular_activity TO service_role;
GRANT REFERENCES ON TABLE public.extracurricular_activity TO service_role;
GRANT SELECT ON TABLE public.extracurricular_activity TO service_role;
GRANT TRIGGER ON TABLE public.extracurricular_activity TO service_role;
GRANT TRUNCATE ON TABLE public.extracurricular_activity TO service_role;
GRANT UPDATE ON TABLE public.extracurricular_activity TO service_role;
GRANT DELETE ON TABLE public.extracurricular_category TO authenticated;
GRANT INSERT ON TABLE public.extracurricular_category TO authenticated;
GRANT UPDATE ON TABLE public.extracurricular_category TO authenticated;
GRANT DELETE ON TABLE public.extracurricular_category TO postgres;
GRANT INSERT ON TABLE public.extracurricular_category TO postgres;
GRANT MAINTAIN ON TABLE public.extracurricular_category TO postgres;
GRANT REFERENCES ON TABLE public.extracurricular_category TO postgres;
GRANT SELECT ON TABLE public.extracurricular_category TO postgres;
GRANT TRIGGER ON TABLE public.extracurricular_category TO postgres;
GRANT TRUNCATE ON TABLE public.extracurricular_category TO postgres;
GRANT UPDATE ON TABLE public.extracurricular_category TO postgres;
GRANT DELETE ON TABLE public.extracurricular_category TO service_role;
GRANT INSERT ON TABLE public.extracurricular_category TO service_role;
GRANT MAINTAIN ON TABLE public.extracurricular_category TO service_role;
GRANT REFERENCES ON TABLE public.extracurricular_category TO service_role;
GRANT SELECT ON TABLE public.extracurricular_category TO service_role;
GRANT TRIGGER ON TABLE public.extracurricular_category TO service_role;
GRANT TRUNCATE ON TABLE public.extracurricular_category TO service_role;
GRANT UPDATE ON TABLE public.extracurricular_category TO service_role;
GRANT SELECT ON TABLE public.extracurricular_category_extracurricular_category_id_seq TO postgres;
GRANT UPDATE ON TABLE public.extracurricular_category_extracurricular_category_id_seq TO postgres;
GRANT USAGE ON TABLE public.extracurricular_category_extracurricular_category_id_seq TO postgres;
GRANT SELECT ON TABLE public.extracurricular_category_extracurricular_category_id_seq TO service_role;
GRANT UPDATE ON TABLE public.extracurricular_category_extracurricular_category_id_seq TO service_role;
GRANT USAGE ON TABLE public.extracurricular_category_extracurricular_category_id_seq TO service_role;
GRANT DELETE ON TABLE public.faculty_course_assignment TO authenticated;
GRANT INSERT ON TABLE public.faculty_course_assignment TO authenticated;
GRANT UPDATE ON TABLE public.faculty_course_assignment TO authenticated;
GRANT DELETE ON TABLE public.faculty_course_assignment TO postgres;
GRANT INSERT ON TABLE public.faculty_course_assignment TO postgres;
GRANT MAINTAIN ON TABLE public.faculty_course_assignment TO postgres;
GRANT REFERENCES ON TABLE public.faculty_course_assignment TO postgres;
GRANT SELECT ON TABLE public.faculty_course_assignment TO postgres;
GRANT TRIGGER ON TABLE public.faculty_course_assignment TO postgres;
GRANT TRUNCATE ON TABLE public.faculty_course_assignment TO postgres;
GRANT UPDATE ON TABLE public.faculty_course_assignment TO postgres;
GRANT DELETE ON TABLE public.faculty_course_assignment TO service_role;
GRANT INSERT ON TABLE public.faculty_course_assignment TO service_role;
GRANT MAINTAIN ON TABLE public.faculty_course_assignment TO service_role;
GRANT REFERENCES ON TABLE public.faculty_course_assignment TO service_role;
GRANT SELECT ON TABLE public.faculty_course_assignment TO service_role;
GRANT TRIGGER ON TABLE public.faculty_course_assignment TO service_role;
GRANT TRUNCATE ON TABLE public.faculty_course_assignment TO service_role;
GRANT UPDATE ON TABLE public.faculty_course_assignment TO service_role;
GRANT SELECT ON TABLE public.faculty_course_assignment_faculty_assignment_id_seq TO postgres;
GRANT UPDATE ON TABLE public.faculty_course_assignment_faculty_assignment_id_seq TO postgres;
GRANT USAGE ON TABLE public.faculty_course_assignment_faculty_assignment_id_seq TO postgres;
GRANT SELECT ON TABLE public.faculty_course_assignment_faculty_assignment_id_seq TO service_role;
GRANT UPDATE ON TABLE public.faculty_course_assignment_faculty_assignment_id_seq TO service_role;
GRANT USAGE ON TABLE public.faculty_course_assignment_faculty_assignment_id_seq TO service_role;
GRANT DELETE ON TABLE public.faculty_internship TO postgres;
GRANT INSERT ON TABLE public.faculty_internship TO postgres;
GRANT MAINTAIN ON TABLE public.faculty_internship TO postgres;
GRANT REFERENCES ON TABLE public.faculty_internship TO postgres;
GRANT SELECT ON TABLE public.faculty_internship TO postgres;
GRANT TRIGGER ON TABLE public.faculty_internship TO postgres;
GRANT TRUNCATE ON TABLE public.faculty_internship TO postgres;
GRANT UPDATE ON TABLE public.faculty_internship TO postgres;
GRANT DELETE ON TABLE public.faculty_internship TO service_role;
GRANT INSERT ON TABLE public.faculty_internship TO service_role;
GRANT MAINTAIN ON TABLE public.faculty_internship TO service_role;
GRANT REFERENCES ON TABLE public.faculty_internship TO service_role;
GRANT SELECT ON TABLE public.faculty_internship TO service_role;
GRANT TRIGGER ON TABLE public.faculty_internship TO service_role;
GRANT TRUNCATE ON TABLE public.faculty_internship TO service_role;
GRANT UPDATE ON TABLE public.faculty_internship TO service_role;
GRANT DELETE ON TABLE public.fee_activity_audit TO postgres;
GRANT INSERT ON TABLE public.fee_activity_audit TO postgres;
GRANT MAINTAIN ON TABLE public.fee_activity_audit TO postgres;
GRANT REFERENCES ON TABLE public.fee_activity_audit TO postgres;
GRANT SELECT ON TABLE public.fee_activity_audit TO postgres;
GRANT TRIGGER ON TABLE public.fee_activity_audit TO postgres;
GRANT TRUNCATE ON TABLE public.fee_activity_audit TO postgres;
GRANT UPDATE ON TABLE public.fee_activity_audit TO postgres;
GRANT DELETE ON TABLE public.fee_activity_audit TO service_role;
GRANT INSERT ON TABLE public.fee_activity_audit TO service_role;
GRANT MAINTAIN ON TABLE public.fee_activity_audit TO service_role;
GRANT REFERENCES ON TABLE public.fee_activity_audit TO service_role;
GRANT SELECT ON TABLE public.fee_activity_audit TO service_role;
GRANT TRIGGER ON TABLE public.fee_activity_audit TO service_role;
GRANT TRUNCATE ON TABLE public.fee_activity_audit TO service_role;
GRANT UPDATE ON TABLE public.fee_activity_audit TO service_role;
GRANT SELECT ON TABLE public.fee_activity_audit_fee_audit_id_seq TO postgres;
GRANT UPDATE ON TABLE public.fee_activity_audit_fee_audit_id_seq TO postgres;
GRANT USAGE ON TABLE public.fee_activity_audit_fee_audit_id_seq TO postgres;
GRANT SELECT ON TABLE public.fee_activity_audit_fee_audit_id_seq TO service_role;
GRANT UPDATE ON TABLE public.fee_activity_audit_fee_audit_id_seq TO service_role;
GRANT USAGE ON TABLE public.fee_activity_audit_fee_audit_id_seq TO service_role;
GRANT DELETE ON TABLE public.fee_adjustment TO postgres;
GRANT INSERT ON TABLE public.fee_adjustment TO postgres;
GRANT MAINTAIN ON TABLE public.fee_adjustment TO postgres;
GRANT REFERENCES ON TABLE public.fee_adjustment TO postgres;
GRANT SELECT ON TABLE public.fee_adjustment TO postgres;
GRANT TRIGGER ON TABLE public.fee_adjustment TO postgres;
GRANT TRUNCATE ON TABLE public.fee_adjustment TO postgres;
GRANT UPDATE ON TABLE public.fee_adjustment TO postgres;
GRANT DELETE ON TABLE public.fee_adjustment TO service_role;
GRANT INSERT ON TABLE public.fee_adjustment TO service_role;
GRANT MAINTAIN ON TABLE public.fee_adjustment TO service_role;
GRANT REFERENCES ON TABLE public.fee_adjustment TO service_role;
GRANT SELECT ON TABLE public.fee_adjustment TO service_role;
GRANT TRIGGER ON TABLE public.fee_adjustment TO service_role;
GRANT TRUNCATE ON TABLE public.fee_adjustment TO service_role;
GRANT UPDATE ON TABLE public.fee_adjustment TO service_role;
GRANT SELECT ON TABLE public.fee_adjustment_fee_adjustment_id_seq TO postgres;
GRANT UPDATE ON TABLE public.fee_adjustment_fee_adjustment_id_seq TO postgres;
GRANT USAGE ON TABLE public.fee_adjustment_fee_adjustment_id_seq TO postgres;
GRANT SELECT ON TABLE public.fee_adjustment_fee_adjustment_id_seq TO service_role;
GRANT UPDATE ON TABLE public.fee_adjustment_fee_adjustment_id_seq TO service_role;
GRANT USAGE ON TABLE public.fee_adjustment_fee_adjustment_id_seq TO service_role;
GRANT DELETE ON TABLE public.fee_assessment_benefit TO postgres;
GRANT INSERT ON TABLE public.fee_assessment_benefit TO postgres;
GRANT MAINTAIN ON TABLE public.fee_assessment_benefit TO postgres;
GRANT REFERENCES ON TABLE public.fee_assessment_benefit TO postgres;
GRANT SELECT ON TABLE public.fee_assessment_benefit TO postgres;
GRANT TRIGGER ON TABLE public.fee_assessment_benefit TO postgres;
GRANT TRUNCATE ON TABLE public.fee_assessment_benefit TO postgres;
GRANT UPDATE ON TABLE public.fee_assessment_benefit TO postgres;
GRANT DELETE ON TABLE public.fee_assessment_benefit TO service_role;
GRANT INSERT ON TABLE public.fee_assessment_benefit TO service_role;
GRANT MAINTAIN ON TABLE public.fee_assessment_benefit TO service_role;
GRANT REFERENCES ON TABLE public.fee_assessment_benefit TO service_role;
GRANT SELECT ON TABLE public.fee_assessment_benefit TO service_role;
GRANT TRIGGER ON TABLE public.fee_assessment_benefit TO service_role;
GRANT TRUNCATE ON TABLE public.fee_assessment_benefit TO service_role;
GRANT UPDATE ON TABLE public.fee_assessment_benefit TO service_role;
GRANT SELECT ON TABLE public.fee_assessment_benefit_assessment_benefit_id_seq TO postgres;
GRANT UPDATE ON TABLE public.fee_assessment_benefit_assessment_benefit_id_seq TO postgres;
GRANT USAGE ON TABLE public.fee_assessment_benefit_assessment_benefit_id_seq TO postgres;
GRANT SELECT ON TABLE public.fee_assessment_benefit_assessment_benefit_id_seq TO service_role;
GRANT UPDATE ON TABLE public.fee_assessment_benefit_assessment_benefit_id_seq TO service_role;
GRANT USAGE ON TABLE public.fee_assessment_benefit_assessment_benefit_id_seq TO service_role;
GRANT DELETE ON TABLE public.fee_category TO postgres;
GRANT INSERT ON TABLE public.fee_category TO postgres;
GRANT MAINTAIN ON TABLE public.fee_category TO postgres;
GRANT REFERENCES ON TABLE public.fee_category TO postgres;
GRANT SELECT ON TABLE public.fee_category TO postgres;
GRANT TRIGGER ON TABLE public.fee_category TO postgres;
GRANT TRUNCATE ON TABLE public.fee_category TO postgres;
GRANT UPDATE ON TABLE public.fee_category TO postgres;
GRANT DELETE ON TABLE public.fee_category TO service_role;
GRANT INSERT ON TABLE public.fee_category TO service_role;
GRANT MAINTAIN ON TABLE public.fee_category TO service_role;
GRANT REFERENCES ON TABLE public.fee_category TO service_role;
GRANT SELECT ON TABLE public.fee_category TO service_role;
GRANT TRIGGER ON TABLE public.fee_category TO service_role;
GRANT TRUNCATE ON TABLE public.fee_category TO service_role;
GRANT UPDATE ON TABLE public.fee_category TO service_role;
GRANT SELECT ON TABLE public.fee_category_fee_category_id_seq TO postgres;
GRANT UPDATE ON TABLE public.fee_category_fee_category_id_seq TO postgres;
GRANT USAGE ON TABLE public.fee_category_fee_category_id_seq TO postgres;
GRANT SELECT ON TABLE public.fee_category_fee_category_id_seq TO service_role;
GRANT UPDATE ON TABLE public.fee_category_fee_category_id_seq TO service_role;
GRANT USAGE ON TABLE public.fee_category_fee_category_id_seq TO service_role;
GRANT DELETE ON TABLE public.fee_charge_source TO postgres;
GRANT INSERT ON TABLE public.fee_charge_source TO postgres;
GRANT MAINTAIN ON TABLE public.fee_charge_source TO postgres;
GRANT REFERENCES ON TABLE public.fee_charge_source TO postgres;
GRANT SELECT ON TABLE public.fee_charge_source TO postgres;
GRANT TRIGGER ON TABLE public.fee_charge_source TO postgres;
GRANT TRUNCATE ON TABLE public.fee_charge_source TO postgres;
GRANT UPDATE ON TABLE public.fee_charge_source TO postgres;
GRANT DELETE ON TABLE public.fee_charge_source TO service_role;
GRANT INSERT ON TABLE public.fee_charge_source TO service_role;
GRANT MAINTAIN ON TABLE public.fee_charge_source TO service_role;
GRANT REFERENCES ON TABLE public.fee_charge_source TO service_role;
GRANT SELECT ON TABLE public.fee_charge_source TO service_role;
GRANT TRIGGER ON TABLE public.fee_charge_source TO service_role;
GRANT TRUNCATE ON TABLE public.fee_charge_source TO service_role;
GRANT UPDATE ON TABLE public.fee_charge_source TO service_role;
GRANT SELECT ON TABLE public.fee_charge_source_charge_source_id_seq TO postgres;
GRANT UPDATE ON TABLE public.fee_charge_source_charge_source_id_seq TO postgres;
GRANT USAGE ON TABLE public.fee_charge_source_charge_source_id_seq TO postgres;
GRANT SELECT ON TABLE public.fee_charge_source_charge_source_id_seq TO service_role;
GRANT UPDATE ON TABLE public.fee_charge_source_charge_source_id_seq TO service_role;
GRANT USAGE ON TABLE public.fee_charge_source_charge_source_id_seq TO service_role;
GRANT DELETE ON TABLE public.fee_receipt TO postgres;
GRANT INSERT ON TABLE public.fee_receipt TO postgres;
GRANT MAINTAIN ON TABLE public.fee_receipt TO postgres;
GRANT REFERENCES ON TABLE public.fee_receipt TO postgres;
GRANT SELECT ON TABLE public.fee_receipt TO postgres;
GRANT TRIGGER ON TABLE public.fee_receipt TO postgres;
GRANT TRUNCATE ON TABLE public.fee_receipt TO postgres;
GRANT UPDATE ON TABLE public.fee_receipt TO postgres;
GRANT DELETE ON TABLE public.fee_receipt TO service_role;
GRANT INSERT ON TABLE public.fee_receipt TO service_role;
GRANT MAINTAIN ON TABLE public.fee_receipt TO service_role;
GRANT REFERENCES ON TABLE public.fee_receipt TO service_role;
GRANT SELECT ON TABLE public.fee_receipt TO service_role;
GRANT TRIGGER ON TABLE public.fee_receipt TO service_role;
GRANT TRUNCATE ON TABLE public.fee_receipt TO service_role;
GRANT UPDATE ON TABLE public.fee_receipt TO service_role;
GRANT SELECT ON TABLE public.fee_receipt_fee_receipt_id_seq TO postgres;
GRANT UPDATE ON TABLE public.fee_receipt_fee_receipt_id_seq TO postgres;
GRANT USAGE ON TABLE public.fee_receipt_fee_receipt_id_seq TO postgres;
GRANT SELECT ON TABLE public.fee_receipt_fee_receipt_id_seq TO service_role;
GRANT UPDATE ON TABLE public.fee_receipt_fee_receipt_id_seq TO service_role;
GRANT USAGE ON TABLE public.fee_receipt_fee_receipt_id_seq TO service_role;
GRANT DELETE ON TABLE public.fee_refund TO postgres;
GRANT INSERT ON TABLE public.fee_refund TO postgres;
GRANT MAINTAIN ON TABLE public.fee_refund TO postgres;
GRANT REFERENCES ON TABLE public.fee_refund TO postgres;
GRANT SELECT ON TABLE public.fee_refund TO postgres;
GRANT TRIGGER ON TABLE public.fee_refund TO postgres;
GRANT TRUNCATE ON TABLE public.fee_refund TO postgres;
GRANT UPDATE ON TABLE public.fee_refund TO postgres;
GRANT DELETE ON TABLE public.fee_refund TO service_role;
GRANT INSERT ON TABLE public.fee_refund TO service_role;
GRANT MAINTAIN ON TABLE public.fee_refund TO service_role;
GRANT REFERENCES ON TABLE public.fee_refund TO service_role;
GRANT SELECT ON TABLE public.fee_refund TO service_role;
GRANT TRIGGER ON TABLE public.fee_refund TO service_role;
GRANT TRUNCATE ON TABLE public.fee_refund TO service_role;
GRANT UPDATE ON TABLE public.fee_refund TO service_role;
GRANT SELECT ON TABLE public.fee_refund_fee_refund_id_seq TO postgres;
GRANT UPDATE ON TABLE public.fee_refund_fee_refund_id_seq TO postgres;
GRANT USAGE ON TABLE public.fee_refund_fee_refund_id_seq TO postgres;
GRANT SELECT ON TABLE public.fee_refund_fee_refund_id_seq TO service_role;
GRANT UPDATE ON TABLE public.fee_refund_fee_refund_id_seq TO service_role;
GRANT USAGE ON TABLE public.fee_refund_fee_refund_id_seq TO service_role;
GRANT DELETE ON TABLE public.fee_structure TO postgres;
GRANT INSERT ON TABLE public.fee_structure TO postgres;
GRANT MAINTAIN ON TABLE public.fee_structure TO postgres;
GRANT REFERENCES ON TABLE public.fee_structure TO postgres;
GRANT SELECT ON TABLE public.fee_structure TO postgres;
GRANT TRIGGER ON TABLE public.fee_structure TO postgres;
GRANT TRUNCATE ON TABLE public.fee_structure TO postgres;
GRANT UPDATE ON TABLE public.fee_structure TO postgres;
GRANT DELETE ON TABLE public.fee_structure TO service_role;
GRANT INSERT ON TABLE public.fee_structure TO service_role;
GRANT MAINTAIN ON TABLE public.fee_structure TO service_role;
GRANT REFERENCES ON TABLE public.fee_structure TO service_role;
GRANT SELECT ON TABLE public.fee_structure TO service_role;
GRANT TRIGGER ON TABLE public.fee_structure TO service_role;
GRANT TRUNCATE ON TABLE public.fee_structure TO service_role;
GRANT UPDATE ON TABLE public.fee_structure TO service_role;
GRANT SELECT ON TABLE public.fee_structure_fee_structure_id_seq TO postgres;
GRANT UPDATE ON TABLE public.fee_structure_fee_structure_id_seq TO postgres;
GRANT USAGE ON TABLE public.fee_structure_fee_structure_id_seq TO postgres;
GRANT SELECT ON TABLE public.fee_structure_fee_structure_id_seq TO service_role;
GRANT UPDATE ON TABLE public.fee_structure_fee_structure_id_seq TO service_role;
GRANT USAGE ON TABLE public.fee_structure_fee_structure_id_seq TO service_role;
GRANT DELETE ON TABLE public.fee_structure_item TO postgres;
GRANT INSERT ON TABLE public.fee_structure_item TO postgres;
GRANT MAINTAIN ON TABLE public.fee_structure_item TO postgres;
GRANT REFERENCES ON TABLE public.fee_structure_item TO postgres;
GRANT SELECT ON TABLE public.fee_structure_item TO postgres;
GRANT TRIGGER ON TABLE public.fee_structure_item TO postgres;
GRANT TRUNCATE ON TABLE public.fee_structure_item TO postgres;
GRANT UPDATE ON TABLE public.fee_structure_item TO postgres;
GRANT DELETE ON TABLE public.fee_structure_item TO service_role;
GRANT INSERT ON TABLE public.fee_structure_item TO service_role;
GRANT MAINTAIN ON TABLE public.fee_structure_item TO service_role;
GRANT REFERENCES ON TABLE public.fee_structure_item TO service_role;
GRANT SELECT ON TABLE public.fee_structure_item TO service_role;
GRANT TRIGGER ON TABLE public.fee_structure_item TO service_role;
GRANT TRUNCATE ON TABLE public.fee_structure_item TO service_role;
GRANT UPDATE ON TABLE public.fee_structure_item TO service_role;
GRANT SELECT ON TABLE public.fee_structure_item_fee_structure_item_id_seq TO postgres;
GRANT UPDATE ON TABLE public.fee_structure_item_fee_structure_item_id_seq TO postgres;
GRANT USAGE ON TABLE public.fee_structure_item_fee_structure_item_id_seq TO postgres;
GRANT SELECT ON TABLE public.fee_structure_item_fee_structure_item_id_seq TO service_role;
GRANT UPDATE ON TABLE public.fee_structure_item_fee_structure_item_id_seq TO service_role;
GRANT USAGE ON TABLE public.fee_structure_item_fee_structure_item_id_seq TO service_role;
GRANT DELETE ON TABLE public.fee_type TO postgres;
GRANT INSERT ON TABLE public.fee_type TO postgres;
GRANT MAINTAIN ON TABLE public.fee_type TO postgres;
GRANT REFERENCES ON TABLE public.fee_type TO postgres;
GRANT SELECT ON TABLE public.fee_type TO postgres;
GRANT TRIGGER ON TABLE public.fee_type TO postgres;
GRANT TRUNCATE ON TABLE public.fee_type TO postgres;
GRANT UPDATE ON TABLE public.fee_type TO postgres;
GRANT DELETE ON TABLE public.fee_type TO service_role;
GRANT INSERT ON TABLE public.fee_type TO service_role;
GRANT MAINTAIN ON TABLE public.fee_type TO service_role;
GRANT REFERENCES ON TABLE public.fee_type TO service_role;
GRANT SELECT ON TABLE public.fee_type TO service_role;
GRANT TRIGGER ON TABLE public.fee_type TO service_role;
GRANT TRUNCATE ON TABLE public.fee_type TO service_role;
GRANT UPDATE ON TABLE public.fee_type TO service_role;
GRANT SELECT ON TABLE public.fee_type_fee_type_id_seq TO postgres;
GRANT UPDATE ON TABLE public.fee_type_fee_type_id_seq TO postgres;
GRANT USAGE ON TABLE public.fee_type_fee_type_id_seq TO postgres;
GRANT SELECT ON TABLE public.fee_type_fee_type_id_seq TO service_role;
GRANT UPDATE ON TABLE public.fee_type_fee_type_id_seq TO service_role;
GRANT USAGE ON TABLE public.fee_type_fee_type_id_seq TO service_role;
GRANT DELETE ON TABLE public.feedback_choice TO authenticated;
GRANT INSERT ON TABLE public.feedback_choice TO authenticated;
GRANT UPDATE ON TABLE public.feedback_choice TO authenticated;
GRANT DELETE ON TABLE public.feedback_choice TO postgres;
GRANT INSERT ON TABLE public.feedback_choice TO postgres;
GRANT MAINTAIN ON TABLE public.feedback_choice TO postgres;
GRANT REFERENCES ON TABLE public.feedback_choice TO postgres;
GRANT SELECT ON TABLE public.feedback_choice TO postgres;
GRANT TRIGGER ON TABLE public.feedback_choice TO postgres;
GRANT TRUNCATE ON TABLE public.feedback_choice TO postgres;
GRANT UPDATE ON TABLE public.feedback_choice TO postgres;
GRANT DELETE ON TABLE public.feedback_choice TO service_role;
GRANT INSERT ON TABLE public.feedback_choice TO service_role;
GRANT MAINTAIN ON TABLE public.feedback_choice TO service_role;
GRANT REFERENCES ON TABLE public.feedback_choice TO service_role;
GRANT SELECT ON TABLE public.feedback_choice TO service_role;
GRANT TRIGGER ON TABLE public.feedback_choice TO service_role;
GRANT TRUNCATE ON TABLE public.feedback_choice TO service_role;
GRANT UPDATE ON TABLE public.feedback_choice TO service_role;
GRANT SELECT ON TABLE public.feedback_choice_feedback_choice_id_seq TO postgres;
GRANT UPDATE ON TABLE public.feedback_choice_feedback_choice_id_seq TO postgres;
GRANT USAGE ON TABLE public.feedback_choice_feedback_choice_id_seq TO postgres;
GRANT SELECT ON TABLE public.feedback_choice_feedback_choice_id_seq TO service_role;
GRANT UPDATE ON TABLE public.feedback_choice_feedback_choice_id_seq TO service_role;
GRANT USAGE ON TABLE public.feedback_choice_feedback_choice_id_seq TO service_role;
GRANT DELETE ON TABLE public.feedback_cycle TO authenticated;
GRANT INSERT ON TABLE public.feedback_cycle TO authenticated;
GRANT UPDATE ON TABLE public.feedback_cycle TO authenticated;
GRANT DELETE ON TABLE public.feedback_cycle TO postgres;
GRANT INSERT ON TABLE public.feedback_cycle TO postgres;
GRANT MAINTAIN ON TABLE public.feedback_cycle TO postgres;
GRANT REFERENCES ON TABLE public.feedback_cycle TO postgres;
GRANT SELECT ON TABLE public.feedback_cycle TO postgres;
GRANT TRIGGER ON TABLE public.feedback_cycle TO postgres;
GRANT TRUNCATE ON TABLE public.feedback_cycle TO postgres;
GRANT UPDATE ON TABLE public.feedback_cycle TO postgres;
GRANT DELETE ON TABLE public.feedback_cycle TO service_role;
GRANT INSERT ON TABLE public.feedback_cycle TO service_role;
GRANT MAINTAIN ON TABLE public.feedback_cycle TO service_role;
GRANT REFERENCES ON TABLE public.feedback_cycle TO service_role;
GRANT SELECT ON TABLE public.feedback_cycle TO service_role;
GRANT TRIGGER ON TABLE public.feedback_cycle TO service_role;
GRANT TRUNCATE ON TABLE public.feedback_cycle TO service_role;
GRANT UPDATE ON TABLE public.feedback_cycle TO service_role;
GRANT SELECT ON TABLE public.feedback_cycle_feedback_cycle_id_seq TO postgres;
GRANT UPDATE ON TABLE public.feedback_cycle_feedback_cycle_id_seq TO postgres;
GRANT USAGE ON TABLE public.feedback_cycle_feedback_cycle_id_seq TO postgres;
GRANT SELECT ON TABLE public.feedback_cycle_feedback_cycle_id_seq TO service_role;
GRANT UPDATE ON TABLE public.feedback_cycle_feedback_cycle_id_seq TO service_role;
GRANT USAGE ON TABLE public.feedback_cycle_feedback_cycle_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.feedback_cycle_offerings(p_cycle_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.feedback_cycle_offerings(p_cycle_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.feedback_cycle_offerings(p_cycle_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.feedback_form(p_cycle_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.feedback_form(p_cycle_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.feedback_form(p_cycle_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.feedback_my_tasks() TO authenticated;
GRANT EXECUTE ON FUNCTION public.feedback_my_tasks() TO postgres;
GRANT EXECUTE ON FUNCTION public.feedback_my_tasks() TO service_role;
GRANT DELETE ON TABLE public.feedback_question TO authenticated;
GRANT INSERT ON TABLE public.feedback_question TO authenticated;
GRANT UPDATE ON TABLE public.feedback_question TO authenticated;
GRANT DELETE ON TABLE public.feedback_question TO postgres;
GRANT INSERT ON TABLE public.feedback_question TO postgres;
GRANT MAINTAIN ON TABLE public.feedback_question TO postgres;
GRANT REFERENCES ON TABLE public.feedback_question TO postgres;
GRANT SELECT ON TABLE public.feedback_question TO postgres;
GRANT TRIGGER ON TABLE public.feedback_question TO postgres;
GRANT TRUNCATE ON TABLE public.feedback_question TO postgres;
GRANT UPDATE ON TABLE public.feedback_question TO postgres;
GRANT DELETE ON TABLE public.feedback_question TO service_role;
GRANT INSERT ON TABLE public.feedback_question TO service_role;
GRANT MAINTAIN ON TABLE public.feedback_question TO service_role;
GRANT REFERENCES ON TABLE public.feedback_question TO service_role;
GRANT SELECT ON TABLE public.feedback_question TO service_role;
GRANT TRIGGER ON TABLE public.feedback_question TO service_role;
GRANT TRUNCATE ON TABLE public.feedback_question TO service_role;
GRANT UPDATE ON TABLE public.feedback_question TO service_role;
GRANT DELETE ON TABLE public.feedback_question_category TO authenticated;
GRANT INSERT ON TABLE public.feedback_question_category TO authenticated;
GRANT UPDATE ON TABLE public.feedback_question_category TO authenticated;
GRANT DELETE ON TABLE public.feedback_question_category TO postgres;
GRANT INSERT ON TABLE public.feedback_question_category TO postgres;
GRANT MAINTAIN ON TABLE public.feedback_question_category TO postgres;
GRANT REFERENCES ON TABLE public.feedback_question_category TO postgres;
GRANT SELECT ON TABLE public.feedback_question_category TO postgres;
GRANT TRIGGER ON TABLE public.feedback_question_category TO postgres;
GRANT TRUNCATE ON TABLE public.feedback_question_category TO postgres;
GRANT UPDATE ON TABLE public.feedback_question_category TO postgres;
GRANT DELETE ON TABLE public.feedback_question_category TO service_role;
GRANT INSERT ON TABLE public.feedback_question_category TO service_role;
GRANT MAINTAIN ON TABLE public.feedback_question_category TO service_role;
GRANT REFERENCES ON TABLE public.feedback_question_category TO service_role;
GRANT SELECT ON TABLE public.feedback_question_category TO service_role;
GRANT TRIGGER ON TABLE public.feedback_question_category TO service_role;
GRANT TRUNCATE ON TABLE public.feedback_question_category TO service_role;
GRANT UPDATE ON TABLE public.feedback_question_category TO service_role;
GRANT SELECT ON TABLE public.feedback_question_category_feedback_category_id_seq TO postgres;
GRANT UPDATE ON TABLE public.feedback_question_category_feedback_category_id_seq TO postgres;
GRANT USAGE ON TABLE public.feedback_question_category_feedback_category_id_seq TO postgres;
GRANT SELECT ON TABLE public.feedback_question_category_feedback_category_id_seq TO service_role;
GRANT UPDATE ON TABLE public.feedback_question_category_feedback_category_id_seq TO service_role;
GRANT USAGE ON TABLE public.feedback_question_category_feedback_category_id_seq TO service_role;
GRANT SELECT ON TABLE public.feedback_question_feedback_question_id_seq TO postgres;
GRANT UPDATE ON TABLE public.feedback_question_feedback_question_id_seq TO postgres;
GRANT USAGE ON TABLE public.feedback_question_feedback_question_id_seq TO postgres;
GRANT SELECT ON TABLE public.feedback_question_feedback_question_id_seq TO service_role;
GRANT UPDATE ON TABLE public.feedback_question_feedback_question_id_seq TO service_role;
GRANT USAGE ON TABLE public.feedback_question_feedback_question_id_seq TO service_role;
GRANT DELETE ON TABLE public.feedback_questionnaire TO authenticated;
GRANT INSERT ON TABLE public.feedback_questionnaire TO authenticated;
GRANT UPDATE ON TABLE public.feedback_questionnaire TO authenticated;
GRANT DELETE ON TABLE public.feedback_questionnaire TO postgres;
GRANT INSERT ON TABLE public.feedback_questionnaire TO postgres;
GRANT MAINTAIN ON TABLE public.feedback_questionnaire TO postgres;
GRANT REFERENCES ON TABLE public.feedback_questionnaire TO postgres;
GRANT SELECT ON TABLE public.feedback_questionnaire TO postgres;
GRANT TRIGGER ON TABLE public.feedback_questionnaire TO postgres;
GRANT TRUNCATE ON TABLE public.feedback_questionnaire TO postgres;
GRANT UPDATE ON TABLE public.feedback_questionnaire TO postgres;
GRANT DELETE ON TABLE public.feedback_questionnaire TO service_role;
GRANT INSERT ON TABLE public.feedback_questionnaire TO service_role;
GRANT MAINTAIN ON TABLE public.feedback_questionnaire TO service_role;
GRANT REFERENCES ON TABLE public.feedback_questionnaire TO service_role;
GRANT SELECT ON TABLE public.feedback_questionnaire TO service_role;
GRANT TRIGGER ON TABLE public.feedback_questionnaire TO service_role;
GRANT TRUNCATE ON TABLE public.feedback_questionnaire TO service_role;
GRANT UPDATE ON TABLE public.feedback_questionnaire TO service_role;
GRANT DELETE ON TABLE public.feedback_questionnaire_item TO authenticated;
GRANT INSERT ON TABLE public.feedback_questionnaire_item TO authenticated;
GRANT UPDATE ON TABLE public.feedback_questionnaire_item TO authenticated;
GRANT DELETE ON TABLE public.feedback_questionnaire_item TO postgres;
GRANT INSERT ON TABLE public.feedback_questionnaire_item TO postgres;
GRANT MAINTAIN ON TABLE public.feedback_questionnaire_item TO postgres;
GRANT REFERENCES ON TABLE public.feedback_questionnaire_item TO postgres;
GRANT SELECT ON TABLE public.feedback_questionnaire_item TO postgres;
GRANT TRIGGER ON TABLE public.feedback_questionnaire_item TO postgres;
GRANT TRUNCATE ON TABLE public.feedback_questionnaire_item TO postgres;
GRANT UPDATE ON TABLE public.feedback_questionnaire_item TO postgres;
GRANT DELETE ON TABLE public.feedback_questionnaire_item TO service_role;
GRANT INSERT ON TABLE public.feedback_questionnaire_item TO service_role;
GRANT MAINTAIN ON TABLE public.feedback_questionnaire_item TO service_role;
GRANT REFERENCES ON TABLE public.feedback_questionnaire_item TO service_role;
GRANT SELECT ON TABLE public.feedback_questionnaire_item TO service_role;
GRANT TRIGGER ON TABLE public.feedback_questionnaire_item TO service_role;
GRANT TRUNCATE ON TABLE public.feedback_questionnaire_item TO service_role;
GRANT UPDATE ON TABLE public.feedback_questionnaire_item TO service_role;
GRANT SELECT ON TABLE public.feedback_questionnaire_item_questionnaire_item_id_seq TO postgres;
GRANT UPDATE ON TABLE public.feedback_questionnaire_item_questionnaire_item_id_seq TO postgres;
GRANT USAGE ON TABLE public.feedback_questionnaire_item_questionnaire_item_id_seq TO postgres;
GRANT SELECT ON TABLE public.feedback_questionnaire_item_questionnaire_item_id_seq TO service_role;
GRANT UPDATE ON TABLE public.feedback_questionnaire_item_questionnaire_item_id_seq TO service_role;
GRANT USAGE ON TABLE public.feedback_questionnaire_item_questionnaire_item_id_seq TO service_role;
GRANT SELECT ON TABLE public.feedback_questionnaire_questionnaire_id_seq TO postgres;
GRANT UPDATE ON TABLE public.feedback_questionnaire_questionnaire_id_seq TO postgres;
GRANT USAGE ON TABLE public.feedback_questionnaire_questionnaire_id_seq TO postgres;
GRANT SELECT ON TABLE public.feedback_questionnaire_questionnaire_id_seq TO service_role;
GRANT UPDATE ON TABLE public.feedback_questionnaire_questionnaire_id_seq TO service_role;
GRANT USAGE ON TABLE public.feedback_questionnaire_questionnaire_id_seq TO service_role;
GRANT DELETE ON TABLE public.feedback_response TO postgres;
GRANT INSERT ON TABLE public.feedback_response TO postgres;
GRANT MAINTAIN ON TABLE public.feedback_response TO postgres;
GRANT REFERENCES ON TABLE public.feedback_response TO postgres;
GRANT SELECT ON TABLE public.feedback_response TO postgres;
GRANT TRIGGER ON TABLE public.feedback_response TO postgres;
GRANT TRUNCATE ON TABLE public.feedback_response TO postgres;
GRANT UPDATE ON TABLE public.feedback_response TO postgres;
GRANT DELETE ON TABLE public.feedback_response TO service_role;
GRANT INSERT ON TABLE public.feedback_response TO service_role;
GRANT MAINTAIN ON TABLE public.feedback_response TO service_role;
GRANT REFERENCES ON TABLE public.feedback_response TO service_role;
GRANT SELECT ON TABLE public.feedback_response TO service_role;
GRANT TRIGGER ON TABLE public.feedback_response TO service_role;
GRANT TRUNCATE ON TABLE public.feedback_response TO service_role;
GRANT UPDATE ON TABLE public.feedback_response TO service_role;
GRANT SELECT ON TABLE public.feedback_response_feedback_response_id_seq TO postgres;
GRANT UPDATE ON TABLE public.feedback_response_feedback_response_id_seq TO postgres;
GRANT USAGE ON TABLE public.feedback_response_feedback_response_id_seq TO postgres;
GRANT SELECT ON TABLE public.feedback_response_feedback_response_id_seq TO service_role;
GRANT UPDATE ON TABLE public.feedback_response_feedback_response_id_seq TO service_role;
GRANT USAGE ON TABLE public.feedback_response_feedback_response_id_seq TO service_role;
GRANT DELETE ON TABLE public.feedback_response_item TO postgres;
GRANT INSERT ON TABLE public.feedback_response_item TO postgres;
GRANT MAINTAIN ON TABLE public.feedback_response_item TO postgres;
GRANT REFERENCES ON TABLE public.feedback_response_item TO postgres;
GRANT SELECT ON TABLE public.feedback_response_item TO postgres;
GRANT TRIGGER ON TABLE public.feedback_response_item TO postgres;
GRANT TRUNCATE ON TABLE public.feedback_response_item TO postgres;
GRANT UPDATE ON TABLE public.feedback_response_item TO postgres;
GRANT DELETE ON TABLE public.feedback_response_item TO service_role;
GRANT INSERT ON TABLE public.feedback_response_item TO service_role;
GRANT MAINTAIN ON TABLE public.feedback_response_item TO service_role;
GRANT REFERENCES ON TABLE public.feedback_response_item TO service_role;
GRANT SELECT ON TABLE public.feedback_response_item TO service_role;
GRANT TRIGGER ON TABLE public.feedback_response_item TO service_role;
GRANT TRUNCATE ON TABLE public.feedback_response_item TO service_role;
GRANT UPDATE ON TABLE public.feedback_response_item TO service_role;
GRANT SELECT ON TABLE public.feedback_response_item_feedback_response_item_id_seq TO postgres;
GRANT UPDATE ON TABLE public.feedback_response_item_feedback_response_item_id_seq TO postgres;
GRANT USAGE ON TABLE public.feedback_response_item_feedback_response_item_id_seq TO postgres;
GRANT SELECT ON TABLE public.feedback_response_item_feedback_response_item_id_seq TO service_role;
GRANT UPDATE ON TABLE public.feedback_response_item_feedback_response_item_id_seq TO service_role;
GRANT USAGE ON TABLE public.feedback_response_item_feedback_response_item_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.feedback_results(p_cycle_id bigint, p_course_offering_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.feedback_results(p_cycle_id bigint, p_course_offering_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.feedback_results(p_cycle_id bigint, p_course_offering_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.feedback_submit(p_cycle_id bigint, p_course_offering_id bigint, p_faculty_assignment_id bigint, p_answers jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.feedback_submit(p_cycle_id bigint, p_course_offering_id bigint, p_faculty_assignment_id bigint, p_answers jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.feedback_submit(p_cycle_id bigint, p_course_offering_id bigint, p_faculty_assignment_id bigint, p_answers jsonb) TO service_role;
GRANT DELETE ON TABLE public.file_object TO postgres;
GRANT INSERT ON TABLE public.file_object TO postgres;
GRANT MAINTAIN ON TABLE public.file_object TO postgres;
GRANT REFERENCES ON TABLE public.file_object TO postgres;
GRANT SELECT ON TABLE public.file_object TO postgres;
GRANT TRIGGER ON TABLE public.file_object TO postgres;
GRANT TRUNCATE ON TABLE public.file_object TO postgres;
GRANT UPDATE ON TABLE public.file_object TO postgres;
GRANT DELETE ON TABLE public.file_object TO service_role;
GRANT INSERT ON TABLE public.file_object TO service_role;
GRANT MAINTAIN ON TABLE public.file_object TO service_role;
GRANT REFERENCES ON TABLE public.file_object TO service_role;
GRANT SELECT ON TABLE public.file_object TO service_role;
GRANT TRIGGER ON TABLE public.file_object TO service_role;
GRANT TRUNCATE ON TABLE public.file_object TO service_role;
GRANT UPDATE ON TABLE public.file_object TO service_role;
GRANT SELECT ON TABLE public.file_object_file_object_id_seq TO postgres;
GRANT UPDATE ON TABLE public.file_object_file_object_id_seq TO postgres;
GRANT USAGE ON TABLE public.file_object_file_object_id_seq TO postgres;
GRANT SELECT ON TABLE public.file_object_file_object_id_seq TO service_role;
GRANT UPDATE ON TABLE public.file_object_file_object_id_seq TO service_role;
GRANT USAGE ON TABLE public.file_object_file_object_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_academic_years() TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_academic_years() TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_academic_years() TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_account_extras(p_student_account_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_account_extras(p_student_account_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_account_extras(p_student_account_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_account_info(p_student_account_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_account_info(p_student_account_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_account_info(p_student_account_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_accounts(p_search text, p_status text, p_limit integer, p_offset integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_accounts(p_search text, p_status text, p_limit integer, p_offset integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_accounts(p_search text, p_status text, p_limit integer, p_offset integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_adjustment_create(p_number text, p_student_account_id bigint, p_assessment_item_id bigint, p_type text, p_amount numeric, p_reason text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_adjustment_create(p_number text, p_student_account_id bigint, p_assessment_item_id bigint, p_type text, p_amount numeric, p_reason text) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_adjustment_create(p_number text, p_student_account_id bigint, p_assessment_item_id bigint, p_type text, p_amount numeric, p_reason text) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_adjustment_decide(p_adjustment_id bigint, p_approve boolean, p_remarks text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_adjustment_decide(p_adjustment_id bigint, p_approve boolean, p_remarks text) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_adjustment_decide(p_adjustment_id bigint, p_approve boolean, p_remarks text) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_allocate_payment(p_payment_transaction_id bigint, p_assessment_item_id bigint, p_amount numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_allocate_payment(p_payment_transaction_id bigint, p_assessment_item_id bigint, p_amount numeric) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_allocate_payment(p_payment_transaction_id bigint, p_assessment_item_id bigint, p_amount numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_benefit_apply(p_kind text, p_benefit_id bigint, p_assessment_item_id bigint, p_amount numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_benefit_apply(p_kind text, p_benefit_id bigint, p_assessment_item_id bigint, p_amount numeric) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_benefit_apply(p_kind text, p_benefit_id bigint, p_assessment_item_id bigint, p_amount numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_benefit_create(p_kind text, p_student_id bigint, p_academic_year_id integer, p_type_id bigint, p_amount numeric, p_percentage numeric, p_reference text, p_authority text, p_remarks text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_benefit_create(p_kind text, p_student_id bigint, p_academic_year_id integer, p_type_id bigint, p_amount numeric, p_percentage numeric, p_reference text, p_authority text, p_remarks text) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_benefit_create(p_kind text, p_student_id bigint, p_academic_year_id integer, p_type_id bigint, p_amount numeric, p_percentage numeric, p_reference text, p_authority text, p_remarks text) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_benefit_decide(p_kind text, p_id bigint, p_approve boolean, p_amount numeric, p_percentage numeric, p_remarks text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_benefit_decide(p_kind text, p_id bigint, p_approve boolean, p_amount numeric, p_percentage numeric, p_remarks text) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_benefit_decide(p_kind text, p_id bigint, p_approve boolean, p_amount numeric, p_percentage numeric, p_remarks text) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_cancel_receipt(p_receipt_id bigint, p_reason text, p_replace boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_cancel_receipt(p_receipt_id bigint, p_reason text, p_replace boolean) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_cancel_receipt(p_receipt_id bigint, p_reason text, p_replace boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_create_fee_assessment(p_assessment_number text, p_student_account_id bigint, p_academic_year_id integer, p_assessment_type text, p_assessment_date date, p_due_date date, p_items jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_create_fee_assessment(p_assessment_number text, p_student_account_id bigint, p_academic_year_id integer, p_assessment_type text, p_assessment_date date, p_due_date date, p_items jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_create_fee_assessment(p_assessment_number text, p_student_account_id bigint, p_academic_year_id integer, p_assessment_type text, p_assessment_date date, p_due_date date, p_items jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_decide_refund(p_refund_request_id bigint, p_approve boolean, p_approved_amount numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_decide_refund(p_refund_request_id bigint, p_approve boolean, p_approved_amount numeric) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_decide_refund(p_refund_request_id bigint, p_approve boolean, p_approved_amount numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_hold_place(p_student_account_id bigint, p_hold_type text, p_reason text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_hold_place(p_student_account_id bigint, p_hold_type text, p_reason text) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_hold_place(p_student_account_id bigint, p_hold_type text, p_reason text) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_hold_release(p_hold_id bigint, p_reason text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_hold_release(p_hold_id bigint, p_reason text) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_hold_release(p_hold_id bigint, p_reason text) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_holds(p_student_account_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_holds(p_student_account_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_holds(p_student_account_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_instalment_apply(p_assessment_id bigint, p_plan_id integer, p_first_due date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_instalment_apply(p_assessment_id bigint, p_plan_id integer, p_first_due date) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_instalment_apply(p_assessment_id bigint, p_plan_id integer, p_first_due date) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_instalment_cancel(p_assessment_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_instalment_cancel(p_assessment_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_instalment_cancel(p_assessment_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_instalment_refresh(p_assessment_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_instalment_refresh(p_assessment_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_instalment_refresh(p_assessment_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_issue_receipt(p_payment_transaction_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_issue_receipt(p_payment_transaction_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_issue_receipt(p_payment_transaction_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_late_fee_suggest(p_assessment_id bigint, p_rule_id bigint, p_as_of date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_late_fee_suggest(p_assessment_id bigint, p_rule_id bigint, p_as_of date) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_late_fee_suggest(p_assessment_id bigint, p_rule_id bigint, p_as_of date) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_open_account(p_student_number text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_open_account(p_student_number text) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_open_account(p_student_number text) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_payment_receipts(p_student_account_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_payment_receipts(p_student_account_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_payment_receipts(p_student_account_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_penalty_assess(p_student_account_id bigint, p_fee_type_id bigint, p_amount numeric, p_reason text, p_academic_year_id integer, p_due_date date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_penalty_assess(p_student_account_id bigint, p_fee_type_id bigint, p_amount numeric, p_reason text, p_academic_year_id integer, p_due_date date) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_penalty_assess(p_student_account_id bigint, p_fee_type_id bigint, p_amount numeric, p_reason text, p_academic_year_id integer, p_due_date date) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_penalty_waive(p_penalty_id bigint, p_amount numeric, p_reason text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_penalty_waive(p_penalty_id bigint, p_amount numeric, p_reason text) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_penalty_waive(p_penalty_id bigint, p_amount numeric, p_reason text) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_process_refund(p_refund_transaction_number text, p_refund_request_id bigint, p_refund_mode_id integer, p_amount numeric, p_bank_reference text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_process_refund(p_refund_transaction_number text, p_refund_request_id bigint, p_refund_mode_id integer, p_amount numeric, p_bank_reference text) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_process_refund(p_refund_transaction_number text, p_refund_request_id bigint, p_refund_mode_id integer, p_amount numeric, p_bank_reference text) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_receipt_get(p_receipt_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_receipt_get(p_receipt_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_receipt_get(p_receipt_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_record_payment(p_transaction_number text, p_student_account_id bigint, p_payment_mode_id integer, p_amount numeric, p_bank_reference text, p_payer_name text, p_remarks text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_record_payment(p_transaction_number text, p_student_account_id bigint, p_payment_mode_id integer, p_amount numeric, p_bank_reference text, p_payer_name text, p_remarks text) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_record_payment(p_transaction_number text, p_student_account_id bigint, p_payment_mode_id integer, p_amount numeric, p_bank_reference text, p_payer_name text, p_remarks text) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_request_refund(p_request_number text, p_student_account_id bigint, p_payment_transaction_id bigint, p_amount numeric, p_reason text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_request_refund(p_request_number text, p_student_account_id bigint, p_payment_transaction_id bigint, p_amount numeric, p_reason text) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_request_refund(p_request_number text, p_student_account_id bigint, p_payment_transaction_id bigint, p_amount numeric, p_reason text) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_structure_decide(p_id bigint, p_approve boolean, p_remarks text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_structure_decide(p_id bigint, p_approve boolean, p_remarks text) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_structure_decide(p_id bigint, p_approve boolean, p_remarks text) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_structure_delete(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_structure_delete(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_structure_delete(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_structure_get(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_structure_get(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_structure_get(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_structure_item_delete(p_structure_id bigint, p_item_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_structure_item_delete(p_structure_id bigint, p_item_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_structure_item_delete(p_structure_id bigint, p_item_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_structure_item_save(p_structure_id bigint, p_item_id bigint, p jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_structure_item_save(p_structure_id bigint, p_item_id bigint, p jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_structure_item_save(p_structure_id bigint, p_item_id bigint, p jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_structure_list(p_search text, p_status text, p_limit integer, p_offset integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_structure_list(p_search text, p_status text, p_limit integer, p_offset integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_structure_list(p_search text, p_status text, p_limit integer, p_offset integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_structure_new_version(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_structure_new_version(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_structure_new_version(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_structure_save(p_id bigint, p jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_structure_save(p_id bigint, p jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_structure_save(p_id bigint, p jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.fin_structure_submit(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fin_structure_submit(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.fin_structure_submit(p_id bigint) TO service_role;
GRANT DELETE ON TABLE public.financial_ledger_account TO postgres;
GRANT INSERT ON TABLE public.financial_ledger_account TO postgres;
GRANT MAINTAIN ON TABLE public.financial_ledger_account TO postgres;
GRANT REFERENCES ON TABLE public.financial_ledger_account TO postgres;
GRANT SELECT ON TABLE public.financial_ledger_account TO postgres;
GRANT TRIGGER ON TABLE public.financial_ledger_account TO postgres;
GRANT TRUNCATE ON TABLE public.financial_ledger_account TO postgres;
GRANT UPDATE ON TABLE public.financial_ledger_account TO postgres;
GRANT DELETE ON TABLE public.financial_ledger_account TO service_role;
GRANT INSERT ON TABLE public.financial_ledger_account TO service_role;
GRANT MAINTAIN ON TABLE public.financial_ledger_account TO service_role;
GRANT REFERENCES ON TABLE public.financial_ledger_account TO service_role;
GRANT SELECT ON TABLE public.financial_ledger_account TO service_role;
GRANT TRIGGER ON TABLE public.financial_ledger_account TO service_role;
GRANT TRUNCATE ON TABLE public.financial_ledger_account TO service_role;
GRANT UPDATE ON TABLE public.financial_ledger_account TO service_role;
GRANT SELECT ON TABLE public.financial_ledger_account_ledger_account_id_seq TO postgres;
GRANT UPDATE ON TABLE public.financial_ledger_account_ledger_account_id_seq TO postgres;
GRANT USAGE ON TABLE public.financial_ledger_account_ledger_account_id_seq TO postgres;
GRANT SELECT ON TABLE public.financial_ledger_account_ledger_account_id_seq TO service_role;
GRANT UPDATE ON TABLE public.financial_ledger_account_ledger_account_id_seq TO service_role;
GRANT USAGE ON TABLE public.financial_ledger_account_ledger_account_id_seq TO service_role;
GRANT DELETE ON TABLE public.funded_research_project TO postgres;
GRANT INSERT ON TABLE public.funded_research_project TO postgres;
GRANT MAINTAIN ON TABLE public.funded_research_project TO postgres;
GRANT REFERENCES ON TABLE public.funded_research_project TO postgres;
GRANT SELECT ON TABLE public.funded_research_project TO postgres;
GRANT TRIGGER ON TABLE public.funded_research_project TO postgres;
GRANT TRUNCATE ON TABLE public.funded_research_project TO postgres;
GRANT UPDATE ON TABLE public.funded_research_project TO postgres;
GRANT DELETE ON TABLE public.funded_research_project TO service_role;
GRANT INSERT ON TABLE public.funded_research_project TO service_role;
GRANT MAINTAIN ON TABLE public.funded_research_project TO service_role;
GRANT REFERENCES ON TABLE public.funded_research_project TO service_role;
GRANT SELECT ON TABLE public.funded_research_project TO service_role;
GRANT TRIGGER ON TABLE public.funded_research_project TO service_role;
GRANT TRUNCATE ON TABLE public.funded_research_project TO service_role;
GRANT UPDATE ON TABLE public.funded_research_project TO service_role;
GRANT DELETE ON TABLE public.funding_agency TO authenticated;
GRANT INSERT ON TABLE public.funding_agency TO authenticated;
GRANT UPDATE ON TABLE public.funding_agency TO authenticated;
GRANT DELETE ON TABLE public.funding_agency TO postgres;
GRANT INSERT ON TABLE public.funding_agency TO postgres;
GRANT MAINTAIN ON TABLE public.funding_agency TO postgres;
GRANT REFERENCES ON TABLE public.funding_agency TO postgres;
GRANT SELECT ON TABLE public.funding_agency TO postgres;
GRANT TRIGGER ON TABLE public.funding_agency TO postgres;
GRANT TRUNCATE ON TABLE public.funding_agency TO postgres;
GRANT UPDATE ON TABLE public.funding_agency TO postgres;
GRANT DELETE ON TABLE public.funding_agency TO service_role;
GRANT INSERT ON TABLE public.funding_agency TO service_role;
GRANT MAINTAIN ON TABLE public.funding_agency TO service_role;
GRANT REFERENCES ON TABLE public.funding_agency TO service_role;
GRANT SELECT ON TABLE public.funding_agency TO service_role;
GRANT TRIGGER ON TABLE public.funding_agency TO service_role;
GRANT TRUNCATE ON TABLE public.funding_agency TO service_role;
GRANT UPDATE ON TABLE public.funding_agency TO service_role;
GRANT SELECT ON TABLE public.funding_agency_funding_agency_id_seq TO postgres;
GRANT UPDATE ON TABLE public.funding_agency_funding_agency_id_seq TO postgres;
GRANT USAGE ON TABLE public.funding_agency_funding_agency_id_seq TO postgres;
GRANT SELECT ON TABLE public.funding_agency_funding_agency_id_seq TO service_role;
GRANT UPDATE ON TABLE public.funding_agency_funding_agency_id_seq TO service_role;
GRANT USAGE ON TABLE public.funding_agency_funding_agency_id_seq TO service_role;
GRANT DELETE ON TABLE public.funding_type TO authenticated;
GRANT INSERT ON TABLE public.funding_type TO authenticated;
GRANT UPDATE ON TABLE public.funding_type TO authenticated;
GRANT DELETE ON TABLE public.funding_type TO postgres;
GRANT INSERT ON TABLE public.funding_type TO postgres;
GRANT MAINTAIN ON TABLE public.funding_type TO postgres;
GRANT REFERENCES ON TABLE public.funding_type TO postgres;
GRANT SELECT ON TABLE public.funding_type TO postgres;
GRANT TRIGGER ON TABLE public.funding_type TO postgres;
GRANT TRUNCATE ON TABLE public.funding_type TO postgres;
GRANT UPDATE ON TABLE public.funding_type TO postgres;
GRANT DELETE ON TABLE public.funding_type TO service_role;
GRANT INSERT ON TABLE public.funding_type TO service_role;
GRANT MAINTAIN ON TABLE public.funding_type TO service_role;
GRANT REFERENCES ON TABLE public.funding_type TO service_role;
GRANT SELECT ON TABLE public.funding_type TO service_role;
GRANT TRIGGER ON TABLE public.funding_type TO service_role;
GRANT TRUNCATE ON TABLE public.funding_type TO service_role;
GRANT UPDATE ON TABLE public.funding_type TO service_role;
GRANT SELECT ON TABLE public.funding_type_funding_type_id_seq TO postgres;
GRANT UPDATE ON TABLE public.funding_type_funding_type_id_seq TO postgres;
GRANT USAGE ON TABLE public.funding_type_funding_type_id_seq TO postgres;
GRANT SELECT ON TABLE public.funding_type_funding_type_id_seq TO service_role;
GRANT UPDATE ON TABLE public.funding_type_funding_type_id_seq TO service_role;
GRANT USAGE ON TABLE public.funding_type_funding_type_id_seq TO service_role;
GRANT DELETE ON TABLE public.gender TO authenticated;
GRANT INSERT ON TABLE public.gender TO authenticated;
GRANT UPDATE ON TABLE public.gender TO authenticated;
GRANT DELETE ON TABLE public.gender TO postgres;
GRANT INSERT ON TABLE public.gender TO postgres;
GRANT MAINTAIN ON TABLE public.gender TO postgres;
GRANT REFERENCES ON TABLE public.gender TO postgres;
GRANT SELECT ON TABLE public.gender TO postgres;
GRANT TRIGGER ON TABLE public.gender TO postgres;
GRANT TRUNCATE ON TABLE public.gender TO postgres;
GRANT UPDATE ON TABLE public.gender TO postgres;
GRANT DELETE ON TABLE public.gender TO service_role;
GRANT INSERT ON TABLE public.gender TO service_role;
GRANT MAINTAIN ON TABLE public.gender TO service_role;
GRANT REFERENCES ON TABLE public.gender TO service_role;
GRANT SELECT ON TABLE public.gender TO service_role;
GRANT TRIGGER ON TABLE public.gender TO service_role;
GRANT TRUNCATE ON TABLE public.gender TO service_role;
GRANT UPDATE ON TABLE public.gender TO service_role;
GRANT SELECT ON TABLE public.gender_gender_id_seq TO postgres;
GRANT UPDATE ON TABLE public.gender_gender_id_seq TO postgres;
GRANT USAGE ON TABLE public.gender_gender_id_seq TO postgres;
GRANT SELECT ON TABLE public.gender_gender_id_seq TO service_role;
GRANT UPDATE ON TABLE public.gender_gender_id_seq TO service_role;
GRANT USAGE ON TABLE public.gender_gender_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.global_search(p_q text, p_limit integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.global_search(p_q text, p_limit integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.global_search(p_q text, p_limit integer) TO service_role;
GRANT DELETE ON TABLE public.grade_rule TO authenticated;
GRANT INSERT ON TABLE public.grade_rule TO authenticated;
GRANT UPDATE ON TABLE public.grade_rule TO authenticated;
GRANT DELETE ON TABLE public.grade_rule TO postgres;
GRANT INSERT ON TABLE public.grade_rule TO postgres;
GRANT MAINTAIN ON TABLE public.grade_rule TO postgres;
GRANT REFERENCES ON TABLE public.grade_rule TO postgres;
GRANT SELECT ON TABLE public.grade_rule TO postgres;
GRANT TRIGGER ON TABLE public.grade_rule TO postgres;
GRANT TRUNCATE ON TABLE public.grade_rule TO postgres;
GRANT UPDATE ON TABLE public.grade_rule TO postgres;
GRANT DELETE ON TABLE public.grade_rule TO service_role;
GRANT INSERT ON TABLE public.grade_rule TO service_role;
GRANT MAINTAIN ON TABLE public.grade_rule TO service_role;
GRANT REFERENCES ON TABLE public.grade_rule TO service_role;
GRANT SELECT ON TABLE public.grade_rule TO service_role;
GRANT TRIGGER ON TABLE public.grade_rule TO service_role;
GRANT TRUNCATE ON TABLE public.grade_rule TO service_role;
GRANT UPDATE ON TABLE public.grade_rule TO service_role;
GRANT SELECT ON TABLE public.grade_rule_grade_rule_id_seq TO postgres;
GRANT UPDATE ON TABLE public.grade_rule_grade_rule_id_seq TO postgres;
GRANT USAGE ON TABLE public.grade_rule_grade_rule_id_seq TO postgres;
GRANT SELECT ON TABLE public.grade_rule_grade_rule_id_seq TO service_role;
GRANT UPDATE ON TABLE public.grade_rule_grade_rule_id_seq TO service_role;
GRANT USAGE ON TABLE public.grade_rule_grade_rule_id_seq TO service_role;
GRANT DELETE ON TABLE public.grade_scale TO authenticated;
GRANT INSERT ON TABLE public.grade_scale TO authenticated;
GRANT UPDATE ON TABLE public.grade_scale TO authenticated;
GRANT DELETE ON TABLE public.grade_scale TO postgres;
GRANT INSERT ON TABLE public.grade_scale TO postgres;
GRANT MAINTAIN ON TABLE public.grade_scale TO postgres;
GRANT REFERENCES ON TABLE public.grade_scale TO postgres;
GRANT SELECT ON TABLE public.grade_scale TO postgres;
GRANT TRIGGER ON TABLE public.grade_scale TO postgres;
GRANT TRUNCATE ON TABLE public.grade_scale TO postgres;
GRANT UPDATE ON TABLE public.grade_scale TO postgres;
GRANT DELETE ON TABLE public.grade_scale TO service_role;
GRANT INSERT ON TABLE public.grade_scale TO service_role;
GRANT MAINTAIN ON TABLE public.grade_scale TO service_role;
GRANT REFERENCES ON TABLE public.grade_scale TO service_role;
GRANT SELECT ON TABLE public.grade_scale TO service_role;
GRANT TRIGGER ON TABLE public.grade_scale TO service_role;
GRANT TRUNCATE ON TABLE public.grade_scale TO service_role;
GRANT UPDATE ON TABLE public.grade_scale TO service_role;
GRANT SELECT ON TABLE public.grade_scale_grade_scale_id_seq TO postgres;
GRANT UPDATE ON TABLE public.grade_scale_grade_scale_id_seq TO postgres;
GRANT USAGE ON TABLE public.grade_scale_grade_scale_id_seq TO postgres;
GRANT SELECT ON TABLE public.grade_scale_grade_scale_id_seq TO service_role;
GRANT UPDATE ON TABLE public.grade_scale_grade_scale_id_seq TO service_role;
GRANT USAGE ON TABLE public.grade_scale_grade_scale_id_seq TO service_role;
GRANT DELETE ON TABLE public.grievance TO postgres;
GRANT INSERT ON TABLE public.grievance TO postgres;
GRANT MAINTAIN ON TABLE public.grievance TO postgres;
GRANT REFERENCES ON TABLE public.grievance TO postgres;
GRANT SELECT ON TABLE public.grievance TO postgres;
GRANT TRIGGER ON TABLE public.grievance TO postgres;
GRANT TRUNCATE ON TABLE public.grievance TO postgres;
GRANT UPDATE ON TABLE public.grievance TO postgres;
GRANT DELETE ON TABLE public.grievance TO service_role;
GRANT INSERT ON TABLE public.grievance TO service_role;
GRANT MAINTAIN ON TABLE public.grievance TO service_role;
GRANT REFERENCES ON TABLE public.grievance TO service_role;
GRANT SELECT ON TABLE public.grievance TO service_role;
GRANT TRIGGER ON TABLE public.grievance TO service_role;
GRANT TRUNCATE ON TABLE public.grievance TO service_role;
GRANT UPDATE ON TABLE public.grievance TO service_role;
GRANT EXECUTE ON FUNCTION public.grievance_act(p_grievance_id bigint, p_action_type text, p_notes text, p_new_status text, p_resolution text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.grievance_act(p_grievance_id bigint, p_action_type text, p_notes text, p_new_status text, p_resolution text) TO postgres;
GRANT EXECUTE ON FUNCTION public.grievance_act(p_grievance_id bigint, p_action_type text, p_notes text, p_new_status text, p_resolution text) TO service_role;
GRANT DELETE ON TABLE public.grievance_action TO postgres;
GRANT INSERT ON TABLE public.grievance_action TO postgres;
GRANT MAINTAIN ON TABLE public.grievance_action TO postgres;
GRANT REFERENCES ON TABLE public.grievance_action TO postgres;
GRANT SELECT ON TABLE public.grievance_action TO postgres;
GRANT TRIGGER ON TABLE public.grievance_action TO postgres;
GRANT TRUNCATE ON TABLE public.grievance_action TO postgres;
GRANT UPDATE ON TABLE public.grievance_action TO postgres;
GRANT DELETE ON TABLE public.grievance_action TO service_role;
GRANT INSERT ON TABLE public.grievance_action TO service_role;
GRANT MAINTAIN ON TABLE public.grievance_action TO service_role;
GRANT REFERENCES ON TABLE public.grievance_action TO service_role;
GRANT SELECT ON TABLE public.grievance_action TO service_role;
GRANT TRIGGER ON TABLE public.grievance_action TO service_role;
GRANT TRUNCATE ON TABLE public.grievance_action TO service_role;
GRANT UPDATE ON TABLE public.grievance_action TO service_role;
GRANT SELECT ON TABLE public.grievance_action_grievance_action_id_seq TO postgres;
GRANT UPDATE ON TABLE public.grievance_action_grievance_action_id_seq TO postgres;
GRANT USAGE ON TABLE public.grievance_action_grievance_action_id_seq TO postgres;
GRANT SELECT ON TABLE public.grievance_action_grievance_action_id_seq TO service_role;
GRANT UPDATE ON TABLE public.grievance_action_grievance_action_id_seq TO service_role;
GRANT USAGE ON TABLE public.grievance_action_grievance_action_id_seq TO service_role;
GRANT DELETE ON TABLE public.grievance_category TO authenticated;
GRANT INSERT ON TABLE public.grievance_category TO authenticated;
GRANT UPDATE ON TABLE public.grievance_category TO authenticated;
GRANT DELETE ON TABLE public.grievance_category TO postgres;
GRANT INSERT ON TABLE public.grievance_category TO postgres;
GRANT MAINTAIN ON TABLE public.grievance_category TO postgres;
GRANT REFERENCES ON TABLE public.grievance_category TO postgres;
GRANT SELECT ON TABLE public.grievance_category TO postgres;
GRANT TRIGGER ON TABLE public.grievance_category TO postgres;
GRANT TRUNCATE ON TABLE public.grievance_category TO postgres;
GRANT UPDATE ON TABLE public.grievance_category TO postgres;
GRANT DELETE ON TABLE public.grievance_category TO service_role;
GRANT INSERT ON TABLE public.grievance_category TO service_role;
GRANT MAINTAIN ON TABLE public.grievance_category TO service_role;
GRANT REFERENCES ON TABLE public.grievance_category TO service_role;
GRANT SELECT ON TABLE public.grievance_category TO service_role;
GRANT TRIGGER ON TABLE public.grievance_category TO service_role;
GRANT TRUNCATE ON TABLE public.grievance_category TO service_role;
GRANT UPDATE ON TABLE public.grievance_category TO service_role;
GRANT SELECT ON TABLE public.grievance_category_grievance_category_id_seq TO postgres;
GRANT UPDATE ON TABLE public.grievance_category_grievance_category_id_seq TO postgres;
GRANT USAGE ON TABLE public.grievance_category_grievance_category_id_seq TO postgres;
GRANT SELECT ON TABLE public.grievance_category_grievance_category_id_seq TO service_role;
GRANT UPDATE ON TABLE public.grievance_category_grievance_category_id_seq TO service_role;
GRANT USAGE ON TABLE public.grievance_category_grievance_category_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.grievance_detail(p_grievance_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.grievance_detail(p_grievance_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.grievance_detail(p_grievance_id bigint) TO service_role;
GRANT SELECT ON TABLE public.grievance_grievance_id_seq TO postgres;
GRANT UPDATE ON TABLE public.grievance_grievance_id_seq TO postgres;
GRANT USAGE ON TABLE public.grievance_grievance_id_seq TO postgres;
GRANT SELECT ON TABLE public.grievance_grievance_id_seq TO service_role;
GRANT UPDATE ON TABLE public.grievance_grievance_id_seq TO service_role;
GRANT USAGE ON TABLE public.grievance_grievance_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.grievance_list(p_search text, p_status text, p_priority text, p_limit integer, p_offset integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.grievance_list(p_search text, p_status text, p_priority text, p_limit integer, p_offset integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.grievance_list(p_search text, p_status text, p_priority text, p_limit integer, p_offset integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.grievance_my() TO authenticated;
GRANT EXECUTE ON FUNCTION public.grievance_my() TO postgres;
GRANT EXECUTE ON FUNCTION public.grievance_my() TO service_role;
GRANT EXECUTE ON FUNCTION public.grievance_student_respond(p_grievance_id bigint, p_response text, p_notes text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.grievance_student_respond(p_grievance_id bigint, p_response text, p_notes text) TO postgres;
GRANT EXECUTE ON FUNCTION public.grievance_student_respond(p_grievance_id bigint, p_response text, p_notes text) TO service_role;
GRANT EXECUTE ON FUNCTION public.grievance_submit(p_category_id integer, p_department_id integer, p_subject text, p_description text, p_priority text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.grievance_submit(p_category_id integer, p_department_id integer, p_subject text, p_description text, p_priority text) TO postgres;
GRANT EXECUTE ON FUNCTION public.grievance_submit(p_category_id integer, p_department_id integer, p_subject text, p_description text, p_priority text) TO service_role;
GRANT EXECUTE ON FUNCTION public.iam_assign_role(p_user_id bigint, p_role_id integer, p_scope_type text, p_scope_entity_id integer, p_reason text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.iam_assign_role(p_user_id bigint, p_role_id integer, p_scope_type text, p_scope_entity_id integer, p_reason text) TO postgres;
GRANT EXECUTE ON FUNCTION public.iam_assign_role(p_user_id bigint, p_role_id integer, p_scope_type text, p_scope_entity_id integer, p_reason text) TO service_role;
GRANT EXECUTE ON FUNCTION public.iam_can_provision() TO authenticated;
GRANT EXECUTE ON FUNCTION public.iam_can_provision() TO postgres;
GRANT EXECUTE ON FUNCTION public.iam_can_provision() TO service_role;
GRANT EXECUTE ON FUNCTION public.iam_link_auth_user(p_email text, p_student_number text, p_employee_number text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.iam_link_auth_user(p_email text, p_student_number text, p_employee_number text) TO postgres;
GRANT EXECUTE ON FUNCTION public.iam_link_auth_user(p_email text, p_student_number text, p_employee_number text) TO service_role;
GRANT EXECUTE ON FUNCTION public.iam_link_person(p_user_id bigint, p_student_number text, p_employee_number text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.iam_link_person(p_user_id bigint, p_student_number text, p_employee_number text) TO postgres;
GRANT EXECUTE ON FUNCTION public.iam_link_person(p_user_id bigint, p_student_number text, p_employee_number text) TO service_role;
GRANT EXECUTE ON FUNCTION public.iam_mfa_policy_gaps() TO authenticated;
GRANT EXECUTE ON FUNCTION public.iam_mfa_policy_gaps() TO postgres;
GRANT EXECUTE ON FUNCTION public.iam_mfa_policy_gaps() TO service_role;
GRANT EXECUTE ON FUNCTION public.iam_mfa_policy_list() TO authenticated;
GRANT EXECUTE ON FUNCTION public.iam_mfa_policy_list() TO postgres;
GRANT EXECUTE ON FUNCTION public.iam_mfa_policy_list() TO service_role;
GRANT EXECUTE ON FUNCTION public.iam_mfa_policy_set(p_role_code text, p_required boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.iam_mfa_policy_set(p_role_code text, p_required boolean) TO postgres;
GRANT EXECUTE ON FUNCTION public.iam_mfa_policy_set(p_role_code text, p_required boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.iam_override_end(p_override_id bigint, p_reason text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.iam_override_end(p_override_id bigint, p_reason text) TO postgres;
GRANT EXECUTE ON FUNCTION public.iam_override_end(p_override_id bigint, p_reason text) TO service_role;
GRANT EXECUTE ON FUNCTION public.iam_override_list(p_user_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.iam_override_list(p_user_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.iam_override_list(p_user_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.iam_override_set(p_user_id bigint, p_permission_code text, p_effect text, p_scope_type text, p_scope_entity_id integer, p_justification text, p_valid_to timestamp with time zone) TO authenticated;
GRANT EXECUTE ON FUNCTION public.iam_override_set(p_user_id bigint, p_permission_code text, p_effect text, p_scope_type text, p_scope_entity_id integer, p_justification text, p_valid_to timestamp with time zone) TO postgres;
GRANT EXECUTE ON FUNCTION public.iam_override_set(p_user_id bigint, p_permission_code text, p_effect text, p_scope_type text, p_scope_entity_id integer, p_justification text, p_valid_to timestamp with time zone) TO service_role;
GRANT EXECUTE ON FUNCTION public.iam_permission_options(p_search text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.iam_permission_options(p_search text) TO postgres;
GRANT EXECUTE ON FUNCTION public.iam_permission_options(p_search text) TO service_role;
GRANT EXECUTE ON FUNCTION public.iam_provision_user(p_auth_user uuid, p_email text, p_student_number text, p_employee_number text, p_actor_user_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.iam_provision_user(p_auth_user uuid, p_email text, p_student_number text, p_employee_number text, p_actor_user_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.iam_revoke_role(p_assignment_id bigint, p_reason text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.iam_revoke_role(p_assignment_id bigint, p_reason text) TO postgres;
GRANT EXECUTE ON FUNCTION public.iam_revoke_role(p_assignment_id bigint, p_reason text) TO service_role;
GRANT EXECUTE ON FUNCTION public.iam_roles() TO authenticated;
GRANT EXECUTE ON FUNCTION public.iam_roles() TO postgres;
GRANT EXECUTE ON FUNCTION public.iam_roles() TO service_role;
GRANT EXECUTE ON FUNCTION public.iam_set_account_status(p_user_id bigint, p_status text, p_reason text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.iam_set_account_status(p_user_id bigint, p_status text, p_reason text) TO postgres;
GRANT EXECUTE ON FUNCTION public.iam_set_account_status(p_user_id bigint, p_status text, p_reason text) TO service_role;
GRANT EXECUTE ON FUNCTION public.iam_user_detail(p_user_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.iam_user_detail(p_user_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.iam_user_detail(p_user_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.iam_user_list(p_search text, p_status text, p_limit integer, p_offset integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.iam_user_list(p_search text, p_status text, p_limit integer, p_offset integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.iam_user_list(p_search text, p_status text, p_limit integer, p_offset integer) TO service_role;
GRANT DELETE ON TABLE public.indexing_agency TO authenticated;
GRANT INSERT ON TABLE public.indexing_agency TO authenticated;
GRANT UPDATE ON TABLE public.indexing_agency TO authenticated;
GRANT DELETE ON TABLE public.indexing_agency TO postgres;
GRANT INSERT ON TABLE public.indexing_agency TO postgres;
GRANT MAINTAIN ON TABLE public.indexing_agency TO postgres;
GRANT REFERENCES ON TABLE public.indexing_agency TO postgres;
GRANT SELECT ON TABLE public.indexing_agency TO postgres;
GRANT TRIGGER ON TABLE public.indexing_agency TO postgres;
GRANT TRUNCATE ON TABLE public.indexing_agency TO postgres;
GRANT UPDATE ON TABLE public.indexing_agency TO postgres;
GRANT DELETE ON TABLE public.indexing_agency TO service_role;
GRANT INSERT ON TABLE public.indexing_agency TO service_role;
GRANT MAINTAIN ON TABLE public.indexing_agency TO service_role;
GRANT REFERENCES ON TABLE public.indexing_agency TO service_role;
GRANT SELECT ON TABLE public.indexing_agency TO service_role;
GRANT TRIGGER ON TABLE public.indexing_agency TO service_role;
GRANT TRUNCATE ON TABLE public.indexing_agency TO service_role;
GRANT UPDATE ON TABLE public.indexing_agency TO service_role;
GRANT SELECT ON TABLE public.indexing_agency_indexing_agency_id_seq TO postgres;
GRANT UPDATE ON TABLE public.indexing_agency_indexing_agency_id_seq TO postgres;
GRANT USAGE ON TABLE public.indexing_agency_indexing_agency_id_seq TO postgres;
GRANT SELECT ON TABLE public.indexing_agency_indexing_agency_id_seq TO service_role;
GRANT UPDATE ON TABLE public.indexing_agency_indexing_agency_id_seq TO service_role;
GRANT USAGE ON TABLE public.indexing_agency_indexing_agency_id_seq TO service_role;
GRANT DELETE ON TABLE public.industry_sector TO authenticated;
GRANT INSERT ON TABLE public.industry_sector TO authenticated;
GRANT UPDATE ON TABLE public.industry_sector TO authenticated;
GRANT DELETE ON TABLE public.industry_sector TO postgres;
GRANT INSERT ON TABLE public.industry_sector TO postgres;
GRANT MAINTAIN ON TABLE public.industry_sector TO postgres;
GRANT REFERENCES ON TABLE public.industry_sector TO postgres;
GRANT SELECT ON TABLE public.industry_sector TO postgres;
GRANT TRIGGER ON TABLE public.industry_sector TO postgres;
GRANT TRUNCATE ON TABLE public.industry_sector TO postgres;
GRANT UPDATE ON TABLE public.industry_sector TO postgres;
GRANT DELETE ON TABLE public.industry_sector TO service_role;
GRANT INSERT ON TABLE public.industry_sector TO service_role;
GRANT MAINTAIN ON TABLE public.industry_sector TO service_role;
GRANT REFERENCES ON TABLE public.industry_sector TO service_role;
GRANT SELECT ON TABLE public.industry_sector TO service_role;
GRANT TRIGGER ON TABLE public.industry_sector TO service_role;
GRANT TRUNCATE ON TABLE public.industry_sector TO service_role;
GRANT UPDATE ON TABLE public.industry_sector TO service_role;
GRANT SELECT ON TABLE public.industry_sector_industry_sector_id_seq TO postgres;
GRANT UPDATE ON TABLE public.industry_sector_industry_sector_id_seq TO postgres;
GRANT USAGE ON TABLE public.industry_sector_industry_sector_id_seq TO postgres;
GRANT SELECT ON TABLE public.industry_sector_industry_sector_id_seq TO service_role;
GRANT UPDATE ON TABLE public.industry_sector_industry_sector_id_seq TO service_role;
GRANT USAGE ON TABLE public.industry_sector_industry_sector_id_seq TO service_role;
GRANT DELETE ON TABLE public.installment_plan TO postgres;
GRANT INSERT ON TABLE public.installment_plan TO postgres;
GRANT MAINTAIN ON TABLE public.installment_plan TO postgres;
GRANT REFERENCES ON TABLE public.installment_plan TO postgres;
GRANT SELECT ON TABLE public.installment_plan TO postgres;
GRANT TRIGGER ON TABLE public.installment_plan TO postgres;
GRANT TRUNCATE ON TABLE public.installment_plan TO postgres;
GRANT UPDATE ON TABLE public.installment_plan TO postgres;
GRANT DELETE ON TABLE public.installment_plan TO service_role;
GRANT INSERT ON TABLE public.installment_plan TO service_role;
GRANT MAINTAIN ON TABLE public.installment_plan TO service_role;
GRANT REFERENCES ON TABLE public.installment_plan TO service_role;
GRANT SELECT ON TABLE public.installment_plan TO service_role;
GRANT TRIGGER ON TABLE public.installment_plan TO service_role;
GRANT TRUNCATE ON TABLE public.installment_plan TO service_role;
GRANT UPDATE ON TABLE public.installment_plan TO service_role;
GRANT SELECT ON TABLE public.installment_plan_installment_plan_id_seq TO postgres;
GRANT UPDATE ON TABLE public.installment_plan_installment_plan_id_seq TO postgres;
GRANT USAGE ON TABLE public.installment_plan_installment_plan_id_seq TO postgres;
GRANT SELECT ON TABLE public.installment_plan_installment_plan_id_seq TO service_role;
GRANT UPDATE ON TABLE public.installment_plan_installment_plan_id_seq TO service_role;
GRANT USAGE ON TABLE public.installment_plan_installment_plan_id_seq TO service_role;
GRANT DELETE ON TABLE public.institution TO postgres;
GRANT INSERT ON TABLE public.institution TO postgres;
GRANT MAINTAIN ON TABLE public.institution TO postgres;
GRANT REFERENCES ON TABLE public.institution TO postgres;
GRANT SELECT ON TABLE public.institution TO postgres;
GRANT TRIGGER ON TABLE public.institution TO postgres;
GRANT TRUNCATE ON TABLE public.institution TO postgres;
GRANT UPDATE ON TABLE public.institution TO postgres;
GRANT DELETE ON TABLE public.institution TO service_role;
GRANT INSERT ON TABLE public.institution TO service_role;
GRANT MAINTAIN ON TABLE public.institution TO service_role;
GRANT REFERENCES ON TABLE public.institution TO service_role;
GRANT SELECT ON TABLE public.institution TO service_role;
GRANT TRIGGER ON TABLE public.institution TO service_role;
GRANT TRUNCATE ON TABLE public.institution TO service_role;
GRANT UPDATE ON TABLE public.institution TO service_role;
GRANT EXECUTE ON FUNCTION public.institution_create(p jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.institution_create(p jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.institution_create(p jsonb) TO service_role;
GRANT SELECT ON TABLE public.institution_institution_id_seq TO postgres;
GRANT UPDATE ON TABLE public.institution_institution_id_seq TO postgres;
GRANT USAGE ON TABLE public.institution_institution_id_seq TO postgres;
GRANT SELECT ON TABLE public.institution_institution_id_seq TO service_role;
GRANT UPDATE ON TABLE public.institution_institution_id_seq TO service_role;
GRANT USAGE ON TABLE public.institution_institution_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.institution_update(p_id integer, p jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.institution_update(p_id integer, p jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.institution_update(p_id integer, p jsonb) TO service_role;
GRANT DELETE ON TABLE public.journal TO authenticated;
GRANT INSERT ON TABLE public.journal TO authenticated;
GRANT UPDATE ON TABLE public.journal TO authenticated;
GRANT DELETE ON TABLE public.journal TO postgres;
GRANT INSERT ON TABLE public.journal TO postgres;
GRANT MAINTAIN ON TABLE public.journal TO postgres;
GRANT REFERENCES ON TABLE public.journal TO postgres;
GRANT SELECT ON TABLE public.journal TO postgres;
GRANT TRIGGER ON TABLE public.journal TO postgres;
GRANT TRUNCATE ON TABLE public.journal TO postgres;
GRANT UPDATE ON TABLE public.journal TO postgres;
GRANT DELETE ON TABLE public.journal TO service_role;
GRANT INSERT ON TABLE public.journal TO service_role;
GRANT MAINTAIN ON TABLE public.journal TO service_role;
GRANT REFERENCES ON TABLE public.journal TO service_role;
GRANT SELECT ON TABLE public.journal TO service_role;
GRANT TRIGGER ON TABLE public.journal TO service_role;
GRANT TRUNCATE ON TABLE public.journal TO service_role;
GRANT UPDATE ON TABLE public.journal TO service_role;
GRANT SELECT ON TABLE public.journal_journal_id_seq TO postgres;
GRANT UPDATE ON TABLE public.journal_journal_id_seq TO postgres;
GRANT USAGE ON TABLE public.journal_journal_id_seq TO postgres;
GRANT SELECT ON TABLE public.journal_journal_id_seq TO service_role;
GRANT UPDATE ON TABLE public.journal_journal_id_seq TO service_role;
GRANT USAGE ON TABLE public.journal_journal_id_seq TO service_role;
GRANT DELETE ON TABLE public.journal_metric TO authenticated;
GRANT INSERT ON TABLE public.journal_metric TO authenticated;
GRANT UPDATE ON TABLE public.journal_metric TO authenticated;
GRANT DELETE ON TABLE public.journal_metric TO postgres;
GRANT INSERT ON TABLE public.journal_metric TO postgres;
GRANT MAINTAIN ON TABLE public.journal_metric TO postgres;
GRANT REFERENCES ON TABLE public.journal_metric TO postgres;
GRANT SELECT ON TABLE public.journal_metric TO postgres;
GRANT TRIGGER ON TABLE public.journal_metric TO postgres;
GRANT TRUNCATE ON TABLE public.journal_metric TO postgres;
GRANT UPDATE ON TABLE public.journal_metric TO postgres;
GRANT DELETE ON TABLE public.journal_metric TO service_role;
GRANT INSERT ON TABLE public.journal_metric TO service_role;
GRANT MAINTAIN ON TABLE public.journal_metric TO service_role;
GRANT REFERENCES ON TABLE public.journal_metric TO service_role;
GRANT SELECT ON TABLE public.journal_metric TO service_role;
GRANT TRIGGER ON TABLE public.journal_metric TO service_role;
GRANT TRUNCATE ON TABLE public.journal_metric TO service_role;
GRANT UPDATE ON TABLE public.journal_metric TO service_role;
GRANT SELECT ON TABLE public.journal_metric_journal_metric_id_seq TO postgres;
GRANT UPDATE ON TABLE public.journal_metric_journal_metric_id_seq TO postgres;
GRANT USAGE ON TABLE public.journal_metric_journal_metric_id_seq TO postgres;
GRANT SELECT ON TABLE public.journal_metric_journal_metric_id_seq TO service_role;
GRANT UPDATE ON TABLE public.journal_metric_journal_metric_id_seq TO service_role;
GRANT USAGE ON TABLE public.journal_metric_journal_metric_id_seq TO service_role;
GRANT DELETE ON TABLE public.journal_publication TO postgres;
GRANT INSERT ON TABLE public.journal_publication TO postgres;
GRANT MAINTAIN ON TABLE public.journal_publication TO postgres;
GRANT REFERENCES ON TABLE public.journal_publication TO postgres;
GRANT SELECT ON TABLE public.journal_publication TO postgres;
GRANT TRIGGER ON TABLE public.journal_publication TO postgres;
GRANT TRUNCATE ON TABLE public.journal_publication TO postgres;
GRANT UPDATE ON TABLE public.journal_publication TO postgres;
GRANT DELETE ON TABLE public.journal_publication TO service_role;
GRANT INSERT ON TABLE public.journal_publication TO service_role;
GRANT MAINTAIN ON TABLE public.journal_publication TO service_role;
GRANT REFERENCES ON TABLE public.journal_publication TO service_role;
GRANT SELECT ON TABLE public.journal_publication TO service_role;
GRANT TRIGGER ON TABLE public.journal_publication TO service_role;
GRANT TRUNCATE ON TABLE public.journal_publication TO service_role;
GRANT UPDATE ON TABLE public.journal_publication TO service_role;
GRANT DELETE ON TABLE public.journal_publication_indexing TO authenticated;
GRANT INSERT ON TABLE public.journal_publication_indexing TO authenticated;
GRANT UPDATE ON TABLE public.journal_publication_indexing TO authenticated;
GRANT DELETE ON TABLE public.journal_publication_indexing TO postgres;
GRANT INSERT ON TABLE public.journal_publication_indexing TO postgres;
GRANT MAINTAIN ON TABLE public.journal_publication_indexing TO postgres;
GRANT REFERENCES ON TABLE public.journal_publication_indexing TO postgres;
GRANT SELECT ON TABLE public.journal_publication_indexing TO postgres;
GRANT TRIGGER ON TABLE public.journal_publication_indexing TO postgres;
GRANT TRUNCATE ON TABLE public.journal_publication_indexing TO postgres;
GRANT UPDATE ON TABLE public.journal_publication_indexing TO postgres;
GRANT DELETE ON TABLE public.journal_publication_indexing TO service_role;
GRANT INSERT ON TABLE public.journal_publication_indexing TO service_role;
GRANT MAINTAIN ON TABLE public.journal_publication_indexing TO service_role;
GRANT REFERENCES ON TABLE public.journal_publication_indexing TO service_role;
GRANT SELECT ON TABLE public.journal_publication_indexing TO service_role;
GRANT TRIGGER ON TABLE public.journal_publication_indexing TO service_role;
GRANT TRUNCATE ON TABLE public.journal_publication_indexing TO service_role;
GRANT UPDATE ON TABLE public.journal_publication_indexing TO service_role;
GRANT DELETE ON TABLE public.journal_type TO authenticated;
GRANT INSERT ON TABLE public.journal_type TO authenticated;
GRANT UPDATE ON TABLE public.journal_type TO authenticated;
GRANT DELETE ON TABLE public.journal_type TO postgres;
GRANT INSERT ON TABLE public.journal_type TO postgres;
GRANT MAINTAIN ON TABLE public.journal_type TO postgres;
GRANT REFERENCES ON TABLE public.journal_type TO postgres;
GRANT SELECT ON TABLE public.journal_type TO postgres;
GRANT TRIGGER ON TABLE public.journal_type TO postgres;
GRANT TRUNCATE ON TABLE public.journal_type TO postgres;
GRANT UPDATE ON TABLE public.journal_type TO postgres;
GRANT DELETE ON TABLE public.journal_type TO service_role;
GRANT INSERT ON TABLE public.journal_type TO service_role;
GRANT MAINTAIN ON TABLE public.journal_type TO service_role;
GRANT REFERENCES ON TABLE public.journal_type TO service_role;
GRANT SELECT ON TABLE public.journal_type TO service_role;
GRANT TRIGGER ON TABLE public.journal_type TO service_role;
GRANT TRUNCATE ON TABLE public.journal_type TO service_role;
GRANT UPDATE ON TABLE public.journal_type TO service_role;
GRANT SELECT ON TABLE public.journal_type_journal_type_id_seq TO postgres;
GRANT UPDATE ON TABLE public.journal_type_journal_type_id_seq TO postgres;
GRANT USAGE ON TABLE public.journal_type_journal_type_id_seq TO postgres;
GRANT SELECT ON TABLE public.journal_type_journal_type_id_seq TO service_role;
GRANT UPDATE ON TABLE public.journal_type_journal_type_id_seq TO service_role;
GRANT USAGE ON TABLE public.journal_type_journal_type_id_seq TO service_role;
GRANT DELETE ON TABLE public.late_fee_rule TO postgres;
GRANT INSERT ON TABLE public.late_fee_rule TO postgres;
GRANT MAINTAIN ON TABLE public.late_fee_rule TO postgres;
GRANT REFERENCES ON TABLE public.late_fee_rule TO postgres;
GRANT SELECT ON TABLE public.late_fee_rule TO postgres;
GRANT TRIGGER ON TABLE public.late_fee_rule TO postgres;
GRANT TRUNCATE ON TABLE public.late_fee_rule TO postgres;
GRANT UPDATE ON TABLE public.late_fee_rule TO postgres;
GRANT DELETE ON TABLE public.late_fee_rule TO service_role;
GRANT INSERT ON TABLE public.late_fee_rule TO service_role;
GRANT MAINTAIN ON TABLE public.late_fee_rule TO service_role;
GRANT REFERENCES ON TABLE public.late_fee_rule TO service_role;
GRANT SELECT ON TABLE public.late_fee_rule TO service_role;
GRANT TRIGGER ON TABLE public.late_fee_rule TO service_role;
GRANT TRUNCATE ON TABLE public.late_fee_rule TO service_role;
GRANT UPDATE ON TABLE public.late_fee_rule TO service_role;
GRANT SELECT ON TABLE public.late_fee_rule_late_fee_rule_id_seq TO postgres;
GRANT UPDATE ON TABLE public.late_fee_rule_late_fee_rule_id_seq TO postgres;
GRANT USAGE ON TABLE public.late_fee_rule_late_fee_rule_id_seq TO postgres;
GRANT SELECT ON TABLE public.late_fee_rule_late_fee_rule_id_seq TO service_role;
GRANT UPDATE ON TABLE public.late_fee_rule_late_fee_rule_id_seq TO service_role;
GRANT USAGE ON TABLE public.late_fee_rule_late_fee_rule_id_seq TO service_role;
GRANT DELETE ON TABLE public.late_fee_slab TO postgres;
GRANT INSERT ON TABLE public.late_fee_slab TO postgres;
GRANT MAINTAIN ON TABLE public.late_fee_slab TO postgres;
GRANT REFERENCES ON TABLE public.late_fee_slab TO postgres;
GRANT SELECT ON TABLE public.late_fee_slab TO postgres;
GRANT TRIGGER ON TABLE public.late_fee_slab TO postgres;
GRANT TRUNCATE ON TABLE public.late_fee_slab TO postgres;
GRANT UPDATE ON TABLE public.late_fee_slab TO postgres;
GRANT DELETE ON TABLE public.late_fee_slab TO service_role;
GRANT INSERT ON TABLE public.late_fee_slab TO service_role;
GRANT MAINTAIN ON TABLE public.late_fee_slab TO service_role;
GRANT REFERENCES ON TABLE public.late_fee_slab TO service_role;
GRANT SELECT ON TABLE public.late_fee_slab TO service_role;
GRANT TRIGGER ON TABLE public.late_fee_slab TO service_role;
GRANT TRUNCATE ON TABLE public.late_fee_slab TO service_role;
GRANT UPDATE ON TABLE public.late_fee_slab TO service_role;
GRANT SELECT ON TABLE public.late_fee_slab_late_fee_slab_id_seq TO postgres;
GRANT UPDATE ON TABLE public.late_fee_slab_late_fee_slab_id_seq TO postgres;
GRANT USAGE ON TABLE public.late_fee_slab_late_fee_slab_id_seq TO postgres;
GRANT SELECT ON TABLE public.late_fee_slab_late_fee_slab_id_seq TO service_role;
GRANT UPDATE ON TABLE public.late_fee_slab_late_fee_slab_id_seq TO service_role;
GRANT USAGE ON TABLE public.late_fee_slab_late_fee_slab_id_seq TO service_role;
GRANT DELETE ON TABLE public.login_audit TO postgres;
GRANT INSERT ON TABLE public.login_audit TO postgres;
GRANT MAINTAIN ON TABLE public.login_audit TO postgres;
GRANT REFERENCES ON TABLE public.login_audit TO postgres;
GRANT SELECT ON TABLE public.login_audit TO postgres;
GRANT TRIGGER ON TABLE public.login_audit TO postgres;
GRANT TRUNCATE ON TABLE public.login_audit TO postgres;
GRANT UPDATE ON TABLE public.login_audit TO postgres;
GRANT DELETE ON TABLE public.login_audit TO service_role;
GRANT INSERT ON TABLE public.login_audit TO service_role;
GRANT MAINTAIN ON TABLE public.login_audit TO service_role;
GRANT REFERENCES ON TABLE public.login_audit TO service_role;
GRANT SELECT ON TABLE public.login_audit TO service_role;
GRANT TRIGGER ON TABLE public.login_audit TO service_role;
GRANT TRUNCATE ON TABLE public.login_audit TO service_role;
GRANT UPDATE ON TABLE public.login_audit TO service_role;
GRANT EXECUTE ON FUNCTION public.login_audit_list(p_search text, p_success boolean, p_from timestamp with time zone, p_to timestamp with time zone, p_limit integer, p_offset integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.login_audit_list(p_search text, p_success boolean, p_from timestamp with time zone, p_to timestamp with time zone, p_limit integer, p_offset integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.login_audit_list(p_search text, p_success boolean, p_from timestamp with time zone, p_to timestamp with time zone, p_limit integer, p_offset integer) TO service_role;
GRANT SELECT ON TABLE public.login_audit_login_audit_id_seq TO postgres;
GRANT UPDATE ON TABLE public.login_audit_login_audit_id_seq TO postgres;
GRANT USAGE ON TABLE public.login_audit_login_audit_id_seq TO postgres;
GRANT SELECT ON TABLE public.login_audit_login_audit_id_seq TO service_role;
GRANT UPDATE ON TABLE public.login_audit_login_audit_id_seq TO service_role;
GRANT USAGE ON TABLE public.login_audit_login_audit_id_seq TO service_role;
GRANT DELETE ON TABLE public.membership_type TO authenticated;
GRANT INSERT ON TABLE public.membership_type TO authenticated;
GRANT UPDATE ON TABLE public.membership_type TO authenticated;
GRANT DELETE ON TABLE public.membership_type TO postgres;
GRANT INSERT ON TABLE public.membership_type TO postgres;
GRANT MAINTAIN ON TABLE public.membership_type TO postgres;
GRANT REFERENCES ON TABLE public.membership_type TO postgres;
GRANT SELECT ON TABLE public.membership_type TO postgres;
GRANT TRIGGER ON TABLE public.membership_type TO postgres;
GRANT TRUNCATE ON TABLE public.membership_type TO postgres;
GRANT UPDATE ON TABLE public.membership_type TO postgres;
GRANT DELETE ON TABLE public.membership_type TO service_role;
GRANT INSERT ON TABLE public.membership_type TO service_role;
GRANT MAINTAIN ON TABLE public.membership_type TO service_role;
GRANT REFERENCES ON TABLE public.membership_type TO service_role;
GRANT SELECT ON TABLE public.membership_type TO service_role;
GRANT TRIGGER ON TABLE public.membership_type TO service_role;
GRANT TRUNCATE ON TABLE public.membership_type TO service_role;
GRANT UPDATE ON TABLE public.membership_type TO service_role;
GRANT SELECT ON TABLE public.membership_type_membership_type_id_seq TO postgres;
GRANT UPDATE ON TABLE public.membership_type_membership_type_id_seq TO postgres;
GRANT USAGE ON TABLE public.membership_type_membership_type_id_seq TO postgres;
GRANT SELECT ON TABLE public.membership_type_membership_type_id_seq TO service_role;
GRANT UPDATE ON TABLE public.membership_type_membership_type_id_seq TO service_role;
GRANT USAGE ON TABLE public.membership_type_membership_type_id_seq TO service_role;
GRANT DELETE ON TABLE public.mentor_assignment TO postgres;
GRANT INSERT ON TABLE public.mentor_assignment TO postgres;
GRANT MAINTAIN ON TABLE public.mentor_assignment TO postgres;
GRANT REFERENCES ON TABLE public.mentor_assignment TO postgres;
GRANT SELECT ON TABLE public.mentor_assignment TO postgres;
GRANT TRIGGER ON TABLE public.mentor_assignment TO postgres;
GRANT TRUNCATE ON TABLE public.mentor_assignment TO postgres;
GRANT UPDATE ON TABLE public.mentor_assignment TO postgres;
GRANT DELETE ON TABLE public.mentor_assignment TO service_role;
GRANT INSERT ON TABLE public.mentor_assignment TO service_role;
GRANT MAINTAIN ON TABLE public.mentor_assignment TO service_role;
GRANT REFERENCES ON TABLE public.mentor_assignment TO service_role;
GRANT SELECT ON TABLE public.mentor_assignment TO service_role;
GRANT TRIGGER ON TABLE public.mentor_assignment TO service_role;
GRANT TRUNCATE ON TABLE public.mentor_assignment TO service_role;
GRANT UPDATE ON TABLE public.mentor_assignment TO service_role;
GRANT SELECT ON TABLE public.mentor_assignment_mentor_assignment_id_seq TO postgres;
GRANT UPDATE ON TABLE public.mentor_assignment_mentor_assignment_id_seq TO postgres;
GRANT USAGE ON TABLE public.mentor_assignment_mentor_assignment_id_seq TO postgres;
GRANT SELECT ON TABLE public.mentor_assignment_mentor_assignment_id_seq TO service_role;
GRANT UPDATE ON TABLE public.mentor_assignment_mentor_assignment_id_seq TO service_role;
GRANT USAGE ON TABLE public.mentor_assignment_mentor_assignment_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.mentoring_assign(p_student_number text, p_employee_number text, p_start date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mentoring_assign(p_student_number text, p_employee_number text, p_start date) TO postgres;
GRANT EXECUTE ON FUNCTION public.mentoring_assign(p_student_number text, p_employee_number text, p_start date) TO service_role;
GRANT EXECUTE ON FUNCTION public.mentoring_assignment_info(p_assignment_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mentoring_assignment_info(p_assignment_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.mentoring_assignment_info(p_assignment_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.mentoring_assignments(p_search text, p_status text, p_limit integer, p_offset integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mentoring_assignments(p_search text, p_status text, p_limit integer, p_offset integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.mentoring_assignments(p_search text, p_status text, p_limit integer, p_offset integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.mentoring_end_assignment(p_assignment_id bigint, p_status text, p_end_date date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mentoring_end_assignment(p_assignment_id bigint, p_status text, p_end_date date) TO postgres;
GRANT EXECUTE ON FUNCTION public.mentoring_end_assignment(p_assignment_id bigint, p_status text, p_end_date date) TO service_role;
GRANT EXECUTE ON FUNCTION public.mentoring_record_session(p_assignment_id bigint, p_date timestamp with time zone, p_observations text, p_action_plan text, p_follow_up date, p_status text, p_level text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mentoring_record_session(p_assignment_id bigint, p_date timestamp with time zone, p_observations text, p_action_plan text, p_follow_up date, p_status text, p_level text) TO postgres;
GRANT EXECUTE ON FUNCTION public.mentoring_record_session(p_assignment_id bigint, p_date timestamp with time zone, p_observations text, p_action_plan text, p_follow_up date, p_status text, p_level text) TO service_role;
GRANT EXECUTE ON FUNCTION public.mentoring_sessions(p_assignment_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mentoring_sessions(p_assignment_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.mentoring_sessions(p_assignment_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.mentoring_update_session(p_session_id bigint, p_date timestamp with time zone, p_observations text, p_action_plan text, p_follow_up date, p_status text, p_level text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mentoring_update_session(p_session_id bigint, p_date timestamp with time zone, p_observations text, p_action_plan text, p_follow_up date, p_status text, p_level text) TO postgres;
GRANT EXECUTE ON FUNCTION public.mentoring_update_session(p_session_id bigint, p_date timestamp with time zone, p_observations text, p_action_plan text, p_follow_up date, p_status text, p_level text) TO service_role;
GRANT DELETE ON TABLE public.metric_type TO authenticated;
GRANT INSERT ON TABLE public.metric_type TO authenticated;
GRANT UPDATE ON TABLE public.metric_type TO authenticated;
GRANT DELETE ON TABLE public.metric_type TO postgres;
GRANT INSERT ON TABLE public.metric_type TO postgres;
GRANT MAINTAIN ON TABLE public.metric_type TO postgres;
GRANT REFERENCES ON TABLE public.metric_type TO postgres;
GRANT SELECT ON TABLE public.metric_type TO postgres;
GRANT TRIGGER ON TABLE public.metric_type TO postgres;
GRANT TRUNCATE ON TABLE public.metric_type TO postgres;
GRANT UPDATE ON TABLE public.metric_type TO postgres;
GRANT DELETE ON TABLE public.metric_type TO service_role;
GRANT INSERT ON TABLE public.metric_type TO service_role;
GRANT MAINTAIN ON TABLE public.metric_type TO service_role;
GRANT REFERENCES ON TABLE public.metric_type TO service_role;
GRANT SELECT ON TABLE public.metric_type TO service_role;
GRANT TRIGGER ON TABLE public.metric_type TO service_role;
GRANT TRUNCATE ON TABLE public.metric_type TO service_role;
GRANT UPDATE ON TABLE public.metric_type TO service_role;
GRANT SELECT ON TABLE public.metric_type_metric_type_id_seq TO postgres;
GRANT UPDATE ON TABLE public.metric_type_metric_type_id_seq TO postgres;
GRANT USAGE ON TABLE public.metric_type_metric_type_id_seq TO postgres;
GRANT SELECT ON TABLE public.metric_type_metric_type_id_seq TO service_role;
GRANT UPDATE ON TABLE public.metric_type_metric_type_id_seq TO service_role;
GRANT USAGE ON TABLE public.metric_type_metric_type_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.mfa_recovery_generate() TO authenticated;
GRANT EXECUTE ON FUNCTION public.mfa_recovery_generate() TO postgres;
GRANT EXECUTE ON FUNCTION public.mfa_recovery_generate() TO service_role;
GRANT EXECUTE ON FUNCTION public.mfa_recovery_status() TO authenticated;
GRANT EXECUTE ON FUNCTION public.mfa_recovery_status() TO postgres;
GRANT EXECUTE ON FUNCTION public.mfa_recovery_status() TO service_role;
GRANT EXECUTE ON FUNCTION public.mfa_recovery_use(p_code text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mfa_recovery_use(p_code text) TO postgres;
GRANT EXECUTE ON FUNCTION public.mfa_recovery_use(p_code text) TO service_role;
GRANT EXECUTE ON FUNCTION public.mfa_sync() TO authenticated;
GRANT EXECUTE ON FUNCTION public.mfa_sync() TO postgres;
GRANT EXECUTE ON FUNCTION public.mfa_sync() TO service_role;
GRANT EXECUTE ON FUNCTION public.my_context() TO authenticated;
GRANT EXECUTE ON FUNCTION public.my_context() TO postgres;
GRANT EXECUTE ON FUNCTION public.my_context() TO service_role;
GRANT EXECUTE ON FUNCTION public.my_dashboard() TO authenticated;
GRANT EXECUTE ON FUNCTION public.my_dashboard() TO postgres;
GRANT EXECUTE ON FUNCTION public.my_dashboard() TO service_role;
GRANT EXECUTE ON FUNCTION public.my_notification_count() TO authenticated;
GRANT EXECUTE ON FUNCTION public.my_notification_count() TO postgres;
GRANT EXECUTE ON FUNCTION public.my_notification_count() TO service_role;
GRANT EXECUTE ON FUNCTION public.my_notifications(p_limit integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.my_notifications(p_limit integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.my_notifications(p_limit integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.my_profile() TO authenticated;
GRANT EXECUTE ON FUNCTION public.my_profile() TO postgres;
GRANT EXECUTE ON FUNCTION public.my_profile() TO service_role;
GRANT EXECUTE ON FUNCTION public.my_profile_update(p jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.my_profile_update(p jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.my_profile_update(p jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.my_recent_logins(p_limit integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.my_recent_logins(p_limit integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.my_recent_logins(p_limit integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.my_results() TO authenticated;
GRANT EXECUTE ON FUNCTION public.my_results() TO postgres;
GRANT EXECUTE ON FUNCTION public.my_results() TO service_role;
GRANT EXECUTE ON FUNCTION public.notification_dismiss(p_key text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.notification_dismiss(p_key text) TO postgres;
GRANT EXECUTE ON FUNCTION public.notification_dismiss(p_key text) TO service_role;
GRANT EXECUTE ON FUNCTION public.notification_dismiss_all() TO authenticated;
GRANT EXECUTE ON FUNCTION public.notification_dismiss_all() TO postgres;
GRANT EXECUTE ON FUNCTION public.notification_dismiss_all() TO service_role;
GRANT EXECUTE ON FUNCTION public.offering_generate_courses(p_programme_term_offering_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.offering_generate_courses(p_programme_term_offering_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.offering_generate_courses(p_programme_term_offering_id bigint) TO service_role;
GRANT DELETE ON TABLE public.organization_type TO authenticated;
GRANT INSERT ON TABLE public.organization_type TO authenticated;
GRANT UPDATE ON TABLE public.organization_type TO authenticated;
GRANT DELETE ON TABLE public.organization_type TO postgres;
GRANT INSERT ON TABLE public.organization_type TO postgres;
GRANT MAINTAIN ON TABLE public.organization_type TO postgres;
GRANT REFERENCES ON TABLE public.organization_type TO postgres;
GRANT SELECT ON TABLE public.organization_type TO postgres;
GRANT TRIGGER ON TABLE public.organization_type TO postgres;
GRANT TRUNCATE ON TABLE public.organization_type TO postgres;
GRANT UPDATE ON TABLE public.organization_type TO postgres;
GRANT DELETE ON TABLE public.organization_type TO service_role;
GRANT INSERT ON TABLE public.organization_type TO service_role;
GRANT MAINTAIN ON TABLE public.organization_type TO service_role;
GRANT REFERENCES ON TABLE public.organization_type TO service_role;
GRANT SELECT ON TABLE public.organization_type TO service_role;
GRANT TRIGGER ON TABLE public.organization_type TO service_role;
GRANT TRUNCATE ON TABLE public.organization_type TO service_role;
GRANT UPDATE ON TABLE public.organization_type TO service_role;
GRANT SELECT ON TABLE public.organization_type_organization_type_id_seq TO postgres;
GRANT UPDATE ON TABLE public.organization_type_organization_type_id_seq TO postgres;
GRANT USAGE ON TABLE public.organization_type_organization_type_id_seq TO postgres;
GRANT SELECT ON TABLE public.organization_type_organization_type_id_seq TO service_role;
GRANT UPDATE ON TABLE public.organization_type_organization_type_id_seq TO service_role;
GRANT USAGE ON TABLE public.organization_type_organization_type_id_seq TO service_role;
GRANT DELETE ON TABLE public.organizer TO authenticated;
GRANT INSERT ON TABLE public.organizer TO authenticated;
GRANT UPDATE ON TABLE public.organizer TO authenticated;
GRANT DELETE ON TABLE public.organizer TO postgres;
GRANT INSERT ON TABLE public.organizer TO postgres;
GRANT MAINTAIN ON TABLE public.organizer TO postgres;
GRANT REFERENCES ON TABLE public.organizer TO postgres;
GRANT SELECT ON TABLE public.organizer TO postgres;
GRANT TRIGGER ON TABLE public.organizer TO postgres;
GRANT TRUNCATE ON TABLE public.organizer TO postgres;
GRANT UPDATE ON TABLE public.organizer TO postgres;
GRANT DELETE ON TABLE public.organizer TO service_role;
GRANT INSERT ON TABLE public.organizer TO service_role;
GRANT MAINTAIN ON TABLE public.organizer TO service_role;
GRANT REFERENCES ON TABLE public.organizer TO service_role;
GRANT SELECT ON TABLE public.organizer TO service_role;
GRANT TRIGGER ON TABLE public.organizer TO service_role;
GRANT TRUNCATE ON TABLE public.organizer TO service_role;
GRANT UPDATE ON TABLE public.organizer TO service_role;
GRANT SELECT ON TABLE public.organizer_organizer_id_seq TO postgres;
GRANT UPDATE ON TABLE public.organizer_organizer_id_seq TO postgres;
GRANT USAGE ON TABLE public.organizer_organizer_id_seq TO postgres;
GRANT SELECT ON TABLE public.organizer_organizer_id_seq TO service_role;
GRANT UPDATE ON TABLE public.organizer_organizer_id_seq TO service_role;
GRANT USAGE ON TABLE public.organizer_organizer_id_seq TO service_role;
GRANT DELETE ON TABLE public.participation_level TO authenticated;
GRANT INSERT ON TABLE public.participation_level TO authenticated;
GRANT UPDATE ON TABLE public.participation_level TO authenticated;
GRANT DELETE ON TABLE public.participation_level TO postgres;
GRANT INSERT ON TABLE public.participation_level TO postgres;
GRANT MAINTAIN ON TABLE public.participation_level TO postgres;
GRANT REFERENCES ON TABLE public.participation_level TO postgres;
GRANT SELECT ON TABLE public.participation_level TO postgres;
GRANT TRIGGER ON TABLE public.participation_level TO postgres;
GRANT TRUNCATE ON TABLE public.participation_level TO postgres;
GRANT UPDATE ON TABLE public.participation_level TO postgres;
GRANT DELETE ON TABLE public.participation_level TO service_role;
GRANT INSERT ON TABLE public.participation_level TO service_role;
GRANT MAINTAIN ON TABLE public.participation_level TO service_role;
GRANT REFERENCES ON TABLE public.participation_level TO service_role;
GRANT SELECT ON TABLE public.participation_level TO service_role;
GRANT TRIGGER ON TABLE public.participation_level TO service_role;
GRANT TRUNCATE ON TABLE public.participation_level TO service_role;
GRANT UPDATE ON TABLE public.participation_level TO service_role;
GRANT SELECT ON TABLE public.participation_level_participation_level_id_seq TO postgres;
GRANT UPDATE ON TABLE public.participation_level_participation_level_id_seq TO postgres;
GRANT USAGE ON TABLE public.participation_level_participation_level_id_seq TO postgres;
GRANT SELECT ON TABLE public.participation_level_participation_level_id_seq TO service_role;
GRANT UPDATE ON TABLE public.participation_level_participation_level_id_seq TO service_role;
GRANT USAGE ON TABLE public.participation_level_participation_level_id_seq TO service_role;
GRANT DELETE ON TABLE public.password_history TO postgres;
GRANT INSERT ON TABLE public.password_history TO postgres;
GRANT MAINTAIN ON TABLE public.password_history TO postgres;
GRANT REFERENCES ON TABLE public.password_history TO postgres;
GRANT SELECT ON TABLE public.password_history TO postgres;
GRANT TRIGGER ON TABLE public.password_history TO postgres;
GRANT TRUNCATE ON TABLE public.password_history TO postgres;
GRANT UPDATE ON TABLE public.password_history TO postgres;
GRANT DELETE ON TABLE public.password_history TO service_role;
GRANT INSERT ON TABLE public.password_history TO service_role;
GRANT MAINTAIN ON TABLE public.password_history TO service_role;
GRANT REFERENCES ON TABLE public.password_history TO service_role;
GRANT SELECT ON TABLE public.password_history TO service_role;
GRANT TRIGGER ON TABLE public.password_history TO service_role;
GRANT TRUNCATE ON TABLE public.password_history TO service_role;
GRANT UPDATE ON TABLE public.password_history TO service_role;
GRANT SELECT ON TABLE public.password_history_password_history_id_seq TO postgres;
GRANT UPDATE ON TABLE public.password_history_password_history_id_seq TO postgres;
GRANT USAGE ON TABLE public.password_history_password_history_id_seq TO postgres;
GRANT SELECT ON TABLE public.password_history_password_history_id_seq TO service_role;
GRANT UPDATE ON TABLE public.password_history_password_history_id_seq TO service_role;
GRANT USAGE ON TABLE public.password_history_password_history_id_seq TO service_role;
GRANT DELETE ON TABLE public.payment_allocation TO postgres;
GRANT INSERT ON TABLE public.payment_allocation TO postgres;
GRANT MAINTAIN ON TABLE public.payment_allocation TO postgres;
GRANT REFERENCES ON TABLE public.payment_allocation TO postgres;
GRANT SELECT ON TABLE public.payment_allocation TO postgres;
GRANT TRIGGER ON TABLE public.payment_allocation TO postgres;
GRANT TRUNCATE ON TABLE public.payment_allocation TO postgres;
GRANT UPDATE ON TABLE public.payment_allocation TO postgres;
GRANT DELETE ON TABLE public.payment_allocation TO service_role;
GRANT INSERT ON TABLE public.payment_allocation TO service_role;
GRANT MAINTAIN ON TABLE public.payment_allocation TO service_role;
GRANT REFERENCES ON TABLE public.payment_allocation TO service_role;
GRANT SELECT ON TABLE public.payment_allocation TO service_role;
GRANT TRIGGER ON TABLE public.payment_allocation TO service_role;
GRANT TRUNCATE ON TABLE public.payment_allocation TO service_role;
GRANT UPDATE ON TABLE public.payment_allocation TO service_role;
GRANT SELECT ON TABLE public.payment_allocation_payment_allocation_id_seq TO postgres;
GRANT UPDATE ON TABLE public.payment_allocation_payment_allocation_id_seq TO postgres;
GRANT USAGE ON TABLE public.payment_allocation_payment_allocation_id_seq TO postgres;
GRANT SELECT ON TABLE public.payment_allocation_payment_allocation_id_seq TO service_role;
GRANT UPDATE ON TABLE public.payment_allocation_payment_allocation_id_seq TO service_role;
GRANT USAGE ON TABLE public.payment_allocation_payment_allocation_id_seq TO service_role;
GRANT DELETE ON TABLE public.payment_mode TO postgres;
GRANT INSERT ON TABLE public.payment_mode TO postgres;
GRANT MAINTAIN ON TABLE public.payment_mode TO postgres;
GRANT REFERENCES ON TABLE public.payment_mode TO postgres;
GRANT SELECT ON TABLE public.payment_mode TO postgres;
GRANT TRIGGER ON TABLE public.payment_mode TO postgres;
GRANT TRUNCATE ON TABLE public.payment_mode TO postgres;
GRANT UPDATE ON TABLE public.payment_mode TO postgres;
GRANT DELETE ON TABLE public.payment_mode TO service_role;
GRANT INSERT ON TABLE public.payment_mode TO service_role;
GRANT MAINTAIN ON TABLE public.payment_mode TO service_role;
GRANT REFERENCES ON TABLE public.payment_mode TO service_role;
GRANT SELECT ON TABLE public.payment_mode TO service_role;
GRANT TRIGGER ON TABLE public.payment_mode TO service_role;
GRANT TRUNCATE ON TABLE public.payment_mode TO service_role;
GRANT UPDATE ON TABLE public.payment_mode TO service_role;
GRANT SELECT ON TABLE public.payment_mode_payment_mode_id_seq TO postgres;
GRANT UPDATE ON TABLE public.payment_mode_payment_mode_id_seq TO postgres;
GRANT USAGE ON TABLE public.payment_mode_payment_mode_id_seq TO postgres;
GRANT SELECT ON TABLE public.payment_mode_payment_mode_id_seq TO service_role;
GRANT UPDATE ON TABLE public.payment_mode_payment_mode_id_seq TO service_role;
GRANT USAGE ON TABLE public.payment_mode_payment_mode_id_seq TO service_role;
GRANT DELETE ON TABLE public.payment_transaction TO postgres;
GRANT INSERT ON TABLE public.payment_transaction TO postgres;
GRANT MAINTAIN ON TABLE public.payment_transaction TO postgres;
GRANT REFERENCES ON TABLE public.payment_transaction TO postgres;
GRANT SELECT ON TABLE public.payment_transaction TO postgres;
GRANT TRIGGER ON TABLE public.payment_transaction TO postgres;
GRANT TRUNCATE ON TABLE public.payment_transaction TO postgres;
GRANT UPDATE ON TABLE public.payment_transaction TO postgres;
GRANT DELETE ON TABLE public.payment_transaction TO service_role;
GRANT INSERT ON TABLE public.payment_transaction TO service_role;
GRANT MAINTAIN ON TABLE public.payment_transaction TO service_role;
GRANT REFERENCES ON TABLE public.payment_transaction TO service_role;
GRANT SELECT ON TABLE public.payment_transaction TO service_role;
GRANT TRIGGER ON TABLE public.payment_transaction TO service_role;
GRANT TRUNCATE ON TABLE public.payment_transaction TO service_role;
GRANT UPDATE ON TABLE public.payment_transaction TO service_role;
GRANT SELECT ON TABLE public.payment_transaction_payment_transaction_id_seq TO postgres;
GRANT UPDATE ON TABLE public.payment_transaction_payment_transaction_id_seq TO postgres;
GRANT USAGE ON TABLE public.payment_transaction_payment_transaction_id_seq TO postgres;
GRANT SELECT ON TABLE public.payment_transaction_payment_transaction_id_seq TO service_role;
GRANT UPDATE ON TABLE public.payment_transaction_payment_transaction_id_seq TO service_role;
GRANT USAGE ON TABLE public.payment_transaction_payment_transaction_id_seq TO service_role;
GRANT DELETE ON TABLE public.permission TO postgres;
GRANT INSERT ON TABLE public.permission TO postgres;
GRANT MAINTAIN ON TABLE public.permission TO postgres;
GRANT REFERENCES ON TABLE public.permission TO postgres;
GRANT SELECT ON TABLE public.permission TO postgres;
GRANT TRIGGER ON TABLE public.permission TO postgres;
GRANT TRUNCATE ON TABLE public.permission TO postgres;
GRANT UPDATE ON TABLE public.permission TO postgres;
GRANT DELETE ON TABLE public.permission TO service_role;
GRANT INSERT ON TABLE public.permission TO service_role;
GRANT MAINTAIN ON TABLE public.permission TO service_role;
GRANT REFERENCES ON TABLE public.permission TO service_role;
GRANT SELECT ON TABLE public.permission TO service_role;
GRANT TRIGGER ON TABLE public.permission TO service_role;
GRANT TRUNCATE ON TABLE public.permission TO service_role;
GRANT UPDATE ON TABLE public.permission TO service_role;
GRANT SELECT ON TABLE public.permission_permission_id_seq TO postgres;
GRANT UPDATE ON TABLE public.permission_permission_id_seq TO postgres;
GRANT USAGE ON TABLE public.permission_permission_id_seq TO postgres;
GRANT SELECT ON TABLE public.permission_permission_id_seq TO service_role;
GRANT UPDATE ON TABLE public.permission_permission_id_seq TO service_role;
GRANT USAGE ON TABLE public.permission_permission_id_seq TO service_role;
GRANT DELETE ON TABLE public.previous_organization TO authenticated;
GRANT INSERT ON TABLE public.previous_organization TO authenticated;
GRANT UPDATE ON TABLE public.previous_organization TO authenticated;
GRANT DELETE ON TABLE public.previous_organization TO postgres;
GRANT INSERT ON TABLE public.previous_organization TO postgres;
GRANT MAINTAIN ON TABLE public.previous_organization TO postgres;
GRANT REFERENCES ON TABLE public.previous_organization TO postgres;
GRANT SELECT ON TABLE public.previous_organization TO postgres;
GRANT TRIGGER ON TABLE public.previous_organization TO postgres;
GRANT TRUNCATE ON TABLE public.previous_organization TO postgres;
GRANT UPDATE ON TABLE public.previous_organization TO postgres;
GRANT DELETE ON TABLE public.previous_organization TO service_role;
GRANT INSERT ON TABLE public.previous_organization TO service_role;
GRANT MAINTAIN ON TABLE public.previous_organization TO service_role;
GRANT REFERENCES ON TABLE public.previous_organization TO service_role;
GRANT SELECT ON TABLE public.previous_organization TO service_role;
GRANT TRIGGER ON TABLE public.previous_organization TO service_role;
GRANT TRUNCATE ON TABLE public.previous_organization TO service_role;
GRANT UPDATE ON TABLE public.previous_organization TO service_role;
GRANT SELECT ON TABLE public.previous_organization_previous_organization_id_seq TO postgres;
GRANT UPDATE ON TABLE public.previous_organization_previous_organization_id_seq TO postgres;
GRANT USAGE ON TABLE public.previous_organization_previous_organization_id_seq TO postgres;
GRANT SELECT ON TABLE public.previous_organization_previous_organization_id_seq TO service_role;
GRANT UPDATE ON TABLE public.previous_organization_previous_organization_id_seq TO service_role;
GRANT USAGE ON TABLE public.previous_organization_previous_organization_id_seq TO service_role;
GRANT DELETE ON TABLE public.previous_organization_type TO authenticated;
GRANT INSERT ON TABLE public.previous_organization_type TO authenticated;
GRANT UPDATE ON TABLE public.previous_organization_type TO authenticated;
GRANT DELETE ON TABLE public.previous_organization_type TO postgres;
GRANT INSERT ON TABLE public.previous_organization_type TO postgres;
GRANT MAINTAIN ON TABLE public.previous_organization_type TO postgres;
GRANT REFERENCES ON TABLE public.previous_organization_type TO postgres;
GRANT SELECT ON TABLE public.previous_organization_type TO postgres;
GRANT TRIGGER ON TABLE public.previous_organization_type TO postgres;
GRANT TRUNCATE ON TABLE public.previous_organization_type TO postgres;
GRANT UPDATE ON TABLE public.previous_organization_type TO postgres;
GRANT DELETE ON TABLE public.previous_organization_type TO service_role;
GRANT INSERT ON TABLE public.previous_organization_type TO service_role;
GRANT MAINTAIN ON TABLE public.previous_organization_type TO service_role;
GRANT REFERENCES ON TABLE public.previous_organization_type TO service_role;
GRANT SELECT ON TABLE public.previous_organization_type TO service_role;
GRANT TRIGGER ON TABLE public.previous_organization_type TO service_role;
GRANT TRUNCATE ON TABLE public.previous_organization_type TO service_role;
GRANT UPDATE ON TABLE public.previous_organization_type TO service_role;
GRANT SELECT ON TABLE public.previous_organization_type_previous_organization_type_id_seq TO postgres;
GRANT UPDATE ON TABLE public.previous_organization_type_previous_organization_type_id_seq TO postgres;
GRANT USAGE ON TABLE public.previous_organization_type_previous_organization_type_id_seq TO postgres;
GRANT SELECT ON TABLE public.previous_organization_type_previous_organization_type_id_seq TO service_role;
GRANT UPDATE ON TABLE public.previous_organization_type_previous_organization_type_id_seq TO service_role;
GRANT USAGE ON TABLE public.previous_organization_type_previous_organization_type_id_seq TO service_role;
GRANT SELECT ON TABLE public.professional_contribution_typ_professional_contribution_typ_seq TO postgres;
GRANT UPDATE ON TABLE public.professional_contribution_typ_professional_contribution_typ_seq TO postgres;
GRANT USAGE ON TABLE public.professional_contribution_typ_professional_contribution_typ_seq TO postgres;
GRANT SELECT ON TABLE public.professional_contribution_typ_professional_contribution_typ_seq TO service_role;
GRANT UPDATE ON TABLE public.professional_contribution_typ_professional_contribution_typ_seq TO service_role;
GRANT USAGE ON TABLE public.professional_contribution_typ_professional_contribution_typ_seq TO service_role;
GRANT DELETE ON TABLE public.professional_contribution_type TO authenticated;
GRANT INSERT ON TABLE public.professional_contribution_type TO authenticated;
GRANT UPDATE ON TABLE public.professional_contribution_type TO authenticated;
GRANT DELETE ON TABLE public.professional_contribution_type TO postgres;
GRANT INSERT ON TABLE public.professional_contribution_type TO postgres;
GRANT MAINTAIN ON TABLE public.professional_contribution_type TO postgres;
GRANT REFERENCES ON TABLE public.professional_contribution_type TO postgres;
GRANT SELECT ON TABLE public.professional_contribution_type TO postgres;
GRANT TRIGGER ON TABLE public.professional_contribution_type TO postgres;
GRANT TRUNCATE ON TABLE public.professional_contribution_type TO postgres;
GRANT UPDATE ON TABLE public.professional_contribution_type TO postgres;
GRANT DELETE ON TABLE public.professional_contribution_type TO service_role;
GRANT INSERT ON TABLE public.professional_contribution_type TO service_role;
GRANT MAINTAIN ON TABLE public.professional_contribution_type TO service_role;
GRANT REFERENCES ON TABLE public.professional_contribution_type TO service_role;
GRANT SELECT ON TABLE public.professional_contribution_type TO service_role;
GRANT TRIGGER ON TABLE public.professional_contribution_type TO service_role;
GRANT TRUNCATE ON TABLE public.professional_contribution_type TO service_role;
GRANT UPDATE ON TABLE public.professional_contribution_type TO service_role;
GRANT DELETE ON TABLE public.professional_development_activity TO postgres;
GRANT INSERT ON TABLE public.professional_development_activity TO postgres;
GRANT MAINTAIN ON TABLE public.professional_development_activity TO postgres;
GRANT REFERENCES ON TABLE public.professional_development_activity TO postgres;
GRANT SELECT ON TABLE public.professional_development_activity TO postgres;
GRANT TRIGGER ON TABLE public.professional_development_activity TO postgres;
GRANT TRUNCATE ON TABLE public.professional_development_activity TO postgres;
GRANT UPDATE ON TABLE public.professional_development_activity TO postgres;
GRANT DELETE ON TABLE public.professional_development_activity TO service_role;
GRANT INSERT ON TABLE public.professional_development_activity TO service_role;
GRANT MAINTAIN ON TABLE public.professional_development_activity TO service_role;
GRANT REFERENCES ON TABLE public.professional_development_activity TO service_role;
GRANT SELECT ON TABLE public.professional_development_activity TO service_role;
GRANT TRIGGER ON TABLE public.professional_development_activity TO service_role;
GRANT TRUNCATE ON TABLE public.professional_development_activity TO service_role;
GRANT UPDATE ON TABLE public.professional_development_activity TO service_role;
GRANT DELETE ON TABLE public.programme TO authenticated;
GRANT INSERT ON TABLE public.programme TO authenticated;
GRANT UPDATE ON TABLE public.programme TO authenticated;
GRANT DELETE ON TABLE public.programme TO postgres;
GRANT INSERT ON TABLE public.programme TO postgres;
GRANT MAINTAIN ON TABLE public.programme TO postgres;
GRANT REFERENCES ON TABLE public.programme TO postgres;
GRANT SELECT ON TABLE public.programme TO postgres;
GRANT TRIGGER ON TABLE public.programme TO postgres;
GRANT TRUNCATE ON TABLE public.programme TO postgres;
GRANT UPDATE ON TABLE public.programme TO postgres;
GRANT DELETE ON TABLE public.programme TO service_role;
GRANT INSERT ON TABLE public.programme TO service_role;
GRANT MAINTAIN ON TABLE public.programme TO service_role;
GRANT REFERENCES ON TABLE public.programme TO service_role;
GRANT SELECT ON TABLE public.programme TO service_role;
GRANT TRIGGER ON TABLE public.programme TO service_role;
GRANT TRUNCATE ON TABLE public.programme TO service_role;
GRANT UPDATE ON TABLE public.programme TO service_role;
GRANT SELECT ON TABLE public.programme_programme_id_seq TO postgres;
GRANT UPDATE ON TABLE public.programme_programme_id_seq TO postgres;
GRANT USAGE ON TABLE public.programme_programme_id_seq TO postgres;
GRANT SELECT ON TABLE public.programme_programme_id_seq TO service_role;
GRANT UPDATE ON TABLE public.programme_programme_id_seq TO service_role;
GRANT USAGE ON TABLE public.programme_programme_id_seq TO service_role;
GRANT DELETE ON TABLE public.programme_specialization TO authenticated;
GRANT INSERT ON TABLE public.programme_specialization TO authenticated;
GRANT UPDATE ON TABLE public.programme_specialization TO authenticated;
GRANT DELETE ON TABLE public.programme_specialization TO postgres;
GRANT INSERT ON TABLE public.programme_specialization TO postgres;
GRANT MAINTAIN ON TABLE public.programme_specialization TO postgres;
GRANT REFERENCES ON TABLE public.programme_specialization TO postgres;
GRANT SELECT ON TABLE public.programme_specialization TO postgres;
GRANT TRIGGER ON TABLE public.programme_specialization TO postgres;
GRANT TRUNCATE ON TABLE public.programme_specialization TO postgres;
GRANT UPDATE ON TABLE public.programme_specialization TO postgres;
GRANT DELETE ON TABLE public.programme_specialization TO service_role;
GRANT INSERT ON TABLE public.programme_specialization TO service_role;
GRANT MAINTAIN ON TABLE public.programme_specialization TO service_role;
GRANT REFERENCES ON TABLE public.programme_specialization TO service_role;
GRANT SELECT ON TABLE public.programme_specialization TO service_role;
GRANT TRIGGER ON TABLE public.programme_specialization TO service_role;
GRANT TRUNCATE ON TABLE public.programme_specialization TO service_role;
GRANT UPDATE ON TABLE public.programme_specialization TO service_role;
GRANT SELECT ON TABLE public.programme_specialization_specialization_id_seq TO postgres;
GRANT UPDATE ON TABLE public.programme_specialization_specialization_id_seq TO postgres;
GRANT USAGE ON TABLE public.programme_specialization_specialization_id_seq TO postgres;
GRANT SELECT ON TABLE public.programme_specialization_specialization_id_seq TO service_role;
GRANT UPDATE ON TABLE public.programme_specialization_specialization_id_seq TO service_role;
GRANT USAGE ON TABLE public.programme_specialization_specialization_id_seq TO service_role;
GRANT DELETE ON TABLE public.programme_term_offering TO authenticated;
GRANT INSERT ON TABLE public.programme_term_offering TO authenticated;
GRANT UPDATE ON TABLE public.programme_term_offering TO authenticated;
GRANT DELETE ON TABLE public.programme_term_offering TO postgres;
GRANT INSERT ON TABLE public.programme_term_offering TO postgres;
GRANT MAINTAIN ON TABLE public.programme_term_offering TO postgres;
GRANT REFERENCES ON TABLE public.programme_term_offering TO postgres;
GRANT SELECT ON TABLE public.programme_term_offering TO postgres;
GRANT TRIGGER ON TABLE public.programme_term_offering TO postgres;
GRANT TRUNCATE ON TABLE public.programme_term_offering TO postgres;
GRANT UPDATE ON TABLE public.programme_term_offering TO postgres;
GRANT DELETE ON TABLE public.programme_term_offering TO service_role;
GRANT INSERT ON TABLE public.programme_term_offering TO service_role;
GRANT MAINTAIN ON TABLE public.programme_term_offering TO service_role;
GRANT REFERENCES ON TABLE public.programme_term_offering TO service_role;
GRANT SELECT ON TABLE public.programme_term_offering TO service_role;
GRANT TRIGGER ON TABLE public.programme_term_offering TO service_role;
GRANT TRUNCATE ON TABLE public.programme_term_offering TO service_role;
GRANT UPDATE ON TABLE public.programme_term_offering TO service_role;
GRANT SELECT ON TABLE public.programme_term_offering_programme_term_offering_id_seq TO postgres;
GRANT UPDATE ON TABLE public.programme_term_offering_programme_term_offering_id_seq TO postgres;
GRANT USAGE ON TABLE public.programme_term_offering_programme_term_offering_id_seq TO postgres;
GRANT SELECT ON TABLE public.programme_term_offering_programme_term_offering_id_seq TO service_role;
GRANT UPDATE ON TABLE public.programme_term_offering_programme_term_offering_id_seq TO service_role;
GRANT USAGE ON TABLE public.programme_term_offering_programme_term_offering_id_seq TO service_role;
GRANT USAGE ON SCHEMA public TO PUBLIC;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT CREATE ON SCHEMA public TO pg_database_owner;
GRANT USAGE ON SCHEMA public TO pg_database_owner;
GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO service_role;
GRANT DELETE ON TABLE public.publication_type TO authenticated;
GRANT INSERT ON TABLE public.publication_type TO authenticated;
GRANT UPDATE ON TABLE public.publication_type TO authenticated;
GRANT DELETE ON TABLE public.publication_type TO postgres;
GRANT INSERT ON TABLE public.publication_type TO postgres;
GRANT MAINTAIN ON TABLE public.publication_type TO postgres;
GRANT REFERENCES ON TABLE public.publication_type TO postgres;
GRANT SELECT ON TABLE public.publication_type TO postgres;
GRANT TRIGGER ON TABLE public.publication_type TO postgres;
GRANT TRUNCATE ON TABLE public.publication_type TO postgres;
GRANT UPDATE ON TABLE public.publication_type TO postgres;
GRANT DELETE ON TABLE public.publication_type TO service_role;
GRANT INSERT ON TABLE public.publication_type TO service_role;
GRANT MAINTAIN ON TABLE public.publication_type TO service_role;
GRANT REFERENCES ON TABLE public.publication_type TO service_role;
GRANT SELECT ON TABLE public.publication_type TO service_role;
GRANT TRIGGER ON TABLE public.publication_type TO service_role;
GRANT TRUNCATE ON TABLE public.publication_type TO service_role;
GRANT UPDATE ON TABLE public.publication_type TO service_role;
GRANT SELECT ON TABLE public.publication_type_publication_type_id_seq TO postgres;
GRANT UPDATE ON TABLE public.publication_type_publication_type_id_seq TO postgres;
GRANT USAGE ON TABLE public.publication_type_publication_type_id_seq TO postgres;
GRANT SELECT ON TABLE public.publication_type_publication_type_id_seq TO service_role;
GRANT UPDATE ON TABLE public.publication_type_publication_type_id_seq TO service_role;
GRANT USAGE ON TABLE public.publication_type_publication_type_id_seq TO service_role;
GRANT DELETE ON TABLE public.publisher TO authenticated;
GRANT INSERT ON TABLE public.publisher TO authenticated;
GRANT UPDATE ON TABLE public.publisher TO authenticated;
GRANT DELETE ON TABLE public.publisher TO postgres;
GRANT INSERT ON TABLE public.publisher TO postgres;
GRANT MAINTAIN ON TABLE public.publisher TO postgres;
GRANT REFERENCES ON TABLE public.publisher TO postgres;
GRANT SELECT ON TABLE public.publisher TO postgres;
GRANT TRIGGER ON TABLE public.publisher TO postgres;
GRANT TRUNCATE ON TABLE public.publisher TO postgres;
GRANT UPDATE ON TABLE public.publisher TO postgres;
GRANT DELETE ON TABLE public.publisher TO service_role;
GRANT INSERT ON TABLE public.publisher TO service_role;
GRANT MAINTAIN ON TABLE public.publisher TO service_role;
GRANT REFERENCES ON TABLE public.publisher TO service_role;
GRANT SELECT ON TABLE public.publisher TO service_role;
GRANT TRIGGER ON TABLE public.publisher TO service_role;
GRANT TRUNCATE ON TABLE public.publisher TO service_role;
GRANT UPDATE ON TABLE public.publisher TO service_role;
GRANT SELECT ON TABLE public.publisher_publisher_id_seq TO postgres;
GRANT UPDATE ON TABLE public.publisher_publisher_id_seq TO postgres;
GRANT USAGE ON TABLE public.publisher_publisher_id_seq TO postgres;
GRANT SELECT ON TABLE public.publisher_publisher_id_seq TO service_role;
GRANT UPDATE ON TABLE public.publisher_publisher_id_seq TO service_role;
GRANT USAGE ON TABLE public.publisher_publisher_id_seq TO service_role;
GRANT DELETE ON TABLE public.qualification_level TO authenticated;
GRANT INSERT ON TABLE public.qualification_level TO authenticated;
GRANT UPDATE ON TABLE public.qualification_level TO authenticated;
GRANT DELETE ON TABLE public.qualification_level TO postgres;
GRANT INSERT ON TABLE public.qualification_level TO postgres;
GRANT MAINTAIN ON TABLE public.qualification_level TO postgres;
GRANT REFERENCES ON TABLE public.qualification_level TO postgres;
GRANT SELECT ON TABLE public.qualification_level TO postgres;
GRANT TRIGGER ON TABLE public.qualification_level TO postgres;
GRANT TRUNCATE ON TABLE public.qualification_level TO postgres;
GRANT UPDATE ON TABLE public.qualification_level TO postgres;
GRANT DELETE ON TABLE public.qualification_level TO service_role;
GRANT INSERT ON TABLE public.qualification_level TO service_role;
GRANT MAINTAIN ON TABLE public.qualification_level TO service_role;
GRANT REFERENCES ON TABLE public.qualification_level TO service_role;
GRANT SELECT ON TABLE public.qualification_level TO service_role;
GRANT TRIGGER ON TABLE public.qualification_level TO service_role;
GRANT TRUNCATE ON TABLE public.qualification_level TO service_role;
GRANT UPDATE ON TABLE public.qualification_level TO service_role;
GRANT SELECT ON TABLE public.qualification_level_qualification_level_id_seq TO postgres;
GRANT UPDATE ON TABLE public.qualification_level_qualification_level_id_seq TO postgres;
GRANT USAGE ON TABLE public.qualification_level_qualification_level_id_seq TO postgres;
GRANT SELECT ON TABLE public.qualification_level_qualification_level_id_seq TO service_role;
GRANT UPDATE ON TABLE public.qualification_level_qualification_level_id_seq TO service_role;
GRANT USAGE ON TABLE public.qualification_level_qualification_level_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.record_sections(p_kind text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_sections(p_kind text) TO postgres;
GRANT EXECUTE ON FUNCTION public.record_sections(p_kind text) TO service_role;
GRANT EXECUTE ON FUNCTION public.ref_delete(p_table text, p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ref_delete(p_table text, p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.ref_delete(p_table text, p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.ref_list() TO authenticated;
GRANT EXECUTE ON FUNCTION public.ref_list() TO postgres;
GRANT EXECUTE ON FUNCTION public.ref_list() TO service_role;
GRANT EXECUTE ON FUNCTION public.ref_rows(p_table text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ref_rows(p_table text) TO postgres;
GRANT EXECUTE ON FUNCTION public.ref_rows(p_table text) TO service_role;
GRANT EXECUTE ON FUNCTION public.ref_save(p_table text, p_id bigint, p jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ref_save(p_table text, p_id bigint, p jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.ref_save(p_table text, p_id bigint, p jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.ref_schema(p_table text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ref_schema(p_table text) TO postgres;
GRANT EXECUTE ON FUNCTION public.ref_schema(p_table text) TO service_role;
GRANT DELETE ON TABLE public.refund_request TO postgres;
GRANT INSERT ON TABLE public.refund_request TO postgres;
GRANT MAINTAIN ON TABLE public.refund_request TO postgres;
GRANT REFERENCES ON TABLE public.refund_request TO postgres;
GRANT SELECT ON TABLE public.refund_request TO postgres;
GRANT TRIGGER ON TABLE public.refund_request TO postgres;
GRANT TRUNCATE ON TABLE public.refund_request TO postgres;
GRANT UPDATE ON TABLE public.refund_request TO postgres;
GRANT DELETE ON TABLE public.refund_request TO service_role;
GRANT INSERT ON TABLE public.refund_request TO service_role;
GRANT MAINTAIN ON TABLE public.refund_request TO service_role;
GRANT REFERENCES ON TABLE public.refund_request TO service_role;
GRANT SELECT ON TABLE public.refund_request TO service_role;
GRANT TRIGGER ON TABLE public.refund_request TO service_role;
GRANT TRUNCATE ON TABLE public.refund_request TO service_role;
GRANT UPDATE ON TABLE public.refund_request TO service_role;
GRANT SELECT ON TABLE public.refund_request_refund_request_id_seq TO postgres;
GRANT UPDATE ON TABLE public.refund_request_refund_request_id_seq TO postgres;
GRANT USAGE ON TABLE public.refund_request_refund_request_id_seq TO postgres;
GRANT SELECT ON TABLE public.refund_request_refund_request_id_seq TO service_role;
GRANT UPDATE ON TABLE public.refund_request_refund_request_id_seq TO service_role;
GRANT USAGE ON TABLE public.refund_request_refund_request_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.registration_candidates(p_offering_id bigint, p_q text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.registration_candidates(p_offering_id bigint, p_q text) TO postgres;
GRANT EXECUTE ON FUNCTION public.registration_candidates(p_offering_id bigint, p_q text) TO service_role;
GRANT EXECUTE ON FUNCTION public.registration_roster(p_offering_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.registration_roster(p_offering_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.registration_roster(p_offering_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.registration_term_info(p_term_registration_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.registration_term_info(p_term_registration_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.registration_term_info(p_term_registration_id bigint) TO service_role;
GRANT DELETE ON TABLE public.religion TO authenticated;
GRANT INSERT ON TABLE public.religion TO authenticated;
GRANT UPDATE ON TABLE public.religion TO authenticated;
GRANT DELETE ON TABLE public.religion TO postgres;
GRANT INSERT ON TABLE public.religion TO postgres;
GRANT MAINTAIN ON TABLE public.religion TO postgres;
GRANT REFERENCES ON TABLE public.religion TO postgres;
GRANT SELECT ON TABLE public.religion TO postgres;
GRANT TRIGGER ON TABLE public.religion TO postgres;
GRANT TRUNCATE ON TABLE public.religion TO postgres;
GRANT UPDATE ON TABLE public.religion TO postgres;
GRANT DELETE ON TABLE public.religion TO service_role;
GRANT INSERT ON TABLE public.religion TO service_role;
GRANT MAINTAIN ON TABLE public.religion TO service_role;
GRANT REFERENCES ON TABLE public.religion TO service_role;
GRANT SELECT ON TABLE public.religion TO service_role;
GRANT TRIGGER ON TABLE public.religion TO service_role;
GRANT TRUNCATE ON TABLE public.religion TO service_role;
GRANT UPDATE ON TABLE public.religion TO service_role;
GRANT SELECT ON TABLE public.religion_religion_id_seq TO postgres;
GRANT UPDATE ON TABLE public.religion_religion_id_seq TO postgres;
GRANT USAGE ON TABLE public.religion_religion_id_seq TO postgres;
GRANT SELECT ON TABLE public.religion_religion_id_seq TO service_role;
GRANT UPDATE ON TABLE public.religion_religion_id_seq TO service_role;
GRANT USAGE ON TABLE public.religion_religion_id_seq TO service_role;
GRANT DELETE ON TABLE public.research_project_financial_utilization TO authenticated;
GRANT INSERT ON TABLE public.research_project_financial_utilization TO authenticated;
GRANT UPDATE ON TABLE public.research_project_financial_utilization TO authenticated;
GRANT DELETE ON TABLE public.research_project_financial_utilization TO postgres;
GRANT INSERT ON TABLE public.research_project_financial_utilization TO postgres;
GRANT MAINTAIN ON TABLE public.research_project_financial_utilization TO postgres;
GRANT REFERENCES ON TABLE public.research_project_financial_utilization TO postgres;
GRANT SELECT ON TABLE public.research_project_financial_utilization TO postgres;
GRANT TRIGGER ON TABLE public.research_project_financial_utilization TO postgres;
GRANT TRUNCATE ON TABLE public.research_project_financial_utilization TO postgres;
GRANT UPDATE ON TABLE public.research_project_financial_utilization TO postgres;
GRANT DELETE ON TABLE public.research_project_financial_utilization TO service_role;
GRANT INSERT ON TABLE public.research_project_financial_utilization TO service_role;
GRANT MAINTAIN ON TABLE public.research_project_financial_utilization TO service_role;
GRANT REFERENCES ON TABLE public.research_project_financial_utilization TO service_role;
GRANT SELECT ON TABLE public.research_project_financial_utilization TO service_role;
GRANT TRIGGER ON TABLE public.research_project_financial_utilization TO service_role;
GRANT TRUNCATE ON TABLE public.research_project_financial_utilization TO service_role;
GRANT UPDATE ON TABLE public.research_project_financial_utilization TO service_role;
GRANT SELECT ON TABLE public.research_project_financial_utilization_utilization_id_seq TO postgres;
GRANT UPDATE ON TABLE public.research_project_financial_utilization_utilization_id_seq TO postgres;
GRANT USAGE ON TABLE public.research_project_financial_utilization_utilization_id_seq TO postgres;
GRANT SELECT ON TABLE public.research_project_financial_utilization_utilization_id_seq TO service_role;
GRANT UPDATE ON TABLE public.research_project_financial_utilization_utilization_id_seq TO service_role;
GRANT USAGE ON TABLE public.research_project_financial_utilization_utilization_id_seq TO service_role;
GRANT DELETE ON TABLE public.research_proposal TO postgres;
GRANT INSERT ON TABLE public.research_proposal TO postgres;
GRANT MAINTAIN ON TABLE public.research_proposal TO postgres;
GRANT REFERENCES ON TABLE public.research_proposal TO postgres;
GRANT SELECT ON TABLE public.research_proposal TO postgres;
GRANT TRIGGER ON TABLE public.research_proposal TO postgres;
GRANT TRUNCATE ON TABLE public.research_proposal TO postgres;
GRANT UPDATE ON TABLE public.research_proposal TO postgres;
GRANT DELETE ON TABLE public.research_proposal TO service_role;
GRANT INSERT ON TABLE public.research_proposal TO service_role;
GRANT MAINTAIN ON TABLE public.research_proposal TO service_role;
GRANT REFERENCES ON TABLE public.research_proposal TO service_role;
GRANT SELECT ON TABLE public.research_proposal TO service_role;
GRANT TRIGGER ON TABLE public.research_proposal TO service_role;
GRANT TRUNCATE ON TABLE public.research_proposal TO service_role;
GRANT UPDATE ON TABLE public.research_proposal TO service_role;
GRANT DELETE ON TABLE public.research_status TO authenticated;
GRANT INSERT ON TABLE public.research_status TO authenticated;
GRANT UPDATE ON TABLE public.research_status TO authenticated;
GRANT DELETE ON TABLE public.research_status TO postgres;
GRANT INSERT ON TABLE public.research_status TO postgres;
GRANT MAINTAIN ON TABLE public.research_status TO postgres;
GRANT REFERENCES ON TABLE public.research_status TO postgres;
GRANT SELECT ON TABLE public.research_status TO postgres;
GRANT TRIGGER ON TABLE public.research_status TO postgres;
GRANT TRUNCATE ON TABLE public.research_status TO postgres;
GRANT UPDATE ON TABLE public.research_status TO postgres;
GRANT DELETE ON TABLE public.research_status TO service_role;
GRANT INSERT ON TABLE public.research_status TO service_role;
GRANT MAINTAIN ON TABLE public.research_status TO service_role;
GRANT REFERENCES ON TABLE public.research_status TO service_role;
GRANT SELECT ON TABLE public.research_status TO service_role;
GRANT TRIGGER ON TABLE public.research_status TO service_role;
GRANT TRUNCATE ON TABLE public.research_status TO service_role;
GRANT UPDATE ON TABLE public.research_status TO service_role;
GRANT SELECT ON TABLE public.research_status_research_status_id_seq TO postgres;
GRANT UPDATE ON TABLE public.research_status_research_status_id_seq TO postgres;
GRANT USAGE ON TABLE public.research_status_research_status_id_seq TO postgres;
GRANT SELECT ON TABLE public.research_status_research_status_id_seq TO service_role;
GRANT UPDATE ON TABLE public.research_status_research_status_id_seq TO service_role;
GRANT USAGE ON TABLE public.research_status_research_status_id_seq TO service_role;
GRANT DELETE ON TABLE public.research_supervision TO authenticated;
GRANT INSERT ON TABLE public.research_supervision TO authenticated;
GRANT UPDATE ON TABLE public.research_supervision TO authenticated;
GRANT DELETE ON TABLE public.research_supervision TO postgres;
GRANT INSERT ON TABLE public.research_supervision TO postgres;
GRANT MAINTAIN ON TABLE public.research_supervision TO postgres;
GRANT REFERENCES ON TABLE public.research_supervision TO postgres;
GRANT SELECT ON TABLE public.research_supervision TO postgres;
GRANT TRIGGER ON TABLE public.research_supervision TO postgres;
GRANT TRUNCATE ON TABLE public.research_supervision TO postgres;
GRANT UPDATE ON TABLE public.research_supervision TO postgres;
GRANT DELETE ON TABLE public.research_supervision TO service_role;
GRANT INSERT ON TABLE public.research_supervision TO service_role;
GRANT MAINTAIN ON TABLE public.research_supervision TO service_role;
GRANT REFERENCES ON TABLE public.research_supervision TO service_role;
GRANT SELECT ON TABLE public.research_supervision TO service_role;
GRANT TRIGGER ON TABLE public.research_supervision TO service_role;
GRANT TRUNCATE ON TABLE public.research_supervision TO service_role;
GRANT UPDATE ON TABLE public.research_supervision TO service_role;
GRANT SELECT ON TABLE public.research_supervision_research_supervision_id_seq TO postgres;
GRANT UPDATE ON TABLE public.research_supervision_research_supervision_id_seq TO postgres;
GRANT USAGE ON TABLE public.research_supervision_research_supervision_id_seq TO postgres;
GRANT SELECT ON TABLE public.research_supervision_research_supervision_id_seq TO service_role;
GRANT UPDATE ON TABLE public.research_supervision_research_supervision_id_seq TO service_role;
GRANT USAGE ON TABLE public.research_supervision_research_supervision_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.result_compute_term(p_term_registration_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.result_compute_term(p_term_registration_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.result_compute_term(p_term_registration_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.result_course_sheet(p_course_offering_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.result_course_sheet(p_course_offering_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.result_course_sheet(p_course_offering_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.result_publish_term(p_term_registration_id bigint, p_publish boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.result_publish_term(p_term_registration_id bigint, p_publish boolean) TO postgres;
GRANT EXECUTE ON FUNCTION public.result_publish_term(p_term_registration_id bigint, p_publish boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.result_record_course(p_course_registration_id bigint, p_internal numeric, p_external numeric, p_attempt integer, p_status text, p_remarks text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.result_record_course(p_course_registration_id bigint, p_internal numeric, p_external numeric, p_attempt integer, p_status text, p_remarks text) TO postgres;
GRANT EXECUTE ON FUNCTION public.result_record_course(p_course_registration_id bigint, p_internal numeric, p_external numeric, p_attempt integer, p_status text, p_remarks text) TO service_role;
GRANT EXECUTE ON FUNCTION public.result_term_sheet(p_offering_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.result_term_sheet(p_offering_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.result_term_sheet(p_offering_id bigint) TO service_role;
GRANT DELETE ON TABLE public.role TO postgres;
GRANT INSERT ON TABLE public.role TO postgres;
GRANT MAINTAIN ON TABLE public.role TO postgres;
GRANT REFERENCES ON TABLE public.role TO postgres;
GRANT SELECT ON TABLE public.role TO postgres;
GRANT TRIGGER ON TABLE public.role TO postgres;
GRANT TRUNCATE ON TABLE public.role TO postgres;
GRANT UPDATE ON TABLE public.role TO postgres;
GRANT DELETE ON TABLE public.role TO service_role;
GRANT INSERT ON TABLE public.role TO service_role;
GRANT MAINTAIN ON TABLE public.role TO service_role;
GRANT REFERENCES ON TABLE public.role TO service_role;
GRANT SELECT ON TABLE public.role TO service_role;
GRANT TRIGGER ON TABLE public.role TO service_role;
GRANT TRUNCATE ON TABLE public.role TO service_role;
GRANT UPDATE ON TABLE public.role TO service_role;
GRANT DELETE ON TABLE public.role_delegation TO postgres;
GRANT INSERT ON TABLE public.role_delegation TO postgres;
GRANT MAINTAIN ON TABLE public.role_delegation TO postgres;
GRANT REFERENCES ON TABLE public.role_delegation TO postgres;
GRANT SELECT ON TABLE public.role_delegation TO postgres;
GRANT TRIGGER ON TABLE public.role_delegation TO postgres;
GRANT TRUNCATE ON TABLE public.role_delegation TO postgres;
GRANT UPDATE ON TABLE public.role_delegation TO postgres;
GRANT DELETE ON TABLE public.role_delegation TO service_role;
GRANT INSERT ON TABLE public.role_delegation TO service_role;
GRANT MAINTAIN ON TABLE public.role_delegation TO service_role;
GRANT REFERENCES ON TABLE public.role_delegation TO service_role;
GRANT SELECT ON TABLE public.role_delegation TO service_role;
GRANT TRIGGER ON TABLE public.role_delegation TO service_role;
GRANT TRUNCATE ON TABLE public.role_delegation TO service_role;
GRANT UPDATE ON TABLE public.role_delegation TO service_role;
GRANT SELECT ON TABLE public.role_delegation_role_delegation_id_seq TO postgres;
GRANT UPDATE ON TABLE public.role_delegation_role_delegation_id_seq TO postgres;
GRANT USAGE ON TABLE public.role_delegation_role_delegation_id_seq TO postgres;
GRANT SELECT ON TABLE public.role_delegation_role_delegation_id_seq TO service_role;
GRANT UPDATE ON TABLE public.role_delegation_role_delegation_id_seq TO service_role;
GRANT USAGE ON TABLE public.role_delegation_role_delegation_id_seq TO service_role;
GRANT DELETE ON TABLE public.role_permission TO postgres;
GRANT INSERT ON TABLE public.role_permission TO postgres;
GRANT MAINTAIN ON TABLE public.role_permission TO postgres;
GRANT REFERENCES ON TABLE public.role_permission TO postgres;
GRANT SELECT ON TABLE public.role_permission TO postgres;
GRANT TRIGGER ON TABLE public.role_permission TO postgres;
GRANT TRUNCATE ON TABLE public.role_permission TO postgres;
GRANT UPDATE ON TABLE public.role_permission TO postgres;
GRANT DELETE ON TABLE public.role_permission TO service_role;
GRANT INSERT ON TABLE public.role_permission TO service_role;
GRANT MAINTAIN ON TABLE public.role_permission TO service_role;
GRANT REFERENCES ON TABLE public.role_permission TO service_role;
GRANT SELECT ON TABLE public.role_permission TO service_role;
GRANT TRIGGER ON TABLE public.role_permission TO service_role;
GRANT TRUNCATE ON TABLE public.role_permission TO service_role;
GRANT UPDATE ON TABLE public.role_permission TO service_role;
GRANT SELECT ON TABLE public.role_role_id_seq TO postgres;
GRANT UPDATE ON TABLE public.role_role_id_seq TO postgres;
GRANT USAGE ON TABLE public.role_role_id_seq TO postgres;
GRANT SELECT ON TABLE public.role_role_id_seq TO service_role;
GRANT UPDATE ON TABLE public.role_role_id_seq TO service_role;
GRANT USAGE ON TABLE public.role_role_id_seq TO service_role;
GRANT DELETE ON TABLE public.role_type TO authenticated;
GRANT INSERT ON TABLE public.role_type TO authenticated;
GRANT UPDATE ON TABLE public.role_type TO authenticated;
GRANT DELETE ON TABLE public.role_type TO postgres;
GRANT INSERT ON TABLE public.role_type TO postgres;
GRANT MAINTAIN ON TABLE public.role_type TO postgres;
GRANT REFERENCES ON TABLE public.role_type TO postgres;
GRANT SELECT ON TABLE public.role_type TO postgres;
GRANT TRIGGER ON TABLE public.role_type TO postgres;
GRANT TRUNCATE ON TABLE public.role_type TO postgres;
GRANT UPDATE ON TABLE public.role_type TO postgres;
GRANT DELETE ON TABLE public.role_type TO service_role;
GRANT INSERT ON TABLE public.role_type TO service_role;
GRANT MAINTAIN ON TABLE public.role_type TO service_role;
GRANT REFERENCES ON TABLE public.role_type TO service_role;
GRANT SELECT ON TABLE public.role_type TO service_role;
GRANT TRIGGER ON TABLE public.role_type TO service_role;
GRANT TRUNCATE ON TABLE public.role_type TO service_role;
GRANT UPDATE ON TABLE public.role_type TO service_role;
GRANT SELECT ON TABLE public.role_type_role_type_id_seq TO postgres;
GRANT UPDATE ON TABLE public.role_type_role_type_id_seq TO postgres;
GRANT USAGE ON TABLE public.role_type_role_type_id_seq TO postgres;
GRANT SELECT ON TABLE public.role_type_role_type_id_seq TO service_role;
GRANT UPDATE ON TABLE public.role_type_role_type_id_seq TO service_role;
GRANT USAGE ON TABLE public.role_type_role_type_id_seq TO service_role;
GRANT DELETE ON TABLE public.room TO authenticated;
GRANT INSERT ON TABLE public.room TO authenticated;
GRANT UPDATE ON TABLE public.room TO authenticated;
GRANT DELETE ON TABLE public.room TO postgres;
GRANT INSERT ON TABLE public.room TO postgres;
GRANT MAINTAIN ON TABLE public.room TO postgres;
GRANT REFERENCES ON TABLE public.room TO postgres;
GRANT SELECT ON TABLE public.room TO postgres;
GRANT TRIGGER ON TABLE public.room TO postgres;
GRANT TRUNCATE ON TABLE public.room TO postgres;
GRANT UPDATE ON TABLE public.room TO postgres;
GRANT DELETE ON TABLE public.room TO service_role;
GRANT INSERT ON TABLE public.room TO service_role;
GRANT MAINTAIN ON TABLE public.room TO service_role;
GRANT REFERENCES ON TABLE public.room TO service_role;
GRANT SELECT ON TABLE public.room TO service_role;
GRANT TRIGGER ON TABLE public.room TO service_role;
GRANT TRUNCATE ON TABLE public.room TO service_role;
GRANT UPDATE ON TABLE public.room TO service_role;
GRANT SELECT ON TABLE public.room_room_id_seq TO postgres;
GRANT UPDATE ON TABLE public.room_room_id_seq TO postgres;
GRANT USAGE ON TABLE public.room_room_id_seq TO postgres;
GRANT SELECT ON TABLE public.room_room_id_seq TO service_role;
GRANT UPDATE ON TABLE public.room_room_id_seq TO service_role;
GRANT USAGE ON TABLE public.room_room_id_seq TO service_role;
GRANT DELETE ON TABLE public.scholarship_scheme TO postgres;
GRANT INSERT ON TABLE public.scholarship_scheme TO postgres;
GRANT MAINTAIN ON TABLE public.scholarship_scheme TO postgres;
GRANT REFERENCES ON TABLE public.scholarship_scheme TO postgres;
GRANT SELECT ON TABLE public.scholarship_scheme TO postgres;
GRANT TRIGGER ON TABLE public.scholarship_scheme TO postgres;
GRANT TRUNCATE ON TABLE public.scholarship_scheme TO postgres;
GRANT UPDATE ON TABLE public.scholarship_scheme TO postgres;
GRANT DELETE ON TABLE public.scholarship_scheme TO service_role;
GRANT INSERT ON TABLE public.scholarship_scheme TO service_role;
GRANT MAINTAIN ON TABLE public.scholarship_scheme TO service_role;
GRANT REFERENCES ON TABLE public.scholarship_scheme TO service_role;
GRANT SELECT ON TABLE public.scholarship_scheme TO service_role;
GRANT TRIGGER ON TABLE public.scholarship_scheme TO service_role;
GRANT TRUNCATE ON TABLE public.scholarship_scheme TO service_role;
GRANT UPDATE ON TABLE public.scholarship_scheme TO service_role;
GRANT SELECT ON TABLE public.scholarship_scheme_scholarship_scheme_id_seq TO postgres;
GRANT UPDATE ON TABLE public.scholarship_scheme_scholarship_scheme_id_seq TO postgres;
GRANT USAGE ON TABLE public.scholarship_scheme_scholarship_scheme_id_seq TO postgres;
GRANT SELECT ON TABLE public.scholarship_scheme_scholarship_scheme_id_seq TO service_role;
GRANT UPDATE ON TABLE public.scholarship_scheme_scholarship_scheme_id_seq TO service_role;
GRANT USAGE ON TABLE public.scholarship_scheme_scholarship_scheme_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.section_delete(p_kind text, p_parent_id bigint, p_section text, p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.section_delete(p_kind text, p_parent_id bigint, p_section text, p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.section_delete(p_kind text, p_parent_id bigint, p_section text, p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.section_lookup_options(p_table text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.section_lookup_options(p_table text) TO postgres;
GRANT EXECUTE ON FUNCTION public.section_lookup_options(p_table text) TO service_role;
GRANT EXECUTE ON FUNCTION public.section_rows(p_kind text, p_parent_id bigint, p_section text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.section_rows(p_kind text, p_parent_id bigint, p_section text) TO postgres;
GRANT EXECUTE ON FUNCTION public.section_rows(p_kind text, p_parent_id bigint, p_section text) TO service_role;
GRANT EXECUTE ON FUNCTION public.section_save(p_kind text, p_parent_id bigint, p_section text, p_id bigint, p jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.section_save(p_kind text, p_parent_id bigint, p_section text, p_id bigint, p jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.section_save(p_kind text, p_parent_id bigint, p_section text, p_id bigint, p jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.section_schema(p_kind text, p_section text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.section_schema(p_kind text, p_section text) TO postgres;
GRANT EXECUTE ON FUNCTION public.section_schema(p_kind text, p_section text) TO service_role;
GRANT DELETE ON TABLE public.semester TO authenticated;
GRANT INSERT ON TABLE public.semester TO authenticated;
GRANT UPDATE ON TABLE public.semester TO authenticated;
GRANT DELETE ON TABLE public.semester TO postgres;
GRANT INSERT ON TABLE public.semester TO postgres;
GRANT MAINTAIN ON TABLE public.semester TO postgres;
GRANT REFERENCES ON TABLE public.semester TO postgres;
GRANT SELECT ON TABLE public.semester TO postgres;
GRANT TRIGGER ON TABLE public.semester TO postgres;
GRANT TRUNCATE ON TABLE public.semester TO postgres;
GRANT UPDATE ON TABLE public.semester TO postgres;
GRANT DELETE ON TABLE public.semester TO service_role;
GRANT INSERT ON TABLE public.semester TO service_role;
GRANT MAINTAIN ON TABLE public.semester TO service_role;
GRANT REFERENCES ON TABLE public.semester TO service_role;
GRANT SELECT ON TABLE public.semester TO service_role;
GRANT TRIGGER ON TABLE public.semester TO service_role;
GRANT TRUNCATE ON TABLE public.semester TO service_role;
GRANT UPDATE ON TABLE public.semester TO service_role;
GRANT SELECT ON TABLE public.semester_semester_id_seq TO postgres;
GRANT UPDATE ON TABLE public.semester_semester_id_seq TO postgres;
GRANT USAGE ON TABLE public.semester_semester_id_seq TO postgres;
GRANT SELECT ON TABLE public.semester_semester_id_seq TO service_role;
GRANT UPDATE ON TABLE public.semester_semester_id_seq TO service_role;
GRANT USAGE ON TABLE public.semester_semester_id_seq TO service_role;
GRANT DELETE ON TABLE public.service_fee_request TO postgres;
GRANT INSERT ON TABLE public.service_fee_request TO postgres;
GRANT MAINTAIN ON TABLE public.service_fee_request TO postgres;
GRANT REFERENCES ON TABLE public.service_fee_request TO postgres;
GRANT SELECT ON TABLE public.service_fee_request TO postgres;
GRANT TRIGGER ON TABLE public.service_fee_request TO postgres;
GRANT TRUNCATE ON TABLE public.service_fee_request TO postgres;
GRANT UPDATE ON TABLE public.service_fee_request TO postgres;
GRANT DELETE ON TABLE public.service_fee_request TO service_role;
GRANT INSERT ON TABLE public.service_fee_request TO service_role;
GRANT MAINTAIN ON TABLE public.service_fee_request TO service_role;
GRANT REFERENCES ON TABLE public.service_fee_request TO service_role;
GRANT SELECT ON TABLE public.service_fee_request TO service_role;
GRANT TRIGGER ON TABLE public.service_fee_request TO service_role;
GRANT TRUNCATE ON TABLE public.service_fee_request TO service_role;
GRANT UPDATE ON TABLE public.service_fee_request TO service_role;
GRANT SELECT ON TABLE public.service_fee_request_service_fee_request_id_seq TO postgres;
GRANT UPDATE ON TABLE public.service_fee_request_service_fee_request_id_seq TO postgres;
GRANT USAGE ON TABLE public.service_fee_request_service_fee_request_id_seq TO postgres;
GRANT SELECT ON TABLE public.service_fee_request_service_fee_request_id_seq TO service_role;
GRANT UPDATE ON TABLE public.service_fee_request_service_fee_request_id_seq TO service_role;
GRANT USAGE ON TABLE public.service_fee_request_service_fee_request_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_assessment_event_guard() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_assessment_event_guard() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_assessment_mark_guard() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_assessment_mark_guard() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_attendance_session_guard() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_attendance_session_guard() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_course_result_lock() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_course_result_lock() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_fee_benefit_guard() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_fee_benefit_guard() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_fee_item_sync() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_fee_item_sync() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_fee_refund_guard() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_fee_refund_guard() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_feedback_cycle_guard() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_feedback_cycle_guard() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_feedback_item_guard() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_feedback_item_guard() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_feedback_questionnaire_guard() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_feedback_questionnaire_guard() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_guard_announcement() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_guard_announcement() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_guard_assessment_event() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_guard_assessment_event() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_guard_attendance_correction_request() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_guard_attendance_correction_request() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_guard_certificate_hold() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_guard_certificate_hold() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_guard_certificate_request() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_guard_certificate_request() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_guard_conference_activity_indexing() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_guard_conference_activity_indexing() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_guard_consultancy_project() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_guard_consultancy_project() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_guard_employee_aadhaar() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_guard_employee_aadhaar() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_guard_employee_bank_account() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_guard_employee_bank_account() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_guard_employee_document() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_guard_employee_document() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_guard_employee_pan() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_guard_employee_pan() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_guard_evidence_document() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_guard_evidence_document() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_guard_journal_metric() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_guard_journal_metric() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_guard_journal_publication_indexing() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_guard_journal_publication_indexing() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_guard_staff_activity() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_guard_staff_activity() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_guard_student_activity() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_guard_student_activity() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_guard_student_activity_evidence() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_guard_student_activity_evidence() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_guard_student_course_registration() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_guard_student_course_registration() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_guard_student_document() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_guard_student_document() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_guard_student_term_registration() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_guard_student_term_registration() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_guard_student_term_result() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_guard_student_term_result() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_guard_term_registration_hold() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_guard_term_registration_hold() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_payment_allocation_guard() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_payment_allocation_guard() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_payment_allocation_sync() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_payment_allocation_sync() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_recalc_fee_item_paid(p_item_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_recalc_fee_item_paid(p_item_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_registration_course_guard() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_registration_course_guard() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_registration_term_guard() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_registration_term_guard() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_sync_fee_assessment_totals(p_assessment_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_sync_fee_assessment_totals(p_assessment_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_term_result_lock() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_term_result_lock() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_timetable_guard() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_timetable_guard() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_touch_updated_at() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_touch_updated_at() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_user_permission_override_scope() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_user_permission_override_scope() TO service_role;
GRANT EXECUTE ON FUNCTION public.sims_user_role_assignment_scope() TO postgres;
GRANT EXECUTE ON FUNCTION public.sims_user_role_assignment_scope() TO service_role;
GRANT DELETE ON TABLE public.social_category TO authenticated;
GRANT INSERT ON TABLE public.social_category TO authenticated;
GRANT UPDATE ON TABLE public.social_category TO authenticated;
GRANT DELETE ON TABLE public.social_category TO postgres;
GRANT INSERT ON TABLE public.social_category TO postgres;
GRANT MAINTAIN ON TABLE public.social_category TO postgres;
GRANT REFERENCES ON TABLE public.social_category TO postgres;
GRANT SELECT ON TABLE public.social_category TO postgres;
GRANT TRIGGER ON TABLE public.social_category TO postgres;
GRANT TRUNCATE ON TABLE public.social_category TO postgres;
GRANT UPDATE ON TABLE public.social_category TO postgres;
GRANT DELETE ON TABLE public.social_category TO service_role;
GRANT INSERT ON TABLE public.social_category TO service_role;
GRANT MAINTAIN ON TABLE public.social_category TO service_role;
GRANT REFERENCES ON TABLE public.social_category TO service_role;
GRANT SELECT ON TABLE public.social_category TO service_role;
GRANT TRIGGER ON TABLE public.social_category TO service_role;
GRANT TRUNCATE ON TABLE public.social_category TO service_role;
GRANT UPDATE ON TABLE public.social_category TO service_role;
GRANT SELECT ON TABLE public.social_category_social_category_id_seq TO postgres;
GRANT UPDATE ON TABLE public.social_category_social_category_id_seq TO postgres;
GRANT USAGE ON TABLE public.social_category_social_category_id_seq TO postgres;
GRANT SELECT ON TABLE public.social_category_social_category_id_seq TO service_role;
GRANT UPDATE ON TABLE public.social_category_social_category_id_seq TO service_role;
GRANT USAGE ON TABLE public.social_category_social_category_id_seq TO service_role;
GRANT DELETE ON TABLE public.staff_activity TO postgres;
GRANT INSERT ON TABLE public.staff_activity TO postgres;
GRANT MAINTAIN ON TABLE public.staff_activity TO postgres;
GRANT REFERENCES ON TABLE public.staff_activity TO postgres;
GRANT SELECT ON TABLE public.staff_activity TO postgres;
GRANT TRIGGER ON TABLE public.staff_activity TO postgres;
GRANT TRUNCATE ON TABLE public.staff_activity TO postgres;
GRANT UPDATE ON TABLE public.staff_activity TO postgres;
GRANT DELETE ON TABLE public.staff_activity TO service_role;
GRANT INSERT ON TABLE public.staff_activity TO service_role;
GRANT MAINTAIN ON TABLE public.staff_activity TO service_role;
GRANT REFERENCES ON TABLE public.staff_activity TO service_role;
GRANT SELECT ON TABLE public.staff_activity TO service_role;
GRANT TRIGGER ON TABLE public.staff_activity TO service_role;
GRANT TRUNCATE ON TABLE public.staff_activity TO service_role;
GRANT UPDATE ON TABLE public.staff_activity TO service_role;
GRANT DELETE ON TABLE public.staff_activity_contributor TO postgres;
GRANT INSERT ON TABLE public.staff_activity_contributor TO postgres;
GRANT MAINTAIN ON TABLE public.staff_activity_contributor TO postgres;
GRANT REFERENCES ON TABLE public.staff_activity_contributor TO postgres;
GRANT SELECT ON TABLE public.staff_activity_contributor TO postgres;
GRANT TRIGGER ON TABLE public.staff_activity_contributor TO postgres;
GRANT TRUNCATE ON TABLE public.staff_activity_contributor TO postgres;
GRANT UPDATE ON TABLE public.staff_activity_contributor TO postgres;
GRANT DELETE ON TABLE public.staff_activity_contributor TO service_role;
GRANT INSERT ON TABLE public.staff_activity_contributor TO service_role;
GRANT MAINTAIN ON TABLE public.staff_activity_contributor TO service_role;
GRANT REFERENCES ON TABLE public.staff_activity_contributor TO service_role;
GRANT SELECT ON TABLE public.staff_activity_contributor TO service_role;
GRANT TRIGGER ON TABLE public.staff_activity_contributor TO service_role;
GRANT TRUNCATE ON TABLE public.staff_activity_contributor TO service_role;
GRANT UPDATE ON TABLE public.staff_activity_contributor TO service_role;
GRANT SELECT ON TABLE public.staff_activity_contributor_staff_activity_contributor_id_seq TO postgres;
GRANT UPDATE ON TABLE public.staff_activity_contributor_staff_activity_contributor_id_seq TO postgres;
GRANT USAGE ON TABLE public.staff_activity_contributor_staff_activity_contributor_id_seq TO postgres;
GRANT SELECT ON TABLE public.staff_activity_contributor_staff_activity_contributor_id_seq TO service_role;
GRANT UPDATE ON TABLE public.staff_activity_contributor_staff_activity_contributor_id_seq TO service_role;
GRANT USAGE ON TABLE public.staff_activity_contributor_staff_activity_contributor_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.staff_activity_delete(p_activity_id bigint, p_reason text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_activity_delete(p_activity_id bigint, p_reason text) TO postgres;
GRANT EXECUTE ON FUNCTION public.staff_activity_delete(p_activity_id bigint, p_reason text) TO service_role;
GRANT EXECUTE ON FUNCTION public.staff_activity_get(p_activity_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_activity_get(p_activity_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.staff_activity_get(p_activity_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.staff_activity_list(p_employee_id bigint, p_search text, p_approval text, p_group text, p_limit integer, p_offset integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_activity_list(p_employee_id bigint, p_search text, p_approval text, p_group text, p_limit integer, p_offset integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.staff_activity_list(p_employee_id bigint, p_search text, p_approval text, p_group text, p_limit integer, p_offset integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.staff_activity_report(p_year integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_activity_report(p_year integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.staff_activity_report(p_year integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.staff_activity_review(p_activity_id bigint, p_step text, p_decision text, p_remarks text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_activity_review(p_activity_id bigint, p_step text, p_decision text, p_remarks text) TO postgres;
GRANT EXECUTE ON FUNCTION public.staff_activity_review(p_activity_id bigint, p_step text, p_decision text, p_remarks text) TO service_role;
GRANT EXECUTE ON FUNCTION public.staff_activity_save(p_activity_id bigint, p_employee_id bigint, p jsonb, p_detail jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_activity_save(p_activity_id bigint, p_employee_id bigint, p jsonb, p_detail jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.staff_activity_save(p_activity_id bigint, p_employee_id bigint, p jsonb, p_detail jsonb) TO service_role;
GRANT SELECT ON TABLE public.staff_activity_staff_activity_id_seq TO postgres;
GRANT UPDATE ON TABLE public.staff_activity_staff_activity_id_seq TO postgres;
GRANT USAGE ON TABLE public.staff_activity_staff_activity_id_seq TO postgres;
GRANT SELECT ON TABLE public.staff_activity_staff_activity_id_seq TO service_role;
GRANT UPDATE ON TABLE public.staff_activity_staff_activity_id_seq TO service_role;
GRANT USAGE ON TABLE public.staff_activity_staff_activity_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.staff_activity_submit(p_activity_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_activity_submit(p_activity_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.staff_activity_submit(p_activity_id bigint) TO service_role;
GRANT DELETE ON TABLE public.staff_award TO postgres;
GRANT INSERT ON TABLE public.staff_award TO postgres;
GRANT MAINTAIN ON TABLE public.staff_award TO postgres;
GRANT REFERENCES ON TABLE public.staff_award TO postgres;
GRANT SELECT ON TABLE public.staff_award TO postgres;
GRANT TRIGGER ON TABLE public.staff_award TO postgres;
GRANT TRUNCATE ON TABLE public.staff_award TO postgres;
GRANT UPDATE ON TABLE public.staff_award TO postgres;
GRANT DELETE ON TABLE public.staff_award TO service_role;
GRANT INSERT ON TABLE public.staff_award TO service_role;
GRANT MAINTAIN ON TABLE public.staff_award TO service_role;
GRANT REFERENCES ON TABLE public.staff_award TO service_role;
GRANT SELECT ON TABLE public.staff_award TO service_role;
GRANT TRIGGER ON TABLE public.staff_award TO service_role;
GRANT TRUNCATE ON TABLE public.staff_award TO service_role;
GRANT UPDATE ON TABLE public.staff_award TO service_role;
GRANT DELETE ON TABLE public.staff_category TO authenticated;
GRANT INSERT ON TABLE public.staff_category TO authenticated;
GRANT UPDATE ON TABLE public.staff_category TO authenticated;
GRANT DELETE ON TABLE public.staff_category TO postgres;
GRANT INSERT ON TABLE public.staff_category TO postgres;
GRANT MAINTAIN ON TABLE public.staff_category TO postgres;
GRANT REFERENCES ON TABLE public.staff_category TO postgres;
GRANT SELECT ON TABLE public.staff_category TO postgres;
GRANT TRIGGER ON TABLE public.staff_category TO postgres;
GRANT TRUNCATE ON TABLE public.staff_category TO postgres;
GRANT UPDATE ON TABLE public.staff_category TO postgres;
GRANT DELETE ON TABLE public.staff_category TO service_role;
GRANT INSERT ON TABLE public.staff_category TO service_role;
GRANT MAINTAIN ON TABLE public.staff_category TO service_role;
GRANT REFERENCES ON TABLE public.staff_category TO service_role;
GRANT SELECT ON TABLE public.staff_category TO service_role;
GRANT TRIGGER ON TABLE public.staff_category TO service_role;
GRANT TRUNCATE ON TABLE public.staff_category TO service_role;
GRANT UPDATE ON TABLE public.staff_category TO service_role;
GRANT SELECT ON TABLE public.staff_category_staff_category_id_seq TO postgres;
GRANT UPDATE ON TABLE public.staff_category_staff_category_id_seq TO postgres;
GRANT USAGE ON TABLE public.staff_category_staff_category_id_seq TO postgres;
GRANT SELECT ON TABLE public.staff_category_staff_category_id_seq TO service_role;
GRANT UPDATE ON TABLE public.staff_category_staff_category_id_seq TO service_role;
GRANT USAGE ON TABLE public.staff_category_staff_category_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.staff_contributor_add(p_activity_id bigint, p_employee_id bigint, p_external_name text, p_external_email text, p_affiliation text, p_role_type_id integer, p_is_corresponding boolean, p_details text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_contributor_add(p_activity_id bigint, p_employee_id bigint, p_external_name text, p_external_email text, p_affiliation text, p_role_type_id integer, p_is_corresponding boolean, p_details text) TO postgres;
GRANT EXECUTE ON FUNCTION public.staff_contributor_add(p_activity_id bigint, p_employee_id bigint, p_external_name text, p_external_email text, p_affiliation text, p_role_type_id integer, p_is_corresponding boolean, p_details text) TO service_role;
GRANT EXECUTE ON FUNCTION public.staff_contributor_remove(p_contributor_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_contributor_remove(p_contributor_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.staff_contributor_remove(p_contributor_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.staff_detail_schema(p_activity_type_id integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_detail_schema(p_activity_type_id integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.staff_detail_schema(p_activity_type_id integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.staff_evidence_add(p_activity_id bigint, p_document_type_id integer, p_evidence_type_id integer, p_title text, p_issue_date date, p_issuing_authority text, p_certificate_number text, p_storage_key text, p_file_name text, p_mime text, p_size bigint, p_checksum text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_evidence_add(p_activity_id bigint, p_document_type_id integer, p_evidence_type_id integer, p_title text, p_issue_date date, p_issuing_authority text, p_certificate_number text, p_storage_key text, p_file_name text, p_mime text, p_size bigint, p_checksum text) TO postgres;
GRANT EXECUTE ON FUNCTION public.staff_evidence_add(p_activity_id bigint, p_document_type_id integer, p_evidence_type_id integer, p_title text, p_issue_date date, p_issuing_authority text, p_certificate_number text, p_storage_key text, p_file_name text, p_mime text, p_size bigint, p_checksum text) TO service_role;
GRANT EXECUTE ON FUNCTION public.staff_evidence_delete(p_evidence_id bigint, p_reason text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_evidence_delete(p_evidence_id bigint, p_reason text) TO postgres;
GRANT EXECUTE ON FUNCTION public.staff_evidence_delete(p_evidence_id bigint, p_reason text) TO service_role;
GRANT EXECUTE ON FUNCTION public.staff_evidence_download_info(p_evidence_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_evidence_download_info(p_evidence_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.staff_evidence_download_info(p_evidence_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.staff_evidence_replace(p_evidence_id bigint, p_reason text, p_storage_key text, p_file_name text, p_mime text, p_size bigint, p_checksum text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_evidence_replace(p_evidence_id bigint, p_reason text, p_storage_key text, p_file_name text, p_mime text, p_size bigint, p_checksum text) TO postgres;
GRANT EXECUTE ON FUNCTION public.staff_evidence_replace(p_evidence_id bigint, p_reason text, p_storage_key text, p_file_name text, p_mime text, p_size bigint, p_checksum text) TO service_role;
GRANT EXECUTE ON FUNCTION public.staff_indexing_delete(p_activity_id bigint, p_agency_id integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_indexing_delete(p_activity_id bigint, p_agency_id integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.staff_indexing_delete(p_activity_id bigint, p_agency_id integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.staff_indexing_list(p_activity_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_indexing_list(p_activity_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.staff_indexing_list(p_activity_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.staff_indexing_save(p_activity_id bigint, p_agency_id integer, p_status text, p_year integer, p_url text, p_remarks text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_indexing_save(p_activity_id bigint, p_agency_id integer, p_status text, p_year integer, p_url text, p_remarks text) TO postgres;
GRANT EXECUTE ON FUNCTION public.staff_indexing_save(p_activity_id bigint, p_agency_id integer, p_status text, p_year integer, p_url text, p_remarks text) TO service_role;
GRANT EXECUTE ON FUNCTION public.staff_lookup_add(p_table text, p jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_lookup_add(p_table text, p jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.staff_lookup_add(p_table text, p jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.staff_lookup_options(p_table text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_lookup_options(p_table text) TO postgres;
GRANT EXECUTE ON FUNCTION public.staff_lookup_options(p_table text) TO service_role;
GRANT EXECUTE ON FUNCTION public.staff_lookup_schema(p_table text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_lookup_schema(p_table text) TO postgres;
GRANT EXECUTE ON FUNCTION public.staff_lookup_schema(p_table text) TO service_role;
GRANT DELETE ON TABLE public.staff_professional_contribution TO postgres;
GRANT INSERT ON TABLE public.staff_professional_contribution TO postgres;
GRANT MAINTAIN ON TABLE public.staff_professional_contribution TO postgres;
GRANT REFERENCES ON TABLE public.staff_professional_contribution TO postgres;
GRANT SELECT ON TABLE public.staff_professional_contribution TO postgres;
GRANT TRIGGER ON TABLE public.staff_professional_contribution TO postgres;
GRANT TRUNCATE ON TABLE public.staff_professional_contribution TO postgres;
GRANT UPDATE ON TABLE public.staff_professional_contribution TO postgres;
GRANT DELETE ON TABLE public.staff_professional_contribution TO service_role;
GRANT INSERT ON TABLE public.staff_professional_contribution TO service_role;
GRANT MAINTAIN ON TABLE public.staff_professional_contribution TO service_role;
GRANT REFERENCES ON TABLE public.staff_professional_contribution TO service_role;
GRANT SELECT ON TABLE public.staff_professional_contribution TO service_role;
GRANT TRIGGER ON TABLE public.staff_professional_contribution TO service_role;
GRANT TRUNCATE ON TABLE public.staff_professional_contribution TO service_role;
GRANT UPDATE ON TABLE public.staff_professional_contribution TO service_role;
GRANT DELETE ON TABLE public.staff_professional_membership TO postgres;
GRANT INSERT ON TABLE public.staff_professional_membership TO postgres;
GRANT MAINTAIN ON TABLE public.staff_professional_membership TO postgres;
GRANT REFERENCES ON TABLE public.staff_professional_membership TO postgres;
GRANT SELECT ON TABLE public.staff_professional_membership TO postgres;
GRANT TRIGGER ON TABLE public.staff_professional_membership TO postgres;
GRANT TRUNCATE ON TABLE public.staff_professional_membership TO postgres;
GRANT UPDATE ON TABLE public.staff_professional_membership TO postgres;
GRANT DELETE ON TABLE public.staff_professional_membership TO service_role;
GRANT INSERT ON TABLE public.staff_professional_membership TO service_role;
GRANT MAINTAIN ON TABLE public.staff_professional_membership TO service_role;
GRANT REFERENCES ON TABLE public.staff_professional_membership TO service_role;
GRANT SELECT ON TABLE public.staff_professional_membership TO service_role;
GRANT TRIGGER ON TABLE public.staff_professional_membership TO service_role;
GRANT TRUNCATE ON TABLE public.staff_professional_membership TO service_role;
GRANT UPDATE ON TABLE public.staff_professional_membership TO service_role;
GRANT DELETE ON TABLE public.staff_type TO authenticated;
GRANT INSERT ON TABLE public.staff_type TO authenticated;
GRANT UPDATE ON TABLE public.staff_type TO authenticated;
GRANT DELETE ON TABLE public.staff_type TO postgres;
GRANT INSERT ON TABLE public.staff_type TO postgres;
GRANT MAINTAIN ON TABLE public.staff_type TO postgres;
GRANT REFERENCES ON TABLE public.staff_type TO postgres;
GRANT SELECT ON TABLE public.staff_type TO postgres;
GRANT TRIGGER ON TABLE public.staff_type TO postgres;
GRANT TRUNCATE ON TABLE public.staff_type TO postgres;
GRANT UPDATE ON TABLE public.staff_type TO postgres;
GRANT DELETE ON TABLE public.staff_type TO service_role;
GRANT INSERT ON TABLE public.staff_type TO service_role;
GRANT MAINTAIN ON TABLE public.staff_type TO service_role;
GRANT REFERENCES ON TABLE public.staff_type TO service_role;
GRANT SELECT ON TABLE public.staff_type TO service_role;
GRANT TRIGGER ON TABLE public.staff_type TO service_role;
GRANT TRUNCATE ON TABLE public.staff_type TO service_role;
GRANT UPDATE ON TABLE public.staff_type TO service_role;
GRANT SELECT ON TABLE public.staff_type_staff_type_id_seq TO postgres;
GRANT UPDATE ON TABLE public.staff_type_staff_type_id_seq TO postgres;
GRANT USAGE ON TABLE public.staff_type_staff_type_id_seq TO postgres;
GRANT SELECT ON TABLE public.staff_type_staff_type_id_seq TO service_role;
GRANT UPDATE ON TABLE public.staff_type_staff_type_id_seq TO service_role;
GRANT USAGE ON TABLE public.staff_type_staff_type_id_seq TO service_role;
GRANT DELETE ON TABLE public.state TO authenticated;
GRANT INSERT ON TABLE public.state TO authenticated;
GRANT UPDATE ON TABLE public.state TO authenticated;
GRANT DELETE ON TABLE public.state TO postgres;
GRANT INSERT ON TABLE public.state TO postgres;
GRANT MAINTAIN ON TABLE public.state TO postgres;
GRANT REFERENCES ON TABLE public.state TO postgres;
GRANT SELECT ON TABLE public.state TO postgres;
GRANT TRIGGER ON TABLE public.state TO postgres;
GRANT TRUNCATE ON TABLE public.state TO postgres;
GRANT UPDATE ON TABLE public.state TO postgres;
GRANT DELETE ON TABLE public.state TO service_role;
GRANT INSERT ON TABLE public.state TO service_role;
GRANT MAINTAIN ON TABLE public.state TO service_role;
GRANT REFERENCES ON TABLE public.state TO service_role;
GRANT SELECT ON TABLE public.state TO service_role;
GRANT TRIGGER ON TABLE public.state TO service_role;
GRANT TRUNCATE ON TABLE public.state TO service_role;
GRANT UPDATE ON TABLE public.state TO service_role;
GRANT SELECT ON TABLE public.state_state_id_seq TO postgres;
GRANT UPDATE ON TABLE public.state_state_id_seq TO postgres;
GRANT USAGE ON TABLE public.state_state_id_seq TO postgres;
GRANT SELECT ON TABLE public.state_state_id_seq TO service_role;
GRANT UPDATE ON TABLE public.state_state_id_seq TO service_role;
GRANT USAGE ON TABLE public.state_state_id_seq TO service_role;
GRANT DELETE ON TABLE public.student TO authenticated;
GRANT INSERT ON TABLE public.student TO authenticated;
GRANT UPDATE ON TABLE public.student TO authenticated;
GRANT DELETE ON TABLE public.student TO postgres;
GRANT INSERT ON TABLE public.student TO postgres;
GRANT MAINTAIN ON TABLE public.student TO postgres;
GRANT REFERENCES ON TABLE public.student TO postgres;
GRANT SELECT ON TABLE public.student TO postgres;
GRANT TRIGGER ON TABLE public.student TO postgres;
GRANT TRUNCATE ON TABLE public.student TO postgres;
GRANT UPDATE ON TABLE public.student TO postgres;
GRANT DELETE ON TABLE public.student TO service_role;
GRANT INSERT ON TABLE public.student TO service_role;
GRANT MAINTAIN ON TABLE public.student TO service_role;
GRANT REFERENCES ON TABLE public.student TO service_role;
GRANT SELECT ON TABLE public.student TO service_role;
GRANT TRIGGER ON TABLE public.student TO service_role;
GRANT TRUNCATE ON TABLE public.student TO service_role;
GRANT UPDATE ON TABLE public.student TO service_role;
GRANT DELETE ON TABLE public.student_activity TO postgres;
GRANT INSERT ON TABLE public.student_activity TO postgres;
GRANT MAINTAIN ON TABLE public.student_activity TO postgres;
GRANT REFERENCES ON TABLE public.student_activity TO postgres;
GRANT SELECT ON TABLE public.student_activity TO postgres;
GRANT TRIGGER ON TABLE public.student_activity TO postgres;
GRANT TRUNCATE ON TABLE public.student_activity TO postgres;
GRANT UPDATE ON TABLE public.student_activity TO postgres;
GRANT DELETE ON TABLE public.student_activity TO service_role;
GRANT INSERT ON TABLE public.student_activity TO service_role;
GRANT MAINTAIN ON TABLE public.student_activity TO service_role;
GRANT REFERENCES ON TABLE public.student_activity TO service_role;
GRANT SELECT ON TABLE public.student_activity TO service_role;
GRANT TRIGGER ON TABLE public.student_activity TO service_role;
GRANT TRUNCATE ON TABLE public.student_activity TO service_role;
GRANT UPDATE ON TABLE public.student_activity TO service_role;
GRANT EXECUTE ON FUNCTION public.student_activity_delete(p_activity_id bigint, p_reason text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.student_activity_delete(p_activity_id bigint, p_reason text) TO postgres;
GRANT EXECUTE ON FUNCTION public.student_activity_delete(p_activity_id bigint, p_reason text) TO service_role;
GRANT DELETE ON TABLE public.student_activity_evidence TO postgres;
GRANT INSERT ON TABLE public.student_activity_evidence TO postgres;
GRANT MAINTAIN ON TABLE public.student_activity_evidence TO postgres;
GRANT REFERENCES ON TABLE public.student_activity_evidence TO postgres;
GRANT SELECT ON TABLE public.student_activity_evidence TO postgres;
GRANT TRIGGER ON TABLE public.student_activity_evidence TO postgres;
GRANT TRUNCATE ON TABLE public.student_activity_evidence TO postgres;
GRANT UPDATE ON TABLE public.student_activity_evidence TO postgres;
GRANT DELETE ON TABLE public.student_activity_evidence TO service_role;
GRANT INSERT ON TABLE public.student_activity_evidence TO service_role;
GRANT MAINTAIN ON TABLE public.student_activity_evidence TO service_role;
GRANT REFERENCES ON TABLE public.student_activity_evidence TO service_role;
GRANT SELECT ON TABLE public.student_activity_evidence TO service_role;
GRANT TRIGGER ON TABLE public.student_activity_evidence TO service_role;
GRANT TRUNCATE ON TABLE public.student_activity_evidence TO service_role;
GRANT UPDATE ON TABLE public.student_activity_evidence TO service_role;
GRANT EXECUTE ON FUNCTION public.student_activity_evidence_add(p_activity_id bigint, p_document_type_id integer, p_evidence_type_id integer, p_title text, p_issue_date date, p_issuing_authority text, p_certificate_number text, p_storage_key text, p_file_name text, p_mime text, p_size bigint, p_checksum text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.student_activity_evidence_add(p_activity_id bigint, p_document_type_id integer, p_evidence_type_id integer, p_title text, p_issue_date date, p_issuing_authority text, p_certificate_number text, p_storage_key text, p_file_name text, p_mime text, p_size bigint, p_checksum text) TO postgres;
GRANT EXECUTE ON FUNCTION public.student_activity_evidence_add(p_activity_id bigint, p_document_type_id integer, p_evidence_type_id integer, p_title text, p_issue_date date, p_issuing_authority text, p_certificate_number text, p_storage_key text, p_file_name text, p_mime text, p_size bigint, p_checksum text) TO service_role;
GRANT SELECT ON TABLE public.student_activity_evidence_aud_student_activity_evidence_aud_seq TO postgres;
GRANT UPDATE ON TABLE public.student_activity_evidence_aud_student_activity_evidence_aud_seq TO postgres;
GRANT USAGE ON TABLE public.student_activity_evidence_aud_student_activity_evidence_aud_seq TO postgres;
GRANT SELECT ON TABLE public.student_activity_evidence_aud_student_activity_evidence_aud_seq TO service_role;
GRANT UPDATE ON TABLE public.student_activity_evidence_aud_student_activity_evidence_aud_seq TO service_role;
GRANT USAGE ON TABLE public.student_activity_evidence_aud_student_activity_evidence_aud_seq TO service_role;
GRANT DELETE ON TABLE public.student_activity_evidence_audit TO postgres;
GRANT INSERT ON TABLE public.student_activity_evidence_audit TO postgres;
GRANT MAINTAIN ON TABLE public.student_activity_evidence_audit TO postgres;
GRANT REFERENCES ON TABLE public.student_activity_evidence_audit TO postgres;
GRANT SELECT ON TABLE public.student_activity_evidence_audit TO postgres;
GRANT TRIGGER ON TABLE public.student_activity_evidence_audit TO postgres;
GRANT TRUNCATE ON TABLE public.student_activity_evidence_audit TO postgres;
GRANT UPDATE ON TABLE public.student_activity_evidence_audit TO postgres;
GRANT DELETE ON TABLE public.student_activity_evidence_audit TO service_role;
GRANT INSERT ON TABLE public.student_activity_evidence_audit TO service_role;
GRANT MAINTAIN ON TABLE public.student_activity_evidence_audit TO service_role;
GRANT REFERENCES ON TABLE public.student_activity_evidence_audit TO service_role;
GRANT SELECT ON TABLE public.student_activity_evidence_audit TO service_role;
GRANT TRIGGER ON TABLE public.student_activity_evidence_audit TO service_role;
GRANT TRUNCATE ON TABLE public.student_activity_evidence_audit TO service_role;
GRANT UPDATE ON TABLE public.student_activity_evidence_audit TO service_role;
GRANT EXECUTE ON FUNCTION public.student_activity_evidence_delete(p_evidence_id bigint, p_reason text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.student_activity_evidence_delete(p_evidence_id bigint, p_reason text) TO postgres;
GRANT EXECUTE ON FUNCTION public.student_activity_evidence_delete(p_evidence_id bigint, p_reason text) TO service_role;
GRANT EXECUTE ON FUNCTION public.student_activity_evidence_download_info(p_evidence_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.student_activity_evidence_download_info(p_evidence_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.student_activity_evidence_download_info(p_evidence_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.student_activity_evidence_replace(p_evidence_id bigint, p_reason text, p_storage_key text, p_file_name text, p_mime text, p_size bigint, p_checksum text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.student_activity_evidence_replace(p_evidence_id bigint, p_reason text, p_storage_key text, p_file_name text, p_mime text, p_size bigint, p_checksum text) TO postgres;
GRANT EXECUTE ON FUNCTION public.student_activity_evidence_replace(p_evidence_id bigint, p_reason text, p_storage_key text, p_file_name text, p_mime text, p_size bigint, p_checksum text) TO service_role;
GRANT SELECT ON TABLE public.student_activity_evidence_req_student_activity_evidence_req_seq TO postgres;
GRANT UPDATE ON TABLE public.student_activity_evidence_req_student_activity_evidence_req_seq TO postgres;
GRANT USAGE ON TABLE public.student_activity_evidence_req_student_activity_evidence_req_seq TO postgres;
GRANT SELECT ON TABLE public.student_activity_evidence_req_student_activity_evidence_req_seq TO service_role;
GRANT UPDATE ON TABLE public.student_activity_evidence_req_student_activity_evidence_req_seq TO service_role;
GRANT USAGE ON TABLE public.student_activity_evidence_req_student_activity_evidence_req_seq TO service_role;
GRANT DELETE ON TABLE public.student_activity_evidence_requirement TO authenticated;
GRANT INSERT ON TABLE public.student_activity_evidence_requirement TO authenticated;
GRANT UPDATE ON TABLE public.student_activity_evidence_requirement TO authenticated;
GRANT DELETE ON TABLE public.student_activity_evidence_requirement TO postgres;
GRANT INSERT ON TABLE public.student_activity_evidence_requirement TO postgres;
GRANT MAINTAIN ON TABLE public.student_activity_evidence_requirement TO postgres;
GRANT REFERENCES ON TABLE public.student_activity_evidence_requirement TO postgres;
GRANT SELECT ON TABLE public.student_activity_evidence_requirement TO postgres;
GRANT TRIGGER ON TABLE public.student_activity_evidence_requirement TO postgres;
GRANT TRUNCATE ON TABLE public.student_activity_evidence_requirement TO postgres;
GRANT UPDATE ON TABLE public.student_activity_evidence_requirement TO postgres;
GRANT DELETE ON TABLE public.student_activity_evidence_requirement TO service_role;
GRANT INSERT ON TABLE public.student_activity_evidence_requirement TO service_role;
GRANT MAINTAIN ON TABLE public.student_activity_evidence_requirement TO service_role;
GRANT REFERENCES ON TABLE public.student_activity_evidence_requirement TO service_role;
GRANT SELECT ON TABLE public.student_activity_evidence_requirement TO service_role;
GRANT TRIGGER ON TABLE public.student_activity_evidence_requirement TO service_role;
GRANT TRUNCATE ON TABLE public.student_activity_evidence_requirement TO service_role;
GRANT UPDATE ON TABLE public.student_activity_evidence_requirement TO service_role;
GRANT SELECT ON TABLE public.student_activity_evidence_student_activity_evidence_id_seq TO postgres;
GRANT UPDATE ON TABLE public.student_activity_evidence_student_activity_evidence_id_seq TO postgres;
GRANT USAGE ON TABLE public.student_activity_evidence_student_activity_evidence_id_seq TO postgres;
GRANT SELECT ON TABLE public.student_activity_evidence_student_activity_evidence_id_seq TO service_role;
GRANT UPDATE ON TABLE public.student_activity_evidence_student_activity_evidence_id_seq TO service_role;
GRANT USAGE ON TABLE public.student_activity_evidence_student_activity_evidence_id_seq TO service_role;
GRANT SELECT ON TABLE public.student_activity_evidence_ver_student_activity_evidence_ver_seq TO postgres;
GRANT UPDATE ON TABLE public.student_activity_evidence_ver_student_activity_evidence_ver_seq TO postgres;
GRANT USAGE ON TABLE public.student_activity_evidence_ver_student_activity_evidence_ver_seq TO postgres;
GRANT SELECT ON TABLE public.student_activity_evidence_ver_student_activity_evidence_ver_seq TO service_role;
GRANT UPDATE ON TABLE public.student_activity_evidence_ver_student_activity_evidence_ver_seq TO service_role;
GRANT USAGE ON TABLE public.student_activity_evidence_ver_student_activity_evidence_ver_seq TO service_role;
GRANT DELETE ON TABLE public.student_activity_evidence_version TO postgres;
GRANT INSERT ON TABLE public.student_activity_evidence_version TO postgres;
GRANT MAINTAIN ON TABLE public.student_activity_evidence_version TO postgres;
GRANT REFERENCES ON TABLE public.student_activity_evidence_version TO postgres;
GRANT SELECT ON TABLE public.student_activity_evidence_version TO postgres;
GRANT TRIGGER ON TABLE public.student_activity_evidence_version TO postgres;
GRANT TRUNCATE ON TABLE public.student_activity_evidence_version TO postgres;
GRANT UPDATE ON TABLE public.student_activity_evidence_version TO postgres;
GRANT DELETE ON TABLE public.student_activity_evidence_version TO service_role;
GRANT INSERT ON TABLE public.student_activity_evidence_version TO service_role;
GRANT MAINTAIN ON TABLE public.student_activity_evidence_version TO service_role;
GRANT REFERENCES ON TABLE public.student_activity_evidence_version TO service_role;
GRANT SELECT ON TABLE public.student_activity_evidence_version TO service_role;
GRANT TRIGGER ON TABLE public.student_activity_evidence_version TO service_role;
GRANT TRUNCATE ON TABLE public.student_activity_evidence_version TO service_role;
GRANT UPDATE ON TABLE public.student_activity_evidence_version TO service_role;
GRANT EXECUTE ON FUNCTION public.student_activity_get(p_activity_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.student_activity_get(p_activity_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.student_activity_get(p_activity_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.student_activity_list(p_student_id bigint, p_search text, p_approval text, p_limit integer, p_offset integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.student_activity_list(p_student_id bigint, p_search text, p_approval text, p_limit integer, p_offset integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.student_activity_list(p_student_id bigint, p_search text, p_approval text, p_limit integer, p_offset integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.student_activity_report(p_year integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.student_activity_report(p_year integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.student_activity_report(p_year integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.student_activity_review(p_activity_id bigint, p_step text, p_decision text, p_remarks text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.student_activity_review(p_activity_id bigint, p_step text, p_decision text, p_remarks text) TO postgres;
GRANT EXECUTE ON FUNCTION public.student_activity_review(p_activity_id bigint, p_step text, p_decision text, p_remarks text) TO service_role;
GRANT EXECUTE ON FUNCTION public.student_activity_save(p_activity_id bigint, p_student_id bigint, p jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.student_activity_save(p_activity_id bigint, p_student_id bigint, p jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.student_activity_save(p_activity_id bigint, p_student_id bigint, p jsonb) TO service_role;
GRANT SELECT ON TABLE public.student_activity_student_activity_id_seq TO postgres;
GRANT UPDATE ON TABLE public.student_activity_student_activity_id_seq TO postgres;
GRANT USAGE ON TABLE public.student_activity_student_activity_id_seq TO postgres;
GRANT SELECT ON TABLE public.student_activity_student_activity_id_seq TO service_role;
GRANT UPDATE ON TABLE public.student_activity_student_activity_id_seq TO service_role;
GRANT USAGE ON TABLE public.student_activity_student_activity_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.student_activity_submit(p_activity_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.student_activity_submit(p_activity_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.student_activity_submit(p_activity_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.student_activity_team_add(p_activity_id bigint, p_student_id bigint, p_external_name text, p_external_email text, p_role text, p_is_lead boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.student_activity_team_add(p_activity_id bigint, p_student_id bigint, p_external_name text, p_external_email text, p_role text, p_is_lead boolean) TO postgres;
GRANT EXECUTE ON FUNCTION public.student_activity_team_add(p_activity_id bigint, p_student_id bigint, p_external_name text, p_external_email text, p_role text, p_is_lead boolean) TO service_role;
GRANT DELETE ON TABLE public.student_activity_team_member TO postgres;
GRANT INSERT ON TABLE public.student_activity_team_member TO postgres;
GRANT MAINTAIN ON TABLE public.student_activity_team_member TO postgres;
GRANT REFERENCES ON TABLE public.student_activity_team_member TO postgres;
GRANT SELECT ON TABLE public.student_activity_team_member TO postgres;
GRANT TRIGGER ON TABLE public.student_activity_team_member TO postgres;
GRANT TRUNCATE ON TABLE public.student_activity_team_member TO postgres;
GRANT UPDATE ON TABLE public.student_activity_team_member TO postgres;
GRANT DELETE ON TABLE public.student_activity_team_member TO service_role;
GRANT INSERT ON TABLE public.student_activity_team_member TO service_role;
GRANT MAINTAIN ON TABLE public.student_activity_team_member TO service_role;
GRANT REFERENCES ON TABLE public.student_activity_team_member TO service_role;
GRANT SELECT ON TABLE public.student_activity_team_member TO service_role;
GRANT TRIGGER ON TABLE public.student_activity_team_member TO service_role;
GRANT TRUNCATE ON TABLE public.student_activity_team_member TO service_role;
GRANT UPDATE ON TABLE public.student_activity_team_member TO service_role;
GRANT SELECT ON TABLE public.student_activity_team_member_student_activity_team_member_i_seq TO postgres;
GRANT UPDATE ON TABLE public.student_activity_team_member_student_activity_team_member_i_seq TO postgres;
GRANT USAGE ON TABLE public.student_activity_team_member_student_activity_team_member_i_seq TO postgres;
GRANT SELECT ON TABLE public.student_activity_team_member_student_activity_team_member_i_seq TO service_role;
GRANT UPDATE ON TABLE public.student_activity_team_member_student_activity_team_member_i_seq TO service_role;
GRANT USAGE ON TABLE public.student_activity_team_member_student_activity_team_member_i_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.student_activity_team_remove(p_member_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.student_activity_team_remove(p_member_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.student_activity_team_remove(p_member_id bigint) TO service_role;
GRANT DELETE ON TABLE public.student_activity_type TO authenticated;
GRANT INSERT ON TABLE public.student_activity_type TO authenticated;
GRANT UPDATE ON TABLE public.student_activity_type TO authenticated;
GRANT DELETE ON TABLE public.student_activity_type TO postgres;
GRANT INSERT ON TABLE public.student_activity_type TO postgres;
GRANT MAINTAIN ON TABLE public.student_activity_type TO postgres;
GRANT REFERENCES ON TABLE public.student_activity_type TO postgres;
GRANT SELECT ON TABLE public.student_activity_type TO postgres;
GRANT TRIGGER ON TABLE public.student_activity_type TO postgres;
GRANT TRUNCATE ON TABLE public.student_activity_type TO postgres;
GRANT UPDATE ON TABLE public.student_activity_type TO postgres;
GRANT DELETE ON TABLE public.student_activity_type TO service_role;
GRANT INSERT ON TABLE public.student_activity_type TO service_role;
GRANT MAINTAIN ON TABLE public.student_activity_type TO service_role;
GRANT REFERENCES ON TABLE public.student_activity_type TO service_role;
GRANT SELECT ON TABLE public.student_activity_type TO service_role;
GRANT TRIGGER ON TABLE public.student_activity_type TO service_role;
GRANT TRUNCATE ON TABLE public.student_activity_type TO service_role;
GRANT UPDATE ON TABLE public.student_activity_type TO service_role;
GRANT SELECT ON TABLE public.student_activity_type_student_activity_type_id_seq TO postgres;
GRANT UPDATE ON TABLE public.student_activity_type_student_activity_type_id_seq TO postgres;
GRANT USAGE ON TABLE public.student_activity_type_student_activity_type_id_seq TO postgres;
GRANT SELECT ON TABLE public.student_activity_type_student_activity_type_id_seq TO service_role;
GRANT UPDATE ON TABLE public.student_activity_type_student_activity_type_id_seq TO service_role;
GRANT USAGE ON TABLE public.student_activity_type_student_activity_type_id_seq TO service_role;
GRANT DELETE ON TABLE public.student_address TO authenticated;
GRANT INSERT ON TABLE public.student_address TO authenticated;
GRANT UPDATE ON TABLE public.student_address TO authenticated;
GRANT DELETE ON TABLE public.student_address TO postgres;
GRANT INSERT ON TABLE public.student_address TO postgres;
GRANT MAINTAIN ON TABLE public.student_address TO postgres;
GRANT REFERENCES ON TABLE public.student_address TO postgres;
GRANT SELECT ON TABLE public.student_address TO postgres;
GRANT TRIGGER ON TABLE public.student_address TO postgres;
GRANT TRUNCATE ON TABLE public.student_address TO postgres;
GRANT UPDATE ON TABLE public.student_address TO postgres;
GRANT DELETE ON TABLE public.student_address TO service_role;
GRANT INSERT ON TABLE public.student_address TO service_role;
GRANT MAINTAIN ON TABLE public.student_address TO service_role;
GRANT REFERENCES ON TABLE public.student_address TO service_role;
GRANT SELECT ON TABLE public.student_address TO service_role;
GRANT TRIGGER ON TABLE public.student_address TO service_role;
GRANT TRUNCATE ON TABLE public.student_address TO service_role;
GRANT UPDATE ON TABLE public.student_address TO service_role;
GRANT SELECT ON TABLE public.student_address_student_address_id_seq TO postgres;
GRANT UPDATE ON TABLE public.student_address_student_address_id_seq TO postgres;
GRANT USAGE ON TABLE public.student_address_student_address_id_seq TO postgres;
GRANT SELECT ON TABLE public.student_address_student_address_id_seq TO service_role;
GRANT UPDATE ON TABLE public.student_address_student_address_id_seq TO service_role;
GRANT USAGE ON TABLE public.student_address_student_address_id_seq TO service_role;
GRANT DELETE ON TABLE public.student_assessment_mark TO postgres;
GRANT INSERT ON TABLE public.student_assessment_mark TO postgres;
GRANT MAINTAIN ON TABLE public.student_assessment_mark TO postgres;
GRANT REFERENCES ON TABLE public.student_assessment_mark TO postgres;
GRANT SELECT ON TABLE public.student_assessment_mark TO postgres;
GRANT TRIGGER ON TABLE public.student_assessment_mark TO postgres;
GRANT TRUNCATE ON TABLE public.student_assessment_mark TO postgres;
GRANT UPDATE ON TABLE public.student_assessment_mark TO postgres;
GRANT DELETE ON TABLE public.student_assessment_mark TO service_role;
GRANT INSERT ON TABLE public.student_assessment_mark TO service_role;
GRANT MAINTAIN ON TABLE public.student_assessment_mark TO service_role;
GRANT REFERENCES ON TABLE public.student_assessment_mark TO service_role;
GRANT SELECT ON TABLE public.student_assessment_mark TO service_role;
GRANT TRIGGER ON TABLE public.student_assessment_mark TO service_role;
GRANT TRUNCATE ON TABLE public.student_assessment_mark TO service_role;
GRANT UPDATE ON TABLE public.student_assessment_mark TO service_role;
GRANT SELECT ON TABLE public.student_assessment_mark_student_assessment_mark_id_seq TO postgres;
GRANT UPDATE ON TABLE public.student_assessment_mark_student_assessment_mark_id_seq TO postgres;
GRANT USAGE ON TABLE public.student_assessment_mark_student_assessment_mark_id_seq TO postgres;
GRANT SELECT ON TABLE public.student_assessment_mark_student_assessment_mark_id_seq TO service_role;
GRANT UPDATE ON TABLE public.student_assessment_mark_student_assessment_mark_id_seq TO service_role;
GRANT USAGE ON TABLE public.student_assessment_mark_student_assessment_mark_id_seq TO service_role;
GRANT DELETE ON TABLE public.student_attendance TO postgres;
GRANT INSERT ON TABLE public.student_attendance TO postgres;
GRANT MAINTAIN ON TABLE public.student_attendance TO postgres;
GRANT REFERENCES ON TABLE public.student_attendance TO postgres;
GRANT SELECT ON TABLE public.student_attendance TO postgres;
GRANT TRIGGER ON TABLE public.student_attendance TO postgres;
GRANT TRUNCATE ON TABLE public.student_attendance TO postgres;
GRANT UPDATE ON TABLE public.student_attendance TO postgres;
GRANT DELETE ON TABLE public.student_attendance TO service_role;
GRANT INSERT ON TABLE public.student_attendance TO service_role;
GRANT MAINTAIN ON TABLE public.student_attendance TO service_role;
GRANT REFERENCES ON TABLE public.student_attendance TO service_role;
GRANT SELECT ON TABLE public.student_attendance TO service_role;
GRANT TRIGGER ON TABLE public.student_attendance TO service_role;
GRANT TRUNCATE ON TABLE public.student_attendance TO service_role;
GRANT UPDATE ON TABLE public.student_attendance TO service_role;
GRANT DELETE ON TABLE public.student_course_registration TO authenticated;
GRANT INSERT ON TABLE public.student_course_registration TO authenticated;
GRANT UPDATE ON TABLE public.student_course_registration TO authenticated;
GRANT DELETE ON TABLE public.student_course_registration TO postgres;
GRANT INSERT ON TABLE public.student_course_registration TO postgres;
GRANT MAINTAIN ON TABLE public.student_course_registration TO postgres;
GRANT REFERENCES ON TABLE public.student_course_registration TO postgres;
GRANT SELECT ON TABLE public.student_course_registration TO postgres;
GRANT TRIGGER ON TABLE public.student_course_registration TO postgres;
GRANT TRUNCATE ON TABLE public.student_course_registration TO postgres;
GRANT UPDATE ON TABLE public.student_course_registration TO postgres;
GRANT DELETE ON TABLE public.student_course_registration TO service_role;
GRANT INSERT ON TABLE public.student_course_registration TO service_role;
GRANT MAINTAIN ON TABLE public.student_course_registration TO service_role;
GRANT REFERENCES ON TABLE public.student_course_registration TO service_role;
GRANT SELECT ON TABLE public.student_course_registration TO service_role;
GRANT TRIGGER ON TABLE public.student_course_registration TO service_role;
GRANT TRUNCATE ON TABLE public.student_course_registration TO service_role;
GRANT UPDATE ON TABLE public.student_course_registration TO service_role;
GRANT SELECT ON TABLE public.student_course_registration_course_registration_id_seq TO postgres;
GRANT UPDATE ON TABLE public.student_course_registration_course_registration_id_seq TO postgres;
GRANT USAGE ON TABLE public.student_course_registration_course_registration_id_seq TO postgres;
GRANT SELECT ON TABLE public.student_course_registration_course_registration_id_seq TO service_role;
GRANT UPDATE ON TABLE public.student_course_registration_course_registration_id_seq TO service_role;
GRANT USAGE ON TABLE public.student_course_registration_course_registration_id_seq TO service_role;
GRANT DELETE ON TABLE public.student_course_result TO postgres;
GRANT INSERT ON TABLE public.student_course_result TO postgres;
GRANT MAINTAIN ON TABLE public.student_course_result TO postgres;
GRANT REFERENCES ON TABLE public.student_course_result TO postgres;
GRANT SELECT ON TABLE public.student_course_result TO postgres;
GRANT TRIGGER ON TABLE public.student_course_result TO postgres;
GRANT TRUNCATE ON TABLE public.student_course_result TO postgres;
GRANT UPDATE ON TABLE public.student_course_result TO postgres;
GRANT DELETE ON TABLE public.student_course_result TO service_role;
GRANT INSERT ON TABLE public.student_course_result TO service_role;
GRANT MAINTAIN ON TABLE public.student_course_result TO service_role;
GRANT REFERENCES ON TABLE public.student_course_result TO service_role;
GRANT SELECT ON TABLE public.student_course_result TO service_role;
GRANT TRIGGER ON TABLE public.student_course_result TO service_role;
GRANT TRUNCATE ON TABLE public.student_course_result TO service_role;
GRANT UPDATE ON TABLE public.student_course_result TO service_role;
GRANT SELECT ON TABLE public.student_course_result_student_course_result_id_seq TO postgres;
GRANT UPDATE ON TABLE public.student_course_result_student_course_result_id_seq TO postgres;
GRANT USAGE ON TABLE public.student_course_result_student_course_result_id_seq TO postgres;
GRANT SELECT ON TABLE public.student_course_result_student_course_result_id_seq TO service_role;
GRANT UPDATE ON TABLE public.student_course_result_student_course_result_id_seq TO service_role;
GRANT USAGE ON TABLE public.student_course_result_student_course_result_id_seq TO service_role;
GRANT DELETE ON TABLE public.student_document TO authenticated;
GRANT INSERT ON TABLE public.student_document TO authenticated;
GRANT UPDATE ON TABLE public.student_document TO authenticated;
GRANT DELETE ON TABLE public.student_document TO postgres;
GRANT INSERT ON TABLE public.student_document TO postgres;
GRANT MAINTAIN ON TABLE public.student_document TO postgres;
GRANT REFERENCES ON TABLE public.student_document TO postgres;
GRANT SELECT ON TABLE public.student_document TO postgres;
GRANT TRIGGER ON TABLE public.student_document TO postgres;
GRANT TRUNCATE ON TABLE public.student_document TO postgres;
GRANT UPDATE ON TABLE public.student_document TO postgres;
GRANT DELETE ON TABLE public.student_document TO service_role;
GRANT INSERT ON TABLE public.student_document TO service_role;
GRANT MAINTAIN ON TABLE public.student_document TO service_role;
GRANT REFERENCES ON TABLE public.student_document TO service_role;
GRANT SELECT ON TABLE public.student_document TO service_role;
GRANT TRIGGER ON TABLE public.student_document TO service_role;
GRANT TRUNCATE ON TABLE public.student_document TO service_role;
GRANT UPDATE ON TABLE public.student_document TO service_role;
GRANT EXECUTE ON FUNCTION public.student_document_delete(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.student_document_delete(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.student_document_delete(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.student_document_download_info(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.student_document_download_info(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.student_document_download_info(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.student_document_list(p_student_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.student_document_list(p_student_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.student_document_list(p_student_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.student_document_register(p_student_id bigint, p_document_type_id integer, p_storage_key text, p_file_name text, p_mime_type text, p_size bigint, p_checksum text, p_document_number text, p_issue_date date, p_expiry_date date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.student_document_register(p_student_id bigint, p_document_type_id integer, p_storage_key text, p_file_name text, p_mime_type text, p_size bigint, p_checksum text, p_document_number text, p_issue_date date, p_expiry_date date) TO postgres;
GRANT EXECUTE ON FUNCTION public.student_document_register(p_student_id bigint, p_document_type_id integer, p_storage_key text, p_file_name text, p_mime_type text, p_size bigint, p_checksum text, p_document_number text, p_issue_date date, p_expiry_date date) TO service_role;
GRANT EXECUTE ON FUNCTION public.student_document_review(p_id bigint, p_decision text, p_remarks text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.student_document_review(p_id bigint, p_decision text, p_remarks text) TO postgres;
GRANT EXECUTE ON FUNCTION public.student_document_review(p_id bigint, p_decision text, p_remarks text) TO service_role;
GRANT SELECT ON TABLE public.student_document_student_document_id_seq TO postgres;
GRANT UPDATE ON TABLE public.student_document_student_document_id_seq TO postgres;
GRANT USAGE ON TABLE public.student_document_student_document_id_seq TO postgres;
GRANT SELECT ON TABLE public.student_document_student_document_id_seq TO service_role;
GRANT UPDATE ON TABLE public.student_document_student_document_id_seq TO service_role;
GRANT USAGE ON TABLE public.student_document_student_document_id_seq TO service_role;
GRANT DELETE ON TABLE public.student_entrance_exam TO authenticated;
GRANT INSERT ON TABLE public.student_entrance_exam TO authenticated;
GRANT UPDATE ON TABLE public.student_entrance_exam TO authenticated;
GRANT DELETE ON TABLE public.student_entrance_exam TO postgres;
GRANT INSERT ON TABLE public.student_entrance_exam TO postgres;
GRANT MAINTAIN ON TABLE public.student_entrance_exam TO postgres;
GRANT REFERENCES ON TABLE public.student_entrance_exam TO postgres;
GRANT SELECT ON TABLE public.student_entrance_exam TO postgres;
GRANT TRIGGER ON TABLE public.student_entrance_exam TO postgres;
GRANT TRUNCATE ON TABLE public.student_entrance_exam TO postgres;
GRANT UPDATE ON TABLE public.student_entrance_exam TO postgres;
GRANT DELETE ON TABLE public.student_entrance_exam TO service_role;
GRANT INSERT ON TABLE public.student_entrance_exam TO service_role;
GRANT MAINTAIN ON TABLE public.student_entrance_exam TO service_role;
GRANT REFERENCES ON TABLE public.student_entrance_exam TO service_role;
GRANT SELECT ON TABLE public.student_entrance_exam TO service_role;
GRANT TRIGGER ON TABLE public.student_entrance_exam TO service_role;
GRANT TRUNCATE ON TABLE public.student_entrance_exam TO service_role;
GRANT UPDATE ON TABLE public.student_entrance_exam TO service_role;
GRANT SELECT ON TABLE public.student_entrance_exam_student_entrance_exam_id_seq TO postgres;
GRANT UPDATE ON TABLE public.student_entrance_exam_student_entrance_exam_id_seq TO postgres;
GRANT USAGE ON TABLE public.student_entrance_exam_student_entrance_exam_id_seq TO postgres;
GRANT SELECT ON TABLE public.student_entrance_exam_student_entrance_exam_id_seq TO service_role;
GRANT UPDATE ON TABLE public.student_entrance_exam_student_entrance_exam_id_seq TO service_role;
GRANT USAGE ON TABLE public.student_entrance_exam_student_entrance_exam_id_seq TO service_role;
GRANT DELETE ON TABLE public.student_exit TO authenticated;
GRANT INSERT ON TABLE public.student_exit TO authenticated;
GRANT UPDATE ON TABLE public.student_exit TO authenticated;
GRANT DELETE ON TABLE public.student_exit TO postgres;
GRANT INSERT ON TABLE public.student_exit TO postgres;
GRANT MAINTAIN ON TABLE public.student_exit TO postgres;
GRANT REFERENCES ON TABLE public.student_exit TO postgres;
GRANT SELECT ON TABLE public.student_exit TO postgres;
GRANT TRIGGER ON TABLE public.student_exit TO postgres;
GRANT TRUNCATE ON TABLE public.student_exit TO postgres;
GRANT UPDATE ON TABLE public.student_exit TO postgres;
GRANT DELETE ON TABLE public.student_exit TO service_role;
GRANT INSERT ON TABLE public.student_exit TO service_role;
GRANT MAINTAIN ON TABLE public.student_exit TO service_role;
GRANT REFERENCES ON TABLE public.student_exit TO service_role;
GRANT SELECT ON TABLE public.student_exit TO service_role;
GRANT TRIGGER ON TABLE public.student_exit TO service_role;
GRANT TRUNCATE ON TABLE public.student_exit TO service_role;
GRANT UPDATE ON TABLE public.student_exit TO service_role;
GRANT SELECT ON TABLE public.student_exit_student_exit_id_seq TO postgres;
GRANT UPDATE ON TABLE public.student_exit_student_exit_id_seq TO postgres;
GRANT USAGE ON TABLE public.student_exit_student_exit_id_seq TO postgres;
GRANT SELECT ON TABLE public.student_exit_student_exit_id_seq TO service_role;
GRANT UPDATE ON TABLE public.student_exit_student_exit_id_seq TO service_role;
GRANT USAGE ON TABLE public.student_exit_student_exit_id_seq TO service_role;
GRANT DELETE ON TABLE public.student_fee_assessment TO postgres;
GRANT INSERT ON TABLE public.student_fee_assessment TO postgres;
GRANT MAINTAIN ON TABLE public.student_fee_assessment TO postgres;
GRANT REFERENCES ON TABLE public.student_fee_assessment TO postgres;
GRANT SELECT ON TABLE public.student_fee_assessment TO postgres;
GRANT TRIGGER ON TABLE public.student_fee_assessment TO postgres;
GRANT TRUNCATE ON TABLE public.student_fee_assessment TO postgres;
GRANT UPDATE ON TABLE public.student_fee_assessment TO postgres;
GRANT DELETE ON TABLE public.student_fee_assessment TO service_role;
GRANT INSERT ON TABLE public.student_fee_assessment TO service_role;
GRANT MAINTAIN ON TABLE public.student_fee_assessment TO service_role;
GRANT REFERENCES ON TABLE public.student_fee_assessment TO service_role;
GRANT SELECT ON TABLE public.student_fee_assessment TO service_role;
GRANT TRIGGER ON TABLE public.student_fee_assessment TO service_role;
GRANT TRUNCATE ON TABLE public.student_fee_assessment TO service_role;
GRANT UPDATE ON TABLE public.student_fee_assessment TO service_role;
GRANT SELECT ON TABLE public.student_fee_assessment_fee_assessment_id_seq TO postgres;
GRANT UPDATE ON TABLE public.student_fee_assessment_fee_assessment_id_seq TO postgres;
GRANT USAGE ON TABLE public.student_fee_assessment_fee_assessment_id_seq TO postgres;
GRANT SELECT ON TABLE public.student_fee_assessment_fee_assessment_id_seq TO service_role;
GRANT UPDATE ON TABLE public.student_fee_assessment_fee_assessment_id_seq TO service_role;
GRANT USAGE ON TABLE public.student_fee_assessment_fee_assessment_id_seq TO service_role;
GRANT DELETE ON TABLE public.student_fee_assessment_item TO postgres;
GRANT INSERT ON TABLE public.student_fee_assessment_item TO postgres;
GRANT MAINTAIN ON TABLE public.student_fee_assessment_item TO postgres;
GRANT REFERENCES ON TABLE public.student_fee_assessment_item TO postgres;
GRANT SELECT ON TABLE public.student_fee_assessment_item TO postgres;
GRANT TRIGGER ON TABLE public.student_fee_assessment_item TO postgres;
GRANT TRUNCATE ON TABLE public.student_fee_assessment_item TO postgres;
GRANT UPDATE ON TABLE public.student_fee_assessment_item TO postgres;
GRANT DELETE ON TABLE public.student_fee_assessment_item TO service_role;
GRANT INSERT ON TABLE public.student_fee_assessment_item TO service_role;
GRANT MAINTAIN ON TABLE public.student_fee_assessment_item TO service_role;
GRANT REFERENCES ON TABLE public.student_fee_assessment_item TO service_role;
GRANT SELECT ON TABLE public.student_fee_assessment_item TO service_role;
GRANT TRIGGER ON TABLE public.student_fee_assessment_item TO service_role;
GRANT TRUNCATE ON TABLE public.student_fee_assessment_item TO service_role;
GRANT UPDATE ON TABLE public.student_fee_assessment_item TO service_role;
GRANT SELECT ON TABLE public.student_fee_assessment_item_assessment_item_id_seq TO postgres;
GRANT UPDATE ON TABLE public.student_fee_assessment_item_assessment_item_id_seq TO postgres;
GRANT USAGE ON TABLE public.student_fee_assessment_item_assessment_item_id_seq TO postgres;
GRANT SELECT ON TABLE public.student_fee_assessment_item_assessment_item_id_seq TO service_role;
GRANT UPDATE ON TABLE public.student_fee_assessment_item_assessment_item_id_seq TO service_role;
GRANT USAGE ON TABLE public.student_fee_assessment_item_assessment_item_id_seq TO service_role;
GRANT DELETE ON TABLE public.student_fee_concession TO postgres;
GRANT INSERT ON TABLE public.student_fee_concession TO postgres;
GRANT MAINTAIN ON TABLE public.student_fee_concession TO postgres;
GRANT REFERENCES ON TABLE public.student_fee_concession TO postgres;
GRANT SELECT ON TABLE public.student_fee_concession TO postgres;
GRANT TRIGGER ON TABLE public.student_fee_concession TO postgres;
GRANT TRUNCATE ON TABLE public.student_fee_concession TO postgres;
GRANT UPDATE ON TABLE public.student_fee_concession TO postgres;
GRANT DELETE ON TABLE public.student_fee_concession TO service_role;
GRANT INSERT ON TABLE public.student_fee_concession TO service_role;
GRANT MAINTAIN ON TABLE public.student_fee_concession TO service_role;
GRANT REFERENCES ON TABLE public.student_fee_concession TO service_role;
GRANT SELECT ON TABLE public.student_fee_concession TO service_role;
GRANT TRIGGER ON TABLE public.student_fee_concession TO service_role;
GRANT TRUNCATE ON TABLE public.student_fee_concession TO service_role;
GRANT UPDATE ON TABLE public.student_fee_concession TO service_role;
GRANT SELECT ON TABLE public.student_fee_concession_student_concession_id_seq TO postgres;
GRANT UPDATE ON TABLE public.student_fee_concession_student_concession_id_seq TO postgres;
GRANT USAGE ON TABLE public.student_fee_concession_student_concession_id_seq TO postgres;
GRANT SELECT ON TABLE public.student_fee_concession_student_concession_id_seq TO service_role;
GRANT UPDATE ON TABLE public.student_fee_concession_student_concession_id_seq TO service_role;
GRANT USAGE ON TABLE public.student_fee_concession_student_concession_id_seq TO service_role;
GRANT DELETE ON TABLE public.student_fee_penalty TO postgres;
GRANT INSERT ON TABLE public.student_fee_penalty TO postgres;
GRANT MAINTAIN ON TABLE public.student_fee_penalty TO postgres;
GRANT REFERENCES ON TABLE public.student_fee_penalty TO postgres;
GRANT SELECT ON TABLE public.student_fee_penalty TO postgres;
GRANT TRIGGER ON TABLE public.student_fee_penalty TO postgres;
GRANT TRUNCATE ON TABLE public.student_fee_penalty TO postgres;
GRANT UPDATE ON TABLE public.student_fee_penalty TO postgres;
GRANT DELETE ON TABLE public.student_fee_penalty TO service_role;
GRANT INSERT ON TABLE public.student_fee_penalty TO service_role;
GRANT MAINTAIN ON TABLE public.student_fee_penalty TO service_role;
GRANT REFERENCES ON TABLE public.student_fee_penalty TO service_role;
GRANT SELECT ON TABLE public.student_fee_penalty TO service_role;
GRANT TRIGGER ON TABLE public.student_fee_penalty TO service_role;
GRANT TRUNCATE ON TABLE public.student_fee_penalty TO service_role;
GRANT UPDATE ON TABLE public.student_fee_penalty TO service_role;
GRANT SELECT ON TABLE public.student_fee_penalty_fee_penalty_id_seq TO postgres;
GRANT UPDATE ON TABLE public.student_fee_penalty_fee_penalty_id_seq TO postgres;
GRANT USAGE ON TABLE public.student_fee_penalty_fee_penalty_id_seq TO postgres;
GRANT SELECT ON TABLE public.student_fee_penalty_fee_penalty_id_seq TO service_role;
GRANT UPDATE ON TABLE public.student_fee_penalty_fee_penalty_id_seq TO service_role;
GRANT USAGE ON TABLE public.student_fee_penalty_fee_penalty_id_seq TO service_role;
GRANT DELETE ON TABLE public.student_financial_account TO postgres;
GRANT INSERT ON TABLE public.student_financial_account TO postgres;
GRANT MAINTAIN ON TABLE public.student_financial_account TO postgres;
GRANT REFERENCES ON TABLE public.student_financial_account TO postgres;
GRANT SELECT ON TABLE public.student_financial_account TO postgres;
GRANT TRIGGER ON TABLE public.student_financial_account TO postgres;
GRANT TRUNCATE ON TABLE public.student_financial_account TO postgres;
GRANT UPDATE ON TABLE public.student_financial_account TO postgres;
GRANT DELETE ON TABLE public.student_financial_account TO service_role;
GRANT INSERT ON TABLE public.student_financial_account TO service_role;
GRANT MAINTAIN ON TABLE public.student_financial_account TO service_role;
GRANT REFERENCES ON TABLE public.student_financial_account TO service_role;
GRANT SELECT ON TABLE public.student_financial_account TO service_role;
GRANT TRIGGER ON TABLE public.student_financial_account TO service_role;
GRANT TRUNCATE ON TABLE public.student_financial_account TO service_role;
GRANT UPDATE ON TABLE public.student_financial_account TO service_role;
GRANT SELECT ON TABLE public.student_financial_account_student_account_id_seq TO postgres;
GRANT UPDATE ON TABLE public.student_financial_account_student_account_id_seq TO postgres;
GRANT USAGE ON TABLE public.student_financial_account_student_account_id_seq TO postgres;
GRANT SELECT ON TABLE public.student_financial_account_student_account_id_seq TO service_role;
GRANT UPDATE ON TABLE public.student_financial_account_student_account_id_seq TO service_role;
GRANT USAGE ON TABLE public.student_financial_account_student_account_id_seq TO service_role;
GRANT DELETE ON TABLE public.student_financial_hold TO postgres;
GRANT INSERT ON TABLE public.student_financial_hold TO postgres;
GRANT MAINTAIN ON TABLE public.student_financial_hold TO postgres;
GRANT REFERENCES ON TABLE public.student_financial_hold TO postgres;
GRANT SELECT ON TABLE public.student_financial_hold TO postgres;
GRANT TRIGGER ON TABLE public.student_financial_hold TO postgres;
GRANT TRUNCATE ON TABLE public.student_financial_hold TO postgres;
GRANT UPDATE ON TABLE public.student_financial_hold TO postgres;
GRANT DELETE ON TABLE public.student_financial_hold TO service_role;
GRANT INSERT ON TABLE public.student_financial_hold TO service_role;
GRANT MAINTAIN ON TABLE public.student_financial_hold TO service_role;
GRANT REFERENCES ON TABLE public.student_financial_hold TO service_role;
GRANT SELECT ON TABLE public.student_financial_hold TO service_role;
GRANT TRIGGER ON TABLE public.student_financial_hold TO service_role;
GRANT TRUNCATE ON TABLE public.student_financial_hold TO service_role;
GRANT UPDATE ON TABLE public.student_financial_hold TO service_role;
GRANT SELECT ON TABLE public.student_financial_hold_financial_hold_id_seq TO postgres;
GRANT UPDATE ON TABLE public.student_financial_hold_financial_hold_id_seq TO postgres;
GRANT USAGE ON TABLE public.student_financial_hold_financial_hold_id_seq TO postgres;
GRANT SELECT ON TABLE public.student_financial_hold_financial_hold_id_seq TO service_role;
GRANT UPDATE ON TABLE public.student_financial_hold_financial_hold_id_seq TO service_role;
GRANT USAGE ON TABLE public.student_financial_hold_financial_hold_id_seq TO service_role;
GRANT DELETE ON TABLE public.student_installment_schedule TO postgres;
GRANT INSERT ON TABLE public.student_installment_schedule TO postgres;
GRANT MAINTAIN ON TABLE public.student_installment_schedule TO postgres;
GRANT REFERENCES ON TABLE public.student_installment_schedule TO postgres;
GRANT SELECT ON TABLE public.student_installment_schedule TO postgres;
GRANT TRIGGER ON TABLE public.student_installment_schedule TO postgres;
GRANT TRUNCATE ON TABLE public.student_installment_schedule TO postgres;
GRANT UPDATE ON TABLE public.student_installment_schedule TO postgres;
GRANT DELETE ON TABLE public.student_installment_schedule TO service_role;
GRANT INSERT ON TABLE public.student_installment_schedule TO service_role;
GRANT MAINTAIN ON TABLE public.student_installment_schedule TO service_role;
GRANT REFERENCES ON TABLE public.student_installment_schedule TO service_role;
GRANT SELECT ON TABLE public.student_installment_schedule TO service_role;
GRANT TRIGGER ON TABLE public.student_installment_schedule TO service_role;
GRANT TRUNCATE ON TABLE public.student_installment_schedule TO service_role;
GRANT UPDATE ON TABLE public.student_installment_schedule TO service_role;
GRANT SELECT ON TABLE public.student_installment_schedule_student_installment_id_seq TO postgres;
GRANT UPDATE ON TABLE public.student_installment_schedule_student_installment_id_seq TO postgres;
GRANT USAGE ON TABLE public.student_installment_schedule_student_installment_id_seq TO postgres;
GRANT SELECT ON TABLE public.student_installment_schedule_student_installment_id_seq TO service_role;
GRANT UPDATE ON TABLE public.student_installment_schedule_student_installment_id_seq TO service_role;
GRANT USAGE ON TABLE public.student_installment_schedule_student_installment_id_seq TO service_role;
GRANT DELETE ON TABLE public.student_parent_guardian TO authenticated;
GRANT INSERT ON TABLE public.student_parent_guardian TO authenticated;
GRANT UPDATE ON TABLE public.student_parent_guardian TO authenticated;
GRANT DELETE ON TABLE public.student_parent_guardian TO postgres;
GRANT INSERT ON TABLE public.student_parent_guardian TO postgres;
GRANT MAINTAIN ON TABLE public.student_parent_guardian TO postgres;
GRANT REFERENCES ON TABLE public.student_parent_guardian TO postgres;
GRANT SELECT ON TABLE public.student_parent_guardian TO postgres;
GRANT TRIGGER ON TABLE public.student_parent_guardian TO postgres;
GRANT TRUNCATE ON TABLE public.student_parent_guardian TO postgres;
GRANT UPDATE ON TABLE public.student_parent_guardian TO postgres;
GRANT DELETE ON TABLE public.student_parent_guardian TO service_role;
GRANT INSERT ON TABLE public.student_parent_guardian TO service_role;
GRANT MAINTAIN ON TABLE public.student_parent_guardian TO service_role;
GRANT REFERENCES ON TABLE public.student_parent_guardian TO service_role;
GRANT SELECT ON TABLE public.student_parent_guardian TO service_role;
GRANT TRIGGER ON TABLE public.student_parent_guardian TO service_role;
GRANT TRUNCATE ON TABLE public.student_parent_guardian TO service_role;
GRANT UPDATE ON TABLE public.student_parent_guardian TO service_role;
GRANT SELECT ON TABLE public.student_parent_guardian_student_parent_guardian_id_seq TO postgres;
GRANT UPDATE ON TABLE public.student_parent_guardian_student_parent_guardian_id_seq TO postgres;
GRANT USAGE ON TABLE public.student_parent_guardian_student_parent_guardian_id_seq TO postgres;
GRANT SELECT ON TABLE public.student_parent_guardian_student_parent_guardian_id_seq TO service_role;
GRANT UPDATE ON TABLE public.student_parent_guardian_student_parent_guardian_id_seq TO service_role;
GRANT USAGE ON TABLE public.student_parent_guardian_student_parent_guardian_id_seq TO service_role;
GRANT DELETE ON TABLE public.student_previous_education TO authenticated;
GRANT INSERT ON TABLE public.student_previous_education TO authenticated;
GRANT UPDATE ON TABLE public.student_previous_education TO authenticated;
GRANT DELETE ON TABLE public.student_previous_education TO postgres;
GRANT INSERT ON TABLE public.student_previous_education TO postgres;
GRANT MAINTAIN ON TABLE public.student_previous_education TO postgres;
GRANT REFERENCES ON TABLE public.student_previous_education TO postgres;
GRANT SELECT ON TABLE public.student_previous_education TO postgres;
GRANT TRIGGER ON TABLE public.student_previous_education TO postgres;
GRANT TRUNCATE ON TABLE public.student_previous_education TO postgres;
GRANT UPDATE ON TABLE public.student_previous_education TO postgres;
GRANT DELETE ON TABLE public.student_previous_education TO service_role;
GRANT INSERT ON TABLE public.student_previous_education TO service_role;
GRANT MAINTAIN ON TABLE public.student_previous_education TO service_role;
GRANT REFERENCES ON TABLE public.student_previous_education TO service_role;
GRANT SELECT ON TABLE public.student_previous_education TO service_role;
GRANT TRIGGER ON TABLE public.student_previous_education TO service_role;
GRANT TRUNCATE ON TABLE public.student_previous_education TO service_role;
GRANT UPDATE ON TABLE public.student_previous_education TO service_role;
GRANT SELECT ON TABLE public.student_previous_education_previous_education_id_seq TO postgres;
GRANT UPDATE ON TABLE public.student_previous_education_previous_education_id_seq TO postgres;
GRANT USAGE ON TABLE public.student_previous_education_previous_education_id_seq TO postgres;
GRANT SELECT ON TABLE public.student_previous_education_previous_education_id_seq TO service_role;
GRANT UPDATE ON TABLE public.student_previous_education_previous_education_id_seq TO service_role;
GRANT USAGE ON TABLE public.student_previous_education_previous_education_id_seq TO service_role;
GRANT DELETE ON TABLE public.student_programme_enrolment TO authenticated;
GRANT INSERT ON TABLE public.student_programme_enrolment TO authenticated;
GRANT UPDATE ON TABLE public.student_programme_enrolment TO authenticated;
GRANT DELETE ON TABLE public.student_programme_enrolment TO postgres;
GRANT INSERT ON TABLE public.student_programme_enrolment TO postgres;
GRANT MAINTAIN ON TABLE public.student_programme_enrolment TO postgres;
GRANT REFERENCES ON TABLE public.student_programme_enrolment TO postgres;
GRANT SELECT ON TABLE public.student_programme_enrolment TO postgres;
GRANT TRIGGER ON TABLE public.student_programme_enrolment TO postgres;
GRANT TRUNCATE ON TABLE public.student_programme_enrolment TO postgres;
GRANT UPDATE ON TABLE public.student_programme_enrolment TO postgres;
GRANT DELETE ON TABLE public.student_programme_enrolment TO service_role;
GRANT INSERT ON TABLE public.student_programme_enrolment TO service_role;
GRANT MAINTAIN ON TABLE public.student_programme_enrolment TO service_role;
GRANT REFERENCES ON TABLE public.student_programme_enrolment TO service_role;
GRANT SELECT ON TABLE public.student_programme_enrolment TO service_role;
GRANT TRIGGER ON TABLE public.student_programme_enrolment TO service_role;
GRANT TRUNCATE ON TABLE public.student_programme_enrolment TO service_role;
GRANT UPDATE ON TABLE public.student_programme_enrolment TO service_role;
GRANT SELECT ON TABLE public.student_programme_enrolment_enrolment_id_seq TO postgres;
GRANT UPDATE ON TABLE public.student_programme_enrolment_enrolment_id_seq TO postgres;
GRANT USAGE ON TABLE public.student_programme_enrolment_enrolment_id_seq TO postgres;
GRANT SELECT ON TABLE public.student_programme_enrolment_enrolment_id_seq TO service_role;
GRANT UPDATE ON TABLE public.student_programme_enrolment_enrolment_id_seq TO service_role;
GRANT USAGE ON TABLE public.student_programme_enrolment_enrolment_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.student_register(p_student jsonb, p_enrolment jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.student_register(p_student jsonb, p_enrolment jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.student_register(p_student jsonb, p_enrolment jsonb) TO service_role;
GRANT DELETE ON TABLE public.student_residence TO authenticated;
GRANT INSERT ON TABLE public.student_residence TO authenticated;
GRANT UPDATE ON TABLE public.student_residence TO authenticated;
GRANT DELETE ON TABLE public.student_residence TO postgres;
GRANT INSERT ON TABLE public.student_residence TO postgres;
GRANT MAINTAIN ON TABLE public.student_residence TO postgres;
GRANT REFERENCES ON TABLE public.student_residence TO postgres;
GRANT SELECT ON TABLE public.student_residence TO postgres;
GRANT TRIGGER ON TABLE public.student_residence TO postgres;
GRANT TRUNCATE ON TABLE public.student_residence TO postgres;
GRANT UPDATE ON TABLE public.student_residence TO postgres;
GRANT DELETE ON TABLE public.student_residence TO service_role;
GRANT INSERT ON TABLE public.student_residence TO service_role;
GRANT MAINTAIN ON TABLE public.student_residence TO service_role;
GRANT REFERENCES ON TABLE public.student_residence TO service_role;
GRANT SELECT ON TABLE public.student_residence TO service_role;
GRANT TRIGGER ON TABLE public.student_residence TO service_role;
GRANT TRUNCATE ON TABLE public.student_residence TO service_role;
GRANT UPDATE ON TABLE public.student_residence TO service_role;
GRANT SELECT ON TABLE public.student_residence_student_residence_id_seq TO postgres;
GRANT UPDATE ON TABLE public.student_residence_student_residence_id_seq TO postgres;
GRANT USAGE ON TABLE public.student_residence_student_residence_id_seq TO postgres;
GRANT SELECT ON TABLE public.student_residence_student_residence_id_seq TO service_role;
GRANT UPDATE ON TABLE public.student_residence_student_residence_id_seq TO service_role;
GRANT USAGE ON TABLE public.student_residence_student_residence_id_seq TO service_role;
GRANT DELETE ON TABLE public.student_scholarship TO postgres;
GRANT INSERT ON TABLE public.student_scholarship TO postgres;
GRANT MAINTAIN ON TABLE public.student_scholarship TO postgres;
GRANT REFERENCES ON TABLE public.student_scholarship TO postgres;
GRANT SELECT ON TABLE public.student_scholarship TO postgres;
GRANT TRIGGER ON TABLE public.student_scholarship TO postgres;
GRANT TRUNCATE ON TABLE public.student_scholarship TO postgres;
GRANT UPDATE ON TABLE public.student_scholarship TO postgres;
GRANT DELETE ON TABLE public.student_scholarship TO service_role;
GRANT INSERT ON TABLE public.student_scholarship TO service_role;
GRANT MAINTAIN ON TABLE public.student_scholarship TO service_role;
GRANT REFERENCES ON TABLE public.student_scholarship TO service_role;
GRANT SELECT ON TABLE public.student_scholarship TO service_role;
GRANT TRIGGER ON TABLE public.student_scholarship TO service_role;
GRANT TRUNCATE ON TABLE public.student_scholarship TO service_role;
GRANT UPDATE ON TABLE public.student_scholarship TO service_role;
GRANT SELECT ON TABLE public.student_scholarship_student_scholarship_id_seq TO postgres;
GRANT UPDATE ON TABLE public.student_scholarship_student_scholarship_id_seq TO postgres;
GRANT USAGE ON TABLE public.student_scholarship_student_scholarship_id_seq TO postgres;
GRANT SELECT ON TABLE public.student_scholarship_student_scholarship_id_seq TO service_role;
GRANT UPDATE ON TABLE public.student_scholarship_student_scholarship_id_seq TO service_role;
GRANT USAGE ON TABLE public.student_scholarship_student_scholarship_id_seq TO service_role;
GRANT DELETE ON TABLE public.student_sponsorship TO postgres;
GRANT INSERT ON TABLE public.student_sponsorship TO postgres;
GRANT MAINTAIN ON TABLE public.student_sponsorship TO postgres;
GRANT REFERENCES ON TABLE public.student_sponsorship TO postgres;
GRANT SELECT ON TABLE public.student_sponsorship TO postgres;
GRANT TRIGGER ON TABLE public.student_sponsorship TO postgres;
GRANT TRUNCATE ON TABLE public.student_sponsorship TO postgres;
GRANT UPDATE ON TABLE public.student_sponsorship TO postgres;
GRANT DELETE ON TABLE public.student_sponsorship TO service_role;
GRANT INSERT ON TABLE public.student_sponsorship TO service_role;
GRANT MAINTAIN ON TABLE public.student_sponsorship TO service_role;
GRANT REFERENCES ON TABLE public.student_sponsorship TO service_role;
GRANT SELECT ON TABLE public.student_sponsorship TO service_role;
GRANT TRIGGER ON TABLE public.student_sponsorship TO service_role;
GRANT TRUNCATE ON TABLE public.student_sponsorship TO service_role;
GRANT UPDATE ON TABLE public.student_sponsorship TO service_role;
GRANT SELECT ON TABLE public.student_sponsorship_student_sponsorship_id_seq TO postgres;
GRANT UPDATE ON TABLE public.student_sponsorship_student_sponsorship_id_seq TO postgres;
GRANT USAGE ON TABLE public.student_sponsorship_student_sponsorship_id_seq TO postgres;
GRANT SELECT ON TABLE public.student_sponsorship_student_sponsorship_id_seq TO service_role;
GRANT UPDATE ON TABLE public.student_sponsorship_student_sponsorship_id_seq TO service_role;
GRANT USAGE ON TABLE public.student_sponsorship_student_sponsorship_id_seq TO service_role;
GRANT SELECT ON TABLE public.student_student_id_seq TO postgres;
GRANT UPDATE ON TABLE public.student_student_id_seq TO postgres;
GRANT USAGE ON TABLE public.student_student_id_seq TO postgres;
GRANT SELECT ON TABLE public.student_student_id_seq TO service_role;
GRANT UPDATE ON TABLE public.student_student_id_seq TO service_role;
GRANT USAGE ON TABLE public.student_student_id_seq TO service_role;
GRANT DELETE ON TABLE public.student_term_registration TO authenticated;
GRANT INSERT ON TABLE public.student_term_registration TO authenticated;
GRANT UPDATE ON TABLE public.student_term_registration TO authenticated;
GRANT DELETE ON TABLE public.student_term_registration TO postgres;
GRANT INSERT ON TABLE public.student_term_registration TO postgres;
GRANT MAINTAIN ON TABLE public.student_term_registration TO postgres;
GRANT REFERENCES ON TABLE public.student_term_registration TO postgres;
GRANT SELECT ON TABLE public.student_term_registration TO postgres;
GRANT TRIGGER ON TABLE public.student_term_registration TO postgres;
GRANT TRUNCATE ON TABLE public.student_term_registration TO postgres;
GRANT UPDATE ON TABLE public.student_term_registration TO postgres;
GRANT DELETE ON TABLE public.student_term_registration TO service_role;
GRANT INSERT ON TABLE public.student_term_registration TO service_role;
GRANT MAINTAIN ON TABLE public.student_term_registration TO service_role;
GRANT REFERENCES ON TABLE public.student_term_registration TO service_role;
GRANT SELECT ON TABLE public.student_term_registration TO service_role;
GRANT TRIGGER ON TABLE public.student_term_registration TO service_role;
GRANT TRUNCATE ON TABLE public.student_term_registration TO service_role;
GRANT UPDATE ON TABLE public.student_term_registration TO service_role;
GRANT SELECT ON TABLE public.student_term_registration_term_registration_id_seq TO postgres;
GRANT UPDATE ON TABLE public.student_term_registration_term_registration_id_seq TO postgres;
GRANT USAGE ON TABLE public.student_term_registration_term_registration_id_seq TO postgres;
GRANT SELECT ON TABLE public.student_term_registration_term_registration_id_seq TO service_role;
GRANT UPDATE ON TABLE public.student_term_registration_term_registration_id_seq TO service_role;
GRANT USAGE ON TABLE public.student_term_registration_term_registration_id_seq TO service_role;
GRANT DELETE ON TABLE public.student_term_result TO postgres;
GRANT INSERT ON TABLE public.student_term_result TO postgres;
GRANT MAINTAIN ON TABLE public.student_term_result TO postgres;
GRANT REFERENCES ON TABLE public.student_term_result TO postgres;
GRANT SELECT ON TABLE public.student_term_result TO postgres;
GRANT TRIGGER ON TABLE public.student_term_result TO postgres;
GRANT TRUNCATE ON TABLE public.student_term_result TO postgres;
GRANT UPDATE ON TABLE public.student_term_result TO postgres;
GRANT DELETE ON TABLE public.student_term_result TO service_role;
GRANT INSERT ON TABLE public.student_term_result TO service_role;
GRANT MAINTAIN ON TABLE public.student_term_result TO service_role;
GRANT REFERENCES ON TABLE public.student_term_result TO service_role;
GRANT SELECT ON TABLE public.student_term_result TO service_role;
GRANT TRIGGER ON TABLE public.student_term_result TO service_role;
GRANT TRUNCATE ON TABLE public.student_term_result TO service_role;
GRANT UPDATE ON TABLE public.student_term_result TO service_role;
GRANT SELECT ON TABLE public.student_term_result_student_term_result_id_seq TO postgres;
GRANT UPDATE ON TABLE public.student_term_result_student_term_result_id_seq TO postgres;
GRANT USAGE ON TABLE public.student_term_result_student_term_result_id_seq TO postgres;
GRANT SELECT ON TABLE public.student_term_result_student_term_result_id_seq TO service_role;
GRANT UPDATE ON TABLE public.student_term_result_student_term_result_id_seq TO service_role;
GRANT USAGE ON TABLE public.student_term_result_student_term_result_id_seq TO service_role;
GRANT DELETE ON TABLE public.student_user_account TO postgres;
GRANT INSERT ON TABLE public.student_user_account TO postgres;
GRANT MAINTAIN ON TABLE public.student_user_account TO postgres;
GRANT REFERENCES ON TABLE public.student_user_account TO postgres;
GRANT SELECT ON TABLE public.student_user_account TO postgres;
GRANT TRIGGER ON TABLE public.student_user_account TO postgres;
GRANT TRUNCATE ON TABLE public.student_user_account TO postgres;
GRANT UPDATE ON TABLE public.student_user_account TO postgres;
GRANT DELETE ON TABLE public.student_user_account TO service_role;
GRANT INSERT ON TABLE public.student_user_account TO service_role;
GRANT MAINTAIN ON TABLE public.student_user_account TO service_role;
GRANT REFERENCES ON TABLE public.student_user_account TO service_role;
GRANT SELECT ON TABLE public.student_user_account TO service_role;
GRANT TRIGGER ON TABLE public.student_user_account TO service_role;
GRANT TRUNCATE ON TABLE public.student_user_account TO service_role;
GRANT UPDATE ON TABLE public.student_user_account TO service_role;
GRANT DELETE ON TABLE public.study_mode TO authenticated;
GRANT INSERT ON TABLE public.study_mode TO authenticated;
GRANT UPDATE ON TABLE public.study_mode TO authenticated;
GRANT DELETE ON TABLE public.study_mode TO postgres;
GRANT INSERT ON TABLE public.study_mode TO postgres;
GRANT MAINTAIN ON TABLE public.study_mode TO postgres;
GRANT REFERENCES ON TABLE public.study_mode TO postgres;
GRANT SELECT ON TABLE public.study_mode TO postgres;
GRANT TRIGGER ON TABLE public.study_mode TO postgres;
GRANT TRUNCATE ON TABLE public.study_mode TO postgres;
GRANT UPDATE ON TABLE public.study_mode TO postgres;
GRANT DELETE ON TABLE public.study_mode TO service_role;
GRANT INSERT ON TABLE public.study_mode TO service_role;
GRANT MAINTAIN ON TABLE public.study_mode TO service_role;
GRANT REFERENCES ON TABLE public.study_mode TO service_role;
GRANT SELECT ON TABLE public.study_mode TO service_role;
GRANT TRIGGER ON TABLE public.study_mode TO service_role;
GRANT TRUNCATE ON TABLE public.study_mode TO service_role;
GRANT UPDATE ON TABLE public.study_mode TO service_role;
GRANT SELECT ON TABLE public.study_mode_study_mode_id_seq TO postgres;
GRANT UPDATE ON TABLE public.study_mode_study_mode_id_seq TO postgres;
GRANT USAGE ON TABLE public.study_mode_study_mode_id_seq TO postgres;
GRANT SELECT ON TABLE public.study_mode_study_mode_id_seq TO service_role;
GRANT UPDATE ON TABLE public.study_mode_study_mode_id_seq TO service_role;
GRANT USAGE ON TABLE public.study_mode_study_mode_id_seq TO service_role;
GRANT DELETE ON TABLE public.sub_caste TO authenticated;
GRANT INSERT ON TABLE public.sub_caste TO authenticated;
GRANT UPDATE ON TABLE public.sub_caste TO authenticated;
GRANT DELETE ON TABLE public.sub_caste TO postgres;
GRANT INSERT ON TABLE public.sub_caste TO postgres;
GRANT MAINTAIN ON TABLE public.sub_caste TO postgres;
GRANT REFERENCES ON TABLE public.sub_caste TO postgres;
GRANT SELECT ON TABLE public.sub_caste TO postgres;
GRANT TRIGGER ON TABLE public.sub_caste TO postgres;
GRANT TRUNCATE ON TABLE public.sub_caste TO postgres;
GRANT UPDATE ON TABLE public.sub_caste TO postgres;
GRANT DELETE ON TABLE public.sub_caste TO service_role;
GRANT INSERT ON TABLE public.sub_caste TO service_role;
GRANT MAINTAIN ON TABLE public.sub_caste TO service_role;
GRANT REFERENCES ON TABLE public.sub_caste TO service_role;
GRANT SELECT ON TABLE public.sub_caste TO service_role;
GRANT TRIGGER ON TABLE public.sub_caste TO service_role;
GRANT TRUNCATE ON TABLE public.sub_caste TO service_role;
GRANT UPDATE ON TABLE public.sub_caste TO service_role;
GRANT SELECT ON TABLE public.sub_caste_sub_caste_id_seq TO postgres;
GRANT UPDATE ON TABLE public.sub_caste_sub_caste_id_seq TO postgres;
GRANT USAGE ON TABLE public.sub_caste_sub_caste_id_seq TO postgres;
GRANT SELECT ON TABLE public.sub_caste_sub_caste_id_seq TO service_role;
GRANT UPDATE ON TABLE public.sub_caste_sub_caste_id_seq TO service_role;
GRANT USAGE ON TABLE public.sub_caste_sub_caste_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.svc_my_terms() TO authenticated;
GRANT EXECUTE ON FUNCTION public.svc_my_terms() TO postgres;
GRANT EXECUTE ON FUNCTION public.svc_my_terms() TO service_role;
GRANT EXECUTE ON FUNCTION public.svc_request_cancel(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.svc_request_cancel(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.svc_request_cancel(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.svc_request_create(p_kind text, p_term_id bigint, p_planned_date date, p_detail text, p_student_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.svc_request_create(p_kind text, p_term_id bigint, p_planned_date date, p_detail text, p_student_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.svc_request_create(p_kind text, p_term_id bigint, p_planned_date date, p_detail text, p_student_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.svc_request_decide(p_id bigint, p_action text, p_remarks text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.svc_request_decide(p_id bigint, p_action text, p_remarks text) TO postgres;
GRANT EXECUTE ON FUNCTION public.svc_request_decide(p_id bigint, p_action text, p_remarks text) TO service_role;
GRANT EXECUTE ON FUNCTION public.svc_request_list(p_kind text, p_status text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.svc_request_list(p_kind text, p_status text) TO postgres;
GRANT EXECUTE ON FUNCTION public.svc_request_list(p_kind text, p_status text) TO service_role;
GRANT EXECUTE ON FUNCTION public.teaching_populate_roster(p_cos_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.teaching_populate_roster(p_cos_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.teaching_populate_roster(p_cos_id bigint) TO service_role;
GRANT DELETE ON TABLE public.time_slot TO authenticated;
GRANT INSERT ON TABLE public.time_slot TO authenticated;
GRANT UPDATE ON TABLE public.time_slot TO authenticated;
GRANT DELETE ON TABLE public.time_slot TO postgres;
GRANT INSERT ON TABLE public.time_slot TO postgres;
GRANT MAINTAIN ON TABLE public.time_slot TO postgres;
GRANT REFERENCES ON TABLE public.time_slot TO postgres;
GRANT SELECT ON TABLE public.time_slot TO postgres;
GRANT TRIGGER ON TABLE public.time_slot TO postgres;
GRANT TRUNCATE ON TABLE public.time_slot TO postgres;
GRANT UPDATE ON TABLE public.time_slot TO postgres;
GRANT DELETE ON TABLE public.time_slot TO service_role;
GRANT INSERT ON TABLE public.time_slot TO service_role;
GRANT MAINTAIN ON TABLE public.time_slot TO service_role;
GRANT REFERENCES ON TABLE public.time_slot TO service_role;
GRANT SELECT ON TABLE public.time_slot TO service_role;
GRANT TRIGGER ON TABLE public.time_slot TO service_role;
GRANT TRUNCATE ON TABLE public.time_slot TO service_role;
GRANT UPDATE ON TABLE public.time_slot TO service_role;
GRANT SELECT ON TABLE public.time_slot_time_slot_id_seq TO postgres;
GRANT UPDATE ON TABLE public.time_slot_time_slot_id_seq TO postgres;
GRANT USAGE ON TABLE public.time_slot_time_slot_id_seq TO postgres;
GRANT SELECT ON TABLE public.time_slot_time_slot_id_seq TO service_role;
GRANT UPDATE ON TABLE public.time_slot_time_slot_id_seq TO service_role;
GRANT USAGE ON TABLE public.time_slot_time_slot_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.timetable_assignments(p_cos_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.timetable_assignments(p_cos_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.timetable_assignments(p_cos_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.timetable_entries(p_pto bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.timetable_entries(p_pto bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.timetable_entries(p_pto bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.timetable_generate_sessions(p_cos_id bigint, p_from date, p_to date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.timetable_generate_sessions(p_cos_id bigint, p_from date, p_to date) TO postgres;
GRANT EXECUTE ON FUNCTION public.timetable_generate_sessions(p_cos_id bigint, p_from date, p_to date) TO service_role;
GRANT EXECUTE ON FUNCTION public.timetable_offering_info(p_pto bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.timetable_offering_info(p_pto bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.timetable_offering_info(p_pto bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.timetable_offerings(p_term bigint, p_programme integer, p_limit integer, p_offset integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.timetable_offerings(p_term bigint, p_programme integer, p_limit integer, p_offset integer) TO postgres;
GRANT EXECUTE ON FUNCTION public.timetable_offerings(p_term bigint, p_programme integer, p_limit integer, p_offset integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.timetable_rooms() TO authenticated;
GRANT EXECUTE ON FUNCTION public.timetable_rooms() TO postgres;
GRANT EXECUTE ON FUNCTION public.timetable_rooms() TO service_role;
GRANT EXECUTE ON FUNCTION public.timetable_sections(p_pto bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.timetable_sections(p_pto bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.timetable_sections(p_pto bigint) TO service_role;
GRANT DELETE ON TABLE public.timetable_session TO authenticated;
GRANT INSERT ON TABLE public.timetable_session TO authenticated;
GRANT UPDATE ON TABLE public.timetable_session TO authenticated;
GRANT DELETE ON TABLE public.timetable_session TO postgres;
GRANT INSERT ON TABLE public.timetable_session TO postgres;
GRANT MAINTAIN ON TABLE public.timetable_session TO postgres;
GRANT REFERENCES ON TABLE public.timetable_session TO postgres;
GRANT SELECT ON TABLE public.timetable_session TO postgres;
GRANT TRIGGER ON TABLE public.timetable_session TO postgres;
GRANT TRUNCATE ON TABLE public.timetable_session TO postgres;
GRANT UPDATE ON TABLE public.timetable_session TO postgres;
GRANT DELETE ON TABLE public.timetable_session TO service_role;
GRANT INSERT ON TABLE public.timetable_session TO service_role;
GRANT MAINTAIN ON TABLE public.timetable_session TO service_role;
GRANT REFERENCES ON TABLE public.timetable_session TO service_role;
GRANT SELECT ON TABLE public.timetable_session TO service_role;
GRANT TRIGGER ON TABLE public.timetable_session TO service_role;
GRANT TRUNCATE ON TABLE public.timetable_session TO service_role;
GRANT UPDATE ON TABLE public.timetable_session TO service_role;
GRANT SELECT ON TABLE public.timetable_session_timetable_session_id_seq TO postgres;
GRANT UPDATE ON TABLE public.timetable_session_timetable_session_id_seq TO postgres;
GRANT USAGE ON TABLE public.timetable_session_timetable_session_id_seq TO postgres;
GRANT SELECT ON TABLE public.timetable_session_timetable_session_id_seq TO service_role;
GRANT UPDATE ON TABLE public.timetable_session_timetable_session_id_seq TO service_role;
GRANT USAGE ON TABLE public.timetable_session_timetable_session_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION public.timetable_slots() TO authenticated;
GRANT EXECUTE ON FUNCTION public.timetable_slots() TO postgres;
GRANT EXECUTE ON FUNCTION public.timetable_slots() TO service_role;
GRANT DELETE ON TABLE public.training_program_type TO authenticated;
GRANT INSERT ON TABLE public.training_program_type TO authenticated;
GRANT UPDATE ON TABLE public.training_program_type TO authenticated;
GRANT DELETE ON TABLE public.training_program_type TO postgres;
GRANT INSERT ON TABLE public.training_program_type TO postgres;
GRANT MAINTAIN ON TABLE public.training_program_type TO postgres;
GRANT REFERENCES ON TABLE public.training_program_type TO postgres;
GRANT SELECT ON TABLE public.training_program_type TO postgres;
GRANT TRIGGER ON TABLE public.training_program_type TO postgres;
GRANT TRUNCATE ON TABLE public.training_program_type TO postgres;
GRANT UPDATE ON TABLE public.training_program_type TO postgres;
GRANT DELETE ON TABLE public.training_program_type TO service_role;
GRANT INSERT ON TABLE public.training_program_type TO service_role;
GRANT MAINTAIN ON TABLE public.training_program_type TO service_role;
GRANT REFERENCES ON TABLE public.training_program_type TO service_role;
GRANT SELECT ON TABLE public.training_program_type TO service_role;
GRANT TRIGGER ON TABLE public.training_program_type TO service_role;
GRANT TRUNCATE ON TABLE public.training_program_type TO service_role;
GRANT UPDATE ON TABLE public.training_program_type TO service_role;
GRANT SELECT ON TABLE public.training_program_type_training_program_type_id_seq TO postgres;
GRANT UPDATE ON TABLE public.training_program_type_training_program_type_id_seq TO postgres;
GRANT USAGE ON TABLE public.training_program_type_training_program_type_id_seq TO postgres;
GRANT SELECT ON TABLE public.training_program_type_training_program_type_id_seq TO service_role;
GRANT UPDATE ON TABLE public.training_program_type_training_program_type_id_seq TO service_role;
GRANT USAGE ON TABLE public.training_program_type_training_program_type_id_seq TO service_role;
GRANT DELETE ON TABLE public.university TO authenticated;
GRANT INSERT ON TABLE public.university TO authenticated;
GRANT UPDATE ON TABLE public.university TO authenticated;
GRANT DELETE ON TABLE public.university TO postgres;
GRANT INSERT ON TABLE public.university TO postgres;
GRANT MAINTAIN ON TABLE public.university TO postgres;
GRANT REFERENCES ON TABLE public.university TO postgres;
GRANT SELECT ON TABLE public.university TO postgres;
GRANT TRIGGER ON TABLE public.university TO postgres;
GRANT TRUNCATE ON TABLE public.university TO postgres;
GRANT UPDATE ON TABLE public.university TO postgres;
GRANT DELETE ON TABLE public.university TO service_role;
GRANT INSERT ON TABLE public.university TO service_role;
GRANT MAINTAIN ON TABLE public.university TO service_role;
GRANT REFERENCES ON TABLE public.university TO service_role;
GRANT SELECT ON TABLE public.university TO service_role;
GRANT TRIGGER ON TABLE public.university TO service_role;
GRANT TRUNCATE ON TABLE public.university TO service_role;
GRANT UPDATE ON TABLE public.university TO service_role;
GRANT SELECT ON TABLE public.university_university_id_seq TO postgres;
GRANT UPDATE ON TABLE public.university_university_id_seq TO postgres;
GRANT USAGE ON TABLE public.university_university_id_seq TO postgres;
GRANT SELECT ON TABLE public.university_university_id_seq TO service_role;
GRANT UPDATE ON TABLE public.university_university_id_seq TO service_role;
GRANT USAGE ON TABLE public.university_university_id_seq TO service_role;
GRANT DELETE ON TABLE public.user_account TO postgres;
GRANT INSERT ON TABLE public.user_account TO postgres;
GRANT MAINTAIN ON TABLE public.user_account TO postgres;
GRANT REFERENCES ON TABLE public.user_account TO postgres;
GRANT SELECT ON TABLE public.user_account TO postgres;
GRANT TRIGGER ON TABLE public.user_account TO postgres;
GRANT TRUNCATE ON TABLE public.user_account TO postgres;
GRANT UPDATE ON TABLE public.user_account TO postgres;
GRANT DELETE ON TABLE public.user_account TO service_role;
GRANT INSERT ON TABLE public.user_account TO service_role;
GRANT MAINTAIN ON TABLE public.user_account TO service_role;
GRANT REFERENCES ON TABLE public.user_account TO service_role;
GRANT SELECT ON TABLE public.user_account TO service_role;
GRANT TRIGGER ON TABLE public.user_account TO service_role;
GRANT TRUNCATE ON TABLE public.user_account TO service_role;
GRANT UPDATE ON TABLE public.user_account TO service_role;
GRANT SELECT ON TABLE public.user_account_user_id_seq TO postgres;
GRANT UPDATE ON TABLE public.user_account_user_id_seq TO postgres;
GRANT USAGE ON TABLE public.user_account_user_id_seq TO postgres;
GRANT SELECT ON TABLE public.user_account_user_id_seq TO service_role;
GRANT UPDATE ON TABLE public.user_account_user_id_seq TO service_role;
GRANT USAGE ON TABLE public.user_account_user_id_seq TO service_role;
GRANT DELETE ON TABLE public.user_permission_override TO postgres;
GRANT INSERT ON TABLE public.user_permission_override TO postgres;
GRANT MAINTAIN ON TABLE public.user_permission_override TO postgres;
GRANT REFERENCES ON TABLE public.user_permission_override TO postgres;
GRANT SELECT ON TABLE public.user_permission_override TO postgres;
GRANT TRIGGER ON TABLE public.user_permission_override TO postgres;
GRANT TRUNCATE ON TABLE public.user_permission_override TO postgres;
GRANT UPDATE ON TABLE public.user_permission_override TO postgres;
GRANT DELETE ON TABLE public.user_permission_override TO service_role;
GRANT INSERT ON TABLE public.user_permission_override TO service_role;
GRANT MAINTAIN ON TABLE public.user_permission_override TO service_role;
GRANT REFERENCES ON TABLE public.user_permission_override TO service_role;
GRANT SELECT ON TABLE public.user_permission_override TO service_role;
GRANT TRIGGER ON TABLE public.user_permission_override TO service_role;
GRANT TRUNCATE ON TABLE public.user_permission_override TO service_role;
GRANT UPDATE ON TABLE public.user_permission_override TO service_role;
GRANT SELECT ON TABLE public.user_permission_override_user_permission_override_id_seq TO postgres;
GRANT UPDATE ON TABLE public.user_permission_override_user_permission_override_id_seq TO postgres;
GRANT USAGE ON TABLE public.user_permission_override_user_permission_override_id_seq TO postgres;
GRANT SELECT ON TABLE public.user_permission_override_user_permission_override_id_seq TO service_role;
GRANT UPDATE ON TABLE public.user_permission_override_user_permission_override_id_seq TO service_role;
GRANT USAGE ON TABLE public.user_permission_override_user_permission_override_id_seq TO service_role;
GRANT DELETE ON TABLE public.user_role_assignment TO postgres;
GRANT INSERT ON TABLE public.user_role_assignment TO postgres;
GRANT MAINTAIN ON TABLE public.user_role_assignment TO postgres;
GRANT REFERENCES ON TABLE public.user_role_assignment TO postgres;
GRANT SELECT ON TABLE public.user_role_assignment TO postgres;
GRANT TRIGGER ON TABLE public.user_role_assignment TO postgres;
GRANT TRUNCATE ON TABLE public.user_role_assignment TO postgres;
GRANT UPDATE ON TABLE public.user_role_assignment TO postgres;
GRANT DELETE ON TABLE public.user_role_assignment TO service_role;
GRANT INSERT ON TABLE public.user_role_assignment TO service_role;
GRANT MAINTAIN ON TABLE public.user_role_assignment TO service_role;
GRANT REFERENCES ON TABLE public.user_role_assignment TO service_role;
GRANT SELECT ON TABLE public.user_role_assignment TO service_role;
GRANT TRIGGER ON TABLE public.user_role_assignment TO service_role;
GRANT TRUNCATE ON TABLE public.user_role_assignment TO service_role;
GRANT UPDATE ON TABLE public.user_role_assignment TO service_role;
GRANT SELECT ON TABLE public.user_role_assignment_user_role_assignment_id_seq TO postgres;
GRANT UPDATE ON TABLE public.user_role_assignment_user_role_assignment_id_seq TO postgres;
GRANT USAGE ON TABLE public.user_role_assignment_user_role_assignment_id_seq TO postgres;
GRANT SELECT ON TABLE public.user_role_assignment_user_role_assignment_id_seq TO service_role;
GRANT UPDATE ON TABLE public.user_role_assignment_user_role_assignment_id_seq TO service_role;
GRANT USAGE ON TABLE public.user_role_assignment_user_role_assignment_id_seq TO service_role;
GRANT SELECT ON TABLE public.v_active_role_permission TO authenticated;
GRANT DELETE ON TABLE public.v_active_role_permission TO postgres;
GRANT INSERT ON TABLE public.v_active_role_permission TO postgres;
GRANT MAINTAIN ON TABLE public.v_active_role_permission TO postgres;
GRANT REFERENCES ON TABLE public.v_active_role_permission TO postgres;
GRANT SELECT ON TABLE public.v_active_role_permission TO postgres;
GRANT TRIGGER ON TABLE public.v_active_role_permission TO postgres;
GRANT TRUNCATE ON TABLE public.v_active_role_permission TO postgres;
GRANT UPDATE ON TABLE public.v_active_role_permission TO postgres;
GRANT DELETE ON TABLE public.v_active_role_permission TO service_role;
GRANT INSERT ON TABLE public.v_active_role_permission TO service_role;
GRANT MAINTAIN ON TABLE public.v_active_role_permission TO service_role;
GRANT REFERENCES ON TABLE public.v_active_role_permission TO service_role;
GRANT SELECT ON TABLE public.v_active_role_permission TO service_role;
GRANT TRIGGER ON TABLE public.v_active_role_permission TO service_role;
GRANT TRUNCATE ON TABLE public.v_active_role_permission TO service_role;
GRANT UPDATE ON TABLE public.v_active_role_permission TO service_role;
GRANT SELECT ON TABLE public.v_active_user_role TO authenticated;
GRANT DELETE ON TABLE public.v_active_user_role TO postgres;
GRANT INSERT ON TABLE public.v_active_user_role TO postgres;
GRANT MAINTAIN ON TABLE public.v_active_user_role TO postgres;
GRANT REFERENCES ON TABLE public.v_active_user_role TO postgres;
GRANT SELECT ON TABLE public.v_active_user_role TO postgres;
GRANT TRIGGER ON TABLE public.v_active_user_role TO postgres;
GRANT TRUNCATE ON TABLE public.v_active_user_role TO postgres;
GRANT UPDATE ON TABLE public.v_active_user_role TO postgres;
GRANT DELETE ON TABLE public.v_active_user_role TO service_role;
GRANT INSERT ON TABLE public.v_active_user_role TO service_role;
GRANT MAINTAIN ON TABLE public.v_active_user_role TO service_role;
GRANT REFERENCES ON TABLE public.v_active_user_role TO service_role;
GRANT SELECT ON TABLE public.v_active_user_role TO service_role;
GRANT TRIGGER ON TABLE public.v_active_user_role TO service_role;
GRANT TRUNCATE ON TABLE public.v_active_user_role TO service_role;
GRANT UPDATE ON TABLE public.v_active_user_role TO service_role;
GRANT SELECT ON TABLE public.v_effective_user_permission TO authenticated;
GRANT DELETE ON TABLE public.v_effective_user_permission TO postgres;
GRANT INSERT ON TABLE public.v_effective_user_permission TO postgres;
GRANT MAINTAIN ON TABLE public.v_effective_user_permission TO postgres;
GRANT REFERENCES ON TABLE public.v_effective_user_permission TO postgres;
GRANT SELECT ON TABLE public.v_effective_user_permission TO postgres;
GRANT TRIGGER ON TABLE public.v_effective_user_permission TO postgres;
GRANT TRUNCATE ON TABLE public.v_effective_user_permission TO postgres;
GRANT UPDATE ON TABLE public.v_effective_user_permission TO postgres;
GRANT DELETE ON TABLE public.v_effective_user_permission TO service_role;
GRANT INSERT ON TABLE public.v_effective_user_permission TO service_role;
GRANT MAINTAIN ON TABLE public.v_effective_user_permission TO service_role;
GRANT REFERENCES ON TABLE public.v_effective_user_permission TO service_role;
GRANT SELECT ON TABLE public.v_effective_user_permission TO service_role;
GRANT TRIGGER ON TABLE public.v_effective_user_permission TO service_role;
GRANT TRUNCATE ON TABLE public.v_effective_user_permission TO service_role;
GRANT UPDATE ON TABLE public.v_effective_user_permission TO service_role;
GRANT SELECT ON TABLE public.v_employee_previous_experience TO authenticated;
GRANT DELETE ON TABLE public.v_employee_previous_experience TO postgres;
GRANT INSERT ON TABLE public.v_employee_previous_experience TO postgres;
GRANT MAINTAIN ON TABLE public.v_employee_previous_experience TO postgres;
GRANT REFERENCES ON TABLE public.v_employee_previous_experience TO postgres;
GRANT SELECT ON TABLE public.v_employee_previous_experience TO postgres;
GRANT TRIGGER ON TABLE public.v_employee_previous_experience TO postgres;
GRANT TRUNCATE ON TABLE public.v_employee_previous_experience TO postgres;
GRANT UPDATE ON TABLE public.v_employee_previous_experience TO postgres;
GRANT DELETE ON TABLE public.v_employee_previous_experience TO service_role;
GRANT INSERT ON TABLE public.v_employee_previous_experience TO service_role;
GRANT MAINTAIN ON TABLE public.v_employee_previous_experience TO service_role;
GRANT REFERENCES ON TABLE public.v_employee_previous_experience TO service_role;
GRANT SELECT ON TABLE public.v_employee_previous_experience TO service_role;
GRANT TRIGGER ON TABLE public.v_employee_previous_experience TO service_role;
GRANT TRUNCATE ON TABLE public.v_employee_previous_experience TO service_role;
GRANT UPDATE ON TABLE public.v_employee_previous_experience TO service_role;
GRANT SELECT ON TABLE public.v_fee_collection_summary TO authenticated;
GRANT DELETE ON TABLE public.v_fee_collection_summary TO postgres;
GRANT INSERT ON TABLE public.v_fee_collection_summary TO postgres;
GRANT MAINTAIN ON TABLE public.v_fee_collection_summary TO postgres;
GRANT REFERENCES ON TABLE public.v_fee_collection_summary TO postgres;
GRANT SELECT ON TABLE public.v_fee_collection_summary TO postgres;
GRANT TRIGGER ON TABLE public.v_fee_collection_summary TO postgres;
GRANT TRUNCATE ON TABLE public.v_fee_collection_summary TO postgres;
GRANT UPDATE ON TABLE public.v_fee_collection_summary TO postgres;
GRANT DELETE ON TABLE public.v_fee_collection_summary TO service_role;
GRANT INSERT ON TABLE public.v_fee_collection_summary TO service_role;
GRANT MAINTAIN ON TABLE public.v_fee_collection_summary TO service_role;
GRANT REFERENCES ON TABLE public.v_fee_collection_summary TO service_role;
GRANT SELECT ON TABLE public.v_fee_collection_summary TO service_role;
GRANT TRIGGER ON TABLE public.v_fee_collection_summary TO service_role;
GRANT TRUNCATE ON TABLE public.v_fee_collection_summary TO service_role;
GRANT UPDATE ON TABLE public.v_fee_collection_summary TO service_role;
GRANT SELECT ON TABLE public.v_staff_activity_profile TO authenticated;
GRANT DELETE ON TABLE public.v_staff_activity_profile TO postgres;
GRANT INSERT ON TABLE public.v_staff_activity_profile TO postgres;
GRANT MAINTAIN ON TABLE public.v_staff_activity_profile TO postgres;
GRANT REFERENCES ON TABLE public.v_staff_activity_profile TO postgres;
GRANT SELECT ON TABLE public.v_staff_activity_profile TO postgres;
GRANT TRIGGER ON TABLE public.v_staff_activity_profile TO postgres;
GRANT TRUNCATE ON TABLE public.v_staff_activity_profile TO postgres;
GRANT UPDATE ON TABLE public.v_staff_activity_profile TO postgres;
GRANT DELETE ON TABLE public.v_staff_activity_profile TO service_role;
GRANT INSERT ON TABLE public.v_staff_activity_profile TO service_role;
GRANT MAINTAIN ON TABLE public.v_staff_activity_profile TO service_role;
GRANT REFERENCES ON TABLE public.v_staff_activity_profile TO service_role;
GRANT SELECT ON TABLE public.v_staff_activity_profile TO service_role;
GRANT TRIGGER ON TABLE public.v_staff_activity_profile TO service_role;
GRANT TRUNCATE ON TABLE public.v_staff_activity_profile TO service_role;
GRANT UPDATE ON TABLE public.v_staff_activity_profile TO service_role;
GRANT SELECT ON TABLE public.v_staff_evidence_search TO authenticated;
GRANT DELETE ON TABLE public.v_staff_evidence_search TO postgres;
GRANT INSERT ON TABLE public.v_staff_evidence_search TO postgres;
GRANT MAINTAIN ON TABLE public.v_staff_evidence_search TO postgres;
GRANT REFERENCES ON TABLE public.v_staff_evidence_search TO postgres;
GRANT SELECT ON TABLE public.v_staff_evidence_search TO postgres;
GRANT TRIGGER ON TABLE public.v_staff_evidence_search TO postgres;
GRANT TRUNCATE ON TABLE public.v_staff_evidence_search TO postgres;
GRANT UPDATE ON TABLE public.v_staff_evidence_search TO postgres;
GRANT DELETE ON TABLE public.v_staff_evidence_search TO service_role;
GRANT INSERT ON TABLE public.v_staff_evidence_search TO service_role;
GRANT MAINTAIN ON TABLE public.v_staff_evidence_search TO service_role;
GRANT REFERENCES ON TABLE public.v_staff_evidence_search TO service_role;
GRANT SELECT ON TABLE public.v_staff_evidence_search TO service_role;
GRANT TRIGGER ON TABLE public.v_staff_evidence_search TO service_role;
GRANT TRUNCATE ON TABLE public.v_staff_evidence_search TO service_role;
GRANT UPDATE ON TABLE public.v_staff_evidence_search TO service_role;
GRANT SELECT ON TABLE public.v_student_activity_evidence_search TO authenticated;
GRANT DELETE ON TABLE public.v_student_activity_evidence_search TO postgres;
GRANT INSERT ON TABLE public.v_student_activity_evidence_search TO postgres;
GRANT MAINTAIN ON TABLE public.v_student_activity_evidence_search TO postgres;
GRANT REFERENCES ON TABLE public.v_student_activity_evidence_search TO postgres;
GRANT SELECT ON TABLE public.v_student_activity_evidence_search TO postgres;
GRANT TRIGGER ON TABLE public.v_student_activity_evidence_search TO postgres;
GRANT TRUNCATE ON TABLE public.v_student_activity_evidence_search TO postgres;
GRANT UPDATE ON TABLE public.v_student_activity_evidence_search TO postgres;
GRANT DELETE ON TABLE public.v_student_activity_evidence_search TO service_role;
GRANT INSERT ON TABLE public.v_student_activity_evidence_search TO service_role;
GRANT MAINTAIN ON TABLE public.v_student_activity_evidence_search TO service_role;
GRANT REFERENCES ON TABLE public.v_student_activity_evidence_search TO service_role;
GRANT SELECT ON TABLE public.v_student_activity_evidence_search TO service_role;
GRANT TRIGGER ON TABLE public.v_student_activity_evidence_search TO service_role;
GRANT TRUNCATE ON TABLE public.v_student_activity_evidence_search TO service_role;
GRANT UPDATE ON TABLE public.v_student_activity_evidence_search TO service_role;
GRANT SELECT ON TABLE public.v_student_activity_profile TO authenticated;
GRANT DELETE ON TABLE public.v_student_activity_profile TO postgres;
GRANT INSERT ON TABLE public.v_student_activity_profile TO postgres;
GRANT MAINTAIN ON TABLE public.v_student_activity_profile TO postgres;
GRANT REFERENCES ON TABLE public.v_student_activity_profile TO postgres;
GRANT SELECT ON TABLE public.v_student_activity_profile TO postgres;
GRANT TRIGGER ON TABLE public.v_student_activity_profile TO postgres;
GRANT TRUNCATE ON TABLE public.v_student_activity_profile TO postgres;
GRANT UPDATE ON TABLE public.v_student_activity_profile TO postgres;
GRANT DELETE ON TABLE public.v_student_activity_profile TO service_role;
GRANT INSERT ON TABLE public.v_student_activity_profile TO service_role;
GRANT MAINTAIN ON TABLE public.v_student_activity_profile TO service_role;
GRANT REFERENCES ON TABLE public.v_student_activity_profile TO service_role;
GRANT SELECT ON TABLE public.v_student_activity_profile TO service_role;
GRANT TRIGGER ON TABLE public.v_student_activity_profile TO service_role;
GRANT TRUNCATE ON TABLE public.v_student_activity_profile TO service_role;
GRANT UPDATE ON TABLE public.v_student_activity_profile TO service_role;
GRANT SELECT ON TABLE public.v_student_fee_balance TO authenticated;
GRANT DELETE ON TABLE public.v_student_fee_balance TO postgres;
GRANT INSERT ON TABLE public.v_student_fee_balance TO postgres;
GRANT MAINTAIN ON TABLE public.v_student_fee_balance TO postgres;
GRANT REFERENCES ON TABLE public.v_student_fee_balance TO postgres;
GRANT SELECT ON TABLE public.v_student_fee_balance TO postgres;
GRANT TRIGGER ON TABLE public.v_student_fee_balance TO postgres;
GRANT TRUNCATE ON TABLE public.v_student_fee_balance TO postgres;
GRANT UPDATE ON TABLE public.v_student_fee_balance TO postgres;
GRANT DELETE ON TABLE public.v_student_fee_balance TO service_role;
GRANT INSERT ON TABLE public.v_student_fee_balance TO service_role;
GRANT MAINTAIN ON TABLE public.v_student_fee_balance TO service_role;
GRANT REFERENCES ON TABLE public.v_student_fee_balance TO service_role;
GRANT SELECT ON TABLE public.v_student_fee_balance TO service_role;
GRANT TRIGGER ON TABLE public.v_student_fee_balance TO service_role;
GRANT TRUNCATE ON TABLE public.v_student_fee_balance TO service_role;
GRANT UPDATE ON TABLE public.v_student_fee_balance TO service_role;
GRANT DELETE ON TABLE public.verification_status TO authenticated;
GRANT INSERT ON TABLE public.verification_status TO authenticated;
GRANT UPDATE ON TABLE public.verification_status TO authenticated;
GRANT DELETE ON TABLE public.verification_status TO postgres;
GRANT INSERT ON TABLE public.verification_status TO postgres;
GRANT MAINTAIN ON TABLE public.verification_status TO postgres;
GRANT REFERENCES ON TABLE public.verification_status TO postgres;
GRANT SELECT ON TABLE public.verification_status TO postgres;
GRANT TRIGGER ON TABLE public.verification_status TO postgres;
GRANT TRUNCATE ON TABLE public.verification_status TO postgres;
GRANT UPDATE ON TABLE public.verification_status TO postgres;
GRANT DELETE ON TABLE public.verification_status TO service_role;
GRANT INSERT ON TABLE public.verification_status TO service_role;
GRANT MAINTAIN ON TABLE public.verification_status TO service_role;
GRANT REFERENCES ON TABLE public.verification_status TO service_role;
GRANT SELECT ON TABLE public.verification_status TO service_role;
GRANT TRIGGER ON TABLE public.verification_status TO service_role;
GRANT TRUNCATE ON TABLE public.verification_status TO service_role;
GRANT UPDATE ON TABLE public.verification_status TO service_role;
GRANT SELECT ON TABLE public.verification_status_verification_status_id_seq TO postgres;
GRANT UPDATE ON TABLE public.verification_status_verification_status_id_seq TO postgres;
GRANT USAGE ON TABLE public.verification_status_verification_status_id_seq TO postgres;
GRANT SELECT ON TABLE public.verification_status_verification_status_id_seq TO service_role;
GRANT UPDATE ON TABLE public.verification_status_verification_status_id_seq TO service_role;
GRANT USAGE ON TABLE public.verification_status_verification_status_id_seq TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.activity_actor(p_student bigint, p_perm text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.activity_child_ok(p_activity_id bigint, p_detail_table text, p_perm_prefix text, p_action text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.admission_action_for(p_to text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.admission_authorize(p_application_id bigint, p_action text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.admission_transition_ok(p_from text, p_to text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.announcement_audience_ok(p_audience text, p_department integer) TO postgres;
GRANT DELETE ON TABLE sims_private.announcement_author TO postgres;
GRANT INSERT ON TABLE sims_private.announcement_author TO postgres;
GRANT MAINTAIN ON TABLE sims_private.announcement_author TO postgres;
GRANT REFERENCES ON TABLE sims_private.announcement_author TO postgres;
GRANT SELECT ON TABLE sims_private.announcement_author TO postgres;
GRANT TRIGGER ON TABLE sims_private.announcement_author TO postgres;
GRANT TRUNCATE ON TABLE sims_private.announcement_author TO postgres;
GRANT UPDATE ON TABLE sims_private.announcement_author TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.announcement_can(p_action text, p_department integer) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.announcement_check(p_type integer, p_department integer, p_title text, p_description text, p_from timestamp with time zone, p_to timestamp with time zone, p_audience text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.announcement_editable(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.announcement_editable(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.announcement_visible(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.announcement_visible(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.asm_authorize(p_course_offering_id bigint, p_module text, p_action text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.astatus(p_code text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.att_authorize_cos(p_cos_id bigint, p_module text, p_action text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.att_session_cos(p_session_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.audit_manual(p_module text, p_action text, p_table text, p_id bigint, p_before jsonb, p_after jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.audit_row() TO postgres;
GRANT DELETE ON TABLE sims_private.auth_identity_map TO postgres;
GRANT INSERT ON TABLE sims_private.auth_identity_map TO postgres;
GRANT MAINTAIN ON TABLE sims_private.auth_identity_map TO postgres;
GRANT REFERENCES ON TABLE sims_private.auth_identity_map TO postgres;
GRANT SELECT ON TABLE sims_private.auth_identity_map TO postgres;
GRANT TRIGGER ON TABLE sims_private.auth_identity_map TO postgres;
GRANT TRUNCATE ON TABLE sims_private.auth_identity_map TO postgres;
GRANT UPDATE ON TABLE sims_private.auth_identity_map TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.caller_has_role(p_role_code text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.can_campus(p_codes text[], p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.can_campus(p_codes text[], p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.can_campus(p_codes text[], p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.can_department(p_codes text[], p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.can_department(p_codes text[], p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.can_department(p_codes text[], p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.can_employee(p_codes text[], p_id bigint, p_write boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.can_employee(p_codes text[], p_id bigint, p_write boolean) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.can_employee(p_codes text[], p_id bigint, p_write boolean) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.can_global(p_codes text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.can_global(p_codes text[]) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.can_global(p_codes text[]) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.can_institution(p_codes text[], p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.can_institution(p_codes text[], p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.can_institution(p_codes text[], p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.can_programme(p_codes text[], p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.can_programme(p_codes text[], p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.can_programme(p_codes text[], p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.can_see_applicant(p_applicant_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.can_see_applicant(p_applicant_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.can_see_applicant(p_applicant_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.can_student(p_codes text[], p_id bigint, p_write boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.can_student(p_codes text[], p_id bigint, p_write boolean) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.can_student(p_codes text[], p_id bigint, p_write boolean) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.can_use_announcement_path(p_name text, p_write boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.can_use_announcement_path(p_name text, p_write boolean) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.can_use_employee_doc_path(p_name text, p_write boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.can_use_employee_doc_path(p_name text, p_write boolean) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.can_use_student_doc_path(p_name text, p_write boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.can_use_student_doc_path(p_name text, p_write boolean) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.can_user(p_codes text[], p_id bigint, p_write boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.can_user(p_codes text[], p_id bigint, p_write boolean) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.can_user(p_codes text[], p_id bigint, p_write boolean) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.check_employee_upload(p_employee bigint, p_key text, p_file_name text, p_mime text, p_size bigint, p_checksum text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.check_institution_fields(p jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.check_student_upload(p_student bigint, p_key text, p_file_name text, p_mime text, p_size bigint, p_checksum text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.course_result_published(p_course_registration_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.course_result_published(p_course_registration_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.course_result_published(p_course_registration_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.covers(p_codes text[], p_inst bigint, p_campus bigint, p_dept bigint, p_prog bigint, p_self_ok boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.covers(p_codes text[], p_inst bigint, p_campus bigint, p_dept bigint, p_prog bigint, p_self_ok boolean) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.covers(p_codes text[], p_inst bigint, p_campus bigint, p_dept bigint, p_prog bigint, p_self_ok boolean) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.current_employee_id() TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.current_employee_id() TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.current_employee_id() TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.current_student_id() TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.current_student_id() TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.current_student_id() TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.current_user_id() TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.current_user_id() TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.current_user_id() TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.doc_announcement_id(p_name text) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.doc_announcement_id(p_name text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.doc_employee_id(p_name text) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.doc_employee_id(p_name text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.doc_student_id(p_name text) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.doc_student_id(p_name text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.eff(p_codes text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.eff(p_codes text[]) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.eff(p_codes text[]) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.eff_set_of(p_codes text[]) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.emp_all_can(p_emp bigint, p_action text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.emp_can(p_emp bigint, p_resource text, p_action text, p_write boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.emp_can(p_emp bigint, p_resource text, p_action text, p_write boolean) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.emp_doc_rule_ok(p_doc bigint, p_need text) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.emp_doc_rule_ok(p_doc bigint, p_need text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.emp_is_owner(p_emp bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.emp_is_owner(p_emp bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.emp_sensitive_log(p_emp bigint, p_action text, p_entity text, p_id bigint, p_purpose text, p_doc bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.emp_sensitive_row(p_kind text, p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.emp_write_allowed(p_emp bigint, p_resource text, p_existing_status text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.employee_institution_immutable() TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.event_published(p_event_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.event_published(p_event_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.event_published(p_event_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.exec_dml(p_sql text, p_json jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.exec_dml_id(p_sql text, p_json jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.feedback_min_responses() TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.feedback_questionnaire_locked(p_questionnaire_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.feedback_rating_max() TO postgres;
GRANT DELETE ON TABLE sims_private.feedback_submission TO postgres;
GRANT INSERT ON TABLE sims_private.feedback_submission TO postgres;
GRANT MAINTAIN ON TABLE sims_private.feedback_submission TO postgres;
GRANT REFERENCES ON TABLE sims_private.feedback_submission TO postgres;
GRANT SELECT ON TABLE sims_private.feedback_submission TO postgres;
GRANT TRIGGER ON TABLE sims_private.feedback_submission TO postgres;
GRANT TRUNCATE ON TABLE sims_private.feedback_submission TO postgres;
GRANT UPDATE ON TABLE sims_private.feedback_submission TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.fin_assessment_student(p_assessment_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.fin_audit(p_action text, p_entity text, p_id bigint, p_old jsonb, p_new jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.fin_authorize(p_student_account_id bigint, p_resource text, p_action text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.fin_authorize_student(p_student_id bigint, p_resource text, p_action text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.fin_benefit_load(p_kind text, p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.fin_check_amount(p_amount numeric, p_what text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.fin_creator_is_caller(p_entity text, p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.fin_editable_item(p_item_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.fin_hold_active(p_student_id bigint, p_type text) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.fin_hold_active(p_student_id bigint, p_type text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.fin_next_receipt_number() TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.fin_refresh_status(p_item_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.fin_refunded_on_payment(p_payment_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.form_columns(p_table text, p_exclude text[]) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.fs_can(p_institution bigint, p_programme bigint, p_action text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.fs_load(p_id bigint, p_action text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.grievance_transition_ok(p_from text, p_to text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.has_any_grant(p_codes text[]) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.indexing_table(p_activity_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.is_active_member() TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.is_active_member() TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.is_active_member() TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.is_me_student(p_student bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.is_me_student(p_student bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.is_mentor_of(p_assignment_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.jwt_aal() TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.link_auth_user(p_auth_user uuid, p_user_id bigint, p_actor text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.link_auth_user(p_auth_user uuid, p_user_id bigint, p_actor text) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.mentoring_audit(p_action text, p_session_id bigint, p_assignment_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.mentoring_can_see(p_assignment_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.mentoring_check_session(p_date timestamp with time zone, p_observations text, p_action_plan text, p_follow_up date, p_status text, p_level text) TO postgres;
GRANT DELETE ON TABLE sims_private.mfa_recovery_attempt TO postgres;
GRANT INSERT ON TABLE sims_private.mfa_recovery_attempt TO postgres;
GRANT MAINTAIN ON TABLE sims_private.mfa_recovery_attempt TO postgres;
GRANT REFERENCES ON TABLE sims_private.mfa_recovery_attempt TO postgres;
GRANT SELECT ON TABLE sims_private.mfa_recovery_attempt TO postgres;
GRANT TRIGGER ON TABLE sims_private.mfa_recovery_attempt TO postgres;
GRANT TRUNCATE ON TABLE sims_private.mfa_recovery_attempt TO postgres;
GRANT UPDATE ON TABLE sims_private.mfa_recovery_attempt TO postgres;
GRANT DELETE ON TABLE sims_private.mfa_recovery_code TO postgres;
GRANT INSERT ON TABLE sims_private.mfa_recovery_code TO postgres;
GRANT MAINTAIN ON TABLE sims_private.mfa_recovery_code TO postgres;
GRANT REFERENCES ON TABLE sims_private.mfa_recovery_code TO postgres;
GRANT SELECT ON TABLE sims_private.mfa_recovery_code TO postgres;
GRANT TRIGGER ON TABLE sims_private.mfa_recovery_code TO postgres;
GRANT TRUNCATE ON TABLE sims_private.mfa_recovery_code TO postgres;
GRANT UPDATE ON TABLE sims_private.mfa_recovery_code TO postgres;
GRANT DELETE ON TABLE sims_private.mfa_required_role TO postgres;
GRANT INSERT ON TABLE sims_private.mfa_required_role TO postgres;
GRANT MAINTAIN ON TABLE sims_private.mfa_required_role TO postgres;
GRANT REFERENCES ON TABLE sims_private.mfa_required_role TO postgres;
GRANT SELECT ON TABLE sims_private.mfa_required_role TO postgres;
GRANT TRIGGER ON TABLE sims_private.mfa_required_role TO postgres;
GRANT TRUNCATE ON TABLE sims_private.mfa_required_role TO postgres;
GRANT UPDATE ON TABLE sims_private.mfa_required_role TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.mfa_setup_required(p_user bigint) TO postgres;
GRANT DELETE ON TABLE sims_private.notification_dismissal TO postgres;
GRANT INSERT ON TABLE sims_private.notification_dismissal TO postgres;
GRANT MAINTAIN ON TABLE sims_private.notification_dismissal TO postgres;
GRANT REFERENCES ON TABLE sims_private.notification_dismissal TO postgres;
GRANT SELECT ON TABLE sims_private.notification_dismissal TO postgres;
GRANT TRIGGER ON TABLE sims_private.notification_dismissal TO postgres;
GRANT TRUNCATE ON TABLE sims_private.notification_dismissal TO postgres;
GRANT UPDATE ON TABLE sims_private.notification_dismissal TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.notifications_all() TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_admission_application_application_id_admitted_student_id(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_admission_application_application_id_admitted_student_id(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_admission_application_application_id_admitted_student_id(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_announcement_announcement_id_department_id(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_announcement_announcement_id_department_id(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_announcement_announcement_id_department_id(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_assessment_component_assessment_component_id_c_556a8c03e6(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_assessment_component_assessment_component_id_c_556a8c03e6(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_assessment_component_assessment_component_id_c_556a8c03e6(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_building_building_id_campus_id(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_building_building_id_campus_id(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_building_building_id_campus_id(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_class_section_class_section_id_programme_term_offering_id(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_class_section_class_section_id_programme_term_offering_id(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_class_section_class_section_id_programme_term_offering_id(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_conference_activity_staff_activity_id_staff_activity_id(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_conference_activity_staff_activity_id_staff_activity_id(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_conference_activity_staff_activity_id_staff_activity_id(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_course_catalog_course_id_owning_department_id(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_course_catalog_course_id_owning_department_id(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_course_catalog_course_id_owning_department_id(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_course_offering_course_offering_id_programme_t_6af0a6bfe1(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_course_offering_course_offering_id_programme_t_6af0a6bfe1(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_course_offering_course_offering_id_programme_t_6af0a6bfe1(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_course_offering_section_course_offering_sectio_7deeb92c3b(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_course_offering_section_course_offering_sectio_7deeb92c3b(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_course_offering_section_course_offering_sectio_7deeb92c3b(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_course_offering_section_student_course_offerin_c13eb2db9e(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_course_offering_section_student_course_offerin_c13eb2db9e(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_course_offering_section_student_course_offerin_c13eb2db9e(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_curriculum_scheme_curriculum_scheme_id_programme_id(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_curriculum_scheme_curriculum_scheme_id_programme_id(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_curriculum_scheme_curriculum_scheme_id_programme_id(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_employee_document_employee_document_id_employee_id(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_employee_document_employee_document_id_employee_id(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_employee_document_employee_document_id_employee_id(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_evidence_document_evidence_document_id_staff_activity_id(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_evidence_document_evidence_document_id_staff_activity_id(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_evidence_document_evidence_document_id_staff_activity_id(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_fee_structure_fee_structure_id_programme_id(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_fee_structure_fee_structure_id_programme_id(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_fee_structure_fee_structure_id_programme_id(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_feedback_response_feedback_response_id_term_re_148ea414c7(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_feedback_response_feedback_response_id_term_re_148ea414c7(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_feedback_response_feedback_response_id_term_re_148ea414c7(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_funded_research_project_staff_activity_id_prin_85828402ed(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_funded_research_project_staff_activity_id_prin_85828402ed(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_funded_research_project_staff_activity_id_prin_85828402ed(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_grievance_grievance_id_student_id(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_grievance_grievance_id_student_id(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_grievance_grievance_id_student_id(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_journal_publication_staff_activity_id_staff_activity_id(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_journal_publication_staff_activity_id_staff_activity_id(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_journal_publication_staff_activity_id_staff_activity_id(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_mentor_assignment_mentor_assignment_id_student_id(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_mentor_assignment_mentor_assignment_id_student_id(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_mentor_assignment_mentor_assignment_id_student_id(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_payment_transaction_payment_transaction_id_stu_04cbabf9c9(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_payment_transaction_payment_transaction_id_stu_04cbabf9c9(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_payment_transaction_payment_transaction_id_stu_04cbabf9c9(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_programme_term_offering_programme_term_offerin_dd560b84f3(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_programme_term_offering_programme_term_offerin_dd560b84f3(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_programme_term_offering_programme_term_offerin_dd560b84f3(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_refund_request_refund_request_id_student_account_id(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_refund_request_refund_request_id_student_account_id(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_refund_request_refund_request_id_student_account_id(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_staff_activity_staff_activity_id_employee_id(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_staff_activity_staff_activity_id_employee_id(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_staff_activity_staff_activity_id_employee_id(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_staff_professional_contribution_staff_activity_a926f20bfe(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_staff_professional_contribution_staff_activity_a926f20bfe(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_staff_professional_contribution_staff_activity_a926f20bfe(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_activity_evidence_student_activity_evi_20620f7c4c(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_activity_evidence_student_activity_evi_20620f7c4c(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_activity_evidence_student_activity_evi_20620f7c4c(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_activity_student_activity_id_student_id(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_activity_student_activity_id_student_id(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_activity_student_activity_id_student_id(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_attendance_class_session_id_course_off_a5763429ec(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_attendance_class_session_id_course_off_a5763429ec(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_attendance_class_session_id_course_off_a5763429ec(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_course_registration_course_registratio_92ae207afd(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_course_registration_course_registratio_92ae207afd(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_course_registration_course_registratio_92ae207afd(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_fee_assessment_fee_assessment_id_stude_d877e246a8(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_fee_assessment_fee_assessment_id_stude_d877e246a8(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_fee_assessment_fee_assessment_id_stude_d877e246a8(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_fee_assessment_item_assessment_item_id_81c18f4ea9(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_fee_assessment_item_assessment_item_id_81c18f4ea9(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_fee_assessment_item_assessment_item_id_81c18f4ea9(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_fee_concession_student_concession_id_student_id(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_fee_concession_student_concession_id_student_id(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_fee_concession_student_concession_id_student_id(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_financial_account_student_account_id_student_id(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_financial_account_student_account_id_student_id(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_financial_account_student_account_id_student_id(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_programme_enrolment_enrolment_id_student_id(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_programme_enrolment_enrolment_id_student_id(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_programme_enrolment_enrolment_id_student_id(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_term_registration_term_registration_id_7e00744235(p_id bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_term_registration_term_registration_id_7e00744235(p_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.nx_student_term_registration_term_registration_id_7e00744235(p_id bigint) TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.other_super_admins(p_user_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.pii_decrypt(p bytea) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.pii_encrypt(p text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.pii_fingerprint(p text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.pii_key() TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.pk_column(p_table text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.programme_institution(p_programme integer) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.programme_of_cos(p_cos_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.programme_of_offering(p_course_offering_id bigint) TO postgres;
GRANT DELETE ON TABLE sims_private.receipt_counter TO postgres;
GRANT INSERT ON TABLE sims_private.receipt_counter TO postgres;
GRANT MAINTAIN ON TABLE sims_private.receipt_counter TO postgres;
GRANT REFERENCES ON TABLE sims_private.receipt_counter TO postgres;
GRANT SELECT ON TABLE sims_private.receipt_counter TO postgres;
GRANT TRIGGER ON TABLE sims_private.receipt_counter TO postgres;
GRANT TRUNCATE ON TABLE sims_private.receipt_counter TO postgres;
GRANT UPDATE ON TABLE sims_private.receipt_counter TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.ref_def(p_table text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.ref_tables() TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.request_header(p_name text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.section_can(p_kind text, p_perm_prefix text, p_action text, p_parent_id bigint) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.section_def(p_kind text, p_section text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.section_option_tables() TO postgres;
GRANT USAGE ON SCHEMA sims_private TO authenticated;
GRANT CREATE ON SCHEMA sims_private TO postgres;
GRANT USAGE ON SCHEMA sims_private TO postgres;
GRANT USAGE ON SCHEMA sims_private TO service_role;
GRANT EXECUTE ON FUNCTION sims_private.staff_actor(p_employee bigint, p_perm text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.staff_detail_table(p_type_code text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.staff_lookup_tables() TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.staff_option_tables() TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.storage_key_is_orphan(p_name text) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.storage_key_is_orphan(p_name text) TO postgres;
GRANT DELETE ON TABLE sims_private.student_service_request TO postgres;
GRANT INSERT ON TABLE sims_private.student_service_request TO postgres;
GRANT MAINTAIN ON TABLE sims_private.student_service_request TO postgres;
GRANT REFERENCES ON TABLE sims_private.student_service_request TO postgres;
GRANT SELECT ON TABLE sims_private.student_service_request TO postgres;
GRANT TRIGGER ON TABLE sims_private.student_service_request TO postgres;
GRANT TRUNCATE ON TABLE sims_private.student_service_request TO postgres;
GRANT UPDATE ON TABLE sims_private.student_service_request TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.svc_hold_check(p_student bigint, p_kind text, p_step text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.user_id_any_aal() TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.verhoeff_valid(p text) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.verhoeff_valid(p text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.vstatus(p_code text) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.write_detail(p_table text, p_key_col text, p_id bigint, p_detail jsonb, p_insert boolean) TO postgres;
GRANT EXECUTE ON FUNCTION sims_private.write_row(p_table text, p_pk text, p_parent_col text, p_parent_id bigint, p_id bigint, p jsonb) TO postgres;
GRANT SELECT (academic_term_id, academic_year_id, term_code, term_name, term_type, start_date, end_date, registration_start_date, registration_end_date, status) ON TABLE public.academic_term TO authenticated;
GRANT SELECT (academic_year_id, year_code, start_date, end_date, status) ON TABLE public.academic_year TO authenticated;
GRANT SELECT (access_action_id, action_code, action_name, description, is_active) ON TABLE public.access_action TO authenticated;
GRANT SELECT (access_module_id, module_code, module_name, description, display_order, is_active) ON TABLE public.access_module TO authenticated;
GRANT SELECT (access_resource_id, access_module_id, resource_code, resource_name, description, is_active) ON TABLE public.access_resource TO authenticated;
GRANT SELECT (activity_audit_id, user_id, module_code, action_code, entity_name, entity_id, activity_at, ip_address, request_identifier, before_values, after_values, details) ON TABLE public.activity_audit TO authenticated;
GRANT SELECT (activity_evidence_requirement_id, activity_type_id, evidence_type_id, document_type_id, is_mandatory, minimum_files, maximum_files, valid_from, valid_to, is_active) ON TABLE public.activity_evidence_requirement TO authenticated;
GRANT SELECT (activity_type_id, activity_type_code, activity_type_name, activity_group, description, is_active) ON TABLE public.activity_type TO authenticated;
GRANT SELECT (admission_applicant_id, first_name, middle_name, last_name, display_name, date_of_birth, gender_id, primary_email, primary_phone, nationality_country_id, social_category_id, caste_id, sub_caste_id, created_at, updated_at) ON TABLE public.admission_applicant TO authenticated;
GRANT SELECT (application_id, application_number, admission_applicant_id, admitted_student_id, programme_id, specialization_id, academic_year_id, admission_category_id, application_date, application_status, eligibility_status, remarks, created_at, updated_at) ON TABLE public.admission_application TO authenticated;
GRANT SELECT (admission_category_id, category_code, category_name, description, is_active) ON TABLE public.admission_category TO authenticated;
GRANT SELECT (admission_payment_id, application_id, payment_transaction_id, created_at) ON TABLE public.admission_payment TO authenticated;
GRANT SELECT (announcement_id, announcement_type_id, department_id, title, description, publish_from, publish_to, approval_status, audience_type, created_at) ON TABLE public.announcement TO authenticated;
GRANT SELECT (announcement_id, file_object_id, display_order) ON TABLE public.announcement_attachment TO authenticated;
GRANT SELECT (announcement_type_id, type_code, type_name, is_active) ON TABLE public.announcement_type TO authenticated;
GRANT SELECT (approval_status_id, status_code, status_name, is_terminal, is_active) ON TABLE public.approval_status TO authenticated;
GRANT SELECT (assessment_component_id, course_offering_id, component_code, component_name, component_type, maximum_marks, weightage_percent, is_mandatory) ON TABLE public.assessment_component TO authenticated;
GRANT SELECT (assessment_event_id, assessment_component_id, course_offering_id, event_number, event_title, assessment_date, start_time, end_time, maximum_marks, reduced_maximum_marks, details, status) ON TABLE public.assessment_event TO authenticated;
GRANT SELECT (attendance_correction_id, class_session_id, course_offering_section_student_id, old_status_id, requested_status_id, reason, request_status, requested_at, resolved_at) ON TABLE public.attendance_correction_request TO authenticated;
GRANT SELECT (attendance_status_id, status_code, status_name, counts_as_present, is_active) ON TABLE public.attendance_status TO authenticated;
GRANT SELECT (award_category_id, category_code, category_name, is_active) ON TABLE public.award_category TO authenticated;
GRANT SELECT (awarding_body_id, awarding_body_type_id, awarding_body_name, university_type, city, state_id, country_id, website_url, is_active, created_at, updated_at) ON TABLE public.awarding_body TO authenticated;
GRANT SELECT (awarding_body_type_id, type_code, type_name, is_active) ON TABLE public.awarding_body_type TO authenticated;
GRANT SELECT (blood_group_id, blood_group_code, is_active) ON TABLE public.blood_group TO authenticated;
GRANT SELECT (building_id, campus_id, building_code, building_name, is_active) ON TABLE public.building TO authenticated;
GRANT SELECT (campus_id, institution_id, campus_code, campus_name, address_line_1, address_line_2, city, state_id, postal_code, phone, email, is_active) ON TABLE public.campus TO authenticated;
GRANT SELECT (caste_id, social_category_id, caste_code, caste_name, is_active) ON TABLE public.caste TO authenticated;
GRANT SELECT (certificate_request_id, request_number, student_id, certificate_type_id, requested_at, purpose, request_status, issued_at, certificate_number, file_object_id) ON TABLE public.certificate_request TO authenticated;
GRANT SELECT (certificate_type_id, certificate_code, certificate_name, is_active) ON TABLE public.certificate_type TO authenticated;
GRANT SELECT (class_batch_id, class_section_id, batch_code, batch_name, capacity, is_active) ON TABLE public.class_batch TO authenticated;
GRANT SELECT (class_section_id, programme_term_offering_id, section_code, section_name, capacity, home_room_id, is_active) ON TABLE public.class_section TO authenticated;
GRANT SELECT (class_session_id, course_offering_section_id, faculty_assignment_id, timetable_session_id, session_date, start_time, end_time, room_id, session_type, planned_topic, topic_covered, class_number, session_status, created_at) ON TABLE public.class_session TO authenticated;
GRANT SELECT (staff_activity_id, cocurricular_category_id, event_name, organizer_id, institution_organization_id, event_date, venue_name, city, state_id, country_id, achievement_award, contribution_details) ON TABLE public.cocurricular_activity TO authenticated;
GRANT SELECT (cocurricular_category_id, category_code, category_name, is_active) ON TABLE public.cocurricular_category TO authenticated;
GRANT SELECT (concession_type_id, concession_code, concession_name, concession_basis, maximum_percentage, maximum_amount, approval_required, is_active) ON TABLE public.concession_type TO authenticated;
GRANT SELECT (staff_activity_id, conference_event_id, conference_contribution_type_id, publication_type_id, paper_title, abstract_text, proceedings_title, proceedings_volume, proceedings_issue, page_from, page_to, isbn, issn, doi, proceedings_url, presentation_title, award_name, award_details, award_date) ON TABLE public.conference_activity TO authenticated;
GRANT SELECT (staff_activity_id, indexing_agency_id, indexing_status, source_url, remarks) ON TABLE public.conference_activity_indexing TO authenticated;
GRANT SELECT (conference_contribution_type_id, type_code, type_name, is_active) ON TABLE public.conference_contribution_type TO authenticated;
GRANT SELECT (conference_event_id, conference_title, conference_edition, organizer_id, sponsoring_organization_id, proceedings_publisher_id, participation_level_id, event_mode_id, venue_name, city, state_id, country_id, start_date, end_date, conference_website, brochure_url, is_active, created_at, updated_at) ON TABLE public.conference_event TO authenticated;
GRANT SELECT (confidentiality_level_id, level_code, level_name, display_order, is_active) ON TABLE public.confidentiality_level TO authenticated;
GRANT SELECT (staff_activity_id, consultancy_title, client_organization_id, principal_consultant_employee_id, consultancy_type, work_order_number, agreement_number, purchase_order_number, project_start_date, completion_date, consultancy_amount, amount_received, faculty_incentive_share, currency_code, deliverables, status, client_feedback) ON TABLE public.consultancy_project TO authenticated;
GRANT SELECT (country_id, iso_code, country_name, is_active) ON TABLE public.country TO authenticated;
GRANT SELECT (course_id, owning_department_id, course_category_id, course_code, course_title, short_title, course_type, lecture_hours, tutorial_hours, practical_hours, self_study_hours, credits, effective_from, effective_to, is_active) ON TABLE public.course_catalog TO authenticated;
GRANT SELECT (course_category_id, category_code, category_name, is_graded, contributes_to_gpa, is_active) ON TABLE public.course_category TO authenticated;
GRANT SELECT (course_offering_id, programme_term_offering_id, curriculum_course_id, course_id, offering_code, registration_capacity, status) ON TABLE public.course_offering TO authenticated;
GRANT SELECT (course_offering_section_id, course_offering_id, programme_term_offering_id, class_section_id, class_batch_id, class_batch_key, session_type) ON TABLE public.course_offering_section TO authenticated;
GRANT SELECT (course_offering_section_student_id, course_offering_section_id, course_registration_id, course_offering_id, roster_status, effective_from, effective_to) ON TABLE public.course_offering_section_student TO authenticated;
GRANT SELECT (course_id, prerequisite_course_id, minimum_grade) ON TABLE public.course_prerequisite TO authenticated;
GRANT SELECT (curriculum_course_id, curriculum_scheme_id, semester_id, course_id, course_category_id, is_mandatory, elective_group_code, display_order, internal_max_marks, external_max_marks, passing_marks, exam_duration_minutes) ON TABLE public.curriculum_course TO authenticated;
GRANT SELECT (curriculum_scheme_id, programme_id, specialization_id, scheme_code, scheme_name, regulation_year, total_credits, effective_from, effective_to, status) ON TABLE public.curriculum_scheme TO authenticated;
GRANT SELECT (department_id, campus_id, department_code, department_name, department_type, is_active) ON TABLE public.department TO authenticated;
GRANT SELECT (designation_id, staff_category_id, designation_code, designation_name, description, is_active) ON TABLE public.designation TO authenticated;
GRANT SELECT (document_type_id, document_code, document_name, requires_verification, is_active) ON TABLE public.document_type TO authenticated;
GRANT SELECT (education_institution_id, education_institution_type_id, institution_name, city, state_id, country_id, website_url, is_active, created_at, updated_at) ON TABLE public.education_institution TO authenticated;
GRANT SELECT (education_institution_type_id, type_code, type_name, is_active) ON TABLE public.education_institution_type TO authenticated;
GRANT SELECT (employee_id, institution_id, employment_source_id, external_agency_id, employee_number, agency_employee_number, first_name, middle_name, last_name, display_name, date_of_birth, gender_id, blood_group_id, primary_email, primary_phone, nationality_country_id, religion_id, social_category_id, caste_id, sub_caste_id, photo_url, joining_date, employment_type, employment_status, created_at, updated_at) ON TABLE public.employee TO authenticated;
GRANT SELECT (employee_aadhaar_id, employee_id, aadhaar_number_fingerprint, aadhaar_number_last4, aadhaar_number_masked, name_as_per_aadhaar, format_validated, verification_status, verified_by_user_id, verified_at, verification_remarks, collection_purpose, remarks, created_by_user_id, updated_by_user_id, created_at, updated_at, deleted_at) ON TABLE public.employee_aadhaar TO authenticated;
GRANT SELECT (employee_address_id, employee_id, address_type, address_line_1, address_line_2, city, state_id, country_id, postal_code, valid_from, valid_to, is_primary, current_primary_employee_id) ON TABLE public.employee_address TO authenticated;
GRANT SELECT (employee_assignment_id, employee_id, campus_id, department_id, designation_id, start_date, end_date, is_primary, current_primary_employee_id) ON TABLE public.employee_assignment TO authenticated;
GRANT SELECT (employee_bank_account_id, employee_id, account_holder_name, bank_name, branch_name, account_number_fingerprint, account_number_last4, account_number_confirmed, account_type, ifsc_code, micr_code, branch_code, bank_address, city, state_id, country_id, upi_id, is_salary_account, is_primary, account_status, verification_status, verified_by_user_id, verified_at, verification_remarks, effective_from, effective_to, remarks, created_by_user_id, updated_by_user_id, created_at, updated_at, deleted_at, active_primary_employee_id) ON TABLE public.employee_bank_account TO authenticated;
GRANT SELECT (employee_id, course_id, competency_level, valid_from, valid_to) ON TABLE public.employee_competency TO authenticated;
GRANT SELECT (employee_document_id, employee_id, document_scope, employee_qualification_id, employee_previous_employment_id, employee_bank_account_id, employee_pan_id, employee_aadhaar_id, employee_document_category_id, document_type_id, file_object_id, document_title, document_number, issue_date, expiry_date, version_number, supersedes_employee_document_id, verification_status, verified_by_user_id, verified_at, verification_remarks, approval_status, approved_by_user_id, approved_at, approval_remarks, confidentiality_level, is_private, is_active, created_by_user_id, updated_by_user_id, deleted_by_user_id, created_at, updated_at, deleted_at) ON TABLE public.employee_document TO authenticated;
GRANT SELECT (employee_document_access_rule_id, employee_document_id, role_id, user_id, can_view, can_download, can_update, can_verify, can_approve, valid_from, valid_to, granted_by_user_id, created_at) ON TABLE public.employee_document_access_rule TO authenticated;
GRANT SELECT (employee_document_category_id, category_code, category_name, default_confidentiality, requires_verification, requires_approval, is_active) ON TABLE public.employee_document_category TO authenticated;
GRANT SELECT (employee_pan_id, employee_id, pan_number_fingerprint, pan_number_masked, name_as_per_pan, pan_issue_date, pan_issue_details, format_validated, verification_status, verified_by_user_id, verified_at, verification_remarks, remarks, created_by_user_id, updated_by_user_id, created_at, updated_at, deleted_at) ON TABLE public.employee_pan TO authenticated;
GRANT SELECT (employee_previous_employment_id, employee_id, previous_organization_id, department_division, designation, employment_type, nature_of_work, employment_start_date, employment_end_date, experience_days, last_drawn_salary, salary_currency_code, reason_for_leaving, reporting_authority_name, reporting_authority_designation, reporting_authority_phone, reporting_authority_email, remarks, created_by_user_id, updated_by_user_id, created_at, updated_at, deleted_at) ON TABLE public.employee_previous_employment TO authenticated;
GRANT SELECT (employee_qualification_id, employee_id, qualification_level_id, education_institution_id, awarding_body_id, study_mode_id, degree_certificate_name, specialization, course_program_name, start_date, start_year, completion_date, completion_year, passing_year, registration_roll_number, result, class_grade, cgpa, cgpa_scale, percentage, maximum_marks, marks_obtained, qualification_status, is_highest_qualification, active_highest_employee_id, remarks, created_by_user_id, updated_by_user_id, created_at, updated_at, deleted_at) ON TABLE public.employee_qualification TO authenticated;
GRANT SELECT (employee_sensitive_access_audit_id, user_id, employee_id, action_code, entity_type, entity_id, employee_document_id, access_purpose, was_successful, failure_reason, ip_address, user_agent, request_identifier, accessed_at) ON TABLE public.employee_sensitive_access_audit TO authenticated;
GRANT SELECT (employee_id, user_id, linked_at) ON TABLE public.employee_user_account TO authenticated;
GRANT SELECT (employment_source_id, source_code, source_name, is_external, description, is_active, created_at, updated_at) ON TABLE public.employment_source TO authenticated;
GRANT SELECT (enrolment_status_history_id, enrolment_id, old_status, new_status, effective_date, reason) ON TABLE public.enrolment_status_history TO authenticated;
GRANT SELECT (event_mode_id, mode_code, mode_name, is_active) ON TABLE public.event_mode TO authenticated;
GRANT SELECT (evidence_document_id, staff_activity_id, document_type_id, evidence_type_id, confidentiality_level_id, document_title, description, academic_year_id, document_issue_date, issuing_authority, issuing_organization_id, certificate_document_number, expiry_date, verification_status_id, verified_by_user_id, verified_at, verification_remarks, approval_status_id, approved_by_user_id, approved_at, rejection_reason, current_version_number, is_active, created_by_user_id, updated_by_user_id, created_at, updated_at, deleted_at, deleted_by_user_id, deletion_reason) ON TABLE public.evidence_document TO authenticated;
GRANT SELECT (evidence_document_audit_id, evidence_document_id, evidence_document_version_id, action_code, performed_by_user_id, performed_at, ip_address, user_agent, before_values, after_values, remarks) ON TABLE public.evidence_document_audit TO authenticated;
GRANT SELECT (evidence_document_id, evidence_tag_id) ON TABLE public.evidence_document_tag TO authenticated;
GRANT SELECT (evidence_document_version_id, evidence_document_id, version_number, file_object_id, change_reason, uploaded_by_user_id, uploaded_at, is_current) ON TABLE public.evidence_document_version TO authenticated;
GRANT SELECT (evidence_tag_id, tag_code, tag_name, is_active) ON TABLE public.evidence_tag TO authenticated;
GRANT SELECT (evidence_type_id, evidence_type_code, evidence_type_name, description, is_active) ON TABLE public.evidence_type TO authenticated;
GRANT SELECT (external_agency_id, institution_id, agency_code, agency_name, service_type, contact_person, phone, email, contract_start_date, contract_end_date, address, is_active, created_at, updated_at) ON TABLE public.external_agency TO authenticated;
GRANT SELECT (organization_id, organization_code, organization_name, short_name, website_url, email, phone, address_line_1, address_line_2, city, state_id, country_id, postal_code, is_active, created_at, updated_at) ON TABLE public.external_organization TO authenticated;
GRANT SELECT (organization_id, organization_type_id) ON TABLE public.external_organization_type TO authenticated;
GRANT SELECT (staff_activity_id, extracurricular_category_id, event_name, organizer_id, institution_organization_id, event_date, venue_name, city, state_id, country_id, award_recognition, activity_details) ON TABLE public.extracurricular_activity TO authenticated;
GRANT SELECT (extracurricular_category_id, category_code, category_name, is_active) ON TABLE public.extracurricular_category TO authenticated;
GRANT SELECT (faculty_assignment_id, course_offering_section_id, employee_id, assignment_role, workload_hours, start_date, end_date, assignment_status) ON TABLE public.faculty_course_assignment TO authenticated;
GRANT SELECT (staff_activity_id, organization_id, internship_title, internship_domain, industry_sector_id, location_text, mentor_name, mentor_designation, mentor_email, work_undertaken, technologies_tools, outcomes, stipend_incentive_type, stipend_incentive_amount, currency_code, funding_source, mou_reference, collaboration_reference) ON TABLE public.faculty_internship TO authenticated;
GRANT SELECT (fee_audit_id, user_id, action_code, entity_name, entity_id, old_values, new_values, ip_address, performed_at) ON TABLE public.fee_activity_audit TO authenticated;
GRANT SELECT (fee_adjustment_id, adjustment_number, student_account_id, assessment_item_id, adjustment_type, adjustment_date, adjustment_amount, reason, approval_status, approved_by, approved_at) ON TABLE public.fee_adjustment TO authenticated;
GRANT SELECT (assessment_benefit_id, assessment_item_id, benefit_type, student_concession_id, student_scholarship_id, student_sponsorship_id, benefit_amount, applied_date, approved_by) ON TABLE public.fee_assessment_benefit TO authenticated;
GRANT SELECT (fee_category_id, category_code, category_name, description, display_order, is_refundable, is_active, created_at, updated_at) ON TABLE public.fee_category TO authenticated;
GRANT SELECT (charge_source_id, assessment_item_id, source_module, source_entity, source_entity_id) ON TABLE public.fee_charge_source TO authenticated;
GRANT SELECT (fee_receipt_id, receipt_number, payment_transaction_id, receipt_date, receipt_amount, receipt_status, issued_by, cancelled_by, cancelled_at, cancellation_reason, original_receipt_id) ON TABLE public.fee_receipt TO authenticated;
GRANT SELECT (fee_refund_id, refund_request_id, refund_transaction_number, refund_date, refund_amount, refund_mode_id, bank_reference_number, processed_by, refund_status, remarks) ON TABLE public.fee_refund TO authenticated;
GRANT SELECT (fee_structure_id, structure_code, structure_name, institution_id, campus_id, programme_id, specialization_id, academic_year_id, admission_category_id, version_number, effective_from, effective_to, approval_status, approved_by, approved_at, remarks, is_active, created_at, updated_at) ON TABLE public.fee_structure TO authenticated;
GRANT SELECT (fee_structure_item_id, fee_structure_id, fee_type_id, semester_id, academic_term_id, semester_key, academic_term_key, amount, due_date, due_days_from_registration, installment_allowed, waiver_allowed, late_fee_rule_id, display_order, remarks) ON TABLE public.fee_structure_item TO authenticated;
GRANT SELECT (fee_type_id, fee_category_id, fee_code, fee_name, description, charge_frequency, ledger_account_id, is_mandatory, is_refundable, is_taxable, is_active, created_at, updated_at) ON TABLE public.fee_type TO authenticated;
GRANT SELECT (feedback_choice_id, feedback_question_id, choice_text, score, display_order, is_active) ON TABLE public.feedback_choice TO authenticated;
GRANT SELECT (feedback_cycle_id, questionnaire_id, academic_term_id, cycle_name, start_at, end_at, result_visibility, status) ON TABLE public.feedback_cycle TO authenticated;
GRANT SELECT (feedback_question_id, feedback_category_id, question_text, response_type, is_active) ON TABLE public.feedback_question TO authenticated;
GRANT SELECT (feedback_category_id, category_code, category_name, is_active) ON TABLE public.feedback_question_category TO authenticated;
GRANT SELECT (questionnaire_id, questionnaire_code, questionnaire_name, questionnaire_type, is_anonymous, status) ON TABLE public.feedback_questionnaire TO authenticated;
GRANT SELECT (questionnaire_item_id, questionnaire_id, feedback_question_id, weightage, display_order, is_required) ON TABLE public.feedback_questionnaire_item TO authenticated;
GRANT SELECT (feedback_response_id, feedback_cycle_id, term_registration_id, course_offering_id, faculty_assignment_id, submitted_at, response_token) ON TABLE public.feedback_response TO authenticated;
GRANT SELECT (feedback_response_item_id, feedback_response_id, questionnaire_item_id, feedback_choice_id, numeric_score, text_response) ON TABLE public.feedback_response_item TO authenticated;
GRANT SELECT (file_object_id, storage_provider, storage_key, original_file_name, mime_type, file_size_bytes, checksum_sha256, uploaded_at, stored_file_name, storage_url, file_extension, confidentiality_level, is_encrypted, uploaded_by_user_id, updated_at, deleted_at, encryption_key_reference, virus_scan_status, virus_scanned_at) ON TABLE public.file_object TO authenticated;
GRANT SELECT (ledger_account_id, parent_account_id, account_code, account_name, account_type, is_active) ON TABLE public.financial_ledger_account TO authenticated;
GRANT SELECT (staff_activity_id, source_proposal_activity_id, project_title, principal_investigator_employee_id, department_id, funding_agency_id, funding_type_id, scheme_program_name, requested_amount, sanctioned_amount, amount_received, amount_utilized, currency_code, sanction_date, sanction_order_number, project_start_date, project_end_date, duration_months, research_status_id, project_objectives, research_domain, project_outcomes, publications_generated, patents_generated, products_generated, other_outputs, utilization_summary, completion_date) ON TABLE public.funded_research_project TO authenticated;
GRANT SELECT (funding_agency_id, organization_id, funding_type_id, agency_category, is_active) ON TABLE public.funding_agency TO authenticated;
GRANT SELECT (funding_type_id, funding_type_code, funding_type_name, is_external, description, is_active) ON TABLE public.funding_type TO authenticated;
GRANT SELECT (gender_id, gender_code, gender_name, is_active) ON TABLE public.gender TO authenticated;
GRANT SELECT (grade_rule_id, grade_scale_id, grade_letter, grade_point, minimum_percentage, maximum_percentage, result_status) ON TABLE public.grade_rule TO authenticated;
GRANT SELECT (grade_scale_id, scale_name, effective_from, effective_to, is_active) ON TABLE public.grade_scale TO authenticated;
GRANT SELECT (grievance_id, grievance_number, student_id, grievance_category_id, department_id, submitted_at, subject, description, priority, status, resolved_at, resolution) ON TABLE public.grievance TO authenticated;
GRANT SELECT (grievance_action_id, grievance_id, action_at, action_type, action_notes, new_status) ON TABLE public.grievance_action TO authenticated;
GRANT SELECT (grievance_category_id, category_code, category_name, is_active) ON TABLE public.grievance_category TO authenticated;
GRANT SELECT (indexing_agency_id, agency_code, agency_name, website_url, description, is_active) ON TABLE public.indexing_agency TO authenticated;
GRANT SELECT (industry_sector_id, sector_code, sector_name, description, is_active) ON TABLE public.industry_sector TO authenticated;
GRANT SELECT (installment_plan_id, plan_code, plan_name, number_of_installments, minimum_initial_percentage, approval_required, is_active) ON TABLE public.installment_plan TO authenticated;
GRANT SELECT (institution_id, university_id, institution_code, institution_name, legal_name, website_url, email, phone, is_active, created_at, updated_at) ON TABLE public.institution TO authenticated;
GRANT SELECT (journal_id, journal_name, journal_type_id, publisher_id, issn, eissn, website_url, country_id, is_peer_reviewed_default, is_open_access_default, is_active, created_at, updated_at) ON TABLE public.journal TO authenticated;
GRANT SELECT (journal_metric_id, journal_id, metric_type_id, metric_year, metric_value, quartile, source_name, source_url, verified_at) ON TABLE public.journal_metric TO authenticated;
GRANT SELECT (staff_activity_id, publication_type_id, journal_id, paper_title, volume_number, issue_number, edition, page_from, page_to, article_number, publication_date, publication_year, doi, url, peer_reviewed, open_access, primary_author_position, primary_staff_corresponding_author, affiliation_text, abstract_text, keywords) ON TABLE public.journal_publication TO authenticated;
GRANT SELECT (staff_activity_id, indexing_agency_id, indexed_year, indexing_status, source_url, remarks) ON TABLE public.journal_publication_indexing TO authenticated;
GRANT SELECT (journal_type_id, journal_type_code, journal_type_name, description, is_active) ON TABLE public.journal_type TO authenticated;
GRANT SELECT (late_fee_rule_id, rule_code, rule_name, calculation_method, grace_period_days, fixed_amount, daily_amount, percentage_rate, maximum_amount, effective_from, effective_to, is_active) ON TABLE public.late_fee_rule TO authenticated;
GRANT SELECT (late_fee_slab_id, late_fee_rule_id, from_day, to_day, late_fee_amount) ON TABLE public.late_fee_slab TO authenticated;
GRANT SELECT (login_audit_id, user_id, username_attempted, login_at, logout_at, ip_address, user_agent, was_successful, failure_reason, session_identifier) ON TABLE public.login_audit TO authenticated;
GRANT SELECT (membership_type_id, type_code, type_name, is_active) ON TABLE public.membership_type TO authenticated;
GRANT SELECT (mentor_assignment_id, student_id, employee_id, start_date, end_date, assignment_status) ON TABLE public.mentor_assignment TO authenticated;
GRANT SELECT (metric_type_id, metric_code, metric_name, description, is_active) ON TABLE public.metric_type TO authenticated;
GRANT SELECT (organization_type_id, organization_type_code, organization_type_name, is_active) ON TABLE public.organization_type TO authenticated;
GRANT SELECT (organizer_id, organization_id, is_active) ON TABLE public.organizer TO authenticated;
GRANT SELECT (participation_level_id, level_code, level_name, display_order, is_active) ON TABLE public.participation_level TO authenticated;
GRANT SELECT (password_history_id, user_id, changed_at) ON TABLE public.password_history TO authenticated;
GRANT SELECT (payment_allocation_id, payment_transaction_id, assessment_item_id, allocated_amount, allocation_date, allocated_by) ON TABLE public.payment_allocation TO authenticated;
GRANT SELECT (payment_mode_id, mode_code, mode_name, requires_reference, is_online, is_active) ON TABLE public.payment_mode TO authenticated;
GRANT SELECT (payment_transaction_id, transaction_number, student_account_id, application_id, transaction_date, payment_mode_id, amount, currency_code, payment_status, gateway_name, gateway_transaction_id, bank_reference_number, cheque_number, cheque_date, bank_name, payer_name, payer_contact, received_by, remarks, created_at) ON TABLE public.payment_transaction TO authenticated;
GRANT SELECT (permission_id, access_resource_id, access_action_id, permission_code, permission_name, description, is_sensitive, is_active) ON TABLE public.permission TO authenticated;
GRANT SELECT (previous_organization_id, previous_organization_type_id, organization_name, address_line_1, address_line_2, city, state_id, country_id, postal_code, phone, email, website_url, is_active, created_at, updated_at) ON TABLE public.previous_organization TO authenticated;
GRANT SELECT (previous_organization_type_id, type_code, type_name, classification, is_active) ON TABLE public.previous_organization_type TO authenticated;
GRANT SELECT (professional_contribution_type_id, contribution_code, contribution_name, description, is_active) ON TABLE public.professional_contribution_type TO authenticated;
GRANT SELECT (staff_activity_id, training_program_type_id, program_title, organizer_id, sponsoring_organization_id, funding_agency_id, venue_name, city, state_id, country_id, event_mode_id, duration_days, duration_hours, financial_support_received, financial_support_amount, currency_code, certificate_number, learning_outcomes) ON TABLE public.professional_development_activity TO authenticated;
GRANT SELECT (programme_id, department_id, programme_code, programme_name, award_name, programme_level, duration_semesters, maximum_duration_semesters, is_active) ON TABLE public.programme TO authenticated;
GRANT SELECT (specialization_id, programme_id, specialization_code, specialization_name, is_active) ON TABLE public.programme_specialization TO authenticated;
GRANT SELECT (programme_term_offering_id, academic_term_id, programme_id, specialization_id, specialization_key, curriculum_scheme_id, semester_id, status) ON TABLE public.programme_term_offering TO authenticated;
GRANT SELECT (publication_type_id, publication_type_code, publication_type_name, description, is_active, created_at, updated_at) ON TABLE public.publication_type TO authenticated;
GRANT SELECT (publisher_id, organization_id, is_active) ON TABLE public.publisher TO authenticated;
GRANT SELECT (qualification_level_id, level_code, level_name, display_order, is_terminal_degree, description, is_active, created_at, updated_at) ON TABLE public.qualification_level TO authenticated;
GRANT SELECT (refund_request_id, refund_request_number, student_account_id, payment_transaction_id, request_date, refund_reason, requested_amount, approved_amount, request_status, approved_by, approved_at) ON TABLE public.refund_request TO authenticated;
GRANT SELECT (religion_id, religion_code, religion_name, is_active) ON TABLE public.religion TO authenticated;
GRANT SELECT (utilization_id, staff_activity_id, financial_year, reporting_period_from, reporting_period_to, opening_balance, amount_received, expenditure_amount, closing_balance, utilization_certificate_number, statement_of_expenditure_number, remarks, created_at) ON TABLE public.research_project_financial_utilization TO authenticated;
GRANT SELECT (staff_activity_id, proposal_title, principal_investigator_employee_id, department_id, proposal_submission_date, funding_agency_id, funding_type_id, scheme_program_name, requested_amount, currency_code, research_status_id, proposal_reference_number, project_objectives, research_domain, expected_outcomes, review_comments) ON TABLE public.research_proposal TO authenticated;
GRANT SELECT (research_status_id, status_code, status_name, display_order, is_terminal, is_active) ON TABLE public.research_status TO authenticated;
GRANT SELECT (research_supervision_id, staff_activity_id, supervision_level, scholar_name, student_id, registration_number, research_title, registration_date, completion_date, supervision_role, status, awarding_organization_id) ON TABLE public.research_supervision TO authenticated;
GRANT SELECT (role_id, parent_role_id, role_code, role_name, role_category, role_level, description, is_system_role, is_assignable, is_active, created_at, updated_at) ON TABLE public.role TO authenticated;
GRANT SELECT (role_delegation_id, delegator_user_id, delegate_user_id, source_assignment_id, valid_from, valid_to, delegation_status, reason, approved_by_user_id, created_at) ON TABLE public.role_delegation TO authenticated;
GRANT SELECT (role_id, permission_id, permission_effect, granted_at) ON TABLE public.role_permission TO authenticated;
GRANT SELECT (role_type_id, role_code, role_name, description, is_active) ON TABLE public.role_type TO authenticated;
GRANT SELECT (room_id, building_id, room_code, room_name, room_type, capacity, is_active) ON TABLE public.room TO authenticated;
GRANT SELECT (scholarship_scheme_id, scheme_code, scheme_name, sponsoring_authority, scheme_type, maximum_amount, is_reimbursable, is_active) ON TABLE public.scholarship_scheme TO authenticated;
GRANT SELECT (semester_id, semester_number, semester_name) ON TABLE public.semester TO authenticated;
GRANT SELECT (service_fee_request_id, request_number, student_id, certificate_request_id, fee_type_id, request_date, service_description, quantity, unit_amount, total_amount, fee_assessment_id, request_status, processed_by, processed_at) ON TABLE public.service_fee_request TO authenticated;
GRANT SELECT (social_category_id, category_code, category_name, is_active) ON TABLE public.social_category TO authenticated;
GRANT SELECT (staff_activity_id, employee_id, activity_type_id, academic_year_id, institution_id, campus_id, department_id, participation_level_id, primary_role_type_id, activity_title, start_date, end_date, description, outcomes, remarks, verification_status_id, verified_by_user_id, verified_at, verification_remarks, approval_status_id, approved_by_user_id, approved_at, approval_remarks, rejection_reason, created_by_user_id, updated_by_user_id, created_at, updated_at, deleted_at, deleted_by_user_id, deletion_reason) ON TABLE public.staff_activity TO authenticated;
GRANT SELECT (staff_activity_contributor_id, staff_activity_id, employee_id, external_person_name, external_person_email, external_organization_id, affiliation_text, role_type_id, contributor_sequence, is_corresponding_author, contribution_details, is_primary, created_at) ON TABLE public.staff_activity_contributor TO authenticated;
GRANT SELECT (staff_activity_id, award_category_id, award_name, awarding_organization_id, award_date, citation_details, cash_prize_amount, incentive_amount, currency_code, award_reference_number) ON TABLE public.staff_award TO authenticated;
GRANT SELECT (staff_category_id, staff_type_id, category_code, category_name, description, is_active, created_at, updated_at) ON TABLE public.staff_category TO authenticated;
GRANT SELECT (staff_activity_id, professional_contribution_type_id, organization_id, journal_id, conference_event_id, programme_id, course_id, student_id, title_topic, appointment_reference_number, contribution_date, start_date, end_date, number_of_reviews, number_of_candidates, contribution_details, outcome_details) ON TABLE public.staff_professional_contribution TO authenticated;
GRANT SELECT (staff_activity_id, organization_id, membership_type_id, membership_number, membership_start_date, membership_expiry_date, is_lifetime_membership, role_type_id, participation_level_id, renewal_required, membership_status) ON TABLE public.staff_professional_membership TO authenticated;
GRANT SELECT (staff_type_id, type_code, type_name, description, is_active, created_at, updated_at) ON TABLE public.staff_type TO authenticated;
GRANT SELECT (state_id, country_id, state_code, state_name, is_active) ON TABLE public.state TO authenticated;
GRANT SELECT (student_id, student_number, university_seat_number, first_name, middle_name, last_name, display_name, date_of_birth, gender_id, blood_group_id, primary_email, primary_phone, nationality_country_id, religion_id, social_category_id, caste_id, sub_caste_id, photo_url, admission_date, student_status, notes, created_at, updated_at) ON TABLE public.student TO authenticated;
GRANT SELECT (student_activity_id, student_id, student_activity_type_id, academic_year_id, institution_id, campus_id, department_id, programme_id, participation_level_id, event_mode_id, external_organization_id, organizer_name, activity_title, event_name, team_name, participation_role, start_date, end_date, venue_name, city, state_id, country_id, achievement_type, position_rank, award_name, award_details, cash_prize_amount, currency_code, certificate_number, activity_url, description, outcomes, remarks, verification_status_id, verified_by_user_id, verified_at, verification_remarks, approval_status_id, approved_by_user_id, approved_at, approval_remarks, rejection_reason, created_by_user_id, updated_by_user_id, created_at, updated_at, deleted_at, deleted_by_user_id, deletion_reason) ON TABLE public.student_activity TO authenticated;
GRANT SELECT (student_activity_evidence_id, student_activity_id, document_type_id, evidence_type_id, confidentiality_level_id, document_title, description, academic_year_id, document_issue_date, issuing_authority, issuing_organization_id, certificate_document_number, expiry_date, verification_status_id, verified_by_user_id, verified_at, verification_remarks, approval_status_id, approved_by_user_id, approved_at, rejection_reason, current_version_number, is_active, created_by_user_id, updated_by_user_id, created_at, updated_at, deleted_at, deleted_by_user_id, deletion_reason) ON TABLE public.student_activity_evidence TO authenticated;
GRANT SELECT (student_activity_evidence_audit_id, student_activity_evidence_id, student_activity_evidence_version_id, action_code, performed_by_user_id, performed_at, ip_address, user_agent, before_values, after_values, remarks) ON TABLE public.student_activity_evidence_audit TO authenticated;
GRANT SELECT (student_activity_evidence_requirement_id, student_activity_type_id, evidence_type_id, document_type_id, is_mandatory, minimum_files, maximum_files, valid_from, valid_to, is_active, document_type_key) ON TABLE public.student_activity_evidence_requirement TO authenticated;
GRANT SELECT (student_activity_evidence_version_id, student_activity_evidence_id, version_number, file_object_id, change_reason, uploaded_by_user_id, uploaded_at, is_current, current_document_key) ON TABLE public.student_activity_evidence_version TO authenticated;
GRANT SELECT (student_activity_team_member_id, student_activity_id, student_id, external_member_name, external_member_email, external_organization_id, member_role, member_sequence, is_team_lead, remarks, created_at) ON TABLE public.student_activity_team_member TO authenticated;
GRANT SELECT (student_activity_type_id, type_code, type_name, activity_group, description, requires_team_details, supports_achievement, is_active, created_at, updated_at) ON TABLE public.student_activity_type TO authenticated;
GRANT SELECT (student_address_id, student_id, address_type, address_line_1, address_line_2, city, state_id, country_id, postal_code, valid_from, valid_to, is_primary, current_primary_student_id) ON TABLE public.student_address TO authenticated;
GRANT SELECT (student_assessment_mark_id, assessment_event_id, course_registration_id, course_offering_id, attendance_status, marks_obtained, reduced_marks, remarks, evaluated_at) ON TABLE public.student_assessment_mark TO authenticated;
GRANT SELECT (class_session_id, course_offering_section_student_id, course_offering_section_id, attendance_status_id, marked_at, marked_by_user_id, remarks) ON TABLE public.student_attendance TO authenticated;
GRANT SELECT (course_registration_id, term_registration_id, course_offering_id, registration_type, registration_date, registration_status) ON TABLE public.student_course_registration TO authenticated;
GRANT SELECT (student_course_result_id, course_registration_id, attempt_number, internal_marks, external_marks, total_marks, grade_letter, grade_point, credits_earned, result_status, result_date, remarks) ON TABLE public.student_course_result TO authenticated;
GRANT SELECT (student_document_id, student_id, document_type_id, file_object_id, document_number, issue_date, expiry_date, verification_status, verified_at, remarks) ON TABLE public.student_document TO authenticated;
GRANT SELECT (student_entrance_exam_id, student_id, exam_name, registration_number, rank_number, score, exam_year, allotment_date, registration_fee) ON TABLE public.student_entrance_exam TO authenticated;
GRANT SELECT (student_exit_id, enrolment_id, exit_type, exit_date, destination_institution, old_registration_number, remarks) ON TABLE public.student_exit TO authenticated;
GRANT SELECT (fee_assessment_id, assessment_number, student_account_id, application_id, enrolment_id, term_registration_id, academic_year_id, academic_term_id, fee_structure_id, assessment_type, assessment_date, gross_amount, concession_amount, scholarship_amount, adjustment_amount, net_payable_amount, amount_paid, balance_amount, due_date, assessment_status, remarks, created_by, created_at, updated_at) ON TABLE public.student_fee_assessment TO authenticated;
GRANT SELECT (assessment_item_id, fee_assessment_id, fee_type_id, fee_structure_item_id, description, original_amount, concession_amount, scholarship_amount, adjustment_amount, net_amount, amount_paid, balance_amount, due_date, item_status) ON TABLE public.student_fee_assessment_item TO authenticated;
GRANT SELECT (student_concession_id, student_id, concession_type_id, academic_year_id, application_number, application_date, approved_percentage, approved_amount, valid_from, valid_to, approval_status, approved_by, approved_at, remarks) ON TABLE public.student_fee_concession TO authenticated;
GRANT SELECT (fee_penalty_id, student_account_id, assessment_item_id, fee_type_id, penalty_date, penalty_reason, penalty_amount, waived_amount, net_penalty_amount, penalty_status, approved_by) ON TABLE public.student_fee_penalty TO authenticated;
GRANT SELECT (student_account_id, student_id, account_number, account_status, opening_balance, credit_balance, created_at, updated_at) ON TABLE public.student_financial_account TO authenticated;
GRANT SELECT (financial_hold_id, student_account_id, hold_type, hold_reason, placed_at, placed_by, released_at, released_by, release_reason, hold_status) ON TABLE public.student_financial_hold TO authenticated;
GRANT SELECT (student_installment_id, fee_assessment_id, installment_plan_id, installment_number, due_date, installment_amount, amount_paid, balance_amount, installment_status) ON TABLE public.student_installment_schedule TO authenticated;
GRANT SELECT (student_parent_guardian_id, student_id, relationship_type, full_name, occupation, annual_income, email, phone, address_line_1, address_line_2, city, state_id, country_id, postal_code, is_primary_contact) ON TABLE public.student_parent_guardian TO authenticated;
GRANT SELECT (previous_education_id, student_id, qualification_level, examination_name, institution_name, board_university, registration_number, month_of_passing, year_of_passing, result_class, marks_obtained, maximum_marks, percentage) ON TABLE public.student_previous_education TO authenticated;
GRANT SELECT (enrolment_id, student_id, programme_id, specialization_id, curriculum_scheme_id, admission_academic_year_id, admission_category_id, admission_date, admission_semester_id, expected_completion_date, enrolment_status) ON TABLE public.student_programme_enrolment TO authenticated;
GRANT SELECT (student_residence_id, student_id, residence_type, hostel_name, room_number, start_date, end_date, is_current) ON TABLE public.student_residence TO authenticated;
GRANT SELECT (student_scholarship_id, student_id, scholarship_scheme_id, academic_year_id, application_number, sanction_number, applied_amount, sanctioned_amount, received_amount, application_status, sanction_date, received_date, remarks) ON TABLE public.student_scholarship TO authenticated;
GRANT SELECT (student_sponsorship_id, student_id, academic_year_id, sponsoring_authority, sanction_reference, sanctioned_amount, valid_from, valid_to, approval_status, approved_by, approved_at) ON TABLE public.student_sponsorship TO authenticated;
GRANT SELECT (term_registration_id, enrolment_id, programme_term_offering_id, class_section_id, class_batch_id, roll_number, registration_date, registration_status) ON TABLE public.student_term_registration TO authenticated;
GRANT SELECT (student_term_result_id, term_registration_id, credits_registered, credits_earned, sgpa, cgpa, result_status, published_at) ON TABLE public.student_term_result TO authenticated;
GRANT SELECT (student_id, user_id, linked_at) ON TABLE public.student_user_account TO authenticated;
GRANT SELECT (study_mode_id, mode_code, mode_name, is_active) ON TABLE public.study_mode TO authenticated;
GRANT SELECT (sub_caste_id, caste_id, sub_caste_code, sub_caste_name, is_active) ON TABLE public.sub_caste TO authenticated;
GRANT SELECT (time_slot_id, campus_id, slot_code, start_time, end_time, is_break, is_active) ON TABLE public.time_slot TO authenticated;
GRANT SELECT (timetable_session_id, course_offering_section_id, faculty_assignment_id, day_of_week, time_slot_id, room_id, effective_from, effective_to) ON TABLE public.timetable_session TO authenticated;
GRANT SELECT (training_program_type_id, type_code, type_name, description, is_active) ON TABLE public.training_program_type TO authenticated;
GRANT SELECT (university_id, university_code, university_name, legal_name, university_type, website_url, email, phone, address_line_1, address_line_2, city, state_id, postal_code, is_active, created_at, updated_at) ON TABLE public.university TO authenticated;
GRANT SELECT (user_id, username, email, account_status, must_change_password, multi_factor_enabled, failed_login_count, locked_until, password_changed_at, last_login_at, created_at, updated_at) ON TABLE public.user_account TO authenticated;
GRANT SELECT (user_permission_override_id, user_id, permission_id, permission_effect, scope_type, scope_entity_id, normalized_scope_entity_id, valid_from, valid_to, granted_by_user_id, justification, created_at) ON TABLE public.user_permission_override TO authenticated;
GRANT SELECT (user_role_assignment_id, user_id, role_id, scope_type, institution_id, campus_id, department_id, programme_id, scope_entity_id, valid_from, valid_to, assignment_status, is_primary, assigned_by_user_id, assignment_reason, created_at) ON TABLE public.user_role_assignment TO authenticated;
GRANT SELECT (verification_status_id, status_code, status_name, is_terminal, is_active) ON TABLE public.verification_status TO authenticated;

-- -----------------------------------------------------------------------------
-- Default privileges (the live project grants service_role the same
-- rights on objects that are created later)
-- -----------------------------------------------------------------------------
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;
