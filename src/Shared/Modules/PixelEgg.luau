--!strict
-- PixelEgg
-- Builds the game's signature PIXEL / VOXEL egg — cube "studs" filling an egg
-- ellipsoid — as a self-contained ANCHORED Model. Shared so BOTH the client dig
-- site (the egg that pops out of a mound) and the SERVER incubators (the egg shown
-- hatching inside the glass case) render the EXACT same egg.
--
-- The colour is supplied by the caller (RarityColors.tier(rarity)); the SHAPE and
-- voxel grid depend only on `height`, so passing the SAME height for every rarity
-- yields same-SIZE eggs that differ ONLY in colour — which is exactly what the
-- incubator display wants (normalise size, keep colour).

local PixelEgg = {}

-- egg is taller than it is wide; VOX_H = how many voxels tall (higher = finer pixels
-- + more parts). 12 matches the dug egg exactly; the incubator passes a smaller value
-- so its (always-on) display eggs stay cheap while looking the same.
PixelEgg.WIDTH_RATIO = 0.72
PixelEgg.VOX_H = 12

-- Build a pixel egg centred at `center`, `height` studs tall, tinted `color`.
-- `voxH` (optional) overrides the vertical voxel count (default PixelEgg.VOX_H).
-- Returns the Model (PrimaryPart = a transparent EggCore at the centre, so callers
-- can drive the whole egg with one PivotTo / CFrameValue).
function PixelEgg.build(center: Vector3, height: number, color: Color3, voxH: number?): Model
	local eggModel = Instance.new("Model")
	eggModel.Name = "Egg"

	local core = Instance.new("Part")
	core.Name = "EggCore"
	core.Size = Vector3.new(0.2, 0.2, 0.2)
	core.Transparency = 1
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CFrame = CFrame.new(center)
	core.Parent = eggModel
	eggModel.PrimaryPart = core

	local rx = (height * PixelEgg.WIDTH_RATIO) / 2
	local ry = height / 2
	local rz = rx
	local vox = height / (voxH or PixelEgg.VOX_H)
	local nx, ny, nz = math.floor(rx / vox), math.floor(ry / vox), math.floor(rz / vox)
	for ix = -nx, nx do
		for iy = -ny, ny do
			for iz = -nz, nz do
				local px, py, pz = ix * vox, iy * vox, iz * vox
				if (px * px) / (rx * rx) + (py * py) / (ry * ry) + (pz * pz) / (rz * rz) <= 1 then
					local cube = Instance.new("Part")
					cube.Name = "Stud"
					cube.Size = Vector3.new(vox, vox, vox)
					cube.Color = color
					cube.Material = Enum.Material.Plastic
					cube.TopSurface = Enum.SurfaceType.Studs   -- classic Roblox stud look
					cube.BottomSurface = Enum.SurfaceType.Inlet
					cube.Anchored = true
					cube.CanCollide = false
					cube.CanQuery = false
					cube.CFrame = CFrame.new(center.X + px, center.Y + py, center.Z + pz)
					cube.Parent = eggModel
				end
			end
		end
	end

	return eggModel
end

return PixelEgg
