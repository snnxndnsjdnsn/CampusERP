'use client';

import { createBrowserClient } from '@supabase/ssr';
import { assertSupabaseEnv } from '@/lib/env';

/** Browser-side Supabase client. Used for client components and server actions. */
export function createClient() {
  const { url, key } = assertSupabaseEnv();
  return createBrowserClient(url, key);
}
