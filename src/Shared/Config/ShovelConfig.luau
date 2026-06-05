--!strict
-- ShovelConfig
-- Shovel upgrades that speed up digging eggs out of the ground.
--
-- 9 tiers. Each level raises DigSpeedMult, which SHORTENS the hold-to-dig time:
--   time = max(MinDigTime, stages * PerStage / mult).
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

-- Per-rarity hold-to-dig timing (SHARED by the client DigSite render/prompt AND the
-- server DiggingManager cooldown, so rarer eggs take longer to dig on BOTH sides).
-- Rarer eggs take MORE hold stages; hold time = stages * PerStage / DigSpeedMult.
ShovelConfig.PerStage = 0.32 -- seconds of hold per pop stage
ShovelConfig.Stages = {
	Common    = 3, -- ~0.96s @ mult 1
	Uncommon  = 5, -- ~1.60s
	Rare      = 7, -- ~2.24s
	Legendary = 9, -- ~2.88s
	Mythic    = 9,
}
-- Server cooldown slack vs the client hold time: the server gates on a slightly
-- SHORTER duration so latency/jitter on a fully-held dig never falsely rejects it.
ShovelConfig.CooldownTolerance = 0.85

-- Hold-to-dig duration (seconds) for `rarity` at shovel multiplier `mult`. Mirrors
-- the client prompt's HoldDuration. Floored at MinDigTime (0.3s) so digging is never
-- instant. Unknown rarities fall back to Common.
function ShovelConfig.holdDuration(rarity: string, mult: number): number
	local stages = ShovelConfig.Stages[rarity] or ShovelConfig.Stages.Common
	return math.max(ShovelConfig.MinDigTime, (stages * ShovelConfig.PerStage) / mult)
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
