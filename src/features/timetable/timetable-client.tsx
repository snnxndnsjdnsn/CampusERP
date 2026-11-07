'use client';

import { useRouter } from 'next/navigation';
import { useCallback, useEffect, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input, Select } from '@/components/ui/input';
import { clientRpc } from '@/features/shared/client-rpc';
import type { FacultyAssignment, TimetableOffering } from './types';

/**
 * Interactive parts of the timetable screen.
 *
 * The weekly grid itself is rendered on the server; the browser only picks the
 * offering, generates class sessions and loads the faculty assignments.
 */

/** Choose the programme term offering whose timetable is shown. */
export function OfferingPicker({
  offerings,
  selectedId,
}: {
  offerings: TimetableOffering[];
  selectedId: number | null;
}) {
  const router = useRouter();

  return (
    <Select
      value={selectedId === null ? '' : String(selectedId)}
      onChange={(e) => {
        const id = e.target.value;
        router.push(id ? `/timetable?pto=${id}` : '/timetable');
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

/** Materialise the class sessions for a teaching section over a date range. */
export function GenerateSessionsButton({ sectionId, label }: { sectionId: number; label: string }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [from, setFrom] = useState(() => new Date().toISOString().slice(0, 10));
  const [to, setTo] = useState(() => new Date(Date.now() + 28 * 86400000).toISOString().slice(0, 10));
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function run() {
    setBusy(true);
    setError(null);
    setMessage(null);
    try {
      const created = await clientRpc<number>('timetable_generate_sessions', {
        p_cos_id: sectionId,
        p_from: from,
        p_to: to,
      });
      setMessage(`${created} class session${created === 1 ? '' : 's'} generated for ${label}.`);
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The class sessions could not be generated.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap items-center gap-2">
        <Input
          type="date"
          value={from}
          onChange={(e) => setFrom(e.target.value)}
          className="h-8 w-36 text-xs"
          aria-label="From date"
        />
        <Input
          type="date"
          value={to}
          onChange={(e) => setTo(e.target.value)}
          className="h-8 w-36 text-xs"
          aria-label="To date"
        />
        <Button size="sm" variant="outline" onClick={run} disabled={busy || !from || !to}>
          {busy ? 'Generatingâ€¦' : 'Generate sessions'}
        </Button>
      </div>
      {message && <p className="text-xs text-muted-foreground">{message}</p>}
      {error && (
        <p className="rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800" role="alert">
          {error}
        </p>
      )}
    </div>
  );
}

/** Load the faculty assigned to one teaching section. */
export function SectionAssignments({ sectionId }: { sectionId: number }) {
  const [rows, setRows] = useState<FacultyAssignment[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const data = await clientRpc<FacultyAssignment[]>('timetable_assignments', { p_cos_id: sectionId });
      setRows(Array.isArray(data) ? data : []);
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The faculty assignments could not be read.');
    } finally {
      setLoading(false);
    }
  }, [sectionId]);

  useEffect(() => {
    void (async () => {
      await load();
    })();
  }, [load]);

  if (loading) return <p className="text-sm text-muted-foreground">Loading assignmentsâ€¦</p>;
  if (error) {
    return (
      <p className="rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800" role="alert">
        {error}
      </p>
    );
  }
  if (rows.length === 0) return <p className="text-sm text-muted-foreground">No faculty assigned to this section.</p>;

  return (
    <ul className="space-y-1 text-sm">
      {rows.map((r) => (
        <li key={r.faculty_assignment_id} className="flex flex-wrap items-center gap-2">
          <span className="font-medium">{r.employee_name}</span>
          <span className="text-muted-foreground">{r.assignment_role}</span>
          <span className="text-xs text-muted-foreground">{r.assignment_status}</span>
        </li>
      ))}
    </ul>
  );
}
