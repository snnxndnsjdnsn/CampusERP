import * as React from 'react';
import { cn } from '@/lib/utils';

/** A consistent "nothing here" panel. */
export function EmptyState({
  title,
  description,
  action,
  className,
}: {
  title: string;
  description?: string;
  action?: React.ReactNode;
  className?: string;
}) {
  return (
    <div className={cn('rounded-lg border border-dashed border-border p-8 text-center', className)}>
      <p className="text-sm font-medium">{title}</p>
      {description && <p className="mx-auto mt-1 max-w-md text-sm text-muted-foreground">{description}</p>}
      {action && <div className="mt-4 flex justify-center">{action}</div>}
    </div>
  );
}

/** An inline error panel for a failed database call. */
export function ErrorPanel({ message, className }: { message: string; className?: string }) {
  return (
    <div className={cn('rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-800', className)} role="alert">
      {message}
    </div>
  );
}
