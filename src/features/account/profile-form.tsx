'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { ErrorPanel } from '@/components/ui/empty-state';
import { Input, Label } from '@/components/ui/input';
import { useRpc } from '@/features/shared/use-rpc';

/**
 * Edit the caller's own contact details.
 *
 * `my_profile_update` only accepts `primary_email` and `primary_phone`; every other
 * field is rejected by the database, so this form sends exactly those two keys.
 */
export function ProfileForm({
  initialEmail,
  initialPhone,
}: {
  initialEmail: string | null;
  initialPhone: string | null;
}) {
  const { run, busy, error } = useRpc();
  const [email, setEmail] = useState(initialEmail ?? '');
  const [phone, setPhone] = useState(initialPhone ?? '');
  const [saved, setSaved] = useState(false);

  async function onSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSaved(false);
    const ok = await run('my_profile_update', {
      p: { primary_email: email.trim(), primary_phone: phone.trim() },
    });
    if (ok) setSaved(true);
  }

  return (
    <form onSubmit={onSubmit} className="space-y-4">
      {error && <ErrorPanel message={error} />}
      {saved && !error && (
        <p className="rounded-md border border-emerald-200 bg-emerald-50 p-3 text-sm text-emerald-800">
          Contact details saved.
        </p>
      )}

      <div className="grid gap-4 sm:grid-cols-2">
        <div className="space-y-1.5">
          <Label htmlFor="profile-email">Primary email</Label>
          <Input
            id="profile-email"
            type="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            placeholder="name@example.com"
            autoComplete="email"
          />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="profile-phone">Primary phone</Label>
          <Input
            id="profile-phone"
            type="tel"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            placeholder="+91 98765 43210"
            autoComplete="tel"
          />
        </div>
      </div>

      <Button type="submit" disabled={busy}>
        {busy ? 'Saving…' : 'Save contact details'}
      </Button>
    </form>
  );
}

export default ProfileForm;
