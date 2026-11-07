'use client';

import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input, Select } from '@/components/ui/input';
import { clientRpc, clientUpdate } from '@/features/shared/client-rpc';
import { MARK_STATUSES, type AssessmentEventRow, type AssessmentOffering, type AssessmentSheetRow } from './types';

/**
 * Interactive parts of the assessment screen.
 *
 * Marks are entered with `assessment_enter_marks`; publishing an event is the
 * one operation the schema exposes without a `public.*` function, so it is a
 * direct update of the RLS-protected `assessment_event` row. The database still
 * refuses to publish an event that has not been conducted.
 */

function ErrorText({ message }: { message: string | null }) {
  if (!message) return null;
  return (
    <p className="rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800" role="alert">
      {message}
    </p>
  );
}

/** Choose the course offering whose assessment events are shown. */
export function OfferingPicker({
  offerings,
  selectedId,
}: {
  offerings: AssessmentOffering[];
  selectedId: number | null;
}) {
  const router = useRouter();

  return (
    <Select
      value={selectedId === null ? '' : String(selectedId)}
      onChange={(e) => {
        const id = e.target.value;
        router.push(id ? `/assessment?offering=${id}` : '/assessment');
      }}
      aria-label="Course offering"
      className="max-w-lg"
    >
      <option value="">Select a course offering</option>
      {offerings.map((o) => (
        <option key={o.course_offering_id} value={o.course_offering_id}>
          {o.course_code} â€” {o.course_title} Â· {o.term_name} Â· {o.programme_name}
        </option>
      ))}
    </Select>
  );
}

/** Choose the assessment event whose sheet is marked. */
export function EventPicker({
  events,
  offeringId,
  selectedId,
}: {
  events: AssessmentEventRow[];
  offeringId: number;
  selectedId: number | null;
}) {
  const router = useRouter();

  return (
    <Select
      value={selectedId === null ? '' : String(selectedId)}
      onChange={(e) => {
        const id = e.target.value;
        router.push(id ? `/assessment?offering=${offeringId}&event=${id}` : `/assessment?offering=${offeringId}`);
      }}
      aria-label="Assessment event"
      className="max-w-lg"
    >
      <option value="">Select an assessment event</option>
      {events.map((e) => (
        <option key={e.assessment_event_id} value={e.assessment_event_id}>
          {e.event_title} Â· {e.assessment_date} Â· {e.status}
        </option>
      ))}
    </Select>
  );
}

type Entry = { status: string; marks: string; reduced: string; remarks: string };

/** Enter the marks of every registered student for one assessment event. */
export function MarksEntryForm({
  eventId,
  rows,
  maximumMarks,
  reducedMaximumMarks,
}: {
  eventId: number;
  rows: AssessmentSheetRow[];
  maximumMarks: number;
  reducedMaximumMarks: number | null;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [entries, setEntries] = useState<Record<number, Entry>>(() => {
    const initial: Record<number, Entry> = {};
    for (const r of rows) {
      initial[r.course_registration_id] = {
        status: r.attendance_status ?? 'PRESENT',
        marks: r.marks_obtained === null ? '' : String(r.marks_obtained),
        reduced: r.reduced_marks === null ? '' : String(r.reduced_marks),
        remarks: r.remarks ?? '',
      };
    }
    return initial;
  });

  function update(id: number, patch: Partial<Entry>) {
    setEntries((prev) => ({ ...prev, [id]: { ...(prev[id] ?? { status: 'PRESENT', marks: '', reduced: '', remarks: '' }), ...patch } }));
  }

  async function submit() {
    setBusy(true);
    setError(null);
    setMessage(null);

    const marks: Record<string, unknown>[] = [];
    for (const r of rows) {
      const entry = entries[r.course_registration_id];
      if (!entry || !entry.status) continue;
      const payload: Record<string, unknown> = {
        course_registration_id: r.course_registration_id,
        attendance_status: entry.status,
      };
      if (entry.status === 'PRESENT') {
        if (entry.marks.trim() !== '') payload.marks_obtained = Number(entry.marks);
        if (entry.reduced.trim() !== '') payload.reduced_marks = Number(entry.reduced);
      }
      if (entry.remarks.trim() !== '') payload.remarks = entry.remarks.trim();
      marks.push(payload);
    }

    if (marks.length === 0) {
      setError('Enter a status for at least one student.');
      setBusy(false);
      return;
    }

    try {
      const saved = await clientRpc<number>('assessment_enter_marks', { p_event_id: eventId, p_marks: marks });
      setMessage(`${saved} mark${saved === 1 ? '' : 's'} saved.`);
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The marks could not be saved.');
    } finally {
      setBusy(false);
    }
  }

  if (rows.length === 0) {
    return <p className="text-sm text-muted-foreground">No student is registered for this course offering.</p>;
  }

  return (
    <div className="space-y-3">
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b">
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Student</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Number</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Status</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Marks</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Reduced</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Remarks</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => {
              const entry = entries[r.course_registration_id] ?? {
                status: 'PRESENT',
                marks: '',
                reduced: '',
                remarks: '',
              };
              const isPresent = entry.status === 'PRESENT';
              return (
                <tr key={r.course_registration_id} className="border-b">
                  <td className="px-3 py-2 font-medium">{r.display_name}</td>
                  <td className="px-3 py-2">{r.student_number}</td>
                  <td className="px-3 py-2">
                    <Select
                      value={entry.status}
                      onChange={(e) => update(r.course_registration_id, { status: e.target.value })}
                      className="h-8 w-36 text-xs"
                      aria-label={`Assessment status for ${r.display_name}`}
                    >
                      {MARK_STATUSES.map((s) => (
                        <option key={s} value={s}>
                          {s}
                        </option>
                      ))}
                    </Select>
                  </td>
                  <td className="px-3 py-2">
                    <Input
                      type="number"
                      step="0.01"
                      min="0"
                      max={maximumMarks}
                      value={entry.marks}
                      onChange={(e) => update(r.course_registration_id, { marks: e.target.value })}
                      disabled={!isPresent}
                      className="h-8 w-24 text-xs"
                      aria-label={`Marks for ${r.display_name}`}
                    />
                  </td>
                  <td className="px-3 py-2">
                    <Input
                      type="number"
                      step="0.01"
                      min="0"
                      max={reducedMaximumMarks ?? undefined}
                      value={entry.reduced}
                      onChange={(e) => update(r.course_registration_id, { reduced: e.target.value })}
                      disabled={!isPresent || reducedMaximumMarks === null}
                      className="h-8 w-24 text-xs"
                      aria-label={`Reduced marks for ${r.display_name}`}
                    />
                  </td>
                  <td className="px-3 py-2">
                    <Input
                      value={entry.remarks}
                      onChange={(e) => update(r.course_registration_id, { remarks: e.target.value })}
                      maxLength={500}
                      className="h-8 w-48 text-xs"
                      aria-label={`Remarks for ${r.display_name}`}
                    />
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
      <ErrorText message={error} />
      {message && <p className="text-sm text-muted-foreground">{message}</p>}
      <Button onClick={submit} disabled={busy}>
        {busy ? 'Savingâ€¦' : 'Save marks'}
      </Button>
    </div>
  );
}

/** Move a conducted event to PUBLISHED. */
export function PublishEventButton({ eventId, status }: { eventId: number; status: string }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (status === 'PUBLISHED') {
    return <p className="text-sm text-muted-foreground">This event is published; its marks are locked.</p>;
  }
  if (status !== 'CONDUCTED') {
    return (
      <p className="text-sm text-muted-foreground">
        Save the marks first: an event can only be published once it has been conducted.
      </p>
    );
  }

  async function publish() {
    setBusy(true);
    setError(null);
    try {
      await clientUpdate('assessment_event', { status: 'PUBLISHED' }, { assessment_event_id: eventId });
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The event could not be published.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-2">
      <Button onClick={publish} disabled={busy}>
        {busy ? 'Publishingâ€¦' : 'Publish event'}
      </Button>
      <ErrorText message={error} />
    </div>
  );
}
