/**
 * The name of one record, for buttons, headings and notices.
 *
 * The catalogue labels a table by its rows - "Academic years", "Buildings" -
 * because that is what a table header wants. The controls that act on those
 * rows talk about a single record: "Add academic year" says what it does,
 * "Add row" says nothing at all. Every editor derives its wording from the
 * same label, so a table the database adds later gets the right wording
 * without anyone editing the screens.
 */

/** Plurals that do not end in a simple "-s". */
const INVARIANT = new Set(['series', 'species', 'premises']);

/** Singularise one word of a label: "years" -> "year", "campuses" -> "campus". */
function singularWord(word: string): string {
  const lower = word.toLowerCase();
  if (INVARIANT.has(lower)) return word;

  // "facilities" -> "facility", "categories" -> "category"
  if (word.length > 3 && /[^aeiou]ies$/i.test(word)) return `${word.slice(0, -3)}y`;
  // "addresses" -> "address", "boxes" -> "box", "batches" -> "batch"
  if (/(sses|shes|ches|xes|zes)$/i.test(word)) return word.slice(0, -2);
  // The Latin plurals: "statuses" -> "status", "campuses" -> "campus"
  if (/uses$/i.test(word)) return word.slice(0, -2);
  // "courses" -> "course": here the trailing "e" belongs to the singular
  if (/ses$/i.test(word)) return word.slice(0, -1);
  // "buildings" -> "building"; "class", "status" and "analysis" keep their "s"
  if (/s$/i.test(word) && !/(ss|us|is)$/i.test(word)) return word.slice(0, -1);

  return word;
}

/**
 * The singular, sentence-case name of the records a table holds.
 *
 * A compound label ("Parents and guardians") names several kinds of record at
 * once, so singularising it would read as nonsense - it is only lower-cased.
 */
export function recordNoun(label: string): string {
  const trimmed = label.trim();
  if (!trimmed) return trimmed;

  const phrase = trimmed.includes(' and ')
    ? trimmed
    : trimmed
        .split(/\s+/)
        .map(singularWord)
        .join(' ');

  return phrase.charAt(0).toLowerCase() + phrase.slice(1);
}

/** The same name with a capital letter, for the start of a notice. */
export function recordNounTitle(label: string): string {
  const noun = recordNoun(label);
  return noun.charAt(0).toUpperCase() + noun.slice(1);
}
