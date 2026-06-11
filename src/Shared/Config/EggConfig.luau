--!strict
-- EggConfig
-- Defines each egg rarity: hatch cost (Cash), base incubation time (seconds), and the
-- POOL of (brainrot tier, variant) combos it can hatch.
--
-- Egg order (low -> high): Common, Uncommon, Rare, Epic, Legendary, Mythic.
--   * Epic  egg = purple, size between Rare & Legendary.
--   * Mythic egg = red, one size bigger than Legendary; it has NO base (Normal) brainrots.
--
-- Each base brainrot tier (Common..Legendary) seeds three eggs: its OWN egg with the Normal
-- version, the egg ONE tier up with the Gold version, and the egg TWO tiers up with the
-- Diamond version (clamped to Mythic, the top egg). Galaxy versions are created by the
-- factory but PARKED (no egg yet) until more eggs/versions are added.
--
-- NOTE: the per-zone DIG ODDS (which egg you dig) live in ZoneConfig.

export type EggRarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary" | "Mythic"

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

-- How many egg tiers UP each variant shifts a brainrot. Galaxy (+3) is created but PARKED
-- (it would need eggs above Mythic), so it is intentionally absent here until new eggs exist.
EggConfig.VariantOffset = { Normal = 0, Gold = 1, Diamond = 2 }

EggConfig.Eggs = {
	Common = {
		DisplayName = "Common Egg",
		HatchCost = 15,        -- Cash to start hatching
		Incubation = 3,        -- seconds (before incubator reduction)
		BrainrotTier = "Common", -- (legacy/reference; the POOL below is authoritative)
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
		BrainrotTier = "Legendary", -- unused (Mythic has no Normal brainrots); fallback only
	},
}

function EggConfig.get(rarity: string)
	return EggConfig.Eggs[rarity]
end

function EggConfig.exists(rarity: string): boolean
	return EggConfig.Eggs[rarity] ~= nil
end

local function indexOf(list: { string }, v: string): number?
	for i, x in ipairs(list) do
		if x == v then
			return i
		end
	end
	return nil
end

-- The pool of { tier, variant } groups obtainable from `eggRarity`. A brainrot of base tier
-- T (index ti) populates egg min(ti + variantOffset, top). E.g. the Rare egg returns
-- {Normal Rare, Gold Uncommon, Diamond Common}; the Mythic egg returns
-- {Gold Legendary, Diamond Legendary, Diamond Epic}.
function EggConfig.poolGroups(eggRarity: string): { { tier: string, variant: string } }
	local e = indexOf(EggConfig.Order, eggRarity)
	if not e then
		return {}
	end
	local maxIdx = #EggConfig.Order               -- Mythic (the clamp ceiling)
	local baseCount = maxIdx - 1                   -- base tiers = every egg EXCEPT Mythic
	local groups = {}
	for ti = 1, baseCount do
		local baseTier = EggConfig.Order[ti]
		for variant, off in pairs(EggConfig.VariantOffset) do
			if math.min(ti + off, maxIdx) == e then
				table.insert(groups, { tier = baseTier, variant = variant })
			end
		end
	end
	return groups
end

return EggConfig
