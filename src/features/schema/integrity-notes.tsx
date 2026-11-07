'use client';

/** One of the fourteen integrity notes of schema module 39. */
export type IntegrityNote = {
  /** The note number, as the schema source numbers it. */
  number: number;
  /** A short heading for the note. */
  heading: string;
  /** The note itself, transcribed from the schema source. */
  text: string;
};

/**
 * The integrity rules the service layer enforces.
 *
 * The schema source writes these as a numbered list of plain English rules.
 * They are not database constraints - a trigger or a check constraint cannot
 * look at a file's content or ask whether a campus matches an assignment that
 * was valid on the day - so the application enforces them through the
 * functions it exposes.
 */
export const INTEGRITY_NOTES: IntegrityNote[] = [
  {
    number: 1,
    heading: 'One child table per activity',
    text: 'Exactly one specialized child table should exist for each staff_activity, matching activity_type.activity_group/activity_type_code.',
  },
  {
    number: 2,
    heading: 'The employee must be in scope',
    text: 'staff_activity.employee_id must be within the authorized RBAC row scope.',
  },
  {
    number: 3,
    heading: 'The location follows the assignment',
    text: 'campus_id and department_id should match the employee assignment valid for the activity date when the institution requires historical accuracy.',
  },
  {
    number: 4,
    heading: 'Only the allowed file types',
    text: 'Only allowed MIME types/extensions should be accepted: PDF, JPG/JPEG, PNG, DOC/DOCX, XLS/XLSX, PPT/PPTX, ZIP.',
  },
  {
    number: 5,
    heading: 'Trust the content, not the extension',
    text: 'Validate MIME type from file content; do not trust extension alone.',
  },
  {
    number: 6,
    heading: 'No executables, and scan every upload',
    text: 'Restrict executable/script formats and scan uploads for malware.',
  },
  {
    number: 7,
    heading: 'Confidential files stay private',
    text: 'For confidential evidence, storage objects should be private and accessed through authorization-checked signed/temporary URLs.',
  },
  {
    number: 8,
    heading: 'Replacement creates a new version',
    text: 'Replacement should create a new evidence_document_version; do not overwrite prior file_object records when version retention is required.',
  },
  {
    number: 9,
    heading: 'One current version per document',
    text: 'Exactly one version should have is_current=TRUE for each evidence document.',
  },
  {
    number: 10,
    heading: 'Verification and approval are audited',
    text: 'Verification and approval actions should append evidence_document_audit rows and the existing activity_audit log.',
  },
  {
    number: 11,
    heading: 'Soft deletion is the normal path',
    text: 'Soft deletion should be the normal delete path for staff_activity and evidence_document. Hard deletion should be restricted to privileged admins.',
  },
  {
    number: 12,
    heading: 'Identifiers are format checked',
    text: 'DOI, ISSN, ISBN, membership numbers, sanction/order numbers and certificate numbers should receive format validation appropriate to their issuing source.',
  },
  {
    number: 13,
    heading: 'Research amounts are reconciled',
    text: 'Sanctioned/received/utilized research amounts should be reconciled by service logic and financial reports.',
  },
  {
    number: 14,
    heading: 'Search enforces confidentiality',
    text: 'Search results must enforce confidentiality and row-level RBAC before exposing evidence metadata or file download URLs.',
  },
];

/**
 * The fourteen integrity notes, as a numbered list.
 *
 * The rules are enforced in the service layer rather than by the database: a
 * constraint cannot read a file's content, ask whether a campus matches the
 * assignment that was valid on the day, or decide what a search may show. The
 * application enforces them through the functions it exposes, and the database
 * enforces what it can around them.
 */
export function IntegrityNotes() {
  return (
    <div className="space-y-4">
      <p className="rounded-lg border border-border bg-muted/40 p-4 text-sm text-muted-foreground">
        These rules are enforced in the service layer, not by the database. A constraint cannot read a file&apos;s
        content or ask whether a campus matches the assignment that was valid on the day, so the application enforces
        them through the RPCs it exposes, and the database enforces what it can around them.
      </p>

      <ol className="space-y-3">
        {INTEGRITY_NOTES.map((note) => (
          <li key={note.number} className="rounded-lg border border-border bg-card p-4">
            <div className="flex items-start gap-3">
              <span className="mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-primary text-xs font-semibold text-primary-foreground">
                {note.number}
              </span>
              <div>
                <p className="text-sm font-semibold">{note.heading}</p>
                <p className="mt-1 text-sm text-muted-foreground">{note.text}</p>
              </div>
            </div>
          </li>
        ))}
      </ol>
    </div>
  );
}
