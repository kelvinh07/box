--!strict
-- RarityColors
-- The "color language" of the game. Tiers AND variants each map to a bright,
-- highly-saturated color used consistently across UI, podiums, labels and glow.

local RarityColors = {}

-- Tier colors (egg rarity / brainrot tier)
RarityColors.Tier = {
	Common    = Color3.fromRGB(220, 224, 230), -- white/gray
	Uncommon  = Color3.fromRGB(60, 230, 110),  -- bold green
	Rare      = Color3.fromRGB(50, 150, 255),  -- electric blue
	Epic      = Color3.fromRGB(160, 70, 235),  -- purple (Epic egg + Epic tier)
	Legendary = Color3.fromRGB(255, 175, 35),  -- gold/orange
	Mythic    = Color3.fromRGB(255, 45, 45),   -- RED (Mythic egg)
}

-- Variant colors (applied on top of any brainrot)
RarityColors.Variant = {
	Normal  = Color3.fromRGB(235, 235, 235),
	Gold    = Color3.fromRGB(255, 215, 0),    -- yellow glow
	Diamond = Color3.fromRGB(80, 240, 255),   -- cyan glow
	Galaxy  = Color3.fromRGB(180, 90, 255),   -- purple / rainbow shimmer
}

-- Currency accent colors
RarityColors.Cash = Color3.fromRGB(95, 230, 90)
RarityColors.Gems = Color3.fromRGB(90, 200, 255)

function RarityColors.tier(tier: string): Color3
	return RarityColors.Tier[tier] or RarityColors.Tier.Common
end

function RarityColors.variant(variant: string): Color3
	return RarityColors.Variant[variant] or RarityColors.Variant.Normal
end

return RarityColors
