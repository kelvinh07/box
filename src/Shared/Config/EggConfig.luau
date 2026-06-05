--!strict
-- EggConfig
-- Defines each egg rarity: hatch cost (Cash), base incubation time (seconds),
-- and the brainrot tier the egg hatches into.
--
-- NOTE: the per-zone DIG ODDS live in ZoneConfig (they change per zone).
-- EggConfig only holds the intrinsic, zone-independent properties of an egg.

export type EggRarity = "Common" | "Uncommon" | "Rare" | "Legendary"

local EggConfig = {}

-- Ordered list (used for UI ordering and iteration).
EggConfig.Order = { "Common", "Uncommon", "Rare", "Legendary" } :: { string }

EggConfig.Eggs = {
	Common = {
		DisplayName = "Common Egg",
		HatchCost = 10,        -- Cash to start hatching
		Incubation = 3,        -- seconds (before HatchSpeed reduction)
		BrainrotTier = "Common",
	},
	Uncommon = {
		DisplayName = "Uncommon Egg",
		HatchCost = 25,
		Incubation = 5,
		BrainrotTier = "Uncommon",
	},
	Rare = {
		DisplayName = "Rare Egg",
		HatchCost = 100,
		Incubation = 10,
		BrainrotTier = "Rare",
	},
	Legendary = {
		DisplayName = "Legendary Egg",
		HatchCost = 500,
		Incubation = 20,
		BrainrotTier = "Legendary",
	},
}

function EggConfig.get(rarity: string)
	return EggConfig.Eggs[rarity]
end

function EggConfig.exists(rarity: string): boolean
	return EggConfig.Eggs[rarity] ~= nil
end

return EggConfig
