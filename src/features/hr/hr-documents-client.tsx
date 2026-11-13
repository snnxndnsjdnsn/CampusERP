'use client';

import { Fragment, useState } from 'react';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Input, Label, Select, Textarea } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { formatDate, formatDateTime, humanise } from '@/lib/format';
import { deleteStoredFile, rpcCall, signedDocumentUrl, useRpcAction } from '@/features/shared/client-rpc';
import { FileUploadField, type PickedFile } from '@/features/shared/file-upload-field';

/* ------------------------------------------------------------------ types */

export type EmployeeDocument = {
  employee_document_id: number;
  category: string;
  document_title: string;
  original_file_name: string;
  mime_type: string;
  file_size_bytes: number;
  document_number: string | null;
  issue_date: string | null;
  expiry_date: string | null;
  verification_status: string;
  effective_status: string;
  approval_status: string;
  verification_remarks: string | null;
  uploaded_at: string;
  confidentiality_level: string;
};

export type DocumentCategory = {
  employee_document_category_id: number;
  category_code: string;
  category_name: string;
  is_active: boolean;
};

export type DocumentTypeOption = { id: number; label: string };

export type AccessRule = {
  id: number;
  who: string;
  can_view: boolean;
  can_download: boolean;
  valid_from: string;
  valid_to: string | null;
  active: boolean;
};

/* --------------------------------------------------------------- register */

export function EmployeeDocumentRegisterForm({
  employeeId,
  categories,
  documentTypes,
}: {
  employeeId: number;
  categories: DocumentCategory[];
  documentTypes: DocumentTypeOption[];
}) {
  const { busy, error, notice, run } = useRpcAction();
  const [categoryId, setCategoryId] = useState('');
  const [typeId, setTypeId] = useState('');
  const [title, setTitle] = useState('');
  const [file, setFile] = useState<PickedFile | null>(null);
  const [checksum, setChecksum] = useState('');
  const [documentNumber, setDocumentNumber] = useState('');
  const [issueDate, setIssueDate] = useState('');
  const [expiryDate, setExpiryDate] = useState('');

  async function submit() {
    if (!file) return;
    await run<number>(
      'employee_document_register',
      {
        p_employee_id: employeeId,
        p_category_id: Number(categoryId),
        p_document_type_id: Number(typeId),
        p_title: title.trim(),
        p_storage_key: file.storageKey,
        p_file_name: file.fileName,
        p_mime_type: file.mimeType,
        p_size: file.size,
        p_checksum: checksum.trim() || null,
        p_document_number: documentNumber.trim() || null,
        p_issue_date: issueDate || null,
        p_expiry_date: expiryDate || null,
      },
      { success: 'The document has been registered.' },
    );
    setTitle('');
    setFile(null);
    setChecksum('');
    setDocumentNumber('');
    setIssueDate('');
    setExpiryDate('');
  }

  const ready = categoryId !== '' && typeId !== '' && title.trim() !== '' && file !== null;

  return (
    <div className="space-y-3">
      <div className="grid gap-3 sm:grid-cols-2">
        <div className="space-y-1">
          <Label htmlFor="emp-doc-category">Category</Label>
          <Select id="emp-doc-category" value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>
            <option value="">Choose a category</option>
            {categories
              .filter((c) => c.is_active)
              .map((c) => (
                <option key={c.employee_document_category_id} value={c.employee_document_category_id}>
                  {c.category_name}
                </option>
              ))}
          </Select>
        </div>
        <div className="space-y-1">
          <Label htmlFor="emp-doc-type">Document type</Label>
          <Select id="emp-doc-type" value={typeId} onChange={(e) => setTypeId(e.target.value)}>
            <option value="">Choose a document type</option>
            {documentTypes.map((t) => (
              <option key={t.id} value={t.id}>
                {t.label}
              </option>
            ))}
          </Select>
        </div>
      </div>

      <div className="space-y-1">
        <Label htmlFor="emp-doc-title">Title</Label>
        <Input id="emp-doc-title" value={title} onChange={(e) => setTitle(e.target.value)} maxLength={250} />
      </div>

      <FileUploadField
        id="emp-doc-file"
        label="Document file"
        prefix={`employee/${employeeId}`}
        onUploaded={setFile}
      />

      <div className="grid gap-3 sm:grid-cols-2">
        <div className="space-y-1">
          <Label htmlFor="emp-doc-checksum">SHA-256 checksum (optional)</Label>
          <Input id="emp-doc-checksum" value={checksum} onChange={(e) => setChecksum(e.target.value)} maxLength={64} />
        </div>
        <div className="space-y-1">
          <Label htmlFor="emp-doc-number">Document number</Label>
          <Input id="emp-doc-number" value={documentNumber} onChange={(e) => setDocumentNumber(e.target.value)} maxLength={100} />
        </div>
        <div className="space-y-1">
          <Label htmlFor="emp-doc-issue">Issue date</Label>
          <Input id="emp-doc-issue" type="date" value={issueDate} onChange={(e) => setIssueDate(e.target.value)} />
        </div>
        <div className="space-y-1">
          <Label htmlFor="emp-doc-expiry">Expiry date</Label>
          <Input id="emp-doc-expiry" type="date" value={expiryDate} onChange={(e) => setExpiryDate(e.target.value)} />
        </div>
      </div>

      {error ? <ErrorPanel message={error} /> : null}
      {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
      <Button onClick={submit} disabled={busy || !ready}>
        {busy ? 'Registering…' : 'Register the document'}
      </Button>
    </div>
  );
}

/* ------------------------------------------------------------- access rules */

function AccessRulePanel({ documentId }: { documentId: number }) {
  const { busy, error, notice, run } = useRpcAction();
  const [rules, setRules] = useState<AccessRule[] | null>(null);
  const [loading, setLoading] = useState(false);
  const [roleCode, setRoleCode] = useState('');
  const [username, setUsername] = useState('');
  const [canView, setCanView] = useState(true);
  const [canDownload, setCanDownload] = useState(false);
  const [validTo, setValidTo] = useState('');

  async function load() {
    setLoading(true);
    const res = await rpcCall<AccessRule[]>('emp_doc_rule_list', { p_document_id: documentId });
    setLoading(false);
    if (!res.ok) {
      setRules([]);
      return;
    }
    setRules(Array.isArray(res.data) ? res.data : []);
  }

  async function add() {
    const saved = await run<number>(
      'emp_doc_rule_set',
      {
        p_document_id: documentId,
        p_role_code: roleCode.trim() || null,
        p_username: username.trim() || null,
        p_can_view: canView,
        p_can_download: canDownload,
        p_valid_to: validTo ? new Date(validTo).toISOString() : null,
      },
      { success: 'The access rule has been added.' },
    );
    if (saved.ok) {
      setRoleCode('');
      setUsername('');
      setValidTo('');
      await load();
    }
  }

  async function end(ruleId: number) {
    const ended = await run<void>('emp_doc_rule_end', { p_rule_id: ruleId }, { success: 'The access rule has ended.' });
    if (ended.ok) await load();
  }

  return (
    <div className="space-y-3 rounded-md border border-border bg-muted/30 p-3">
      <div className="flex items-center justify-between">
        <h4 className="text-sm font-semibold">Access rules</h4>
        <Button size="sm" variant="ghost" onClick={load} disabled={loading}>
          {loading ? 'Loading…' : 'Load rules'}
        </Button>
      </div>

      {rules === null ? (
        <p className="text-xs text-muted-foreground">Load the rules to see who may open this document.</p>
      ) : rules.length === 0 ? (
        <p className="text-xs text-muted-foreground">No access rule has been recorded for this document.</p>
      ) : (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Who</TableHead>
              <TableHead>View</TableHead>
              <TableHead>Download</TableHead>
              <TableHead>Valid</TableHead>
              <TableHead>End</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {rules.map((r) => (
              <TableRow key={r.id}>
                <TableCell className="text-xs">{r.who}</TableCell>
                <TableCell className="text-xs">{r.can_view ? 'Yes' : 'No'}</TableCell>
                <TableCell className="text-xs">{r.can_download ? 'Yes' : 'No'}</TableCell>
                <TableCell className="text-xs">
                  <div>{formatDateTime(r.valid_from)}</div>
                  <div className="text-muted-foreground">{r.valid_to ? `to ${formatDateTime(r.valid_to)}` : 'no end date'}</div>
                </TableCell>
                <TableCell>
                  {r.active ? (
                    <Button size="sm" variant="ghost" onClick={() => end(r.id)} disabled={busy}>
                      End
                    </Button>
                  ) : (
                    <span className="text-xs text-muted-foreground">Ended</span>
                  )}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      )}

      <div className="grid gap-2 sm:grid-cols-4">
        <div className="space-y-1">
          <Label htmlFor={`rule-role-${documentId}`}>Role code</Label>
          <Input id={`rule-role-${documentId}`} value={roleCode} onChange={(e) => setRoleCode(e.target.value)} maxLength={60} />
        </div>
        <div className="space-y-1">
          <Label htmlFor={`rule-user-${documentId}`}>Username</Label>
          <Input id={`rule-user-${documentId}`} value={username} onChange={(e) => setUsername(e.target.value)} maxLength={120} />
        </div>
        <div className="space-y-1">
          <Label htmlFor={`rule-until-${documentId}`}>Valid until</Label>
          <Input id={`rule-until-${documentId}`} type="datetime-local" value={validTo} onChange={(e) => setValidTo(e.target.value)} />
        </div>
        <div className="flex items-end gap-3 pb-1">
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={canView} onChange={(e) => setCanView(e.target.checked)} />
            View
          </label>
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" checked={canDownload} onChange={(e) => setCanDownload(e.target.checked)} />
            Download
          </label>
        </div>
      </div>
      {error ? <ErrorPanel message={error} /> : null}
      {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
      <Button size="sm" onClick={add} disabled={busy || (roleCode.trim() === '' && username.trim() === '') || (!canView && !canDownload)}>
        {busy ? 'Saving…' : 'Add the rule'}
      </Button>
      <p className="text-xs text-muted-foreground">Name either a role or a user, not both.</p>
    </div>
  );
}

/* ------------------------------------------------------------ row controls */

function DocumentReviewControl({ doc }: { doc: EmployeeDocument }) {
  const { busy, error, notice, run } = useRpcAction();
  const [remarks, setRemarks] = useState('');
  const [open, setOpen] = useState(false);

  async function review(decision: 'VERIFIED' | 'REJECTED') {
    await run<void>(
      'employee_document_review',
      { p_id: doc.employee_document_id, p_decision: decision, p_remarks: remarks.trim() || null },
      { success: decision === 'VERIFIED' ? 'The document has been verified.' : 'The document has been rejected.' },
    );
    setOpen(false);
    setRemarks('');
  }

  if (doc.verification_status !== 'PENDING') return null;

  return (
    <div className="space-y-2">
      {open ? (
        <>
          <div className="space-y-1">
            <Label htmlFor={`emp-review-${doc.employee_document_id}`}>Remarks (required to reject)</Label>
            <Textarea
              id={`emp-review-${doc.employee_document_id}`}
              value={remarks}
              onChange={(e) => setRemarks(e.target.value)}
              maxLength={1000}
            />
          </div>
          {error ? <ErrorPanel message={error} /> : null}
          {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
          <div className="flex flex-wrap gap-2">
            <Button size="sm" onClick={() => review('VERIFIED')} disabled={busy}>
              Verify
            </Button>
            <Button size="sm" variant="destructive" onClick={() => review('REJECTED')} disabled={busy || !remarks.trim()}>
              Reject
            </Button>
            <Button size="sm" variant="ghost" onClick={() => setOpen(false)} disabled={busy}>
              Cancel
            </Button>
          </div>
        </>
      ) : (
        <Button size="sm" variant="outline" onClick={() => setOpen(true)}>
          Review
        </Button>
      )}
    </div>
  );
}

function DocumentDownloadControl({ doc }: { doc: EmployeeDocument }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function download() {
    setBusy(true);
    setError(null);
    const res = await rpcCall<Record<string, unknown>>('employee_document_download_info', { p_id: doc.employee_document_id });
    if (!res.ok) {
      setBusy(false);
      setError(res.error);
      return;
    }
    const key = String(res.data.storage_key ?? '');
    const url = key ? await signedDocumentUrl(key) : null;
    setBusy(false);
    if (!url) {
      setError('The document file could not be opened.');
      return;
    }
    window.open(url, '_blank', 'noopener');
  }

  return (
    <div className="space-y-2">
      {error ? <ErrorPanel message={error} /> : null}
      <Button size="sm" variant="outline" onClick={download} disabled={busy}>
        {busy ? 'Opening…' : 'Open'}
      </Button>
    </div>
  );
}

function DocumentDeleteControl({ doc }: { doc: EmployeeDocument }) {
  const { busy, error, notice, run } = useRpcAction();

  async function remove() {
    const result = await run<string>('employee_document_delete', { p_id: doc.employee_document_id }, { success: 'The document has been removed.' });
    if (result.ok) {
      const key = typeof result.data === 'string' ? result.data : '';
      if (key) await deleteStoredFile(key);
    }
  }

  if (doc.verification_status === 'VERIFIED') return null;

  return (
    <div className="space-y-2">
      {error ? <ErrorPanel message={error} /> : null}
      {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
      <Button size="sm" variant="ghost" onClick={remove} disabled={busy}>
        {busy ? 'Removing…' : 'Remove'}
      </Button>
    </div>
  );
}

/* ------------------------------------------------------------------ table */

export function EmployeeDocumentTable({ rows }: { rows: EmployeeDocument[] }) {
  const [expanded, setExpanded] = useState<number | null>(null);

  if (rows.length === 0) {
    return <EmptyState title="No documents" description="Register an HR document above and it will appear here." />;
  }

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Title</TableHead>
          <TableHead>Category</TableHead>
          <TableHead>File</TableHead>
          <TableHead>Number</TableHead>
          <TableHead>Dates</TableHead>
          <TableHead>Status</TableHead>
          <TableHead>Actions</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.map((d) => (
          <Fragment key={d.employee_document_id}>
            <TableRow>
              <TableCell>
                <div className="font-medium">{d.document_title}</div>
                <div className="text-xs text-muted-foreground">{humanise(d.confidentiality_level)}</div>
              </TableCell>
              <TableCell className="text-xs">{d.category}</TableCell>
              <TableCell className="text-xs">
                <div className="max-w-[14rem] truncate">{d.original_file_name}</div>
                <div className="text-muted-foreground">{d.mime_type}</div>
              </TableCell>
              <TableCell className="font-mono text-xs">{d.document_number ?? '—'}</TableCell>
              <TableCell className="text-xs">
                <div>Issued {formatDate(d.issue_date)}</div>
                <div className="text-muted-foreground">Expires {formatDate(d.expiry_date)}</div>
              </TableCell>
              <TableCell>
                <Badge variant={statusVariant(d.effective_status)}>{humanise(d.effective_status)}</Badge>
                {d.approval_status && d.approval_status !== 'NOT_REQUIRED' ? (
                  <div className="mt-1">
                    <Badge variant={statusVariant(d.approval_status)}>{humanise(d.approval_status)}</Badge>
                  </div>
                ) : null}
                {d.verification_remarks ? <div className="mt-1 max-w-xs text-xs text-muted-foreground">{d.verification_remarks}</div> : null}
              </TableCell>
              <TableCell>
                <div className="flex flex-col gap-2">
                  <DocumentReviewControl doc={d} />
                  <DocumentDownloadControl doc={d} />
                  <DocumentDeleteControl doc={d} />
                  <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => setExpanded((v) => (v === d.employee_document_id ? null : d.employee_document_id))}
                  >
                    {expanded === d.employee_document_id ? 'Close rules' : 'Access rules'}
                  </Button>
                </div>
              </TableCell>
            </TableRow>
            {expanded === d.employee_document_id ? (
              <TableRow>
                <TableCell colSpan={7} className="p-0">
                  <AccessRulePanel documentId={d.employee_document_id} />
                </TableCell>
              </TableRow>
            ) : null}
          </Fragment>
        ))}
      </TableBody>
    </Table>
  );
}
