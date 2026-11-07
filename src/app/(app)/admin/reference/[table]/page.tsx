import Link from 'next/link';
import { notFound } from 'next/navigation';
import { PageHeader } from '@/components/page-header';
import { Button } from '@/components/ui/button';
import { ReferenceTableEditor } from '@/features/detail/reference-table-editor';
import { safeRpc } from '@/features/shared/server-rpc';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

type RefTable = { tbl: string; label: string; module_code: string };

/**
 * One reference table, deep-linkable.
 *
 * `/admin/reference` is the picker; this route opens a single table directly so
 * a row can be linked to. The table must be one the database offers through
 * `ref_list`, otherwise the page is not found.
 */
export default async function ReferenceTablePage({ params }: { params: Promise<{ table: string }> }) {
  const { table } = await params;
  const { supabase } = await requireContext();

  const { data, error } = await safeRpc<RefTable[]>(supabase, 'ref_list');
  const tables = data ?? [];
  const match = tables.find((t) => t.tbl === table);

  if (!match) {
    if (error) {
      return (
        <>
          <PageHeader title="Reference data" />
          <p className="rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800" role="alert">
            {error}
          </p>
        </>
      );
    }
    notFound();
  }

  return (
    <>
      <PageHeader
        title={match.label}
        description={`Reference table ${match.tbl} · module ${match.module_code}`}
        actions={
          <Link href="/admin/reference">
            <Button variant="outline">All reference tables</Button>
          </Link>
        }
      />
      <ReferenceTableEditor table={match.tbl} />
    </>
  );
}
