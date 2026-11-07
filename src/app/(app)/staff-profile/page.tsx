import { StaffProfileScreen } from '@/features/staff-profile/staff-profile-screen';

export const dynamic = 'force-dynamic';

/**
 * Staff profile & research.
 *
 * The list comes from `staff_activity_list`, which decides what the caller may
 * see. Opening a record asks `staff_activity_get`; the per-type detail form is
 * built from `staff_detail_schema`, so the database describes its own fields.
 *
 * Schema modules 20 to 34 have their own addresses under `/staff-profile`;
 * see `src/app/(app)/staff-profile/[section]/page.tsx`.
 */
export default async function StaffProfilePage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; approval?: string; group?: string }>;
}) {
  const sp = await searchParams;

  return (
    <StaffProfileScreen
      q={(sp.q ?? '').trim()}
      approval={(sp.approval ?? '').trim()}
      group={(sp.group ?? '').trim()}
    />
  );
}
