-- =============================================================================================
-- 010. staff_profile_and_research
-- ---------------------------------------------------------------------------------------------
-- GENERATED FILE - do not edit by hand.
-- Regenerate with: npm run migrate:build   (python tools/translate.py && python tools/build_migrations.py)
--
-- Source of truth: the live Supabase catalogue (tools/catalogue/live_catalogue.json),
-- dumped read-only from project khqqfgqvwdxlqkncwtmh by tools/dump_catalogue.py.
-- =============================================================================================

-- -----------------------------------------------------------------------------
-- Seed rows for the tables of module 'staff profile and research'.
-- Only the rows the live database really contains are emitted; every
-- statement carries explicit primary keys and is idempotent.
-- -----------------------------------------------------------------------------
-- MySQL module 19: STAFF PROFILE REFERENCE / MASTER DATA

INSERT INTO public.publication_type (publication_type_id, publication_type_code, publication_type_name, description, is_active, created_at, updated_at) VALUES
  (1, 'JOURNAL_ARTICLE', 'Journal Article', 'Article or paper published in a journal', TRUE, '2026-11-03T18:30:11.728312+00:00'::timestamptz, '2026-11-03T18:30:11.728312+00:00'::timestamptz),
  (2, 'CONFERENCE_PAPER', 'Conference Paper', 'Paper published in conference proceedings', TRUE, '2026-11-03T18:30:11.728312+00:00'::timestamptz, '2026-11-03T18:30:11.728312+00:00'::timestamptz),
  (3, 'BOOK_CHAPTER', 'Book Chapter', 'Chapter published in an edited book', TRUE, '2026-11-03T18:30:11.728312+00:00'::timestamptz, '2026-11-03T18:30:11.728312+00:00'::timestamptz),
  (4, 'OTHER_PUBLICATION', 'Other Publication', 'Other scholarly publication', TRUE, '2026-11-03T18:30:11.728312+00:00'::timestamptz, '2026-11-03T18:30:11.728312+00:00'::timestamptz)
ON CONFLICT DO NOTHING;
INSERT INTO public.journal_type (journal_type_id, journal_type_code, journal_type_name, description, is_active) VALUES
  (1, 'INTERNATIONAL', 'International', NULL, TRUE),
  (2, 'NATIONAL', 'National', NULL, TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO public.indexing_agency (indexing_agency_id, agency_code, agency_name, website_url, description, is_active) VALUES
  (1, 'SCOPUS', 'Scopus', NULL, NULL, TRUE),
  (2, 'WOS', 'Web of Science', NULL, NULL, TRUE),
  (3, 'SCI', 'Science Citation Index', NULL, NULL, TRUE),
  (4, 'SCIE', 'Science Citation Index Expanded', NULL, NULL, TRUE),
  (5, 'ESCI', 'Emerging Sources Citation Index', NULL, NULL, TRUE),
  (6, 'UGC_CARE', 'UGC-CARE', NULL, NULL, TRUE),
  (7, 'PUBMED', 'PubMed', NULL, NULL, TRUE),
  (8, 'DOAJ', 'Directory of Open Access Journals', NULL, NULL, TRUE),
  (9, 'IEEE_XPLORE', 'IEEE Xplore', NULL, NULL, TRUE),
  (10, 'DBLP', 'DBLP', NULL, NULL, TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO public.metric_type (metric_type_id, metric_code, metric_name, description, is_active) VALUES
  (1, 'IMPACT_FACTOR', 'Impact Factor', NULL, TRUE),
  (2, 'CITESCORE', 'CiteScore', NULL, TRUE),
  (3, 'SJR', 'SCImago Journal Rank', NULL, TRUE),
  (4, 'SNIP', 'Source Normalized Impact per Paper', NULL, TRUE),
  (5, 'H_INDEX', 'H-Index', NULL, TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO public.funding_type (funding_type_id, funding_type_code, funding_type_name, is_external, description, is_active) VALUES
  (1, 'INTERNAL', 'Internal Funding', FALSE, NULL, TRUE),
  (2, 'EXTERNAL', 'External Funding', TRUE, NULL, TRUE),
  (3, 'INDUSTRY', 'Industry Funding', TRUE, NULL, TRUE),
  (4, 'GOVERNMENT', 'Government Funding', TRUE, NULL, TRUE),
  (5, 'CENTRAL_GOVERNMENT', 'Central Government Funding', TRUE, NULL, TRUE),
  (6, 'STATE_GOVERNMENT', 'State Government Funding', TRUE, NULL, TRUE),
  (7, 'CSR', 'Corporate Social Responsibility Funding', TRUE, NULL, TRUE),
  (8, 'UNIVERSITY', 'University Funding', FALSE, NULL, TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO public.research_status (research_status_id, status_code, status_name, display_order, is_terminal, is_active) VALUES
  (1, 'DRAFT', 'Draft', 10, FALSE, TRUE),
  (2, 'SUBMITTED', 'Submitted', 20, FALSE, TRUE),
  (3, 'UNDER_REVIEW', 'Under Review', 30, FALSE, TRUE),
  (4, 'APPROVED', 'Approved', 40, FALSE, TRUE),
  (5, 'SANCTIONED', 'Sanctioned', 50, FALSE, TRUE),
  (6, 'REJECTED', 'Rejected', 60, TRUE, TRUE),
  (7, 'ONGOING', 'Ongoing', 70, FALSE, TRUE),
  (8, 'COMPLETED', 'Completed', 80, TRUE, TRUE),
  (9, 'CLOSED', 'Closed', 90, TRUE, TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO public.training_program_type (training_program_type_id, type_code, type_name, description, is_active) VALUES
  (1, 'WORKSHOP', 'Workshop', NULL, TRUE),
  (2, 'FDP', 'Faculty Development Programme', NULL, TRUE),
  (3, 'STTP', 'Short-Term Training Programme', NULL, TRUE),
  (4, 'REFRESHER', 'Refresher Course', NULL, TRUE),
  (5, 'ORIENTATION', 'Orientation Programme', NULL, TRUE),
  (6, 'CERTIFICATION', 'Certification Programme', NULL, TRUE),
  (7, 'INDUSTRIAL_TRAINING', 'Industrial Training', NULL, TRUE),
  (8, 'PROFESSIONAL_TRAINING', 'Professional Training', NULL, TRUE),
  (9, 'OTHER', 'Other Training Programme', NULL, TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO public.membership_type (membership_type_id, type_code, type_name, is_active) VALUES
  (1, 'MEMBER', 'Member', TRUE),
  (2, 'LIFE_MEMBER', 'Life Member', TRUE),
  (3, 'FELLOW', 'Fellow', TRUE),
  (4, 'SENIOR_MEMBER', 'Senior Member', TRUE),
  (5, 'ASSOCIATE_MEMBER', 'Associate Member', TRUE),
  (6, 'HONORARY_MEMBER', 'Honorary Member', TRUE),
  (7, 'OFFICE_BEARER', 'Office Bearer', TRUE),
  (8, 'OTHER', 'Other Membership', TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO public.award_category (award_category_id, category_code, category_name, is_active) VALUES
  (1, 'ACADEMIC', 'Academic Award', TRUE),
  (2, 'RESEARCH', 'Research Award', TRUE),
  (3, 'TEACHING', 'Teaching Award', TRUE),
  (4, 'PROFESSIONAL', 'Professional Award', TRUE),
  (5, 'SERVICE', 'Service Recognition', TRUE),
  (6, 'SPORTS', 'Sports Award', TRUE),
  (7, 'CULTURAL', 'Cultural Award', TRUE),
  (8, 'OTHER', 'Other Award', TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO public.conference_contribution_type (conference_contribution_type_id, type_code, type_name, is_active) VALUES
  (1, 'PAPER_PRESENTATION', 'Paper Presentation', TRUE),
  (2, 'POSTER_PRESENTATION', 'Poster Presentation', TRUE),
  (3, 'PAPER_PUBLICATION', 'Paper Publication', TRUE),
  (4, 'PARTICIPATION', 'Participation', TRUE),
  (5, 'INVITED_TALK', 'Invited Talk', TRUE),
  (6, 'KEYNOTE', 'Keynote Address', TRUE),
  (7, 'SESSION_CHAIR', 'Session Chair', TRUE),
  (8, 'CONFERENCE_CHAIR', 'Conference Chair', TRUE),
  (9, 'OTHER', 'Other Contribution', TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO public.professional_contribution_type (professional_contribution_type_id, contribution_code, contribution_name, description, is_active) VALUES
  (1, 'JOURNAL_REVIEWER', 'Journal Reviewer', NULL, TRUE),
  (2, 'CONFERENCE_REVIEWER', 'Conference Reviewer', NULL, TRUE),
  (3, 'JOURNAL_EDITOR', 'Journal Editor', NULL, TRUE),
  (4, 'EDITORIAL_BOARD', 'Editorial Board Member', NULL, TRUE),
  (5, 'CONFERENCE_CHAIR', 'Conference Chair', NULL, TRUE),
  (6, 'SESSION_CHAIR', 'Session Chair', NULL, TRUE),
  (7, 'BOARD_OF_STUDIES', 'Board of Studies Member', NULL, TRUE),
  (8, 'ACADEMIC_COUNCIL', 'Academic Council Member', NULL, TRUE),
  (9, 'EXAMINATION_DUTY', 'Examination Duty', NULL, TRUE),
  (10, 'QUESTION_PAPER_SETTING', 'Question Paper Setting', NULL, TRUE),
  (11, 'PHD_SUPERVISION', 'Ph.D. Research Supervision', NULL, TRUE),
  (12, 'PG_SUPERVISION', 'PG Research Supervision', NULL, TRUE),
  (13, 'INVITED_TALK', 'Invited Talk', NULL, TRUE),
  (14, 'GUEST_LECTURE', 'Guest Lecture', NULL, TRUE),
  (15, 'RESOURCE_PERSON', 'Resource Person Activity', NULL, TRUE),
  (16, 'MENTORING', 'Mentoring', NULL, TRUE),
  (17, 'CURRICULUM_DEVELOPMENT', 'Curriculum Development', NULL, TRUE),
  (18, 'INSTITUTIONAL_COMMITTEE', 'Institutional Committee', NULL, TRUE),
  (19, 'OTHER', 'Other Professional Contribution', NULL, TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO public.participation_level (participation_level_id, level_code, level_name, display_order, is_active) VALUES
  (1, 'DEPARTMENT', 'Department', 10, TRUE),
  (2, 'INSTITUTE', 'Institute', 20, TRUE),
  (3, 'UNIVERSITY', 'University', 30, TRUE),
  (4, 'REGIONAL', 'Regional', 40, TRUE),
  (5, 'STATE', 'State', 50, TRUE),
  (6, 'NATIONAL', 'National', 60, TRUE),
  (7, 'INTERNATIONAL', 'International', 70, TRUE)
ON CONFLICT DO NOTHING;
