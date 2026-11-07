import type { SupabaseClient } from '@supabase/supabase-js';
import { rpcJson, rpcRows, selectRows } from '@/lib/api';

/**
 * Read helpers that never throw.
 *
 * A page must render even when the database returns nothing (or refuses the
 * read), so every read returns `{ data, error }` and the page decides how to
 * show the failure. RLS still decides *which* rows come back — nothing here
 * filters rows for authorisation.
 */

export type ReadResult<T> = { data: T[]; error: string | null };

export type ReadOptions = {
  order?: { column: string; ascending?: boolean };
  limit?: number;
};

export function errorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}

/** Read a table through RLS. */
export async function readTable<T extends Record<string, unknown>>(
  supabase: SupabaseClient,
  table: string,
  columns = '*',
  options: ReadOptions = {},
): Promise<ReadResult<T>> {
  try {
    const data = await selectRows<T>(supabase, table, columns, options);
    return { data, error: null };
  } catch (error) {
    return { data: [], error: errorMessage(error) };
  }
}

/** Call a `RETURNS TABLE(...)` function. */
export async function readRpcRows<T extends Record<string, unknown>>(
  supabase: SupabaseClient,
  fn: string,
  args: Record<string, unknown> = {},
): Promise<ReadResult<T>> {
  try {
    const data = await rpcRows<T>(supabase, fn, args);
    return { data, error: null };
  } catch (error) {
    return { data: [], error: errorMessage(error) };
  }
}

/** Call a `RETURNS jsonb` / scalar function. */
export async function readRpcJson<T>(
  supabase: SupabaseClient,
  fn: string,
  args: Record<string, unknown> = {},
): Promise<{ data: T | null; error: string | null }> {
  try {
    const data = await rpcJson<T>(supabase, fn, args);
    return { data, error: null };
  } catch (error) {
    return { data: null, error: errorMessage(error) };
  }
}
