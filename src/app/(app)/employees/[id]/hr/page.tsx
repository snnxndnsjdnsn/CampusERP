import Link from 'next/link';
import { notFound } from 'next/navigation';
import { PageHeader } from '@/components/page-header';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { AdminTableEditor } from '@/features/admin/admin-table-editor';
import { DetailStack, DetailTable } from '@/features/detail/detail-ui';
import { SensitivePanel, type SensitiveCan, type SensitiveRow } from '@/features/detail/sensitive-panel';
import { safeRpc } from '@/features/shared/server-rpc';
import { formatDate } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

type SensitivePayload = {
  pan?: SensitiveRow | null;
  aadhaar?: SensitiveRow | null;
  bank?: SensitiveRow[];
  can?: SensitiveCan;
};

type DocumentRow = {
  employee_document_id: number;
  category: string;
  document_title: string;
  original_file_name: string | null;
  document_number: string | null;
  issue_date: string | null;
  expiry_date: string | null;
  verification_status: string;
  effective_status: string;
  approval_status: string;
  confidentiality_level: string;
  uploaded_at: string | null;
};

/**
 * An employee's secure HR file.
 *
 * Both calls are SECURITY DEFINER and refuse anyone without the matching
 * permission, so the page shows only what the database allows and the reveal
 * action is audited by the database rather than by the browser.
 */
export default async function EmployeeHrPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const { supabase } = await requireContext();

  const employeeId = Number(id);
  if (!Number.isInteger(employeeId) || employeeId <= 0) notFound();

  const [sensitiveRes, documentsRes] = await Promise.all([
    safeRpc<SensitivePayload>(supabase, 'emp_sensitive_list', { p_employee_id: employeeId }),
    safeRpc<DocumentRow[]>(supabase, 'employee_document_list', { p_employee_id: employeeId }),
  ]);

  const payload = sensitiveRes.data;
  const documents = documentsRes.data ?? [];

  return (
    <>
      <PageHeader
        title="Secure HR file"
        description={`Employee #${employeeId}. Identifiers are masked until explicitly revealed.`}
        actions={
          <Link href={`/employees/${employeeId}/records`}>
            <Button variant="outline">Back to the record</Button>
          </Link>
        }
      />

      <AdminTableEditor
        modules={['EMPLOYEE']}
        title="Manage the HR file"
        description="Add, edit and remove the employee records, their assignments and the HR details behind this screen. Every change is written through the database and audited."
      />

      <DetailStack>
        {sensitiveRes.error && (
          <p className="rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800" role="alert">
            {sensitiveRes.error}
          </p>
        )}

        {payload && (
          <>
            <Card>
              <CardHeader>
                <CardTitle>PAN</CardTitle>
              </CardHeader>
              <CardContent>
                <SensitivePanel kind="PAN" rows={payload.pan ? [payload.pan] : []} can={payload.can ?? {}} />
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>Aadhaar</CardTitle>
              </CardHeader>
              <CardContent>
                <SensitivePanel kind="AADHAAR" rows={payload.aadhaar ? [payload.aadhaar] : []} can={payload.can ?? {}} />
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>Bank accounts</CardTitle>
              </CardHeader>
              <CardContent>
                <SensitivePanel kind="BANK_ACCOUNT" rows={payload.bank ?? []} can={payload.can ?? {}} />
              </CardContent>
            </Card>
          </>
        )}

        <DetailTable
          title="Documents"
          rows={documents}
          rowKey={(r) => String(r.employee_document_id)}
          emptyTitle="No documents on file"
          emptyDescription="Qualifications and evidence appear here once they have been registered."
          columns={[
            { key: 'title', header: 'Title', render: (r) => r.document_title },
            { key: 'category', header: 'Category', render: (r) => r.category },
            { key: 'file', header: 'File', render: (r) => r.original_file_name ?? '—' },
            { key: 'number', header: 'Number', render: (r) => r.document_number ?? '—' },
            { key: 'issued', header: 'Issued', render: (r) => formatDate(r.issue_date) },
            { key: 'expires', header: 'Expires', render: (r) => formatDate(r.expiry_date) },
            {
              key: 'verification',
              header: 'Verification',
              render: (r) => <Badge variant={statusVariant(r.verification_status)}>{r.verification_status}</Badge>,
            },
            {
              key: 'approval',
              header: 'Approval',
              render: (r) => <Badge variant={statusVariant(r.approval_status)}>{r.approval_status}</Badge>,
            },
            { key: 'confidentiality', header: 'Confidentiality', render: (r) => r.confidentiality_level },
            { key: 'uploaded', header: 'Uploaded', render: (r) => formatDate(r.uploaded_at) },
          ]}
        />
      </DetailStack>
    </>
  );
}
