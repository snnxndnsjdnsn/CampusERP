import { PageHeader, StatTile } from '@/components/page-header';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { rpcSafe } from '@/lib/api';
import { formatDate, formatNumber, formatPercent } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

type MyCourseResult = {
  course_code: string;
  course_title: string;
  credits: number | null;
  internal_marks: number | null;
  external_marks: number | null;
  total_marks: number | null;
  grade_letter: string | null;
  grade_point: number | null;
  credits_earned: number | null;
  result_status: string | null;
};

type MyTermResult = {
  term_registration_id: number;
  term_name: string;
  semester_name: string;
  programme_name: string;
  credits_registered: number | null;
  credits_earned: number | null;
  sgpa: number | null;
  cgpa: number | null;
  result_status: string | null;
  published_at: string | null;
  courses: MyCourseResult[];
};

export default async function MyResultsPage() {
  const { supabase } = await requireContext();
  const { data, error } = await rpcSafe<MyTermResult[]>(supabase, 'my_results');
  const terms = Array.isArray(data) ? data : [];

  const totalCredits = terms.reduce((sum, t) => sum + Number(t.credits_earned ?? 0), 0);
  const latestCgpa = terms.length > 0 ? (terms[0]?.cgpa ?? null) : null;

  return (
    <>
      <PageHeader
        title="My results"
        description="Your published term results, course by course."
      />

      {error && (
        <div className="mb-6">
          <ErrorPanel message={`Your results could not be read: ${error}`} />
        </div>
      )}

      {terms.length === 0 && !error ? (
        <EmptyState
          title="No published results yet"
          description="Results appear here once your department publishes them."
        />
      ) : (
        <>
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <StatTile label="Terms published" value={formatNumber(terms.length)} />
            <StatTile label="Credits earned" value={formatNumber(totalCredits)} />
            <StatTile label="Latest CGPA" value={formatNumber(latestCgpa)} />
            <StatTile
              label="Latest SGPA"
              value={formatNumber(terms[0]?.sgpa ?? null)}
              tone={terms[0]?.result_status === 'PASS' ? 'success' : 'default'}
            />
          </div>

          <div className="mt-6 space-y-6">
            {terms.map((term) => {
              const registered = Number(term.credits_registered ?? 0);
              const earned = Number(term.credits_earned ?? 0);
              const completion = registered > 0 ? (100 * earned) / registered : null;
              const courses = term.courses ?? [];
              return (
                <Card key={term.term_registration_id}>
                  <CardHeader>
                    <CardTitle>{term.term_name}</CardTitle>
                    <CardDescription>
                      {term.programme_name} · {term.semester_name} · published {formatDate(term.published_at)}
                    </CardDescription>
                  </CardHeader>
                  <CardContent className="space-y-4">
                    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
                      <StatTile label="SGPA" value={formatNumber(term.sgpa)} />
                      <StatTile label="CGPA" value={formatNumber(term.cgpa)} />
                      <StatTile label="Credits earned" value={`${formatNumber(earned)} / ${formatNumber(registered)}`} />
                      <StatTile label="Credits completed" value={formatPercent(completion)} />
                    </div>

                    <div className="flex flex-wrap items-center gap-2">
                      <span className="text-sm text-muted-foreground">Result</span>
                      {term.result_status ? (
                        <Badge variant={statusVariant(term.result_status)}>{term.result_status}</Badge>
                      ) : (
                        <span className="text-sm text-muted-foreground">Not recorded</span>
                      )}
                    </div>

                    {courses.length === 0 ? (
                      <EmptyState title="No course results" description="No course has been graded for this term yet." />
                    ) : (
                      <Table>
                        <TableHeader>
                          <TableRow>
                            <TableHead>Course</TableHead>
                            <TableHead className="text-right">Credits</TableHead>
                            <TableHead className="text-right">Internal</TableHead>
                            <TableHead className="text-right">External</TableHead>
                            <TableHead className="text-right">Total</TableHead>
                            <TableHead>Grade</TableHead>
                            <TableHead className="text-right">Points</TableHead>
                            <TableHead className="text-right">Credits earned</TableHead>
                            <TableHead>Status</TableHead>
                          </TableRow>
                        </TableHeader>
                        <TableBody>
                          {courses.map((c) => (
                            <TableRow key={`${term.term_registration_id}-${c.course_code}`}>
                              <TableCell>
                                <div className="font-medium">{c.course_code}</div>
                                <div className="text-xs text-muted-foreground">{c.course_title}</div>
                              </TableCell>
                              <TableCell className="text-right tabular-nums">{formatNumber(c.credits)}</TableCell>
                              <TableCell className="text-right tabular-nums">{formatNumber(c.internal_marks)}</TableCell>
                              <TableCell className="text-right tabular-nums">{formatNumber(c.external_marks)}</TableCell>
                              <TableCell className="text-right tabular-nums">{formatNumber(c.total_marks)}</TableCell>
                              <TableCell className="font-medium">{c.grade_letter ?? '—'}</TableCell>
                              <TableCell className="text-right tabular-nums">{formatNumber(c.grade_point)}</TableCell>
                              <TableCell className="text-right tabular-nums">{formatNumber(c.credits_earned)}</TableCell>
                              <TableCell>
                                {c.result_status ? (
                                  <Badge variant={statusVariant(c.result_status)}>{c.result_status}</Badge>
                                ) : (
                                  <span className="text-xs text-muted-foreground">—</span>
                                )}
                              </TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    )}
                  </CardContent>
                </Card>
              );
            })}
          </div>
        </>
      )}
    </>
  );
}
