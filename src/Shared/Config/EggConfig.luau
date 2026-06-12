--!strict
-- EggConfig
-- Defines each egg rarity: hatch cost (Cash), base incubation time (seconds), and the
-- POOL of (brainrot tier, variant) combos it can hatch.
--
-- Egg order (low -> high): Common, Uncommon, Rare, Epic, Legendary, Mythic.
--   * Epic  egg = purple, size between Rare & Legendary.
--   * Mythic egg = red, one size bigger than Legendary.
--
-- Each egg hatches EVERY variant (Normal/Gold/Diamond/Galaxy) of its OWN brainrot tier — e.g. the
-- Common egg can give a Normal, Gold, Diamond OR Galaxy COMMON brainrot. The per-variant roll odds
-- (Normal 80 / Gold 15 / Diamond 4 / Galaxy 1, nudged by Luck) live in VariantConfig and are
-- applied in IncubationManager.pickPoolGroup, so rarer versions are correspondingly rarer.
-- The Mythic egg has no base tier of its own: it draws from the TOP tier (Legendary) but DROPS the
-- Normal variant, making it the premium "guaranteed shiny" egg (Gold/Diamond/Galaxy only).
--
-- NOTE: the per-zone DIG ODDS (which egg you dig) live in ZoneConfig.

export type EggRarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"

local VariantConfig = require(script.Parent.VariantConfig)

local EggConfig = {}

-- Ordered list (used for UI ordering, dig odds, and the pool math below).
EggConfig.Order = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" } :: { string }

-- DISPLAY SIZING — the SINGLE source of truth for how big the (full-detail) pixel egg is, shared
-- by the in-world dug egg (Client/DigSite), the in-hand egg Tool (ToolFactory), and the inventory
-- ViewportFrame cards (Client/ToolVisual). egg height = HeightBase * RevealMult[rarity].
EggConfig.HeightBase = 0.6 -- one "x" of egg height
EggConfig.RevealMult = {
	Common    = 8,
	Uncommon  = 10,
	Rare      = 12,
	Epic      = 13.5, -- between Rare and Legendary
	Legendary = 15,
	Mythic    = 17,   -- one size bigger than Legendary
}

-- The full-detail display height (studs) for an egg of `rarity` (defaults to Common's mult).
function EggConfig.displayHeight(rarity: string): number
	return EggConfig.HeightBase * (EggConfig.RevealMult[rarity] or EggConfig.RevealMult.Common)
end

-- Voxel resolution (PixelEgg voxH) for the in-hand egg TOOL. Set to 12 to match the dug egg's
-- FULL detail (per design: the held egg should be the real egg at full size + detail). NOTE the
-- cost: the Tool egg is SERVER-built, welded, and replicated to every client while equipped — at
-- voxH 12 each egg is ~489 welded parts (vs ~59 at voxH 6). voxH only trades part-count for pixel
-- fineness (size/silhouette come from displayHeight), so if a playtest shows replication/instance
-- pressure with many players holding eggs, dialing this back to 6-8 keeps the look while cutting parts.
EggConfig.ToolVoxH = 12

-- Per-egg variant EXCLUSIONS. The Mythic egg has no base tier of its own, so it draws from the
-- top base tier (Legendary, via its BrainrotTier) but DROPS the Normal variant — making it the
-- premium "guaranteed shiny" egg (Gold/Diamond/Galaxy Legendary only).
EggConfig.ExcludeVariants = {
	Mythic = { Normal = true },
}

EggConfig.Eggs = {
	Common = {
		DisplayName = "Common Egg",
		HatchCost = 15,        -- Cash to start hatching
		Incubation = 3,        -- seconds (before incubator reduction)
		BrainrotTier = "Common", -- the brainrot TIER this egg hatches (ALL 4 variants of it; see poolGroups)
	},
	Uncommon = {
		DisplayName = "Uncommon Egg",
		HatchCost = 60,
		Incubation = 5,
		BrainrotTier = "Uncommon",
	},
	Rare = {
		DisplayName = "Rare Egg",
		HatchCost = 250,
		Incubation = 10,
		BrainrotTier = "Rare",
	},
	Epic = {
		DisplayName = "Epic Egg",
		HatchCost = 900,
		Incubation = 15,
		BrainrotTier = "Epic",
	},
	Legendary = {
		DisplayName = "Legendary Egg",
		HatchCost = 3000,
		Incubation = 20,
		BrainrotTier = "Legendary",
	},
	Mythic = {
		DisplayName = "Mythic Egg",
		HatchCost = 10000,
		Incubation = 30,
		BrainrotTier = "Legendary", -- Mythic has no base tier; draws Legendary but drops Normal (see ExcludeVariants)
	},
}

function EggConfig.get(rarity: string)
	return EggConfig.Eggs[rarity]
end

function EggConfig.exists(rarity: string): boolean
	return EggConfig.Eggs[rarity] ~= nil
end

-- The pool of { tier, variant } groups an egg can hatch: EVERY variant (Normal/Gold/Diamond/
-- Galaxy) of the egg's OWN brainrot tier (its BrainrotTier), minus any per-egg excluded variant.
-- The per-variant ROLL ODDS (VariantConfig.Weight: Normal 80 / Gold 15 / Diamond 4 / Galaxy 1,
-- nudged by Luck) are applied in IncubationManager.pickPoolGroup — so every egg can yield all four
-- versions of its brainrots, with the rarer versions correspondingly rarer.
function EggConfig.poolGroups(eggRarity: string): { { tier: string, variant: string } }
	local egg = EggConfig.Eggs[eggRarity]
	if not egg then
		return {}
	end
	local tier = egg.BrainrotTier
	local excluded = EggConfig.ExcludeVariants[eggRarity]
	local groups = {}
	for _, variant in ipairs(VariantConfig.Order) do
		if not (excluded and excluded[variant]) then
			table.insert(groups, { tier = tier, variant = variant })
		end
	end
	return groups
end

return EggConfig
