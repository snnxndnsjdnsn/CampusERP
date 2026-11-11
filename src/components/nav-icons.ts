/**
 * The icon of every address the navigation can reach.
 *
 * It lives in its own module so both the shell and the command palette can
 * import it without importing each other. `src/components/app-shell.tsx`
 * re-exports it, which is where the unit test has always found it.
 */
import {
  Activity, Award, BadgeCheck, BookOpen, BookText, Briefcase, Building2, CalendarCheck, CalendarDays, CircleDollarSign, ClipboardCheck, ClipboardList, Contact, Database, FileCheck2, FileText, FlaskConical, FolderOpen, GraduationCap, Handshake, HeartHandshake, IdCard, LayoutDashboard, ListChecks, Megaphone, MessageSquare, Microscope, PartyPopper, PenLine, Presentation, Receipt, ScrollText, Settings, ShieldCheck, Table2, Trophy, Users,
} from 'lucide-react';

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
  // Schema modules 18 and 35 to 39 - the screens that were missing until now.
  '/schema/18': Database,
  '/schema/35': ListChecks,
  '/schema/36': ShieldCheck,
  '/reporting': Microscope,
  '/schema/38': FolderOpen,
  '/schema/39': FileCheck2,
};
