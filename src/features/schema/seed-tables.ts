/**
 * The seeded lookup vocabulary of schema module 35.
 *
 * The MySQL source seeds these tables with the words the staff profile screens
 * pick their options from - publication types, statuses, levels, categories.
 * The application keeps the same vocabulary, but a table is not guaranteed to
 * be present in every database, so the list is read defensively: a table that
 * is missing is recorded and the page carries on without it.
 */

/** One seeded lookup table. */
export type SeedTable = {
  /** The table name, as the database spells it. */
  table: string;
  /** The primary key column. */
  idColumn: string;
  /** The columns that carry the label of the row. */
  labelColumns: string[];
};

/** The seeded tables, in the order the source seeds them. */
export const SEED_TABLES: SeedTable[] = [
  { table: 'publication_type', idColumn: 'publication_type_id', labelColumns: ['publication_type_code', 'publication_type_name'] },
  { table: 'journal_type', idColumn: 'journal_type_id', labelColumns: ['journal_type_code', 'journal_type_name'] },
  { table: 'indexing_agency', idColumn: 'indexing_agency_id', labelColumns: ['agency_code', 'agency_name'] },
  { table: 'metric_type', idColumn: 'metric_type_id', labelColumns: ['metric_code', 'metric_name'] },
  { table: 'funding_type', idColumn: 'funding_type_id', labelColumns: ['funding_type_code', 'funding_type_name'] },
  { table: 'funding_agency', idColumn: 'organization_id', labelColumns: ['agency_category'] },
  { table: 'activity_type', idColumn: 'activity_type_id', labelColumns: ['activity_type_code', 'activity_type_name', 'activity_group'] },
  { table: 'research_status', idColumn: 'research_status_id', labelColumns: ['status_code', 'status_name'] },
  { table: 'evidence_type', idColumn: 'evidence_type_id', labelColumns: ['evidence_type_code', 'evidence_type_name'] },
  { table: 'verification_status', idColumn: 'verification_status_id', labelColumns: ['status_code', 'status_name'] },
  { table: 'approval_status', idColumn: 'approval_status_id', labelColumns: ['status_code', 'status_name'] },
  { table: 'participation_level', idColumn: 'participation_level_id', labelColumns: ['level_code', 'level_name'] },
  { table: 'role_type', idColumn: 'role_type_id', labelColumns: ['role_code', 'role_name'] },
  { table: 'event_mode', idColumn: 'event_mode_id', labelColumns: ['mode_code', 'mode_name'] },
  { table: 'training_program_type', idColumn: 'training_program_type_id', labelColumns: ['type_code', 'type_name'] },
  {
    table: 'conference_contribution_type',
    idColumn: 'conference_contribution_type_id',
    labelColumns: ['type_code', 'type_name'],
  },
  { table: 'industry_sector', idColumn: 'industry_sector_id', labelColumns: ['sector_code', 'sector_name'] },
  { table: 'cocurricular_category', idColumn: 'cocurricular_category_id', labelColumns: ['category_code', 'category_name'] },
  {
    table: 'extracurricular_category',
    idColumn: 'extracurricular_category_id',
    labelColumns: ['category_code', 'category_name'],
  },
  { table: 'award_category', idColumn: 'award_category_id', labelColumns: ['category_code', 'category_name'] },
  { table: 'membership_type', idColumn: 'membership_type_id', labelColumns: ['type_code', 'type_name'] },
  {
    table: 'professional_contribution_type',
    idColumn: 'professional_contribution_type_id',
    labelColumns: ['contribution_code', 'contribution_name'],
  },
  { table: 'confidentiality_level', idColumn: 'confidentiality_level_id', labelColumns: ['level_code', 'level_name'] },
  {
    table: 'organization_type',
    idColumn: 'organization_type_id',
    labelColumns: ['organization_type_code', 'organization_type_name'],
  },
  { table: 'external_organization_type', idColumn: 'organization_id', labelColumns: ['organization_type_id'] },
  { table: 'organizer', idColumn: 'organizer_id', labelColumns: ['organization_id'] },
  { table: 'publisher', idColumn: 'publisher_id', labelColumns: ['organization_id'] },
];
