-- =============================================================================================
-- 011. evidence_and_seed_data
-- ---------------------------------------------------------------------------------------------
-- GENERATED FILE - do not edit by hand.
-- Regenerate with: npm run migrate:build   (python tools/translate.py && python tools/build_migrations.py)
--
-- Source of truth: the live Supabase catalogue (tools/catalogue/live_catalogue.json),
-- dumped read-only from project khqqfgqvwdxlqkncwtmh by tools/dump_catalogue.py.
-- =============================================================================================

-- -----------------------------------------------------------------------------
-- Seed rows for the tables of module 'evidence and seed data'.
-- Only the rows the live database really contains are emitted; every
-- statement carries explicit primary keys and is idempotent.
-- -----------------------------------------------------------------------------
-- MySQL module 19: STAFF PROFILE REFERENCE / MASTER DATA
-- MySQL module 34: DOCUMENT/EVIDENCE REQUIREMENT CONFIGURATION

INSERT INTO public.evidence_type (evidence_type_id, evidence_type_code, evidence_type_name, description, is_active) VALUES
  (1, 'PUBLISHED_PAPER', 'Published Paper PDF', NULL, TRUE),
  (2, 'FIRST_PAGE', 'First Page of Publication', NULL, TRUE),
  (3, 'JOURNAL_COVER', 'Journal Cover Page', NULL, TRUE),
  (4, 'TABLE_OF_CONTENTS', 'Table of Contents', NULL, TRUE),
  (5, 'DOI_PROOF', 'DOI Proof', NULL, TRUE),
  (6, 'INDEXING_PROOF', 'Indexing Proof', NULL, TRUE),
  (7, 'ACCEPTANCE_LETTER', 'Acceptance Letter', NULL, TRUE),
  (8, 'PUBLICATION_CERTIFICATE', 'Publication Certificate', NULL, TRUE),
  (9, 'CONFERENCE_PAPER', 'Conference Paper', NULL, TRUE),
  (10, 'PROCEEDINGS_COPY', 'Proceedings Copy', NULL, TRUE),
  (11, 'PRESENTATION_CERTIFICATE', 'Presentation Certificate', NULL, TRUE),
  (12, 'PARTICIPATION_CERTIFICATE', 'Participation Certificate', NULL, TRUE),
  (13, 'COMPLETION_CERTIFICATE', 'Completion Certificate', NULL, TRUE),
  (14, 'RESOURCE_PERSON_CERTIFICATE', 'Resource Person Certificate', NULL, TRUE),
  (15, 'REGISTRATION_PROOF', 'Registration Proof', NULL, TRUE),
  (16, 'AWARD_CERTIFICATE', 'Award / Best Paper Certificate', NULL, TRUE),
  (17, 'BROCHURE', 'Program / Conference Brochure', NULL, TRUE),
  (18, 'PHOTOGRAPH', 'Photograph', NULL, TRUE),
  (19, 'INVITATION_LETTER', 'Invitation Letter', NULL, TRUE),
  (20, 'ATTENDANCE_PROOF', 'Attendance Proof', NULL, TRUE),
  (21, 'TRAINING_MATERIAL', 'Training Material', NULL, TRUE),
  (22, 'INTERNSHIP_OFFER', 'Internship Offer Letter', NULL, TRUE),
  (23, 'INTERNSHIP_CERTIFICATE', 'Internship Certificate', NULL, TRUE),
  (24, 'INDUSTRY_EVALUATION', 'Industry Evaluation', NULL, TRUE),
  (25, 'INTERNSHIP_REPORT', 'Internship Report', NULL, TRUE),
  (26, 'STIPEND_PROOF', 'Stipend / Incentive Proof', NULL, TRUE),
  (27, 'MOU_AGREEMENT', 'MoU / Agreement', NULL, TRUE),
  (28, 'RESEARCH_PROPOSAL', 'Research Proposal', NULL, TRUE),
  (29, 'SUBMISSION_ACK', 'Proposal Submission Acknowledgement', NULL, TRUE),
  (30, 'APPROVAL_LETTER', 'Approval Letter', NULL, TRUE),
  (31, 'SANCTION_LETTER', 'Sanction Letter', NULL, TRUE),
  (32, 'FUNDING_ORDER', 'Funding Order', NULL, TRUE),
  (33, 'PROGRESS_REPORT', 'Progress Report', NULL, TRUE),
  (34, 'UTILIZATION_CERTIFICATE', 'Utilization Certificate', NULL, TRUE),
  (35, 'STATEMENT_EXPENDITURE', 'Statement of Expenditure', NULL, TRUE),
  (36, 'AUDITED_STATEMENT', 'Audited Financial Statement', NULL, TRUE),
  (37, 'PROJECT_COMPLETION_REPORT', 'Project Completion Report', NULL, TRUE),
  (38, 'OUTCOME_REPORT', 'Outcome Report', NULL, TRUE),
  (39, 'WORK_ORDER', 'Work Order', NULL, TRUE),
  (40, 'PURCHASE_ORDER', 'Purchase Order', NULL, TRUE),
  (41, 'INVOICE', 'Invoice', NULL, TRUE),
  (42, 'PAYMENT_PROOF', 'Payment Proof', NULL, TRUE),
  (43, 'CLIENT_FEEDBACK', 'Client Feedback', NULL, TRUE),
  (44, 'CONSULTANCY_REPORT', 'Consultancy Report', NULL, TRUE),
  (45, 'APPRECIATION_CERTIFICATE', 'Appreciation Certificate', NULL, TRUE),
  (46, 'APPOINTMENT_ORDER', 'Appointment / Order Letter', NULL, TRUE),
  (47, 'CITATION', 'Citation', NULL, TRUE),
  (48, 'AWARD_LETTER', 'Award Letter', NULL, TRUE),
  (49, 'MEDIA_EVIDENCE', 'Newspaper / Media Evidence', NULL, TRUE),
  (50, 'MEMBERSHIP_CERTIFICATE', 'Membership Certificate / Card', NULL, TRUE),
  (51, 'RENEWAL_DOCUMENT', 'Renewal Document', NULL, TRUE),
  (52, 'REVIEWER_CERTIFICATE', 'Reviewer Certificate', NULL, TRUE),
  (53, 'EDITORIAL_BOARD_CERTIFICATE', 'Editorial Board Certificate', NULL, TRUE),
  (54, 'ACKNOWLEDGEMENT_LETTER', 'Acknowledgement Letter', NULL, TRUE),
  (55, 'OFFICIAL_ORDER', 'Official Order', NULL, TRUE),
  (56, 'OTHER_SUPPORTING', 'Other Supporting Evidence', NULL, TRUE),
  (57, 'STUDENT_PARTICIPATION_CERTIFICATE', 'Student Participation Certificate', NULL, TRUE),
  (58, 'STUDENT_ACHIEVEMENT_CERTIFICATE', 'Student Achievement / Winner Certificate', NULL, TRUE),
  (59, 'STUDENT_MEDAL_PROOF', 'Medal / Sports Achievement Proof', NULL, TRUE),
  (60, 'STUDENT_SCORE_SHEET', 'Competition Score / Result Sheet', NULL, TRUE),
  (61, 'STUDENT_EVENT_PHOTO', 'Student Event Photograph', NULL, TRUE),
  (62, 'STUDENT_HACKATHON_RESULT', 'Hackathon Result / Ranking Proof', NULL, TRUE),
  (63, 'STUDENT_PRESENTATION_PROOF', 'Presentation / Paper Presentation Proof', NULL, TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO public.activity_type (activity_type_id, activity_type_code, activity_type_name, activity_group, description, is_active) VALUES
  (1, 'JOURNAL_PUBLICATION', 'Journal Publication', 'PUBLICATION', NULL, TRUE),
  (2, 'CONFERENCE_PUBLICATION', 'Conference Publication', 'CONFERENCE', NULL, TRUE),
  (3, 'CONFERENCE_PRESENTATION', 'Conference Presentation', 'CONFERENCE', NULL, TRUE),
  (4, 'WORKSHOP', 'Workshop', 'PROFESSIONAL_DEVELOPMENT', NULL, TRUE),
  (5, 'FDP', 'Faculty Development Programme', 'PROFESSIONAL_DEVELOPMENT', NULL, TRUE),
  (6, 'STTP', 'Short-Term Training Programme', 'PROFESSIONAL_DEVELOPMENT', NULL, TRUE),
  (7, 'TRAINING', 'Training Programme', 'PROFESSIONAL_DEVELOPMENT', NULL, TRUE),
  (8, 'FACULTY_INTERNSHIP', 'Faculty / Industry Internship', 'INTERNSHIP', NULL, TRUE),
  (9, 'RESEARCH_PROPOSAL', 'Research Proposal', 'RESEARCH', NULL, TRUE),
  (10, 'FUNDED_RESEARCH_PROJECT', 'Funded Research Project', 'RESEARCH', NULL, TRUE),
  (11, 'CONSULTANCY', 'Consultancy Assignment', 'CONSULTANCY', NULL, TRUE),
  (12, 'INDUSTRY_SPONSORED_PROJECT', 'Industry-Sponsored Project', 'CONSULTANCY', NULL, TRUE),
  (13, 'CO_CURRICULAR', 'Co-Curricular Activity', 'CO_CURRICULAR', NULL, TRUE),
  (14, 'EXTRA_CURRICULAR', 'Extra-Curricular Activity', 'EXTRA_CURRICULAR', NULL, TRUE),
  (15, 'AWARD_RECOGNITION', 'Award / Honour / Recognition', 'AWARD', NULL, TRUE),
  (16, 'PROFESSIONAL_MEMBERSHIP', 'Professional Membership / Academic Body', 'MEMBERSHIP', NULL, TRUE),
  (17, 'ACADEMIC_PROFESSIONAL_CONTRIBUTION', 'Academic / Professional Contribution', 'ACADEMIC_PROFESSIONAL_CONTRIBUTION', NULL, TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO public.approval_status (approval_status_id, status_code, status_name, is_terminal, is_active) VALUES
  (1, 'DRAFT', 'Draft', FALSE, TRUE),
  (2, 'SUBMITTED', 'Submitted', FALSE, TRUE),
  (3, 'UNDER_REVIEW', 'Under Review', FALSE, TRUE),
  (4, 'APPROVED', 'Approved', TRUE, TRUE),
  (5, 'REJECTED', 'Rejected', TRUE, TRUE),
  (6, 'ARCHIVED', 'Archived', TRUE, TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO public.verification_status (verification_status_id, status_code, status_name, is_terminal, is_active) VALUES
  (1, 'NOT_SUBMITTED', 'Not Submitted', FALSE, TRUE),
  (2, 'PENDING', 'Pending Verification', FALSE, TRUE),
  (3, 'UNDER_VERIFICATION', 'Under Verification', FALSE, TRUE),
  (4, 'VERIFIED', 'Verified', TRUE, TRUE),
  (5, 'REJECTED', 'Rejected', TRUE, TRUE),
  (6, 'NEEDS_CORRECTION', 'Needs Correction', FALSE, TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO public.confidentiality_level (confidentiality_level_id, level_code, level_name, display_order, is_active) VALUES
  (1, 'PUBLIC', 'Public', 10, TRUE),
  (2, 'INTERNAL', 'Internal', 20, TRUE),
  (3, 'RESTRICTED', 'Restricted', 30, TRUE),
  (4, 'CONFIDENTIAL', 'Confidential', 40, TRUE),
  (5, 'HIGHLY_CONFIDENTIAL', 'Highly Confidential', 50, TRUE)
ON CONFLICT DO NOTHING;
INSERT INTO public.event_mode (event_mode_id, mode_code, mode_name, is_active) VALUES
  (1, 'ONLINE', 'Online', TRUE),
  (2, 'OFFLINE', 'Offline', TRUE),
  (3, 'HYBRID', 'Hybrid', TRUE)
ON CONFLICT DO NOTHING;
