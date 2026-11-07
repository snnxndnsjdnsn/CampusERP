import { notFound } from 'next/navigation';
import { StaffProfileScreen } from '@/features/staff-profile/staff-profile-screen';
import { staffSection } from '@/lib/staff-sections';

export const dynamic = 'force-dynamic';

/**
 * A staff-profile research sub-module - schema modules 20 to 34.
 *
 * The MySQL source gives each of them its own tables, but the application
 * models them as one screen: `staff_activity` is a supertype and
 * `activity_type` says which specialised child table a row belongs to. So each
 * sub-module is an address inside `/staff-profile` that opens the screen
 * filtered to its `activity_group`.
 *
 * The filter in the address bar still wins, so `?group=` can narrow a section
 * further. The section map lives in `src/lib/staff-sections.ts`.
 */
export default async function StaffProfileSectionPage({
  params,
  searchParams,
}: {
  params: Promise<{ section: string }>;
  searchParams: Promise<{ q?: string; approval?: string; group?: string }>;
}) {
  const { section: slug } = await params;
  const sp = await searchParams;

  const section = staffSection(slug);
  if (!section) notFound();

  // The section decides the group; an explicit `?group=` in the address bar
  // overrides it.
  const group = (sp.group ?? '').trim() || section.group;

  return (
    <StaffProfileScreen
      q={(sp.q ?? '').trim()}
      approval={(sp.approval ?? '').trim()}
      group={group}
      formAction={`/staff-profile/${section.slug}`}
      heading={{
        title: `${section.module} · ${section.title}`,
        description: section.group
          ? `Schema module ${section.module} of the staff profile. The list is filtered to the ${section.group} group; the filter below can narrow it further.`
          : `Schema module ${section.module} of the staff profile. This section has no group of its own - the activity form carries its fields.`,
      }}
    />
  );
}
