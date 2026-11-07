'use client';

import { useEffect, useState } from 'react';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Input, Label, Select, Textarea } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { formatDateTime, humanise } from '@/lib/format';
import { asObject, rpcCall, useRpcAction } from '@/features/shared/client-rpc';

/* ------------------------------------------------------------------ types */

export type AnnouncementFeedItem = {
  announcement_id: number;
  title: string;
  description: string;
  type_name: string;
  department_name: string | null;
  publish_from: string;
  publish_to: string | null;
};

export type ManagedAnnouncement = {
  announcement_id: number;
  title: string;
  type_name: string;
  department_name: string | null;
  audience_type: string;
  approval_status: string;
  publish_from: string;
  publish_to: string | null;
  is_mine: boolean;
  total_count: number;
};

export type AnnouncementType = {
  announcement_type_id: number;
  type_code: string;
  type_name: string;
  is_active: boolean;
};

export type DepartmentTarget = { department_id: number; department_name: string };

const AUDIENCES = ['ALL', 'STUDENTS', 'STAFF', 'DEPARTMENT'];

type FormState = {
  typeId: string;
  departmentId: string;
  title: string;
  description: string;
  publishFrom: string;
  publishTo: string;
  audience: string;
};

const EMPTY_FORM: FormState = {
  typeId: '',
  departmentId: '',
  title: '',
  description: '',
  publishFrom: '',
  publishTo: '',
  audience: 'ALL',
};

/* ---------------------------------------------------------------- helpers */

/** `2026-03-04T09:30` in the browser's own timezone, for `<input type="datetime-local">`. */
function toLocalInput(value: unknown): string {
  if (value === null || value === undefined || value === '') return '';
  const d = new Date(String(value));
  if (Number.isNaN(d.getTime())) return '';
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

/** The database stores `timestamptz`; the browser sends an absolute instant. */
function toIso(value: string): string | null {
  if (!value) return null;
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return null;
  return d.toISOString();
}

/* ------------------------------------------------------------ form fields */

function AnnouncementFormFields({
  value,
  onChange,
  types,
  targets,
  idPrefix,
}: {
  value: FormState;
  onChange: (next: FormState) => void;
  types: AnnouncementType[];
  targets: DepartmentTarget[];
  idPrefix: string;
}) {
  const set = (patch: Partial<FormState>) => onChange({ ...value, ...patch });

  return (
    <div className="space-y-3">
      <div className="grid gap-3 sm:grid-cols-3">
        <div className="space-y-1">
          <Label htmlFor={`${idPrefix}-type`}>Type</Label>
          <Select id={`${idPrefix}-type`} value={value.typeId} onChange={(e) => set({ typeId: e.target.value })}>
            <option value="">Choose a type</option>
            {types
              .filter((t) => t.is_active)
              .map((t) => (
                <option key={t.announcement_type_id} value={t.announcement_type_id}>
                  {t.type_name}
                </option>
              ))}
          </Select>
        </div>
        <div className="space-y-1">
          <Label htmlFor={`${idPrefix}-department`}>Department</Label>
          <Select id={`${idPrefix}-department`} value={value.departmentId} onChange={(e) => set({ departmentId: e.target.value })}>
            <option value="">No department (global)</option>
            {targets.map((d) => (
              <option key={d.department_id} value={d.department_id}>
                {d.department_name}
              </option>
            ))}
          </Select>
        </div>
        <div className="space-y-1">
          <Label htmlFor={`${idPrefix}-audience`}>Audience</Label>
          <Select id={`${idPrefix}-audience`} value={value.audience} onChange={(e) => set({ audience: e.target.value })}>
            {AUDIENCES.map((a) => (
              <option key={a} value={a}>
                {humanise(a)}
              </option>
            ))}
          </Select>
        </div>
      </div>

      <div className="space-y-1">
        <Label htmlFor={`${idPrefix}-title`}>Title</Label>
        <Input id={`${idPrefix}-title`} value={value.title} onChange={(e) => set({ title: e.target.value })} maxLength={250} />
      </div>

      <div className="space-y-1">
        <Label htmlFor={`${idPrefix}-description`}>Text</Label>
        <Textarea id={`${idPrefix}-description`} value={value.description} onChange={(e) => set({ description: e.target.value })} maxLength={20000} />
      </div>

      <div className="grid gap-3 sm:grid-cols-2">
        <div className="space-y-1">
          <Label htmlFor={`${idPrefix}-from`}>Publish from</Label>
          <Input id={`${idPrefix}-from`} type="datetime-local" value={value.publishFrom} onChange={(e) => set({ publishFrom: e.target.value })} />
        </div>
        <div className="space-y-1">
          <Label htmlFor={`${idPrefix}-to`}>Publish to (optional)</Label>
          <Input id={`${idPrefix}-to`} type="datetime-local" value={value.publishTo} onChange={(e) => set({ publishTo: e.target.value })} />
        </div>
      </div>
    </div>
  );
}

/** The payload every write to `announcement_save` needs. */
function saveArgs(form: FormState, id: number | null) {
  return {
    p_id: id,
    p_type_id: Number(form.typeId),
    p_department_id: form.departmentId === '' ? null : Number(form.departmentId),
    p_title: form.title.trim(),
    p_description: form.description.trim(),
    p_publish_from: toIso(form.publishFrom),
    p_publish_to: toIso(form.publishTo),
    p_audience: form.audience,
  };
}

/* --------------------------------------------------------------- composer */

export function AnnouncementComposer({
  types,
  targets,
  canPostGlobal,
}: {
  types: AnnouncementType[];
  targets: DepartmentTarget[];
  canPostGlobal: boolean;
}) {
  const { busy, error, notice, run } = useRpcAction();
  const [form, setForm] = useState<FormState>(EMPTY_FORM);

  async function save(andSubmit: boolean) {
    const saved = await run<number>('announcement_save', saveArgs(form, null), {
      success: andSubmit ? 'The announcement has been submitted for approval.' : 'The announcement has been saved as a draft.',
    });
    if (saved.ok && andSubmit) {
      await run<void>('announcement_submit', { p_id: Number(saved.data) }, { success: 'The announcement has been submitted for approval.' });
    }
    if (saved.ok) setForm(EMPTY_FORM);
  }

  const ready =
    form.typeId !== '' &&
    form.title.trim() !== '' &&
    form.description.trim() !== '' &&
    form.publishFrom !== '' &&
    (form.audience !== 'DEPARTMENT' || form.departmentId !== '');

  return (
    <div className="space-y-3">
      <AnnouncementFormFields value={form} onChange={setForm} types={types} targets={targets} idPrefix="ann-new" />
      {!canPostGlobal && targets.length === 0 ? (
        <p className="text-sm text-muted-foreground">You do not have a department you may announce to.</p>
      ) : null}
      {error ? <ErrorPanel message={error} /> : null}
      {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
      <div className="flex flex-wrap gap-2">
        <Button onClick={() => save(false)} disabled={busy || !ready}>
          {busy ? 'Saving…' : 'Save draft'}
        </Button>
        <Button variant="outline" onClick={() => save(true)} disabled={busy || !ready}>
          Save and submit
        </Button>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------ edit a draft */

function AnnouncementEditForm({
  id,
  types,
  targets,
  onClose,
}: {
  id: number;
  types: AnnouncementType[];
  targets: DepartmentTarget[];
  onClose: () => void;
}) {
  const { busy, error, notice, run } = useRpcAction();
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [form, setForm] = useState<FormState>(EMPTY_FORM);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const res = await rpcCall<Record<string, unknown>>('announcement_detail', { p_id: id });
      if (cancelled) return;
      if (!res.ok) {
        setLoadError(res.error);
        setLoading(false);
        return;
      }
      const d = asObject(res.data);
      setForm({
        typeId: d.type_id === null || d.type_id === undefined ? '' : String(d.type_id),
        departmentId: d.department_id === null || d.department_id === undefined ? '' : String(d.department_id),
        title: String(d.title ?? ''),
        description: String(d.description ?? ''),
        publishFrom: toLocalInput(d.publish_from),
        publishTo: toLocalInput(d.publish_to),
        audience: String(d.audience_type ?? 'ALL'),
      });
      setLoading(false);
    })();
    return () => {
      cancelled = true;
    };
  }, [id]);

  async function save(andSubmit: boolean) {
    const saved = await run<number>('announcement_save', saveArgs(form, id), {
      success: andSubmit ? 'The announcement has been submitted for approval.' : 'The announcement has been saved as a draft.',
    });
    if (saved.ok && andSubmit) {
      await run<void>('announcement_submit', { p_id: id }, { success: 'The announcement has been submitted for approval.' });
    }
    if (saved.ok) onClose();
  }

  if (loading) return <p className="text-sm text-muted-foreground">Loading the announcement…</p>;
  if (loadError) return <ErrorPanel message={loadError} />;

  const ready =
    form.typeId !== '' &&
    form.title.trim() !== '' &&
    form.description.trim() !== '' &&
    form.publishFrom !== '' &&
    (form.audience !== 'DEPARTMENT' || form.departmentId !== '');

  return (
    <div className="space-y-3 rounded-md border border-border p-3">
      <AnnouncementFormFields value={form} onChange={setForm} types={types} targets={targets} idPrefix={`ann-edit-${id}`} />
      {error ? <ErrorPanel message={error} /> : null}
      {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
      <div className="flex flex-wrap gap-2">
        <Button size="sm" onClick={() => save(false)} disabled={busy || !ready}>
          Save draft
        </Button>
        <Button size="sm" variant="outline" onClick={() => save(true)} disabled={busy || !ready}>
          Save and submit
        </Button>
        <Button size="sm" variant="ghost" onClick={onClose} disabled={busy}>
          Close
        </Button>
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ feed */

export function AnnouncementFeed({ rows }: { rows: AnnouncementFeedItem[] }) {
  if (rows.length === 0) {
    return <EmptyState title="No announcements" description="Nothing has been published for you yet." />;
  }

  return (
    <div className="space-y-3">
      {rows.map((a) => (
        <Card key={a.announcement_id}>
          <CardHeader>
            <CardTitle className="text-base">{a.title}</CardTitle>
            <p className="text-xs text-muted-foreground">
              {a.type_name}
              {a.department_name ? ` · ${a.department_name}` : ''} · {formatDateTime(a.publish_from)}
              {a.publish_to ? ` → ${formatDateTime(a.publish_to)}` : ''}
            </p>
          </CardHeader>
          <CardContent>
            <p className="whitespace-pre-line text-sm">{a.description}</p>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}

/* ----------------------------------------------------------- manage list */

function AnnouncementActions({
  row,
  types,
  targets,
}: {
  row: ManagedAnnouncement;
  types: AnnouncementType[];
  targets: DepartmentTarget[];
}) {
  const { busy, error, notice, run } = useRpcAction();
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState(false);
  const [loading, setLoading] = useState(false);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [detail, setDetail] = useState<Record<string, unknown> | null>(null);

  // The database says what this caller may do with this announcement, so the
  // buttons are built from `announcement_detail` rather than guessed from the row.
  async function openPanel() {
    setOpen(true);
    setLoading(true);
    setLoadError(null);
    const res = await rpcCall<Record<string, unknown>>('announcement_detail', { p_id: row.announcement_id });
    setLoading(false);
    if (!res.ok) {
      setLoadError(res.error);
      return;
    }
    setDetail(asObject(res.data));
  }

  async function submit() {
    await run<void>('announcement_submit', { p_id: row.announcement_id }, { success: 'The announcement has been submitted for approval.' });
  }

  async function decide(approve: boolean) {
    await run<void>(
      'announcement_decide',
      { p_id: row.announcement_id, p_approve: approve },
      { success: approve ? 'The announcement has been approved.' : 'The announcement has been rejected.' },
    );
  }

  async function archive() {
    await run<void>('announcement_archive', { p_id: row.announcement_id }, { success: 'The announcement has been archived.' });
  }

  const canEdit = detail?.can_edit === true;
  const canSubmit = detail?.can_submit === true;
  const canDecide = detail?.can_decide === true;
  const canArchive = detail?.can_archive === true;

  return (
    <div className="space-y-2">
      {error ? <ErrorPanel message={error} /> : null}
      {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
      {loadError ? <ErrorPanel message={loadError} /> : null}

      {!open ? (
        <Button size="sm" variant="outline" onClick={openPanel}>
          Manage
        </Button>
      ) : (
        <>
          {loading ? <p className="text-xs text-muted-foreground">Checking what you may do…</p> : null}
          {!loading && detail ? (
            <div className="flex flex-wrap gap-2">
              {canEdit ? (
                <Button size="sm" variant="outline" onClick={() => setEditing((v) => !v)} disabled={busy}>
                  {editing ? 'Close editor' : 'Edit'}
                </Button>
              ) : null}
              {canSubmit ? (
                <Button size="sm" onClick={submit} disabled={busy}>
                  Submit
                </Button>
              ) : null}
              {canDecide ? (
                <>
                  <Button size="sm" onClick={() => decide(true)} disabled={busy}>
                    Approve
                  </Button>
                  <Button size="sm" variant="destructive" onClick={() => decide(false)} disabled={busy}>
                    Reject
                  </Button>
                </>
              ) : null}
              {canArchive ? (
                <Button size="sm" variant="ghost" onClick={archive} disabled={busy}>
                  Archive
                </Button>
              ) : null}
              {!canEdit && !canSubmit && !canDecide && !canArchive ? (
                <span className="text-xs text-muted-foreground">You have no action on this announcement.</span>
              ) : null}
            </div>
          ) : null}
          {editing ? <AnnouncementEditForm id={row.announcement_id} types={types} targets={targets} onClose={() => setEditing(false)} /> : null}
        </>
      )}
    </div>
  );
}

export function AnnouncementManageList({
  rows,
  types,
  targets,
}: {
  rows: ManagedAnnouncement[];
  types: AnnouncementType[];
  targets: DepartmentTarget[];
}) {
  if (rows.length === 0) {
    return <EmptyState title="Nothing to manage" description="Announcements you author or administer appear here." />;
  }

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Title</TableHead>
          <TableHead>Type</TableHead>
          <TableHead>Department</TableHead>
          <TableHead>Audience</TableHead>
          <TableHead>Status</TableHead>
          <TableHead>Publish window</TableHead>
          <TableHead>Actions</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.map((a) => (
          <TableRow key={a.announcement_id}>
            <TableCell>
              <div className="max-w-xs font-medium">{a.title}</div>
              {a.is_mine ? <div className="text-xs text-muted-foreground">Yours</div> : null}
            </TableCell>
            <TableCell>{a.type_name}</TableCell>
            <TableCell>{a.department_name ?? '—'}</TableCell>
            <TableCell>{humanise(a.audience_type)}</TableCell>
            <TableCell>
              <Badge variant={statusVariant(a.approval_status)}>{humanise(a.approval_status)}</Badge>
            </TableCell>
            <TableCell className="text-xs">
              <div>{formatDateTime(a.publish_from)}</div>
              {a.publish_to ? <div className="text-muted-foreground">to {formatDateTime(a.publish_to)}</div> : null}
            </TableCell>
            <TableCell>
              <AnnouncementActions row={a} types={types} targets={targets} />
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
