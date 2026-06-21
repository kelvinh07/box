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

-- Voxels whose ellipsoid value is BELOW this are carved out, leaving a hollow ~1-voxel SHELL
-- (so a brainrot can sit INSIDE the cracked bottom cup without the egg's interior clipping it).
PixelEgg.SHELL_INNER = 0.46

-- Build ONE HALF of a CRACKED pixel egg — a hollow eggshell cut along a jagged horizontal line.
-- `half` is "bottom" (the cup that stays upright) or "top" (the lid that popped off). Same
-- ellipsoid/voxel basis as PixelEgg.build so it reads as the SAME egg, just hollowed + split.
-- Returns an anchored Model (PrimaryPart = transparent EggCore at `center`).
function PixelEgg.buildHalf(center: Vector3, height: number, color: Color3, half: string, voxH: number?): Model
	local eggModel = Instance.new("Model")
	eggModel.Name = "EggHalf_" .. half

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
				local e = (px * px) / (rx * rx) + (py * py) / (ry * ry) + (pz * pz) / (rz * rz)
				if e <= 1 and e >= PixelEgg.SHELL_INNER then
					-- jagged horizontal crack about the egg's middle (two sine harmonics around the
					-- vertical axis), so the two halves interlock like a real broken eggshell.
					local ang = math.atan2(pz, px)
					local crackY = ry * 0.16 * math.sin(ang * 5) + ry * 0.08 * math.sin(ang * 2 + 1.3)
					local keep = (half == "top") and (py > crackY) or (half ~= "top" and py <= crackY)
					if keep then
						local cube = Instance.new("Part")
						cube.Name = "Stud"
						cube.Size = Vector3.new(vox, vox, vox)
						cube.Color = color
						cube.Material = Enum.Material.Plastic
						cube.TopSurface = Enum.SurfaceType.Studs
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
	end

	return eggModel
end

return PixelEgg
