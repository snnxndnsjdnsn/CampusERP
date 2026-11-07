import { PageHeader, StatTile } from '@/components/page-header';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { safeRpcRows, safeSelect } from '@/features/academic/data';
import type { AssessmentOffering, AssessmentOfferingInfo } from '@/features/assessment/types';
import { CourseResultForm, ResultOfferingPicker, TermResultActions } from '@/features/results/results-client';
import type { GradeRuleRow, GradeScaleRow, ResultCourseSheetRow, ResultTermSheetRow } from '@/features/results/types';
import { formatDate, formatNumber, formatPercent } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

function idParam(value: string | string[] | undefined): number | null {
  const raw = Array.isArray(value) ? value[0] : value;
  if (!raw || !/^\d+$/.test(raw)) return null;
  const n = Number(raw);
  return Number.isSafeInteger(n) ? n : null;
}

export default async function ResultsGradesPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { supabase } = await requireContext();
  const sp = await searchParams;
  const offeringId = idParam(sp.offering);

  const offerings = await safeRpcRows<AssessmentOffering>(supabase, 'assessment_offerings', { p_limit: 200, p_offset: 0 });
  const programmeTermOfferingId = Number(
    offerings.data.find((o) => o.course_offering_id === offeringId)?.programme_term_offering_id ?? 0,
  );

  const [courseSheet, info, termSheet, scales, rules] = await Promise.all([
    offeringId === null
      ? Promise.resolve({ data: [] as ResultCourseSheetRow[], error: null })
      : safeRpcRows<ResultCourseSheetRow>(supabase, 'result_course_sheet', { p_course_offering_id: offeringId }),
    offeringId === null
      ? Promise.resolve({ data: [] as AssessmentOfferingInfo[], error: null })
      : safeRpcRows<AssessmentOfferingInfo>(supabase, 'assessment_offering_info', {
          p_course_offering_id: offeringId,
        }),
    offeringId === null
      ? Promise.resolve({ data: [] as ResultTermSheetRow[], error: null })
      : safeRpcRows<ResultTermSheetRow>(supabase, 'result_term_sheet', {
          p_offering_id: programmeTermOfferingId,
        }),
    safeSelect<GradeScaleRow>(supabase, 'grade_scale', '*', { limit: 100 }),
    safeSelect<GradeRuleRow>(supabase, 'grade_rule', '*', { limit: 500 }),
  ]);

  const offering = info.data[0] ?? null;
  const selectedOffering = offerings.data.find((o) => o.course_offering_id === offeringId) ?? null;
  const activeScale = scales.data.find((s) => s.is_active) ?? scales.data[0] ?? null;
  const activeRules = activeScale
    ? rules.data
        .filter((r) => r.grade_scale_id === activeScale.grade_scale_id)
        .sort((a, b) => Number(b.minimum_percentage) - Number(a.minimum_percentage))
    : [];

  const passed = courseSheet.data.filter((r) => r.result_status === 'PASS').length;
  const graded = courseSheet.data.filter((r) => r.grade_letter !== null).length;

  return (
    <>
      <PageHeader
        title="Results and grade book"
        description="Record course results, compute term results and publish them to students."
      />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatTile label="Course offerings" value={formatNumber(offerings.data.length)} />
        <StatTile label="Students on the sheet" value={formatNumber(courseSheet.data.length)} />
        <StatTile label="Graded" value={formatNumber(graded)} />
        <StatTile label="Passed" value={formatNumber(passed)} tone="success" />
      </div>

      <Card className="mt-6">
        <CardHeader>
          <CardTitle>Course offering</CardTitle>
          <CardDescription>Pick the offering whose result sheet you want to work with.</CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <ResultOfferingPicker offerings={offerings.data} selectedId={offeringId} />
          {selectedOffering && (
            <div className="flex flex-wrap items-center gap-3 text-sm">
              <span className="font-medium">
                {selectedOffering.course_code} — {selectedOffering.course_title}
              </span>
              <span className="text-muted-foreground">
                {selectedOffering.term_name} · {selectedOffering.programme_name} · {selectedOffering.semester_name}
              </span>
              {offering && (
                <span className="text-muted-foreground">
                  Internal {formatNumber(offering.internal_max_marks)} · External {formatNumber(offering.external_max_marks)} ·
                  Pass {formatNumber(offering.passing_marks)}
                </span>
              )}
            </div>
          )}
          {offerings.error && <ErrorPanel message={`The offerings could not be read: ${offerings.error}`} />}
        </CardContent>
      </Card>

      <Card className="mt-6">
        <CardHeader>
          <CardTitle>Grade book</CardTitle>
          <CardDescription>
            {activeScale
              ? `${activeScale.scale_name} · effective from ${formatDate(activeScale.effective_from)}`
              : 'No grade scale is defined.'}
          </CardDescription>
        </CardHeader>
        <CardContent>
          {scales.error && <ErrorPanel message={`The grade scales could not be read: ${scales.error}`} />}
          {activeRules.length === 0 ? (
            <EmptyState title="No grade rules" description="A grade scale with its bands is needed before results can be graded." />
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Grade</TableHead>
                  <TableHead className="text-right">Grade point</TableHead>
                  <TableHead className="text-right">From</TableHead>
                  <TableHead className="text-right">To</TableHead>
                  <TableHead>Outcome</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {activeRules.map((r) => (
                  <TableRow key={r.grade_rule_id}>
                    <TableCell className="font-medium">{r.grade_letter}</TableCell>
                    <TableCell className="text-right tabular-nums">{formatNumber(r.grade_point)}</TableCell>
                    <TableCell className="text-right tabular-nums">{formatPercent(r.minimum_percentage)}</TableCell>
                    <TableCell className="text-right tabular-nums">{formatPercent(r.maximum_percentage)}</TableCell>
                    <TableCell>
                      <Badge variant={statusVariant(r.result_status)}>{r.result_status}</Badge>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {offeringId !== null && (
        <>
          <Card className="mt-6">
            <CardHeader>
              <CardTitle>Course result sheet</CardTitle>
              <CardDescription>Record the internal and external marks of each student.</CardDescription>
            </CardHeader>
            <CardContent>
              {courseSheet.error && <ErrorPanel message={`The result sheet could not be read: ${courseSheet.error}`} />}
              {courseSheet.data.length === 0 && !courseSheet.error ? (
                <EmptyState title="No students registered" description="Nobody is registered for this course offering." />
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Student</TableHead>
                      <TableHead>Student number</TableHead>
                      <TableHead className="text-right">Internal</TableHead>
                      <TableHead className="text-right">External</TableHead>
                      <TableHead className="text-right">Total</TableHead>
                      <TableHead>Grade</TableHead>
                      <TableHead className="text-right">Points</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead className="text-right">Record</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {courseSheet.data.map((r) => (
                      <TableRow key={r.course_registration_id}>
                        <TableCell className="font-medium">{r.display_name}</TableCell>
                        <TableCell>{r.student_number}</TableCell>
                        <TableCell className="text-right tabular-nums">{formatNumber(r.internal_marks)}</TableCell>
                        <TableCell className="text-right tabular-nums">{formatNumber(r.external_marks)}</TableCell>
                        <TableCell className="text-right tabular-nums">{formatNumber(r.total_marks)}</TableCell>
                        <TableCell>{r.grade_letter ?? '—'}</TableCell>
                        <TableCell className="text-right tabular-nums">{formatNumber(r.grade_point)}</TableCell>
                        <TableCell>
                          {r.result_status ? (
                            <Badge variant={statusVariant(r.result_status)}>{r.result_status}</Badge>
                          ) : (
                            <span className="text-xs text-muted-foreground">Not recorded</span>
                          )}
                        </TableCell>
                        <TableCell className="text-right">
                          <CourseResultForm
                            row={r}
                            internalMaxMarks={offering?.internal_max_marks ?? null}
                            externalMaxMarks={offering?.external_max_marks ?? null}
                          />
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>

          <Card className="mt-6">
            <CardHeader>
              <CardTitle>Term result sheet</CardTitle>
              <CardDescription>Compute the term result, then publish it to the student.</CardDescription>
            </CardHeader>
            <CardContent>
              {termSheet.error && <ErrorPanel message={`The term sheet could not be read: ${termSheet.error}`} />}
              {termSheet.data.length === 0 && !termSheet.error ? (
                <EmptyState title="No term registrations" description="Nobody is registered for this offering." />
              ) : (
                <Table>
                  <TableHeader>
                    <TableRow>
                      <TableHead>Student</TableHead>
                      <TableHead>Student number</TableHead>
                      <TableHead className="text-right">Credits registered</TableHead>
                      <TableHead className="text-right">Credits earned</TableHead>
                      <TableHead className="text-right">SGPA</TableHead>
                      <TableHead className="text-right">CGPA</TableHead>
                      <TableHead>Status</TableHead>
                      <TableHead>Published</TableHead>
                      <TableHead className="text-right">Actions</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {termSheet.data.map((r) => (
                      <TableRow key={r.term_registration_id}>
                        <TableCell className="font-medium">{r.display_name}</TableCell>
                        <TableCell>{r.student_number}</TableCell>
                        <TableCell className="text-right tabular-nums">{formatNumber(r.credits_registered)}</TableCell>
                        <TableCell className="text-right tabular-nums">{formatNumber(r.credits_earned)}</TableCell>
                        <TableCell className="text-right tabular-nums">{formatNumber(r.sgpa)}</TableCell>
                        <TableCell className="text-right tabular-nums">{formatNumber(r.cgpa)}</TableCell>
                        <TableCell>
                          {r.result_status ? (
                            <Badge variant={statusVariant(r.result_status)}>{r.result_status}</Badge>
                          ) : (
                            <span className="text-xs text-muted-foreground">Not computed</span>
                          )}
                        </TableCell>
                        <TableCell>{r.published_at ? formatDate(r.published_at) : '—'}</TableCell>
                        <TableCell className="text-right">
                          <TermResultActions
                            termRegistrationId={r.term_registration_id}
                            published={r.published_at !== null}
                          />
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              )}
            </CardContent>
          </Card>
        </>
      )}
    </>
  );
}
