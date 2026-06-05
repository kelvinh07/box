--!strict
-- BrainrotMath
-- The single source of truth for how much a brainrot earns. Used by the SERVER
-- (EconomyManager) to grant income and by the CLIENT (Collection/preview) to show
-- it — so the displayed number always matches what the server pays out.
--
-- Income is TIER-BASED, then layered with the variant, the per-brainrot level,
-- and the permanent rebirth multipliers. Spec values are PER MINUTE; we divide by
-- 60 because the income loop ticks every 1s (so we return PER SECOND).
--
--   cash/min = tierCash * Variant.CashMult * 1.2^(level-1) * 1.2^rebirthCount
--   gem/min  = (tierGem + Variant.GemBonus) * 1.2^(level-1) * 1.5^rebirthCount
--   income() returns each of the above divided by 60 (per-second).
--
-- ZoneConfig CashScale/GemScale are NO LONGER used by income — zone scaling has
-- been replaced by the rebirth multipliers.

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

	local tierCash, tierGem = BrainrotConfig.tierIncomePerMin(entry.tier)
	local level = entry.level or 1
	local levelMult = BrainrotConfig.levelMult(level)
	local rb = rebirthCount or 0

	local cashPerMin = tierCash * variant.CashMult * levelMult * (1.2 ^ rb)
	local gemPerMin = (tierGem + variant.GemBonus) * levelMult * (1.5 ^ rb)

	return cashPerMin / 60, gemPerMin / 60
end

return BrainrotMath
