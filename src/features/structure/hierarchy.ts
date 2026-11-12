/**
 * The institution structure hierarchy, expressed as the foreign keys the
 * schema actually has.
 *
 * The database owns every write: `institution_create` / `institution_update`
 * for the register itself and `admin_table_save` for everything below it, and
 * each of them re-checks the caller's permission and scope before a row is
 * stored. This module decides only *which button to offer next* - a display
 * affordance, never an authorisation decision. A wrong edge here cannot write
 * a row the caller is not allowed to write: at worst it offers a button that
 * the database then refuses, and the refusal is what the builder shows.
 *
 * It is written down rather than derived because the catalogue the client can
 * reach - `admin_table_list` / `admin_table_schema` - deliberately does not
 * expose `scope_path`, so there is nothing to read the parents from. The edges
 * below are the DDL of migrations 001 and 068:
 *
 *   campus.institution_id                  department.campus_id
 *   land.campus_id                         building.campus_id
 *   building.land_id (optional)            programme.department_id
 *   programme_specialization.programme_id  floor.building_id
 *   room.building_id                       room.floor_id (optional)
 *
 * Only the tables of the INSTITUTION module are here, so the builder offers
 * exactly the tables this screen's Manage panel already offers.
 */

/** One parent -> child edge of the hierarchy. */
export type StructureStep = {
  /** the table this step creates */
  table: string;
  /** the table it hangs off */
  parent: string;
  /** the column on `table` that carries the parent's key */
  fk: string;
};

/**
 * A second parent that is filled in when the caller is already inside it.
 *
 * A building belongs to a campus and may stand on a land parcel; a room
 * belongs to a building and may be on a floor. The required parent is
 * inherited from the path, and the optional one is too - but only when the
 * path actually passes through it, so starting from the campus still offers
 * the land and the floor as choices rather than forcing them.
 */
export type OptionalParent = {
  /** the column on the child table to fill in */
  fk: string;
  /** the ancestor table whose key supplies it */
  from: string;
};

/** Where the builder starts: the institution register. */
export const ROOT_TABLE = 'institution';

/** The label of the root, which is not in the admin catalogue at all. */
export const ROOT_LABEL = 'Institutions';

export const STRUCTURE_STEPS: StructureStep[] = [
  { table: 'campus', parent: 'institution', fk: 'institution_id' },
  { table: 'department', parent: 'campus', fk: 'campus_id' },
  { table: 'land', parent: 'campus', fk: 'campus_id' },
  { table: 'building', parent: 'campus', fk: 'campus_id' },
  { table: 'programme', parent: 'department', fk: 'department_id' },
  { table: 'programme_specialization', parent: 'programme', fk: 'programme_id' },
  { table: 'floor', parent: 'building', fk: 'building_id' },
  { table: 'room', parent: 'building', fk: 'building_id' },
];

export const STRUCTURE_OPTIONAL: Record<string, OptionalParent[]> = {
  building: [{ fk: 'land_id', from: 'land' }],
  room: [{ fk: 'floor_id', from: 'floor' }],
};

/** The tables that can be created directly under `table`, in display order. */
export function childrenOf(table: string): string[] {
  return STRUCTURE_STEPS.filter((step) => step.parent === table).map((step) => step.table);
}

/**
 * The column that identifies one row, or `''` when the key is composite.
 *
 * Only single-column keys are drilled into - every table with children has
 * one - but a level still has to be drawn for a table like
 * `programme_specialization`, whose key is two columns wide, and an empty
 * string indexes nothing rather than throwing.
 */
export function firstPk(pkCols: readonly string[]): string {
  return pkCols[0] ?? '';
}

/** The edge that puts `child` under `parent`, or null when there is none. */
export function stepFor(parent: string, child: string): StructureStep | null {
  return STRUCTURE_STEPS.find((step) => step.parent === parent && step.table === child) ?? null;
}

/**
 * One node of the path the builder is currently inside.
 *
 * The whole row travels with the node rather than just its key, because a
 * child's foreign key is inherited from whichever ancestor carries that
 * column: a room under a floor takes its `building_id` from the floor.
 */
export type PathNode = {
  table: string;
  key: number;
  label: string;
  row: Record<string, unknown>;
};

/**
 * The foreign keys of `table` that the current path already decides, and
 * which must therefore be hidden from the form and injected into the payload.
 *
 * The required parent is inherited from the deepest ancestor that carries the
 * column; an optional parent is inherited only from an ancestor of its own
 * table. Anything left out stays visible as a normal field, so a room added
 * from a building still offers the floor as a choice.
 */
export function inheritForeignKeys(
  path: readonly PathNode[],
  table: string,
): { values: Record<string, string>; hidden: string[] } {
  const values: Record<string, string> = {};
  const hidden: string[] = [];

  const focus = path[path.length - 1];
  const step = focus ? stepFor(focus.table, table) : null;
  if (step) {
    // Deepest ancestor first: the floor knows the building as well as the
    // building does, and it is the more specific answer.
    for (let i = path.length - 1; i >= 0; i -= 1) {
      const node = path[i];
      if (!node) continue;
      const raw = node.row[step.fk];
      if (raw !== null && raw !== undefined && raw !== '') {
        values[step.fk] = String(raw);
        hidden.push(step.fk);
        break;
      }
    }
  }

  for (const optional of STRUCTURE_OPTIONAL[table] ?? []) {
    const ancestor = [...path].reverse().find((node) => node.table === optional.from);
    if (ancestor) {
      values[optional.fk] = String(ancestor.key);
      hidden.push(optional.fk);
    }
  }

  return { values, hidden };
}

/**
 * The label of a row, for the builder's list.
 *
 * The database already publishes a label expression for every editable table
 * through `admin_lookup_options`, so that is what is used first. A row whose
 * name is more useful than its label expression - the institution, whose
 * expression is its code - falls back to the name column, and anything still
 * unlabelled falls back to its key so no row is ever blank.
 */
export function rowLabel(
  row: Record<string, unknown>,
  pkCols: readonly string[],
  lookup: string | undefined,
): string {
  const nameKey = Object.keys(row).find((key) => key.endsWith('_name') && row[key]);
  if (nameKey) return String(row[nameKey]);

  if (lookup) return lookup;

  const key = pkCols.map((column) => String(row[column] ?? '')).filter(Boolean).join(' / ');
  return key || '—';
}

/** The secondary line of a row: its code, number or type, if it has one. */
export function rowDetail(row: Record<string, unknown>, primary: string): string | null {
  const parts = Object.keys(row)
    .filter((key) => /_(code|number|type)$/.test(key))
    .map((key) => String(row[key] ?? '').trim())
    .filter((value) => value && value !== primary);
  return parts.length > 0 ? parts.join(' · ') : null;
}
