'use client';

import { useCallback, useEffect, useState } from 'react';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input, Select, Textarea } from '@/components/ui/input';
import { rpcCall, signedDocumentUrl, useRpcAction } from '@/features/shared/client-rpc';
import { formatDate, formatNumber, humanise } from '@/lib/format';
import {
  INDEXING_TYPE_CODES,
  type EmployeeOption,
  type IndexingList,
  type Option,
  type StaffActivityDetail,
} from './types';

/**
 * One staff activity, in full.
 *
 * Contributors, evidence and indexing are separate families of `staff_*`
 * functions, each with its own rules. The browser sends the move and shows the
 * refusal; the database decides whether it is allowed.
 */

const VERIFY_DECISIONS = ['VERIFIED', 'NEEDS_CORRECTION', 'REJECTED'];
const APPROVE_DECISIONS = ['APPROVED', 'REJECTED'];
const INDEXING_STATUSES = ['CLAIMED', 'VERIFIED', 'DISCONTINUED', 'NOT_INDEXED'];
const MIME_TYPES = [
  { value: 'application/pdf', label: 'PDF document' },
  { value: 'image/jpeg', label: 'JPEG image' },
  { value: 'image/png', label: 'PNG image' },
];

export function ActivityPanel({
  detail,
  typeCode,
  employees,
  roleTypes,
  documentTypes,
  evidenceTypes,
  indexingAgencies,
  onChanged,
  onClosed,
  onEdit,
}: {
  detail: StaffActivityDetail;
  typeCode: string;
  employees: EmployeeOption[];
  roleTypes: Option[];
  documentTypes: Option[];
  evidenceTypes: Option[];
  indexingAgencies: Option[];
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
    const result = await run('staff_activity_review', {
      p_activity_id: detail.staff_activity_id,
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
            {detail.staff_name} · {detail.employee_number} · {detail.type_name} · {detail.activity_group}
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
              onClick={() => void act('staff_activity_submit', { p_activity_id: detail.staff_activity_id })}
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
              <label htmlFor="staff-delete-reason" className="mb-1 block text-sm font-medium leading-none">
                Reason (optional)
              </label>
              <Input
                id="staff-delete-reason"
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
                void act('staff_activity_delete', {
                  p_activity_id: detail.staff_activity_id,
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
              <label htmlFor="staff-decision" className="mb-1 block text-sm font-medium leading-none">
                Decision
              </label>
              <Select id="staff-decision" value={decision} onChange={(e) => setDecision(e.target.value)}>
                {(reviewStep === 'VERIFY' ? VERIFY_DECISIONS : APPROVE_DECISIONS).map((d) => (
                  <option key={d} value={d}>
                    {humanise(d)}
                  </option>
                ))}
              </Select>
            </div>
            <div className="min-w-[16rem] flex-1">
              <label htmlFor="staff-remarks" className="mb-1 block text-sm font-medium leading-none">
                Remarks
              </label>
              <Input
                id="staff-remarks"
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
            <Field label="Academic year" value={detail.academic_year_id ? `#${detail.academic_year_id}` : '—'} />
            <Field
              label="Participation level"
              value={detail.participation_level_id ? `#${detail.participation_level_id}` : '—'}
            />
            <Field label="Primary role" value={detail.primary_role_type_id ? `#${detail.primary_role_type_id}` : '—'} />
            <Field label="Evidence" value={formatNumber(detail.evidence.length)} />
          </dl>
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
          <h4 className="text-sm font-semibold">{detail.detail_table ? 'Type details' : 'Type details'}</h4>
          {detail.detail_table ? (
            <dl className="mt-2 grid gap-2 text-sm sm:grid-cols-2">
              {Object.entries(detail.detail).map(([key, value]) => (
                <Field key={key} label={humanise(key)} value={formatValue(value)} />
              ))}
            </dl>
          ) : (
            <p className="mt-2 text-sm text-muted-foreground">This activity type has no extra fields.</p>
          )}
        </div>
      </div>

      <Contributors detail={detail} employees={employees} roleTypes={roleTypes} onChanged={onChanged} />
      <Evidence detail={detail} documentTypes={documentTypes} evidenceTypes={evidenceTypes} onChanged={onChanged} />
      {INDEXING_TYPE_CODES.includes(typeCode) ? (
        <Indexing detail={detail} agencies={indexingAgencies} onChanged={onChanged} />
      ) : null}
    </section>
  );
}

/* ------------------------------------------------------------------ */
/* Contributors                                                        */
/* ------------------------------------------------------------------ */

function Contributors({
  detail,
  employees,
  roleTypes,
  onChanged,
}: {
  detail: StaffActivityDetail;
  employees: EmployeeOption[];
  roleTypes: Option[];
  onChanged: () => void;
}) {
  const { run, busy, error } = useRpcAction();
  const [adding, setAdding] = useState(false);
  const [employeeId, setEmployeeId] = useState('');
  const [externalName, setExternalName] = useState('');
  const [externalEmail, setExternalEmail] = useState('');
  const [affiliation, setAffiliation] = useState('');
  const [roleTypeId, setRoleTypeId] = useState('');
  const [corresponding, setCorresponding] = useState(false);
  const [details, setDetails] = useState('');
  const [formError, setFormError] = useState<string | null>(null);

  async function add(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const employee = employeeId ? Number(employeeId) : null;
    const external = externalName.trim();
    if ((employee === null) === (external === '')) {
      setFormError('Give either an employee or an external person — not both.');
      return;
    }
    setFormError(null);

    const result = await run<number>('staff_contributor_add', {
      p_activity_id: detail.staff_activity_id,
      p_employee_id: employee,
      p_external_name: external || null,
      p_external_email: externalEmail.trim() || null,
      p_affiliation: affiliation.trim() || null,
      p_role_type_id: roleTypeId ? Number(roleTypeId) : null,
      p_is_corresponding: corresponding,
      p_details: details.trim() || null,
    });
    if (result.ok) {
      setEmployeeId('');
      setExternalName('');
      setExternalEmail('');
      setAffiliation('');
      setRoleTypeId('');
      setCorresponding(false);
      setDetails('');
      onChanged();
    }
  }

  return (
    <section className="mt-4 rounded-lg border border-border p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h4 className="text-sm font-semibold">Contributors ({detail.contributors.length})</h4>
        {detail.can_edit ? (
          <Button size="sm" variant="outline" onClick={() => setAdding((v) => !v)}>
            {adding ? 'Close' : 'Add contributor'}
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
              <label htmlFor="contrib-employee" className="mb-1 block text-sm font-medium leading-none">
                Employee
              </label>
              <Select id="contrib-employee" value={employeeId} onChange={(e) => setEmployeeId(e.target.value)}>
                <option value="">An external person</option>
                {employees.map((e) => (
                  <option key={e.employee_id} value={e.employee_id}>
                    {e.display_name} · {e.employee_number}
                  </option>
                ))}
              </Select>
            </div>
            <div>
              <label htmlFor="contrib-name" className="mb-1 block text-sm font-medium leading-none">
                External name
              </label>
              <Input
                id="contrib-name"
                value={externalName}
                onChange={(e) => setExternalName(e.target.value)}
                maxLength={250}
                disabled={employeeId !== ''}
              />
            </div>
            <div>
              <label htmlFor="contrib-email" className="mb-1 block text-sm font-medium leading-none">
                External email
              </label>
              <Input
                id="contrib-email"
                type="email"
                value={externalEmail}
                onChange={(e) => setExternalEmail(e.target.value)}
                maxLength={254}
                disabled={employeeId !== ''}
              />
            </div>
            <div>
              <label htmlFor="contrib-affiliation" className="mb-1 block text-sm font-medium leading-none">
                Affiliation
              </label>
              <Input
                id="contrib-affiliation"
                value={affiliation}
                onChange={(e) => setAffiliation(e.target.value)}
                maxLength={500}
              />
            </div>
            <div>
              <label htmlFor="contrib-role" className="mb-1 block text-sm font-medium leading-none">
                Role
              </label>
              <Select id="contrib-role" value={roleTypeId} onChange={(e) => setRoleTypeId(e.target.value)}>
                <option value="">Not stated</option>
                {roleTypes.map((o) => (
                  <option key={o.id} value={o.id}>
                    {o.label}
                  </option>
                ))}
              </Select>
            </div>
            <div className="flex items-end gap-2">
              <label className="flex items-center gap-2 text-sm">
                <input
                  type="checkbox"
                  checked={corresponding}
                  onChange={(e) => setCorresponding(e.target.checked)}
                  className="h-4 w-4 rounded border-border"
                />
                Corresponding author
              </label>
            </div>
          </div>
          <div>
            <label htmlFor="contrib-details" className="mb-1 block text-sm font-medium leading-none">
              Contribution details
            </label>
            <Textarea id="contrib-details" rows={2} value={details} onChange={(e) => setDetails(e.target.value)} maxLength={1000} />
          </div>
          <Button type="submit" size="sm" disabled={busy}>
            Add contributor
          </Button>
        </form>
      ) : null}

      {detail.contributors.length === 0 ? (
        <p className="mt-2 text-sm text-muted-foreground">No contributors are listed on this activity.</p>
      ) : (
        <ul className="mt-3 divide-y divide-border">
          {detail.contributors.map((c) => (
            <li key={c.contributor_id} className="flex flex-wrap items-center justify-between gap-2 py-2">
              <div>
                <div className="text-sm font-medium">
                  {c.name}
                  {c.is_corresponding ? <span className="ml-2 text-xs text-muted-foreground">corresponding</span> : null}
                </div>
                <div className="text-xs text-muted-foreground">
                  {c.role ?? 'No role'}
                  {c.affiliation ? ` · ${c.affiliation}` : ''}
                </div>
              </div>
              {detail.can_edit ? (
                <Button
                  size="sm"
                  variant="ghost"
                  disabled={busy}
                  onClick={() =>
                    void run('staff_contributor_remove', { p_contributor_id: c.contributor_id }).then((r) => {
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
  detail: StaffActivityDetail;
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
  const [storageKey, setStorageKey] = useState(`employee/${detail.employee_id}/`);
  const [fileName, setFileName] = useState('');
  const [mime, setMime] = useState('application/pdf');
  const [size, setSize] = useState('');
  const [checksum, setChecksum] = useState('');
  const [replaceId, setReplaceId] = useState('');
  const [replaceReason, setReplaceReason] = useState('');
  const [downloadError, setDownloadError] = useState<string | null>(null);

  async function download(evidenceId: number) {
    const info = await rpcCall<{ storage_key: string; file_name: string; mime_type: string }>(
      'staff_evidence_download_info',
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
    const result = await run<number>('staff_evidence_add', {
      p_activity_id: detail.staff_activity_id,
      p_document_type_id: Number(documentTypeId),
      p_evidence_type_id: evidenceTypeId ? Number(evidenceTypeId) : null,
      p_title: title.trim(),
      p_issue_date: issueDate || null,
      p_issuing_authority: authority.trim() || null,
      p_certificate_number: certificateNumber.trim() || null,
      p_storage_key: storageKey.trim(),
      p_file_name: fileName.trim(),
      p_mime: mime,
      p_size: Number(size),
      p_checksum: checksum.trim() || null,
    });
    if (result.ok) {
      setTitle('');
      setIssueDate('');
      setAuthority('');
      setCertificateNumber('');
      setFileName('');
      setSize('');
      setChecksum('');
      onChanged();
    }
  }

  async function replace(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!replaceId) return;
    const result = await run<number>('staff_evidence_replace', {
      p_evidence_id: Number(replaceId),
      p_reason: replaceReason.trim(),
      p_storage_key: storageKey.trim(),
      p_file_name: fileName.trim(),
      p_mime: mime,
      p_size: Number(size),
      p_checksum: checksum.trim() || null,
    });
    if (result.ok) {
      setReplaceId('');
      setReplaceReason('');
      setFileName('');
      setSize('');
      setChecksum('');
      onChanged();
    }
  }

  async function remove(evidenceId: number) {
    const result = await run('staff_evidence_delete', { p_evidence_id: evidenceId, p_reason: null });
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
            storageKey={storageKey}
            setStorageKey={setStorageKey}
            fileName={fileName}
            setFileName={setFileName}
            mime={mime}
            setMime={setMime}
            size={size}
            setSize={setSize}
            checksum={checksum}
            setChecksum={setChecksum}
            employeeId={detail.employee_id}
          />
          <Button type="submit" size="sm" disabled={busy}>
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
            storageKey={storageKey}
            setStorageKey={setStorageKey}
            fileName={fileName}
            setFileName={setFileName}
            mime={mime}
            setMime={setMime}
            size={size}
            setSize={setSize}
            checksum={checksum}
            setChecksum={setChecksum}
            employeeId={detail.employee_id}
          />
          <Button type="submit" size="sm" disabled={busy}>
            Replace file
          </Button>
        </form>
      ) : null}

      {detail.evidence.length === 0 ? (
        <p className="mt-2 text-sm text-muted-foreground">No evidence has been attached to this activity.</p>
      ) : (
        <ul className="mt-3 divide-y divide-border">
          {detail.evidence.map((e) => (
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
  storageKey,
  setStorageKey,
  fileName,
  setFileName,
  mime,
  setMime,
  size,
  setSize,
  checksum,
  setChecksum,
  employeeId,
}: {
  storageKey: string;
  setStorageKey: (v: string) => void;
  fileName: string;
  setFileName: (v: string) => void;
  mime: string;
  setMime: (v: string) => void;
  size: string;
  setSize: (v: string) => void;
  checksum: string;
  setChecksum: (v: string) => void;
  employeeId: number;
}) {
  return (
    <div className="space-y-3">
      <div>
        <label htmlFor="evidence-key" className="mb-1 block text-sm font-medium leading-none">
          Storage key <span className="text-destructive">*</span>
        </label>
        <Input
          id="evidence-key"
          required
          value={storageKey}
          onChange={(e) => setStorageKey(e.target.value)}
          placeholder={`employee/${employeeId}/certificate.pdf`}
        />
        <p className="mt-1 text-xs text-muted-foreground">
          The file must already be uploaded to the <span className="font-mono">sims-documents</span> bucket under{' '}
          <span className="font-mono">employee/{employeeId}/</span>.
        </p>
      </div>
      <div className="grid gap-3 md:grid-cols-4">
        <div>
          <label htmlFor="evidence-file" className="mb-1 block text-sm font-medium leading-none">
            File name <span className="text-destructive">*</span>
          </label>
          <Input
            id="evidence-file"
            required
            maxLength={255}
            value={fileName}
            onChange={(e) => setFileName(e.target.value)}
            placeholder="certificate.pdf"
          />
        </div>
        <div>
          <label htmlFor="evidence-mime" className="mb-1 block text-sm font-medium leading-none">
            File type <span className="text-destructive">*</span>
          </label>
          <Select id="evidence-mime" value={mime} onChange={(e) => setMime(e.target.value)}>
            {MIME_TYPES.map((m) => (
              <option key={m.value} value={m.value}>
                {m.label}
              </option>
            ))}
          </Select>
        </div>
        <div>
          <label htmlFor="evidence-size" className="mb-1 block text-sm font-medium leading-none">
            Size in bytes <span className="text-destructive">*</span>
          </label>
          <Input
            id="evidence-size"
            type="number"
            min={1}
            required
            value={size}
            onChange={(e) => setSize(e.target.value)}
          />
        </div>
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
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Indexing                                                            */
/* ------------------------------------------------------------------ */

function Indexing({
  detail,
  agencies,
  onChanged,
}: {
  detail: StaffActivityDetail;
  agencies: Option[];
  onChanged: () => void;
}) {
  const { run, busy, error } = useRpcAction();
  const [list, setList] = useState<IndexingList | null>(null);
  const [listError, setListError] = useState<string | null>(null);
  const [agencyId, setAgencyId] = useState('');
  const [status, setStatus] = useState('CLAIMED');
  const [year, setYear] = useState('');
  const [url, setUrl] = useState('');
  const [remarks, setRemarks] = useState('');

  const load = useCallback(async () => {
    const result = await rpcCall<IndexingList>('staff_indexing_list', { p_activity_id: detail.staff_activity_id });
    if (!result.ok) {
      setListError(result.error);
      setList(null);
      return;
    }
    setListError(null);
    setList(result.data);
  }, [detail.staff_activity_id]);

  useEffect(() => {
    void (async () => {
      await load();
    })();
  }, [load]);

  async function save(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const result = await run('staff_indexing_save', {
      p_activity_id: detail.staff_activity_id,
      p_agency_id: Number(agencyId),
      p_status: status,
      p_year: year ? Number(year) : null,
      p_url: url.trim() || null,
      p_remarks: remarks.trim() || null,
    });
    if (result.ok) {
      setAgencyId('');
      setYear('');
      setUrl('');
      setRemarks('');
      await load();
      onChanged();
    }
  }

  async function remove(rowAgencyId: number) {
    const result = await run('staff_indexing_delete', {
      p_activity_id: detail.staff_activity_id,
      p_agency_id: rowAgencyId,
    });
    if (result.ok) {
      await load();
      onChanged();
    }
  }

  return (
    <section className="mt-4 rounded-lg border border-border p-4">
      <h4 className="text-sm font-semibold">Indexing</h4>
      {error || listError ? (
        <p className="mt-2 rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800">{error ?? listError}</p>
      ) : null}

      {list && list.can_edit ? (
        <form onSubmit={save} className="mt-3 space-y-3" noValidate>
          <div className="grid gap-3 md:grid-cols-4">
            <div>
              <label htmlFor="indexing-agency" className="mb-1 block text-sm font-medium leading-none">
                Agency <span className="text-destructive">*</span>
              </label>
              <Select id="indexing-agency" required value={agencyId} onChange={(e) => setAgencyId(e.target.value)}>
                <option value="">Select an agency</option>
                {agencies.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.label}
                  </option>
                ))}
              </Select>
            </div>
            <div>
              <label htmlFor="indexing-status" className="mb-1 block text-sm font-medium leading-none">
                Status
              </label>
              <Select id="indexing-status" value={status} onChange={(e) => setStatus(e.target.value)}>
                {INDEXING_STATUSES.map((s) => (
                  <option key={s} value={s}>
                    {humanise(s)}
                  </option>
                ))}
              </Select>
            </div>
            <div>
              <label htmlFor="indexing-year" className="mb-1 block text-sm font-medium leading-none">
                Year
              </label>
              <Input
                id="indexing-year"
                type="number"
                min={1900}
                max={2100}
                value={year}
                onChange={(e) => setYear(e.target.value)}
              />
            </div>
            <div>
              <label htmlFor="indexing-url" className="mb-1 block text-sm font-medium leading-none">
                Source link
              </label>
              <Input
                id="indexing-url"
                type="url"
                maxLength={1000}
                value={url}
                onChange={(e) => setUrl(e.target.value)}
                placeholder="https://…"
              />
            </div>
          </div>
          <div>
            <label htmlFor="indexing-remarks" className="mb-1 block text-sm font-medium leading-none">
              Remarks
            </label>
            <Input
              id="indexing-remarks"
              maxLength={500}
              value={remarks}
              onChange={(e) => setRemarks(e.target.value)}
            />
          </div>
          <Button type="submit" size="sm" disabled={busy}>
            Save indexing
          </Button>
        </form>
      ) : null}

      {!list || list.rows.length === 0 ? (
        <p className="mt-2 text-sm text-muted-foreground">No indexing claims are recorded for this publication.</p>
      ) : (
        <ul className="mt-3 divide-y divide-border">
          {list.rows.map((row) => (
            <li key={row.agency_id} className="flex flex-wrap items-center justify-between gap-2 py-2">
              <div>
                <div className="text-sm font-medium">{row.agency}</div>
                <div className="text-xs text-muted-foreground">
                  {humanise(row.status)}
                  {row.year ? ` · ${row.year}` : ''}
                  {row.url ? ` · ${row.url}` : ''}
                </div>
              </div>
              {list.can_edit ? (
                <Button size="sm" variant="ghost" disabled={busy} onClick={() => void remove(row.agency_id)}>
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

function formatValue(value: unknown): string {
  if (value === null || value === undefined || value === '') return '—';
  if (typeof value === 'boolean') return value ? 'Yes' : 'No';
  if (typeof value === 'number') return String(value);
  if (typeof value === 'string') {
    if (/^\d{4}-\d{2}-\d{2}/.test(value)) return formatDate(value);
    return value;
  }
  return String(value);
}
