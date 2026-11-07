-- =============================================================================================
-- 055. research_leftovers
-- ---------------------------------------------------------------------------------------------
-- GENERATED FILE - do not edit by hand.
-- Regenerate with: npm run migrate:build   (python tools/translate.py && python tools/build_migrations.py)
--
-- Source of truth: the live Supabase catalogue (tools/catalogue/live_catalogue.json),
-- dumped read-only from project khqqfgqvwdxlqkncwtmh by tools/dump_catalogue.py.
-- =============================================================================================

-- -----------------------------------------------------------------------------
-- This migration was consolidated.
--
-- The original per-feature file cannot be reconstructed from a catalogue
-- dump: a dump records the objects that exist, not the file that created
-- them.  The content that this version number used to carry therefore
-- lives in the consolidated files:
--
--   017  the `sims_private` schema and every helper function
--   018  every RLS policy
--   019  `my_context()` and the public read RPCs
--   020  every trigger
--   021  every grant and the remaining public functions
--
-- The version number is kept so that the migration history of the remote
-- project (001..063 already applied) stays aligned: the file name, the
-- ordering and the applied version are unchanged, only the payload moved.
-- -----------------------------------------------------------------------------
--
-- MySQL module 19: STAFF PROFILE REFERENCE / MASTER DATA
--
DO $consolidated$
BEGIN
  -- intentionally empty: the payload was consolidated into 017/018/019/020/021
END
$consolidated$;
