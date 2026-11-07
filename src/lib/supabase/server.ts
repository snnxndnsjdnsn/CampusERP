import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { assertSupabaseEnv } from '@/lib/env';

/**
 * A Supabase client bound to the request's cookies.
 *
 * The cookie jar is read-only in a Server Component, so `setAll` swallows writes
 * there; the session refresh happens in the proxy/middleware layer instead.
 */
export async function createClient() {
  const { url, key } = assertSupabaseEnv();
  const cookieStore = await cookies();
  return createServerClient(url, key, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          for (const { name, value, options } of cookiesToSet) {
            cookieStore.set(name, value, options);
          }
        } catch {
          // Server Components cannot set cookies; the proxy layer refreshes the session.
        }
      },
    },
  });
}
