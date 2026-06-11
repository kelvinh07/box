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
-- Currency: ALL tiers cost GEMS. Tiers 1-3 are open to everyone; tiers 4-6 require 5
-- rebirths and tiers 7-9 require 10 rebirths to buy (see ShovelConfig.tierUnlockRebirths).

local ShovelConfig = {}

ShovelConfig.MaxLevel = 9

-- Hold-to-dig is floored here so a dig is never instant, no matter the shovel.
ShovelConfig.MinDigTime = 0.3

-- Index = level. Level 0 means "not purchased" (bare hands).
-- DigSpeedMult is strictly increasing; the 0.3s floor keeps top tiers non-instant.
ShovelConfig.Levels = {
	[1] = { Name = "Wood",    DigSpeedMult = 1.15, Cost = 15,   Currency = "Gems" },
	[2] = { Name = "Stone",   DigSpeedMult = 1.35, Cost = 40,   Currency = "Gems" },
	[3] = { Name = "Glass",   DigSpeedMult = 1.60, Cost = 90,   Currency = "Gems" },
	[4] = { Name = "Copper",  DigSpeedMult = 1.90, Cost = 180,  Currency = "Gems" },
	[5] = { Name = "Iron",    DigSpeedMult = 2.25, Cost = 320,  Currency = "Gems" },
	[6] = { Name = "Gold",    DigSpeedMult = 2.65, Cost = 550,  Currency = "Gems" },
	[7] = { Name = "Emerald", DigSpeedMult = 2.95, Cost = 900,  Currency = "Gems" },
	[8] = { Name = "Diamond", DigSpeedMult = 3.10, Cost = 1500, Currency = "Gems" },
	[9] = { Name = "Galaxy",  DigSpeedMult = 3.20, Cost = 2500, Currency = "Gems" },
}

-- ZONE-based dig timing (SHARED by the client DigSite prompt/animation AND the server
-- DiggingManager cooldown). Every egg in a zone digs in the same BASE time regardless of
-- rarity; deeper zones take longer; the shovel multiplier divides it back down.
ShovelConfig.PerStage = 0.32 -- seconds per pop "bounce" step the egg rises in (animation only)
-- Base dig seconds per zone at shovel mult 1 (no shovel). Climbs deeper in, CAPPED at 60s
-- (1 minute). The shovel multiplier divides this back down (floored at MinDigTime 0.3s).
ShovelConfig.ZoneDigSeconds = { [1] = 5, [2] = 7, [3] = 10, [4] = 14, [5] = 20, [6] = 30, [7] = 45, [8] = 60 }
ShovelConfig.DefaultDigSeconds = 60 -- base dig seconds for zones beyond the table (capped at 1 min)
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
-- Returns (0, "Gems") for out-of-range levels (e.g. 0 or > MaxLevel).
function ShovelConfig.cost(level: number): (number, string)
	local entry = ShovelConfig.Levels[level]
	if not entry then
		return 0, "Gems"
	end
	return entry.Cost, entry.Currency
end

-- Rebirths required to BUY a shovel tier: tiers 1-3 open (0), tiers 4-6 need 5,
-- tiers 7-9 need 10. (Tunable gating thresholds.)
function ShovelConfig.tierUnlockRebirths(level: number): number
	if level >= 7 then
		return 10
	elseif level >= 4 then
		return 5
	end
	return 0
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
