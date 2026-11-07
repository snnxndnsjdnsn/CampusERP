import type { SupabaseClient } from '@supabase/supabase-js';
import { PageHeader, StatTile } from '@/components/page-header';
import { Badge } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { ErrorPanel, EmptyState } from '@/components/ui/empty-state';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { ActivityReport, GlobalSearch } from '@/features/reporting/reporting-client';
import { REPORTING_VIEWS, type ReportingView } from '@/features/reporting/reporting-views';
import { canReadModule } from '@/lib/context';
import { formatNumber } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

/** How many columns of a sample row are shown before the table is cut short. */
const SAMPLE_COLUMNS = 8;

/** One reporting view, as it was read. */
type ViewRead = {
  /** The view name, as the database spells it. */
  name: string;
  /** One line saying what the view is for. */
  description: string;
  /** How many rows the view holds for this caller. */
  count: number | null;
  /** The columns of the sample rows. */
  columns: string[];
  /** The sample rows. */
  rows: Record<string, unknown>[];
  /** Why the view could not be read, if it could not. */
  error: string | null;
};

/**
 * Reporting and search views - schema module 37.
 *
 * The database offers a set of views that join the tables of several modules
 * into the shapes the reports need. The page reads each of them to prove it
 * works, and the live search and the two activity reports are run from the
 * browser so that they are always current.
 */
export default async function ReportingPage() {
  const { ctx, supabase } = await requireContext();

  // The sidebar only offers the reporting screen to a caller who can read the
  // `REPORTING` module. The address has to agree with the sidebar, otherwise a
  // typed URL would open a screen the navigation deliberately hides. The
  // database still refuses the data itself - this is the door, not the lock.
  if (!canReadModule(ctx, 'REPORTING')) {
    return (
      <>
        <PageHeader
          title="37 · Reporting and search views"
          description="The views the database offers for reporting, and the live search and activity reports that read them."
        />
        <EmptyState
          title="This screen is not open to your account"
          description="It belongs to the REPORTING module, and your account does not read it. The sidebar only offers it to the accounts that may use it."
        />
      </>
    );
  }

  const views = await Promise.all(REPORTING_VIEWS.map((v) => readReportingView(supabase, v)));
  const readable = views.filter((v) => !v.error).length;

  return (
    <>
      <PageHeader
        title="37 · Reporting and search views"
        description="The views the database offers for reporting, and the live search and activity reports that read them."
      />

      <div className="grid gap-4 sm:grid-cols-3">
        <StatTile label="Views" value={formatNumber(views.length)} />
        <StatTile label="Readable" value={formatNumber(readable)} tone="success" />
        <StatTile label="Not readable" value={formatNumber(views.length - readable)} tone={views.length - readable > 0 ? 'warning' : 'default'} />
      </div>

      <section className="mt-6">
        <Card>
          <CardHeader>
            <CardTitle>Search</CardTitle>
            <CardDescription>
              The directory search of the database. It matches students, employees, courses, programmes and departments.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <GlobalSearch />
          </CardContent>
        </Card>
      </section>

      <section className="mt-6 grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Staff activity report</CardTitle>
            <CardDescription>Records and staff members per activity group and approval status.</CardDescription>
          </CardHeader>
          <CardContent>
            <ActivityReport
              fn="staff_activity_report"
              title="Staff activity"
              description="The report checks STAFF_PROFILE.STAFF_REPORT.READ before it aggregates."
            />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Student activity report</CardTitle>
            <CardDescription>Activities and awards per activity type and approval status.</CardDescription>
          </CardHeader>
          <CardContent>
            <ActivityReport
              fn="student_activity_report"
              title="Student activity"
              description="The report checks the student activity report permission before it aggregates."
            />
          </CardContent>
        </Card>
      </section>

      <section className="mt-6">
        <h2 className="mb-2 text-sm font-semibold uppercase tracking-wide text-muted-foreground">Views</h2>
        <div className="space-y-4">
          {views.map((view) => (
            <ViewCard key={view.name} view={view} />
          ))}
        </div>
      </section>
    </>
  );
}

function ViewCard({ view }: { view: ViewRead }) {
  const columns = view.columns.slice(0, SAMPLE_COLUMNS);

  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-center gap-2">
          <CardTitle className="font-mono text-sm">{view.name}</CardTitle>
          {view.error ? (
            <Badge variant="destructive">Not readable</Badge>
          ) : (
            <Badge variant="muted">{formatNumber(view.count ?? 0)} rows</Badge>
          )}
        </div>
        <CardDescription>{view.description}</CardDescription>
      </CardHeader>
      <CardContent>
        {view.error ? (
          <ErrorPanel message={view.error} />
        ) : view.rows.length === 0 ? (
          <p className="text-sm text-muted-foreground">The view returned no rows for you.</p>
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                {columns.map((column) => (
                  <TableHead key={column}>{column}</TableHead>
                ))}
              </TableRow>
            </TableHeader>
            <TableBody>
              {view.rows.map((row, i) => (
                <TableRow key={i}>
                  {columns.map((column) => (
                    <TableCell key={column} className="text-xs">
                      {row[column] === null || row[column] === undefined ? '—' : String(row[column])}
                    </TableCell>
                  ))}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        )}
      </CardContent>
    </Card>
  );
}

/**
 * Read a couple of rows of a reporting view.
 *
 * The read proves the view is there and reachable for this caller; the count
 * that comes back with it is the number of rows the caller may see.
 */
async function readReportingView(supabase: SupabaseClient, view: ReportingView): Promise<ViewRead> {
  try {
    const { data, count, error } = await supabase.from(view.name).select('*', { count: 'exact' }).limit(2);
    if (error) {
      return { name: view.name, description: view.description, count: null, columns: [], rows: [], error: error.message };
    }

    const rows = (data ?? []) as Record<string, unknown>[];
    const columns = rows.length > 0 ? Object.keys(rows[0]!) : [];
    return { name: view.name, description: view.description, count: count ?? null, columns, rows, error: null };
  } catch (e) {
    return {
      name: view.name,
      description: view.description,
      count: null,
      columns: [],
      rows: [],
      error: e instanceof Error ? e.message : 'The view could not be read.',
    };
  }
}
