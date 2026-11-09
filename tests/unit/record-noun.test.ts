import { describe, expect, it } from 'vitest';
import { recordNoun, recordNounTitle } from '@/features/shared/record-noun';

/**
 * The wording of the editors comes from the catalogue's own labels, so these
 * are the real labels of migrations 067 and 068 - the controls are only as
 * good as the singularisation behind them.
 */
describe('recordNoun', () => {
  it('names one record of a plural label', () => {
    expect(recordNoun('Academic years')).toBe('academic year');
    expect(recordNoun('Buildings')).toBe('building');
    expect(recordNoun('Facility types')).toBe('facility type');
    expect(recordNoun('Programme enrolments')).toBe('programme enrolment');
    expect(recordNoun('Land parcels')).toBe('land parcel');
    expect(recordNoun('Term schedules')).toBe('term schedule');
    expect(recordNoun('Payment modes')).toBe('payment mode');
    expect(recordNoun('Late-fee rules')).toBe('late-fee rule');
    expect(recordNoun('Teaching time slots')).toBe('teaching time slot');
    expect(recordNoun('Ledger accounts')).toBe('ledger account');
    expect(recordNoun('Student exit records')).toBe('student exit record');
    expect(recordNoun('Section student allocations')).toBe('section student allocation');
    expect(recordNoun('Feedback questionnaires')).toBe('feedback questionnaire');
  });

  it('handles the plurals that do not simply drop the "s"', () => {
    expect(recordNoun('Campuses')).toBe('campus');
    expect(recordNoun('Approval statuses')).toBe('approval status');
    expect(recordNoun('Courses')).toBe('course');
    expect(recordNoun('Addresses')).toBe('address');
    expect(recordNoun('Social categories')).toBe('social category');
    expect(recordNoun('Indexing agencies')).toBe('indexing agency');
    expect(recordNoun('Awarding bodies')).toBe('awarding body');
    expect(recordNoun('Universities')).toBe('university');
    expect(recordNoun('Employee competencies')).toBe('employee competency');
    expect(recordNoun('Sub-castes')).toBe('sub-caste');
    expect(recordNoun('Student residences')).toBe('student residence');
    expect(recordNoun('Payment modes')).toBe('payment mode');
  });

  it('leaves a label that already names one record alone', () => {
    expect(recordNoun('Residence')).toBe('residence');
    expect(recordNoun('Research supervision')).toBe('research supervision');
    expect(recordNoun('Financial utilisation')).toBe('financial utilisation');
    expect(recordNoun('Previous employment')).toBe('previous employment');
    expect(recordNoun('Enrolment status history')).toBe('enrolment status history');
    expect(recordNoun('Employee previous employment')).toBe('employee previous employment');
  });

  it('keeps a compound label in the plural', () => {
    expect(recordNoun('Parents and guardians')).toBe('parents and guardians');
    expect(recordNoun('Student parents and guardians')).toBe('student parents and guardians');
  });

  it('keeps the capital inside a name', () => {
    expect(recordNoun('Employee PAN records')).toBe('employee PAN record');
    expect(recordNoun('Employee Aadhaar records')).toBe('employee Aadhaar record');
  });

  it('returns an empty label unchanged', () => {
    expect(recordNoun('')).toBe('');
    expect(recordNoun('   ')).toBe('');
  });
});

describe('recordNounTitle', () => {
  it('starts a notice with a capital', () => {
    expect(recordNounTitle('Academic years')).toBe('Academic year');
    expect(recordNounTitle('Addresses')).toBe('Address');
    expect(recordNounTitle('Residence')).toBe('Residence');
    expect(recordNounTitle('Parents and guardians')).toBe('Parents and guardians');
    expect(recordNounTitle('Employee PAN records')).toBe('Employee PAN record');
  });
});
