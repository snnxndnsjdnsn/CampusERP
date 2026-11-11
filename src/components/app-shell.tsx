'use client';

import { Bell, ChevronRight, LogOut, Menu, Search, UserRound, X } from 'lucide-react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useEffect, useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import { CommandPalette } from '@/components/command-palette';
import { ICONS } from '@/components/nav-icons';
import { NAV_PARENTS, type NavGroup, type NavItem } from '@/lib/nav';
import { cn } from '@/lib/utils';

// The icon of every address, re-exported from its own module so the shell and
// the palette can both use it without importing each other. The unit test has
// always found it here.
export { ICONS } from '@/components/nav-icons';

/**
 * The nav item the current address belongs to.
 *
 * The deepest match wins: `/staff-profile/publication` belongs to the
 * sub-module, not to `/staff-profile`, and `/admin/users/new` belongs to the
 * new-user page, not to `/admin/users`.
 */
function activeItem(pathname: string, groups: NavGroup[]): NavItem | undefined {
  return groups
    .flatMap((g) => [...g.items, ...(g.children ?? [])])
    .filter((i) => pathname === i.href || pathname.startsWith(i.href + '/'))
    .sort((a, b) => b.href.length - a.href.length)[0];
}

function Breadcrumbs({ groups }: { groups: NavGroup[] }) {
  const pathname = usePathname();
  const items = groups.flatMap((g) => [...g.items, ...(g.children ?? [])]);
  // The deepest match wins, so a sub-module gets its own crumb rather than
  // its parent's.
  let current = activeItem(pathname, groups);
  if (!current) {
    // breadcrumb-only fallback for routes without their own nav item (e.g. /admin/mfa-policy)
    const parent = NAV_PARENTS[pathname] ??
      Object.keys(NAV_PARENTS)
        .filter((k) => pathname.startsWith(k + '/'))
        .sort((a, b) => b.length - a.length)[0];
    if (parent) current = items.find((i) => i.href === parent);
  }
  const detail = current && pathname !== current.href;
  return (
    <nav aria-label="Breadcrumb" className="flex items-center gap-1 text-sm text-muted-foreground">
      <span>SIMS</span>
      {current && (
        <>
          <ChevronRight className="h-4 w-4" aria-hidden />
          {detail ? (
            <Link href={current.href} className="hover:underline">
              {current.label}
            </Link>
          ) : (
            <span aria-current="page" className="text-foreground">
              {current.label}
            </span>
          )}
        </>
      )}
      {detail && (
        <>
          <ChevronRight className="h-4 w-4" aria-hidden />
          <span aria-current="page" className="text-foreground">
            Details
          </span>
        </>
      )}
    </nav>
  );
}

/**
 * Every group, every link, drawn straight from `NAV_GROUPS` - nothing is
 * collapsed away. The same list serves the desktop sidebar and the mobile
 * drawer; `onNavigate` lets an overlay hosting it close once a link is
 * followed.
 */
function SidebarNav({
  groups,
  current,
  onNavigate,
}: {
  groups: NavGroup[];
  current?: string;
  onNavigate?: () => void;
}) {
  const active = (href: string) => href === current;
  return (
    <>
      {groups.map((group) => (
        <div key={group.id}>
          <div className="px-3 pt-4 pb-1 text-[11px] font-medium uppercase tracking-wide text-muted-foreground">{group.label}</div>
          <div className="space-y-1">
            {group.items.map((item) => {
              const Icon = ICONS[item.href] ?? UserRound;
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  onClick={onNavigate}
                  aria-current={active(item.href) ? 'page' : undefined}
                  className={cn(
                    'flex items-center gap-3 rounded-md px-3 py-2 text-sm hover:bg-muted',
                    active(item.href) && 'bg-muted font-medium text-primary',
                  )}
                >
                  <Icon className="h-4 w-4" aria-hidden />
                  {item.label}
                </Link>
              );
            })}
            {group.children?.map((item) => {
              const Icon = ICONS[item.href] ?? UserRound;
              return (
                <Link
                  key={item.href}
                  href={item.href}
                  onClick={onNavigate}
                  aria-current={active(item.href) ? 'page' : undefined}
                  className={cn(
                    'flex items-center gap-3 rounded-md py-1.5 pl-6 pr-3 text-[13px] hover:bg-muted',
                    active(item.href) && 'bg-muted font-medium text-primary',
                  )}
                >
                  <Icon className="h-3.5 w-3.5 shrink-0" aria-hidden />
                  {item.label}
                </Link>
              );
            })}
          </div>
        </div>
      ))}
    </>
  );
}

/**
 * The frame every signed-in screen is drawn in.
 *
 * The sidebar is the full list from `NAV_GROUPS` - every group header and
 * every link, visible at once. The command palette (Ctrl-K, or the Search box
 * in the header) is the fast path when you already know where you are going.
 * On a phone the same full list lives behind one menu button instead of a
 * row of sixty chips.
 */
export function AppShell({
  groups,
  user,
  notificationCount = 0,
  children,
}: {
  groups: NavGroup[];
  user: { name: string; role: string };
  notificationCount?: number;
  children: React.ReactNode;
}) {
  const pathname = usePathname();
  const current = activeItem(pathname, groups)?.href;

  const [paletteOpen, setPaletteOpen] = useState(false);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const shortcutKeyRef = useRef<HTMLElement>(null);

  // Both overlays close from their own controls rather than from a route
  // effect: the palette closes when it takes you somewhere, the drawer when a
  // link inside it is followed (`onNavigate`), and Escape closes either.

  // Ctrl-K / Cmd-K opens the palette from anywhere, including mid-typing.
  // Escape closes the drawer (the palette listens for its own).
  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === 'k') {
        event.preventDefault();
        setPaletteOpen((open) => !open);
      } else if (event.key === 'Escape') {
        setDrawerOpen(false);
      }
    }
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, []);

  // The shortcut label follows the platform: "⌘ K" on a Mac, "Ctrl K"
  // elsewhere. It is written straight into the DOM instead of into state, so
  // the server's first paint ("Ctrl K") and the client's agree everywhere.
  useEffect(() => {
    if (/Mac|iPhone|iPad/.test(window.navigator.platform) && shortcutKeyRef.current) {
      shortcutKeyRef.current.textContent = '⌘ K';
    }
  }, []);

  // An open drawer covers the page, so the page behind it stops scrolling.
  useEffect(() => {
    if (!drawerOpen) return;
    const previous = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => {
      document.body.style.overflow = previous;
    };
  }, [drawerOpen]);

  return (
    <div className="min-h-screen md:flex">
      <aside className="hidden w-60 shrink-0 border-r border-border bg-card md:block" aria-label="Primary">
        <div className="px-5 py-4 text-lg font-semibold tracking-tight">SIMS</div>
        <nav className="px-3 pb-4">
          <SidebarNav groups={groups} current={current} />
        </nav>
      </aside>

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex items-center justify-between gap-4 border-b border-border bg-card px-4 py-3 md:px-6">
          <Breadcrumbs groups={groups} />
          <div className="flex items-center gap-2 sm:gap-3">
            <button
              type="button"
              onClick={() => setPaletteOpen(true)}
              aria-label="Search or jump to a page"
              className="flex h-9 items-center gap-2 rounded-md border border-border bg-background px-2.5 text-sm text-muted-foreground hover:bg-muted sm:w-48 lg:w-56"
            >
              <Search className="h-4 w-4 shrink-0" aria-hidden />
              <span className="hidden truncate sm:inline">Search or jump to…</span>
              <kbd
                ref={shortcutKeyRef}
                className="ml-auto hidden shrink-0 rounded border border-border bg-muted px-1.5 text-[11px] font-medium sm:inline"
              >
                Ctrl K
              </kbd>
            </button>

            <button
              type="button"
              onClick={() => setDrawerOpen(true)}
              aria-label="Open navigation menu"
              className="inline-flex h-9 w-9 items-center justify-center rounded-md border border-border hover:bg-muted md:hidden"
            >
              <Menu className="h-4 w-4" aria-hidden />
            </button>

            <Link
              href="/notifications"
              className="relative inline-flex h-9 w-9 items-center justify-center rounded-md border border-border hover:bg-muted"
              aria-label={notificationCount > 0 ? `Notifications, ${notificationCount} new` : 'Notifications'}
            >
              <Bell className="h-4 w-4" aria-hidden />
              {notificationCount > 0 && <span aria-hidden className="absolute -right-1.5 -top-1.5 min-w-[1.25rem] rounded-full bg-primary px-1 text-center text-[11px] leading-5 text-primary-foreground">{notificationCount > 99 ? '99+' : notificationCount}</span>}
            </Link>
            <div className="hidden text-right text-sm leading-tight sm:block">
              <div className="font-medium">{user.name}</div>
              <div className="text-xs text-muted-foreground">{user.role}</div>
            </div>
            <form action="/auth/signout" method="post">
              <Button type="submit" variant="outline" aria-label="Sign out">
                <LogOut className="h-4 w-4" aria-hidden />
                <span className="hidden sm:inline">Sign out</span>
              </Button>
            </form>
          </div>
        </header>

        <main className="flex-1 p-4 md:p-6">{children}</main>
      </div>

      {/* The same full list, behind one button, instead of a row of chips. */}
      {drawerOpen ? (
        <div className="fixed inset-0 z-40 md:hidden">
          <div className="absolute inset-0 bg-black/40" onClick={() => setDrawerOpen(false)} />
          <div
            role="dialog"
            aria-modal="true"
            aria-label="Navigation"
            className="absolute inset-y-0 left-0 w-72 max-w-[85vw] overflow-y-auto border-r border-border bg-card p-4"
          >
            <div className="mb-2 flex items-center justify-between">
              <span className="text-lg font-semibold tracking-tight">SIMS</span>
              <button
                type="button"
                onClick={() => setDrawerOpen(false)}
                aria-label="Close navigation menu"
                className="inline-flex h-9 w-9 items-center justify-center rounded-md border border-border hover:bg-muted"
              >
                <X className="h-4 w-4" aria-hidden />
              </button>
            </div>
            <nav aria-label="Primary mobile">
              <SidebarNav groups={groups} current={current} onNavigate={() => setDrawerOpen(false)} />
            </nav>
          </div>
        </div>
      ) : null}

      {/* Mounted only while open, so every opening starts with an empty box. */}
      {paletteOpen ? <CommandPalette groups={groups} onClose={() => setPaletteOpen(false)} /> : null}
    </div>
  );
}
