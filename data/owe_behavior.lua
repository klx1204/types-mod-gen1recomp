-- Overworld behaviour per species, mirroring pokeemerald-expansion's
-- gOWESpeciesBehavior (src/data/pokemon/wild_encounter_ow_behavior.h).
--
-- The shipped expansion sets no species at all, so every wild Pokemon uses
-- "ignore": it wanders on its encounter tiles and waits to be bumped into.
-- Add rows to opt a species into something livelier.
--
-- Keys: ignore, chase, flee, watch, approach, despawn
-- Speeds and ranges come from the table in visible_wild.lua:
--   view 4 tiles deep, 3 wide, gives up past 5 tiles.
--
-- Example:
--   [261] = "chase",    -- Poochyena runs the player down
--   [41]  = "flee",     -- Zubat bolts
return {
}
