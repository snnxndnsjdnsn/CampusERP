import { PageHeader, StatTile } from '@/components/page-header';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { AdminTableEditor } from '@/features/admin/admin-table-editor';
import { DocumentRegisterForm, MyDocumentsPanel, type Lookup, type StudentDocument } from '@/features/my-documents/my-documents-client';
import { safeRows } from '@/features/shared/server-rpc';
import { formatNumber } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

export default async function MyDocumentsPage() {
  const { ctx, supabase } = await requireContext();
  const studentId = ctx.student_id;

  // The database decides which documents this caller may read; the page only shows
  // what `student_document_list` returns for the caller's own student record.
  const documents =
    studentId === null
      ? { rows: [] as StudentDocument[], error: null as string | null }
      : await safeRows<StudentDocument>(supabase, 'student_document_list', { p_student_id: studentId });

  // Document types are reference data; `section_lookup_options` is the public reader.
  const types = await safeRows<{ id: number; label: string }>(supabase, 'section_lookup_options', {
    p_table: 'document_type',
  });
  const typeOptions: Lookup[] = types.rows.map((t) => ({ id: Number(t.id), label: String(t.label ?? '') }));

  const pending = documents.rows.filter((d) => d.verification_status === 'PENDING').length;
  const verified = documents.rows.filter((d) => d.verification_status === 'VERIFIED').length;

  return (
    <>
      <PageHeader title="My documents" description="Register the documents the college holds for you, and follow their verification." />

      <AdminTableEditor
        modules={['DOCUMENT']}
        title="Manage the document records"
        description="Add, edit and remove the certificate types, certificate requests, student documents and student exits behind this screen. Every change is written through the database and audited."
      />

      <div className="grid gap-4 sm:grid-cols-3">
        <StatTile label="Registered" value={formatNumber(documents.rows.length)} />
        <StatTile label="Awaiting verification" value={formatNumber(pending)} tone="warning" />
        <StatTile label="Verified" value={formatNumber(verified)} tone="success" />
      </div>

      {studentId === null ? (
        <section className="mt-6">
          <EmptyState title="No student record" description="This account is not linked to a student, so there are no documents to show." />
        </section>
      ) : (
        <>
          <section className="mt-6">
            <Card>
              <CardHeader>
                <CardTitle>Register a document</CardTitle>
              </CardHeader>
              <CardContent>
                {types.error ? <ErrorPanel message={types.error} /> : <DocumentRegisterForm studentId={studentId} documentTypes={typeOptions} />}
              </CardContent>
            </Card>
          </section>

          <section className="mt-6">
            <Card>
              <CardHeader>
                <CardTitle>My documents</CardTitle>
              </CardHeader>
              <CardContent>
                {documents.error ? <ErrorPanel message={documents.error} /> : <MyDocumentsPanel rows={documents.rows} />}
              </CardContent>
            </Card>
          </section>
        </>
      )}
    </>
  );
}
