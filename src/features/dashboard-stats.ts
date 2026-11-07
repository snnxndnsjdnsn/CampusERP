import type { SupabaseClient } from '@supabase/supabase-js';
import { rpcSafe } from '@/lib/api';
import type { SimsContext } from '@/lib/context';

/**
 * Dashboard statistics.
 *
 * Every number comes from a database function so that RLS decides what the caller
 * may see: a faculty member sees their own department's counts, a student sees
 * their own attendance and results, and a registrar sees the whole institution.
 */

export type StatusCount = { label: string; n: number };

export type DashboardStats = {
  /** Counts grouped by a workflow status (applications, registrations, sessions…). */
  applications: StatusCount[];
  registrations: StatusCount[];
  sessions: StatusCount[];
  termResults: StatusCount[];
  employees: { employment_type: string; employment_status: string; n: number }[];
  enrolments: { programme_id: number; label: string; enrolment_status: string; n: number }[];
  feeCollection: { month: string; collected: number; payments: number }[];
  feeOutstanding: { payable: number; paid: number; balance: number; overdue_assessments: number } | null;
};

export type StudentDashboard = {
  attendance: {
    course: string;
    section_id: number;
    conducted: number;
    present: number;
    percentage: number | null;
  }[];
  today: { course: string; start: string | null; end: string | null; room: string | null }[];
  results: unknown[];
};

function toCounts(rows: { application_status?: string; registration_status?: string; session_status?: string; result_status?: string; n: number }[], key: string): StatusCount[] {
  return rows.map((r) => ({ label: String((r as Record<string, unknown>)[key] ?? 'UNKNOWN'), n: Number(r.n) }));
}

/**
 * Load the administrative dashboard figures.
 *
 * Each call is independent and tolerant: a module the caller cannot read simply
 * contributes nothing instead of failing the whole page.
 */
export async function loadDashboardStats(supabase: SupabaseClient): Promise<DashboardStats> {
  const [apps, regs, sessions, results, employees, enrolments, feeCollection, feeOutstanding] = await Promise.all([
    rpcSafe(supabase, 'dash_applications'),
    rpcSafe(supabase, 'dash_registrations'),
    rpcSafe(supabase, 'dash_sessions', { p_days: 30 }),
    rpcSafe(supabase, 'dash_term_results'),
    rpcSafe(supabase, 'dash_employees'),
    rpcSafe(supabase, 'dash_enrolments'),
    rpcSafe(supabase, 'dash_fee_collection', { p_months: 6 }),
    rpcSafe(supabase, 'dash_fee_outstanding'),
  ]);

  return {
    applications: toCounts((apps.data ?? []) as never[], 'application_status'),
    registrations: toCounts((regs.data ?? []) as never[], 'registration_status'),
    sessions: toCounts((sessions.data ?? []) as never[], 'session_status'),
    termResults: toCounts((results.data ?? []) as never[], 'result_status'),
    employees: (employees.data ?? []) as DashboardStats['employees'],
    enrolments: (enrolments.data ?? []) as DashboardStats['enrolments'],
    feeCollection: ((feeCollection.data ?? []) as { month: string; collected: number; payments: number }[]).map((r) => ({
      month: String(r.month),
      collected: Number(r.collected ?? 0),
      payments: Number(r.payments ?? 0),
    })),
    feeOutstanding: (feeOutstanding.data ?? null) as DashboardStats['feeOutstanding'],
  };
}

/** Load the student-facing dashboard figures (attendance, today's classes, results). */
export async function loadStudentDashboard(supabase: SupabaseClient): Promise<StudentDashboard> {
  const { data } = await rpcSafe<Record<string, unknown>>(supabase, 'my_dashboard');
  const d = (data ?? {}) as Record<string, unknown>;
  return {
    attendance: (d.attendance ?? []) as StudentDashboard['attendance'],
    today: (d.today ?? []) as StudentDashboard['today'],
    results: (d.results ?? []) as unknown[],
  };
}

/** Load the caller's own published term results. */
export async function loadMyResults(supabase: SupabaseClient) {
  const { data } = await rpcSafe<unknown[]>(supabase, 'my_results');
  return data ?? [];
}

/** Load the caller's own profile summary. */
export async function loadMyProfile(supabase: SupabaseClient) {
  const { data } = await rpcSafe<Record<string, unknown>>(supabase, 'my_profile');
  return (data ?? { kind: 'none' }) as { kind: string; name?: string; number?: string; primary_email?: string; primary_phone?: string };
}

/** Load the caller's notifications. */
export async function loadNotifications(supabase: SupabaseClient) {
  const { data } = await rpcSafe<{ notif_key: string; kind: string; title: string; body: string; href: string; at: string }[]>(
    supabase,
    'my_notifications',
    { p_limit: 50 },
  );
  return data ?? [];
}

/** The modules the caller may read, sorted, for the dashboard's module summary. */
export function readableModuleList(ctx: SimsContext): string[] {
  return [...ctx.readable_modules].sort();
}
