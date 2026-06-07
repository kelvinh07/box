--!strict
-- Palette
-- The single source of truth for the world's VIBRANT, SATURATED look. Recolor
-- everything via these Color3s so the whole game stays consistent. The BASES are a
-- clean SATURATED GRAY (brainrot-base look); the floor is a LIGHTER lime; everything
-- else stays bright/vivid. Pairs with the semi-pixelated legoish studded surfaces.

local Palette = {
	Grass         = Color3.fromRGB(101, 217, 26), -- studded grass green (#65D91A); studded via Surface like the rest of the world
	GrassCheckerB = Color3.fromRGB(84, 179, 18),  -- darker green (#54B312) overlaid as the 6x6 checker on top of the studs
	Snow      = Color3.fromRGB(248, 252, 255),  -- bright snow (border top cap)
	Dirt      = Color3.fromRGB(228, 142, 74),   -- vivid warm orange (studded border "walls" / mounds)
	DigField  = Color3.fromRGB(120, 68, 32),    -- dig-site first layer (darker than the tan mounds)
	BaseWall  = Color3.fromRGB(162, 168, 182),  -- clean saturated gray (brainrot-base look)
	BaseTrim  = Color3.fromRGB(96, 102, 120),   -- dark cool gray (pillars/trim/roof/headers/rails/steps)
	BaseFloor = Color3.fromRGB(120, 126, 144),  -- medium gray (platform/floor slabs)
	Glass     = Color3.fromRGB(150, 235, 255),  -- bright cyan glass (windows/incubator dome)
	Wall      = Color3.fromRGB(226, 176, 130),  -- lighter warm brown (rebirth/zone walls; was saturated coral)
	Plate     = Color3.fromRGB(50, 250, 110),   -- vivid green (pressure plates)
	Podium    = Color3.fromRGB(135, 80, 230),   -- saturated purple (podiums; keep Neon material)
	PodiumRim = Color3.fromRGB(110, 235, 255),  -- bright cyan rim
	Fence     = Color3.fromRGB(176, 100, 48),   -- warm wood fence
	Stone     = Color3.fromRGB(124, 130, 146),  -- studded rock piles framing the zone walls
	TreeTrunk = Color3.fromRGB(120, 74, 44),    -- procedural-tree trunk (fallback foliage)
	TreeLeaf  = Color3.fromRGB(74, 196, 86),    -- procedural-tree foliage (vivid forest green)
	Incubator = Color3.fromRGB(72, 116, 245),   -- vivid blue incubator body
	LockRed   = Color3.fromRGB(255, 58, 86),    -- vivid red (locked staircase barrier)
	Pink      = Color3.fromRGB(255, 80, 175),
	Cyan      = Color3.fromRGB(55, 205, 255),
	Lime      = Color3.fromRGB(80, 240, 80),
	Gold      = Color3.fromRGB(255, 205, 50),
	Purple    = Color3.fromRGB(185, 95, 255),
}

return Palette
