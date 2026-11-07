'use client';

import type { ReactNode } from 'react';
import { ErrorPanel } from '@/components/ui/empty-state';
import { formatMoney } from '@/lib/format';

/** Small building blocks shared by the fee forms. */

export function Field({
  label,
  htmlFor,
  children,
  hint,
}: {
  label: string;
  htmlFor: string;
  children: ReactNode;
  hint?: string;
}) {
  return (
    <div className="space-y-1.5">
      <label htmlFor={htmlFor} className="text-sm font-medium leading-none">
        {label}
      </label>
      {children}
      {hint ? <p className="text-xs text-muted-foreground">{hint}</p> : null}
    </div>
  );
}

/** The error raised by the database, shown next to the form that caused it. */
export function FormError({ message }: { message: string | null }) {
  if (!message) return null;
  return (
    <p className="rounded-md border border-red-200 bg-red-50 p-2 text-sm text-red-800" role="alert">
      {message}
    </p>
  );
}

/** A read error that must not take the page down. */
export function ReadError({ message }: { message: string | null }) {
  if (!message) return null;
  return <ErrorPanel message={message} />;
}

/** Today's date, used as the default for due dates. */
export function today(): string {
  return new Date().toISOString().slice(0, 10);
}

/** An amount, formatted the way the rest of the application shows money. */
export function Money({ value }: { value: number | string | null | undefined }) {
  return <span className="tabular-nums">{formatMoney(value)}</span>;
}
