import * as React from 'react';
import { cva, type VariantProps } from 'class-variance-authority';
import { cn } from '@/lib/utils';

const badgeVariants = cva(
  'inline-flex items-center rounded-full border px-2 py-0.5 text-xs font-medium',
  {
    variants: {
      variant: {
        default: 'border-transparent bg-primary text-primary-foreground',
        secondary: 'border-transparent bg-secondary text-secondary-foreground',
        outline: 'border-border text-foreground',
        success: 'border-transparent bg-emerald-100 text-emerald-800',
        warning: 'border-transparent bg-amber-100 text-amber-800',
        destructive: 'border-transparent bg-red-100 text-red-800',
        info: 'border-transparent bg-sky-100 text-sky-800',
        muted: 'border-transparent bg-muted text-muted-foreground',
      },
    },
    defaultVariants: { variant: 'default' },
  },
);

export type BadgeProps = React.HTMLAttributes<HTMLSpanElement> & VariantProps<typeof badgeVariants>;

export function Badge({ className, variant, ...props }: BadgeProps) {
  return <span className={cn(badgeVariants({ variant }), className)} {...props} />;
}

/**
 * Map a workflow status string to a badge colour.
 *
 * Statuses come straight from the database's enumerations, so the mapping is
 * deliberately generic: anything unknown falls back to `muted`.
 */
export function statusVariant(status: string | null | undefined): BadgeProps['variant'] {
  if (!status) return 'muted';
  const s = status.toUpperCase();
  if (['PASS', 'PASSED', 'ACTIVE', 'APPROVED', 'PUBLISHED', 'PAID', 'VERIFIED', 'COMPLETED', 'CONDUCTED', 'SUCCESS'].includes(s)) {
    return 'success';
  }
  if (['FAIL', 'FAILED', 'REJECTED', 'CANCELLED', 'CANCELED', 'OVERDUE', 'ABSENT', 'DENIED', 'BLOCKED'].includes(s)) return 'destructive';
  if (['PENDING', 'DRAFT', 'SUBMITTED', 'PARTIALLY_PAID', 'IN_PROGRESS', 'PLANNED', 'OPEN', 'REGISTRATION_OPEN'].includes(s)) return 'warning';
  if (['SCHEDULED', 'UNDER_REVIEW', 'INCOMPLETE'].includes(s)) return 'info';
  return 'muted';
}

export { badgeVariants };
