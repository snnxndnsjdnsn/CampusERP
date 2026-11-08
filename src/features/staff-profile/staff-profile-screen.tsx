import { PageHeader, StatTile } from '@/components/page-header';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { ErrorPanel } from '@/components/ui/empty-state';
import { AdminTableEditor } from '@/features/admin/admin-table-editor';
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

const APPROVAL_STATUSES = ['DRAFT', 'SUBMITTED', 'UNDER_REVIEW', 'APPROVED', 'REJECTED'];

export type StaffProfileScreenProps = {
  /** Free-text search over title, staff member and employee number. */
  q?: string;
  /** Approval status filter. */
  approval?: string;
  /** `activity_type.activity_group` filter. */
  group?: string;
  /** Where the filter form posts, so a sub-module address keeps its section. */
  formAction?: string;
  /** Replaces the page heading when the screen is opened through a sub-module address. */
  heading?: { title: string; description: string };
};

/**
 * The staff profile screen.
 *
 * The list comes from `staff_activity_list`, which decides what the caller may
 * see. Opening a record asks `staff_activity_get`; the per-type detail form is
 * built from `staff_detail_schema`, so the database describes its own fields.
 *
 * Schema modules 20 to 34 are sections of this screen rather than screens of
 * their own: the route `/staff-profile/[section]` opens it filtered to the
 * section's `activity_group`. See `src/lib/staff-sections.ts`.
 */
export async function StaffProfileScreen({
  q = '',
  approval = '',
  group = '',
  formAction = '/staff-profile',
  heading,
}: StaffProfileScreenProps) {
  const { supabase } = await requireContext();

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
        title={heading?.title ?? 'Staff profile'}
        description={
          heading?.description ??
          'Research, publications, professional development and every other activity recorded against a member of staff. The database decides what each person may see.'
        }
      />

      <AdminTableEditor
        modules={['STAFF_PROFILE']}
        title="Manage the staff profile"
        description="Add, edit and remove the staff activity records and the vocabulary behind this screen. Every change is written through the database and audited."
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
            action={formAction}
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
