import { PageHeader } from '@/components/page-header';
import { ErrorPanel } from '@/components/ui/empty-state';
import { ReferenceEditor, type RefTable } from '@/features/reference/reference-editor';
import { readRpcRows } from '@/features/shared/reads';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

/**
 * Module 1 · Common reference data.
 *
 * The editable catalogue lives in the database (`ref_list`); this page only
 * renders it and hands the writes to `ref_save` / `ref_delete`.
 */
export default async function ReferenceDataPage() {
  const { supabase } = await requireContext();

  const { data: tables, error } = await readRpcRows<RefTable>(supabase, 'ref_list');

  return (
    <>
      <PageHeader
        title="Reference data"
        description="The lookup tables the rest of the system depends on: countries, states, genders, categories, designations and more."
      />

      {error ? <ErrorPanel message={`Could not load the reference catalogue: ${error}`} /> : null}

      <ReferenceEditor tables={tables} />
    </>
  );
}
