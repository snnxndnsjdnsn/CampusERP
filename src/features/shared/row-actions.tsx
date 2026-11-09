'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/button';

/**
 * The actions of one table row: edit it, or delete it.
 *
 * Deleting takes two clicks on purpose. The first only asks; the second -
 * "Confirm delete" - does it, so a stray click on a destructive button never
 * removes anything. The confirmation is drawn in the row itself rather than
 * in a browser dialog, which keeps it inside the page's own visual language.
 */
export function RowActions({
  onEdit,
  onDelete,
  canEdit = true,
  canDelete = true,
}: {
  onEdit: () => void;
  onDelete?: () => void;
  canEdit?: boolean;
  canDelete?: boolean;
}) {
  const [confirming, setConfirming] = useState(false);
  const deletable = canDelete && Boolean(onDelete);

  if (confirming && onDelete) {
    return (
      <div className="flex justify-end gap-2">
        <Button size="sm" variant="outline" onClick={() => setConfirming(false)}>
          Cancel
        </Button>
        <Button
          size="sm"
          variant="destructive"
          onClick={() => {
            setConfirming(false);
            onDelete();
          }}
        >
          Confirm delete
        </Button>
      </div>
    );
  }

  return (
    <div className="flex justify-end gap-2">
      {canEdit ? (
        <Button size="sm" variant="outline" onClick={onEdit}>
          Edit
        </Button>
      ) : null}
      {deletable ? (
        <Button size="sm" variant="destructive" onClick={() => setConfirming(true)}>
          Delete
        </Button>
      ) : null}
    </div>
  );
}
