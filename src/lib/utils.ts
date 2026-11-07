import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

/** Merge conditional class names, resolving Tailwind conflicts (later wins). */
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/**
 * Sanitise a `next` redirect target.
 *
 * Only same-site relative paths are allowed. Anything absolute, protocol-relative
 * or otherwise ambiguous falls back to `/dashboard`, so a crafted login link
 * cannot bounce a user to another origin.
 */
export function safeNextPath(value: string | null | undefined): string {
  if (!value) return '/dashboard';
  if (!value.startsWith('/')) return '/dashboard';
  if (value.startsWith('//')) return '/dashboard';
  if (value.startsWith('/\\')) return '/dashboard';
  if (/[\r\n]/.test(value)) return '/dashboard';
  return value;
}
