'use client';

import { useState } from 'react';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Input, Label, Select, Textarea } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { formatDate, formatDateTime, humanise } from '@/lib/format';
import { deleteStoredFile, rpcCall, signedDocumentUrl, useRpcAction } from '@/features/shared/client-rpc';
import { FileUploadField, type PickedFile } from '@/features/shared/file-upload-field';

/* ------------------------------------------------------------------ types */

export type StudentDocument = {
  student_document_id: number;
  document_type: string;
  requires_verification: boolean;
  original_file_name: string;
  mime_type: string;
  file_size_bytes: number;
  document_number: string | null;
  issue_date: string | null;
  expiry_date: string | null;
  verification_status: string;
  effective_status: string;
  verified_at: string | null;
  remarks: string | null;
  uploaded_at: string;
};

export type Lookup = { id: number; label: string };

/* --------------------------------------------------------------- register */

export function DocumentRegisterForm({ studentId, documentTypes }: { studentId: number; documentTypes: Lookup[] }) {
  const { busy, error, notice, run } = useRpcAction();
  const [typeId, setTypeId] = useState('');
  const [file, setFile] = useState<PickedFile | null>(null);
  const [checksum, setChecksum] = useState('');
  const [documentNumber, setDocumentNumber] = useState('');
  const [issueDate, setIssueDate] = useState('');
  const [expiryDate, setExpiryDate] = useState('');

  async function submit() {
    if (!file) return;
    await run<number>(
      'student_document_register',
      {
        p_student_id: studentId,
        p_document_type_id: Number(typeId),
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
    setFile(null);
    setChecksum('');
    setDocumentNumber('');
    setIssueDate('');
    setExpiryDate('');
  }

  const ready = typeId !== '' && file !== null;

  return (
    <div className="space-y-3">
      <div className="grid gap-3 sm:grid-cols-2">
        <div className="space-y-1">
          <Label htmlFor="doc-type">Document type</Label>
          <Select id="doc-type" value={typeId} onChange={(e) => setTypeId(e.target.value)}>
            <option value="">Choose a document type</option>
            {documentTypes.map((t) => (
              <option key={t.id} value={t.id}>
                {t.label}
              </option>
            ))}
          </Select>
        </div>
        <FileUploadField
          id="doc-file"
          label="Document file"
          prefix={`student/${studentId}`}
          onUploaded={setFile}
        />
      </div>

      <div className="grid gap-3 sm:grid-cols-2">
        <div className="space-y-1">
          <Label htmlFor="doc-checksum">SHA-256 checksum (optional)</Label>
          <Input id="doc-checksum" value={checksum} onChange={(e) => setChecksum(e.target.value)} maxLength={64} />
        </div>
        <div className="space-y-1">
          <Label htmlFor="doc-number">Document number</Label>
          <Input id="doc-number" value={documentNumber} onChange={(e) => setDocumentNumber(e.target.value)} maxLength={100} />
        </div>
        <div className="space-y-1">
          <Label htmlFor="doc-issue">Issue date</Label>
          <Input id="doc-issue" type="date" value={issueDate} onChange={(e) => setIssueDate(e.target.value)} />
        </div>
        <div className="space-y-1">
          <Label htmlFor="doc-expiry">Expiry date</Label>
          <Input id="doc-expiry" type="date" value={expiryDate} onChange={(e) => setExpiryDate(e.target.value)} />
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

/* ---------------------------------------------------------------- review */

function DocumentReviewControl({ doc }: { doc: StudentDocument }) {
  const { busy, error, notice, run } = useRpcAction();
  const [remarks, setRemarks] = useState('');
  const [open, setOpen] = useState(false);

  async function review(decision: 'VERIFIED' | 'REJECTED') {
    await run<void>(
      'student_document_review',
      { p_id: doc.student_document_id, p_decision: decision, p_remarks: remarks.trim() || null },
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
            <Label htmlFor={`doc-remarks-${doc.student_document_id}`}>Remarks (required to reject)</Label>
            <Textarea
              id={`doc-remarks-${doc.student_document_id}`}
              value={remarks}
              onChange={(e) => setRemarks(e.target.value)}
              maxLength={500}
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

/* ---------------------------------------------------------------- delete */

function DocumentDeleteControl({ doc }: { doc: StudentDocument }) {
  const { busy, error, notice, run } = useRpcAction();

  async function remove() {
    const result = await run<string>('student_document_delete', { p_id: doc.student_document_id }, { success: 'The document has been removed.' });
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

/* -------------------------------------------------------------- download */

function DocumentDownloadControl({ doc }: { doc: StudentDocument }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function download() {
    setBusy(true);
    setError(null);
    const res = await rpcCall<Record<string, unknown>>('student_document_download_info', { p_id: doc.student_document_id });
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

/* ---------------------------------------------------------------- panel */

export function MyDocumentsPanel({ rows }: { rows: StudentDocument[] }) {
  if (rows.length === 0) {
    return <EmptyState title="No documents yet" description="Register a document above and it will appear here." />;
  }

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Document</TableHead>
          <TableHead>File</TableHead>
          <TableHead>Number</TableHead>
          <TableHead>Dates</TableHead>
          <TableHead>Status</TableHead>
          <TableHead>Uploaded</TableHead>
          <TableHead>Actions</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.map((d) => (
          <TableRow key={d.student_document_id}>
            <TableCell>
              <div>{d.document_type}</div>
              {d.requires_verification ? <div className="text-xs text-muted-foreground">Needs verification</div> : null}
            </TableCell>
            <TableCell>
              <div className="max-w-[14rem] truncate text-xs">{d.original_file_name}</div>
              <div className="text-xs text-muted-foreground">{d.mime_type}</div>
            </TableCell>
            <TableCell className="font-mono text-xs">{d.document_number ?? '—'}</TableCell>
            <TableCell className="text-xs">
              <div>Issued {formatDate(d.issue_date)}</div>
              <div className="text-muted-foreground">Expires {formatDate(d.expiry_date)}</div>
            </TableCell>
            <TableCell>
              <Badge variant={statusVariant(d.effective_status)}>{humanise(d.effective_status)}</Badge>
              {d.remarks ? <div className="mt-1 max-w-xs text-xs text-muted-foreground">{d.remarks}</div> : null}
              {d.verified_at ? <div className="text-xs text-muted-foreground">{formatDateTime(d.verified_at)}</div> : null}
            </TableCell>
            <TableCell className="text-xs">{formatDateTime(d.uploaded_at)}</TableCell>
            <TableCell>
              <div className="flex flex-col gap-2">
                <DocumentReviewControl doc={d} />
                <DocumentDownloadControl doc={d} />
                <DocumentDeleteControl doc={d} />
              </div>
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
