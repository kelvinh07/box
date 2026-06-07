--!strict
-- Surface
-- The single source of truth for the world's CLASSIC ROBLOX "STUDS & INLETS" look.
--
-- Modern Studio renders `SurfaceType.Studs`/`Inlet` almost invisibly, so just setting
-- TopSurface = Studs (what we used to do) no longer produces the crisp, pixelated retro
-- grid the reference games have. To get it EXACTLY like that, we overlay the classic stud
-- TEXTURE on every face of a part, tinted to the part's own colour so the world stays
-- vibrant & saturated (the opaque texture would otherwise read flat grey).
--
-- One helper, used by MapBuilder / BaseManager / StandManager `makePart` and the dig
-- mounds, so every world surface is studded identically. Glow / glass / wood / cloth and
-- see-through parts are left alone so they keep their own look (neon plates, glass windows,
-- wooden booths, NPC avatars, billboards).

local Surface = {}

-- Classic stud surface texture (opaque grey studs; we drive the colour via Color3).
-- StudsPerTile = how many world studs ONE stud image spans. Bigger = CHUNKIER, more
-- visible studs (like the reference games). 1 was a too-fine grid that read as flat;
-- ~3 gives the bold, clearly-bumped studs we want.
Surface.StudTexture = "rbxassetid://8130710802"
Surface.StudsPerTile = 3

-- The opaque grey stud texture is multiplied by this tint (a brightened part colour).
-- We DELIBERATELY keep this <= 1 now: the old 1.16 over-brightened, clipping the stud
-- HIGHLIGHTS to white so the studs washed out flat. Tinting a touch BELOW the part
-- colour keeps the baked stud shadows dark, so the inlets read DEEP and the studs pop
-- as colored 3D bumps (saturation is preserved — this darkens value, not hue).
local TINT_BRIGHTEN = 0.8

local FACES = {
	Enum.NormalId.Top, Enum.NormalId.Bottom,
	Enum.NormalId.Front, Enum.NormalId.Back,
	Enum.NormalId.Left, Enum.NormalId.Right,
}

-- Materials that must keep their own appearance => never studded.
local SKIP_MATERIAL: { [Enum.Material]: boolean } = {
	[Enum.Material.Neon] = true,       -- glowing plates / podiums / barriers
	[Enum.Material.Glass] = true,      -- windows / incubator dome
	[Enum.Material.ForceField] = true, -- shields
	[Enum.Material.Wood] = true,       -- booth legs / natural wood
	[Enum.Material.WoodPlanks] = true, -- booth counters / stairs
	[Enum.Material.Fabric] = true,     -- cloth signs / banners
}

local function brighten(c: Color3, k: number): Color3
	return Color3.new(math.min(c.R * k, 1), math.min(c.G * k, 1), math.min(c.B * k, 1))
end
Surface.brighten = brighten

-- Should this part receive the classic studs overlay?
function Surface.shouldStud(part: BasePart): boolean
	if SKIP_MATERIAL[part.Material] then return false end
	if part.Transparency > 0.3 then return false end -- see-through / billboard anchors
	return true
end

-- Overlay the classic studs texture on all 6 faces, tinted to a brightened part colour.
function Surface.applyStuds(part: BasePart, studsPerTile: number?)
	local spt = studsPerTile or Surface.StudsPerTile
	local tint = brighten(part.Color, TINT_BRIGHTEN)
	-- flatten the modern surface bevels so they don't fight the texture
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for _, face in ipairs(FACES) do
		local t = Instance.new("Texture")
		t.Name = "Studs"
		t.Texture = Surface.StudTexture
		t.Face = face
		t.StudsPerTileU = spt
		t.StudsPerTileV = spt
		t.Color3 = tint
		t.Parent = part
	end
end

return Surface
