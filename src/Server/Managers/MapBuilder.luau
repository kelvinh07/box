--!strict
-- MapBuilder
-- Builds the SHARED world:
--   * a big bright ground,
--   * the spawn point in the middle of the lobby arc.
--
-- Per-player bases, walls and ALL dig areas (entry/zone-1 included) are built by
-- BaseManager as one unified per-player lane. DigCenter below remains the
-- ring center used by BaseManager.

local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local Surface = require(ReplicatedStorage.Shared.Modules.Surface)

local MapBuilder = {}

-- Build an anchored part with the classic studded legoish look (Surface.applyStuds
-- overlays the real Roblox studs texture on every face — `SurfaceType.Studs` alone no
-- longer renders strongly enough). Pass `NoStuds = true` to opt a part out.
local function makePart(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	local noStuds = props.NoStuds
	props.NoStuds = nil
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	if not noStuds and Surface.shouldStud(p) then
		Surface.applyStuds(p)
	end
	return p
end

-- ring center used by BaseManager (lanes fan out from here)
MapBuilder.DigCenter = Vector3.new(0, 0, 0)

-- Frames the play area with a thick DIRT CLIFF capped by SNOW (grass-cliff look,
-- snow on top). A square ring centered at (0, *, 30), inner half-extent 340 studs:
-- inner faces sit at x=+/-320 and z=-290 / +350 — all OUTSIDE the bases (~radius
-- 250), the dig lane (z~302) and the stands (z~-92), with margin. The dirt walls
-- collide so players can't leave the map.
local function buildBorder(folder: Folder)
	-- { XZ center, dirt size } for each of the 4 ring walls.
	local walls = {
		{ pos = Vector3.new(-340, 0, 30), size = Vector3.new(40, 55, 720) },  -- WEST
		{ pos = Vector3.new(340, 0, 30), size = Vector3.new(40, 55, 720) },   -- EAST
		{ pos = Vector3.new(0, 0, -310), size = Vector3.new(720, 55, 40) },   -- SOUTH
		{ pos = Vector3.new(0, 0, 370), size = Vector3.new(720, 55, 40) },    -- NORTH
	}

	for _, w in ipairs(walls) do
		-- dirt cliff: base sits on the ground, centered at y = 1 + 55/2
		makePart({
			Name = "BorderDirt",
			Size = w.size,
			Color = Palette.Dirt,
			Anchored = true,
			CanCollide = true,
			CFrame = CFrame.new(w.pos.X, 1 + 55 / 2, w.pos.Z),
			Parent = folder,
		})

		-- snow cap on top: same XZ footprint + 4 studs on each horizontal axis,
		-- height 8, sitting on top of the 55-tall dirt at y = 1 + 55 + 8/2
		makePart({
			Name = "BorderSnow",
			Size = Vector3.new(w.size.X + 4, 8, w.size.Z + 4),
			Color = Palette.Snow,
			Anchored = true,
			CanCollide = true,
			CFrame = CFrame.new(w.pos.X, 1 + 55 + 8 / 2, w.pos.Z),
			Parent = folder,
		})
	end
end

function MapBuilder.build()
	local folder = Workspace:FindFirstChild("World") :: Folder
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "World"
	folder.Parent = Workspace

	-- big bright ground: clean studded plastic so the classic Roblox studs read crisply
	makePart({
		Name = "Ground",
		Size = Vector3.new(1200, 2, 1200),
		Color = Palette.Grass, -- vivid lime play-ground grass
		CFrame = CFrame.new(0, 0, 200),
		Parent = folder,
	})

	-- spawn in the middle of the lobby arc (behind the dig site)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.Color = Color3.fromRGB(255, 200, 60)
	spawn.Material = Enum.Material.Neon
	spawn.CFrame = CFrame.new(0, 1.6, -70)
	spawn.Neutral = true
	spawn.Parent = folder

	-- frame the play area with a snow-capped dirt cliff
	buildBorder(folder)

	return folder
end

return MapBuilder
