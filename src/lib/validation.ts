import { z } from 'zod';

/**
 * Input validation for every form and query string in the application.
 *
 * The rules here are the first line of defence, not the last: the database still
 * enforces every constraint. What validation buys us is a clear rejection message
 * instead of a database error, and the guarantee that a user-supplied string can
 * never be interpreted as a filter or a query fragment.
 */

/**
 * Characters that are significant in filters, wildcards, quoting or statement
 * termination. They are stripped from any free-text search term.
 */
const SEARCH_STRIP = /[,()%*"\\';]/g;

/** Maximum length of a search term. */
export const SEARCH_MAX_LENGTH = 80;

/**
 * Strip filter-significant characters from a search term and cap its length.
 *
 * `a,b)(c%d*e"f\g` becomes `abcdefg`; `x'; drop table student;--` becomes
 * `x drop table student--`. Letters, digits, spaces and dashes survive.
 */
export function sanitizeSearch(value: string | null | undefined): string {
  if (!value) return '';
  return value.replace(SEARCH_STRIP, '').slice(0, SEARCH_MAX_LENGTH);
}

export const loginSchema = z.object({
  email: z.email('Enter a valid email address'),
  password: z.string().min(1, 'Enter your password'),
});

export const forgotSchema = z.object({
  email: z.email('Enter a valid email address'),
});

/**
 * A new password needs at least 10 characters with an upper-case letter, a
 * lower-case letter and a digit, and the confirmation must match.
 */
export const newPasswordSchema = z
  .object({
    password: z
      .string()
      .min(10, 'Use at least 10 characters')
      .regex(/[A-Z]/, 'Include an upper-case letter')
      .regex(/[a-z]/, 'Include a lower-case letter')
      .regex(/[0-9]/, 'Include a digit'),
    confirm: z.string().min(1, 'Repeat the new password'),
  })
  .refine((v) => v.password === v.confirm, { message: 'The passwords do not match', path: ['confirm'] });

/** Columns a student list may be sorted by. Never include sensitive columns. */
export const STUDENT_SORT_COLUMNS = [
  'display_name',
  'student_number',
  'first_name',
  'last_name',
  'admission_date',
  'created_at',
] as const;

/**
 * Query parameters for the student list screen.
 *
 * Every field falls back to a safe default instead of failing, so a hand-edited
 * URL can never make the page error or select a column that should not be exposed.
 */
export const studentListParams = z.object({
  page: z.coerce.number().int().min(1).catch(1),
  sort: z.enum(STUDENT_SORT_COLUMNS).catch('display_name'),
  dir: z.enum(['asc', 'desc']).catch('asc'),
  q: z
    .string()
    .optional()
    .transform((v) => sanitizeSearch(v))
    .catch(''),
});

export type StudentListParams = z.infer<typeof studentListParams>;
