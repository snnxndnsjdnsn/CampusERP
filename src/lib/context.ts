/**
 * The caller's identity, as resolved by the database.
 *
 * `my_context()` is the single source of truth: it is SECURITY DEFINER, it reads
 * `auth.uid()` from the verified JWT, and it resolves the identity map, the active
 * role assignments, the effective permissions and the readable module list.
 * The application never derives permissions on its own.
 */

export type SimsRole = {
  role_code: string;
  role_name: string;
  scope_type: string;
  institution_id: number | null;
  campus_id: number | null;
  department_id: number | null;
  programme_id: number | null;
};

export type SimsContext = {
  user_id: number;
  username: string;
  email: string | null;
  /** Set when the account is linked to a student record. */
  student_id: number | null;
  /** Set when the account is linked to an employee record. */
  employee_id: number | null;
  /** True when the caller's role demands an authenticator app that is not set up yet. */
  mfa_setup_required: boolean;
  roles: SimsRole[];
  /** Distinct first segments of the caller's `*.READ` permission codes, e.g. `STUDENT`. */
  readable_modules: string[];
  /** Every effective `MODULE.RESOURCE.ACTION` grant (SELF-scoped grants excluded). */
  permissions: string[];
};

/** Narrow an unknown JSON payload from an RPC into a SimsContext. */
export function parseContext(raw: unknown): SimsContext | null {
  if (!raw || typeof raw !== 'object') return null;
  const o = raw as Record<string, unknown>;
  if (typeof o.user_id !== 'number') return null;
  const num = (v: unknown): number | null => (typeof v === 'number' ? v : null);
  const roles = Array.isArray(o.roles)
    ? (o.roles as Record<string, unknown>[]).map((r) => ({
        role_code: String(r.role_code ?? ''),
        role_name: String(r.role_name ?? ''),
        scope_type: String(r.scope_type ?? ''),
        institution_id: num(r.institution_id),
        campus_id: num(r.campus_id),
        department_id: num(r.department_id),
        programme_id: num(r.programme_id),
      }))
    : [];
  return {
    user_id: o.user_id,
    username: String(o.username ?? ''),
    email: typeof o.email === 'string' ? o.email : null,
    student_id: num(o.student_id),
    employee_id: num(o.employee_id),
    mfa_setup_required: o.mfa_setup_required === true,
    roles,
    readable_modules: Array.isArray(o.readable_modules) ? o.readable_modules.map(String) : [],
    permissions: Array.isArray(o.permissions) ? o.permissions.map(String) : [],
  };
}

/** True when the caller holds the given permission code (exact match). */
export function can(ctx: SimsContext, permission: string): boolean {
  return ctx.permissions.includes(permission);
}

/** True when the caller holds any of the given permission codes. */
export function canAny(ctx: SimsContext, ...permissions: string[]): boolean {
  return permissions.some((p) => ctx.permissions.includes(p));
}

/** True when the caller can read the given module (the sidebar's visibility rule). */
export function canReadModule(ctx: SimsContext, module: string): boolean {
  return ctx.readable_modules.includes(module);
}
