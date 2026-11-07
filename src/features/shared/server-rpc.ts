import type { SupabaseClient } from '@supabase/supabase-js';
import { rpcSafe, selectRows } from '@/lib/api';

/**
 * Server-side read helpers.
 *
 * The database is the authorisation boundary, so a page never decides what the
 * caller may see. These wrappers simply make a refusal visible instead of
 * letting it take the whole page down: every page must render even when the
 * caller has no rows, no permission, or an empty database.
 */

export type SafeResult<T> = { data: T | null; error: string | null };

/** Call a `public.*` RPC and tolerate failure. */
export async function safeRpc<T>(supabase: SupabaseClient, fn: string, args: Record<string, unknown> = {}): Promise<SafeResult<T>> {
  const { data, error } = await rpcSafe<T>(supabase, fn, args);
  return { data: data ?? null, error };
}

/** Call a `public.*` RPC that returns rows and tolerate failure. */
export async function safeRows<T extends Record<string, unknown>>(
  supabase: SupabaseClient,
  fn: string,
  args: Record<string, unknown> = {},
): Promise<{ rows: T[]; error: string | null }> {
  const { data, error } = await rpcSafe<T[]>(supabase, fn, args);
  return { rows: data ?? [], error };
}

/** Read a lookup table through RLS and tolerate failure. */
export async function safeSelect<T extends Record<string, unknown>>(
  supabase: SupabaseClient,
  table: string,
  columns = '*',
  options: { order?: { column: string; ascending?: boolean }; limit?: number } = {},
): Promise<{ rows: T[]; error: string | null }> {
  try {
    const rows = await selectRows<T>(supabase, table, columns, options);
    return { rows, error: null };
  } catch (e) {
    return { rows: [], error: e instanceof Error ? e.message : 'The lookup could not be read.' };
  }
}

/** A simple `{ id, label }` option list. */
export type Option = { id: number; label: string };

/** Turn a table read into `{ id, label }` options. */
export function toOptions<T extends Record<string, unknown>>(rows: T[], idCol: string, labelCol: string): Option[] {
  return rows.map((r) => ({ id: Number(r[idCol]), label: String(r[labelCol] ?? '') }));
}

/** Narrow a `jsonb` payload to an object, whatever shape the driver returned it in. */
export function asJsonObject<T>(value: unknown): T | null {
  if (value === null || value === undefined) return null;
  if (typeof value === 'string') {
    try {
      const parsed = JSON.parse(value) as unknown;
      return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? (parsed as T) : null;
    } catch {
      return null;
    }
  }
  if (typeof value === 'object' && !Array.isArray(value)) return value as T;
  return null;
}

/** Narrow a `jsonb` payload to an array, whatever shape the driver returned it in. */
export function asJsonArray<T>(value: unknown): T[] {
  if (Array.isArray(value)) return value as T[];
  if (typeof value === 'string') {
    try {
      const parsed = JSON.parse(value) as unknown;
      return Array.isArray(parsed) ? (parsed as T[]) : [];
    } catch {
      return [];
    }
  }
  return [];
}
