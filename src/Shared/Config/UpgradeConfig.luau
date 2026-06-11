--!strict
-- UpgradeConfig
-- Gem-purchased Luck, the Incubator upgrade track, plus the Rebirth rules.
--
-- Luck: 9 tiers (all Gems). Each level adds a "luck value" that:
--   * shifts dig odds toward Rare/Legendary eggs, and
--   * improves variant roll odds (Gold/Diamond/Galaxy).
-- Total luck = sum of unlocked Luck tier Values ONLY. Rebirth grants NO luck.
--
-- Incubator (formerly "HatchSpeed"): 9 named tiers. Each level increases the
-- incubation-time reduction toward ~0.95. Currency: ALL tiers cost GEMS now; tiers 1-3
-- are open, 4-6 need 5 rebirths, 7-9 need 10 rebirths (incubatorTierUnlockRebirths).
-- The 0.5s hatch floor lives in IncubationManager (so hatching is never instant).
--
-- Rebirth: a permanent, compounding CASH multiplier (1.35^rb). There is NO gem multiplier.
-- Rebirth is gated purely by LIFETIME cash (cashMilestone) and no longer costs gems.
-- The level-cost multiplier (1.5^rb) still scales cash level-up costs.

local UpgradeConfig = {}

----------------------------------------------------------------------------- LUCK
-- Index = level. Level 0 means "not purchased". 9 tiers, all Gems. Max tier = 9.
UpgradeConfig.Luck = {
	MaxLevel = 9,
	Levels = {
		[1] = { GemCost = 80,    Value = 0.15 },
		[2] = { GemCost = 250,   Value = 0.35 },
		[3] = { GemCost = 650,   Value = 0.60 },
		[4] = { GemCost = 1500,  Value = 0.90 },
		[5] = { GemCost = 3500,  Value = 1.30 },
		[6] = { GemCost = 7500,  Value = 1.80 },
		[7] = { GemCost = 15000, Value = 2.40 },
		[8] = { GemCost = 30000, Value = 3.10 },
		[9] = { GemCost = 60000, Value = 4.00 },
	},
}

------------------------------------------------------------------------ INCUBATOR
-- Index = level. Level 0 means "not purchased". 9 named tiers. Max tier = 9.
-- Reduction is strictly increasing toward ~0.95. Currency: 1-5 Cash, 6-9 Gems.
UpgradeConfig.Incubator = {
	MaxLevel = 9,
	Levels = {
		[1] = { Name = "Hay Nest",            Reduction = 0.10, Cost = 20,   Currency = "Gems" },
		[2] = { Name = "Clay Kiln",           Reduction = 0.20, Cost = 50,   Currency = "Gems" },
		[3] = { Name = "Copper Warmer",       Reduction = 0.30, Cost = 110,  Currency = "Gems" },
		[4] = { Name = "Crystal Chamber",     Reduction = 0.40, Cost = 220,  Currency = "Gems" },
		[5] = { Name = "Arcane Forge",        Reduction = 0.50, Cost = 400,  Currency = "Gems" },
		[6] = { Name = "Volcanic Cradle",     Reduction = 0.62, Cost = 650,  Currency = "Gems" },
		[7] = { Name = "Quantum Pod",         Reduction = 0.74, Cost = 1000, Currency = "Gems" },
		[8] = { Name = "Celestial Nest",      Reduction = 0.85, Cost = 1600, Currency = "Gems" },
		[9] = { Name = "The Primordial Core", Reduction = 0.95, Cost = 2600, Currency = "Gems" },
	},
}

------------------------------------------------------------------------- REBIRTH
UpgradeConfig.Rebirth = {
	-- LIFETIME cash required to PERFORM each rebirth, indexed by the rebirth NUMBER you are
	-- working toward (1 = your first rebirth). LifetimeCash is CUMULATIVE and NEVER resets, so
	-- each entry is the absolute total ever-earned cash needed to unlock that rebirth. Beyond
	-- #12: previous * MilestoneGrowth (floored). Tuned STARTER values — edit freely.
	LifetimeMilestones = {
		[1]  = 3600,
		[2]  = 51800,
		[3]  = 223900,
		[4]  = 749800,
		[5]  = 2220300,
		[6]  = 6206400,
		[7]  = 16574600,
		[8]  = 42908700,
		[9]  = 108603700,
		[10] = 270201500,
		[11] = 663221800,
		[12] = 1610196300,
	},
	MilestoneGrowth = 2.4,
}

------------------------------------------------------------------------- HELPERS

-- Total Luck value for a player. `rebirths` is accepted for signature
-- compatibility but IGNORED (rebirth grants no luck). Total = sum of unlocked
-- Luck tier Values only.
function UpgradeConfig.totalLuck(luckLevel: number, rebirths: number?): number
	local total = 0
	for lvl = 1, math.min(luckLevel, UpgradeConfig.Luck.MaxLevel) do
		total += UpgradeConfig.Luck.Levels[lvl].Value
	end
	return total
end

-- Total incubation reduction (0..0.95) for an incubator level. Level 0 = 0.
function UpgradeConfig.incubatorReduction(incubatorLevel: number): number
	local lvl = math.clamp(incubatorLevel, 0, UpgradeConfig.Incubator.MaxLevel)
	if lvl == 0 then
		return 0
	end
	return UpgradeConfig.Incubator.Levels[lvl].Reduction
end

-- Rebirths required to BUY an incubator tier: tiers 1-3 open (0), 4-6 need 5, 7-9 need 10.
function UpgradeConfig.incubatorTierUnlockRebirths(level: number): number
	if level >= 7 then
		return 10
	elseif level >= 4 then
		return 5
	end
	return 0
end

-- LIFETIME cash required for a player with `rebirthCount` rebirths to do their NEXT rebirth
-- (i.e. the requirement for rebirth #rebirthCount+1). Table for 1..12, then *MilestoneGrowth.
function UpgradeConfig.cashMilestone(rebirthCount: number): number
	local target = (rebirthCount or 0) + 1
	local m = UpgradeConfig.Rebirth.LifetimeMilestones
	if m[target] then
		return m[target]
	end
	local value = m[12]
	for _ = 13, target do
		value = math.floor(value * UpgradeConfig.Rebirth.MilestoneGrowth)
	end
	return value
end

-- Rebirth no longer costs Gems (it is gated purely by LIFETIME cash). Kept returning 0
-- for backward compatibility with any caller/snapshot that still references it.
function UpgradeConfig.gemCost(_rebirthCount: number): number
	return 0
end

-- Permanent, compounding rebirth income multipliers + the level-cost multiplier.
-- These are derived purely from the rebirth count.
-- Rebirth grants NO gem multiplier — gem income is fixed per brainrot. Always 1.
function UpgradeConfig.gemMultiplier(_rebirths: number): number
	return 1
end

-- Permanent, compounding CASH multiplier: 1.35x per rebirth.
function UpgradeConfig.cashMultiplier(rebirths: number): number
	return 1.35 ^ rebirths
end

function UpgradeConfig.levelCostMultiplier(rebirths: number): number
	return 1.5 ^ rebirths
end

return UpgradeConfig
