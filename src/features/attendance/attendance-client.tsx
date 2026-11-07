'use client';

import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input, Select, Textarea } from '@/components/ui/input';
import { clientRpc } from '@/features/shared/client-rpc';
import type { AttendanceSheetRow, AttendanceStatus, ClassSessionRow } from './types';

/**
 * Interactive parts of the attendance screen.
 *
 * Marking, correction requests and correction decisions all go through
 * `public.*` functions; the database decides who may mark and who may approve.
 */

function ErrorText({ message }: { message: string | null }) {
  if (!message) return null;
  return (
    <p className="rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800" role="alert">
      {message}
    </p>
  );
}

/** Choose the class session whose attendance is marked. */
export function SessionPicker({
  sessions,
  selectedId,
}: {
  sessions: ClassSessionRow[];
  selectedId: number | null;
}) {
  const router = useRouter();

  return (
    <Select
      value={selectedId === null ? '' : String(selectedId)}
      onChange={(e) => {
        const id = e.target.value;
        router.push(id ? `/attendance?session=${id}` : '/attendance');
      }}
      aria-label="Class session"
      className="max-w-lg"
    >
      <option value="">Select a class session</option>
      {sessions.map((s) => (
        <option key={s.class_session_id} value={s.class_session_id}>
          {s.session_date} Â· {s.course_label ?? `Section ${s.course_offering_section_id}`} Â· {s.start_time?.slice(0, 5)}
          {s.section_code ? ` Â· ${s.section_code}` : ''} Â· {s.session_status}
        </option>
      ))}
    </Select>
  );
}

/** Mark the attendance of every student on the roster sheet. */
export function AttendanceMarkForm({
  sessionId,
  rows,
  statuses,
}: {
  sessionId: number;
  rows: AttendanceSheetRow[];
  statuses: AttendanceStatus[];
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [chosen, setChosen] = useState<Record<number, string>>({});
  const [remarks, setRemarks] = useState<Record<number, string>>({});

  const statusName = (id: number | null): string => {
    if (id === null) return 'Not marked';
    return statuses.find((s) => s.attendance_status_id === id)?.status_name ?? `Status ${id}`;
  };

  async function submit() {
    setBusy(true);
    setError(null);
    setMessage(null);
    const marks = rows
      .filter((r) => chosen[r.roster_id])
      .map((r) => ({
        roster_id: r.roster_id,
        status_id: Number(chosen[r.roster_id]),
        remarks: (remarks[r.roster_id] ?? '').trim() || undefined,
      }));
    if (marks.length === 0) {
      setError('Choose an attendance status for at least one student.');
      setBusy(false);
      return;
    }
    try {
      const saved = await clientRpc<number>('attendance_mark', { p_session_id: sessionId, p_marks: marks });
      setMessage(`${saved} attendance entr${saved === 1 ? 'y' : 'ies'} saved.`);
      setChosen({});
      setRemarks({});
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The attendance could not be saved.');
    } finally {
      setBusy(false);
    }
  }

  if (rows.length === 0) {
    return <p className="text-sm text-muted-foreground">This section has no roster yet.</p>;
  }

  return (
    <div className="space-y-3">
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b">
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Student</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Number</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Marked</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Status</th>
              <th className="px-3 py-2 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">Remarks</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.roster_id} className="border-b">
                <td className="px-3 py-2 font-medium">{r.display_name}</td>
                <td className="px-3 py-2">{r.student_number}</td>
                <td className="px-3 py-2 text-xs text-muted-foreground">{statusName(r.attendance_status_id)}</td>
                <td className="px-3 py-2">
                  <Select
                    value={chosen[r.roster_id] ?? ''}
                    onChange={(e) => setChosen((prev) => ({ ...prev, [r.roster_id]: e.target.value }))}
                    className="h-8 w-40 text-xs"
                    aria-label={`Attendance status for ${r.display_name}`}
                  >
                    <option value="">Not set</option>
                    {statuses.map((s) => (
                      <option key={s.attendance_status_id} value={s.attendance_status_id}>
                        {s.status_name}
                      </option>
                    ))}
                  </Select>
                </td>
                <td className="px-3 py-2">
                  <Input
                    value={remarks[r.roster_id] ?? ''}
                    onChange={(e) => setRemarks((prev) => ({ ...prev, [r.roster_id]: e.target.value }))}
                    maxLength={500}
                    className="h-8 w-48 text-xs"
                    aria-label={`Remarks for ${r.display_name}`}
                  />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <ErrorText message={error} />
      {message && <p className="text-sm text-muted-foreground">{message}</p>}
      <Button onClick={submit} disabled={busy}>
        {busy ? 'Savingâ€¦' : 'Save attendance'}
      </Button>
    </div>
  );
}

/** Ask for a marked attendance to be corrected. */
export function CorrectionRequestForm({
  sessionId,
  rows,
  statuses,
}: {
  sessionId: number;
  rows: AttendanceSheetRow[];
  statuses: AttendanceStatus[];
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [rosterId, setRosterId] = useState('');
  const [statusId, setStatusId] = useState('');
  const [reason, setReason] = useState('');

  const marked = rows.filter((r) => r.attendance_status_id !== null);

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    setMessage(null);
    try {
      await clientRpc<number>('attendance_request_correction', {
        p_session_id: sessionId,
        p_roster_id: Number(rosterId),
        p_requested_status_id: Number(statusId),
        p_reason: reason.trim(),
      });
      setMessage('The correction request was submitted.');
      setRosterId('');
      setStatusId('');
      setReason('');
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The correction request could not be submitted.');
    } finally {
      setBusy(false);
    }
  }

  if (marked.length === 0) {
    return <p className="text-sm text-muted-foreground">Mark the attendance first; corrections need a recorded status.</p>;
  }

  return (
    <form onSubmit={submit} className="space-y-3" noValidate>
      <div className="flex flex-wrap gap-2">
        <Select value={rosterId} onChange={(e) => setRosterId(e.target.value)} required className="h-9 w-56" aria-label="Student">
          <option value="">Select a student</option>
          {marked.map((r) => (
            <option key={r.roster_id} value={r.roster_id}>
              {r.display_name} ({r.student_number})
            </option>
          ))}
        </Select>
        <Select value={statusId} onChange={(e) => setStatusId(e.target.value)} required className="h-9 w-48" aria-label="Requested status">
          <option value="">Requested status</option>
          {statuses.map((s) => (
            <option key={s.attendance_status_id} value={s.attendance_status_id}>
              {s.status_name}
            </option>
          ))}
        </Select>
      </div>
      <Textarea
        value={reason}
        onChange={(e) => setReason(e.target.value)}
        placeholder="Why should the attendance be corrected?"
        required
        maxLength={1000}
        rows={2}
        aria-label="Reason"
      />
      <ErrorText message={error} />
      {message && <p className="text-sm text-muted-foreground">{message}</p>}
      <Button type="submit" disabled={busy}>
        {busy ? 'Submittingâ€¦' : 'Request correction'}
      </Button>
    </form>
  );
}

/** Approve or reject a pending correction request. */
export function CorrectionDecision({ correctionId }: { correctionId: number }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function decide(approve: boolean) {
    setBusy(true);
    setError(null);
    try {
      await clientRpc<null>('attendance_decide_correction', {
        p_correction_id: correctionId,
        p_approve: approve,
      });
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The correction could not be decided.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-1">
      <div className="flex gap-2">
        <Button size="sm" onClick={() => decide(true)} disabled={busy}>
          Approve
        </Button>
        <Button size="sm" variant="outline" onClick={() => decide(false)} disabled={busy}>
          Reject
        </Button>
      </div>
      <ErrorText message={error} />
    </div>
  );
}
