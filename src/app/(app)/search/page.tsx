import Link from 'next/link';
import { PageHeader } from '@/components/page-header';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { EmptyState, ErrorPanel } from '@/components/ui/empty-state';
import { Input, Label } from '@/components/ui/input';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { rpcSafe } from '@/lib/api';
import { requireContext } from '@/lib/server-context';

export const dynamic = 'force-dynamic';

type SearchRow = {
  kind: string;
  id: number;
  title: string | null;
  subtitle: string | null;
};

/** Where a result of each kind lives in the application. */
const KIND_ROUTE: Record<string, string> = {
  student: '/students',
  employee: '/employees',
  course: '/courses',
  programme: '/curriculum',
  department: '/structure',
};

export default async function SearchPage({ searchParams }: { searchParams: Promise<{ q?: string }> }) {
  const { q } = await searchParams;
  const { supabase } = await requireContext();
  const query = (q ?? '').trim();

  // The database ignores queries shorter than two characters.
  const result =
    query.length >= 2
      ? await rpcSafe<SearchRow[]>(supabase, 'global_search', { p_q: query, p_limit: 20 })
      : { data: [] as SearchRow[], error: null as string | null };

  const rows = result.data ?? [];

  return (
    <>
      <PageHeader title="Search" description="Find students, employees, courses, programmes and departments." />

      <Card>
        <CardContent>
          <form action="/search" method="get" role="search" className="flex flex-wrap items-end gap-3">
            <div className="min-w-[16rem] flex-1 space-y-1.5">
              <Label htmlFor="search-q">Search</Label>
              <Input id="search-q" name="q" type="search" defaultValue={query} maxLength={80} placeholder="Name, number or code" />
            </div>
            <Button type="submit">Search</Button>
          </form>
        </CardContent>
      </Card>

      <div className="mt-4">
        {result.error ? (
          <ErrorPanel message={result.error} />
        ) : query.length === 0 ? (
          <EmptyState title="Nothing searched yet" description="Type at least two characters to search the directory." />
        ) : query.length < 2 ? (
          <EmptyState title="Search needs two characters" description="Type at least two characters to search the directory." />
        ) : rows.length === 0 ? (
          <EmptyState title="No matches" description={`Nothing visible to you matches “${query}”.`} />
        ) : (
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Kind</TableHead>
                <TableHead>Name</TableHead>
                <TableHead>Reference</TableHead>
                <TableHead className="text-right">Open</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {rows.map((r) => {
                const href = KIND_ROUTE[r.kind];
                return (
                  <TableRow key={`${r.kind}-${r.id}`}>
                    <TableCell>
                      <Badge variant="muted">{r.kind}</Badge>
                    </TableCell>
                    <TableCell className="font-medium">{r.title ?? '—'}</TableCell>
                    <TableCell className="font-mono text-xs">{r.subtitle ?? '—'}</TableCell>
                    <TableCell className="text-right">
                      {href ? (
                        <Link
                          href={`${href}?q=${encodeURIComponent(query)}`}
                          className="text-sm font-medium text-primary underline-offset-4 hover:underline"
                        >
                          View
                        </Link>
                      ) : (
                        <span className="text-xs text-muted-foreground">—</span>
                      )}
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        )}
      </div>
    </>
  );
}
