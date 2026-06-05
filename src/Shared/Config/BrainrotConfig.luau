--!strict
-- BrainrotConfig
-- The base roster of Italian Brainrot memes. Each entry defines:
--   Tier       - which egg tier hatches it
--   BaseCash   - Cash generated per income cycle (BEFORE variant + zone scaling)
--   BaseGem    - Gems generated per income cycle (BEFORE variant + zone scaling)
--   Color      - chunky placeholder color (also used as a glow accent)
--   Scale      - relative model size on the podium
--
-- Variants (Normal/Gold/Diamond/Galaxy) multiply these stats — see VariantConfig.
-- Zones scale these stats — see ZoneConfig.
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

return BrainrotConfig
