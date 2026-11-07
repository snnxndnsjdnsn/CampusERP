'use client';

import {
  Activity, Award, BadgeCheck, Bell, BookOpen, BookText, Briefcase, Building2, CalendarCheck, CalendarDays, ChevronRight, CircleDollarSign, ClipboardCheck, ClipboardList, Contact, Database, FileCheck2, FileText, FlaskConical, FolderOpen, GraduationCap, Handshake, HeartHandshake, IdCard, LayoutDashboard, ListChecks, LogOut, Megaphone, MessageSquare, Microscope, PartyPopper, PenLine, Presentation, Receipt, ScrollText, Search, Settings, ShieldCheck, Table2, Trophy, Users, UserRound,
} from 'lucide-react';
import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { Button } from '@/components/ui/button';
import { NAV_PARENTS, type NavGroup, type NavItem } from '@/lib/nav';
import { cn } from '@/lib/utils';

export const ICONS: Record<string, React.ComponentType<{ className?: string }>> = {
  '/dashboard': LayoutDashboard,
  '/announcements': Megaphone,
  '/students': GraduationCap,
  '/admissions': ClipboardList,
  '/registration': ClipboardCheck,
  '/attendance': CalendarCheck,
  '/timetable': Table2,
  '/assessment': FileText,
  '/results': Award,
  '/results/grades': Award,
  '/my-results': Award,
  '/my-documents': FileText,
  '/certificates': BadgeCheck,
  '/requests': FileCheck2,
  '/my-hr': Contact,
  '/activities': Trophy,
  '/staff-profile': Microscope,
  '/grievances': MessageSquare,
  '/mentoring': HeartHandshake,
  '/feedback': ScrollText,
  '/finance': Receipt,
  '/employees': Briefcase,
  '/structure': Building2,
  '/calendar': CalendarDays,
  '/curriculum': BookOpen,
  '/courses': BookText,
  '/admin/users': Users,
  '/admin/reference': Database,
  '/audit': ShieldCheck,
  '/settings': Settings,
  // Schema modules 20 to 34 - the staff-profile research sub-modules. Each is
  // an address inside the staff-profile screen.
  '/staff-profile/activity': Activity,
  '/staff-profile/publication': BookOpen,
  '/staff-profile/conference': Presentation,
  '/staff-profile/development': GraduationCap,
  '/staff-profile/internship': Handshake,
  '/staff-profile/research': FlaskConical,
  '/staff-profile/funded-research': CircleDollarSign,
  '/staff-profile/consultancy': Briefcase,
  '/staff-profile/co-curricular': Users,
  '/staff-profile/extra-curricular': PartyPopper,
  '/staff-profile/award': Trophy,
  '/staff-profile/membership': IdCard,
  '/staff-profile/contribution': PenLine,
  '/staff-profile/evidence': FolderOpen,
  '/staff-profile/evidence-requirements': ListChecks,
};

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
  const active = (href: string) => href === current;
  return (
    <div className="min-h-screen md:flex">
      <aside className="hidden w-60 shrink-0 border-r border-border bg-card md:block" aria-label="Primary">
        <div className="px-5 py-4 text-lg font-semibold tracking-tight">SIMS</div>
        <nav className="px-3 pb-4">
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
        </nav>
      </aside>
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex items-center justify-between gap-4 border-b border-border bg-card px-4 py-3 md:px-6">
          <Breadcrumbs groups={groups} />
          <div className="flex items-center gap-3">
            <form action="/search" method="get" role="search" className="hidden sm:block">
              <label htmlFor="global-search" className="sr-only">Search</label>
              <div className="relative">
                <Search className="pointer-events-none absolute left-2 top-2.5 h-4 w-4 text-muted-foreground" aria-hidden />
                <input id="global-search" name="q" type="search" placeholder="Search" maxLength={80} className="h-9 w-44 rounded-md border border-border bg-background pl-8 pr-2 text-sm" />
              </div>
            </form>
            <Link href="/search" className="inline-flex h-9 w-9 items-center justify-center rounded-md border border-border sm:hidden" aria-label="Search"><Search className="h-4 w-4" aria-hidden /></Link>
            <Link href="/notifications" className="relative inline-flex h-9 w-9 items-center justify-center rounded-md border border-border hover:bg-muted" aria-label={notificationCount > 0 ? `Notifications, ${notificationCount} new` : 'Notifications'}>
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
        <nav className="flex gap-1 overflow-x-auto border-b border-border bg-card px-3 py-2 md:hidden" aria-label="Primary mobile">
          {groups.flatMap((g) => [...g.items, ...(g.children ?? [])]).map((item) => (
            <Link
              key={item.href}
              href={item.href}
              aria-current={active(item.href) ? 'page' : undefined}
              className={cn('whitespace-nowrap rounded-md px-3 py-1.5 text-sm hover:bg-muted', active(item.href) && 'bg-muted font-medium text-primary')}
            >
              {item.label}
            </Link>
          ))}
        </nav>
        <main className="flex-1 p-4 md:p-6">{children}</main>
      </div>
    </div>
  );
}
