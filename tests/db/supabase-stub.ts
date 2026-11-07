/**
 * A minimal stand-in for the Supabase platform inside embedded PostgreSQL (PGlite).
 *
 * It reproduces only what the migrations and the RLS policies actually touch:
 * the auth schema, the storage schema, the vault schema and the three database
 * roles.  It is NOT a Supabase emulator — there is no PostgREST, no GoTrue and
 * no storage API.
 *
 * The SQL lives in a template literal so tools/validate/seed_counts.mjs can read
 * the same text straight out of this file by splitting on the backtick character.
 * The comment above deliberately contains no backtick of its own, so that the
 * first backtick-delimited chunk of this file is the SQL.
 */
export const SUPABASE_STUB = `
-- ---------------------------------------------------------------------------
-- Roles
-- ---------------------------------------------------------------------------
DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN BYPASSRLS;
  END IF;
END
$do$;

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- auth schema
-- ---------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS auth;
CREATE SCHEMA IF NOT EXISTS storage;

GRANT USAGE ON SCHEMA auth, storage TO anon, authenticated, service_role;

CREATE TABLE IF NOT EXISTS auth.users (
  id uuid PRIMARY KEY,
  email text UNIQUE,
  encrypted_password text,
  email_confirmed_at timestamptz,
  raw_user_meta_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS auth.mfa_factors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  friendly_name text,
  factor_type text NOT NULL,
  status text NOT NULL DEFAULT 'verified',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS auth.sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- The JWT claims are carried in session settings, exactly like PostgREST does.
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid
  LANGUAGE sql STABLE
  AS $fn$
    SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
  $fn$;

CREATE OR REPLACE FUNCTION auth.role() RETURNS text
  LANGUAGE sql STABLE
  AS $fn$
    SELECT COALESCE(NULLIF(current_setting('request.jwt.claim.role', true), ''), current_user)
  $fn$;

CREATE OR REPLACE FUNCTION auth.email() RETURNS text
  LANGUAGE sql STABLE
  AS $fn$
    SELECT NULLIF(current_setting('request.jwt.claim.email', true), '')
  $fn$;

CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb
  LANGUAGE sql STABLE
  AS $fn$
    SELECT COALESCE(NULLIF(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
  $fn$;

GRANT SELECT ON auth.users, auth.mfa_factors, auth.sessions TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION auth.uid(), auth.role(), auth.email(), auth.jwt() TO anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- storage schema
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS storage.buckets (
  id text PRIMARY KEY,
  name text NOT NULL,
  public boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS storage.objects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bucket_id text REFERENCES storage.buckets(id),
  name text NOT NULL,
  owner uuid,
  metadata jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS storage_objects_bucket_id_idx ON storage.objects (bucket_id);
CREATE INDEX IF NOT EXISTS storage_objects_name_idx ON storage.objects (name);

GRANT SELECT ON storage.buckets, storage.objects TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- vault schema
-- ---------------------------------------------------------------------------
-- Supabase Vault is a managed secret store.  The sims_private.pii_key() helper
-- reads the key from it, so the schema has to exist before the migrations run.
CREATE SCHEMA IF NOT EXISTS vault;

CREATE TABLE IF NOT EXISTS vault.secrets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  description text,
  secret text NOT NULL,
  key_id uuid,
  nonce bytea,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- The live view exposes the plaintext in the decrypted_secret column; the stub
-- stores the secret in the clear, so the two columns carry the same value.
CREATE OR REPLACE VIEW vault.decrypted_secrets AS
  SELECT id, name, description, secret, secret AS decrypted_secret,
         key_id, nonce, created_at, updated_at
    FROM vault.secrets;

GRANT USAGE ON SCHEMA vault TO authenticated, service_role;
GRANT SELECT ON vault.secrets, vault.decrypted_secrets TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- extensions schema
-- ---------------------------------------------------------------------------
-- On a real Supabase project the extensions live in their own schema and the
-- migrations call them qualified (extensions.pgp_sym_encrypt, ...), so the
-- stub has to provide the same schema with pgcrypto installed into it.
CREATE SCHEMA IF NOT EXISTS extensions;

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

GRANT USAGE ON SCHEMA extensions TO anon, authenticated, service_role;
`;

/**
 * The PGlite-only part of the Supabase stand-in.
 *
 * On a real Supabase project pgcrypto is installed into the extensions schema,
 * and the live database calls it as extensions.pgp_sym_encrypt,
 * extensions.hmac, extensions.crypt and so on.  PGlite has no extensions
 * schema, so the extension is installed there explicitly.
 *
 * This is kept apart from SUPABASE_STUB because the stub is also replayed
 * against the live database, where the extensions schema already exists.
 */
export const PGLITE_SHIM = `
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto SCHEMA extensions;
`;
