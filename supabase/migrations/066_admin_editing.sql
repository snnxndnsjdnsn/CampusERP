-- =============================================================================================
-- 066. ADMIN EDITING SURFACE FOR THE READ-ONLY MODULE SCREENS
-- =============================================================================================
-- Why this file exists:
--   * Modules 3 (ACADEMIC CALENDAR), 4 (CURRICULUM / COURSES), 5 (STUDENT), 7 (REGISTRATION)
--     and 8 (TIMETABLE) were built as read-only screens.  The database was already write
--     ready for every one of those tables - the row level policies carry INSERT / UPDATE /
--     DELETE rules with the right permission code and the right scope - but the
--     application had no way to reach them: there is no `calendar_*`, `curriculum_*`,
--     `student_*`, `registration_*` or `timetable_*` write function, and the two generic
--     editors (`ref_save` / `section_save`) do not cover these tables.
--   * This file adds one generic, catalogue driven write surface for them:
--       admin_table_list()      the editable tables the caller may work on
--       admin_table_schema()    the column descriptors of one of them
--       admin_table_save()      insert / update one row
--       admin_table_delete()    delete one row
--       admin_lookup_options()  the foreign key dropdowns
--     and the private catalogue the five functions share.
--
-- How authorisation works:
--   * The catalogue (`sims_private.admin_table_def`) records, for every editable table, the
--     permission prefix, whether the table is governed by a single CONFIGURE code or by
--     the CREATE / UPDATE / DELETE triple, and how the scope of a row is resolved
--     (global, campus, department, programme or student - directly or through one
--     foreign key hop).
--   * `sims_private.admin_can()` turns that catalogue into the same decision the row
--     level policy makes, using the same `sims_private.can_*` helpers:
--         global      -> can_global(code)
--         campus      -> can_campus(code, campus_id)
--         department  -> can_department(code, owning_department_id)
--         programme   -> can_programme(code, programme_id)
--         student     -> can_student(code, student_id, true)
--     A caller therefore cannot write a row that its own role would not be allowed to
--     write directly, and a scoped caller cannot reach outside its scope by forging an
--     identifier: the scope is resolved from the row that is being written.
--   * Because the write functions are SECURITY DEFINER, the row level policies do not
--     run for them, so the function makes the same decision the policy makes in two
--     parts: the row that exists now (USING) and the row as it is afterwards
--     (WITH CHECK).  The second part is what stops a scoped caller from moving a row
--     out of its own scope.
--   * The write functions are SECURITY DEFINER, exactly like `ref_save` / `section_save`,
--     because they have to write rows the caller may not be able to select.  The
--     permission check inside the function IS the gate; an unknown table is rejected with
--     SQLSTATE 22023 and a caller without the permission with SQLSTATE 42501.
--   * Every write is recorded in `activity_audit` by the table's own audit trigger
--     (`sims_private.audit_row`), exactly like every other write in the schema.  Two of
--     the fifteen tables - `time_slot` and `room` - were the only ones without such a
--     trigger, so this file adds it for them.  That keeps one audit row per change
--     (the write functions must not audit as well, or every change would be recorded
--     twice) and keeps the action codes uniform: INSERT / UPDATE / DELETE.
--
-- Rules this file obeys:
--   * It creates functions, grants EXECUTE on them and adds two audit triggers.
--     It never changes a table definition, a policy or an existing function.
--   * `CREATE OR REPLACE` makes the file idempotent: re-running it replaces the bodies
--     and leaves the catalogue unchanged.
--   * `admin_lookup_options()` is SECURITY INVOKER on purpose.  It hands the browser the
--     foreign key dropdowns, and a dropdown must only ever offer the rows the caller may
--     see, so the read has to go through the row level policies of the referenced table.
-- =============================================================================================

-- ---------------------------------------------------------------------------------------------
-- 1. The catalogue of editable tables.
-- ---------------------------------------------------------------------------------------------
-- perm_mode = 'CONFIGURE'  -> one permission code (prefix.ALL.CONFIGURE) for every action
-- perm_mode = 'ACTION'     -> prefix.ALL.CREATE / .UPDATE / .DELETE, one per action
-- scope_kind                -> how the scope of a row is resolved
-- scope_col                 -> the column that carries the scope (directly)
-- scope_ref                 -> '<table>.<column>' when the scope is one foreign key hop away
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION sims_private.admin_table_def(p_table text)
RETURNS TABLE(
    tbl text,
    label text,
    module_code text,
    perm_prefix text,
    perm_mode text,
    scope_kind text,
    scope_col text,
    scope_ref text
)
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT v.tbl, v.label, v.module_code, v.perm_prefix, v.perm_mode, v.scope_kind, v.scope_col, v.scope_ref
      FROM (VALUES
        -- module 3 - academic calendar
        ('academic_year',               'Academic years',          'ACADEMIC_CALENDAR', 'ACADEMIC_CALENDAR', 'CONFIGURE', 'global',     NULL,                        NULL),
        ('academic_term',               'Academic terms',          'ACADEMIC_CALENDAR', 'ACADEMIC_CALENDAR', 'CONFIGURE', 'global',     NULL,                        NULL),
        ('semester',                    'Semesters',               'ACADEMIC_CALENDAR', 'ACADEMIC_CALENDAR', 'CONFIGURE', 'global',     NULL,                        NULL),
        ('time_slot',                   'Teaching time slots',     'ACADEMIC_CALENDAR', 'ACADEMIC_CALENDAR', 'ACTION',    'campus',     'campus_id',                 NULL),
        -- module 4 - curriculum and courses
        ('course_category',             'Course categories',       'CURRICULUM',        'CURRICULUM',        'CONFIGURE', 'global',     NULL,                        NULL),
        ('curriculum_scheme',           'Curriculum schemes',      'CURRICULUM',        'CURRICULUM',        'ACTION',    'programme',  'programme_id',              NULL),
        ('curriculum_course',           'Curriculum courses',      'CURRICULUM',        'CURRICULUM',        'ACTION',    'programme',  'curriculum_scheme_id',      'curriculum_scheme.programme_id'),
        ('course_catalog',              'Courses',                 'CURRICULUM',        'CURRICULUM',        'ACTION',    'department', 'owning_department_id',     NULL),
        -- module 5 - student register and enrolments
        ('student',                     'Students',                'STUDENT',           'STUDENT',           'ACTION',    'student',    'student_id',                NULL),
        ('student_programme_enrolment', 'Programme enrolments',    'STUDENT',           'ADMISSION',         'ACTION',    'student',    'student_id',                NULL),
        -- module 7 - registration
        ('programme_term_offering',     'Programme term offerings','REGISTRATION',      'REGISTRATION',      'ACTION',    'programme',  'programme_id',              NULL),
        ('course_offering',             'Course offerings',        'REGISTRATION',      'TEACHING',          'ACTION',    'programme',  'programme_term_offering_id','programme_term_offering.programme_id'),
        ('class_section',               'Class sections',          'REGISTRATION',      'REGISTRATION',      'ACTION',    'programme',  'programme_term_offering_id','programme_term_offering.programme_id'),
        ('student_term_registration',   'Term registrations',      'REGISTRATION',      'REGISTRATION',      'ACTION',    'student',    'enrolment_id',              'student_programme_enrolment.student_id'),
        -- module 8 - timetable
        ('room',                        'Rooms',                   'TIMETABLE',         'INSTITUTION',       'ACTION',    'campus',     'building_id',               'building.campus_id')
      ) AS v(tbl, label, module_code, perm_prefix, perm_mode, scope_kind, scope_col, scope_ref)
     WHERE p_table IS NULL OR v.tbl = p_table;
$function$;

-- ---------------------------------------------------------------------------------------------
-- 2. The catalogue of foreign key dropdown sources.
-- ---------------------------------------------------------------------------------------------
-- `label_sql` is the expression that produces the text of one option.  It may reach
-- through one foreign key so that a curriculum course is offered as "CS101 - Programming"
-- rather than as a bare number.
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION sims_private.admin_lookup_def(p_table text)
RETURNS TABLE(
    tbl text,
    pk_col text,
    label_sql text
)
LANGUAGE sql
IMMUTABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT v.tbl, v.pk_col, v.label_sql
      FROM (VALUES
        ('academic_year',              'academic_year_id',              'year_code'),
        ('academic_term',              'academic_term_id',              'term_name'),
        ('semester',                   'semester_id',                   'semester_name'),
        ('campus',                     'campus_id',                     'campus_name'),
        ('building',                   'building_id',                   'building_name'),
        ('department',                 'department_id',                 'department_name'),
        ('programme',                  'programme_id',                  'programme_name'),
        ('programme_specialization',   'specialization_id',             'specialization_name'),
        ('course_category',            'course_category_id',            'category_name'),
        ('course_catalog',             'course_id',                     'course_title'),
        ('curriculum_scheme',          'curriculum_scheme_id',          'scheme_name'),
        ('curriculum_course',          'curriculum_course_id',          '(SELECT c.course_code || '' - '' || c.course_title FROM public.course_catalog c WHERE c.course_id = t.course_id)'),
        ('programme_term_offering',    'programme_term_offering_id',    '(SELECT p.programme_name || '' - '' || a.term_name FROM public.programme p JOIN public.academic_term a ON a.academic_term_id = t.academic_term_id WHERE p.programme_id = t.programme_id)'),
        ('student',                    'student_id',                    'display_name'),
        ('admission_category',         'admission_category_id',         'category_name'),
        ('student_programme_enrolment','enrolment_id',                  '(SELECT s.display_name FROM public.student s WHERE s.student_id = t.student_id)'),
        ('room',                       'room_id',                       'room_name'),
        ('gender',                     'gender_id',                     'gender_name'),
        ('blood_group',                'blood_group_id',                'blood_group_code'),
        ('country',                    'country_id',                    'country_name'),
        ('religion',                   'religion_id',                   'religion_name'),
        ('social_category',            'social_category_id',            'category_name'),
        ('caste',                      'caste_id',                      'caste_name'),
        ('sub_caste',                  'sub_caste_id',                  'sub_caste_name')
      ) AS v(tbl, pk_col, label_sql)
     WHERE p_table IS NULL OR v.tbl = p_table;
$function$;

-- ---------------------------------------------------------------------------------------------
-- 3. Does the caller hold any of these permission codes, in any scope?
-- ---------------------------------------------------------------------------------------------
-- Used to decide whether a table is offered at all.  The per row decision is made by
-- `admin_can()` below, which honours the DENY overrides as well.
--
-- The SELF scope is deliberately not counted: `sims_private.can_*` is always called with
-- `p_self_ok = false` for a write, so a SELF scoped grant never authorises one.  Counting
-- it here would offer a table to a student who can never write a row of it.
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION sims_private.admin_holds(p_codes text[])
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT s.ga
        OR COALESCE(cardinality(s.ai), 0) > 0
        OR COALESCE(cardinality(s.ac), 0) > 0
        OR COALESCE(cardinality(s.ad), 0) > 0
        OR COALESCE(cardinality(s.ap), 0) > 0
      FROM sims_private.eff_set_of(p_codes) s;
$function$;

-- ---------------------------------------------------------------------------------------------
-- 4. Resolve the scope of the row that is about to be written.
-- ---------------------------------------------------------------------------------------------
-- For an update or a delete the scope comes from the row that exists; for an insert it
-- comes from the payload that is about to be written.  When the scope is one foreign key
-- hop away the hop is followed here, so the check always runs against the scope the row
-- really belongs to.
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION sims_private.admin_scope_value(
    p_table text,
    p_scope_kind text,
    p_scope_col text,
    p_scope_ref text,
    p_row_id bigint,
    p_payload jsonb
)
RETURNS bigint
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_pk text;
    v_scope bigint;
    v_raw text;
    v_ref_table text;
    v_ref_column text;
BEGIN
    IF p_scope_kind IS NULL OR p_scope_kind = 'global' THEN
        RETURN NULL;
    END IF;

    v_pk := sims_private.pk_column(p_table);

    IF p_row_id IS NOT NULL THEN
        EXECUTE format('SELECT %I::bigint FROM public.%I WHERE %I = $1', p_scope_col, p_table, v_pk)
           INTO v_scope USING p_row_id;
    ELSE
        v_raw := btrim(COALESCE(p_payload ->> p_scope_col, ''));
        IF v_raw ~ '^-?[0-9]+$' THEN
            v_scope := v_raw::bigint;
        ELSE
            v_scope := NULL;
        END IF;
    END IF;

    IF p_scope_ref IS NULL OR v_scope IS NULL THEN
        RETURN v_scope;
    END IF;

    v_ref_table := split_part(p_scope_ref, '.', 1);
    v_ref_column := split_part(p_scope_ref, '.', 2);

    EXECUTE format('SELECT %I::bigint FROM public.%I WHERE %I = $1',
                   v_ref_column, v_ref_table, sims_private.pk_column(v_ref_table))
       INTO v_scope USING v_scope;

    RETURN v_scope;
END $function$;

-- ---------------------------------------------------------------------------------------------
-- 5. The authorisation decision for one write.
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION sims_private.admin_can(
    p_table text,
    p_action text,
    p_row_id bigint,
    p_payload jsonb
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    d record;
    v_code text;
    v_scope bigint;
BEGIN
    SELECT * INTO d FROM sims_private.admin_table_def(p_table);
    IF d.tbl IS NULL THEN
        RETURN false;
    END IF;

    v_code := CASE
        WHEN d.perm_mode = 'CONFIGURE' THEN d.perm_prefix || '.ALL.CONFIGURE'
        ELSE d.perm_prefix || '.ALL.' || upper(p_action)
    END;

    v_scope := sims_private.admin_scope_value(d.tbl, d.scope_kind, d.scope_col, d.scope_ref, p_row_id, p_payload);

    RETURN CASE d.scope_kind
        WHEN 'global'     THEN sims_private.can_global(ARRAY[v_code]::text[])
        WHEN 'campus'     THEN sims_private.can_campus(ARRAY[v_code]::text[], v_scope)
        WHEN 'department' THEN sims_private.can_department(ARRAY[v_code]::text[], v_scope)
        WHEN 'programme'  THEN sims_private.can_programme(ARRAY[v_code]::text[], v_scope)
        WHEN 'student'    THEN sims_private.can_student(ARRAY[v_code]::text[], v_scope, true)
        ELSE false
    END;
END $function$;

-- ---------------------------------------------------------------------------------------------
-- 6. The editable tables the caller may work on.
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_table_list()
RETURNS TABLE(
    tbl text,
    label text,
    module_code text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT d.tbl, d.label, d.module_code
      FROM sims_private.admin_table_def(NULL) d
     WHERE sims_private.admin_holds(ARRAY[
               CASE WHEN d.perm_mode = 'CONFIGURE' THEN d.perm_prefix || '.ALL.CONFIGURE' ELSE d.perm_prefix || '.ALL.CREATE'  END,
               CASE WHEN d.perm_mode = 'CONFIGURE' THEN d.perm_prefix || '.ALL.CONFIGURE' ELSE d.perm_prefix || '.ALL.UPDATE'  END,
               CASE WHEN d.perm_mode = 'CONFIGURE' THEN d.perm_prefix || '.ALL.CONFIGURE' ELSE d.perm_prefix || '.ALL.DELETE'  END
             ]::text[])
     ORDER BY d.module_code, d.label;
$function$;

-- ---------------------------------------------------------------------------------------------
-- 7. The shape of one editable table.
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_table_schema(p_table text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    d record;
    v_pk text;
BEGIN
    SELECT * INTO d FROM sims_private.admin_table_def(p_table);
    IF d.tbl IS NULL THEN
        RAISE EXCEPTION 'Unknown table' USING ERRCODE = '22023';
    END IF;

    IF NOT sims_private.admin_holds(ARRAY[
           CASE WHEN d.perm_mode = 'CONFIGURE' THEN d.perm_prefix || '.ALL.CONFIGURE' ELSE d.perm_prefix || '.ALL.CREATE' END,
           CASE WHEN d.perm_mode = 'CONFIGURE' THEN d.perm_prefix || '.ALL.CONFIGURE' ELSE d.perm_prefix || '.ALL.UPDATE' END,
           CASE WHEN d.perm_mode = 'CONFIGURE' THEN d.perm_prefix || '.ALL.CONFIGURE' ELSE d.perm_prefix || '.ALL.DELETE' END
         ]::text[]) THEN
        RAISE EXCEPTION 'Not authorised (%)', d.label USING ERRCODE = '42501';
    END IF;

    v_pk := sims_private.pk_column(p_table);

    RETURN jsonb_build_object(
        'table', d.tbl,
        'label', d.label,
        'module_code', d.module_code,
        'pk', v_pk,
        'columns', sims_private.form_columns(p_table, ARRAY[v_pk])
    );
END $function$;

-- ---------------------------------------------------------------------------------------------
-- 8. Insert or update one row.
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_table_save(p_table text, p_id bigint, p jsonb)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    d record;
    v_pk text;
    v_exists integer;
    v_after jsonb;
    v_id bigint;
    v_action text;
    v_code text;
BEGIN
    SELECT * INTO d FROM sims_private.admin_table_def(p_table);
    IF d.tbl IS NULL THEN
        RAISE EXCEPTION 'Unknown table' USING ERRCODE = '22023';
    END IF;

    IF p IS NULL OR jsonb_typeof(p) <> 'object' THEN
        RAISE EXCEPTION 'The details must be an object' USING ERRCODE = '22023';
    END IF;

    v_action := CASE WHEN p_id IS NULL THEN 'CREATE' ELSE 'UPDATE' END;
    v_code := CASE
        WHEN d.perm_mode = 'CONFIGURE' THEN d.perm_prefix || '.ALL.CONFIGURE'
        ELSE d.perm_prefix || '.ALL.' || v_action
    END;

    v_pk := sims_private.pk_column(p_table);

    -- The write functions are SECURITY DEFINER, so the row level policies do not
    -- run for them.  The function therefore has to make the same decision the
    -- policy makes, in two parts:
    --
    --   USING      the row that exists now (an update) or the row that is about
    --              to be written (an insert)
    --   WITH CHECK the row as it is afterwards
    --
    -- The second part is what stops a scoped caller from moving a row out of
    -- its own scope: without it a department could hand its course to another
    -- department, which the policy's WITH CHECK clause forbids.

    IF p_id IS NOT NULL THEN
        EXECUTE format('SELECT 1 FROM public.%I WHERE %I = $1', p_table, v_pk) INTO v_exists USING p_id;
        IF v_exists IS NULL THEN
            RAISE EXCEPTION 'Unknown row' USING ERRCODE = '22023';
        END IF;

        IF NOT sims_private.admin_can(p_table, 'UPDATE', p_id, NULL) THEN
            RAISE EXCEPTION 'Not authorised to update % (%)', lower(d.label), v_code USING ERRCODE = '42501';
        END IF;
    ELSE
        IF NOT sims_private.admin_can(p_table, 'CREATE', NULL, p) THEN
            RAISE EXCEPTION 'Not authorised to create % (%)', lower(d.label), v_code USING ERRCODE = '42501';
        END IF;
    END IF;

    -- The write itself is audited by the table's own `sims_private.audit_row` trigger,
    -- so the function must not audit as well - that would record every change twice.
    v_id := sims_private.write_row(p_table, v_pk, NULL, NULL, p_id, p);

    -- WITH CHECK: the row as it is now.  A refusal here aborts the transaction,
    -- so the write and its audit row are rolled back together.
    EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE t.%I = $1', p_table, v_pk) INTO v_after USING v_id;
    IF NOT sims_private.admin_can(p_table, v_action, NULL, v_after) THEN
        RAISE EXCEPTION 'Not authorised to % % outside your scope (%)',
            lower(v_action), lower(d.label), v_code USING ERRCODE = '42501';
    END IF;

    RETURN v_id;
END $function$;

-- ---------------------------------------------------------------------------------------------
-- 9. Delete one row.
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_table_delete(p_table text, p_id bigint)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    d record;
    v_pk text;
    v_exists integer;
    v_code text;
BEGIN
    SELECT * INTO d FROM sims_private.admin_table_def(p_table);
    IF d.tbl IS NULL THEN
        RAISE EXCEPTION 'Unknown table' USING ERRCODE = '22023';
    END IF;

    v_code := CASE
        WHEN d.perm_mode = 'CONFIGURE' THEN d.perm_prefix || '.ALL.CONFIGURE'
        ELSE d.perm_prefix || '.ALL.DELETE'
    END;

    IF NOT sims_private.admin_can(p_table, 'DELETE', p_id, NULL) THEN
        RAISE EXCEPTION 'Not authorised to delete % (%)', lower(d.label), v_code USING ERRCODE = '42501';
    END IF;

    v_pk := sims_private.pk_column(p_table);

    EXECUTE format('SELECT 1 FROM public.%I WHERE %I = $1', p_table, v_pk) INTO v_exists USING p_id;
    IF v_exists IS NULL THEN
        RAISE EXCEPTION 'Unknown row' USING ERRCODE = '22023';
    END IF;

    BEGIN
        EXECUTE format('DELETE FROM public.%I WHERE %I = $1', p_table, v_pk) USING p_id;
    EXCEPTION WHEN foreign_key_violation THEN
        RAISE EXCEPTION 'This row is still in use and cannot be deleted' USING ERRCODE = '45000';
    END;

    -- Audited by the table's own `sims_private.audit_row` trigger - see `admin_table_save`.
END $function$;

-- ---------------------------------------------------------------------------------------------
-- 10. The foreign key dropdowns.
-- ---------------------------------------------------------------------------------------------
-- SECURITY INVOKER on purpose: the options have to come from the rows the caller may
-- see, so the read goes through the row level policies of the referenced table.
-- ---------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_lookup_options(p_table text)
RETURNS TABLE(
    id bigint,
    label text
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    d record;
BEGIN
    SELECT * INTO d FROM sims_private.admin_lookup_def(p_table);
    IF d.tbl IS NULL THEN
        RAISE EXCEPTION 'Unknown lookup table' USING ERRCODE = '22023';
    END IF;

    RETURN QUERY EXECUTE format(
        'SELECT %I::bigint, (%s)::text FROM public.%I t ORDER BY 2 LIMIT 1000',
        d.pk_col, d.label_sql, p_table);
END $function$;

-- ---------------------------------------------------------------------------------------------
-- 11. The two missing audit triggers.
-- ---------------------------------------------------------------------------------------------
-- Thirteen of the fifteen editable tables already carry an `AFTER INSERT OR DELETE OR
-- UPDATE ... EXECUTE FUNCTION sims_private.audit_row(...)` trigger, so a write through
-- `admin_table_save` / `admin_table_delete` is recorded in `activity_audit` by the
-- trigger.  `time_slot` and `room` were the only two without one, which would have left
-- their changes out of the audit trail.  These two triggers close that gap and use the
-- same module codes as the rest of the schema: `time_slot` belongs to the academic
-- calendar, `room` to the timetable.
--
-- `DROP TRIGGER IF EXISTS` first, so the file stays idempotent.
-- ---------------------------------------------------------------------------------------------

DROP TRIGGER IF EXISTS trg_time_slot_audit ON public.time_slot;
CREATE TRIGGER trg_time_slot_audit
AFTER INSERT OR DELETE OR UPDATE ON public.time_slot
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('ACADEMIC_CALENDAR', 'time_slot_id');

DROP TRIGGER IF EXISTS trg_room_audit ON public.room;
CREATE TRIGGER trg_room_audit
AFTER INSERT OR DELETE OR UPDATE ON public.room
FOR EACH ROW EXECUTE FUNCTION sims_private.audit_row('TIMETABLE', 'room_id');

-- ---------------------------------------------------------------------------------------------
-- Grants.
-- ---------------------------------------------------------------------------------------------
-- The two catalogue helpers are readable by the browser because the lookup RPC is
-- SECURITY INVOKER and therefore has to reach them as the caller.  They describe the
-- shape of the schema only - no row of the database is exposed by either of them.
-- ---------------------------------------------------------------------------------------------

GRANT EXECUTE ON FUNCTION sims_private.admin_table_def(text) TO authenticated;
GRANT EXECUTE ON FUNCTION sims_private.admin_lookup_def(text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.admin_table_list() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_table_schema(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_table_save(text, bigint, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_table_delete(text, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_lookup_options(text) TO authenticated;

GRANT EXECUTE ON FUNCTION public.admin_table_list() TO postgres;
GRANT EXECUTE ON FUNCTION public.admin_table_schema(text) TO postgres;
GRANT EXECUTE ON FUNCTION public.admin_table_save(text, bigint, jsonb) TO postgres;
GRANT EXECUTE ON FUNCTION public.admin_table_delete(text, bigint) TO postgres;
GRANT EXECUTE ON FUNCTION public.admin_lookup_options(text) TO postgres;

GRANT EXECUTE ON FUNCTION public.admin_table_list() TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_table_schema(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_table_save(text, bigint, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_table_delete(text, bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_lookup_options(text) TO service_role;
