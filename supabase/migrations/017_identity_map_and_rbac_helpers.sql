-- =============================================================================================
-- 017. identity_map_and_rbac_helpers
-- ---------------------------------------------------------------------------------------------
-- GENERATED FILE - do not edit by hand.
-- Regenerate with: npm run migrate:build   (python tools/translate.py && python tools/build_migrations.py)
--
-- Source of truth: the live Supabase catalogue (tools/catalogue/live_catalogue.json),
-- dumped read-only from project khqqfgqvwdxlqkncwtmh by tools/dump_catalogue.py.
-- =============================================================================================

-- -----------------------------------------------------------------------------
-- The `sims_private` schema and the helper functions.
--
-- `sims_private` holds the identity map, the MFA tables and the authorisation
-- helpers (`can_global`, `can_programme`, `current_user_id`, ...).  It is NOT
-- part of the Data API surface (see supabase/config.toml), but the RLS
-- policies call into it, so `authenticated` needs USAGE on the schema and
-- EXECUTE on the helpers - exactly as in the live database.
--
-- The public trigger helpers (`sims_guard_*`, `sims_touch_updated_at`, ...)
-- live here as well because the triggers in 020 depend on them.
-- -----------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS sims_private;

CREATE OR REPLACE FUNCTION public.sims_assessment_event_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.status = 'PUBLISHED' AND OLD.status <> 'PUBLISHED' AND OLD.status <> 'CONDUCTED' THEN
        RAISE EXCEPTION 'An event can be published only after it is CONDUCTED (status is %)', OLD.status USING ERRCODE = '45000';
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.status = 'PUBLISHED' AND NEW.status = 'PUBLISHED'
       AND (NEW.maximum_marks IS DISTINCT FROM OLD.maximum_marks OR NEW.reduced_maximum_marks IS DISTINCT FROM OLD.reduced_maximum_marks) THEN
        RAISE EXCEPTION 'The maximum marks of a PUBLISHED event are locked' USING ERRCODE = '45000';
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_assessment_mark_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_ev record; v_event_id bigint := COALESCE(NEW.assessment_event_id, OLD.assessment_event_id);
BEGIN
    SELECT status, maximum_marks, reduced_maximum_marks INTO v_ev FROM assessment_event WHERE assessment_event_id = v_event_id;
    IF v_ev IS NULL THEN RETURN COALESCE(NEW, OLD); END IF;
    IF v_ev.status IN ('PUBLISHED', 'CANCELLED') THEN
        RAISE EXCEPTION 'Marks of a % assessment event are locked', v_ev.status USING ERRCODE = '45000';
    END IF;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    IF NEW.attendance_status <> 'PRESENT' AND (NEW.marks_obtained IS NOT NULL OR NEW.reduced_marks IS NOT NULL) THEN
        RAISE EXCEPTION 'A % entry cannot carry marks', NEW.attendance_status USING ERRCODE = '45000';
    END IF;
    IF NEW.marks_obtained IS NOT NULL AND NEW.marks_obtained > v_ev.maximum_marks THEN
        RAISE EXCEPTION 'Marks (%) exceed the event maximum (%)', NEW.marks_obtained, v_ev.maximum_marks USING ERRCODE = '45000';
    END IF;
    IF NEW.reduced_marks IS NOT NULL AND (v_ev.reduced_maximum_marks IS NULL OR NEW.reduced_marks > v_ev.reduced_maximum_marks) THEN
        RAISE EXCEPTION 'Reduced marks (%) exceed the reduced maximum (%)', NEW.reduced_marks, COALESCE(v_ev.reduced_maximum_marks::text, 'not set') USING ERRCODE = '45000';
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_attendance_session_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_cos bigint;
BEGIN
    IF NEW.faculty_assignment_id IS NOT NULL THEN
        SELECT course_offering_section_id INTO v_cos FROM faculty_course_assignment WHERE faculty_assignment_id = NEW.faculty_assignment_id;
        IF v_cos IS NOT NULL AND v_cos <> NEW.course_offering_section_id THEN
            RAISE EXCEPTION 'The instructor assignment belongs to a different teaching section' USING ERRCODE = '45000';
        END IF;
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_fee_benefit_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_original numeric(12,2);
    v_existing numeric(12,2);
    v_self bigint := CASE WHEN TG_OP = 'UPDATE' THEN OLD.assessment_benefit_id ELSE NULL END;
BEGIN
    SELECT original_amount INTO v_original FROM student_fee_assessment_item WHERE assessment_item_id = NEW.assessment_item_id FOR UPDATE;
    SELECT COALESCE(SUM(benefit_amount),0) INTO v_existing FROM fee_assessment_benefit
      WHERE assessment_item_id = NEW.assessment_item_id AND (v_self IS NULL OR assessment_benefit_id <> v_self);
    IF v_existing + NEW.benefit_amount > v_original THEN
        RAISE EXCEPTION 'Benefits exceed original assessment item amount' USING ERRCODE = '45000';
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_fee_refund_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_approved numeric(12,2);
    v_request_status text;
    v_payment_id bigint;
    v_payment_amount numeric(12,2);
    v_request_refunded numeric(12,2);
    v_payment_refunded numeric(12,2);
    v_self bigint := CASE WHEN TG_OP = 'UPDATE' THEN OLD.fee_refund_id ELSE NULL END;
BEGIN
    SELECT approved_amount, request_status, payment_transaction_id INTO v_approved, v_request_status, v_payment_id
      FROM refund_request WHERE refund_request_id = NEW.refund_request_id FOR UPDATE;
    IF v_approved IS NULL OR v_request_status NOT IN ('APPROVED','PROCESSED') THEN
        RAISE EXCEPTION 'Refund request must be approved' USING ERRCODE = '45000';
    END IF;
    SELECT COALESCE(SUM(refund_amount),0) INTO v_request_refunded FROM fee_refund
      WHERE refund_request_id = NEW.refund_request_id AND refund_status = 'SUCCESS'
        AND (v_self IS NULL OR fee_refund_id <> v_self);
    IF NEW.refund_status = 'SUCCESS' AND v_request_refunded + NEW.refund_amount > v_approved THEN
        RAISE EXCEPTION 'Refund exceeds approved amount' USING ERRCODE = '45000';
    END IF;
    IF v_payment_id IS NOT NULL AND NEW.refund_status = 'SUCCESS' THEN
        SELECT amount INTO v_payment_amount FROM payment_transaction WHERE payment_transaction_id = v_payment_id FOR UPDATE;
        SELECT COALESCE(SUM(fr.refund_amount),0) INTO v_payment_refunded
          FROM fee_refund fr JOIN refund_request rr ON rr.refund_request_id = fr.refund_request_id
          WHERE rr.payment_transaction_id = v_payment_id AND fr.refund_status = 'SUCCESS'
            AND (v_self IS NULL OR fr.fee_refund_id <> v_self);
        IF v_payment_refunded + NEW.refund_amount > v_payment_amount THEN
            RAISE EXCEPTION 'Cumulative refund exceeds payment amount' USING ERRCODE = '45000';
        END IF;
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_feedback_cycle_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_q record; v_items integer;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF OLD.status <> NEW.status AND NOT (
               (OLD.status = 'SCHEDULED' AND NEW.status IN ('OPEN', 'CANCELLED')) OR (OLD.status = 'OPEN' AND NEW.status IN ('CLOSED', 'CANCELLED'))) THEN
            RAISE EXCEPTION 'A % feedback cycle cannot become %', OLD.status, NEW.status USING ERRCODE = '45000';
        END IF;
        IF OLD.status IN ('CLOSED', 'CANCELLED') AND (NEW.questionnaire_id, NEW.academic_term_id, NEW.start_at, NEW.end_at) IS DISTINCT FROM (OLD.questionnaire_id, OLD.academic_term_id, OLD.start_at, OLD.end_at) THEN
            RAISE EXCEPTION 'A % feedback cycle cannot be changed', OLD.status USING ERRCODE = '45000';
        END IF;
        IF OLD.status <> 'SCHEDULED' AND NEW.questionnaire_id <> OLD.questionnaire_id THEN
            RAISE EXCEPTION 'The questionnaire of a cycle that has opened cannot be changed' USING ERRCODE = '45000';
        END IF;
        IF EXISTS (SELECT 1 FROM feedback_response WHERE feedback_cycle_id = OLD.feedback_cycle_id) AND NEW.academic_term_id <> OLD.academic_term_id THEN
            RAISE EXCEPTION 'The term of a cycle with responses cannot be changed' USING ERRCODE = '45000';
        END IF;
    END IF;
    IF NEW.status = 'OPEN' AND (TG_OP = 'INSERT' OR OLD.status <> 'OPEN') THEN
        SELECT status INTO v_q FROM feedback_questionnaire WHERE questionnaire_id = NEW.questionnaire_id;
        SELECT count(*) INTO v_items FROM feedback_questionnaire_item WHERE questionnaire_id = NEW.questionnaire_id;
        IF v_q.status IS DISTINCT FROM 'ACTIVE' THEN RAISE EXCEPTION 'Only a cycle with an ACTIVE questionnaire can be opened' USING ERRCODE = '45000'; END IF;
        IF v_items = 0 THEN RAISE EXCEPTION 'The questionnaire has no questions' USING ERRCODE = '45000'; END IF;
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_payment_allocation_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_payment_amount numeric(12,2);
    v_status text;
    v_payment_account bigint;
    v_payment_application bigint;
    v_item_net numeric(12,2);
    v_assessment_account bigint;
    v_assessment_application bigint;
    v_existing_payment numeric(12,2);
    v_existing_item numeric(12,2);
    v_self bigint := CASE WHEN TG_OP = 'UPDATE' THEN OLD.payment_allocation_id ELSE NULL END;
BEGIN
    SELECT amount, payment_status, student_account_id, application_id
      INTO v_payment_amount, v_status, v_payment_account, v_payment_application
      FROM payment_transaction WHERE payment_transaction_id = NEW.payment_transaction_id FOR UPDATE;
    IF v_status <> 'SUCCESS' THEN
        RAISE EXCEPTION 'Only SUCCESS payments can be allocated' USING ERRCODE = '45000';
    END IF;
    SELECT i.net_amount, a.student_account_id, a.application_id
      INTO v_item_net, v_assessment_account, v_assessment_application
      FROM student_fee_assessment_item i JOIN student_fee_assessment a ON a.fee_assessment_id = i.fee_assessment_id
      WHERE i.assessment_item_id = NEW.assessment_item_id FOR UPDATE;
    IF NOT ((v_payment_account IS NOT NULL AND v_payment_account IS NOT DISTINCT FROM v_assessment_account)
            OR (v_payment_application IS NOT NULL AND v_payment_application IS NOT DISTINCT FROM v_assessment_application)) THEN
        RAISE EXCEPTION 'Payment and assessment contexts do not match' USING ERRCODE = '45000';
    END IF;
    SELECT COALESCE(SUM(allocated_amount),0) INTO v_existing_payment FROM payment_allocation
      WHERE payment_transaction_id = NEW.payment_transaction_id
        AND (v_self IS NULL OR payment_allocation_id <> v_self);
    IF v_existing_payment + NEW.allocated_amount > v_payment_amount THEN
        RAISE EXCEPTION 'Allocation exceeds payment amount' USING ERRCODE = '45000';
    END IF;
    SELECT COALESCE(SUM(allocated_amount),0) INTO v_existing_item FROM payment_allocation
      WHERE assessment_item_id = NEW.assessment_item_id
        AND (v_self IS NULL OR payment_allocation_id <> v_self);
    IF v_existing_item + NEW.allocated_amount > v_item_net THEN
        RAISE EXCEPTION 'Allocation exceeds assessment item net amount' USING ERRCODE = '45000';
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_recalc_fee_item_paid(p_item_id bigint)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'public', 'pg_temp'
AS $function$
    UPDATE student_fee_assessment_item i
    SET amount_paid     = (SELECT COALESCE(SUM(pa.allocated_amount),0) FROM payment_allocation pa WHERE pa.assessment_item_id = p_item_id),
        balance_amount  = net_amount - (SELECT COALESCE(SUM(pa.allocated_amount),0) FROM payment_allocation pa WHERE pa.assessment_item_id = p_item_id)
    WHERE i.assessment_item_id = p_item_id;
$function$;

CREATE OR REPLACE FUNCTION public.sims_registration_course_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_term record; v_off record; v_used integer;
BEGIN
    SELECT programme_term_offering_id, registration_status INTO v_term FROM student_term_registration WHERE term_registration_id = NEW.term_registration_id;
    SELECT programme_term_offering_id, registration_capacity, status INTO v_off FROM course_offering WHERE course_offering_id = NEW.course_offering_id;
    IF v_term IS NULL OR v_off IS NULL THEN RETURN NEW; END IF;

    IF v_term.programme_term_offering_id <> v_off.programme_term_offering_id THEN
        RAISE EXCEPTION 'The course offering does not belong to the same programme term as the student''s registration' USING ERRCODE = '45000';
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF v_term.registration_status IN ('CANCELLED', 'COMPLETED') THEN
            RAISE EXCEPTION 'The term registration is %; courses cannot be added', v_term.registration_status USING ERRCODE = '45000';
        END IF;
        IF v_off.status IN ('COMPLETED', 'CANCELLED') THEN
            RAISE EXCEPTION 'This course offering is % and no longer accepts registrations', v_off.status USING ERRCODE = '45000';
        END IF;
    END IF;

    IF v_off.registration_capacity IS NOT NULL AND NEW.registration_status IN ('REGISTERED', 'APPROVED', 'COMPLETED')
       AND (TG_OP = 'INSERT' OR OLD.registration_status IN ('DROPPED', 'WITHDRAWN') OR NEW.course_offering_id IS DISTINCT FROM OLD.course_offering_id) THEN
        PERFORM 1 FROM course_offering WHERE course_offering_id = NEW.course_offering_id FOR UPDATE;  -- serialise concurrent registrations
        SELECT count(*) INTO v_used FROM student_course_registration
         WHERE course_offering_id = NEW.course_offering_id AND registration_status IN ('REGISTERED', 'APPROVED', 'COMPLETED')
           AND (TG_OP = 'INSERT' OR course_registration_id <> NEW.course_registration_id);
        IF v_used >= v_off.registration_capacity THEN
            RAISE EXCEPTION 'The course offering is full (capacity %)', v_off.registration_capacity USING ERRCODE = '45000';
        END IF;
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_registration_term_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_off record; v_enr record; v_cap integer; v_used integer;
BEGIN
    SELECT programme_id, specialization_id, status INTO v_off FROM programme_term_offering WHERE programme_term_offering_id = NEW.programme_term_offering_id;
    SELECT programme_id, specialization_id, enrolment_status INTO v_enr FROM student_programme_enrolment WHERE enrolment_id = NEW.enrolment_id;
    IF v_off IS NULL OR v_enr IS NULL THEN RETURN NEW; END IF;  -- foreign keys report missing parents

    IF v_enr.programme_id <> v_off.programme_id THEN
        RAISE EXCEPTION 'The student is enrolled in a different programme than this offering' USING ERRCODE = '45000';
    END IF;
    IF v_off.specialization_id IS NOT NULL AND v_enr.specialization_id IS DISTINCT FROM v_off.specialization_id THEN
        RAISE EXCEPTION 'The student is not in the specialisation this offering is for' USING ERRCODE = '45000';
    END IF;

    IF TG_OP = 'INSERT' THEN
        IF v_off.status IN ('COMPLETED', 'CANCELLED') THEN
            RAISE EXCEPTION 'This offering is % and no longer accepts registrations', v_off.status USING ERRCODE = '45000';
        END IF;
        IF v_enr.enrolment_status <> 'ACTIVE' THEN
            RAISE EXCEPTION 'Only students with an ACTIVE enrolment can register (enrolment is %)', v_enr.enrolment_status USING ERRCODE = '45000';
        END IF;
    END IF;

    IF NEW.class_section_id IS NOT NULL AND NEW.registration_status <> 'CANCELLED'
       AND (TG_OP = 'INSERT' OR NEW.class_section_id IS DISTINCT FROM OLD.class_section_id OR OLD.registration_status = 'CANCELLED') THEN
        SELECT capacity INTO v_cap FROM class_section WHERE class_section_id = NEW.class_section_id FOR UPDATE;
        IF v_cap IS NOT NULL THEN
            SELECT count(*) INTO v_used FROM student_term_registration
             WHERE class_section_id = NEW.class_section_id AND registration_status <> 'CANCELLED'
               AND (TG_OP = 'INSERT' OR term_registration_id <> NEW.term_registration_id);
            IF v_used >= v_cap THEN RAISE EXCEPTION 'The section is full (capacity %)', v_cap USING ERRCODE = '45000'; END IF;
        END IF;
    END IF;
    IF NEW.class_batch_id IS NOT NULL AND NEW.registration_status <> 'CANCELLED'
       AND (TG_OP = 'INSERT' OR NEW.class_batch_id IS DISTINCT FROM OLD.class_batch_id OR OLD.registration_status = 'CANCELLED') THEN
        SELECT capacity INTO v_cap FROM class_batch WHERE class_batch_id = NEW.class_batch_id FOR UPDATE;
        IF v_cap IS NOT NULL THEN
            SELECT count(*) INTO v_used FROM student_term_registration
             WHERE class_batch_id = NEW.class_batch_id AND registration_status <> 'CANCELLED'
               AND (TG_OP = 'INSERT' OR term_registration_id <> NEW.term_registration_id);
            IF v_used >= v_cap THEN RAISE EXCEPTION 'The batch is full (capacity %)', v_cap USING ERRCODE = '45000'; END IF;
        END IF;
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_sync_fee_assessment_totals(p_assessment_id bigint)
 RETURNS void
 LANGUAGE sql
 SET search_path TO 'public', 'pg_temp'
AS $function$
    UPDATE student_fee_assessment a
    SET gross_amount        = (SELECT COALESCE(SUM(i.original_amount),0)   FROM student_fee_assessment_item i WHERE i.fee_assessment_id = p_assessment_id),
        concession_amount   = (SELECT COALESCE(SUM(i.concession_amount),0) FROM student_fee_assessment_item i WHERE i.fee_assessment_id = p_assessment_id),
        scholarship_amount  = (SELECT COALESCE(SUM(i.scholarship_amount),0) FROM student_fee_assessment_item i WHERE i.fee_assessment_id = p_assessment_id),
        adjustment_amount   = (SELECT COALESCE(SUM(i.adjustment_amount),0) FROM student_fee_assessment_item i WHERE i.fee_assessment_id = p_assessment_id),
        net_payable_amount  = (SELECT COALESCE(SUM(i.net_amount),0)        FROM student_fee_assessment_item i WHERE i.fee_assessment_id = p_assessment_id),
        amount_paid         = (SELECT COALESCE(SUM(i.amount_paid),0)       FROM student_fee_assessment_item i WHERE i.fee_assessment_id = p_assessment_id),
        balance_amount      = (SELECT COALESCE(SUM(i.balance_amount),0)    FROM student_fee_assessment_item i WHERE i.fee_assessment_id = p_assessment_id)
    WHERE a.fee_assessment_id = p_assessment_id;
$function$;

CREATE OR REPLACE FUNCTION public.sims_term_result_lock()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.published_at IS NOT NULL THEN RAISE EXCEPTION 'A published term result cannot be deleted' USING ERRCODE = '45000'; END IF;
        RETURN OLD;
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.published_at IS NOT NULL AND NEW.published_at IS NOT NULL
       AND (NEW.credits_registered, NEW.credits_earned, NEW.sgpa, NEW.cgpa, NEW.result_status) IS DISTINCT FROM (OLD.credits_registered, OLD.credits_earned, OLD.sgpa, OLD.cgpa, OLD.result_status) THEN
        RAISE EXCEPTION 'The term result is published; unpublish it before recomputing' USING ERRCODE = '45000';
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_timetable_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_slot record; v_room record; v_fa record; v_emp bigint; v_to date := COALESCE(NEW.effective_to, 'infinity'::date);
BEGIN
    IF NEW.effective_to IS NOT NULL AND NEW.effective_to < NEW.effective_from THEN
        RAISE EXCEPTION 'The end date cannot be before the start date' USING ERRCODE = '45000';
    END IF;

    SELECT campus_id, start_time, end_time, is_break, is_active INTO v_slot FROM time_slot WHERE time_slot_id = NEW.time_slot_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Unknown time slot' USING ERRCODE = '23503'; END IF;
    IF v_slot.is_break THEN RAISE EXCEPTION 'A break slot cannot hold a class' USING ERRCODE = '45000'; END IF;
    IF NOT v_slot.is_active THEN RAISE EXCEPTION 'The time slot is inactive' USING ERRCODE = '45000'; END IF;

    IF NEW.room_id IS NOT NULL THEN
        SELECT b.campus_id, r.is_active INTO v_room FROM room r JOIN building b ON b.building_id = r.building_id WHERE r.room_id = NEW.room_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'Unknown room' USING ERRCODE = '23503'; END IF;
        IF NOT v_room.is_active THEN RAISE EXCEPTION 'The room is inactive' USING ERRCODE = '45000'; END IF;
        IF v_room.campus_id <> v_slot.campus_id THEN RAISE EXCEPTION 'The room is on a different campus from the time slot' USING ERRCODE = '45000'; END IF;
    END IF;

    IF NEW.faculty_assignment_id IS NOT NULL THEN
        SELECT course_offering_section_id, employee_id, assignment_status INTO v_fa FROM faculty_course_assignment WHERE faculty_assignment_id = NEW.faculty_assignment_id;
        IF NOT FOUND THEN RAISE EXCEPTION 'Unknown instructor assignment' USING ERRCODE = '23503'; END IF;
        IF v_fa.course_offering_section_id <> NEW.course_offering_section_id THEN
            RAISE EXCEPTION 'The instructor assignment belongs to a different teaching section' USING ERRCODE = '45000';
        END IF;
        IF v_fa.assignment_status <> 'ACTIVE' THEN RAISE EXCEPTION 'The instructor assignment is not ACTIVE' USING ERRCODE = '45000'; END IF;
        v_emp := v_fa.employee_id;
    END IF;

    -- Fixed lock order (room, instructor, section) so concurrent writers cannot deadlock.
    IF NEW.room_id IS NOT NULL THEN PERFORM pg_advisory_xact_lock(hashtextextended('tt:room:' || NEW.room_id, 0)); END IF;
    IF v_emp IS NOT NULL THEN PERFORM pg_advisory_xact_lock(hashtextextended('tt:emp:' || v_emp, 0)); END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended('tt:cos:' || NEW.course_offering_section_id, 0));

    IF NEW.room_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM timetable_session t JOIN time_slot s ON s.time_slot_id = t.time_slot_id
        WHERE t.room_id = NEW.room_id AND t.day_of_week = NEW.day_of_week AND t.timetable_session_id IS DISTINCT FROM NEW.timetable_session_id
          AND t.effective_from <= v_to AND COALESCE(t.effective_to, 'infinity'::date) >= NEW.effective_from
          AND s.start_time < v_slot.end_time AND s.end_time > v_slot.start_time) THEN
        RAISE EXCEPTION 'The room is already booked at that time' USING ERRCODE = '45000';
    END IF;

    IF v_emp IS NOT NULL AND EXISTS (
        SELECT 1 FROM timetable_session t JOIN time_slot s ON s.time_slot_id = t.time_slot_id
        JOIN faculty_course_assignment fa ON fa.faculty_assignment_id = t.faculty_assignment_id
        WHERE fa.employee_id = v_emp AND t.day_of_week = NEW.day_of_week AND t.timetable_session_id IS DISTINCT FROM NEW.timetable_session_id
          AND t.effective_from <= v_to AND COALESCE(t.effective_to, 'infinity'::date) >= NEW.effective_from
          AND s.start_time < v_slot.end_time AND s.end_time > v_slot.start_time) THEN
        RAISE EXCEPTION 'The instructor already teaches at that time' USING ERRCODE = '45000';
    END IF;

    IF EXISTS (
        SELECT 1 FROM timetable_session t JOIN time_slot s ON s.time_slot_id = t.time_slot_id
        WHERE t.course_offering_section_id = NEW.course_offering_section_id AND t.day_of_week = NEW.day_of_week AND t.timetable_session_id IS DISTINCT FROM NEW.timetable_session_id
          AND t.effective_from <= v_to AND COALESCE(t.effective_to, 'infinity'::date) >= NEW.effective_from
          AND s.start_time < v_slot.end_time AND s.end_time > v_slot.start_time) THEN
        RAISE EXCEPTION 'This teaching section already has a class at that time' USING ERRCODE = '45000';
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_touch_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    -- MySQL ON UPDATE only bumps the column when the row actually changed.
    IF NEW IS DISTINCT FROM OLD THEN
        NEW.updated_at := CURRENT_TIMESTAMP;
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_user_permission_override_scope()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF NEW.scope_type = 'INSTITUTION' AND NOT EXISTS (SELECT 1 FROM institution WHERE institution_id = NEW.scope_entity_id) THEN
        RAISE EXCEPTION 'Invalid institution scope_entity_id' USING ERRCODE = '45000';
    ELSIF NEW.scope_type = 'CAMPUS' AND NOT EXISTS (SELECT 1 FROM campus WHERE campus_id = NEW.scope_entity_id) THEN
        RAISE EXCEPTION 'Invalid campus scope_entity_id' USING ERRCODE = '45000';
    ELSIF NEW.scope_type = 'DEPARTMENT' AND NOT EXISTS (SELECT 1 FROM department WHERE department_id = NEW.scope_entity_id) THEN
        RAISE EXCEPTION 'Invalid department scope_entity_id' USING ERRCODE = '45000';
    ELSIF NEW.scope_type = 'PROGRAMME' AND NOT EXISTS (SELECT 1 FROM programme WHERE programme_id = NEW.scope_entity_id) THEN
        RAISE EXCEPTION 'Invalid programme scope_entity_id' USING ERRCODE = '45000';
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_user_role_assignment_scope()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_role_level text;
BEGIN
    SELECT role_level INTO v_role_level FROM role WHERE role_id = NEW.role_id;
    IF v_role_level <> NEW.scope_type THEN
        RAISE EXCEPTION 'Role level must match assignment scope_type' USING ERRCODE = '45000';
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.admission_action_for(p_to text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE p_to
        WHEN 'SUBMITTED' THEN 'UPDATE' WHEN 'UNDER_REVIEW' THEN 'UPDATE' WHEN 'CANCELLED' THEN 'UPDATE'
        WHEN 'ELIGIBLE' THEN 'VERIFY' WHEN 'INELIGIBLE' THEN 'VERIFY'
        WHEN 'SELECTED' THEN 'APPROVE' WHEN 'WAITLISTED' THEN 'APPROVE' WHEN 'REJECTED' THEN 'APPROVE'
    END
$function$;

CREATE OR REPLACE FUNCTION sims_private.announcement_check(p_type integer, p_department integer, p_title text, p_description text, p_from timestamp with time zone, p_to timestamp with time zone, p_audience text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF p_title IS NULL OR btrim(p_title) = '' OR length(btrim(p_title)) > 250 THEN RAISE EXCEPTION 'The title is required (at most 250 characters)' USING ERRCODE = '22023'; END IF;
    IF p_description IS NULL OR btrim(p_description) = '' OR length(p_description) > 20000 THEN RAISE EXCEPTION 'The text is required (at most 20000 characters)' USING ERRCODE = '22023'; END IF;
    IF p_audience NOT IN ('ALL', 'STUDENTS', 'STAFF', 'DEPARTMENT') THEN RAISE EXCEPTION 'The audience must be ALL, STUDENTS, STAFF or DEPARTMENT' USING ERRCODE = '22023'; END IF;
    IF p_audience = 'DEPARTMENT' AND p_department IS NULL THEN RAISE EXCEPTION 'A department audience needs a department' USING ERRCODE = '22023'; END IF;
    IF p_from IS NULL THEN RAISE EXCEPTION 'The publication start is required' USING ERRCODE = '22023'; END IF;
    IF p_to IS NOT NULL AND p_to <= p_from THEN RAISE EXCEPTION 'The publication end must be after the start' USING ERRCODE = '22023'; END IF;
    IF NOT EXISTS (SELECT 1 FROM announcement_type WHERE announcement_type_id = p_type AND is_active) THEN RAISE EXCEPTION 'Choose an active announcement type' USING ERRCODE = '22023'; END IF;
    IF p_department IS NOT NULL AND NOT EXISTS (SELECT 1 FROM department WHERE department_id = p_department) THEN RAISE EXCEPTION 'Unknown department' USING ERRCODE = '22023'; END IF;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.astatus(p_code text)
 RETURNS smallint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ SELECT approval_status_id FROM approval_status WHERE status_code = p_code $function$;

CREATE OR REPLACE FUNCTION sims_private.att_session_cos(p_session_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT course_offering_section_id FROM public.class_session WHERE class_session_id = p_session_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.check_institution_fields(p jsonb)
 RETURNS void
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE v_email text := NULLIF(btrim(p ->> 'email'), ''); v_web text := NULLIF(btrim(p ->> 'website_url'), '');
BEGIN
    IF v_email IS NOT NULL AND v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN
        RAISE EXCEPTION 'email is not a valid email address' USING ERRCODE = '22023';
    END IF;
    IF v_web IS NOT NULL AND v_web !~* '^https?://[^[:space:]]+$' THEN
        RAISE EXCEPTION 'website_url must start with http:// or https://' USING ERRCODE = '22023';
    END IF;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.course_result_published(p_course_registration_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT EXISTS (
        SELECT 1 FROM public.student_course_registration cr
        JOIN public.student_term_result tr ON tr.term_registration_id = cr.term_registration_id
        WHERE cr.course_registration_id = p_course_registration_id AND tr.published_at IS NOT NULL)
$function$;

CREATE OR REPLACE FUNCTION sims_private.describe_columns(p_table text, p_exclude text[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'name', a.attname,
        'type', regexp_replace(CASE WHEN t.typtype = 'd' THEN format_type(t.typbasetype, t.typtypmod) ELSE format_type(a.atttypid, a.atttypmod) END, '\(.*\)', ''),
        'required', a.attnotnull AND NOT a.atthasdef,
        'max_length', CASE WHEN t.typname = 'varchar' AND a.atttypmod > 4 THEN a.atttypmod - 4 END,
        'ref_table', (SELECT cf.confrelid::regclass::text FROM pg_constraint cf WHERE cf.contype = 'f' AND cf.conrelid = a.attrelid AND cf.conkey = ARRAY[a.attnum] LIMIT 1),
        'choices', (SELECT (SELECT jsonb_agg(m[1]) FROM regexp_matches(pg_get_constraintdef(cc.oid), '''([A-Za-z0-9_ ./-]+)''', 'g') m)
                    FROM pg_constraint cc WHERE cc.contype = 'c' AND cc.conrelid = a.attrelid AND cc.conkey = ARRAY[a.attnum] AND pg_get_constraintdef(cc.oid) ~ '(IN|ANY)' LIMIT 1)
    ) ORDER BY a.attnum), '[]'::jsonb)
    FROM pg_attribute a JOIN pg_type t ON t.oid = a.atttypid
    WHERE a.attrelid = format('public.%I', p_table)::regclass AND a.attnum > 0 AND NOT a.attisdropped AND a.attgenerated = '' AND a.attname <> ALL (p_exclude)
$function$;

CREATE OR REPLACE FUNCTION sims_private.doc_announcement_id(p_name text)
 RETURNS bigint
 LANGUAGE sql
 IMMUTABLE
AS $function$ SELECT CASE WHEN length(p_name) <= 400 AND p_name ~ '^announcement/[0-9]{1,15}/[^/]+$' THEN split_part(p_name, '/', 2)::bigint END $function$;

CREATE OR REPLACE FUNCTION sims_private.doc_employee_id(p_name text)
 RETURNS bigint
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE WHEN length(p_name) <= 400 AND p_name ~ '^employee/[0-9]{1,15}/[^/]+$' THEN split_part(p_name, '/', 2)::bigint END
$function$;

CREATE OR REPLACE FUNCTION sims_private.doc_student_id(p_name text)
 RETURNS bigint
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE WHEN length(p_name) <= 400 AND p_name ~ '^student/[0-9]{1,15}/[^/]+$' THEN split_part(p_name, '/', 2)::bigint END
$function$;

CREATE OR REPLACE FUNCTION sims_private.emp_sensitive_row(p_kind text, p_id bigint)
 RETURNS TABLE(employee_id bigint, status text, last_editor bigint, ciphertext bytea)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF p_kind = 'PAN' THEN RETURN QUERY SELECT t.employee_id::bigint, t.verification_status::text, t.updated_by_user_id::bigint, t.pan_number_ciphertext FROM employee_pan t WHERE t.employee_pan_id = p_id FOR UPDATE;
    ELSIF p_kind = 'AADHAAR' THEN RETURN QUERY SELECT t.employee_id::bigint, t.verification_status::text, t.updated_by_user_id::bigint, t.aadhaar_number_ciphertext FROM employee_aadhaar t WHERE t.employee_aadhaar_id = p_id FOR UPDATE;
    ELSIF p_kind = 'BANK_ACCOUNT' THEN RETURN QUERY SELECT t.employee_id::bigint, t.verification_status::text, t.updated_by_user_id::bigint, t.account_number_ciphertext FROM employee_bank_account t WHERE t.employee_bank_account_id = p_id AND t.deleted_at IS NULL FOR UPDATE;
    ELSE RAISE EXCEPTION 'Unknown kind' USING ERRCODE = '22023'; END IF;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.employee_institution_immutable()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF current_user = 'authenticated' AND NEW.institution_id IS DISTINCT FROM OLD.institution_id THEN
        RAISE EXCEPTION 'An employee cannot be moved to another institution through this interface' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.event_published(p_event_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT COALESCE((SELECT status = 'PUBLISHED' FROM public.assessment_event WHERE assessment_event_id = p_event_id), false)
$function$;

CREATE OR REPLACE FUNCTION sims_private.exec_dml(p_sql text, p_json jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_state text; v_msg text; v_col text; v_con text;
BEGIN
    EXECUTE p_sql USING p_json;
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT, v_col = COLUMN_NAME, v_con = CONSTRAINT_NAME;
    IF v_state = '23502' THEN RAISE EXCEPTION 'The field "%" is required', COALESCE(v_col, 'unknown') USING ERRCODE = '22023';
    ELSIF v_state = '23503' THEN RAISE EXCEPTION 'One of the selected options does not exist (%)', COALESCE(v_con, 'unknown') USING ERRCODE = '22023';
    ELSIF v_state = '23505' THEN RAISE EXCEPTION 'That value is already recorded (%)', COALESCE(v_con, 'unknown') USING ERRCODE = '23505';
    ELSIF v_state = '23514' THEN RAISE EXCEPTION 'A value is not allowed (%)', COALESCE(v_con, 'unknown') USING ERRCODE = '22023';
    ELSIF v_state LIKE '22%' THEN RAISE EXCEPTION 'A value has the wrong format or is too long: %', v_msg USING ERRCODE = '22023';
    ELSE RAISE; END IF;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.exec_dml_id(p_sql text, p_json jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_state text; v_msg text; v_col text; v_con text; v_id bigint;
BEGIN
    EXECUTE p_sql INTO v_id USING p_json;
    RETURN v_id;
EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT, v_col = COLUMN_NAME, v_con = CONSTRAINT_NAME;
    IF v_state = '23502' THEN RAISE EXCEPTION 'The field "%" is required', COALESCE(v_col, 'unknown') USING ERRCODE = '22023';
    ELSIF v_state = '23503' THEN RAISE EXCEPTION 'One of the selected options does not exist, or this row is still in use (%)', COALESCE(v_con, 'unknown') USING ERRCODE = '22023';
    ELSIF v_state = '23505' THEN RAISE EXCEPTION 'That value is already recorded (%)', COALESCE(v_con, 'unknown') USING ERRCODE = '23505';
    ELSIF v_state = '23514' THEN RAISE EXCEPTION 'A value is not allowed (%)', COALESCE(v_con, 'unknown') USING ERRCODE = '22023';
    ELSIF v_state LIKE '22%' THEN RAISE EXCEPTION 'A value has the wrong format or is too long: %', v_msg USING ERRCODE = '22023';
    ELSE RAISE; END IF;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.feedback_min_responses()
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$ SELECT 5 $function$;

CREATE OR REPLACE FUNCTION sims_private.feedback_questionnaire_locked(p_questionnaire_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT EXISTS (SELECT 1 FROM feedback_cycle c WHERE c.questionnaire_id = p_questionnaire_id
                   AND (c.status IN ('OPEN', 'CLOSED') OR EXISTS (SELECT 1 FROM feedback_response r WHERE r.feedback_cycle_id = c.feedback_cycle_id)))
$function$;

CREATE OR REPLACE FUNCTION sims_private.feedback_rating_max()
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$ SELECT 5 $function$;

CREATE OR REPLACE FUNCTION sims_private.fin_assessment_student(p_assessment_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT f.student_id FROM student_fee_assessment a JOIN student_financial_account f ON f.student_account_id = a.student_account_id WHERE a.fee_assessment_id = p_assessment_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.fin_benefit_load(p_kind text, p_id bigint)
 RETURNS TABLE(student_id bigint, status text, open_status text, usable_status text, basis text, pct numeric, amount numeric, max_pct numeric, max_amount numeric, valid_from date, valid_to date)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF p_kind = 'CONCESSION' THEN
        RETURN QUERY SELECT c.student_id::bigint, c.approval_status::text, 'SUBMITTED'::text, 'APPROVED'::text, t.concession_basis::text, c.approved_percentage::numeric, c.approved_amount::numeric,
                            t.maximum_percentage::numeric, t.maximum_amount::numeric, c.valid_from, c.valid_to
                       FROM student_fee_concession c JOIN concession_type t ON t.concession_type_id = c.concession_type_id WHERE c.student_concession_id = p_id FOR UPDATE OF c;
    ELSIF p_kind = 'SCHOLARSHIP' THEN
        RETURN QUERY SELECT s.student_id::bigint, s.application_status::text, 'SUBMITTED'::text, 'SANCTIONED'::text, 'FIXED_AMOUNT'::text, NULL::numeric, COALESCE(s.sanctioned_amount, s.applied_amount)::numeric,
                            NULL::numeric, m.maximum_amount::numeric, NULL::date, NULL::date
                       FROM student_scholarship s JOIN scholarship_scheme m ON m.scholarship_scheme_id = s.scholarship_scheme_id WHERE s.student_scholarship_id = p_id FOR UPDATE OF s;
    ELSIF p_kind = 'SPONSORSHIP' THEN
        RETURN QUERY SELECT s.student_id::bigint, s.approval_status::text, 'PENDING'::text, 'APPROVED'::text, 'FIXED_AMOUNT'::text, NULL::numeric, s.sanctioned_amount::numeric,
                            NULL::numeric, NULL::numeric, s.valid_from, s.valid_to
                       FROM student_sponsorship s WHERE s.student_sponsorship_id = p_id FOR UPDATE OF s;
    ELSE
        RAISE EXCEPTION 'Unknown benefit kind' USING ERRCODE = '22023';
    END IF;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.fin_check_amount(p_amount numeric, p_what text)
 RETURNS void
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
    IF p_amount IS NULL OR p_amount <= 0 OR p_amount <> round(p_amount, 2) OR p_amount >= 10000000000 THEN
        RAISE EXCEPTION '% must be a positive amount with at most 2 decimals', p_what USING ERRCODE = '22023';
    END IF;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.fin_editable_item(p_item_id bigint)
 RETURNS TABLE(student_id bigint, student_account_id bigint, fee_assessment_id bigint, original_amount numeric, net_amount numeric, amount_paid numeric, balance_amount numeric)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE r record;
BEGIN
    SELECT a.student_account_id AS acc, f.student_id AS stu, i.fee_assessment_id AS fa, i.item_status, i.original_amount AS orig, i.net_amount AS net, i.amount_paid AS paid, i.balance_amount AS bal
      INTO r
      FROM student_fee_assessment_item i
      JOIN student_fee_assessment a ON a.fee_assessment_id = i.fee_assessment_id
      JOIN student_financial_account f ON f.student_account_id = a.student_account_id
     WHERE i.assessment_item_id = p_item_id FOR UPDATE OF i;
    IF r.acc IS NULL THEN RAISE EXCEPTION 'Unknown fee item' USING ERRCODE = '45000'; END IF;
    IF r.item_status IN ('CANCELLED', 'WAIVED') THEN RAISE EXCEPTION 'Fee item is %', r.item_status USING ERRCODE = '45000'; END IF;
    IF EXISTS (SELECT 1 FROM student_installment_schedule s WHERE s.fee_assessment_id = r.fa AND s.installment_status <> 'CANCELLED') THEN
        RAISE EXCEPTION 'The assessment has an instalment schedule: cancel it before changing the amounts' USING ERRCODE = '45000';
    END IF;
    RETURN QUERY SELECT r.stu::bigint, r.acc::bigint, r.fa::bigint, r.orig::numeric, r.net::numeric, r.paid::numeric, r.bal::numeric;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.fin_hold_active(p_student_id bigint, p_type text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT EXISTS (SELECT 1 FROM student_financial_hold h JOIN student_financial_account a ON a.student_account_id = h.student_account_id WHERE a.student_id = p_student_id AND h.hold_type = p_type AND h.hold_status = 'ACTIVE')
$function$;

CREATE OR REPLACE FUNCTION sims_private.fin_next_receipt_number()
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE y integer := extract(year FROM now())::integer; m integer := extract(month FROM now())::integer; ay text; n integer;
BEGIN
    IF m < 4 THEN y := y - 1; END IF;
    ay := y::text || '-' || lpad(((y + 1) % 100)::text, 2, '0');
    INSERT INTO sims_private.receipt_counter AS c (academic_year, last_number) VALUES (ay, 1)
    ON CONFLICT (academic_year) DO UPDATE SET last_number = c.last_number + 1 RETURNING c.last_number INTO n;
    RETURN 'REC/' || ay || '/' || lpad(n::text, 6, '0');
END $function$;

CREATE OR REPLACE FUNCTION sims_private.fin_refresh_status(p_item_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_fa bigint;
BEGIN
    UPDATE student_fee_assessment_item
       SET item_status = CASE WHEN balance_amount = 0 AND amount_paid > 0 THEN 'PAID' WHEN balance_amount = 0 THEN 'WAIVED' WHEN amount_paid > 0 THEN 'PARTIALLY_PAID' ELSE item_status END
     WHERE assessment_item_id = p_item_id AND item_status IN ('ASSESSED', 'PARTIALLY_PAID', 'OVERDUE')
    RETURNING fee_assessment_id INTO v_fa;
    IF v_fa IS NOT NULL THEN
        UPDATE student_fee_assessment
           SET assessment_status = CASE WHEN balance_amount = 0 AND amount_paid > 0 THEN 'PAID' WHEN balance_amount = 0 THEN 'WAIVED' WHEN amount_paid > 0 THEN 'PARTIALLY_PAID' ELSE assessment_status END
         WHERE fee_assessment_id = v_fa AND assessment_status IN ('ASSESSED', 'PARTIALLY_PAID', 'OVERDUE');
    END IF;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.fin_refunded_on_payment(p_payment_id bigint)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT COALESCE(SUM(fr.refund_amount), 0) FROM public.fee_refund fr JOIN public.refund_request rr ON rr.refund_request_id = fr.refund_request_id
     WHERE rr.payment_transaction_id = p_payment_id AND fr.refund_status = 'SUCCESS'
$function$;

CREATE OR REPLACE FUNCTION sims_private.grievance_transition_ok(p_from text, p_to text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT (p_from, p_to) IN (('SUBMITTED', 'ASSIGNED'), ('SUBMITTED', 'REJECTED'), ('ASSIGNED', 'UNDER_REVIEW'), ('ASSIGNED', 'REJECTED'), ('UNDER_REVIEW', 'RESOLVED'),
                              ('UNDER_REVIEW', 'REJECTED'), ('RESOLVED', 'CLOSED'), ('RESOLVED', 'UNDER_REVIEW'), ('REJECTED', 'CLOSED'))
$function$;

CREATE OR REPLACE FUNCTION sims_private.indexing_table(p_activity_id bigint)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT CASE WHEN EXISTS (SELECT 1 FROM journal_publication WHERE staff_activity_id = p_activity_id) THEN 'journal_publication_indexing'
                WHEN EXISTS (SELECT 1 FROM conference_activity WHERE staff_activity_id = p_activity_id) THEN 'conference_activity_indexing' END
$function$;

CREATE OR REPLACE FUNCTION sims_private.jwt_aal()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
    SELECT COALESCE(CASE WHEN NULLIF(current_setting('request.jwt.claims', true), '') IS NULL THEN NULL
                         ELSE NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'aal' END, 'aal1')
$function$;

CREATE OR REPLACE FUNCTION sims_private.link_auth_user(p_auth_user uuid, p_user_id bigint, p_actor text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM public.user_account WHERE user_id = p_user_id) THEN
        RAISE EXCEPTION 'user_account % does not exist', p_user_id USING ERRCODE = '45000';
    END IF;
    INSERT INTO sims_private.auth_identity_map (auth_user_id, user_id, linked_by) VALUES (p_auth_user, p_user_id, p_actor);
END $function$;

CREATE OR REPLACE FUNCTION sims_private.mentoring_check_session(p_date timestamp with time zone, p_observations text, p_action_plan text, p_follow_up date, p_status text, p_level text)
 RETURNS void
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
    IF p_date IS NULL THEN RAISE EXCEPTION 'The session date is required' USING ERRCODE = '22023'; END IF;
    IF p_status NOT IN ('SCHEDULED', 'COMPLETED', 'CANCELLED', 'FOLLOW_UP_REQUIRED') THEN RAISE EXCEPTION 'Invalid session status' USING ERRCODE = '22023'; END IF;
    IF p_level NOT IN ('NORMAL', 'RESTRICTED', 'HIGHLY_RESTRICTED') THEN RAISE EXCEPTION 'Invalid confidentiality level' USING ERRCODE = '22023'; END IF;
    IF length(COALESCE(p_observations, '')) > 10000 OR length(COALESCE(p_action_plan, '')) > 10000 THEN RAISE EXCEPTION 'Notes are limited to 10000 characters' USING ERRCODE = '22023'; END IF;
    IF p_follow_up IS NOT NULL AND p_follow_up < p_date::date THEN RAISE EXCEPTION 'The follow-up date cannot be before the session' USING ERRCODE = '45000'; END IF;
    IF p_status = 'FOLLOW_UP_REQUIRED' AND p_follow_up IS NULL THEN RAISE EXCEPTION 'A follow-up date is required when a follow-up is needed' USING ERRCODE = '45000'; END IF;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.mfa_setup_required(p_user bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT EXISTS (SELECT 1 FROM public.user_account u WHERE u.user_id = p_user AND NOT u.multi_factor_enabled)
       AND EXISTS (SELECT 1 FROM public.v_active_user_role a JOIN public.role r ON r.role_code = a.role_code JOIN sims_private.mfa_required_role m ON m.role_id = r.role_id WHERE a.user_id = p_user)
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_admission_application_application_id_admitted_student_id(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT admitted_student_id::bigint FROM public.admission_application WHERE application_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_announcement_announcement_id_department_id(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT department_id::bigint FROM public.announcement WHERE announcement_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_assessment_component_assessment_component_id_c_556a8c03e6(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT course_offering_id::bigint FROM public.assessment_component WHERE assessment_component_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_building_building_id_campus_id(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT campus_id::bigint FROM public.building WHERE building_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_class_section_class_section_id_programme_term_offering_id(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT programme_term_offering_id::bigint FROM public.class_section WHERE class_section_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_conference_activity_staff_activity_id_staff_activity_id(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT staff_activity_id::bigint FROM public.conference_activity WHERE staff_activity_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_course_catalog_course_id_owning_department_id(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT owning_department_id::bigint FROM public.course_catalog WHERE course_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_course_offering_course_offering_id_programme_t_6af0a6bfe1(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT programme_term_offering_id::bigint FROM public.course_offering WHERE course_offering_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_course_offering_section_course_offering_sectio_7deeb92c3b(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT course_offering_id::bigint FROM public.course_offering_section WHERE course_offering_section_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_course_offering_section_student_course_offerin_c13eb2db9e(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT course_registration_id::bigint FROM public.course_offering_section_student WHERE course_offering_section_student_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_curriculum_scheme_curriculum_scheme_id_programme_id(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT programme_id::bigint FROM public.curriculum_scheme WHERE curriculum_scheme_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_employee_document_employee_document_id_employee_id(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT employee_id::bigint FROM public.employee_document WHERE employee_document_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_evidence_document_evidence_document_id_staff_activity_id(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT staff_activity_id::bigint FROM public.evidence_document WHERE evidence_document_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_fee_structure_fee_structure_id_programme_id(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT programme_id::bigint FROM public.fee_structure WHERE fee_structure_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_feedback_response_feedback_response_id_term_re_148ea414c7(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT term_registration_id::bigint FROM public.feedback_response WHERE feedback_response_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_funded_research_project_staff_activity_id_prin_85828402ed(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT principal_investigator_employee_id::bigint FROM public.funded_research_project WHERE staff_activity_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_grievance_grievance_id_student_id(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT student_id::bigint FROM public.grievance WHERE grievance_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_journal_publication_staff_activity_id_staff_activity_id(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT staff_activity_id::bigint FROM public.journal_publication WHERE staff_activity_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_mentor_assignment_mentor_assignment_id_student_id(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT student_id::bigint FROM public.mentor_assignment WHERE mentor_assignment_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_payment_transaction_payment_transaction_id_stu_04cbabf9c9(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT student_account_id::bigint FROM public.payment_transaction WHERE payment_transaction_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_programme_term_offering_programme_term_offerin_dd560b84f3(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT programme_id::bigint FROM public.programme_term_offering WHERE programme_term_offering_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_refund_request_refund_request_id_student_account_id(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT student_account_id::bigint FROM public.refund_request WHERE refund_request_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_staff_activity_staff_activity_id_employee_id(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT employee_id::bigint FROM public.staff_activity WHERE staff_activity_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_staff_professional_contribution_staff_activity_a926f20bfe(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT staff_activity_id::bigint FROM public.staff_professional_contribution WHERE staff_activity_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_student_activity_evidence_student_activity_evi_20620f7c4c(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT student_activity_id::bigint FROM public.student_activity_evidence WHERE student_activity_evidence_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_student_activity_student_activity_id_student_id(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT student_id::bigint FROM public.student_activity WHERE student_activity_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_student_attendance_class_session_id_course_off_a5763429ec(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT course_offering_section_student_id::bigint FROM public.student_attendance WHERE class_session_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_student_course_registration_course_registratio_92ae207afd(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT term_registration_id::bigint FROM public.student_course_registration WHERE course_registration_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_student_fee_assessment_fee_assessment_id_stude_d877e246a8(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT student_account_id::bigint FROM public.student_fee_assessment WHERE fee_assessment_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_student_fee_assessment_item_assessment_item_id_81c18f4ea9(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT fee_assessment_id::bigint FROM public.student_fee_assessment_item WHERE assessment_item_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_student_fee_concession_student_concession_id_student_id(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT student_id::bigint FROM public.student_fee_concession WHERE student_concession_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_student_financial_account_student_account_id_student_id(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT student_id::bigint FROM public.student_financial_account WHERE student_account_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_student_programme_enrolment_enrolment_id_student_id(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT student_id::bigint FROM public.student_programme_enrolment WHERE enrolment_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.nx_student_term_registration_term_registration_id_7e00744235(p_id bigint)
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT enrolment_id::bigint FROM public.student_term_registration WHERE term_registration_id = p_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.other_super_admins(p_user_id bigint)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT count(DISTINCT a.user_id)::integer FROM user_role_assignment a JOIN role r ON r.role_id = a.role_id JOIN user_account u ON u.user_id = a.user_id
    WHERE r.role_code = 'SUPER_ADMIN' AND a.scope_type = 'GLOBAL' AND a.assignment_status = 'ACTIVE' AND a.valid_from <= now() AND (a.valid_to IS NULL OR a.valid_to > now())
      AND u.account_status = 'ACTIVE' AND a.user_id <> p_user_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.pii_key()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_temp'
AS $function$ SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'sims_pii_key' $function$;

CREATE OR REPLACE FUNCTION sims_private.pk_column(p_table text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT at.attname::text FROM pg_constraint cp JOIN pg_attribute at ON at.attrelid = cp.conrelid AND at.attnum = cp.conkey[1]
    WHERE cp.contype = 'p' AND cp.conrelid = format('public.%I', p_table)::regclass AND array_length(cp.conkey, 1) = 1
$function$;

CREATE OR REPLACE FUNCTION sims_private.programme_institution(p_programme integer)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT c.institution_id::integer FROM public.programme p JOIN public.department d ON d.department_id = p.department_id JOIN public.campus c ON c.campus_id = d.campus_id WHERE p.programme_id = p_programme
$function$;

CREATE OR REPLACE FUNCTION sims_private.programme_of_cos(p_cos_id bigint)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT pto.programme_id FROM public.course_offering_section cos
    JOIN public.programme_term_offering pto ON pto.programme_term_offering_id = cos.programme_term_offering_id
    WHERE cos.course_offering_section_id = p_cos_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.programme_of_offering(p_course_offering_id bigint)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT pto.programme_id FROM public.course_offering co JOIN public.programme_term_offering pto ON pto.programme_term_offering_id = co.programme_term_offering_id
    WHERE co.course_offering_id = p_course_offering_id
$function$;

CREATE OR REPLACE FUNCTION sims_private.ref_def(p_table text)
 RETURNS TABLE(perm text, module_code text, label text)
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT v.perm, v.module_code, v.label FROM (VALUES
        ('blood_group', 'IAM.ALL.CONFIGURE', 'PLATFORM', 'Blood groups'), ('caste', 'IAM.ALL.CONFIGURE', 'PLATFORM', 'Castes'), ('country', 'IAM.ALL.CONFIGURE', 'PLATFORM', 'Countries'),
        ('gender', 'IAM.ALL.CONFIGURE', 'PLATFORM', 'Genders'), ('religion', 'IAM.ALL.CONFIGURE', 'PLATFORM', 'Religions'), ('social_category', 'IAM.ALL.CONFIGURE', 'PLATFORM', 'Social categories'),
        ('state', 'IAM.ALL.CONFIGURE', 'PLATFORM', 'States'), ('sub_caste', 'IAM.ALL.CONFIGURE', 'PLATFORM', 'Sub-castes'), ('document_type', 'IAM.ALL.CONFIGURE', 'PLATFORM', 'Document types'),
        ('publication_type', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE', 'Publication types'), ('journal_type', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE', 'Journal types'),
        ('indexing_agency', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE', 'Indexing agencies'), ('funding_type', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE', 'Funding types'),
        ('award_category', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE', 'Award categories'), ('membership_type', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE', 'Membership types'),
        ('metric_type', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE', 'Journal metric types'), ('journal_metric', 'STAFF_PROFILE.ALL.CONFIGURE', 'STAFF_PROFILE', 'Journal metrics'),
        ('certificate_type', 'DOCUMENT.ALL.CONFIGURE', 'DOCUMENT', 'Certificate types'), ('qualification_level', 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE', 'Qualification levels'), ('education_institution', 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE', 'Education institutions'),
        ('awarding_body', 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE', 'Awarding bodies'), ('study_mode', 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE', 'Study modes'),
        ('previous_organization', 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE', 'Previous organisations'), ('staff_category', 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE', 'Staff categories'),
        ('staff_type', 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE', 'Staff types'), ('designation', 'EMPLOYEE.ALL.CONFIGURE', 'EMPLOYEE', 'Designations'),
        ('fee_category', 'FEES.FEE_STRUCTURE.CONFIGURE', 'FEES', 'Fee categories'), ('financial_ledger_account', 'FEES.FEE_STRUCTURE.CONFIGURE', 'FEES', 'Ledger accounts'),
        ('fee_type', 'FEES.FEE_STRUCTURE.CONFIGURE', 'FEES', 'Fee types'), ('late_fee_rule', 'FEES.FEE_STRUCTURE.CONFIGURE', 'FEES', 'Late-fee rules'),
        ('late_fee_slab', 'FEES.FEE_STRUCTURE.CONFIGURE', 'FEES', 'Late-fee slabs'), ('concession_type', 'FEES.FEE_STRUCTURE.CONFIGURE', 'FEES', 'Concession types'),
        ('scholarship_scheme', 'FEES.FEE_STRUCTURE.CONFIGURE', 'FEES', 'Scholarship schemes'), ('installment_plan', 'FEES.FEE_STRUCTURE.CONFIGURE', 'FEES', 'Instalment plans'),
        ('payment_mode', 'FEES.FEE_STRUCTURE.CONFIGURE', 'FEES', 'Payment modes')
    ) AS v(tbl, perm, module_code, label) WHERE v.tbl = p_table
$function$;

CREATE OR REPLACE FUNCTION sims_private.ref_tables()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT ARRAY['blood_group', 'caste', 'country', 'gender', 'religion', 'social_category', 'state', 'sub_caste', 'document_type', 'certificate_type', 'publication_type', 'journal_type', 'indexing_agency', 'funding_type',
                 'award_category', 'membership_type', 'metric_type', 'journal_metric', 'qualification_level', 'education_institution', 'awarding_body', 'study_mode', 'previous_organization', 'staff_category', 'staff_type',
                 'designation', 'fee_category', 'financial_ledger_account', 'fee_type', 'late_fee_rule', 'late_fee_slab', 'concession_type', 'scholarship_scheme', 'installment_plan', 'payment_mode']
$function$;

CREATE OR REPLACE FUNCTION sims_private.request_header(p_name text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
    RETURN NULLIF(btrim(current_setting('request.headers', true)::jsonb ->> p_name), '');
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.section_def(p_kind text, p_section text)
 RETURNS TABLE(tbl text, parent_col text, pk_col text, perm_prefix text, label text, module_code text)
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT v.tbl, v.parent_col, v.pk_col, v.perm_prefix, v.label, v.module_code FROM (VALUES
        ('student', 'address', 'student_address', 'student_id', 'student_address_id', 'STUDENT.ALL', 'Addresses', 'STUDENT'),
        ('student', 'guardian', 'student_parent_guardian', 'student_id', 'student_parent_guardian_id', 'STUDENT.ALL', 'Parents and guardians', 'STUDENT'),
        ('student', 'previous_education', 'student_previous_education', 'student_id', 'previous_education_id', 'STUDENT.ALL', 'Previous education', 'STUDENT'),
        ('student', 'entrance_exam', 'student_entrance_exam', 'student_id', 'student_entrance_exam_id', 'STUDENT.ALL', 'Entrance exams', 'STUDENT'),
        ('student', 'residence', 'student_residence', 'student_id', 'student_residence_id', 'STUDENT.ALL', 'Residence', 'STUDENT'),
        ('employee', 'address', 'employee_address', 'employee_id', 'employee_address_id', 'EMPLOYEE.ALL', 'Addresses', 'EMPLOYEE'),
        ('employee', 'qualification', 'employee_qualification', 'employee_id', 'employee_qualification_id', 'EMPLOYEE.QUALIFICATION', 'Qualifications', 'EMPLOYEE'),
        ('employee', 'experience', 'employee_previous_employment', 'employee_id', 'employee_previous_employment_id', 'EMPLOYEE.EXPERIENCE', 'Previous employment', 'EMPLOYEE'),
        ('activity', 'supervision', 'research_supervision', 'staff_activity_id', 'research_supervision_id', 'STAFF_PROFILE.STAFF_ACTIVITY', 'Research supervision', 'STAFF_PROFILE'),
        ('activity', 'utilization', 'research_project_financial_utilization', 'staff_activity_id', 'utilization_id', 'STAFF_PROFILE.STAFF_RESEARCH', 'Financial utilisation', 'STAFF_PROFILE')
    ) AS v(kind, section, tbl, parent_col, pk_col, perm_prefix, label, module_code) WHERE v.kind = p_kind AND v.section = p_section
$function$;

CREATE OR REPLACE FUNCTION sims_private.staff_detail_table(p_type_code text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE p_type_code
        WHEN 'JOURNAL_PUBLICATION' THEN 'journal_publication'
        WHEN 'CONFERENCE_PUBLICATION' THEN 'conference_activity' WHEN 'CONFERENCE_PRESENTATION' THEN 'conference_activity'
        WHEN 'WORKSHOP' THEN 'professional_development_activity' WHEN 'FDP' THEN 'professional_development_activity' WHEN 'STTP' THEN 'professional_development_activity' WHEN 'TRAINING' THEN 'professional_development_activity'
        WHEN 'FACULTY_INTERNSHIP' THEN 'faculty_internship'
        WHEN 'RESEARCH_PROPOSAL' THEN 'research_proposal' WHEN 'FUNDED_RESEARCH_PROJECT' THEN 'funded_research_project'
        WHEN 'CONSULTANCY' THEN 'consultancy_project' WHEN 'INDUSTRY_SPONSORED_PROJECT' THEN 'consultancy_project'
        WHEN 'CO_CURRICULAR' THEN 'cocurricular_activity' WHEN 'EXTRA_CURRICULAR' THEN 'extracurricular_activity'
        WHEN 'AWARD_RECOGNITION' THEN 'staff_award' WHEN 'PROFESSIONAL_MEMBERSHIP' THEN 'staff_professional_membership'
        WHEN 'ACADEMIC_PROFESSIONAL_CONTRIBUTION' THEN 'staff_professional_contribution' END
$function$;

CREATE OR REPLACE FUNCTION sims_private.staff_lookup_tables()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT ARRAY['journal', 'publisher', 'conference_event', 'organizer', 'external_organization', 'funding_agency']
$function$;

CREATE OR REPLACE FUNCTION sims_private.staff_option_tables()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT ARRAY['award_category', 'cocurricular_category', 'conference_contribution_type', 'conference_event', 'country', 'course_catalog', 'department', 'event_mode', 'external_organization',
                 'extracurricular_category', 'funding_agency', 'funding_type', 'industry_sector', 'journal', 'journal_type', 'membership_type', 'organizer', 'participation_level',
                 'professional_contribution_type', 'programme', 'publication_type', 'publisher', 'research_status', 'role_type', 'state', 'training_program_type']
$function$;

CREATE OR REPLACE FUNCTION sims_private.storage_key_is_orphan(p_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT NOT EXISTS (SELECT 1 FROM file_object WHERE storage_key = p_name)
$function$;

CREATE OR REPLACE FUNCTION sims_private.user_id_any_aal()
 RETURNS bigint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT m.user_id FROM sims_private.auth_identity_map m JOIN public.user_account u ON u.user_id = m.user_id
    WHERE m.auth_user_id = auth.uid() AND u.account_status = 'ACTIVE' AND (u.locked_until IS NULL OR u.locked_until <= now())
$function$;

CREATE OR REPLACE FUNCTION sims_private.verhoeff_valid(p text)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
    d integer[] := ARRAY[[0,1,2,3,4,5,6,7,8,9],[1,2,3,4,0,6,7,8,9,5],[2,3,4,0,1,7,8,9,5,6],[3,4,0,1,2,8,9,5,6,7],[4,0,1,2,3,9,5,6,7,8],[5,9,8,7,6,0,4,3,2,1],[6,5,9,8,7,1,0,4,3,2],[7,6,5,9,8,2,1,0,4,3],[8,7,6,5,9,3,2,1,0,4],[9,8,7,6,5,4,3,2,1,0]];
    pm integer[] := ARRAY[[0,1,2,3,4,5,6,7,8,9],[1,5,7,6,2,8,3,0,9,4],[5,8,0,3,7,9,6,1,4,2],[8,9,1,6,0,4,3,5,2,7],[9,4,5,3,1,2,6,8,7,0],[4,2,8,6,5,7,3,9,0,1],[2,7,9,3,8,0,6,4,1,5],[7,0,4,6,9,1,3,2,5,8]];
    c integer := 0; i integer; n integer := length(p);
BEGIN
    IF p !~ '^[0-9]+$' THEN RETURN false; END IF;
    FOR i IN 0..n - 1 LOOP
        c := d[c + 1][pm[(i % 8) + 1][substr(p, n - i, 1)::integer + 1] + 1];
    END LOOP;
    RETURN c = 0;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.vstatus(p_code text)
 RETURNS smallint
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ SELECT verification_status_id FROM verification_status WHERE status_code = p_code $function$;

CREATE OR REPLACE FUNCTION public.sims_course_result_lock()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_reg bigint := COALESCE(NEW.course_registration_id, OLD.course_registration_id);
BEGIN
    IF sims_private.course_result_published(v_reg) THEN
        RAISE EXCEPTION 'The term result is published; unpublish it before changing course results' USING ERRCODE = '45000';
    END IF;
    RETURN COALESCE(NEW, OLD);
END $function$;

CREATE OR REPLACE FUNCTION public.sims_fee_item_sync()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        PERFORM sims_sync_fee_assessment_totals(NEW.fee_assessment_id);
    END IF;
    IF TG_OP = 'DELETE' OR (TG_OP = 'UPDATE' AND OLD.fee_assessment_id <> NEW.fee_assessment_id) THEN
        PERFORM sims_sync_fee_assessment_totals(OLD.fee_assessment_id);
    END IF;
    RETURN NULL;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_feedback_item_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF sims_private.feedback_questionnaire_locked(CASE WHEN TG_OP = 'DELETE' THEN OLD.questionnaire_id ELSE NEW.questionnaire_id END)
       OR (TG_OP = 'UPDATE' AND NEW.questionnaire_id <> OLD.questionnaire_id AND sims_private.feedback_questionnaire_locked(OLD.questionnaire_id)) THEN
        RAISE EXCEPTION 'The questions of a questionnaire used by an open or closed cycle (or with responses) cannot be changed' USING ERRCODE = '45000';
    END IF;
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_feedback_questionnaire_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF (NEW.status, NEW.is_anonymous, NEW.questionnaire_type) IS DISTINCT FROM (OLD.status, OLD.is_anonymous, OLD.questionnaire_type)
       AND sims_private.feedback_questionnaire_locked(OLD.questionnaire_id) AND NOT (OLD.status = 'ACTIVE' AND NEW.status = 'RETIRED' AND NEW.is_anonymous = OLD.is_anonymous AND NEW.questionnaire_type = OLD.questionnaire_type) THEN
        RAISE EXCEPTION 'The status, type and anonymity of a questionnaire used by an open or closed cycle (or with responses) cannot be changed, except retiring it' USING ERRCODE = '45000';
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_guard_certificate_hold()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF NEW.request_status IN ('APPROVED', 'ISSUED') AND NEW.request_status IS DISTINCT FROM OLD.request_status AND sims_private.fin_hold_active(NEW.student_id, 'CERTIFICATE') THEN
        RAISE EXCEPTION 'Certificates are blocked by a fee hold. Please contact the fee office.' USING ERRCODE = '45000';
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_guard_term_registration_hold()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_student bigint;
BEGIN
    SELECT student_id INTO v_student FROM student_programme_enrolment WHERE enrolment_id = NEW.enrolment_id;
    IF v_student IS NOT NULL AND sims_private.fin_hold_active(v_student, 'REGISTRATION') THEN
        RAISE EXCEPTION 'Registration is blocked by a fee hold. Please contact the fee office.' USING ERRCODE = '45000';
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_payment_allocation_sync()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        PERFORM sims_recalc_fee_item_paid(NEW.assessment_item_id);
    END IF;
    IF TG_OP = 'DELETE' OR (TG_OP = 'UPDATE' AND OLD.assessment_item_id <> NEW.assessment_item_id) THEN
        PERFORM sims_recalc_fee_item_paid(OLD.assessment_item_id);
    END IF;
    RETURN NULL;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.check_employee_upload(p_employee bigint, p_key text, p_file_name text, p_mime text, p_size bigint, p_checksum text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_ext text; v_meta jsonb;
BEGIN
    IF sims_private.doc_employee_id(p_key) IS DISTINCT FROM p_employee THEN RAISE EXCEPTION 'The file is not stored under this employee' USING ERRCODE = '22023'; END IF;
    IF p_file_name IS NULL OR btrim(p_file_name) = '' OR length(p_file_name) > 255 THEN RAISE EXCEPTION 'The file name is required (at most 255 characters)' USING ERRCODE = '22023'; END IF;
    IF p_mime NOT IN ('application/pdf', 'image/jpeg', 'image/png') THEN RAISE EXCEPTION 'Only PDF, JPEG and PNG files are accepted' USING ERRCODE = '22023'; END IF;
    v_ext := lower(substring(p_file_name FROM '\.([A-Za-z0-9]{1,10})$'));
    IF v_ext IS NULL OR NOT ((p_mime = 'application/pdf' AND v_ext = 'pdf') OR (p_mime = 'image/jpeg' AND v_ext IN ('jpg', 'jpeg')) OR (p_mime = 'image/png' AND v_ext = 'png')) THEN
        RAISE EXCEPTION 'The file name does not match its type' USING ERRCODE = '22023';
    END IF;
    IF p_size IS NULL OR p_size <= 0 OR p_size > 10485760 THEN RAISE EXCEPTION 'The file must be between 1 byte and 10 MB' USING ERRCODE = '22023'; END IF;
    IF p_checksum IS NOT NULL AND p_checksum !~ '^[0-9A-Fa-f]{64}$' THEN RAISE EXCEPTION 'Invalid checksum' USING ERRCODE = '22023'; END IF;
    SELECT metadata INTO v_meta FROM storage.objects WHERE bucket_id = 'sims-documents' AND name = p_key;
    IF NOT FOUND THEN RAISE EXCEPTION 'The file has not been uploaded' USING ERRCODE = '22023'; END IF;
    IF v_meta ? 'size' AND (v_meta ->> 'size')::bigint <> p_size THEN RAISE EXCEPTION 'The uploaded file size does not match' USING ERRCODE = '22023'; END IF;
    IF EXISTS (SELECT 1 FROM file_object WHERE storage_key = p_key) THEN RAISE EXCEPTION 'That file is already registered' USING ERRCODE = '23505'; END IF;
    RETURN v_ext;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.check_student_upload(p_student bigint, p_key text, p_file_name text, p_mime text, p_size bigint, p_checksum text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_ext text; v_meta jsonb;
BEGIN
    IF sims_private.doc_student_id(p_key) IS DISTINCT FROM p_student THEN RAISE EXCEPTION 'The file is not stored under this student' USING ERRCODE = '22023'; END IF;
    IF p_file_name IS NULL OR btrim(p_file_name) = '' OR length(p_file_name) > 255 THEN RAISE EXCEPTION 'The file name is required (at most 255 characters)' USING ERRCODE = '22023'; END IF;
    IF p_mime NOT IN ('application/pdf', 'image/jpeg', 'image/png') THEN RAISE EXCEPTION 'Only PDF, JPEG and PNG files are accepted' USING ERRCODE = '22023'; END IF;
    v_ext := lower(substring(p_file_name FROM '\.([A-Za-z0-9]{1,10})$'));
    IF v_ext IS NULL OR NOT ((p_mime = 'application/pdf' AND v_ext = 'pdf') OR (p_mime = 'image/jpeg' AND v_ext IN ('jpg', 'jpeg')) OR (p_mime = 'image/png' AND v_ext = 'png')) THEN
        RAISE EXCEPTION 'The file name does not match its type' USING ERRCODE = '22023';
    END IF;
    IF p_size IS NULL OR p_size <= 0 OR p_size > 10485760 THEN RAISE EXCEPTION 'The file must be between 1 byte and 10 MB' USING ERRCODE = '22023'; END IF;
    IF p_checksum IS NOT NULL AND p_checksum !~ '^[0-9A-Fa-f]{64}$' THEN RAISE EXCEPTION 'Invalid checksum' USING ERRCODE = '22023'; END IF;
    SELECT metadata INTO v_meta FROM storage.objects WHERE bucket_id = 'sims-documents' AND name = p_key;
    IF NOT FOUND THEN RAISE EXCEPTION 'The file has not been uploaded' USING ERRCODE = '22023'; END IF;
    IF v_meta ? 'size' AND (v_meta ->> 'size')::bigint <> p_size THEN RAISE EXCEPTION 'The uploaded file size does not match' USING ERRCODE = '22023'; END IF;
    IF EXISTS (SELECT 1 FROM file_object WHERE storage_key = p_key) THEN RAISE EXCEPTION 'That file is already registered' USING ERRCODE = '23505'; END IF;
    RETURN v_ext;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.current_user_id()
 RETURNS bigint
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_key text; v_hit text; v_id bigint;
BEGIN
    v_key := 'sims.uid_' || md5(COALESCE(auth.uid()::text, '') || '|' || sims_private.jwt_aal());
    v_hit := current_setting(v_key, true);
    IF v_hit IS NOT NULL AND v_hit <> '' THEN RETURN NULLIF(v_hit, '-')::bigint; END IF;
    SELECT m.user_id INTO v_id
    FROM sims_private.auth_identity_map m
    JOIN public.user_account u ON u.user_id = m.user_id
    WHERE m.auth_user_id = auth.uid()
      AND u.account_status = 'ACTIVE'
      AND (u.locked_until IS NULL OR u.locked_until <= now())
      AND (NOT u.multi_factor_enabled OR sims_private.jwt_aal() = 'aal2');
    PERFORM set_config(v_key, COALESCE(v_id::text, '-'), true);
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.form_columns(p_table text, p_exclude text[])
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT COALESCE(jsonb_agg(c), '[]'::jsonb) FROM jsonb_array_elements(sims_private.describe_columns(p_table, p_exclude || ARRAY['created_at', 'updated_at'])) c
    WHERE c ->> 'ref_table' IS DISTINCT FROM 'user_account' AND (c ->> 'name') NOT LIKE '%\_by\_user\_id' AND (c ->> 'name') NOT LIKE 'deleted%'
$function$;

CREATE OR REPLACE FUNCTION sims_private.pii_decrypt(p bytea)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_temp'
AS $function$ SELECT extensions.pgp_sym_decrypt(p, sims_private.pii_key()) $function$;

CREATE OR REPLACE FUNCTION sims_private.pii_encrypt(p text)
 RETURNS bytea
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_temp'
AS $function$ SELECT extensions.pgp_sym_encrypt(p, sims_private.pii_key()) $function$;

CREATE OR REPLACE FUNCTION sims_private.pii_fingerprint(p text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_temp'
AS $function$ SELECT encode(extensions.hmac(p, sims_private.pii_key(), 'sha256'), 'hex') $function$;

CREATE OR REPLACE FUNCTION sims_private.section_option_tables()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT sims_private.ref_tables() || ARRAY['journal', 'external_organization']
$function$;

CREATE OR REPLACE FUNCTION sims_private.svc_hold_check(p_student bigint, p_kind text, p_step text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_hold text;
BEGIN
    v_hold := CASE WHEN p_step = 'request' THEN CASE p_kind WHEN 'HALL_TICKET' THEN 'EXAMINATION' END ELSE p_kind END;
    IF v_hold IS NOT NULL AND sims_private.fin_hold_active(p_student, v_hold) THEN RAISE EXCEPTION 'This is blocked by a fee hold (%). Please contact the fee office.', lower(replace(v_hold, '_', ' ')) USING ERRCODE = '45000'; END IF;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.write_detail(p_table text, p_key_col text, p_id bigint, p_detail jsonb, p_insert boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_bad text; v_cols text; v_json jsonb;
BEGIN
    IF p_detail IS NULL OR jsonb_typeof(p_detail) <> 'object' THEN RAISE EXCEPTION 'The details must be an object' USING ERRCODE = '22023'; END IF;
    v_json := p_detail - p_key_col;
    SELECT string_agg(k, ', ') INTO v_bad FROM jsonb_object_keys(v_json) k
    WHERE NOT EXISTS (SELECT 1 FROM pg_attribute at WHERE at.attrelid = format('public.%I', p_table)::regclass AND at.attname = k AND at.attnum > 0 AND NOT at.attisdropped AND at.attgenerated = '');
    IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'Unknown detail field(s): %', v_bad USING ERRCODE = '22023'; END IF;
    IF p_insert THEN v_json := jsonb_strip_nulls(v_json); END IF;
    v_json := v_json || jsonb_build_object(p_key_col, p_id);
    SELECT string_agg(quote_ident(k), ', ') INTO v_cols FROM jsonb_object_keys(v_json) k;
    IF p_insert THEN
        PERFORM sims_private.exec_dml(format('INSERT INTO public.%I (%s) SELECT %s FROM jsonb_populate_record(NULL::public.%I, $1)', p_table, v_cols, v_cols, p_table), v_json);
    ELSE
        v_json := v_json - p_key_col;
        IF v_json = '{}'::jsonb THEN RETURN; END IF;
        SELECT string_agg(quote_ident(k), ', ') INTO v_cols FROM jsonb_object_keys(v_json) k;
        PERFORM sims_private.exec_dml(format('UPDATE public.%I t SET (%s) = (SELECT %s FROM jsonb_populate_record(NULL::public.%I, $1)) WHERE t.%I = %s', p_table, v_cols, v_cols, p_table, p_key_col, p_id),
                                      v_json);
    END IF;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.audit_manual(p_module text, p_action text, p_table text, p_id bigint, p_before jsonb, p_after jsonb)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    INSERT INTO activity_audit (user_id, module_code, action_code, entity_name, entity_id, before_values, after_values)
    VALUES (sims_private.current_user_id(), p_module, p_action, p_table, p_id::text, p_before, p_after)
$function$;

CREATE OR REPLACE FUNCTION sims_private.audit_row()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_old jsonb; v_new jsonb; v_before jsonb; v_after jsonb; v_id text;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_new := to_jsonb(NEW); v_after := v_new; v_id := v_new ->> TG_ARGV[1];
    ELSIF TG_OP = 'DELETE' THEN
        v_old := to_jsonb(OLD); v_before := v_old; v_id := v_old ->> TG_ARGV[1];
    ELSE
        v_old := to_jsonb(OLD); v_new := to_jsonb(NEW); v_id := v_new ->> TG_ARGV[1];
        SELECT jsonb_object_agg(n.key, n.value), jsonb_object_agg(n.key, v_old -> n.key)
          INTO v_after, v_before
          FROM jsonb_each(v_new) n
         WHERE n.key <> 'updated_at' AND n.value IS DISTINCT FROM (v_old -> n.key);
        IF v_after IS NULL THEN RETURN NULL; END IF;  -- nothing but updated_at changed
    END IF;
    INSERT INTO public.activity_audit (user_id, module_code, action_code, entity_name, entity_id, before_values, after_values)
    VALUES (sims_private.current_user_id(), TG_ARGV[0], TG_OP, TG_TABLE_NAME, v_id, v_before, v_after);
    RETURN NULL;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.caller_has_role(p_role_code text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT EXISTS (SELECT 1 FROM user_role_assignment a JOIN role r ON r.role_id = a.role_id
                   WHERE a.user_id = sims_private.current_user_id() AND r.role_code = p_role_code AND a.scope_type = 'GLOBAL' AND a.assignment_status = 'ACTIVE'
                     AND a.valid_from <= now() AND (a.valid_to IS NULL OR a.valid_to > now()))
$function$;

CREATE OR REPLACE FUNCTION sims_private.current_employee_id()
 RETURNS bigint
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_key text; v_hit text; v_id bigint; v_uid bigint := sims_private.current_user_id();
BEGIN
    IF v_uid IS NULL THEN RETURN NULL; END IF;
    v_key := 'sims.emp_' || v_uid;
    v_hit := current_setting(v_key, true);
    IF v_hit IS NOT NULL AND v_hit <> '' THEN RETURN NULLIF(v_hit, '-')::bigint; END IF;
    SELECT e.employee_id INTO v_id FROM public.employee_user_account e WHERE e.user_id = v_uid;
    PERFORM set_config(v_key, COALESCE(v_id::text, '-'), true);
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.current_student_id()
 RETURNS bigint
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_key text; v_hit text; v_id bigint; v_uid bigint := sims_private.current_user_id();
BEGIN
    IF v_uid IS NULL THEN RETURN NULL; END IF;
    v_key := 'sims.stu_' || v_uid;
    v_hit := current_setting(v_key, true);
    IF v_hit IS NOT NULL AND v_hit <> '' THEN RETURN NULLIF(v_hit, '-')::bigint; END IF;
    SELECT s.student_id INTO v_id FROM public.student_user_account s WHERE s.user_id = v_uid;
    PERFORM set_config(v_key, COALESCE(v_id::text, '-'), true);
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.eff(p_codes text[])
 RETURNS TABLE(scope_type text, scope_entity_id bigint, permission_effect text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid bigint := sims_private.current_user_id(); v_key text; v_hit text; v_json jsonb;
BEGIN
    IF v_uid IS NULL THEN RETURN; END IF;
    v_key := 'sims.eff_' || md5(v_uid::text || '|' || array_to_string(p_codes, ','));
    v_hit := current_setting(v_key, true);
    IF v_hit IS NULL OR v_hit = '' THEN
        SELECT COALESCE(jsonb_agg(jsonb_build_array(v.scope_type, v.scope_entity_id, v.permission_effect)), '[]'::jsonb) INTO v_json
        FROM public.v_effective_user_permission v WHERE v.user_id = v_uid AND v.permission_code = ANY (p_codes);
        v_hit := v_json::text;
        PERFORM set_config(v_key, v_hit, true);
    END IF;
    RETURN QUERY SELECT x ->> 0, (x ->> 1)::bigint, x ->> 2 FROM jsonb_array_elements(v_hit::jsonb) x;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.eff_set_of(p_codes text[])
 RETURNS sims_private.eff_set
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid bigint := sims_private.current_user_id(); v_key text; v_hit text; v sims_private.eff_set;
BEGIN
    IF v_uid IS NULL THEN RETURN ROW(false, false, false, false, '{}', '{}', '{}', '{}', '{}', '{}', '{}', '{}')::sims_private.eff_set; END IF;
    v_key := 'sims.set_' || md5(v_uid::text || '|' || array_to_string(p_codes, ','));
    v_hit := current_setting(v_key, true);
    IF v_hit IS NOT NULL AND v_hit <> '' THEN RETURN v_hit::sims_private.eff_set; END IF;
    v := (SELECT ROW(
        COALESCE(bool_or(x.scope_type = 'GLOBAL' AND x.permission_effect = 'ALLOW'), false), COALESCE(bool_or(x.scope_type = 'GLOBAL' AND x.permission_effect = 'DENY'), false),
        COALESCE(bool_or(x.scope_type = 'SELF' AND x.permission_effect = 'ALLOW'), false), COALESCE(bool_or(x.scope_type = 'SELF' AND x.permission_effect = 'DENY'), false),
        COALESCE(array_agg(x.scope_entity_id) FILTER (WHERE x.scope_type = 'INSTITUTION' AND x.permission_effect = 'ALLOW'), '{}'), COALESCE(array_agg(x.scope_entity_id) FILTER (WHERE x.scope_type = 'INSTITUTION' AND x.permission_effect = 'DENY'), '{}'),
        COALESCE(array_agg(x.scope_entity_id) FILTER (WHERE x.scope_type = 'CAMPUS' AND x.permission_effect = 'ALLOW'), '{}'), COALESCE(array_agg(x.scope_entity_id) FILTER (WHERE x.scope_type = 'CAMPUS' AND x.permission_effect = 'DENY'), '{}'),
        COALESCE(array_agg(x.scope_entity_id) FILTER (WHERE x.scope_type = 'DEPARTMENT' AND x.permission_effect = 'ALLOW'), '{}'), COALESCE(array_agg(x.scope_entity_id) FILTER (WHERE x.scope_type = 'DEPARTMENT' AND x.permission_effect = 'DENY'), '{}'),
        COALESCE(array_agg(x.scope_entity_id) FILTER (WHERE x.scope_type = 'PROGRAMME' AND x.permission_effect = 'ALLOW'), '{}'), COALESCE(array_agg(x.scope_entity_id) FILTER (WHERE x.scope_type = 'PROGRAMME' AND x.permission_effect = 'DENY'), '{}')
    )::sims_private.eff_set
    FROM public.v_effective_user_permission x WHERE x.user_id = v_uid AND x.permission_code = ANY (p_codes));
    PERFORM set_config(v_key, v::text, true);
    RETURN v;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.emp_doc_rule_ok(p_doc bigint, p_need text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT EXISTS (
        SELECT 1 FROM employee_document_access_rule r
         WHERE r.employee_document_id = p_doc AND r.valid_from <= now() AND (r.valid_to IS NULL OR r.valid_to > now())
           AND CASE p_need WHEN 'download' THEN r.can_download ELSE r.can_view OR r.can_download END
           AND (r.user_id = sims_private.current_user_id()
                OR (r.role_id IS NOT NULL AND EXISTS (SELECT 1 FROM public.v_active_user_role a WHERE a.user_id = sims_private.current_user_id() AND a.role_id = r.role_id))))
$function$;

CREATE OR REPLACE FUNCTION sims_private.emp_sensitive_log(p_emp bigint, p_action text, p_entity text, p_id bigint, p_purpose text, p_doc bigint DEFAULT NULL::bigint)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    INSERT INTO employee_sensitive_access_audit (user_id, employee_id, action_code, entity_type, entity_id, employee_document_id, access_purpose)
    VALUES (sims_private.current_user_id(), p_emp, p_action, p_entity, p_id, p_doc, left(p_purpose, 500))
$function$;

CREATE OR REPLACE FUNCTION sims_private.fin_audit(p_action text, p_entity text, p_id bigint, p_old jsonb, p_new jsonb)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    INSERT INTO public.fee_activity_audit (user_id, action_code, entity_name, entity_id, old_values, new_values)
    VALUES (sims_private.current_user_id(), p_action, p_entity, p_id, p_old, p_new)
$function$;

CREATE OR REPLACE FUNCTION sims_private.fin_creator_is_caller(p_entity text, p_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT EXISTS (SELECT 1 FROM fee_activity_audit WHERE entity_name = p_entity AND entity_id = p_id AND action_code IN ('BENEFIT_REQUESTED', 'ADJUSTMENT_REQUESTED') AND user_id = sims_private.current_user_id())
$function$;

CREATE OR REPLACE FUNCTION sims_private.is_active_member()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT sims_private.current_user_id() IS NOT NULL
$function$;

CREATE OR REPLACE FUNCTION sims_private.mentoring_audit(p_action text, p_session_id bigint, p_assignment_id bigint)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    INSERT INTO public.activity_audit (user_id, module_code, action_code, entity_name, entity_id, after_values)
    VALUES (sims_private.current_user_id(), 'MENTORING', p_action, 'counselling_session', p_session_id::text, jsonb_build_object('mentor_assignment_id', p_assignment_id))
$function$;

CREATE OR REPLACE FUNCTION sims_private.write_row(p_table text, p_pk text, p_parent_col text, p_parent_id bigint, p_id bigint, p jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_allowed text[]; v_bad text; v_json jsonb; v_cols text;
BEGIN
    IF p IS NULL OR jsonb_typeof(p) <> 'object' THEN RAISE EXCEPTION 'The details must be an object' USING ERRCODE = '22023'; END IF;
    SELECT array_agg(c ->> 'name') INTO v_allowed FROM jsonb_array_elements(sims_private.form_columns(p_table, ARRAY[p_pk] || CASE WHEN p_parent_col IS NULL THEN ARRAY[]::text[] ELSE ARRAY[p_parent_col] END)) c;
    SELECT string_agg(k, ', ') INTO v_bad FROM jsonb_object_keys(p) k WHERE k <> ALL (COALESCE(v_allowed, ARRAY[]::text[]));
    IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'Unknown field(s): %', v_bad USING ERRCODE = '22023'; END IF;
    IF p_id IS NULL THEN
        v_json := jsonb_strip_nulls(p) || CASE WHEN p_parent_col IS NULL THEN '{}'::jsonb ELSE jsonb_build_object(p_parent_col, p_parent_id) END;
        IF v_json = '{}'::jsonb THEN RAISE EXCEPTION 'Nothing to save' USING ERRCODE = '22023'; END IF;
        SELECT string_agg(quote_ident(k), ', ') INTO v_cols FROM jsonb_object_keys(v_json) k;
        RETURN sims_private.exec_dml_id(format('INSERT INTO public.%I (%s) SELECT %s FROM jsonb_populate_record(NULL::public.%I, $1) RETURNING %I::bigint', p_table, v_cols, v_cols, p_table, p_pk), v_json);
    END IF;
    IF p = '{}'::jsonb THEN RETURN p_id; END IF;
    SELECT string_agg(quote_ident(k), ', ') INTO v_cols FROM jsonb_object_keys(p) k;
    PERFORM sims_private.exec_dml(format('UPDATE public.%I t SET (%s) = (SELECT %s FROM jsonb_populate_record(NULL::public.%I, $1)) WHERE t.%I = %s', p_table, v_cols, v_cols, p_table, p_pk, p_id), p);
    RETURN p_id;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.announcement_audience_ok(p_audience text, p_department integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    WITH me AS (SELECT sims_private.current_student_id() AS sid, sims_private.current_employee_id() AS eid),
    s AS (
        SELECT (SELECT sid FROM me) IS NOT NULL AS is_student,
               EXISTS (SELECT 1 FROM student_programme_enrolment e JOIN programme p ON p.programme_id = e.programme_id
                       WHERE e.student_id = (SELECT sid FROM me) AND e.enrolment_status = 'ACTIVE' AND (p_department IS NULL OR p.department_id = p_department)) AS student_in,
               (SELECT eid FROM me) IS NOT NULL AS is_staff,
               EXISTS (SELECT 1 FROM employee_assignment a
                       WHERE a.employee_id = (SELECT eid FROM me) AND (a.end_date IS NULL OR a.end_date >= current_date) AND (p_department IS NULL OR a.department_id = p_department)) AS staff_in
    )
    SELECT CASE p_audience
        WHEN 'ALL' THEN (is_student AND student_in) OR (is_staff AND staff_in)
        WHEN 'STUDENTS' THEN is_student AND student_in
        WHEN 'STAFF' THEN is_staff AND staff_in
        WHEN 'DEPARTMENT' THEN p_department IS NOT NULL AND ((is_student AND student_in) OR (is_staff AND staff_in))
        ELSE false END
    FROM s
$function$;

CREATE OR REPLACE FUNCTION sims_private.can_employee(p_codes text[], p_id bigint, p_write boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE s sims_private.eff_set := sims_private.eff_set_of(p_codes); r record;
BEGIN
    IF s.ga AND NOT s.gd THEN RETURN true; END IF;
    IF NOT p_write AND p_id IS NOT NULL AND (s.ga OR s.sa) AND NOT (s.gd OR s.sd) AND p_id = sims_private.current_employee_id() THEN RETURN true; END IF;
    IF NOT s.ga AND cardinality(s.ai) + cardinality(s.ac) + cardinality(s.ad) + cardinality(s.ap) = 0 THEN RETURN false; END IF;
    FOR r IN SELECT e.institution_id::bigint AS i FROM public.employee e WHERE e.employee_id = p_id LOOP                       -- institution scope of the employee record
        IF (s.ga OR r.i = ANY (s.ai)) AND NOT (s.gd OR r.i = ANY (s.di)) THEN RETURN true; END IF;
    END LOOP;
    FOR r IN SELECT c.institution_id::bigint AS i, c.campus_id::bigint AS cm, a.department_id::bigint AS dp                    -- scope through a current assignment
             FROM public.employee_assignment a JOIN public.campus c ON c.campus_id = a.campus_id WHERE a.employee_id = p_id AND a.end_date IS NULL LOOP
        IF (s.ga OR r.i = ANY (s.ai) OR r.cm = ANY (s.ac) OR r.dp = ANY (s.ad)) AND NOT (s.gd OR r.i = ANY (s.di) OR r.cm = ANY (s.dc) OR r.dp = ANY (s.dd)) THEN RETURN true; END IF;
    END LOOP;
    RETURN false;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.can_student(p_codes text[], p_id bigint, p_write boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE s sims_private.eff_set := sims_private.eff_set_of(p_codes); r record;
BEGIN
    IF s.ga AND NOT s.gd THEN RETURN true; END IF;                                            -- can_global
    IF NOT p_write AND p_id IS NOT NULL AND (s.ga OR s.sa) AND NOT (s.gd OR s.sd) AND p_id = sims_private.current_student_id() THEN RETURN true; END IF; -- own record (SELF scope)
    IF NOT s.ga AND cardinality(s.ai) + cardinality(s.ac) + cardinality(s.ad) + cardinality(s.ap) = 0 THEN RETURN false; END IF;     -- no scoped grant at all: nothing to look up
    FOR r IN SELECT c.institution_id::bigint AS i, c.campus_id::bigint AS cm, d.department_id::bigint AS dp, p.programme_id::bigint AS pr
             FROM public.student_programme_enrolment e JOIN public.programme p ON p.programme_id = e.programme_id JOIN public.department d ON d.department_id = p.department_id JOIN public.campus c ON c.campus_id = d.campus_id
             WHERE e.student_id = p_id LOOP
        IF (s.ga OR r.i = ANY (s.ai) OR r.cm = ANY (s.ac) OR r.dp = ANY (s.ad) OR r.pr = ANY (s.ap))
           AND NOT (s.gd OR r.i = ANY (s.di) OR r.cm = ANY (s.dc) OR r.dp = ANY (s.dd) OR r.pr = ANY (s.dp)) THEN RETURN true; END IF;
    END LOOP;
    RETURN false;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.covers(p_codes text[], p_inst bigint, p_campus bigint, p_dept bigint, p_prog bigint, p_self_ok boolean DEFAULT false)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE s sims_private.eff_set := sims_private.eff_set_of(p_codes);
BEGIN
    RETURN (s.ga OR (p_self_ok AND s.sa) OR COALESCE(p_inst = ANY (s.ai), false) OR COALESCE(p_campus = ANY (s.ac), false) OR COALESCE(p_dept = ANY (s.ad), false) OR COALESCE(p_prog = ANY (s.ap), false))
       AND NOT (s.gd OR (p_self_ok AND s.sd) OR COALESCE(p_inst = ANY (s.di), false) OR COALESCE(p_campus = ANY (s.dc), false) OR COALESCE(p_dept = ANY (s.dd), false) OR COALESCE(p_prog = ANY (s.dp), false));
END $function$;

CREATE OR REPLACE FUNCTION sims_private.emp_is_owner(p_emp bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ SELECT COALESCE(p_emp = sims_private.current_employee_id(), false) $function$;

CREATE OR REPLACE FUNCTION sims_private.has_any_grant(p_codes text[])
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE s sims_private.eff_set := sims_private.eff_set_of(p_codes);
BEGIN
    RETURN s.ga OR s.sa OR cardinality(s.ai) + cardinality(s.ac) + cardinality(s.ad) + cardinality(s.ap) > 0;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.is_me_student(p_student bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$ SELECT COALESCE(p_student = sims_private.current_student_id(), false) $function$;

CREATE OR REPLACE FUNCTION sims_private.is_mentor_of(p_assignment_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT EXISTS (SELECT 1 FROM public.mentor_assignment a WHERE a.mentor_assignment_id = p_assignment_id AND a.employee_id = sims_private.current_employee_id())
$function$;

CREATE OR REPLACE FUNCTION public.announcements_feed(p_limit integer DEFAULT 20)
 RETURNS TABLE(announcement_id bigint, title text, description text, type_name text, department_name text, publish_from timestamp with time zone, publish_to timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT a.announcement_id::bigint, a.title::text, a.description::text, t.type_name::text, d.department_name::text, a.publish_from, a.publish_to
    FROM announcement a JOIN announcement_type t ON t.announcement_type_id = a.announcement_type_id LEFT JOIN department d ON d.department_id = a.department_id
    WHERE a.approval_status = 'APPROVED' AND a.publish_from <= now() AND (a.publish_to IS NULL OR a.publish_to > now())
      AND sims_private.announcement_audience_ok(a.audience_type, a.department_id)
    ORDER BY a.publish_from DESC, a.announcement_id DESC LIMIT LEAST(GREATEST(p_limit, 1), 100)
$function$;

CREATE OR REPLACE FUNCTION public.sims_guard_attendance_correction_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF current_user <> 'authenticated' THEN RETURN NEW; END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN (NEW.request_status IS DISTINCT FROM OLD.request_status AND (NEW.request_status IN ('APPROVED', 'REJECTED') OR OLD.request_status IN ('APPROVED', 'REJECTED'))) ELSE NEW.request_status IN ('APPROVED', 'REJECTED') END) THEN
        IF NOT sims_private.can_student(ARRAY['ATTENDANCE.ALL.APPROVE']::text[], sims_private.nx_student_programme_enrolment_enrolment_id_student_id(sims_private.nx_student_term_registration_term_registration_id_7e00744235(sims_private.nx_student_course_registration_course_registratio_92ae207afd(sims_private.nx_course_offering_section_student_course_offerin_c13eb2db9e(sims_private.nx_student_attendance_class_session_id_course_off_a5763429ec(NEW.class_session_id))))), true) THEN
            RAISE EXCEPTION 'Not authorised to APPROVE (attendance_correction_request.request_status)' USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_guard_certificate_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF current_user <> 'authenticated' THEN RETURN NEW; END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN (NEW.request_status IS DISTINCT FROM OLD.request_status AND (NEW.request_status IN ('APPROVED', 'REJECTED') OR OLD.request_status IN ('APPROVED', 'REJECTED'))) ELSE NEW.request_status IN ('APPROVED', 'REJECTED') END) THEN
        IF NOT sims_private.can_student(ARRAY['DOCUMENT.ALL.APPROVE']::text[], NEW.student_id, true) THEN
            RAISE EXCEPTION 'Not authorised to APPROVE (certificate_request.request_status)' USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_guard_conference_activity_indexing()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF current_user <> 'authenticated' THEN RETURN NEW; END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN (NEW.indexing_status IS DISTINCT FROM OLD.indexing_status AND (NEW.indexing_status IN ('VERIFIED') OR OLD.indexing_status IN ('VERIFIED'))) ELSE NEW.indexing_status IN ('VERIFIED') END) THEN
        IF NOT sims_private.can_employee(ARRAY['STAFF_PROFILE.STAFF_ACTIVITY.VERIFY']::text[], sims_private.nx_staff_activity_staff_activity_id_employee_id(sims_private.nx_conference_activity_staff_activity_id_staff_activity_id(NEW.staff_activity_id)), true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (conference_activity_indexing.indexing_status)' USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_guard_consultancy_project()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF current_user <> 'authenticated' THEN RETURN NEW; END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN (NEW.status IS DISTINCT FROM OLD.status AND (NEW.status IN ('APPROVED') OR OLD.status IN ('APPROVED'))) ELSE NEW.status IN ('APPROVED') END) THEN
        IF NOT sims_private.can_employee(ARRAY['STAFF_PROFILE.STAFF_RESEARCH.APPROVE']::text[], NEW.principal_consultant_employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to APPROVE (consultancy_project.status)' USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_guard_employee_aadhaar()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF current_user <> 'authenticated' THEN RETURN NEW; END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN (NEW.verification_status IS DISTINCT FROM OLD.verification_status AND (NEW.verification_status IN ('VERIFIED', 'REJECTED') OR OLD.verification_status IN ('VERIFIED', 'REJECTED'))) ELSE NEW.verification_status IN ('VERIFIED', 'REJECTED') END) THEN
        IF NOT sims_private.can_employee(ARRAY['EMPLOYEE.AADHAAR.VERIFY']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (employee_aadhaar.verification_status)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.verified_at IS DISTINCT FROM OLD.verified_at ELSE NEW.verified_at IS NOT NULL END) THEN
        IF NOT sims_private.can_employee(ARRAY['EMPLOYEE.AADHAAR.VERIFY']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (employee_aadhaar.verified_at)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.verified_by_user_id IS DISTINCT FROM OLD.verified_by_user_id ELSE NEW.verified_by_user_id IS NOT NULL END) THEN
        IF NOT sims_private.can_employee(ARRAY['EMPLOYEE.AADHAAR.VERIFY']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (employee_aadhaar.verified_by_user_id)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.verification_remarks IS DISTINCT FROM OLD.verification_remarks ELSE NEW.verification_remarks IS NOT NULL END) THEN
        IF NOT sims_private.can_employee(ARRAY['EMPLOYEE.AADHAAR.VERIFY']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (employee_aadhaar.verification_remarks)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF ((CASE WHEN TG_OP = 'UPDATE' THEN NEW.verified_by_user_id IS DISTINCT FROM OLD.verified_by_user_id ELSE NEW.verified_by_user_id IS NOT NULL END)
       AND NEW.verified_by_user_id IS NOT NULL AND NEW.verified_by_user_id IS DISTINCT FROM sims_private.current_user_id()) THEN
        RAISE EXCEPTION 'employee_aadhaar.verified_by_user_id must be the acting user' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_guard_employee_bank_account()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF current_user <> 'authenticated' THEN RETURN NEW; END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN (NEW.verification_status IS DISTINCT FROM OLD.verification_status AND (NEW.verification_status IN ('VERIFIED', 'REJECTED') OR OLD.verification_status IN ('VERIFIED', 'REJECTED'))) ELSE NEW.verification_status IN ('VERIFIED', 'REJECTED') END) THEN
        IF NOT sims_private.can_employee(ARRAY['EMPLOYEE.BANK_ACCOUNT.VERIFY']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (employee_bank_account.verification_status)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.verified_at IS DISTINCT FROM OLD.verified_at ELSE NEW.verified_at IS NOT NULL END) THEN
        IF NOT sims_private.can_employee(ARRAY['EMPLOYEE.BANK_ACCOUNT.VERIFY']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (employee_bank_account.verified_at)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.verified_by_user_id IS DISTINCT FROM OLD.verified_by_user_id ELSE NEW.verified_by_user_id IS NOT NULL END) THEN
        IF NOT sims_private.can_employee(ARRAY['EMPLOYEE.BANK_ACCOUNT.VERIFY']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (employee_bank_account.verified_by_user_id)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.verification_remarks IS DISTINCT FROM OLD.verification_remarks ELSE NEW.verification_remarks IS NOT NULL END) THEN
        IF NOT sims_private.can_employee(ARRAY['EMPLOYEE.BANK_ACCOUNT.VERIFY']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (employee_bank_account.verification_remarks)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF ((CASE WHEN TG_OP = 'UPDATE' THEN NEW.verified_by_user_id IS DISTINCT FROM OLD.verified_by_user_id ELSE NEW.verified_by_user_id IS NOT NULL END)
       AND NEW.verified_by_user_id IS NOT NULL AND NEW.verified_by_user_id IS DISTINCT FROM sims_private.current_user_id()) THEN
        RAISE EXCEPTION 'employee_bank_account.verified_by_user_id must be the acting user' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_guard_employee_document()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF current_user <> 'authenticated' THEN RETURN NEW; END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN (NEW.verification_status IS DISTINCT FROM OLD.verification_status AND (NEW.verification_status IN ('VERIFIED', 'REJECTED') OR OLD.verification_status IN ('VERIFIED', 'REJECTED'))) ELSE NEW.verification_status IN ('VERIFIED', 'REJECTED') END) THEN
        IF NOT sims_private.can_employee(ARRAY['EMPLOYEE.EMPLOYEE_DOCUMENT.VERIFY']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (employee_document.verification_status)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN (NEW.approval_status IS DISTINCT FROM OLD.approval_status AND (NEW.approval_status IN ('APPROVED', 'REJECTED') OR OLD.approval_status IN ('APPROVED', 'REJECTED'))) ELSE NEW.approval_status IN ('APPROVED', 'REJECTED') END) THEN
        IF NOT sims_private.can_employee(ARRAY['EMPLOYEE.EMPLOYEE_DOCUMENT.APPROVE']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to APPROVE (employee_document.approval_status)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.approved_at IS DISTINCT FROM OLD.approved_at ELSE NEW.approved_at IS NOT NULL END) THEN
        IF NOT sims_private.can_employee(ARRAY['EMPLOYEE.EMPLOYEE_DOCUMENT.APPROVE']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to APPROVE (employee_document.approved_at)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.approved_by_user_id IS DISTINCT FROM OLD.approved_by_user_id ELSE NEW.approved_by_user_id IS NOT NULL END) THEN
        IF NOT sims_private.can_employee(ARRAY['EMPLOYEE.EMPLOYEE_DOCUMENT.APPROVE']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to APPROVE (employee_document.approved_by_user_id)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.approval_remarks IS DISTINCT FROM OLD.approval_remarks ELSE NEW.approval_remarks IS NOT NULL END) THEN
        IF NOT sims_private.can_employee(ARRAY['EMPLOYEE.EMPLOYEE_DOCUMENT.APPROVE']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to APPROVE (employee_document.approval_remarks)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.verified_at IS DISTINCT FROM OLD.verified_at ELSE NEW.verified_at IS NOT NULL END) THEN
        IF NOT sims_private.can_employee(ARRAY['EMPLOYEE.EMPLOYEE_DOCUMENT.VERIFY']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (employee_document.verified_at)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.verified_by_user_id IS DISTINCT FROM OLD.verified_by_user_id ELSE NEW.verified_by_user_id IS NOT NULL END) THEN
        IF NOT sims_private.can_employee(ARRAY['EMPLOYEE.EMPLOYEE_DOCUMENT.VERIFY']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (employee_document.verified_by_user_id)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.verification_remarks IS DISTINCT FROM OLD.verification_remarks ELSE NEW.verification_remarks IS NOT NULL END) THEN
        IF NOT sims_private.can_employee(ARRAY['EMPLOYEE.EMPLOYEE_DOCUMENT.VERIFY']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (employee_document.verification_remarks)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF ((CASE WHEN TG_OP = 'UPDATE' THEN NEW.approved_by_user_id IS DISTINCT FROM OLD.approved_by_user_id ELSE NEW.approved_by_user_id IS NOT NULL END)
       AND NEW.approved_by_user_id IS NOT NULL AND NEW.approved_by_user_id IS DISTINCT FROM sims_private.current_user_id()) THEN
        RAISE EXCEPTION 'employee_document.approved_by_user_id must be the acting user' USING ERRCODE = '42501';
    END IF;
    IF ((CASE WHEN TG_OP = 'UPDATE' THEN NEW.verified_by_user_id IS DISTINCT FROM OLD.verified_by_user_id ELSE NEW.verified_by_user_id IS NOT NULL END)
       AND NEW.verified_by_user_id IS NOT NULL AND NEW.verified_by_user_id IS DISTINCT FROM sims_private.current_user_id()) THEN
        RAISE EXCEPTION 'employee_document.verified_by_user_id must be the acting user' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_guard_employee_pan()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF current_user <> 'authenticated' THEN RETURN NEW; END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN (NEW.verification_status IS DISTINCT FROM OLD.verification_status AND (NEW.verification_status IN ('VERIFIED', 'REJECTED') OR OLD.verification_status IN ('VERIFIED', 'REJECTED'))) ELSE NEW.verification_status IN ('VERIFIED', 'REJECTED') END) THEN
        IF NOT sims_private.can_employee(ARRAY['EMPLOYEE.PAN.VERIFY']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (employee_pan.verification_status)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.verified_at IS DISTINCT FROM OLD.verified_at ELSE NEW.verified_at IS NOT NULL END) THEN
        IF NOT sims_private.can_employee(ARRAY['EMPLOYEE.PAN.VERIFY']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (employee_pan.verified_at)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.verified_by_user_id IS DISTINCT FROM OLD.verified_by_user_id ELSE NEW.verified_by_user_id IS NOT NULL END) THEN
        IF NOT sims_private.can_employee(ARRAY['EMPLOYEE.PAN.VERIFY']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (employee_pan.verified_by_user_id)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.verification_remarks IS DISTINCT FROM OLD.verification_remarks ELSE NEW.verification_remarks IS NOT NULL END) THEN
        IF NOT sims_private.can_employee(ARRAY['EMPLOYEE.PAN.VERIFY']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (employee_pan.verification_remarks)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF ((CASE WHEN TG_OP = 'UPDATE' THEN NEW.verified_by_user_id IS DISTINCT FROM OLD.verified_by_user_id ELSE NEW.verified_by_user_id IS NOT NULL END)
       AND NEW.verified_by_user_id IS NOT NULL AND NEW.verified_by_user_id IS DISTINCT FROM sims_private.current_user_id()) THEN
        RAISE EXCEPTION 'employee_pan.verified_by_user_id must be the acting user' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_guard_evidence_document()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF current_user <> 'authenticated' THEN RETURN NEW; END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN (NEW.approval_status_id IS DISTINCT FROM OLD.approval_status_id AND ((SELECT l.status_code FROM approval_status l WHERE l.approval_status_id = NEW.approval_status_id) IN ('APPROVED', 'REJECTED') OR (SELECT l.status_code FROM approval_status l WHERE l.approval_status_id = OLD.approval_status_id) IN ('APPROVED', 'REJECTED'))) ELSE (SELECT l.status_code FROM approval_status l WHERE l.approval_status_id = NEW.approval_status_id) IN ('APPROVED', 'REJECTED') END) THEN
        IF NOT sims_private.can_employee(ARRAY['STAFF_PROFILE.STAFF_EVIDENCE.APPROVE']::text[], sims_private.nx_staff_activity_staff_activity_id_employee_id(NEW.staff_activity_id), true) THEN
            RAISE EXCEPTION 'Not authorised to APPROVE (evidence_document.approval_status_id)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN (NEW.verification_status_id IS DISTINCT FROM OLD.verification_status_id AND ((SELECT l.status_code FROM verification_status l WHERE l.verification_status_id = NEW.verification_status_id) IN ('VERIFIED', 'REJECTED', 'NEEDS_CORRECTION') OR (SELECT l.status_code FROM verification_status l WHERE l.verification_status_id = OLD.verification_status_id) IN ('VERIFIED', 'REJECTED', 'NEEDS_CORRECTION'))) ELSE (SELECT l.status_code FROM verification_status l WHERE l.verification_status_id = NEW.verification_status_id) IN ('VERIFIED', 'REJECTED', 'NEEDS_CORRECTION') END) THEN
        IF NOT sims_private.can_employee(ARRAY['STAFF_PROFILE.STAFF_EVIDENCE.VERIFY']::text[], sims_private.nx_staff_activity_staff_activity_id_employee_id(NEW.staff_activity_id), true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (evidence_document.verification_status_id)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.approved_at IS DISTINCT FROM OLD.approved_at ELSE NEW.approved_at IS NOT NULL END) THEN
        IF NOT sims_private.can_employee(ARRAY['STAFF_PROFILE.STAFF_EVIDENCE.APPROVE']::text[], sims_private.nx_staff_activity_staff_activity_id_employee_id(NEW.staff_activity_id), true) THEN
            RAISE EXCEPTION 'Not authorised to APPROVE (evidence_document.approved_at)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.approved_by_user_id IS DISTINCT FROM OLD.approved_by_user_id ELSE NEW.approved_by_user_id IS NOT NULL END) THEN
        IF NOT sims_private.can_employee(ARRAY['STAFF_PROFILE.STAFF_EVIDENCE.APPROVE']::text[], sims_private.nx_staff_activity_staff_activity_id_employee_id(NEW.staff_activity_id), true) THEN
            RAISE EXCEPTION 'Not authorised to APPROVE (evidence_document.approved_by_user_id)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.verified_at IS DISTINCT FROM OLD.verified_at ELSE NEW.verified_at IS NOT NULL END) THEN
        IF NOT sims_private.can_employee(ARRAY['STAFF_PROFILE.STAFF_EVIDENCE.VERIFY']::text[], sims_private.nx_staff_activity_staff_activity_id_employee_id(NEW.staff_activity_id), true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (evidence_document.verified_at)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.verified_by_user_id IS DISTINCT FROM OLD.verified_by_user_id ELSE NEW.verified_by_user_id IS NOT NULL END) THEN
        IF NOT sims_private.can_employee(ARRAY['STAFF_PROFILE.STAFF_EVIDENCE.VERIFY']::text[], sims_private.nx_staff_activity_staff_activity_id_employee_id(NEW.staff_activity_id), true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (evidence_document.verified_by_user_id)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.verification_remarks IS DISTINCT FROM OLD.verification_remarks ELSE NEW.verification_remarks IS NOT NULL END) THEN
        IF NOT sims_private.can_employee(ARRAY['STAFF_PROFILE.STAFF_EVIDENCE.VERIFY']::text[], sims_private.nx_staff_activity_staff_activity_id_employee_id(NEW.staff_activity_id), true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (evidence_document.verification_remarks)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF ((CASE WHEN TG_OP = 'UPDATE' THEN NEW.approved_by_user_id IS DISTINCT FROM OLD.approved_by_user_id ELSE NEW.approved_by_user_id IS NOT NULL END)
       AND NEW.approved_by_user_id IS NOT NULL AND NEW.approved_by_user_id IS DISTINCT FROM sims_private.current_user_id()) THEN
        RAISE EXCEPTION 'evidence_document.approved_by_user_id must be the acting user' USING ERRCODE = '42501';
    END IF;
    IF ((CASE WHEN TG_OP = 'UPDATE' THEN NEW.verified_by_user_id IS DISTINCT FROM OLD.verified_by_user_id ELSE NEW.verified_by_user_id IS NOT NULL END)
       AND NEW.verified_by_user_id IS NOT NULL AND NEW.verified_by_user_id IS DISTINCT FROM sims_private.current_user_id()) THEN
        RAISE EXCEPTION 'evidence_document.verified_by_user_id must be the acting user' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_guard_journal_publication_indexing()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF current_user <> 'authenticated' THEN RETURN NEW; END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN (NEW.indexing_status IS DISTINCT FROM OLD.indexing_status AND (NEW.indexing_status IN ('VERIFIED') OR OLD.indexing_status IN ('VERIFIED'))) ELSE NEW.indexing_status IN ('VERIFIED') END) THEN
        IF NOT sims_private.can_employee(ARRAY['STAFF_PROFILE.STAFF_ACTIVITY.VERIFY']::text[], sims_private.nx_staff_activity_staff_activity_id_employee_id(sims_private.nx_journal_publication_staff_activity_id_staff_activity_id(NEW.staff_activity_id)), true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (journal_publication_indexing.indexing_status)' USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_guard_staff_activity()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF current_user <> 'authenticated' THEN RETURN NEW; END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN (NEW.approval_status_id IS DISTINCT FROM OLD.approval_status_id AND ((SELECT l.status_code FROM approval_status l WHERE l.approval_status_id = NEW.approval_status_id) IN ('APPROVED', 'REJECTED') OR (SELECT l.status_code FROM approval_status l WHERE l.approval_status_id = OLD.approval_status_id) IN ('APPROVED', 'REJECTED'))) ELSE (SELECT l.status_code FROM approval_status l WHERE l.approval_status_id = NEW.approval_status_id) IN ('APPROVED', 'REJECTED') END) THEN
        IF NOT sims_private.can_employee(ARRAY['STAFF_PROFILE.STAFF_ACTIVITY.APPROVE']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to APPROVE (staff_activity.approval_status_id)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN (NEW.verification_status_id IS DISTINCT FROM OLD.verification_status_id AND ((SELECT l.status_code FROM verification_status l WHERE l.verification_status_id = NEW.verification_status_id) IN ('VERIFIED', 'REJECTED', 'NEEDS_CORRECTION') OR (SELECT l.status_code FROM verification_status l WHERE l.verification_status_id = OLD.verification_status_id) IN ('VERIFIED', 'REJECTED', 'NEEDS_CORRECTION'))) ELSE (SELECT l.status_code FROM verification_status l WHERE l.verification_status_id = NEW.verification_status_id) IN ('VERIFIED', 'REJECTED', 'NEEDS_CORRECTION') END) THEN
        IF NOT sims_private.can_employee(ARRAY['STAFF_PROFILE.STAFF_ACTIVITY.VERIFY']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (staff_activity.verification_status_id)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.approved_at IS DISTINCT FROM OLD.approved_at ELSE NEW.approved_at IS NOT NULL END) THEN
        IF NOT sims_private.can_employee(ARRAY['STAFF_PROFILE.STAFF_ACTIVITY.APPROVE']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to APPROVE (staff_activity.approved_at)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.approved_by_user_id IS DISTINCT FROM OLD.approved_by_user_id ELSE NEW.approved_by_user_id IS NOT NULL END) THEN
        IF NOT sims_private.can_employee(ARRAY['STAFF_PROFILE.STAFF_ACTIVITY.APPROVE']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to APPROVE (staff_activity.approved_by_user_id)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.approval_remarks IS DISTINCT FROM OLD.approval_remarks ELSE NEW.approval_remarks IS NOT NULL END) THEN
        IF NOT sims_private.can_employee(ARRAY['STAFF_PROFILE.STAFF_ACTIVITY.APPROVE']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to APPROVE (staff_activity.approval_remarks)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.verified_at IS DISTINCT FROM OLD.verified_at ELSE NEW.verified_at IS NOT NULL END) THEN
        IF NOT sims_private.can_employee(ARRAY['STAFF_PROFILE.STAFF_ACTIVITY.VERIFY']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (staff_activity.verified_at)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.verified_by_user_id IS DISTINCT FROM OLD.verified_by_user_id ELSE NEW.verified_by_user_id IS NOT NULL END) THEN
        IF NOT sims_private.can_employee(ARRAY['STAFF_PROFILE.STAFF_ACTIVITY.VERIFY']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (staff_activity.verified_by_user_id)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.verification_remarks IS DISTINCT FROM OLD.verification_remarks ELSE NEW.verification_remarks IS NOT NULL END) THEN
        IF NOT sims_private.can_employee(ARRAY['STAFF_PROFILE.STAFF_ACTIVITY.VERIFY']::text[], NEW.employee_id, true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (staff_activity.verification_remarks)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF ((CASE WHEN TG_OP = 'UPDATE' THEN NEW.approved_by_user_id IS DISTINCT FROM OLD.approved_by_user_id ELSE NEW.approved_by_user_id IS NOT NULL END)
       AND NEW.approved_by_user_id IS NOT NULL AND NEW.approved_by_user_id IS DISTINCT FROM sims_private.current_user_id()) THEN
        RAISE EXCEPTION 'staff_activity.approved_by_user_id must be the acting user' USING ERRCODE = '42501';
    END IF;
    IF ((CASE WHEN TG_OP = 'UPDATE' THEN NEW.verified_by_user_id IS DISTINCT FROM OLD.verified_by_user_id ELSE NEW.verified_by_user_id IS NOT NULL END)
       AND NEW.verified_by_user_id IS NOT NULL AND NEW.verified_by_user_id IS DISTINCT FROM sims_private.current_user_id()) THEN
        RAISE EXCEPTION 'staff_activity.verified_by_user_id must be the acting user' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_guard_student_activity()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF current_user <> 'authenticated' THEN RETURN NEW; END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN (NEW.approval_status_id IS DISTINCT FROM OLD.approval_status_id AND ((SELECT l.status_code FROM approval_status l WHERE l.approval_status_id = NEW.approval_status_id) IN ('APPROVED', 'REJECTED') OR (SELECT l.status_code FROM approval_status l WHERE l.approval_status_id = OLD.approval_status_id) IN ('APPROVED', 'REJECTED'))) ELSE (SELECT l.status_code FROM approval_status l WHERE l.approval_status_id = NEW.approval_status_id) IN ('APPROVED', 'REJECTED') END) THEN
        IF NOT sims_private.can_student(ARRAY['STUDENT.STUDENT_ACTIVITY.APPROVE']::text[], NEW.student_id, true) THEN
            RAISE EXCEPTION 'Not authorised to APPROVE (student_activity.approval_status_id)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN (NEW.verification_status_id IS DISTINCT FROM OLD.verification_status_id AND ((SELECT l.status_code FROM verification_status l WHERE l.verification_status_id = NEW.verification_status_id) IN ('VERIFIED', 'REJECTED', 'NEEDS_CORRECTION') OR (SELECT l.status_code FROM verification_status l WHERE l.verification_status_id = OLD.verification_status_id) IN ('VERIFIED', 'REJECTED', 'NEEDS_CORRECTION'))) ELSE (SELECT l.status_code FROM verification_status l WHERE l.verification_status_id = NEW.verification_status_id) IN ('VERIFIED', 'REJECTED', 'NEEDS_CORRECTION') END) THEN
        IF NOT sims_private.can_student(ARRAY['STUDENT.STUDENT_ACTIVITY.VERIFY']::text[], NEW.student_id, true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (student_activity.verification_status_id)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.approved_at IS DISTINCT FROM OLD.approved_at ELSE NEW.approved_at IS NOT NULL END) THEN
        IF NOT sims_private.can_student(ARRAY['STUDENT.STUDENT_ACTIVITY.APPROVE']::text[], NEW.student_id, true) THEN
            RAISE EXCEPTION 'Not authorised to APPROVE (student_activity.approved_at)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.approved_by_user_id IS DISTINCT FROM OLD.approved_by_user_id ELSE NEW.approved_by_user_id IS NOT NULL END) THEN
        IF NOT sims_private.can_student(ARRAY['STUDENT.STUDENT_ACTIVITY.APPROVE']::text[], NEW.student_id, true) THEN
            RAISE EXCEPTION 'Not authorised to APPROVE (student_activity.approved_by_user_id)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.approval_remarks IS DISTINCT FROM OLD.approval_remarks ELSE NEW.approval_remarks IS NOT NULL END) THEN
        IF NOT sims_private.can_student(ARRAY['STUDENT.STUDENT_ACTIVITY.APPROVE']::text[], NEW.student_id, true) THEN
            RAISE EXCEPTION 'Not authorised to APPROVE (student_activity.approval_remarks)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.verified_at IS DISTINCT FROM OLD.verified_at ELSE NEW.verified_at IS NOT NULL END) THEN
        IF NOT sims_private.can_student(ARRAY['STUDENT.STUDENT_ACTIVITY.VERIFY']::text[], NEW.student_id, true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (student_activity.verified_at)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.verified_by_user_id IS DISTINCT FROM OLD.verified_by_user_id ELSE NEW.verified_by_user_id IS NOT NULL END) THEN
        IF NOT sims_private.can_student(ARRAY['STUDENT.STUDENT_ACTIVITY.VERIFY']::text[], NEW.student_id, true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (student_activity.verified_by_user_id)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.verification_remarks IS DISTINCT FROM OLD.verification_remarks ELSE NEW.verification_remarks IS NOT NULL END) THEN
        IF NOT sims_private.can_student(ARRAY['STUDENT.STUDENT_ACTIVITY.VERIFY']::text[], NEW.student_id, true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (student_activity.verification_remarks)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF ((CASE WHEN TG_OP = 'UPDATE' THEN NEW.approved_by_user_id IS DISTINCT FROM OLD.approved_by_user_id ELSE NEW.approved_by_user_id IS NOT NULL END)
       AND NEW.approved_by_user_id IS NOT NULL AND NEW.approved_by_user_id IS DISTINCT FROM sims_private.current_user_id()) THEN
        RAISE EXCEPTION 'student_activity.approved_by_user_id must be the acting user' USING ERRCODE = '42501';
    END IF;
    IF ((CASE WHEN TG_OP = 'UPDATE' THEN NEW.verified_by_user_id IS DISTINCT FROM OLD.verified_by_user_id ELSE NEW.verified_by_user_id IS NOT NULL END)
       AND NEW.verified_by_user_id IS NOT NULL AND NEW.verified_by_user_id IS DISTINCT FROM sims_private.current_user_id()) THEN
        RAISE EXCEPTION 'student_activity.verified_by_user_id must be the acting user' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_guard_student_activity_evidence()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF current_user <> 'authenticated' THEN RETURN NEW; END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN (NEW.approval_status_id IS DISTINCT FROM OLD.approval_status_id AND ((SELECT l.status_code FROM approval_status l WHERE l.approval_status_id = NEW.approval_status_id) IN ('APPROVED', 'REJECTED') OR (SELECT l.status_code FROM approval_status l WHERE l.approval_status_id = OLD.approval_status_id) IN ('APPROVED', 'REJECTED'))) ELSE (SELECT l.status_code FROM approval_status l WHERE l.approval_status_id = NEW.approval_status_id) IN ('APPROVED', 'REJECTED') END) THEN
        IF NOT sims_private.can_student(ARRAY['STUDENT.STUDENT_ACTIVITY_EVIDENCE.APPROVE']::text[], sims_private.nx_student_activity_student_activity_id_student_id(NEW.student_activity_id), true) THEN
            RAISE EXCEPTION 'Not authorised to APPROVE (student_activity_evidence.approval_status_id)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN (NEW.verification_status_id IS DISTINCT FROM OLD.verification_status_id AND ((SELECT l.status_code FROM verification_status l WHERE l.verification_status_id = NEW.verification_status_id) IN ('VERIFIED', 'REJECTED', 'NEEDS_CORRECTION') OR (SELECT l.status_code FROM verification_status l WHERE l.verification_status_id = OLD.verification_status_id) IN ('VERIFIED', 'REJECTED', 'NEEDS_CORRECTION'))) ELSE (SELECT l.status_code FROM verification_status l WHERE l.verification_status_id = NEW.verification_status_id) IN ('VERIFIED', 'REJECTED', 'NEEDS_CORRECTION') END) THEN
        IF NOT sims_private.can_student(ARRAY['STUDENT.STUDENT_ACTIVITY_EVIDENCE.VERIFY']::text[], sims_private.nx_student_activity_student_activity_id_student_id(NEW.student_activity_id), true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (student_activity_evidence.verification_status_id)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.approved_at IS DISTINCT FROM OLD.approved_at ELSE NEW.approved_at IS NOT NULL END) THEN
        IF NOT sims_private.can_student(ARRAY['STUDENT.STUDENT_ACTIVITY_EVIDENCE.APPROVE']::text[], sims_private.nx_student_activity_student_activity_id_student_id(NEW.student_activity_id), true) THEN
            RAISE EXCEPTION 'Not authorised to APPROVE (student_activity_evidence.approved_at)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.approved_by_user_id IS DISTINCT FROM OLD.approved_by_user_id ELSE NEW.approved_by_user_id IS NOT NULL END) THEN
        IF NOT sims_private.can_student(ARRAY['STUDENT.STUDENT_ACTIVITY_EVIDENCE.APPROVE']::text[], sims_private.nx_student_activity_student_activity_id_student_id(NEW.student_activity_id), true) THEN
            RAISE EXCEPTION 'Not authorised to APPROVE (student_activity_evidence.approved_by_user_id)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.verified_at IS DISTINCT FROM OLD.verified_at ELSE NEW.verified_at IS NOT NULL END) THEN
        IF NOT sims_private.can_student(ARRAY['STUDENT.STUDENT_ACTIVITY_EVIDENCE.VERIFY']::text[], sims_private.nx_student_activity_student_activity_id_student_id(NEW.student_activity_id), true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (student_activity_evidence.verified_at)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.verified_by_user_id IS DISTINCT FROM OLD.verified_by_user_id ELSE NEW.verified_by_user_id IS NOT NULL END) THEN
        IF NOT sims_private.can_student(ARRAY['STUDENT.STUDENT_ACTIVITY_EVIDENCE.VERIFY']::text[], sims_private.nx_student_activity_student_activity_id_student_id(NEW.student_activity_id), true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (student_activity_evidence.verified_by_user_id)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.verification_remarks IS DISTINCT FROM OLD.verification_remarks ELSE NEW.verification_remarks IS NOT NULL END) THEN
        IF NOT sims_private.can_student(ARRAY['STUDENT.STUDENT_ACTIVITY_EVIDENCE.VERIFY']::text[], sims_private.nx_student_activity_student_activity_id_student_id(NEW.student_activity_id), true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (student_activity_evidence.verification_remarks)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF ((CASE WHEN TG_OP = 'UPDATE' THEN NEW.approved_by_user_id IS DISTINCT FROM OLD.approved_by_user_id ELSE NEW.approved_by_user_id IS NOT NULL END)
       AND NEW.approved_by_user_id IS NOT NULL AND NEW.approved_by_user_id IS DISTINCT FROM sims_private.current_user_id()) THEN
        RAISE EXCEPTION 'student_activity_evidence.approved_by_user_id must be the acting user' USING ERRCODE = '42501';
    END IF;
    IF ((CASE WHEN TG_OP = 'UPDATE' THEN NEW.verified_by_user_id IS DISTINCT FROM OLD.verified_by_user_id ELSE NEW.verified_by_user_id IS NOT NULL END)
       AND NEW.verified_by_user_id IS NOT NULL AND NEW.verified_by_user_id IS DISTINCT FROM sims_private.current_user_id()) THEN
        RAISE EXCEPTION 'student_activity_evidence.verified_by_user_id must be the acting user' USING ERRCODE = '42501';
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_guard_student_course_registration()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF current_user <> 'authenticated' THEN RETURN NEW; END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN (NEW.registration_status IS DISTINCT FROM OLD.registration_status AND (NEW.registration_status IN ('APPROVED', 'REJECTED') OR OLD.registration_status IN ('APPROVED', 'REJECTED'))) ELSE NEW.registration_status IN ('APPROVED', 'REJECTED') END) THEN
        IF NOT sims_private.can_student(ARRAY['REGISTRATION.ALL.APPROVE']::text[], sims_private.nx_student_programme_enrolment_enrolment_id_student_id(sims_private.nx_student_term_registration_term_registration_id_7e00744235(NEW.term_registration_id)), true) THEN
            RAISE EXCEPTION 'Not authorised to APPROVE (student_course_registration.registration_status)' USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_guard_student_document()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF current_user <> 'authenticated' THEN RETURN NEW; END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN (NEW.verification_status IS DISTINCT FROM OLD.verification_status AND (NEW.verification_status IN ('VERIFIED', 'REJECTED') OR OLD.verification_status IN ('VERIFIED', 'REJECTED'))) ELSE NEW.verification_status IN ('VERIFIED', 'REJECTED') END) THEN
        IF NOT sims_private.can_student(ARRAY['DOCUMENT.ALL.VERIFY']::text[], NEW.student_id, true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (student_document.verification_status)' USING ERRCODE = '42501';
        END IF;
    END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.verified_at IS DISTINCT FROM OLD.verified_at ELSE NEW.verified_at IS NOT NULL END) THEN
        IF NOT sims_private.can_student(ARRAY['DOCUMENT.ALL.VERIFY']::text[], NEW.student_id, true) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (student_document.verified_at)' USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_guard_student_term_registration()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF current_user <> 'authenticated' THEN RETURN NEW; END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN (NEW.registration_status IS DISTINCT FROM OLD.registration_status AND (NEW.registration_status IN ('APPROVED', 'REJECTED') OR OLD.registration_status IN ('APPROVED', 'REJECTED'))) ELSE NEW.registration_status IN ('APPROVED', 'REJECTED') END) THEN
        IF NOT sims_private.can_student(ARRAY['REGISTRATION.ALL.APPROVE']::text[], sims_private.nx_student_programme_enrolment_enrolment_id_student_id(NEW.enrolment_id), true) THEN
            RAISE EXCEPTION 'Not authorised to APPROVE (student_term_registration.registration_status)' USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_guard_student_term_result()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF current_user <> 'authenticated' THEN RETURN NEW; END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.published_at IS DISTINCT FROM OLD.published_at ELSE NEW.published_at IS NOT NULL END) THEN
        IF NOT sims_private.can_student(ARRAY['RESULT.ALL.PUBLISH']::text[], sims_private.nx_student_programme_enrolment_enrolment_id_student_id(sims_private.nx_student_term_registration_term_registration_id_7e00744235(NEW.term_registration_id)), true) THEN
            RAISE EXCEPTION 'Not authorised to PUBLISH (student_term_result.published_at)' USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.activity_actor(p_student bigint, p_perm text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT CASE WHEN COALESCE(p_student = sims_private.current_student_id(), false) THEN 'owner'
                WHEN sims_private.can_student(ARRAY[p_perm]::text[], p_student, true) THEN 'staff' END
$function$;

CREATE OR REPLACE FUNCTION sims_private.can_global(p_codes text[])
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT sims_private.covers(p_codes, NULL, NULL, NULL, NULL, false)
$function$;

CREATE OR REPLACE FUNCTION sims_private.can_institution(p_codes text[], p_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT sims_private.covers(p_codes, p_id, NULL, NULL, NULL, false)
$function$;

CREATE OR REPLACE FUNCTION sims_private.can_use_employee_doc_path(p_name text, p_write boolean)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT COALESCE(sims_private.doc_employee_id(p_name) = sims_private.current_employee_id()
                    OR sims_private.can_employee(ARRAY[CASE WHEN p_write THEN 'STAFF_PROFILE.STAFF_EVIDENCE.CREATE' ELSE 'STAFF_PROFILE.STAFF_EVIDENCE.READ' END]::text[], sims_private.doc_employee_id(p_name), p_write), false)
$function$;

CREATE OR REPLACE FUNCTION sims_private.can_use_student_doc_path(p_name text, p_write boolean)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT COALESCE(
      CASE WHEN p_name LIKE 'employee/%' THEN
        sims_private.doc_employee_id(p_name) = sims_private.current_employee_id()
        OR sims_private.can_employee(ARRAY[CASE WHEN p_write THEN 'EMPLOYEE.EMPLOYEE_DOCUMENT.CREATE' ELSE 'EMPLOYEE.EMPLOYEE_DOCUMENT.READ' END]::text[], sims_private.doc_employee_id(p_name), p_write)
        OR (NOT p_write AND EXISTS (SELECT 1 FROM file_object f JOIN employee_document d ON d.file_object_id = f.file_object_id WHERE f.storage_key = p_name AND d.deleted_at IS NULL AND sims_private.emp_doc_rule_ok(d.employee_document_id, 'download')))
      ELSE
        sims_private.doc_student_id(p_name) = sims_private.current_student_id()
        OR sims_private.can_student(ARRAY[CASE WHEN p_write THEN 'DOCUMENT.ALL.CREATE' ELSE 'DOCUMENT.ALL.READ' END]::text[], sims_private.doc_student_id(p_name), p_write)
      END, false)
$function$;

CREATE OR REPLACE FUNCTION sims_private.emp_all_can(p_emp bigint, p_action text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT COALESCE(p_emp IS NOT NULL AND sims_private.can_employee(ARRAY['EMPLOYEE.ALL.' || p_action]::text[], p_emp, p_action <> 'READ'), false)
$function$;

CREATE OR REPLACE FUNCTION sims_private.emp_can(p_emp bigint, p_resource text, p_action text, p_write boolean)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT p_emp IS NOT NULL AND sims_private.can_employee(ARRAY['EMPLOYEE.' || p_resource || '.' || p_action]::text[], p_emp, p_write)
$function$;

CREATE OR REPLACE FUNCTION sims_private.fin_authorize(p_student_account_id bigint, p_resource text, p_action text)
 RETURNS bigint
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_student bigint;
BEGIN
    SELECT student_id INTO v_student FROM public.student_financial_account WHERE student_account_id = p_student_account_id;
    -- Same error for "unknown" and "out of scope": no account enumeration.
    IF v_student IS NULL OR NOT sims_private.can_student(ARRAY['FEES.' || p_resource || '.' || p_action]::text[], v_student, true) THEN
        RAISE EXCEPTION 'Not authorised (FEES.%.%) or unknown account', p_resource, p_action USING ERRCODE = '42501';
    END IF;
    RETURN v_student;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.fin_authorize_student(p_student_id bigint, p_resource text, p_action text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF p_student_id IS NULL OR NOT sims_private.can_student(ARRAY['FEES.' || p_resource || '.' || p_action]::text[], p_student_id, true) THEN
        RAISE EXCEPTION 'Not authorised (FEES.%.%) or unknown student', p_resource, p_action USING ERRCODE = '42501';
    END IF;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.mentoring_can_see(p_assignment_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT COALESCE((SELECT sims_private.can_student(ARRAY['MENTORING.ALL.READ']::text[], a.student_id, false) OR a.employee_id = sims_private.current_employee_id()
                     FROM public.mentor_assignment a WHERE a.mentor_assignment_id = p_assignment_id), false)
$function$;

CREATE OR REPLACE FUNCTION sims_private.staff_actor(p_employee bigint, p_perm text)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT CASE WHEN COALESCE(p_employee = sims_private.current_employee_id(), false) THEN 'owner'
                WHEN sims_private.can_employee(ARRAY[p_perm]::text[], p_employee, true) THEN 'staff' END
$function$;

CREATE OR REPLACE FUNCTION public.sims_guard_journal_metric()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF current_user <> 'authenticated' THEN RETURN NEW; END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN NEW.verified_at IS DISTINCT FROM OLD.verified_at ELSE NEW.verified_at IS NOT NULL END) THEN
        IF NOT sims_private.can_global(ARRAY['STAFF_PROFILE.ALL.VERIFY']::text[]) THEN
            RAISE EXCEPTION 'Not authorised to VERIFY (journal_metric.verified_at)' USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.activity_child_ok(p_activity_id bigint, p_detail_table text, p_perm_prefix text, p_action text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE a record; v_ok boolean;
BEGIN
    SELECT x.employee_id, aps.status_code AS acode INTO a FROM staff_activity x JOIN approval_status aps ON aps.approval_status_id = x.approval_status_id WHERE x.staff_activity_id = p_activity_id AND x.deleted_at IS NULL;
    IF a.employee_id IS NULL THEN RETURN false; END IF;
    EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I WHERE staff_activity_id = $1)', p_detail_table) INTO v_ok USING p_activity_id;
    IF NOT v_ok THEN RETURN false; END IF;
    IF p_action = 'READ' THEN RETURN COALESCE(a.employee_id = sims_private.current_employee_id(), false) OR sims_private.can_employee(ARRAY[p_perm_prefix || '.READ']::text[], a.employee_id, false); END IF;
    IF a.acode NOT IN ('DRAFT', 'APPROVED') THEN RETURN false; END IF;
    RETURN sims_private.staff_actor(a.employee_id, p_perm_prefix || '.' || p_action) IS NOT NULL;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.can_campus(p_codes text[], p_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT COALESCE((SELECT sims_private.covers(p_codes, c.institution_id, c.campus_id, NULL, NULL, false)
                     FROM public.campus c WHERE c.campus_id = p_id),
                    sims_private.can_global(p_codes))
$function$;

CREATE OR REPLACE FUNCTION sims_private.can_department(p_codes text[], p_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT COALESCE((SELECT sims_private.covers(p_codes, c.institution_id, c.campus_id, d.department_id, NULL, false)
                     FROM public.department d JOIN public.campus c ON c.campus_id = d.campus_id
                     WHERE d.department_id = p_id),
                    sims_private.can_global(p_codes))
$function$;

CREATE OR REPLACE FUNCTION sims_private.can_programme(p_codes text[], p_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT COALESCE((SELECT sims_private.covers(p_codes, c.institution_id, c.campus_id, d.department_id, p.programme_id, false)
                     FROM public.programme p
                     JOIN public.department d ON d.department_id = p.department_id
                     JOIN public.campus c ON c.campus_id = d.campus_id
                     WHERE p.programme_id = p_id),
                    sims_private.can_global(p_codes))
$function$;

CREATE OR REPLACE FUNCTION sims_private.can_user(p_codes text[], p_id bigint, p_write boolean)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT sims_private.can_global(p_codes)
        OR (NOT p_write AND p_id IS NOT NULL AND p_id = sims_private.current_user_id())
$function$;

CREATE OR REPLACE FUNCTION sims_private.emp_write_allowed(p_emp bigint, p_resource text, p_existing_status text)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF p_emp IS NULL OR NOT EXISTS (SELECT 1 FROM employee WHERE employee_id = p_emp) THEN RAISE EXCEPTION 'Not authorised or unknown employee' USING ERRCODE = '42501'; END IF;
    IF sims_private.emp_can(p_emp, p_resource, CASE WHEN p_existing_status IS NULL THEN 'CREATE' ELSE 'UPDATE' END, true) THEN RETURN; END IF;
    IF sims_private.emp_is_owner(p_emp) THEN
        IF p_existing_status IS NULL OR p_existing_status IN ('PENDING', 'PENDING_VERIFICATION', 'REJECTED') THEN RETURN; END IF;
        RAISE EXCEPTION 'A verified record can only be changed by HR' USING ERRCODE = '45000';
    END IF;
    RAISE EXCEPTION 'Not authorised (EMPLOYEE.%.%) or unknown employee', p_resource, CASE WHEN p_existing_status IS NULL THEN 'CREATE' ELSE 'UPDATE' END USING ERRCODE = '42501';
END $function$;

CREATE OR REPLACE FUNCTION sims_private.notifications_all()
 RETURNS TABLE(notif_key text, kind text, title text, body text, href text, at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_uid bigint := sims_private.current_user_id(); v_stu bigint := sims_private.current_student_id(); v_emp bigint := sims_private.current_employee_id(); n bigint;
BEGIN
    IF v_uid IS NULL THEN RETURN; END IF;
    RETURN QUERY SELECT 'ann:' || f.announcement_id, 'ANNOUNCEMENT', f.title, left(f.description, 200), '/announcements/' || f.announcement_id, f.publish_from
                 FROM public.announcements_feed(30) f WHERE f.publish_from > now() - interval '14 days';
    IF v_stu IS NOT NULL THEN
        RETURN QUERY SELECT 'doc:' || d.student_document_id || ':' || d.verification_status, 'DOCUMENT', 'Your ' || lower(t.document_name) || ' was ' || lower(d.verification_status), COALESCE(d.remarks, '')::text, '/my-documents', d.verified_at
                     FROM student_document d JOIN document_type t ON t.document_type_id = d.document_type_id
                     WHERE d.student_id = v_stu AND d.verification_status IN ('VERIFIED', 'REJECTED') AND d.verified_at > now() - interval '30 days';
        RETURN QUERY SELECT 'act:' || a.student_activity_id || ':' || aps.status_code || ':' || vs.status_code, 'ACTIVITY',
                            CASE WHEN vs.status_code = 'NEEDS_CORRECTION' THEN 'Your activity needs correction' WHEN aps.status_code = 'APPROVED' THEN 'Your activity was approved' ELSE 'Your activity was rejected' END,
                            a.activity_title::text, '/activities/' || a.student_activity_id, a.updated_at
                     FROM student_activity a JOIN approval_status aps ON aps.approval_status_id = a.approval_status_id JOIN verification_status vs ON vs.verification_status_id = a.verification_status_id
                     WHERE a.student_id = v_stu AND a.deleted_at IS NULL AND a.updated_at > now() - interval '30 days' AND (aps.status_code IN ('APPROVED', 'REJECTED') OR vs.status_code = 'NEEDS_CORRECTION');
        RETURN QUERY SELECT 'grv:' || g.grievance_id || ':' || g.status, 'GRIEVANCE', 'Your grievance is ' || lower(replace(g.status, '_', ' ')), g.subject::text, '/grievances/' || g.grievance_id,
                            (SELECT max(ga.action_at) FROM grievance_action ga WHERE ga.grievance_id = g.grievance_id)
                     FROM grievance g WHERE g.student_id = v_stu AND g.status IN ('ASSIGNED', 'UNDER_REVIEW', 'RESOLVED', 'REJECTED')
                       AND (SELECT max(ga.action_at) FROM grievance_action ga WHERE ga.grievance_id = g.grievance_id) > now() - interval '30 days';
    END IF;
    IF v_emp IS NOT NULL THEN
        RETURN QUERY SELECT 'staff:' || a.staff_activity_id || ':' || aps.status_code || ':' || vs.status_code, 'STAFF_RECORD',
                            CASE WHEN vs.status_code = 'NEEDS_CORRECTION' THEN 'Your record needs correction' WHEN aps.status_code = 'APPROVED' THEN 'Your record was approved' ELSE 'Your record was rejected' END,
                            a.activity_title::text, '/staff-profile/' || a.staff_activity_id, a.updated_at
                     FROM staff_activity a JOIN approval_status aps ON aps.approval_status_id = a.approval_status_id JOIN verification_status vs ON vs.verification_status_id = a.verification_status_id
                     WHERE a.employee_id = v_emp AND a.deleted_at IS NULL AND a.updated_at > now() - interval '30 days' AND (aps.status_code IN ('APPROVED', 'REJECTED') OR vs.status_code = 'NEEDS_CORRECTION');
    END IF;
    -- review queues (counts; the key carries the count so a growing queue shows up again after being dismissed)
    IF sims_private.has_any_grant(ARRAY['STUDENT.STUDENT_ACTIVITY.VERIFY']::text[]) THEN
        SELECT count(*) INTO n FROM student_activity a JOIN approval_status aps ON aps.approval_status_id = a.approval_status_id
            WHERE a.deleted_at IS NULL AND aps.status_code = 'SUBMITTED' AND sims_private.can_student(ARRAY['STUDENT.STUDENT_ACTIVITY.VERIFY']::text[], a.student_id, true);
    ELSE n := 0; END IF;
    IF n > 0 THEN RETURN QUERY SELECT 'task:act-verify:' || n, 'TASK', n || ' student ' || CASE WHEN n = 1 THEN 'activity awaits' ELSE 'activities await' END || ' verification', ''::text, '/activities?status=SUBMITTED', now(); END IF;
    IF sims_private.has_any_grant(ARRAY['STUDENT.STUDENT_ACTIVITY.APPROVE']::text[]) THEN
        SELECT count(*) INTO n FROM student_activity a JOIN approval_status aps ON aps.approval_status_id = a.approval_status_id
            WHERE a.deleted_at IS NULL AND aps.status_code = 'UNDER_REVIEW' AND sims_private.can_student(ARRAY['STUDENT.STUDENT_ACTIVITY.APPROVE']::text[], a.student_id, true);
    ELSE n := 0; END IF;
    IF n > 0 THEN RETURN QUERY SELECT 'task:act-approve:' || n, 'TASK', n || ' student ' || CASE WHEN n = 1 THEN 'activity awaits' ELSE 'activities await' END || ' approval', ''::text, '/activities?status=UNDER_REVIEW', now(); END IF;
    IF sims_private.has_any_grant(ARRAY['STAFF_PROFILE.STAFF_ACTIVITY.VERIFY']::text[]) THEN
        SELECT count(*) INTO n FROM staff_activity a JOIN approval_status aps ON aps.approval_status_id = a.approval_status_id
            WHERE a.deleted_at IS NULL AND aps.status_code = 'SUBMITTED' AND a.employee_id IS DISTINCT FROM v_emp AND sims_private.can_employee(ARRAY['STAFF_PROFILE.STAFF_ACTIVITY.VERIFY']::text[], a.employee_id, true);
    ELSE n := 0; END IF;
    IF n > 0 THEN RETURN QUERY SELECT 'task:staff-verify:' || n, 'TASK', n || ' staff ' || CASE WHEN n = 1 THEN 'record awaits' ELSE 'records await' END || ' verification', ''::text, '/staff-profile?status=SUBMITTED', now(); END IF;
    IF sims_private.has_any_grant(ARRAY['STAFF_PROFILE.STAFF_ACTIVITY.APPROVE']::text[]) THEN
        SELECT count(*) INTO n FROM staff_activity a JOIN approval_status aps ON aps.approval_status_id = a.approval_status_id
            WHERE a.deleted_at IS NULL AND aps.status_code = 'UNDER_REVIEW' AND a.employee_id IS DISTINCT FROM v_emp AND sims_private.can_employee(ARRAY['STAFF_PROFILE.STAFF_ACTIVITY.APPROVE']::text[], a.employee_id, true);
    ELSE n := 0; END IF;
    IF n > 0 THEN RETURN QUERY SELECT 'task:staff-approve:' || n, 'TASK', n || ' staff ' || CASE WHEN n = 1 THEN 'record awaits' ELSE 'records await' END || ' approval', ''::text, '/staff-profile?status=UNDER_REVIEW', now(); END IF;
    IF sims_private.has_any_grant(ARRAY['GRIEVANCE.ALL.UPDATE']::text[]) THEN
        SELECT count(*) INTO n FROM grievance g WHERE g.status = 'SUBMITTED' AND sims_private.can_student(ARRAY['GRIEVANCE.ALL.UPDATE']::text[], g.student_id, true);
    ELSE n := 0; END IF;
    IF n > 0 THEN RETURN QUERY SELECT 'task:grv:' || n, 'TASK', n || ' new ' || CASE WHEN n = 1 THEN 'grievance awaits' ELSE 'grievances await' END || ' attention', ''::text, '/grievances?status=SUBMITTED', now(); END IF;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_guard_announcement()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF current_user <> 'authenticated' THEN RETURN NEW; END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN (NEW.approval_status IS DISTINCT FROM OLD.approval_status AND (NEW.approval_status IN ('APPROVED', 'REJECTED') OR OLD.approval_status IN ('APPROVED', 'REJECTED'))) ELSE NEW.approval_status IN ('APPROVED', 'REJECTED') END) THEN
        IF NOT sims_private.can_department(ARRAY['COMMUNICATION.ALL.APPROVE']::text[], NEW.department_id) THEN
            RAISE EXCEPTION 'Not authorised to APPROVE (announcement.approval_status)' USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.sims_guard_assessment_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
    IF current_user <> 'authenticated' THEN RETURN NEW; END IF;
    IF (CASE WHEN TG_OP = 'UPDATE' THEN (NEW.status IS DISTINCT FROM OLD.status AND (NEW.status IN ('PUBLISHED') OR OLD.status IN ('PUBLISHED'))) ELSE NEW.status IN ('PUBLISHED') END) THEN
        IF NOT sims_private.can_programme(ARRAY['ASSESSMENT.ALL.PUBLISH']::text[], sims_private.nx_programme_term_offering_programme_term_offerin_dd560b84f3(sims_private.nx_course_offering_course_offering_id_programme_t_6af0a6bfe1(sims_private.nx_assessment_component_assessment_component_id_c_556a8c03e6(NEW.assessment_component_id)))) THEN
            RAISE EXCEPTION 'Not authorised to PUBLISH (assessment_event.status)' USING ERRCODE = '42501';
        END IF;
    END IF;
    RETURN NEW;
END $function$;

CREATE OR REPLACE FUNCTION public.student_register(p_student jsonb, p_enrolment jsonb DEFAULT NULL::jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_prog integer; v_scheme_prog integer; v_id bigint;
    v_first text := NULLIF(btrim(p_student ->> 'first_name'), '');
    v_mid text := NULLIF(btrim(p_student ->> 'middle_name'), '');
    v_last text := NULLIF(btrim(p_student ->> 'last_name'), '');
    v_number text := NULLIF(btrim(p_student ->> 'student_number'), '');
    v_email text := NULLIF(btrim(p_student ->> 'primary_email'), '');
    v_dob date := NULLIF(p_student ->> 'date_of_birth', '')::date;
    v_adm date; v_constraint text;
BEGIN
    IF p_student IS NULL OR jsonb_typeof(p_student) <> 'object' THEN
        RAISE EXCEPTION 'p_student must be an object' USING ERRCODE = '22023';
    END IF;
    IF p_enrolment IS NOT NULL THEN
        IF jsonb_typeof(p_enrolment) <> 'object' THEN RAISE EXCEPTION 'p_enrolment must be an object' USING ERRCODE = '22023'; END IF;
        v_prog := (p_enrolment ->> 'programme_id')::integer;
        IF v_prog IS NULL THEN RAISE EXCEPTION 'programme_id is required for an enrolment' USING ERRCODE = '22023'; END IF;
        IF NOT (sims_private.can_programme(ARRAY['STUDENT.ALL.CREATE']::text[], v_prog)
                AND sims_private.can_programme(ARRAY['ADMISSION.ALL.CREATE']::text[], v_prog)) THEN
            RAISE EXCEPTION 'Not authorised to register students in this programme' USING ERRCODE = '42501';
        END IF;
    ELSIF NOT sims_private.can_global(ARRAY['STUDENT.ALL.CREATE']::text[]) THEN
        -- Without an enrolment there is no scope to check against: only global grants may create an unenrolled student.
        RAISE EXCEPTION 'Not authorised to register students without a programme enrolment' USING ERRCODE = '42501';
    END IF;

    IF v_number IS NULL OR v_first IS NULL THEN RAISE EXCEPTION 'student_number and first_name are required' USING ERRCODE = '22023'; END IF;
    IF v_email IS NOT NULL AND v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN
        RAISE EXCEPTION 'primary_email is not a valid email address' USING ERRCODE = '22023';
    END IF;
    IF v_dob IS NOT NULL AND (v_dob >= current_date OR v_dob < DATE '1900-01-01') THEN
        RAISE EXCEPTION 'date_of_birth is not plausible' USING ERRCODE = '22023';
    END IF;

    IF p_enrolment IS NOT NULL THEN
        SELECT programme_id INTO v_scheme_prog FROM curriculum_scheme WHERE curriculum_scheme_id = (p_enrolment ->> 'curriculum_scheme_id')::bigint;
        IF v_scheme_prog IS DISTINCT FROM v_prog THEN
            RAISE EXCEPTION 'The curriculum scheme does not belong to the selected programme' USING ERRCODE = '45000';
        END IF;
    END IF;
    v_adm := COALESCE(NULLIF(p_student ->> 'admission_date', '')::date, NULLIF(p_enrolment ->> 'admission_date', '')::date);

    BEGIN
        INSERT INTO student (student_number, first_name, middle_name, last_name, display_name, date_of_birth, gender_id, blood_group_id,
                             primary_email, primary_phone, nationality_country_id, religion_id, social_category_id, admission_date, notes)
        VALUES (v_number, v_first, v_mid, v_last, btrim(concat_ws(' ', v_first, v_mid, v_last)), v_dob,
                NULLIF(p_student ->> 'gender_id', '')::smallint, NULLIF(p_student ->> 'blood_group_id', '')::smallint,
                v_email, NULLIF(btrim(p_student ->> 'primary_phone'), ''), NULLIF(p_student ->> 'nationality_country_id', '')::integer,
                NULLIF(p_student ->> 'religion_id', '')::integer, NULLIF(p_student ->> 'social_category_id', '')::integer, v_adm,
                NULLIF(btrim(p_student ->> 'notes'), ''))
        RETURNING student_id INTO v_id;
    EXCEPTION WHEN unique_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF v_constraint IN ('student_student_number_key', 'uq_student_primary_email', 'student_university_seat_number_key') THEN
            RAISE EXCEPTION 'Student number or email is already registered' USING ERRCODE = '23505';
        END IF;
        RAISE;  -- any other uniqueness failure is a real error and must not be disguised
    END;

    IF p_enrolment IS NOT NULL THEN
        INSERT INTO student_programme_enrolment (student_id, programme_id, specialization_id, curriculum_scheme_id, admission_academic_year_id,
                                                 admission_category_id, admission_date, admission_semester_id)
        VALUES (v_id, v_prog, NULLIF(p_enrolment ->> 'specialization_id', '')::integer, (p_enrolment ->> 'curriculum_scheme_id')::bigint,
                (p_enrolment ->> 'admission_academic_year_id')::integer, NULLIF(p_enrolment ->> 'admission_category_id', '')::integer,
                COALESCE(NULLIF(p_enrolment ->> 'admission_date', '')::date, v_adm, current_date), (p_enrolment ->> 'admission_semester_id')::smallint);
    END IF;
    RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.admission_authorize(p_application_id bigint, p_action text)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_prog integer;
BEGIN
    SELECT programme_id INTO v_prog FROM admission_application WHERE application_id = p_application_id;
    IF v_prog IS NULL OR NOT sims_private.can_programme(ARRAY['ADMISSION.ALL.' || p_action]::text[], v_prog) THEN
        RAISE EXCEPTION 'Not authorised (ADMISSION.ALL.%) or unknown application', p_action USING ERRCODE = '42501';
    END IF;
    RETURN v_prog;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.announcement_can(p_action text, p_department integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT sims_private.can_department(ARRAY['COMMUNICATION.ALL.' || p_action]::text[], p_department)
$function$;

CREATE OR REPLACE FUNCTION sims_private.asm_authorize(p_course_offering_id bigint, p_module text, p_action text)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_prog integer := sims_private.programme_of_offering(p_course_offering_id);
BEGIN
    IF v_prog IS NULL OR NOT sims_private.can_programme(ARRAY[p_module || '.ALL.' || p_action]::text[], v_prog) THEN
        RAISE EXCEPTION 'Not authorised (%.ALL.%) or unknown record', p_module, p_action USING ERRCODE = '42501';
    END IF;
    RETURN v_prog;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.att_authorize_cos(p_cos_id bigint, p_module text, p_action text)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_prog integer := sims_private.programme_of_cos(p_cos_id);
BEGIN
    IF v_prog IS NULL OR NOT sims_private.can_programme(ARRAY[p_module || '.ALL.' || p_action]::text[], v_prog) THEN
        RAISE EXCEPTION 'Not authorised (%.ALL.%) or unknown teaching section', p_module, p_action USING ERRCODE = '42501';
    END IF;
    RETURN v_prog;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.can_see_applicant(p_applicant_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT sims_private.can_global(ARRAY['ADMISSION.ALL.READ']::text[])
        OR EXISTS (SELECT 1 FROM public.admission_application a
                   WHERE a.admission_applicant_id = p_applicant_id
                     AND sims_private.can_programme(ARRAY['ADMISSION.ALL.READ']::text[], a.programme_id))
$function$;

CREATE OR REPLACE FUNCTION sims_private.fs_can(p_institution bigint, p_programme bigint, p_action text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT CASE WHEN p_programme IS NOT NULL THEN sims_private.can_programme(ARRAY['FEES.FEE_STRUCTURE.' || p_action]::text[], p_programme)
                ELSE sims_private.can_institution(ARRAY['FEES.FEE_STRUCTURE.' || p_action]::text[], p_institution) END
$function$;

CREATE OR REPLACE FUNCTION sims_private.section_can(p_kind text, p_perm_prefix text, p_action text, p_parent_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT CASE p_kind
        WHEN 'student' THEN sims_private.can_student(ARRAY[p_perm_prefix || '.' || p_action]::text[], p_parent_id, p_action <> 'READ')
        WHEN 'employee' THEN sims_private.can_employee(ARRAY[p_perm_prefix || '.' || p_action]::text[], p_parent_id, p_action <> 'READ')
        WHEN 'activity' THEN sims_private.activity_child_ok(p_parent_id,
            CASE p_perm_prefix WHEN 'STAFF_PROFILE.STAFF_RESEARCH' THEN 'funded_research_project' ELSE 'staff_professional_contribution' END, p_perm_prefix, p_action)
        ELSE false END
$function$;

CREATE OR REPLACE FUNCTION sims_private.tt_can_read_pto(p_pto bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT COALESCE((SELECT sims_private.can_programme(ARRAY['TIMETABLE.ALL.READ']::text[], pto.programme_id) FROM public.programme_term_offering pto WHERE pto.programme_term_offering_id = p_pto), false)
$function$;

CREATE OR REPLACE FUNCTION public.admission_admit(p_application_id bigint, p_student jsonb, p_enrolment jsonb)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE v_app record; v_prog integer; v_app_row record; v_applicant record; v_student bigint; v_stu jsonb;
BEGIN
    v_prog := sims_private.admission_authorize(p_application_id, 'APPROVE');
    IF NOT sims_private.can_programme(ARRAY['STUDENT.ALL.CREATE']::text[], v_prog) THEN
        RAISE EXCEPTION 'Not authorised to create students in this programme' USING ERRCODE = '42501';
    END IF;
    SELECT * INTO v_app FROM admission_application WHERE application_id = p_application_id FOR UPDATE;
    IF v_app.application_status = 'ADMITTED' AND v_app.admitted_student_id IS NOT NULL THEN RETURN v_app.admitted_student_id; END IF;  -- idempotent replay
    IF v_app.application_status <> 'SELECTED' THEN
        RAISE EXCEPTION 'Only a SELECTED application can be admitted (status is %)', v_app.application_status USING ERRCODE = '45000';
    END IF;
    IF p_student IS NULL OR NULLIF(btrim(p_student ->> 'student_number'), '') IS NULL THEN
        RAISE EXCEPTION 'student_number is required' USING ERRCODE = '22023';
    END IF;
    SELECT * INTO v_applicant FROM admission_applicant WHERE admission_applicant_id = v_app.admission_applicant_id;

    -- applicant details are defaults; explicit values in p_student win
    v_stu := jsonb_strip_nulls(jsonb_build_object(
        'first_name', v_applicant.first_name, 'middle_name', v_applicant.middle_name, 'last_name', v_applicant.last_name,
        'date_of_birth', v_applicant.date_of_birth, 'gender_id', v_applicant.gender_id, 'primary_email', v_applicant.primary_email,
        'primary_phone', v_applicant.primary_phone, 'nationality_country_id', v_applicant.nationality_country_id,
        'social_category_id', v_applicant.social_category_id)) || p_student;

    v_student := public.student_register(
        v_stu,
        jsonb_strip_nulls(jsonb_build_object('programme_id', v_app.programme_id, 'specialization_id', v_app.specialization_id,
                                             'admission_category_id', v_app.admission_category_id)) || COALESCE(p_enrolment, '{}'::jsonb));

    UPDATE admission_application SET application_status = 'ADMITTED', admitted_student_id = v_student WHERE application_id = p_application_id;
    RETURN v_student;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.announcement_editable(p_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT COALESCE((SELECT a.approval_status IN ('DRAFT', 'REJECTED')
                         AND ((aa.user_id IS NOT NULL AND aa.user_id IS NOT DISTINCT FROM sims_private.current_user_id()) OR sims_private.announcement_can('UPDATE', a.department_id))
                     FROM announcement a LEFT JOIN sims_private.announcement_author aa ON aa.announcement_id = a.announcement_id WHERE a.announcement_id = p_id), false)
$function$;

CREATE OR REPLACE FUNCTION sims_private.announcement_visible(p_id bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT COALESCE((SELECT (aa.user_id IS NOT NULL AND aa.user_id IS NOT DISTINCT FROM sims_private.current_user_id())
                         OR sims_private.announcement_can('READ', a.department_id)
                         OR (a.approval_status = 'APPROVED' AND a.publish_from <= now() AND (a.publish_to IS NULL OR a.publish_to > now()) AND sims_private.announcement_audience_ok(a.audience_type, a.department_id))
                     FROM announcement a LEFT JOIN sims_private.announcement_author aa ON aa.announcement_id = a.announcement_id WHERE a.announcement_id = p_id), false)
$function$;

CREATE OR REPLACE FUNCTION sims_private.fs_load(p_id bigint, p_action text)
 RETURNS fee_structure
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE s public.fee_structure%ROWTYPE;
BEGIN
    SELECT * INTO s FROM fee_structure WHERE fee_structure_id = p_id FOR UPDATE;
    IF s.fee_structure_id IS NULL OR NOT COALESCE(sims_private.fs_can(s.institution_id, s.programme_id, p_action), false) THEN
        RAISE EXCEPTION 'Not authorised (FEES.FEE_STRUCTURE.%) or unknown fee structure', p_action USING ERRCODE = '42501';
    END IF;
    RETURN s;
END $function$;

CREATE OR REPLACE FUNCTION sims_private.admission_transition_ok(p_from text, p_to text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT (p_from, p_to) IN (
        ('DRAFT', 'SUBMITTED'), ('DRAFT', 'CANCELLED'),
        ('SUBMITTED', 'UNDER_REVIEW'), ('SUBMITTED', 'REJECTED'), ('SUBMITTED', 'CANCELLED'),
        ('UNDER_REVIEW', 'ELIGIBLE'), ('UNDER_REVIEW', 'INELIGIBLE'), ('UNDER_REVIEW', 'REJECTED'), ('UNDER_REVIEW', 'CANCELLED'),
        ('ELIGIBLE', 'SELECTED'), ('ELIGIBLE', 'WAITLISTED'), ('ELIGIBLE', 'REJECTED'), ('ELIGIBLE', 'CANCELLED'),
        ('INELIGIBLE', 'REJECTED'), ('INELIGIBLE', 'CANCELLED'),
        ('WAITLISTED', 'SELECTED'), ('WAITLISTED', 'REJECTED'), ('WAITLISTED', 'CANCELLED'),
        ('SELECTED', 'REJECTED'), ('SELECTED', 'CANCELLED')
    )  -- SELECTED -> ADMITTED happens only inside admission_admit()
$function$;

CREATE OR REPLACE FUNCTION sims_private.can_use_announcement_path(p_name text, p_write boolean)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
    SELECT COALESCE(CASE WHEN p_write THEN sims_private.announcement_editable(sims_private.doc_announcement_id(p_name)) ELSE sims_private.announcement_visible(sims_private.doc_announcement_id(p_name)) END, false)
$function$;
