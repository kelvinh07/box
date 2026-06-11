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

-- Per-tier income. CASH is PER SECOND (integer; the 1s loop adds it directly, no /60) and
-- is scaled by variant/level/rebirth in BrainrotMath. GEMS are now a FIXED whole gems/SECOND
-- per tier (NOT per-minute): no /60, no level scaling, no rebirth multiplier — a brainrot
-- makes the same gems/sec forever. The variant adds a fixed flat gem/sec on top (VariantConfig).
-- Cash ladder ratios sit between Gold x2.2 and Diamond x3.6 so Gold(N) < Normal(N+1) < Diamond(N).
-- (Gem values are tunable starter values.)
BrainrotConfig.TierIncome = {
	Common    = { CashPerSec = 7,   GemPerSec = 0 },
	Uncommon  = { CashPerSec = 18,  GemPerSec = 1 },
	Rare      = { CashPerSec = 46,  GemPerSec = 2 },
	Epic      = { CashPerSec = 120, GemPerSec = 4 },
	Legendary = { CashPerSec = 310, GemPerSec = 7 },
	Mythic    = { CashPerSec = 900, GemPerSec = 12 }, -- no base-Mythic brainrots; safe fallback
}

-- Per-brainrot leveling. Cap is 30; entry.level lives in 1..30 (default 1).
-- Leveling is CASH ONLY and raises ONLY the brainrot's cash/sec (its gem/sec is FIXED — see
-- TierIncome). The cost to REACH each level grows smoothly (base * growth^(n-2), rounded to a
-- tidy number) and is the SAME for every brainrot (tier-independent), so leveling pays off most
-- on rarer brainrots. The rebirth levelCostMultiplier (1.5^rebirthCount) is layered on top in
-- EconomyManager. (Tunable: MaxLevel / base / growth.)
BrainrotConfig.MaxLevel = 30
BrainrotConfig.Levels = {}
do
	local base = 150   -- cash cost to reach level 2
	local growth = 1.4 -- each level costs ~40% more than the previous
	local function nice(n: number): number
		if n < 100 then
			return math.floor(n / 5 + 0.5) * 5
		end
		local digits = math.floor(math.log(n) / math.log(10))
		local mag = 10 ^ (digits - 1)
		return math.floor(n / mag + 0.5) * mag
	end
	for lvl = 2, BrainrotConfig.MaxLevel do
		BrainrotConfig.Levels[lvl] = { Cost = nice(base * growth ^ (lvl - 2)), Currency = "Cash" }
	end
end

-- Roster of the imported "Animals" models (ServerStorage.BrainrotModels). Each entry's KEY
-- must match the model name exactly so BrainrotFactory can clone the right model. Sorted into
-- 5 base tiers by how advanced/rare each looks. Color is a fallback/label accent only (the real
-- mesh is used); Scale grows with tier so rarer brainrots read bigger on the podium.
local C_COMMON    = Color3.fromRGB(220, 224, 230)
local C_UNCOMMON  = Color3.fromRGB(60, 230, 110)
local C_RARE      = Color3.fromRGB(50, 150, 255)
local C_EPIC      = Color3.fromRGB(160, 70, 235)
local C_LEGENDARY = Color3.fromRGB(255, 175, 35)

BrainrotConfig.Brainrots = {
	---------------------------------------------------------------- COMMON
	["Noobini Pizzanini"]    = { Tier = "Common", BaseCash = 0, BaseGem = 0, Color = C_COMMON, Scale = 1.0 },
	["Tim Cheese"]           = { Tier = "Common", BaseCash = 0, BaseGem = 0, Color = C_COMMON, Scale = 1.0 },
	["Svinina Bombardino"]   = { Tier = "Common", BaseCash = 0, BaseGem = 0, Color = C_COMMON, Scale = 1.0 },
	["Ta Ta Ta Ta Sahur"]    = { Tier = "Common", BaseCash = 0, BaseGem = 0, Color = C_COMMON, Scale = 1.0 },
	["Fluriflura"]           = { Tier = "Common", BaseCash = 0, BaseGem = 0, Color = C_COMMON, Scale = 1.0 },
	["67"]                   = { Tier = "Common", BaseCash = 0, BaseGem = 0, Color = C_COMMON, Scale = 1.0 },
	["Bananita Dolphinita"]  = { Tier = "Common", BaseCash = 0, BaseGem = 0, Color = C_COMMON, Scale = 1.05 },
	["Talpa Di Fero"]        = { Tier = "Common", BaseCash = 0, BaseGem = 0, Color = C_COMMON, Scale = 1.05 },

	---------------------------------------------------------------- UNCOMMON
	["Trippi Troppi"]        = { Tier = "Uncommon", BaseCash = 0, BaseGem = 0, Color = C_UNCOMMON, Scale = 1.1 },
	["Tung Tung Tung Sahur"] = { Tier = "Uncommon", BaseCash = 0, BaseGem = 0, Color = C_UNCOMMON, Scale = 1.1 },
	["Chimpanzini Bananini"] = { Tier = "Uncommon", BaseCash = 0, BaseGem = 0, Color = C_UNCOMMON, Scale = 1.1 },
	["Gangster Footera"]     = { Tier = "Uncommon", BaseCash = 0, BaseGem = 0, Color = C_UNCOMMON, Scale = 1.1 },
	["Trulimero Trulicina"]  = { Tier = "Uncommon", BaseCash = 0, BaseGem = 0, Color = C_UNCOMMON, Scale = 1.1 },
	["Bombombini Gusini"]    = { Tier = "Uncommon", BaseCash = 0, BaseGem = 0, Color = C_UNCOMMON, Scale = 1.15 },
	["Chef Crabracadabra"]   = { Tier = "Uncommon", BaseCash = 0, BaseGem = 0, Color = C_UNCOMMON, Scale = 1.15 },

	---------------------------------------------------------------- RARE
	["Blueberrinni Octopusini"] = { Tier = "Rare", BaseCash = 0, BaseGem = 0, Color = C_RARE, Scale = 1.2 },
	["Boneca Ambalabu"]      = { Tier = "Rare", BaseCash = 0, BaseGem = 0, Color = C_RARE, Scale = 1.2 },
	["Bandito Bobritto"]     = { Tier = "Rare", BaseCash = 0, BaseGem = 0, Color = C_RARE, Scale = 1.2 },
	["Brr Brr Patapim"]      = { Tier = "Rare", BaseCash = 0, BaseGem = 0, Color = C_RARE, Scale = 1.25 },
	["Cappuccino Assassino"] = { Tier = "Rare", BaseCash = 0, BaseGem = 0, Color = C_RARE, Scale = 1.2 },
	["Ballerina Cappuccina"] = { Tier = "Rare", BaseCash = 0, BaseGem = 0, Color = C_RARE, Scale = 1.25 },
	["Lirilì Larilà"]        = { Tier = "Rare", BaseCash = 0, BaseGem = 0, Color = C_RARE, Scale = 1.25 },

	---------------------------------------------------------------- EPIC
	["Bombardiro Crocodilo"] = { Tier = "Epic", BaseCash = 0, BaseGem = 0, Color = C_EPIC, Scale = 1.3 },
	["Bambini Crostini"]     = { Tier = "Epic", BaseCash = 0, BaseGem = 0, Color = C_EPIC, Scale = 1.3 },
	["Orangutini Ananassini"]= { Tier = "Epic", BaseCash = 0, BaseGem = 0, Color = C_EPIC, Scale = 1.3 },
	["Tralalero Tralala"]    = { Tier = "Epic", BaseCash = 0, BaseGem = 0, Color = C_EPIC, Scale = 1.3 },
	["Frigo Camelo"]         = { Tier = "Epic", BaseCash = 0, BaseGem = 0, Color = C_EPIC, Scale = 1.3 },
	["Cocofanto Elefanto"]   = { Tier = "Epic", BaseCash = 0, BaseGem = 0, Color = C_EPIC, Scale = 1.35 },
	["Brri Brri Bicus Dicus Bombicus"] = { Tier = "Epic", BaseCash = 0, BaseGem = 0, Color = C_EPIC, Scale = 1.35 },

	---------------------------------------------------------------- LEGENDARY
	["Burbaloni Loliloli"]   = { Tier = "Legendary", BaseCash = 0, BaseGem = 0, Color = C_LEGENDARY, Scale = 1.4 },
	["Glorbo Fruttodrillo"]  = { Tier = "Legendary", BaseCash = 0, BaseGem = 0, Color = C_LEGENDARY, Scale = 1.4 },
	["La Vacca Saturno Saturnita"] = { Tier = "Legendary", BaseCash = 0, BaseGem = 0, Color = C_LEGENDARY, Scale = 1.5 },
	["Odin Din Din Dun"]     = { Tier = "Legendary", BaseCash = 0, BaseGem = 0, Color = C_LEGENDARY, Scale = 1.45 },
	["Rhino Toasterino"]     = { Tier = "Legendary", BaseCash = 0, BaseGem = 0, Color = C_LEGENDARY, Scale = 1.45 },
	["Graipuss Medussi"]     = { Tier = "Legendary", BaseCash = 0, BaseGem = 0, Color = C_LEGENDARY, Scale = 1.5 },
	["Girafa Celestre"]      = { Tier = "Legendary", BaseCash = 0, BaseGem = 0, Color = C_LEGENDARY, Scale = 1.5 },
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

-- Per-brainrot level multiplier — applies to CASH ONLY (gem income is fixed; see BrainrotMath).
-- Level 1 = 1x; Level 30 = 1.1^29 ≈ 15.9x.
function BrainrotConfig.levelMult(level: number): number
	return 1.1 ^ ((level or 1) - 1)
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

-- Base income for a tier, before variant/level/rebirth: returns
-- (cashPerSecond, gemPerMinute). Cash is PER-SECOND (integer), gems PER-MINUTE
-- (BrainrotMath divides only the gems by 60). Unknown tiers fall back to Common.
function BrainrotConfig.tierIncome(tier: string): (number, number)
	local income = BrainrotConfig.TierIncome[tier] or BrainrotConfig.TierIncome.Common
	return income.CashPerSec, income.GemPerSec
end

return BrainrotConfig
