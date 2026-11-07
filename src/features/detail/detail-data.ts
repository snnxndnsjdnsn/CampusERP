import type { SupabaseClient } from '@supabase/supabase-js';

/**
 * Detail-screen data helpers.
 *
 * These live in their own folder because the detail screens need one thing the
 * generic helpers do not offer: a read that is filtered by a primary key.
 * The filter is applied by the database (through RLS), never in JavaScript, so
 * a caller can only ever receive a row the database already allows.
 */

export type SafeResult<T> = { data: T | null; error: string | null };

/**
 * Read one row by primary key.
 *
 * Returns `{ data: null }` when the row does not exist or the caller may not
 * see it - the two cases are deliberately indistinguishable.
 */
export async function safeSelectOne<T extends Record<string, unknown>>(
  supabase: SupabaseClient,
  table: string,
  idColumn: string,
  id: number,
  columns = '*',
): Promise<SafeResult<T>> {
  try {
    const { data, error } = await supabase.from(table).select(columns).eq(idColumn, id).maybeSingle();
    if (error) return { data: null, error: error.message };
    return { data: (data as T | null) ?? null, error: null };
  } catch (e) {
    return { data: null, error: e instanceof Error ? e.message : 'The record could not be read.' };
  }
}

/**
 * Read the rows of a child table that belong to one parent.
 *
 * The filter is a foreign-key equality, so the database still decides which
 * rows are visible.
 */
export async function safeSelectWhere<T extends Record<string, unknown>>(
  supabase: SupabaseClient,
  table: string,
  column: string,
  value: number,
  columns = '*',
  options: { order?: { column: string; ascending?: boolean }; limit?: number } = {},
): Promise<{ rows: T[]; error: string | null }> {
  try {
    let q = supabase.from(table).select(columns).eq(column, value);
    if (options.order) q = q.order(options.order.column, { ascending: options.order.ascending ?? true });
    if (options.limit) q = q.limit(options.limit);
    const { data, error } = await q;
    if (error) return { rows: [], error: error.message };
    return { rows: (data ?? []) as unknown as T[], error: null };
  } catch (e) {
    return { rows: [], error: e instanceof Error ? e.message : 'The records could not be read.' };
  }
}
