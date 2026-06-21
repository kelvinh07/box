--!strict
-- ShovelModel
-- Builds the game's signature PIXEL / VOXEL SHOVEL — a looped yellow handle + shaft over a blue
-- DISHED spade blade — as a self-contained ANCHORED Model, studded like the rest of the world via
-- Surface.applyStuds (so it reads with the same classic legoish stud grid as every other surface).
--
-- Pure geometry: this is the shovel ASSET only, not wired into any gameplay system. Instance it
-- wherever a shovel prop/display is wanted (e.g. ShovelModel.build():PivotTo(cf)). The voxel grid
-- is authored in unit cells (x = width, y = up, z = depth/front); `cube` scales every cell.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local Surface = require(ReplicatedStorage.Shared.Modules.Surface)

local ShovelModel = {}

local YELLOW = Palette.Gold               -- handle + shaft (matches the reference's golden yellow)
local BLUE = Color3.fromRGB(45, 148, 235) -- spade blade (vivid azure to match the reference art)

-- Spade silhouette, row by row {y, xMin, xMax}: a soft 1-cell tip widening to broad rounded
-- shoulders just under the socket — the classic shovel-scoop outline.
local BLADE_ROWS = {
	{ 0, 0, 0 },
	{ 1, -1, 1 },
	{ 2, -2, 2 },
	{ 3, -3, 3 },
	{ 4, -3, 3 },
	{ 5, -4, 4 },
	{ 6, -4, 4 },
	{ 7, -4, 4 },
	{ 8, -3, 3 },
}

-- Build the voxel shovel around the origin. `cube` = stud size of each voxel cell (default 1).
-- Returns an anchored Model whose PrimaryPart is a transparent core at its centre (so callers can
-- PivotTo / orient the whole shovel with one move).
function ShovelModel.build(cube: number?): Model
	local CUBE = cube or 1
	local model = Instance.new("Model")
	model.Name = "Shovel"

	local function put(x: number, y: number, z: number, color: Color3)
		local p = Instance.new("Part")
		p.Name = "Vox"
		p.Size = Vector3.new(CUBE, CUBE, CUBE)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.Color = color
		p.Material = Enum.Material.Plastic
		p.CFrame = CFrame.new(x * CUBE, y * CUBE, z * CUBE)
		p.Parent = model
		Surface.applyStuds(p, CUBE) -- ~1 stud per cell face => classic studded look at any cube size
	end

	-- BLADE: a flat dished panel (z=1) with a RAISED rim on its perimeter (z=2) so the spade reads
	-- as a concave scoop opening toward the front, exactly like the reference.
	local rowRange: { [number]: { number } } = {}
	for _, r in ipairs(BLADE_ROWS) do
		rowRange[r[1]] = { r[2], r[3] }
	end
	local function isBlade(x: number, y: number): boolean
		local r = rowRange[y]
		return r ~= nil and x >= r[1] and x <= r[2]
	end
	for _, r in ipairs(BLADE_ROWS) do
		local y, a, b = r[1], r[2], r[3]
		for x = a, b do
			put(x, y, 1, BLUE)
			if not (isBlade(x - 1, y) and isBlade(x + 1, y) and isBlade(x, y - 1) and isBlade(x, y + 1)) then
				put(x, y, 2, BLUE) -- perimeter cell => raised rim
			end
		end
	end

	-- COLLAR: short blue socket joining the blade top to the shaft.
	for y = 9, 10 do
		for x = -1, 1 do
			put(x, y, 1, BLUE)
			put(x, y, 2, BLUE)
		end
	end

	-- SHAFT: the long yellow handle stem (2 cells deep, 3 wide).
	for y = 11, 19 do
		for x = -1, 1 do
			put(x, y, 1, YELLOW)
			put(x, y, 2, YELLOW)
		end
	end

	-- GRIP: a rounded-rectangle yellow LOOP at the top (open in the middle), corners trimmed for the
	-- D-handle shape.
	local g0, g1 = 20, 25
	for y = g0, g1 do
		for x = -2, 2 do
			local border = (y == g0 or y == g1 or x == -2 or x == 2)
			local corner = (y == g0 or y == g1) and (x == -2 or x == 2)
			if border and not corner then
				put(x, y, 1, YELLOW)
				put(x, y, 2, YELLOW)
			end
		end
	end

	-- transparent core at the geometric centre => PrimaryPart for easy positioning.
	local core = Instance.new("Part")
	core.Name = "Center"
	core.Size = Vector3.new(0.2, 0.2, 0.2)
	core.Transparency = 1
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CFrame = CFrame.new(0, 12.5 * CUBE, 1.5 * CUBE)
	core.Parent = model
	model.PrimaryPart = core

	return model
end

return ShovelModel
