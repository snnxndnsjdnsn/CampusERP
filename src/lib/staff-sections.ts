/**
 * The staff-profile research sub-modules - schema modules 20 to 34.
 *
 * The MySQL source gives each of them its own tables (`journal`,
 * `conference_event`, `faculty_internship`, `research_proposal`,
 * `funded_research_project`, `consultancy_project`, `cocurricular_activity`,
 * `extracurricular_activity`, `staff_award`,
 * `staff_professional_membership`, `staff_professional_contribution`,
 * `evidence_document`, `activity_evidence_requirement` and the rest), but the
 * application models them as one screen: `staff_activity` is a supertype and
 * `activity_type` says which specialised child table a row belongs to.
 *
 * So the sub-modules are **sections of one screen**, not separate screens.
 * Each one gets its own address under `/staff-profile` and opens the screen
 * filtered to its `activity_group`.
 *
 * Two pairs are coarser than the schema:
 *
 *  - modules 25 and 26 (research proposals, funded research projects) share
 *    the `RESEARCH` group, so both open the same filtered list;
 *  - modules 33 and 34 (evidence, and the evidence requirements) are edited
 *    inside the activity form, so they open the screen unfiltered.
 *
 * The screen's own filter dropdown is the finer instrument in both cases.
 */

export type StaffSection = {
  /** The address segment under `/staff-profile`. */
  slug: string;
  /** The schema module number this section stands for. */
  module: string;
  /** The module title, as the MySQL source writes it. */
  title: string;
  /**
   * The `activity_type.activity_group` to filter by. Empty means the screen
   * opens unfiltered.
   */
  group: string;
};

/** The sections, in schema module order. */
export const STAFF_SECTIONS: StaffSection[] = [
  { slug: 'activity', module: '20', title: 'Staff activity supertype', group: '' },
  { slug: 'publication', module: '21', title: 'Journals and journal publications', group: 'PUBLICATION' },
  {
    slug: 'conference',
    module: '22',
    title: 'Conferences, publications and presentations',
    group: 'CONFERENCE',
  },
  {
    slug: 'development',
    module: '23',
    title: 'Workshop / FDP / STTP / training / certification',
    group: 'PROFESSIONAL_DEVELOPMENT',
  },
  { slug: 'internship', module: '24', title: 'Industry / faculty internship', group: 'INTERNSHIP' },
  { slug: 'research', module: '25', title: 'Research proposals', group: 'RESEARCH' },
  { slug: 'funded-research', module: '26', title: 'Funded research projects', group: 'RESEARCH' },
  {
    slug: 'consultancy',
    module: '27',
    title: 'Consultancy / industry-sponsored project',
    group: 'CONSULTANCY',
  },
  { slug: 'co-curricular', module: '28', title: 'Co-curricular activities', group: 'CO_CURRICULAR' },
  {
    slug: 'extra-curricular',
    module: '29',
    title: 'Extra-curricular activities',
    group: 'EXTRA_CURRICULAR',
  },
  { slug: 'award', module: '30', title: 'Awards, honours and recognitions', group: 'AWARD' },
  {
    slug: 'membership',
    module: '31',
    title: 'Professional memberships and academic bodies',
    group: 'MEMBERSHIP',
  },
  {
    slug: 'contribution',
    module: '32',
    title: 'Academic and professional contributions',
    group: 'ACADEMIC_PROFESSIONAL_CONTRIBUTION',
  },
  {
    slug: 'evidence',
    module: '33',
    title: 'Centralized evidence / document management',
    group: '',
  },
  {
    slug: 'evidence-requirements',
    module: '34',
    title: 'Document/evidence requirement configuration',
    group: '',
  },
];

/** The section behind an address segment, if there is one. */
export function staffSection(slug: string): StaffSection | undefined {
  return STAFF_SECTIONS.find((s) => s.slug === slug);
}
