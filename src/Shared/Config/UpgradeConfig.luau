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
-- incubation-time reduction toward ~0.95. Currency: tiers 1-5 Cash, 6-9 Gems.
-- The 0.5s hatch floor lives in IncubationManager (so hatching is never instant).
--
-- Rebirth: permanent, compounding income multipliers (cash 1.2^rb, gems 1.5^rb)
-- and the level-cost multiplier (1.5^rb). The cash milestone is driven by
-- LifetimeCash; the gem cost is charged from Gems. See cashMilestone/gemCost.

local UpgradeConfig = {}

----------------------------------------------------------------------------- LUCK
-- Index = level. Level 0 means "not purchased". 9 tiers, all Gems. Max tier = 9.
UpgradeConfig.Luck = {
	MaxLevel = 9,
	Levels = {
		[1] = { GemCost = 50,    Value = 0.15 },
		[2] = { GemCost = 150,   Value = 0.35 },
		[3] = { GemCost = 400,   Value = 0.60 },
		[4] = { GemCost = 1000,  Value = 0.90 },
		[5] = { GemCost = 2500,  Value = 1.30 },
		[6] = { GemCost = 6000,  Value = 1.80 },
		[7] = { GemCost = 12000, Value = 2.40 },
		[8] = { GemCost = 25000, Value = 3.10 },
		[9] = { GemCost = 50000, Value = 4.00 },
	},
}

------------------------------------------------------------------------ INCUBATOR
-- Index = level. Level 0 means "not purchased". 9 named tiers. Max tier = 9.
-- Reduction is strictly increasing toward ~0.95. Currency: 1-5 Cash, 6-9 Gems.
UpgradeConfig.Incubator = {
	MaxLevel = 9,
	Levels = {
		[1] = { Name = "Hay Nest",            Reduction = 0.10, Cost = 100,  Currency = "Cash" },
		[2] = { Name = "Clay Kiln",           Reduction = 0.20, Cost = 300,  Currency = "Cash" },
		[3] = { Name = "Copper Warmer",       Reduction = 0.30, Cost = 800,  Currency = "Cash" },
		[4] = { Name = "Crystal Chamber",     Reduction = 0.40, Cost = 2000, Currency = "Cash" },
		[5] = { Name = "Arcane Forge",        Reduction = 0.50, Cost = 5000, Currency = "Cash" },
		[6] = { Name = "Volcanic Cradle",     Reduction = 0.62, Cost = 200,  Currency = "Gems" },
		[7] = { Name = "Quantum Pod",         Reduction = 0.74, Cost = 600,  Currency = "Gems" },
		[8] = { Name = "Celestial Nest",      Reduction = 0.85, Cost = 1500, Currency = "Gems" },
		[9] = { Name = "The Primordial Core", Reduction = 0.95, Cost = 4000, Currency = "Gems" },
	},
}

------------------------------------------------------------------------- REBIRTH
UpgradeConfig.Rebirth = {
	-- LifetimeCash you must reach to be allowed your NEXT rebirth (indexed by
	-- rebirthCount). For rebirthCount >= 5: previous * 2.5 (floored).
	CashMilestones = { [0] = 50000, [1] = 150000, [2] = 400000, [3] = 1000000, [4] = 2500000 },
	CashMilestoneGrowth = 2.5,
	-- Gem cost of your NEXT rebirth (indexed by rebirthCount). For
	-- rebirthCount >= 5: previous * 1.75 (floored).
	GemCosts = { [0] = 500, [1] = 875, [2] = 1531, [3] = 2678, [4] = 4687 },
	GemCostGrowth = 1.75,
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

-- LifetimeCash milestone required for the rebirth at `rebirthCount`.
-- Table for 0..4, then *2.5 compounding (floored) beyond.
function UpgradeConfig.cashMilestone(rebirthCount: number): number
	local milestones = UpgradeConfig.Rebirth.CashMilestones
	if milestones[rebirthCount] then
		return milestones[rebirthCount]
	end
	local value = milestones[4]
	for _ = 5, rebirthCount do
		value = math.floor(value * UpgradeConfig.Rebirth.CashMilestoneGrowth)
	end
	return value
end

-- Gem cost of the rebirth at `rebirthCount` (the cost of your NEXT rebirth).
-- Table for 0..4, then *1.75 compounding (floored) beyond.
function UpgradeConfig.gemCost(rebirthCount: number): number
	local costs = UpgradeConfig.Rebirth.GemCosts
	if costs[rebirthCount] then
		return costs[rebirthCount]
	end
	local value = costs[4]
	for _ = 5, rebirthCount do
		value = math.floor(value * UpgradeConfig.Rebirth.GemCostGrowth)
	end
	return value
end

-- Permanent, compounding rebirth income multipliers + the level-cost multiplier.
-- These are derived purely from the rebirth count.
function UpgradeConfig.gemMultiplier(rebirths: number): number
	return 1.5 ^ rebirths
end

function UpgradeConfig.cashMultiplier(rebirths: number): number
	return 1.2 ^ rebirths
end

function UpgradeConfig.levelCostMultiplier(rebirths: number): number
	return 1.5 ^ rebirths
end

return UpgradeConfig
