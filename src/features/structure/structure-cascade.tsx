'use client';

import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { EmptyState } from '@/components/ui/empty-state';
import { Label, Select } from '@/components/ui/input';
import {
  DynamicForm,
  buildPayload,
  coerce,
  valuesFromRow,
  type FormColumn,
  type FormValues,
  type LookupMap,
} from '@/features/shared/dynamic-form';
import { Alert, Notice } from '@/features/shared/feedback';
import { RecordForm } from '@/features/shared/record-form';
import { recordNoun, recordNounTitle } from '@/features/shared/record-noun';
import { errorMessage } from '@/features/shared/reads';
import { formatNumber } from '@/lib/format';
import type { AdminSchema } from '@/features/admin/admin-table-editor';
import { createClient } from '@/lib/supabase/client';
import {
  ROOT_LABEL,
  ROOT_TABLE,
  childrenOf,
  firstPk,
  inheritForeignKeys,
  rowDetail,
  rowLabel,
  stepFor,
  type PathNode,
} from './hierarchy';

type Row = Record<string, unknown>;

/** The rows drawn at one level of the hierarchy. */
type Level = {
  table: string;
  label: string;
  pkCols: string[];
  rows: Row[];
  /**
   * The record these rows hang off, carried on the level rather than read
   * from `path`.
   *
   * `path` updates the moment a row is opened; `level` updates only after the
   * read that follows. Reading the header from `path` would paint one frame of
   * the *new* level's Add buttons and the *new* parent's name above the
   * *old* list. Everything drawn under this heading comes from here instead,
   * so the heading and the list can never disagree.
   */
  parentLabel: string | null;
  /**
   * The tables that can be created *here* - the children of the parent these
   * rows hang off.
   *
   * Same reason as `parentLabel`: it comes from `path`, which updates before
   * the read does, so it is carried on the level to keep the buttons and the
   * list in the same frame.
   */
  creates: string[];
  /**
   * How many rows exist here, which is not necessarily how many were drawn:
   * the read is capped at `LEVEL_LIMIT`, and the header must not report the
   * cap as though it were the total.
   */
  total: number;
};

/** How many rows one level shows. The Manage panel uses the same ceiling. */
const LEVEL_LIMIT = 500;

/**
 * The columns of the institution register.
 *
 * `institution` is the one table here that is not in the admin catalogue - it
 * is written through `institution_create` / `institution_update`, which know
 * how to validate a code and an owning university - so its shape is described
 * here in the same column form `admin_table_schema` hands out, and the rest of
 * the builder then treats it like any other table.
 */
const INSTITUTION_COLUMNS: FormColumn[] = [
  { name: 'university_id', type: 'integer', required: true, max_length: null, ref_table: 'university', choices: null },
  { name: 'institution_code', type: 'text', required: true, max_length: 20, ref_table: null, choices: null },
  { name: 'institution_name', type: 'text', required: true, max_length: 200, ref_table: null, choices: null },
  { name: 'legal_name', type: 'text', required: false, max_length: 250, ref_table: null, choices: null },
  { name: 'website_url', type: 'text', required: false, max_length: 255, ref_table: null, choices: null },
  { name: 'email', type: 'text', required: false, max_length: 254, ref_table: null, choices: null },
  { name: 'phone', type: 'text', required: false, max_length: 25, ref_table: null, choices: null },
  { name: 'is_active', type: 'boolean', required: false, max_length: null, ref_table: null, choices: null },
];

const INSTITUTION_SCHEMA: AdminSchema = {
  table: ROOT_TABLE,
  label: ROOT_LABEL,
  module_codes: ['INSTITUTION'],
  pk: 'institution_id',
  pk_cols: ['institution_id'],
  columns: INSTITUTION_COLUMNS,
};

/**
 * The guided way to build the institution structure.
 *
 * The Manage panel below this card edits one table at a time, which is the
 * right tool for maintenance and the wrong one for setup: adding an
 * institution leaves you to work out that a campus comes next, and adding a
 * building leaves the floors and the rooms somewhere else entirely.
 *
 * This card follows the hierarchy instead. It starts at the institution
 * register, drills into whichever record you open, and offers every table that
 * can be created underneath it - with the parent already chosen, because you
 * are standing inside it. Save a record and the tables that hang off *that*
 * record are offered next, so the whole chain down to a room is one connected
 * sequence of saves rather than a hunt through a table picker.
 *
 * Everything is still written by the database: `institution_create` for the
 * register, `admin_table_save` for the rest, each re-checking permission and
 * scope. The inherited foreign keys are injected into the payload rather than
 * shown as a field the user could drift away from, so a room added from a
 * floor cannot end up on another building.
 */
export function StructureCascade({
  universities,
}: {
  universities: { id: number; label: string }[];
}) {
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);

  const [path, setPath] = useState<PathNode[]>([]);
  const [level, setLevel] = useState<Level | null>(null);
  const [schemas, setSchemas] = useState<Record<string, AdminSchema>>({
    [ROOT_TABLE]: INSTITUTION_SCHEMA,
  });
  const [lookups, setLookups] = useState<LookupMap>({ university: universities });
  const [allowed, setAllowed] = useState<boolean | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [adding, setAdding] = useState<{
    table: string;
    values: FormValues;
    hidden: string[];
  } | null>(null);
  /** The tables offered immediately after a save: "Next: …". */
  const [nextSteps, setNextSteps] = useState<string[]>([]);

  /**
   * The caches live in refs rather than in `schemas` state alone.
   *
   * `loadLevel` must keep a stable identity - the effect that calls it keys
   * off that identity - so `loadSchema` cannot depend on the `schemas` state
   * it fills without re-creating `loadLevel` on every write, which would
   * re-run the effect, write again, and loop. The ref is the cache; the state
   * exists only so the render reads the same values.
   */
  const schemasRef = useRef<Record<string, AdminSchema>>({ [ROOT_TABLE]: INSTITUTION_SCHEMA });

  /** Labels of a table's rows, keyed by table, so a level does not re-read them. */
  const labelsRef = useRef<Record<string, Record<number, string>>>({});

  /** Which `loadLevel` call is the current one; older ones are discarded. */
  const loadTokenRef = useRef(0);

  const loadSchema = useCallback(
    async (table: string): Promise<AdminSchema | null> => {
      if (table === ROOT_TABLE) return INSTITUTION_SCHEMA;
      const cached = schemasRef.current[table];
      if (cached) return cached;

      const { data, error: schemaError } = await supabase.rpc('admin_table_schema', { p_table: table });
      // A refusal is not cached: it may be a transient failure, and the next
      // visit deserves another attempt rather than a permanently empty form.
      if (schemaError || !data) return null;
      const schema = data as AdminSchema;
      schemasRef.current = { ...schemasRef.current, [table]: schema };
      setSchemas((prev) => ({ ...prev, [table]: schema }));
      return schema;
    },
    [supabase],
  );

  /** The labels the database publishes for a table, for the list. */
  const loadLabels = useCallback(
    async (table: string): Promise<Record<number, string>> => {
      const cached = labelsRef.current[table];
      if (cached) return cached;

      const { data } = await supabase.rpc('admin_lookup_options', { p_table: table });
      if (!Array.isArray(data)) return {};
      const map: Record<number, string> = {};
      for (const option of data as { id: number; label: string }[]) map[Number(option.id)] = option.label;
      labelsRef.current = { ...labelsRef.current, [table]: map };
      return map;
    },
    [supabase],
  );

  /**
   * Read the level the path currently points at: every table that can be
   * created here, the rows of each that belong to this parent, and the labels
   * to draw them with.
   */
  const loadLevel = useCallback(
    async (currentPath: PathNode[]) => {
      const at = currentPath[currentPath.length - 1] ?? null;
      const tables = at ? childrenOf(at.table) : [ROOT_TABLE];

      // Two loads can be in flight at once - a fast click through the
      // breadcrumb, or a save that re-reads while the effect is already
      // reading. Whoever starts last owns the screen, and whoever started
      // earlier is discarded on arrival rather than overwriting it.
      const token = (loadTokenRef.current += 1);

      setLoading(true);
      setError(null);
      try {
        const levels = await Promise.all(
          tables.map(async (table): Promise<Level | null> => {
            try {
              const step = at ? stepFor(at.table, table) : null;
              const schema = await loadSchema(table);
              // A table whose schema is refused is one the caller may not write
              // to; its rows are still listed if they are readable, but nothing
              // can be added under it.
              const pkCols = table === ROOT_TABLE ? ['institution_id'] : (schema?.pk_cols ?? []);

              const [rowsRes, labels] = await Promise.all([
                step
                  ? supabase
                      .from(table)
                      .select('*', { count: 'exact' })
                      .eq(step.fk, at!.key)
                      .limit(LEVEL_LIMIT)
                  : supabase.from(table).select('*', { count: 'exact' }).limit(LEVEL_LIMIT),
                loadLabels(table),
              ]);
              // One unreadable table must not blank the level: the other
              // tables still draw, and this one is simply left out.
              if (rowsRes.error) return null;

              const rows = (rowsRes.data ?? []) as Row[];
              return {
                table,
                label: table === ROOT_TABLE ? ROOT_LABEL : (schema?.label ?? table),
                pkCols,
                parentLabel: at?.label ?? null,
                creates: tables,
                // `count` ignores the limit, so it is the real size of the
                // level; `rows` is only what fit under it.
                total: rowsRes.count ?? rows.length,
                rows: rows.map((row) => {
                  const id = Number(row[firstPk(pkCols)]);
                  return { ...row, __label: labels[id] };
                }),
              };
            } catch {
              return null;
            }
          }),
        );

        if (token !== loadTokenRef.current) return;

        const first = levels.find((entry): entry is Level => entry !== null);
        setLevel(first ?? null);

        const unreadable = levels.filter((entry) => entry === null);
        if (unreadable.length > 0 && first === null) {
          setError('You do not have access to this part of the structure.');
        }
      } catch (e) {
        if (token !== loadTokenRef.current) return;
        setLevel(null);
        setError(errorMessage(e));
      } finally {
        if (token === loadTokenRef.current) setLoading(false);
      }
    },
    [loadLabels, loadSchema, supabase],
  );

  // Which of this screen's tables may the caller write to? The card is only
  // worth drawing when there is something here to create.
  useEffect(() => {
    let cancelled = false;
    void (async () => {
      const { data, error: listError } = await supabase.rpc('admin_table_list');
      if (cancelled) return;
      if (listError) {
        setAllowed(false);
        return;
      }
      const mine = ((data ?? []) as { module_codes: string[] }[]).filter((entry) =>
        (entry.module_codes ?? []).includes('INSTITUTION'),
      );
      setAllowed(mine.length > 0);
    })();
    return () => {
      cancelled = true;
    };
  }, [supabase]);

  useEffect(() => {
    void (async () => {
      await loadLevel(path);
    })();
  }, [path, loadLevel]);

  /**
   * The form for one table, with the foreign keys the path already decides
   * taken out of the fields and kept aside for the payload.
   */
  const openAdd = useCallback(
    async (table: string) => {
      setError(null);
      setNotice(null);
      const schema = schemas[table] ?? (await loadSchema(table));
      if (!schema) {
        setError('You do not have permission to add here.');
        return;
      }

      const { values: inherited, hidden } = inheritForeignKeys(path, table);
      const values = valuesFromRow(schema.columns, null);
      for (const [column, value] of Object.entries(inherited)) values[column] = value;

      // Labels for any dropdown the form draws.
      const refs = [...new Set(schema.columns.map((c) => c.ref_table).filter((t): t is string => Boolean(t)))];
      const missing = refs.filter((ref) => !lookups[ref]);
      if (missing.length > 0) {
        const next: LookupMap = {};
        for (const ref of missing) {
          const { data } = await supabase.rpc('admin_lookup_options', { p_table: ref });
          if (Array.isArray(data)) next[ref] = data as { id: number; label: string }[];
        }
        if (Object.keys(next).length > 0) setLookups((prev) => ({ ...prev, ...next }));
      }

      setNextSteps([]);
      setAdding({ table, values, hidden });
    },
    [loadSchema, lookups, path, supabase, schemas],
  );

  async function save() {
    if (!adding) return;
    const { table, values, hidden } = adding;
    const schema = schemas[table] ?? INSTITUTION_SCHEMA;
    const visible = schema.columns.filter((column) => !hidden.includes(column.name));

    setSaving(true);
    setError(null);
    try {
      const payload = buildPayload(visible, values, null);

      // The hidden columns are not fields, so `buildPayload` never sees them;
      // they are written straight into the payload, coerced the same way.
      for (const column of schema.columns) {
        if (!hidden.includes(column.name)) continue;
        const raw = values[column.name] ?? '';
        if (raw !== '') payload[column.name] = coerce(column, raw);
      }

      let created: number;
      if (table === ROOT_TABLE) {
        const { data, error: createError } = await supabase.rpc('institution_create', { p: payload });
        if (createError) throw new Error(createError.message);
        created = Number(data);
      } else {
        const { data, error: saveError } = await supabase.rpc('admin_table_save', {
          p_table: table,
          p_key: null,
          p: payload,
        });
        if (saveError) throw new Error(saveError.message);
        created = Number(data);
      }

      const noun = recordNounTitle(schema.label);
      setNotice(`${noun} added.`);
      setAdding(null);

      // The new row's label is not in the labels read before it existed.
      delete labelsRef.current[table];

      const kids = childrenOf(table);

      if (kids.length === 0) {
        // A leaf - a room, a specialisation - has nowhere to go next, so the
        // list stays where it is and simply gains the record.
        setNextSteps([]);
        await loadLevel(path);
        router.refresh();
        return;
      }

      // The chips are drawn from the catalogue's labels, and the level below
      // has not been read yet, so the labels are fetched here - otherwise the
      // chip says "Add land" while the button it leads to says "Add land
      // parcel", which reads like two different things.
      await Promise.all(kids.map((kid) => loadSchema(kid)));

      // Stand inside what was just saved, so its own children become the
      // level below and the next step is one click away.
      const pkCol = schema.pk ?? firstPk(schema.pk_cols);
      const { data: row } = await supabase.from(table).select('*').eq(pkCol, created).maybeSingle();
      const fresh = (row as Row | null) ?? { ...payload, [pkCol]: created };

      setNextSteps(kids);
      setPath([
        ...path,
        { table, key: created, label: rowLabel(fresh, schema.pk_cols, undefined), row: fresh },
      ]);
      router.refresh();
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setSaving(false);
    }
  }

  function drillInto(row: Row) {
    if (!level) return;
    const key = Number(row[firstPk(level.pkCols)]);
    setAdding(null);
    setNextSteps([]);
    setNotice(null);
    setError(null);
    setPath([
      ...path,
      {
        table: level.table,
        key,
        label: rowLabel(row, level.pkCols, row.__label as string | undefined),
        row,
      },
    ]);
  }

  function goTo(index: number) {
    setAdding(null);
    setNextSteps([]);
    setNotice(null);
    setError(null);
    setPath(path.slice(0, index));
  }

  /** Walk into an institution chosen from the root picker. */
  function openInstitution(value: string) {
    if (!value || !level) return;
    const row = level.rows.find((entry) => String(entry[firstPk(level.pkCols)]) === value);
    if (row) drillInto(row);
  }

  if (allowed === null) return null;
  if (!allowed) return null;

  const addingSchema = adding ? (schemas[adding.table] ?? INSTITUTION_SCHEMA) : null;
  const visibleColumns = addingSchema && adding
    ? addingSchema.columns.filter((column) => !adding.hidden.includes(column.name))
    : [];
  const noun = addingSchema ? recordNoun(addingSchema.label) : 'record';
  const parentLabel = level?.parentLabel ?? null;

  return (
    <Card className="mb-6" data-testid="structure-cascade">
      <CardHeader>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <CardTitle>Structure builder</CardTitle>
            <CardDescription>
              Follow the hierarchy down: an institution, then its campuses, departments and programmes -
              or its land, buildings, floors and rooms. Each record offers its own children as soon as it is
              saved.
            </CardDescription>
          </div>
          {path.length > 0 ? (
            <Button variant="outline" size="sm" onClick={() => goTo(0)}>
              Start again
            </Button>
          ) : null}
        </div>
      </CardHeader>

      <CardContent className="space-y-4">
        {error ? <Alert message={error} /> : null}
        {notice ? <Notice testId="cascade-notice">{notice}</Notice> : null}

        {/* Where you are. Every ancestor is a way back. */}
        <nav aria-label="Structure path" className="flex flex-wrap items-center gap-1 text-sm">
          {path.length === 0 ? (
            <span className="font-medium">{ROOT_LABEL}</span>
          ) : (
            <>
              <button
                type="button"
                className="text-muted-foreground underline-offset-2 hover:underline"
                onClick={() => goTo(0)}
              >
                {ROOT_LABEL}
              </button>
              {path.map((node, index) => (
                <span key={`${node.table}-${node.key}`} className="flex items-center gap-1">
                  <span className="text-muted-foreground" aria-hidden>
                    ›
                  </span>
                  {index === path.length - 1 ? (
                    <span className="font-medium">{node.label}</span>
                  ) : (
                    <button
                      type="button"
                      className="text-muted-foreground underline-offset-2 hover:underline"
                      onClick={() => goTo(index + 1)}
                    >
                      {node.label}
                    </button>
                  )}
                </span>
              ))}
            </>
          )}
        </nav>

        {/*
          The form sits above the list: with the level underneath it, a form at
          the bottom of the card is a long scroll away from the button that
          opened it.
        */}
        {adding && addingSchema ? (
          <RecordForm
            title={`New ${noun}${parentLabel ? ` under ${parentLabel}` : ''}`}
            isNew
            saving={saving}
            onCancel={() => setAdding(null)}
            onSave={() => void save()}
            testId="cascade-form"
          >
            {adding.hidden.length > 0 ? (
              <p className="mb-3 text-sm text-muted-foreground">
                Added under {parentLabel ?? 'the selected record'}.
              </p>
            ) : null}
            <DynamicForm
              columns={visibleColumns}
              values={adding.values}
              lookups={lookups}
              idPrefix="cascade"
              onChange={(name, value) =>
                setAdding((prev) => (prev ? { ...prev, values: { ...prev.values, [name]: value } } : prev))
              }
            />
          </RecordForm>
        ) : null}

        {/* What comes next, offered straight after a save. */}
        {nextSteps.length > 0 && !adding ? (
          <div
            className="flex flex-wrap items-center gap-2 rounded-md border border-emerald-200 bg-emerald-50 px-3 py-2"
            data-testid="cascade-next"
          >
            <span className="text-sm font-medium text-emerald-800">Next step{nextSteps.length > 1 ? 's' : ''}:</span>
            {nextSteps.map((table) => (
              <Button key={table} size="sm" variant="outline" onClick={() => void openAdd(table)}>
                Add {recordNoun(schemas[table]?.label ?? table)}
              </Button>
            ))}
            <span className="text-xs text-emerald-700">
              or keep building from the record you just added.
            </span>
          </div>
        ) : null}

        {loading ? (
          <p className="text-sm text-muted-foreground">Loading…</p>
        ) : !level ? (
          <EmptyState
            title="Nothing to show here"
            description="You do not have access to this part of the structure."
          />
        ) : path.length === 0 ? (
          /*
            The register below already lists the institutions as a table, so
            the builder starts from a picker rather than a second copy of it.
            Choosing one puts you inside it, and the campuses underneath
            become the level to build on.
          */
          <div className="space-y-3">
            <div className="flex flex-wrap items-end gap-3">
              <div className="w-72 max-w-full">
                <Label htmlFor="cascade-institution" className="mb-1 block">
                  Start with an institution
                </Label>
                <Select
                  id="cascade-institution"
                  value=""
                  onChange={(e) => openInstitution(e.target.value)}
                >
                  <option value="">Choose an institution…</option>
                  {level.rows.map((row) => {
                    const keyText = String(row[firstPk(level.pkCols)] ?? '');
                    return (
                      <option key={keyText} value={keyText}>
                        {rowLabel(row, level.pkCols, row.__label as string | undefined)}
                      </option>
                    );
                  })}
                </Select>
              </div>
              <Button onClick={() => void openAdd(ROOT_TABLE)}>New institution</Button>
            </div>

            {level.rows.length === 0 ? (
              <EmptyState
                title="No institutions yet"
                description="Register the first institution to start building the structure under it."
              />
            ) : (
              <p className="text-sm text-muted-foreground">
                {level.rows.length} institution{level.rows.length === 1 ? '' : 's'} registered. Pick one to
                add campuses, departments, programmes, land, buildings, floors and rooms under it.
              </p>
            )}
          </div>
        ) : (
          <>
            <div className="flex flex-wrap items-center justify-between gap-3">
              <p className="text-sm text-muted-foreground">
                {level.total > level.rows.length
                  ? `Showing ${formatNumber(level.rows.length)} of ${formatNumber(level.total)}`
                  : formatNumber(level.total)}{' '}
                {level.label.toLowerCase()} under {parentLabel}
              </p>
              <div className="flex flex-wrap gap-2">
                {level.creates.map((table) => (
                  <Button key={table} size="sm" onClick={() => void openAdd(table)}>
                    Add {recordNoun(schemas[table]?.label ?? table)}
                  </Button>
                ))}
              </div>
            </div>

            {level.rows.length === 0 ? (
              <EmptyState
                title={`No ${level.label.toLowerCase()} yet`}
                description={`Use “Add” to create the first one under ${parentLabel}.`}
              />
            ) : (
              <ul className="divide-y rounded-md border" data-testid="cascade-list">
                {level.rows.map((row) => {
                  const keyText = level.pkCols.map((column) => String(row[column] ?? '')).join(' / ');
                  const primary = rowLabel(row, level.pkCols, row.__label as string | undefined);
                  const detail = rowDetail(row, primary);
                  const hasChildren = childrenOf(level.table).length > 0;

                  return (
                    <li key={keyText} className="flex items-center justify-between gap-3 px-3 py-2">
                      <div className="min-w-0">
                        <p className="truncate text-sm font-medium">{primary}</p>
                        {detail ? (
                          <p className="truncate text-xs text-muted-foreground">{detail}</p>
                        ) : null}
                      </div>
                      {hasChildren ? (
                        <Button size="sm" variant="outline" onClick={() => drillInto(row)}>
                          Open
                        </Button>
                      ) : null}
                    </li>
                  );
                })}
              </ul>
            )}

            {/*
              The read is capped, and a capped list that looks complete is
              worse than an obviously short one: say so, and say where the
              rest can be reached.
            */}
            {level.total > level.rows.length ? (
              <p className="text-xs text-muted-foreground" data-testid="cascade-truncated">
                This list stops at {formatNumber(level.rows.length)} rows. Use “Filter rows” in the Manage
                panel below to reach the remaining {formatNumber(level.total - level.rows.length)}.
              </p>
            ) : null}
          </>
        )}
      </CardContent>
    </Card>
  );
}
