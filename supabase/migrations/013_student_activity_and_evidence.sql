-- =============================================================================================
-- 013. student_activity_and_evidence
-- ---------------------------------------------------------------------------------------------
-- GENERATED FILE - do not edit by hand.
-- Regenerate with: npm run migrate:build   (python tools/translate.py && python tools/build_migrations.py)
--
-- Source of truth: the live Supabase catalogue (tools/catalogue/live_catalogue.json),
-- dumped read-only from project khqqfgqvwdxlqkncwtmh by tools/dump_catalogue.py.
-- =============================================================================================

-- -----------------------------------------------------------------------------
-- Seed rows for the tables of module 'student activity and evidence'.
-- Only the rows the live database really contains are emitted; every
-- statement carries explicit primary keys and is idempotent.
-- -----------------------------------------------------------------------------
-- MySQL module 40: STUDENT ACTIVITY & EVIDENCE MODULE
-- MySQL module 19: STAFF PROFILE REFERENCE / MASTER DATA
-- MySQL module 13: DOCUMENT, CERTIFICATE AND EXIT MODULE

INSERT INTO public.student_activity_type (student_activity_type_id, type_code, type_name, activity_group, description, requires_team_details, supports_achievement, is_active, created_at, updated_at) VALUES
  (1, 'CONFERENCE_PARTICIPATION', 'Conference Participation', 'CONFERENCE', NULL, FALSE, TRUE, TRUE, '2026-11-03T18:30:12.827787+00:00'::timestamptz, '2026-11-03T18:30:12.827787+00:00'::timestamptz),
  (2, 'CONFERENCE_PRESENTATION', 'Conference Paper / Poster Presentation', 'CONFERENCE', NULL, FALSE, TRUE, TRUE, '2026-11-03T18:30:12.827787+00:00'::timestamptz, '2026-11-03T18:30:12.827787+00:00'::timestamptz),
  (3, 'WORKSHOP', 'Workshop', 'WORKSHOP', NULL, FALSE, TRUE, TRUE, '2026-11-03T18:30:12.827787+00:00'::timestamptz, '2026-11-03T18:30:12.827787+00:00'::timestamptz),
  (4, 'HACKATHON', 'Hackathon', 'HACKATHON', NULL, TRUE, TRUE, TRUE, '2026-11-03T18:30:12.827787+00:00'::timestamptz, '2026-11-03T18:30:12.827787+00:00'::timestamptz),
  (5, 'SPORTS', 'Sports', 'SPORTS', NULL, TRUE, TRUE, TRUE, '2026-11-03T18:30:12.827787+00:00'::timestamptz, '2026-11-03T18:30:12.827787+00:00'::timestamptz),
  (6, 'CULTURAL_EVENT', 'Cultural Event', 'CULTURAL', NULL, TRUE, TRUE, TRUE, '2026-11-03T18:30:12.827787+00:00'::timestamptz, '2026-11-03T18:30:12.827787+00:00'::timestamptz),
  (7, 'TECHNICAL_EVENT', 'Technical Event', 'TECHNICAL', NULL, TRUE, TRUE, TRUE, '2026-11-03T18:30:12.827787+00:00'::timestamptz, '2026-11-03T18:30:12.827787+00:00'::timestamptz),
  (8, 'COMPETITION', 'Competition', 'COMPETITION', NULL, TRUE, TRUE, TRUE, '2026-11-03T18:30:12.827787+00:00'::timestamptz, '2026-11-03T18:30:12.827787+00:00'::timestamptz),
  (9, 'CERTIFICATION', 'Certification', 'CERTIFICATION', NULL, FALSE, TRUE, TRUE, '2026-11-03T18:30:12.827787+00:00'::timestamptz, '2026-11-03T18:30:12.827787+00:00'::timestamptz),
  (10, 'CLUB_ACTIVITY', 'Club Activity', 'CLUB', NULL, TRUE, TRUE, TRUE, '2026-11-03T18:30:12.827787+00:00'::timestamptz, '2026-11-03T18:30:12.827787+00:00'::timestamptz),
  (11, 'NSS_ACTIVITY', 'NSS Activity', 'NSS', NULL, TRUE, TRUE, TRUE, '2026-11-03T18:30:12.827787+00:00'::timestamptz, '2026-11-03T18:30:12.827787+00:00'::timestamptz),
  (12, 'NCC_ACTIVITY', 'NCC Activity', 'NCC', NULL, TRUE, TRUE, TRUE, '2026-11-03T18:30:12.827787+00:00'::timestamptz, '2026-11-03T18:30:12.827787+00:00'::timestamptz),
  (13, 'COMMUNITY_SERVICE', 'Community / Social Service', 'COMMUNITY_SERVICE', NULL, TRUE, TRUE, TRUE, '2026-11-03T18:30:12.827787+00:00'::timestamptz, '2026-11-03T18:30:12.827787+00:00'::timestamptz),
  (14, 'ENTREPRENEURSHIP', 'Entrepreneurship Activity', 'ENTREPRENEURSHIP', NULL, TRUE, TRUE, TRUE, '2026-11-03T18:30:12.827787+00:00'::timestamptz, '2026-11-03T18:30:12.827787+00:00'::timestamptz),
  (15, 'INNOVATION', 'Innovation / Prototype Activity', 'INNOVATION', NULL, TRUE, TRUE, TRUE, '2026-11-03T18:30:12.827787+00:00'::timestamptz, '2026-11-03T18:30:12.827787+00:00'::timestamptz),
  (16, 'OTHER', 'Other Student Activity', 'OTHER', NULL, FALSE, TRUE, TRUE, '2026-11-03T18:30:12.827787+00:00'::timestamptz, '2026-11-03T18:30:12.827787+00:00'::timestamptz)
ON CONFLICT DO NOTHING;
INSERT INTO public.cocurricular_category (cocurricular_category_id, category_code, category_name, is_active) VALUES
  (1, 'TECHNICAL_EVENT', 'Technical Event', TRUE),
  (2, 'HACKATHON', 'Hackathon', TRUE),
  (3, 'PROJECT_EXHIBITION', 'Project Exhibition', TRUE),
  (4, 'ACADEMIC_COMPETITION', 'Academic Competition', TRUE),
  (5, 'MENTORING_EVENT', 'Mentoring Event', TRUE),
  (6, 'JUDGING', 'Judging / Evaluation', TRUE),
  (7, 'COMMITTEE_ACTIVITY', 'Committee Activity', TRUE),
  (8, 'OTHER', 'Other Co-Curricular Activity', TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO public.extracurricular_category (extracurricular_category_id, category_code, category_name, is_active) VALUES
  (1, 'SPORTS', 'Sports', TRUE),
  (2, 'CULTURAL', 'Cultural Activity', TRUE),
  (3, 'SOCIAL_SERVICE', 'Social Service', TRUE),
  (4, 'NSS', 'NSS Activity', TRUE),
  (5, 'NCC', 'NCC Activity', TRUE),
  (6, 'CLUB', 'Club Activity', TRUE),
  (7, 'PROFESSIONAL_SOCIETY', 'Professional Society Activity', TRUE),
  (8, 'COMMUNITY_OUTREACH', 'Community Outreach', TRUE),
  (9, 'INSTITUTIONAL_ACTIVITY', 'Institutional Activity', TRUE),
  (10, 'COMPETITION', 'Competition', TRUE),
  (11, 'OTHER', 'Other Extra-Curricular Activity', TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO public.certificate_type (certificate_type_id, certificate_code, certificate_name, is_active) VALUES
  (1, 'BONAFIDE', 'Bonafide certificate', TRUE),
  (2, 'CHARACTER', 'Character certificate', TRUE),
  (3, 'NO_DUES', 'No-dues certificate', TRUE),
  (4, 'MIGRATION', 'Migration certificate', TRUE),
  (5, 'STUDY', 'Study certificate', TRUE)
ON CONFLICT DO NOTHING;
