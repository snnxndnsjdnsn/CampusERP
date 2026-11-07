import type { SupabaseClient } from '@supabase/supabase-js';

/**
 * Thin, typed wrappers around the database's RPC surface.
 *
 * Every read and write in this application goes through a `public.*` function.
 * The database is the authorisation boundary: RLS and the SECURITY DEFINER helpers
 * decide what a caller may see, so the client never filters rows itself.
 */

export type RpcArgs = Record<string, unknown>;

export class RpcError extends Error {
  constructor(
    readonly fn: string,
    readonly message: string,
    readonly code?: string,
  ) {
    super(`${fn}: ${message}`);
    this.name = 'RpcError';
  }
}

/** Call a function that returns a single JSON value (`jsonb` / `scalar`). */
export async function rpcJson<T>(supabase: SupabaseClient, fn: string, args: RpcArgs = {}): Promise<T> {
  const { data, error } = await supabase.rpc(fn, args);
  if (error) throw new RpcError(fn, error.message, error.code);
  return data as T;
}

/** Call a function that returns a set of rows (`RETURNS TABLE(...)`). */
export async function rpcRows<T extends Record<string, unknown>>(
  supabase: SupabaseClient,
  fn: string,
  args: RpcArgs = {},
): Promise<T[]> {
  const { data, error } = await supabase.rpc(fn, args);
  if (error) throw new RpcError(fn, error.message, error.code);
  return (data ?? []) as T[];
}

/**
 * Call a function and tolerate failure.
 *
 * Used for decorative reads (badge counts, optional panels) where a database error
 * must never take the page down.
 */
export async function rpcSafe<T>(
  supabase: SupabaseClient,
  fn: string,
  args: RpcArgs = {},
): Promise<{ data: T | null; error: string | null }> {
  const { data, error } = await supabase.rpc(fn, args);
  if (error) return { data: null, error: error.message };
  return { data: data as T, error: null };
}

/** Read a table through RLS. */
export async function selectRows<T extends Record<string, unknown>>(
  supabase: SupabaseClient,
  table: string,
  columns = '*',
  options: { order?: { column: string; ascending?: boolean }; limit?: number } = {},
): Promise<T[]> {
  let q = supabase.from(table).select(columns);
  if (options.order) q = q.order(options.order.column, { ascending: options.order.ascending ?? true });
  if (options.limit) q = q.limit(options.limit);
  const { data, error } = await q;
  if (error) throw new Error(`${table}: ${error.message}`);
  return (data ?? []) as unknown as T[];
}

/** A JSON value that may be a string, an object, or null. */
export type MaybeJson = string | Record<string, unknown> | unknown[] | null;

/** Parse a JSON column that the database may return as text or as jsonb. */
export function asJson<T>(value: MaybeJson, fallback: T): T {
  if (value === null || value === undefined) return fallback;
  if (typeof value === 'string') {
    try {
      return JSON.parse(value) as T;
    } catch {
      return fallback;
    }
  }
  return value as T;
}
