'use client';

import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input, Select } from '@/components/ui/input';
import { clientRpc } from '@/features/shared/client-rpc';
import type { TermOffering } from './types';

/**
 * Interactive parts of the registration screen.
 *
 * The browser only navigates and calls `public.*` functions; the database
 * decides which offerings, candidates and courses the caller may touch.
 */

/** Choose the programme term offering the page works with. */
export function OfferingPicker({
  offerings,
  selectedId,
}: {
  offerings: TermOffering[];
  selectedId: number | null;
}) {
  const router = useRouter();

  return (
    <Select
      value={selectedId === null ? '' : String(selectedId)}
      onChange={(e) => {
        const id = e.target.value;
        router.push(id ? `/registration?pto=${id}` : '/registration');
      }}
      aria-label="Programme term offering"
      className="max-w-md"
    >
      <option value="">Select a term offering</option>
      {offerings.map((o) => (
        <option key={o.programme_term_offering_id} value={o.programme_term_offering_id}>
          {o.term_name} Â· {o.programme_name} Â· {o.semester_name}
        </option>
      ))}
    </Select>
  );
}

/** Create the course offerings for the chosen programme term offering. */
export function GenerateCoursesButton({ offeringId }: { offeringId: number }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function run() {
    setBusy(true);
    setError(null);
    setMessage(null);
    try {
      const created = await clientRpc<number>('offering_generate_courses', {
        p_programme_term_offering_id: offeringId,
      });
      setMessage(`${created} course offering${created === 1 ? '' : 's'} created.`);
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The course offerings could not be generated.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-2">
      <Button onClick={run} disabled={busy} variant="outline">
        {busy ? 'Generatingâ€¦' : 'Generate course offerings'}
      </Button>
      {message && <p className="text-sm text-muted-foreground">{message}</p>}
      {error && (
        <p className="rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}

/** Search the students who may still be registered for this offering. */
export function CandidateSearch({ offeringId, query }: { offeringId: number; query: string }) {
  const router = useRouter();
  const [value, setValue] = useState(query);

  return (
    <form
      className="flex gap-2"
      onSubmit={(e) => {
        e.preventDefault();
        router.push(`/registration?pto=${offeringId}&q=${encodeURIComponent(value.trim())}`);
      }}
    >
      <Input
        value={value}
        onChange={(e) => setValue(e.target.value)}
        placeholder="Search by name or student number"
        maxLength={80}
        aria-label="Search candidates"
      />
      <Button type="submit" variant="outline">
        Search
      </Button>
    </form>
  );
}
