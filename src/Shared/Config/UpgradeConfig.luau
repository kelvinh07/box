--!strict
-- UpgradeConfig
-- Gem-purchased upgrades plus the Rebirth rules.
--
-- Luck: 5 tiers. Each level adds a "luck value" that:
--   * shifts dig odds toward Rare/Legendary eggs, and
--   * improves variant roll odds (Gold/Diamond/Galaxy).
-- Total luck = sum of unlocked Luck levels' Value + Rebirth luck bonus.
--
-- HatchSpeed: 5 tiers. Each level increases incubation-time reduction.
-- HARD CAPPED at 0.50 (50%) so eggs can never hatch faster than half time.

local UpgradeConfig = {}

UpgradeConfig.MaxHatchSpeedReduction = 0.50 -- hard cap, never exceed

-- Index = level. Level 0 means "not purchased".
UpgradeConfig.Luck = {
	MaxLevel = 5,
	Levels = {
		[1] = { GemCost = 50,   Value = 0.15 },
		[2] = { GemCost = 150,  Value = 0.35 },
		[3] = { GemCost = 400,  Value = 0.60 },
		[4] = { GemCost = 1000, Value = 0.90 },
		[5] = { GemCost = 2500, Value = 1.30 },
	},
}

UpgradeConfig.HatchSpeed = {
	MaxLevel = 5,
	Levels = {
		[1] = { GemCost = 40,   Reduction = 0.10 },
		[2] = { GemCost = 120,  Reduction = 0.20 },
		[3] = { GemCost = 320,  Reduction = 0.30 },
		[4] = { GemCost = 800,  Reduction = 0.40 },
		[5] = { GemCost = 2000, Reduction = 0.50 }, -- == cap
	},
}

-- Rebirth rules
UpgradeConfig.Rebirth = {
	-- Cash you must reach (in your CURRENT zone scaling) to be allowed to rebirth.
	CashMilestone = 50000,
	-- Gem cost scales with how many rebirths you've already done.
	BaseGemCost = 100,
	GemCostGrowth = 1.75,
	-- Permanent luck granted per rebirth (added to total luck forever).
	LuckBonusPerRebirth = 0.10,
}

-- Total Luck value for a player given their luck level and rebirth count.
function UpgradeConfig.totalLuck(luckLevel: number, rebirths: number): number
	local total = 0
	for lvl = 1, math.min(luckLevel, UpgradeConfig.Luck.MaxLevel) do
		total += UpgradeConfig.Luck.Levels[lvl].Value
	end
	total += rebirths * UpgradeConfig.Rebirth.LuckBonusPerRebirth
	return total
end

-- Total incubation reduction (0..cap) for a hatch-speed level.
function UpgradeConfig.hatchReduction(hatchSpeedLevel: number): number
	local lvl = math.clamp(hatchSpeedLevel, 0, UpgradeConfig.HatchSpeed.MaxLevel)
	if lvl == 0 then
		return 0
	end
	local reduction = UpgradeConfig.HatchSpeed.Levels[lvl].Reduction
	return math.min(reduction, UpgradeConfig.MaxHatchSpeedReduction)
end

-- Gem cost of the player's NEXT rebirth.
function UpgradeConfig.rebirthGemCost(rebirths: number): number
	return math.floor(
		UpgradeConfig.Rebirth.BaseGemCost
			* (UpgradeConfig.Rebirth.GemCostGrowth ^ rebirths)
	)
end

return UpgradeConfig
