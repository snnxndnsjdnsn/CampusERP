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
--    9  attendance              class sessions -> attendance rows
--   10  assessment and result   components -> events -> marks -> course and term results
--   13  documents and fees      fee structure -> assessment -> payment -> allocation -> receipt
--   14  communication           announcement
--   19  staff profile           staff activity (research record)
--   40  student activity        student activity (co-curricular record)
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
