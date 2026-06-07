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
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")

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
	p.Material = Enum.Material.Plastic
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

-- A dimmer, moodier sky than the old flat over-bright daylight, plus a soft atmosphere
-- haze for depth/aesthetic. Set at RUNTIME (server) so it always applies on Play and
-- replicates to clients (project.json holds matching baseline values for the editor).
-- Bright, SATURATED candy-world look — but MATTE (no glossy specular) and with NO floor
-- glare. The vivid pop comes from rich palette colours + a global saturation boost, NOT
-- from bloom/specular (which are what cause glare/gloss), so we keep those OFF.
local function setupSky()
	Lighting.Brightness = 4
	Lighting.Ambient = Color3.fromRGB(80, 80, 80)
	Lighting.OutdoorAmbient = Color3.fromRGB(120, 140, 100)
	Lighting.ClockTime = 14
	Lighting.ExposureCompensation = 0.1
	Lighting.ColorShift_Top = Color3.fromRGB(255, 250, 242) -- subtle warm-white (toned down — full warm was too yellow)
	Lighting.EnvironmentSpecularScale = 0 -- NO glossy specular highlights on surfaces (matte)
	-- NOTE: Lighting.Technology = ShadowMap is set in default.project.json — it's a protected
	-- property that game scripts (and the Studio MCP) can't write at runtime.

	-- hide the sun & moon: no visible sun, no flare
	local sky = Lighting:FindFirstChildOfClass("Sky") or Instance.new("Sky")
	sky.CelestialBodiesShown = false
	sky.Parent = Lighting

	-- remove any sun-ray / lens-flare effect
	local rays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if rays then
		rays:Destroy()
	end

	-- bloom OFF: bloom was the floor/surface glare. Bright surfaces should look bright, not bloom.
	local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
	if bloom then
		bloom.Enabled = false
	end

	-- disable any manual ColorGrading LUT (it was muting the palette)
	local grading = Lighting:FindFirstChildOfClass("ColorGradingEffect")
	if grading then
		grading.Enabled = false
	end

	-- POP the colours: a strong global SATURATION boost so the world reads vivid/candy-bright.
	-- This is pure colour richness — it adds NO gloss or glare.
	local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect") or Instance.new("ColorCorrectionEffect")
	cc.Name = "VibrantBoost"
	cc.Saturation = 0.5
	cc.Contrast = 0.1
	cc.Brightness = 0.05
	cc.TintColor = Color3.fromRGB(255, 255, 255)
	cc.Enabled = true
	cc.Parent = Lighting

	-- atmosphere OFF (Density/Haze/Glare 0) so colours stay fully crisp & saturated (no haze wash)
	local atm = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atm.Density = 0
	atm.Haze = 0
	atm.Glare = 0
	atm.Parent = Lighting
end

-- Static, blocky RECTANGULAR clouds floating high above the map (legoish aesthetic; they
-- don't move). Smooth white, non-collidable, no shadow; a fixed seed keeps them identical
-- on every server start. Each "cloud" is a little cluster of overlapping boxes.
local function buildClouds(folder: Folder)
	local clouds = Instance.new("Folder")
	clouds.Name = "Clouds"
	clouds.Parent = folder
	local rng = Random.new(1337)
	for _ = 1, 16 do
		local cx = rng:NextNumber(-360, 360)
		local cz = rng:NextNumber(-220, 540)
		local cy = rng:NextNumber(120, 180)
		for _ = 1, rng:NextInteger(3, 5) do
			makePart({
				Name = "Cloud",
				NoStuds = true, -- clouds are smooth, not studded
				Size = Vector3.new(rng:NextNumber(30, 66), rng:NextNumber(9, 16), rng:NextNumber(22, 46)),
				Color = Color3.fromRGB(248, 250, 255),
				Transparency = 0.05,
				CanCollide = false,
				CastShadow = false,
				CFrame = CFrame.new(cx + rng:NextNumber(-24, 24), cy + rng:NextNumber(-6, 6), cz + rng:NextNumber(-18, 18)),
				Parent = clouds,
			})
		end
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

	-- big bright STUDDED grass ground (classic stud texture, like dirt/walls/bases). Tagged
	-- GrassSurface so Client/GrassChecker overlays the 6x6 two-green checker ON TOP of the
	-- studs (the studs still read through the overlay).
	local ground = makePart({
		Name = "Ground",
		Size = Vector3.new(1200, 2, 1200),
		Color = Palette.Grass,
		CFrame = CFrame.new(0, 0, 200),
		Parent = folder,
	})
	CollectionService:AddTag(ground, "GrassSurface")

	-- INVISIBLE spawn anchor in the lobby (no visible yellow plate). It's flush with the
	-- ground top (y=1) so it's neither seen nor an obstacle. Players are immediately
	-- teleported to the front of their OWN (empty) base by BaseManager.assignBase, so this
	-- is only the engine's initial spawn point.
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(14, 1, 14)
	spawn.Transparency = 1
	spawn.Material = Enum.Material.Plastic
	spawn.CFrame = CFrame.new(0, 0.5, -70) -- top sits at y=1, flush with the ground
	spawn.Neutral = true
	spawn.Parent = folder

	-- NOTE: the old map-wide snow-capped dirt border was removed. The play area is now
	-- framed by the two grass-topped dirt cliffs flanking the dig lane, built by
	-- BaseManager.buildLaneSideWalls (tighter lane). More borders TBD.

	-- dimmer sky + soft atmosphere, and static blocky clouds for aesthetic
	setupSky()
	buildClouds(folder)

	return folder
end

return MapBuilder
