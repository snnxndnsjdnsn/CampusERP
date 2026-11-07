import { PageHeader } from '@/components/page-header';
import { ErrorPanel } from '@/components/ui/empty-state';
import {
  UserDetailPanel,
  type IamRole,
  type PermissionOption,
  type PermissionOverride,
  type ScopeEntities,
  type UserDetail,
} from '@/features/iam/iam-client';
import { asJsonArray, asJsonObject, safeRpc, safeRows, safeSelect } from '@/features/shared/server-rpc';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

export default async function AdminUserDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const userId = Number.parseInt(id, 10);
  const { supabase } = await requireContext();

  if (!Number.isFinite(userId)) {
    return (
      <>
        <PageHeader title="User" />
        <ErrorPanel message="That user id is not valid." />
      </>
    );
  }

  // The database decides whether this caller may read the account at all.
  const detailResult = await safeRpc<UserDetail>(supabase, 'iam_user_detail', { p_user_id: userId });
  const detail = asJsonObject<UserDetail>(detailResult.data);

  const overrideResult = await safeRpc<PermissionOverride[]>(supabase, 'iam_override_list', { p_user_id: userId });
  const overrides = asJsonArray<PermissionOverride>(overrideResult.data);

  const roles = await safeRows<IamRole>(supabase, 'iam_roles');
  const permissions = await safeRows<PermissionOption>(supabase, 'iam_permission_options');

  // Scope entities for role grants and permission overrides.
  const institutions = await safeSelect<{ institution_id: number; institution_name: string }>(
    supabase,
    'institution',
    'institution_id, institution_name',
    { order: { column: 'institution_name', ascending: true } },
  );
  const campuses = await safeSelect<{ campus_id: number; campus_name: string }>(supabase, 'campus', 'campus_id, campus_name', {
    order: { column: 'campus_name', ascending: true },
  });
  const departments = await safeSelect<{ department_id: number; department_name: string }>(
    supabase,
    'department',
    'department_id, department_name',
    { order: { column: 'department_name', ascending: true } },
  );
  const programmes = await safeSelect<{ programme_id: number; programme_name: string }>(
    supabase,
    'programme',
    'programme_id, programme_name',
    { order: { column: 'programme_name', ascending: true } },
  );

  const entities: ScopeEntities = {
    INSTITUTION: institutions.rows.map((r) => ({ id: Number(r.institution_id), label: r.institution_name })),
    CAMPUS: campuses.rows.map((r) => ({ id: Number(r.campus_id), label: r.campus_name })),
    DEPARTMENT: departments.rows.map((r) => ({ id: Number(r.department_id), label: r.department_name })),
    PROGRAMME: programmes.rows.map((r) => ({ id: Number(r.programme_id), label: r.programme_name })),
  };

  if (detailResult.error) {
    return (
      <>
        <PageHeader title="User" />
        <ErrorPanel message={detailResult.error} />
      </>
    );
  }

  if (!detail) {
    return (
      <>
        <PageHeader title="User" />
        <ErrorPanel message="That user could not be found." />
      </>
    );
  }

  return (
    <>
      <PageHeader title={detail.username} description={`Account ${detail.user_id} · ${detail.email ?? 'no email on file'}`} />
      <UserDetailPanel
        detail={detail}
        roles={roles.rows}
        entities={entities}
        permissions={permissions.rows}
        overrides={overrides}
      />
    </>
  );
}
