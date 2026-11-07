'use client';

import { useEffect, useState } from 'react';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Input, Label, Select, Textarea } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { formatDateTime, humanise } from '@/lib/format';
import { asArray, asObject, rpcCall, useRpcAction } from '@/features/shared/client-rpc';

/* ------------------------------------------------------------------ types */

export type GrievanceRow = {
  grievance_id: number;
  grievance_number: string;
  student_number: string;
  student_name: string;
  category_name: string;
  subject: string;
  priority: string;
  status: string;
  submitted_at: string;
};

export type MyGrievance = {
  grievance_id: number;
  grievance_number: string;
  category_name: string;
  subject: string;
  priority: string;
  status: string;
  submitted_at: string;
  resolved_at: string | null;
};

export type GrievanceDetail = {
  grievance_id: number;
  grievance_number: string;
  student_number: string;
  student_name: string;
  category_name: string;
  department_name: string | null;
  subject: string;
  description: string;
  priority: string;
  status: string;
  submitted_at: string;
  resolved_at: string | null;
  resolution: string | null;
  is_owner: boolean;
  can_act: boolean;
  actions: { action_at: string; action_type: string; action_notes: string | null; new_status: string | null }[];
};

export type Lookup = { id: number; label: string };

const PRIORITIES = ['LOW', 'NORMAL', 'HIGH', 'URGENT'];
const STATUSES = ['SUBMITTED', 'ASSIGNED', 'UNDER_REVIEW', 'RESOLVED', 'REJECTED', 'CLOSED'];

/* --------------------------------------------------------------- helpers */

function toDetail(raw: unknown): GrievanceDetail {
  const o = asObject(raw);
  const actions = asArray<Record<string, unknown>>(o.actions).map((a) => ({
    action_at: String(a.action_at ?? ''),
    action_type: String(a.action_type ?? ''),
    action_notes: a.action_notes === null || a.action_notes === undefined ? null : String(a.action_notes),
    new_status: a.new_status === null || a.new_status === undefined ? null : String(a.new_status),
  }));
  return {
    grievance_id: Number(o.grievance_id),
    grievance_number: String(o.grievance_number ?? ''),
    student_number: String(o.student_number ?? ''),
    student_name: String(o.student_name ?? ''),
    category_name: String(o.category_name ?? ''),
    department_name: o.department_name === null || o.department_name === undefined ? null : String(o.department_name),
    subject: String(o.subject ?? ''),
    description: String(o.description ?? ''),
    priority: String(o.priority ?? ''),
    status: String(o.status ?? ''),
    submitted_at: String(o.submitted_at ?? ''),
    resolved_at: o.resolved_at === null || o.resolved_at === undefined ? null : String(o.resolved_at),
    resolution: o.resolution === null || o.resolution === undefined ? null : String(o.resolution),
    is_owner: o.is_owner === true,
    can_act: o.can_act === true,
    actions,
  };
}

/* --------------------------------------------------------- student: submit */

export function GrievanceSubmitForm({ categories, departments }: { categories: Lookup[]; departments: Lookup[] }) {
  const { busy, error, notice, run } = useRpcAction();
  const [categoryId, setCategoryId] = useState('');
  const [departmentId, setDepartmentId] = useState('');
  const [subject, setSubject] = useState('');
  const [description, setDescription] = useState('');
  const [priority, setPriority] = useState('NORMAL');

  async function submit() {
    await run<number>(
      'grievance_submit',
      {
        p_category_id: Number(categoryId),
        p_department_id: departmentId === '' ? null : Number(departmentId),
        p_subject: subject,
        p_description: description,
        p_priority: priority,
      },
      { success: 'Your grievance has been submitted.' },
    );
    setSubject('');
    setDescription('');
  }

  return (
    <div className="space-y-3">
      <div className="grid gap-3 sm:grid-cols-3">
        <div className="space-y-1">
          <Label htmlFor="grievance-category">Category</Label>
          <Select id="grievance-category" value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>
            <option value="">Choose a category</option>
            {categories.map((c) => (
              <option key={c.id} value={c.id}>
                {c.label}
              </option>
            ))}
          </Select>
        </div>
        <div className="space-y-1">
          <Label htmlFor="grievance-department">Department (optional)</Label>
          <Select id="grievance-department" value={departmentId} onChange={(e) => setDepartmentId(e.target.value)}>
            <option value="">No specific department</option>
            {departments.map((d) => (
              <option key={d.id} value={d.id}>
                {d.label}
              </option>
            ))}
          </Select>
        </div>
        <div className="space-y-1">
          <Label htmlFor="grievance-priority">Priority</Label>
          <Select id="grievance-priority" value={priority} onChange={(e) => setPriority(e.target.value)}>
            {PRIORITIES.map((p) => (
              <option key={p} value={p}>
                {humanise(p)}
              </option>
            ))}
          </Select>
        </div>
      </div>
      <div className="space-y-1">
        <Label htmlFor="grievance-subject">Subject</Label>
        <Input id="grievance-subject" value={subject} onChange={(e) => setSubject(e.target.value)} maxLength={200} />
      </div>
      <div className="space-y-1">
        <Label htmlFor="grievance-description">Description</Label>
        <Textarea id="grievance-description" value={description} onChange={(e) => setDescription(e.target.value)} maxLength={5000} />
      </div>
      {error ? <ErrorPanel message={error} /> : null}
      {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
      <Button onClick={submit} disabled={busy || !categoryId || !subject.trim() || !description.trim()}>
        {busy ? 'Submitting…' : 'Submit grievance'}
      </Button>
    </div>
  );
}

/* ------------------------------------------------------ student: my cases */

function RespondControl({ grievance }: { grievance: MyGrievance }) {
  const { busy, error, notice, run } = useRpcAction();
  const [notes, setNotes] = useState('');
  const [open, setOpen] = useState(false);

  const canClose = grievance.status === 'RESOLVED' || grievance.status === 'REJECTED';
  const canReopen = grievance.status === 'RESOLVED';
  if (!canClose && !canReopen) return null;

  async function respond(response: 'CLOSE' | 'REOPEN') {
    await run<void>(
      'grievance_student_respond',
      { p_grievance_id: grievance.grievance_id, p_response: response, p_notes: notes.trim() || null },
      { success: response === 'CLOSE' ? 'The grievance has been closed.' : 'The grievance has been re-opened.' },
    );
    setOpen(false);
  }

  return (
    <div className="space-y-2">
      {open ? (
        <>
          <div className="space-y-1">
            <Label htmlFor={`respond-${grievance.grievance_id}`}>Note (optional)</Label>
            <Textarea
              id={`respond-${grievance.grievance_id}`}
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              maxLength={2000}
            />
          </div>
          {error ? <ErrorPanel message={error} /> : null}
          {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
          <div className="flex gap-2">
            {canClose ? (
              <Button size="sm" onClick={() => respond('CLOSE')} disabled={busy}>
                Close
              </Button>
            ) : null}
            {canReopen ? (
              <Button size="sm" variant="outline" onClick={() => respond('REOPEN')} disabled={busy}>
                Re-open
              </Button>
            ) : null}
            <Button size="sm" variant="ghost" onClick={() => setOpen(false)} disabled={busy}>
              Cancel
            </Button>
          </div>
        </>
      ) : (
        <Button size="sm" variant="outline" onClick={() => setOpen(true)}>
          Respond
        </Button>
      )}
    </div>
  );
}

export function MyGrievances({ rows }: { rows: MyGrievance[] }) {
  if (rows.length === 0) {
    return <EmptyState title="You have not raised any grievances" description="Use the form above to raise one." />;
  }
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Number</TableHead>
          <TableHead>Category</TableHead>
          <TableHead>Subject</TableHead>
          <TableHead>Priority</TableHead>
          <TableHead>Status</TableHead>
          <TableHead>Submitted</TableHead>
          <TableHead />
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.map((g) => (
          <TableRow key={g.grievance_id}>
            <TableCell className="font-mono text-xs">{g.grievance_number}</TableCell>
            <TableCell>{g.category_name}</TableCell>
            <TableCell className="max-w-xs">{g.subject}</TableCell>
            <TableCell>
              <Badge variant={statusVariant(g.priority)}>{humanise(g.priority)}</Badge>
            </TableCell>
            <TableCell>
              <Badge variant={statusVariant(g.status)}>{humanise(g.status)}</Badge>
            </TableCell>
            <TableCell>{formatDateTime(g.submitted_at)}</TableCell>
            <TableCell>
              <RespondControl grievance={g} />
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}

/* --------------------------------------------------------- staff: the desk */

export function GrievanceDesk() {
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState('');
  const [priority, setPriority] = useState('');
  const [rows, setRows] = useState<GrievanceRow[]>([]);
  const [listError, setListError] = useState<string | null>(null);
  const [selectedId, setSelectedId] = useState<number | null>(null);
  const [detail, setDetail] = useState<GrievanceDetail | null>(null);
  const [detailError, setDetailError] = useState<string | null>(null);
  const [actionType, setActionType] = useState('COMMENT');
  const [notes, setNotes] = useState('');
  const [newStatus, setNewStatus] = useState('UNDER_REVIEW');
  const [resolution, setResolution] = useState('');
  const { busy, error, notice, run } = useRpcAction();

  async function loadList() {
    const res = await rpcCall<Record<string, unknown>[]>('grievance_list', {
      p_search: search.trim() || null,
      p_status: status || null,
      p_priority: priority || null,
      p_limit: 50,
      p_offset: 0,
    });
    if (!res.ok) {
      setListError(res.error);
      setRows([]);
      return;
    }
    setListError(null);
    setRows(
      res.data.map((r) => ({
        grievance_id: Number(r.grievance_id),
        grievance_number: String(r.grievance_number ?? ''),
        student_number: String(r.student_number ?? ''),
        student_name: String(r.student_name ?? ''),
        category_name: String(r.category_name ?? ''),
        subject: String(r.subject ?? ''),
        priority: String(r.priority ?? ''),
        status: String(r.status ?? ''),
        submitted_at: String(r.submitted_at ?? ''),
      })),
    );
  }

  useEffect(() => {
    void (async () => {
      await loadList();
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      if (selectedId === null) {
        setDetail(null);
        return;
      }
      const res = await rpcCall<unknown>('grievance_detail', { p_grievance_id: selectedId });
      if (cancelled) return;
      if (!res.ok) {
        setDetailError(res.error);
        setDetail(null);
        return;
      }
      setDetailError(null);
      setDetail(toDetail(res.data));
    })();
    return () => {
      cancelled = true;
    };
  }, [selectedId]);

  async function act() {
    if (selectedId === null) return;
    const args: Record<string, unknown> = {
      p_grievance_id: selectedId,
      p_action_type: actionType,
      p_notes: notes.trim() || null,
    };
    if (actionType === 'STATUS_CHANGE') {
      args.p_new_status = newStatus;
      args.p_resolution = resolution.trim() || null;
    }
    const res = await run<void>('grievance_act', args, { success: 'The grievance has been updated.' });
    if (res.ok) {
      setNotes('');
      setResolution('');
      await loadList();
    }
  }

  return (
    <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
      <div className="space-y-3">
        <div className="grid gap-3 sm:grid-cols-3">
          <div className="space-y-1">
            <Label htmlFor="grievance-search">Search</Label>
            <Input id="grievance-search" value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Number, subject or student" />
          </div>
          <div className="space-y-1">
            <Label htmlFor="grievance-status-filter">Status</Label>
            <Select id="grievance-status-filter" value={status} onChange={(e) => setStatus(e.target.value)}>
              <option value="">Any status</option>
              {STATUSES.map((s) => (
                <option key={s} value={s}>
                  {humanise(s)}
                </option>
              ))}
            </Select>
          </div>
          <div className="space-y-1">
            <Label htmlFor="grievance-priority-filter">Priority</Label>
            <Select id="grievance-priority-filter" value={priority} onChange={(e) => setPriority(e.target.value)}>
              <option value="">Any priority</option>
              {PRIORITIES.map((p) => (
                <option key={p} value={p}>
                  {humanise(p)}
                </option>
              ))}
            </Select>
          </div>
        </div>
        <Button variant="outline" onClick={() => void loadList()}>
          Apply filters
        </Button>

        {listError ? <ErrorPanel message={listError} /> : null}

        {rows.length === 0 ? (
          <EmptyState title="No grievances match" description="Adjust the filters or wait for new cases." />
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Number</TableHead>
                <TableHead>Student</TableHead>
                <TableHead>Subject</TableHead>
                <TableHead>Priority</TableHead>
                <TableHead>Status</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((g) => (
                <TableRow
                  key={g.grievance_id}
                  onClick={() => setSelectedId(g.grievance_id)}
                  className={selectedId === g.grievance_id ? 'bg-muted' : 'cursor-pointer'}
                >
                  <TableCell className="font-mono text-xs">{g.grievance_number}</TableCell>
                  <TableCell>
                    <div>{g.student_name}</div>
                    <div className="text-xs text-muted-foreground">{g.student_number}</div>
                  </TableCell>
                  <TableCell className="max-w-xs">{g.subject}</TableCell>
                  <TableCell>
                    <Badge variant={statusVariant(g.priority)}>{humanise(g.priority)}</Badge>
                  </TableCell>
                  <TableCell>
                    <Badge variant={statusVariant(g.status)}>{humanise(g.status)}</Badge>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Case detail</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          {detailError ? <ErrorPanel message={detailError} /> : null}
          {!detail ? (
            <EmptyState title="Select a grievance" description="Choose a row on the left to read its history." />
          ) : (
            <>
              <div>
                <p className="font-medium">{detail.subject}</p>
                <p className="text-xs text-muted-foreground">
                  {detail.grievance_number} · {detail.category_name} · {detail.student_name} ({detail.student_number})
                </p>
              </div>
              <div className="flex flex-wrap gap-2">
                <Badge variant={statusVariant(detail.status)}>{humanise(detail.status)}</Badge>
                <Badge variant={statusVariant(detail.priority)}>{humanise(detail.priority)}</Badge>
              </div>
              <p className="whitespace-pre-wrap text-sm">{detail.description}</p>
              {detail.resolution ? (
                <div className="rounded-md border border-border p-3 text-sm">
                  <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Resolution</p>
                  <p className="mt-1 whitespace-pre-wrap">{detail.resolution}</p>
                </div>
              ) : null}

              <div className="space-y-2">
                <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">History</p>
                {detail.actions.length === 0 ? (
                  <p className="text-sm text-muted-foreground">No actions recorded yet.</p>
                ) : (
                  <ul className="space-y-2">
                    {detail.actions.map((a, i) => (
                      <li key={`${a.action_at}-${i}`} className="rounded border border-border p-2 text-sm">
                        <div className="flex flex-wrap items-center justify-between gap-2">
                          <Badge variant="muted">{humanise(a.action_type)}</Badge>
                          <span className="text-xs text-muted-foreground">{formatDateTime(a.action_at)}</span>
                        </div>
                        {a.new_status ? <p className="mt-1 text-xs">New status: {humanise(a.new_status)}</p> : null}
                        {a.action_notes ? <p className="mt-1 whitespace-pre-wrap">{a.action_notes}</p> : null}
                      </li>
                    ))}
                  </ul>
                )}
              </div>

              {detail.can_act ? (
                <div className="space-y-3 rounded-md border border-border p-3">
                  <p className="text-sm font-medium">Act on this case</p>
                  <div className="grid gap-3 sm:grid-cols-2">
                    <div className="space-y-1">
                      <Label htmlFor="grievance-action">Action</Label>
                      <Select id="grievance-action" value={actionType} onChange={(e) => setActionType(e.target.value)}>
                        <option value="COMMENT">Comment (visible to the student)</option>
                        <option value="INTERNAL_NOTE">Internal note</option>
                        <option value="STATUS_CHANGE">Change the status</option>
                      </Select>
                    </div>
                    {actionType === 'STATUS_CHANGE' ? (
                      <div className="space-y-1">
                        <Label htmlFor="grievance-new-status">New status</Label>
                        <Select id="grievance-new-status" value={newStatus} onChange={(e) => setNewStatus(e.target.value)}>
                          {STATUSES.map((s) => (
                            <option key={s} value={s}>
                              {humanise(s)}
                            </option>
                          ))}
                        </Select>
                      </div>
                    ) : null}
                  </div>
                  <div className="space-y-1">
                    <Label htmlFor="grievance-notes">Notes</Label>
                    <Textarea id="grievance-notes" value={notes} onChange={(e) => setNotes(e.target.value)} maxLength={2000} />
                  </div>
                  {actionType === 'STATUS_CHANGE' ? (
                    <div className="space-y-1">
                      <Label htmlFor="grievance-resolution">Resolution (required to resolve or reject)</Label>
                      <Textarea id="grievance-resolution" value={resolution} onChange={(e) => setResolution(e.target.value)} maxLength={5000} />
                    </div>
                  ) : null}
                  {error ? <ErrorPanel message={error} /> : null}
                  {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
                  <Button onClick={act} disabled={busy}>
                    {busy ? 'Saving…' : 'Record the action'}
                  </Button>
                </div>
              ) : null}
            </>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
