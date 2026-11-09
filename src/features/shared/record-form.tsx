'use client';

import { useEffect, useRef, type ReactNode } from 'react';
import { Button } from '@/components/ui/button';

/**
 * The form half of a record editor.
 *
 * It is drawn *above* the table it edits: on a table with any number of rows
 * a form at the bottom of the page is a long scroll away from the control
 * that opened it. When it opens it scrolls itself to the top of the viewport
 * and takes focus - a new record lands in its first field, an existing one in
 * the form itself - and Escape closes it, so the keyboard never has to chase
 * it back up the page.
 */
export function RecordForm({
  title,
  isNew,
  saving,
  onCancel,
  onSave,
  saveLabel = 'Save changes',
  testId,
  children,
}: {
  title: string;
  isNew: boolean;
  saving: boolean;
  onCancel: () => void;
  onSave: () => void;
  saveLabel?: string;
  testId?: string;
  children: ReactNode;
}) {
  const containerRef = useRef<HTMLDivElement>(null);
  const cancelRef = useRef(onCancel);

  // The caller's `onCancel` is usually an inline closure, so it is read
  // through a ref instead of re-subscribing the listener on every keystroke.
  useEffect(() => {
    cancelRef.current = onCancel;
  });

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;
    container.scrollIntoView({ block: 'start' });
    if (isNew) {
      const first = container.querySelector<HTMLElement>('input, select, textarea');
      (first ?? container).focus();
    } else {
      container.focus();
    }
  }, [isNew]);

  useEffect(() => {
    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') cancelRef.current();
    }
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, []);

  return (
    <div
      ref={containerRef}
      tabIndex={-1}
      data-testid={testId}
      className="rounded-lg border border-border p-4 outline-none"
    >
      <div className="mb-3 flex items-center justify-between gap-3">
        <h3 className="text-sm font-semibold">{title}</h3>
        <Button size="sm" variant="ghost" onClick={onCancel}>
          Cancel
        </Button>
      </div>

      {children}

      <div className="mt-4 flex justify-end gap-2">
        <Button variant="outline" onClick={onCancel}>
          Cancel
        </Button>
        <Button disabled={saving} onClick={onSave}>
          {saving ? 'Saving…' : saveLabel}
        </Button>
      </div>
    </div>
  );
}
