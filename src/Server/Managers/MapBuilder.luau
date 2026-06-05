--!strict
-- MapBuilder
-- Builds the SHARED world:
--   * a big bright ground,
--   * the spawn point in the middle of the lobby arc.
--
-- Per-player bases, walls and ALL dig areas (entry/zone-1 included) are built by
-- BaseManager as one unified per-player lane. DigCenter/DigRadius below remain the
-- ring center + base sizing used by BaseManager.

local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ZoneConfig = require(ReplicatedStorage.Shared.Config.ZoneConfig)

local MapBuilder = {}

local function makePart(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	return p
end

-- ring center + base sizing used by BaseManager (lanes fan out from here)
MapBuilder.DigCenter = Vector3.new(0, 0, 0)
MapBuilder.DigRadius = 34

function MapBuilder.build()
	local folder = Workspace:FindFirstChild("World") :: Folder
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = "World"
	folder.Parent = Workspace

	-- big bright ground
	makePart({
		Name = "Ground",
		Size = Vector3.new(1200, 2, 1200),
		Color = Color3.fromRGB(120, 210, 110),
		Material = Enum.Material.Grass,
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

	return folder
end

return MapBuilder
