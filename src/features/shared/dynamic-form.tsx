'use client';

import { Input, Label, Select } from '@/components/ui/input';

/**
 * A form generated from the database's own column description.
 *
 * `ref_schema()` and `section_schema()` both return the same shape — a list of
 * `{ name, type, required, max_length, ref_table, choices }` descriptors — so a
 * single renderer serves every generic editor in the application.
 */

export type FormColumn = {
  name: string;
  type: string;
  required: boolean;
  max_length: number | null;
  ref_table: string | null;
  choices: string[] | null;
};

export type FormValues = Record<string, string>;

export type LookupOption = { id: number; label: string };

export type LookupMap = Record<string, LookupOption[]>;

export function isBoolean(type: string): boolean {
  return type.trim().toLowerCase() === 'boolean';
}

export function isNumeric(type: string): boolean {
  return /^(smallint|integer|bigint|numeric|decimal|real|double precision)/i.test(type.trim());
}

export function isDate(type: string): boolean {
  return type.trim().toLowerCase() === 'date';
}

export function isTimestamp(type: string): boolean {
  return type.trim().toLowerCase().startsWith('timestamp');
}

export function isTime(type: string): boolean {
  const t = type.trim().toLowerCase();
  return t.startsWith('time');
}

/** Stringify a database row into the flat string map the form works with. */
export function valuesFromRow(columns: readonly FormColumn[], row: Record<string, unknown> | null): FormValues {
  const values: FormValues = {};
  for (const column of columns) {
    const raw = row ? row[column.name] : null;
    values[column.name] = raw === null || raw === undefined ? '' : String(raw);
  }
  return values;
}

/** Turn one form value into the jsonb value the database expects. */
export function coerce(column: FormColumn, raw: string): unknown {
  if (isBoolean(column.type)) return raw === 'true';
  if (isNumeric(column.type)) {
    const n = Number(raw);
    return Number.isFinite(n) ? n : raw;
  }
  return raw;
}

/**
 * Build the jsonb payload for `ref_save()` / `section_save()`.
 *
 * On an update only the changed columns are sent, so an untouched column is
 * never overwritten with NULL. On a create every non-empty column is sent and
 * the database defaults fill the rest.
 */
export function buildPayload(
  columns: readonly FormColumn[],
  values: FormValues,
  original: FormValues | null,
): Record<string, unknown> {
  const payload: Record<string, unknown> = {};
  for (const column of columns) {
    const raw = values[column.name] ?? '';
    if (original) {
      const before = original[column.name] ?? '';
      if (raw === before) continue;
      payload[column.name] = raw === '' ? null : coerce(column, raw);
    } else {
      if (raw === '') continue;
      payload[column.name] = coerce(column, raw);
    }
  }
  return payload;
}

export function DynamicForm({
  columns,
  values,
  onChange,
  lookups,
  idPrefix,
}: {
  columns: readonly FormColumn[];
  values: FormValues;
  onChange: (name: string, value: string) => void;
  lookups: LookupMap;
  idPrefix: string;
}) {
  if (columns.length === 0) {
    return <p className="text-sm text-muted-foreground">This table has no editable columns.</p>;
  }

  return (
    <div className="grid gap-3 sm:grid-cols-2">
      {columns.map((column) => {
        const id = `${idPrefix}-${column.name}`;
        const value = values[column.name] ?? '';
        const lookup = column.ref_table ? lookups[column.ref_table] : undefined;
        const wide = column.type.trim().toLowerCase() === 'text';

        return (
          <div key={column.name} className={wide ? 'sm:col-span-2' : undefined}>
            <Label htmlFor={id} className="mb-1 block capitalize">
              {column.name.replace(/_/g, ' ')}
              {column.required ? <span className="text-destructive"> *</span> : null}
            </Label>

            {column.choices && column.choices.length > 0 ? (
              <Select id={id} value={value} onChange={(e) => onChange(column.name, e.target.value)}>
                <option value="">—</option>
                {column.choices.map((choice) => (
                  <option key={choice} value={choice}>
                    {choice}
                  </option>
                ))}
              </Select>
            ) : isBoolean(column.type) ? (
              <Select id={id} value={value} onChange={(e) => onChange(column.name, e.target.value)}>
                <option value="">—</option>
                <option value="true">Yes</option>
                <option value="false">No</option>
              </Select>
            ) : lookup && lookup.length > 0 ? (
              <Select id={id} value={value} onChange={(e) => onChange(column.name, e.target.value)}>
                <option value="">—</option>
                {lookup.map((option) => (
                  <option key={option.id} value={String(option.id)}>
                    {option.label}
                  </option>
                ))}
              </Select>
            ) : (
              <Input
                id={id}
                type={
                  isNumeric(column.type)
                    ? 'number'
                    : isDate(column.type)
                      ? 'date'
                      : isTimestamp(column.type)
                        ? 'datetime-local'
                        : isTime(column.type)
                          ? 'time'
                          : 'text'
                }
                value={value}
                maxLength={column.max_length ?? undefined}
                onChange={(e) => onChange(column.name, e.target.value)}
                placeholder={column.ref_table ? `${column.ref_table} id` : undefined}
              />
            )}

            {column.ref_table ? (
              <p className="mt-1 text-xs text-muted-foreground">References {column.ref_table}.</p>
            ) : null}
          </div>
        );
      })}
    </div>
  );
}
