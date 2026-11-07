import type { SupabaseClient } from '@supabase/supabase-js';

/**
 * Server-side read helpers for the academic modules.
 *
 * Every read is tolerant: a module the caller may not read contributes no rows
 * instead of taking the whole page down. The database still decides what is
 * visible — these helpers never filter rows to hide data.
 */

export type SelectOptions = {
  order?: { column: string; ascending?: boolean };
  limit?: number;
  eq?: Record<string, string | number | boolean>;
  in?: Record<string, (string | number)[]>;
};

export type SafeResult<T> = { data: T[]; error: string | null };

/** Read a table through RLS without ever throwing. */
export async function safeSelect<T extends Record<string, unknown>>(
  supabase: SupabaseClient,
  table: string,
  columns = '*',
  options: SelectOptions = {},
): Promise<SafeResult<T>> {
  let q = supabase.from(table).select(columns);
  for (const [column, value] of Object.entries(options.eq ?? {})) q = q.eq(column, value);
  for (const [column, values] of Object.entries(options.in ?? {})) {
    if (values.length > 0) q = q.in(column, values);
  }
  if (options.order) q = q.order(options.order.column, { ascending: options.order.ascending ?? true });
  if (options.limit) q = q.limit(options.limit);
  const { data, error } = await q;
  if (error) return { data: [], error: error.message };
  return { data: (data ?? []) as unknown as T[], error: null };
}

/** Call a `RETURNS TABLE(...)` function without ever throwing. */
export async function safeRpcRows<T>(
  supabase: SupabaseClient,
  fn: string,
  args: Record<string, unknown> = {},
): Promise<SafeResult<T>> {
  const { data, error } = await supabase.rpc(fn, args);
  if (error) return { data: [], error: error.message };
  return { data: (data ?? []) as T[], error: null };
}

/** Build a `id -> label` lookup from a list of rows. */
export function indexBy<T>(rows: T[], key: keyof T, label: keyof T): Map<unknown, string> {
  const map = new Map<unknown, string>();
  for (const row of rows) map.set(row[key], String(row[label] ?? ''));
  return map;
}

/** ISO weekday (1 = Monday … 7 = Sunday) to a short label. */
export const DAY_LABELS: Record<number, string> = {
  1: 'Mon',
  2: 'Tue',
  3: 'Wed',
  4: 'Thu',
  5: 'Fri',
  6: 'Sat',
  7: 'Sun',
};

/** `HH:MM:SS` (a Postgres `time`) to `HH:MM`. */
export function shortTime(value: string | null | undefined): string {
  if (!value) return '—';
  const parts = value.split(':');
  const hh = parts[0] ?? '';
  const mm = parts[1] ?? '';
  if (!hh) return value;
  return mm ? `${hh}:${mm}` : hh;
}
