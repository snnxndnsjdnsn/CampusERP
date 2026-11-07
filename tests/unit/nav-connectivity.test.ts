import fs from 'node:fs';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { ICONS } from '@/components/app-shell';
import { NAV_GROUPS, NAV_ITEMS } from '@/lib/nav';
import { STAFF_SECTIONS } from '@/lib/staff-sections';

/**
 * Proves navigation ↔ database ↔ routes stay wired together:
 * every sidebar link points at a real page, a real access_module row, and a real icon,
 * and the group order stays locked to the schema's numbered module structure.
 */

const APP_DIR = path.resolve(__dirname, '../../src/app/(app)');
const MIGRATIONS_DIR = path.resolve(__dirname, '../../supabase/migrations');

/** Distinct access_module codes referenced anywhere in the navigation. */
const navModules: string[] = [
  ...new Set(
    NAV_GROUPS.flatMap((g) => g.items).flatMap((i) =>
      !i.module ? [] : Array.isArray(i.module) ? i.module : [i.module],
    ),
  ),
].sort();

/**
 * Module codes seeded by `INSERT INTO access_module (...) VALUES (...);` across all migrations.
 *
 * The parser is deliberately tolerant: the schema qualifier is optional, the
 * column list is read so the code is taken from the right position, and tuples
 * are split on top-level commas only (so a quoted name containing a comma
 * cannot shift the columns).
 */
function seededModuleCodes(): Set<string> {
  const codes = new Set<string>();

  for (const file of fs.readdirSync(MIGRATIONS_DIR).filter((f) => f.endsWith('.sql'))) {
    const sql = fs.readFileSync(path.join(MIGRATIONS_DIR, file), 'utf8');
    const statements = sql.match(/INSERT\s+INTO\s+(?:public\.)?access_module\b[\s\S]*?;/gi) ?? [];

    for (const stmt of statements) {
      const columnsMatch = stmt.match(/\(([^)]*)\)\s*VALUES/i);
      if (!columnsMatch) continue;
      const columns = (columnsMatch[1] ?? '')
        .split(',')
        .map((c) => c.trim().replace(/^public\./, '').toLowerCase());
      const codeIndex = columns.indexOf('module_code');
      if (codeIndex < 0) continue;

      const valuesAt = stmt.toUpperCase().indexOf('VALUES');
      if (valuesAt < 0) continue;
      const valuesPart = stmt.slice(valuesAt + 'VALUES'.length);
      for (const tuple of splitTopLevelTuples(valuesPart)) {
        const fields = splitTopLevel(tuple);
        const code = fields[codeIndex]?.trim().replace(/^'|'$/g, '');
        if (code) codes.add(code);
      }
    }
  }

  return codes;
}

/** Split a VALUES body into its parenthesised tuples. */
function splitTopLevelTuples(text: string): string[] {
  const tuples: string[] = [];
  let depth = 0;
  let start = -1;
  let inString = false;

  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];
    if (inString) {
      if (ch === "'") {
        if (text[i + 1] === "'") i += 1;
        else inString = false;
      }
      continue;
    }
    if (ch === "'") {
      inString = true;
      continue;
    }
    if (ch === '(') {
      if (depth === 0) start = i + 1;
      depth += 1;
    } else if (ch === ')') {
      depth -= 1;
      if (depth === 0 && start >= 0) {
        tuples.push(text.slice(start, i));
        start = -1;
      }
    }
  }

  return tuples;
}

/** Split one tuple on commas that are not inside a string literal. */
function splitTopLevel(text: string): string[] {
  const parts: string[] = [];
  let current = '';
  let inString = false;

  for (let i = 0; i < text.length; i += 1) {
    const ch = text[i];
    if (inString) {
      current += ch;
      if (ch === "'") {
        if (text[i + 1] === "'") {
          current += text[i + 1];
          i += 1;
        } else {
          inString = false;
        }
      }
      continue;
    }
    if (ch === "'") {
      inString = true;
      current += ch;
      continue;
    }
    if (ch === ',') {
      parts.push(current);
      current = '';
      continue;
    }
    current += ch;
  }

  parts.push(current);
  return parts;
}

/**
 * Does a nav href resolve to a real page?
 *
 * A href may end in a dynamic segment - `/staff-profile/publication` is served
 * by `src/app/(app)/staff-profile/[section]/page.tsx` - so a literal folder is
 * not enough. The walk follows the address one segment at a time, preferring a
 * literal folder and falling back to a `[param]` one, and the last folder must
 * hold a `page.tsx`.
 */
function routeExists(href: string): boolean {
  const segments = href.replace(/^\//, '').split('/').filter(Boolean);

  const walk = (dir: string, index: number): boolean => {
    if (index === segments.length) return fs.existsSync(path.join(dir, 'page.tsx'));

    const segment = segments[index];
    if (segment === undefined) return false;

    const candidates: string[] = [];

    const literal = path.join(dir, segment);
    if (fs.existsSync(literal) && fs.statSync(literal).isDirectory()) candidates.push(literal);

    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (entry.isDirectory() && entry.name.startsWith('[')) candidates.push(path.join(dir, entry.name));
    }

    return candidates.some((candidate) => walk(candidate, index + 1));
  };

  return walk(APP_DIR, 0);
}

describe('navigation connectivity', () => {
  it('every nav href resolves to an existing app route', () => {
    const broken = NAV_ITEMS.filter((i) => !routeExists(i.href)).map(
      (i) => `${i.href} -> src/app/(app)${i.href}/page.tsx`,
    );
    expect(broken, `nav hrefs without a page.tsx:\n${broken.join('\n')}`).toEqual([]);
  });

  it('every nav module is seeded as an access_module row', () => {
    const seeded = seededModuleCodes();
    expect(seeded.size, 'no INSERT INTO access_module statements found in migrations').toBeGreaterThan(0);
    const missing = navModules.filter((m) => !seeded.has(m));
    expect(missing, `nav modules with no seeded access_module row: ${missing.join(', ')}`).toEqual([]);
  });

  it('every seeded access_module is used by navigation or explicitly allowlisted', () => {
    // Allowlist of seeded-but-unused codes:
    // - TEACHING: its screens live inside the registration/attendance detail flows, not a page of their own.
    // - REPORTING: no dedicated screen yet.
    // - COMMUNICATION: the announcement feed is intentionally ungated (see the 'communication' group).
    const allowlist = new Set(['TEACHING', 'REPORTING', 'COMMUNICATION']);
    const unused = [...seededModuleCodes()].filter((c) => !navModules.includes(c) && !allowlist.has(c)).sort();
    expect(unused, `seeded access_module codes missing from navigation: ${unused.join(', ')}`).toEqual([]);
  });

  it('every nav href has a sidebar icon', () => {
    const missing = NAV_ITEMS.map((i) => i.href).filter((h) => !ICONS[h]);
    expect(missing, `ICONS entries missing for: ${missing.join(', ')}`).toEqual([]);
  });

  it('the staff group carries every research sub-module, 20 to 34', () => {
    const staff = NAV_GROUPS.find((g) => g.id === 'staff');
    expect(staff, 'the staff group is missing').toBeDefined();

    const children = staff?.children ?? [];
    expect(children.map((c) => c.href)).toEqual(STAFF_SECTIONS.map((s) => `/staff-profile/${s.slug}`));

    // The module number is the first thing the label says, so the sidebar
    // shows the schema's numbering and not just a screen name.
    const numbers = children.map((c) => c.label.split(' · ')[0]);
    expect(numbers).toEqual(['20', '21', '22', '23', '24', '25', '26', '27', '28', '29', '30', '31', '32', '33', '34']);

    // Every sub-module is gated by the same access module as its screen.
    expect(children.every((c) => c.module === 'STAFF_PROFILE')).toBe(true);
  });

  it('every staff sub-module address is a known section', () => {
    const children = NAV_GROUPS.find((g) => g.id === 'staff')?.children ?? [];
    const unknown = children
      .map((c) => c.href.replace('/staff-profile/', ''))
      .filter((slug) => !STAFF_SECTIONS.some((s) => s.slug === slug));
    expect(unknown, `staff sub-module addresses with no section: ${unknown.join(', ')}`).toEqual([]);
  });

  it('an address that no route serves is rejected', () => {
    expect(routeExists('/definitely/not/a/route')).toBe(false);
    expect(routeExists('/staff-profile')).toBe(true);
    expect(routeExists('/staff-profile/publication')).toBe(true);
  });

  it('NAV_GROUPS stay in the canonical database module order', () => {
    expect(NAV_GROUPS.map((g) => g.id)).toEqual([
      'overview',
      'reference', // 1 · Common reference
      'institution', // 2
      'calendar', // 3
      'curriculum', // 4
      'people', // 5
      'admission', // 6
      'registration', // 7
      'teaching', // 8
      'attendance', // 9
      'assessment', // 10
      'feedback', // 11
      'support', // 12
      'documents', // 13
      'communication', // 14
      'iam', // 15
      'hr', // 16
      'finance', // 17
      'staff', // 19 · Staff profile (schema modules 20–34 are its research sub-modules, drawn as children)
      'activities', // 40
      'account',
    ]);
  });
});
