import type { SupabaseClient } from '@supabase/supabase-js';
import { emptyExtras, type AccountExtras } from './types';

/**
 * Server-side reads for the fee tables that have no list function.
 *
 * `fin_*` covers every write and most reads; the assessment, item, refund and
 * adjustment tables are read straight from the database, where RLS decides which
 * rows the caller may see. Nothing here filters rows for authorisation.
 */

export type ReadResult<T> = { rows: T[]; error: string | null };

/** Read the rows of a fee table that belong to one student account. */
export async function readAccountRows<T extends Record<string, unknown>>(
  supabase: SupabaseClient,
  table: string,
  columns: string,
  accountId: number,
  options: { order?: { column: string; ascending?: boolean }; limit?: number } = {},
): Promise<ReadResult<T>> {
  try {
    let q = supabase.from(table).select(columns).eq('student_account_id', accountId);
    if (options.order) q = q.order(options.order.column, { ascending: options.order.ascending ?? true });
    if (options.limit) q = q.limit(options.limit);
    const { data, error } = await q;
    if (error) return { rows: [], error: error.message };
    return { rows: (data ?? []) as unknown as T[], error: null };
  } catch (e) {
    return { rows: [], error: e instanceof Error ? e.message : 'The rows could not be read.' };
  }
}

/** Read the fee items that belong to a set of assessments. */
export async function readAssessmentItems<T extends Record<string, unknown>>(
  supabase: SupabaseClient,
  assessmentIds: number[],
): Promise<ReadResult<T>> {
  if (assessmentIds.length === 0) return { rows: [], error: null };
  try {
    const { data, error } = await supabase
      .from('student_fee_assessment_item')
      .select('*')
      .in('fee_assessment_id', assessmentIds);
    if (error) return { rows: [], error: error.message };
    return { rows: (data ?? []) as T[], error: null };
  } catch (e) {
    return { rows: [], error: e instanceof Error ? e.message : 'The fee items could not be read.' };
  }
}

/** Normalise the `fin_account_extras` payload: a missing section is simply empty. */
export function normaliseExtras(raw: unknown): AccountExtras {
  const base = emptyExtras();
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return base;
  const o = raw as Record<string, unknown>;
  const list = (key: string): Record<string, unknown>[] =>
    Array.isArray(o[key]) ? (o[key] as Record<string, unknown>[]) : [];
  const can = (o.can && typeof o.can === 'object' && !Array.isArray(o.can) ? o.can : {}) as Record<string, unknown>;
  const flag = (key: string) => can[key] === true;

  return {
    benefits: list('benefits') as AccountExtras['benefits'],
    adjustments: list('adjustments') as AccountExtras['adjustments'],
    instalments: list('instalments') as AccountExtras['instalments'],
    penalties: list('penalties') as AccountExtras['penalties'],
    can: {
      benefit_create: flag('benefit_create'),
      benefit_approve: flag('benefit_approve'),
      benefit_apply: flag('benefit_apply'),
      adjust_create: flag('adjust_create'),
      adjust_approve: flag('adjust_approve'),
      assess_create: flag('assess_create'),
      assess_update: flag('assess_update'),
    },
  };
}
