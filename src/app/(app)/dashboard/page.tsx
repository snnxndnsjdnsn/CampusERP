import Link from 'next/link';
import { PageHeader, StatTile } from '@/components/page-header';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState } from '@/components/ui/empty-state';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { loadDashboardStats, loadStudentDashboard, readableModuleList } from '@/features/dashboard-stats';
import { formatMoney, formatNumber, formatPercent, formatTime } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

function StatusBreakdown({ title, rows }: { title: string; rows: { label: string; n: number }[] }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
      </CardHeader>
      <CardContent>
        {rows.length === 0 ? (
          <p className="text-sm text-muted-foreground">No data visible to you.</p>
        ) : (
          <ul className="space-y-2">
            {rows.map((r) => (
              <li key={r.label} className="flex items-center justify-between gap-3">
                <Badge variant={statusVariant(r.label)}>{r.label}</Badge>
                <span className="font-medium tabular-nums">{formatNumber(r.n)}</span>
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}

export default async function DashboardPage() {
  const { ctx, supabase } = await requireContext();

  if (ctx.student_id !== null) {
    const student = await loadStudentDashboard(supabase);
    const totalConducted = student.attendance.reduce((a, c) => a + c.conducted, 0);
    const totalPresent = student.attendance.reduce((a, c) => a + c.present, 0);
    const overall = totalConducted > 0 ? (100 * totalPresent) / totalConducted : null;

    return (
      <>
        <PageHeader title={`Welcome, ${ctx.username}`} description="Your attendance, classes and results at a glance." />
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <StatTile label="Overall attendance" value={overall === null ? '—' : formatPercent(overall)} />
          <StatTile label="Classes attended" value={`${formatNumber(totalPresent)} / ${formatNumber(totalConducted)}`} />
          <StatTile label="Classes today" value={formatNumber(student.today.length)} />
          <StatTile label="Published results" value={formatNumber(student.results.length)} />
        </div>

        <div className="mt-6 grid gap-4 lg:grid-cols-2">
          <Card>
            <CardHeader>
              <CardTitle>Attendance by course</CardTitle>
            </CardHeader>
            <CardContent>
              {student.attendance.length === 0 ? (
                <EmptyState title="No attendance recorded yet" description="Attendance appears here once your classes begin." />
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Course</TableHead>
                      <TableHead className="text-right">Held</TableHead>
                      <TableHead className="text-right">Present</TableHead>
                      <TableHead className="text-right">%</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {student.attendance.map((a) => (
                      <TableRow key={a.section_id}>
                        <TableCell>{a.course}</TableCell>
                        <TableCell className="text-right tabular-nums">{formatNumber(a.conducted)}</TableCell>
                        <TableCell className="text-right tabular-nums">{formatNumber(a.present)}</TableCell>
                        <TableCell className="text-right tabular-nums">{formatPercent(a.percentage)}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Today&apos;s classes</CardTitle>
            </CardHeader>
            <CardContent>
              {student.today.length === 0 ? (
                <EmptyState title="No classes scheduled today" />
              ) : (
                <ul className="space-y-2">
                  {student.today.map((t, i) => (
                    <li key={`${t.course}-${i}`} className="flex items-center justify-between gap-3 text-sm">
                      <span>{t.course}</span>
                      <span className="text-muted-foreground">
                        {formatTime(t.start)} – {formatTime(t.end)}
                        {t.room ? ` · ${t.room}` : ''}
                      </span>
                    </li>
                  ))}
                </ul>
              )}
            </CardContent>
          </Card>
        </div>

        <div className="mt-6">
          <Link href="/my-results" className="text-sm font-medium text-primary underline-offset-4 hover:underline">
            View my results →
          </Link>
        </div>
      </>
    );
  }

  const stats = await loadDashboardStats(supabase);
  const modules = readableModuleList(ctx);

  return (
    <>
      <PageHeader
        title={`Welcome, ${ctx.username}`}
        description="Institutional overview. Every figure is scoped by your role and enforced by the database."
      />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatTile
          label="Applications"
          value={formatNumber(stats.applications.reduce((a, r) => a + r.n, 0))}
          hint={`${stats.applications.length} statuses`}
        />
        <StatTile
          label="Term registrations"
          value={formatNumber(stats.registrations.reduce((a, r) => a + r.n, 0))}
          hint={`${stats.registrations.length} statuses`}
        />
        <StatTile
          label="Fee outstanding"
          value={formatMoney(stats.feeOutstanding?.balance ?? 0)}
          tone={(stats.feeOutstanding?.balance ?? 0) > 0 ? 'warning' : 'default'}
          hint={`${formatNumber(stats.feeOutstanding?.overdue_assessments ?? 0)} overdue`}
        />
        <StatTile
          label="Modules readable"
          value={formatNumber(modules.length)}
          hint={modules.slice(0, 3).join(', ') || 'none'}
        />
      </div>

      <div className="mt-6 grid gap-4 md:grid-cols-2 xl:grid-cols-4">
        <StatusBreakdown title="Admission applications" rows={stats.applications} />
        <StatusBreakdown title="Term registrations" rows={stats.registrations} />
        <StatusBreakdown title="Sessions (30 days)" rows={stats.sessions} />
        <StatusBreakdown title="Term results" rows={stats.termResults} />
      </div>

      <div className="mt-6 grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Fee collection · last 6 months</CardTitle>
          </CardHeader>
          <CardContent>
            {stats.feeCollection.length === 0 ? (
              <p className="text-sm text-muted-foreground">No collections visible to you.</p>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Month</TableHead>
                    <TableHead className="text-right">Collected</TableHead>
                    <TableHead className="text-right">Payments</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {stats.feeCollection.map((m) => (
                    <TableRow key={m.month}>
                      <TableCell>{m.month}</TableCell>
                      <TableCell className="text-right tabular-nums">{formatMoney(m.collected)}</TableCell>
                      <TableCell className="text-right tabular-nums">{formatNumber(m.payments)}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Enrolments by programme</CardTitle>
          </CardHeader>
          <CardContent>
            {stats.enrolments.length === 0 ? (
              <p className="text-sm text-muted-foreground">No enrolments visible to you.</p>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>Programme</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead className="text-right">Students</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {stats.enrolments.map((e) => (
                    <TableRow key={`${e.programme_id}-${e.enrolment_status}`}>
                      <TableCell>{e.label}</TableCell>
                      <TableCell>
                        <Badge variant={statusVariant(e.enrolment_status)}>{e.enrolment_status}</Badge>
                      </TableCell>
                      <TableCell className="text-right tabular-nums">{formatNumber(e.n)}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>
      </div>
    </>
  );
}
