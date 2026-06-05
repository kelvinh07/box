--!strict
-- AssetConfig
-- Maps brainrot names (and shared props) to Roblox Creator Store asset IDs.
--
-- HOW TO USE CREATOR STORE MODELS:
--   1. In Roblox Studio, open the Toolbox > Creator Store and search the
--      brainrot name (e.g. "Tung Tung Tung Sahur", "Bombardiro Crocodilo").
--      ONLY take models from the official Creator Store (trusted, moderated).
--      Prefer free assets from verified creators with high favorites/usage.
--   2. Right-click the model in the Toolbox > "Copy Asset ID".
--   3. Paste it below as a NUMBER (e.g. Brainrots["Tralalero Tralala"] = 1234567890).
--
-- Any brainrot left as `nil` automatically falls back to a chunky, brightly
-- colored PROCEDURAL placeholder built by BrainrotFactory — so the game is
-- fully playable on first run with zero asset IDs filled in. Swap them in later.
--
-- The MCP `insert_from_creator_store` tool can also be used to bulk-insert these
-- models into Studio; once inserted, grab their asset IDs and paste them here.

local AssetConfig = {}

-- ⬇️ Fill these in with real Creator Store asset IDs to replace placeholders.
AssetConfig.Brainrots = {
	-- Common
	["Brr Brr Patapim"]      = nil, -- TODO: paste Creator Store asset id
	["Boneca Ambalabu"]      = nil, -- TODO
	["Chimpanzini Bananini"] = nil, -- TODO
	["Trippi Troppi"]        = nil, -- TODO
	["Frigo Camelo"]         = nil, -- TODO
	-- Uncommon
	["Cappuccino Assassino"] = nil, -- TODO
	["Ballerina Cappuccina"] = nil, -- TODO
	["Lirilì Larilà"]        = nil, -- TODO
	["Bombombini Gusini"]    = nil, -- TODO
	-- Rare
	["Tung Tung Tung Sahur"] = nil, -- TODO
	["Bombardiro Crocodilo"] = nil, -- TODO
	["Tralalero Tralala"]    = nil, -- TODO
	-- Legendary
	["Trippa Troppa Tralala Lirili Rilà Tung Tung Sahur Boneca"] = nil, -- TODO
	-- Mythic (zone 2+)
	["Spaghettini Vesuviano"]           = nil,
	["Cocco Locco Bombardino"]          = nil,
	["Frulli Frulla Mortadella"]        = nil,
	["Ananasso Tralaledino Supremo"]    = nil,
	["Polpettone Galattico Crocofanto"] = nil,
} :: { [string]: number? }

-- Optional decorative assets. Leave nil to use procedural fallbacks.
AssetConfig.EggModel = nil       -- TODO: a generic egg model asset id (shown in incubator)
AssetConfig.IncubatorModel = nil -- TODO: an incubator/machine model asset id

-- UI icons. These are rbxassetid image references; the included defaults are
-- generic Roblox emoji-style icons. Replace with Creator Store icon asset ids.
AssetConfig.Icons = {
	Cash = "rbxassetid://9405173871", -- placeholder coin-ish icon (swap me)
	Gems = "rbxassetid://9405173871", -- placeholder gem-ish icon (swap me)
}

-- Sound effects (rbxassetid). These are common free Roblox SFX ids.
AssetConfig.Sounds = {
	Dig     = "rbxassetid://9114057287",
	Hatch   = "rbxassetid://9114054146",
	Purchase= "rbxassetid://9114054146",
	Rebirth = "rbxassetid://9114054146",
	Sparkle = "rbxassetid://9114057287",
}

function AssetConfig.brainrotAssetId(name: string): number?
	return AssetConfig.Brainrots[name]
end

return AssetConfig
