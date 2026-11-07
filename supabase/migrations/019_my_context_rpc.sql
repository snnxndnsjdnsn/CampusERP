-- =============================================================================================
-- 019. my_context_rpc
-- ---------------------------------------------------------------------------------------------
-- GENERATED FILE - do not edit by hand.
-- Regenerate with: npm run migrate:build   (python tools/translate.py && python tools/build_migrations.py)
--
-- Source of truth: the live Supabase catalogue (tools/catalogue/live_catalogue.json),
-- dumped read-only from project khqqfgqvwdxlqkncwtmh by tools/dump_catalogue.py.
-- =============================================================================================

-- -----------------------------------------------------------------------------
-- `my_context()` and the public read RPCs.
--
-- These are the functions the application calls through PostgREST.  They are
-- SECURITY DEFINER with a pinned search_path, so they read the rows the
-- caller is allowed to see without exposing the tables themselves.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.announcement_attachment_list(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF NOT sims_private.announcement_visible(p_id) THEN RAISE EXCEPTION 'Unknown announcement' USING ERRCODE = '42501'; END IF;
    RETURN jsonb_build_object('can_edit', sims_private.announcement_editable(p_id),
        'files', COALESCE((SELECT jsonb_agg(jsonb_build_object('file_id', f.file_object_id, 'name', f.original_file_name, 'mime', f.mime_type, 'size', f.file_size_bytes) ORDER BY t.display_order, f.file_object_id)
                           FROM announcement_attachment t JOIN file_object f ON f.file_object_id = t.file_object_id WHERE t.announcement_id = p_id AND f.deleted_at IS NULL), '[]'::jsonb));
END $function$;

CREATE OR REPLACE FUNCTION public.announcement_can_post_global()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ SELECT sims_private.announcement_can('CREATE', NULL) $function$;

CREATE OR REPLACE FUNCTION public.announcement_detail(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a record; v_author boolean; v_manage boolean; v_can_edit boolean;
BEGIN
    SELECT x.*, t.type_name, d.department_name, aa.user_id AS author_id INTO a
    FROM announcement x JOIN announcement_type t ON t.announcement_type_id = x.announcement_type_id LEFT JOIN department d ON d.department_id = x.department_id
    LEFT JOIN sims_private.announcement_author aa ON aa.announcement_id = x.announcement_id WHERE x.announcement_id = p_id;
    IF a.announcement_id IS NULL THEN RAISE EXCEPTION 'Unknown announcement' USING ERRCODE = '42501'; END IF;
    v_author := a.author_id IS NOT DISTINCT FROM sims_private.current_user_id() AND a.author_id IS NOT NULL;
    v_manage := v_author OR sims_private.announcement_can('READ', a.department_id);
    IF NOT v_manage AND NOT (a.approval_status = 'APPROVED' AND a.publish_from <= now() AND (a.publish_to IS NULL OR a.publish_to > now()) AND sims_private.announcement_audience_ok(a.audience_type, a.department_id)) THEN
        RAISE EXCEPTION 'Unknown announcement' USING ERRCODE = '42501';
    END IF;
    v_can_edit := v_author OR sims_private.announcement_can('UPDATE', a.department_id);
    RETURN jsonb_build_object('announcement_id', a.announcement_id, 'title', a.title, 'description', a.description, 'type_id', a.announcement_type_id, 'type_name', a.type_name,
        'department_id', a.department_id, 'department_name', a.department_name, 'audience_type', a.audience_type, 'approval_status', a.approval_status,
        'publish_from', a.publish_from, 'publish_to', a.publish_to, 'is_mine', v_author,
        'can_edit', v_manage AND v_can_edit AND a.approval_status IN ('DRAFT', 'REJECTED'),
        'can_submit', v_manage AND v_can_edit AND a.approval_status IN ('DRAFT', 'REJECTED'),
        'can_decide', v_manage AND a.approval_status = 'PENDING' AND sims_private.announcement_can('APPROVE', a.department_id)
                      AND (NOT v_author OR sims_private.can_global(ARRAY['COMMUNICATION.ALL.CONFIGURE']::text[])),
        'can_archive', v_manage AND a.approval_status IN ('DRAFT', 'APPROVED', 'REJECTED') AND (sims_private.announcement_can('UPDATE', a.department_id) OR (v_author AND a.approval_status IN ('DRAFT', 'REJECTED'))),
        'managed', v_manage);
END $function$;

CREATE OR REPLACE FUNCTION public.announcement_targets()
 RETURNS TABLE(department_id integer, department_name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT d.department_id::integer, d.department_name::text FROM department d WHERE sims_private.announcement_can('CREATE', d.department_id) ORDER BY d.department_name
$function$;

CREATE OR REPLACE FUNCTION public.announcements_manage(p_status text DEFAULT NULL::text, p_search text DEFAULT NULL::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS TABLE(announcement_id bigint, title text, type_name text, department_name text, audience_type text, approval_status text, publish_from timestamp with time zone, publish_to timestamp with time zone, is_mine boolean, total_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    WITH visible AS (
        SELECT a.announcement_id, a.title::text, t.type_name::text, d.department_name::text, a.audience_type::text, a.approval_status::text, a.publish_from, a.publish_to,
               COALESCE(aa.user_id = sims_private.current_user_id(), false) AS is_mine
        FROM announcement a JOIN announcement_type t ON t.announcement_type_id = a.announcement_type_id LEFT JOIN department d ON d.department_id = a.department_id
        LEFT JOIN sims_private.announcement_author aa ON aa.announcement_id = a.announcement_id
        WHERE (p_status IS NULL OR a.approval_status = p_status)
          AND (p_search IS NULL OR btrim(p_search) = '' OR position(lower(btrim(p_search)) IN lower(a.title)) > 0)
          AND (sims_private.announcement_can('READ', a.department_id) OR aa.user_id = sims_private.current_user_id())
    )
    SELECT v.announcement_id::bigint, v.title, v.type_name, v.department_name, v.audience_type, v.approval_status, v.publish_from, v.publish_to, v.is_mine, count(*) OVER ()
    FROM visible v ORDER BY v.publish_from DESC, v.announcement_id DESC LIMIT LEAST(GREATEST(p_limit, 1), 200) OFFSET GREATEST(p_offset, 0)
$function$;

CREATE OR REPLACE FUNCTION public.assessment_offering_info(p_course_offering_id bigint)
 RETURNS TABLE(course_offering_id bigint, programme_term_offering_id bigint, programme_id integer, offering_code text, course_code text, course_title text, credits numeric, term_name text, programme_name text, semester_name text, internal_max_marks numeric, external_max_marks numeric, passing_marks numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_prog integer := sims_private.programme_of_offering(p_course_offering_id);
BEGIN
    IF v_prog IS NULL OR NOT (sims_private.can_programme(ARRAY['ASSESSMENT.ALL.READ']::text[], v_prog) OR sims_private.can_programme(ARRAY['RESULT.ALL.READ']::text[], v_prog)) THEN
        RAISE EXCEPTION 'Not authorised (ASSESSMENT.ALL.READ / RESULT.ALL.READ) or unknown offering' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    SELECT co.course_offering_id, co.programme_term_offering_id::bigint, pto.programme_id::integer, co.offering_code::text, c.course_code::text, c.course_title::text, c.credits,
           t.term_name::text, p.programme_name::text, s.semester_name::text, cc.internal_max_marks, cc.external_max_marks, cc.passing_marks
    FROM course_offering co
    JOIN programme_term_offering pto ON pto.programme_term_offering_id = co.programme_term_offering_id
    JOIN course_catalog c ON c.course_id = co.course_id
    JOIN academic_term t ON t.academic_term_id = pto.academic_term_id
    JOIN programme p ON p.programme_id = pto.programme_id
    JOIN semester s ON s.semester_id = pto.semester_id
    LEFT JOIN curriculum_course cc ON cc.curriculum_course_id = co.curriculum_course_id
    WHERE co.course_offering_id = p_course_offering_id;
END $function$;

CREATE OR REPLACE FUNCTION public.assessment_offerings(p_term bigint DEFAULT NULL::bigint, p_programme integer DEFAULT NULL::integer, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS TABLE(course_offering_id bigint, programme_term_offering_id bigint, offering_code text, course_code text, course_title text, term_name text, programme_name text, semester_name text, total_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    WITH visible AS (
        SELECT co.course_offering_id, co.programme_term_offering_id, co.offering_code, c.course_code, c.course_title, t.term_name, p.programme_name, s.semester_name
        FROM course_offering co
        JOIN programme_term_offering pto ON pto.programme_term_offering_id = co.programme_term_offering_id
        JOIN course_catalog c ON c.course_id = co.course_id
        JOIN academic_term t ON t.academic_term_id = pto.academic_term_id
        JOIN programme p ON p.programme_id = pto.programme_id
        JOIN semester s ON s.semester_id = pto.semester_id
        WHERE (p_term IS NULL OR pto.academic_term_id = p_term) AND (p_programme IS NULL OR pto.programme_id = p_programme)
          AND (sims_private.can_programme(ARRAY['ASSESSMENT.ALL.READ']::text[], pto.programme_id) OR sims_private.can_programme(ARRAY['RESULT.ALL.READ']::text[], pto.programme_id))
    )
    SELECT v.course_offering_id, v.programme_term_offering_id, v.offering_code::text, v.course_code::text, v.course_title::text, v.term_name::text, v.programme_name::text, v.semester_name::text,
           count(*) OVER ()
    FROM visible v ORDER BY v.course_offering_id DESC LIMIT LEAST(GREATEST(p_limit, 1), 200) OFFSET GREATEST(p_offset, 0)
$function$;

CREATE OR REPLACE FUNCTION public.assessment_sheet(p_event_id bigint)
 RETURNS TABLE(course_registration_id bigint, student_id bigint, student_number text, display_name text, attendance_status text, marks_obtained numeric, reduced_marks numeric, remarks text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_off bigint;
BEGIN
    SELECT course_offering_id INTO v_off FROM assessment_event WHERE assessment_event_id = p_event_id;
    IF v_off IS NULL THEN RAISE EXCEPTION 'Not authorised (ASSESSMENT.ALL.READ) or unknown event' USING ERRCODE = '42501'; END IF;
    PERFORM sims_private.asm_authorize(v_off, 'ASSESSMENT', 'READ');
    RETURN QUERY
    SELECT cr.course_registration_id, s.student_id, s.student_number::text, s.display_name::text, m.attendance_status::text, m.marks_obtained, m.reduced_marks, m.remarks::text
    FROM student_course_registration cr
    JOIN student_term_registration tr ON tr.term_registration_id = cr.term_registration_id
    JOIN student_programme_enrolment e ON e.enrolment_id = tr.enrolment_id
    JOIN student s ON s.student_id = e.student_id
    LEFT JOIN student_assessment_mark m ON m.assessment_event_id = p_event_id AND m.course_registration_id = cr.course_registration_id
    WHERE cr.course_offering_id = v_off AND cr.registration_status IN ('REGISTERED', 'APPROVED', 'COMPLETED')
    ORDER BY s.display_name, cr.course_registration_id;
END $function$;

CREATE OR REPLACE FUNCTION public.attendance_sheet(p_session_id bigint)
 RETURNS TABLE(roster_id bigint, student_id bigint, student_number text, display_name text, attendance_status_id integer, remarks text, marked_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_cos bigint := sims_private.att_session_cos(p_session_id);
BEGIN
    IF v_cos IS NULL THEN RAISE EXCEPTION 'Not authorised (ATTENDANCE.ALL.READ) or unknown session' USING ERRCODE = '42501'; END IF;
    PERFORM sims_private.att_authorize_cos(v_cos, 'ATTENDANCE', 'READ');
    RETURN QUERY
    SELECT r.course_offering_section_student_id, s.student_id, s.student_number::text, s.display_name::text, a.attendance_status_id::integer, a.remarks::text, a.marked_at
    FROM course_offering_section_student r
    JOIN student_course_registration cr ON cr.course_registration_id = r.course_registration_id
    JOIN student_term_registration tr ON tr.term_registration_id = cr.term_registration_id
    JOIN student_programme_enrolment e ON e.enrolment_id = tr.enrolment_id
    JOIN student s ON s.student_id = e.student_id
    LEFT JOIN student_attendance a ON a.class_session_id = p_session_id AND a.course_offering_section_student_id = r.course_offering_section_student_id
    WHERE r.course_offering_section_id = v_cos AND r.roster_status = 'ACTIVE'
    ORDER BY s.display_name, r.course_offering_section_student_id;
END $function$;

CREATE OR REPLACE FUNCTION public.attendance_summary(p_cos_id bigint)
 RETURNS TABLE(roster_id bigint, student_id bigint, student_number text, display_name text, conducted_sessions integer, present_sessions integer, percentage numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_total integer;
BEGIN
    PERFORM sims_private.att_authorize_cos(p_cos_id, 'ATTENDANCE', 'READ');
    SELECT count(*)::integer INTO v_total FROM class_session WHERE course_offering_section_id = p_cos_id AND session_status = 'CONDUCTED';
    RETURN QUERY
    SELECT r.course_offering_section_student_id, s.student_id, s.student_number::text, s.display_name::text, v_total,
           count(*) FILTER (WHERE st.counts_as_present AND cs.session_status = 'CONDUCTED')::integer,
           CASE WHEN v_total = 0 THEN NULL ELSE round(100.0 * count(*) FILTER (WHERE st.counts_as_present AND cs.session_status = 'CONDUCTED') / v_total, 1) END
    FROM course_offering_section_student r
    JOIN student_course_registration cr ON cr.course_registration_id = r.course_registration_id
    JOIN student_term_registration tr ON tr.term_registration_id = cr.term_registration_id
    JOIN student_programme_enrolment e ON e.enrolment_id = tr.enrolment_id
    JOIN student s ON s.student_id = e.student_id
    LEFT JOIN student_attendance a ON a.course_offering_section_student_id = r.course_offering_section_student_id
    LEFT JOIN attendance_status st ON st.attendance_status_id = a.attendance_status_id
    LEFT JOIN class_session cs ON cs.class_session_id = a.class_session_id
    WHERE r.course_offering_section_id = p_cos_id AND r.roster_status = 'ACTIVE'
    GROUP BY r.course_offering_section_student_id, s.student_id, s.student_number, s.display_name
    ORDER BY s.display_name;
END $function$;

CREATE OR REPLACE FUNCTION public.audit_get(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a record;
BEGIN
    IF NOT sims_private.can_global(ARRAY['AUDIT.ALL.READ']::text[]) THEN RAISE EXCEPTION 'Not authorised (AUDIT.ALL.READ)' USING ERRCODE = '42501'; END IF;
    SELECT x.*, u.username INTO a FROM activity_audit x LEFT JOIN user_account u ON u.user_id = x.user_id WHERE x.activity_audit_id = p_id;
    IF a.activity_audit_id IS NULL THEN RAISE EXCEPTION 'Unknown audit entry' USING ERRCODE = '22023'; END IF;
    RETURN jsonb_build_object('activity_audit_id', a.activity_audit_id, 'activity_at', a.activity_at, 'username', a.username, 'module_code', a.module_code, 'action_code', a.action_code,
        'entity_name', a.entity_name, 'entity_id', a.entity_id, 'before_values', a.before_values, 'after_values', a.after_values, 'details', a.details);
END $function$;

CREATE OR REPLACE FUNCTION public.audit_list(p_module text DEFAULT NULL::text, p_action text DEFAULT NULL::text, p_search text DEFAULT NULL::text, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 25, p_offset integer DEFAULT 0)
 RETURNS TABLE(activity_audit_id bigint, activity_at timestamp with time zone, username text, module_code text, action_code text, entity_name text, entity_id text, total_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT a.activity_audit_id::bigint, a.activity_at, u.username::text, a.module_code::text, a.action_code::text, a.entity_name::text, a.entity_id::text, count(*) OVER ()
    FROM activity_audit a LEFT JOIN user_account u ON u.user_id = a.user_id
    WHERE sims_private.can_global(ARRAY['AUDIT.ALL.READ']::text[])
      AND (p_module IS NULL OR a.module_code = p_module) AND (p_action IS NULL OR a.action_code = p_action)
      AND (p_from IS NULL OR a.activity_at >= p_from) AND (p_to IS NULL OR a.activity_at < p_to)
      AND (p_search IS NULL OR btrim(p_search) = '' OR position(lower(btrim(p_search)) IN lower(COALESCE(a.entity_name, '') || ' ' || COALESCE(a.entity_id, '') || ' ' || COALESCE(u.username, ''))) > 0)
    ORDER BY a.activity_at DESC, a.activity_audit_id DESC LIMIT LEAST(GREATEST(p_limit, 1), 200) OFFSET GREATEST(p_offset, 0)
$function$;

CREATE OR REPLACE FUNCTION public.audit_modules()
 RETURNS TABLE(module_code text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT DISTINCT a.module_code::text FROM activity_audit a WHERE sims_private.can_global(ARRAY['AUDIT.ALL.READ']::text[]) ORDER BY 1
$function$;

CREATE OR REPLACE FUNCTION public.cert_request_list(p_student_id bigint DEFAULT NULL::bigint, p_status text DEFAULT NULL::text)
 RETURNS TABLE(certificate_request_id bigint, request_number text, student_id bigint, student_number text, student_name text, certificate_name text, purpose text, request_status text, requested_at timestamp with time zone, issued_at timestamp with time zone, certificate_number text, has_file boolean, can_approve boolean, can_issue boolean, can_cancel boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT r.certificate_request_id::bigint, r.request_number::text, r.student_id::bigint, s.student_number::text, s.display_name::text, t.certificate_name::text, r.purpose::text, r.request_status::text, r.requested_at, r.issued_at,
           r.certificate_number::text, r.file_object_id IS NOT NULL,
           r.request_status = 'SUBMITTED' AND sims_private.can_student(ARRAY['DOCUMENT.ALL.APPROVE']::text[], r.student_id, true),
           r.request_status = 'APPROVED' AND sims_private.can_student(ARRAY['DOCUMENT.ALL.CREATE']::text[], r.student_id, true),
           r.request_status = 'SUBMITTED' AND (sims_private.is_me_student(r.student_id) OR sims_private.can_student(ARRAY['DOCUMENT.ALL.UPDATE']::text[], r.student_id, true))
    FROM certificate_request r JOIN student s ON s.student_id = r.student_id JOIN certificate_type t ON t.certificate_type_id = r.certificate_type_id
    WHERE (p_student_id IS NULL OR r.student_id = p_student_id) AND (p_status IS NULL OR r.request_status = p_status)
      AND (sims_private.is_me_student(r.student_id) OR sims_private.can_student(ARRAY['DOCUMENT.ALL.READ']::text[], r.student_id, false))
    ORDER BY r.requested_at DESC, r.certificate_request_id DESC LIMIT 200
$function$;

CREATE OR REPLACE FUNCTION public.dash_applications()
 RETURNS TABLE(application_status text, n bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT a.application_status::text, count(*) FROM admission_application a GROUP BY a.application_status ORDER BY 1
$function$;

CREATE OR REPLACE FUNCTION public.dash_employees()
 RETURNS TABLE(employment_type text, employment_status text, n bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT e.employment_type::text, e.employment_status::text, count(*) FROM employee e GROUP BY e.employment_type, e.employment_status ORDER BY 1, 2
$function$;

CREATE OR REPLACE FUNCTION public.dash_enrolments()
 RETURNS TABLE(programme_id integer, label text, enrolment_status text, n bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT e.programme_id::integer, COALESCE(p.programme_name, 'Programme #' || e.programme_id)::text, e.enrolment_status::text, count(*)
    FROM student_programme_enrolment e LEFT JOIN programme p ON p.programme_id = e.programme_id
    GROUP BY e.programme_id, p.programme_name, e.enrolment_status ORDER BY 2, 3
$function$;

CREATE OR REPLACE FUNCTION public.dash_fee_collection(p_months integer DEFAULT 6)
 RETURNS TABLE(month date, collected numeric, payments bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
    WITH m AS (
        SELECT generate_series(date_trunc('month', timezone('UTC', now()))::date - ((GREATEST(LEAST(COALESCE(p_months, 6), 36), 1) - 1) * interval '1 month'),
                               date_trunc('month', timezone('UTC', now()))::date, interval '1 month')::date AS month
    )
    SELECT m.month, COALESCE(sum(p.amount), 0), count(p.payment_transaction_id)
    FROM m LEFT JOIN payment_transaction p
      ON p.payment_status = 'SUCCESS' AND date_trunc('month', timezone('UTC', p.transaction_date))::date = m.month
    GROUP BY m.month ORDER BY m.month
$function$;

CREATE OR REPLACE FUNCTION public.dash_fee_outstanding()
 RETURNS TABLE(payable numeric, paid numeric, balance numeric, overdue_assessments bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT COALESCE(sum(f.net_payable_amount), 0), COALESCE(sum(f.amount_paid), 0), COALESCE(sum(f.balance_amount), 0),
           count(*) FILTER (WHERE f.balance_amount > 0 AND f.due_date IS NOT NULL AND f.due_date < current_date)
    FROM student_fee_assessment f WHERE f.assessment_status NOT IN ('CANCELLED', 'WAIVED', 'DRAFT')
$function$;

CREATE OR REPLACE FUNCTION public.dash_registrations()
 RETURNS TABLE(registration_status text, n bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT r.registration_status::text, count(*) FROM student_term_registration r GROUP BY r.registration_status ORDER BY 1
$function$;

CREATE OR REPLACE FUNCTION public.dash_sessions(p_days integer DEFAULT 30)
 RETURNS TABLE(session_status text, n bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT c.session_status::text, count(*) FROM class_session c
    WHERE c.session_date <= current_date AND c.session_date > current_date - GREATEST(LEAST(COALESCE(p_days, 30), 366), 1)
    GROUP BY c.session_status ORDER BY 1
$function$;

CREATE OR REPLACE FUNCTION public.dash_term_results()
 RETURNS TABLE(result_status text, published boolean, n bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT r.result_status::text, r.published_at IS NOT NULL, count(*) FROM student_term_result r GROUP BY r.result_status, r.published_at IS NOT NULL ORDER BY 1, 2
$function$;

CREATE OR REPLACE FUNCTION public.emp_competency_list(p_employee_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF NOT (sims_private.emp_is_owner(p_employee_id) OR sims_private.emp_all_can(p_employee_id, 'READ')) THEN RAISE EXCEPTION 'Not authorised (EMPLOYEE.ALL.READ) or unknown employee' USING ERRCODE = '42501'; END IF;
    RETURN jsonb_build_object('can_edit', sims_private.emp_all_can(p_employee_id, 'CREATE'), 'can_delete', sims_private.emp_all_can(p_employee_id, 'DELETE'),
        'rows', COALESCE((SELECT jsonb_agg(jsonb_build_object('course_id', c.course_id, 'course_code', k.course_code, 'course_title', k.course_title, 'level', c.competency_level, 'valid_from', c.valid_from, 'valid_to', c.valid_to,
                  'active', (c.valid_from IS NULL OR c.valid_from <= current_date) AND (c.valid_to IS NULL OR c.valid_to >= current_date)) ORDER BY k.course_code)
                  FROM employee_competency c JOIN course_catalog k ON k.course_id = c.course_id WHERE c.employee_id = p_employee_id), '[]'::jsonb));
END $function$;

CREATE OR REPLACE FUNCTION public.emp_doc_rule_list(p_document_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_emp bigint;
BEGIN
    SELECT employee_id INTO v_emp FROM employee_document WHERE employee_document_id = p_document_id AND deleted_at IS NULL;
    IF v_emp IS NULL OR NOT sims_private.emp_can(v_emp, 'EMPLOYEE_DOCUMENT', 'UPDATE', true) THEN RAISE EXCEPTION 'Not authorised (EMPLOYEE.EMPLOYEE_DOCUMENT.UPDATE) or unknown document' USING ERRCODE = '42501'; END IF;
    RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id', r.employee_document_access_rule_id, 'who', COALESCE('role ' || ro.role_name, 'user ' || u.username), 'can_view', r.can_view, 'can_download', r.can_download,
              'valid_from', r.valid_from, 'valid_to', r.valid_to, 'active', r.valid_from <= now() AND (r.valid_to IS NULL OR r.valid_to > now())) ORDER BY r.employee_document_access_rule_id DESC)
              FROM employee_document_access_rule r LEFT JOIN role ro ON ro.role_id = r.role_id LEFT JOIN user_account u ON u.user_id = r.user_id WHERE r.employee_document_id = p_document_id), '[]'::jsonb);
END $function$;

CREATE OR REPLACE FUNCTION public.emp_sensitive_list(p_employee_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_own boolean := sims_private.emp_is_owner(p_employee_id); r jsonb;
BEGIN
    IF NOT (v_own OR sims_private.emp_can(p_employee_id, 'PAN', 'READ', false) OR sims_private.emp_can(p_employee_id, 'AADHAAR', 'READ', false) OR sims_private.emp_can(p_employee_id, 'BANK_ACCOUNT', 'READ', false)) THEN
        RAISE EXCEPTION 'Not authorised (EMPLOYEE.PAN.READ) or unknown employee' USING ERRCODE = '42501';
    END IF;
    r := jsonb_build_object(
      'pan', CASE WHEN v_own OR sims_private.emp_can(p_employee_id, 'PAN', 'READ', false) THEN (SELECT to_jsonb(x) FROM (SELECT employee_pan_id AS id, pan_number_masked AS masked, name_as_per_pan AS name, verification_status AS status, verification_remarks AS remarks, pan_issue_date AS issue_date, updated_at FROM employee_pan WHERE employee_id = p_employee_id) x) END,
      'aadhaar', CASE WHEN v_own OR sims_private.emp_can(p_employee_id, 'AADHAAR', 'READ', false) THEN (SELECT to_jsonb(x) FROM (SELECT employee_aadhaar_id AS id, aadhaar_number_masked AS masked, name_as_per_aadhaar AS name, verification_status AS status, verification_remarks AS remarks, collection_purpose AS purpose, updated_at FROM employee_aadhaar WHERE employee_id = p_employee_id) x) END,
      'bank', CASE WHEN v_own OR sims_private.emp_can(p_employee_id, 'BANK_ACCOUNT', 'READ', false) THEN (SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.is_primary DESC, x.id), '[]'::jsonb) FROM (SELECT employee_bank_account_id AS id, account_holder_name AS holder, bank_name AS bank, branch_name AS branch, 'XXXXXX' || account_number_last4 AS masked, account_type AS type, ifsc_code AS ifsc, upi_id AS upi, is_primary, is_salary_account AS is_salary, account_status AS account_status, verification_status AS status, verification_remarks AS remarks FROM employee_bank_account WHERE employee_id = p_employee_id AND deleted_at IS NULL) x) ELSE '[]'::jsonb END,
      'can', jsonb_build_object(
        'owner', v_own,
        'edit_pan', sims_private.emp_can(p_employee_id, 'PAN', 'UPDATE', true) OR v_own, 'edit_aadhaar', sims_private.emp_can(p_employee_id, 'AADHAAR', 'UPDATE', true) OR v_own, 'edit_bank', sims_private.emp_can(p_employee_id, 'BANK_ACCOUNT', 'UPDATE', true) OR v_own,
        'verify_pan', sims_private.emp_can(p_employee_id, 'PAN', 'VERIFY', true), 'verify_aadhaar', sims_private.emp_can(p_employee_id, 'AADHAAR', 'VERIFY', true), 'verify_bank', sims_private.emp_can(p_employee_id, 'BANK_ACCOUNT', 'VERIFY', true),
        'reveal_pan', v_own OR sims_private.emp_can(p_employee_id, 'PAN', 'EXPORT', true), 'reveal_aadhaar', v_own OR sims_private.emp_can(p_employee_id, 'AADHAAR', 'EXPORT', true), 'reveal_bank', v_own OR sims_private.emp_can(p_employee_id, 'BANK_ACCOUNT', 'EXPORT', true),
        'delete_pan', sims_private.emp_can(p_employee_id, 'PAN', 'DELETE', true), 'delete_aadhaar', sims_private.emp_can(p_employee_id, 'AADHAAR', 'DELETE', true), 'delete_bank', sims_private.emp_can(p_employee_id, 'BANK_ACCOUNT', 'DELETE', true)));
    RETURN r;
END $function$;

CREATE OR REPLACE FUNCTION public.emp_sensitive_reveal(p_kind text, p_id bigint, p_purpose text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE r record; v_own boolean;
BEGIN
    SELECT * INTO r FROM sims_private.emp_sensitive_row(p_kind, p_id);
    v_own := sims_private.emp_is_owner(r.employee_id);
    IF r.employee_id IS NULL OR NOT (v_own OR sims_private.emp_can(r.employee_id, p_kind, 'EXPORT', true)) THEN RAISE EXCEPTION 'Not authorised (EMPLOYEE.%.EXPORT) or unknown record', p_kind USING ERRCODE = '42501'; END IF;
    IF NOT v_own AND (p_purpose IS NULL OR length(btrim(p_purpose)) < 5 OR length(p_purpose) > 500) THEN RAISE EXCEPTION 'State the purpose of viewing the full number (5 to 500 characters)' USING ERRCODE = '22023'; END IF;
    PERFORM sims_private.emp_sensitive_log(r.employee_id, 'DECRYPT', p_kind, p_id, COALESCE(p_purpose, 'owner'));
    RETURN sims_private.pii_decrypt(r.ciphertext);
END $function$;

CREATE OR REPLACE FUNCTION public.employee_document_download_info(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE d record;
BEGIN
    SELECT d0.employee_document_id, d0.employee_id, f.storage_key, f.original_file_name, f.mime_type INTO d
    FROM employee_document d0 JOIN file_object f ON f.file_object_id = d0.file_object_id WHERE d0.employee_document_id = p_id AND d0.deleted_at IS NULL AND f.deleted_at IS NULL;
    IF d.employee_document_id IS NULL OR NOT (sims_private.emp_is_owner(d.employee_id) OR sims_private.emp_can(d.employee_id, 'EMPLOYEE_DOCUMENT', 'READ', false) OR sims_private.emp_doc_rule_ok(d.employee_document_id, 'download')) THEN
        RAISE EXCEPTION 'Not authorised (EMPLOYEE.EMPLOYEE_DOCUMENT.READ) or unknown document' USING ERRCODE = '42501';
    END IF;
    PERFORM sims_private.emp_sensitive_log(d.employee_id, 'DOWNLOAD', 'EMPLOYEE_DOCUMENT', p_id, NULL, p_id);
    RETURN jsonb_build_object('storage_key', d.storage_key, 'file_name', d.original_file_name, 'mime_type', d.mime_type);
END $function$;

CREATE OR REPLACE FUNCTION public.employee_document_list(p_employee_id bigint)
 RETURNS TABLE(employee_document_id bigint, category text, document_title text, original_file_name text, mime_type text, file_size_bytes bigint, document_number text, issue_date date, expiry_date date, verification_status text, effective_status text, approval_status text, verification_remarks text, uploaded_at timestamp with time zone, confidentiality_level text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT d.employee_document_id::bigint, c.category_name::text, d.document_title::text, f.original_file_name::text, f.mime_type::text, f.file_size_bytes::bigint, d.document_number::text, d.issue_date, d.expiry_date,
           d.verification_status::text, CASE WHEN d.verification_status = 'VERIFIED' AND d.expiry_date < CURRENT_DATE THEN 'EXPIRED' ELSE d.verification_status END::text, d.approval_status::text,
           d.verification_remarks::text, f.uploaded_at, d.confidentiality_level::text
    FROM employee_document d JOIN employee_document_category c ON c.employee_document_category_id = d.employee_document_category_id JOIN file_object f ON f.file_object_id = d.file_object_id
    WHERE d.employee_id = p_employee_id AND d.deleted_at IS NULL AND f.deleted_at IS NULL
      AND (sims_private.emp_is_owner(p_employee_id) OR sims_private.emp_can(p_employee_id, 'EMPLOYEE_DOCUMENT', 'READ', false) OR sims_private.emp_doc_rule_ok(d.employee_document_id, 'view'))
    ORDER BY f.uploaded_at DESC, d.employee_document_id DESC
$function$;

CREATE OR REPLACE FUNCTION public.feedback_cycle_offerings(p_cycle_id bigint)
 RETURNS TABLE(course_offering_id bigint, course_label text, programme_name text, responses bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT co.course_offering_id::bigint, (cc.course_code || ' — ' || cc.course_title)::text, p.programme_name::text,
           (SELECT count(*) FROM feedback_response r WHERE r.feedback_cycle_id = p_cycle_id AND r.course_offering_id = co.course_offering_id)
    FROM feedback_cycle cy
    JOIN programme_term_offering pto ON pto.academic_term_id = cy.academic_term_id
    JOIN course_offering co ON co.programme_term_offering_id = pto.programme_term_offering_id
    JOIN course_catalog cc ON cc.course_id = co.course_id
    JOIN programme p ON p.programme_id = pto.programme_id
    WHERE cy.feedback_cycle_id = p_cycle_id AND cy.result_visibility <> 'HIDDEN'
      AND sims_private.can_programme(ARRAY['FEEDBACK.ALL.READ']::text[], pto.programme_id)
    ORDER BY cc.course_code, co.course_offering_id
$function$;

CREATE OR REPLACE FUNCTION public.feedback_form(p_cycle_id bigint)
 RETURNS TABLE(questionnaire_item_id bigint, display_order integer, is_required boolean, question_text text, response_type text, category_name text, choices jsonb)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT i.questionnaire_item_id::bigint, i.display_order::integer, i.is_required, q.question_text::text, q.response_type::text, k.category_name::text,
           COALESCE((SELECT jsonb_agg(jsonb_build_object('id', c.feedback_choice_id, 'text', c.choice_text) ORDER BY c.display_order NULLS LAST, c.feedback_choice_id)
                     FROM feedback_choice c WHERE c.feedback_question_id = q.feedback_question_id AND c.is_active), '[]'::jsonb)
    FROM feedback_cycle cy
    JOIN feedback_questionnaire_item i ON i.questionnaire_id = cy.questionnaire_id
    JOIN feedback_question q ON q.feedback_question_id = i.feedback_question_id
    JOIN feedback_question_category k ON k.feedback_category_id = q.feedback_category_id
    WHERE cy.feedback_cycle_id = p_cycle_id ORDER BY i.display_order, i.questionnaire_item_id
$function$;

CREATE OR REPLACE FUNCTION public.feedback_my_tasks()
 RETURNS TABLE(feedback_cycle_id bigint, cycle_name text, questionnaire_type text, is_anonymous boolean, end_at timestamp with time zone, course_offering_id bigint, course_label text, faculty_assignment_id bigint, instructor_name text, submitted boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    WITH me AS (SELECT sims_private.current_student_id() AS sid),
    cyc AS (
        SELECT c.feedback_cycle_id, c.cycle_name, c.academic_term_id, c.end_at, q.questionnaire_type, q.is_anonymous
        FROM feedback_cycle c JOIN feedback_questionnaire q ON q.questionnaire_id = c.questionnaire_id
        WHERE c.status = 'OPEN' AND now() >= c.start_at AND now() <= c.end_at AND q.status = 'ACTIVE'
    ),
    trs AS (
        SELECT tr.term_registration_id, pto.academic_term_id
        FROM student_term_registration tr
        JOIN student_programme_enrolment e ON e.enrolment_id = tr.enrolment_id
        JOIN programme_term_offering pto ON pto.programme_term_offering_id = tr.programme_term_offering_id
        WHERE e.student_id = (SELECT sid FROM me) AND tr.registration_status IN ('REGISTERED', 'APPROVED', 'COMPLETED')
    ),
    targets AS (
        -- COURSE: one task per registered course
        SELECT cyc.feedback_cycle_id, trs.term_registration_id, cr.course_offering_id, NULL::bigint AS faculty_assignment_id
        FROM cyc JOIN trs ON trs.academic_term_id = cyc.academic_term_id
        JOIN student_course_registration cr ON cr.term_registration_id = trs.term_registration_id AND cr.registration_status IN ('REGISTERED', 'APPROVED', 'COMPLETED')
        WHERE cyc.questionnaire_type = 'COURSE'
        UNION ALL
        -- FACULTY: one task per active instructor of each registered course
        SELECT cyc.feedback_cycle_id, trs.term_registration_id, cr.course_offering_id, fa.faculty_assignment_id
        FROM cyc JOIN trs ON trs.academic_term_id = cyc.academic_term_id
        JOIN student_course_registration cr ON cr.term_registration_id = trs.term_registration_id AND cr.registration_status IN ('REGISTERED', 'APPROVED', 'COMPLETED')
        JOIN course_offering_section cos ON cos.course_offering_id = cr.course_offering_id
        JOIN faculty_course_assignment fa ON fa.course_offering_section_id = cos.course_offering_section_id AND fa.assignment_status IN ('ACTIVE', 'COMPLETED')
        WHERE cyc.questionnaire_type = 'FACULTY'
        UNION ALL
        -- other types: one task per cycle (the student's most recent registration in the term)
        (SELECT DISTINCT ON (cyc.feedback_cycle_id) cyc.feedback_cycle_id, trs.term_registration_id, NULL::bigint, NULL::bigint
         FROM cyc JOIN trs ON trs.academic_term_id = cyc.academic_term_id
         WHERE cyc.questionnaire_type NOT IN ('COURSE', 'FACULTY') ORDER BY cyc.feedback_cycle_id, trs.term_registration_id DESC)
    )
    SELECT DISTINCT ON (cyc.feedback_cycle_id, t.course_offering_id, t.faculty_assignment_id)
           cyc.feedback_cycle_id, cyc.cycle_name::text, cyc.questionnaire_type::text, cyc.is_anonymous, cyc.end_at,
           t.course_offering_id, (cc.course_code || ' — ' || cc.course_title)::text, t.faculty_assignment_id, emp.display_name::text,
           EXISTS (SELECT 1 FROM sims_private.feedback_submission s WHERE s.feedback_cycle_id = t.feedback_cycle_id AND s.term_registration_id = t.term_registration_id
                   AND s.course_offering_id = COALESCE(t.course_offering_id, 0) AND s.faculty_assignment_id = COALESCE(t.faculty_assignment_id, 0))
    FROM targets t
    JOIN cyc ON cyc.feedback_cycle_id = t.feedback_cycle_id
    LEFT JOIN course_offering co ON co.course_offering_id = t.course_offering_id
    LEFT JOIN course_catalog cc ON cc.course_id = co.course_id
    LEFT JOIN faculty_course_assignment fa ON fa.faculty_assignment_id = t.faculty_assignment_id
    LEFT JOIN employee emp ON emp.employee_id = fa.employee_id
    WHERE (SELECT sid FROM me) IS NOT NULL
    ORDER BY cyc.feedback_cycle_id, t.course_offering_id, t.faculty_assignment_id
$function$;

CREATE OR REPLACE FUNCTION public.feedback_results(p_cycle_id bigint, p_course_offering_id bigint DEFAULT NULL::bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_cycle record; v_emp bigint := sims_private.current_employee_id(); v_gl boolean := sims_private.can_global(ARRAY['FEEDBACK.ALL.CONFIGURE']::text[]);
    v_glread boolean := sims_private.can_global(ARRAY['FEEDBACK.ALL.READ']::text[]); v_member boolean := sims_private.is_active_member();
    v_visible bigint[]; v_full bigint[]; v_count integer; v_out jsonb;
BEGIN
    SELECT c.feedback_cycle_id, c.cycle_name, c.result_visibility AS vis, c.status, q.questionnaire_id, q.questionnaire_type, q.is_anonymous
    INTO v_cycle FROM feedback_cycle c JOIN feedback_questionnaire q ON q.questionnaire_id = c.questionnaire_id WHERE c.feedback_cycle_id = p_cycle_id;
    IF v_cycle IS NULL OR NOT v_member THEN RAISE EXCEPTION 'Not authorised (FEEDBACK.ALL.READ) or unknown cycle' USING ERRCODE = '42501'; END IF;

    WITH r AS (
        SELECT fr.feedback_response_id,
               EXISTS (SELECT 1 FROM faculty_course_assignment fa WHERE fa.faculty_assignment_id = fr.faculty_assignment_id AND fa.employee_id = v_emp) AS own,
               (fr.course_offering_id IS NOT NULL AND sims_private.can_programme(ARRAY['FEEDBACK.ALL.READ']::text[], sims_private.programme_of_offering(fr.course_offering_id))) AS prog_read
        FROM feedback_response fr
        WHERE fr.feedback_cycle_id = p_cycle_id AND (p_course_offering_id IS NULL OR fr.course_offering_id = p_course_offering_id)
    ), f AS (
        SELECT r.feedback_response_id,
               (v_gl OR (v_cycle.vis <> 'HIDDEN' AND (r.prog_read OR v_glread) AND (NOT r.own OR v_cycle.vis IN ('FACULTY', 'PUBLIC')))
                     OR (v_cycle.vis IN ('FACULTY', 'PUBLIC') AND r.own)) AS full_access
        FROM r
    )
    SELECT array_agg(feedback_response_id) FILTER (WHERE full_access OR v_cycle.vis = 'PUBLIC'), array_agg(feedback_response_id) FILTER (WHERE full_access)
    INTO v_visible, v_full FROM f;
    v_visible := COALESCE(v_visible, '{}'); v_full := COALESCE(v_full, '{}');
    v_count := cardinality(v_visible);

    IF v_count < sims_private.feedback_min_responses() THEN
        RETURN jsonb_build_object('cycle_name', v_cycle.cycle_name, 'visibility', v_cycle.vis, 'questionnaire_type', v_cycle.questionnaire_type, 'anonymous', v_cycle.is_anonymous,
                                  'response_count', v_count, 'suppressed', true, 'minimum', sims_private.feedback_min_responses(), 'questions', '[]'::jsonb);
    END IF;

    SELECT jsonb_build_object('cycle_name', v_cycle.cycle_name, 'visibility', v_cycle.vis, 'questionnaire_type', v_cycle.questionnaire_type, 'anonymous', v_cycle.is_anonymous,
                              'response_count', v_count, 'suppressed', false, 'minimum', sims_private.feedback_min_responses(),
        'questions', COALESCE(jsonb_agg(jsonb_build_object(
            'questionnaire_item_id', i.questionnaire_item_id, 'question_text', q.question_text, 'response_type', q.response_type,
            'answered', (SELECT count(*) FROM feedback_response_item x WHERE x.questionnaire_item_id = i.questionnaire_item_id AND x.feedback_response_id = ANY (v_visible)),
            'average', (SELECT round(avg(x.numeric_score), 2) FROM feedback_response_item x WHERE x.questionnaire_item_id = i.questionnaire_item_id AND x.feedback_response_id = ANY (v_visible) AND x.numeric_score IS NOT NULL),
            'distribution', CASE q.response_type
                WHEN 'RATING' THEN COALESCE((SELECT jsonb_agg(jsonb_build_object('label', s.score::text, 'count', s.n) ORDER BY s.score)
                    FROM (SELECT x.numeric_score AS score, count(*) AS n FROM feedback_response_item x WHERE x.questionnaire_item_id = i.questionnaire_item_id AND x.feedback_response_id = ANY (v_visible) GROUP BY x.numeric_score) s), '[]'::jsonb)
                WHEN 'SINGLE_CHOICE' THEN COALESCE((SELECT jsonb_agg(jsonb_build_object('label', s.choice_text, 'count', s.n) ORDER BY s.n DESC, s.choice_text)
                    FROM (SELECT c.choice_text, count(*) AS n FROM feedback_response_item x JOIN feedback_choice c ON c.feedback_choice_id = x.feedback_choice_id
                          WHERE x.questionnaire_item_id = i.questionnaire_item_id AND x.feedback_response_id = ANY (v_visible) GROUP BY c.choice_text) s), '[]'::jsonb)
                WHEN 'MULTIPLE_CHOICE' THEN COALESCE((SELECT jsonb_agg(jsonb_build_object('label', s.choice_text, 'count', s.n) ORDER BY s.n DESC, s.choice_text)
                    FROM (SELECT c.choice_text, count(*) AS n FROM feedback_response_item x
                          CROSS JOIN LATERAL unnest(string_to_array(x.text_response, ',')) AS sel(id)
                          JOIN feedback_choice c ON c.feedback_choice_id = sel.id::bigint
                          WHERE x.questionnaire_item_id = i.questionnaire_item_id AND x.feedback_response_id = ANY (v_visible) GROUP BY c.choice_text) s), '[]'::jsonb)
                ELSE '[]'::jsonb END,
            'texts', CASE q.response_type WHEN 'TEXT' THEN COALESCE((SELECT jsonb_agg(x.text_response ORDER BY x.feedback_response_item_id)
                    FROM feedback_response_item x WHERE x.questionnaire_item_id = i.questionnaire_item_id AND x.feedback_response_id = ANY (v_full) AND x.text_response IS NOT NULL), '[]'::jsonb) ELSE '[]'::jsonb END
        ) ORDER BY i.display_order, i.questionnaire_item_id), '[]'::jsonb))
    INTO v_out
    FROM feedback_questionnaire_item i JOIN feedback_question q ON q.feedback_question_id = i.feedback_question_id
    WHERE i.questionnaire_id = v_cycle.questionnaire_id;
    RETURN v_out;
END $function$;

CREATE OR REPLACE FUNCTION public.fin_academic_years()
 RETURNS TABLE(academic_year_id integer, year_code text, status text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT y.academic_year_id::integer, y.year_code::text, y.status::text FROM academic_year y
    WHERE sims_private.current_user_id() IS NOT NULL ORDER BY y.start_date DESC
$function$;

CREATE OR REPLACE FUNCTION public.fin_account_extras(p_student_account_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_stu bigint; v_ben boolean; v_adj boolean; r jsonb;
BEGIN
    -- read checks (p_write = false) so that a student's own record is covered by the SELF scope
    SELECT student_id INTO v_stu FROM student_financial_account WHERE student_account_id = p_student_account_id;
    IF v_stu IS NULL OR NOT sims_private.can_student(ARRAY['FEES.FEE_ASSESSMENT.READ']::text[], v_stu, false) THEN
        RAISE EXCEPTION 'Not authorised (FEES.FEE_ASSESSMENT.READ) or unknown account' USING ERRCODE = '42501';
    END IF;
    v_ben := sims_private.can_student(ARRAY['FEES.FEE_BENEFIT.READ']::text[], v_stu, false);
    v_adj := sims_private.can_student(ARRAY['FEES.FEE_REFUND.READ']::text[], v_stu, false);
    r := jsonb_build_object(
      'benefits', CASE WHEN NOT v_ben THEN '[]'::jsonb ELSE (
        SELECT COALESCE(jsonb_agg(x ORDER BY x->>'requested' DESC), '[]'::jsonb) FROM (
          SELECT jsonb_build_object('kind', 'CONCESSION', 'id', c.student_concession_id, 'name', t.concession_name, 'status', c.approval_status, 'percentage', c.approved_percentage, 'amount', c.approved_amount,
                 'applied', COALESCE((SELECT sum(benefit_amount) FROM fee_assessment_benefit WHERE student_concession_id = c.student_concession_id), 0), 'requested', c.application_date, 'remarks', c.remarks) AS x
            FROM student_fee_concession c JOIN concession_type t ON t.concession_type_id = c.concession_type_id WHERE c.student_id = v_stu
          UNION ALL
          SELECT jsonb_build_object('kind', 'SCHOLARSHIP', 'id', s.student_scholarship_id, 'name', m.scheme_name, 'status', s.application_status, 'percentage', NULL, 'amount', COALESCE(s.sanctioned_amount, s.applied_amount),
                 'applied', COALESCE((SELECT sum(benefit_amount) FROM fee_assessment_benefit WHERE student_scholarship_id = s.student_scholarship_id), 0), 'requested', s.sanction_date, 'remarks', s.remarks)
            FROM student_scholarship s JOIN scholarship_scheme m ON m.scholarship_scheme_id = s.scholarship_scheme_id WHERE s.student_id = v_stu
          UNION ALL
          SELECT jsonb_build_object('kind', 'SPONSORSHIP', 'id', p.student_sponsorship_id, 'name', p.sponsoring_authority, 'status', p.approval_status, 'percentage', NULL, 'amount', p.sanctioned_amount,
                 'applied', COALESCE((SELECT sum(benefit_amount) FROM fee_assessment_benefit WHERE student_sponsorship_id = p.student_sponsorship_id), 0), 'requested', p.approved_at, 'remarks', p.sanction_reference)
            FROM student_sponsorship p WHERE p.student_id = v_stu) q) END,
      'adjustments', CASE WHEN NOT v_adj THEN '[]'::jsonb ELSE (
        SELECT COALESCE(jsonb_agg(jsonb_build_object('id', a.fee_adjustment_id, 'number', a.adjustment_number, 'type', a.adjustment_type, 'amount', a.adjustment_amount, 'status', a.approval_status,
               'reason', a.reason, 'item_id', a.assessment_item_id, 'date', a.adjustment_date) ORDER BY a.fee_adjustment_id DESC), '[]'::jsonb) FROM fee_adjustment a WHERE a.student_account_id = p_student_account_id) END,
      'instalments', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', s.student_installment_id, 'assessment_id', s.fee_assessment_id, 'number', s.installment_number, 'due', s.due_date, 'amount', s.installment_amount,
               'paid', s.amount_paid, 'status', s.installment_status) ORDER BY s.fee_assessment_id, s.installment_number), '[]'::jsonb)
               FROM student_installment_schedule s JOIN student_fee_assessment a ON a.fee_assessment_id = s.fee_assessment_id WHERE a.student_account_id = p_student_account_id AND s.installment_status <> 'CANCELLED'),
      'penalties', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', p.fee_penalty_id, 'date', p.penalty_date, 'reason', p.penalty_reason, 'amount', p.penalty_amount, 'waived', p.waived_amount,
               'net', p.net_penalty_amount, 'status', p.penalty_status) ORDER BY p.fee_penalty_id DESC), '[]'::jsonb) FROM student_fee_penalty p WHERE p.student_account_id = p_student_account_id),
      'can', jsonb_build_object(
        'benefit_create', sims_private.can_student(ARRAY['FEES.FEE_BENEFIT.CREATE']::text[], v_stu, true),
        'benefit_approve', sims_private.can_student(ARRAY['FEES.FEE_BENEFIT.APPROVE']::text[], v_stu, true),
        'benefit_apply', sims_private.can_student(ARRAY['FEES.FEE_BENEFIT.UPDATE']::text[], v_stu, true),
        'adjust_create', sims_private.can_student(ARRAY['FEES.FEE_REFUND.CREATE']::text[], v_stu, true),
        'adjust_approve', sims_private.can_student(ARRAY['FEES.FEE_REFUND.APPROVE']::text[], v_stu, true),
        'assess_create', sims_private.can_student(ARRAY['FEES.FEE_ASSESSMENT.CREATE']::text[], v_stu, true),
        'assess_update', sims_private.can_student(ARRAY['FEES.FEE_ASSESSMENT.UPDATE']::text[], v_stu, true)));
    RETURN r;
END $function$;

CREATE OR REPLACE FUNCTION public.fin_account_info(p_student_account_id bigint)
 RETURNS TABLE(student_account_id bigint, student_id bigint, account_number text, account_status text, student_number text, display_name text, opening_balance numeric, credit_balance numeric, total_payable numeric, total_paid numeric, total_balance numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_student bigint;
BEGIN
    SELECT a.student_id INTO v_student FROM student_financial_account a WHERE a.student_account_id = p_student_account_id;
    IF v_student IS NULL OR NOT sims_private.can_student(ARRAY['FEES.FEE_ASSESSMENT.READ']::text[], v_student, false) THEN
        RAISE EXCEPTION 'Not authorised (FEES.FEE_ASSESSMENT.READ) or unknown account' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    SELECT a.student_account_id::bigint, a.student_id::bigint, a.account_number::text, a.account_status::text, s.student_number::text, s.display_name::text, a.opening_balance, a.credit_balance,
           COALESCE((SELECT sum(f.net_payable_amount) FROM student_fee_assessment f WHERE f.student_account_id = a.student_account_id AND f.assessment_status NOT IN ('CANCELLED', 'WAIVED')), 0),
           COALESCE((SELECT sum(f.amount_paid) FROM student_fee_assessment f WHERE f.student_account_id = a.student_account_id AND f.assessment_status NOT IN ('CANCELLED', 'WAIVED')), 0),
           COALESCE((SELECT sum(f.balance_amount) FROM student_fee_assessment f WHERE f.student_account_id = a.student_account_id AND f.assessment_status NOT IN ('CANCELLED', 'WAIVED')), 0)
    FROM student_financial_account a JOIN student s ON s.student_id = a.student_id
    WHERE a.student_account_id = p_student_account_id;
END $function$;

CREATE OR REPLACE FUNCTION public.fin_accounts(p_search text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS TABLE(student_account_id bigint, student_id bigint, account_number text, account_status text, student_number text, display_name text, total_payable numeric, total_paid numeric, total_balance numeric, total_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    WITH visible AS (
        SELECT a.student_account_id, a.student_id, a.account_number::text, a.account_status::text, s.student_number::text, s.display_name::text,
               COALESCE((SELECT sum(f.net_payable_amount) FROM student_fee_assessment f WHERE f.student_account_id = a.student_account_id AND f.assessment_status NOT IN ('CANCELLED', 'WAIVED')), 0) AS total_payable,
               COALESCE((SELECT sum(f.amount_paid) FROM student_fee_assessment f WHERE f.student_account_id = a.student_account_id AND f.assessment_status NOT IN ('CANCELLED', 'WAIVED')), 0) AS total_paid,
               COALESCE((SELECT sum(f.balance_amount) FROM student_fee_assessment f WHERE f.student_account_id = a.student_account_id AND f.assessment_status NOT IN ('CANCELLED', 'WAIVED')), 0) AS total_balance
        FROM student_financial_account a
        JOIN student s ON s.student_id = a.student_id
        WHERE (p_status IS NULL OR a.account_status = p_status)
          AND (p_search IS NULL OR btrim(p_search) = '' OR position(lower(btrim(p_search)) IN lower(s.student_number || ' ' || s.display_name || ' ' || a.account_number)) > 0)
          AND sims_private.can_student(ARRAY['FEES.FEE_ASSESSMENT.READ']::text[], a.student_id, false)
    )
    SELECT v.*, count(*) OVER () FROM visible v ORDER BY v.display_name, v.student_account_id
    LIMIT LEAST(GREATEST(p_limit, 1), 200) OFFSET GREATEST(p_offset, 0)
$function$;

CREATE OR REPLACE FUNCTION public.fin_holds(p_student_account_id bigint)
 RETURNS TABLE(financial_hold_id bigint, hold_type text, hold_reason text, hold_status text, placed_at timestamp with time zone, released_at timestamp with time zone, release_reason text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_student bigint;
BEGIN
    SELECT student_id INTO v_student FROM student_financial_account WHERE student_account_id = p_student_account_id;
    IF v_student IS NULL OR NOT sims_private.can_student(ARRAY['FEES.FEE_ASSESSMENT.READ']::text[], v_student, false) THEN RAISE EXCEPTION 'Not authorised (FEES.FEE_ASSESSMENT.READ) or unknown account' USING ERRCODE = '42501'; END IF;
    RETURN QUERY SELECT h.financial_hold_id::bigint, h.hold_type::text, h.hold_reason::text, h.hold_status::text, h.placed_at, h.released_at, h.release_reason::text
                 FROM student_financial_hold h WHERE h.student_account_id = p_student_account_id ORDER BY (h.hold_status = 'ACTIVE') DESC, h.placed_at DESC, h.financial_hold_id DESC;
END $function$;

CREATE OR REPLACE FUNCTION public.fin_late_fee_suggest(p_assessment_id bigint, p_rule_id bigint, p_as_of date DEFAULT CURRENT_DATE)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a record; r record; v_days integer; v_amt numeric := 0;
BEGIN
    PERFORM sims_private.fin_authorize_student(sims_private.fin_assessment_student(p_assessment_id), 'FEE_ASSESSMENT', 'READ');
    SELECT due_date, balance_amount, assessment_status INTO a FROM student_fee_assessment WHERE fee_assessment_id = p_assessment_id;
    SELECT * INTO r FROM late_fee_rule WHERE late_fee_rule_id = p_rule_id AND is_active AND effective_from <= p_as_of AND (effective_to IS NULL OR effective_to >= p_as_of);
    IF NOT FOUND THEN RAISE EXCEPTION 'Unknown, inactive or not yet effective late-fee rule' USING ERRCODE = '22023'; END IF;
    IF a.due_date IS NULL OR a.balance_amount <= 0 OR a.assessment_status IN ('CANCELLED', 'WAIVED', 'PAID', 'DRAFT') THEN RETURN 0; END IF;
    v_days := (p_as_of - a.due_date) - r.grace_period_days;
    IF v_days <= 0 THEN RETURN 0; END IF;
    v_amt := CASE r.calculation_method
        WHEN 'FIXED' THEN COALESCE(r.fixed_amount, 0)
        WHEN 'PER_DAY' THEN COALESCE(r.daily_amount, 0) * v_days
        WHEN 'PERCENTAGE' THEN round(a.balance_amount * COALESCE(r.percentage_rate, 0) / 100, 2)
        ELSE COALESCE((SELECT late_fee_amount FROM late_fee_slab WHERE late_fee_rule_id = p_rule_id AND from_day <= v_days AND (to_day IS NULL OR to_day >= v_days) ORDER BY from_day DESC LIMIT 1), 0) END;
    IF r.maximum_amount IS NOT NULL THEN v_amt := least(v_amt, r.maximum_amount); END IF;
    RETURN round(v_amt, 2);
END $function$;

CREATE OR REPLACE FUNCTION public.fin_payment_receipts(p_student_account_id bigint)
 RETURNS TABLE(payment_transaction_id bigint, transaction_number text, transaction_date timestamp with time zone, amount numeric, payment_status text, mode_name text, fee_receipt_id bigint, receipt_number text, receipt_status text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_student bigint;
BEGIN
    SELECT student_id INTO v_student FROM student_financial_account WHERE student_account_id = p_student_account_id;
    IF v_student IS NULL OR NOT sims_private.can_student(ARRAY['FEES.FEE_PAYMENT.READ']::text[], v_student, false) THEN RAISE EXCEPTION 'Not authorised (FEES.FEE_PAYMENT.READ) or unknown account' USING ERRCODE = '42501'; END IF;
    RETURN QUERY
    SELECT t.payment_transaction_id::bigint, t.transaction_number::text, t.transaction_date, t.amount, t.payment_status::text, m.mode_name::text, f.fee_receipt_id::bigint, f.receipt_number::text, f.receipt_status::text
    FROM payment_transaction t JOIN payment_mode m ON m.payment_mode_id = t.payment_mode_id
    LEFT JOIN LATERAL (SELECT x.* FROM fee_receipt x WHERE x.payment_transaction_id = t.payment_transaction_id ORDER BY (x.receipt_status = 'ISSUED') DESC, x.fee_receipt_id DESC LIMIT 1) f ON true
    WHERE t.student_account_id = p_student_account_id ORDER BY t.transaction_date DESC, t.payment_transaction_id DESC;
END $function$;

CREATE OR REPLACE FUNCTION public.fin_receipt_get(p_receipt_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE r record; v_student bigint;
BEGIN
    SELECT f.*, t.transaction_number, t.transaction_date, t.amount, t.payer_name, t.bank_reference_number, t.student_account_id, m.mode_name, a.account_number, a.student_id, s.student_number, s.display_name INTO r
    FROM fee_receipt f JOIN payment_transaction t ON t.payment_transaction_id = f.payment_transaction_id JOIN payment_mode m ON m.payment_mode_id = t.payment_mode_id
    JOIN student_financial_account a ON a.student_account_id = t.student_account_id JOIN student s ON s.student_id = a.student_id WHERE f.fee_receipt_id = p_receipt_id;
    v_student := r.student_id;
    IF r.fee_receipt_id IS NULL OR NOT sims_private.can_student(ARRAY['FEES.FEE_PAYMENT.READ']::text[], v_student, false) THEN RAISE EXCEPTION 'Not authorised (FEES.FEE_PAYMENT.READ) or unknown receipt' USING ERRCODE = '42501'; END IF;
    RETURN jsonb_build_object('fee_receipt_id', r.fee_receipt_id, 'receipt_number', r.receipt_number, 'receipt_date', r.receipt_date, 'receipt_amount', r.receipt_amount, 'receipt_status', r.receipt_status,
        'cancellation_reason', r.cancellation_reason, 'original_receipt_id', r.original_receipt_id, 'transaction_number', r.transaction_number, 'transaction_date', r.transaction_date, 'payment_mode', r.mode_name,
        'bank_reference', r.bank_reference_number, 'payer_name', r.payer_name, 'account_number', r.account_number, 'student_account_id', r.student_account_id, 'student_number', r.student_number, 'student_name', r.display_name,
        'allocations', COALESCE((SELECT jsonb_agg(jsonb_build_object('fee', COALESCE(i.description, ft.fee_name), 'amount', pa.allocated_amount) ORDER BY pa.payment_allocation_id)
                                 FROM payment_allocation pa JOIN student_fee_assessment_item i ON i.assessment_item_id = pa.assessment_item_id JOIN fee_type ft ON ft.fee_type_id = i.fee_type_id
                                 WHERE pa.payment_transaction_id = r.payment_transaction_id), '[]'::jsonb),
        'can_cancel', sims_private.can_student(ARRAY['FEES.FEE_PAYMENT.UPDATE']::text[], v_student, true) AND r.receipt_status = 'ISSUED');
END $function$;

CREATE OR REPLACE FUNCTION public.fin_structure_get(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE s record; v_editable boolean;
BEGIN
    SELECT f.*, i.institution_name, p.programme_name, y.year_code INTO s FROM fee_structure f JOIN institution i ON i.institution_id = f.institution_id LEFT JOIN programme p ON p.programme_id = f.programme_id
      JOIN academic_year y ON y.academic_year_id = f.academic_year_id WHERE f.fee_structure_id = p_id;
    IF s.fee_structure_id IS NULL OR NOT COALESCE(sims_private.fs_can(s.institution_id, s.programme_id, 'READ'), false) THEN RAISE EXCEPTION 'Not authorised (FEES.FEE_STRUCTURE.READ) or unknown fee structure' USING ERRCODE = '42501'; END IF;
    v_editable := s.approval_status IN ('DRAFT', 'REJECTED') AND COALESCE(sims_private.fs_can(s.institution_id, s.programme_id, 'UPDATE'), false);
    RETURN jsonb_build_object('fee_structure_id', s.fee_structure_id, 'structure_code', s.structure_code, 'structure_name', s.structure_name, 'institution_id', s.institution_id, 'institution_name', s.institution_name,
        'campus_id', s.campus_id, 'programme_id', s.programme_id, 'programme_name', s.programme_name, 'academic_year_id', s.academic_year_id, 'year_code', s.year_code, 'admission_category_id', s.admission_category_id,
        'version_number', s.version_number, 'effective_from', s.effective_from, 'effective_to', s.effective_to, 'approval_status', s.approval_status, 'remarks', s.remarks, 'approved_at', s.approved_at,
        'can_edit', v_editable, 'can_submit', v_editable,
        'can_decide', s.approval_status = 'SUBMITTED' AND COALESCE(sims_private.fs_can(s.institution_id, s.programme_id, 'APPROVE'), false)
                      AND NOT EXISTS (SELECT 1 FROM fee_activity_audit a WHERE a.entity_name = 'fee_structure' AND a.entity_id = p_id AND a.action_code = 'STRUCTURE_SUBMITTED' AND a.user_id = sims_private.current_user_id()),
        'can_version', s.approval_status IN ('APPROVED', 'SUPERSEDED') AND COALESCE(sims_private.fs_can(s.institution_id, s.programme_id, 'CREATE'), false),
        'can_delete', s.approval_status IN ('DRAFT', 'REJECTED') AND COALESCE(sims_private.fs_can(s.institution_id, s.programme_id, 'DELETE'), false),
        'items', COALESCE((SELECT jsonb_agg(jsonb_build_object('id', x.fee_structure_item_id, 'fee_type_id', x.fee_type_id, 'fee_type', t.fee_name, 'semester_id', x.semester_id, 'academic_term_id', x.academic_term_id, 'amount', x.amount,
                  'due_date', x.due_date, 'due_days', x.due_days_from_registration, 'installment_allowed', x.installment_allowed, 'waiver_allowed', x.waiver_allowed, 'late_fee_rule_id', x.late_fee_rule_id,
                  'display_order', x.display_order, 'remarks', x.remarks) ORDER BY x.display_order, x.fee_structure_item_id)
                  FROM fee_structure_item x JOIN fee_type t ON t.fee_type_id = x.fee_type_id WHERE x.fee_structure_id = p_id), '[]'::jsonb));
END $function$;

CREATE OR REPLACE FUNCTION public.fin_structure_list(p_search text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS TABLE(fee_structure_id bigint, structure_code text, structure_name text, institution_name text, programme_name text, year_code text, version_number integer, approval_status text, effective_from date, effective_to date, item_count bigint, total_amount numeric, total_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    WITH v AS (
        SELECT f.fee_structure_id, f.structure_code, f.structure_name, i.institution_name, p.programme_name, y.year_code, f.version_number, f.approval_status, f.effective_from, f.effective_to,
               (SELECT count(*) FROM fee_structure_item x WHERE x.fee_structure_id = f.fee_structure_id) AS item_count, (SELECT COALESCE(sum(x.amount), 0) FROM fee_structure_item x WHERE x.fee_structure_id = f.fee_structure_id) AS total_amount
        FROM fee_structure f JOIN institution i ON i.institution_id = f.institution_id LEFT JOIN programme p ON p.programme_id = f.programme_id JOIN academic_year y ON y.academic_year_id = f.academic_year_id
        WHERE sims_private.fs_can(f.institution_id, f.programme_id, 'READ') AND (p_status IS NULL OR f.approval_status = p_status)
          AND (p_search IS NULL OR p_search = '' OR f.structure_code ILIKE '%' || replace(replace(replace(p_search, '\', '\\'), '%', '\%'), '_', '\_') || '%' OR f.structure_name ILIKE '%' || replace(replace(replace(p_search, '\', '\\'), '%', '\%'), '_', '\_') || '%'))
    SELECT v.fee_structure_id::bigint, v.structure_code::text, v.structure_name::text, v.institution_name::text, v.programme_name::text, v.year_code::text, v.version_number::integer, v.approval_status::text, v.effective_from, v.effective_to,
           v.item_count, v.total_amount::numeric, count(*) OVER ()
    FROM v ORDER BY v.effective_from DESC, v.fee_structure_id DESC LIMIT LEAST(GREATEST(p_limit, 1), 100) OFFSET GREATEST(p_offset, 0)
$function$;

CREATE OR REPLACE FUNCTION public.global_search(p_q text, p_limit integer DEFAULT 8)
 RETURNS TABLE(kind text, id bigint, title text, subtitle text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
    WITH q AS (SELECT '%' || replace(replace(replace(lower(btrim(COALESCE(p_q, ''))), '\', '\\'), '%', '\%'), '_', '\_') || '%' AS pat, length(btrim(COALESCE(p_q, ''))) AS n, LEAST(GREATEST(p_limit, 1), 25) AS lim)
    SELECT * FROM (
        (SELECT 'student'::text, s.student_id::bigint, s.display_name::text, s.student_number::text FROM student s, q WHERE q.n >= 2 AND (lower(s.display_name) LIKE q.pat OR lower(s.student_number) LIKE q.pat) ORDER BY s.display_name LIMIT (SELECT lim FROM q))
        UNION ALL
        (SELECT 'employee'::text, e.employee_id::bigint, e.display_name::text, e.employee_number::text FROM employee e, q WHERE q.n >= 2 AND (lower(e.display_name) LIKE q.pat OR lower(e.employee_number) LIKE q.pat) ORDER BY e.display_name LIMIT (SELECT lim FROM q))
        UNION ALL
        (SELECT 'course'::text, c.course_id::bigint, c.course_title::text, c.course_code::text FROM course_catalog c, q WHERE q.n >= 2 AND (lower(c.course_title) LIKE q.pat OR lower(c.course_code) LIKE q.pat) ORDER BY c.course_title LIMIT (SELECT lim FROM q))
        UNION ALL
        (SELECT 'programme'::text, p.programme_id::bigint, p.programme_name::text, p.programme_code::text FROM programme p, q WHERE q.n >= 2 AND (lower(p.programme_name) LIKE q.pat OR lower(p.programme_code) LIKE q.pat) ORDER BY p.programme_name LIMIT (SELECT lim FROM q))
        UNION ALL
        (SELECT 'department'::text, d.department_id::bigint, d.department_name::text, d.department_code::text FROM department d, q WHERE q.n >= 2 AND (lower(d.department_name) LIKE q.pat OR lower(d.department_code) LIKE q.pat) ORDER BY d.department_name LIMIT (SELECT lim FROM q))
    ) r
$function$;

CREATE OR REPLACE FUNCTION public.grievance_detail(p_grievance_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE g record; v_owner boolean; v_staff boolean;
BEGIN
    SELECT gr.*, s.student_number AS snum, s.display_name AS sname, c.category_name AS cname, d.department_name AS dname INTO g
    FROM grievance gr JOIN student s ON s.student_id = gr.student_id JOIN grievance_category c ON c.grievance_category_id = gr.grievance_category_id
    LEFT JOIN department d ON d.department_id = gr.department_id WHERE gr.grievance_id = p_grievance_id;
    v_owner := COALESCE(g.student_id = sims_private.current_student_id(), false);
    v_staff := g.student_id IS NOT NULL AND sims_private.can_student(ARRAY['GRIEVANCE.ALL.READ']::text[], g.student_id, true);
    IF g.grievance_id IS NULL OR NOT (v_owner OR v_staff) THEN RAISE EXCEPTION 'Not authorised (GRIEVANCE.ALL.READ) or unknown grievance' USING ERRCODE = '42501'; END IF;
    RETURN jsonb_build_object(
        'grievance_id', g.grievance_id, 'grievance_number', g.grievance_number, 'student_number', g.snum, 'student_name', g.sname, 'category_name', g.cname, 'department_name', g.dname,
        'subject', g.subject, 'description', g.description, 'priority', g.priority, 'status', g.status, 'submitted_at', g.submitted_at, 'resolved_at', g.resolved_at, 'resolution', g.resolution,
        'is_owner', v_owner, 'can_act', sims_private.can_student(ARRAY['GRIEVANCE.ALL.UPDATE']::text[], g.student_id, true),
        'actions', COALESCE((SELECT jsonb_agg(jsonb_build_object('action_at', a.action_at, 'action_type', a.action_type, 'action_notes', a.action_notes, 'new_status', a.new_status) ORDER BY a.action_at, a.grievance_action_id)
                              FROM grievance_action a WHERE a.grievance_id = g.grievance_id AND (v_staff OR a.action_type <> 'INTERNAL_NOTE')), '[]'::jsonb));
END $function$;

CREATE OR REPLACE FUNCTION public.grievance_list(p_search text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_priority text DEFAULT NULL::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS TABLE(grievance_id bigint, grievance_number text, student_number text, student_name text, category_name text, subject text, priority text, status text, submitted_at timestamp with time zone, total_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    WITH visible AS (
        SELECT g.grievance_id, g.grievance_number::text, s.student_number::text, s.display_name::text AS student_name, c.category_name::text, g.subject::text, g.priority::text, g.status::text, g.submitted_at
        FROM grievance g JOIN student s ON s.student_id = g.student_id JOIN grievance_category c ON c.grievance_category_id = g.grievance_category_id
        WHERE (p_status IS NULL OR g.status = p_status) AND (p_priority IS NULL OR g.priority = p_priority)
          AND (p_search IS NULL OR btrim(p_search) = '' OR position(lower(btrim(p_search)) IN lower(g.grievance_number || ' ' || g.subject || ' ' || s.student_number || ' ' || s.display_name)) > 0)
          AND sims_private.can_student(ARRAY['GRIEVANCE.ALL.READ']::text[], g.student_id, true)
    )
    SELECT v.grievance_id::bigint, v.grievance_number, v.student_number, v.student_name, v.category_name, v.subject, v.priority, v.status, v.submitted_at, count(*) OVER ()
    FROM visible v ORDER BY CASE v.priority WHEN 'URGENT' THEN 0 WHEN 'HIGH' THEN 1 WHEN 'NORMAL' THEN 2 ELSE 3 END, v.submitted_at, v.grievance_id LIMIT LEAST(GREATEST(p_limit, 1), 200) OFFSET GREATEST(p_offset, 0)
$function$;

CREATE OR REPLACE FUNCTION public.grievance_my()
 RETURNS TABLE(grievance_id bigint, grievance_number text, category_name text, subject text, priority text, status text, submitted_at timestamp with time zone, resolved_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT g.grievance_id::bigint, g.grievance_number::text, c.category_name::text, g.subject::text, g.priority::text, g.status::text, g.submitted_at, g.resolved_at
    FROM grievance g JOIN grievance_category c ON c.grievance_category_id = g.grievance_category_id
    WHERE g.student_id = sims_private.current_student_id() ORDER BY g.submitted_at DESC, g.grievance_id DESC
$function$;

CREATE OR REPLACE FUNCTION public.iam_can_provision()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT sims_private.can_global(ARRAY['IAM.ALL.CREATE']::text[])
$function$;

CREATE OR REPLACE FUNCTION public.iam_mfa_policy_gaps()
 RETURNS TABLE(user_id bigint, username text, role_code text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF NOT sims_private.can_global(ARRAY['IAM.ALL.READ']::text[]) THEN RAISE EXCEPTION 'Not authorised (IAM.ALL.READ)' USING ERRCODE = '42501'; END IF;
    RETURN QUERY SELECT DISTINCT u.user_id::bigint, u.username::text, r.role_code::text FROM public.v_active_user_role a JOIN public.user_account u ON u.user_id = a.user_id
                 JOIN role r ON r.role_code = a.role_code JOIN sims_private.mfa_required_role m ON m.role_id = r.role_id
                 WHERE u.account_status = 'ACTIVE' AND NOT u.multi_factor_enabled ORDER BY 2, 3;
END $function$;

CREATE OR REPLACE FUNCTION public.iam_mfa_policy_list()
 RETURNS TABLE(role_code text, role_name text, required boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF NOT sims_private.can_global(ARRAY['IAM.ALL.READ']::text[]) THEN RAISE EXCEPTION 'Not authorised (IAM.ALL.READ)' USING ERRCODE = '42501'; END IF;
    RETURN QUERY SELECT r.role_code::text, r.role_name::text, EXISTS (SELECT 1 FROM sims_private.mfa_required_role m WHERE m.role_id = r.role_id) FROM role r WHERE r.is_active ORDER BY r.role_code;
END $function$;

CREATE OR REPLACE FUNCTION public.iam_override_list(p_user_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF NOT sims_private.can_global(ARRAY['IAM.ALL.READ']::text[]) THEN RAISE EXCEPTION 'Not authorised (IAM.ALL.READ)' USING ERRCODE = '42501'; END IF;
    RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id', o.user_permission_override_id, 'permission', p.permission_code, 'effect', o.permission_effect, 'scope_type', o.scope_type,
              'scope', CASE o.scope_type WHEN 'INSTITUTION' THEN (SELECT institution_name FROM institution WHERE institution_id = o.scope_entity_id)
                                         WHEN 'CAMPUS' THEN (SELECT campus_name FROM campus WHERE campus_id = o.scope_entity_id)
                                         WHEN 'DEPARTMENT' THEN (SELECT department_name FROM department WHERE department_id = o.scope_entity_id)
                                         WHEN 'PROGRAMME' THEN (SELECT programme_name FROM programme WHERE programme_id = o.scope_entity_id) END,
              'valid_from', o.valid_from, 'valid_to', o.valid_to, 'active', o.valid_to IS NULL OR o.valid_to > now(), 'justification', o.justification,
              'granted_by', (SELECT username FROM user_account WHERE user_id = o.granted_by_user_id)) ORDER BY o.user_permission_override_id DESC)
              FROM user_permission_override o JOIN permission p ON p.permission_id = o.permission_id WHERE o.user_id = p_user_id), '[]'::jsonb);
END $function$;

CREATE OR REPLACE FUNCTION public.iam_permission_options(p_search text DEFAULT NULL::text)
 RETURNS TABLE(permission_code text, permission_name text, is_sensitive boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF NOT sims_private.can_global(ARRAY['IAM.ALL.UPDATE']::text[]) THEN RAISE EXCEPTION 'Not authorised (IAM.ALL.UPDATE)' USING ERRCODE = '42501'; END IF;
    IF length(COALESCE(p_search, '')) > 60 THEN RAISE EXCEPTION 'The search text is too long' USING ERRCODE = '22023'; END IF;
    RETURN QUERY SELECT p.permission_code::text, p.permission_name::text, p.is_sensitive FROM permission p
                  WHERE p_search IS NULL OR p_search = '' OR p.permission_code ILIKE '%' || replace(replace(replace(p_search, '\', '\\'), '%', '\%'), '_', '\_') || '%'
                  ORDER BY p.permission_code LIMIT 40;
END $function$;

CREATE OR REPLACE FUNCTION public.iam_provision_user(p_auth_user uuid, p_email text, p_student_number text, p_employee_number text, p_actor_user_id bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_email text := lower(btrim(COALESCE(p_email, ''))); v_user bigint; v_student bigint; v_employee bigint;
BEGIN
    IF p_auth_user IS NULL THEN RAISE EXCEPTION 'The Auth user id is required' USING ERRCODE = '22023'; END IF;
    IF v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' OR length(v_email) > 254 THEN RAISE EXCEPTION 'A valid email address is required' USING ERRCODE = '22023'; END IF;
    IF NULLIF(btrim(p_student_number), '') IS NOT NULL AND NULLIF(btrim(p_employee_number), '') IS NOT NULL THEN
        RAISE EXCEPTION 'Link the account to a student or an employee, not both' USING ERRCODE = '22023';
    END IF;

    -- idempotent replay: the Auth user is already provisioned
    SELECT user_id INTO v_user FROM sims_private.auth_identity_map WHERE auth_user_id = p_auth_user;
    IF v_user IS NOT NULL THEN RETURN v_user; END IF;

    IF EXISTS (SELECT 1 FROM user_account WHERE lower(username) = v_email OR lower(email) = v_email) THEN
        RAISE EXCEPTION 'An account with that email already exists' USING ERRCODE = '23505';
    END IF;
    IF NULLIF(btrim(p_student_number), '') IS NOT NULL THEN
        SELECT student_id INTO v_student FROM student WHERE student_number = btrim(p_student_number);
        IF v_student IS NULL THEN RAISE EXCEPTION 'Unknown student number' USING ERRCODE = '22023'; END IF;
        IF EXISTS (SELECT 1 FROM student_user_account WHERE student_id = v_student) THEN RAISE EXCEPTION 'That student already has an account' USING ERRCODE = '23505'; END IF;
    END IF;
    IF NULLIF(btrim(p_employee_number), '') IS NOT NULL THEN
        SELECT employee_id INTO v_employee FROM employee WHERE employee_number = btrim(p_employee_number);
        IF v_employee IS NULL THEN RAISE EXCEPTION 'Unknown employee number' USING ERRCODE = '22023'; END IF;
        IF EXISTS (SELECT 1 FROM employee_user_account WHERE employee_id = v_employee) THEN RAISE EXCEPTION 'That employee already has an account' USING ERRCODE = '23505'; END IF;
    END IF;

    INSERT INTO user_account (username, password_hash, email, account_status, must_change_password)
    VALUES (v_email, '!supabase-auth', v_email, 'ACTIVE', true) RETURNING user_id INTO v_user;
    IF v_student IS NOT NULL THEN INSERT INTO student_user_account (student_id, user_id) VALUES (v_student, v_user); END IF;
    IF v_employee IS NOT NULL THEN INSERT INTO employee_user_account (employee_id, user_id) VALUES (v_employee, v_user); END IF;
    PERFORM sims_private.link_auth_user(p_auth_user, v_user, COALESCE('provisioned by user ' || p_actor_user_id, 'provisioned'));
    INSERT INTO activity_audit (user_id, module_code, action_code, entity_name, entity_id, after_values)
    VALUES (p_actor_user_id, 'IAM', 'PROVISION', 'user_account', v_user::text, jsonb_build_object('email', v_email, 'student_id', v_student, 'employee_id', v_employee));
    RETURN v_user;
END $function$;

CREATE OR REPLACE FUNCTION public.iam_roles()
 RETURNS TABLE(role_id integer, role_code text, role_name text, role_level text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT r.role_id::integer, r.role_code::text, r.role_name::text, r.role_level::text FROM role r
    WHERE r.is_active AND r.is_assignable AND sims_private.can_global(ARRAY['IAM.ALL.READ']::text[]) ORDER BY r.role_name
$function$;

CREATE OR REPLACE FUNCTION public.iam_user_detail(p_user_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE u record;
BEGIN
    IF NOT sims_private.can_global(ARRAY['IAM.ALL.READ']::text[]) THEN RAISE EXCEPTION 'Not authorised (IAM.ALL.READ)' USING ERRCODE = '42501'; END IF;
    SELECT user_id, username, email, account_status, last_login_at, locked_until INTO u FROM user_account WHERE user_id = p_user_id;
    IF u.user_id IS NULL THEN RAISE EXCEPTION 'Unknown user' USING ERRCODE = '22023'; END IF;
    RETURN jsonb_build_object('user_id', u.user_id, 'username', u.username, 'email', u.email, 'account_status', u.account_status, 'last_login_at', u.last_login_at, 'locked_until', u.locked_until,
        'is_self', u.user_id = sims_private.current_user_id(), 'can_update', sims_private.can_global(ARRAY['IAM.ALL.UPDATE']::text[]),
        'assignments', COALESCE((SELECT jsonb_agg(jsonb_build_object('assignment_id', a.user_role_assignment_id, 'role_name', r.role_name, 'role_code', r.role_code, 'scope_type', a.scope_type,
                'scope', COALESCE(i.institution_name, c.campus_name, d.department_name, p.programme_name, ''), 'status', a.assignment_status, 'valid_from', a.valid_from, 'valid_to', a.valid_to, 'reason', a.assignment_reason)
                ORDER BY a.assignment_status, a.user_role_assignment_id)
            FROM user_role_assignment a JOIN role r ON r.role_id = a.role_id LEFT JOIN institution i ON i.institution_id = a.institution_id LEFT JOIN campus c ON c.campus_id = a.campus_id
            LEFT JOIN department d ON d.department_id = a.department_id LEFT JOIN programme p ON p.programme_id = a.programme_id WHERE a.user_id = u.user_id), '[]'::jsonb));
END $function$;

CREATE OR REPLACE FUNCTION public.iam_user_list(p_search text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS TABLE(user_id bigint, username text, email text, account_status text, last_login_at timestamp with time zone, roles text, linked_to text, total_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    WITH v AS (
        SELECT u.user_id, u.username::text, u.email::text, u.account_status::text, u.last_login_at,
               COALESCE((SELECT string_agg(DISTINCT r.role_name, ', ' ORDER BY r.role_name) FROM user_role_assignment a JOIN role r ON r.role_id = a.role_id
                         WHERE a.user_id = u.user_id AND a.assignment_status = 'ACTIVE' AND (a.valid_to IS NULL OR a.valid_to > now())), '')::text AS roles,
               COALESCE((SELECT 'Student ' || s.student_number FROM student_user_account su JOIN student s ON s.student_id = su.student_id WHERE su.user_id = u.user_id),
                        (SELECT 'Employee ' || e.employee_number FROM employee_user_account eu JOIN employee e ON e.employee_id = eu.employee_id WHERE eu.user_id = u.user_id), '')::text AS linked_to
        FROM user_account u
        WHERE sims_private.can_global(ARRAY['IAM.ALL.READ']::text[]) AND (p_status IS NULL OR u.account_status = p_status)
          AND (p_search IS NULL OR btrim(p_search) = '' OR position(lower(btrim(p_search)) IN lower(u.username || ' ' || COALESCE(u.email, ''))) > 0)
    )
    SELECT v.user_id::bigint, v.username, v.email, v.account_status, v.last_login_at, v.roles, v.linked_to, count(*) OVER ()
    FROM v ORDER BY v.username LIMIT LEAST(GREATEST(p_limit, 1), 200) OFFSET GREATEST(p_offset, 0)
$function$;

CREATE OR REPLACE FUNCTION public.login_audit_list(p_search text DEFAULT NULL::text, p_success boolean DEFAULT NULL::boolean, p_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_to timestamp with time zone DEFAULT NULL::timestamp with time zone, p_limit integer DEFAULT 25, p_offset integer DEFAULT 0)
 RETURNS TABLE(login_audit_id bigint, login_at timestamp with time zone, logout_at timestamp with time zone, username_attempted text, username text, was_successful boolean, failure_reason text, ip_address text, total_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT l.login_audit_id::bigint, l.login_at, l.logout_at, l.username_attempted::text, u.username::text, l.was_successful, l.failure_reason::text, l.ip_address::text, count(*) OVER ()
    FROM login_audit l LEFT JOIN user_account u ON u.user_id = l.user_id
    WHERE sims_private.can_global(ARRAY['AUDIT.ALL.READ']::text[]) AND (p_success IS NULL OR l.was_successful = p_success)
      AND (p_from IS NULL OR l.login_at >= p_from) AND (p_to IS NULL OR l.login_at < p_to)
      AND (p_search IS NULL OR btrim(p_search) = '' OR position(lower(btrim(p_search)) IN lower(l.username_attempted || ' ' || COALESCE(l.ip_address, ''))) > 0)
    ORDER BY l.login_at DESC, l.login_audit_id DESC LIMIT LEAST(GREATEST(p_limit, 1), 200) OFFSET GREATEST(p_offset, 0)
$function$;

CREATE OR REPLACE FUNCTION public.mentoring_assignment_info(p_assignment_id bigint)
 RETURNS TABLE(mentor_assignment_id bigint, student_id bigint, student_number text, student_name text, employee_id bigint, mentor_name text, start_date date, end_date date, assignment_status text, is_mine boolean, can_assign boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF NOT sims_private.mentoring_can_see(p_assignment_id) THEN RAISE EXCEPTION 'Not authorised (MENTORING.ALL.READ) or unknown assignment' USING ERRCODE = '42501'; END IF;
    RETURN QUERY
    SELECT a.mentor_assignment_id::bigint, a.student_id::bigint, s.student_number::text, s.display_name::text, a.employee_id::bigint, e.display_name::text, a.start_date, a.end_date, a.assignment_status::text,
           COALESCE(a.employee_id = sims_private.current_employee_id(), false), sims_private.can_student(ARRAY['MENTORING.ALL.ASSIGN']::text[], a.student_id, true)
    FROM mentor_assignment a JOIN student s ON s.student_id = a.student_id JOIN employee e ON e.employee_id = a.employee_id WHERE a.mentor_assignment_id = p_assignment_id;
END $function$;

CREATE OR REPLACE FUNCTION public.mentoring_assignments(p_search text DEFAULT NULL::text, p_status text DEFAULT NULL::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS TABLE(mentor_assignment_id bigint, student_id bigint, student_number text, student_name text, employee_id bigint, mentor_name text, start_date date, end_date date, assignment_status text, session_count bigint, is_mine boolean, total_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    WITH me AS (SELECT sims_private.current_employee_id() AS emp),
    visible AS (
        SELECT a.mentor_assignment_id, a.student_id, s.student_number::text, s.display_name::text AS student_name, a.employee_id, e.display_name::text AS mentor_name, a.start_date, a.end_date,
               a.assignment_status::text,
               (SELECT count(*) FROM counselling_session c WHERE c.mentor_assignment_id = a.mentor_assignment_id) AS session_count,
               COALESCE(a.employee_id = (SELECT emp FROM me), false) AS is_mine
        FROM mentor_assignment a JOIN student s ON s.student_id = a.student_id JOIN employee e ON e.employee_id = a.employee_id
        WHERE (p_status IS NULL OR a.assignment_status = p_status)
          AND (p_search IS NULL OR btrim(p_search) = '' OR position(lower(btrim(p_search)) IN lower(s.student_number || ' ' || s.display_name || ' ' || e.display_name)) > 0)
          AND (a.employee_id = (SELECT emp FROM me) OR sims_private.can_student(ARRAY['MENTORING.ALL.READ']::text[], a.student_id, false))
    )
    SELECT v.*, count(*) OVER () FROM visible v ORDER BY v.is_mine DESC, v.mentor_assignment_id DESC LIMIT LEAST(GREATEST(p_limit, 1), 200) OFFSET GREATEST(p_offset, 0)
$function$;

CREATE OR REPLACE FUNCTION public.mentoring_sessions(p_assignment_id bigint)
 RETURNS TABLE(counselling_session_id bigint, session_date timestamp with time zone, session_status text, confidentiality_level text, follow_up_date date, observations text, action_plan text, redacted boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_mentor boolean; v_student bigint;
BEGIN
    IF NOT sims_private.mentoring_can_see(p_assignment_id) THEN RAISE EXCEPTION 'Not authorised (MENTORING.ALL.READ) or unknown assignment' USING ERRCODE = '42501'; END IF;
    v_mentor := sims_private.is_mentor_of(p_assignment_id);
    SELECT student_id INTO v_student FROM mentor_assignment WHERE mentor_assignment_id = p_assignment_id;
    RETURN QUERY
    WITH s AS (
        SELECT c.*, (v_mentor OR (c.confidentiality_level = 'NORMAL' AND sims_private.can_student(ARRAY['MENTORING.ALL.READ']::text[], v_student, false))
                     OR (c.confidentiality_level = 'RESTRICTED' AND sims_private.can_global(ARRAY['MENTORING.ALL.READ']::text[]))) AS full_access
        FROM counselling_session c WHERE c.mentor_assignment_id = p_assignment_id
    )
    SELECT s.counselling_session_id::bigint, s.session_date, s.session_status::text, s.confidentiality_level::text, s.follow_up_date,
           CASE WHEN s.full_access THEN s.observations END, CASE WHEN s.full_access THEN s.action_plan END, NOT s.full_access
    FROM s ORDER BY s.session_date DESC, s.counselling_session_id DESC;
END $function$;

CREATE OR REPLACE FUNCTION public.mfa_recovery_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid bigint := sims_private.current_user_id();
BEGIN
    IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authorised' USING ERRCODE = '42501'; END IF;
    RETURN jsonb_build_object('unused', (SELECT count(*) FROM sims_private.mfa_recovery_code WHERE user_id = v_uid AND used_at IS NULL),
                              'generated_at', (SELECT max(created_at) FROM sims_private.mfa_recovery_code WHERE user_id = v_uid));
END $function$;

CREATE OR REPLACE FUNCTION public.my_context()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    WITH me AS (SELECT sims_private.current_user_id() AS uid)
    SELECT CASE WHEN me.uid IS NULL THEN NULL ELSE jsonb_build_object(
        'user_id', me.uid,
        'username', (SELECT u.username FROM public.user_account u WHERE u.user_id = me.uid),
        'email', (SELECT u.email FROM public.user_account u WHERE u.user_id = me.uid),
        'student_id', sims_private.current_student_id(),
        'employee_id', sims_private.current_employee_id(),
        'mfa_setup_required', sims_private.mfa_setup_required(me.uid),
        'roles', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                    'role_code', r.role_code, 'role_name', r.role_name, 'scope_type', r.scope_type,
                    'institution_id', r.institution_id, 'campus_id', r.campus_id,
                    'department_id', r.department_id, 'programme_id', r.programme_id))
                 FROM public.v_active_user_role r WHERE r.user_id = me.uid), '[]'::jsonb),
        'readable_modules', COALESCE((SELECT jsonb_agg(DISTINCT split_part(v.permission_code, '.', 1))
                 FROM public.v_effective_user_permission v
                 WHERE v.user_id = me.uid AND v.permission_effect = 'ALLOW' AND v.permission_code LIKE '%.READ'), '[]'::jsonb),
        'permissions', COALESCE((SELECT jsonb_agg(DISTINCT v.permission_code)
                 FROM public.v_effective_user_permission v
                 WHERE v.user_id = me.uid AND v.permission_effect = 'ALLOW' AND v.scope_type <> 'SELF'), '[]'::jsonb)
    ) END
    FROM me
$function$;

CREATE OR REPLACE FUNCTION public.my_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_stu bigint := sims_private.current_student_id(); v_emp bigint := sims_private.current_employee_id(); v_out jsonb := '{}'::jsonb;
BEGIN
    IF sims_private.current_user_id() IS NULL THEN RETURN NULL; END IF;
    IF v_stu IS NOT NULL THEN
        v_out := v_out || jsonb_build_object(
            'attendance', COALESCE((
                SELECT jsonb_agg(jsonb_build_object('course', x.course, 'section_id', x.cos, 'conducted', x.conducted, 'present', x.present,
                                                    'percentage', CASE WHEN x.conducted = 0 THEN NULL ELSE round(100.0 * x.present / x.conducted, 1) END) ORDER BY x.course)
                FROM (
                    SELECT (c.course_code || ' — ' || c.course_title) AS course, cos.course_offering_section_id AS cos,
                           count(DISTINCT cs.class_session_id) AS conducted,
                           count(DISTINCT cs.class_session_id) FILTER (WHERE st.counts_as_present) AS present
                    FROM course_offering_section_student r
                    JOIN student_course_registration cr ON cr.course_registration_id = r.course_registration_id
                    JOIN student_term_registration tr ON tr.term_registration_id = cr.term_registration_id
                    JOIN student_programme_enrolment e ON e.enrolment_id = tr.enrolment_id
                    JOIN course_offering_section cos ON cos.course_offering_section_id = r.course_offering_section_id
                    JOIN course_offering co ON co.course_offering_id = cos.course_offering_id
                    JOIN course_catalog c ON c.course_id = co.course_id
                    LEFT JOIN class_session cs ON cs.course_offering_section_id = cos.course_offering_section_id AND cs.session_status = 'CONDUCTED'
                    LEFT JOIN student_attendance a ON a.class_session_id = cs.class_session_id AND a.course_offering_section_student_id = r.course_offering_section_student_id
                    LEFT JOIN attendance_status st ON st.attendance_status_id = a.attendance_status_id
                    WHERE e.student_id = v_stu AND r.roster_status = 'ACTIVE'
                    GROUP BY c.course_code, c.course_title, cos.course_offering_section_id
                ) x), '[]'::jsonb),
            'today', COALESCE((
                SELECT jsonb_agg(jsonb_build_object('course', (c.course_code || ' — ' || c.course_title), 'start', cs.start_time, 'end', cs.end_time, 'type', cs.session_type, 'status', cs.session_status,
                                                    'room', CASE WHEN rm.room_id IS NULL THEN NULL ELSE bl.building_code || '-' || rm.room_code END) ORDER BY cs.start_time)
                FROM course_offering_section_student r
                JOIN student_course_registration cr ON cr.course_registration_id = r.course_registration_id
                JOIN student_term_registration tr ON tr.term_registration_id = cr.term_registration_id
                JOIN student_programme_enrolment e ON e.enrolment_id = tr.enrolment_id
                JOIN course_offering_section cos ON cos.course_offering_section_id = r.course_offering_section_id
                JOIN course_offering co ON co.course_offering_id = cos.course_offering_id
                JOIN course_catalog c ON c.course_id = co.course_id
                JOIN class_session cs ON cs.course_offering_section_id = cos.course_offering_section_id AND cs.session_date = current_date AND cs.session_status <> 'CANCELLED'
                LEFT JOIN room rm ON rm.room_id = cs.room_id LEFT JOIN building bl ON bl.building_id = rm.building_id
                WHERE e.student_id = v_stu AND r.roster_status = 'ACTIVE'), '[]'::jsonb));
    END IF;
    IF v_emp IS NOT NULL THEN
        v_out := v_out || jsonb_build_object(
            'upcoming', COALESCE((
                SELECT jsonb_agg(jsonb_build_object('session_id', cs.class_session_id, 'course', (c.course_code || ' — ' || c.course_title), 'section', csec.section_code, 'date', cs.session_date, 'start', cs.start_time,
                                                    'end', cs.end_time, 'type', cs.session_type, 'status', cs.session_status) ORDER BY cs.session_date, cs.start_time)
                FROM class_session cs
                JOIN faculty_course_assignment fa ON fa.faculty_assignment_id = cs.faculty_assignment_id
                JOIN course_offering_section cos ON cos.course_offering_section_id = cs.course_offering_section_id
                JOIN course_offering co ON co.course_offering_id = cos.course_offering_id
                JOIN course_catalog c ON c.course_id = co.course_id
                JOIN class_section csec ON csec.class_section_id = cos.class_section_id
                WHERE fa.employee_id = v_emp AND cs.session_date BETWEEN current_date AND current_date + 7 AND cs.session_status <> 'CANCELLED'), '[]'::jsonb),
            'unmarked', (SELECT count(*) FROM class_session cs JOIN faculty_course_assignment fa ON fa.faculty_assignment_id = cs.faculty_assignment_id
                         WHERE fa.employee_id = v_emp AND cs.session_status = 'PLANNED' AND cs.session_date < current_date AND cs.session_date >= current_date - 30),
            'sections', (SELECT count(DISTINCT fa.course_offering_section_id) FROM faculty_course_assignment fa WHERE fa.employee_id = v_emp AND (fa.end_date IS NULL OR fa.end_date >= current_date)));
    END IF;
    RETURN v_out;
END $function$;

CREATE OR REPLACE FUNCTION public.my_notification_count()
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT count(*)::integer FROM sims_private.notifications_all() n
    WHERE NOT EXISTS (SELECT 1 FROM sims_private.notification_dismissal d WHERE d.user_id = sims_private.current_user_id() AND d.notif_key = n.notif_key)
$function$;

CREATE OR REPLACE FUNCTION public.my_notifications(p_limit integer DEFAULT 50)
 RETURNS TABLE(notif_key text, kind text, title text, body text, href text, at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT n.notif_key, n.kind, n.title, n.body, n.href, n.at FROM sims_private.notifications_all() n
    WHERE NOT EXISTS (SELECT 1 FROM sims_private.notification_dismissal d WHERE d.user_id = sims_private.current_user_id() AND d.notif_key = n.notif_key)
    ORDER BY n.at DESC NULLS LAST, n.notif_key LIMIT LEAST(GREATEST(p_limit, 1), 200)
$function$;

CREATE OR REPLACE FUNCTION public.my_profile()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT COALESCE(
        (SELECT jsonb_build_object('kind', 'student', 'name', s.display_name, 'number', s.student_number, 'primary_email', s.primary_email, 'primary_phone', s.primary_phone) FROM student s WHERE s.student_id = sims_private.current_student_id()),
        (SELECT jsonb_build_object('kind', 'employee', 'name', e.display_name, 'number', e.employee_number, 'primary_email', e.primary_email, 'primary_phone', e.primary_phone) FROM employee e WHERE e.employee_id = sims_private.current_employee_id()),
        jsonb_build_object('kind', 'none'))
$function$;

CREATE OR REPLACE FUNCTION public.my_recent_logins(p_limit integer DEFAULT 10)
 RETURNS TABLE(login_at timestamp with time zone, logout_at timestamp with time zone, was_successful boolean, failure_reason text, ip_address text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT l.login_at, l.logout_at, l.was_successful, l.failure_reason::text, l.ip_address::text FROM login_audit l
    WHERE l.user_id = sims_private.current_user_id() ORDER BY l.login_at DESC, l.login_audit_id DESC LIMIT LEAST(GREATEST(p_limit, 1), 50)
$function$;

CREATE OR REPLACE FUNCTION public.my_results()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT COALESCE(jsonb_agg(term_obj ORDER BY t_start DESC, term_registration_id DESC), '[]'::jsonb)
    FROM (
        SELECT tr.term_registration_id, t.start_date AS t_start,
               jsonb_build_object(
                   'term_registration_id', tr.term_registration_id, 'term_name', t.term_name, 'semester_name', s.semester_name, 'programme_name', p.programme_name,
                   'credits_registered', r.credits_registered, 'credits_earned', r.credits_earned, 'sgpa', r.sgpa, 'cgpa', r.cgpa, 'result_status', r.result_status, 'published_at', r.published_at,
                   'courses', COALESCE((
                       SELECT jsonb_agg(jsonb_build_object('course_code', c.course_code, 'course_title', c.course_title, 'credits', c.credits, 'internal_marks', x.internal_marks,
                                                           'external_marks', x.external_marks, 'total_marks', x.total_marks, 'grade_letter', x.grade_letter, 'grade_point', x.grade_point,
                                                           'credits_earned', x.credits_earned, 'result_status', x.result_status) ORDER BY c.course_code)
                       FROM student_course_registration cr
                       JOIN course_offering co ON co.course_offering_id = cr.course_offering_id
                       JOIN course_catalog c ON c.course_id = co.course_id
                       JOIN LATERAL (SELECT y.* FROM student_course_result y WHERE y.course_registration_id = cr.course_registration_id ORDER BY y.attempt_number DESC LIMIT 1) x ON true
                       WHERE cr.term_registration_id = tr.term_registration_id), '[]'::jsonb)
               ) AS term_obj
        FROM student_term_registration tr
        JOIN student_programme_enrolment e ON e.enrolment_id = tr.enrolment_id
        JOIN student_term_result r ON r.term_registration_id = tr.term_registration_id AND r.published_at IS NOT NULL
        JOIN programme_term_offering pto ON pto.programme_term_offering_id = tr.programme_term_offering_id
        JOIN academic_term t ON t.academic_term_id = pto.academic_term_id
        JOIN semester s ON s.semester_id = pto.semester_id
        JOIN programme p ON p.programme_id = pto.programme_id
        WHERE e.student_id = sims_private.current_student_id() AND NOT sims_private.fin_hold_active(e.student_id, 'RESULT')
    ) q
$function$;

CREATE OR REPLACE FUNCTION public.record_sections(p_kind text)
 RETURNS TABLE(section text, label text)
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT v.section, v.label FROM (VALUES
        ('student', 'address', 'Addresses'), ('student', 'guardian', 'Parents and guardians'), ('student', 'previous_education', 'Previous education'),
        ('student', 'entrance_exam', 'Entrance exams'), ('student', 'residence', 'Residence'),
        ('employee', 'address', 'Addresses'), ('employee', 'qualification', 'Qualifications'), ('employee', 'experience', 'Previous employment'),
        ('activity', 'supervision', 'Research supervision'), ('activity', 'utilization', 'Financial utilisation')
    ) AS v(kind, section, label) WHERE v.kind = p_kind
$function$;

CREATE OR REPLACE FUNCTION public.ref_list()
 RETURNS TABLE(tbl text, label text, module_code text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT t, d.label, d.module_code FROM unnest(sims_private.ref_tables()) t, LATERAL sims_private.ref_def(t) d WHERE sims_private.can_global(ARRAY[d.perm]::text[]) ORDER BY d.module_code, d.label
$function$;

CREATE OR REPLACE FUNCTION public.ref_rows(p_table text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE d record; v_pk text; v_rows jsonb;
BEGIN
    SELECT * INTO d FROM sims_private.ref_def(p_table);
    IF d.perm IS NULL THEN RAISE EXCEPTION 'Unknown reference table' USING ERRCODE = '22023'; END IF;
    IF NOT sims_private.can_global(ARRAY[d.perm]::text[]) THEN RAISE EXCEPTION 'Not authorised (%)', d.perm USING ERRCODE = '42501'; END IF;
    v_pk := sims_private.pk_column(p_table);
    EXECUTE format('SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.%I), ''[]''::jsonb) FROM (SELECT * FROM public.%I ORDER BY %I LIMIT 1000) t', v_pk, p_table, v_pk) INTO v_rows;
    RETURN v_rows;
END $function$;

CREATE OR REPLACE FUNCTION public.ref_save(p_table text, p_id bigint, p jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE d record; v_pk text; v_before jsonb; v_id bigint; v_after jsonb;
BEGIN
    SELECT * INTO d FROM sims_private.ref_def(p_table);
    IF d.perm IS NULL THEN RAISE EXCEPTION 'Unknown reference table' USING ERRCODE = '22023'; END IF;
    IF NOT sims_private.can_global(ARRAY[d.perm]::text[]) THEN RAISE EXCEPTION 'Not authorised (%)', d.perm USING ERRCODE = '42501'; END IF;
    v_pk := sims_private.pk_column(p_table);
    IF p_id IS NOT NULL THEN
        EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE t.%I = $1', p_table, v_pk) INTO v_before USING p_id;
        IF v_before IS NULL THEN RAISE EXCEPTION 'Unknown row' USING ERRCODE = '22023'; END IF;
    END IF;
    v_id := sims_private.write_row(p_table, v_pk, NULL, NULL, p_id, p);
    EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE t.%I = $1', p_table, v_pk) INTO v_after USING v_id;
    PERFORM sims_private.audit_manual(d.module_code, CASE WHEN p_id IS NULL THEN 'INSERT' ELSE 'UPDATE' END, p_table, v_id, v_before, v_after);
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.ref_schema(p_table text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE d record; v_pk text;
BEGIN
    SELECT * INTO d FROM sims_private.ref_def(p_table);
    IF d.perm IS NULL THEN RAISE EXCEPTION 'Unknown reference table' USING ERRCODE = '22023'; END IF;
    IF NOT sims_private.can_global(ARRAY[d.perm]::text[]) THEN RAISE EXCEPTION 'Not authorised (%)', d.perm USING ERRCODE = '42501'; END IF;
    v_pk := sims_private.pk_column(p_table);
    RETURN jsonb_build_object('table', p_table, 'label', d.label, 'pk', v_pk, 'columns', sims_private.form_columns(p_table, ARRAY[v_pk]));
END $function$;

CREATE OR REPLACE FUNCTION public.registration_candidates(p_offering_id bigint, p_q text DEFAULT NULL::text)
 RETURNS TABLE(enrolment_id bigint, student_id bigint, student_number text, display_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_off record; v_q text := NULLIF(btrim(p_q), '');
BEGIN
    SELECT programme_id, specialization_id INTO v_off FROM programme_term_offering WHERE programme_term_offering_id = p_offering_id;
    IF v_off IS NULL OR NOT sims_private.can_programme(ARRAY['REGISTRATION.ALL.CREATE']::text[], v_off.programme_id) THEN
        RAISE EXCEPTION 'Not authorised (REGISTRATION.ALL.CREATE) or unknown offering' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    SELECT e.enrolment_id::bigint, s.student_id, s.student_number::text, s.display_name::text
    FROM student_programme_enrolment e JOIN student s ON s.student_id = e.student_id
    WHERE e.programme_id = v_off.programme_id AND e.enrolment_status = 'ACTIVE'
      AND (v_off.specialization_id IS NULL OR e.specialization_id = v_off.specialization_id)
      AND NOT EXISTS (SELECT 1 FROM student_term_registration r WHERE r.enrolment_id = e.enrolment_id AND r.programme_term_offering_id = p_offering_id)
      AND (v_q IS NULL OR s.display_name ILIKE '%' || replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_') || '%'
                       OR s.student_number ILIKE '%' || replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_') || '%')
    ORDER BY s.display_name
    LIMIT 50;
END $function$;

CREATE OR REPLACE FUNCTION public.registration_roster(p_offering_id bigint)
 RETURNS TABLE(term_registration_id bigint, enrolment_id bigint, student_id bigint, student_number text, display_name text, roll_number text, class_section_id bigint, class_batch_id bigint, registration_date date, registration_status text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_prog integer;
BEGIN
    SELECT programme_id INTO v_prog FROM programme_term_offering WHERE programme_term_offering_id = p_offering_id;
    IF v_prog IS NULL OR NOT sims_private.can_programme(ARRAY['REGISTRATION.ALL.READ']::text[], v_prog) THEN
        RAISE EXCEPTION 'Not authorised (REGISTRATION.ALL.READ) or unknown offering' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    SELECT r.term_registration_id, r.enrolment_id::bigint, s.student_id, s.student_number::text, s.display_name::text,
           r.roll_number::text, r.class_section_id::bigint, r.class_batch_id::bigint, r.registration_date, r.registration_status::text
    FROM student_term_registration r
    JOIN student_programme_enrolment e ON e.enrolment_id = r.enrolment_id
    JOIN student s ON s.student_id = e.student_id
    WHERE r.programme_term_offering_id = p_offering_id
    ORDER BY s.display_name, r.term_registration_id;
END $function$;

CREATE OR REPLACE FUNCTION public.registration_term_info(p_term_registration_id bigint)
 RETURNS TABLE(term_registration_id bigint, enrolment_id bigint, student_id bigint, student_number text, display_name text, programme_term_offering_id bigint, class_section_id bigint, class_batch_id bigint, roll_number text, registration_date date, registration_status text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_prog integer;
BEGIN
    SELECT o.programme_id INTO v_prog FROM student_term_registration r JOIN programme_term_offering o ON o.programme_term_offering_id = r.programme_term_offering_id
     WHERE r.term_registration_id = p_term_registration_id;
    IF v_prog IS NULL OR NOT sims_private.can_programme(ARRAY['REGISTRATION.ALL.READ']::text[], v_prog) THEN
        RAISE EXCEPTION 'Not authorised (REGISTRATION.ALL.READ) or unknown registration' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    SELECT r.term_registration_id, r.enrolment_id::bigint, s.student_id, s.student_number::text, s.display_name::text, r.programme_term_offering_id::bigint,
           r.class_section_id::bigint, r.class_batch_id::bigint, r.roll_number::text, r.registration_date, r.registration_status::text
    FROM student_term_registration r
    JOIN student_programme_enrolment e ON e.enrolment_id = r.enrolment_id
    JOIN student s ON s.student_id = e.student_id
    WHERE r.term_registration_id = p_term_registration_id;
END $function$;

CREATE OR REPLACE FUNCTION public.result_course_sheet(p_course_offering_id bigint)
 RETURNS TABLE(course_registration_id bigint, student_id bigint, student_number text, display_name text, internal_marks numeric, external_marks numeric, total_marks numeric, grade_letter text, grade_point numeric, result_status text, attempt_number integer, published boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    PERFORM sims_private.asm_authorize(p_course_offering_id, 'RESULT', 'READ');
    RETURN QUERY
    SELECT cr.course_registration_id, s.student_id, s.student_number::text, s.display_name::text, r.internal_marks, r.external_marks, r.total_marks,
           r.grade_letter::text, r.grade_point, r.result_status::text, r.attempt_number::integer, sims_private.course_result_published(cr.course_registration_id)
    FROM student_course_registration cr
    JOIN student_term_registration tr ON tr.term_registration_id = cr.term_registration_id
    JOIN student_programme_enrolment e ON e.enrolment_id = tr.enrolment_id
    JOIN student s ON s.student_id = e.student_id
    LEFT JOIN LATERAL (SELECT x.* FROM student_course_result x WHERE x.course_registration_id = cr.course_registration_id ORDER BY x.attempt_number DESC LIMIT 1) r ON true
    WHERE cr.course_offering_id = p_course_offering_id AND cr.registration_status IN ('REGISTERED', 'APPROVED', 'COMPLETED')
    ORDER BY s.display_name, cr.course_registration_id;
END $function$;

CREATE OR REPLACE FUNCTION public.result_term_sheet(p_offering_id bigint)
 RETURNS TABLE(term_registration_id bigint, student_id bigint, student_number text, display_name text, credits_registered numeric, credits_earned numeric, sgpa numeric, cgpa numeric, result_status text, published_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_prog integer;
BEGIN
    SELECT programme_id INTO v_prog FROM programme_term_offering WHERE programme_term_offering_id = p_offering_id;
    IF v_prog IS NULL OR NOT sims_private.can_programme(ARRAY['RESULT.ALL.READ']::text[], v_prog) THEN
        RAISE EXCEPTION 'Not authorised (RESULT.ALL.READ) or unknown offering' USING ERRCODE = '42501';
    END IF;
    RETURN QUERY
    SELECT tr.term_registration_id, s.student_id, s.student_number::text, s.display_name::text, r.credits_registered, r.credits_earned, r.sgpa, r.cgpa, r.result_status::text, r.published_at
    FROM student_term_registration tr
    JOIN student_programme_enrolment e ON e.enrolment_id = tr.enrolment_id
    JOIN student s ON s.student_id = e.student_id
    LEFT JOIN student_term_result r ON r.term_registration_id = tr.term_registration_id
    WHERE tr.programme_term_offering_id = p_offering_id AND tr.registration_status IN ('REGISTERED', 'APPROVED', 'COMPLETED')
    ORDER BY s.display_name, tr.term_registration_id;
END $function$;

CREATE OR REPLACE FUNCTION public.section_lookup_options(p_table text)
 RETURNS TABLE(id bigint, label text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_pk text; v_label text; v_oid oid;
BEGIN
    IF NOT sims_private.is_active_member() THEN RAISE EXCEPTION 'Not authorised' USING ERRCODE = '42501'; END IF;
    IF p_table <> ALL (sims_private.section_option_tables()) THEN RAISE EXCEPTION 'Unknown lookup table' USING ERRCODE = '22023'; END IF;
    v_oid := format('public.%I', p_table)::regclass;
    v_pk := sims_private.pk_column(p_table);
    SELECT at.attname INTO v_label FROM pg_attribute at JOIN pg_type ty ON ty.oid = at.atttypid
    WHERE at.attrelid = v_oid AND at.attnum > 0 AND NOT at.attisdropped AND ty.typname IN ('varchar', 'text') AND at.attname <> v_pk ORDER BY (at.attname LIKE '%name') DESC, at.attnum LIMIT 1;
    RETURN QUERY EXECUTE format('SELECT %I::bigint, %I::text FROM public.%I ORDER BY 2 LIMIT 1000', v_pk, v_label, p_table);
END $function$;

CREATE OR REPLACE FUNCTION public.section_rows(p_kind text, p_parent_id bigint, p_section text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE d record; v_rows jsonb;
BEGIN
    SELECT * INTO d FROM sims_private.section_def(p_kind, p_section);
    IF d.tbl IS NULL THEN RAISE EXCEPTION 'Unknown section' USING ERRCODE = '22023'; END IF;
    IF NOT sims_private.section_can(p_kind, d.perm_prefix, 'READ', p_parent_id) THEN RAISE EXCEPTION 'Not authorised (%.READ)', d.perm_prefix USING ERRCODE = '42501'; END IF;
    EXECUTE format('SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY t.%I), ''[]''::jsonb) FROM public.%I t WHERE t.%I = $1', d.pk_col, d.tbl, d.parent_col) INTO v_rows USING p_parent_id;
    RETURN jsonb_build_object('rows', v_rows, 'can_create', sims_private.section_can(p_kind, d.perm_prefix, 'CREATE', p_parent_id), 'can_update', sims_private.section_can(p_kind, d.perm_prefix, 'UPDATE', p_parent_id),
                              'can_delete', sims_private.section_can(p_kind, d.perm_prefix, 'DELETE', p_parent_id));
END $function$;

CREATE OR REPLACE FUNCTION public.section_save(p_kind text, p_parent_id bigint, p_section text, p_id bigint, p jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE d record; v_before jsonb; v_id bigint; v_after jsonb;
BEGIN
    SELECT * INTO d FROM sims_private.section_def(p_kind, p_section);
    IF d.tbl IS NULL THEN RAISE EXCEPTION 'Unknown section' USING ERRCODE = '22023'; END IF;
    IF NOT sims_private.section_can(p_kind, d.perm_prefix, CASE WHEN p_id IS NULL THEN 'CREATE' ELSE 'UPDATE' END, p_parent_id) THEN
        RAISE EXCEPTION 'Not authorised (%.%)', d.perm_prefix, CASE WHEN p_id IS NULL THEN 'CREATE' ELSE 'UPDATE' END USING ERRCODE = '42501';
    END IF;
    IF p_kind = 'student' AND NOT EXISTS (SELECT 1 FROM student WHERE student_id = p_parent_id) THEN RAISE EXCEPTION 'Unknown student' USING ERRCODE = '22023'; END IF;
    IF p_kind = 'employee' AND NOT EXISTS (SELECT 1 FROM employee WHERE employee_id = p_parent_id) THEN RAISE EXCEPTION 'Unknown employee' USING ERRCODE = '22023'; END IF;
    IF p_id IS NOT NULL THEN
        EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE t.%I = $1 AND t.%I = $2', d.tbl, d.pk_col, d.parent_col) INTO v_before USING p_id, p_parent_id;
        IF v_before IS NULL THEN RAISE EXCEPTION 'Unknown row' USING ERRCODE = '22023'; END IF;
    END IF;
    v_id := sims_private.write_row(d.tbl, d.pk_col, d.parent_col, p_parent_id, p_id, p);
    EXECUTE format('SELECT to_jsonb(t) FROM public.%I t WHERE t.%I = $1', d.tbl, d.pk_col) INTO v_after USING v_id;
    PERFORM sims_private.audit_manual(d.module_code, CASE WHEN p_id IS NULL THEN 'INSERT' ELSE 'UPDATE' END, d.tbl, v_id, v_before, v_after);
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.section_schema(p_kind text, p_section text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE d record;
BEGIN
    IF NOT sims_private.is_active_member() THEN RAISE EXCEPTION 'Not authorised' USING ERRCODE = '42501'; END IF;
    SELECT * INTO d FROM sims_private.section_def(p_kind, p_section);
    IF d.tbl IS NULL THEN RAISE EXCEPTION 'Unknown section' USING ERRCODE = '22023'; END IF;
    RETURN jsonb_build_object('table', d.tbl, 'label', d.label, 'pk', d.pk_col, 'columns', sims_private.form_columns(d.tbl, ARRAY[d.pk_col, d.parent_col]));
END $function$;

CREATE OR REPLACE FUNCTION public.staff_activity_get(p_activity_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a record; v_owner boolean; v_draft boolean; v_table text; v_detail jsonb;
BEGIN
    SELECT x.*, t.activity_type_name, t.activity_type_code, t.activity_group, e.employee_number AS enum, e.display_name AS ename, vs.status_code AS vcode, aps.status_code AS acode INTO a
    FROM staff_activity x JOIN activity_type t ON t.activity_type_id = x.activity_type_id JOIN employee e ON e.employee_id = x.employee_id
    JOIN verification_status vs ON vs.verification_status_id = x.verification_status_id JOIN approval_status aps ON aps.approval_status_id = x.approval_status_id
    WHERE x.staff_activity_id = p_activity_id AND x.deleted_at IS NULL;
    v_owner := COALESCE(a.employee_id = sims_private.current_employee_id(), false);
    IF a.staff_activity_id IS NULL OR NOT (v_owner OR sims_private.can_employee(ARRAY['STAFF_PROFILE.STAFF_ACTIVITY.READ']::text[], a.employee_id, false)) THEN
        RAISE EXCEPTION 'Not authorised (STAFF_PROFILE.STAFF_ACTIVITY.READ) or unknown record' USING ERRCODE = '42501';
    END IF;
    v_draft := a.acode = 'DRAFT';
    v_table := sims_private.staff_detail_table(a.activity_type_code);
    IF v_table IS NOT NULL THEN EXECUTE format('SELECT to_jsonb(t) - ''staff_activity_id'' FROM public.%I t WHERE t.staff_activity_id = $1', v_table) INTO v_detail USING p_activity_id; END IF;
    RETURN jsonb_build_object('staff_activity_id', a.staff_activity_id, 'employee_id', a.employee_id, 'employee_number', a.enum, 'staff_name', a.ename, 'activity_type_id', a.activity_type_id, 'type_name', a.activity_type_name,
        'activity_group', a.activity_group, 'academic_year_id', a.academic_year_id, 'participation_level_id', a.participation_level_id, 'primary_role_type_id', a.primary_role_type_id, 'activity_title', a.activity_title,
        'start_date', a.start_date, 'end_date', a.end_date, 'description', a.description, 'outcomes', a.outcomes, 'verification_status', a.vcode, 'verification_remarks', a.verification_remarks,
        'approval_status', a.acode, 'approval_remarks', a.approval_remarks, 'rejection_reason', a.rejection_reason, 'detail_table', v_table, 'detail', COALESCE(v_detail, '{}'::jsonb), 'is_owner', v_owner,
        'can_edit', v_draft AND sims_private.staff_actor(a.employee_id, 'STAFF_PROFILE.STAFF_ACTIVITY.UPDATE') IS NOT NULL,
        'can_delete', a.acode IN ('DRAFT', 'REJECTED') AND sims_private.staff_actor(a.employee_id, 'STAFF_PROFILE.STAFF_ACTIVITY.DELETE') IS NOT NULL,
        'can_verify', a.acode = 'SUBMITTED' AND NOT v_owner AND sims_private.can_employee(ARRAY['STAFF_PROFILE.STAFF_ACTIVITY.VERIFY']::text[], a.employee_id, true),
        'can_approve', a.acode = 'UNDER_REVIEW' AND NOT v_owner AND sims_private.can_employee(ARRAY['STAFF_PROFILE.STAFF_ACTIVITY.APPROVE']::text[], a.employee_id, true),
        'contributors', COALESCE((SELECT jsonb_agg(jsonb_build_object('contributor_id', c.staff_activity_contributor_id, 'name', COALESCE(ce.display_name, c.external_person_name), 'is_employee', c.employee_id IS NOT NULL,
                                 'role', rt.role_name, 'affiliation', c.affiliation_text, 'is_corresponding', c.is_corresponding_author) ORDER BY c.contributor_sequence, c.staff_activity_contributor_id)
                                 FROM staff_activity_contributor c LEFT JOIN employee ce ON ce.employee_id = c.employee_id LEFT JOIN role_type rt ON rt.role_type_id = c.role_type_id WHERE c.staff_activity_id = a.staff_activity_id), '[]'::jsonb),
        'evidence', COALESCE((SELECT jsonb_agg(jsonb_build_object('evidence_id', ev.evidence_document_id, 'title', ev.document_title, 'evidence_type', et.evidence_type_name, 'version', ev.current_version_number,
                                'file_name', f.original_file_name, 'size', f.file_size_bytes, 'issued', ev.document_issue_date, 'authority', ev.issuing_authority, 'certificate_number', ev.certificate_document_number) ORDER BY ev.evidence_document_id)
                                FROM evidence_document ev LEFT JOIN evidence_type et ON et.evidence_type_id = ev.evidence_type_id
                                JOIN evidence_document_version v ON v.evidence_document_id = ev.evidence_document_id AND v.is_current JOIN file_object f ON f.file_object_id = v.file_object_id
                                WHERE ev.staff_activity_id = a.staff_activity_id AND ev.deleted_at IS NULL), '[]'::jsonb));
END $function$;

CREATE OR REPLACE FUNCTION public.staff_activity_list(p_employee_id bigint DEFAULT NULL::bigint, p_search text DEFAULT NULL::text, p_approval text DEFAULT NULL::text, p_group text DEFAULT NULL::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS TABLE(staff_activity_id bigint, employee_id bigint, employee_number text, staff_name text, type_name text, activity_group text, activity_title text, start_date date, verification_status text, approval_status text, evidence_count bigint, total_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT pg.staff_activity_id::bigint, pg.employee_id::bigint, pg.employee_number, pg.staff_name, pg.type_name, pg.activity_group, pg.activity_title, pg.start_date, pg.verification_status, pg.approval_status,
           (SELECT count(*) FROM evidence_document ev WHERE ev.staff_activity_id = pg.staff_activity_id AND ev.deleted_at IS NULL), pg.total_count
    FROM (
        SELECT v.*, count(*) OVER () AS total_count FROM (
            SELECT a.staff_activity_id, a.employee_id, e.employee_number::text, e.display_name::text AS staff_name, t.activity_type_name::text AS type_name, t.activity_group::text, a.activity_title::text, a.start_date,
                   vs.status_code::text AS verification_status, aps.status_code::text AS approval_status, a.created_at
            FROM staff_activity a JOIN employee e ON e.employee_id = a.employee_id JOIN activity_type t ON t.activity_type_id = a.activity_type_id
            JOIN verification_status vs ON vs.verification_status_id = a.verification_status_id JOIN approval_status aps ON aps.approval_status_id = a.approval_status_id
            WHERE a.deleted_at IS NULL AND (p_employee_id IS NULL OR a.employee_id = p_employee_id)
              AND (p_approval IS NULL OR a.approval_status_id = (SELECT x.approval_status_id FROM approval_status x WHERE x.status_code = p_approval))
              AND (p_group IS NULL OR a.activity_type_id IN (SELECT y.activity_type_id FROM activity_type y WHERE y.activity_group = p_group))
              AND (p_search IS NULL OR btrim(p_search) = '' OR position(lower(btrim(p_search)) IN lower(a.activity_title || ' ' || e.display_name || ' ' || e.employee_number)) > 0)
              AND (COALESCE(a.employee_id = sims_private.current_employee_id(), false) OR sims_private.can_employee(ARRAY['STAFF_PROFILE.STAFF_ACTIVITY.READ']::text[], a.employee_id, false))
        ) v
        ORDER BY v.created_at DESC, v.staff_activity_id DESC LIMIT LEAST(GREATEST(p_limit, 1), 200) OFFSET GREATEST(p_offset, 0)
    ) pg
    ORDER BY pg.created_at DESC, pg.staff_activity_id DESC
$function$;

CREATE OR REPLACE FUNCTION public.staff_activity_report(p_year integer DEFAULT NULL::integer)
 RETURNS TABLE(activity_group text, approval_status text, records bigint, employees bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT t.activity_group::text, aps.status_code::text, count(*), count(DISTINCT a.employee_id)
    FROM staff_activity a JOIN activity_type t ON t.activity_type_id = a.activity_type_id JOIN approval_status aps ON aps.approval_status_id = a.approval_status_id
    WHERE a.deleted_at IS NULL AND (p_year IS NULL OR a.academic_year_id = p_year) AND sims_private.can_employee(ARRAY['STAFF_PROFILE.STAFF_REPORT.READ']::text[], a.employee_id, false)
    GROUP BY t.activity_group, aps.status_code ORDER BY t.activity_group, aps.status_code
$function$;

CREATE OR REPLACE FUNCTION public.staff_detail_schema(p_activity_type_id integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_code text; v_table text;
BEGIN
    IF NOT sims_private.is_active_member() THEN RAISE EXCEPTION 'Not authorised' USING ERRCODE = '42501'; END IF;
    SELECT activity_type_code INTO v_code FROM activity_type WHERE activity_type_id = p_activity_type_id;
    v_table := sims_private.staff_detail_table(v_code);
    IF v_table IS NULL THEN RETURN jsonb_build_object('table', NULL, 'columns', '[]'::jsonb); END IF;
    RETURN jsonb_build_object('table', v_table, 'columns', sims_private.describe_columns(v_table, ARRAY['staff_activity_id']));
END $function$;

CREATE OR REPLACE FUNCTION public.staff_indexing_list(p_activity_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_table text := sims_private.indexing_table(p_activity_id); v_rows jsonb;
BEGIN
    IF v_table IS NULL OR NOT (SELECT sims_private.activity_child_ok(p_activity_id, CASE v_table WHEN 'journal_publication_indexing' THEN 'journal_publication' ELSE 'conference_activity' END, 'STAFF_PROFILE.STAFF_ACTIVITY', 'READ')) THEN
        RAISE EXCEPTION 'Not authorised (STAFF_PROFILE.STAFF_ACTIVITY.READ) or unknown record' USING ERRCODE = '42501';
    END IF;
    EXECUTE format('SELECT COALESCE(jsonb_agg(jsonb_build_object(''agency_id'', i.indexing_agency_id, ''agency'', g.agency_name, ''status'', i.indexing_status, ''url'', i.source_url, ''remarks'', i.remarks, ''year'', %s) ORDER BY g.agency_name), ''[]''::jsonb)
                    FROM public.%I i JOIN public.indexing_agency g ON g.indexing_agency_id = i.indexing_agency_id WHERE i.staff_activity_id = $1',
                   CASE WHEN v_table = 'journal_publication_indexing' THEN 'i.indexed_year' ELSE 'NULL::integer' END, v_table) INTO v_rows USING p_activity_id;
    RETURN jsonb_build_object('rows', v_rows, 'kind', CASE v_table WHEN 'journal_publication_indexing' THEN 'JOURNAL' ELSE 'CONFERENCE' END,
        'can_edit', sims_private.activity_child_ok(p_activity_id, CASE v_table WHEN 'journal_publication_indexing' THEN 'journal_publication' ELSE 'conference_activity' END, 'STAFF_PROFILE.STAFF_ACTIVITY', 'UPDATE'));
END $function$;

CREATE OR REPLACE FUNCTION public.staff_lookup_options(p_table text)
 RETURNS TABLE(id bigint, label text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_pk text; v_label text; v_oid oid;
BEGIN
    IF NOT sims_private.is_active_member() THEN RAISE EXCEPTION 'Not authorised' USING ERRCODE = '42501'; END IF;
    IF p_table <> ALL (sims_private.staff_option_tables()) THEN RAISE EXCEPTION 'Unknown lookup table' USING ERRCODE = '22023'; END IF;
    v_oid := to_regclass(format('public.%I', p_table));
    IF v_oid IS NULL THEN RAISE EXCEPTION 'Unknown lookup table' USING ERRCODE = '22023'; END IF;
    SELECT at.attname INTO v_pk FROM pg_constraint cp JOIN pg_attribute at ON at.attrelid = cp.conrelid AND at.attnum = cp.conkey[1] WHERE cp.contype = 'p' AND cp.conrelid = v_oid;
    SELECT at.attname INTO v_label FROM pg_attribute at JOIN pg_type ty ON ty.oid = at.atttypid
    WHERE at.attrelid = v_oid AND at.attnum > 0 AND NOT at.attisdropped AND ty.typname IN ('varchar', 'text') AND at.attname <> v_pk
    ORDER BY (at.attname LIKE '%name') DESC, at.attnum LIMIT 1;
    IF v_pk IS NULL OR v_label IS NULL THEN RAISE EXCEPTION 'Unknown lookup table' USING ERRCODE = '22023'; END IF;
    RETURN QUERY EXECUTE format('SELECT %I::bigint, %I::text FROM public.%I ORDER BY 2 LIMIT 500', v_pk, v_label, p_table);
END $function$;

CREATE OR REPLACE FUNCTION public.staff_lookup_schema(p_table text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_pk text;
BEGIN
    IF NOT sims_private.is_active_member() THEN RAISE EXCEPTION 'Not authorised' USING ERRCODE = '42501'; END IF;
    IF p_table <> ALL (sims_private.staff_lookup_tables()) THEN RAISE EXCEPTION 'That list cannot be extended here' USING ERRCODE = '22023'; END IF;
    SELECT at.attname INTO v_pk FROM pg_constraint cp JOIN pg_attribute at ON at.attrelid = cp.conrelid AND at.attnum = cp.conkey[1] WHERE cp.contype = 'p' AND cp.conrelid = format('public.%I', p_table)::regclass;
    RETURN jsonb_build_object('table', p_table, 'columns', sims_private.describe_columns(p_table, ARRAY[v_pk, 'created_at', 'updated_at', 'is_active']));
END $function$;

CREATE OR REPLACE FUNCTION public.student_activity_get(p_activity_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a record; v_owner boolean; v_draft boolean;
BEGIN
    SELECT x.*, t.type_name, t.requires_team_details, s.student_number AS snum, s.display_name AS sname, vs.status_code AS vcode, aps.status_code AS acode INTO a
    FROM student_activity x JOIN student_activity_type t ON t.student_activity_type_id = x.student_activity_type_id JOIN student s ON s.student_id = x.student_id
    JOIN verification_status vs ON vs.verification_status_id = x.verification_status_id JOIN approval_status aps ON aps.approval_status_id = x.approval_status_id
    WHERE x.student_activity_id = p_activity_id AND x.deleted_at IS NULL;
    v_owner := COALESCE(a.student_id = sims_private.current_student_id(), false);
    IF a.student_activity_id IS NULL OR NOT (v_owner OR sims_private.can_student(ARRAY['STUDENT.STUDENT_ACTIVITY.READ']::text[], a.student_id, false)) THEN
        RAISE EXCEPTION 'Not authorised (STUDENT.STUDENT_ACTIVITY.READ) or unknown activity' USING ERRCODE = '42501';
    END IF;
    v_draft := a.acode = 'DRAFT';
    RETURN jsonb_build_object('student_activity_id', a.student_activity_id, 'student_id', a.student_id, 'student_number', a.snum, 'student_name', a.sname, 'student_activity_type_id', a.student_activity_type_id, 'type_name', a.type_name,
        'requires_team_details', a.requires_team_details, 'academic_year_id', a.academic_year_id, 'participation_level_id', a.participation_level_id, 'event_mode_id', a.event_mode_id, 'organizer_name', a.organizer_name,
        'activity_title', a.activity_title, 'event_name', a.event_name, 'team_name', a.team_name, 'participation_role', a.participation_role, 'start_date', a.start_date, 'end_date', a.end_date, 'venue_name', a.venue_name,
        'city', a.city, 'achievement_type', a.achievement_type, 'position_rank', a.position_rank, 'award_name', a.award_name, 'activity_url', a.activity_url, 'description', a.description, 'outcomes', a.outcomes,
        'verification_status', a.vcode, 'verification_remarks', a.verification_remarks, 'approval_status', a.acode, 'approval_remarks', a.approval_remarks, 'rejection_reason', a.rejection_reason,
        'is_owner', v_owner,
        'can_edit', v_draft AND sims_private.activity_actor(a.student_id, 'STUDENT.STUDENT_ACTIVITY.UPDATE') IS NOT NULL,
        'can_delete', a.acode IN ('DRAFT', 'REJECTED') AND sims_private.activity_actor(a.student_id, 'STUDENT.STUDENT_ACTIVITY.DELETE') IS NOT NULL,
        'can_verify', a.acode = 'SUBMITTED' AND sims_private.can_student(ARRAY['STUDENT.STUDENT_ACTIVITY.VERIFY']::text[], a.student_id, true),
        'can_approve', a.acode = 'UNDER_REVIEW' AND sims_private.can_student(ARRAY['STUDENT.STUDENT_ACTIVITY.APPROVE']::text[], a.student_id, true),
        'team', COALESCE((SELECT jsonb_agg(jsonb_build_object('member_id', m.student_activity_team_member_id, 'name', COALESCE(ms.display_name, m.external_member_name), 'is_student', m.student_id IS NOT NULL, 'role', m.member_role, 'is_lead', m.is_team_lead) ORDER BY m.member_sequence, m.student_activity_team_member_id)
                          FROM student_activity_team_member m LEFT JOIN student ms ON ms.student_id = m.student_id WHERE m.student_activity_id = a.student_activity_id), '[]'::jsonb),
        'evidence', COALESCE((SELECT jsonb_agg(jsonb_build_object('evidence_id', ev.student_activity_evidence_id, 'title', ev.document_title, 'evidence_type', et.evidence_type_name, 'version', ev.current_version_number,
                                'file_name', f.original_file_name, 'size', f.file_size_bytes, 'issued', ev.document_issue_date, 'authority', ev.issuing_authority, 'certificate_number', ev.certificate_document_number) ORDER BY ev.student_activity_evidence_id)
                          FROM student_activity_evidence ev LEFT JOIN evidence_type et ON et.evidence_type_id = ev.evidence_type_id
                          JOIN student_activity_evidence_version v ON v.student_activity_evidence_id = ev.student_activity_evidence_id AND v.is_current JOIN file_object f ON f.file_object_id = v.file_object_id
                          WHERE ev.student_activity_id = a.student_activity_id AND ev.deleted_at IS NULL), '[]'::jsonb));
END $function$;

CREATE OR REPLACE FUNCTION public.student_activity_list(p_student_id bigint DEFAULT NULL::bigint, p_search text DEFAULT NULL::text, p_approval text DEFAULT NULL::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS TABLE(student_activity_id bigint, student_id bigint, student_number text, student_name text, type_name text, activity_title text, achievement_type text, start_date date, verification_status text, approval_status text, evidence_count bigint, total_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT pg.student_activity_id::bigint, pg.student_id::bigint, pg.student_number, pg.student_name, pg.type_name, pg.activity_title, pg.achievement_type, pg.start_date, pg.verification_status, pg.approval_status,
           (SELECT count(*) FROM student_activity_evidence ev WHERE ev.student_activity_id = pg.student_activity_id AND ev.deleted_at IS NULL), pg.total_count
    FROM (
        SELECT v.*, count(*) OVER () AS total_count FROM (
            SELECT a.student_activity_id, a.student_id, s.student_number::text, s.display_name::text AS student_name, t.type_name::text, a.activity_title::text, a.achievement_type::text, a.start_date,
                   vs.status_code::text AS verification_status, aps.status_code::text AS approval_status, a.created_at
            FROM student_activity a JOIN student s ON s.student_id = a.student_id JOIN student_activity_type t ON t.student_activity_type_id = a.student_activity_type_id
            JOIN verification_status vs ON vs.verification_status_id = a.verification_status_id JOIN approval_status aps ON aps.approval_status_id = a.approval_status_id
            WHERE a.deleted_at IS NULL AND (p_student_id IS NULL OR a.student_id = p_student_id)
              AND (p_approval IS NULL OR a.approval_status_id = (SELECT x.approval_status_id FROM approval_status x WHERE x.status_code = p_approval))
              AND (p_search IS NULL OR btrim(p_search) = '' OR position(lower(btrim(p_search)) IN lower(a.activity_title || ' ' || s.display_name || ' ' || s.student_number)) > 0)
              AND (COALESCE(a.student_id = sims_private.current_student_id(), false) OR sims_private.can_student(ARRAY['STUDENT.STUDENT_ACTIVITY.READ']::text[], a.student_id, false))
        ) v
        ORDER BY v.created_at DESC, v.student_activity_id DESC LIMIT LEAST(GREATEST(p_limit, 1), 200) OFFSET GREATEST(p_offset, 0)
    ) pg
    ORDER BY pg.created_at DESC, pg.student_activity_id DESC
$function$;

CREATE OR REPLACE FUNCTION public.student_activity_report(p_year integer DEFAULT NULL::integer)
 RETURNS TABLE(type_name text, approval_status text, activities bigint, winners bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT t.type_name::text, aps.status_code::text, count(*), count(*) FILTER (WHERE a.achievement_type NOT IN ('PARTICIPATION', 'OTHER'))
    FROM student_activity a JOIN student_activity_type t ON t.student_activity_type_id = a.student_activity_type_id JOIN approval_status aps ON aps.approval_status_id = a.approval_status_id
    WHERE a.deleted_at IS NULL AND (p_year IS NULL OR a.academic_year_id = p_year) AND sims_private.can_student(ARRAY['STUDENT.STUDENT_ACTIVITY_REPORT.READ']::text[], a.student_id, false)
    GROUP BY t.type_name, aps.status_code ORDER BY t.type_name, aps.status_code
$function$;

CREATE OR REPLACE FUNCTION public.student_document_list(p_student_id bigint)
 RETURNS TABLE(student_document_id bigint, document_type text, requires_verification boolean, original_file_name text, mime_type text, file_size_bytes bigint, document_number text, issue_date date, expiry_date date, verification_status text, effective_status text, verified_at timestamp with time zone, remarks text, uploaded_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT d.student_document_id::bigint, t.document_name::text, t.requires_verification, f.original_file_name::text, f.mime_type::text, f.file_size_bytes::bigint, d.document_number::text,
           d.issue_date, d.expiry_date, d.verification_status::text,
           CASE WHEN d.verification_status = 'VERIFIED' AND d.expiry_date < CURRENT_DATE THEN 'EXPIRED' ELSE d.verification_status END::text,
           d.verified_at, d.remarks::text, f.uploaded_at
    FROM student_document d JOIN document_type t ON t.document_type_id = d.document_type_id JOIN file_object f ON f.file_object_id = d.file_object_id
    WHERE d.student_id = p_student_id AND f.deleted_at IS NULL
      AND (COALESCE(p_student_id = sims_private.current_student_id(), false) OR sims_private.can_student(ARRAY['DOCUMENT.ALL.READ']::text[], p_student_id, false))
    ORDER BY f.uploaded_at DESC, d.student_document_id DESC
$function$;

CREATE OR REPLACE FUNCTION public.svc_my_terms()
 RETURNS TABLE(academic_term_id bigint, term_name text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT DISTINCT t.academic_term_id::bigint, t.term_name::text FROM student_term_registration tr JOIN student_programme_enrolment e ON e.enrolment_id = tr.enrolment_id
    JOIN programme_term_offering o ON o.programme_term_offering_id = tr.programme_term_offering_id JOIN academic_term t ON t.academic_term_id = o.academic_term_id
    WHERE e.student_id = sims_private.current_student_id() AND tr.registration_status IN ('REGISTERED', 'APPROVED') ORDER BY 2
$function$;

CREATE OR REPLACE FUNCTION public.svc_request_list(p_kind text DEFAULT NULL::text, p_status text DEFAULT NULL::text)
 RETURNS TABLE(service_request_id bigint, request_number text, request_kind text, student_id bigint, student_number text, student_name text, term_name text, planned_date date, detail text, request_status text, decision_remarks text, reference_number text, created_at timestamp with time zone, can_decide boolean, can_cancel boolean, hold_blocked boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT r.service_request_id::bigint, r.request_number, r.request_kind, r.student_id::bigint, s.student_number::text, s.display_name::text, t.term_name::text, r.planned_date, r.detail, r.request_status, r.decision_remarks, r.reference_number, r.created_at,
           r.request_status IN ('SUBMITTED', 'APPROVED') AND COALESCE(sims_private.can_student(ARRAY['DOCUMENT.ALL.APPROVE']::text[], r.student_id, true), false),
           r.request_status = 'SUBMITTED' AND (sims_private.is_me_student(r.student_id) OR COALESCE(sims_private.can_student(ARRAY['DOCUMENT.ALL.UPDATE']::text[], r.student_id, true), false)),
           sims_private.fin_hold_active(r.student_id, r.request_kind)
    FROM sims_private.student_service_request r JOIN student s ON s.student_id = r.student_id LEFT JOIN academic_term t ON t.academic_term_id = r.academic_term_id
    WHERE (p_kind IS NULL OR r.request_kind = p_kind) AND (p_status IS NULL OR r.request_status = p_status)
      AND (sims_private.is_me_student(r.student_id) OR COALESCE(sims_private.can_student(ARRAY['DOCUMENT.ALL.READ']::text[], r.student_id, false), false))
    ORDER BY r.created_at DESC, r.service_request_id DESC LIMIT 200
$function$;

CREATE OR REPLACE FUNCTION public.timetable_assignments(p_cos_id bigint)
 RETURNS TABLE(faculty_assignment_id bigint, employee_name text, assignment_role text, assignment_status text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    PERFORM sims_private.att_authorize_cos(p_cos_id, 'TIMETABLE', 'READ');
    RETURN QUERY
    SELECT fa.faculty_assignment_id::bigint, e.display_name::text, fa.assignment_role::text, fa.assignment_status::text
    FROM faculty_course_assignment fa JOIN employee e ON e.employee_id = fa.employee_id
    WHERE fa.course_offering_section_id = p_cos_id ORDER BY e.display_name, fa.faculty_assignment_id;
END $function$;

CREATE OR REPLACE FUNCTION public.timetable_entries(p_pto bigint)
 RETURNS TABLE(timetable_session_id bigint, course_offering_section_id bigint, course_label text, section_code text, batch_code text, session_type text, instructor_name text, day_of_week integer, time_slot_id integer, slot_code text, start_time time without time zone, end_time time without time zone, room_id bigint, room_label text, effective_from date, effective_to date)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF NOT sims_private.tt_can_read_pto(p_pto) THEN RAISE EXCEPTION 'Not authorised (TIMETABLE.ALL.READ) or unknown offering' USING ERRCODE = '42501'; END IF;
    RETURN QUERY
    SELECT t.timetable_session_id::bigint, cos.course_offering_section_id::bigint, (c.course_code || ' — ' || c.course_title)::text, cs.section_code::text, b.batch_code::text, cos.session_type::text,
           e.display_name::text, t.day_of_week::integer, t.time_slot_id::integer, s.slot_code::text, s.start_time, s.end_time, t.room_id::bigint,
           (bl.building_code || '-' || r.room_code)::text, t.effective_from, t.effective_to
    FROM timetable_session t
    JOIN course_offering_section cos ON cos.course_offering_section_id = t.course_offering_section_id
    JOIN course_offering co ON co.course_offering_id = cos.course_offering_id
    JOIN course_catalog c ON c.course_id = co.course_id
    JOIN class_section cs ON cs.class_section_id = cos.class_section_id
    LEFT JOIN class_batch b ON b.class_batch_id = cos.class_batch_id
    JOIN time_slot s ON s.time_slot_id = t.time_slot_id
    LEFT JOIN room r ON r.room_id = t.room_id
    LEFT JOIN building bl ON bl.building_id = r.building_id
    LEFT JOIN faculty_course_assignment fa ON fa.faculty_assignment_id = t.faculty_assignment_id
    LEFT JOIN employee e ON e.employee_id = fa.employee_id
    WHERE cos.programme_term_offering_id = p_pto
    ORDER BY t.day_of_week, s.start_time, c.course_code, cs.section_code;
END $function$;

CREATE OR REPLACE FUNCTION public.timetable_offering_info(p_pto bigint)
 RETURNS TABLE(programme_term_offering_id bigint, term_name text, programme_name text, semester_name text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF NOT sims_private.tt_can_read_pto(p_pto) THEN RAISE EXCEPTION 'Not authorised (TIMETABLE.ALL.READ) or unknown offering' USING ERRCODE = '42501'; END IF;
    RETURN QUERY SELECT pto.programme_term_offering_id::bigint, t.term_name::text, p.programme_name::text, s.semester_name::text
    FROM programme_term_offering pto JOIN academic_term t ON t.academic_term_id = pto.academic_term_id JOIN programme p ON p.programme_id = pto.programme_id JOIN semester s ON s.semester_id = pto.semester_id
    WHERE pto.programme_term_offering_id = p_pto;
END $function$;

CREATE OR REPLACE FUNCTION public.timetable_offerings(p_term bigint DEFAULT NULL::bigint, p_programme integer DEFAULT NULL::integer, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS TABLE(programme_term_offering_id bigint, term_name text, programme_name text, semester_name text, section_count bigint, entry_count bigint, total_count bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    WITH visible AS (
        SELECT pto.programme_term_offering_id, t.term_name::text, p.programme_name::text, s.semester_name::text,
               (SELECT count(*) FROM course_offering_section c WHERE c.programme_term_offering_id = pto.programme_term_offering_id) AS section_count,
               (SELECT count(*) FROM timetable_session x JOIN course_offering_section c ON c.course_offering_section_id = x.course_offering_section_id WHERE c.programme_term_offering_id = pto.programme_term_offering_id) AS entry_count
        FROM programme_term_offering pto
        JOIN academic_term t ON t.academic_term_id = pto.academic_term_id
        JOIN programme p ON p.programme_id = pto.programme_id
        JOIN semester s ON s.semester_id = pto.semester_id
        WHERE (p_term IS NULL OR pto.academic_term_id = p_term) AND (p_programme IS NULL OR pto.programme_id = p_programme)
          AND sims_private.can_programme(ARRAY['TIMETABLE.ALL.READ']::text[], pto.programme_id)
    )
    SELECT v.programme_term_offering_id, v.term_name, v.programme_name, v.semester_name, v.section_count, v.entry_count, count(*) OVER ()
    FROM visible v ORDER BY v.programme_term_offering_id DESC LIMIT LEAST(GREATEST(p_limit, 1), 200) OFFSET GREATEST(p_offset, 0)
$function$;

CREATE OR REPLACE FUNCTION public.timetable_rooms()
 RETURNS TABLE(room_id bigint, campus_id integer, campus_name text, room_label text, room_type text, capacity integer, is_active boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT r.room_id::bigint, b.campus_id::integer, c.campus_name::text, (b.building_code || '-' || r.room_code)::text, r.room_type::text, r.capacity::integer, r.is_active
    FROM room r JOIN building b ON b.building_id = r.building_id JOIN campus c ON c.campus_id = b.campus_id
    WHERE sims_private.can_campus(ARRAY['TIMETABLE.ALL.READ']::text[], b.campus_id)
    ORDER BY c.campus_name, b.building_code, r.room_code
$function$;

CREATE OR REPLACE FUNCTION public.timetable_sections(p_pto bigint)
 RETURNS TABLE(course_offering_section_id bigint, course_label text, section_code text, batch_code text, session_type text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF NOT sims_private.tt_can_read_pto(p_pto) THEN RAISE EXCEPTION 'Not authorised (TIMETABLE.ALL.READ) or unknown offering' USING ERRCODE = '42501'; END IF;
    RETURN QUERY
    SELECT cos.course_offering_section_id::bigint, (c.course_code || ' — ' || c.course_title)::text, cs.section_code::text, b.batch_code::text, cos.session_type::text
    FROM course_offering_section cos
    JOIN course_offering co ON co.course_offering_id = cos.course_offering_id
    JOIN course_catalog c ON c.course_id = co.course_id
    JOIN class_section cs ON cs.class_section_id = cos.class_section_id
    LEFT JOIN class_batch b ON b.class_batch_id = cos.class_batch_id
    WHERE cos.programme_term_offering_id = p_pto
    ORDER BY c.course_code, cs.section_code, b.batch_code NULLS FIRST, cos.session_type;
END $function$;

CREATE OR REPLACE FUNCTION public.timetable_slots()
 RETURNS TABLE(time_slot_id integer, campus_id integer, campus_name text, slot_code text, start_time time without time zone, end_time time without time zone, is_break boolean, is_active boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT s.time_slot_id::integer, s.campus_id::integer, c.campus_name::text, s.slot_code::text, s.start_time, s.end_time, s.is_break, s.is_active
    FROM time_slot s JOIN campus c ON c.campus_id = s.campus_id
    WHERE sims_private.can_campus(ARRAY['TIMETABLE.ALL.READ']::text[], s.campus_id)
    ORDER BY c.campus_name, s.start_time
$function$;

CREATE OR REPLACE FUNCTION public.iam_link_auth_user(p_email text, p_student_number text DEFAULT NULL::text, p_employee_number text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_email text := lower(btrim(COALESCE(p_email, ''))); v_auth uuid;
BEGIN
    IF NOT sims_private.can_global(ARRAY['IAM.ALL.CREATE']::text[]) THEN RAISE EXCEPTION 'Not authorised (IAM.ALL.CREATE)' USING ERRCODE = '42501'; END IF;
    IF v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' OR length(v_email) > 254 THEN RAISE EXCEPTION 'A valid email address is required' USING ERRCODE = '22023'; END IF;
    SELECT id INTO v_auth FROM auth.users WHERE lower(email) = v_email LIMIT 1;
    IF v_auth IS NULL THEN RAISE EXCEPTION 'No sign-in account with that email exists yet: create it in the Authentication dashboard first' USING ERRCODE = '22023'; END IF;
    IF EXISTS (SELECT 1 FROM sims_private.auth_identity_map WHERE auth_user_id = v_auth) THEN RAISE EXCEPTION 'That sign-in account is already linked' USING ERRCODE = '23505'; END IF;
    RETURN public.iam_provision_user(v_auth, v_email, p_student_number, p_employee_number, sims_private.current_user_id());
END $function$;
