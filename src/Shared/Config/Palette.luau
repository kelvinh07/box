--!strict
-- Palette
-- The single source of truth for the world's VIBRANT, SATURATED look
-- (Pet-Simulator candy aesthetic). Recolor everything via these Color3s so the
-- whole game stays consistent — never hard-code muted grays again.

local Palette = {
	Grass     = Color3.fromRGB(124, 226, 62),   -- vivid lime play-ground grass
	Snow      = Color3.fromRGB(245, 250, 255),  -- bright snow (border top cap)
	Dirt      = Color3.fromRGB(204, 122, 60),   -- warm vivid brown (border cliffs)
	DigField  = Color3.fromRGB(122, 72, 38),    -- dig-site first layer (darker than the tan mounds)
	BaseWall  = Color3.fromRGB(150, 210, 255),  -- vivid sky blue
	BaseTrim  = Color3.fromRGB(140, 120, 245),  -- vivid violet (pillars/trim/roof/headers/rails/steps)
	BaseFloor = Color3.fromRGB(100, 110, 175),  -- brighter blue-gray (platform/floor slabs)
	Glass     = Color3.fromRGB(150, 235, 255),  -- bright cyan glass (windows/incubator dome)
	Wall      = Color3.fromRGB(255, 125, 95),   -- vivid coral (rebirth/zone walls)
	Plate     = Color3.fromRGB(70, 245, 120),   -- vivid green (pressure plates)
	Podium    = Color3.fromRGB(95, 80, 170),    -- vivid purple (podiums; keep Neon material)
	PodiumRim = Color3.fromRGB(120, 230, 255),  -- bright cyan rim
	Fence     = Color3.fromRGB(170, 105, 55),   -- warm wood fence
	Incubator = Color3.fromRGB(90, 120, 230),   -- vivid blue incubator body
	LockRed   = Color3.fromRGB(255, 70, 95),    -- vivid red (locked staircase barrier)
	Pink      = Color3.fromRGB(255, 90, 175),
	Cyan      = Color3.fromRGB(70, 205, 255),
	Lime      = Color3.fromRGB(90, 235, 90),
	Gold      = Color3.fromRGB(255, 205, 55),
	Purple    = Color3.fromRGB(180, 100, 255),
}

return Palette
