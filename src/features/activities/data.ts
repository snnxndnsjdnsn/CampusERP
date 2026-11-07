import type { SupabaseClient } from '@supabase/supabase-js';
import { readTable } from '@/features/shared/reads';
import type { ActivityTypeRow, Option, StudentOption } from './types';

/**
 * Server-side lookups for the student activities module.
 *
 * The activity types come from their own table; the reference lists come from
 * the shared tables, where RLS decides which rows the caller may see. Nothing
 * here filters rows to hide data — a list that cannot be read comes back empty.
 */

export type LookupResult = { options: Option[]; error: string | null };

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

/** The activity types a student may record. */
export async function readActivityTypes(
  supabase: SupabaseClient,
): Promise<{ rows: ActivityTypeRow[]; error: string | null }> {
  const { data, error } = await readTable<Record<string, unknown>>(
    supabase,
    'student_activity_type',
    'student_activity_type_id, type_code, type_name, activity_group, description, requires_team_details, supports_achievement, is_active',
    { order: { column: 'type_name', ascending: true }, limit: 500 },
  );
  if (error) return { rows: [], error };

  return {
    rows: data.map((t) => ({
      student_activity_type_id: Number(t.student_activity_type_id),
      type_code: String(t.type_code ?? ''),
      type_name: String(t.type_name ?? ''),
      activity_group: String(t.activity_group ?? ''),
      description: t.description === null || t.description === undefined ? null : String(t.description),
      requires_team_details: t.requires_team_details === true,
      supports_achievement: t.supports_achievement !== false,
      is_active: t.is_active !== false,
    })),
    error: null,
  };
}

/**
 * The students the caller may read.
 *
 * The student table is protected by `STUDENT.ALL.READ`, so a student account
 * sees nothing here — the form then falls back to "yourself".
 */
export async function readStudents(
  supabase: SupabaseClient,
): Promise<{ rows: StudentOption[]; error: string | null }> {
  const { data, error } = await readTable<Record<string, unknown>>(
    supabase,
    'student',
    'student_id, student_number, display_name',
    { order: { column: 'display_name', ascending: true }, limit: 500 },
  );
  if (error) return { rows: [], error };

  return {
    rows: data.map((s) => ({
      student_id: Number(s.student_id),
      student_number: String(s.student_number ?? ''),
      display_name: String(s.display_name ?? ''),
    })),
    error: null,
  };
}
