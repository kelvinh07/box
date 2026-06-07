--!strict
-- ShovelConfig
-- Shovel upgrades that speed up digging eggs out of the ground.
--
-- 9 tiers. Each level raises DigSpeedMult, which SHORTENS the hold-to-dig time:
--   time = max(MinDigTime, ZoneDigSeconds[zone] / mult).
-- DIG TIME IS ZONE-BASED, NOT rarity-based: every egg in a zone takes the SAME base time
-- to dig (so you can't tell a Common from a Legendary by the dig length), and deeper zones
-- dig slower — which is exactly what better shovels speed back up.
-- Bigger mult = faster digging, but the MinDigTime (0.3s) floor guarantees a dig
-- is NEVER instant even at the top tier. Level 0 means "bare hands" (no shovel)
-- and digs at the base rate (mult 1.0). Tier 9 is the max shovel.
--
-- Currency: tiers 1-5 cost Cash, tiers 6-9 cost Gems.

local ShovelConfig = {}

ShovelConfig.MaxLevel = 9

-- Hold-to-dig is floored here so a dig is never instant, no matter the shovel.
ShovelConfig.MinDigTime = 0.3

-- Index = level. Level 0 means "not purchased" (bare hands).
-- DigSpeedMult is strictly increasing; the 0.3s floor keeps top tiers non-instant.
ShovelConfig.Levels = {
	[1] = { Name = "Wood",    DigSpeedMult = 1.15, Cost = 50,   Currency = "Cash" },
	[2] = { Name = "Stone",   DigSpeedMult = 1.35, Cost = 150,  Currency = "Cash" },
	[3] = { Name = "Glass",   DigSpeedMult = 1.60, Cost = 400,  Currency = "Cash" },
	[4] = { Name = "Copper",  DigSpeedMult = 1.90, Cost = 1000, Currency = "Cash" },
	[5] = { Name = "Iron",    DigSpeedMult = 2.25, Cost = 2500, Currency = "Cash" },
	[6] = { Name = "Gold",    DigSpeedMult = 2.65, Cost = 100,  Currency = "Gems" },
	[7] = { Name = "Emerald", DigSpeedMult = 2.95, Cost = 300,  Currency = "Gems" },
	[8] = { Name = "Diamond", DigSpeedMult = 3.10, Cost = 800,  Currency = "Gems" },
	[9] = { Name = "Galaxy",  DigSpeedMult = 3.20, Cost = 2000, Currency = "Gems" },
}

-- ZONE-based dig timing (SHARED by the client DigSite prompt/animation AND the server
-- DiggingManager cooldown). Every egg in a zone digs in the same BASE time regardless of
-- rarity; deeper zones take longer; the shovel multiplier divides it back down.
ShovelConfig.PerStage = 0.32 -- seconds per pop "bounce" step the egg rises in (animation only)
ShovelConfig.ZoneDigSeconds = { [1] = 10, [2] = 13, [3] = 16 } -- base dig seconds per zone (mult 1)
ShovelConfig.DefaultDigSeconds = 16 -- base dig seconds for zones beyond the table (future)
-- Server cooldown slack vs the client hold time: the server gates on a slightly SHORTER
-- duration so latency/jitter on a fully-held dig never falsely rejects it.
ShovelConfig.CooldownTolerance = 0.85

-- Base seconds to dig ANY egg in `zone` (before the shovel multiplier).
function ShovelConfig.zoneDigSeconds(zone: number): number
	return ShovelConfig.ZoneDigSeconds[zone] or ShovelConfig.DefaultDigSeconds
end

-- Hold-to-dig duration (seconds) for `zone` at shovel multiplier `mult`. Mirrors the
-- client prompt's HoldDuration. Floored at MinDigTime (0.3s) so digging is never instant.
function ShovelConfig.zoneDigDuration(zone: number, mult: number): number
	return math.max(ShovelConfig.MinDigTime, ShovelConfig.zoneDigSeconds(zone) / mult)
end

-- The level table for a given level (or nil if out of range / level 0).
function ShovelConfig.get(level: number): any?
	return ShovelConfig.Levels[level]
end

-- Cost + currency to purchase shovel `level` (the cost to OWN that tier).
-- Returns (0, "Cash") for out-of-range levels (e.g. 0 or > MaxLevel).
function ShovelConfig.cost(level: number): (number, string)
	local entry = ShovelConfig.Levels[level]
	if not entry then
		return 0, "Cash"
	end
	return entry.Cost, entry.Currency
end

-- Dig-speed multiplier for a shovel level. Level 0 (bare hands) returns 1.0.
function ShovelConfig.digSpeedMult(level: number): number
	local lvl = math.clamp(level, 0, ShovelConfig.MaxLevel)
	if lvl == 0 then
		return 1.0
	end
	return ShovelConfig.Levels[lvl].DigSpeedMult
end

return ShovelConfig
