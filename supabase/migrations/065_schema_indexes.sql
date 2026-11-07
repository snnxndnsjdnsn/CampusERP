-- 065. SCHEMA INDEXES CATALOGUE RPC
-- =============================================================================================
-- Why this file exists:
--   * Module 18 (PERFORMANCE INDEXES) and module 38 (PERFORMANCE INDEXES) of the MySQL
--     specification describe the index catalogue of the schema.  The application has to
--     show that catalogue (index name, the table it belongs to, the columns it covers,
--     whether it is unique / primary and the CREATE INDEX statement itself), and the
--     only source of truth for it is the live PostgreSQL catalogue.
--   * The catalogue lives in `pg_catalog` (`pg_indexes`, `pg_index`, `pg_class`,
--     `pg_attribute`, `pg_policies`).  `pg_catalog` is not exposed by PostgREST, and the
--     browser cannot read it directly at all, so no client-side query can produce the
--     index list.  A read-only RPC in the `public` schema is the only way to hand the
--     index catalogue to the application.
--   * The permission check inside the function IS the gate.  `public.schema_indexes` is
--     SECURITY DEFINER, so it can read `pg_catalog` on behalf of the caller, but it
--     refuses to return anything unless the caller holds the matching global permission:
--       * scope 'all'   -> requires IAM.ALL.READ        (the full catalogue)
--       * scope 'staff' -> requires STAFF_PROFILE.ALL.READ (only the tables that carry a
--         STAFF_PROFILE row level policy, so a staff reader sees the indexes of the
--         staff profile tables and nothing else)
--     An unknown scope is rejected with SQLSTATE 22023 (invalid parameter value) and a
--     caller without the permission is rejected with SQLSTATE 42501 (insufficient
--     privilege), exactly like the other read RPCs of the project.
--   * The function is STABLE and read-only: it never writes and it pins its
--     `search_path` to 'public', 'pg_temp'.
--
-- Rules this file obeys:
--   * It only creates one function and grants EXECUTE on it - it never touches a table,
--     a policy or an existing function.
--   * The function is SECURITY DEFINER, so the owner of the function (the migration
--     runner) needs the rights to read `pg_catalog`; the caller does not.
--   * `CREATE OR REPLACE` makes the file idempotent: re-running it replaces the body
--     and leaves the catalogue unchanged.
-- =============================================================================================

CREATE OR REPLACE FUNCTION public.schema_indexes(p_scope text DEFAULT NULL)
RETURNS TABLE(
    index_name text,
    table_name text,
    index_columns text[],
    is_unique boolean,
    is_primary boolean,
    definition text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_scope text := lower(btrim(COALESCE(p_scope, 'all')));
BEGIN
    IF v_scope NOT IN ('all', 'staff') THEN
        RAISE EXCEPTION 'Unknown scope' USING ERRCODE = '22023';
    END IF;

    IF v_scope = 'staff' THEN
        IF NOT sims_private.can_global(ARRAY['STAFF_PROFILE.ALL.READ']::text[]) THEN
            RAISE EXCEPTION 'Not authorised (STAFF_PROFILE.ALL.READ)' USING ERRCODE = '42501';
        END IF;
    ELSE
        IF NOT sims_private.can_global(ARRAY['IAM.ALL.READ']::text[]) THEN
            RAISE EXCEPTION 'Not authorised (IAM.ALL.READ)' USING ERRCODE = '42501';
        END IF;
    END IF;

    RETURN QUERY
    SELECT ic.relname::text,
           tc.relname::text,
           COALESCE(
             (SELECT array_agg(a.attname::text ORDER BY k.ord)
                FROM unnest(ix.indkey) WITH ORDINALITY AS k(attnum, ord)
                JOIN pg_attribute a ON a.attrelid = ix.indrelid AND a.attnum = k.attnum),
             ARRAY[]::text[]
           ),
           ix.indisunique,
           ix.indisprimary,
           pg_get_indexdef(ix.indexrelid)::text
      FROM pg_index ix
      JOIN pg_class ic ON ic.oid = ix.indexrelid
      JOIN pg_class tc ON tc.oid = ix.indrelid
      JOIN pg_namespace n ON n.oid = tc.relnamespace
     WHERE n.nspname = 'public'
       AND (v_scope = 'all'
            OR tc.relname IN (
                 SELECT DISTINCT tablename FROM pg_policies
                  WHERE schemaname = 'public'
                    AND (qual LIKE '%STAFF_PROFILE.%' OR with_check LIKE '%STAFF_PROFILE.%')
            ))
     ORDER BY tc.relname, ic.relname;
END $function$;

GRANT EXECUTE ON FUNCTION public.schema_indexes(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.schema_indexes(text) TO postgres;
GRANT EXECUTE ON FUNCTION public.schema_indexes(text) TO service_role;
