'use client';

import { useState } from 'react';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Input, Label, Select, Textarea } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { formatDateTime, humanise } from '@/lib/format';
import { rpcCall, signedDocumentUrl, useRpcAction } from '@/features/shared/client-rpc';
import { FileUploadField, type PickedFile } from '@/features/shared/file-upload-field';

/* ------------------------------------------------------------------ types */

export type CertificateRequest = {
  certificate_request_id: number;
  request_number: string;
  student_id: number;
  student_number: string;
  student_name: string;
  certificate_name: string;
  purpose: string;
  request_status: string;
  requested_at: string;
  issued_at: string | null;
  certificate_number: string | null;
  has_file: boolean;
  can_approve: boolean;
  can_issue: boolean;
  can_cancel: boolean;
};

export type Lookup = { id: number; label: string };

/* ------------------------------------------------------------ new request */

export function CertificateRequestForm({ types }: { types: Lookup[] }) {
  const { busy, error, notice, run } = useRpcAction();
  const [typeId, setTypeId] = useState('');
  const [purpose, setPurpose] = useState('');

  async function submit() {
    await run<number>(
      'cert_request_create',
      { p_type_id: Number(typeId), p_purpose: purpose.trim() },
      { success: 'Your certificate request has been submitted.' },
    );
    setPurpose('');
  }

  return (
    <div className="space-y-3">
      <div className="grid gap-3 sm:grid-cols-2">
        <div className="space-y-1">
          <Label htmlFor="cert-type">Certificate</Label>
          <Select id="cert-type" value={typeId} onChange={(e) => setTypeId(e.target.value)}>
            <option value="">Choose a certificate</option>
            {types.map((t) => (
              <option key={t.id} value={t.id}>
                {t.label}
              </option>
            ))}
          </Select>
        </div>
        <div className="space-y-1">
          <Label htmlFor="cert-purpose">Purpose</Label>
          <Input id="cert-purpose" value={purpose} onChange={(e) => setPurpose(e.target.value)} maxLength={500} placeholder="Why do you need it?" />
        </div>
      </div>
      {error ? <ErrorPanel message={error} /> : null}
      {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
      <Button onClick={submit} disabled={busy || !typeId || purpose.trim().length < 3}>
        {busy ? 'Submitting…' : 'Request the certificate'}
      </Button>
    </div>
  );
}

/* --------------------------------------------------------------- decisions */

function DecideControl({ request }: { request: CertificateRequest }) {
  const { busy, error, notice, run } = useRpcAction();
  const [remarks, setRemarks] = useState('');
  const [open, setOpen] = useState(false);

  async function decide(approve: boolean) {
    await run<void>(
      'cert_request_decide',
      { p_id: request.certificate_request_id, p_approve: approve, p_remarks: remarks.trim() || null },
      { success: approve ? 'The request has been approved.' : 'The request has been rejected.' },
    );
    setOpen(false);
  }

  if (!request.can_approve) return null;

  return (
    <div className="space-y-2">
      {open ? (
        <>
          <div className="space-y-1">
            <Label htmlFor={`cert-remarks-${request.certificate_request_id}`}>Remarks (required to reject)</Label>
            <Textarea
              id={`cert-remarks-${request.certificate_request_id}`}
              value={remarks}
              onChange={(e) => setRemarks(e.target.value)}
              maxLength={500}
            />
          </div>
          {error ? <ErrorPanel message={error} /> : null}
          {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
          <div className="flex gap-2">
            <Button size="sm" onClick={() => decide(true)} disabled={busy}>
              Approve
            </Button>
            <Button size="sm" variant="destructive" onClick={() => decide(false)} disabled={busy || !remarks.trim()}>
              Reject
            </Button>
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

function IssueControl({ request }: { request: CertificateRequest }) {
  const { busy, error, notice, run } = useRpcAction();
  const [open, setOpen] = useState(false);
  const [number, setNumber] = useState('');
  const [file, setFile] = useState<PickedFile | null>(null);
  const [checksum, setChecksum] = useState('');

  async function issue() {
    if (!file) return;
    await run<void>(
      'cert_request_issue',
      {
        p_id: request.certificate_request_id,
        p_certificate_number: number.trim(),
        p_storage_key: file.storageKey,
        p_file_name: file.fileName,
        p_size: file.size,
        p_checksum: checksum.trim() || null,
      },
      { success: 'The certificate has been issued.' },
    );
    setOpen(false);
  }

  if (!request.can_issue) return null;

  return (
    <div className="space-y-2">
      {open ? (
        <>
          <div className="grid gap-2 sm:grid-cols-2">
            <div className="space-y-1">
              <Label htmlFor={`cert-number-${request.certificate_request_id}`}>Certificate number</Label>
              <Input id={`cert-number-${request.certificate_request_id}`} value={number} onChange={(e) => setNumber(e.target.value)} maxLength={50} />
            </div>
            <FileUploadField
              id={`cert-file-${request.certificate_request_id}`}
              label="Certificate file"
              prefix={`student/${request.student_id}`}
              onUploaded={setFile}
            />
          </div>
          <div className="space-y-1">
            <Label htmlFor={`cert-checksum-${request.certificate_request_id}`}>SHA-256 checksum (optional)</Label>
            <Input id={`cert-checksum-${request.certificate_request_id}`} value={checksum} onChange={(e) => setChecksum(e.target.value)} maxLength={64} />
          </div>
          {error ? <ErrorPanel message={error} /> : null}
          {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}
          <div className="flex gap-2">
            <Button size="sm" onClick={issue} disabled={busy || !number.trim() || !file}>
              Issue
            </Button>
            <Button size="sm" variant="ghost" onClick={() => setOpen(false)} disabled={busy}>
              Cancel
            </Button>
          </div>
        </>
      ) : (
        <Button size="sm" variant="outline" onClick={() => setOpen(true)}>
          Issue
        </Button>
      )}
    </div>
  );
}

/* --------------------------------------------------------- cancel/download */

function CancelControl({ request }: { request: CertificateRequest }) {
  const { busy, error, notice, run } = useRpcAction();

  async function cancel() {
    await run<void>('cert_request_cancel', { p_id: request.certificate_request_id }, { success: 'The request has been cancelled.' });
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

function DownloadControl({ request }: { request: CertificateRequest }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function download() {
    setBusy(true);
    setError(null);
    const res = await rpcCall<Record<string, unknown>>('cert_request_download_info', { p_id: request.certificate_request_id });
    if (!res.ok) {
      setBusy(false);
      setError(res.error);
      return;
    }
    const key = String(res.data.storage_key ?? '');
    const url = key ? await signedDocumentUrl(key) : null;
    setBusy(false);
    if (!url) {
      setError('The certificate file could not be opened.');
      return;
    }
    window.open(url, '_blank', 'noopener');
  }

  if (!request.has_file) return null;

  return (
    <div className="space-y-2">
      {error ? <ErrorPanel message={error} /> : null}
      <Button size="sm" variant="outline" onClick={download} disabled={busy}>
        {busy ? 'Opening…' : 'Download'}
      </Button>
    </div>
  );
}

/* -------------------------------------------------------------- workspace */

export function CertificateWorkspace({ rows }: { rows: CertificateRequest[] }) {
  if (rows.length === 0) {
    return <EmptyState title="No certificate requests" description="Requests appear here once they are raised." />;
  }

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Request</TableHead>
          <TableHead>Student</TableHead>
          <TableHead>Certificate</TableHead>
          <TableHead>Purpose</TableHead>
          <TableHead>Status</TableHead>
          <TableHead>Requested</TableHead>
          <TableHead>Actions</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {rows.map((r) => (
          <TableRow key={r.certificate_request_id}>
            <TableCell className="font-mono text-xs">{r.request_number}</TableCell>
            <TableCell>
              <div>{r.student_name}</div>
              <div className="text-xs text-muted-foreground">{r.student_number}</div>
            </TableCell>
            <TableCell>{r.certificate_name}</TableCell>
            <TableCell className="max-w-xs text-xs">{r.purpose}</TableCell>
            <TableCell>
              <Badge variant={statusVariant(r.request_status)}>{humanise(r.request_status)}</Badge>
              {r.certificate_number ? <div className="mt-1 font-mono text-xs">{r.certificate_number}</div> : null}
              {r.issued_at ? <div className="text-xs text-muted-foreground">{formatDateTime(r.issued_at)}</div> : null}
            </TableCell>
            <TableCell>{formatDateTime(r.requested_at)}</TableCell>
            <TableCell>
              <div className="flex flex-col gap-2">
                <DecideControl request={r} />
                <IssueControl request={r} />
                <DownloadControl request={r} />
                <CancelControl request={r} />
              </div>
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
