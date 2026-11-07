'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Badge, statusVariant } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Input, Label, Select } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import {
  DynamicForm,
  buildPayload,
  isBoolean,
  isDate,
  isNumeric,
  isTime,
  isTimestamp,
  valuesFromRow,
  type FormColumn,
  type FormValues,
  type LookupMap,
  type LookupOption,
} from '@/features/shared/dynamic-form';
import { errorMessage } from '@/features/shared/reads';
import { formatDate, formatDateTime, formatNumber } from '@/lib/format';
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

export type ParentOption = { id: number; label: string; sub: string | null };

export type ParentOptions = {
  student: ParentOption[];
  employee: ParentOption[];
  activity: ParentOption[];
};

export type SectionKind = 'student' | 'employee' | 'activity';

type Row = Record<string, unknown>;

type SectionSchema = {
  table: string;
  label: string;
  pk: string;
  columns: FormColumn[];
};

const KINDS: { value: SectionKind; label: string }[] = [
  { value: 'student', label: 'Student records' },
  { value: 'employee', label: 'Employee records' },
  { value: 'activity', label: 'Staff research activity' },
];

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

function renderCell(column: FormColumn, raw: unknown) {
  if (raw === null || raw === undefined || raw === '') return '—';
  if (isBoolean(column.type)) return raw === true || raw === 'true' ? 'Yes' : 'No';
  if (isNumeric(column.type)) return formatNumber(Number(raw));
  if (isDate(column.type)) return formatDate(String(raw));
  if (isTimestamp(column.type)) return formatDateTime(String(raw));
  if (isTime(column.type)) return String(raw);
  return String(raw);
}

/**
 * Module 2 · Institution structure.
 *
 * Two independent editors live here:
 *  - the institution register itself (`institution_create` / `institution_update`);
 *  - a generic record-section editor driven by the `section_*` family, which
 *    knows how to list, describe, save and delete the child rows of a student,
 *    an employee or a staff research activity.
 */
export function StructureEditor({
  institutions,
  universities,
  parents,
}: {
  institutions: InstitutionRow[];
  universities: UniversityOption[];
  parents: ParentOptions;
}) {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);

  const [tab, setTab] = useState<'institution' | 'sections'>('institution');
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  // ---------------------------------------------------------------- institution
  const [instForm, setInstForm] = useState<{
    id: number | null;
    values: Record<string, string>;
    original: Record<string, string> | null;
  } | null>(null);
  const [savingInstitution, setSavingInstitution] = useState(false);

  function startCreateInstitution() {
    setError(null);
    setInstForm({
      id: null,
      values: {
        university_id: '',
        institution_code: '',
        institution_name: '',
        legal_name: '',
        website_url: '',
        email: '',
        phone: '',
        is_active: 'true',
      },
      original: null,
    });
  }

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

  async function saveInstitution() {
    if (!instForm) return;
    setSavingInstitution(true);
    setError(null);
    try {
      const payload: Record<string, unknown> = {};
      for (const field of INSTITUTION_FIELDS) {
        if (instForm.id !== null && field.name === 'university_id') continue;
        const raw = (instForm.values[field.name] ?? '').trim();
        if (instForm.original) {
          const before = instForm.original[field.name] ?? '';
          if (raw === before) continue;
          payload[field.name] = field.name === 'university_id' ? Number(raw) : raw;
        } else if (raw !== '') {
          payload[field.name] = field.name === 'university_id' ? Number(raw) : raw;
        }
      }

      if (instForm.id === null) {
        const { error: createError } = await supabase.rpc('institution_create', { p: payload });
        if (createError) throw new Error(createError.message);
        setNotice('Institution created.');
      } else {
        const { error: updateError } = await supabase.rpc('institution_update', {
          p_id: instForm.id,
          p: payload,
        });
        if (updateError) throw new Error(updateError.message);
        setNotice('Institution updated.');
      }
      setInstForm(null);
      router.refresh();
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setSavingInstitution(false);
    }
  }

  // ------------------------------------------------------------------ sections
  const [kind, setKind] = useState<SectionKind>('student');
  const [sections, setSections] = useState<{ section: string; label: string }[]>([]);
  const [section, setSection] = useState('');
  const [parentId, setParentId] = useState('');
  const [parentQuery, setParentQuery] = useState('');
  const [sectionSchema, setSectionSchema] = useState<SectionSchema | null>(null);
  const [sectionRows, setSectionRows] = useState<Row[]>([]);
  const [permissions, setPermissions] = useState({ create: false, update: false, delete: false });
  const [lookups, setLookups] = useState<LookupMap>({});
  const [sectionForm, setSectionForm] = useState<{
    id: number | null;
    values: FormValues;
    original: FormValues | null;
  } | null>(null);
  const [savingSection, setSavingSection] = useState(false);

  const loadSections = useCallback(
    async (nextKind: SectionKind) => {
      const { data, error: sectionsError } = await supabase.rpc('record_sections', { p_kind: nextKind });
      if (sectionsError) {
        setError(sectionsError.message);
        setSections([]);
        return;
      }
      const list = Array.isArray(data) ? (data as { section: string; label: string }[]) : [];
      setSections(list);
      setSection(list[0]?.section ?? '');
    },
    [supabase],
  );

  useEffect(() => {
    void (async () => {
      // Clear the section first: the previous kind's section is not valid for the
      // new one, and asking the database for it would raise "Unknown section".
      setSection('');
      setParentId('');
      setParentQuery('');
      setSectionForm(null);
      setError(null);
      await loadSections(kind);
    })();
  }, [kind, loadSections]);

  const loadSectionRows = useCallback(
    async (nextKind: SectionKind, nextSection: string, nextParentId: string) => {
      if (!nextSection || !nextParentId) {
        setSectionRows([]);
        setSectionSchema(null);
        setPermissions({ create: false, update: false, delete: false });
        return;
      }
      setError(null);
      const parent = Number(nextParentId);
      const [rowsRes, schemaRes] = await Promise.all([
        supabase.rpc('section_rows', {
          p_kind: nextKind,
          p_parent_id: parent,
          p_section: nextSection,
        }),
        supabase.rpc('section_schema', { p_kind: nextKind, p_section: nextSection }),
      ]);
      if (rowsRes.error) {
        setError(rowsRes.error.message);
        setSectionRows([]);
        setPermissions({ create: false, update: false, delete: false });
      } else {
        const payload = (rowsRes.data ?? {}) as {
          rows?: Row[];
          can_create?: boolean;
          can_update?: boolean;
          can_delete?: boolean;
        };
        setSectionRows(Array.isArray(payload.rows) ? payload.rows : []);
        setPermissions({
          create: payload.can_create === true,
          update: payload.can_update === true,
          delete: payload.can_delete === true,
        });
      }
      if (schemaRes.error) {
        setSectionSchema(null);
      } else {
        setSectionSchema(schemaRes.data as SectionSchema);
      }
    },
    [supabase],
  );

  useEffect(() => {
    void (async () => {
      setSectionForm(null);
      await loadSectionRows(kind, section, parentId);
    })();
  }, [kind, section, parentId, loadSectionRows]);

  // Foreign-key dropdowns for the section form.
  useEffect(() => {
    if (!sectionSchema) return;
    const refs = [...new Set(sectionSchema.columns.map((c) => c.ref_table).filter((t): t is string => Boolean(t)))];
    if (refs.length === 0) return;
    let cancelled = false;
    void (async () => {
      const next: LookupMap = {};
      for (const ref of refs) {
        if (lookups[ref]) continue;
        const { data, error: lookupError } = await supabase.rpc('section_lookup_options', { p_table: ref });
        if (!lookupError && Array.isArray(data)) next[ref] = data as LookupOption[];
      }
      if (!cancelled && Object.keys(next).length > 0) setLookups((prev) => ({ ...prev, ...next }));
    })();
    return () => {
      cancelled = true;
    };
  }, [sectionSchema, supabase, lookups]);

  async function saveSection() {
    if (!sectionSchema || !sectionForm || !parentId) return;
    setSavingSection(true);
    setError(null);
    try {
      const payload = buildPayload(sectionSchema.columns, sectionForm.values, sectionForm.original);
      const { error: saveError } = await supabase.rpc('section_save', {
        p_kind: kind,
        p_parent_id: Number(parentId),
        p_section: section,
        p_id: sectionForm.id,
        p: payload,
      });
      if (saveError) throw new Error(saveError.message);
      setSectionForm(null);
      setNotice(sectionForm.id === null ? 'Row added.' : 'Row updated.');
      await loadSectionRows(kind, section, parentId);
      router.refresh();
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setSavingSection(false);
    }
  }

  async function removeSectionRow(id: number) {
    if (!parentId) return;
    setError(null);
    const { error: deleteError } = await supabase.rpc('section_delete', {
      p_kind: kind,
      p_parent_id: Number(parentId),
      p_section: section,
      p_id: id,
    });
    if (deleteError) {
      setError(deleteError.message);
      return;
    }
    setNotice('Row deleted.');
    await loadSectionRows(kind, section, parentId);
    router.refresh();
  }

  const parentList = useMemo(() => parents[kind] ?? [], [parents, kind]);
  const visibleParents = useMemo(() => {
    const q = parentQuery.trim().toLowerCase();
    if (!q) return parentList;
    return parentList.filter(
      (p) => p.label.toLowerCase().includes(q) || (p.sub ?? '').toLowerCase().includes(q),
    );
  }, [parentList, parentQuery]);

  const universityLabel = (id: number) => universities.find((u) => u.id === id)?.label ?? `#${id}`;

  return (
    <div className="space-y-4">
      <div className="flex gap-2">
        <Button variant={tab === 'institution' ? 'default' : 'outline'} onClick={() => setTab('institution')}>
          Institutions
        </Button>
        <Button variant={tab === 'sections' ? 'default' : 'outline'} onClick={() => setTab('sections')}>
          Record sections
        </Button>
      </div>

      {error ? <ErrorPanel message={error} /> : null}
      {notice ? <p className="text-sm text-emerald-700">{notice}</p> : null}

      {tab === 'institution' ? (
        <Card>
          <CardHeader className="flex-row items-center justify-between gap-3 space-y-0">
            <div>
              <CardTitle>Institution register</CardTitle>
              <CardDescription>
                {institutions.length} institution{institutions.length === 1 ? '' : 's'} visible to you.
              </CardDescription>
            </div>
            <Button onClick={startCreateInstitution}>New institution</Button>
          </CardHeader>
          <CardContent className="space-y-4">
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
                        <Button size="sm" variant="outline" onClick={() => startEditInstitution(row)}>
                          Edit
                        </Button>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}

            {instForm ? (
              <div className="rounded-lg border border-border p-4">
                <div className="mb-3 flex items-center justify-between">
                  <h3 className="text-sm font-semibold">
                    {instForm.id === null ? 'New institution' : `Edit institution ${instForm.id}`}
                  </h3>
                  <Button size="sm" variant="ghost" onClick={() => setInstForm(null)}>
                    Cancel
                  </Button>
                </div>

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

                <div className="mt-4 flex justify-end gap-2">
                  <Button variant="outline" onClick={() => setInstForm(null)}>
                    Cancel
                  </Button>
                  <Button disabled={savingInstitution} onClick={() => void saveInstitution()}>
                    {savingInstitution ? 'Saving…' : 'Save institution'}
                  </Button>
                </div>
              </div>
            ) : null}
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle>Record sections</CardTitle>
              <CardDescription>
                Pick a record type, a section and the parent record. The database decides which sections and rows you may see.
              </CardDescription>
            </CardHeader>
            <CardContent className="grid gap-4 md:grid-cols-3">
              <div>
                <Label htmlFor="section-kind" className="mb-1 block">
                  Record type
                </Label>
                <Select id="section-kind" value={kind} onChange={(e) => setKind(e.target.value as SectionKind)}>
                  {KINDS.map((k) => (
                    <option key={k.value} value={k.value}>
                      {k.label}
                    </option>
                  ))}
                </Select>
              </div>

              <div>
                <Label htmlFor="section-name" className="mb-1 block">
                  Section
                </Label>
                <Select
                  id="section-name"
                  value={section}
                  onChange={(e) => setSection(e.target.value)}
                  disabled={sections.length === 0}
                >
                  {sections.length === 0 ? <option value="">No sections available</option> : null}
                  {sections.map((s) => (
                    <option key={s.section} value={s.section}>
                      {s.label}
                    </option>
                  ))}
                </Select>
              </div>

              <div>
                <Label htmlFor="parent-query" className="mb-1 block">
                  Find parent record
                </Label>
                <Input
                  id="parent-query"
                  type="search"
                  placeholder="Name or number"
                  value={parentQuery}
                  onChange={(e) => setParentQuery(e.target.value)}
                />
              </div>

              <div className="md:col-span-3">
                <Label htmlFor="parent-record" className="mb-1 block">
                  Parent record
                </Label>
                <Select id="parent-record" value={parentId} onChange={(e) => setParentId(e.target.value)}>
                  <option value="">Select a record</option>
                  {visibleParents.map((p) => (
                    <option key={p.id} value={String(p.id)}>
                      {p.label}
                      {p.sub ? ` — ${p.sub}` : ''}
                    </option>
                  ))}
                </Select>
                {parentList.length === 0 ? (
                  <p className="mt-1 text-xs text-muted-foreground">No parent records are visible to you.</p>
                ) : visibleParents.length === 0 ? (
                  <p className="mt-1 text-xs text-muted-foreground">No record matches “{parentQuery}”.</p>
                ) : null}
              </div>
            </CardContent>
          </Card>

          {sectionSchema && parentId ? (
            <Card>
              <CardHeader className="flex-row items-center justify-between gap-3 space-y-0">
                <div>
                  <CardTitle>{sectionSchema.label}</CardTitle>
                  <CardDescription>
                    {sectionRows.length} row{sectionRows.length === 1 ? '' : 's'} · table{' '}
                    <code>{sectionSchema.table}</code>
                  </CardDescription>
                </div>
                {permissions.create ? (
                  <Button
                    onClick={() => {
                      setSectionForm({
                        id: null,
                        values: valuesFromRow(sectionSchema.columns, null),
                        original: null,
                      });
                      setError(null);
                    }}
                  >
                    Add row
                  </Button>
                ) : null}
              </CardHeader>
              <CardContent className="space-y-4">
                {sectionRows.length === 0 ? (
                  <EmptyState
                    title="Nothing recorded in this section yet"
                    description="Use “Add row” to create the first entry, if your permissions allow it."
                  />
                ) : (
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>{sectionSchema.pk}</TableHead>
                        {sectionSchema.columns.map((c) => (
                          <TableHead key={c.name}>{c.name.replace(/_/g, ' ')}</TableHead>
                        ))}
                        <TableHead className="text-right">Actions</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {sectionRows.map((row) => {
                        const id = Number(row[sectionSchema.pk]);
                        return (
                          <TableRow key={id}>
                            <TableCell className="font-medium tabular-nums">{String(row[sectionSchema.pk] ?? '')}</TableCell>
                            {sectionSchema.columns.map((c) => (
                              <TableCell key={c.name}>{renderCell(c, row[c.name])}</TableCell>
                            ))}
                            <TableCell className="text-right">
                              <div className="flex justify-end gap-2">
                                {permissions.update ? (
                                  <Button
                                    size="sm"
                                    variant="outline"
                                    onClick={() => {
                                      const values = valuesFromRow(sectionSchema.columns, row);
                                      setSectionForm({ id, values, original: values });
                                      setError(null);
                                    }}
                                  >
                                    Edit
                                  </Button>
                                ) : null}
                                {permissions.delete ? (
                                  <Button size="sm" variant="destructive" onClick={() => void removeSectionRow(id)}>
                                    Delete
                                  </Button>
                                ) : null}
                              </div>
                            </TableCell>
                          </TableRow>
                        );
                      })}
                    </TableBody>
                  </Table>
                )}

                {sectionForm ? (
                  <div className="rounded-lg border border-border p-4">
                    <div className="mb-3 flex items-center justify-between">
                      <h3 className="text-sm font-semibold">
                        {sectionForm.id === null ? 'New row' : `Edit row ${sectionForm.id}`}
                      </h3>
                      <Button size="sm" variant="ghost" onClick={() => setSectionForm(null)}>
                        Cancel
                      </Button>
                    </div>
                    <DynamicForm
                      columns={sectionSchema.columns}
                      values={sectionForm.values}
                      lookups={lookups}
                      idPrefix={`sec-${sectionForm.id ?? 'new'}`}
                      onChange={(name, value) =>
                        setSectionForm((prev) => (prev ? { ...prev, values: { ...prev.values, [name]: value } } : prev))
                      }
                    />
                    <div className="mt-4 flex justify-end gap-2">
                      <Button variant="outline" onClick={() => setSectionForm(null)}>
                        Cancel
                      </Button>
                      <Button disabled={savingSection} onClick={() => void saveSection()}>
                        {savingSection ? 'Saving…' : 'Save row'}
                      </Button>
                    </div>
                  </div>
                ) : null}
              </CardContent>
            </Card>
          ) : null}
        </div>
      )}
    </div>
  );
}
