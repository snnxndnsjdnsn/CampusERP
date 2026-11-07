'use client';

import { useCallback, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { ErrorPanel } from '@/components/ui/empty-state';
import { Input, Label } from '@/components/ui/input';
import { createClient } from '@/lib/supabase/client';
import { formatDateTime } from '@/lib/format';

type MfaFactor = {
  id: string;
  friendly_name?: string | null;
  factor_type: string;
  status: string;
};

type RecoveryStatus = { unused: number | null; generated_at: string | null };

type Enrolment = { id: string; qr: string; secret: string };

const ISSUER = 'SIMS';

/**
 * Two-step verification panel.
 *
 * The authenticator factor itself lives in Supabase Auth (`supabase.auth.mfa.*`);
 * the database only mirrors whether MFA is enabled (`mfa_sync()`), and owns the
 * recovery codes (`mfa_recovery_status` / `mfa_recovery_generate` / `mfa_recovery_use`).
 */
export function MfaPanel() {
  const router = useRouter();
  const [factors, setFactors] = useState<MfaFactor[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [enrolment, setEnrolment] = useState<Enrolment | null>(null);
  const [challengeId, setChallengeId] = useState<string | null>(null);
  const [code, setCode] = useState('');
  const [recovery, setRecovery] = useState<RecoveryStatus>({ unused: null, generated_at: null });
  const [newCodes, setNewCodes] = useState<string[] | null>(null);
  const [recoveryCode, setRecoveryCode] = useState('');

  const refresh = useCallback(async () => {
    const supabase = createClient();
    const [factorResult, recoveryResult] = await Promise.all([
      supabase.auth.mfa.listFactors(),
      supabase.rpc('mfa_recovery_status'),
    ]);
    if (factorResult.error) {
      setError(factorResult.error.message);
    } else {
      setFactors(factorResult.data.all);
    }
    const status = recoveryResult.data as RecoveryStatus | null;
    if (status) {
      setRecovery({ unused: status.unused ?? null, generated_at: status.generated_at ?? null });
    }
    setLoading(false);
  }, []);

  useEffect(() => {
    void (async () => {
      await refresh();
    })();
  }, [refresh]);

  const sync = useCallback(async () => {
    const supabase = createClient();
    await supabase.rpc('mfa_sync');
  }, []);

  async function startEnrolment() {
    setBusy(true);
    setError(null);
    setNotice(null);
    try {
      const supabase = createClient();
      const { data, error: enrollError } = await supabase.auth.mfa.enroll({
        factorType: 'totp',
        friendlyName: 'Authenticator app',
        issuer: ISSUER,
      });
      if (enrollError) {
        setError(enrollError.message);
        return;
      }
      setEnrolment({ id: data.id, qr: data.totp.qr_code, secret: data.totp.secret });
      setChallengeId(null);
      setCode('');
    } finally {
      setBusy(false);
    }
  }

  async function verifyEnrolment() {
    if (!enrolment) return;
    setBusy(true);
    setError(null);
    try {
      const supabase = createClient();
      let challenge = challengeId;
      if (!challenge) {
        const { data, error: challengeError } = await supabase.auth.mfa.challenge({ factorId: enrolment.id });
        if (challengeError) {
          setError(challengeError.message);
          return;
        }
        challenge = data.id;
        setChallengeId(challenge);
      }
      const { error: verifyError } = await supabase.auth.mfa.verify({
        factorId: enrolment.id,
        challengeId: challenge,
        code: code.trim(),
      });
      if (verifyError) {
        setError(verifyError.message);
        return;
      }
      await sync();
      setEnrolment(null);
      setChallengeId(null);
      setCode('');
      setNotice('Authenticator connected. Two-step verification is now active.');
      await refresh();
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  async function removeFactor(factorId: string) {
    setBusy(true);
    setError(null);
    try {
      const supabase = createClient();
      const { error: unenrollError } = await supabase.auth.mfa.unenroll({ factorId });
      if (unenrollError) {
        setError(unenrollError.message);
        return;
      }
      await sync();
      setNotice('Authenticator removed.');
      await refresh();
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  async function generateRecoveryCodes() {
    setBusy(true);
    setError(null);
    setNotice(null);
    try {
      const supabase = createClient();
      const { data, error: rpcError } = await supabase.rpc('mfa_recovery_generate');
      if (rpcError) {
        setError(rpcError.message);
        return;
      }
      setNewCodes(Array.isArray(data) ? data.map(String) : []);
      setNotice('New recovery codes generated. Store them somewhere safe — they are shown once.');
      await refresh();
    } finally {
      setBusy(false);
    }
  }

  async function applyRecoveryCode() {
    setBusy(true);
    setError(null);
    setNotice(null);
    try {
      const supabase = createClient();
      const { data, error: rpcError } = await supabase.rpc('mfa_recovery_use', { p_code: recoveryCode.trim() });
      if (rpcError) {
        setError(rpcError.message);
        return;
      }
      if (data === true) {
        setRecoveryCode('');
        setNotice('Recovery code accepted. Set up a new authenticator to continue.');
        await refresh();
        router.refresh();
      } else {
        setError('That recovery code is not valid.');
      }
    } finally {
      setBusy(false);
    }
  }

  const verified = factors.filter((f) => f.status === 'verified');
  const pending = factors.filter((f) => f.status !== 'verified');

  return (
    <div className="space-y-4">
      <Card>
        <CardHeader>
          <CardTitle>Authenticator app</CardTitle>
          <CardDescription>
            Add an authenticator app (Google Authenticator, Authy, 1Password) and approve every sign-in with a
            six-digit code.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {error && <ErrorPanel message={error} />}
          {notice && (
            <p className="rounded-md border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-800">{notice}</p>
          )}

          {loading ? (
            <p className="text-sm text-muted-foreground">Checking your authenticator…</p>
          ) : verified.length > 0 ? (
            <div className="space-y-3">
              <ul className="space-y-2">
                {verified.map((f) => (
                  <li key={f.id} className="flex items-center justify-between gap-3 rounded-md border border-border p-3">
                    <div>
                      <div className="text-sm font-medium">{f.friendly_name ?? 'Authenticator app'}</div>
                      <div className="text-xs text-muted-foreground">Factor {f.id.slice(0, 8)}… · {f.factor_type}</div>
                    </div>
                    <div className="flex items-center gap-2">
                      <Badge variant="success">Verified</Badge>
                      <Button variant="outline" size="sm" disabled={busy} onClick={() => void removeFactor(f.id)}>
                        Remove
                      </Button>
                    </div>
                  </li>
                ))}
              </ul>
              {pending.length > 0 && (
                <p className="text-xs text-muted-foreground">
                  {pending.length} unverified factor{pending.length === 1 ? '' : 's'} pending. Remove them if you no longer
                  need them.
                </p>
              )}
            </div>
          ) : enrolment ? (
            <div className="space-y-4">
              <p className="text-sm text-muted-foreground">
                Scan this code with your authenticator app, then enter the six-digit code it shows.
              </p>
              {/* The QR payload is an SVG produced by Supabase Auth; it is rendered as an image, not injected as markup. */}
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={`data:image/svg+xml;utf-8,${encodeURIComponent(enrolment.qr)}`}
                alt="Authenticator setup QR code"
                className="h-48 w-48 rounded-md border border-border bg-white p-2"
              />
              <div>
                <Label htmlFor="mfa-secret">Setup key</Label>
                <p className="mt-1 font-mono text-sm break-all">{enrolment.secret}</p>
              </div>
              <div className="space-y-2">
                <Label htmlFor="mfa-code">Six-digit code</Label>
                <Input
                  id="mfa-code"
                  inputMode="numeric"
                  autoComplete="one-time-code"
                  maxLength={8}
                  value={code}
                  onChange={(e) => setCode(e.target.value)}
                  placeholder="123456"
                />
              </div>
              <div className="flex gap-2">
                <Button disabled={busy || code.trim().length < 6} onClick={() => void verifyEnrolment()}>
                  {busy ? 'Working…' : 'Verify and activate'}
                </Button>
                <Button variant="ghost" disabled={busy} onClick={() => setEnrolment(null)}>
                  Cancel
                </Button>
              </div>
            </div>
          ) : (
            <div className="space-y-3">
              <p className="text-sm text-muted-foreground">
                No authenticator is connected to this account yet.
              </p>
              <Button disabled={busy} onClick={() => void startEnrolment()}>
                {busy ? 'Working…' : 'Set up authenticator'}
              </Button>
            </div>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Recovery codes</CardTitle>
          <CardDescription>
            Recovery codes let you sign in when your phone is unavailable. Each code works once.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex flex-wrap items-center gap-3 text-sm">
            <Badge variant={recovery.unused && recovery.unused > 0 ? 'success' : 'muted'}>
              {recovery.unused === null ? 'Unknown' : `${recovery.unused} unused`}
            </Badge>
            <span className="text-muted-foreground">
              {recovery.generated_at ? `Generated ${formatDateTime(recovery.generated_at)}` : 'Never generated'}
            </span>
          </div>

          <Button variant="outline" disabled={busy} onClick={() => void generateRecoveryCodes()}>
            Generate new recovery codes
          </Button>

          {newCodes && newCodes.length > 0 && (
            <div className="rounded-md border border-border bg-muted p-3">
              <p className="mb-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
                Save these now — they are not shown again
              </p>
              <ul className="grid grid-cols-2 gap-1 font-mono text-sm">
                {newCodes.map((c) => (
                  <li key={c}>{c}</li>
                ))}
              </ul>
            </div>
          )}

          <div className="space-y-2 border-t border-border pt-4">
            <Label htmlFor="mfa-recovery-code">Lost access to your authenticator?</Label>
            <p className="text-xs text-muted-foreground">
              Enter one of your recovery codes to reset two-step verification.
            </p>
            <div className="flex flex-wrap gap-2">
              <Input
                id="mfa-recovery-code"
                value={recoveryCode}
                onChange={(e) => setRecoveryCode(e.target.value)}
                placeholder="XXXXX-XXXXX"
                className="max-w-[14rem]"
              />
              <Button variant="secondary" disabled={busy || recoveryCode.trim().length < 4} onClick={() => void applyRecoveryCode()}>
                Use code
              </Button>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}

export default MfaPanel;
