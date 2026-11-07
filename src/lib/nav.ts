import type { SimsContext } from '@/lib/context';
import { STAFF_SECTIONS } from '@/lib/staff-sections';

export type NavItem = {
  href: string;
  label: string;
  /**
   * access_module code(s); undefined = always shown to any signed-in, provisioned user.
   * An array = shown if the user can read ANY of them (the page authorises either module).
   */
  module?: string | string[];
  /** shown only to a signed-in student (linked student record) */
  studentOnly?: boolean;
  /** shown only to a signed-in employee (linked employee record) */
  employeeOnly?: boolean;
  /** also shown to a linked student even without the module (the feature authorises students by identity) */
  alsoStudent?: boolean;
};

/** A sidebar section. Groups follow the schema's numbered module structure (see SIMS-DatabaseWithoutLessonPlan.sql). */
export type NavGroup = {
  id: string;
  label: string;
  items: NavItem[];
  /**
   * Sub-modules of the group's screen, drawn indented under it.
   *
   * A child is a module of the schema that has no screen of its own but does
   * have an address inside its parent's screen - the staff-profile research
   * modules 20 to 34 are the example.
   */
  children?: NavItem[];
};

/**
 * Canonical grouped navigation, ordered exactly like the database's numbered modules
 * (1..17, 19, 40) with unnumbered Overview/Account bookends. Only pages that actually
 * exist belong here. Visibility is a convenience; RLS is the enforcement.
 *
 * Schema modules 20 to 34 are the staff-profile research sub-modules. They have
 * no screen of their own, so they hang off the `staff` group as children rather
 * than becoming groups of their own.
 */
export const NAV_GROUPS: NavGroup[] = [
  {
    id: 'overview',
    label: 'Overview',
    items: [{ href: '/dashboard', label: 'Dashboard' }],
  },
  {
    id: 'reference',
    label: '1 · Common reference',
    // schema module 1 is reference data; the administration UI needs IAM.ALL.CONFIGURE
    items: [{ href: '/admin/reference', label: 'Reference data', module: 'IAM' }],
  },
  {
    id: 'institution',
    label: '2 · Institution structure',
    items: [{ href: '/structure', label: 'Institution structure', module: 'INSTITUTION' }],
  },
  {
    id: 'calendar',
    label: '3 · Academic calendar',
    items: [{ href: '/calendar', label: 'Academic calendar', module: 'ACADEMIC_CALENDAR' }],
  },
  {
    id: 'curriculum',
    label: '4 · Curriculum & courses',
    items: [
      { href: '/curriculum', label: 'Curriculum', module: 'CURRICULUM' },
      { href: '/courses', label: 'Courses', module: 'CURRICULUM' },
    ],
  },
  {
    id: 'people',
    label: '5 · Students & staff',
    items: [
      { href: '/students', label: 'Students', module: 'STUDENT' },
      { href: '/employees', label: 'Employees', module: 'EMPLOYEE' },
    ],
  },
  {
    id: 'admission',
    label: '6 · Admissions',
    items: [{ href: '/admissions', label: 'Admissions', module: 'ADMISSION' }],
  },
  {
    id: 'registration',
    label: '7 · Registration',
    items: [{ href: '/registration', label: 'Registration', module: 'REGISTRATION' }],
  },
  {
    id: 'teaching',
    label: '8 · Teaching & timetable',
    items: [{ href: '/timetable', label: 'Timetable', module: 'TIMETABLE' }],
  },
  {
    id: 'attendance',
    label: '9 · Attendance',
    items: [{ href: '/attendance', label: 'Attendance', module: 'ATTENDANCE' }],
  },
  {
    id: 'assessment',
    label: '10 · Assessment & results',
    items: [
      { href: '/assessment', label: 'Assessment', module: ['ASSESSMENT', 'RESULT'] }, // the page allows either module
      { href: '/results', label: 'Results', module: 'RESULT' },
      { href: '/my-results', label: 'My results', studentOnly: true },
    ],
  },
  {
    id: 'feedback',
    label: '11 · Feedback',
    items: [{ href: '/feedback', label: 'Feedback', module: 'FEEDBACK' }],
  },
  {
    id: 'support',
    label: '12 · Mentoring & grievance',
    items: [
      { href: '/mentoring', label: 'Mentoring', module: 'MENTORING' },
      { href: '/grievances', label: 'Grievances', module: 'GRIEVANCE', alsoStudent: true },
    ],
  },
  {
    id: 'documents',
    label: '13 · Documents & certificates',
    items: [
      { href: '/certificates', label: 'Certificates', module: 'DOCUMENT', alsoStudent: true },
      { href: '/requests', label: 'Hall ticket and graduation', module: 'DOCUMENT', alsoStudent: true },
      { href: '/my-documents', label: 'My documents', studentOnly: true },
    ],
  },
  {
    id: 'communication',
    label: '14 · Communication',
    // the announcement feed is intentionally visible to every signed-in user; do not gate it
    items: [{ href: '/announcements', label: 'Announcements' }],
  },
  {
    id: 'iam',
    label: '15 · Access & audit',
    items: [
      { href: '/admin/users', label: 'Users and roles', module: 'IAM' },
      { href: '/audit', label: 'Audit log', module: 'AUDIT' },
    ],
  },
  {
    id: 'hr',
    label: '16 · Employee HR',
    items: [{ href: '/my-hr', label: 'My HR records', employeeOnly: true }],
  },
  {
    id: 'finance',
    label: '17 · Fees & finance',
    items: [{ href: '/finance', label: 'Fees', module: 'FEES' }],
  },
  {
    id: 'staff',
    label: '19 · Staff profile & research',
    items: [{ href: '/staff-profile', label: 'Staff profile', module: 'STAFF_PROFILE' }],
    // Schema modules 20 to 34 - the research sub-modules. Each is an address
    // inside this screen, not a screen of its own.
    children: STAFF_SECTIONS.map((s) => ({
      href: `/staff-profile/${s.slug}`,
      label: `${s.module} · ${s.title}`,
      module: 'STAFF_PROFILE',
    })),
  },
  {
    id: 'activities',
    label: '40 · Student activities',
    items: [{ href: '/activities', label: 'Activities', module: 'STUDENT', alsoStudent: true }],
  },
  {
    id: 'account',
    label: 'Account',
    items: [{ href: '/settings', label: 'Settings' }],
  },
];

/** Flat back-compat view of every nav item, in group order. */
export const NAV_ITEMS: NavItem[] = NAV_GROUPS.flatMap((g) => [...g.items, ...(g.children ?? [])]);

function itemVisible(i: NavItem, ctx: SimsContext, mods: ReadonlySet<string>): boolean {
  if (i.studentOnly) return ctx.student_id !== null;
  if (i.employeeOnly) return ctx.employee_id !== null;
  if (!i.module) return true;
  const readable = Array.isArray(i.module) ? i.module.some((m) => mods.has(m)) : mods.has(i.module);
  return readable || (i.alsoStudent === true && ctx.student_id !== null);
}

/** Visible groups (empty groups dropped), item order preserved within each group. */
export function visibleNavGroups(ctx: SimsContext): NavGroup[] {
  const mods = new Set(ctx.readable_modules);
  const out: NavGroup[] = [];
  for (const g of NAV_GROUPS) {
    const items = g.items.filter((i) => itemVisible(i, ctx, mods));
    const children = g.children?.filter((i) => itemVisible(i, ctx, mods));
    if (items.length > 0) out.push({ ...g, items, ...(children && children.length > 0 ? { children } : {}) });
  }
  return out;
}

export function visibleNav(ctx: SimsContext): NavItem[] {
  return visibleNavGroups(ctx).flatMap((g) => [...g.items, ...(g.children ?? [])]);
}

export function primaryRoleLabel(ctx: SimsContext): string {
  return ctx.roles[0]?.role_name ?? 'No active role';
}

/** Breadcrumb-only parent fallback for routes that have no nav item of their own. */
export const NAV_PARENTS: Record<string, string> = { '/admin/mfa-policy': '/admin/users' };
