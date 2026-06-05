--!strict
-- BrainrotConfig
-- The base roster of Italian Brainrot memes. Each entry defines:
--   Tier       - which egg tier hatches it
--   BaseCash   - LEGACY: no longer used by income (kept for reference only)
--   BaseGem    - LEGACY: no longer used by income (kept for reference only)
--   Color      - chunky placeholder color (also used as a glow accent)
--   Scale      - relative model size on the podium
--
-- INCOME is now TIER-BASED (see BrainrotConfig.TierIncome) and scaled by the
-- variant, the per-brainrot level, and the rebirth multipliers — see BrainrotMath.
-- The per-brainrot BaseCash/BaseGem fields below are UNUSED by income; they are
-- left in place so older tooling/asset wiring keeps working.
--
-- Variants (Normal/Gold/Diamond/Galaxy) multiply these stats — see VariantConfig.
--
-- The same base roster is reused across all variants so the roster stays small.

export type Brainrot = {
	Name: string,
	Tier: string,
	BaseCash: number,
	BaseGem: number,
	Color: Color3,
	Scale: number,
}

local BrainrotConfig = {}

-- Per-tier income, expressed PER MINUTE (BrainrotMath divides by 60 for the 1s loop).
-- This is the single tier-based income table; variant multiplier, per-brainrot level
-- multiplier (1.2^(level-1)) and the rebirth multipliers are layered on in BrainrotMath.
BrainrotConfig.TierIncome = {
	Common    = { CashPerMin = 10,   GemPerMin = 0 },
	Uncommon  = { CashPerMin = 35,   GemPerMin = 0 },
	Rare      = { CashPerMin = 120,  GemPerMin = 1 },
	Legendary = { CashPerMin = 500,  GemPerMin = 5 },
	Mythic    = { CashPerMin = 2000, GemPerMin = 15 },
}

-- Per-brainrot leveling. Cap is 10; entry.level lives in 1..10 (default 1).
-- Costs are the BASE cost of reaching the target level, BEFORE the rebirth
-- levelCostMultiplier (1.5^rebirthCount) is applied. Currency: levels 2-5 = Cash,
-- levels 6-10 = Gems.
BrainrotConfig.MaxLevel = 10
BrainrotConfig.Levels = {
	[2]  = { Cost = 200,   Currency = "Cash" },
	[3]  = { Cost = 600,   Currency = "Cash" },
	[4]  = { Cost = 1500,  Currency = "Cash" },
	[5]  = { Cost = 3500,  Currency = "Cash" },
	[6]  = { Cost = 500,   Currency = "Gems" },
	[7]  = { Cost = 1200,  Currency = "Gems" },
	[8]  = { Cost = 3000,  Currency = "Gems" },
	[9]  = { Cost = 7500,  Currency = "Gems" },
	[10] = { Cost = 18000, Currency = "Gems" },
}

BrainrotConfig.Brainrots = {
	---------------------------------------------------------------- COMMON
	["Brr Brr Patapim"]      = { Tier = "Common",  BaseCash = 1,  BaseGem = 0,    Color = Color3.fromRGB(120, 200, 90),  Scale = 1.0 },
	["Boneca Ambalabu"]      = { Tier = "Common",  BaseCash = 1,  BaseGem = 0,    Color = Color3.fromRGB(90, 180, 220),  Scale = 1.0 },
	["Chimpanzini Bananini"] = { Tier = "Common",  BaseCash = 2,  BaseGem = 0,    Color = Color3.fromRGB(245, 215, 60),  Scale = 1.0 },
	["Trippi Troppi"]        = { Tier = "Common",  BaseCash = 2,  BaseGem = 0,    Color = Color3.fromRGB(230, 120, 200), Scale = 1.0 },
	["Frigo Camelo"]         = { Tier = "Common",  BaseCash = 3,  BaseGem = 0,    Color = Color3.fromRGB(150, 220, 235), Scale = 1.1 },

	---------------------------------------------------------------- UNCOMMON
	["Cappuccino Assassino"] = { Tier = "Uncommon", BaseCash = 5,  BaseGem = 0,   Color = Color3.fromRGB(90, 60, 40),    Scale = 1.1 },
	["Ballerina Cappuccina"] = { Tier = "Uncommon", BaseCash = 6,  BaseGem = 0,   Color = Color3.fromRGB(210, 150, 90),  Scale = 1.1 },
	["Lirilì Larilà"]        = { Tier = "Uncommon", BaseCash = 7,  BaseGem = 0,   Color = Color3.fromRGB(120, 220, 180), Scale = 1.1 },
	["Bombombini Gusini"]    = { Tier = "Uncommon", BaseCash = 8,  BaseGem = 0,   Color = Color3.fromRGB(160, 200, 80),  Scale = 1.15 },

	---------------------------------------------------------------- RARE
	["Tung Tung Tung Sahur"] = { Tier = "Rare", BaseCash = 18, BaseGem = 0.05,    Color = Color3.fromRGB(150, 110, 70),  Scale = 1.25 },
	["Bombardiro Crocodilo"] = { Tier = "Rare", BaseCash = 22, BaseGem = 0.06,    Color = Color3.fromRGB(70, 130, 60),   Scale = 1.3 },
	["Tralalero Tralala"]    = { Tier = "Rare", BaseCash = 26, BaseGem = 0.08,    Color = Color3.fromRGB(60, 160, 230),  Scale = 1.3 },

	---------------------------------------------------------------- LEGENDARY
	["Trippa Troppa Tralala Lirili Rilà Tung Tung Sahur Boneca"] = {
		Tier = "Legendary", BaseCash = 150, BaseGem = 0.25,
		Color = Color3.fromRGB(255, 175, 35), Scale = 1.8,
	},

	---------------------------------------------------------------- MYTHIC (Zone 2+ exclusive, invented)
	["Spaghettini Vesuviano"]          = { Tier = "Mythic", BaseCash = 320,  BaseGem = 0.5,  Color = Color3.fromRGB(255, 90, 60),   Scale = 1.6 },
	["Cocco Locco Bombardino"]         = { Tier = "Mythic", BaseCash = 380,  BaseGem = 0.6,  Color = Color3.fromRGB(120, 70, 200),  Scale = 1.7 },
	["Frulli Frulla Mortadella"]       = { Tier = "Mythic", BaseCash = 450,  BaseGem = 0.7,  Color = Color3.fromRGB(255, 70, 150),  Scale = 1.7 },
	["Ananasso Tralaledino Supremo"]   = { Tier = "Mythic", BaseCash = 600,  BaseGem = 0.9,  Color = Color3.fromRGB(255, 220, 40),  Scale = 1.9 },
	["Polpettone Galattico Crocofanto"]= { Tier = "Mythic", BaseCash = 850,  BaseGem = 1.2,  Color = Color3.fromRGB(80, 255, 230),  Scale = 2.0 },
}

-- Returns a list of brainrot names belonging to a tier.
function BrainrotConfig.namesByTier(tier: string): { string }
	local out = {}
	for name, data in pairs(BrainrotConfig.Brainrots) do
		if data.Tier == tier then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

function BrainrotConfig.get(name: string)
	return BrainrotConfig.Brainrots[name]
end

-- Per-brainrot level multiplier (applies to BOTH cash and gems).
-- Level 1 = 1x; Level 10 = 1.2^9 = 5.16x.
function BrainrotConfig.levelMult(level: number): number
	return 1.2 ^ ((level or 1) - 1)
end

-- BASE cost (and currency) to reach `targetLevel`, BEFORE rebirth scaling.
-- Returns (0, "Cash") for out-of-range levels (e.g. <=1 or >MaxLevel).
function BrainrotConfig.levelUpCost(targetLevel: number): (number, string)
	local entry = BrainrotConfig.Levels[targetLevel]
	if not entry then
		return 0, "Cash"
	end
	return entry.Cost, entry.Currency
end

-- Per-MINUTE base income for a tier (cash, gem), before variant/level/rebirth.
-- Unknown tiers fall back to Common.
function BrainrotConfig.tierIncomePerMin(tier: string): (number, number)
	local income = BrainrotConfig.TierIncome[tier] or BrainrotConfig.TierIncome.Common
	return income.CashPerMin, income.GemPerMin
end

return BrainrotConfig
