/**
 * The schema modules that have a screen of their own.
 *
 * The sidebar follows the numbered module structure of
 * `SIMS-DatabaseWithoutLessonPlan.sql`. Modules 18, 35, 36, 38 and 39 describe
 * the database itself - its indexes, its seed vocabulary, its access
 * registration, its integrity rules - rather than a business area, so they all
 * live behind one dynamic route (`/schema/[module]`) and share one screen.
 */

/** One module of the schema that has an address under `/schema`. */
export type SchemaModule = {
  /** The schema module number, as the MySQL source numbers it. */
  module: string;
  /** The module title, as the source writes it. */
  title: string;
  /** One line saying what the screen shows. */
  description: string;
  /**
   * The `access_module` code(s) that gate the screen.
   *
   * They are the codes the sidebar uses to decide whether the entry is shown
   * and the codes the read functions check before they hand the data over, so
   * the screen and the navigation always agree about who may see what. An
   * array means the caller needs to read **any** of them, which is the same
   * rule the navigation uses.
   */
  accessModules: string[];
};

/** The modules, in schema module order. */
export const SCHEMA_MODULES: SchemaModule[] = [
  {
    module: '18',
    title: 'Performance indexes and file storage',
    description:
      'The index catalogue of the live database, and the metadata of the file storage table that module 18 extends.',
    accessModules: ['IAM'],
  },
  {
    module: '35',
    title: 'Seed reference data',
    description:
      'The lookup vocabulary the staff profile screens pick their options from, table by table.',
    accessModules: ['IAM', 'STAFF_PROFILE'],
  },
  {
    module: '36',
    title: 'RBAC registration for staff profile and evidence',
    description:
      'The access module, its resources, its permissions and the roles that hold them.',
    accessModules: ['IAM'],
  },
  {
    module: '38',
    title: 'Performance indexes (staff profile)',
    description:
      'The index catalogue of the tables that carry a staff profile row-level security policy.',
    accessModules: ['STAFF_PROFILE', 'IAM'],
  },
  {
    module: '39',
    title: 'Data-integrity notes enforced at application/service layer',
    description:
      'The fourteen rules the service layer enforces because the database itself cannot.',
    accessModules: ['IAM', 'AUDIT'],
  },
];

/** The module behind an address segment, if there is one. */
export function schemaModule(slug: string): SchemaModule | undefined {
  return SCHEMA_MODULES.find((m) => m.module === slug);
}
