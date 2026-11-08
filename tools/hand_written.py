#!/usr/bin/env python3
"""The objects the hand written migrations (064 and later) own.

`tools/build_migrations.py` regenerates migrations 001-063 from the live
catalogue dump.  The dump is taken from the live database, so it also carries
everything the hand written migrations create - and a build that copied those
objects into the generated files would create every one of them twice when the
set is applied to a fresh database, or reference an object that does not exist
yet.

`tools/build_migrations.py` keeps its own `HAND_WRITTEN_FUNCTIONS` /
`HAND_WRITTEN_TRIGGERS` lists for the functions and triggers it renders.  The
tables, on the other hand, are shared with `tools/build_rls.py`, which must
leave their policies out of 018 for the same reason: 068 creates the tables and
their policies together, long after 018 has run.

Keep this list in step with the hand written migrations: every table they
create, and every column they add to a table that the generated set creates,
belongs here.
"""
from __future__ import annotations

# 068_property_and_calendar.sql - the property hierarchy (land -> building ->
# floor -> room with their facilities and documents) and the calendar of
# events (academic + term calendars, weeks, days and holidays).
HAND_WRITTEN_TABLES = frozenset({
    "building_document",
    "calendar",
    "calendar_term_schedule",
    "calendar_week",
    "calendar_week_day",
    "facility_type",
    "floor",
    "floor_facility",
    "holiday",
    "land",
    "land_document",
    "room_facility",
})

# Columns 068 hangs onto the tables the generated set creates, with the
# constraints it adds for them.  001 must keep rendering `building` and `room`
# exactly as they were before 068, or its `REFERENCES public.land` would point
# at a table that does not exist yet.
HAND_WRITTEN_COLUMNS = {
    "building": ("land_id", "total_floors", "construction_year"),
    "room": ("floor_id", "area_sqft"),
}

HAND_WRITTEN_CONSTRAINTS = frozenset({
    "fk_building_land",
    "fk_room_floor",
})


def strip_hand_written_tables(cat: dict) -> dict:
    """Remove the hand written tables and everything that hangs off them.

    A table that 068 creates must not be re-created by 001, must not get its
    RLS enabled by 016, its policies from 018, its triggers from 020, its
    grants or sequence grants from 021, its identity sequence resynced by 015 -
    all of those run before 068, where the table does not exist yet.  The
    composite row types the tables bring along, and the columns 068 adds to
    `building` and `room`, go the same way.
    """
    tables = HAND_WRITTEN_TABLES
    cat["tables"] = [t for t in cat["tables"] if t.get("name") not in tables]
    for t in cat["tables"]:
        if t.get("name") in HAND_WRITTEN_COLUMNS:
            drop = HAND_WRITTEN_COLUMNS[t["name"]]
            t["columns"] = [c for c in t.get("columns", []) if c.get("name") not in drop]
            t["constraints"] = [
                c for c in t.get("constraints", [])
                if c.get("name") not in HAND_WRITTEN_CONSTRAINTS
            ]
    cat["policies"] = [p for p in cat["policies"] if p.get("table") not in tables]
    cat["indexes"] = [i for i in cat["indexes"] if i.get("table") not in tables]
    sequences = [
        s for s in cat.get("sequences", [])
        if len((s.get("owned_by") or "").split(".")) >= 3
        and (s.get("owned_by") or "").split(".")[1] in tables
    ]
    cat["sequences"] = [
        s for s in cat.get("sequences", [])
        if len((s.get("owned_by") or "").split(".")) < 3
        or (s.get("owned_by") or "").split(".")[1] not in tables
    ]
    objects = tables | {s["name"] for s in sequences}
    cat["grants"] = [g for g in cat["grants"] if g.get("object") not in objects]
    cat["composites"] = [c for c in cat.get("composites", []) if c.get("name") not in tables]
    return cat
