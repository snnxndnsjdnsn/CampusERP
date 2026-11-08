-- =============================================================================================
-- SIMS DEMO / TEST DATA  -  tools/seed_demo.sql
-- =============================================================================================
-- One coherent demo tenant that exercises the whole schema, module by module, so that every
-- screen has something to show and every foreign key can be followed end to end:
--
--    1  common reference        (lookups come from migration 064)
--    2  institution structure   university -> institution -> campus -> department -> programme
--    3  academic calendar       academic year -> term -> semesters -> time slots
--    4  curriculum and courses  scheme -> courses -> curriculum courses
--    5  student and staff       students, enrolments, employees, assignments
--    6  admission               applicant -> application
--    7  registration            term registration -> course registration -> section roster
--    8  teaching allocation     course offering -> section -> faculty assignment
--    8  timetable               weekly teaching plan -> timetable session
--    9  attendance              class sessions -> attendance rows
--   10  assessment and result   components -> events -> marks -> course and term results
--   11  feedback                questions -> questionnaires -> open cycles
--   12  mentoring and grievance mentor assignment -> counselling -> complaint -> action
--   13  documents and fees      fee structure -> assessment -> payment -> allocation -> receipt
--   13  documents               file object -> student document -> certificate -> service request
--   14  communication           announcement
--   16  employee HR             qualification -> experience -> address -> identity -> document
--   19  staff profile           staff activity (research record)
--   40  student activity        student activity (co-curricular record) and its teams
--
-- HOW TO USE
--   * Locally: tests/db/demo_connectivity.test.ts applies this file to an embedded database and
--     asserts every join above, so the file is verified on every test run.
--   * On the live project: apply it once with a direct connection, for example
--       psql "$SUPABASE_DB_URL" -f tools/seed_demo.sql
--     It is idempotent, so it can be re-run safely.
--
-- RULES
--   * No explicit ids. Every row uses its identity default and is found again by its natural
--     key, so the identity sequences stay correct and the file can be re-run any number of times.
--   * Every insert is guarded by NOT EXISTS, so a second run changes nothing.
--   * Business keys are prefixed DEMO- so the rows are easy to find and to remove.
--   * No user accounts: a SIMS user needs a Supabase Auth identity, which cannot be created from
--     SQL. Create the users in the Supabase dashboard, then link them with
--     public.iam_link_auth_user(email, student_number, employee_number).
--   * The employee identity rows (aadhaar, PAN, bank account) are written only when the project
--     holds the vault secret that sims_private.pii_key() reads. Without it they are left out
--     instead of failing the transaction.
-- =============================================================================================

-- ---------------------------------------------------------------------------------------------
-- Module 2 - university and institution structure
-- ---------------------------------------------------------------------------------------------
INSERT INTO university (university_code, university_name, legal_name, university_type, city, state_id, is_active)
SELECT 'DEMO-UNIV', 'Demo University', 'Demo University Society', 'PRIVATE', 'Haveri',
       (SELECT state_id FROM state WHERE state_code = 'KA'
          AND country_id = (SELECT country_id FROM country WHERE iso_code = 'IN') LIMIT 1), true
WHERE NOT EXISTS (SELECT 1 FROM university WHERE university_code = 'DEMO-UNIV');

INSERT INTO institution (university_id, institution_code, institution_name, legal_name, email, phone, is_active)
SELECT (SELECT university_id FROM university WHERE university_code = 'DEMO-UNIV'),
       'DEMO-INST', 'Demo Institute of Technology', 'Demo Institute of Technology',
       'office@demo-univ.edu', '+91-9000000000', true
WHERE NOT EXISTS (SELECT 1 FROM institution WHERE institution_code = 'DEMO-INST');

INSERT INTO campus (institution_id, campus_code, campus_name, address_line_1, city, state_id, is_active)
SELECT (SELECT institution_id FROM institution WHERE institution_code = 'DEMO-INST'),
       'DEMO-CAMPUS', 'Demo Main Campus', '1 College Road', 'Haveri',
       (SELECT state_id FROM state WHERE state_code = 'KA'
          AND country_id = (SELECT country_id FROM country WHERE iso_code = 'IN') LIMIT 1), true
WHERE NOT EXISTS (SELECT 1 FROM campus WHERE campus_code = 'DEMO-CAMPUS');

INSERT INTO department (campus_id, department_code, department_name, department_type, is_active)
SELECT d.campus_id, v.code, v.name, 'ACADEMIC', true
FROM (VALUES ('DEMO-CSE', 'Department of Computer Science'), ('DEMO-MGT', 'Department of Management')) AS v(code, name)
JOIN campus d ON d.campus_code = 'DEMO-CAMPUS'
WHERE NOT EXISTS (SELECT 1 FROM department x WHERE x.department_code = v.code);

INSERT INTO programme (department_id, programme_code, programme_name, award_name, programme_level, duration_semesters, maximum_duration_semesters, is_active)
SELECT d.department_id, v.code, v.name, v.award, v.level, v.dur, v.maxdur, true
FROM (VALUES
  ('DEMO-BSC-CS', 'Bachelor of Science in Computer Science', 'B.Sc.', 'UG', 6, 8),
  ('DEMO-MBA', 'Master of Business Administration', 'MBA', 'PG', 2, 4)
) AS v(code, name, award, level, dur, maxdur)
JOIN department d ON d.department_code = CASE WHEN v.code = 'DEMO-MBA' THEN 'DEMO-MGT' ELSE 'DEMO-CSE' END
WHERE NOT EXISTS (SELECT 1 FROM programme x WHERE x.programme_code = v.code);

INSERT INTO programme_specialization (programme_id, specialization_code, specialization_name, is_active)
SELECT p.programme_id, 'DEMO-CS-DS', 'Data Science', true
FROM programme p WHERE p.programme_code = 'DEMO-BSC-CS'
  AND NOT EXISTS (SELECT 1 FROM programme_specialization x WHERE x.specialization_code = 'DEMO-CS-DS');

INSERT INTO building (campus_id, building_code, building_name, is_active)
SELECT c.campus_id, 'DEMO-BLDG-A', 'Academic Block A', true
FROM campus c WHERE c.campus_code = 'DEMO-CAMPUS'
  AND NOT EXISTS (SELECT 1 FROM building x WHERE x.building_code = 'DEMO-BLDG-A');

INSERT INTO room (building_id, room_code, room_name, room_type, capacity, is_active)
SELECT b.building_id, 'DEMO-101', 'Lecture Hall 101', 'CLASSROOM', 60, true
FROM building b WHERE b.building_code = 'DEMO-BLDG-A'
  AND NOT EXISTS (SELECT 1 FROM room x WHERE x.room_code = 'DEMO-101');

-- ---------------------------------------------------------------------------------------------
-- Module 3 - academic calendar
-- ---------------------------------------------------------------------------------------------
INSERT INTO academic_year (year_code, start_date, end_date, status)
VALUES ('2025-26', '2025-06-01', '2026-05-31', 'ACTIVE')
ON CONFLICT DO NOTHING;

INSERT INTO academic_term (academic_year_id, term_code, term_name, term_type, start_date, end_date, registration_start_date, registration_end_date, status)
SELECT (SELECT academic_year_id FROM academic_year WHERE year_code = '2025-26'),
       '2025-26-ODD', 'Odd Semester 2025-26', 'ODD', '2025-07-01', '2025-11-30', '2025-06-15', '2025-07-15', 'ACTIVE'
WHERE NOT EXISTS (SELECT 1 FROM academic_term WHERE term_code = '2025-26-ODD');

INSERT INTO academic_term (academic_year_id, term_code, term_name, term_type, start_date, end_date, registration_start_date, registration_end_date, status)
SELECT (SELECT academic_year_id FROM academic_year WHERE year_code = '2025-26'),
       '2025-26-EVEN', 'Even Semester 2025-26', 'EVEN', '2025-12-01', '2026-04-30', '2025-11-15', '2025-12-15', 'PLANNED'
WHERE NOT EXISTS (SELECT 1 FROM academic_term WHERE term_code = '2025-26-EVEN');

INSERT INTO semester (semester_number, semester_name)
SELECT v.n, 'Semester ' || v.n
FROM (VALUES (1), (2), (3), (4), (5), (6)) AS v(n)
WHERE NOT EXISTS (SELECT 1 FROM semester x WHERE x.semester_number = v.n);

INSERT INTO time_slot (campus_id, slot_code, start_time, end_time, is_break, is_active)
SELECT c.campus_id, v.code, v.s::time, v.e::time, false, true
FROM (VALUES
  ('DEMO-T1', '09:00', '10:00'), ('DEMO-T2', '10:15', '11:15'), ('DEMO-T3', '11:30', '12:30'),
  ('DEMO-T4', '13:30', '14:30'), ('DEMO-T5', '14:45', '15:45')
) AS v(code, s, e)
JOIN campus c ON c.campus_code = 'DEMO-CAMPUS'
WHERE NOT EXISTS (SELECT 1 FROM time_slot x WHERE x.slot_code = v.code);

-- ---------------------------------------------------------------------------------------------
-- Module 4 - curriculum and course catalogue
-- ---------------------------------------------------------------------------------------------
INSERT INTO course_category (category_code, category_name, is_graded, contributes_to_gpa, is_active)
VALUES ('DEMO-CORE', 'Core', true, true, true),
       ('DEMO-ELECTIVE', 'Elective', true, true, true),
       ('DEMO-SKILL', 'Skill', false, false, true)
ON CONFLICT DO NOTHING;

INSERT INTO course_catalog (owning_department_id, course_category_id, course_code, course_title, course_type, lecture_hours, tutorial_hours, practical_hours, self_study_hours, credits, effective_from, is_active)
SELECT d.department_id, c.course_category_id, v.code, v.title, v.ctype, v.lh, v.th, v.ph, v.sh, v.cr, '2025-06-01', true
FROM (VALUES
  ('DEMO-CS101', 'Programming Fundamentals', 'THEORY', 4, 0, 0, 2, 4),
  ('DEMO-CS102', 'Data Structures and Algorithms', 'THEORY_LAB', 3, 0, 2, 1, 4),
  ('DEMO-CS103', 'Programming Laboratory', 'THEORY_LAB', 0, 0, 4, 0, 2),
  ('DEMO-MGT101', 'Principles of Management', 'THEORY', 3, 0, 0, 1, 3)
) AS v(code, title, ctype, lh, th, ph, sh, cr)
JOIN department d ON d.department_code = CASE WHEN v.code LIKE 'DEMO-MGT%' THEN 'DEMO-MGT' ELSE 'DEMO-CSE' END
JOIN course_category c ON c.category_code = 'DEMO-CORE'
WHERE NOT EXISTS (SELECT 1 FROM course_catalog x WHERE x.course_code = v.code);

INSERT INTO curriculum_scheme (programme_id, scheme_code, scheme_name, regulation_year, total_credits, effective_from, status)
SELECT p.programme_id, 'DEMO-UGCS-2025', 'UG Computer Science 2025', 2025, 120, '2025-06-01', 'ACTIVE'
FROM programme p WHERE p.programme_code = 'DEMO-BSC-CS'
  AND NOT EXISTS (SELECT 1 FROM curriculum_scheme x WHERE x.scheme_code = 'DEMO-UGCS-2025');

INSERT INTO curriculum_course (curriculum_scheme_id, semester_id, course_id, course_category_id, is_mandatory, display_order, internal_max_marks, external_max_marks, passing_marks, exam_duration_minutes)
SELECT cs.curriculum_scheme_id, sem.semester_id, c.course_id, cat.course_category_id, true, v.ord, 30, 70, 40, 120
FROM (VALUES ('DEMO-CS101', 1, 1), ('DEMO-CS103', 1, 2), ('DEMO-CS102', 2, 3)) AS v(code, semno, ord)
JOIN curriculum_scheme cs ON cs.scheme_code = 'DEMO-UGCS-2025'
JOIN semester sem ON sem.semester_number = v.semno
JOIN course_catalog c ON c.course_code = v.code
JOIN course_category cat ON cat.category_code = 'DEMO-CORE'
WHERE NOT EXISTS (
  SELECT 1 FROM curriculum_course x
  WHERE x.curriculum_scheme_id = cs.curriculum_scheme_id AND x.course_id = c.course_id
);

-- ---------------------------------------------------------------------------------------------
-- Module 5 - students and staff (independent root entities)
-- ---------------------------------------------------------------------------------------------
INSERT INTO student (student_number, first_name, last_name, display_name, date_of_birth, gender_id, blood_group_id, primary_email, primary_phone, nationality_country_id, religion_id, social_category_id, admission_date, student_status)
SELECT v.num, v.fn, v.ln, v.fn || ' ' || v.ln, v.dob::date,
       (SELECT gender_id FROM gender WHERE gender_code = v.g),
       (SELECT blood_group_id FROM blood_group WHERE blood_group_code = v.bg),
       v.email, v.phone,
       (SELECT country_id FROM country WHERE iso_code = 'IN'),
       (SELECT religion_id FROM religion WHERE religion_code = v.rel),
       (SELECT social_category_id FROM social_category WHERE category_code = v.sc),
       '2025-08-01', 'ACTIVE'
FROM (VALUES
  ('DEMO-S001', 'Asha',   'Rao',  '2004-03-12', 'F', 'O+', 'asha.rao@demo.edu',    '+91-9000000001', 'HIN', 'GENERAL'),
  ('DEMO-S002', 'Vikram', 'Shah', '2003-11-02', 'M', 'B+', 'vikram.shah@demo.edu',  '+91-9000000002', 'HIN', 'OBC'),
  ('DEMO-S003', 'Meera',  'Iyer', '2004-07-25', 'F', 'A+', 'meera.iyer@demo.edu',   '+91-9000000003', 'HIN', 'SC')
) AS v(num, fn, ln, dob, g, bg, email, phone, rel, sc)
WHERE NOT EXISTS (SELECT 1 FROM student x WHERE x.student_number = v.num);

INSERT INTO student_address (student_id, address_type, address_line_1, city, state_id, country_id, postal_code, is_primary)
SELECT s.student_id, 'PERMANENT', '12 Demo Hostel Road', 'Haveri',
       (SELECT state_id FROM state WHERE state_code = 'KA'
          AND country_id = (SELECT country_id FROM country WHERE iso_code = 'IN') LIMIT 1),
       (SELECT country_id FROM country WHERE iso_code = 'IN'), '581115', true
FROM student s WHERE s.student_number IN ('DEMO-S001', 'DEMO-S002', 'DEMO-S003')
  AND NOT EXISTS (SELECT 1 FROM student_address x WHERE x.student_id = s.student_id AND x.address_type = 'PERMANENT');

INSERT INTO student_programme_enrolment (student_id, programme_id, specialization_id, curriculum_scheme_id, admission_academic_year_id, admission_category_id, admission_date, admission_semester_id, expected_completion_date, enrolment_status)
SELECT s.student_id, p.programme_id, sp.specialization_id, cs.curriculum_scheme_id, ay.academic_year_id,
       ac.admission_category_id, '2025-08-01', sem.semester_id, '2028-05-31', 'ACTIVE'
FROM student s
JOIN programme p ON p.programme_code = 'DEMO-BSC-CS'
JOIN curriculum_scheme cs ON cs.scheme_code = 'DEMO-UGCS-2025'
JOIN academic_year ay ON ay.year_code = '2025-26'
JOIN semester sem ON sem.semester_number = 1
JOIN admission_category ac ON ac.category_code = 'GENERAL'
LEFT JOIN programme_specialization sp ON sp.specialization_code = 'DEMO-CS-DS'
WHERE s.student_number IN ('DEMO-S001', 'DEMO-S002', 'DEMO-S003')
  AND NOT EXISTS (SELECT 1 FROM student_programme_enrolment x WHERE x.student_id = s.student_id AND x.programme_id = p.programme_id);

INSERT INTO employee (institution_id, employment_source_id, employee_number, first_name, last_name, display_name, date_of_birth, gender_id, primary_email, primary_phone, joining_date, employment_type, employment_status)
SELECT (SELECT institution_id FROM institution WHERE institution_code = 'DEMO-INST'),
       (SELECT employment_source_id FROM employment_source WHERE source_code = 'INSTITUTION'),
       v.num, v.fn, v.ln, v.fn || ' ' || v.ln, v.dob::date,
       (SELECT gender_id FROM gender WHERE gender_code = v.g), v.email, v.phone, '2020-06-01', 'REGULAR', 'ACTIVE'
FROM (VALUES
  ('DEMO-E001', 'Anita',  'Rao',   '1978-04-22', 'F', 'anita.rao@demo.edu',   '+91-9000000011'),
  ('DEMO-E002', 'Suresh', 'Kumar', '1985-09-30', 'M', 'suresh.kumar@demo.edu', '+91-9000000012')
) AS v(num, fn, ln, dob, g, email, phone)
WHERE NOT EXISTS (SELECT 1 FROM employee x WHERE x.employee_number = v.num);

INSERT INTO employee_assignment (employee_id, campus_id, department_id, designation_id, start_date, is_primary)
SELECT e.employee_id, c.campus_id, d.department_id,
       (SELECT designation_id FROM designation WHERE designation_code = 'PROFESSOR'),
       '2020-06-01', true
FROM employee e
JOIN campus c ON c.campus_code = 'DEMO-CAMPUS'
JOIN department d ON d.department_code = 'DEMO-CSE'
WHERE e.employee_number IN ('DEMO-E001', 'DEMO-E002')
  AND NOT EXISTS (SELECT 1 FROM employee_assignment x WHERE x.employee_id = e.employee_id AND x.is_primary AND x.end_date IS NULL);

-- =============================================================================================
-- CHUNK 2 - admission, registration, teaching, attendance, assessment and results
-- =============================================================================================
-- The rows below continue the one demo tenant that chunk 1 started: an applicant becomes an
-- admitted student, the student registers for a term, the term runs, and the term ends in a
-- published result.  Every row is addressed by its DEMO-* business key, so the chunk can be
-- replayed any number of times without changing anything.
--
-- NOTE ON THE DEMO-* STUDENT NUMBERS
--   Chunk 1 fixes DEMO-S001 = Asha Rao, DEMO-S002 = Vikram Shah and DEMO-S003 = Meera Iyer.
--   The natural key is the contract, so every row below is addressed by its DEMO-* student
--   number and never by a personal name.
--
-- ORDER MATTERS IN TWO PLACES
--   * The assessment event is created CONDUCTED, the marks are entered, and only then is the
--     event published: sims_assessment_mark_guard locks the marks of a PUBLISHED event.
--   * The term result is created unpublished and published afterwards, because
--     sims_course_result_lock refuses to touch a course result once the term result is
--     published.

-- ---------------------------------------------------------------------------------------------
-- Module 6 - admission
-- ---------------------------------------------------------------------------------------------
INSERT INTO public.admission_applicant (first_name, last_name, display_name, date_of_birth, gender_id, primary_email, primary_phone, nationality_country_id, social_category_id)
SELECT v.fn, v.ln, v.fn || ' ' || v.ln, v.dob,
       (SELECT gender_id FROM public.gender WHERE gender_code = v.g),
       v.email, v.phone,
       (SELECT country_id FROM public.country WHERE iso_code = 'IN'),
       (SELECT social_category_id FROM public.social_category WHERE category_code = v.sc)
FROM (VALUES
  ('Meera', 'Iyer', '2004-07-25'::date, 'F', 'meera.iyer@demo.edu',  '+91-9000000003', 'SC'),
  ('Kiran', 'Nair', '2004-05-18'::date, 'M', 'kiran.nair@demo.edu', '+91-9000000004', 'OBC')
) AS v(fn, ln, dob, g, email, phone, sc)
WHERE NOT EXISTS (
  SELECT 1 FROM public.admission_applicant x WHERE x.primary_email = v.email
);

INSERT INTO public.admission_application (application_number, admission_applicant_id, admitted_student_id, programme_id, specialization_id, academic_year_id, admission_category_id, application_date, application_status, eligibility_status, remarks)
SELECT v.num, a.admission_applicant_id,
       CASE WHEN v.num = 'DEMO-APPLICATION-001'
            THEN (SELECT student_id FROM public.student WHERE student_number = 'DEMO-S003')
            ELSE NULL END,
       p.programme_id,
       (SELECT sp.specialization_id FROM public.programme_specialization sp
         JOIN public.programme pp ON pp.programme_id = sp.programme_id
        WHERE sp.specialization_code = 'DEMO-CS-DS' AND pp.programme_code = 'DEMO-BSC-CS'),
       ay.academic_year_id,
       (SELECT admission_category_id FROM public.admission_category WHERE category_code = 'GENERAL'),
       v.appdate, v.status, v.elig, v.remarks
FROM (VALUES
  ('DEMO-APPLICATION-001', 'meera.iyer@demo.edu',  '2025-07-10'::date, 'ADMITTED',     'ELIGIBLE', 'Admitted on the strength of the entrance examination score.'),
  ('DEMO-APPLICATION-002', 'kiran.nair@demo.edu', '2025-08-05'::date, 'UNDER_REVIEW', 'PENDING',  'Documents are still being verified.')
) AS v(num, email, appdate, status, elig, remarks)
JOIN public.admission_applicant a ON a.primary_email = v.email
JOIN public.programme p ON p.programme_code = 'DEMO-BSC-CS'
JOIN public.academic_year ay ON ay.year_code = '2025-26'
WHERE NOT EXISTS (
  SELECT 1 FROM public.admission_application x WHERE x.application_number = v.num
);

-- ---------------------------------------------------------------------------------------------
-- Module 7 - registration: the term offering, the section and the roll
-- ---------------------------------------------------------------------------------------------
INSERT INTO public.programme_term_offering (academic_term_id, programme_id, specialization_id, curriculum_scheme_id, semester_id, status)
SELECT t.academic_term_id, p.programme_id, sp.specialization_id, cs.curriculum_scheme_id, sem.semester_id, 'ACTIVE'
FROM public.academic_term t
JOIN public.programme p ON p.programme_code = 'DEMO-BSC-CS'
JOIN public.programme_specialization sp ON sp.specialization_code = 'DEMO-CS-DS' AND sp.programme_id = p.programme_id
JOIN public.curriculum_scheme cs ON cs.scheme_code = 'DEMO-UGCS-2025' AND cs.programme_id = p.programme_id
JOIN public.semester sem ON sem.semester_number = 1
WHERE t.term_code = '2025-26-ODD'
  AND NOT EXISTS (
    SELECT 1 FROM public.programme_term_offering x
    WHERE x.academic_term_id = t.academic_term_id
      AND x.programme_id = p.programme_id
      AND x.specialization_id = sp.specialization_id
      AND x.semester_id = sem.semester_id
  );

INSERT INTO public.class_section (programme_term_offering_id, section_code, section_name, capacity, home_room_id, is_active)
SELECT pto.programme_term_offering_id, 'DEMO-A', 'Section A', 60,
       (SELECT room_id FROM public.room WHERE room_code = 'DEMO-101'), true
FROM public.programme_term_offering pto
JOIN public.academic_term t ON t.academic_term_id = pto.academic_term_id
JOIN public.programme p ON p.programme_id = pto.programme_id
WHERE t.term_code = '2025-26-ODD' AND p.programme_code = 'DEMO-BSC-CS'
  AND NOT EXISTS (
    SELECT 1 FROM public.class_section x
    WHERE x.programme_term_offering_id = pto.programme_term_offering_id AND x.section_code = 'DEMO-A'
  );

INSERT INTO public.class_batch (class_section_id, batch_code, batch_name, capacity, is_active)
SELECT cs.class_section_id, 'DEMO-B1', 'Batch 1', 30, true
FROM public.class_section cs
WHERE cs.section_code = 'DEMO-A'
  AND NOT EXISTS (
    SELECT 1 FROM public.class_batch x WHERE x.class_section_id = cs.class_section_id AND x.batch_code = 'DEMO-B1'
  );

INSERT INTO public.student_term_registration (enrolment_id, programme_term_offering_id, class_section_id, class_batch_id, roll_number, registration_date, registration_status)
SELECT e.enrolment_id, pto.programme_term_offering_id, cs.class_section_id, cb.class_batch_id, v.roll, '2025-07-20'::date, 'REGISTERED'
FROM (VALUES
  ('DEMO-S001', 'DEMO-R001'),
  ('DEMO-S002', 'DEMO-R002'),
  ('DEMO-S003', 'DEMO-R003')
) AS v(snum, roll)
JOIN public.student_programme_enrolment e ON e.student_id = (SELECT student_id FROM public.student WHERE student_number = v.snum)
JOIN public.programme_term_offering pto ON pto.programme_id = e.programme_id AND pto.specialization_id = e.specialization_id
JOIN public.academic_term t ON t.academic_term_id = pto.academic_term_id AND t.term_code = '2025-26-ODD'
JOIN public.class_section cs ON cs.programme_term_offering_id = pto.programme_term_offering_id AND cs.section_code = 'DEMO-A'
JOIN public.class_batch cb ON cb.class_section_id = cs.class_section_id AND cb.batch_code = 'DEMO-B1'
WHERE NOT EXISTS (
  SELECT 1 FROM public.student_term_registration x
  WHERE x.enrolment_id = e.enrolment_id AND x.programme_term_offering_id = pto.programme_term_offering_id
);

-- ---------------------------------------------------------------------------------------------
-- Module 8 - teaching allocation: the course offering, the section and the instructor
-- ---------------------------------------------------------------------------------------------
INSERT INTO public.course_offering (programme_term_offering_id, curriculum_course_id, course_id, offering_code, registration_capacity, status)
SELECT pto.programme_term_offering_id, cc.curriculum_course_id, c.course_id, v.code, 60, 'ACTIVE'
FROM (VALUES ('DEMO-CS101'), ('DEMO-CS103')) AS v(code)
JOIN public.course_catalog c ON c.course_code = v.code
JOIN public.curriculum_course cc ON cc.course_id = c.course_id
JOIN public.curriculum_scheme cs ON cs.curriculum_scheme_id = cc.curriculum_scheme_id AND cs.scheme_code = 'DEMO-UGCS-2025'
JOIN public.programme_term_offering pto ON pto.curriculum_scheme_id = cs.curriculum_scheme_id
JOIN public.academic_term t ON t.academic_term_id = pto.academic_term_id AND t.term_code = '2025-26-ODD'
WHERE NOT EXISTS (
  SELECT 1 FROM public.course_offering x WHERE x.offering_code = v.code
);

INSERT INTO public.course_offering_section (course_offering_id, programme_term_offering_id, class_section_id, class_batch_id, session_type)
SELECT co.course_offering_id, co.programme_term_offering_id, cs.class_section_id, cb.class_batch_id, v.stype
FROM (VALUES
  ('DEMO-CS101', 'LECTURE',  NULL::text),
  ('DEMO-CS103', 'PRACTICAL', 'DEMO-B1')
) AS v(code, stype, batch_code)
JOIN public.course_offering co ON co.offering_code = v.code
JOIN public.class_section cs ON cs.programme_term_offering_id = co.programme_term_offering_id AND cs.section_code = 'DEMO-A'
LEFT JOIN public.class_batch cb ON cb.class_section_id = cs.class_section_id AND cb.batch_code = v.batch_code
WHERE NOT EXISTS (
  SELECT 1 FROM public.course_offering_section x
  WHERE x.course_offering_id = co.course_offering_id
    AND x.class_section_id = cs.class_section_id
    AND x.session_type = v.stype
    AND x.class_batch_id IS NOT DISTINCT FROM cb.class_batch_id
);

INSERT INTO public.faculty_course_assignment (course_offering_section_id, employee_id, assignment_role, workload_hours, start_date, end_date, assignment_status)
SELECT cos.course_offering_section_id, e.employee_id, v.role, v.hours, '2025-07-01'::date, '2026-05-31'::date, 'ACTIVE'
FROM (VALUES
  ('DEMO-CS101', 'DEMO-E001', 'PRIMARY_INSTRUCTOR', 16.00::numeric),
  ('DEMO-CS103', 'DEMO-E002', 'LAB_INSTRUCTOR',     12.00::numeric)
) AS v(code, emp, role, hours)
JOIN public.course_offering co ON co.offering_code = v.code
JOIN public.course_offering_section cos ON cos.course_offering_id = co.course_offering_id
JOIN public.employee e ON e.employee_number = v.emp
WHERE NOT EXISTS (
  SELECT 1 FROM public.faculty_course_assignment x
  WHERE x.course_offering_section_id = cos.course_offering_section_id
    AND x.employee_id = e.employee_id
    AND x.assignment_role = v.role
);

-- ---------------------------------------------------------------------------------------------
-- Module 7/8 - course registration and section roster
-- ---------------------------------------------------------------------------------------------
INSERT INTO public.student_course_registration (term_registration_id, course_offering_id, registration_type, registration_date, registration_status)
SELECT tr.term_registration_id, co.course_offering_id, 'REGULAR', '2025-07-21'::date, 'REGISTERED'
FROM public.student_term_registration tr
JOIN public.course_offering co ON co.programme_term_offering_id = tr.programme_term_offering_id
WHERE tr.roll_number IN ('DEMO-R001', 'DEMO-R002', 'DEMO-R003')
  AND co.offering_code IN ('DEMO-CS101', 'DEMO-CS103')
  AND NOT EXISTS (
    SELECT 1 FROM public.student_course_registration x
    WHERE x.term_registration_id = tr.term_registration_id AND x.course_offering_id = co.course_offering_id
  );

INSERT INTO public.course_offering_section_student (course_offering_section_id, course_registration_id, course_offering_id, roster_status, effective_from, effective_to)
SELECT cos.course_offering_section_id, cr.course_registration_id, cr.course_offering_id, 'ACTIVE', '2025-07-21'::date, NULL
FROM public.student_course_registration cr
JOIN public.course_offering co ON co.course_offering_id = cr.course_offering_id
JOIN public.course_offering_section cos ON cos.course_offering_id = co.course_offering_id
WHERE co.offering_code IN ('DEMO-CS101', 'DEMO-CS103')
  AND NOT EXISTS (
    SELECT 1 FROM public.course_offering_section_student x
    WHERE x.course_offering_section_id = cos.course_offering_section_id
      AND x.course_registration_id = cr.course_registration_id
  );

-- ---------------------------------------------------------------------------------------------
-- Module 9 - attendance
-- ---------------------------------------------------------------------------------------------
INSERT INTO public.class_session (course_offering_section_id, faculty_assignment_id, session_date, start_time, end_time, room_id, session_type, planned_topic, topic_covered, class_number, session_status)
SELECT cos.course_offering_section_id, fca.faculty_assignment_id, v.sdate, v.st, v.et,
       (SELECT room_id FROM public.room WHERE room_code = 'DEMO-101'), cos.session_type, v.topic, v.topic, v.cno, 'CONDUCTED'
FROM (VALUES
  ('DEMO-CS101', 'PRIMARY_INSTRUCTOR', '2025-08-04'::date, '09:00'::time, '10:00'::time, 'Introduction to programming',    1),
  ('DEMO-CS101', 'PRIMARY_INSTRUCTOR', '2025-08-06'::date, '09:00'::time, '10:00'::time, 'Control flow and functions',     2),
  ('DEMO-CS103', 'LAB_INSTRUCTOR',     '2025-08-08'::date, '14:45'::time, '15:45'::time, 'Programming laboratory 1',       1)
) AS v(code, role, sdate, st, et, topic, cno)
JOIN public.course_offering co ON co.offering_code = v.code
JOIN public.course_offering_section cos ON cos.course_offering_id = co.course_offering_id
LEFT JOIN public.faculty_course_assignment fca
       ON fca.course_offering_section_id = cos.course_offering_section_id
      AND fca.assignment_role = v.role
WHERE NOT EXISTS (
  SELECT 1 FROM public.class_session x
  WHERE x.course_offering_section_id = cos.course_offering_section_id
    AND x.session_date = v.sdate
    AND x.start_time = v.st
);

INSERT INTO public.student_attendance (class_session_id, course_offering_section_student_id, course_offering_section_id, attendance_status_id, marked_at, remarks)
SELECT cs.class_session_id, r.course_offering_section_student_id, cs.course_offering_section_id,
       (SELECT attendance_status_id FROM public.attendance_status WHERE status_code = v.stcode),
       (cs.session_date::timestamp + cs.end_time) AT TIME ZONE 'UTC',
       NULLIF(v.remark, '')
FROM (VALUES
  ('DEMO-CS101', '2025-08-04'::date, 'DEMO-S001', 'PRESENT', ''),
  ('DEMO-CS101', '2025-08-04'::date, 'DEMO-S002', 'PRESENT', ''),
  ('DEMO-CS101', '2025-08-04'::date, 'DEMO-S003', 'PRESENT', ''),
  ('DEMO-CS101', '2025-08-06'::date, 'DEMO-S001', 'PRESENT', ''),
  ('DEMO-CS101', '2025-08-06'::date, 'DEMO-S002', 'LATE',    'Arrived ten minutes late.'),
  ('DEMO-CS101', '2025-08-06'::date, 'DEMO-S003', 'PRESENT', ''),
  ('DEMO-CS103', '2025-08-08'::date, 'DEMO-S001', 'PRESENT', ''),
  ('DEMO-CS103', '2025-08-08'::date, 'DEMO-S002', 'PRESENT', ''),
  ('DEMO-CS103', '2025-08-08'::date, 'DEMO-S003', 'ABSENT',  'Absent for the programming laboratory.')
) AS v(code, sdate, snum, stcode, remark)
JOIN public.course_offering co ON co.offering_code = v.code
JOIN public.class_session cs ON cs.course_offering_section_id IN (
       SELECT course_offering_section_id FROM public.course_offering_section WHERE course_offering_id = co.course_offering_id)
  AND cs.session_date = v.sdate
JOIN public.course_offering_section_student r ON r.course_offering_section_id = cs.course_offering_section_id
JOIN public.student_course_registration cr ON cr.course_registration_id = r.course_registration_id
JOIN public.student_term_registration tr ON tr.term_registration_id = cr.term_registration_id
JOIN public.student_programme_enrolment e ON e.enrolment_id = tr.enrolment_id
JOIN public.student s ON s.student_id = e.student_id AND s.student_number = v.snum
WHERE NOT EXISTS (
  SELECT 1 FROM public.student_attendance x
  WHERE x.class_session_id = cs.class_session_id
    AND x.course_offering_section_student_id = r.course_offering_section_student_id
);

-- ---------------------------------------------------------------------------------------------
-- Module 10 - assessment and results
-- ---------------------------------------------------------------------------------------------
INSERT INTO public.assessment_component (course_offering_id, component_code, component_name, component_type, maximum_marks, weightage_percent, is_mandatory)
SELECT co.course_offering_id, v.ccode, v.cname, v.ctype, v.maxm, v.weight, true
FROM (VALUES
  ('DEMO-CS101', 'IA1', 'Internal Assessment 1',    'INTERNAL_TEST', 30.00::numeric, 40.00::numeric),
  ('DEMO-CS101', 'END', 'End Semester Examination', 'OTHER',         70.00::numeric, 60.00::numeric),
  ('DEMO-CS103', 'IA1', 'Internal Assessment 1',    'INTERNAL_TEST', 30.00::numeric, 40.00::numeric),
  ('DEMO-CS103', 'END', 'End Semester Examination', 'OTHER',         70.00::numeric, 60.00::numeric)
) AS v(code, ccode, cname, ctype, maxm, weight)
JOIN public.course_offering co ON co.offering_code = v.code
WHERE NOT EXISTS (
  SELECT 1 FROM public.assessment_component x
  WHERE x.course_offering_id = co.course_offering_id AND x.component_code = v.ccode
);

INSERT INTO public.assessment_event (assessment_component_id, course_offering_id, event_number, event_title, assessment_date, start_time, end_time, maximum_marks, details, status)
SELECT ac.assessment_component_id, ac.course_offering_id, v.num, v.title, v.adate, v.st, v.et, ac.maximum_marks, v.details, 'CONDUCTED'
FROM (VALUES
  ('DEMO-CS101', 'IA1', 1, 'Internal Assessment 1',   '2025-09-10'::date, '10:15'::time, '11:15'::time, 'First internal assessment of the odd semester.'),
  ('DEMO-CS101', 'END', 1, 'End Semester Examination', '2025-11-05'::date, '09:00'::time, '12:00'::time, 'End semester examination paper.'),
  ('DEMO-CS103', 'IA1', 1, 'Internal Assessment 1',   '2025-09-12'::date, '10:15'::time, '11:15'::time, 'Laboratory internal assessment.'),
  ('DEMO-CS103', 'END', 1, 'End Semester Examination', '2025-11-07'::date, '09:00'::time, '12:00'::time, 'Laboratory end semester examination.')
) AS v(code, ccode, num, title, adate, st, et, details)
JOIN public.course_offering co ON co.offering_code = v.code
JOIN public.assessment_component ac ON ac.course_offering_id = co.course_offering_id AND ac.component_code = v.ccode
WHERE NOT EXISTS (
  SELECT 1 FROM public.assessment_event x
  WHERE x.assessment_component_id = ac.assessment_component_id AND x.event_number = v.num
);

INSERT INTO public.student_assessment_mark (assessment_event_id, course_registration_id, course_offering_id, attendance_status, marks_obtained, remarks, evaluated_at)
SELECT ae.assessment_event_id, cr.course_registration_id, cr.course_offering_id, v.astatus, v.marks, NULLIF(v.remark, ''),
       (ae.assessment_date::timestamp + time '18:00') AT TIME ZONE 'UTC'
FROM (VALUES
  ('DEMO-CS101', 'IA1', 'DEMO-S001', 'PRESENT', 26.00::numeric, ''),
  ('DEMO-CS101', 'IA1', 'DEMO-S002', 'PRESENT', 21.00::numeric, ''),
  ('DEMO-CS101', 'IA1', 'DEMO-S003', 'PRESENT', 18.00::numeric, ''),
  ('DEMO-CS101', 'END', 'DEMO-S001', 'PRESENT', 64.00::numeric, ''),
  ('DEMO-CS101', 'END', 'DEMO-S002', 'PRESENT', 55.00::numeric, ''),
  ('DEMO-CS101', 'END', 'DEMO-S003', 'PRESENT', 48.00::numeric, ''),
  ('DEMO-CS103', 'IA1', 'DEMO-S001', 'PRESENT', 24.00::numeric, ''),
  ('DEMO-CS103', 'IA1', 'DEMO-S002', 'PRESENT', 22.00::numeric, ''),
  ('DEMO-CS103', 'IA1', 'DEMO-S003', 'ABSENT',  NULL::numeric, 'Absent for the internal assessment.'),
  ('DEMO-CS103', 'END', 'DEMO-S001', 'PRESENT', 60.00::numeric, ''),
  ('DEMO-CS103', 'END', 'DEMO-S002', 'PRESENT', 58.00::numeric, ''),
  ('DEMO-CS103', 'END', 'DEMO-S003', 'PRESENT', 50.00::numeric, '')
) AS v(code, ccode, snum, astatus, marks, remark)
JOIN public.course_offering co ON co.offering_code = v.code
JOIN public.assessment_component ac ON ac.course_offering_id = co.course_offering_id AND ac.component_code = v.ccode
JOIN public.assessment_event ae ON ae.assessment_component_id = ac.assessment_component_id
JOIN public.student_course_registration cr ON cr.course_offering_id = co.course_offering_id
JOIN public.student_term_registration tr ON tr.term_registration_id = cr.term_registration_id
JOIN public.student_programme_enrolment e ON e.enrolment_id = tr.enrolment_id
JOIN public.student s ON s.student_id = e.student_id AND s.student_number = v.snum
WHERE NOT EXISTS (
  SELECT 1 FROM public.student_assessment_mark x
  WHERE x.assessment_event_id = ae.assessment_event_id AND x.course_registration_id = cr.course_registration_id
);

-- The event is published only now that its marks are in: sims_assessment_event_guard refuses to
-- publish an event that was not CONDUCTED.
UPDATE public.assessment_event ae
SET status = 'PUBLISHED'
FROM public.assessment_component ac, public.course_offering co
WHERE ac.assessment_component_id = ae.assessment_component_id
  AND co.course_offering_id = ac.course_offering_id
  AND co.offering_code IN ('DEMO-CS101', 'DEMO-CS103')
  AND ae.status = 'CONDUCTED';

INSERT INTO public.student_course_result (course_registration_id, attempt_number, internal_marks, external_marks, total_marks, grade_letter, grade_point, credits_earned, result_status, result_date, remarks)
SELECT cr.course_registration_id, 1, v.internal, v.external, v.internal + v.external, v.grade, v.gp, v.credits, v.status, '2025-11-20'::date, NULLIF(v.remark, '')
FROM (VALUES
  ('DEMO-CS101', 'DEMO-S001', 26.00::numeric, 64.00::numeric, 'O',  10.00::numeric, 4.0::numeric, 'PASS', ''),
  ('DEMO-CS101', 'DEMO-S002', 21.00::numeric, 55.00::numeric, 'A',   8.00::numeric, 4.0::numeric, 'PASS', ''),
  ('DEMO-CS101', 'DEMO-S003', 18.00::numeric, 48.00::numeric, 'B+',  7.00::numeric, 4.0::numeric, 'PASS', ''),
  ('DEMO-CS103', 'DEMO-S001', 24.00::numeric, 60.00::numeric, 'A+',  9.00::numeric, 2.0::numeric, 'PASS', ''),
  ('DEMO-CS103', 'DEMO-S002', 22.00::numeric, 58.00::numeric, 'A+',  9.00::numeric, 2.0::numeric, 'PASS', ''),
  ('DEMO-CS103', 'DEMO-S003',  0.00::numeric, 50.00::numeric, 'B',   6.00::numeric, 2.0::numeric, 'PASS', 'Absent for the internal assessment.')
) AS v(code, snum, internal, external, grade, gp, credits, status, remark)
JOIN public.course_offering co ON co.offering_code = v.code
JOIN public.student_course_registration cr ON cr.course_offering_id = co.course_offering_id
JOIN public.student_term_registration tr ON tr.term_registration_id = cr.term_registration_id
JOIN public.student_programme_enrolment e ON e.enrolment_id = tr.enrolment_id
JOIN public.student s ON s.student_id = e.student_id AND s.student_number = v.snum
WHERE NOT EXISTS (
  SELECT 1 FROM public.student_course_result x
  WHERE x.course_registration_id = cr.course_registration_id AND x.attempt_number = 1
);

-- The term result is created unpublished and published afterwards, because
-- sims_course_result_lock refuses to touch a course result once the term result is published.
INSERT INTO public.student_term_result (term_registration_id, credits_registered, credits_earned, sgpa, cgpa, result_status, published_at)
SELECT tr.term_registration_id, 6.0::numeric, 6.0::numeric, v.sgpa, v.sgpa, 'PASS', NULL
FROM (VALUES
  ('DEMO-S001', 9.67::numeric),
  ('DEMO-S002', 8.33::numeric),
  ('DEMO-S003', 6.67::numeric)
) AS v(snum, sgpa)
JOIN public.student s ON s.student_number = v.snum
JOIN public.student_programme_enrolment e ON e.student_id = s.student_id
JOIN public.student_term_registration tr ON tr.enrolment_id = e.enrolment_id
WHERE tr.roll_number IN ('DEMO-R001', 'DEMO-R002', 'DEMO-R003')
  AND NOT EXISTS (
    SELECT 1 FROM public.student_term_result x WHERE x.term_registration_id = tr.term_registration_id
  );

UPDATE public.student_term_result
SET published_at = '2025-11-22 10:00:00+00'::timestamptz
WHERE published_at IS NULL
  AND term_registration_id IN (
    SELECT tr.term_registration_id
    FROM public.student_term_registration tr
    JOIN public.student_programme_enrolment e ON e.enrolment_id = tr.enrolment_id
    JOIN public.student s ON s.student_id = e.student_id
    WHERE tr.roll_number IN ('DEMO-R001', 'DEMO-R002', 'DEMO-R003')
  );

-- =============================================================================================
-- CHUNK 3 - finance, communication and activity
-- =============================================================================================
-- The fee structure of the demo programme is assessed against the three demo students, one of
-- them pays part of it, and the receipt is issued.  The communication and activity rows close
-- the loop: an announcement reaches the students, a staff member records a publication and two
-- students record their co-curricular work.
--
-- NOTHING HERE TOUCHES A SOURCE-SEEDED TABLE
--   announcement_type is a demo lookup and is safe to extend, but event_mode, activity_type,
--   student_activity_type, verification_status, approval_status, participation_level,
--   payment_mode and fee_type are seeded by the MySQL reference and are only read here.

-- ---------------------------------------------------------------------------------------------
-- Module 13 - documents and fees: the structure
-- ---------------------------------------------------------------------------------------------
INSERT INTO public.fee_structure (structure_code, structure_name, institution_id, campus_id, programme_id, specialization_id, academic_year_id, admission_category_id, version_number, effective_from, effective_to, approval_status, approved_at, remarks, is_active)
SELECT 'DEMO-FS-UGCS-2025', 'UG Computer Science 2025 - Semester 1',
       (SELECT institution_id FROM public.institution WHERE institution_code = 'DEMO-INST'),
       (SELECT campus_id FROM public.campus WHERE campus_code = 'DEMO-CAMPUS'),
       (SELECT programme_id FROM public.programme WHERE programme_code = 'DEMO-BSC-CS'),
       (SELECT sp.specialization_id FROM public.programme_specialization sp
         JOIN public.programme p ON p.programme_id = sp.programme_id
        WHERE sp.specialization_code = 'DEMO-CS-DS' AND p.programme_code = 'DEMO-BSC-CS'),
       (SELECT academic_year_id FROM public.academic_year WHERE year_code = '2025-26'),
       (SELECT admission_category_id FROM public.admission_category WHERE category_code = 'GENERAL'),
       1, '2025-07-01'::date, '2026-05-31'::date, 'APPROVED', '2025-06-20 10:00:00+00'::timestamptz,
       'Approved by the academic council.', true
WHERE NOT EXISTS (
  SELECT 1 FROM public.fee_structure x WHERE x.structure_code = 'DEMO-FS-UGCS-2025'
);

INSERT INTO public.fee_structure_item (fee_structure_id, fee_type_id, semester_id, academic_term_id, amount, due_date, due_days_from_registration, installment_allowed, waiver_allowed, display_order, remarks)
SELECT fs.fee_structure_id, ft.fee_type_id, sem.semester_id, t.academic_term_id, v.amount, v.due, v.days, true, true, v.ord, v.remark
FROM (VALUES
  ('TUITION_FEE',   120000.00::numeric, '2025-08-15'::date, 30, 1, 'Tuition fee for the first semester.'),
  ('LAB_FEE',        25000.00::numeric, '2025-08-15'::date, 30, 2, 'Laboratory fee for the programming laboratory.'),
  ('LIBRARY_FEE',     5000.00::numeric, '2025-08-15'::date, 30, 3, 'Library membership for the academic year.'),
  ('EXAM_FEE',        3000.00::numeric, '2025-10-01'::date, 90, 4, 'End semester examination fee.')
) AS v(fee_code, amount, due, days, ord, remark)
JOIN public.fee_structure fs ON fs.structure_code = 'DEMO-FS-UGCS-2025'
JOIN public.fee_type ft ON ft.fee_code = v.fee_code
JOIN public.semester sem ON sem.semester_number = 1
JOIN public.academic_term t ON t.term_code = '2025-26-ODD'
WHERE NOT EXISTS (
  SELECT 1 FROM public.fee_structure_item x
  WHERE x.fee_structure_id = fs.fee_structure_id
    AND x.fee_type_id = ft.fee_type_id
    AND x.semester_id = sem.semester_id
    AND x.academic_term_id = t.academic_term_id
);

-- ---------------------------------------------------------------------------------------------
-- Module 13 - documents and fees: the accounts and the assessments
-- ---------------------------------------------------------------------------------------------
INSERT INTO public.student_financial_account (student_id, account_number, account_status, opening_balance, credit_balance)
SELECT s.student_id, v.acct, 'ACTIVE', 0.00::numeric, 0.00::numeric
FROM (VALUES
  ('DEMO-S001', 'DEMO-FIN-001'),
  ('DEMO-S002', 'DEMO-FIN-002'),
  ('DEMO-S003', 'DEMO-FIN-003')
) AS v(snum, acct)
JOIN public.student s ON s.student_number = v.snum
WHERE NOT EXISTS (
  SELECT 1 FROM public.student_financial_account x WHERE x.account_number = v.acct
);

-- The header is inserted with zero totals on purpose: the trg_fee_item_* triggers recompute the
-- gross, concession, net, paid and balance columns from the item rows, so the assessment can
-- never disagree with its own items.
INSERT INTO public.student_fee_assessment (assessment_number, student_account_id, application_id, enrolment_id, term_registration_id, academic_year_id, academic_term_id, fee_structure_id, assessment_type, assessment_date, gross_amount, concession_amount, scholarship_amount, adjustment_amount, net_payable_amount, amount_paid, balance_amount, due_date, assessment_status, remarks)
SELECT v.num, fa.student_account_id,
       (SELECT x.application_id FROM public.admission_application x WHERE x.admitted_student_id = s.student_id),
       e.enrolment_id, tr.term_registration_id,
       ay.academic_year_id, t.academic_term_id, fs.fee_structure_id, 'ACADEMIC', '2025-07-25'::date,
       0.00::numeric, 0.00::numeric, 0.00::numeric, 0.00::numeric, 0.00::numeric, 0.00::numeric, 0.00::numeric,
       '2025-08-15'::date, 'DRAFT', 'Semester 1 fee assessment.'
FROM (VALUES
  ('DEMO-S001', 'DEMO-FEA-001'),
  ('DEMO-S002', 'DEMO-FEA-002'),
  ('DEMO-S003', 'DEMO-FEA-003')
) AS v(snum, num)
JOIN public.student s ON s.student_number = v.snum
JOIN public.student_financial_account fa ON fa.student_id = s.student_id
JOIN public.student_programme_enrolment e ON e.student_id = s.student_id
JOIN public.student_term_registration tr ON tr.enrolment_id = e.enrolment_id
JOIN public.academic_year ay ON ay.academic_year_id = e.admission_academic_year_id
JOIN public.academic_term t ON t.term_code = '2025-26-ODD'
JOIN public.fee_structure fs ON fs.structure_code = 'DEMO-FS-UGCS-2025'
WHERE NOT EXISTS (
  SELECT 1 FROM public.student_fee_assessment x WHERE x.assessment_number = v.num
);

-- DEMO-FEA-003 (Meera Iyer, DEMO-S003) carries a 5000 concession on the tuition fee.
INSERT INTO public.student_fee_assessment_item (fee_assessment_id, fee_type_id, fee_structure_item_id, description, original_amount, concession_amount, scholarship_amount, adjustment_amount, net_amount, amount_paid, balance_amount, due_date, item_status)
SELECT fsa.fee_assessment_id, fsi.fee_type_id, fsi.fee_structure_item_id, fsi.remarks,
       fsi.amount, c.concession, 0.00::numeric, 0.00::numeric,
       fsi.amount - c.concession, 0.00::numeric, fsi.amount - c.concession, fsi.due_date, 'ASSESSED'
FROM public.student_fee_assessment fsa
JOIN public.fee_structure_item fsi ON fsi.fee_structure_id = fsa.fee_structure_id
JOIN public.fee_type ft ON ft.fee_type_id = fsi.fee_type_id
CROSS JOIN LATERAL (
  SELECT CASE WHEN fsa.assessment_number = 'DEMO-FEA-003' AND ft.fee_code = 'TUITION_FEE'
              THEN 5000.00::numeric ELSE 0.00::numeric END AS concession
) c
WHERE fsa.assessment_number IN ('DEMO-FEA-001', 'DEMO-FEA-002', 'DEMO-FEA-003')
  AND NOT EXISTS (
    SELECT 1 FROM public.student_fee_assessment_item x
    WHERE x.fee_assessment_id = fsa.fee_assessment_id AND x.fee_type_id = fsi.fee_type_id
  );

UPDATE public.student_fee_assessment
SET assessment_status = 'ASSESSED'
WHERE assessment_number IN ('DEMO-FEA-001', 'DEMO-FEA-002', 'DEMO-FEA-003')
  AND assessment_status = 'DRAFT';

-- ---------------------------------------------------------------------------------------------
-- Module 13 - documents and fees: the payment, the allocation and the receipt
-- ---------------------------------------------------------------------------------------------
INSERT INTO public.payment_transaction (transaction_number, student_account_id, application_id, transaction_date, payment_mode_id, amount, currency_code, payment_status, gateway_name, gateway_transaction_id, payer_name, payer_contact, remarks)
SELECT 'DEMO-PAY-001', fa.student_account_id, NULL, '2025-08-20 10:30:00+00'::timestamptz,
       (SELECT payment_mode_id FROM public.payment_mode WHERE mode_code = 'UPI'),
       50000.00::numeric, 'INR', 'SUCCESS', 'DEMO-UPI', 'DEMO-UPI-TXN-0001',
       s.display_name, s.primary_phone, 'Part payment against DEMO-FEA-003.'
FROM public.student_financial_account fa
JOIN public.student s ON s.student_id = fa.student_id
WHERE s.student_number = 'DEMO-S003'
  AND NOT EXISTS (
    SELECT 1 FROM public.payment_transaction x WHERE x.transaction_number = 'DEMO-PAY-001'
  );

INSERT INTO public.payment_allocation (payment_transaction_id, assessment_item_id, allocated_amount, allocation_date, allocated_by)
SELECT pt.payment_transaction_id, i.assessment_item_id, 50000.00::numeric, '2025-08-20 10:35:00+00'::timestamptz, NULL
FROM public.payment_transaction pt
JOIN public.student_fee_assessment a ON a.student_account_id = pt.student_account_id
JOIN public.student_fee_assessment_item i ON i.fee_assessment_id = a.fee_assessment_id
JOIN public.fee_type ft ON ft.fee_type_id = i.fee_type_id
WHERE pt.transaction_number = 'DEMO-PAY-001' AND ft.fee_code = 'TUITION_FEE'
  AND NOT EXISTS (
    SELECT 1 FROM public.payment_allocation x
    WHERE x.payment_transaction_id = pt.payment_transaction_id AND x.assessment_item_id = i.assessment_item_id
  );

-- The receipt number is only drawn when the payment has no receipt yet, so that a replay does
-- not burn a number from sims_private.receipt_counter.
INSERT INTO public.fee_receipt (receipt_number, payment_transaction_id, receipt_date, receipt_amount, receipt_status)
SELECT sims_private.fin_next_receipt_number(), pt.payment_transaction_id, '2025-08-20 10:40:00+00'::timestamptz, pt.amount, 'ISSUED'
FROM public.payment_transaction pt
WHERE pt.transaction_number = 'DEMO-PAY-001'
  AND NOT EXISTS (
    SELECT 1 FROM public.fee_receipt r WHERE r.payment_transaction_id = pt.payment_transaction_id
  );

-- The allocation trigger recomputes the paid and balance columns but leaves the status columns
-- alone, so they are refreshed explicitly here.
UPDATE public.student_fee_assessment_item i
SET item_status = 'PARTIALLY_PAID'
FROM public.student_fee_assessment a, public.fee_type ft
WHERE a.fee_assessment_id = i.fee_assessment_id
  AND ft.fee_type_id = i.fee_type_id
  AND a.assessment_number = 'DEMO-FEA-003'
  AND ft.fee_code = 'TUITION_FEE'
  AND i.item_status = 'ASSESSED';

UPDATE public.student_fee_assessment
SET assessment_status = 'PARTIALLY_PAID'
WHERE assessment_number = 'DEMO-FEA-003'
  AND assessment_status = 'ASSESSED';

-- ---------------------------------------------------------------------------------------------
-- Module 14 - communication
-- ---------------------------------------------------------------------------------------------
INSERT INTO public.announcement_type (type_code, type_name, is_active)
VALUES ('DEMO-GENERAL', 'Demo General', true),
       ('DEMO-ACADEMIC', 'Demo Academic', true),
       ('DEMO-EXAM', 'Demo Examination', true)
ON CONFLICT DO NOTHING;

INSERT INTO public.announcement (announcement_type_id, department_id, title, description, publish_from, publish_to, approval_status, audience_type)
SELECT t.announcement_type_id, d.department_id, v.title, v.description, v.pfrom, v.pto, 'APPROVED', v.audience
FROM (VALUES
  ('DEMO-GENERAL',  NULL::text, 'Demo University orientation',
   'The orientation for the odd semester starts on 2025-08-04 in the academic block.',
   '2025-08-01 09:00:00+00'::timestamptz, NULL::timestamptz, 'ALL'),
  ('DEMO-ACADEMIC', 'DEMO-CSE', 'Mid semester study leave',
   'The mid semester study leave runs from 2025-10-01 to 2025-10-07.',
   '2025-09-25 09:00:00+00'::timestamptz, '2025-10-08 09:00:00+00'::timestamptz, 'STUDENTS')
) AS v(tcode, dept, title, description, pfrom, pto, audience)
JOIN public.announcement_type t ON t.type_code = v.tcode
LEFT JOIN public.department d ON d.department_code = v.dept
WHERE NOT EXISTS (
  SELECT 1 FROM public.announcement x WHERE x.title = v.title
);

-- ---------------------------------------------------------------------------------------------
-- Module 19 - staff profile: the research record
-- ---------------------------------------------------------------------------------------------
INSERT INTO public.staff_activity (employee_id, activity_type_id, academic_year_id, institution_id, campus_id, department_id, participation_level_id, primary_role_type_id, activity_title, start_date, end_date, description, outcomes, verification_status_id, approval_status_id, remarks)
SELECT e.employee_id,
       (SELECT activity_type_id FROM public.activity_type WHERE activity_type_code = 'JOURNAL_PUBLICATION'),
       (SELECT academic_year_id FROM public.academic_year WHERE year_code = '2025-26'),
       (SELECT institution_id FROM public.institution WHERE institution_code = 'DEMO-INST'),
       (SELECT campus_id FROM public.campus WHERE campus_code = 'DEMO-CAMPUS'),
       (SELECT department_id FROM public.department WHERE department_code = 'DEMO-CSE'),
       (SELECT participation_level_id FROM public.participation_level WHERE level_code = 'DEPARTMENT'),
       (SELECT role_type_id FROM public.role_type WHERE role_code = 'AUTHOR'),
       'Attendance analytics of the first year programming laboratory',
       '2025-07-14'::date, '2025-09-30'::date,
       'Research record for the journal article on the laboratory attendance of the first year.',
       'Manuscript prepared and submitted to a peer reviewed journal.',
       (SELECT verification_status_id FROM public.verification_status WHERE status_code = 'PENDING'),
       (SELECT approval_status_id FROM public.approval_status WHERE status_code = 'DRAFT'),
       'Awaiting verification and approval.'
FROM public.employee e
WHERE e.employee_number = 'DEMO-E001'
  AND NOT EXISTS (
    SELECT 1 FROM public.staff_activity x
    WHERE x.employee_id = e.employee_id
      AND x.activity_title = 'Attendance analytics of the first year programming laboratory'
  );

-- ---------------------------------------------------------------------------------------------
-- Module 40 - student activity: the co-curricular record
-- ---------------------------------------------------------------------------------------------
INSERT INTO public.student_activity (student_id, student_activity_type_id, academic_year_id, institution_id, campus_id, department_id, programme_id, participation_level_id, event_mode_id, activity_title, event_name, team_name, participation_role, start_date, end_date, venue_name, city, achievement_type, position_rank, award_name, certificate_number, description, outcomes, verification_status_id, approval_status_id, remarks)
SELECT s.student_id,
       (SELECT student_activity_type_id FROM public.student_activity_type WHERE type_code = 'SPORTS'),
       (SELECT academic_year_id FROM public.academic_year WHERE year_code = '2025-26'),
       (SELECT institution_id FROM public.institution WHERE institution_code = 'DEMO-INST'),
       (SELECT campus_id FROM public.campus WHERE campus_code = 'DEMO-CAMPUS'),
       (SELECT department_id FROM public.department WHERE department_code = 'DEMO-CSE'),
       (SELECT programme_id FROM public.programme WHERE programme_code = 'DEMO-BSC-CS'),
       (SELECT participation_level_id FROM public.participation_level WHERE level_code = 'DEPARTMENT'),
       (SELECT event_mode_id FROM public.event_mode WHERE mode_code = 'OFFLINE'),
       'Inter-college athletics meet',
       'Demo Inter-college Athletics Meet',
       'Demo Athletics Team',
       'Captain',
       '2025-09-27'::date, '2025-09-28'::date,
       'Demo Sports Ground', 'Haveri',
       'WINNER', 1,
       'Winner of the 100 metres race',
       'DEMO-CERT-S001',
       'Represented the department in the inter-college athletics meet.',
       'Won the 100 metres race.',
       (SELECT verification_status_id FROM public.verification_status WHERE status_code = 'PENDING'),
       (SELECT approval_status_id FROM public.approval_status WHERE status_code = 'DRAFT'),
       'Awaiting verification and approval.'
FROM public.student s
WHERE s.student_number = 'DEMO-S001'
  AND NOT EXISTS (
    SELECT 1 FROM public.student_activity x
    WHERE x.student_id = s.student_id
      AND x.activity_title = 'Inter-college athletics meet'
  );

INSERT INTO public.student_activity (student_id, student_activity_type_id, academic_year_id, institution_id, campus_id, department_id, programme_id, participation_level_id, event_mode_id, activity_title, event_name, team_name, participation_role, start_date, end_date, venue_name, city, achievement_type, position_rank, award_name, certificate_number, description, outcomes, verification_status_id, approval_status_id, remarks)
SELECT s.student_id,
       (SELECT student_activity_type_id FROM public.student_activity_type WHERE type_code = 'HACKATHON'),
       (SELECT academic_year_id FROM public.academic_year WHERE year_code = '2025-26'),
       (SELECT institution_id FROM public.institution WHERE institution_code = 'DEMO-INST'),
       (SELECT campus_id FROM public.campus WHERE campus_code = 'DEMO-CAMPUS'),
       (SELECT department_id FROM public.department WHERE department_code = 'DEMO-CSE'),
       (SELECT programme_id FROM public.programme WHERE programme_code = 'DEMO-BSC-CS'),
       (SELECT participation_level_id FROM public.participation_level WHERE level_code = 'DEPARTMENT'),
       (SELECT event_mode_id FROM public.event_mode WHERE mode_code = 'OFFLINE'),
       'Smart India Hackathon',
       'Smart India Hackathon 2025',
       'CodeCraft',
       'Developer',
       '2025-09-12'::date, '2025-09-13'::date,
       'Demo Innovation Centre', 'Haveri',
       'PARTICIPATION', NULL,
       NULL, NULL,
       'Participated in the Smart India Hackathon as a member of the CodeCraft team.',
       'Built a working prototype of the attendance analytics dashboard.',
       (SELECT verification_status_id FROM public.verification_status WHERE status_code = 'PENDING'),
       (SELECT approval_status_id FROM public.approval_status WHERE status_code = 'DRAFT'),
       'Awaiting verification and approval.'
FROM public.student s
WHERE s.student_number = 'DEMO-S002'
  AND NOT EXISTS (
    SELECT 1 FROM public.student_activity x
    WHERE x.student_id = s.student_id
      AND x.activity_title = 'Smart India Hackathon'
  );

-- =============================================================================================
-- CHUNK 4 - timetable, mentoring, documents, feedback, employee HR and service requests
-- =============================================================================================
-- The rows below fill the modules that chunk 1 to chunk 3 left empty: the weekly teaching plan,
-- the student complaints and their trail, the mentoring record, the document vault, the feedback
-- questionnaires, the employee HR profile and the student service requests.  Every row is again
-- addressed by its DEMO-* business key, so the chunk can be replayed any number of times.
--
-- ORDER MATTERS IN FOUR PLACES
--   * The timetable rows are inserted after the teaching allocation of chunk 2, because
--     sims_timetable_guard checks the room, the instructor and the teaching section for a clash.
--   * The feedback questions are attached to their questionnaire before the cycle is opened, because
--     sims_feedback_cycle_guard refuses to open a cycle whose questionnaire has no question and
--     sims_feedback_item_guard refuses to change the questions of a questionnaire that is already
--     used by an open cycle.
--   * The employee documents are inserted after the qualification, the previous employment and the
--     identity rows they point at.
--   * The service request table lives in the private schema, so its insert is written as a CTE:
--     the seed tool reads the table name from the statement and a plain INSERT INTO
--     sims_private... would be read as a table called "sims_private".

-- ---------------------------------------------------------------------------------------------
-- Module 8 - timetable: the weekly teaching plan
-- ---------------------------------------------------------------------------------------------
-- The demo institute has a single room, so the plan is laid out so that no two entries share a
-- room, an instructor or a teaching section at the same time:
--
--    DEMO-CS101  lecture    Anita Rao     DEMO-T1  Monday, Wednesday, Friday
--                           DEMO-T2  Tuesday, Thursday
--    DEMO-CS103  practical  Suresh Kumar  DEMO-T5  Monday to Friday
--
-- DEMO-T1 (09:00-10:00), DEMO-T2 (10:15-11:15) and DEMO-T5 (14:45-15:45) do not overlap, so
-- sims_timetable_guard lets every row through.
INSERT INTO public.timetable_session (course_offering_section_id, faculty_assignment_id, day_of_week, time_slot_id, room_id, effective_from, effective_to)
SELECT cos.course_offering_section_id, fa.faculty_assignment_id, v.day, ts.time_slot_id, r.room_id,
       '2025-07-01'::date, '2026-05-31'::date
FROM (VALUES
  ('DEMO-CS101', 'PRIMARY_INSTRUCTOR', 1, 'DEMO-T1'),
  ('DEMO-CS101', 'PRIMARY_INSTRUCTOR', 3, 'DEMO-T1'),
  ('DEMO-CS101', 'PRIMARY_INSTRUCTOR', 5, 'DEMO-T1'),
  ('DEMO-CS101', 'PRIMARY_INSTRUCTOR', 2, 'DEMO-T2'),
  ('DEMO-CS101', 'PRIMARY_INSTRUCTOR', 4, 'DEMO-T2'),
  ('DEMO-CS103', 'LAB_INSTRUCTOR',     1, 'DEMO-T5'),
  ('DEMO-CS103', 'LAB_INSTRUCTOR',     2, 'DEMO-T5'),
  ('DEMO-CS103', 'LAB_INSTRUCTOR',     3, 'DEMO-T5'),
  ('DEMO-CS103', 'LAB_INSTRUCTOR',     4, 'DEMO-T5'),
  ('DEMO-CS103', 'LAB_INSTRUCTOR',     5, 'DEMO-T5')
) AS v(offering_code, rolecode, day, slot_code)
JOIN public.course_offering co ON co.offering_code = v.offering_code
JOIN public.course_offering_section cos ON cos.course_offering_id = co.course_offering_id
JOIN public.faculty_course_assignment fa ON fa.course_offering_section_id = cos.course_offering_section_id
                                         AND fa.assignment_role = v.rolecode
JOIN public.time_slot ts ON ts.slot_code = v.slot_code
JOIN public.room r ON r.room_code = 'DEMO-101'
WHERE NOT EXISTS (
  SELECT 1 FROM public.timetable_session t
  WHERE t.course_offering_section_id = cos.course_offering_section_id
    AND t.faculty_assignment_id = fa.faculty_assignment_id
    AND t.day_of_week = v.day
    AND t.time_slot_id = ts.time_slot_id
    AND t.effective_from = '2025-07-01'::date
);

-- ---------------------------------------------------------------------------------------------
-- Module 12 - grievance: the categories, the complaints and their trail
-- ---------------------------------------------------------------------------------------------
INSERT INTO public.grievance_category (category_code, category_name, is_active)
VALUES ('DEMO-ACADEMIC', 'Demo Academic', true),
       ('DEMO-HOSTEL', 'Demo Hostel and Facilities', true),
       ('DEMO-FEES', 'Demo Fees and Payments', true),
       ('DEMO-EXAM', 'Demo Examinations', true)
ON CONFLICT DO NOTHING;

INSERT INTO public.grievance (grievance_number, student_id, grievance_category_id, department_id, submitted_at, subject, description, priority, status, resolved_at, resolution)
SELECT v.num, s.student_id, gc.grievance_category_id, d.department_id, v.submitted_at, v.subject, v.description,
       v.priority, v.status, v.resolved_at, v.resolution
FROM (VALUES
  ('DEMO-GRV-001', 'DEMO-S001', 'DEMO-ACADEMIC', 'DEMO-CSE',
   '2025-09-05 09:15:00+00'::timestamptz,
   'The laboratory slot clashes with the theory class',
   'The programming laboratory is scheduled at the same time as the theory class, so the practical cannot be attended.',
   'HIGH', 'CLOSED', '2025-09-12 11:00:00+00'::timestamptz,
   'The laboratory was moved to the fifth slot of the afternoon.'),
  ('DEMO-GRV-002', 'DEMO-S002', 'DEMO-HOSTEL', 'DEMO-CSE',
   '2025-09-10 08:40:00+00'::timestamptz,
   'The hostel water supply is out of order',
   'There has been no water in the hostel block since the second week of September.',
   'NORMAL', 'UNDER_REVIEW', NULL::timestamptz, NULL::text),
  ('DEMO-GRV-003', 'DEMO-S003', 'DEMO-FEES', 'DEMO-CSE',
   '2025-09-15 14:05:00+00'::timestamptz,
   'The laboratory fee was charged twice',
   'The laboratory fee appears on two different fee assessments for the same semester.',
   'URGENT', 'SUBMITTED', NULL::timestamptz, NULL::text)
) AS v(num, snum, catcode, deptcode, submitted_at, subject, description, priority, status, resolved_at, resolution)
JOIN public.student s ON s.student_number = v.snum
JOIN public.grievance_category gc ON gc.category_code = v.catcode
JOIN public.department d ON d.department_code = v.deptcode
WHERE NOT EXISTS (
  SELECT 1 FROM public.grievance x WHERE x.grievance_number = v.num
);

-- The action trail mirrors the status of the complaint it belongs to.
INSERT INTO public.grievance_action (grievance_id, action_at, action_type, action_notes, new_status)
SELECT g.grievance_id, v.action_at, v.action_type, v.action_notes, v.new_status
FROM (VALUES
  ('DEMO-GRV-001', '2025-09-05 09:20:00+00'::timestamptz, 'SUBMITTED', 'The complaint was received by the department office.', 'SUBMITTED'),
  ('DEMO-GRV-001', '2025-09-06 10:00:00+00'::timestamptz, 'ASSIGNED', 'The complaint was assigned to the head of the department.', 'ASSIGNED'),
  ('DEMO-GRV-001', '2025-09-08 11:00:00+00'::timestamptz, 'UNDER_REVIEW', 'The timetable of the laboratory was checked.', 'UNDER_REVIEW'),
  ('DEMO-GRV-001', '2025-09-12 10:45:00+00'::timestamptz, 'RESOLVED', 'The laboratory was moved to the fifth slot of the afternoon.', 'RESOLVED'),
  ('DEMO-GRV-001', '2025-09-12 11:00:00+00'::timestamptz, 'CLOSED', 'The student was informed and the complaint was closed.', 'CLOSED'),
  ('DEMO-GRV-002', '2025-09-10 08:45:00+00'::timestamptz, 'SUBMITTED', 'The complaint was received by the student section office.', 'SUBMITTED'),
  ('DEMO-GRV-002', '2025-09-11 10:30:00+00'::timestamptz, 'ASSIGNED', 'The complaint was assigned to the estate office.', 'ASSIGNED'),
  ('DEMO-GRV-003', '2025-09-15 14:10:00+00'::timestamptz, 'SUBMITTED', 'The complaint was received by the fee office.', 'SUBMITTED')
) AS v(num, action_at, action_type, action_notes, new_status)
JOIN public.grievance g ON g.grievance_number = v.num
WHERE NOT EXISTS (
  SELECT 1 FROM public.grievance_action a
  WHERE a.grievance_id = g.grievance_id AND a.action_at = v.action_at AND a.action_type = v.action_type
);

-- ---------------------------------------------------------------------------------------------
-- Module 12 - mentoring: the mentor assignments and the counselling record
-- ---------------------------------------------------------------------------------------------
INSERT INTO public.mentor_assignment (student_id, employee_id, start_date, end_date, assignment_status)
SELECT s.student_id, e.employee_id, v.start_date, v.end_date, v.assignment_status
FROM (VALUES
  ('DEMO-S001', 'DEMO-E001', '2025-07-01'::date, NULL::date, 'ACTIVE'),
  ('DEMO-S002', 'DEMO-E002', '2025-07-01'::date, NULL::date, 'ACTIVE'),
  ('DEMO-S003', 'DEMO-E001', '2025-07-01'::date, NULL::date, 'ACTIVE')
) AS v(snum, empnum, start_date, end_date, assignment_status)
JOIN public.student s ON s.student_number = v.snum
JOIN public.employee e ON e.employee_number = v.empnum
WHERE NOT EXISTS (
  SELECT 1 FROM public.mentor_assignment x
  WHERE x.student_id = s.student_id AND x.employee_id = e.employee_id AND x.start_date = v.start_date
);

INSERT INTO public.counselling_session (mentor_assignment_id, session_date, observations, action_plan, follow_up_date, session_status, confidentiality_level)
SELECT ma.mentor_assignment_id, v.session_date, v.observations, v.action_plan, v.follow_up_date, v.session_status, v.confidentiality_level
FROM (VALUES
  ('DEMO-S001', 'DEMO-E001', '2025-08-11 10:00:00+00'::timestamptz,
   'The student is settling in well but finds the laboratory pace fast.',
   'Share the laboratory handbook and arrange a study group.',
   '2025-09-15'::date, 'COMPLETED', 'RESTRICTED'),
  ('DEMO-S001', 'DEMO-E001', '2025-09-16 10:00:00+00'::timestamptz,
   'The laboratory handbook helped and the study group is running.',
   'Keep the weekly check-in until the internal assessment.',
   NULL::date, 'COMPLETED', 'NORMAL'),
  ('DEMO-S002', 'DEMO-E002', '2025-09-01 15:00:00+00'::timestamptz,
   'The student is worried about the hostel and the course load together.',
   'Refer the hostel issue to the estate office and share the study plan.',
   '2025-10-01'::date, 'FOLLOW_UP_REQUIRED', 'RESTRICTED'),
  ('DEMO-S003', 'DEMO-E001', '2025-10-06 11:30:00+00'::timestamptz,
   'The student is preparing for the competitive coding event.',
   'Mentor the team and review the submission before the final round.',
   NULL::date, 'COMPLETED', 'HIGHLY_RESTRICTED')
) AS v(snum, empnum, session_date, observations, action_plan, follow_up_date, session_status, confidentiality_level)
JOIN public.mentor_assignment ma ON ma.student_id = (SELECT student_id FROM public.student WHERE student_number = v.snum)
                              AND ma.employee_id = (SELECT employee_id FROM public.employee WHERE employee_number = v.empnum)
WHERE NOT EXISTS (
  SELECT 1 FROM public.counselling_session c
  WHERE c.mentor_assignment_id = ma.mentor_assignment_id AND c.session_date = v.session_date
);

-- ---------------------------------------------------------------------------------------------
-- Module 13 - documents: the files, the student documents and the certificate requests
-- ---------------------------------------------------------------------------------------------
-- The files are placeholders: the storage key, the name, the type and the size are what the
-- screens show, and the checksum is the sha256 of the storage key so that the row is stable.
INSERT INTO public.file_object (storage_provider, storage_key, original_file_name, mime_type, file_size_bytes, checksum_sha256, uploaded_at, stored_file_name, file_extension, confidentiality_level, is_encrypted, virus_scan_status, virus_scanned_at)
SELECT 'supabase-storage', v.storage_key, v.file_name, v.mime_type, v.file_size, v.checksum, v.uploaded_at,
       v.file_name, 'pdf', v.confidentiality_level, false, 'CLEAN', v.uploaded_at
FROM (VALUES
  ('DEMO/student/DEMO-S001/marks-card-sem1.pdf', 'marks-card-sem1.pdf', 'application/pdf', 184320,
   'd96bf84faab25084685228fb1caafbc0d30e72ffec0d4fa5be5edd54645d12ff', '2025-08-10 09:00:00+00'::timestamptz, 'INTERNAL'),
  ('DEMO/student/DEMO-S002/consolidated-marks-sem1.pdf', 'consolidated-marks-sem1.pdf', 'application/pdf', 156800,
   '5a8d16b98f68f4d22c36ec82f8fe5169c8ea2450a127588b8c3e67caeadf8a4e', '2025-08-12 09:30:00+00'::timestamptz, 'INTERNAL'),
  ('DEMO/student/DEMO-S003/migration-certificate.pdf', 'migration-certificate.pdf', 'application/pdf', 98304,
   '7442ec115f77c6248beabbc12f678b93535ca725f4a44006b40338839a0d9c4d', '2025-08-14 10:15:00+00'::timestamptz, 'INTERNAL'),
  ('DEMO/certificate/DEMO-CERT-REQ-003-bonafide.pdf', 'bonafide-certificate.pdf', 'application/pdf', 65536,
   'f4493f51bb6d47b4b9f5f6dc75032a5d44f97c17acad092089bc8a8f2e061d6e', '2025-09-10 12:05:00+00'::timestamptz, 'CONFIDENTIAL'),
  ('DEMO/employee/DEMO-E001/qualification/phd-award-certificate.pdf', 'phd-award-certificate.pdf', 'application/pdf', 245760,
   '729224069944ef7c51a4d8a25a23e15cd137525e3f1cdda1969deeacc0f53ee6', '2025-09-01 09:00:00+00'::timestamptz, 'CONFIDENTIAL'),
  ('DEMO/employee/DEMO-E002/qualification/masters-degree-certificate.pdf', 'masters-degree-certificate.pdf', 'application/pdf', 204800,
   '2013281572f6d97412031543ce469af049784601faecf5b59880656d357152f1', '2025-09-01 09:05:00+00'::timestamptz, 'CONFIDENTIAL'),
  ('DEMO/employee/DEMO-E001/experience/relieving-letter.pdf', 'relieving-letter.pdf', 'application/pdf', 40960,
   '595423f7e88720156b02542022b36918f359100890fc0bf9162136f15be46e90', '2025-09-01 09:10:00+00'::timestamptz, 'CONFIDENTIAL'),
  ('DEMO/employee/DEMO-E001/general/appointment-letter.pdf', 'appointment-letter.pdf', 'application/pdf', 53248,
   '2ace404bfc0ccaa5f6764a2aba7e0bd4ae066ddbdc196ed5303f279215ade4c2', '2025-09-01 09:15:00+00'::timestamptz, 'CONFIDENTIAL'),
  ('DEMO/employee/DEMO-E002/general/staff-identity-card.pdf', 'staff-identity-card.pdf', 'application/pdf', 30720,
   'd21d1198d67740f2d0b9002c6a916385e1d4cd6520636ec0e0a7d1b52667b285', '2025-09-01 09:20:00+00'::timestamptz, 'INTERNAL'),
  ('DEMO/employee/DEMO-E001/pan/pan-card.pdf', 'pan-card.pdf', 'application/pdf', 45056,
   '3d3f73b71b23cb3d62499bcb2114ddcaae5d35020dbb907b57ad5983b3ac90ed', '2025-09-02 09:00:00+00'::timestamptz, 'HIGHLY_RESTRICTED'),
  ('DEMO/employee/DEMO-E001/aadhaar/e-aadhaar.pdf', 'e-aadhaar.pdf', 'application/pdf', 61440,
   'ca8c07baeca27678544329c151343f84917737881384db4d1427dd82bad4871c', '2025-09-02 09:05:00+00'::timestamptz, 'HIGHLY_RESTRICTED'),
  ('DEMO/employee/DEMO-E002/bank/bank-confirmation.pdf', 'bank-confirmation.pdf', 'application/pdf', 36864,
   '6f6d50be5040b199c074529e3c7174052d642285ab00d8c82abef1b090c39636', '2025-09-02 09:10:00+00'::timestamptz, 'HIGHLY_RESTRICTED')
) AS v(storage_key, file_name, mime_type, file_size, checksum, uploaded_at, confidentiality_level)
WHERE NOT EXISTS (
  SELECT 1 FROM public.file_object x WHERE x.storage_key = v.storage_key
);

INSERT INTO public.student_document (student_id, document_type_id, file_object_id, document_number, issue_date, expiry_date, verification_status, verified_at, remarks)
SELECT s.student_id, dt.document_type_id, f.file_object_id, v.document_number, v.issue_date, v.expiry_date,
       v.verification_status, v.verified_at, v.remarks
FROM (VALUES
  ('DEMO-S001', 'MARKS_CARD', 'DEMO/student/DEMO-S001/marks-card-sem1.pdf', 'DEMO-S001-MC-2025',
   '2025-08-10'::date, NULL::date, 'VERIFIED', '2025-08-12 10:00:00+00'::timestamptz, 'Verified against the examination cell record.'),
  ('DEMO-S002', 'CONSOLIDATED_MARKS', 'DEMO/student/DEMO-S002/consolidated-marks-sem1.pdf', 'DEMO-S002-CMC-2025',
   '2025-08-12'::date, NULL::date, 'VERIFIED', '2025-08-14 11:00:00+00'::timestamptz, 'Verified against the examination cell record.'),
  ('DEMO-S003', 'MIGRATION_CERT', 'DEMO/student/DEMO-S003/migration-certificate.pdf', 'DEMO-S003-MIG-2025',
   '2025-08-14'::date, NULL::date, 'VERIFIED', '2025-08-16 09:30:00+00'::timestamptz, 'Verified against the admission record.')
) AS v(snum, doccode, storage_key, document_number, issue_date, expiry_date, verification_status, verified_at, remarks)
JOIN public.student s ON s.student_number = v.snum
JOIN public.document_type dt ON dt.document_code = v.doccode
JOIN public.file_object f ON f.storage_key = v.storage_key
WHERE NOT EXISTS (
  SELECT 1 FROM public.student_document x
  WHERE x.student_id = s.student_id AND x.document_type_id = dt.document_type_id AND x.document_number = v.document_number
);

INSERT INTO public.certificate_request (request_number, student_id, certificate_type_id, requested_at, purpose, request_status, issued_at, certificate_number, file_object_id)
SELECT v.request_number, s.student_id, ct.certificate_type_id, v.requested_at, v.purpose, v.request_status,
       v.issued_at, v.certificate_number, f.file_object_id
FROM (VALUES
  ('DEMO-CERT-REQ-001', 'DEMO-S001', 'BONAFIDE', '2025-09-02 10:00:00+00'::timestamptz,
   'Applied for a bonafide certificate for a bank loan.', 'SUBMITTED', NULL::timestamptz, NULL::text, NULL::text),
  ('DEMO-CERT-REQ-002', 'DEMO-S002', 'CHARACTER', '2025-09-04 11:30:00+00'::timestamptz,
   'Applied for a character certificate for a passport application.', 'APPROVED', NULL::timestamptz, NULL::text, NULL::text),
  ('DEMO-CERT-REQ-003', 'DEMO-S003', 'NO_DUES', '2025-09-06 09:45:00+00'::timestamptz,
   'Applied for a no dues certificate for the transfer application.', 'ISSUED',
   '2025-09-10 12:00:00+00'::timestamptz, 'DEMO-CERT-2025-0003', 'DEMO/certificate/DEMO-CERT-REQ-003-bonafide.pdf')
) AS v(request_number, snum, certcode, requested_at, purpose, request_status, issued_at, certificate_number, storage_key)
JOIN public.student s ON s.student_number = v.snum
JOIN public.certificate_type ct ON ct.certificate_code = v.certcode
LEFT JOIN public.file_object f ON f.storage_key = v.storage_key
WHERE NOT EXISTS (
  SELECT 1 FROM public.certificate_request x WHERE x.request_number = v.request_number
);

-- ---------------------------------------------------------------------------------------------
-- Module 11 - feedback: the questions, the questionnaires and the open cycles
-- ---------------------------------------------------------------------------------------------
INSERT INTO public.feedback_question_category (category_code, category_name, is_active)
VALUES ('DEMO-TEACHING', 'Demo Teaching and Learning', true),
       ('DEMO-COURSE-CONTENT', 'Demo Course Content', true),
       ('DEMO-FACULTY', 'Demo Faculty Support', true)
ON CONFLICT DO NOTHING;

INSERT INTO public.feedback_question (feedback_category_id, question_text, response_type, is_active)
SELECT c.feedback_category_id, v.question_text, v.response_type, true
FROM (VALUES
  ('DEMO-TEACHING', 'How would you rate the clarity of the lectures?', 'RATING'),
  ('DEMO-COURSE-CONTENT', 'How much of the course material was covered?', 'SINGLE_CHOICE'),
  ('DEMO-COURSE-CONTENT', 'What should be improved in this course?', 'TEXT'),
  ('DEMO-FACULTY', 'How would you rate the support you received from the faculty?', 'RATING'),
  ('DEMO-FACULTY', 'How often did you receive feedback on your progress?', 'MULTIPLE_CHOICE')
) AS v(catcode, question_text, response_type)
JOIN public.feedback_question_category c ON c.category_code = v.catcode
WHERE NOT EXISTS (
  SELECT 1 FROM public.feedback_question x
  WHERE x.feedback_category_id = c.feedback_category_id AND x.question_text = v.question_text
);

INSERT INTO public.feedback_choice (feedback_question_id, choice_text, score, display_order, is_active)
SELECT q.feedback_question_id, v.choice_text, v.score, v.display_order, true
FROM (VALUES
  ('How would you rate the clarity of the lectures?', 'Excellent', 5.00::numeric, 1),
  ('How would you rate the clarity of the lectures?', 'Good', 4.00::numeric, 2),
  ('How would you rate the clarity of the lectures?', 'Average', 3.00::numeric, 3),
  ('How would you rate the clarity of the lectures?', 'Poor', 2.00::numeric, 4),
  ('How much of the course material was covered?', 'Almost everything', 5.00::numeric, 1),
  ('How much of the course material was covered?', 'About half', 3.00::numeric, 2),
  ('How much of the course material was covered?', 'Very little', 1.00::numeric, 3),
  ('How would you rate the support you received from the faculty?', 'Excellent', 5.00::numeric, 1),
  ('How would you rate the support you received from the faculty?', 'Good', 4.00::numeric, 2),
  ('How would you rate the support you received from the faculty?', 'Average', 3.00::numeric, 3),
  ('How would you rate the support you received from the faculty?', 'Poor', 2.00::numeric, 4),
  ('How often did you receive feedback on your progress?', 'After every session', 5.00::numeric, 1),
  ('How often did you receive feedback on your progress?', 'Every week', 4.00::numeric, 2),
  ('How often did you receive feedback on your progress?', 'Every fortnight', 3.00::numeric, 3),
  ('How often did you receive feedback on your progress?', 'Once a month', 2.00::numeric, 4),
  ('How often did you receive feedback on your progress?', 'Rarely', 1.00::numeric, 5),
  ('How often did you receive feedback on your progress?', 'Never', 0.00::numeric, 6)
) AS v(question_text, choice_text, score, display_order)
JOIN public.feedback_question q ON q.question_text = v.question_text
WHERE NOT EXISTS (
  SELECT 1 FROM public.feedback_choice x
  WHERE x.feedback_question_id = q.feedback_question_id AND x.choice_text = v.choice_text
);

INSERT INTO public.feedback_questionnaire (questionnaire_code, questionnaire_name, questionnaire_type, is_anonymous, status)
VALUES ('DEMO-FB-COURSE-2025', 'Demo Course Feedback 2025', 'COURSE', true, 'ACTIVE'),
       ('DEMO-FB-FACULTY-2025', 'Demo Faculty Feedback 2025', 'FACULTY', true, 'ACTIVE')
ON CONFLICT DO NOTHING;

-- The questions are attached before the cycle is opened, because sims_feedback_item_guard locks the
-- questions of a questionnaire that an open cycle already uses.
INSERT INTO public.feedback_questionnaire_item (questionnaire_id, feedback_question_id, weightage, display_order, is_required)
SELECT qn.questionnaire_id, q.feedback_question_id, v.weightage, v.display_order, true
FROM (VALUES
  ('DEMO-FB-COURSE-2025', 'How would you rate the clarity of the lectures?', 40.00::numeric, 1),
  ('DEMO-FB-COURSE-2025', 'How much of the course material was covered?', 30.00::numeric, 2),
  ('DEMO-FB-COURSE-2025', 'What should be improved in this course?', 30.00::numeric, 3),
  ('DEMO-FB-FACULTY-2025', 'How would you rate the support you received from the faculty?', 60.00::numeric, 1),
  ('DEMO-FB-FACULTY-2025', 'How often did you receive feedback on your progress?', 40.00::numeric, 2)
) AS v(qcode, question_text, weightage, display_order)
JOIN public.feedback_questionnaire qn ON qn.questionnaire_code = v.qcode
JOIN public.feedback_question q ON q.question_text = v.question_text
WHERE NOT EXISTS (
  SELECT 1 FROM public.feedback_questionnaire_item x
  WHERE x.questionnaire_id = qn.questionnaire_id AND x.feedback_question_id = q.feedback_question_id
);

-- The cycles stay open until the end of 2026 so that the feedback task list is never empty.
INSERT INTO public.feedback_cycle (questionnaire_id, academic_term_id, cycle_name, start_at, end_at, result_visibility, status)
SELECT qn.questionnaire_id, t.academic_term_id, v.cycle_name, v.start_at, v.end_at, v.result_visibility, 'OPEN'
FROM (VALUES
  ('DEMO-FB-COURSE-2025', 'Demo Course Feedback - Odd Semester 2025',
   '2025-10-01 00:00:00+00'::timestamptz, '2026-12-31 23:59:59+00'::timestamptz, 'FACULTY'),
  ('DEMO-FB-FACULTY-2025', 'Demo Faculty Feedback - Odd Semester 2025',
   '2025-10-01 00:00:00+00'::timestamptz, '2026-12-31 23:59:59+00'::timestamptz, 'ADMIN_ONLY')
) AS v(qcode, cycle_name, start_at, end_at, result_visibility)
JOIN public.feedback_questionnaire qn ON qn.questionnaire_code = v.qcode
JOIN public.academic_term t ON t.term_code = '2025-26-ODD'
WHERE NOT EXISTS (
  SELECT 1 FROM public.feedback_cycle x
  WHERE x.questionnaire_id = qn.questionnaire_id
    AND x.academic_term_id = t.academic_term_id
    AND x.cycle_name = v.cycle_name
);

-- ---------------------------------------------------------------------------------------------
-- Module 16 - employee HR: the lookups the profile points at
-- ---------------------------------------------------------------------------------------------
INSERT INTO public.previous_organization (previous_organization_type_id, organization_name, address_line_1, city, state_id, country_id, postal_code, phone, email, website_url, is_active)
SELECT t.previous_organization_type_id, 'Demo Polytechnic, Haveri', '18 Demo Industrial Road', 'Haveri',
       (SELECT state_id FROM public.state WHERE state_code = 'KA'
          AND country_id = (SELECT country_id FROM public.country WHERE iso_code = 'IN') LIMIT 1),
       (SELECT country_id FROM public.country WHERE iso_code = 'IN'),
       '581115', '+91-9000000021', 'office@demo-poly.edu', 'https://demo-poly.edu', true
FROM public.previous_organization_type t
WHERE t.type_code = 'PRIVATE_COMPANY'
  AND NOT EXISTS (
    SELECT 1 FROM public.previous_organization x
    WHERE x.organization_name = 'Demo Polytechnic, Haveri' AND x.city = 'Haveri'
  );

INSERT INTO public.education_institution (education_institution_type_id, institution_name, city, state_id, country_id, website_url, is_active)
SELECT t.education_institution_type_id, 'Demo University, Haveri', 'Haveri',
       (SELECT state_id FROM public.state WHERE state_code = 'KA'
          AND country_id = (SELECT country_id FROM public.country WHERE iso_code = 'IN') LIMIT 1),
       (SELECT country_id FROM public.country WHERE iso_code = 'IN'),
       'https://demo-univ.edu', true
FROM public.education_institution_type t
WHERE t.type_code = 'UNIVERSITY'
  AND NOT EXISTS (
    SELECT 1 FROM public.education_institution x
    WHERE x.institution_name = 'Demo University, Haveri' AND x.city = 'Haveri'
  );

-- ---------------------------------------------------------------------------------------------
-- Module 16 - employee HR: the qualifications, the experience and the addresses
-- ---------------------------------------------------------------------------------------------
INSERT INTO public.employee_qualification (employee_id, qualification_level_id, education_institution_id, study_mode_id, degree_certificate_name, specialization, course_program_name, start_date, completion_date, passing_year, result, class_grade, cgpa, cgpa_scale, percentage, qualification_status, is_highest_qualification, remarks)
SELECT e.employee_id, ql.qualification_level_id, ei.education_institution_id, sm.study_mode_id,
       v.degree_certificate_name, v.specialization, v.course_program_name, v.start_date, v.completion_date,
       v.passing_year, v.outcome, v.class_grade, v.cgpa, v.cgpa_scale, v.percentage, 'COMPLETED', true, v.remarks
FROM (VALUES
  ('DEMO-E001', 'PHD', 'Ph.D. in Computer Science', 'Machine Learning', 'Ph.D. Computer Science',
   '2012-08-01'::date, '2016-06-15'::date, 2016, 'PASS', 'FIRST CLASS', 8.750::numeric, 10.000::numeric, 87.50::numeric,
   'Doctorate awarded by the demo university.'),
  ('DEMO-E002', 'POSTGRADUATE', 'Master of Technology in Computer Science', 'Data Structures', 'M.Tech. Computer Science',
   '2008-07-01'::date, '2010-06-01'::date, 2010, 'PASS', 'FIRST CLASS', 8.200::numeric, 10.000::numeric, 82.00::numeric,
   'Master degree awarded by the demo university.')
) AS v(empnum, levelcode, degree_certificate_name, specialization, course_program_name, start_date, completion_date, passing_year, outcome, class_grade, cgpa, cgpa_scale, percentage, remarks)
JOIN public.employee e ON e.employee_number = v.empnum
JOIN public.qualification_level ql ON ql.level_code = v.levelcode
JOIN public.education_institution ei ON ei.institution_name = 'Demo University, Haveri' AND ei.city = 'Haveri'
JOIN public.study_mode sm ON sm.mode_code = 'REGULAR'
WHERE NOT EXISTS (
  SELECT 1 FROM public.employee_qualification x
  WHERE x.employee_id = e.employee_id AND x.degree_certificate_name = v.degree_certificate_name
);

INSERT INTO public.employee_previous_employment (employee_id, previous_organization_id, department_division, designation, employment_type, nature_of_work, employment_start_date, employment_end_date, experience_days, last_drawn_salary, salary_currency_code, reason_for_leaving, reporting_authority_name, reporting_authority_designation, reporting_authority_phone, reporting_authority_email, remarks)
SELECT e.employee_id, po.previous_organization_id, 'Computer Science', 'Assistant Professor', 'FULL_TIME',
       'Teaching the programming fundamentals and supervising the laboratory.',
       '2010-07-01'::date, '2016-12-31'::date, 2375, 720000.00::numeric, 'INR',
       'Joined the demo institute as a professor.',
       'Ravi Menon', 'Principal', '+91-9000000022', 'principal@demo-poly.edu',
       'Previous experience recorded for the staff profile.'
FROM public.employee e
JOIN public.previous_organization po ON po.organization_name = 'Demo Polytechnic, Haveri' AND po.city = 'Haveri'
WHERE e.employee_number = 'DEMO-E001'
  AND NOT EXISTS (
    SELECT 1 FROM public.employee_previous_employment x
    WHERE x.employee_id = e.employee_id AND x.previous_organization_id = po.previous_organization_id
  );

INSERT INTO public.employee_address (employee_id, address_type, address_line_1, address_line_2, city, state_id, country_id, postal_code, valid_from, is_primary)
SELECT e.employee_id, v.address_type, v.address_line_1, v.address_line_2, v.city,
       (SELECT state_id FROM public.state WHERE state_code = 'KA'
          AND country_id = (SELECT country_id FROM public.country WHERE iso_code = 'IN') LIMIT 1),
       (SELECT country_id FROM public.country WHERE iso_code = 'IN'), v.postal_code, '2020-06-01'::date, true
FROM (VALUES
  ('DEMO-E001', 'CURRENT', '12 Demo Campus Road', 'Academic Block A', 'Haveri', '581115'),
  ('DEMO-E002', 'PERMANENT', '45 Demo Layout', 'Near Demo Lake', 'Haveri', '581115')
) AS v(empnum, address_type, address_line_1, address_line_2, city, postal_code)
JOIN public.employee e ON e.employee_number = v.empnum
WHERE NOT EXISTS (
  SELECT 1 FROM public.employee_address x
  WHERE x.employee_id = e.employee_id AND x.address_type = v.address_type
);

-- ---------------------------------------------------------------------------------------------
-- Module 16 - employee HR: the identity rows
-- ---------------------------------------------------------------------------------------------
-- The identity rows hold the encrypted number, so they can only be written when the project has
-- the vault secret that sims_private.pii_key() reads.  The guard keeps the whole seed working on
-- a project without that secret: the rows are then left out instead of failing the transaction.
INSERT INTO public.employee_aadhaar (employee_id, aadhaar_number_ciphertext, aadhaar_number_fingerprint, aadhaar_number_last4, aadhaar_number_masked, name_as_per_aadhaar, format_validated, verification_status, collection_purpose, remarks)
SELECT e.employee_id, sims_private.pii_encrypt(v.aadhaar), sims_private.pii_fingerprint(v.aadhaar), v.last4,
       v.masked, v.name_as_per_aadhaar, true, 'PENDING',
       'Employee identity record kept for the staff profile.', 'Collected on the onboarding form.'
FROM (VALUES
  ('DEMO-E001', '900000000018', '0018', 'XXXX XXXX 0018', 'Anita Rao'),
  ('DEMO-E002', '900000000025', '0025', 'XXXX XXXX 0025', 'Suresh Kumar')
) AS v(empnum, aadhaar, last4, masked, name_as_per_aadhaar)
JOIN public.employee e ON e.employee_number = v.empnum
WHERE sims_private.pii_key() IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.employee_aadhaar x WHERE x.employee_id = e.employee_id
  );

INSERT INTO public.employee_pan (employee_id, pan_number_ciphertext, pan_number_fingerprint, pan_number_masked, name_as_per_pan, pan_issue_date, pan_issue_details, format_validated, verification_status, remarks)
SELECT e.employee_id, sims_private.pii_encrypt(v.pan), sims_private.pii_fingerprint(v.pan), v.masked,
       v.name_as_per_pan, '2016-07-01'::date, 'Issued by the demo income tax department.', true, 'PENDING',
       'Tax identity record kept for the staff profile.'
FROM (VALUES
  ('DEMO-E001', 'ABCPE1234F', 'XXXXX1234F', 'Anita Rao'),
  ('DEMO-E002', 'ABCPK5678L', 'XXXXX5678L', 'Suresh Kumar')
) AS v(empnum, pan, masked, name_as_per_pan)
JOIN public.employee e ON e.employee_number = v.empnum
WHERE sims_private.pii_key() IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.employee_pan x WHERE x.employee_id = e.employee_id
  );

INSERT INTO public.employee_bank_account (employee_id, account_holder_name, bank_name, branch_name, account_number_ciphertext, account_number_fingerprint, account_number_last4, account_number_confirmed, account_type, ifsc_code, bank_address, city, state_id, country_id, upi_id, is_salary_account, is_primary, account_status, verification_status, effective_from, remarks)
SELECT e.employee_id, v.holder, 'Demo Bank', 'Haveri Main Branch', sims_private.pii_encrypt(v.account_number),
       sims_private.pii_fingerprint(v.account_number), v.last4, true, 'SAVINGS', 'DEMO0123456',
       '1 Demo Bank Road, Haveri', 'Haveri',
       (SELECT state_id FROM public.state WHERE state_code = 'KA'
          AND country_id = (SELECT country_id FROM public.country WHERE iso_code = 'IN') LIMIT 1),
       (SELECT country_id FROM public.country WHERE iso_code = 'IN'), v.upi_id, true, true, 'ACTIVE', 'PENDING',
       '2020-06-01'::date, 'Salary account recorded on the onboarding form.'
FROM (VALUES
  ('DEMO-E001', 'Anita Rao', '502010000001', '0001', 'anita.rao@demobank'),
  ('DEMO-E002', 'Suresh Kumar', '502010000002', '0002', 'suresh.kumar@demobank')
) AS v(empnum, holder, account_number, last4, upi_id)
JOIN public.employee e ON e.employee_number = v.empnum
WHERE sims_private.pii_key() IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.employee_bank_account x WHERE x.employee_id = e.employee_id
  );

-- ---------------------------------------------------------------------------------------------
-- Module 16 - employee HR: the documents and the access rules
-- ---------------------------------------------------------------------------------------------
-- The scope decides which of the five owner columns is filled, and chk_employee_document_scope
-- refuses a row whose scope and owner columns disagree.  A row whose owner row is missing - the
-- identity rows are only written when the vault secret exists - is left out.
INSERT INTO public.employee_document (employee_id, document_scope, employee_qualification_id, employee_previous_employment_id, employee_bank_account_id, employee_pan_id, employee_aadhaar_id, employee_document_category_id, document_type_id, file_object_id, document_title, document_number, issue_date, expiry_date, version_number, verification_status, verified_at, verification_remarks, approval_status, confidentiality_level, is_private, is_active)
SELECT e.employee_id, v.document_scope,
       CASE WHEN v.document_scope = 'QUALIFICATION' THEN q.employee_qualification_id END,
       CASE WHEN v.document_scope = 'PREVIOUS_EMPLOYMENT' THEN pe.employee_previous_employment_id END,
       CASE WHEN v.document_scope = 'BANK_ACCOUNT' THEN b.employee_bank_account_id END,
       CASE WHEN v.document_scope = 'PAN' THEN p.employee_pan_id END,
       CASE WHEN v.document_scope = 'AADHAAR' THEN a.employee_aadhaar_id END,
       c.employee_document_category_id, dt.document_type_id, f.file_object_id, v.document_title, v.document_number,
       v.issue_date, v.expiry_date, 1, v.verification_status, v.verified_at, v.verification_remarks,
       v.approval_status, v.confidentiality_level, true, true
FROM (VALUES
  ('DEMO-E001', 'QUALIFICATION', 'QUALIFICATION', 'PHD_AWARD_CERT', 'DEMO/employee/DEMO-E001/qualification/phd-award-certificate.pdf',
   'Ph.D. Award Certificate', 'Ph.D. in Computer Science', 'DEMO-E001-PHD-2016', '2016-06-15'::date, NULL::date,
   'VERIFIED', '2025-09-01 09:30:00+00'::timestamptz, 'Checked against the awarding body. Verified copy of the doctorate certificate.', 'NOT_REQUIRED', 'CONFIDENTIAL'),
  ('DEMO-E002', 'QUALIFICATION', 'QUALIFICATION', 'DEGREE_CERT', 'DEMO/employee/DEMO-E002/qualification/masters-degree-certificate.pdf',
   'Master Degree Certificate', 'Master of Technology in Computer Science', 'DEMO-E002-MTECH-2010', '2010-06-01'::date, NULL::date,
   'VERIFIED', '2025-09-01 09:35:00+00'::timestamptz, 'Checked against the awarding body. Verified copy of the master degree certificate.', 'NOT_REQUIRED', 'CONFIDENTIAL'),
  ('DEMO-E001', 'PREVIOUS_EMPLOYMENT', 'EXPERIENCE', 'RELIEVING_LETTER', 'DEMO/employee/DEMO-E001/experience/relieving-letter.pdf',
   'Relieving Letter', 'Demo Polytechnic, Haveri', 'DEMO-E001-REL-2016', '2016-12-31'::date, NULL::date,
   'VERIFIED', '2025-09-01 09:40:00+00'::timestamptz, 'Checked against the previous employer. Relieving letter from the previous employer.', 'NOT_REQUIRED', 'CONFIDENTIAL'),
  ('DEMO-E001', 'EMPLOYEE_GENERAL', 'GENERAL', 'APPOINTMENT_LETTER', 'DEMO/employee/DEMO-E001/general/appointment-letter.pdf',
   'Appointment Letter', NULL::text, 'DEMO-E001-APPT-2020', '2020-06-01'::date, NULL::date,
   'VERIFIED', '2025-09-01 09:45:00+00'::timestamptz, 'Checked against the appointment file. Appointment letter issued by the demo institute.', 'NOT_REQUIRED', 'CONFIDENTIAL'),
  ('DEMO-E002', 'EMPLOYEE_GENERAL', 'GENERAL', 'OTHER_EMPLOYEE_DOC', 'DEMO/employee/DEMO-E002/general/staff-identity-card.pdf',
   'Staff Identity Card', NULL::text, 'DEMO-E002-ID-2020', '2020-06-01'::date, NULL::date,
   'VERIFIED', '2025-09-01 09:50:00+00'::timestamptz, 'Checked against the appointment file. Identity card issued by the demo institute.', 'NOT_REQUIRED', 'INTERNAL'),
  ('DEMO-E001', 'PAN', 'PAN', 'PAN_CARD', 'DEMO/employee/DEMO-E001/pan/pan-card.pdf',
   'PAN Card', NULL::text, 'DEMO-E001-PAN', '2016-07-01'::date, NULL::date,
   'PENDING', NULL::timestamptz, 'Copy of the PAN card kept with the tax identity record.', 'PENDING', 'HIGHLY_RESTRICTED'),
  ('DEMO-E001', 'AADHAAR', 'AADHAAR', 'E_AADHAAR', 'DEMO/employee/DEMO-E001/aadhaar/e-aadhaar.pdf',
   'e-Aadhaar', NULL::text, 'DEMO-E001-AADHAAR', '2016-08-01'::date, NULL::date,
   'PENDING', NULL::timestamptz, 'Copy of the e-Aadhaar kept with the identity record.', 'PENDING', 'HIGHLY_RESTRICTED'),
  ('DEMO-E002', 'BANK_ACCOUNT', 'BANK', 'BANK_CONFIRMATION', 'DEMO/employee/DEMO-E002/bank/bank-confirmation.pdf',
   'Bank Account Confirmation', NULL::text, 'DEMO-E002-BANK', '2020-06-01'::date, NULL::date,
   'PENDING', NULL::timestamptz, 'Bank confirmation kept with the salary account record.', 'PENDING', 'HIGHLY_RESTRICTED')
) AS v(empnum, document_scope, catcode, doccode, storage_key, document_title, refkey, document_number, issue_date, expiry_date, verification_status, verified_at, verification_remarks, approval_status, confidentiality_level)
JOIN public.employee e ON e.employee_number = v.empnum
JOIN public.employee_document_category c ON c.category_code = v.catcode
JOIN public.document_type dt ON dt.document_code = v.doccode
JOIN public.file_object f ON f.storage_key = v.storage_key
LEFT JOIN public.employee_qualification q ON v.document_scope = 'QUALIFICATION'
                                        AND q.employee_id = e.employee_id
                                        AND q.degree_certificate_name = v.refkey
LEFT JOIN public.employee_previous_employment pe ON v.document_scope = 'PREVIOUS_EMPLOYMENT'
                                        AND pe.employee_id = e.employee_id
                                        AND pe.previous_organization_id = (SELECT previous_organization_id FROM public.previous_organization
                                                                         WHERE organization_name = v.refkey AND city = 'Haveri')
LEFT JOIN public.employee_bank_account b ON v.document_scope = 'BANK_ACCOUNT' AND b.employee_id = e.employee_id
LEFT JOIN public.employee_pan p ON v.document_scope = 'PAN' AND p.employee_id = e.employee_id
LEFT JOIN public.employee_aadhaar a ON v.document_scope = 'AADHAAR' AND a.employee_id = e.employee_id
WHERE (v.document_scope <> 'QUALIFICATION' OR q.employee_qualification_id IS NOT NULL)
  AND (v.document_scope <> 'PREVIOUS_EMPLOYMENT' OR pe.employee_previous_employment_id IS NOT NULL)
  AND (v.document_scope <> 'BANK_ACCOUNT' OR b.employee_bank_account_id IS NOT NULL)
  AND (v.document_scope <> 'PAN' OR p.employee_pan_id IS NOT NULL)
  AND (v.document_scope <> 'AADHAAR' OR a.employee_aadhaar_id IS NOT NULL)
  AND NOT EXISTS (
    SELECT 1 FROM public.employee_document x
    WHERE x.employee_id = e.employee_id
      AND x.document_scope = v.document_scope
      AND x.document_title = v.document_title
  );

INSERT INTO public.employee_competency (employee_id, course_id, competency_level, valid_from, valid_to)
SELECT e.employee_id, c.course_id, v.competency_level, v.valid_from, v.valid_to
FROM (VALUES
  ('DEMO-E001', 'DEMO-CS101', 'ADVANCED', '2020-06-01'::date, NULL::date),
  ('DEMO-E001', 'DEMO-CS102', 'INTERMEDIATE', '2020-06-01'::date, NULL::date),
  ('DEMO-E002', 'DEMO-CS103', 'EXPERT', '2020-06-01'::date, NULL::date)
) AS v(empnum, coursecode, competency_level, valid_from, valid_to)
JOIN public.employee e ON e.employee_number = v.empnum
JOIN public.course_catalog c ON c.course_code = v.coursecode
WHERE NOT EXISTS (
  SELECT 1 FROM public.employee_competency x
  WHERE x.employee_id = e.employee_id AND x.course_id = c.course_id
);

INSERT INTO public.employee_document_access_rule (employee_document_id, role_id, can_view, can_download, can_update, can_verify, can_approve, valid_from)
SELECT d.employee_document_id, r.role_id, v.can_view, v.can_download, v.can_update, v.can_verify, v.can_approve,
       '2025-09-01 00:00:00+00'::timestamptz
FROM (VALUES
  ('DEMO-E001', 'QUALIFICATION', 'HEAD_DEPARTMENT', true, true, false, false, false),
  ('DEMO-E001', 'EMPLOYEE_GENERAL', 'HR_ADMIN', true, true, false, true, false)
) AS v(empnum, document_scope, rolecode, can_view, can_download, can_update, can_verify, can_approve)
JOIN public.employee e ON e.employee_number = v.empnum
JOIN public.employee_document d ON d.employee_id = e.employee_id AND d.document_scope = v.document_scope
JOIN public.role r ON r.role_code = v.rolecode
WHERE NOT EXISTS (
  SELECT 1 FROM public.employee_document_access_rule x
  WHERE x.employee_document_id = d.employee_document_id AND x.role_id = r.role_id
);

-- ---------------------------------------------------------------------------------------------
-- Module 13 - student service requests
-- ---------------------------------------------------------------------------------------------
-- The table lives in the private schema, so the insert is written as a CTE.  The seed tool reads
-- the target table from the statement and a plain INSERT INTO sims_private... would be read as a
-- table called "sims_private".
WITH demo_service_request AS (
    SELECT v.request_number, s.student_id, t.academic_term_id, v.request_kind, v.planned_date, v.detail,
           v.request_status, v.decision_remarks, v.reference_number, v.completed_at
    FROM (VALUES
      ('DEMO-SVC-001', 'DEMO-S001', 'HALL_TICKET', '2025-11-20'::date,
       'Hall ticket for the internal assessment of the programming laboratory.',
       'SUBMITTED', NULL::text, NULL::text, NULL::timestamptz),
      ('DEMO-SVC-002', 'DEMO-S002', 'HOSTEL_CHECKOUT', '2025-11-25'::date,
       'Hostel checkout at the end of the odd semester.',
       'APPROVED', 'Approved by the warden of the demo hostel.', 'DEMO-HOSTEL-REL-002', NULL::timestamptz),
      ('DEMO-SVC-003', 'DEMO-S003', 'GRADUATION', '2026-05-30'::date,
       'Graduation clearance for the degree certificate.',
       'COMPLETED', 'Graduation clearance issued by the student section office.', 'DEMO-GRAD-CLR-003',
       '2026-05-28 12:00:00+00'::timestamptz)
    ) AS v(request_number, snum, request_kind, planned_date, detail, request_status, decision_remarks, reference_number, completed_at)
    JOIN public.student s ON s.student_number = v.snum
    LEFT JOIN public.academic_term t ON t.term_code = '2025-26-ODD' AND v.request_kind = 'HALL_TICKET'
)
INSERT INTO sims_private.student_service_request (request_number, request_kind, student_id, academic_term_id, planned_date, detail, request_status, decision_remarks, reference_number, completed_at)
SELECT d.request_number, d.request_kind, d.student_id, d.academic_term_id, d.planned_date, d.detail,
       d.request_status, d.decision_remarks, d.reference_number, d.completed_at
FROM demo_service_request d
WHERE NOT EXISTS (
    SELECT 1 FROM sims_private.student_service_request x WHERE x.request_number = d.request_number
);

-- ---------------------------------------------------------------------------------------------
-- Module 13 - the fee that a certificate request carries
-- ---------------------------------------------------------------------------------------------
INSERT INTO public.service_fee_request (request_number, student_id, certificate_request_id, fee_type_id, request_date, service_description, quantity, unit_amount, total_amount, request_status)
SELECT v.request_number, s.student_id, cr.certificate_request_id, ft.fee_type_id, v.request_date,
       v.service_description, v.quantity, v.unit_amount, v.total_amount, v.request_status
FROM (VALUES
  ('DEMO-SFR-001', 'DEMO-S001', 'DEMO-CERT-REQ-001', '2025-09-03'::date,
   'Certificate fee for the bonafide certificate request.', 1, 500.00::numeric, 500.00::numeric, 'SUBMITTED'),
  ('DEMO-SFR-002', 'DEMO-S003', 'DEMO-CERT-REQ-003', '2025-09-07'::date,
   'Certificate fee for the no dues certificate request.', 1, 500.00::numeric, 500.00::numeric, 'COMPLETED')
) AS v(request_number, snum, certnum, request_date, service_description, quantity, unit_amount, total_amount, request_status)
JOIN public.student s ON s.student_number = v.snum
JOIN public.certificate_request cr ON cr.request_number = v.certnum
JOIN public.fee_type ft ON ft.fee_code = 'CERTIFICATE_FEE'
WHERE NOT EXISTS (
  SELECT 1 FROM public.service_fee_request x WHERE x.request_number = v.request_number
);

-- ---------------------------------------------------------------------------------------------
-- Module 40 - student activity: the teams of the co-curricular record
-- ---------------------------------------------------------------------------------------------
-- The two activities of chunk 3 already carry a team, so the members are attached to those two
-- instead of to a third activity.

INSERT INTO public.student_activity_team_member (student_activity_id, student_id, external_member_name, external_member_email, member_role, member_sequence, is_team_lead, remarks)
SELECT a.student_activity_id, s.student_id, v.external_name, v.external_email, v.member_role, v.member_sequence, v.is_team_lead, v.remarks
FROM (VALUES
  ('Smart India Hackathon', 'DEMO-S002', 'DEMO-S001', NULL::text, NULL::text, 'Developer', 2, false,
   'Joined the team for the prototype build.'),
  ('Smart India Hackathon', 'DEMO-S002', NULL::text, 'Kiran Nair', 'kiran.nair@demo.edu', 'Mentor', 3, false,
   'External mentor from the demo industry partner.'),
  ('Inter-college athletics meet', 'DEMO-S001', 'DEMO-S003', NULL::text, NULL::text, 'Participant', 2, false,
   'Attended the athletics meet as a member of the demo athletics team.')
) AS v(activity_title, owner_snum, snum, external_name, external_email, member_role, member_sequence, is_team_lead, remarks)
JOIN public.student owner ON owner.student_number = v.owner_snum
JOIN public.student_activity a ON a.student_id = owner.student_id AND a.activity_title = v.activity_title
LEFT JOIN public.student s ON s.student_number = v.snum
WHERE NOT EXISTS (
  SELECT 1 FROM public.student_activity_team_member x
  WHERE x.student_activity_id = a.student_activity_id
    AND x.member_sequence = v.member_sequence
);

-- ---------------------------------------------------------------------------------------------
-- Module 19 - staff profile: the research vocabulary and the organisations behind it
-- ---------------------------------------------------------------------------------------------
-- The tables below are the ones the Manage panel offers under the STAFF_PROFILE module that
-- had no rows yet.  Every row is found again by its natural key, so the file stays idempotent
-- and the identity sequences stay correct.

INSERT INTO public.organization_type (organization_type_code, organization_type_name, is_active)
SELECT v.type_code, v.type_name, true
FROM (VALUES
  ('PUBLISHER', 'Publisher'),
  ('SPONSOR', 'Sponsoring Organization'),
  ('FUNDING_AGENCY', 'Funding Agency'),
  ('CONFERENCE_ORGANIZER', 'Conference Organizer'),
  ('PROFESSIONAL_BODY', 'Professional Body'),
  ('EDUCATIONAL_INSTITUTE', 'Educational Institute')
) AS v(type_code, type_name)
WHERE NOT EXISTS (
  SELECT 1 FROM public.organization_type x WHERE x.organization_type_code = v.type_code
);

INSERT INTO public.industry_sector (sector_code, sector_name, description, is_active)
SELECT v.sector_code, v.sector_name, v.description, true
FROM (VALUES
  ('IT', 'Information Technology', 'Software, services and internet companies.'),
  ('EDU', 'Education', 'Schools, higher education and training providers.'),
  ('MFG', 'Manufacturing', 'Industrial and manufacturing companies.'),
  ('FIN', 'Financial Services', 'Banks, insurance and financial services.'),
  ('HLTH', 'Healthcare', 'Hospitals, diagnostics and life sciences.')
) AS v(sector_code, sector_name, description)
WHERE NOT EXISTS (
  SELECT 1 FROM public.industry_sector x WHERE x.sector_code = v.sector_code
);

INSERT INTO public.evidence_tag (tag_code, tag_name, is_active)
SELECT v.tag_code, v.tag_name, true
FROM (VALUES
  ('PENDING', 'Pending Verification'),
  ('VERIFIED', 'Verified'),
  ('REJECTED', 'Rejected'),
  ('ARCHIVED', 'Archived'),
  ('PUBLICATION', 'Publication Evidence')
) AS v(tag_code, tag_name)
WHERE NOT EXISTS (
  SELECT 1 FROM public.evidence_tag x WHERE x.tag_code = v.tag_code
);

INSERT INTO public.external_organization (organization_code, organization_name, short_name, website_url, email, phone, address_line_1, city, state_id, country_id, postal_code, is_active)
SELECT v.org_code, v.org_name, v.short_name, v.website, v.email, v.phone, v.address, v.city,
       (SELECT state_id FROM public.state
         WHERE state_code = 'KA'
           AND country_id = (SELECT country_id FROM public.country WHERE iso_code = 'IN') LIMIT 1),
       (SELECT country_id FROM public.country WHERE iso_code = 'IN' LIMIT 1),
       v.postal_code, true
FROM (VALUES
  ('DEMO-ORG-DEMOUNIV', 'Demo University Press', 'Demo Press',
   'https://press.demo-univ.edu', 'press@demo-univ.edu', '+91-9000000101',
   '1 University Road', 'Haveri', '580001'),
  ('DEMO-ORG-DEMOCONF', 'Demo Conference Association', 'Demo Conf',
   'https://conf.demo-univ.edu', 'office@conf.demo-univ.edu', '+91-9000000102',
   '2 Conference Avenue', 'Haveri', '580002'),
  ('DEMO-ORG-DEMOFUND', 'Demo Research Council', 'Demo Council',
   'https://council.demo-univ.edu', 'grants@demo-univ.edu', '+91-9000000103',
   '3 Council Road', 'Haveri', '580003'),
  ('DEMO-ORG-DEMOSPON', 'Demo Systems Private Limited', 'Demo Systems',
   'https://www.demo-systems.example', 'hr@demo-systems.example', '+91-9000000104',
   '4 Industrial Layout', 'Bengaluru', '560001')
) AS v(org_code, org_name, short_name, website, email, phone, address, city, postal_code)
WHERE NOT EXISTS (
  SELECT 1 FROM public.external_organization x WHERE x.organization_code = v.org_code
);

INSERT INTO public.external_organization_type (organization_id, organization_type_id)
SELECT o.organization_id, t.organization_type_id
FROM (VALUES
  ('DEMO-ORG-DEMOUNIV', 'PUBLISHER'),
  ('DEMO-ORG-DEMOCONF', 'CONFERENCE_ORGANIZER'),
  ('DEMO-ORG-DEMOFUND', 'FUNDING_AGENCY'),
  ('DEMO-ORG-DEMOSPON', 'SPONSOR')
) AS v(org_code, type_code)
JOIN public.external_organization o ON o.organization_code = v.org_code
JOIN public.organization_type t ON t.organization_type_code = v.type_code
WHERE NOT EXISTS (
  SELECT 1 FROM public.external_organization_type x
   WHERE x.organization_id = o.organization_id
     AND x.organization_type_id = t.organization_type_id
);

INSERT INTO public.organizer (organization_id, is_active)
SELECT o.organization_id, true
FROM public.external_organization o
WHERE o.organization_code = 'DEMO-ORG-DEMOCONF'
  AND NOT EXISTS (SELECT 1 FROM public.organizer x WHERE x.organization_id = o.organization_id);

INSERT INTO public.publisher (organization_id, is_active)
SELECT o.organization_id, true
FROM public.external_organization o
WHERE o.organization_code = 'DEMO-ORG-DEMOUNIV'
  AND NOT EXISTS (SELECT 1 FROM public.publisher x WHERE x.organization_id = o.organization_id);

INSERT INTO public.funding_agency (organization_id, funding_type_id, agency_category, is_active)
SELECT o.organization_id, ft.funding_type_id, v.category, true
FROM (VALUES
  ('DEMO-ORG-DEMOFUND', 'GOVERNMENT', 'Demo Government Research Council'),
  ('DEMO-ORG-DEMOSPON', 'INDUSTRY', 'Demo Industry Research Cell')
) AS v(org_code, funding_type_code, category)
JOIN public.external_organization o ON o.organization_code = v.org_code
JOIN public.funding_type ft ON ft.funding_type_code = v.funding_type_code
WHERE NOT EXISTS (
  SELECT 1 FROM public.funding_agency x WHERE x.organization_id = o.organization_id
);

INSERT INTO public.external_agency (institution_id, agency_code, agency_name, service_type, contact_person, phone, email, contract_start_date, contract_end_date, address, is_active)
SELECT i.institution_id, v.agency_code, v.agency_name, v.service_type, v.contact_person, v.phone, v.email,
       v.start_date::date, v.end_date::date, v.address, true
FROM (VALUES
  ('DEMO-AGENCY-001', 'Demo Placement Cell', 'Placement and recruitment', 'Kiran Nair',
   '+91-9000000201', 'placement@demo-univ.edu', '2025-06-01', '2026-05-31',
   '1 University Road, Haveri'),
  ('DEMO-AGENCY-002', 'Demo Housekeeping Services', 'Facility management', 'Latha Iyer',
   '+91-9000000202', 'facilities@demo-univ.edu', '2025-07-01', '2026-06-30',
   '2 Campus Road, Haveri')
) AS v(agency_code, agency_name, service_type, contact_person, phone, email, start_date, end_date, address)
JOIN public.institution i ON i.institution_code = 'DEMO-INST'
WHERE NOT EXISTS (
  SELECT 1 FROM public.external_agency x WHERE x.agency_code = v.agency_code
);

INSERT INTO public.awarding_body (awarding_body_type_id, awarding_body_name, university_type, city, state_id, country_id, website_url, is_active)
SELECT t.awarding_body_type_id, v.body_name, v.university_type, v.city,
       (SELECT state_id FROM public.state
         WHERE state_code = 'KA'
           AND country_id = (SELECT country_id FROM public.country WHERE iso_code = 'IN') LIMIT 1),
       (SELECT country_id FROM public.country WHERE iso_code = 'IN' LIMIT 1),
       v.website, true
FROM (VALUES
  ('BOARD', 'Demo State Board of Higher Education', NULL::text, 'Bengaluru', 'https://demo-board.example'),
  ('UNIVERSITY', 'Demo University', 'PRIVATE', 'Haveri', 'https://demo-univ.edu'),
  ('PROFESSIONAL_BODY', 'Demo Institute of Professional Studies', NULL::text, 'Mumbai', 'https://demo-prof.example')
) AS v(type_code, body_name, university_type, city, website)
JOIN public.awarding_body_type t ON t.type_code = v.type_code
WHERE NOT EXISTS (
  SELECT 1 FROM public.awarding_body x WHERE x.awarding_body_name = v.body_name
);

INSERT INTO public.journal (journal_name, journal_type_id, publisher_id, issn, eissn, website_url, country_id, is_peer_reviewed_default, is_open_access_default, is_active)
SELECT v.journal_name, jt.journal_type_id, p.publisher_id, v.issn, v.eissn, v.website,
       (SELECT country_id FROM public.country WHERE iso_code = 'IN' LIMIT 1),
       v.peer_reviewed, v.open_access, true
FROM (VALUES
  ('Demo Journal of Computing', 'INTERNATIONAL', '1234-5678', '1234-5679', 'https://journal.demo-univ.edu', true, false),
  ('Demo Journal of Management Studies', 'NATIONAL', '2345-6789', '2345-6790', 'https://dms.demo-univ.edu', true, true),
  ('Demo Conference Proceedings in Computing', 'NATIONAL', '3456-7890', NULL::text, 'https://proc.demo-univ.edu', false, true)
) AS v(journal_name, journal_type_code, issn, eissn, website, peer_reviewed, open_access)
JOIN public.journal_type jt ON jt.journal_type_code = v.journal_type_code
JOIN public.publisher p
  ON p.organization_id = (SELECT organization_id FROM public.external_organization
                            WHERE organization_code = 'DEMO-ORG-DEMOUNIV')
WHERE NOT EXISTS (
  SELECT 1 FROM public.journal x WHERE x.journal_name = v.journal_name
);

INSERT INTO public.journal_metric (journal_id, metric_type_id, metric_year, metric_value, quartile, source_name, source_url, verified_at)
SELECT j.journal_id, mt.metric_type_id, v.metric_year, v.metric_value, v.quartile,
       v.source_name, v.source_url, '2026-01-15 00:00:00+00'::timestamptz
FROM (VALUES
  ('Demo Journal of Computing', 'IMPACT_FACTOR', 2025, 2.4000::numeric, 'Q1', 'Demo Journal Metrics', 'https://journal.demo-univ.edu/metrics'),
  ('Demo Journal of Computing', 'H_INDEX', 2025, 18.0000::numeric, NULL::text, 'Demo Journal Metrics', 'https://journal.demo-univ.edu/metrics'),
  ('Demo Journal of Management Studies', 'CITESCORE', 2025, 3.1000::numeric, 'Q2', 'Demo Journal Metrics', 'https://dms.demo-univ.edu/metrics')
) AS v(journal_name, metric_type_code, metric_year, metric_value, quartile, source_name, source_url)
JOIN public.journal j ON j.journal_name = v.journal_name
JOIN public.metric_type mt ON mt.metric_code = v.metric_type_code
WHERE NOT EXISTS (
  SELECT 1 FROM public.journal_metric x
   WHERE x.journal_id = j.journal_id
     AND x.metric_type_id = mt.metric_type_id
     AND x.metric_year = v.metric_year
);

INSERT INTO public.conference_event (conference_title, conference_edition, organizer_id, sponsoring_organization_id, proceedings_publisher_id, participation_level_id, event_mode_id, venue_name, city, state_id, country_id, start_date, end_date, conference_website, brochure_url, is_active)
SELECT v.title, v.edition, o.organizer_id, s.organization_id, p.publisher_id,
       pl.participation_level_id, em.event_mode_id, v.venue, v.city,
       (SELECT state_id FROM public.state
         WHERE state_code = 'KA'
           AND country_id = (SELECT country_id FROM public.country WHERE iso_code = 'IN') LIMIT 1),
       (SELECT country_id FROM public.country WHERE iso_code = 'IN' LIMIT 1),
       v.start_date::date, v.end_date::date, v.website, v.brochure, true
FROM (VALUES
  ('Demo International Conference on Computing', '2025 Edition', 'DEMO-ORG-DEMOSPON', 'INTERNATIONAL', 'HYBRID',
   'Demo Convention Centre', 'Bengaluru', '2025-08-14', '2025-08-16',
   'https://conf.demo-univ.edu/2025', 'https://conf.demo-univ.edu/2025/brochure.pdf'),
  ('Demo National Conference on Management', 'First Edition', NULL::text, 'NATIONAL', 'OFFLINE',
   'Demo Business School Auditorium', 'Haveri', '2026-02-05', '2026-02-06',
   'https://conf.demo-univ.edu/mgmt2026', NULL::text)
) AS v(title, edition, sponsor_code, level_code, mode_code, venue, city, start_date, end_date, website, brochure)
JOIN public.organizer o
  ON o.organization_id = (SELECT organization_id FROM public.external_organization
                            WHERE organization_code = 'DEMO-ORG-DEMOCONF')
JOIN public.publisher p
  ON p.organization_id = (SELECT organization_id FROM public.external_organization
                            WHERE organization_code = 'DEMO-ORG-DEMOUNIV')
JOIN public.participation_level pl ON pl.level_code = v.level_code
JOIN public.event_mode em ON em.mode_code = v.mode_code
LEFT JOIN public.external_organization s ON s.organization_code = v.sponsor_code
WHERE NOT EXISTS (
  SELECT 1 FROM public.conference_event x
   WHERE x.conference_title = v.title
     AND x.conference_edition = v.edition
);

-- ---------------------------------------------------------------------------------------------
-- Module 4 - curriculum: the prerequisites of the courses of the programme
-- ---------------------------------------------------------------------------------------------
INSERT INTO public.course_prerequisite (course_id, prerequisite_course_id, minimum_grade)
SELECT c.course_id, p.course_id, v.minimum_grade
FROM (VALUES
  ('DEMO-CS102', 'DEMO-CS101', 'B'),
  ('DEMO-CS103', 'DEMO-CS102', 'B')
) AS v(course_code, prerequisite_code, minimum_grade)
JOIN public.course_catalog c ON c.course_code = v.course_code
JOIN public.course_catalog p ON p.course_code = v.prerequisite_code
WHERE NOT EXISTS (
  SELECT 1 FROM public.course_prerequisite x
   WHERE x.course_id = c.course_id
     AND x.prerequisite_course_id = p.course_id
);

-- ---------------------------------------------------------------------------------------------
-- Module 5 - students: the record around the student
-- ---------------------------------------------------------------------------------------------
INSERT INTO public.enrolment_status_history (enrolment_id, old_status, new_status, effective_date, reason)
SELECT e.enrolment_id, v.old_status, v.new_status, v.effective_date::date, v.reason
FROM (VALUES
  ('DEMO-S001', NULL::text, 'ACTIVE', '2025-08-01', 'Enrolment confirmed after the admission was approved.'),
  ('DEMO-S002', 'PROVISIONAL', 'ACTIVE', '2025-08-05', 'Provisional admission confirmed after the documents were verified.'),
  ('DEMO-S003', 'PROVISIONAL', 'ACTIVE', '2025-08-06', 'Provisional admission confirmed after the documents were verified.')
) AS v(snum, old_status, new_status, effective_date, reason)
JOIN public.student s ON s.student_number = v.snum
JOIN public.student_programme_enrolment e ON e.student_id = s.student_id
WHERE NOT EXISTS (
  SELECT 1 FROM public.enrolment_status_history x
   WHERE x.enrolment_id = e.enrolment_id
     AND x.new_status = v.new_status
     AND x.effective_date = v.effective_date::date
);

INSERT INTO public.student_entrance_exam (student_id, exam_name, registration_number, rank_number, score, exam_year, allotment_date, registration_fee)
SELECT s.student_id, v.exam_name, v.reg_no, v.rank_number, v.score, v.exam_year,
       v.allotment_date::date, v.fee
FROM (VALUES
  ('DEMO-S001', 'Demo State Entrance Test', 'DEMO-ENT-001', 1204, 78.50::numeric, 2025, '2025-06-12', 1500.00::numeric),
  ('DEMO-S002', 'Demo State Entrance Test', 'DEMO-ENT-002', 2310, 64.25::numeric, 2025, '2025-06-12', 1500.00::numeric),
  ('DEMO-S003', 'Demo University Entrance Test', 'DEMO-ENT-003', 890, 82.75::numeric, 2025, '2025-06-20', 2000.00::numeric)
) AS v(snum, exam_name, reg_no, rank_number, score, exam_year, allotment_date, fee)
JOIN public.student s ON s.student_number = v.snum
WHERE NOT EXISTS (
  SELECT 1 FROM public.student_entrance_exam x WHERE x.registration_number = v.reg_no
);

INSERT INTO public.student_exit (enrolment_id, exit_type, exit_date, destination_institution, old_registration_number, remarks)
SELECT e.enrolment_id, v.exit_type, v.exit_date::date, v.destination, v.old_reg, v.remarks
FROM (VALUES
  ('DEMO-S002', 'TRANSFER', '2026-04-30', 'Demo College of Commerce', 'DEMO-OLD-002',
   'Transfer applied for and recorded; the exit stays open until the registrar closes the enrolment.'),
  ('DEMO-S003', 'TRANSFER', '2026-04-30', 'Demo College of Commerce', 'DEMO-OLD-003',
   'Transfer applied for and recorded; the exit stays open until the registrar closes the enrolment.')
) AS v(snum, exit_type, exit_date, destination, old_reg, remarks)
JOIN public.student s ON s.student_number = v.snum
JOIN public.student_programme_enrolment e ON e.student_id = s.student_id
WHERE NOT EXISTS (
  SELECT 1 FROM public.student_exit x
   WHERE x.enrolment_id = e.enrolment_id
     AND x.exit_date = v.exit_date::date
);

INSERT INTO public.student_parent_guardian (student_id, relationship_type, full_name, occupation, annual_income, email, phone, address_line_1, city, state_id, country_id, postal_code, is_primary_contact)
SELECT s.student_id, v.relationship_type, v.full_name, v.occupation, v.income, v.email, v.phone,
       v.address, v.city,
       (SELECT state_id FROM public.state
         WHERE state_code = 'KA'
           AND country_id = (SELECT country_id FROM public.country WHERE iso_code = 'IN') LIMIT 1),
       (SELECT country_id FROM public.country WHERE iso_code = 'IN' LIMIT 1),
       v.postal_code, v.is_primary
FROM (VALUES
  ('DEMO-S001', 'FATHER', 'Ramesh Rao', 'School Teacher', 480000.00::numeric, 'ramesh.rao@example.com', '+91-9000000301', '12 Nehru Street', 'Haveri', '580001', true),
  ('DEMO-S001', 'MOTHER', 'Sunita Rao', 'Homemaker', 0.00::numeric, 'sunita.rao@example.com', '+91-9000000302', '12 Nehru Street', 'Haveri', '580001', false),
  ('DEMO-S002', 'FATHER', 'Mahesh Shah', 'Shop Owner', 620000.00::numeric, 'mahesh.shah@example.com', '+91-9000000303', '45 Station Road', 'Haveri', '580002', true),
  ('DEMO-S003', 'MOTHER', 'Lakshmi Iyer', 'Nurse', 540000.00::numeric, 'lakshmi.iyer@example.com', '+91-9000000304', '8 Temple Lane', 'Haveri', '580003', true)
) AS v(snum, relationship_type, full_name, occupation, income, email, phone, address, city, postal_code, is_primary)
JOIN public.student s ON s.student_number = v.snum
WHERE NOT EXISTS (
  SELECT 1 FROM public.student_parent_guardian x
   WHERE x.student_id = s.student_id
     AND x.relationship_type = v.relationship_type
);

INSERT INTO public.student_previous_education (student_id, qualification_level, examination_name, institution_name, board_university, registration_number, month_of_passing, year_of_passing, result_class, marks_obtained, maximum_marks, percentage)
SELECT s.student_id, v.level, v.examination, v.institution, v.board, v.reg_no, v.month, v.year,
       v.result_class, v.marks, v.max_marks, v.percentage
FROM (VALUES
  ('DEMO-S001', 'PUC_II', 'Demo State Board Higher Secondary', 'Demo Senior Secondary School', 'Demo State Board', 'DEMO-SSLC-001', 5, 2025, 'FIRST', 482.00::numeric, 600.00::numeric, 80.33::numeric),
  ('DEMO-S002', 'PUC_II', 'Demo State Board Higher Secondary', 'Demo Public School', 'Demo State Board', 'DEMO-SSLC-002', 5, 2025, 'FIRST', 455.00::numeric, 600.00::numeric, 75.83::numeric),
  ('DEMO-S003', 'PUC_II', 'Demo State Board Higher Secondary', 'Demo Model School', 'Demo State Board', 'DEMO-SSLC-003', 5, 2025, 'SECOND', 412.00::numeric, 600.00::numeric, 68.67::numeric)
) AS v(snum, level, examination, institution, board, reg_no, month, year, result_class, marks, max_marks, percentage)
JOIN public.student s ON s.student_number = v.snum
WHERE NOT EXISTS (
  SELECT 1 FROM public.student_previous_education x WHERE x.registration_number = v.reg_no
);

INSERT INTO public.student_residence (student_id, residence_type, hostel_name, room_number, start_date, end_date, is_current)
SELECT s.student_id, v.residence_type, v.hostel, v.room, v.start_date::date, v.end_date::date, v.is_current
FROM (VALUES
  ('DEMO-S001', 'HOSTEL', 'Demo Boys Hostel', 'A-101', '2025-08-01', NULL::text, true),
  ('DEMO-S002', 'HOSTEL', 'Demo Boys Hostel', 'A-102', '2025-08-01', NULL::text, true),
  ('DEMO-S003', 'DAY_SCHOLAR', NULL::text, NULL::text, '2025-08-01', NULL::text, true)
) AS v(snum, residence_type, hostel, room, start_date, end_date, is_current)
JOIN public.student s ON s.student_number = v.snum
WHERE NOT EXISTS (
  SELECT 1 FROM public.student_residence x
   WHERE x.student_id = s.student_id
     AND x.start_date = v.start_date::date
);

-- ---------------------------------------------------------------------------------------------
-- Module 19 and 40 - the evidence a record has to carry
-- ---------------------------------------------------------------------------------------------
INSERT INTO public.activity_evidence_requirement (activity_type_id, evidence_type_id, document_type_id, is_mandatory, minimum_files, maximum_files, valid_from, valid_to, is_active)
SELECT at.activity_type_id, et.evidence_type_id, dt.document_type_id, v.mandatory, v.min_files,
       v.max_files, v.valid_from::date, v.valid_to::date, true
FROM (VALUES
  ('JOURNAL_PUBLICATION', 'PUBLISHED_PAPER', 'OTHER_EMPLOYEE_DOC', true, 1, 3, '2025-06-01', NULL::text),
  ('CONFERENCE_PUBLICATION', 'CONFERENCE_PAPER', 'OTHER_EMPLOYEE_DOC', true, 1, 3, '2025-06-01', NULL::text),
  ('FUNDED_RESEARCH_PROJECT', 'FUNDING_ORDER', 'OTHER_EMPLOYEE_DOC', true, 1, 5, '2025-06-01', NULL::text),
  ('FDP', 'COMPLETION_CERTIFICATE', 'OTHER_EMPLOYEE_DOC', true, 1, 2, '2025-06-01', NULL::text),
  ('AWARD_RECOGNITION', 'AWARD_CERTIFICATE', 'OTHER_EMPLOYEE_DOC', true, 1, 2, '2025-06-01', NULL::text)
) AS v(activity_type_code, evidence_type_code, document_type_code, mandatory, min_files, max_files, valid_from, valid_to)
JOIN public.activity_type at ON at.activity_type_code = v.activity_type_code
JOIN public.evidence_type et ON et.evidence_type_code = v.evidence_type_code
JOIN public.document_type dt ON dt.document_code = v.document_type_code
WHERE NOT EXISTS (
  SELECT 1 FROM public.activity_evidence_requirement x
   WHERE x.activity_type_id = at.activity_type_id
     AND x.evidence_type_id = et.evidence_type_id
);

INSERT INTO public.student_activity_evidence_requirement (student_activity_type_id, evidence_type_id, document_type_id, is_mandatory, minimum_files, maximum_files, valid_from, valid_to, is_active)
SELECT sat.student_activity_type_id, et.evidence_type_id, NULL::bigint, v.mandatory, v.min_files,
       v.max_files, v.valid_from::date, v.valid_to::date, true
FROM (VALUES
  ('CONFERENCE_PARTICIPATION', 'PARTICIPATION_CERTIFICATE', true, 1, 2, '2025-06-01', NULL::text),
  ('CONFERENCE_PRESENTATION', 'PRESENTATION_CERTIFICATE', true, 1, 2, '2025-06-01', NULL::text),
  ('HACKATHON', 'STUDENT_PARTICIPATION_CERTIFICATE', true, 1, 3, '2025-06-01', NULL::text),
  ('SPORTS', 'STUDENT_MEDAL_PROOF', false, 0, 2, '2025-06-01', NULL::text),
  ('CERTIFICATION', 'PUBLICATION_CERTIFICATE', true, 1, 2, '2025-06-01', NULL::text)
) AS v(activity_type_code, evidence_type_code, mandatory, min_files, max_files, valid_from, valid_to)
JOIN public.student_activity_type sat ON sat.type_code = v.activity_type_code
JOIN public.evidence_type et ON et.evidence_type_code = v.evidence_type_code
WHERE NOT EXISTS (
  SELECT 1 FROM public.student_activity_evidence_requirement x
   WHERE x.student_activity_type_id = sat.student_activity_type_id
     AND x.evidence_type_id = et.evidence_type_id
);

-- ---------------------------------------------------------------------------------------------
-- Module 19 - staff profile: the research record of the second employee
-- ---------------------------------------------------------------------------------------------
-- The three records below hang off new staff activities of DEMO-E002, so the journal publication
-- of DEMO-E001 stays the only one of that employee.

INSERT INTO public.staff_activity (employee_id, activity_type_id, academic_year_id, institution_id, campus_id, department_id, participation_level_id, primary_role_type_id, activity_title, start_date, end_date, description, outcomes, verification_status_id, approval_status_id, remarks)
SELECT e.employee_id, at.activity_type_id,
       (SELECT academic_year_id FROM public.academic_year WHERE year_code = '2025-26'),
       (SELECT institution_id FROM public.institution WHERE institution_code = 'DEMO-INST'),
       (SELECT campus_id FROM public.campus WHERE campus_code = 'DEMO-CAMPUS'),
       (SELECT department_id FROM public.department WHERE department_code = 'DEMO-MGT'),
       (SELECT participation_level_id FROM public.participation_level WHERE level_code = 'NATIONAL'),
       (SELECT role_type_id FROM public.role_type WHERE role_code = 'PARTICIPANT'),
       v.title, v.start_date::date, v.end_date::date, v.description, v.outcomes,
       (SELECT verification_status_id FROM public.verification_status WHERE status_code = 'PENDING'),
       (SELECT approval_status_id FROM public.approval_status WHERE status_code = 'DRAFT'),
       'Awaiting verification and approval.'
FROM public.employee e
JOIN (VALUES
  ('CONFERENCE_PUBLICATION', 'Adaptive feedback in the programming laboratory',
   '2025-08-14', '2025-08-16',
   'Conference paper presented at the demo international conference on computing.',
   'Paper presented and the proceedings published.'),
  ('FUNDED_RESEARCH_PROJECT', 'Adaptive learning in the programming laboratory',
   '2025-07-01', '2026-06-30',
   'Funded research project on adaptive learning techniques for the first year programming laboratory.',
   'Two papers and one prototype delivered.'),
  ('ACADEMIC_PROFESSIONAL_CONTRIBUTION', 'Ph.D. supervision of the demo research scholar',
   '2025-09-01', NULL::text,
   'Supervision of the research scholar registered with the demo university.',
   'The thesis is under review.')
) AS v(activity_type_code, title, start_date, end_date, description, outcomes) ON true
JOIN public.activity_type at ON at.activity_type_code = v.activity_type_code
WHERE e.employee_number = 'DEMO-E002'
  AND NOT EXISTS (
    SELECT 1 FROM public.staff_activity x
     WHERE x.employee_id = e.employee_id
       AND x.activity_title = v.title
  );

INSERT INTO public.journal_publication (staff_activity_id, publication_type_id, journal_id, paper_title, volume_number, issue_number, page_from, page_to, publication_date, publication_year, doi, url, peer_reviewed, open_access, primary_author_position, primary_staff_corresponding_author, affiliation_text, abstract_text, keywords)
SELECT sa.staff_activity_id, pt.publication_type_id, j.journal_id, v.paper_title, v.volume, v.issue,
       v.page_from, v.page_to, v.publication_date::date, v.publication_year, v.doi, v.url,
       v.peer_reviewed, v.open_access, v.author_position, v.corresponding, v.affiliation,
       v.abstract, v.keywords
FROM (VALUES
  ('Attendance analytics of the first year programming laboratory', 'Demo Journal of Computing',
   'Attendance analytics of the first year programming laboratory',
   '12', '2', '101', '118', '2025-09-30', 2025, '10.5555/demo.2025.001',
   'https://journal.demo-univ.edu/article/1', true, false, 1, true,
   'Demo Institute of Technology, Haveri',
   'A study of the attendance analytics of the first year programming laboratory.',
   'attendance analytics, programming laboratory')
) AS v(activity_title, journal_name, paper_title, volume, issue, page_from, page_to, publication_date, publication_year,
       doi, url, peer_reviewed, open_access, author_position, corresponding, affiliation, abstract, keywords)
JOIN public.staff_activity sa ON sa.activity_title = v.activity_title
JOIN public.publication_type pt ON pt.publication_type_code = 'JOURNAL_ARTICLE'
JOIN public.journal j ON j.journal_name = v.journal_name
WHERE NOT EXISTS (
  SELECT 1 FROM public.journal_publication x WHERE x.staff_activity_id = sa.staff_activity_id
);

INSERT INTO public.journal_publication_indexing (staff_activity_id, indexing_agency_id, indexed_year, indexing_status, source_url, remarks)
SELECT jp.staff_activity_id, ia.indexing_agency_id, v.indexed_year, v.status, v.source_url, v.remarks
FROM (VALUES
  ('Attendance analytics of the first year programming laboratory', 'SCOPUS', 2025, 'VERIFIED',
   'https://www.scopus.example/record/1', 'Indexed in the demo Scopus record.'),
  ('Attendance analytics of the first year programming laboratory', 'UGC_CARE', 2025, 'CLAIMED',
   'https://ugccare.example/claim/1', 'The UGC-CARE claim is still under review.')
) AS v(activity_title, agency_code, indexed_year, status, source_url, remarks)
JOIN public.staff_activity sa ON sa.activity_title = v.activity_title
JOIN public.journal_publication jp ON jp.staff_activity_id = sa.staff_activity_id
JOIN public.indexing_agency ia ON ia.agency_code = v.agency_code
WHERE NOT EXISTS (
  SELECT 1 FROM public.journal_publication_indexing x
   WHERE x.staff_activity_id = jp.staff_activity_id
     AND x.indexing_agency_id = ia.indexing_agency_id
);

INSERT INTO public.conference_activity (staff_activity_id, conference_event_id, conference_contribution_type_id, publication_type_id, paper_title, abstract_text, proceedings_title, proceedings_volume, page_from, page_to, doi, proceedings_url, presentation_title)
SELECT sa.staff_activity_id, ce.conference_event_id, cct.conference_contribution_type_id,
       pt.publication_type_id, v.paper_title, v.abstract, v.proceedings_title, v.proceedings_volume,
       v.page_from, v.page_to, v.doi, v.proceedings_url, v.presentation_title
FROM (VALUES
  ('Adaptive feedback in the programming laboratory', 'Demo International Conference on Computing',
   'PAPER_PRESENTATION', 'CONFERENCE_PAPER',
   'Adaptive feedback in the programming laboratory',
   'A study of adaptive feedback in the first year programming laboratory.',
   'Proceedings of the Demo International Conference on Computing', '1', '45', '58',
   '10.5555/demo.conf.2025.045', 'https://conf.demo-univ.edu/2025/proceedings',
   'Adaptive feedback in the programming laboratory')
) AS v(activity_title, conference_title, contribution_type_code, publication_type_code, paper_title,
       abstract, proceedings_title, proceedings_volume, page_from, page_to, doi, proceedings_url, presentation_title)
JOIN public.staff_activity sa ON sa.activity_title = v.activity_title
JOIN public.conference_event ce ON ce.conference_title = v.conference_title
JOIN public.conference_contribution_type cct ON cct.type_code = v.contribution_type_code
JOIN public.publication_type pt ON pt.publication_type_code = v.publication_type_code
WHERE NOT EXISTS (
  SELECT 1 FROM public.conference_activity x WHERE x.staff_activity_id = sa.staff_activity_id
);

INSERT INTO public.conference_activity_indexing (staff_activity_id, indexing_agency_id, indexing_status, source_url, remarks)
SELECT ca.staff_activity_id, ia.indexing_agency_id, v.status, v.source_url, v.remarks
FROM (VALUES
  ('Adaptive feedback in the programming laboratory', 'SCOPUS', 'VERIFIED',
   'https://www.scopus.example/record/2', 'Indexed in the demo Scopus record.'),
  ('Adaptive feedback in the programming laboratory', 'DBLP', 'CLAIMED',
   'https://dblp.example/claim/2', 'The DBLP claim is still under review.')
) AS v(activity_title, agency_code, status, source_url, remarks)
JOIN public.staff_activity sa ON sa.activity_title = v.activity_title
JOIN public.conference_activity ca ON ca.staff_activity_id = sa.staff_activity_id
JOIN public.indexing_agency ia ON ia.agency_code = v.agency_code
WHERE NOT EXISTS (
  SELECT 1 FROM public.conference_activity_indexing x
   WHERE x.staff_activity_id = ca.staff_activity_id
     AND x.indexing_agency_id = ia.indexing_agency_id
);

INSERT INTO public.funded_research_project (staff_activity_id, project_title, principal_investigator_employee_id, department_id, funding_agency_id, funding_type_id, scheme_program_name, requested_amount, sanctioned_amount, amount_received, amount_utilized, currency_code, sanction_date, sanction_order_number, project_start_date, project_end_date, duration_months, research_status_id, project_objectives, research_domain, project_outcomes, publications_generated, utilization_summary)
SELECT sa.staff_activity_id, v.project_title, e.employee_id, d.department_id, fa.funding_agency_id,
       ft.funding_type_id, v.scheme, v.requested, v.sanctioned, v.received, v.utilized, 'INR',
       v.sanction_date::date, v.order_no, v.start_date::date, v.end_date::date, v.duration,
       rs.research_status_id, v.objectives, v.domain, v.outcomes, v.publications, v.utilization
FROM (VALUES
  ('Adaptive learning in the programming laboratory', 'Adaptive learning in the programming laboratory',
   'DEMO-E002', 'DEMO-MGT', 'DEMO-ORG-DEMOFUND', 'GOVERNMENT',
   'Demo Research Council - Adaptive Learning Scheme',
   500000.00::numeric, 450000.00::numeric, 450000.00::numeric, 312500.00::numeric,
   '2025-07-01', 'DEMO-SAN-2025-001', '2025-07-01', '2026-06-30', 12, 'ONGOING',
   'To build an adaptive feedback model for the first year programming laboratory.',
   'Learning analytics', 'One journal paper and one conference paper.',
   'Two papers published.', 'The funds received are reported against the utilisation certificate.')
) AS v(activity_title, project_title, empnum, deptcode, org_code, funding_type_code, scheme,
       requested, sanctioned, received, utilized, sanction_date, order_no, start_date, end_date,
       duration, status_code, objectives, domain, outcomes, publications, utilization)
JOIN public.staff_activity sa ON sa.activity_title = v.activity_title
JOIN public.employee e ON e.employee_number = v.empnum
JOIN public.department d ON d.department_code = v.deptcode
JOIN public.funding_agency fa
  ON fa.organization_id = (SELECT organization_id FROM public.external_organization
                            WHERE organization_code = v.org_code)
JOIN public.funding_type ft ON ft.funding_type_code = v.funding_type_code
JOIN public.research_status rs ON rs.status_code = v.status_code
WHERE NOT EXISTS (
  SELECT 1 FROM public.funded_research_project x WHERE x.staff_activity_id = sa.staff_activity_id
);

INSERT INTO public.research_project_financial_utilization (staff_activity_id, financial_year, reporting_period_from, reporting_period_to, opening_balance, amount_received, expenditure_amount, closing_balance, utilization_certificate_number, statement_of_expenditure_number, remarks)
SELECT frp.staff_activity_id, v.financial_year, v.period_from::date, v.period_to::date, v.opening,
       v.received, v.expenditure, v.closing, v.utilization_certificate, v.statement_number, v.remarks
FROM (VALUES
  ('Adaptive learning in the programming laboratory', '2025-26', '2025-07-01', '2026-03-31',
   0.00::numeric, 450000.00::numeric, 312500.00::numeric, 137500.00::numeric,
   'DEMO-UC-2025-001', 'DEMO-SOE-2025-001',
   'The utilisation certificate covers the first three quarters of the project.')
) AS v(activity_title, financial_year, period_from, period_to, opening, received, expenditure,
       closing, utilization_certificate, statement_number, remarks)
JOIN public.staff_activity sa ON sa.activity_title = v.activity_title
JOIN public.funded_research_project frp ON frp.staff_activity_id = sa.staff_activity_id
WHERE NOT EXISTS (
  SELECT 1 FROM public.research_project_financial_utilization x
   WHERE x.staff_activity_id = frp.staff_activity_id
     AND x.financial_year = v.financial_year
);

INSERT INTO public.staff_professional_contribution (staff_activity_id, professional_contribution_type_id, organization_id, programme_id, course_id, student_id, title_topic, appointment_reference_number, contribution_date, start_date, end_date, number_of_reviews, number_of_candidates, contribution_details, outcome_details)
SELECT sa.staff_activity_id, pct.professional_contribution_type_id, eo.organization_id, p.programme_id,
       c.course_id, s.student_id, v.title_topic, v.reference_number, v.contribution_date::date,
       v.start_date::date, v.end_date::date, v.reviews, v.candidates, v.details, v.outcome
FROM (VALUES
  ('Ph.D. supervision of the demo research scholar', 'PHD_SUPERVISION', 'DEMO-ORG-DEMOUNIV',
   'DEMO-BSC-CS', 'DEMO-CS101', 'DEMO-S002',
   'Ph.D. supervision of the demo research scholar', 'DEMO-APPT-2025-011', '2025-09-01',
   '2025-09-01', NULL::text, 0, 1,
   'Supervision of the research scholar registered with the demo university.',
   'The thesis is under review.')
) AS v(activity_title, contribution_type_code, org_code, programme_code, course_code, snum,
       title_topic, reference_number, contribution_date, start_date, end_date, reviews, candidates, details, outcome)
JOIN public.staff_activity sa ON sa.activity_title = v.activity_title
JOIN public.professional_contribution_type pct ON pct.contribution_code = v.contribution_type_code
JOIN public.external_organization eo ON eo.organization_code = v.org_code
JOIN public.programme p ON p.programme_code = v.programme_code
JOIN public.course_catalog c ON c.course_code = v.course_code
JOIN public.student s ON s.student_number = v.snum
WHERE NOT EXISTS (
  SELECT 1 FROM public.staff_professional_contribution x WHERE x.staff_activity_id = sa.staff_activity_id
);

INSERT INTO public.research_supervision (staff_activity_id, supervision_level, scholar_name, student_id, registration_number, research_title, registration_date, completion_date, supervision_role, status, awarding_organization_id)
SELECT spc.staff_activity_id, v.level, v.scholar_name, s.student_id, v.registration_number,
       v.research_title, v.registration_date::date, v.completion_date::date, v.role, v.status,
       eo.organization_id
FROM (VALUES
  ('Ph.D. supervision of the demo research scholar', 'PHD', 'Vikram Shah', 'DEMO-S002',
   'DEMO-PHD-2025-002', 'Adaptive feedback for the programming laboratory', '2025-09-01',
   NULL::text, 'SUPERVISOR', 'ONGOING', 'DEMO-ORG-DEMOUNIV')
) AS v(activity_title, level, scholar_name, snum, registration_number, research_title,
       registration_date, completion_date, role, status, org_code)
JOIN public.staff_activity sa ON sa.activity_title = v.activity_title
JOIN public.staff_professional_contribution spc ON spc.staff_activity_id = sa.staff_activity_id
JOIN public.student s ON s.student_number = v.snum
JOIN public.external_organization eo ON eo.organization_code = v.org_code
WHERE NOT EXISTS (
  SELECT 1 FROM public.research_supervision x WHERE x.staff_activity_id = spc.staff_activity_id
);

-- ---------------------------------------------------------------------------------------------
-- Module 19 - staff profile: the evidence document of the journal publication
-- ---------------------------------------------------------------------------------------------
-- The evidence document names the user who uploaded it, and a SIMS user needs an account.  The
-- seed creates no accounts, so the insert only happens where the project already holds one.

INSERT INTO public.evidence_document (staff_activity_id, document_type_id, evidence_type_id, confidentiality_level_id, document_title, description, academic_year_id, document_issue_date, issuing_authority, issuing_organization_id, certificate_document_number, expiry_date, verification_status_id, approval_status_id, current_version_number, is_active, created_by_user_id)
SELECT sa.staff_activity_id,
       (SELECT document_type_id FROM public.document_type WHERE document_code = 'OTHER_EMPLOYEE_DOC'),
       (SELECT evidence_type_id FROM public.evidence_type WHERE evidence_type_code = 'PUBLISHED_PAPER'),
       (SELECT confidentiality_level_id FROM public.confidentiality_level WHERE level_code = 'INTERNAL'),
       'Published paper of the attendance analytics study',
       'The published paper that backs the journal publication record.',
       (SELECT academic_year_id FROM public.academic_year WHERE year_code = '2025-26'),
       '2025-09-30'::date,
       'Demo Journal of Computing',
       (SELECT organization_id FROM public.external_organization WHERE organization_code = 'DEMO-ORG-DEMOUNIV'),
       'DEMO-EV-001',
       NULL::date,
       (SELECT verification_status_id FROM public.verification_status WHERE status_code = 'PENDING'),
       (SELECT approval_status_id FROM public.approval_status WHERE status_code = 'DRAFT'),
       1, true,
       (SELECT min(user_id) FROM public.user_account)
FROM public.staff_activity sa
WHERE sa.activity_title = 'Attendance analytics of the first year programming laboratory'
  AND EXISTS (SELECT 1 FROM public.user_account)
  AND NOT EXISTS (
    SELECT 1 FROM public.evidence_document x
     WHERE x.staff_activity_id = sa.staff_activity_id
       AND x.document_title = 'Published paper of the attendance analytics study'
  );

INSERT INTO public.evidence_document_tag (evidence_document_id, evidence_tag_id)
SELECT ed.evidence_document_id, et.evidence_tag_id
FROM (VALUES
  ('Published paper of the attendance analytics study', 'PENDING'),
  ('Published paper of the attendance analytics study', 'PUBLICATION')
) AS v(document_title, tag_code)
JOIN public.evidence_document ed ON ed.document_title = v.document_title
JOIN public.evidence_tag et ON et.tag_code = v.tag_code
WHERE NOT EXISTS (
  SELECT 1 FROM public.evidence_document_tag x
   WHERE x.evidence_document_id = ed.evidence_document_id
     AND x.evidence_tag_id = et.evidence_tag_id
);

--------------------------------------------------------------------------------
-- Child / audit / link tables that are not part of the admin editing catalogue.
-- These back the staff-profile, feedback, finance, evidence and IAM screens.
--------------------------------------------------------------------------------
-- ---------------------------------------------------------------------------------------------
-- Module 19 - staff profile: the files, the contributors and the evidence trail
-- ---------------------------------------------------------------------------------------------
-- The evidence of a record only shows up on the screen when the file behind it is registered
-- in `file_object` and the version row points at it.  The three files below are the ones the
-- demo records refer to.

INSERT INTO public.file_object (storage_provider, storage_key, original_file_name, mime_type, file_size_bytes, checksum_sha256, uploaded_at, stored_file_name, file_extension, confidentiality_level, is_encrypted, uploaded_by_user_id, virus_scan_status, virus_scanned_at)
SELECT 'supabase-storage', v.storage_key, v.file_name, 'application/pdf', v.size, v.checksum,
       v.uploaded_at::timestamptz, v.file_name, 'pdf', v.level, false, 1, 'CLEAN', v.uploaded_at::timestamptz
FROM (VALUES
  ('DEMO/employee/DEMO-E001/publication/attendance-analytics-paper.pdf',
   'attendance-analytics-paper.pdf', 262144::bigint,
   'b1f4c0d2e3a5968778695a4b3c2d1e0f9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d',
   '2025-09-30 10:00:00+00', 'CONFIDENTIAL'),
  ('DEMO/student/DEMO-S001/activity/athletics-participation-certificate.pdf',
   'athletics-participation-certificate.pdf', 131072::bigint,
   'c2e5d1f3a4b60798879a5b4c3d2e1f0a9b8c7d6e5f4a3b2c1d0e9f8a7b6c5d4e',
   '2025-09-28 11:00:00+00', 'INTERNAL'),
  ('DEMO/student/DEMO-S002/activity/hackathon-participation-certificate.pdf',
   'hackathon-participation-certificate.pdf', 131072::bigint,
   'a4c7e91b2d5f60831a4c7e91b2d5f60831a4c7e91b2d5f60831a4c7e91b2d5f6',
   '2025-09-13 11:00:00+00', 'INTERNAL'),
  ('DEMO/announcement/demo-university-orientation-brochure.pdf',
   'demo-university-orientation-brochure.pdf', 196608::bigint,
   'd3f6e2a4b5c70899a8b6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f0a9b8c7d6e5f4',
   '2025-08-01 09:30:00+00', 'PUBLIC')
) AS v(storage_key, file_name, size, checksum, uploaded_at, level)
WHERE NOT EXISTS (
  SELECT 1 FROM public.file_object x WHERE x.storage_key = v.storage_key
);

INSERT INTO public.evidence_document_version (evidence_document_id, version_number, file_object_id, change_reason, uploaded_by_user_id, uploaded_at, is_current)
SELECT ev.evidence_document_id, 1, f.file_object_id,
       'The published paper that was uploaded with the publication record.',
       1, '2025-09-30 10:00:00+00'::timestamptz, true
FROM public.evidence_document ev
JOIN public.file_object f
  ON f.storage_key = 'DEMO/employee/DEMO-E001/publication/attendance-analytics-paper.pdf'
WHERE ev.document_title = 'Published paper of the attendance analytics study'
  AND NOT EXISTS (
    SELECT 1 FROM public.evidence_document_version x
     WHERE x.evidence_document_id = ev.evidence_document_id
       AND x.version_number = 1
  );

INSERT INTO public.evidence_document_audit (evidence_document_id, evidence_document_version_id, action_code, performed_by_user_id, performed_at, ip_address, user_agent, before_values, after_values, remarks)
SELECT ev.evidence_document_id, v.evidence_document_version_id, 'UPLOAD', 1,
       '2025-09-30 10:00:00+00'::timestamptz, '10.0.0.1', 'SIMS-DEMO/1.0',
       NULL::jsonb,
       jsonb_build_object('document_title', ev.document_title, 'version_number', 1),
       'The published paper was uploaded against the publication record.'
FROM public.evidence_document ev
JOIN public.evidence_document_version v
  ON v.evidence_document_id = ev.evidence_document_id AND v.version_number = 1
WHERE ev.document_title = 'Published paper of the attendance analytics study'
  AND NOT EXISTS (
    SELECT 1 FROM public.evidence_document_audit x
     WHERE x.evidence_document_id = ev.evidence_document_id
       AND x.action_code = 'UPLOAD'
  );

INSERT INTO public.staff_activity_contributor (staff_activity_id, employee_id, external_person_name, external_person_email, external_organization_id, affiliation_text, role_type_id, contributor_sequence, is_corresponding_author, contribution_details, is_primary)
SELECT sa.staff_activity_id, e.employee_id, v.external_name, v.external_email,
       v.external_org_id, v.affiliation, rt.role_type_id, v.seq, v.corresponding, v.details, v.is_primary
FROM public.staff_activity sa
CROSS JOIN (VALUES
  ('DEMO-E002', NULL::text, NULL::text, NULL::bigint, 'Demo Institute of Technology, Haveri',
   'CO_AUTHOR', 2, false,
   'Co-authored the study and wrote the data analysis section.', false),
  (NULL::text, 'Dr. Leela Menon', 'leela.menon@example.com',
   (SELECT organization_id FROM public.external_organization WHERE organization_code = 'DEMO-ORG-DEMOUNIV'),
   'Demo University, Haveri', 'REVIEWER', 3, false,
   'Reviewed the methodology and the results of the study.', false)
) AS v(empnum, external_name, external_email, external_org_id, affiliation, role_code, seq, corresponding, details, is_primary)
LEFT JOIN public.employee e ON e.employee_number = v.empnum
JOIN public.role_type rt ON rt.role_code = v.role_code
WHERE sa.activity_title = 'Attendance analytics of the first year programming laboratory'
  AND NOT EXISTS (
    SELECT 1 FROM public.staff_activity_contributor x
     WHERE x.staff_activity_id = sa.staff_activity_id
       AND x.contributor_sequence = v.seq
  );

-- ---------------------------------------------------------------------------------------------
-- Module 19 - staff profile: the sections of the record that the supertype alone cannot carry
-- ---------------------------------------------------------------------------------------------
-- The MySQL source gives each of these its own table.  The application models them as one
-- screen: `staff_activity` is the supertype and `activity_type` says which child table a row
-- belongs to.  The eight activities below hang off DEMO-E002, so the record of DEMO-E001 stays
-- the single journal publication the demo asserts.

INSERT INTO public.staff_activity (employee_id, activity_type_id, academic_year_id, institution_id, campus_id, department_id, participation_level_id, primary_role_type_id, activity_title, start_date, end_date, description, outcomes, verification_status_id, approval_status_id, remarks)
SELECT e.employee_id, at.activity_type_id,
       (SELECT academic_year_id FROM public.academic_year WHERE year_code = '2025-26'),
       (SELECT institution_id FROM public.institution WHERE institution_code = 'DEMO-INST'),
       (SELECT campus_id FROM public.campus WHERE campus_code = 'DEMO-CAMPUS'),
       (SELECT department_id FROM public.department WHERE department_code = 'DEMO-MGT'),
       pl.participation_level_id, rt.role_type_id,
       v.title, v.start_date::date, v.end_date::date, v.description, v.outcomes,
       (SELECT verification_status_id FROM public.verification_status WHERE status_code = 'PENDING'),
       (SELECT approval_status_id FROM public.approval_status WHERE status_code = 'DRAFT'),
       'Awaiting verification and approval.'
FROM public.employee e
CROSS JOIN (VALUES
  ('FACULTY_INTERNSHIP', 'Industry internship with Demo Systems',
   '2025-06-02', '2025-07-31',
   'Industry internship carried out with Demo Systems on the attendance analytics platform.',
   'The prototype of the attendance dashboard was handed over to the company.',
   'NATIONAL', 'RESOURCE_PERSON'),
  ('RESEARCH_PROPOSAL', 'Adaptive assessment in the programming laboratory',
   '2025-06-20', NULL::text,
   'Proposal for an adaptive assessment model for the first year programming laboratory.',
   'The proposal is with the demo research council.',
   'NATIONAL', 'PI'),
  ('CONSULTANCY', 'Curriculum consulting for Demo Systems',
   '2025-08-01', '2026-01-31',
   'Consultancy assignment to review the software engineering curriculum of Demo Systems.',
   'The curriculum review report was delivered.',
   'NATIONAL', 'PRINCIPAL_CONSULTANT'),
  ('CO_CURRICULAR', 'Demo coding club mentoring event',
   '2025-10-11', '2025-10-11',
   'Mentoring of the first year students at the demo coding club induction event.',
   'Forty students took part in the induction event.',
   'DEPARTMENT', 'COORDINATOR'),
  ('EXTRA_CURRICULAR', 'Demo university cultural festival',
   '2025-12-05', '2025-12-06',
   'Cultural festival of the demo university.',
   'The department won the group dance competition.',
   'STATE', 'PARTICIPANT'),
  ('AWARD_RECOGNITION', 'Best teacher award of the demo university',
   '2026-04-15', '2026-04-15',
   'The best teacher award of the demo university for the year 2025-26.',
   'The award was received at the annual day.',
   'UNIVERSITY', 'PARTICIPANT'),
  ('PROFESSIONAL_MEMBERSHIP', 'Membership of the Demo Institute of Professional Studies',
   '2025-09-01', '2027-08-31',
   'Professional membership of the Demo Institute of Professional Studies.',
   'The membership is renewed every two years.',
   'NATIONAL', 'OFFICE_BEARER'),
  ('FDP', 'Faculty development programme on outcome based education',
   '2025-07-07', '2025-07-12',
   'Faculty development programme on outcome based education held at the demo university.',
   'The training material was uploaded to the staff profile.',
   'NATIONAL', 'TRAINER')
) AS v(activity_type_code, title, start_date, end_date, description, outcomes, level_code, role_code)JOIN public.activity_type at ON at.activity_type_code = v.activity_type_code
JOIN public.participation_level pl ON pl.level_code = v.level_code
JOIN public.role_type rt ON rt.role_code = v.role_code
WHERE e.employee_number = 'DEMO-E002'
  AND NOT EXISTS (
    SELECT 1 FROM public.staff_activity x
     WHERE x.employee_id = e.employee_id
       AND x.activity_title = v.title
  );

INSERT INTO public.faculty_internship (staff_activity_id, organization_id, internship_title, internship_domain, industry_sector_id, location_text, mentor_name, mentor_designation, mentor_email, work_undertaken, technologies_tools, outcomes, stipend_incentive_type, stipend_incentive_amount, currency_code, funding_source, mou_reference, collaboration_reference)
SELECT sa.staff_activity_id, o.organization_id, v.title, v.domain, s.industry_sector_id,
       v.location, v.mentor_name, v.mentor_designation, v.mentor_email, v.work, v.tools,
       v.outcomes, v.stipend_type, v.stipend_amount, 'INR', v.funding, v.mou, v.collaboration
FROM public.staff_activity sa
CROSS JOIN (VALUES
  ('Industry internship with Demo Systems', 'Software engineering and quality assurance',
   'Bengaluru', 'Anita Deshpande', 'Engineering Manager', 'anita.deshpande@example.com',
   'Built the attendance analytics service and wrote the integration tests.',
   'Java, PostgreSQL, Docker',
   'The service was accepted by the company and the internship was extended by one month.',
   'STIPEND', 25000.00::numeric,
   'Demo Systems Private Limited', 'DEMO-MOU-2025-001', 'DEMO-COLLAB-2025-001')
) AS v(title, domain, location, mentor_name, mentor_designation, mentor_email, work, tools,
       outcomes, stipend_type, stipend_amount, funding, mou, collaboration)
JOIN public.external_organization o ON o.organization_code = 'DEMO-ORG-DEMOSPON'
JOIN public.industry_sector s ON s.sector_code = 'IT'
WHERE sa.activity_title = 'Industry internship with Demo Systems'
  AND NOT EXISTS (
    SELECT 1 FROM public.faculty_internship x WHERE x.staff_activity_id = sa.staff_activity_id
  );

INSERT INTO public.research_proposal (staff_activity_id, proposal_title, principal_investigator_employee_id, department_id, proposal_submission_date, funding_agency_id, funding_type_id, scheme_program_name, requested_amount, currency_code, research_status_id, proposal_reference_number, project_objectives, research_domain, expected_outcomes, review_comments)
SELECT sa.staff_activity_id, v.title, e.employee_id, d.department_id, v.submission_date::date,
       fa.funding_agency_id, ft.funding_type_id, v.scheme, v.amount, 'INR', rs.research_status_id,
       v.reference, v.objectives, v.domain, v.outcomes, v.review
FROM public.staff_activity sa
CROSS JOIN (VALUES
  ('Adaptive assessment in the programming laboratory', '2025-06-20',
   'Demo Research Council - Adaptive Assessment Scheme', 350000.00::numeric,
   'DEMO-RP-2025-001',
   'To build an adaptive assessment model for the first year programming laboratory.',
   'Learning analytics',
   'One journal paper, one prototype and a set of assessment guidelines.',
   'The proposal was accepted for review by the demo research council.')
) AS v(title, submission_date, scheme, amount, reference, objectives, domain, outcomes, review)
JOIN public.employee e ON e.employee_number = 'DEMO-E002'
JOIN public.department d ON d.department_code = 'DEMO-MGT'
JOIN public.funding_agency fa
  ON fa.organization_id = (SELECT organization_id FROM public.external_organization
                            WHERE organization_code = 'DEMO-ORG-DEMOFUND')
JOIN public.funding_type ft ON ft.funding_type_code = 'GOVERNMENT'
JOIN public.research_status rs ON rs.status_code = 'SUBMITTED'
WHERE sa.activity_title = 'Adaptive assessment in the programming laboratory'
  AND NOT EXISTS (
    SELECT 1 FROM public.research_proposal x WHERE x.staff_activity_id = sa.staff_activity_id
  );

INSERT INTO public.consultancy_project (staff_activity_id, consultancy_title, client_organization_id, principal_consultant_employee_id, consultancy_type, work_order_number, agreement_number, purchase_order_number, project_start_date, completion_date, consultancy_amount, amount_received, faculty_incentive_share, currency_code, deliverables, status, client_feedback)
SELECT sa.staff_activity_id, v.title, o.organization_id, e.employee_id, v.consultancy_type,
       v.work_order, v.agreement, v.purchase_order, v.start_date::date, v.completion_date::date,
       v.amount, v.received, v.incentive, 'INR', v.deliverables, v.status, v.feedback
FROM public.staff_activity sa
CROSS JOIN (VALUES
  ('Curriculum consulting for Demo Systems', 'CONSULTANCY',
   'DEMO-WO-2025-001', 'DEMO-AGR-2025-001', 'DEMO-PO-2025-001',
   '2025-08-01', '2026-01-31',
   400000.00::numeric, 200000.00::numeric, 120000.00::numeric,
   'The curriculum review report and the revised course map.',
   'ONGOING',
   'The mid term review was well received and the second tranche was released.')
) AS v(title, consultancy_type, work_order, agreement, purchase_order, start_date, completion_date,
       amount, received, incentive, deliverables, status, feedback)
JOIN public.external_organization o ON o.organization_code = 'DEMO-ORG-DEMOSPON'
JOIN public.employee e ON e.employee_number = 'DEMO-E002'
WHERE sa.activity_title = 'Curriculum consulting for Demo Systems'
  AND NOT EXISTS (
    SELECT 1 FROM public.consultancy_project x WHERE x.staff_activity_id = sa.staff_activity_id
  );

INSERT INTO public.cocurricular_activity (staff_activity_id, cocurricular_category_id, event_name, organizer_id, institution_organization_id, event_date, venue_name, city, state_id, country_id, achievement_award, contribution_details)
SELECT sa.staff_activity_id, c.cocurricular_category_id, v.event_name, o.organizer_id,
       eo.organization_id, v.event_date::date, v.venue, v.city,
       (SELECT state_id FROM public.state
         WHERE state_code = 'KA'
           AND country_id = (SELECT country_id FROM public.country WHERE iso_code = 'IN') LIMIT 1),
       (SELECT country_id FROM public.country WHERE iso_code = 'IN' LIMIT 1),
       v.award, v.details
FROM public.staff_activity sa
CROSS JOIN (VALUES
  ('Demo coding club mentoring event', 'Demo Coding Club Induction Event',
   '2025-10-11', 'Demo Innovation Centre', 'Haveri',
   'Best mentor of the induction event.',
   'Mentored forty first year students through the induction event.')
) AS v(title, event_name, event_date, venue, city, award, details)
JOIN public.cocurricular_category c ON c.category_code = 'TECHNICAL_EVENT'
JOIN public.organizer o
  ON o.organization_id = (SELECT organization_id FROM public.external_organization
                            WHERE organization_code = 'DEMO-ORG-DEMOCONF')
JOIN public.external_organization eo ON eo.organization_code = 'DEMO-ORG-DEMOUNIV'
WHERE sa.activity_title = 'Demo coding club mentoring event'
  AND NOT EXISTS (
    SELECT 1 FROM public.cocurricular_activity x WHERE x.staff_activity_id = sa.staff_activity_id
  );

INSERT INTO public.extracurricular_activity (staff_activity_id, extracurricular_category_id, event_name, organizer_id, institution_organization_id, event_date, venue_name, city, state_id, country_id, award_recognition, activity_details)
SELECT sa.staff_activity_id, c.extracurricular_category_id, v.event_name, o.organizer_id,
       eo.organization_id, v.event_date::date, v.venue, v.city,
       (SELECT state_id FROM public.state
         WHERE state_code = 'KA'
           AND country_id = (SELECT country_id FROM public.country WHERE iso_code = 'IN') LIMIT 1),
       (SELECT country_id FROM public.country WHERE iso_code = 'IN' LIMIT 1),
       v.award, v.details
FROM public.staff_activity sa
CROSS JOIN (VALUES
  ('Demo university cultural festival', 'Demo University Cultural Festival',
   '2025-12-05', 'Demo University Auditorium', 'Haveri',
   'Winner of the group dance competition.',
   'Choreographed the department entry for the group dance competition.')
) AS v(title, event_name, event_date, venue, city, award, details)
JOIN public.extracurricular_category c ON c.category_code = 'CULTURAL'
JOIN public.organizer o
  ON o.organization_id = (SELECT organization_id FROM public.external_organization
                            WHERE organization_code = 'DEMO-ORG-DEMOCONF')
JOIN public.external_organization eo ON eo.organization_code = 'DEMO-ORG-DEMOUNIV'
WHERE sa.activity_title = 'Demo university cultural festival'
  AND NOT EXISTS (
    SELECT 1 FROM public.extracurricular_activity x WHERE x.staff_activity_id = sa.staff_activity_id
  );

INSERT INTO public.staff_award (staff_activity_id, award_category_id, award_name, awarding_organization_id, award_date, citation_details, cash_prize_amount, incentive_amount, currency_code, award_reference_number)
SELECT sa.staff_activity_id, c.award_category_id, v.award_name, eo.organization_id,
       v.award_date::date, v.citation, v.cash_prize, v.incentive, 'INR', v.reference
FROM public.staff_activity sa
CROSS JOIN (VALUES
  ('Best teacher award of the demo university', 'Best Teacher Award of the Demo University 2025-26',
   '2026-04-15',
   'Awarded for the teaching record of the first year programming laboratory.',
   10000.00::numeric, 5000.00::numeric, 'DEMO-AWD-2026-001')
) AS v(title, award_name, award_date, citation, cash_prize, incentive, reference)
JOIN public.award_category c ON c.category_code = 'TEACHING'
JOIN public.external_organization eo ON eo.organization_code = 'DEMO-ORG-DEMOUNIV'
WHERE sa.activity_title = 'Best teacher award of the demo university'
  AND NOT EXISTS (
    SELECT 1 FROM public.staff_award x WHERE x.staff_activity_id = sa.staff_activity_id
  );

INSERT INTO public.staff_professional_membership (staff_activity_id, organization_id, membership_type_id, membership_number, membership_start_date, membership_expiry_date, is_lifetime_membership, role_type_id, participation_level_id, renewal_required, membership_status)
SELECT sa.staff_activity_id, eo.organization_id, mt.membership_type_id, v.membership_number,
       v.start_date::date, v.expiry_date::date, false, rt.role_type_id, pl.participation_level_id,
       true, 'ACTIVE'
FROM public.staff_activity sa
CROSS JOIN (VALUES
  ('Membership of the Demo Institute of Professional Studies', 'DEMO-IPS-2025-0042',
   '2025-09-01', '2027-08-31')
) AS v(title, membership_number, start_date, expiry_date)
JOIN public.external_organization eo ON eo.organization_code = 'DEMO-ORG-DEMOUNIV'
JOIN public.membership_type mt ON mt.type_code = 'MEMBER'
JOIN public.role_type rt ON rt.role_code = 'OFFICE_BEARER'
JOIN public.participation_level pl ON pl.level_code = 'NATIONAL'
WHERE sa.activity_title = 'Membership of the Demo Institute of Professional Studies'
  AND NOT EXISTS (
    SELECT 1 FROM public.staff_professional_membership x WHERE x.staff_activity_id = sa.staff_activity_id
  );

INSERT INTO public.professional_development_activity (staff_activity_id, training_program_type_id, program_title, organizer_id, sponsoring_organization_id, funding_agency_id, venue_name, city, state_id, country_id, event_mode_id, duration_days, duration_hours, financial_support_received, financial_support_amount, currency_code, certificate_number, learning_outcomes)
SELECT sa.staff_activity_id, tt.training_program_type_id, v.program_title, o.organizer_id,
       eo.organization_id, fa.funding_agency_id, v.venue, v.city,
       (SELECT state_id FROM public.state
         WHERE state_code = 'KA'
           AND country_id = (SELECT country_id FROM public.country WHERE iso_code = 'IN') LIMIT 1),
       (SELECT country_id FROM public.country WHERE iso_code = 'IN' LIMIT 1),
       em.event_mode_id, v.days, v.hours, true, v.support, 'INR', v.certificate, v.outcomes
FROM public.staff_activity sa
CROSS JOIN (VALUES
  ('Faculty development programme on outcome based education',
   'Outcome Based Education for the First Year Programming Laboratory',
   'Demo University Academic Block', 'Haveri', 5.00::numeric, 30.00::numeric,
   15000.00::numeric, 'DEMO-FDP-2025-001',
   'The participants rewrote the course outcomes and the assessment map of their courses.')
) AS v(title, program_title, venue, city, days, hours, support, certificate, outcomes)
JOIN public.training_program_type tt ON tt.type_code = 'FDP'
JOIN public.organizer o
  ON o.organization_id = (SELECT organization_id FROM public.external_organization
                            WHERE organization_code = 'DEMO-ORG-DEMOCONF')
JOIN public.external_organization eo ON eo.organization_code = 'DEMO-ORG-DEMOUNIV'
JOIN public.funding_agency fa
  ON fa.organization_id = (SELECT organization_id FROM public.external_organization
                            WHERE organization_code = 'DEMO-ORG-DEMOFUND')
JOIN public.event_mode em ON em.mode_code = 'OFFLINE'
WHERE sa.activity_title = 'Faculty development programme on outcome based education'
  AND NOT EXISTS (
    SELECT 1 FROM public.professional_development_activity x WHERE x.staff_activity_id = sa.staff_activity_id
  );

-- ---------------------------------------------------------------------------------------------
-- Module 40 - student activity: the evidence behind the record
-- ---------------------------------------------------------------------------------------------

INSERT INTO public.student_activity_evidence (student_activity_id, document_type_id, evidence_type_id, confidentiality_level_id, document_title, description, academic_year_id, document_issue_date, issuing_authority, issuing_organization_id, certificate_document_number, verification_status_id, approval_status_id, current_version_number, is_active, created_by_user_id)
SELECT sa.student_activity_id,
       (SELECT document_type_id FROM public.document_type WHERE document_code = 'OTHER_EMPLOYEE_DOC'),
       (SELECT evidence_type_id FROM public.evidence_type WHERE evidence_type_code = 'STUDENT_ACHIEVEMENT_CERTIFICATE'),
       (SELECT confidentiality_level_id FROM public.confidentiality_level WHERE level_code = 'INTERNAL'),
       v.title, v.description,
       (SELECT academic_year_id FROM public.academic_year WHERE year_code = '2025-26'),
       v.issue_date::date, v.authority,
       (SELECT organization_id FROM public.external_organization WHERE organization_code = 'DEMO-ORG-DEMOUNIV'),
       v.certificate,
       (SELECT verification_status_id FROM public.verification_status WHERE status_code = 'PENDING'),
       (SELECT approval_status_id FROM public.approval_status WHERE status_code = 'DRAFT'),
       1, true, 1
FROM (VALUES
  ('Inter-college athletics meet', 'Inter-college athletics participation certificate',
   'The certificate that backs the inter-college athletics record.',
   '2025-09-28', 'Demo University Sports Council', 'DEMO-ACT-001',
   'DEMO/student/DEMO-S001/activity/athletics-participation-certificate.pdf',
   '2025-09-28 11:00:00+00'),
  ('Smart India Hackathon', 'Smart India Hackathon participation certificate',
   'The certificate that backs the hackathon record.',
   '2025-09-13', 'Smart India Hackathon Cell', 'DEMO-ACT-002',
   'DEMO/student/DEMO-S002/activity/hackathon-participation-certificate.pdf',
   '2025-09-13 11:00:00+00')
) AS v(activity_title, title, description, issue_date, authority, certificate, storage_key, uploaded_at)
JOIN public.student_activity sa ON sa.activity_title = v.activity_title
WHERE NOT EXISTS (
  SELECT 1 FROM public.student_activity_evidence x
   WHERE x.student_activity_id = sa.student_activity_id
     AND x.document_title = v.title
);

INSERT INTO public.student_activity_evidence_version (student_activity_evidence_id, version_number, file_object_id, change_reason, uploaded_by_user_id, uploaded_at, is_current)
SELECT ev.student_activity_evidence_id, 1, f.file_object_id,
       'The certificate that was uploaded with the activity record.',
       1, v.uploaded_at::timestamptz, true
FROM public.student_activity_evidence ev
JOIN (VALUES
  ('Inter-college athletics participation certificate',
   'DEMO/student/DEMO-S001/activity/athletics-participation-certificate.pdf',
   '2025-09-28 11:00:00+00'),
  ('Smart India Hackathon participation certificate',
   'DEMO/student/DEMO-S002/activity/hackathon-participation-certificate.pdf',
   '2025-09-13 11:00:00+00')
) AS v(document_title, storage_key, uploaded_at) ON ev.document_title = v.document_title
JOIN public.file_object f ON f.storage_key = v.storage_key
WHERE NOT EXISTS (
  SELECT 1 FROM public.student_activity_evidence_version x
   WHERE x.student_activity_evidence_id = ev.student_activity_evidence_id
     AND x.version_number = 1
);

INSERT INTO public.student_activity_evidence_audit (student_activity_evidence_id, student_activity_evidence_version_id, action_code, performed_by_user_id, performed_at, ip_address, user_agent, before_values, after_values, remarks)
SELECT ev.student_activity_evidence_id, ver.student_activity_evidence_version_id, 'UPLOAD', 1,
       v.uploaded_at::timestamptz, '10.0.0.1', 'SIMS-DEMO/1.0',
       NULL::jsonb,
       jsonb_build_object('document_title', ev.document_title, 'version_number', 1),
       'The participation certificate was uploaded against the activity record.'
FROM public.student_activity_evidence ev
JOIN (VALUES
  ('Inter-college athletics participation certificate', '2025-09-28 11:00:00+00'),
  ('Smart India Hackathon participation certificate', '2025-09-13 11:00:00+00')
) AS v(document_title, uploaded_at) ON ev.document_title = v.document_title
JOIN public.student_activity_evidence_version ver
  ON ver.student_activity_evidence_id = ev.student_activity_evidence_id AND ver.version_number = 1
WHERE NOT EXISTS (
  SELECT 1 FROM public.student_activity_evidence_audit x
   WHERE x.student_activity_evidence_id = ev.student_activity_evidence_id
     AND x.action_code = 'UPLOAD'
);

-- ---------------------------------------------------------------------------------------------
-- Module 24 - feedback: the responses the results screen reads
-- ---------------------------------------------------------------------------------------------
-- The results screen stays empty until a cycle has at least five responses, so both demo
-- cycles get six.  The rows are written the way `feedback_submit` writes them.

INSERT INTO public.feedback_response (feedback_cycle_id, term_registration_id, course_offering_id, faculty_assignment_id, submitted_at, response_token)
SELECT v.cycle_id, v.term_registration_id, v.course_offering_id, v.faculty_assignment_id,
       v.submitted_at::timestamptz, v.token
FROM (VALUES
  (2, 1, 1, 1, '2025-10-06 09:10:00+00', 'DEMO-FB-RESP-001'),
  (2, 2, 1, 1, '2025-10-06 10:25:00+00', 'DEMO-FB-RESP-002'),
  (2, 3, 1, 1, '2025-10-06 11:40:00+00', 'DEMO-FB-RESP-003'),
  (2, 1, 1, 1, '2025-10-07 08:55:00+00', 'DEMO-FB-RESP-004'),
  (2, 2, 1, 1, '2025-10-07 13:15:00+00', 'DEMO-FB-RESP-005'),
  (2, 3, 1, 1, '2025-10-07 16:30:00+00', 'DEMO-FB-RESP-006'),
  (1, 1, 1, 1, '2025-10-08 09:05:00+00', 'DEMO-FB-RESP-007'),
  (1, 2, 1, 1, '2025-10-08 10:35:00+00', 'DEMO-FB-RESP-008'),
  (1, 3, 1, 1, '2025-10-08 12:05:00+00', 'DEMO-FB-RESP-009'),
  (1, 1, 1, 1, '2025-10-09 09:45:00+00', 'DEMO-FB-RESP-010'),
  (1, 2, 1, 1, '2025-10-09 11:20:00+00', 'DEMO-FB-RESP-011'),
  (1, 3, 1, 1, '2025-10-09 14:50:00+00', 'DEMO-FB-RESP-012')
) AS v(cycle_id, term_registration_id, course_offering_id, faculty_assignment_id, submitted_at, token)
WHERE NOT EXISTS (
  SELECT 1 FROM public.feedback_response x WHERE x.response_token = v.token
);

INSERT INTO public.feedback_response_item (feedback_response_id, questionnaire_item_id, feedback_choice_id, numeric_score, text_response)
SELECT fr.feedback_response_id, v.questionnaire_item_id, v.choice_id, v.score, v.text
FROM (VALUES
  ('DEMO-FB-RESP-001', 1, NULL::bigint, 4.00::numeric, NULL::text),
  ('DEMO-FB-RESP-001', 3, NULL::bigint, NULL::numeric, 'The laboratory sessions could have more hands on practice.'),
  ('DEMO-FB-RESP-001', 4, 13::bigint, NULL::numeric, NULL::text),
  ('DEMO-FB-RESP-002', 1, NULL::bigint, 5.00::numeric, NULL::text),
  ('DEMO-FB-RESP-002', 3, NULL::bigint, NULL::numeric, 'The weekly notes are very clear.'),
  ('DEMO-FB-RESP-002', 4, 13::bigint, NULL::numeric, NULL::text),
  ('DEMO-FB-RESP-003', 1, NULL::bigint, 3.00::numeric, NULL::text),
  ('DEMO-FB-RESP-003', 3, NULL::bigint, NULL::numeric, 'Please add one more project of a larger size.'),
  ('DEMO-FB-RESP-003', 4, 12::bigint, NULL::numeric, NULL::text),
  ('DEMO-FB-RESP-004', 1, NULL::bigint, 4.00::numeric, NULL::text),
  ('DEMO-FB-RESP-004', 3, NULL::bigint, NULL::numeric, 'The evaluation of the internal assessment was fair.'),
  ('DEMO-FB-RESP-004', 4, 13::bigint, NULL::numeric, NULL::text),
  ('DEMO-FB-RESP-005', 1, NULL::bigint, 5.00::numeric, NULL::text),
  ('DEMO-FB-RESP-005', 3, NULL::bigint, NULL::numeric, 'The course outline should be shared at the start of the term.'),
  ('DEMO-FB-RESP-005', 4, 13::bigint, NULL::numeric, NULL::text),
  ('DEMO-FB-RESP-006', 1, NULL::bigint, 4.00::numeric, NULL::text),
  ('DEMO-FB-RESP-006', 3, NULL::bigint, NULL::numeric, 'The reference material of the laboratory is helpful.'),
  ('DEMO-FB-RESP-006', 4, 11::bigint, NULL::numeric, NULL::text),
  ('DEMO-FB-RESP-007', 2, NULL::bigint, NULL::numeric, '9,10'),
  ('DEMO-FB-RESP-007', 5, NULL::bigint, 4.00::numeric, NULL::text),
  ('DEMO-FB-RESP-008', 2, NULL::bigint, NULL::numeric, '8,9'),
  ('DEMO-FB-RESP-008', 5, NULL::bigint, 5.00::numeric, NULL::text),
  ('DEMO-FB-RESP-009', 2, NULL::bigint, NULL::numeric, '9'),
  ('DEMO-FB-RESP-009', 5, NULL::bigint, 4.00::numeric, NULL::text),
  ('DEMO-FB-RESP-010', 2, NULL::bigint, NULL::numeric, '8,9,10'),
  ('DEMO-FB-RESP-010', 5, NULL::bigint, 5.00::numeric, NULL::text),
  ('DEMO-FB-RESP-011', 2, NULL::bigint, NULL::numeric, '7,8'),
  ('DEMO-FB-RESP-011', 5, NULL::bigint, 3.00::numeric, NULL::text),
  ('DEMO-FB-RESP-012', 2, NULL::bigint, NULL::numeric, '9,10'),
  ('DEMO-FB-RESP-012', 5, NULL::bigint, 4.00::numeric, NULL::text)
) AS v(token, questionnaire_item_id, choice_id, score, text)
JOIN public.feedback_response fr ON fr.response_token = v.token
WHERE NOT EXISTS (
  SELECT 1 FROM public.feedback_response_item x
   WHERE x.feedback_response_id = fr.feedback_response_id
     AND x.questionnaire_item_id = v.questionnaire_item_id
);

-- ---------------------------------------------------------------------------------------------
-- Module 13 - fees: the benefits, the adjustments, the penalties and the instalments
-- ---------------------------------------------------------------------------------------------
-- The three demo accounts each carry something the super administrator can still act on:
-- DEMO-S003 has a scholarship request that is waiting for a decision and a sponsorship that is
-- only partly applied, DEMO-S001 has a submitted adjustment and an assessed penalty, and
-- DEMO-S002 has an instalment plan that is waiting for a payment.
--
-- Every applied benefit is mirrored in the fee item it was applied to, every approved refund is
-- mirrored in the status of the payment it was refunded from, and every instalment matches the
-- plan that `fin_instalment_apply` would have produced for the assessment.

INSERT INTO public.student_fee_concession (student_id, concession_type_id, academic_year_id, application_number, application_date, approved_percentage, approved_amount, valid_from, valid_to, approval_status, approved_by, approved_at, remarks)
SELECT s.student_id, ct.concession_type_id,
       (SELECT academic_year_id FROM public.academic_year WHERE year_code = '2025-26'),
       v.application_number, v.application_date::date, v.percentage, v.amount,
       v.valid_from::date, v.valid_to::date, v.status, v.approved_by, v.approved_at::timestamptz, v.remarks
FROM (VALUES
  ('DEMO-S003', 'DEMO-CONC-001', '2025-07-10', 5.00::numeric, NULL::numeric,
   '2025-08-01', '2026-05-31', 'APPROVED', 1::bigint, '2025-07-20 10:00:00+00',
   'Merit concession of five percent on the tuition fee of the first semester.')
) AS v(snum, application_number, application_date, percentage, amount, valid_from, valid_to, status, approved_by, approved_at, remarks)
JOIN public.student s ON s.student_number = v.snum
JOIN public.concession_type ct ON ct.concession_code = 'MERIT'
WHERE NOT EXISTS (
  SELECT 1 FROM public.student_fee_concession x WHERE x.application_number = v.application_number
);

INSERT INTO public.student_scholarship (student_id, scholarship_scheme_id, academic_year_id, application_number, sanction_number, applied_amount, sanctioned_amount, received_amount, application_status, sanction_date, received_date, remarks)
SELECT s.student_id, m.scholarship_scheme_id,
       (SELECT academic_year_id FROM public.academic_year WHERE year_code = '2025-26'),
       v.application_number, v.sanction_number, v.applied, v.sanctioned, v.received,
       v.status, v.sanction_date::date, v.received_date::date, v.remarks
FROM (VALUES
  ('DEMO-S003', 'DEMO-SCH-001', NULL::text, 25000.00::numeric, NULL::numeric, 0.00::numeric,
   'SUBMITTED', NULL::text, NULL::text,
   'Institutional merit scholarship of the demo university.')
) AS v(snum, application_number, sanction_number, applied, sanctioned, received, status, sanction_date, received_date, remarks)
JOIN public.student s ON s.student_number = v.snum
JOIN public.scholarship_scheme m ON m.scheme_code = 'INST_MERIT'
WHERE NOT EXISTS (
  SELECT 1 FROM public.student_scholarship x WHERE x.application_number = v.application_number
);

INSERT INTO public.student_sponsorship (student_id, academic_year_id, sponsoring_authority, sanction_reference, sanctioned_amount, valid_from, valid_to, approval_status, approved_by, approved_at)
SELECT s.student_id,
       (SELECT academic_year_id FROM public.academic_year WHERE year_code = '2025-26'),
       v.authority, v.reference, v.amount, v.valid_from::date, v.valid_to::date,
       v.status, v.approved_by, v.approved_at::timestamptz
FROM (VALUES
  ('DEMO-S003', 'Demo Systems Private Limited', 'DEMO-SPON-001', 15000.00::numeric,
   '2025-08-01', '2026-05-31', 'APPROVED', 1::bigint, '2025-08-06 10:00:00+00')
) AS v(snum, authority, reference, amount, valid_from, valid_to, status, approved_by, approved_at)
JOIN public.student s ON s.student_number = v.snum
WHERE NOT EXISTS (
  SELECT 1 FROM public.student_sponsorship x WHERE x.sanction_reference = v.reference
);

-- The concession of 5000 explains the concession that the tuition fee of DEMO-S003 already
-- carries.  The sponsorship has only been applied in part, so 10000 of it are still available.
INSERT INTO public.fee_assessment_benefit (assessment_item_id, benefit_type, student_concession_id, student_scholarship_id, student_sponsorship_id, benefit_amount, applied_date, approved_by)
SELECT v.assessment_item_id, v.benefit_type, v.concession_id, v.scholarship_id, v.sponsorship_id,
       v.amount, v.applied_date::date, 1
FROM (VALUES
  (11::bigint, 'CONCESSION',
   (SELECT student_concession_id FROM public.student_fee_concession WHERE application_number = 'DEMO-CONC-001'),
   NULL::bigint, NULL::bigint, 5000.00::numeric, '2025-07-25'),
  (12::bigint, 'SPONSORSHIP',
   NULL::bigint, NULL::bigint,
   (SELECT student_sponsorship_id FROM public.student_sponsorship WHERE sanction_reference = 'DEMO-SPON-001'),
   5000.00::numeric, '2025-08-02')
) AS v(assessment_item_id, benefit_type, concession_id, scholarship_id, sponsorship_id, amount, applied_date)
WHERE NOT EXISTS (
  SELECT 1 FROM public.fee_assessment_benefit x
   WHERE x.assessment_item_id = v.assessment_item_id
     AND x.benefit_type = v.benefit_type
);

-- The two adjustments are waiting for a decision.  They are not part of any fee item yet, which
-- is exactly what a submitted adjustment looks like.
INSERT INTO public.fee_adjustment (adjustment_number, student_account_id, assessment_item_id, adjustment_type, adjustment_date, adjustment_amount, reason, approval_status)
SELECT v.number, fa.student_account_id, v.assessment_item_id, v.adjustment_type,
       v.adjustment_date::date, v.amount, v.reason, 'SUBMITTED'
FROM (VALUES
  ('DEMO-ADJ-001', 'DEMO-S003', 11::bigint, 'CREDIT', '2025-08-18', 1000.00::numeric,
   'Credit for the early payment of the tuition fee.'),
  ('DEMO-ADJ-002', 'DEMO-S001', 4::bigint, 'WAIVER', '2025-08-20', 500.00::numeric,
   'Waiver of the late payment fine on the library fee.')
) AS v(number, snum, assessment_item_id, adjustment_type, adjustment_date, amount, reason)
JOIN public.student s ON s.student_number = v.snum
JOIN public.student_financial_account fa ON fa.student_id = s.student_id
WHERE NOT EXISTS (
  SELECT 1 FROM public.fee_adjustment x WHERE x.adjustment_number = v.number
);

-- The penalty of DEMO-S001 is assessed but not waived yet.
INSERT INTO public.student_fee_penalty (student_account_id, assessment_item_id, fee_type_id, penalty_date, penalty_reason, penalty_amount, waived_amount, net_penalty_amount, penalty_status, approved_by)
SELECT fa.student_account_id, v.assessment_item_id,
       (SELECT fee_type_id FROM public.fee_type WHERE fee_code = 'LATE_FINE'),
       v.penalty_date::date, v.reason, v.amount, 0.00::numeric, v.amount, 'ASSESSED', 1
FROM (VALUES
  ('DEMO-S001', 6::bigint, '2025-09-05', 'Late payment of the examination fee.', 500.00::numeric)
) AS v(snum, assessment_item_id, penalty_date, reason, amount)
JOIN public.student s ON s.student_number = v.snum
JOIN public.student_financial_account fa ON fa.student_id = s.student_id
WHERE NOT EXISTS (
  SELECT 1 FROM public.student_fee_penalty x
   WHERE x.student_account_id = fa.student_account_id
     AND x.assessment_item_id = v.assessment_item_id
     AND x.penalty_date = v.penalty_date::date
);

-- The instalment plan of DEMO-S002.  The amounts are the ones that the three way split of the
-- plan produces for an assessment of 153000: 40 percent up front and the rest in two equal
-- instalments.
INSERT INTO public.student_installment_schedule (fee_assessment_id, installment_plan_id, installment_number, due_date, installment_amount, amount_paid, balance_amount, installment_status)
SELECT a.fee_assessment_id, ip.installment_plan_id, v.number, v.due_date::date,
       v.amount, 0.00::numeric, v.amount, 'PENDING'
FROM (VALUES
  ('DEMO-FEA-002', 103, 1, '2026-12-01', 61200.00::numeric),
  ('DEMO-FEA-002', 103, 2, '2027-01-01', 45900.00::numeric),
  ('DEMO-FEA-002', 103, 3, '2027-02-01', 45900.00::numeric)
) AS v(assessment_number, plan_id, number, due_date, amount)
JOIN public.student_fee_assessment a ON a.assessment_number = v.assessment_number
JOIN public.installment_plan ip ON ip.installment_plan_id = v.plan_id
WHERE NOT EXISTS (
  SELECT 1 FROM public.student_installment_schedule x
   WHERE x.fee_assessment_id = a.fee_assessment_id
     AND x.installment_number = v.number
);

INSERT INTO public.student_financial_hold (student_account_id, hold_type, hold_reason, placed_at, placed_by, hold_status)
SELECT fa.student_account_id, v.hold_type, v.reason, v.placed_at::timestamptz, 1, 'ACTIVE'
FROM (VALUES
  ('DEMO-S002', 'CERTIFICATE', 'The examination fee of the second instalment is still outstanding.',
   '2025-11-20 10:00:00+00')
) AS v(snum, hold_type, reason, placed_at)
JOIN public.student s ON s.student_number = v.snum
JOIN public.student_financial_account fa ON fa.student_id = s.student_id
WHERE NOT EXISTS (
  SELECT 1 FROM public.student_financial_hold x
   WHERE x.student_account_id = fa.student_account_id
     AND x.hold_type = v.hold_type
);

-- The refund of the tuition payment of DEMO-S003.  It has been processed, so the payment it was
-- refunded from is no longer a plain success.
INSERT INTO public.refund_request (refund_request_number, student_account_id, payment_transaction_id, request_date, refund_reason, requested_amount, approved_amount, request_status, approved_by, approved_at)
SELECT v.number, fa.student_account_id, v.payment_transaction_id, v.request_date::date,
       v.reason, v.requested, v.approved, 'PROCESSED', 1, v.approved_at::timestamptz
FROM (VALUES
  ('DEMO-RF-001', 'DEMO-S003', 1::bigint, '2025-09-10',
   'Part of the tuition fee was refunded when the laboratory component of the first semester was withdrawn.',
   10000.00::numeric, 10000.00::numeric, '2025-09-12 10:00:00+00')
) AS v(number, snum, payment_transaction_id, request_date, reason, requested, approved, approved_at)
JOIN public.student s ON s.student_number = v.snum
JOIN public.student_financial_account fa ON fa.student_id = s.student_id
WHERE NOT EXISTS (
  SELECT 1 FROM public.refund_request x WHERE x.refund_request_number = v.number
);

INSERT INTO public.fee_refund (refund_request_id, refund_transaction_number, refund_date, refund_amount, refund_mode_id, bank_reference_number, processed_by, refund_status, remarks)
SELECT rr.refund_request_id, v.number, v.refund_date::timestamptz, v.amount,
       (SELECT payment_mode_id FROM public.payment_mode WHERE mode_code = 'BANK_TRANSFER'),
       v.bank_reference, 1, 'SUCCESS', v.remarks
FROM (VALUES
  ('DEMO-RF-001', 'DEMO-REF-001', '2025-09-15 11:00:00+00', 10000.00::numeric,
   'DEMO-BANK-REF-001', 'The tuition fee was refunded to the bank account of the student.')
) AS v(request_number, number, refund_date, amount, bank_reference, remarks)
JOIN public.refund_request rr ON rr.refund_request_number = v.request_number
WHERE NOT EXISTS (
  SELECT 1 FROM public.fee_refund x WHERE x.refund_transaction_number = v.number
);

INSERT INTO public.late_fee_rule (rule_code, rule_name, calculation_method, grace_period_days, fixed_amount, daily_amount, percentage_rate, maximum_amount, effective_from, effective_to, is_active)
SELECT v.rule_code, v.rule_name, v.method, v.grace_days, v.fixed_amount, v.daily_amount,
       v.percentage, v.maximum, v.effective_from::date, v.effective_to::date, true
FROM (VALUES
  ('DEMO-LATE-001', 'Demo late payment fine', 'SLAB', 7, NULL::numeric, 100.00::numeric,
   NULL::numeric, 5000.00::numeric, '2025-07-01', '2026-06-30'),
  ('DEMO-LATE-002', 'Demo late payment fine for the examination fee', 'PER_DAY', 3,
   NULL::numeric, 50.00::numeric, NULL::numeric, 1000.00::numeric, '2025-07-01', '2026-06-30')
) AS v(rule_code, rule_name, method, grace_days, fixed_amount, daily_amount, percentage, maximum, effective_from, effective_to)
WHERE NOT EXISTS (
  SELECT 1 FROM public.late_fee_rule x WHERE x.rule_code = v.rule_code
);

INSERT INTO public.late_fee_slab (late_fee_rule_id, from_day, to_day, late_fee_amount)
SELECT r.late_fee_rule_id, v.from_day, v.to_day, v.amount
FROM (VALUES
  ('DEMO-LATE-001', 1, 7, 100.00::numeric),
  ('DEMO-LATE-001', 8, 30, 500.00::numeric),
  ('DEMO-LATE-001', 31, NULL::int, 1000.00::numeric)
) AS v(rule_code, from_day, to_day, amount)
JOIN public.late_fee_rule r ON r.rule_code = v.rule_code
WHERE NOT EXISTS (
  SELECT 1 FROM public.late_fee_slab x
   WHERE x.late_fee_rule_id = r.late_fee_rule_id
     AND x.from_day = v.from_day
     AND x.to_day IS NOT DISTINCT FROM v.to_day
);

-- Every assessment item records where its amount came from.
INSERT INTO public.fee_charge_source (assessment_item_id, source_module, source_entity, source_entity_id)
SELECT i.assessment_item_id, 'ACADEMIC', 'FEE_STRUCTURE_ITEM', fsi.fee_structure_item_id
FROM public.student_fee_assessment_item i
JOIN public.student_fee_assessment a ON a.fee_assessment_id = i.fee_assessment_id
JOIN public.fee_structure_item fsi ON fsi.fee_type_id = i.fee_type_id
JOIN public.fee_structure fs ON fs.fee_structure_id = fsi.fee_structure_id
WHERE fs.structure_code = 'DEMO-FS-UGCS-2025'
  AND a.assessment_number LIKE 'DEMO-%'
  AND NOT EXISTS (
    SELECT 1 FROM public.fee_charge_source x WHERE x.assessment_item_id = i.assessment_item_id
  );

-- The audit trail of the fee module.
INSERT INTO public.fee_activity_audit (user_id, action_code, entity_name, entity_id, old_values, new_values, ip_address, performed_at)
SELECT v.user_id, v.action_code, v.entity_name, v.entity_id, NULL::jsonb, v.new_values, '10.0.0.1', v.performed_at::timestamptz
FROM (VALUES
  (1::bigint, 'BENEFIT_REQUESTED', 'student_scholarship',
   (SELECT student_scholarship_id FROM public.student_scholarship WHERE application_number = 'DEMO-SCH-001'),
   '{"amount": 25000.00}'::jsonb, '2025-07-15 09:00:00+00'),
  (1::bigint, 'BENEFIT_REQUESTED', 'student_sponsorship',
   (SELECT student_sponsorship_id FROM public.student_sponsorship WHERE sanction_reference = 'DEMO-SPON-001'),
   '{"amount": 15000.00}'::jsonb, '2025-07-18 09:00:00+00'),
  (1::bigint, 'BENEFIT_APPLIED', 'fee_assessment_benefit',
   (SELECT assessment_benefit_id FROM public.fee_assessment_benefit WHERE benefit_type = 'CONCESSION' AND assessment_item_id = 11),
   '{"assessment_item_id": 11, "amount": 5000.00}'::jsonb, '2025-07-25 09:00:00+00'),
  (1::bigint, 'BENEFIT_APPLIED', 'fee_assessment_benefit',
   (SELECT assessment_benefit_id FROM public.fee_assessment_benefit WHERE benefit_type = 'SPONSORSHIP' AND assessment_item_id = 12),
   '{"assessment_item_id": 12, "amount": 5000.00}'::jsonb, '2025-08-02 09:00:00+00'),
  (1::bigint, 'ADJUSTMENT_REQUESTED', 'fee_adjustment',
   (SELECT fee_adjustment_id FROM public.fee_adjustment WHERE adjustment_number = 'DEMO-ADJ-001'),
   '{"type": "CREDIT", "amount": 1000.00}'::jsonb, '2025-08-18 09:00:00+00'),
  (1::bigint, 'ADJUSTMENT_REQUESTED', 'fee_adjustment',
   (SELECT fee_adjustment_id FROM public.fee_adjustment WHERE adjustment_number = 'DEMO-ADJ-002'),
   '{"type": "WAIVER", "amount": 500.00}'::jsonb, '2025-08-20 09:00:00+00'),
  (1::bigint, 'PENALTY_ASSESSED', 'student_fee_penalty',
   (SELECT fee_penalty_id FROM public.student_fee_penalty WHERE assessment_item_id = 6),
   '{"amount": 500.00}'::jsonb, '2025-09-05 09:00:00+00'),
  (1::bigint, 'REFUND_REQUESTED', 'refund_request',
   (SELECT refund_request_id FROM public.refund_request WHERE refund_request_number = 'DEMO-RF-001'),
   '{"amount": 10000.00}'::jsonb, '2025-09-10 09:00:00+00'),
  (1::bigint, 'REFUND_APPROVED', 'refund_request',
   (SELECT refund_request_id FROM public.refund_request WHERE refund_request_number = 'DEMO-RF-001'),
   '{"approved_amount": 10000.00}'::jsonb, '2025-09-12 10:00:00+00'),
  (1::bigint, 'REFUND_PROCESSED', 'fee_refund',
   (SELECT fee_refund_id FROM public.fee_refund WHERE refund_transaction_number = 'DEMO-REF-001'),
   '{"amount": 10000.00}'::jsonb, '2025-09-15 11:00:00+00')
) AS v(user_id, action_code, entity_name, entity_id, new_values, performed_at)
WHERE v.entity_id IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.fee_activity_audit x
     WHERE x.action_code = v.action_code
       AND x.entity_name = v.entity_name
       AND x.entity_id = v.entity_id
  );

-- ---------------------------------------------------------------------------------------------
-- Module 6 - admission: the payment that belongs to the application
-- ---------------------------------------------------------------------------------------------

INSERT INTO public.payment_transaction (transaction_number, student_account_id, application_id, transaction_date, payment_mode_id, amount, currency_code, payment_status, gateway_name, gateway_transaction_id, payer_name, payer_contact, remarks)
SELECT 'DEMO-PAY-002', fa.student_account_id, aa.application_id, '2025-07-12 09:45:00+00'::timestamptz,
       (SELECT payment_mode_id FROM public.payment_mode WHERE mode_code = 'UPI'),
       50000.00::numeric, 'INR', 'SUCCESS', 'DEMO-UPI', 'DEMO-UPI-TXN-0002',
       s.display_name, s.primary_phone,
       'Admission fee paid against DEMO-APPLICATION-001.'
FROM public.admission_application aa
JOIN public.student s ON s.student_id = aa.admitted_student_id
JOIN public.student_financial_account fa ON fa.student_id = s.student_id
WHERE aa.application_number = 'DEMO-APPLICATION-001'
  AND NOT EXISTS (
    SELECT 1 FROM public.payment_transaction x WHERE x.transaction_number = 'DEMO-PAY-002'
  );

INSERT INTO public.admission_payment (application_id, payment_transaction_id)
SELECT aa.application_id, pt.payment_transaction_id
FROM public.admission_application aa
JOIN public.payment_transaction pt ON pt.transaction_number = 'DEMO-PAY-002'
WHERE aa.application_number = 'DEMO-APPLICATION-001'
  AND NOT EXISTS (
    SELECT 1 FROM public.admission_payment x
     WHERE x.application_id = aa.application_id
       AND x.payment_transaction_id = pt.payment_transaction_id
  );

-- ---------------------------------------------------------------------------------------------
-- Module 8 - communication: the attachment of the announcement
-- ---------------------------------------------------------------------------------------------

INSERT INTO public.announcement_attachment (announcement_id, file_object_id, display_order)
SELECT a.announcement_id, f.file_object_id, 1
FROM public.announcement a
JOIN public.file_object f
  ON f.storage_key = 'DEMO/announcement/demo-university-orientation-brochure.pdf'
WHERE a.title = 'Demo University orientation'
  AND NOT EXISTS (
    SELECT 1 FROM public.announcement_attachment x
     WHERE x.announcement_id = a.announcement_id
       AND x.file_object_id = f.file_object_id
  );

-- ---------------------------------------------------------------------------------------------
-- Module 2 - IAM: the override, the delegation and the password history
-- ---------------------------------------------------------------------------------------------

INSERT INTO public.user_permission_override (user_id, permission_id, permission_effect, scope_type, valid_from, valid_to, granted_by_user_id, justification)
SELECT 3, p.permission_id, 'ALLOW', 'GLOBAL', '2025-07-01 00:00:00+00'::timestamptz,
       '2026-06-30 23:59:59+00'::timestamptz, 3,
       'The demo super administrator reads the fee benefit records of the whole institution.'
FROM public.permission p
WHERE p.permission_code = 'FEES.FEE_BENEFIT.READ'
  AND NOT EXISTS (
    SELECT 1 FROM public.user_permission_override x
     WHERE x.user_id = 3
       AND x.permission_id = p.permission_id
       AND x.scope_type = 'GLOBAL'
  );

INSERT INTO public.role_delegation (delegator_user_id, delegate_user_id, source_assignment_id, valid_from, valid_to, delegation_status, reason, approved_by_user_id)
SELECT 1, 2, a.user_role_assignment_id, '2025-08-01 00:00:00+00'::timestamptz,
       '2025-12-31 23:59:59+00'::timestamptz, 'ACTIVE',
       'The registrar role was delegated while the registrar was on leave.', 3
FROM public.user_role_assignment a
WHERE a.user_id = 1
  AND NOT EXISTS (
    SELECT 1 FROM public.role_delegation x
     WHERE x.delegator_user_id = 1
       AND x.delegate_user_id = 2
  );

INSERT INTO public.password_history (user_id, password_hash, changed_at)
SELECT 3, '!supabase-auth', '2025-07-01 00:00:00+00'::timestamptz
WHERE NOT EXISTS (
  SELECT 1 FROM public.password_history x WHERE x.user_id = 3
);

-- ---------------------------------------------------------------------------------------------
-- Module 6 - employees: the trail of the sensitive documents that were opened
-- ---------------------------------------------------------------------------------------------

INSERT INTO public.employee_sensitive_access_audit (user_id, employee_id, action_code, entity_type, entity_id, employee_document_id, access_purpose, was_successful, ip_address, user_agent, request_identifier, accessed_at)
SELECT 1, e.employee_id, v.action_code, v.entity_type, v.entity_id, v.document_id,
       v.purpose, true, '10.0.0.1', 'SIMS-DEMO/1.0', v.request_id, v.accessed_at::timestamptz
FROM (VALUES
  ('DEMO-E001', 'READ', 'QUALIFICATION', 1::bigint, 1::bigint,
   'The qualification record was opened while the staff profile was reviewed.',
   'DEMO-ACCESS-001', '2025-09-05 10:00:00+00'),
  ('DEMO-E001', 'DOWNLOAD', 'EMPLOYEE_DOCUMENT', 4::bigint, 4::bigint,
   'The appointment letter was downloaded for the annual audit.',
   'DEMO-ACCESS-002', '2025-09-06 11:30:00+00')
) AS v(empnum, action_code, entity_type, entity_id, document_id, purpose, request_id, accessed_at)
JOIN public.employee e ON e.employee_number = v.empnum
WHERE NOT EXISTS (
  SELECT 1 FROM public.employee_sensitive_access_audit x
   WHERE x.request_identifier = v.request_id
);

-- ---------------------------------------------------------------------------------------------
-- The fee items and the assessment header that the applied benefits changed
-- ---------------------------------------------------------------------------------------------
-- The sponsorship of 5000 was applied to the laboratory fee of DEMO-S003, so that item and the
-- header of its assessment carry the reduced amount.  The values are written as absolute
-- amounts, so replaying the seed changes nothing.

UPDATE public.student_fee_assessment_item
   SET scholarship_amount = 5000.00,
       net_amount = 20000.00,
       balance_amount = 20000.00
 WHERE assessment_item_id = 12
   AND fee_assessment_id = (
     SELECT fee_assessment_id FROM public.student_fee_assessment WHERE assessment_number = 'DEMO-FEA-003'
   );

UPDATE public.student_fee_assessment
   SET concession_amount = 5000.00,
       net_payable_amount = 143000.00,
       amount_paid = 50000.00,
       balance_amount = 93000.00
 WHERE assessment_number = 'DEMO-FEA-003';

-- The tuition payment of DEMO-S003 has been partly refunded.
UPDATE public.payment_transaction
   SET payment_status = 'PARTIALLY_REFUNDED'
 WHERE transaction_number = 'DEMO-PAY-001'
   AND payment_status = 'SUCCESS';
