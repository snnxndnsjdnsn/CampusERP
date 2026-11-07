'use client';

import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input, Select } from '@/components/ui/input';
import { clientRpc } from '@/features/shared/client-rpc';
import type { AssessmentOffering } from '@/features/assessment/types';
import { RESULT_STATUSES, type ResultCourseSheetRow } from './types';

/**
 * Interactive parts of the results screen.
 *
 * Recording a course result, computing a term result and publishing it all go
 * through `public.*` functions; the database decides who may do what.
 */

function ErrorText({ message }: { message: string | null }) {
  if (!message) return null;
  return (
    <p className="rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800" role="alert">
      {message}
    </p>
  );
}

/** Choose the course offering whose result sheet is shown. */
export function ResultOfferingPicker({
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
        router.push(id ? `/results/grades?offering=${id}` : '/results/grades');
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

/** Record (or re-record) the result of one course registration. */
export function CourseResultForm({
  row,
  internalMaxMarks,
  externalMaxMarks,
}: {
  row: ResultCourseSheetRow;
  internalMaxMarks: number | null;
  externalMaxMarks: number | null;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [open, setOpen] = useState(false);
  const [internal, setInternal] = useState(row.internal_marks === null ? '' : String(row.internal_marks));
  const [external, setExternal] = useState(row.external_marks === null ? '' : String(row.external_marks));
  const [attempt, setAttempt] = useState(String(row.attempt_number ?? 1));
  const [status, setStatus] = useState('');
  const [remarks, setRemarks] = useState('');

  if (row.published) {
    return <span className="text-xs text-muted-foreground">Published</span>;
  }

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    setMessage(null);
    try {
      await clientRpc<number>('result_record_course', {
        p_course_registration_id: row.course_registration_id,
        p_internal: status === '' && internal.trim() !== '' ? Number(internal) : null,
        p_external: status === '' && external.trim() !== '' ? Number(external) : null,
        p_attempt: Number(attempt) || 1,
        p_status: status === '' ? null : status,
        p_remarks: remarks.trim() || null,
      });
      setMessage('The result was recorded.');
      setOpen(false);
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The result could not be recorded.');
    } finally {
      setBusy(false);
    }
  }

  if (!open) {
    return (
      <Button size="sm" variant="outline" onClick={() => setOpen(true)}>
        {row.total_marks === null ? 'Record' : 'Edit'}
      </Button>
    );
  }

  return (
    <form onSubmit={submit} className="space-y-2" noValidate>
      <div className="flex flex-wrap gap-2">
        <Input
          type="number"
          step="0.01"
          min="0"
          max={internalMaxMarks ?? undefined}
          value={internal}
          onChange={(e) => setInternal(e.target.value)}
          placeholder="Internal"
          disabled={status !== ''}
          className="h-8 w-24 text-xs"
          aria-label={`Internal marks for ${row.display_name}`}
        />
        <Input
          type="number"
          step="0.01"
          min="0"
          max={externalMaxMarks ?? undefined}
          value={external}
          onChange={(e) => setExternal(e.target.value)}
          placeholder="External"
          disabled={status !== ''}
          className="h-8 w-24 text-xs"
          aria-label={`External marks for ${row.display_name}`}
        />
        <Input
          type="number"
          min="1"
          max="255"
          value={attempt}
          onChange={(e) => setAttempt(e.target.value)}
          className="h-8 w-16 text-xs"
          aria-label={`Attempt for ${row.display_name}`}
        />
        <Select value={status} onChange={(e) => setStatus(e.target.value)} className="h-8 w-32 text-xs" aria-label={`Status for ${row.display_name}`}>
          <option value="">From marks</option>
          {RESULT_STATUSES.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </Select>
        <Input
          value={remarks}
          onChange={(e) => setRemarks(e.target.value)}
          placeholder="Remarks"
          maxLength={500}
          className="h-8 w-40 text-xs"
          aria-label={`Remarks for ${row.display_name}`}
        />
        <Button size="sm" type="submit" disabled={busy}>
          {busy ? 'Savingâ€¦' : 'Save'}
        </Button>
        <Button size="sm" type="button" variant="ghost" onClick={() => setOpen(false)} disabled={busy}>
          Cancel
        </Button>
      </div>
      <ErrorText message={error} />
      {message && <p className="text-xs text-muted-foreground">{message}</p>}
    </form>
  );
}

/** Compute and publish one student's term result. */
export function TermResultActions({
  termRegistrationId,
  published,
}: {
  termRegistrationId: number;
  published: boolean;
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  async function compute() {
    setBusy(true);
    setError(null);
    setMessage(null);
    try {
      await clientRpc<number>('result_compute_term', { p_term_registration_id: termRegistrationId });
      setMessage('The term result was computed.');
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The term result could not be computed.');
    } finally {
      setBusy(false);
    }
  }

  async function publish(next: boolean) {
    setBusy(true);
    setError(null);
    setMessage(null);
    try {
      await clientRpc<null>('result_publish_term', {
        p_term_registration_id: termRegistrationId,
        p_publish: next,
      });
      setMessage(next ? 'The term result was published.' : 'The term result was unpublished.');
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The term result could not be published.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-1">
      <div className="flex flex-wrap justify-end gap-2">
        <Button size="sm" variant="outline" onClick={compute} disabled={busy || published}>
          Compute
        </Button>
        {published ? (
          <Button size="sm" variant="secondary" onClick={() => publish(false)} disabled={busy}>
            Unpublish
          </Button>
        ) : (
          <Button size="sm" onClick={() => publish(true)} disabled={busy}>
            Publish
          </Button>
        )}
      </div>
      <ErrorText message={error} />
      {message && <p className="text-xs text-muted-foreground">{message}</p>}
    </div>
  );
}
