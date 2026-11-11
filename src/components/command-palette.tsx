'use client';

import { Search, UserRound } from 'lucide-react';
import { useRouter } from 'next/navigation';
import { useEffect, useMemo, useRef, useState } from 'react';
import { ICONS } from '@/components/nav-icons';
import { type NavGroup } from '@/lib/nav';
import { cn } from '@/lib/utils';

/**
 * Jump to any page: Ctrl-K (Cmd-K on a Mac), or the Search box in the header.
 *
 * The sidebar lists every group, but it is still fifty links to scan; this is
 * the fast path when you already know where you are going. Type a word from
 * the page's name ("fees", "audit", "21 ·"), or nothing at all to page
 * through everything the caller may see. The last row always offers the full
 * search page, which searches data rather than navigation.
 */
type Entry = {
  href: string;
  label: string;
  /** Where it lives, for the muted text on the right: its group's label. */
  context: string;
  /** Extra words that should match, but not be shown. */
  haystack: string;
};

/** How many results are shown; arrow keys and typing narrow it anyway. */
const MAX_RESULTS = 9;

function buildEntries(groups: NavGroup[]): Entry[] {
  const out: Entry[] = [];
  for (const group of groups) {
    for (const item of [...group.items, ...(group.children ?? [])]) {
      out.push({
        href: item.href,
        label: item.label,
        context: group.label,
        haystack: `${item.label} ${group.label} ${item.href}`.toLowerCase(),
      });
    }
  }
  return out;
}

export function CommandPalette({ groups, onClose }: { groups: NavGroup[]; onClose: () => void }) {
  const router = useRouter();
  const inputRef = useRef<HTMLInputElement>(null);
  const [query, setQuery] = useState('');
  const [cursor, setCursor] = useState(0);

  const entries = useMemo(() => buildEntries(groups), [groups]);

  // Mounted only while open, so the box starts empty and the cursor on row
  // one every time. Focus lands in the input and goes back where it came from
  // when the palette closes.
  useEffect(() => {
    const previous = document.activeElement as HTMLElement | null;
    inputRef.current?.focus();
    return () => previous?.focus?.();
  }, []);

  // Escape closes it wherever focus is: the input, a result, or nowhere.
  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') {
        event.preventDefault();
        onClose();
      }
    }
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [onClose]);

  const results = useMemo(() => {
    const q = query.trim().toLowerCase();
    const matches = q
      ? entries
          .filter((e) => e.haystack.includes(q))
          .sort((a, b) => {
            // A page whose own name starts with what you typed beats one that
            // only mentions it in its group; otherwise keep the sidebar order.
            const score = (e: Entry) => {
              const label = e.label.toLowerCase();
              if (label.startsWith(q)) return 0;
              if (label.includes(q)) return 1;
              return 2;
            };
            return score(a) - score(b);
          })
      : entries;

    const list = matches.slice(0, MAX_RESULTS);
    if (q) {
      list.push({
        href: `/search?q=${encodeURIComponent(query.trim())}`,
        label: `Search for “${query.trim()}”`,
        context: 'Every page and record',
        haystack: '',
      });
    }
    return list;
  }, [entries, query]);

  function go(index: number) {
    const entry = results[index];
    if (!entry) return;
    onClose();
    router.push(entry.href);
  }

  function onKeyDown(event: React.KeyboardEvent<HTMLInputElement>) {
    if (event.key === 'ArrowDown') {
      event.preventDefault();
      setCursor((c) => (results.length === 0 ? 0 : (c + 1) % results.length));
    } else if (event.key === 'ArrowUp') {
      event.preventDefault();
      setCursor((c) => (results.length === 0 ? 0 : (c - 1 + results.length) % results.length));
    } else if (event.key === 'Enter') {
      event.preventDefault();
      go(cursor);
    } else if (event.key === 'Tab') {
      // The input keeps focus: arrows and Enter do everything a Tab would.
      event.preventDefault();
    }
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center bg-black/40 p-4 pt-[12vh]"
      onMouseDown={onClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-label="Jump to a page"
        onMouseDown={(event) => event.stopPropagation()}
        className="w-full max-w-lg overflow-hidden rounded-lg border border-border bg-card shadow-lg"
      >
        <div className="flex items-center gap-2 border-b border-border px-3">
          <Search className="h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />
          <input
            ref={inputRef}
            value={query}
            onChange={(event) => {
              setQuery(event.target.value);
              setCursor(0);
            }}
            onKeyDown={onKeyDown}
            placeholder="Jump to a page…"
            aria-label="Jump to a page"
            role="combobox"
            aria-expanded
            aria-controls="command-palette-results"
            aria-activedescendant={results[cursor] ? `command-palette-result-${cursor}` : undefined}
            className="h-11 w-full bg-transparent text-sm outline-none placeholder:text-muted-foreground"
          />
          <kbd className="shrink-0 rounded border border-border bg-muted px-1.5 text-[11px] font-medium text-muted-foreground">
            Esc
          </kbd>
        </div>

        <ul
          id="command-palette-results"
          role="listbox"
          aria-label="Results"
          className="max-h-72 overflow-y-auto p-1.5"
        >
          {results.length === 0 ? (
            <li className="px-3 py-6 text-center text-sm text-muted-foreground">
              No page matches “{query.trim()}”.
            </li>
          ) : null}
          {results.map((entry, index) => {
            const Icon = ICONS[entry.href] ?? (entry.haystack === '' ? Search : UserRound);
            return (
              <li
                key={`${entry.href}-${index}`}
                id={`command-palette-result-${index}`}
                role="option"
                aria-selected={index === cursor}
                onMouseEnter={() => setCursor(index)}
                // Keep focus on the input so Enter still drives the list.
                onMouseDown={(event) => event.preventDefault()}
                onClick={() => go(index)}
                className={cn(
                  'flex cursor-pointer items-center gap-3 rounded-md px-3 py-2 text-sm',
                  index === cursor && 'bg-muted',
                )}
              >
                <Icon className="h-4 w-4 shrink-0 text-muted-foreground" aria-hidden />
                <span className="truncate">{entry.label}</span>
                <span className="ml-auto shrink-0 truncate pl-3 text-xs text-muted-foreground">
                  {entry.context}
                </span>
              </li>
            );
          })}
        </ul>

        <div className="border-t border-border px-3 py-2 text-[11px] text-muted-foreground">
          ↑ ↓ to move · Enter to open · Esc to close
        </div>
      </div>
    </div>
  );
}
