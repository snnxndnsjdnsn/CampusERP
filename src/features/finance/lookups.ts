import type { SupabaseClient } from '@supabase/supabase-js';
import { safeRows } from '@/features/shared/server-rpc';
import type { Option } from './types';

/**
 * Lookup lists for the fee screens.
 *
 * `section_lookup_options` serves the shared reference lists (fee types, payment
 * modes, plans, concessions, …). The institutional lists are read straight from
 * their tables, where RLS decides which rows the caller may see. Nothing here
 * filters rows for authorisation — only retired entries are left out of a form.
 */

export type LookupResult = { options: Option[]; error: string | null };

/** Read one of the shared reference lists through `section_lookup_options`. */
export async function lookupOptions(supabase: SupabaseClient, table: string): Promise<LookupResult> {
  const { rows, error } = await safeRows<{ id: number; label: string }>(supabase, 'section_lookup_options', {
    p_table: table,
  });
  return {
    options: rows.map((r) => ({ id: Number(r.id), label: String(r.label ?? '') })),
    error,
  };
}

export type TableLookup = {
  /** The table to read. */
  table: string;
  /** The primary key column. */
  idColumn: string;
  /** The column that carries the label. */
  labelColumn: string;
  /** Extra columns to read alongside the two above. */
  extraColumns?: string[];
  /** Only return rows whose `is_active` column is not false. */
  activeOnly?: boolean;
};

/** Read an institutional lookup table directly, through its RLS policy. */
export async function tableOptions(supabase: SupabaseClient, lookup: TableLookup): Promise<LookupResult> {
  const columns = [lookup.idColumn, lookup.labelColumn, ...(lookup.extraColumns ?? [])].join(', ');
  try {
    const { data, error } = await supabase
      .from(lookup.table)
      .select(columns)
      .order(lookup.labelColumn, { ascending: true })
      .limit(500);
    if (error) return { options: [], error: error.message };

    const rows = (data ?? []) as unknown as Record<string, unknown>[];
    const visible = lookup.activeOnly ? rows.filter((r) => r.is_active !== false) : rows;
    return {
      options: visible.map((r) => ({
        id: Number(r[lookup.idColumn]),
        label: String(r[lookup.labelColumn] ?? ''),
      })),
      error: null,
    };
  } catch (e) {
    return { options: [], error: e instanceof Error ? e.message : 'The lookup could not be read.' };
  }
}
