'use client';

import { useRouter } from 'next/navigation';
import { useCallback, useState } from 'react';
import { createClient } from '@/lib/supabase/client';

export type RpcArgs = Record<string, unknown>;

/** PostgREST rejects `undefined` members, so drop them before the call. */
function clean(args: RpcArgs): RpcArgs {
  const out: RpcArgs = {};
  for (const [key, value] of Object.entries(args)) {
    if (value !== undefined) out[key] = value;
  }
  return out;
}

export type RpcRunner = (fn: string, args?: RpcArgs) => Promise<boolean>;

/**
 * Call a `public.*` RPC from the browser and refresh the server tree afterwards.
 *
 * The database is the authorisation boundary: the RPC either succeeds or raises a
 * readable error, and the client never decides what the user may do.
 */
export function useRpc(): { run: RpcRunner; busy: boolean; error: string | null; clearError: () => void } {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const run = useCallback<RpcRunner>(
    async (fn, args = {}) => {
      setBusy(true);
      setError(null);
      try {
        const supabase = createClient();
        const { error: rpcError } = await supabase.rpc(fn, clean(args));
        if (rpcError) {
          setError(rpcError.message);
          return false;
        }
        router.refresh();
        return true;
      } catch (cause) {
        setError(cause instanceof Error ? cause.message : 'The request could not be completed.');
        return false;
      } finally {
        setBusy(false);
      }
    },
    [router],
  );

  return { run, busy, error, clearError: () => setError(null) };
}
