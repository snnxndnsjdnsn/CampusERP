import { redirect } from 'next/navigation';
import type { SupabaseClient } from '@supabase/supabase-js';
import { parseContext, type SimsContext } from '@/lib/context';
import { createClient } from '@/lib/supabase/server';

/**
 * Resolve the caller's identity for a protected page.
 *
 * - Not signed in            -> `/login`
 * - Signed in but not mapped -> `/no-access` (the account exists in Auth but has no
 *   `user_account` row, so the database resolves no identity and every policy denies)
 */
export async function requireContext(): Promise<{ ctx: SimsContext; supabase: SupabaseClient }> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect('/login');

  const { data, error } = await supabase.rpc('my_context');
  if (error) {
    // A failed context read is a hard failure: without it we cannot authorise anything.
    throw new Error(`my_context() failed: ${error.message}`);
  }
  const ctx = parseContext(data);
  if (!ctx) redirect('/no-access');
  return { ctx, supabase };
}

/** Like `requireContext`, but returns `null` instead of redirecting. */
export async function getContext(): Promise<{ ctx: SimsContext; supabase: SupabaseClient } | null> {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;
  const { data } = await supabase.rpc('my_context');
  const ctx = parseContext(data);
  return ctx ? { ctx, supabase } : null;
}
