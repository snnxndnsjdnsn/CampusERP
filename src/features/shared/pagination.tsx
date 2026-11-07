import Link from 'next/link';

/**
 * Offset pagination that keeps the current filters in the URL.
 *
 * The page stays a Server Component: the links are plain anchors, so every result
 * set is reproducible from a copied address.
 */
export function Pagination({
  basePath,
  filters,
  offset,
  limit,
  total,
}: {
  basePath: string;
  filters?: Record<string, string | undefined>;
  offset: number;
  limit: number;
  total: number;
}) {
  const shown = Math.min(limit, Math.max(total - offset, 0));
  if (total <= limit && offset === 0) return null;

  const href = (nextOffset: number) => {
    const params = new URLSearchParams();
    for (const [key, value] of Object.entries(filters ?? {})) {
      if (value) params.set(key, value);
    }
    if (nextOffset > 0) params.set('offset', String(nextOffset));
    const query = params.toString();
    return query ? `${basePath}?${query}` : basePath;
  };

  const previous = Math.max(offset - limit, 0);
  const next = offset + limit < total ? offset + limit : null;

  return (
    <div className="mt-3 flex items-center justify-between text-sm">
      <span className="text-muted-foreground">
        {shown === 0 ? 'No rows' : `${offset + 1}–${offset + shown} of ${total}`}
      </span>
      <div className="flex gap-2">
        {offset > 0 ? (
          <Link
            href={href(previous)}
            className="rounded-md border border-border px-3 py-1 text-sm font-medium hover:bg-muted"
          >
            Previous
          </Link>
        ) : null}
        {next !== null ? (
          <Link
            href={href(next)}
            className="rounded-md border border-border px-3 py-1 text-sm font-medium hover:bg-muted"
          >
            Next
          </Link>
        ) : null}
      </div>
    </div>
  );
}
