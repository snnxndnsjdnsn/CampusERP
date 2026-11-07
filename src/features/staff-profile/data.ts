import type { SupabaseClient } from '@supabase/supabase-js';
import { readTable } from '@/features/shared/reads';
import { safeRows } from '@/features/shared/server-rpc';
import type { ActivityTypeRow, EmployeeOption, Option } from './types';

/**
 * Server-side lookups for the staff profile screens.
 *
 * The staff module keeps its own reference lists (`staff_lookup_options`) and
 * shares the institutional ones with the rest of the application
 * (`section_lookup_options`). Both are `public.*` functions, so they carry the
 * same authorisation rules as the rest of the database.
 *
 * Nothing here filters rows to hide data: RLS and the functions decide what a
 * caller may see. A list that cannot be read simply comes back empty.
 */

export type LookupResult = { options: Option[]; error: string | null };

function toOptions(rows: { id: number; label: string }[]): Option[] {
  return rows.map((r) => ({ id: Number(r.id), label: String(r.label ?? '') }));
}

/** Read one of the staff module's own reference lists. */
export async function staffLookupOptions(supabase: SupabaseClient, table: string): Promise<LookupResult> {
  const { rows, error } = await safeRows<{ id: number; label: string }>(supabase, 'staff_lookup_options', {
    p_table: table,
  });
  return { options: toOptions(rows), error };
}

/** Read one of the shared institutional reference lists. */
export async function sectionLookupOptions(supabase: SupabaseClient, table: string): Promise<LookupResult> {
  const { rows, error } = await safeRows<{ id: number; label: string }>(supabase, 'section_lookup_options', {
    p_table: table,
  });
  return { options: toOptions(rows), error };
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
  const { data, error } = await readTable<Record<string, unknown>>(
    supabase,
    lookup.table,
    columns,
    { order: { column: lookup.labelColumn, ascending: true }, limit: 500 },
  );
  if (error) return { options: [], error };

  const visible = lookup.activeOnly ? data.filter((r) => r.is_active !== false) : data;
  return {
    options: visible.map((r) => ({
      id: Number(r[lookup.idColumn]),
      label: String(r[lookup.labelColumn] ?? ''),
    })),
    error: null,
  };
}

/** The activity types, read straight from their table through RLS. */
export async function readActivityTypes(
  supabase: SupabaseClient,
): Promise<{ rows: ActivityTypeRow[]; error: string | null }> {
  try {
    const { data, error } = await supabase
      .from('activity_type')
      .select('activity_type_id, activity_type_code, activity_type_name, activity_group, is_active')
      .order('activity_type_name', { ascending: true })
      .limit(500);
    if (error) return { rows: [], error: error.message };

    const rows = (data ?? []) as unknown as Record<string, unknown>[];
    return {
      rows: rows.map((t) => ({
        activity_type_id: Number(t.activity_type_id),
        activity_type_code: String(t.activity_type_code ?? ''),
        activity_type_name: String(t.activity_type_name ?? ''),
        activity_group: String(t.activity_group ?? ''),
        is_active: t.is_active !== false,
      })),
      error: null,
    };
  } catch (e) {
    return { rows: [], error: e instanceof Error ? e.message : 'The activity types could not be read.' };
  }
}

/** The members of staff the caller may read, through the employee RLS policy. */
export async function readEmployees(
  supabase: SupabaseClient,
): Promise<{ rows: EmployeeOption[]; error: string | null }> {
  try {
    const { data, error } = await supabase
      .from('employee')
      .select('employee_id, employee_number, display_name')
      .order('display_name', { ascending: true })
      .limit(500);
    if (error) return { rows: [], error: error.message };

    const rows = (data ?? []) as unknown as Record<string, unknown>[];
    return {
      rows: rows.map((e) => ({
        employee_id: Number(e.employee_id),
        employee_number: String(e.employee_number ?? ''),
        display_name: String(e.display_name ?? ''),
      })),
      error: null,
    };
  } catch (e) {
    return { rows: [], error: e instanceof Error ? e.message : 'The staff list could not be read.' };
  }
}
