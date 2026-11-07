'use client';

import { useEffect, useState } from 'react';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Input, Label, Select, Textarea } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { formatDate, formatDateTime, humanise } from '@/lib/format';
import { rpcCall, useRpcAction } from '@/features/shared/client-rpc';

/* ------------------------------------------------------------------ types */

export type MentoringAssignment = {
  mentor_assignment_id: number;
  student_id: number;
  student_number: string;
  student_name: string;
  employee_id: number;
  mentor_name: string;
  start_date: string | null;
  end_date: string | null;
  assignment_status: string;
  session_count: number;
  is_mine: boolean;
};

export type AssignmentInfo = {
  mentor_assignment_id: number;
  student_id: number;
  student_number: string;
  student_name: string;
  employee_id: number;
  mentor_name: string;
  start_date: string | null;
  end_date: string | null;
  assignment_status: string;
  is_mine: boolean;
  can_assign: boolean;
};

export type MentoringSession = {
  counselling_session_id: number;
  session_date: string;
  session_status: string;
  confidentiality_level: string;
  follow_up_date: string | null;
  observations: string | null;
  action_plan: string | null;
  redacted: boolean;
};

const SESSION_STATUSES = ['SCHEDULED', 'COMPLETED', 'CANCELLED', 'FOLLOW_UP_REQUIRED'];
const LEVELS = ['NORMAL', 'RESTRICTED', 'HIGHLY_RESTRICTED'];

/* --------------------------------------------------------------- helpers */

function toInfo(raw: Record<string, unknown>): AssignmentInfo {
  return {
    mentor_assignment_id: Number(raw.mentor_assignment_id),
    student_id: Number(raw.student_id),
    student_number: String(raw.student_number ?? ''),
    student_name: String(raw.student_name ?? ''),
    employee_id: Number(raw.employee_id),
    mentor_name: String(raw.mentor_name ?? ''),
    start_date: raw.start_date === null || raw.start_date === undefined ? null : String(raw.start_date),
    end_date: raw.end_date === null || raw.end_date === undefined ? null : String(raw.end_date),
    assignment_status: String(raw.assignment_status ?? ''),
    is_mine: raw.is_mine === true,
    can_assign: raw.can_assign === true,
  };
}

function toSession(raw: Record<string, unknown>): MentoringSession {
  return {
    counselling_session_id: Number(raw.counselling_session_id),
    session_date: String(raw.session_date ?? ''),
    session_status: String(raw.session_status ?? ''),
    confidentiality_level: String(raw.confidentiality_level ?? ''),
    follow_up_date: raw.follow_up_date === null || raw.follow_up_date === undefined ? null : String(raw.follow_up_date),
    observations: raw.observations === null || raw.observations === undefined ? null : String(raw.observations),
    action_plan: raw.action_plan === null || raw.action_plan === undefined ? null : String(raw.action_plan),
    redacted: raw.redacted === true,
  };
}

function today(): string {
  return new Date().toISOString().slice(0, 10);
}

/* ------------------------------------------------------------ assign form */

function AssignMentorForm() {
  const { busy, error, notice, run } = useRpcAction();
  const [studentNumber, setStudentNumber] = useState('');
  const [employeeNumber, setEmployeeNumber] = useState('');
  const [start, setStart] = useState(today());

  async function submit() {
    await run<number>(
      'mentoring_assign',
      { p_student_number: studentNumber.trim(), p_employee_number: employeeNumber.trim(), p_start: start || null },
      { success: 'The mentor has been assigned.' },
    );
  }

  return (
    <div className="space-y-3">
      <div className="grid gap-3 sm:grid-cols-3">
        <div className="space-y-1">
          <Label htmlFor="mentor-student">Student number</Label>
          <Input id="mentor-student" value={studentNumber} onChange={(e) => setStudentNumber(e.target.value)} placeholder="e.g. STU2024001" />
        </div>
        <div className="space-y-1">
          <Label htmlFor="mentor-employee">Employee number</Label>
          <Input id="mentor-employee" value={employeeNumber} onChange={(e) => setEmployeeNumber(e.target.value)} placeholder="e.g. EMP0012" />
        </div>
        <div className="space-y-1">
          <Label htmlFor="mentor-start">Start date</Label>
          <Input id="mentor-start" type="date" value={start} onChange={(e) => setStart(e.target.value)} />
        </div>
      </div>
      {error ? <ErrorPanel message={error} /> : null}
      {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
      <Button onClick={submit} disabled={busy || !studentNumber.trim() || !employeeNumber.trim()}>
        {busy ? 'Assigning…' : 'Assign mentor'}
      </Button>
    </div>
  );
}

/* ----------------------------------------------------------- session form */

type SessionDraft = {
  date: string;
  observations: string;
  actionPlan: string;
  followUp: string;
  status: string;
  level: string;
};

function emptyDraft(): SessionDraft {
  return {
    date: new Date().toISOString(),
    observations: '',
    actionPlan: '',
    followUp: '',
    status: 'COMPLETED',
    level: 'RESTRICTED',
  };
}

function SessionForm({
  assignmentId,
  session,
  onDone,
}: {
  assignmentId: number;
  session?: MentoringSession;
  onDone: () => void;
}) {
  const { busy, error, notice, run } = useRpcAction();
  const [draft, setDraft] = useState<SessionDraft>(() =>
    session
      ? {
          date: session.session_date,
          observations: session.observations ?? '',
          actionPlan: session.action_plan ?? '',
          followUp: session.follow_up_date ?? '',
          status: session.session_status,
          level: session.confidentiality_level,
        }
      : emptyDraft(),
  );

  async function submit() {
    const args = {
      p_date: draft.date ? new Date(draft.date).toISOString() : null,
      p_observations: draft.observations,
      p_action_plan: draft.actionPlan,
      p_follow_up: draft.followUp || null,
      p_status: draft.status,
      p_level: draft.level,
    };
    const res = session
      ? await run<void>('mentoring_update_session', { p_session_id: session.counselling_session_id, ...args }, { success: 'The session has been updated.' })
      : await run<number>('mentoring_record_session', { p_assignment_id: assignmentId, ...args }, { success: 'The session has been recorded.' });
    if (res.ok) onDone();
  }

  return (
    <div className="space-y-3">
      <div className="grid gap-3 sm:grid-cols-3">
        <div className="space-y-1">
          <Label htmlFor="session-date">Session date</Label>
          <Input id="session-date" type="datetime-local" value={draft.date} onChange={(e) => setDraft({ ...draft, date: e.target.value })} />
        </div>
        <div className="space-y-1">
          <Label htmlFor="session-status">Status</Label>
          <Select id="session-status" value={draft.status} onChange={(e) => setDraft({ ...draft, status: e.target.value })}>
            {SESSION_STATUSES.map((s) => (
              <option key={s} value={s}>
                {humanise(s)}
              </option>
            ))}
          </Select>
        </div>
        <div className="space-y-1">
          <Label htmlFor="session-level">Confidentiality</Label>
          <Select id="session-level" value={draft.level} onChange={(e) => setDraft({ ...draft, level: e.target.value })}>
            {LEVELS.map((s) => (
              <option key={s} value={s}>
                {humanise(s)}
              </option>
            ))}
          </Select>
        </div>
      </div>
      <div className="space-y-1">
        <Label htmlFor="session-followup">Follow-up date</Label>
        <Input id="session-followup" type="date" value={draft.followUp} onChange={(e) => setDraft({ ...draft, followUp: e.target.value })} />
      </div>
      <div className="space-y-1">
        <Label htmlFor="session-observations">Observations</Label>
        <Textarea id="session-observations" value={draft.observations} onChange={(e) => setDraft({ ...draft, observations: e.target.value })} />
      </div>
      <div className="space-y-1">
        <Label htmlFor="session-action">Action plan</Label>
        <Textarea id="session-action" value={draft.actionPlan} onChange={(e) => setDraft({ ...draft, actionPlan: e.target.value })} />
      </div>
      {error ? <ErrorPanel message={error} /> : null}
      {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
      <Button onClick={submit} disabled={busy}>
        {busy ? 'Saving…' : session ? 'Save session' : 'Record session'}
      </Button>
    </div>
  );
}

/* -------------------------------------------------------------- workspace */

export function MentoringWorkspace({ assignments }: { assignments: MentoringAssignment[] }) {
  const [selectedId, setSelectedId] = useState<number | null>(
    assignments.length > 0 ? (assignments[0]?.mentor_assignment_id ?? null) : null,
  );
  const [info, setInfo] = useState<AssignmentInfo | null>(null);
  const [sessions, setSessions] = useState<MentoringSession[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [editing, setEditing] = useState<{ session?: MentoringSession } | null>(null);
  const [showAssign, setShowAssign] = useState(false);
  const [endStatus, setEndStatus] = useState('COMPLETED');
  const [endDate, setEndDate] = useState(today());
  const endAction = useRpcAction();

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      if (selectedId === null) {
        setInfo(null);
        setSessions([]);
        return;
      }
      setLoading(true);
      const [infoRes, sessionRes] = await Promise.all([
        rpcCall<Record<string, unknown>[]>('mentoring_assignment_info', { p_assignment_id: selectedId }),
        rpcCall<Record<string, unknown>[]>('mentoring_sessions', { p_assignment_id: selectedId }),
      ]);
      if (cancelled) return;
      setLoading(false);
      if (!infoRes.ok) {
        setError(infoRes.error);
        setInfo(null);
      } else {
        setError(null);
        setInfo(toInfo(infoRes.data[0] ?? {}));
      }
      if (!sessionRes.ok) {
        setError(sessionRes.error);
        setSessions([]);
      } else {
        setSessions(sessionRes.data.map(toSession));
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [selectedId]);

  async function endAssignment() {
    if (selectedId === null) return;
    await endAction.run<void>(
      'mentoring_end_assignment',
      { p_assignment_id: selectedId, p_status: endStatus, p_end_date: endDate || null },
      { success: 'The assignment has ended.' },
    );
  }

  return (
    <div className="grid gap-4 lg:grid-cols-[minmax(0,22rem)_minmax(0,1fr)]">
      <Card>
        <CardHeader>
          <CardTitle>Mentoring assignments</CardTitle>
        </CardHeader>
        <CardContent className="space-y-2">
          {assignments.length === 0 ? (
            <EmptyState title="No mentoring assignments" description="Assignments you create or can read appear here." />
          ) : (
            <ul className="space-y-2">
              {assignments.map((a) => (
                <li key={a.mentor_assignment_id}>
                  <button
                    type="button"
                    onClick={() => {
                      setSelectedId(a.mentor_assignment_id);
                      setEditing(null);
                    }}
                    className={`w-full rounded-md border p-3 text-left text-sm transition-colors hover:bg-muted ${
                      selectedId === a.mentor_assignment_id ? 'border-primary bg-muted' : 'border-border'
                    }`}
                  >
                    <div className="flex items-center justify-between gap-2">
                      <span className="font-medium">{a.student_name}</span>
                      <Badge variant={statusVariant(a.assignment_status)}>{humanise(a.assignment_status)}</Badge>
                    </div>
                    <div className="mt-1 text-xs text-muted-foreground">
                      {a.student_number} · mentor {a.mentor_name} · {a.session_count} session{a.session_count === 1 ? '' : 's'}
                    </div>
                  </button>
                </li>
              ))}
            </ul>
          )}

          <Button variant="outline" className="mt-2 w-full" onClick={() => setShowAssign((v) => !v)}>
            {showAssign ? 'Hide the assignment form' : 'Assign a mentor'}
          </Button>
          {showAssign ? (
            <div className="mt-3">
              <AssignMentorForm />
            </div>
          ) : null}
        </CardContent>
      </Card>

      <div className="space-y-4">
        {error ? <ErrorPanel message={error} /> : null}
        {loading ? <p className="text-sm text-muted-foreground">Loading…</p> : null}

        {info ? (
          <Card>
            <CardHeader>
              <CardTitle className="flex flex-wrap items-center justify-between gap-2">
                <span>{info.student_name}</span>
                <Badge variant={statusVariant(info.assignment_status)}>{humanise(info.assignment_status)}</Badge>
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-4">
              <dl className="grid gap-x-6 gap-y-1 text-sm sm:grid-cols-2">
                <div className="flex gap-2">
                  <dt className="text-muted-foreground">Student</dt>
                  <dd>{info.student_number}</dd>
                </div>
                <div className="flex gap-2">
                  <dt className="text-muted-foreground">Mentor</dt>
                  <dd>{info.mentor_name}</dd>
                </div>
                <div className="flex gap-2">
                  <dt className="text-muted-foreground">Started</dt>
                  <dd>{formatDate(info.start_date)}</dd>
                </div>
                <div className="flex gap-2">
                  <dt className="text-muted-foreground">Ended</dt>
                  <dd>{formatDate(info.end_date)}</dd>
                </div>
              </dl>

              {info.assignment_status === 'ACTIVE' ? (
                <div className="rounded-md border border-border p-3">
                  <p className="mb-2 text-sm font-medium">End this assignment</p>
                  <div className="grid gap-3 sm:grid-cols-2">
                    <div className="space-y-1">
                      <Label htmlFor="end-status">Outcome</Label>
                      <Select id="end-status" value={endStatus} onChange={(e) => setEndStatus(e.target.value)}>
                        <option value="COMPLETED">Completed</option>
                        <option value="CANCELLED">Cancelled</option>
                      </Select>
                    </div>
                    <div className="space-y-1">
                      <Label htmlFor="end-date">End date</Label>
                      <Input id="end-date" type="date" value={endDate} onChange={(e) => setEndDate(e.target.value)} />
                    </div>
                  </div>
                  {endAction.error ? <ErrorPanel message={endAction.error} /> : null}
                  {endAction.notice ? <p className="mt-2 text-sm text-emerald-700">{endAction.notice}</p> : null}
                  <Button className="mt-2" variant="outline" onClick={endAssignment} disabled={endAction.busy}>
                    {endAction.busy ? 'Saving…' : 'End assignment'}
                  </Button>
                </div>
              ) : null}
            </CardContent>
          </Card>
        ) : null}

        <Card>
          <CardHeader>
            <CardTitle>Counselling sessions</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {sessions.length === 0 ? (
              <EmptyState title="No sessions recorded yet" description="Record the first counselling session for this assignment." />
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Date</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead>Confidentiality</TableHead>
                    <TableHead>Follow-up</TableHead>
                    <TableHead>Notes</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {sessions.map((s) => (
                    <TableRow key={s.counselling_session_id}>
                      <TableCell>{formatDateTime(s.session_date)}</TableCell>
                      <TableCell>
                        <Badge variant={statusVariant(s.session_status)}>{humanise(s.session_status)}</Badge>
                      </TableCell>
                      <TableCell>{humanise(s.confidentiality_level)}</TableCell>
                      <TableCell>{formatDate(s.follow_up_date)}</TableCell>
                      <TableCell className="max-w-xs">
                        {s.redacted ? (
                          <span className="text-muted-foreground">Restricted</span>
                        ) : (
                          <span className="text-xs">{s.observations ?? '—'}</span>
                        )}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}

            {editing ? (
              <div className="rounded-md border border-border p-3">
                <SessionForm
                  assignmentId={selectedId ?? 0}
                  session={editing.session}
                  onDone={() => setEditing(null)}
                />
              </div>
            ) : (
              <div className="flex flex-wrap gap-2">
                <Button onClick={() => setEditing({})}>Record a session</Button>
                {sessions.length > 0 ? (
                  <Button variant="outline" onClick={() => setEditing({ session: sessions[0] })}>
                    Edit the latest session
                  </Button>
                ) : null}
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
