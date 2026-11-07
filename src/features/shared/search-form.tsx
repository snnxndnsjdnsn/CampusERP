import Link from 'next/link';
import { Button } from '@/components/ui/button';
import { Input, Label, Select } from '@/components/ui/input';

export type FilterOption = { value: string; label: string };

export type SearchFilter = {
  name: string;
  label: string;
  value: string;
  options: FilterOption[];
};

/**
 * A plain GET form: the filters live in the URL, so the page stays a Server
 * Component and every result set is reproducible from a link.
 */
export function SearchForm({
  action,
  query,
  filters = [],
  placeholder = 'Search',
  label = 'Search',
}: {
  action: string;
  query: string;
  filters?: SearchFilter[];
  placeholder?: string;
  label?: string;
}) {
  const active = Boolean(query.trim()) || filters.some((f) => f.value !== '');

  return (
    <form action={action} method="get" role="search" className="flex flex-wrap items-end gap-3">
      <div className="min-w-[14rem] flex-1">
        <Label htmlFor="q" className="mb-1 block">
          {label}
        </Label>
        <Input id="q" name="q" type="search" defaultValue={query} placeholder={placeholder} maxLength={120} />
      </div>

      {filters.map((f) => (
        <div key={f.name} className="min-w-[10rem]">
          <Label htmlFor={`filter-${f.name}`} className="mb-1 block">
            {f.label}
          </Label>
          <Select id={`filter-${f.name}`} name={f.name} defaultValue={f.value}>
            <option value="">All</option>
            {f.options.map((o) => (
              <option key={o.value} value={o.value}>
                {o.label}
              </option>
            ))}
          </Select>
        </div>
      ))}

      <Button type="submit" variant="outline">
        Apply
      </Button>
      {active ? (
        <Link href={action} className="pb-2 text-sm font-medium text-primary underline-offset-4 hover:underline">
          Clear
        </Link>
      ) : null}
    </form>
  );
}
