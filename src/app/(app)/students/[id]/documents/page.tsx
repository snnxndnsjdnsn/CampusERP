import Link from 'next/link';
import { notFound } from 'next/navigation';
import { PageHeader } from '@/components/page-header';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { DetailStack, DetailTable } from '@/features/detail/detail-ui';
import { safeRpc } from '@/features/shared/server-rpc';
import { formatDate, formatNumber } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

type DocumentRow = {
  student_document_id: number;
  document_type: string;
  requires_verification: boolean;
  original_file_name: string | null;
  mime_type: string | null;
  file_size_bytes: number | null;
  document_number: string | null;
  issue_date: string | null;
  expiry_date: string | null;
  verification_status: string;
  effective_status: string;
  verified_at: string | null;
  remarks: string | null;
  uploaded_at: string | null;
};

/**
 * A student's documents.
 *
 * `student_document_list` is SECURITY DEFINER and applies the caller's scope,
 * so a student sees their own documents and a verifier sees the ones in their
 * remit - the page never filters anything itself.
 */
export default async function StudentDocumentsPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { supabase } = await requireContext();

  const studentId = Number(id);
  if (!Number.isInteger(studentId) || studentId <= 0) notFound();

  const { data, error } = await safeRpc<DocumentRow[]>(supabase, 'student_document_list', {
    p_student_id: studentId,
  });
  const rows = data ?? [];

  return (
    <>
      <PageHeader
        title="Documents"
        description={`Documents held for student #${studentId}.`}
        actions={
          <Link href={`/students/${studentId}/records`}>
            <Button variant="outline">Back to the record</Button>
          </Link>
        }
      />

      <DetailStack>
        {error && (
          <p className="rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800" role="alert">
            {error}
          </p>
        )}

        <DetailTable
          title="Registered documents"
          rows={rows}
          rowKey={(r) => String(r.student_document_id)}
          emptyTitle="No documents on file"
          emptyDescription="Documents appear here once they have been registered against the student."
          columns={[
            { key: 'type', header: 'Type', render: (r) => r.document_type },
            { key: 'name', header: 'File', render: (r) => r.original_file_name ?? '—' },
            { key: 'number', header: 'Number', render: (r) => r.document_number ?? '—' },
            { key: 'issued', header: 'Issued', render: (r) => formatDate(r.issue_date) },
            { key: 'expires', header: 'Expires', render: (r) => formatDate(r.expiry_date) },
            {
              key: 'verification',
              header: 'Verification',
              render: (r) => <Badge variant={statusVariant(r.verification_status)}>{r.verification_status}</Badge>,
            },
            {
              key: 'effective',
              header: 'Effective',
              render: (r) => <Badge variant={statusVariant(r.effective_status)}>{r.effective_status}</Badge>,
            },
            {
              key: 'requires',
              header: 'Verification required',
              render: (r) => (r.requires_verification ? 'Yes' : 'No'),
            },
            { key: 'size', header: 'Size', numeric: true, render: (r) => formatNumber(r.file_size_bytes) },
            { key: 'uploaded', header: 'Uploaded', render: (r) => formatDate(r.uploaded_at) },
          ]}
        />
      </DetailStack>
    </>
  );
}
