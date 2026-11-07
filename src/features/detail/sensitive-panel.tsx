'use client';

import { useState } from 'react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input, Label } from '@/components/ui/input';
import { rpcCall } from '@/features/shared/client-rpc';
import { formatDate } from '@/lib/format';

/**
 * Sensitive HR identifiers.
 *
 * The database stores these encrypted and only ever returns a masked value
 * through the list function. Revealing the full number is a separate, audited
 * call that requires a stated purpose - the reason is recorded in
 * `employee_sensitive_access_audit` by the database, not by this component.
 */

export type SensitiveKind = 'PAN' | 'AADHAAR' | 'BANK_ACCOUNT';

export type SensitiveRow = {
  id: number;
  masked?: string | null;
  name?: string | null;
  holder?: string | null;
  bank?: string | null;
  branch?: string | null;
  type?: string | null;
  ifsc?: string | null;
  upi?: string | null;
  status?: string | null;
  remarks?: string | null;
  purpose?: string | null;
  issue_date?: string | null;
  updated_at?: string | null;
  is_primary?: boolean;
  is_salary?: boolean;
  account_status?: string | null;
};

export type SensitiveCan = {
  owner?: boolean;
  reveal_pan?: boolean;
  reveal_aadhaar?: boolean;
  reveal_bank?: boolean;
};

function RevealControl({
  kind,
  rowId,
  canReveal,
  isOwner,
}: {
  kind: SensitiveKind;
  rowId: number;
  canReveal: boolean;
  isOwner: boolean;
}) {
  const [purpose, setPurpose] = useState('');
  const [value, setValue] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  if (!canReveal) {
    return <span className="text-xs text-muted-foreground">Not permitted to reveal</span>;
  }

  async function reveal() {
    setBusy(true);
    setError(null);
    const result = await rpcCall<string>('emp_sensitive_reveal', {
      p_kind: kind,
      p_id: rowId,
      p_purpose: purpose.trim() || undefined,
    });
    setBusy(false);
    if (!result.ok) {
      setError(result.error);
      return;
    }
    setValue(result.data);
  }

  return (
    <div className="space-y-2">
      {!isOwner && (
        <div className="space-y-1.5">
          <Label htmlFor={`purpose-${kind}-${rowId}`}>Purpose of access</Label>
          <Input
            id={`purpose-${kind}-${rowId}`}
            value={purpose}
            onChange={(e) => setPurpose(e.target.value)}
            placeholder="e.g. bank KYC verification"
          />
          <p className="text-xs text-muted-foreground">
            The purpose is recorded in the access audit. It must be between 5 and 500 characters.
          </p>
        </div>
      )}
      <div className="flex items-center gap-2">
        <Button size="sm" variant="outline" onClick={reveal} disabled={busy}>
          {busy ? 'Revealing…' : 'Reveal'}
        </Button>
        {value && <code className="rounded bg-muted px-2 py-1 text-xs">{value}</code>}
      </div>
      {error && <p className="text-xs text-red-700">{error}</p>}
    </div>
  );
}

export function SensitivePanel({
  kind,
  rows,
  can,
}: {
  kind: SensitiveKind;
  rows: SensitiveRow[];
  can: SensitiveCan;
}) {
  const canReveal =
    kind === 'PAN' ? can.reveal_pan : kind === 'AADHAAR' ? can.reveal_aadhaar : can.reveal_bank;
  const isOwner = can.owner === true;

  if (rows.length === 0) {
    return <p className="text-sm text-muted-foreground">Nothing on file.</p>;
  }

  return (
    <ul className="space-y-4">
      {rows.map((r) => (
        <li key={r.id} className="rounded-md border border-border p-3">
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div>
              <p className="text-sm font-medium">{r.holder ?? r.name ?? `Record #${r.id}`}</p>
              <p className="text-xs text-muted-foreground">
                {r.bank ? `${r.bank}${r.branch ? ` · ${r.branch}` : ''}` : ''}
                {r.ifsc ? ` · ${r.ifsc}` : ''}
                {r.type ? ` · ${r.type}` : ''}
              </p>
            </div>
            <div className="flex items-center gap-2">
              {r.is_primary ? <Badge variant="info">Primary</Badge> : null}
              {r.status ? <Badge variant="outline">{r.status}</Badge> : null}
            </div>
          </div>

          <p className="mt-2 font-mono text-sm">{r.masked ?? '—'}</p>
          {r.issue_date ? (
            <p className="text-xs text-muted-foreground">Issued {formatDate(r.issue_date)}</p>
          ) : null}
          {r.updated_at ? (
            <p className="text-xs text-muted-foreground">Updated {formatDate(r.updated_at)}</p>
          ) : null}

          <div className="mt-3">
            <RevealControl kind={kind} rowId={r.id} canReveal={canReveal === true} isOwner={isOwner} />
          </div>
        </li>
      ))}
    </ul>
  );
}
