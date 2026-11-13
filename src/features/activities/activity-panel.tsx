'use client';

import { useState } from 'react';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input, Select } from '@/components/ui/input';
import { rpcCall, signedDocumentUrl, useRpcAction } from '@/features/shared/client-rpc';
import { FileUploadField, type PickedFile } from '@/features/shared/file-upload-field';
import { formatDate, formatNumber, humanise } from '@/lib/format';
import { type EvidenceRow, type Option, type StudentActivityDetail, type StudentOption } from './types';

/**
 * One student activity, in full.
 *
 * The team, the evidence and the review decisions are separate families of
 * `student_activity_*` functions, each with its own rules. The browser sends the
 * move and shows the refusal; the database decides whether it is allowed.
 */

const VERIFY_DECISIONS = ['VERIFIED', 'NEEDS_CORRECTION', 'REJECTED'];
const APPROVE_DECISIONS = ['APPROVED', 'REJECTED'];

export function ActivityPanel({
  detail,
  documentTypes,
  evidenceTypes,
  students,
  onChanged,
  onClosed,
  onEdit,
}: {
  detail: StudentActivityDetail;
  documentTypes: Option[];
  evidenceTypes: Option[];
  students: StudentOption[];
  onChanged: () => void;
  onClosed: () => void;
  onEdit: () => void;
}) {
  const { run, busy, error } = useRpcAction();
  const [actionError, setActionError] = useState<string | null>(null);
  const [reviewStep, setReviewStep] = useState<'VERIFY' | 'APPROVE' | null>(null);
  const [decision, setDecision] = useState('');
  const [remarks, setRemarks] = useState('');
  const [deleteReason, setDeleteReason] = useState('');
  const [showDelete, setShowDelete] = useState(false);

  async function act(fn: string, args: Record<string, unknown>) {
    const result = await run(fn, args);
    if (result.ok) {
      setActionError(null);
      onChanged();
    } else {
      setActionError(result.error);
    }
  }

  async function review() {
    if (!reviewStep || !decision) return;
    const result = await run('student_activity_review', {
      p_activity_id: detail.student_activity_id,
      p_step: reviewStep,
      p_decision: decision,
      p_remarks: remarks.trim() || null,
    });
    if (result.ok) {
      setReviewStep(null);
      setDecision('');
      setRemarks('');
      setActionError(null);
      onChanged();
    } else {
      setActionError(result.error);
    }
  }

  return (
    <section className="rounded-lg border border-border bg-card p-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h3 className="text-base font-semibold">{detail.activity_title}</h3>
          <p className="mt-1 text-sm text-muted-foreground">
            {detail.student_name} · {detail.student_number} · {detail.type_name}
          </p>
          <div className="mt-2 flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
            <Badge variant={statusVariant(detail.verification_status)}>{detail.verification_status}</Badge>
            <Badge variant={statusVariant(detail.approval_status)}>{detail.approval_status}</Badge>
            <span>{formatDate(detail.start_date)}</span>
            {detail.end_date ? <span>to {formatDate(detail.end_date)}</span> : null}
            {detail.is_owner ? <span>· your record</span> : null}
          </div>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button size="sm" variant="ghost" onClick={onClosed}>
            Close
          </Button>
          {detail.can_edit ? (
            <Button size="sm" variant="outline" onClick={onEdit}>
              Edit
            </Button>
          ) : null}
          {detail.can_edit ? (
            <Button
              size="sm"
              disabled={busy}
              onClick={() => void act('student_activity_submit', { p_activity_id: detail.student_activity_id })}
            >
              Submit
            </Button>
          ) : null}
          {detail.can_verify ? (
            <Button
              size="sm"
              variant="outline"
              onClick={() => {
                setReviewStep('VERIFY');
                setDecision('VERIFIED');
                setRemarks('');
              }}
            >
              Verify
            </Button>
          ) : null}
          {detail.can_approve ? (
            <Button
              size="sm"
              variant="outline"
              onClick={() => {
                setReviewStep('APPROVE');
                setDecision('APPROVED');
                setRemarks('');
              }}
            >
              Approve
            </Button>
          ) : null}
          {detail.can_delete ? (
            <Button size="sm" variant="destructive" onClick={() => setShowDelete((v) => !v)}>
              Delete
            </Button>
          ) : null}
        </div>
      </div>

      {error || actionError ? (
        <p className="mt-3 rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800">{error ?? actionError}</p>
      ) : null}

      {detail.rejection_reason ? (
        <p className="mt-3 rounded-md border border-amber-200 bg-amber-50 p-2 text-sm text-amber-900">
          Rejected: {detail.rejection_reason}
        </p>
      ) : null}

      {showDelete && detail.can_delete ? (
        <div className="mt-3 rounded-lg border border-border p-3">
          <h4 className="mb-2 text-sm font-semibold">Delete this activity</h4>
          <div className="flex flex-wrap items-end gap-2">
            <div className="min-w-[16rem] flex-1">
              <label htmlFor="activity-delete-reason" className="mb-1 block text-sm font-medium leading-none">
                Reason (optional)
              </label>
              <Input
                id="activity-delete-reason"
                value={deleteReason}
                onChange={(e) => setDeleteReason(e.target.value)}
                maxLength={1000}
              />
            </div>
            <Button
              size="sm"
              variant="destructive"
              disabled={busy}
              onClick={() =>
                void act('student_activity_delete', {
                  p_activity_id: detail.student_activity_id,
                  p_reason: deleteReason.trim() || null,
                }).then(() => setShowDelete(false))
              }
            >
              Delete
            </Button>
            <Button size="sm" variant="ghost" onClick={() => setShowDelete(false)}>
              Keep
            </Button>
          </div>
        </div>
      ) : null}

      {reviewStep ? (
        <div className="mt-3 rounded-lg border border-border p-3">
          <h4 className="mb-2 text-sm font-semibold">{reviewStep === 'VERIFY' ? 'Verification' : 'Approval'}</h4>
          <div className="flex flex-wrap items-end gap-2">
            <div className="min-w-[12rem]">
              <label htmlFor="activity-decision" className="mb-1 block text-sm font-medium leading-none">
                Decision
              </label>
              <Select id="activity-decision" value={decision} onChange={(e) => setDecision(e.target.value)}>
                {(reviewStep === 'VERIFY' ? VERIFY_DECISIONS : APPROVE_DECISIONS).map((d) => (
                  <option key={d} value={d}>
                    {humanise(d)}
                  </option>
                ))}
              </Select>
            </div>
            <div className="min-w-[16rem] flex-1">
              <label htmlFor="activity-remarks" className="mb-1 block text-sm font-medium leading-none">
                Remarks
              </label>
              <Input
                id="activity-remarks"
                value={remarks}
                onChange={(e) => setRemarks(e.target.value)}
                maxLength={1000}
                placeholder="Required unless the record is verified or approved"
              />
            </div>
            <Button size="sm" disabled={busy} onClick={() => void review()}>
              Record
            </Button>
            <Button size="sm" variant="ghost" onClick={() => setReviewStep(null)}>
              Cancel
            </Button>
          </div>
        </div>
      ) : null}

      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        <div>
          <h4 className="text-sm font-semibold">Summary</h4>
          <dl className="mt-2 grid gap-2 text-sm sm:grid-cols-2">
            <Field label="Start date" value={formatDate(detail.start_date)} />
            <Field label="End date" value={formatDate(detail.end_date)} />
            <Field label="Event" value={detail.event_name ?? '—'} />
            <Field label="Team" value={detail.team_name ?? '—'} />
            <Field label="Role" value={detail.participation_role ?? '—'} />
            <Field label="Organiser" value={detail.organizer_name ?? '—'} />
            <Field label="Venue" value={detail.venue_name ?? '—'} />
            <Field label="City" value={detail.city ?? '—'} />
            <Field label="Achievement" value={humanise(detail.achievement_type)} />
            <Field label="Position" value={detail.position_rank ? formatNumber(detail.position_rank) : '—'} />
            <Field label="Award" value={detail.award_name ?? '—'} />
            <Field label="Evidence" value={formatNumber(detail.evidence.length)} />
          </dl>
          {detail.activity_url ? (
            <p className="mt-2 text-sm">
              <a
                href={detail.activity_url}
                target="_blank"
                rel="noreferrer noopener"
                className="font-medium text-primary underline-offset-4 hover:underline"
              >
                {detail.activity_url}
              </a>
            </p>
          ) : null}
          {detail.description ? (
            <div className="mt-3">
              <h5 className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Description</h5>
              <p className="mt-1 whitespace-pre-line text-sm">{detail.description}</p>
            </div>
          ) : null}
          {detail.outcomes ? (
            <div className="mt-3">
              <h5 className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Outcomes</h5>
              <p className="mt-1 whitespace-pre-line text-sm">{detail.outcomes}</p>
            </div>
          ) : null}
        </div>

        <div>
          <h4 className="text-sm font-semibold">Record</h4>
          <dl className="mt-2 grid gap-2 text-sm sm:grid-cols-2">
            <Field label="Academic year" value={detail.academic_year_id ? `#${detail.academic_year_id}` : '—'} />
            <Field
              label="Participation level"
              value={detail.participation_level_id ? `#${detail.participation_level_id}` : '—'}
            />
            <Field label="Event mode" value={detail.event_mode_id ? `#${detail.event_mode_id}` : '—'} />
            <Field label="Verification remarks" value={detail.verification_remarks ?? '—'} />
            <Field label="Approval remarks" value={detail.approval_remarks ?? '—'} />
            <Field label="Team members" value={formatNumber(detail.team.length)} />
          </dl>
        </div>
      </div>

      <Team detail={detail} students={students} onChanged={onChanged} />
      <Evidence detail={detail} documentTypes={documentTypes} evidenceTypes={evidenceTypes} onChanged={onChanged} />
    </section>
  );
}

/* ------------------------------------------------------------------ */
/* Team                                                                */
/* ------------------------------------------------------------------ */

function Team({
  detail,
  students,
  onChanged,
}: {
  detail: StudentActivityDetail;
  students: StudentOption[];
  onChanged: () => void;
}) {
  const { run, busy, error } = useRpcAction();
  const [adding, setAdding] = useState(false);
  const [studentId, setStudentId] = useState('');
  const [externalName, setExternalName] = useState('');
  const [externalEmail, setExternalEmail] = useState('');
  const [role, setRole] = useState('');
  const [isLead, setIsLead] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  async function add(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const student = studentId ? Number(studentId) : null;
    const external = externalName.trim();
    if ((student === null) === (external === '')) {
      setFormError('Give either a student or an external member name — not both.');
      return;
    }
    setFormError(null);

    const result = await run<number>('student_activity_team_add', {
      p_activity_id: detail.student_activity_id,
      p_student_id: student,
      p_external_name: external || null,
      p_external_email: externalEmail.trim() || null,
      p_role: role.trim() || null,
      p_is_lead: isLead,
    });
    if (result.ok) {
      setStudentId('');
      setExternalName('');
      setExternalEmail('');
      setRole('');
      setIsLead(false);
      onChanged();
    }
  }

  return (
    <section className="mt-4 rounded-lg border border-border p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h4 className="text-sm font-semibold">Team ({detail.team.length})</h4>
        {detail.can_edit ? (
          <Button size="sm" variant="outline" onClick={() => setAdding((v) => !v)}>
            {adding ? 'Close' : 'Add a member'}
          </Button>
        ) : null}
      </div>

      {error ? <p className="mt-2 rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800">{error}</p> : null}
      {formError ? (
        <p className="mt-2 rounded-md border border-amber-200 bg-amber-50 p-2 text-sm text-amber-900">{formError}</p>
      ) : null}

      {adding ? (
        <form onSubmit={add} className="mt-3 space-y-3" noValidate>
          <div className="grid gap-3 md:grid-cols-3">
            <div>
              <label htmlFor="team-student" className="mb-1 block text-sm font-medium leading-none">
                Student
              </label>
              <Select id="team-student" value={studentId} onChange={(e) => setStudentId(e.target.value)}>
                <option value="">An external person</option>
                {students.map((s) => (
                  <option key={s.student_id} value={s.student_id}>
                    {s.display_name} · {s.student_number}
                  </option>
                ))}
              </Select>
            </div>
            <div>
              <label htmlFor="team-name" className="mb-1 block text-sm font-medium leading-none">
                External name
              </label>
              <Input
                id="team-name"
                value={externalName}
                onChange={(e) => setExternalName(e.target.value)}
                maxLength={250}
                disabled={studentId !== ''}
              />
            </div>
            <div>
              <label htmlFor="team-email" className="mb-1 block text-sm font-medium leading-none">
                External email
              </label>
              <Input
                id="team-email"
                type="email"
                value={externalEmail}
                onChange={(e) => setExternalEmail(e.target.value)}
                maxLength={254}
                disabled={studentId !== ''}
              />
            </div>
            <div>
              <label htmlFor="team-role" className="mb-1 block text-sm font-medium leading-none">
                Role
              </label>
              <Input id="team-role" value={role} onChange={(e) => setRole(e.target.value)} maxLength={150} />
            </div>
            <div className="flex items-end gap-2">
              <label className="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  checked={isLead}
                  onChange={(e) => setIsLead(e.target.checked)}
                  className="h-4 w-4 rounded border-border"
                />
                Team lead
              </label>
            </div>
          </div>
          <Button type="submit" size="sm" disabled={busy}>
            Add member
          </Button>
        </form>
      ) : null}

      {detail.team.length === 0 ? (
        <p className="mt-2 text-sm text-muted-foreground">No team members are listed on this activity.</p>
      ) : (
        <ul className="mt-3 divide-y divide-border">
          {detail.team.map((m) => (
            <li key={m.member_id} className="flex flex-wrap items-center justify-between gap-2 py-2">
              <div>
                <div className="text-sm font-medium">
                  {m.name}
                  {m.is_lead ? <span className="ml-2 text-xs text-muted-foreground">lead</span> : null}
                </div>
                <div className="text-xs text-muted-foreground">
                  {m.role ?? 'No role'}
                  {m.is_student ? '' : ' · external'}
                </div>
              </div>
              {detail.can_edit ? (
                <Button
                  size="sm"
                  variant="ghost"
                  disabled={busy}
                  onClick={() =>
                    void run('student_activity_team_remove', { p_member_id: m.member_id }).then((r) => {
                      if (r.ok) onChanged();
                    })
                  }
                >
                  Remove
                </Button>
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

/* ------------------------------------------------------------------ */
/* Evidence                                                            */
/* ------------------------------------------------------------------ */

function Evidence({
  detail,
  documentTypes,
  evidenceTypes,
  onChanged,
}: {
  detail: StudentActivityDetail;
  documentTypes: Option[];
  evidenceTypes: Option[];
  onChanged: () => void;
}) {
  const { run, busy, error } = useRpcAction();
  const [adding, setAdding] = useState(false);
  const [replacing, setReplacing] = useState(false);
  const [documentTypeId, setDocumentTypeId] = useState('');
  const [evidenceTypeId, setEvidenceTypeId] = useState('');
  const [title, setTitle] = useState('');
  const [issueDate, setIssueDate] = useState('');
  const [authority, setAuthority] = useState('');
  const [certificateNumber, setCertificateNumber] = useState('');
  const [file, setFile] = useState<PickedFile | null>(null);
  const [checksum, setChecksum] = useState('');
  const [replaceId, setReplaceId] = useState('');
  const [replaceReason, setReplaceReason] = useState('');
  const [downloadError, setDownloadError] = useState<string | null>(null);

  async function download(evidenceId: number) {
    const info = await rpcCall<{ storage_key: string; file_name: string; mime_type: string }>(
      'student_activity_evidence_download_info',
      { p_evidence_id: evidenceId },
    );
    if (!info.ok) {
      setDownloadError(info.error);
      return;
    }
    const url = await signedDocumentUrl(info.data.storage_key);
    if (!url) {
      setDownloadError('The file could not be opened. Ask the owner to check the document.');
      return;
    }
    setDownloadError(null);
    window.open(url, '_blank', 'noopener');
  }

  async function add(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!file) return;
    const result = await run<number>('student_activity_evidence_add', {
      p_activity_id: detail.student_activity_id,
      p_document_type_id: Number(documentTypeId),
      p_evidence_type_id: evidenceTypeId ? Number(evidenceTypeId) : null,
      p_title: title.trim(),
      p_issue_date: issueDate || null,
      p_issuing_authority: authority.trim() || null,
      p_certificate_number: certificateNumber.trim() || null,
      p_storage_key: file.storageKey,
      p_file_name: file.fileName,
      p_mime: file.mimeType,
      p_size: file.size,
      p_checksum: checksum.trim() || null,
    });
    if (result.ok) {
      setTitle('');
      setIssueDate('');
      setAuthority('');
      setCertificateNumber('');
      setFile(null);
      setChecksum('');
      onChanged();
    }
  }

  async function replace(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!replaceId || !file) return;
    const result = await run<number>('student_activity_evidence_replace', {
      p_evidence_id: Number(replaceId),
      p_reason: replaceReason.trim(),
      p_storage_key: file.storageKey,
      p_file_name: file.fileName,
      p_mime: file.mimeType,
      p_size: file.size,
      p_checksum: checksum.trim() || null,
    });
    if (result.ok) {
      setReplaceId('');
      setReplaceReason('');
      setFile(null);
      setChecksum('');
      onChanged();
    }
  }

  async function remove(evidenceId: number) {
    const result = await run('student_activity_evidence_delete', { p_evidence_id: evidenceId, p_reason: null });
    if (result.ok) onChanged();
  }

  return (
    <section className="mt-4 rounded-lg border border-border p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h4 className="text-sm font-semibold">Evidence ({detail.evidence.length})</h4>
        {detail.can_edit ? (
          <div className="flex flex-wrap gap-2">
            <Button size="sm" variant="outline" onClick={() => setAdding((v) => !v)}>
              {adding ? 'Close' : 'Add evidence'}
            </Button>
            <Button size="sm" variant="outline" onClick={() => setReplacing((v) => !v)}>
              {replacing ? 'Close' : 'Replace a file'}
            </Button>
          </div>
        ) : null}
      </div>

      {error ? <p className="mt-2 rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800">{error}</p> : null}
      {downloadError ? (
        <p className="mt-2 rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800">{downloadError}</p>
      ) : null}

      {adding ? (
        <form onSubmit={add} className="mt-3 space-y-3" noValidate>
          <div className="grid gap-3 md:grid-cols-3">
            <div>
              <label htmlFor="evidence-doc-type" className="mb-1 block text-sm font-medium leading-none">
                Document type <span className="text-destructive">*</span>
              </label>
              <Select
                id="evidence-doc-type"
                required
                value={documentTypeId}
                onChange={(e) => setDocumentTypeId(e.target.value)}
              >
                <option value="">Select a type</option>
                {documentTypes.map((o) => (
                  <option key={o.id} value={o.id}>
                    {o.label}
                  </option>
                ))}
              </Select>
            </div>
            <div>
              <label htmlFor="evidence-type" className="mb-1 block text-sm font-medium leading-none">
                Evidence type
              </label>
              <Select id="evidence-type" value={evidenceTypeId} onChange={(e) => setEvidenceTypeId(e.target.value)}>
                <option value="">Not stated</option>
                {evidenceTypes.map((o) => (
                  <option key={o.id} value={o.id}>
                    {o.label}
                  </option>
                ))}
              </Select>
            </div>
            <div>
              <label htmlFor="evidence-title" className="mb-1 block text-sm font-medium leading-none">
                Title <span className="text-destructive">*</span>
              </label>
              <Input
                id="evidence-title"
                required
                maxLength={500}
                value={title}
                onChange={(e) => setTitle(e.target.value)}
              />
            </div>
            <div>
              <label htmlFor="evidence-issue-date" className="mb-1 block text-sm font-medium leading-none">
                Issue date
              </label>
              <Input
                id="evidence-issue-date"
                type="date"
                value={issueDate}
                onChange={(e) => setIssueDate(e.target.value)}
              />
            </div>
            <div>
              <label htmlFor="evidence-authority" className="mb-1 block text-sm font-medium leading-none">
                Issuing authority
              </label>
              <Input
                id="evidence-authority"
                maxLength={300}
                value={authority}
                onChange={(e) => setAuthority(e.target.value)}
              />
            </div>
            <div>
              <label htmlFor="evidence-certificate" className="mb-1 block text-sm font-medium leading-none">
                Certificate number
              </label>
              <Input
                id="evidence-certificate"
                maxLength={150}
                value={certificateNumber}
                onChange={(e) => setCertificateNumber(e.target.value)}
              />
            </div>
          </div>
          <EvidenceFileFields
            setFile={setFile}
            checksum={checksum}
            setChecksum={setChecksum}
            studentId={detail.student_id}
          />
          <Button type="submit" size="sm" disabled={busy || !file}>
            Add evidence
          </Button>
        </form>
      ) : null}

      {replacing ? (
        <form onSubmit={replace} className="mt-3 space-y-3" noValidate>
          <div className="grid gap-3 md:grid-cols-2">
            <div>
              <label htmlFor="replace-evidence" className="mb-1 block text-sm font-medium leading-none">
                Evidence
              </label>
              <Select id="replace-evidence" required value={replaceId} onChange={(e) => setReplaceId(e.target.value)}>
                <option value="">Select the file to replace</option>
                {detail.evidence.map((e) => (
                  <option key={e.evidence_id} value={e.evidence_id}>
                    {e.title}
                  </option>
                ))}
              </Select>
            </div>
            <div>
              <label htmlFor="replace-reason" className="mb-1 block text-sm font-medium leading-none">
                Reason
              </label>
              <Input
                id="replace-reason"
                maxLength={1000}
                value={replaceReason}
                onChange={(e) => setReplaceReason(e.target.value)}
              />
            </div>
          </div>
          <EvidenceFileFields
            setFile={setFile}
            checksum={checksum}
            setChecksum={setChecksum}
            studentId={detail.student_id}
          />
          <Button type="submit" size="sm" disabled={busy || !file}>
            Replace file
          </Button>
        </form>
      ) : null}

      {detail.evidence.length === 0 ? (
        <p className="mt-2 text-sm text-muted-foreground">No evidence has been attached to this activity.</p>
      ) : (
        <ul className="mt-3 divide-y divide-border">
          {detail.evidence.map((e: EvidenceRow) => (
            <li key={e.evidence_id} className="flex flex-wrap items-center justify-between gap-2 py-2">
              <div>
                <div className="text-sm font-medium">{e.title}</div>
                <div className="text-xs text-muted-foreground">
                  {e.evidence_type ?? 'Untyped'} · v{e.version}
                  {e.file_name ? ` · ${e.file_name}` : ''}
                  {e.issued ? ` · ${formatDate(e.issued)}` : ''}
                </div>
              </div>
              <div className="flex flex-wrap gap-2">
                <Button size="sm" variant="ghost" onClick={() => void download(e.evidence_id)}>
                  Open
                </Button>
                {detail.can_edit ? (
                  <Button size="sm" variant="ghost" disabled={busy} onClick={() => void remove(e.evidence_id)}>
                    Remove
                  </Button>
                ) : null}
              </div>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function EvidenceFileFields({
  setFile,
  checksum,
  setChecksum,
  studentId,
}: {
  setFile: (f: PickedFile | null) => void;
  checksum: string;
  setChecksum: (v: string) => void;
  studentId: number;
}) {
  return (
    <div className="grid gap-3 md:grid-cols-2">
      <FileUploadField
        id="evidence-file"
        label="Evidence file"
        prefix={`student/${studentId}`}
        onUploaded={setFile}
      />
      <div>
        <label htmlFor="evidence-checksum" className="mb-1 block text-sm font-medium leading-none">
          SHA-256 checksum
        </label>
        <Input
          id="evidence-checksum"
          maxLength={64}
          value={checksum}
          onChange={(e) => setChecksum(e.target.value)}
        />
      </div>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Shared bits                                                         */
/* ------------------------------------------------------------------ */

function Field({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</dt>
      <dd className="mt-0.5">{value}</dd>
    </div>
  );
}
