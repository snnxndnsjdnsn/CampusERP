import { PageHeader, StatTile } from '@/components/page-header';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { ErrorPanel } from '@/components/ui/empty-state';
import { ActivitiesDesk } from '@/features/activities/activities-client';
import { readActivityTypes, readStudents, tableOptions } from '@/features/activities/data';
import type { ActivityReportRow, StudentActivityRow } from '@/features/activities/types';
import { SearchForm } from '@/features/shared/search-form';
import { safeRows } from '@/features/shared/server-rpc';
import { formatNumber } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

/**
 * Module 40 · Student activities.
 *
 * The list comes from `student_activity_list`, which decides what the caller may
 * see. Opening a record asks `student_activity_get`; every move — the team, the
 * evidence, the review — is a `student_activity_*` function.
 */

const APPROVAL_STATUSES = ['DRAFT', 'SUBMITTED', 'UNDER_REVIEW', 'APPROVED', 'REJECTED'];

export default async function ActivitiesPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; approval?: string }>;
}) {
  const { supabase } = await requireContext();
  const sp = await searchParams;

  const q = (sp.q ?? '').trim();
  const approval = (sp.approval ?? '').trim();

  const [activities, report, types, years, participationLevels, eventModes, students, documentTypes, evidenceTypes] =
    await Promise.all([
      safeRows<StudentActivityRow>(supabase, 'student_activity_list', {
        p_search: q || null,
        p_approval: approval || null,
        p_limit: 50,
      }),
      safeRows<ActivityReportRow>(supabase, 'student_activity_report', { p_year: null }),
      readActivityTypes(supabase),
      tableOptions(supabase, {
        table: 'academic_year',
        idColumn: 'academic_year_id',
        labelColumn: 'year_code',
      }),
      tableOptions(supabase, {
        table: 'participation_level',
        idColumn: 'participation_level_id',
        labelColumn: 'level_name',
        extraColumns: ['is_active'],
        activeOnly: true,
      }),
      tableOptions(supabase, {
        table: 'event_mode',
        idColumn: 'event_mode_id',
        labelColumn: 'mode_name',
        extraColumns: ['is_active'],
        activeOnly: true,
      }),
      readStudents(supabase),
      tableOptions(supabase, {
        table: 'document_type',
        idColumn: 'document_type_id',
        labelColumn: 'document_name',
        extraColumns: ['is_active'],
        activeOnly: true,
      }),
      tableOptions(supabase, {
        table: 'evidence_type',
        idColumn: 'evidence_type_id',
        labelColumn: 'evidence_type_name',
        extraColumns: ['is_active'],
        activeOnly: true,
      }),
    ]);

  const readErrors = [
    activities.error,
    report.error,
    types.error,
    years.error,
    participationLevels.error,
    eventModes.error,
    students.error,
    documentTypes.error,
    evidenceTypes.error,
  ].filter((e): e is string => Boolean(e));

  return (
    <>
      <PageHeader
        title="Student activities"
        description="Competitions, conferences, clubs, sports and community work. A student records the activity, then it is verified and approved."
      />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatTile label="Activities" value={formatNumber(activities.rows.length)} />
        <StatTile label="Types" value={formatNumber(types.rows.filter((t) => t.is_active !== false).length)} />
        <StatTile
          label="Awaiting approval"
          value={formatNumber(activities.rows.filter((a) => a.approval_status === 'UNDER_REVIEW').length)}
          tone="warning"
        />
        <StatTile
          label="Approved"
          value={formatNumber(activities.rows.filter((a) => a.approval_status === 'APPROVED').length)}
          tone="success"
        />
      </div>

      <Card className="mt-6">
        <CardHeader>
          <CardTitle>Filter</CardTitle>
          <CardDescription>The filters live in the address bar, so every result set can be shared.</CardDescription>
        </CardHeader>
        <CardContent>
          <SearchForm
            action="/activities"
            query={q}
            placeholder="Title, student name or student number"
            label="Search activities"
            filters={[
              {
                name: 'approval',
                label: 'Approval',
                value: approval,
                options: APPROVAL_STATUSES.map((s) => ({ value: s, label: s })),
              },
            ]}
          />
        </CardContent>
      </Card>

      {readErrors.length > 0 ? (
        <div className="mt-6">
          <ErrorPanel message={`Some parts of this screen could not be read: ${readErrors.join('; ')}`} />
        </div>
      ) : null}

      <div className="mt-6">
        <ActivitiesDesk
          activities={activities.rows}
          types={types.rows}
          years={years.options}
          participationLevels={participationLevels.options}
          eventModes={eventModes.options}
          students={students.rows}
          documentTypes={documentTypes.options}
          evidenceTypes={evidenceTypes.options}
          report={report.rows}
          readError={activities.error}
        />
      </div>
    </>
  );
}
