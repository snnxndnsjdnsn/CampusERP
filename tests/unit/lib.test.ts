import { describe, expect, it } from 'vitest';
import { parseContext, type SimsContext } from '@/lib/context';
import { isPublicPath } from '@/lib/supabase/middleware';
import { NAV_GROUPS, NAV_ITEMS, visibleNav, visibleNavGroups } from '@/lib/nav';
import { safeNextPath } from '@/lib/utils';
import { forgotSchema, loginSchema, newPasswordSchema, sanitizeSearch, studentListParams } from '@/lib/validation';

const ctx = (modules: string[]) =>
  parseContext({ user_id: 1, username: 'u', email: null, student_id: null, employee_id: null, roles: [], readable_modules: modules })!;

describe('validation', () => {
  it('login requires a valid email and a password', () => {
    expect(loginSchema.safeParse({ email: 'a@b.co', password: 'x' }).success).toBe(true);
    expect(loginSchema.safeParse({ email: 'nope', password: 'x' }).success).toBe(false);
    expect(loginSchema.safeParse({ email: 'a@b.co', password: '' }).success).toBe(false);
    expect(forgotSchema.safeParse({ email: '' }).success).toBe(false);
  });
  it('new password enforces strength and confirmation', () => {
    expect(newPasswordSchema.safeParse({ password: 'Abcdefghi1', confirm: 'Abcdefghi1' }).success).toBe(true);
    expect(newPasswordSchema.safeParse({ password: 'short1A', confirm: 'short1A' }).success).toBe(false);
    expect(newPasswordSchema.safeParse({ password: 'alllowercase1', confirm: 'alllowercase1' }).success).toBe(false);
    expect(newPasswordSchema.safeParse({ password: 'Abcdefghi1', confirm: 'Different1A' }).success).toBe(false);
  });
  it('search sanitiser strips filter-significant characters', () => {
    expect(sanitizeSearch('a,b)(c%d*e"f\\g')).toBe('abcdefg');
    expect(sanitizeSearch("x'; drop table student;--")).toBe('x drop table student--');
    expect(sanitizeSearch(undefined)).toBe('');
    expect(sanitizeSearch('a'.repeat(200))).toHaveLength(80);
  });
  it('student list params fall back to safe defaults', () => {
    const p = studentListParams.parse({ page: '-3', sort: 'password_hash', dir: 'sideways', q: 'Ann,Lee' });
    expect(p).toEqual({ page: 1, sort: 'display_name', dir: 'asc', q: 'AnnLee' });
    expect(studentListParams.parse({ page: '3', sort: 'student_number', dir: 'desc' }).page).toBe(3);
  });
});

describe('redirect safety and routing', () => {
  it('only same-site relative redirects are allowed', () => {
    expect(safeNextPath('/students?page=2')).toBe('/students?page=2');
    for (const bad of ['//evil.com', 'https://evil.com', '/\\evil.com', 'javascript:alert(1)', '', null, undefined]) {
      expect(safeNextPath(bad as string | null | undefined)).toBe('/dashboard');
    }
  });
  it('public paths are exactly login/reset/auth', () => {
    for (const p of ['/login', '/forgot-password', '/reset-password', '/auth/callback']) expect(isPublicPath(p)).toBe(true);
    for (const p of ['/', '/dashboard', '/students', '/loginx', '/settings']) expect(isPublicPath(p)).toBe(false);
  });
});

describe('navigation visibility', () => {
  const hrefs = (c: SimsContext) => visibleNav(c).map((i) => i.href);
  const groupIds = (c: SimsContext) => visibleNavGroups(c).map((g) => g.id);
  const groupOf = (c: SimsContext, href: string) =>
    visibleNavGroups(c).find((g) => g.items.some((i) => i.href === href))?.id;
  /**
   * Asserts exact membership AND order: `expected` is re-ordered through NAV_ITEMS
   * (NAV_GROUPS flattened), so both an extra/missing href and any drift from the
   * canonical module-group order fail.
   */
  const expectVisible = (c: SimsContext, label: string, expected: string[]) => {
    expect(NAV_ITEMS.map((i) => i.href), `${label}: expectation must use real nav hrefs`).toEqual(
      expect.arrayContaining(expected),
    );
    expect(hrefs(c), label).toEqual(NAV_ITEMS.map((i) => i.href).filter((h) => expected.includes(h)));
  };
  /** Exact group membership AND order, verified against the canonical NAV_GROUPS order. */
  const expectGroups = (c: SimsContext, label: string, expected: string[]) => {
    expect(groupIds(c), label).toEqual(expected);
    const canonical = NAV_GROUPS.map((g) => g.id);
    const positions = expected.map((id) => canonical.indexOf(id));
    expect(positions.every((p) => p >= 0), `${label}: unknown group id in expectation`).toBe(true);
    expect(positions, `${label}: groups out of NAV_GROUPS order`).toEqual([...positions].sort((a, b) => a - b));
  };

  it('hides module pages the user cannot read, keeps universal pages', () => {
    // one scenario per schema module; groups are the numbered sidebar sections
    const scenarios: Array<{ modules: string[]; hrefs: string[]; groups: string[] }> = [
      { modules: [], hrefs: ['/dashboard', '/announcements', '/settings'], groups: ['overview', 'communication', 'account'] },
      { modules: ['STUDENT'], hrefs: ['/dashboard', '/students', '/announcements', '/activities', '/settings'], groups: ['overview', 'people', 'communication', 'activities', 'account'] },
      { modules: ['EMPLOYEE'], hrefs: ['/dashboard', '/employees', '/announcements', '/settings'], groups: ['overview', 'people', 'communication', 'account'] },
      { modules: ['ACADEMIC_CALENDAR', 'CURRICULUM'], hrefs: ['/dashboard', '/calendar', '/curriculum', '/courses', '/announcements', '/settings'], groups: ['overview', 'calendar', 'curriculum', 'communication', 'account'] },
      { modules: ['ATTENDANCE'], hrefs: ['/dashboard', '/attendance', '/announcements', '/settings'], groups: ['overview', 'attendance', 'communication', 'account'] },
      { modules: ['REGISTRATION'], hrefs: ['/dashboard', '/registration', '/announcements', '/settings'], groups: ['overview', 'registration', 'communication', 'account'] },
      { modules: ['ADMISSION'], hrefs: ['/dashboard', '/admissions', '/announcements', '/settings'], groups: ['overview', 'admission', 'communication', 'account'] },
      { modules: ['INSTITUTION'], hrefs: ['/dashboard', '/structure', '/announcements', '/settings'], groups: ['overview', 'institution', 'communication', 'account'] },
      { modules: ['ASSESSMENT'], hrefs: ['/dashboard', '/assessment', '/announcements', '/settings'], groups: ['overview', 'assessment', 'communication', 'account'] },
      { modules: ['TIMETABLE'], hrefs: ['/dashboard', '/timetable', '/announcements', '/settings'], groups: ['overview', 'teaching', 'communication', 'account'] },
      { modules: ['GRIEVANCE'], hrefs: ['/dashboard', '/grievances', '/announcements', '/settings'], groups: ['overview', 'support', 'communication', 'account'] },
      { modules: ['MENTORING'], hrefs: ['/dashboard', '/mentoring', '/announcements', '/settings'], groups: ['overview', 'support', 'communication', 'account'] },
      { modules: ['FEEDBACK'], hrefs: ['/dashboard', '/feedback', '/announcements', '/settings'], groups: ['overview', 'feedback', 'communication', 'account'] },
      { modules: ['FEES'], hrefs: ['/dashboard', '/announcements', '/finance', '/settings'], groups: ['overview', 'communication', 'finance', 'account'] }, // FEES-only: just Overview + announcements + finance + Account
      { modules: ['RESULT'], hrefs: ['/dashboard', '/assessment', '/results', '/announcements', '/settings'], groups: ['overview', 'assessment', 'communication', 'account'] }, // /assessment accepts ASSESSMENT or RESULT
    ];
    for (const s of scenarios) {
      const c = ctx(s.modules);
      expectVisible(c, `modules=${s.modules.join(',') || '(none)'}`, s.hrefs);
      expectGroups(c, `modules=${s.modules.join(',') || '(none)'}`, s.groups);
    }
  });
  it('links a student to their own pages inside the right groups, whatever modules they read', () => {
    const c = { ...ctx([]), student_id: 5 };
    // "My results" and "My documents" are for linked students only, whatever modules they can read
    expectVisible(c, 'student, no modules', [
      '/dashboard', '/my-results', '/grievances', '/certificates', '/requests', '/my-documents', '/announcements', '/activities', '/settings',
    ]);
    expectGroups(c, 'student, no modules', ['overview', 'assessment', 'support', 'documents', 'communication', 'activities', 'account']);
    expect(groupOf(c, '/my-results'), 'My results belongs to the assessment group').toBe('assessment');
    expect(groupOf(c, '/grievances'), 'grievances reach students via identity').toBe('support');
    expect(groupOf(c, '/certificates'), 'documents reach students via identity').toBe('documents');
  });
  it('shows employees their own HR records in the HR group', () => {
    const c = { ...ctx([]), employee_id: 7 };
    expectVisible(c, 'employee, no modules', ['/dashboard', '/announcements', '/my-hr', '/settings']); // employees reach their own HR records
    expectGroups(c, 'employee, no modules', ['overview', 'communication', 'hr', 'account']);
    expect(groupOf(c, '/my-hr'), 'My HR records belongs to the hr group').toBe('hr');
  });
  it('shows every nav item to a fully-provisioned student employee, in group order', () => {
    const c = {
      ...ctx(['STUDENT', 'ADMISSION', 'REGISTRATION', 'ATTENDANCE', 'TIMETABLE', 'ASSESSMENT', 'RESULT', 'GRIEVANCE', 'MENTORING', 'FEEDBACK', 'FEES', 'EMPLOYEE', 'INSTITUTION', 'ACADEMIC_CALENDAR', 'CURRICULUM', 'IAM', 'AUDIT', 'STAFF_PROFILE', 'DOCUMENT']),
      student_id: 5,
      employee_id: 7,
    };
    expect(hrefs(c)).toEqual(NAV_ITEMS.map((i) => i.href));
    expect(groupIds(c)).toEqual(NAV_GROUPS.map((g) => g.id));
    expect(hrefs(c).length).toBe(NAV_ITEMS.length); // no duplicates introduced by grouping
  });
  it('parseContext rejects malformed payloads', () => {
    expect(parseContext(null)).toBeNull();
    expect(parseContext({ user_id: 'x' })).toBeNull();
  });
});
