import { NextResponse, type NextRequest } from 'next/server';
import { isPublicPath, refreshSession } from '@/lib/supabase/middleware';

/**
 * Request proxy (Next.js 16's replacement for `middleware.ts`).
 *
 * Two jobs:
 *  1. Refresh the Supabase session cookies so a signed-in user is not signed out
 *     because their access token expired while the tab was open.
 *  2. Keep unauthenticated visitors out of the application. The pages themselves
 *     also call `requireContext()`, so this is defence in depth: the redirect
 *     happens before the page renders rather than after.
 */
export async function proxy(request: NextRequest) {
  const { response, user } = await refreshSession(request);
  const { pathname } = request.nextUrl;

  if (!user && !isPublicPath(pathname)) {
    const url = request.nextUrl.clone();
    url.pathname = '/login';
    url.search = '';
    url.searchParams.set('next', pathname + request.nextUrl.search);
    return NextResponse.redirect(url);
  }

  return response;
}

export const config = {
  // Skip Next.js internals and static assets: the proxy must never block CSS, JS or images.
  matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp|ico|woff2?)$).*)'],
};
