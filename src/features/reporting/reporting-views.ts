/**
 * The reporting and search views of schema module 37.
 *
 * PostgREST cannot see `information_schema`, so the list of views the
 * database offers cannot be discovered at runtime. The names are written down
 * here instead, and every one of them is still read at runtime, so a view that
 * is missing - or that this caller may not see - is reported rather than
 * hidden.
 */

/** One reporting or search view. */
export type ReportingView = {
  /** The view name, as the database spells it. */
  name: string;
  /** One line saying what the view is for. */
  description: string;
};

/** The views, in the order the schema source introduces them. */
export const REPORTING_VIEWS: ReportingView[] = [
  {
    name: 'v_active_role_permission',
    description: 'The permissions every active role assignment grants, with the scope of each grant.',
  },
  {
    name: 'v_active_user_role',
    description: 'The roles every user currently holds, with the scope of each assignment.',
  },
  {
    name: 'v_effective_user_permission',
    description: 'The permissions a user really holds, after role grants and user overrides.',
  },
  {
    name: 'v_employee_previous_experience',
    description: 'The previous employment of every employee, for the HR profile.',
  },
  {
    name: 'v_fee_collection_summary',
    description: 'The assessed, paid and outstanding fee totals of every student account.',
  },
  {
    name: 'v_staff_activity_profile',
    description: 'The staff activity profile, joined to its type, year, organisation and statuses.',
  },
  {
    name: 'v_staff_evidence_search',
    description: 'The staff evidence documents, ready to search and filter.',
  },
  {
    name: 'v_student_activity_evidence_search',
    description: 'The student activity evidence documents, ready to search and filter.',
  },
  {
    name: 'v_student_activity_profile',
    description: 'The student activity profile, joined to its type, year, organisation and statuses.',
  },
  {
    name: 'v_student_fee_balance',
    description: 'The fee balance of every student account.',
  },
];
