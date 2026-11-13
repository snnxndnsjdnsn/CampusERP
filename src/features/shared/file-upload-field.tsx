'use client';

import { useMemo, useState } from 'react';
import { Input, Label } from '@/components/ui/input';
import { createClient } from '@/lib/supabase/client';
import { DOCUMENTS_BUCKET } from '@/features/shared/client-rpc';

/**
 * Picking a document from the computer instead of typing where it lives.
 *
 * Every document form in SIMS used to ask for a storage key, a file name, a
 * size and a type as four hand-filled fields, because nothing in the
 * application could put a file in the bucket. The storage policy (070) can,
 * so this field does the whole mechanical part of a document: it takes the
 * file, checks it the way the register RPC will, puts the blob in the
 * caller's own folder of the private bucket, and hands the form everything
 * the RPC asks for.
 *
 * Uploading is deliberately separate from registering. The blob lands in the
 * bucket the moment it is chosen; the form's own button still does the
 * registering, so a half-filled form leaves an orphan blob rather than a
 * half-registered document.
 */

/** What one picked file turns into: everything the register RPCs ask for. */
export type PickedFile = {
  storageKey: string;
  fileName: string;
  mimeType: string;
  size: number;
};

/** The only types the register RPCs accept, with the extensions that may carry them. */
const ACCEPTED = new Map<string, string[]>([
  ['application/pdf', ['pdf']],
  ['image/jpeg', ['jpg', 'jpeg']],
  ['image/png', ['png']],
]);

/** The register RPCs refuse anything larger; refusing it here saves the upload. */
const MAX_BYTES = 10485760;

/**
 * A fresh storage key for a file whose obvious name is already taken.
 *
 * A key is a one-time identity, not a filename: `file_object.storage_key` is
 * unique, and removing a document keeps its row and its blob on purpose - the
 * audit trail and the version history both point at them. So a name that has
 * ever been registered is registered for good, and the next `marksheet.pdf`
 * has to live somewhere else. Only the suffix moves; the name the form records
 * (`original_file_name`) is the one the user picked and never changes.
 */
function alternateKey(folder: string, name: string): string {
  const dot = name.lastIndexOf('.');
  const stem = dot > 0 ? name.slice(0, dot) : name;
  const suffix = dot > 0 ? name.slice(dot) : '';
  const nonce = Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
  return `${folder}/${stem}-${nonce}${suffix}`;
}

export function FileUploadField({
  id,
  label,
  prefix,
  onUploaded,
}: {
  id: string;
  label: string;
  /** The folder this caller may write into: `student/12`, `employee/3`. */
  prefix: string;
  onUploaded: (file: PickedFile) => void;
}) {
  const supabase = useMemo(() => createClient(), []);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [picked, setPicked] = useState<string | null>(null);

  async function choose(file: File) {
    setBusy(true);
    setError(null);
    setPicked(null);
    try {
      // The register RPC enforces all of this again; refusing a wrong file
      // before uploading it saves the user a wait and the bucket an orphan.
      const extensions = ACCEPTED.get(file.type);
      if (!extensions) throw new Error('Only PDF, JPEG and PNG files are accepted.');
      const name = file.name.split(/[\\/]/).pop() ?? '';
      const extension = (name.match(/\.([A-Za-z0-9]{1,10})$/)?.[1] ?? '').toLowerCase();
      if (!name || !extensions.includes(extension)) throw new Error('The file name does not match its type.');
      if (file.size <= 0 || file.size > MAX_BYTES) throw new Error('The file must be between 1 byte and 10 MB.');

      const folder = prefix.replace(/\/+$/, '');
      let storageKey = `${folder}/${name}`;
      const { error: uploadError } = await supabase.storage
        .from(DOCUMENTS_BUCKET)
        .upload(storageKey, file, { contentType: file.type, upsert: false });
      if (uploadError) {
        // The name was registered by an earlier document that is still on
        // file. Overwriting it is not an option - the record behind it would
        // then describe different bytes - so this file goes under a name of
        // its own. Anything else is a real failure and is shown as one.
        if ((uploadError as { code?: string }).code !== 'KeyAlreadyExists') throw new Error(uploadError.message);
        storageKey = alternateKey(folder, name);
        const { error: retryError } = await supabase.storage
          .from(DOCUMENTS_BUCKET)
          .upload(storageKey, file, { contentType: file.type, upsert: false });
        if (retryError) throw new Error(retryError.message);
      }

      setPicked(name);
      onUploaded({ storageKey, fileName: name, mimeType: file.type, size: file.size });
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The file could not be uploaded.');
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-1">
      <Label htmlFor={id}>{label}</Label>
      <Input
        id={id}
        type="file"
        accept={[...ACCEPTED.keys()].join(',')}
        disabled={busy}
        onChange={(e) => {
          const input = e.currentTarget;
          const file = input.files?.[0];
          if (!file) return;
          void choose(file).then(() => {
            // Letting the same file be picked again after a failed register.
            input.value = '';
          });
        }}
      />
      <p className="text-xs text-muted-foreground">
        {busy ? (
          'Uploading…'
        ) : error ? (
          <span className="text-red-700">{error}</span>
        ) : picked ? (
          <>
            Uploaded as <span className="font-mono">{picked}</span>. Finish the form to register it.
          </>
        ) : (
          <>
            PDF, JPEG or PNG up to 10 MB, filed under{' '}
            <span className="font-mono">{prefix.replace(/\/+$/, '')}/</span> in the private document bucket.
          </>
        )}
      </p>
    </div>
  );
}
