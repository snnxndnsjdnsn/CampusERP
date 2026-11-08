-- =============================================================================================
-- 069. property_column_grants
-- ---------------------------------------------------------------------------------------------
-- Hand written.
--
-- 068 hung five columns onto tables the generated set creates - `building.land_id`,
-- `building.total_floors`, `building.construction_year`, `room.floor_id` and `room.area_sqft`.
-- The generated grants of 021 were rendered from the catalogue before those columns existed,
-- and `authenticated` reads tables column by column (a bare `SELECT *` is refused), so the five
-- new columns need their own column level SELECT grant or the Manage panel cannot read them.
-- =============================================================================================

GRANT SELECT (land_id, total_floors, construction_year) ON TABLE public.building TO authenticated;
GRANT SELECT (floor_id, area_sqft) ON TABLE public.room TO authenticated;
