--!strict
-- BrainrotMath
-- The single source of truth for how much a brainrot earns. Used by the SERVER
-- (EconomyManager) to grant income and by the CLIENT (CollectionUI) to preview
-- it — so the displayed number always matches what the server pays out.
--
--   FinalCash = BaseCash * Variant.CashMult * Zone.CashScale   (per income cycle)
--   FinalGem  = (BaseGem + Variant.GemBonus) * Zone.GemScale   (per income cycle)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage.Shared.Config

local BrainrotConfig = require(Config.BrainrotConfig)
local VariantConfig = require(Config.VariantConfig)
local ZoneConfig = require(Config.ZoneConfig)

local BrainrotMath = {}

export type Entry = {
	id: string,
	base: string,    -- brainrot name
	tier: string,
	variant: string,
}

-- Returns cashPerCycle, gemPerCycle for an owned brainrot in a given zone.
function BrainrotMath.income(entry: Entry, zone: number): (number, number)
	local base = BrainrotConfig.get(entry.base)
	local variant = VariantConfig.get(entry.variant)
	local zoneData = ZoneConfig.get(zone) or ZoneConfig.get(1)
	if not base or not variant or not zoneData then
		return 0, 0
	end

	local cash = base.BaseCash * variant.CashMult * zoneData.CashScale
	local gem = (base.BaseGem + variant.GemBonus) * zoneData.GemScale
	return cash, gem
end

return BrainrotMath
