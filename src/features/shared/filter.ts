/** Small text helpers shared by the module 1–5 list pages. */

export type LabelOption = { id: number; label: string };

/** Case-insensitive substring match across a row's cells. */
export function matchesQuery(cells: readonly unknown[], query: string): boolean {
  const q = query.trim().toLowerCase();
  if (!q) return true;
  return cells.some((cell) => {
    if (cell === null || cell === undefined) return false;
    if (Array.isArray(cell)) return cell.some((c) => String(c ?? '').toLowerCase().includes(q));
    return String(cell).toLowerCase().includes(q);
  });
}

/** Keep the rows whose cells match the search box. */
export function filterByQuery<T>(
  rows: readonly T[],
  query: string,
  cells: (row: T) => readonly unknown[],
): T[] {
  if (!query.trim()) return rows.slice();
  return rows.filter((row) => matchesQuery(cells(row), query));
}

/** Resolve a foreign key to its label, falling back to the raw id. */
export function labelFor(options: readonly LabelOption[], id: number | null | undefined): string {
  if (id === null || id === undefined) return '—';
  return options.find((o) => o.id === id)?.label ?? `#${id}`;
}

/** Distinct, sorted values of a column — used to build filter dropdowns. */
export function distinctValues<T>(rows: readonly T[], pick: (row: T) => string | null | undefined): string[] {
  const seen = new Set<string>();
  for (const row of rows) {
    const v = pick(row);
    if (v !== null && v !== undefined && v !== '') seen.add(v);
  }
  return [...seen].sort((a, b) => a.localeCompare(b));
}
