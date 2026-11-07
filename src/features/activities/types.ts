/**
 * Shapes returned by the `student_activity_*` functions.
 *
 * The database owns every field: the application reads what the functions hand
 * back and never derives a value the database did not supply.
 */

export type Option = { id: number; label: string };

export type ActivityTypeRow = {
  student_activity_type_id: number;
  type_code: string;
  type_name: string;
  activity_group: string;
  description: string | null;
  requires_team_details: boolean;
  supports_achievement: boolean;
  is_active: boolean;
};

export type StudentActivityRow = {
  student_activity_id: number;
  student_id: number;
  student_number: string;
  student_name: string;
  type_name: string;
  activity_title: string;
  achievement_type: string | null;
  start_date: string | null;
  verification_status: string;
  approval_status: string;
  evidence_count: number;
  total_count: number;
};

export type ActivityReportRow = {
  type_name: string;
  approval_status: string;
  activities: number;
  winners: number;
};

export type StudentOption = {
  student_id: number;
  student_number: string;
  display_name: string;
};

export type TeamMember = {
  member_id: number;
  name: string;
  is_student: boolean;
  role: string | null;
  is_lead: boolean;
};

export type EvidenceRow = {
  evidence_id: number;
  title: string;
  evidence_type: string | null;
  version: number;
  file_name: string | null;
  size: number | null;
  issued: string | null;
  authority: string | null;
  certificate_number: string | null;
};

export type StudentActivityDetail = {
  student_activity_id: number;
  student_id: number;
  student_number: string;
  student_name: string;
  student_activity_type_id: number;
  type_name: string;
  requires_team_details: boolean;
  academic_year_id: number | null;
  participation_level_id: number | null;
  event_mode_id: number | null;
  organizer_name: string | null;
  activity_title: string;
  event_name: string | null;
  team_name: string | null;
  participation_role: string | null;
  start_date: string | null;
  end_date: string | null;
  venue_name: string | null;
  city: string | null;
  achievement_type: string;
  position_rank: number | null;
  award_name: string | null;
  activity_url: string | null;
  description: string | null;
  outcomes: string | null;
  verification_status: string;
  verification_remarks: string | null;
  approval_status: string;
  approval_remarks: string | null;
  rejection_reason: string | null;
  is_owner: boolean;
  can_edit: boolean;
  can_delete: boolean;
  can_verify: boolean;
  can_approve: boolean;
  team: TeamMember[];
  evidence: EvidenceRow[];
};

/** The achievement values the database accepts. */
export const ACHIEVEMENT_TYPES = [
  'PARTICIPATION',
  'WINNER',
  'RUNNER_UP',
  'FIRST_PLACE',
  'SECOND_PLACE',
  'THIRD_PLACE',
  'MERIT',
  'SPECIAL_MENTION',
  'QUALIFIED',
  'FINALIST',
  'MEDAL_GOLD',
  'MEDAL_SILVER',
  'MEDAL_BRONZE',
  'RECOGNITION',
  'OTHER',
] as const;

/** The approval states an activity moves through. */
export const APPROVAL_STATUSES = ['DRAFT', 'SUBMITTED', 'UNDER_REVIEW', 'APPROVED', 'REJECTED'] as const;

/** The file types the database accepts for evidence. */
export const MIME_TYPES = [
  { value: 'application/pdf', label: 'PDF document' },
  { value: 'image/jpeg', label: 'JPEG image' },
  { value: 'image/png', label: 'PNG image' },
] as const;
