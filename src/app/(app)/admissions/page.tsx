import { PageHeader, StatTile } from '@/components/page-header';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { safeSelect } from '@/features/academic/data';
import {
  ApplicationAdmit,
  ApplicationEdit,
  ApplicationStatusAction,
  NewApplicationForm,
} from '@/features/admissions/admissions-client';
import type { AdmissionApplicant, AdmissionApplication, AdmissionRow, LookupOption } from '@/features/admissions/types';
import { formatDate, formatNumber } from '@/lib/format';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

type ProgrammeRow = { programme_id: number; programme_name: string };
type YearRow = { academic_year_id: number; year_code: string };
type CategoryRow = { admission_category_id: number; category_name: string; is_active: boolean };
type GenderRow = { gender_id: number; gender_name: string };
type CountryRow = { country_id: number; country_name: string };
type SocialRow = { social_category_id: number; category_name: string };
type SchemeRow = { curriculum_scheme_id: number; scheme_name: string; programme_id: number };
type SemesterRow = { semester_id: number; semester_name: string };

function toOptions<T extends Record<string, unknown>>(rows: T[], idKey: string, labelKey: string): LookupOption[] {
  return rows.map((r) => ({ id: Number(r[idKey]), label: String(r[labelKey] ?? '') }));
}

export default async function AdmissionsPage() {
  const { supabase } = await requireContext();

  const [applications, applicants, programmes, years, categories, genders, countries, socialCategories, schemes, semesters] =
    await Promise.all([
      safeSelect<AdmissionApplication>(supabase, 'admission_application', '*', {
        order: { column: 'application_date', ascending: false },
        limit: 200,
      }),
      safeSelect<AdmissionApplicant>(supabase, 'admission_applicant', '*', { limit: 500 }),
      safeSelect<ProgrammeRow>(supabase, 'programme', 'programme_id, programme_name', { limit: 500 }),
      safeSelect<YearRow>(supabase, 'academic_year', 'academic_year_id, year_code', { limit: 200 }),
      safeSelect<CategoryRow>(supabase, 'admission_category', 'admission_category_id, category_name, is_active', {
        limit: 200,
      }),
      safeSelect<GenderRow>(supabase, 'gender', 'gender_id, gender_name', { limit: 100 }),
      safeSelect<CountryRow>(supabase, 'country', 'country_id, country_name', { limit: 300 }),
      safeSelect<SocialRow>(supabase, 'social_category', 'social_category_id, category_name', { limit: 100 }),
      safeSelect<SchemeRow>(supabase, 'curriculum_scheme', 'curriculum_scheme_id, scheme_name, programme_id', {
        limit: 500,
      }),
      safeSelect<SemesterRow>(supabase, 'semester', 'semester_id, semester_name', { limit: 100 }),
    ]);

  const applicantById = new Map<number, AdmissionApplicant>();
  for (const a of applicants.data) applicantById.set(Number(a.admission_applicant_id), a);
  const programmeById = new Map<number, string>();
  for (const p of programmes.data) programmeById.set(Number(p.programme_id), p.programme_name);

  const rows: AdmissionRow[] = applications.data.map((application) => {
    const applicant = applicantById.get(Number(application.admission_applicant_id)) ?? null;
    return {
      application,
      applicant,
      programme_name: programmeById.get(Number(application.programme_id)) ?? `Programme ${application.programme_id}`,
      applicant_name: applicant?.display_name ?? `Applicant ${application.admission_applicant_id}`,
    };
  });

  const countBy = (status: string) => rows.filter((r) => r.application.application_status === status).length;

  const programmeOptions = toOptions(programmes.data, 'programme_id', 'programme_name');
  const yearOptions = toOptions(years.data, 'academic_year_id', 'year_code');
  const categoryOptions = toOptions(
    categories.data.filter((c) => c.is_active !== false),
    'admission_category_id',
    'category_name',
  );
  const genderOptions = toOptions(genders.data, 'gender_id', 'gender_name');
  const countryOptions = toOptions(countries.data, 'country_id', 'country_name');
  const socialOptions = toOptions(socialCategories.data, 'social_category_id', 'category_name');
  const schemeOptions: LookupOption[] = schemes.data.map((s) => ({
    id: Number(s.curriculum_scheme_id),
    label: s.scheme_name,
    programmeId: Number(s.programme_id),
  }));
  const semesterOptions = toOptions(semesters.data, 'semester_id', 'semester_name');

  return (
    <>
      <PageHeader
        title="Admissions"
        description="Applications, eligibility decisions and admission. Every move is recorded by the database."
      />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatTile label="Applications" value={formatNumber(rows.length)} />
        <StatTile label="Under review" value={formatNumber(countBy('UNDER_REVIEW'))} />
        <StatTile label="Selected" value={formatNumber(countBy('SELECTED'))} />
        <StatTile label="Admitted" value={formatNumber(countBy('ADMITTED'))} tone="success" />
      </div>

      {applications.error && (
        <div className="mt-6">
          <ErrorPanel message={`Applications could not be read: ${applications.error}`} />
        </div>
      )}

      <Card className="mt-6">
        <CardHeader>
          <CardTitle>Register a new application</CardTitle>
          <CardDescription>Creates the applicant and the application in one step.</CardDescription>
        </CardHeader>
        <CardContent>
          <NewApplicationForm
            programmes={programmeOptions}
            academicYears={yearOptions}
            categories={categoryOptions}
            genders={genderOptions}
            countries={countryOptions}
            socialCategories={socialOptions}
          />
        </CardContent>
      </Card>

      <Card className="mt-6">
        <CardHeader>
          <CardTitle>Applications</CardTitle>
          <CardDescription>Move an application through the workflow, then admit it.</CardDescription>
        </CardHeader>
        <CardContent>
          {rows.length === 0 ? (
            <EmptyState
              title="No applications visible to you"
              description="Applications appear here once they are registered for a programme you can read."
            />
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Application</TableHead>
                  <TableHead>Applicant</TableHead>
                  <TableHead>Programme</TableHead>
                  <TableHead>Date</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Eligibility</TableHead>
                  <TableHead className="text-right">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rows.map((row) => (
                  <TableRow key={row.application.application_id}>
                    <TableCell className="font-medium">{row.application.application_number}</TableCell>
                    <TableCell>
                      <div>{row.applicant_name}</div>
                      {row.applicant?.primary_email && (
                        <div className="text-xs text-muted-foreground">{row.applicant.primary_email}</div>
                      )}
                    </TableCell>
                    <TableCell>{row.programme_name}</TableCell>
                    <TableCell>{formatDate(row.application.application_date)}</TableCell>
                    <TableCell>
                      <Badge variant={statusVariant(row.application.application_status)}>
                        {row.application.application_status}
                      </Badge>
                      {row.application.admitted_student_id !== null && (
                        <div className="mt-1 text-xs text-muted-foreground">
                          Student #{row.application.admitted_student_id}
                        </div>
                      )}
                    </TableCell>
                    <TableCell>
                      <Badge variant={statusVariant(row.application.eligibility_status)}>
                        {row.application.eligibility_status}
                      </Badge>
                    </TableCell>
                    <TableCell>
                      <div className="flex flex-col items-end gap-2">
                        <div className="flex flex-wrap justify-end gap-2">
                          <ApplicationStatusAction row={row} />
                          <ApplicationEdit
                            row={row}
                            categories={categoryOptions}
                            genders={genderOptions}
                            countries={countryOptions}
                            socialCategories={socialOptions}
                          />
                        </div>
                        <ApplicationAdmit
                          row={row}
                          schemes={schemeOptions}
                          academicYears={yearOptions}
                          semesters={semesterOptions}
                        />
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>
    </>
  );
}
