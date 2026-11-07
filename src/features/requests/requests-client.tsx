'use client';

import { useState } from 'react';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Input, Label, Select, Textarea } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { formatDate, formatDateTime, humanise } from '@/lib/format';
import { useRpcAction } from '@/features/shared/client-rpc';

/* ------------------------------------------------------------------ types */

export type ServiceRequest = {
  service_request_id: number;
  request_number: string;
  request_kind: string;
  student_id: number;
  student_number: string;
  student_name: string;
  term_name: string | null;
  planned_date: string | null;
  detail: string | null;
  request_status: string;
  decision_remarks: string | null;
  reference_number: string | null;
  created_at: string;
  can_decide: boolean;
  can_cancel: boolean;
  hold_blocked: boolean;
};

export type Term = { academic_term_id: number; term_name: string };

const KINDS = ['HALL_TICKET', 'HOSTEL_CHECKOUT', 'GRADUATION'];

/* ------------------------------------------------------------ new request */

export function ServiceRequestForm({ terms }: { terms: Term[] }) {
  const { busy, error, notice, run } = useRpcAction();
  const [kind, setKind] = useState('HALL_TICKET');
  const [termId, setTermId] = useState('');
  const [plannedDate, setPlannedDate] = useState('');
  const [detail, setDetail] = useState('');

  async function submit() {
    await run<number>(
      'svc_request_create',
      {
        p_kind: kind,
        p_term_id: kind === 'HALL_TICKET' ? (termId === '' ? null : Number(termId)) : null,
        p_planned_date: kind === 'HOSTEL_CHECKOUT' ? (plannedDate || null) : null,
        p_detail: detail.trim() || null,
      },
      { success: 'Your request has been submitted.' },
    );
    setDetail('');
  }

  return (
    <div className="space-y-3">
      <div className="grid gap-3 sm:grid-cols-3">
        <div className="space-y-1">
          <Label htmlFor="svc-kind">Request</Label>
          <Select id="svc-kind" value={kind} onChange={(e) => setKind(e.target.value)}>
            {KINDS.map((k) => (
              <option key={k} value={k}>
                {humanise(k)}
              </option>
            ))}
          </Select>
        </div>
        {kind === 'HALL_TICKET' ? (
          <div className="space-y-1">
            <Label htmlFor="svc-term">Academic term</Label>
            <Select id="svc-term" value={termId} onChange={(e) => setTermId(e.target.value)}>
              <option value="">Choose a term</option>
              {terms.map((t) => (
                <option key={t.academic_term_id} value={t.academic_term_id}>
                  {t.term_name}
                </option>
              ))}
            </Select>
          </div>
        ) : null}
        {kind === 'HOSTEL_CHECKOUT' ? (
          <div className="space-y-1">
            <Label htmlFor="svc-date">Planned check-out date</Label>
            <Input id="svc-date" type="date" value={plannedDate} onChange={(e) => setPlannedDate(e.target.value)} />
          </div>
        ) : null}
      </div>
      <div className="space-y-1">
        <Label htmlFor="svc-detail">Note</Label>
        <Textarea id="svc-detail" value={detail} onChange={(e) => setDetail(e.target.value)} maxLength={500} />
      </div>
      {error ? <ErrorPanel message={error} /> : null}
      {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
      <Button onClick={submit} disabled={busy || (kind === 'HALL_TICKET' && !termId)}>
        {busy ? 'Submitting…' : 'Submit the request'}
      </Button>
    </div>
  );
}

/* --------------------------------------------------------------- decisions */

function DecideControl({ request }: { request: ServiceRequest }) {
  const { busy, error, notice, run } = useRpcAction();
  const [remarks, setRemarks] = useState('');
  const [open, setOpen] = useState(false);

  async function decide(action: 'APPROVE' | 'REJECT' | 'COMPLETE') {
    await run<string>(
      'svc_request_decide',
      { p_id: request.service_request_id, p_action: action, p_remarks: remarks.trim() || null },
      { success: `The request has been ${action === 'APPROVE' ? 'approved' : action === 'REJECT' ? 'rejected' : 'completed'}.` },
    );
    setOpen(false);
  }

  if (!request.can_decide) return null;

  const actions: ('APPROVE' | 'REJECT' | 'COMPLETE')[] =
    request.request_status === 'SUBMITTED' ? ['APPROVE', 'REJECT'] : request.request_status === 'APPROVED' ? ['COMPLETE'] : [];

  return (
    <div className="space-y-2">
      {open ? (
        <>
          <div className="space-y-1">
            <Label htmlFor={`svc-remarks-${request.service_request_id}`}>Remarks (required to reject)</Label>
            <Textarea
              id={`svc-remarks-${request.service_request_id}`}
              value={remarks}
              onChange={(e) => setRemarks(e.target.value)}
              maxLength={500}
            />
          </div>
          {error ? <ErrorPanel message={error} /> : null}
          {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
          <div className="flex flex-wrap gap-2">
            {actions.map((a) => (
              <Button key={a} size="sm" variant={a === 'REJECT' ? 'destructive' : 'default'} onClick={() => decide(a)} disabled={busy || (a === 'REJECT' && !remarks.trim())}>
                {humanise(a)}
              </Button>
            ))}
            <Button size="sm" variant="ghost" onClick={() => setOpen(false)} disabled={busy}>
              Cancel
            </Button>
          </div>
        </>
      ) : (
        <Button size="sm" variant="outline" onClick={() => setOpen(true)}>
          Decide
        </Button>
      )}
    </div>
  );
}

function CancelControl({ request }: { request: ServiceRequest }) {
  const { busy, error, notice, run } = useRpcAction();

  async function cancel() {
    await run<void>('svc_request_cancel', { p_id: request.service_request_id }, { success: 'The request has been cancelled.' });
  }

  if (!request.can_cancel) return null;

  return (
    <div className="space-y-2">
      {error ? <ErrorPanel message={error} /> : null}
      {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
      <Button size="sm" variant="ghost" onClick={cancel} disabled={busy}>
        {busy ? 'Cancelling…' : 'Cancel'}
      </Button>
    </div>
  );
}

/* -------------------------------------------------------------- workspace */

export function ServiceRequestWorkspace({ rows }: { rows: ServiceRequest[] }) {
  if (rows.length === 0) {
    return <EmptyState title="No service requests" description="Hall ticket, hostel check-out and graduation requests appear here." />;
  }

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Request</TableHead>
          <TableHead>Kind</TableHead>
          <TableHead>Student</TableHead>
          <TableHead>Term / date</TableHead>
          <TableHead>Status</TableHead>
          <TableHead>Created</TableHead>
          <TableHead>Actions</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.map((r) => (
          <TableRow key={r.service_request_id}>
            <TableCell className="font-mono text-xs">{r.request_number}</TableCell>
            <TableCell>{humanise(r.request_kind)}</TableCell>
            <TableCell>
              <div>{r.student_name}</div>
              <div className="text-xs text-muted-foreground">{r.student_number}</div>
            </TableCell>
            <TableCell>
              {r.term_name ? <div>{r.term_name}</div> : null}
              {r.planned_date ? <div className="text-xs text-muted-foreground">{formatDate(r.planned_date)}</div> : null}
              {r.detail ? <div className="mt-1 max-w-xs text-xs">{r.detail}</div> : null}
            </TableCell>
            <TableCell>
              <Badge variant={statusVariant(r.request_status)}>{humanise(r.request_status)}</Badge>
              {r.hold_blocked ? (
                <div className="mt-1">
                  <Badge variant="destructive">On hold</Badge>
                </div>
              ) : null}
              {r.reference_number ? <div className="mt-1 font-mono text-xs">{r.reference_number}</div> : null}
              {r.decision_remarks ? <div className="mt-1 text-xs text-muted-foreground">{r.decision_remarks}</div> : null}
            </TableCell>
            <TableCell>{formatDateTime(r.created_at)}</TableCell>
            <TableCell>
              <div className="flex flex-col gap-2">
                <DecideControl request={r} />
                <CancelControl request={r} />
              </div>
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
