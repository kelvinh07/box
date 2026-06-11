--!strict
-- BrainrotMath
-- The single source of truth for how much a brainrot earns. Used by the SERVER
-- (EconomyManager) to grant income and by the CLIENT (Collection/preview) to show
-- it — so the displayed number always matches what the server pays out.
--
-- CASH is the run currency: tier-based, scaled by the variant, the per-brainrot
-- level, and the PERMANENT compounding rebirth multiplier (1.35^rebirths). It is
-- sourced per-second and ROUNDED HALF-UP to a whole integer (no /60).
--
-- GEMS are a FIXED whole-number amount per (tier, variant). They do NOT scale with
-- level and there is NO rebirth gem multiplier — a brainrot makes the same gems/sec
-- forever. (The gem BALANCE still resets on rebirth; the RATE never changes.)
--
--   cash/sec = round( tierCashPerSec * Variant.CashMult * 1.2^(level-1) * 1.35^rebirthCount )
--   gem/sec  = tierGemPerSec + Variant.GemBonus            (FIXED — no level, no rebirth, no /60)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage.Shared.Config

local BrainrotConfig = require(Config.BrainrotConfig)
local VariantConfig = require(Config.VariantConfig)

local BrainrotMath = {}

export type Entry = {
	id: string,
	base: string,    -- brainrot name
	tier: string,
	variant: string,
	level: number?,  -- per-brainrot level 1..10 (defaults to 1)
}

-- Returns cashPerSecond, gemPerSecond for an owned brainrot at a given rebirth count.
-- entry.level defaults to 1. The two outputs feed both the 1s server payout loop
-- and the client income preview, so they must stay identical.
function BrainrotMath.income(entry: Entry, rebirthCount: number): (number, number)
	local variant = VariantConfig.get(entry.variant)
	if not variant then
		return 0, 0
	end

	local tierCash, tierGem = BrainrotConfig.tierIncome(entry.tier) -- both per-second
	local level = entry.level or 1
	local levelMult = BrainrotConfig.levelMult(level)
	local rb = rebirthCount or 0

	-- CASH scales with the variant, the per-brainrot level, and the compounding rebirth
	-- multiplier (1.35^rb). Rounded HALF-UP to a whole integer so cash is never fractional.
	local cashPerSec = tierCash * variant.CashMult * levelMult * (1.35 ^ rb)
	-- GEMS are FIXED per (tier, variant): no level scaling, no rebirth multiplier, no /60.
	local gemPerSec = tierGem + variant.GemBonus

	return math.floor(cashPerSec + 0.5), math.floor(gemPerSec)
end

return BrainrotMath
