'use client';

import { Suspense, useState } from 'react';
import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { Button } from '@/components/ui/button';
import { Input, Label } from '@/components/ui/input';
import { createClient } from '@/lib/supabase/client';
import { loginSchema } from '@/lib/validation';
import { safeNextPath } from '@/lib/utils';

/**
 * The sign-in card.
 *
 * `useSearchParams()` opts a route out of static prerendering, so the part of
 * the page that reads the query string lives behind a Suspense boundary and
 * the card itself is rendered as the fallback.
 */
function LoginCard({ next }: { next: string }) {
  const router = useRouter();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function onSubmit(event: React.FormEvent) {
    event.preventDefault();
    setError(null);

    const parsed = loginSchema.safeParse({ email, password });
    if (!parsed.success) {
      setError(parsed.error.issues[0]?.message ?? 'Check the form and try again.');
      return;
    }

    setBusy(true);
    const supabase = createClient();
    const { error: signInError } = await supabase.auth.signInWithPassword(parsed.data);
    if (signInError) {
      setError(signInError.message);
      setBusy(false);
      return;
    }
    router.replace(next);
    router.refresh();
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-muted/40 p-6">
      <div className="w-full max-w-sm rounded-lg border border-border bg-card p-6 shadow-sm">
        <h1 className="text-lg font-semibold tracking-tight">SIMS</h1>
        <p className="mt-1 text-sm text-muted-foreground">Sign in to continue.</p>

        <form onSubmit={onSubmit} className="mt-6 space-y-4" noValidate>
          <div className="space-y-1.5">
            <Label htmlFor="email">Email</Label>
            <Input
              id="email"
              name="email"
              type="email"
              autoComplete="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="password">Password</Label>
            <Input
              id="password"
              name="password"
              type="password"
              autoComplete="current-password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
          </div>

          {error && (
            <p className="rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800" role="alert">
              {error}
            </p>
          )}

          <Button type="submit" className="w-full" disabled={busy}>
            {busy ? 'Signing in…' : 'Sign in'}
          </Button>
        </form>

        <p className="mt-4 text-sm">
          <Link href="/forgot-password" className="text-primary underline-offset-4 hover:underline">
            Forgot your password?
          </Link>
        </p>
      </div>
    </div>
  );
}

/** Reads the `next` query parameter and hands it to the card. */
function LoginForm() {
  const params = useSearchParams();
  return <LoginCard next={safeNextPath(params.get('next'))} />;
}

export default function LoginPage() {
  return (
    <Suspense fallback={<LoginCard next="/dashboard" />}>
      <LoginForm />
    </Suspense>
  );
}
