import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';
import { assertSupabaseEnv } from '@/lib/env';

/**
 * Paths that may be reached without a session.
 *
 * These are the authentication screens themselves plus the OAuth callback. Every
 * other path requires a signed-in user; the proxy redirects to `/login` otherwise.
 */
const PUBLIC_PATHS = new Set(['/login', '/forgot-password', '/reset-password', '/auth/callback']);

/** True when the path may be reached without signing in. */
export function isPublicPath(pathname: string): boolean {
  return PUBLIC_PATHS.has(pathname);
}

/**
 * Refresh the Supabase session cookies and return the response plus the current user.
 *
 * The caller (the proxy/middleware entry point) writes the refreshed cookies onto
 * the response and continues with it. Keeping the logic here means the entry point
 * is a thin, version-specific shim.
 */
export async function refreshSession(request: NextRequest): Promise<{ response: NextResponse; user: { id: string } | null }> {
  let response = NextResponse.next({ request });
  const { url, key } = assertSupabaseEnv();
  const supabase = createServerClient(url, key, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet) {
        for (const { name, value } of cookiesToSet) {
          request.cookies.set(name, value);
        }
        response = NextResponse.next({ request });
        for (const { name, value, options } of cookiesToSet) {
          response.cookies.set(name, value, options);
        }
      },
    },
  });
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return { response, user };
}
