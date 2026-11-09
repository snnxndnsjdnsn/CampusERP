'use client';

import { useEffect, useRef, type ReactNode } from 'react';
import { ErrorPanel } from '@/components/ui/empty-state';

/**
 * The two lines of feedback an editor shows: what just happened, and what
 * stopped it happening.
 *
 * Both sit at the top of the editor, which is exactly where nobody is looking
 * while a form below them has the focus, so each scrolls itself into view
 * when its message appears - and only then. A message that is already on
 * screen leaves the page alone.
 */

/** A confirmation: "Academic year added." */
export function Notice({ children, testId }: { children: ReactNode; testId?: string }) {
  const ref = useRef<HTMLParagraphElement>(null);
  const text = typeof children === 'string' ? children : '';

  useEffect(() => {
    if (text) ref.current?.scrollIntoView({ block: 'nearest' });
  }, [text]);

  return (
    <p ref={ref} className="text-sm text-emerald-700" data-testid={testId}>
      {children}
    </p>
  );
}

/** A refusal, in the database's own words. */
export function Alert({ message }: { message: string }) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    ref.current?.scrollIntoView({ block: 'nearest' });
  }, [message]);

  return (
    <div ref={ref}>
      <ErrorPanel message={message} />
    </div>
  );
}
