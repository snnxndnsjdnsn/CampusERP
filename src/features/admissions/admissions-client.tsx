'use client';

import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input, Label, Select, Textarea } from '@/components/ui/input';
import { clientRpc } from '@/features/shared/client-rpc';
import { NEXT_STATUS, type AdmissionRow, type LookupOption } from './types';

/**
 * Interactive parts of the admissions screen.
 *
 * Every write goes to a `public.*` function and is followed by
 * `router.refresh()` so the server component re-reads the (now changed) rows.
 * The browser never decides whether an action is allowed â€” the database does.
 */

function today(): string {
  return new Date().toISOString().slice(0, 10);
}

function Field({
  label,
  htmlFor,
  children,
}: {
  label: string;
  htmlFor: string;
  children: React.ReactNode;
}) {
  return (
    <div className="space-y-1.5">
      <Label htmlFor={htmlFor}>{label}</Label>
      {children}
    </div>
  );
}

function ErrorText({ message }: { message: string | null }) {
  if (!message) return null;
  return (
    <p className="rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800" role="alert">
      {message}
    </p>
  );
}

/* ------------------------------------------------------------------ */
/* New application                                                     */
/* ------------------------------------------------------------------ */

export function NewApplicationForm({
  programmes,
  academicYears,
  categories,
  genders,
  countries,
  socialCategories,
}: {
  programmes: LookupOption[];
  academicYears: LookupOption[];
  categories: LookupOption[];
  genders: LookupOption[];
  countries: LookupOption[];
  socialCategories: LookupOption[];
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [open, setOpen] = useState(false);

  async function onSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    const form = new FormData(event.currentTarget);
    const str = (key: string) => String(form.get(key) ?? '').trim();

    const applicant: Record<string, unknown> = { first_name: str('first_name') };
    if (str('middle_name')) applicant.middle_name = str('middle_name');
    if (str('last_name')) applicant.last_name = str('last_name');
    if (str('date_of_birth')) applicant.date_of_birth = str('date_of_birth');
    if (str('gender_id')) applicant.gender_id = Number(str('gender_id'));
    if (str('primary_email')) applicant.primary_email = str('primary_email');
    if (str('primary_phone')) applicant.primary_phone = str('primary_phone');
    if (str('nationality_country_id')) applicant.nationality_country_id = Number(str('nationality_country_id'));
    if (str('social_category_id')) applicant.social_category_id = Number(str('social_category_id'));

    const application: Record<string, unknown> = {
      application_number: str('application_number'),
      programme_id: Number(str('programme_id')),
      academic_year_id: Number(str('academic_year_id')),
      application_date: str('application_date'),
    };
    if (str('admission_category_id')) application.admission_category_id = Number(str('admission_category_id'));
    if (str('remarks')) application.remarks = str('remarks');

    try {
      await clientRpc<number>('admission_apply', { p_applicant: applicant, p_application: application });
      setOpen(false);
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The application could not be saved.');
    } finally {
      setBusy(false);
    }
  }

  if (!open) {
    return (
      <Button onClick={() => setOpen(true)} disabled={programmes.length === 0 || academicYears.length === 0}>
        New application
      </Button>
    );
  }

  return (
    <form onSubmit={onSubmit} className="space-y-4" noValidate>
      <div className="grid gap-4 md:grid-cols-2">
        <Field label="Application number" htmlFor="application_number">
          <Input id="application_number" name="application_number" required maxLength={30} placeholder="ADM-2026-0001" />
        </Field>
        <Field label="Application date" htmlFor="application_date">
          <Input id="application_date" name="application_date" type="date" required defaultValue={today()} />
        </Field>
        <Field label="Programme" htmlFor="programme_id">
          <Select id="programme_id" name="programme_id" required defaultValue="">
            <option value="">Select a programme</option>
            {programmes.map((p) => (
              <option key={p.id} value={p.id}>
                {p.label}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Academic year" htmlFor="academic_year_id">
          <Select id="academic_year_id" name="academic_year_id" required defaultValue="">
            <option value="">Select an academic year</option>
            {academicYears.map((y) => (
              <option key={y.id} value={y.id}>
                {y.label}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Admission category" htmlFor="admission_category_id">
          <Select id="admission_category_id" name="admission_category_id" defaultValue="">
            <option value="">Not set</option>
            {categories.map((c) => (
              <option key={c.id} value={c.id}>
                {c.label}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="First name" htmlFor="first_name">
          <Input id="first_name" name="first_name" required maxLength={100} />
        </Field>
        <Field label="Middle name" htmlFor="middle_name">
          <Input id="middle_name" name="middle_name" maxLength={100} />
        </Field>
        <Field label="Last name" htmlFor="last_name">
          <Input id="last_name" name="last_name" maxLength={100} />
        </Field>
        <Field label="Date of birth" htmlFor="date_of_birth">
          <Input id="date_of_birth" name="date_of_birth" type="date" />
        </Field>
        <Field label="Gender" htmlFor="gender_id">
          <Select id="gender_id" name="gender_id" defaultValue="">
            <option value="">Not stated</option>
            {genders.map((g) => (
              <option key={g.id} value={g.id}>
                {g.label}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Email" htmlFor="primary_email">
          <Input id="primary_email" name="primary_email" type="email" maxLength={254} />
        </Field>
        <Field label="Phone" htmlFor="primary_phone">
          <Input id="primary_phone" name="primary_phone" maxLength={25} />
        </Field>
        <Field label="Nationality" htmlFor="nationality_country_id">
          <Select id="nationality_country_id" name="nationality_country_id" defaultValue="">
            <option value="">Not stated</option>
            {countries.map((c) => (
              <option key={c.id} value={c.id}>
                {c.label}
              </option>
            ))}
          </Select>
        </Field>
        <Field label="Social category" htmlFor="social_category_id">
          <Select id="social_category_id" name="social_category_id" defaultValue="">
            <option value="">Not stated</option>
            {socialCategories.map((c) => (
              <option key={c.id} value={c.id}>
                {c.label}
              </option>
            ))}
          </Select>
        </Field>
      </div>
      <Field label="Remarks" htmlFor="remarks">
        <Textarea id="remarks" name="remarks" rows={2} maxLength={500} />
      </Field>
      <ErrorText message={error} />
      <div className="flex gap-2">
        <Button type="submit" disabled={busy}>
          {busy ? 'Savingâ€¦' : 'Create application'}
        </Button>
        <Button type="button" variant="outline" onClick={() => setOpen(false)} disabled={busy}>
          Cancel
        </Button>
      </div>
    </form>
  );
}

/* ------------------------------------------------------------------ */
/* Status transition                                                   */
/* ------------------------------------------------------------------ */

export function ApplicationStatusAction({ row }: { row: AdmissionRow }) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState('');
  const [remarks, setRemarks] = useState('');
  const options = NEXT_STATUS[row.application.application_status] ?? [];

  if (options.length === 0) {
    return <span className="text-xs text-muted-foreground">No further move</span>;
  }

  async function submit() {
    if (!status) return;
    setBusy(true);
    setError(null);
    try {
      await clientRpc<null>('admission_set_status', {
        p_application_id: row.application.application_id,
        p_new_status: status,
        p_remarks: remarks.trim() || null,
      });
      setStatus('');
      setRemarks('');
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The status could not be changed.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap items-center gap-2">
        <Select value={status} onChange={(e) => setStatus(e.target.value)} className="h-8 w-40 text-xs" aria-label="New status">
          <option value="">Move toâ€¦</option>
          {options.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </Select>
        <Input
          value={remarks}
          onChange={(e) => setRemarks(e.target.value)}
          placeholder="Remarks (optional)"
          className="h-8 w-44 text-xs"
          maxLength={500}
          aria-label="Status remarks"
        />
        <Button size="sm" variant="outline" onClick={submit} disabled={busy || !status}>
          {busy ? 'Savingâ€¦' : 'Set status'}
        </Button>
      </div>
      <ErrorText message={error} />
    </div>
  );
}

/* ------------------------------------------------------------------ */
/* Admit                                                                */
/* ------------------------------------------------------------------ */

export function ApplicationAdmit({
  row,
  schemes,
  academicYears,
  semesters,
}: {
  row: AdmissionRow;
  schemes: LookupOption[];
  academicYears: LookupOption[];
  semesters: LookupOption[];
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [open, setOpen] = useState(false);
  const [studentNumber, setStudentNumber] = useState('');
  const [schemeId, setSchemeId] = useState('');
  const [yearId, setYearId] = useState(String(row.application.academic_year_id ?? ''));
  const [semesterId, setSemesterId] = useState('');

  if (row.application.application_status !== 'SELECTED') {
    return <span className="text-xs text-muted-foreground">Select the application first</span>;
  }

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await clientRpc<number>('admission_admit', {
        p_application_id: row.application.application_id,
        p_student: { student_number: studentNumber.trim() },
        p_enrolment: {
          curriculum_scheme_id: Number(schemeId),
          admission_academic_year_id: Number(yearId),
          admission_semester_id: Number(semesterId),
          admission_date: today(),
        },
      });
      setOpen(false);
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The applicant could not be admitted.');
    } finally {
      setBusy(false);
    }
  }

  if (!open) {
    return (
      <Button size="sm" onClick={() => setOpen(true)}>
        Admit
      </Button>
    );
  }

  return (
    <form onSubmit={submit} className="space-y-2" noValidate>
      <Input
        value={studentNumber}
        onChange={(e) => setStudentNumber(e.target.value)}
        placeholder="Student number"
        required
        maxLength={30}
        className="h-8 w-44 text-xs"
        aria-label="Student number"
      />
      {schemes.length > 0 ? (
        <Select value={schemeId} onChange={(e) => setSchemeId(e.target.value)} required className="h-8 w-44 text-xs" aria-label="Curriculum scheme">
          <option value="">Curriculum schemeâ€¦</option>
          {schemes
            .filter((s) => s.programmeId === undefined || s.programmeId === row.application.programme_id)
            .map((s) => (
              <option key={s.id} value={s.id}>
                {s.label}
              </option>
            ))}
        </Select>
      ) : (
        <Input
          type="number"
          value={schemeId}
          onChange={(e) => setSchemeId(e.target.value)}
          placeholder="Curriculum scheme id"
          required
          className="h-8 w-44 text-xs"
          aria-label="Curriculum scheme id"
        />
      )}
      <Select value={yearId} onChange={(e) => setYearId(e.target.value)} required className="h-8 w-40 text-xs" aria-label="Admission academic year">
        <option value="">Academic yearâ€¦</option>
        {academicYears.map((y) => (
          <option key={y.id} value={y.id}>
            {y.label}
          </option>
        ))}
      </Select>
      <Select value={semesterId} onChange={(e) => setSemesterId(e.target.value)} required className="h-8 w-36 text-xs" aria-label="Admission semester">
        <option value="">Semesterâ€¦</option>
        {semesters.map((s) => (
          <option key={s.id} value={s.id}>
            {s.label}
          </option>
        ))}
      </Select>
      <ErrorText message={error} />
      <div className="flex gap-2">
        <Button size="sm" type="submit" disabled={busy}>
          {busy ? 'Admittingâ€¦' : 'Confirm admission'}
        </Button>
        <Button size="sm" type="button" variant="outline" onClick={() => setOpen(false)} disabled={busy}>
          Cancel
        </Button>
      </div>
    </form>
  );
}

/* ------------------------------------------------------------------ */
/* Edit applicant / application                                        */
/* ------------------------------------------------------------------ */

export function ApplicationEdit({
  row,
  categories,
  genders,
  countries,
  socialCategories,
}: {
  row: AdmissionRow;
  categories: LookupOption[];
  genders: LookupOption[];
  countries: LookupOption[];
  socialCategories: LookupOption[];
}) {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [open, setOpen] = useState(false);
  const applicant = row.applicant;

  async function saveApplicant(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!applicant) return;
    setBusy(true);
    setError(null);
    const form = new FormData(event.currentTarget);
    const str = (key: string) => String(form.get(key) ?? '').trim();
    const patch: Record<string, unknown> = {
      first_name: str('first_name'),
      middle_name: str('middle_name'),
      last_name: str('last_name'),
      primary_email: str('primary_email'),
      primary_phone: str('primary_phone'),
      date_of_birth: str('date_of_birth'),
      gender_id: str('gender_id') ? Number(str('gender_id')) : '',
      nationality_country_id: str('nationality_country_id') ? Number(str('nationality_country_id')) : '',
      social_category_id: str('social_category_id') ? Number(str('social_category_id')) : '',
    };
    try {
      await clientRpc<null>('admission_update_applicant', {
        p_applicant_id: applicant.admission_applicant_id,
        p: patch,
      });
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The applicant could not be updated.');
    } finally {
      setBusy(false);
    }
  }

  async function saveApplication(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    const form = new FormData(event.currentTarget);
    const str = (key: string) => String(form.get(key) ?? '').trim();
    try {
      await clientRpc<null>('admission_update_application', {
        p_application_id: row.application.application_id,
        p: {
          remarks: str('remarks'),
          admission_category_id: str('admission_category_id') ? Number(str('admission_category_id')) : '',
        },
      });
      setOpen(false);
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The application could not be updated.');
    } finally {
      setBusy(false);
    }
  }

  if (!open) {
    return (
      <Button size="sm" variant="outline" onClick={() => setOpen(true)}>
        Edit
      </Button>
    );
  }

  return (
    <div className="space-y-3">
      {applicant && (
        <form onSubmit={saveApplicant} className="space-y-2" noValidate>
          <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Applicant</p>
          <div className="flex flex-wrap gap-2">
            <Input name="first_name" defaultValue={applicant.first_name} required maxLength={100} className="h-8 w-36 text-xs" aria-label="First name" />
            <Input name="middle_name" defaultValue={applicant.middle_name ?? ''} maxLength={100} className="h-8 w-36 text-xs" aria-label="Middle name" />
            <Input name="last_name" defaultValue={applicant.last_name ?? ''} maxLength={100} className="h-8 w-36 text-xs" aria-label="Last name" />
            <Input name="primary_email" type="email" defaultValue={applicant.primary_email ?? ''} maxLength={254} className="h-8 w-48 text-xs" aria-label="Email" />
            <Input name="primary_phone" defaultValue={applicant.primary_phone ?? ''} maxLength={25} className="h-8 w-36 text-xs" aria-label="Phone" />
            <Input name="date_of_birth" type="date" defaultValue={applicant.date_of_birth ?? ''} className="h-8 w-36 text-xs" aria-label="Date of birth" />
            <Select name="gender_id" defaultValue={applicant.gender_id ?? ''} className="h-8 w-32 text-xs" aria-label="Gender">
              <option value="">Genderâ€¦</option>
              {genders.map((g) => (
                <option key={g.id} value={g.id}>
                  {g.label}
                </option>
              ))}
            </Select>
            <Select name="nationality_country_id" defaultValue={applicant.nationality_country_id ?? ''} className="h-8 w-36 text-xs" aria-label="Nationality">
              <option value="">Nationalityâ€¦</option>
              {countries.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.label}
                </option>
              ))}
            </Select>
            <Select name="social_category_id" defaultValue={applicant.social_category_id ?? ''} className="h-8 w-36 text-xs" aria-label="Social category">
              <option value="">Categoryâ€¦</option>
              {socialCategories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.label}
                </option>
              ))}
            </Select>
            <Button size="sm" type="submit" disabled={busy}>
              {busy ? 'Savingâ€¦' : 'Save applicant'}
            </Button>
          </div>
        </form>
      )}

      <form onSubmit={saveApplication} className="space-y-2" noValidate>
        <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Application</p>
        <div className="flex flex-wrap gap-2">
          <Select name="admission_category_id" defaultValue={row.application.admission_category_id ?? ''} className="h-8 w-40 text-xs" aria-label="Admission category">
            <option value="">Categoryâ€¦</option>
            {categories.map((c) => (
              <option key={c.id} value={c.id}>
                {c.label}
              </option>
            ))}
          </Select>
          <Input name="remarks" defaultValue={row.application.remarks ?? ''} maxLength={500} placeholder="Remarks" className="h-8 w-64 text-xs" aria-label="Application remarks" />
          <Button size="sm" type="submit" variant="outline" disabled={busy}>
            {busy ? 'Savingâ€¦' : 'Save application'}
          </Button>
          <Button size="sm" type="button" variant="ghost" onClick={() => setOpen(false)} disabled={busy}>
            Close
          </Button>
        </div>
      </form>
      <ErrorText message={error} />
    </div>
  );
}
