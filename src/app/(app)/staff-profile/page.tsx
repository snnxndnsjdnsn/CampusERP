import { PageHeader, StatTile } from '@/components/page-header';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { ErrorPanel } from '@/components/ui/empty-state';
import {
  readActivityTypes,
  readEmployees,
  sectionLookupOptions,
  staffLookupOptions,
  tableOptions,
} from '@/features/staff-profile/data';
import { StaffProfileDesk } from '@/features/staff-profile/staff-profile-client';
import type { StaffActivityRow, StaffReportRow } from '@/features/staff-profile/types';
import { SearchForm } from '@/features/shared/search-form';
import { safeRows } from '@/features/shared/server-rpc';
import { formatNumber } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

/**
 * Staff profile & research.
 *
 * The list comes from `staff_activity_list`, which decides what the caller may
 * see. Opening a record asks `staff_activity_get`; the per-type detail form is
 * built from `staff_detail_schema`, so the database describes its own fields.
 */

const APPROVAL_STATUSES = ['DRAFT', 'SUBMITTED', 'UNDER_REVIEW', 'APPROVED', 'REJECTED'];

export default async function StaffProfilePage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; approval?: string; group?: string }>;
}) {
  const { supabase } = await requireContext();
  const sp = await searchParams;

  const q = (sp.q ?? '').trim();
  const approval = (sp.approval ?? '').trim();
  const group = (sp.group ?? '').trim();

  const [activities, report, types, years, employees, evidenceTypes, participationLevels, roleTypes, documentTypes, indexingAgencies] =
    await Promise.all([
      safeRows<StaffActivityRow>(supabase, 'staff_activity_list', {
        p_search: q || null,
        p_approval: approval || null,
        p_group: group || null,
        p_limit: 50,
      }),
      safeRows<StaffReportRow>(supabase, 'staff_activity_report', { p_year: null }),
      readActivityTypes(supabase),
      tableOptions(supabase, {
        table: 'academic_year',
        idColumn: 'academic_year_id',
        labelColumn: 'year_code',
      }),
      readEmployees(supabase),
      tableOptions(supabase, {
        table: 'evidence_type',
        idColumn: 'evidence_type_id',
        labelColumn: 'evidence_type_name',
        extraColumns: ['is_active'],
        activeOnly: true,
      }),
      staffLookupOptions(supabase, 'participation_level'),
      staffLookupOptions(supabase, 'role_type'),
      sectionLookupOptions(supabase, 'document_type'),
      sectionLookupOptions(supabase, 'indexing_agency'),
    ]);

  const groupOptions = types.rows
    .map((t) => t.activity_group)
    .filter((g) => g !== '')
    .filter((g, i, all) => all.indexOf(g) === i)
    .map((g) => ({ value: g, label: g }));

  const readErrors = [
    activities.error,
    report.error,
    types.error,
    years.error,
    employees.error,
    evidenceTypes.error,
    participationLevels.error,
    roleTypes.error,
    documentTypes.error,
    indexingAgencies.error,
  ].filter((e): e is string => Boolean(e));

  return (
    <>
      <PageHeader
        title="Staff profile"
        description="Research, publications, professional development and every other activity recorded against a member of staff. The database decides what each person may see."
      />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatTile label="Activities" value={formatNumber(activities.rows.length)} />
        <StatTile label="Groups" value={formatNumber(new Set(activities.rows.map((a) => a.activity_group)).size)} />
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
            action="/staff-profile"
            query={q}
            placeholder="Title, staff member or employee number"
            label="Search activities"
            filters={[
              {
                name: 'approval',
                label: 'Approval',
                value: approval,
                options: APPROVAL_STATUSES.map((s) => ({ value: s, label: s })),
              },
              {
                name: 'group',
                label: 'Group',
                value: group,
                options: groupOptions,
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
        <StaffProfileDesk
          activities={activities.rows}
          types={types.rows}
          years={years.options}
          participationLevels={participationLevels.options}
          roleTypes={roleTypes.options}
          employees={employees.rows}
          documentTypes={documentTypes.options}
          evidenceTypes={evidenceTypes.options}
          indexingAgencies={indexingAgencies.options}
          report={report.rows}
          readError={activities.error}
        />
      </div>
    </>
  );
}
