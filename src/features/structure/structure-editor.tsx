'use client';

import { useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState } from '@/components/ui/empty-state';
import { Input, Label, Select } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Alert, Notice } from '@/features/shared/feedback';
import { RecordForm } from '@/features/shared/record-form';
import { RowActions } from '@/features/shared/row-actions';
import { errorMessage } from '@/features/shared/reads';
import { createClient } from '@/lib/supabase/client';

export type InstitutionRow = {
  institution_id: number;
  university_id: number;
  institution_code: string;
  institution_name: string;
  legal_name: string | null;
  website_url: string | null;
  email: string | null;
  phone: string | null;
  is_active: boolean;
};

export type UniversityOption = { id: number; label: string };

const INSTITUTION_FIELDS = [
  { name: 'university_id', label: 'University', type: 'integer' },
  { name: 'institution_code', label: 'Institution code', type: 'text' },
  { name: 'institution_name', label: 'Institution name', type: 'text' },
  { name: 'legal_name', label: 'Legal name', type: 'text' },
  { name: 'website_url', label: 'Website', type: 'text' },
  { name: 'email', label: 'Email', type: 'text' },
  { name: 'phone', label: 'Phone', type: 'text' },
  { name: 'is_active', label: 'Active', type: 'boolean' },
] as const;

/**
 * Module 2 · Institution structure.
 *
 * The institution register itself is written through `institution_create` /
 * `institution_update`. The child records that hang off a student, an employee
 * or a staff research activity are edited through the generic Manage panel on
 * the screen that owns them.
 */
export function StructureEditor({
  institutions,
  universities,
}: {
  institutions: InstitutionRow[];
  universities: UniversityOption[];
}) {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);

  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  // ---------------------------------------------------------------- institution
  const [instForm, setInstForm] = useState<{
    id: number | null;
    values: Record<string, string>;
    original: Record<string, string> | null;
  } | null>(null);
  const [savingInstitution, setSavingInstitution] = useState(false);

  function startEditInstitution(row: InstitutionRow) {
    setError(null);
    const values: Record<string, string> = {
      university_id: String(row.university_id ?? ''),
      institution_code: row.institution_code ?? '',
      institution_name: row.institution_name ?? '',
      legal_name: row.legal_name ?? '',
      website_url: row.website_url ?? '',
      email: row.email ?? '',
      phone: row.phone ?? '',
      is_active: row.is_active ? 'true' : 'false',
    };
    setInstForm({ id: row.institution_id, values, original: values });
  }

  /**
   * The register maintains what the builder creates: an institution's own
   * details and whether it is active. Creation lives in the builder above so
   * that saving one offers the campuses underneath it straight away.
   */
  async function saveInstitution() {
    if (!instForm || instForm.id === null) return;
    setSavingInstitution(true);
    setError(null);
    try {
      const payload: Record<string, unknown> = {};
      for (const field of INSTITUTION_FIELDS) {
        // An institution belongs to its university for good.
        if (field.name === 'university_id') continue;
        const raw = (instForm.values[field.name] ?? '').trim();
        const before = instForm.original?.[field.name] ?? '';
        if (raw === before) continue;
        payload[field.name] = raw;
      }

      const { error: updateError } = await supabase.rpc('institution_update', {
        p_id: instForm.id,
        p: payload,
      });
      if (updateError) throw new Error(updateError.message);
      setNotice('Institution updated.');
      setInstForm(null);
      router.refresh();
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setSavingInstitution(false);
    }
  }

  const universityLabel = (id: number) => universities.find((u) => u.id === id)?.label ?? `#${id}`;

  return (
    <div className="space-y-4">
      {error ? <Alert message={error} /> : null}
      {notice ? <Notice>{notice}</Notice> : null}

      <Card>
        <CardHeader className="flex-row items-center justify-between gap-3 space-y-0">
          <div>
            <CardTitle>Institution register</CardTitle>
            <CardDescription>
              {institutions.length} institution{institutions.length === 1 ? '' : 's'} visible to you. Review
              them here; create one in the structure builder above.
            </CardDescription>
          </div>
        </CardHeader>
        <CardContent className="space-y-4">
          {/* Above the table: a form below it is a long scroll from the button. */}
          {instForm ? (
            <RecordForm
              title="Edit institution"
              isNew={false}
              saving={savingInstitution}
              onCancel={() => setInstForm(null)}
              onSave={() => void saveInstitution()}
            >
              <div className="grid gap-3 sm:grid-cols-2">
                {INSTITUTION_FIELDS.map((field) => {
                  const id = `inst-${field.name}`;
                  const value = instForm.values[field.name] ?? '';
                  const readOnly = instForm.id !== null && field.name === 'university_id';
                  return (
                    <div key={field.name}>
                      <Label htmlFor={id} className="mb-1 block">
                        {field.label}
                        {field.name === 'university_id' || field.name === 'institution_code' || field.name === 'institution_name' ? (
                          <span className="text-destructive"> *</span>
                        ) : null}
                      </Label>
                      {field.name === 'university_id' ? (
                        <Select
                          id={id}
                          value={value}
                          disabled={readOnly}
                          onChange={(e) =>
                            setInstForm((prev) =>
                              prev ? { ...prev, values: { ...prev.values, [field.name]: e.target.value } } : prev,
                            )
                          }
                        >
                          <option value="">Select a university</option>
                          {universities.map((u) => (
                            <option key={u.id} value={String(u.id)}>
                              {u.label}
                            </option>
                          ))}
                        </Select>
                      ) : field.name === 'is_active' ? (
                        <Select
                          id={id}
                          value={value}
                          onChange={(e) =>
                            setInstForm((prev) =>
                              prev ? { ...prev, values: { ...prev.values, [field.name]: e.target.value } } : prev,
                            )
                          }
                        >
                          <option value="true">Yes</option>
                          <option value="false">No</option>
                        </Select>
                      ) : (
                        <Input
                          id={id}
                          type={
                            field.name === 'email'
                              ? 'email'
                              : field.name === 'website_url'
                                ? 'url'
                                : field.name === 'phone'
                                  ? 'tel'
                                  : 'text'
                          }
                          value={value}
                          disabled={readOnly}
                          onChange={(e) =>
                            setInstForm((prev) =>
                              prev ? { ...prev, values: { ...prev.values, [field.name]: e.target.value } } : prev,
                            )
                          }
                        />
                      )}
                    </div>
                  );
                })}
              </div>
            </RecordForm>
          ) : null}

          {institutions.length === 0 ? (
            <EmptyState
              title="No institutions visible to you"
              description="Institution records are scoped by the INSTITUTION module. Use “New institution” to register one."
            />
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Code</TableHead>
                  <TableHead>Institution</TableHead>
                  <TableHead>University</TableHead>
                  <TableHead>Contact</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead className="text-right">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {institutions.map((row) => (
                  <TableRow key={row.institution_id}>
                    <TableCell className="font-medium">{row.institution_code}</TableCell>
                    <TableCell>
                      <div>{row.institution_name}</div>
                      {row.legal_name ? <div className="text-xs text-muted-foreground">{row.legal_name}</div> : null}
                    </TableCell>
                    <TableCell>{universityLabel(row.university_id)}</TableCell>
                    <TableCell>
                      <div>{row.email ?? '—'}</div>
                      <div className="text-xs text-muted-foreground">{row.phone ?? '—'}</div>
                    </TableCell>
                    <TableCell>
                      <Badge variant={row.is_active ? statusVariant('ACTIVE') : statusVariant('INACTIVE')}>
                        {row.is_active ? 'ACTIVE' : 'INACTIVE'}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-right">
                      <RowActions onEdit={() => startEditInstitution(row)} />
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}

        </CardContent>
      </Card>
    </div>
  );
}
