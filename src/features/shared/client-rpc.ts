'use client';

import { useRouter } from 'next/navigation';
import { useCallback, useState } from 'react';
import { createClient } from '@/lib/supabase/client';

/**
 * Browser-side RPC helper.
 *
 * Every write in this application goes through a `public.*` function, so client
 * components call the same surface the server does. The helper never throws:
 * a database refusal comes back as `{ ok: false, error }` so a form can show it.
 */

export type RpcOutcome<T> = { ok: true; data: T } | { ok: false; error: string };

/** Call a `public.*` RPC from the browser. */
export async function rpcCall<T>(fn: string, args: Record<string, unknown> = {}): Promise<RpcOutcome<T>> {
  try {
    const supabase = createClient();
    const { data, error } = await supabase.rpc(fn, args);
    if (error) return { ok: false, error: error.message };
    return { ok: true, data: data as T };
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : 'The request could not be sent.' };
  }
}

/**
 * Call a `public.*` RPC and throw a readable error when the database refuses.
 *
 * The throwing variant is for the screens that read data and render the result
 * directly; the screens that write use `useRpcAction`, which shows the refusal
 * in the form instead.
 */
export async function clientRpc<T>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const result = await rpcCall<T>(fn, args);
  if (!result.ok) throw new Error(result.error);
  return result.data;
}

/**
 * Update one row of an RLS-protected table.
 *
 * This exists only for the one operation the schema exposes without a
 * `public.*` function: moving an assessment event from CONDUCTED to PUBLISHED.
 * The row-level policy (`ASSESSMENT.ALL.UPDATE`) and the database trigger
 * (`ASSESSMENT.ALL.PUBLISH`) still decide whether the change is allowed.
 */
export async function clientUpdate(
  table: string,
  patch: Record<string, unknown>,
  match: Record<string, unknown>,
): Promise<void> {
  try {
    const supabase = createClient();
    const { error } = await supabase.from(table).update(patch).match(match);
    if (error) throw new Error(error.message);
  } catch (e) {
    throw e instanceof Error ? e : new Error('The row could not be updated.');
  }
}

export type RpcActionOptions = {
  /** Message shown after a successful call. */
  success?: string;
  /** Set to false to keep the current server-rendered data (default: refresh). */
  refresh?: boolean;
};

/**
 * Busy/error state plus a `run` helper that refreshes the server components
 * once the database has accepted the change.
 */
export function useRpcAction() {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const run = useCallback(
    async <T,>(fn: string, args: Record<string, unknown> = {}, options: RpcActionOptions = {}): Promise<RpcOutcome<T>> => {
      setBusy(true);
      setError(null);
      setNotice(null);
      const result = await rpcCall<T>(fn, args);
      setBusy(false);
      if (result.ok) {
        if (options.success) setNotice(options.success);
        if (options.refresh !== false) router.refresh();
      } else {
        setError(result.error);
      }
      return result;
    },
    [router],
  );

  return { busy, error, notice, setError, setNotice, run };
}

/** Normalise a JSON column that may arrive as an array, a JSON string, or null. */
export function asArray<T>(value: unknown): T[] {
  if (Array.isArray(value)) return value as T[];
  if (typeof value === 'string') {
    try {
      const parsed = JSON.parse(value);
      return Array.isArray(parsed) ? (parsed as T[]) : [];
    } catch {
      return [];
    }
  }
  return [];
}

/** Normalise a JSON column that may arrive as an object, a JSON string, or null. */
export function asObject(value: unknown): Record<string, unknown> {
  if (value && typeof value === 'object' && !Array.isArray(value)) return value as Record<string, unknown>;
  if (typeof value === 'string') {
    try {
      const parsed = JSON.parse(value);
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) return parsed as Record<string, unknown>;
    } catch {
      return {};
    }
  }
  return {};
}

/** The private bucket every document in SIMS lives in. */
export const DOCUMENTS_BUCKET = 'sims-documents';

/**
 * Turn a storage key returned by a `*_download_info` function into a short-lived
 * signed URL. The key itself is never enough to read the file.
 */
export async function signedDocumentUrl(storageKey: string, seconds = 120): Promise<string | null> {
  try {
    const supabase = createClient();
    const { data, error } = await supabase.storage.from(DOCUMENTS_BUCKET).createSignedUrl(storageKey, seconds);
    if (error) return null;
    return data?.signedUrl ?? null;
  } catch {
    return null;
  }
}

/**
 * Remove a file from the private bucket.
 *
 * The `*_delete` functions hand back the storage key of the file they removed from
 * the database; this clears the blob as well. It is best effort: the row is already
 * gone by the time it runs, so a refusal here is not worth failing the action over.
 */
export async function deleteStoredFile(storageKey: string): Promise<boolean> {
  try {
    const supabase = createClient();
    const { error } = await supabase.storage.from(DOCUMENTS_BUCKET).remove([storageKey]);
    return !error;
  } catch {
    return false;
  }
}
