import { notFound } from 'next/navigation';
import { schemaModule } from '@/features/schema/module-catalog';
import { SchemaScreen } from '@/features/schema/schema-screen';

export const dynamic = 'force-dynamic';

/**
 * A schema module that has a screen of its own.
 *
 * Modules 18, 35, 36, 38 and 39 describe the database itself - its indexes,
 * its seed vocabulary, its access registration and its integrity rules - so
 * they share one address under `/schema`. The module number in the address
 * decides what is read; anything else is not a module and is a 404.
 *
 * The catalogue of the modules lives in `src/features/schema/module-catalog.ts`.
 */
export default async function SchemaModulePage({ params }: { params: Promise<{ module: string }> }) {
  const { module: slug } = await params;

  const entry = schemaModule(slug);
  if (!entry) notFound();

  return <SchemaScreen entry={entry} />;
}
