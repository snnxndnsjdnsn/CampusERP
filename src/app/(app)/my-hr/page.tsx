import { PageHeader, StatTile } from '@/components/page-header';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { AdminTableEditor } from '@/features/admin/admin-table-editor';
import {
  AadhaarPanel,
  BankPanel,
  CompetencyPanel,
  EMPTY_CAN,
  PanPanel,
  type CompetencySummary,
  type CourseOption,
  type SensitiveSummary,
} from '@/features/hr/hr-client';
import {
  EmployeeDocumentRegisterForm,
  EmployeeDocumentTable,
  type DocumentCategory,
  type DocumentTypeOption,
  type EmployeeDocument,
} from '@/features/hr/hr-documents-client';
import { asJsonObject, safeRpc, safeRows, safeSelect } from '@/features/shared/server-rpc';
import { formatNumber } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

export default async function MyHrPage() {
  const { ctx, supabase } = await requireContext();
  const employeeId = ctx.employee_id;

  // Every read below is scoped to the caller's own employee record; the database
  // still decides whether the caller may see it.
  const sensitiveResult =
    employeeId === null ? { data: null, error: null } : await safeRpc<SensitiveSummary>(supabase, 'emp_sensitive_list', { p_employee_id: employeeId });
  const summary = asJsonObject<SensitiveSummary>(sensitiveResult.data);
  const can = summary?.can ?? EMPTY_CAN;

  const documents =
    employeeId === null
      ? { rows: [] as EmployeeDocument[], error: null as string | null }
      : await safeRows<EmployeeDocument>(supabase, 'employee_document_list', { p_employee_id: employeeId });

  const competencyResult =
    employeeId === null ? { data: null, error: null } : await safeRpc<CompetencySummary>(supabase, 'emp_competency_list', { p_employee_id: employeeId });
  const competencies = asJsonObject<CompetencySummary>(competencyResult.data);

  // Reference data for the document form.
  const categories = await safeSelect<DocumentCategory>(
    supabase,
    'employee_document_category',
    'employee_document_category_id, category_code, category_name, is_active',
    { order: { column: 'category_name', ascending: true } },
  );
  const documentTypes = await safeRows<{ id: number; label: string }>(supabase, 'section_lookup_options', {
    p_table: 'document_type',
  });

  // The course catalogue needs curriculum rights; without them the competency
  // form falls back to a course id.
  const courses = await safeSelect<CourseOption>(supabase, 'course_catalog', 'course_id, course_code, course_title', {
    order: { column: 'course_code', ascending: true },
    limit: 500,
  });

  const typeOptions: DocumentTypeOption[] = documentTypes.rows.map((t) => ({ id: Number(t.id), label: String(t.label ?? '') }));
  const pending = documents.rows.filter((d) => d.verification_status === 'PENDING').length;

  return (
    <>
      <PageHeader title="My HR records" description="Your PAN, Aadhaar, bank accounts, documents and competencies." />

      {/*
        The panel comes before the "no employee record" branch on purpose.  The
        screen is the employee's own file, but an administrator who is not an
        employee still has to be able to reach the employee master and the HR
        tables from here - the panel only offers the tables that caller may
        write to, so it stays empty for an account without the permission.
      */}
      <AdminTableEditor
        modules={['EMPLOYEE']}
        title="Manage the HR records"
        description="Add, edit and remove the employee records, their assignments and the HR details behind this screen. Every change is written through the database and audited."
      />

      {employeeId === null ? (
        <EmptyState title="No employee record" description="This account is not linked to an employee, so there are no HR records to show." />
      ) : (
        <>
          <div className="grid gap-4 sm:grid-cols-3">
            <StatTile label="Documents" value={formatNumber(documents.rows.length)} />
            <StatTile label="Awaiting verification" value={formatNumber(pending)} tone="warning" />
            <StatTile label="Competencies" value={formatNumber(competencies?.rows.length ?? 0)} />
          </div>

          {sensitiveResult.error ? <ErrorPanel message={sensitiveResult.error} /> : null}

          <section className="mt-6">
            <Card>
              <CardHeader>
                <CardTitle>PAN</CardTitle>
              </CardHeader>
              <CardContent>
                <PanPanel employeeId={employeeId} pan={summary?.pan ?? null} can={can} />
              </CardContent>
            </Card>
          </section>

          <section className="mt-6">
            <Card>
              <CardHeader>
                <CardTitle>Aadhaar</CardTitle>
              </CardHeader>
              <CardContent>
                <AadhaarPanel employeeId={employeeId} aadhaar={summary?.aadhaar ?? null} can={can} />
              </CardContent>
            </Card>
          </section>

          <section className="mt-6">
            <Card>
              <CardHeader>
                <CardTitle>Bank accounts</CardTitle>
              </CardHeader>
              <CardContent>
                <BankPanel employeeId={employeeId} accounts={summary?.bank ?? []} can={can} />
              </CardContent>
            </Card>
          </section>

          <section className="mt-6">
            <Card>
              <CardHeader>
                <CardTitle>Register a document</CardTitle>
              </CardHeader>
              <CardContent>
                {categories.error ? <ErrorPanel message={categories.error} /> : null}
                <EmployeeDocumentRegisterForm employeeId={employeeId} categories={categories.rows} documentTypes={typeOptions} />
              </CardContent>
            </Card>
          </section>

          <section className="mt-6">
            <Card>
              <CardHeader>
                <CardTitle>My documents</CardTitle>
              </CardHeader>
              <CardContent>
                {documents.error ? <ErrorPanel message={documents.error} /> : <EmployeeDocumentTable rows={documents.rows} />}
              </CardContent>
            </Card>
          </section>

          <section className="mt-6">
            <Card>
              <CardHeader>
                <CardTitle>Competencies</CardTitle>
              </CardHeader>
              <CardContent>
                {competencyResult.error ? (
                  <ErrorPanel message={competencyResult.error} />
                ) : (
                  <CompetencyPanel
                    employeeId={employeeId}
                    summary={competencies ?? { can_edit: false, can_delete: false, rows: [] }}
                    courses={courses.rows}
                  />
                )}
              </CardContent>
            </Card>
          </section>
        </>
      )}
    </>
  );
}
