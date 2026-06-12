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
	Wall      = Color3.fromRGB(226, 176, 130),  -- lighter warm brown (ghost/locked podiums + incubators)
	ZoneWall  = Color3.fromRGB(195, 200, 208),  -- LIGHT GRAY rebirth/zone divider walls
	Plate     = Color3.fromRGB(50, 250, 110),   -- vivid green (pressure plates)
	Podium    = Color3.fromRGB(135, 80, 230),   -- saturated purple (podiums; keep Neon material)
	PodiumRim = Color3.fromRGB(110, 235, 255),  -- bright cyan rim
	Fence     = Color3.fromRGB(176, 100, 48),   -- warm wood fence
	Stone     = Color3.fromRGB(124, 130, 146),  -- studded rock piles framing the zone walls
	TreeTrunk = Color3.fromRGB(120, 74, 44),    -- procedural-tree trunk (fallback foliage)
	TreeLeaf  = Color3.fromRGB(74, 196, 86),    -- procedural-tree foliage (vivid forest green)
	-- DESERT (zone 3) — sand checker floor + cactus/rock decor
	Sand         = Color3.fromRGB(227, 220, 197), -- #E3DCC5 solid desert floor (zone 3)
	-- GLACIERS (zone 4) — solid ice floor + ice-spike decor
	Ice          = Color3.fromRGB(214, 255, 250), -- #D6FFFA solid glacier floor (zone 4)
	IceSpike     = Color3.fromRGB(222, 246, 250), -- #DEF6FA ice spikes
	Cactus       = Color3.fromRGB(96, 168, 74),   -- desert cactus green
	DesertRock   = Color3.fromRGB(105, 91, 51),   -- #695B33 scattered desert rocks
	-- CRYSTAL CAVERNS (zone 5) — dark blue-teal cave floor; glowing crystal/mushroom/grass decor pops against it
	CavernFloor  = Color3.fromRGB(27, 52, 68),    -- #1B3444 dark cavern floor
	CherryFloor  = Color3.fromRGB(236, 120, 178), -- CHERRY BLOSSOM (zone 6) solid pink floor under the petal carpet
	-- HAUNTED HOLLOW (zone 7) — murky olive floor + dead trees, jack-o-lanterns, cobweb strings
	HauntedFloor = Color3.fromRGB(107, 93, 47),   -- #6B5D2F murky olive-brown graveyard ground
	DeadWood     = Color3.fromRGB(92, 78, 64),    -- bare grey-brown dead-tree bark
	Pumpkin      = Color3.fromRGB(255, 124, 24),  -- vivid jack-o-lantern orange
	Web          = Color3.fromRGB(224, 228, 234), -- pale cobweb silk
	Incubator = Color3.fromRGB(72, 116, 245),   -- vivid blue incubator body
	LockRed   = Color3.fromRGB(255, 58, 86),    -- vivid red (locked staircase barrier)
	Pink      = Color3.fromRGB(255, 80, 175),
	Cyan      = Color3.fromRGB(55, 205, 255),
	Lime      = Color3.fromRGB(80, 240, 80),
	Gold      = Color3.fromRGB(255, 205, 50),
	Purple    = Color3.fromRGB(185, 95, 255),
}

return Palette
