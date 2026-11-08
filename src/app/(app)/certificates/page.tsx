import { PageHeader, StatTile } from '@/components/page-header';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { ErrorPanel } from '@/components/ui/empty-state';
import { AdminTableEditor } from '@/features/admin/admin-table-editor';
import { CertificateRequestForm, CertificateWorkspace, type CertificateRequest, type Lookup } from '@/features/certificates/certificates-client';
import { safeRows } from '@/features/shared/server-rpc';
import { formatNumber } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

export default async function CertificatesPage() {
  const { ctx, supabase } = await requireContext();

  // The database decides which students' requests this caller may read.
  const requests = await safeRows<CertificateRequest>(supabase, 'cert_request_list');

  // Certificate types are reference data; `section_lookup_options` is the public
  // reader for them and applies the same rules as every other lookup.
  const types = await safeRows<{ id: number; label: string }>(supabase, 'section_lookup_options', {
    p_table: 'certificate_type',
  });
  const typeOptions: Lookup[] = types.rows.map((t) => ({ id: Number(t.id), label: String(t.label ?? '') }));

  const submitted = requests.rows.filter((r) => r.request_status === 'SUBMITTED').length;
  const approved = requests.rows.filter((r) => r.request_status === 'APPROVED').length;
  const issued = requests.rows.filter((r) => r.request_status === 'ISSUED').length;

  return (
    <>
      <PageHeader
        title="Certificates"
        description="Raise a certificate request, decide the ones waiting for you, and issue the approved ones."
      />

      <AdminTableEditor
        modules={['DOCUMENT']}
        title="Manage certificates"
        description="Add, edit and remove the certificate types, certificate requests, student documents and student exits behind this screen. Every change is written through the database and audited."
      />

      <div className="grid gap-4 sm:grid-cols-3">
        <StatTile label="Awaiting a decision" value={formatNumber(submitted)} />
        <StatTile label="Approved, not issued" value={formatNumber(approved)} />
        <StatTile label="Issued" value={formatNumber(issued)} />
      </div>

      {ctx.student_id !== null ? (
        <section className="mt-6">
          <Card>
            <CardHeader>
              <CardTitle>Request a certificate</CardTitle>
            </CardHeader>
            <CardContent>
              {types.error ? <ErrorPanel message={types.error} /> : <CertificateRequestForm types={typeOptions} />}
            </CardContent>
          </Card>
        </section>
      ) : null}

      <section className="mt-6">
        <Card>
          <CardHeader>
            <CardTitle>Certificate requests</CardTitle>
          </CardHeader>
          <CardContent>
            {requests.error ? <ErrorPanel message={requests.error} /> : <CertificateWorkspace rows={requests.rows} />}
          </CardContent>
        </Card>
      </section>
    </>
  );
}
