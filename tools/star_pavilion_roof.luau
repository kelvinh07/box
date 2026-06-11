--!nocheck
--==================================================================
-- STAR-PAVILION HIP ROOF  — self-contained Studio/MCP script
--==================================================================
-- Replaces the shop's roof with a clean, symmetric N-sided pyramidal HIP roof:
-- N congruent triangular panels rising from a regular N-gon base perimeter to ONE
-- central apex, with radiating ridge hips, an eave overhang + trim, and an apex cupola.
--
-- Run on the SERVER DataModel while the game is playing (the shop is built at runtime).
-- It reads the shop's footprint + pillar height from the actual parts (nothing hardcoded),
-- deletes the old roof, and rebuilds. Re-running is idempotent.
--
-- This is a STANDALONE tool (lives outside src/, so `rojo build` ignores it). It edits the
-- LIVE session only — a Stop/Play rebuilds StandManager's own roof. Ask to bake it into
-- StandManager.buildPavilion if you want it permanent.
--==================================================================

-- ================= CONFIG (tweak these) =================
local gableCount    = 6                              -- number of peaks/panels (4 = cross-gable, 6 = fan)
local pitchDegrees  = 38                             -- slope of EVERY panel (one shared pitch)
local overhangStuds = 1.5                            -- eave oversail past the (binding) pillar
local roofColor     = Color3.fromRGB(198, 90, 46)    -- terracotta
local ridgeColor    = Color3.fromRGB(158, 68, 32)    -- darker terracotta (ridge/eave beams)
local addCupola     = true                           -- glowing apex lantern + downward spotlight
local roofMaterial  = Enum.Material.SmoothPlastic
local panelThick    = 0.5                            -- roof panel thickness
local ridgeThick    = 1.2                            -- ridge/hip beam thickness
local eaveThick     = 1.0                            -- eave trim thickness
local frontVertex   = true                           -- true: a peak points toward +Z (the lane); false: a flat edge faces +Z

-- ================= FIND THE SHOP =================
local shop = workspace:FindFirstChild("Stands") and workspace.Stands:FindFirstChild("ShopBuilding")
if not shop then
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("Model") and d.Name == "ShopBuilding" then shop = d; break end
	end
end
assert(shop, "ShopBuilding not found in Workspace")

-- ================= READ FOOTPRINT + PILLAR TOP (no hardcoded dims) =================
local floor = shop:FindFirstChild("Floor")
local cx, cz = floor.Position.X, floor.Position.Z       -- footprint centre (X,Z)
local eaveY  = -math.huge                               -- roof eave sits on the pillar tops
local pillars = {}                                      -- pillar XZ offsets from centre
for _, p in ipairs(shop:GetDescendants()) do
	if p:IsA("BasePart") and p.Name == "Pillar" then
		eaveY = math.max(eaveY, p.Position.Y + p.Size.Y / 2)
		table.insert(pillars, Vector2.new(p.Position.X - cx, p.Position.Z - cz))
	end
end
assert(eaveY > -math.huge, "no pillars found")

-- ================= DELETE THE OLD ROOF =================
local old = shop:FindFirstChild("Roof"); if old then old:Destroy() end
for _, d in ipairs(shop:GetChildren()) do
	if d:IsA("WedgePart") or d.Name == "Rafter" or d.Name == "ApexCap" or d.Name == "ApexLamp" then
		d:Destroy()
	end
end
local roofFolder = Instance.new("Folder"); roofFolder.Name = "Roof"; roofFolder.Parent = shop

-- ================= GEOMETRY =================
-- A regular N-gon base perimeter, centred over the footprint at eaveY. Because every edge is the
-- same distance (apothem) from the centre, every panel gets the SAME pitch automatically, and the
-- apex sits directly above the centre (a single apex). To make the eave oversail the pillars, size
-- the apothem so the most-constraining pillar projects just inside it, then add the overhang.
local N = gableCount
local edgeNormalOffset = frontVertex and (math.pi / N) or 0      -- where the edge-midpoints sit
local neededApothem = 0
for _, pv in ipairs(pillars) do
	local r = pv.Magnitude
	if r > 1e-3 then
		local ang = math.atan2(pv.X, pv.Y)                        -- angle from +Z, CW toward +X
		local k   = math.floor((ang - edgeNormalOffset) / (2 * math.pi / N) + 0.5)
		local nrm = edgeNormalOffset + k * (2 * math.pi / N)      -- nearest edge-normal direction
		neededApothem = math.max(neededApothem, r * math.cos(ang - nrm))  -- pillar's reach toward that edge
	end
end
local apothem  = neededApothem + overhangStuds                   -- centre -> edge midpoint
local R        = apothem / math.cos(math.pi / N)                 -- circumradius (centre -> vertex)
local apexRise = apothem * math.tan(math.rad(pitchDegrees))      -- SHARED pitch: rise over the apothem
local apex     = Vector3.new(cx, eaveY + apexRise, cz)           -- THE single apex, above the centre

-- N base vertices at perfectly even angular intervals
local verts = {}
local vertexOffset = frontVertex and 0 or (math.pi / N)
for i = 0, N - 1 do
	local ang = vertexOffset + i * (2 * math.pi / N)
	verts[i + 1] = Vector3.new(cx + R * math.sin(ang), eaveY, cz + R * math.cos(ang))
end

-- ================= TRIANGLE HELPER (Roblox has no native triangle) =================
-- Draws an arbitrary 3D triangle (three Vector3 corners) from TWO WedgeParts.
-- Algorithm (EgoMoose): reorder so 'a' is the right-angle vertex (the altitude foot lies between
-- the other two), then place two wedges that share the altitude seam and exactly tile triangle abc
-- with no skew — robust to the WedgePart fill convention.
local function triangle(a, b, c, thick, color)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then c, a = a, c
	elseif acd > bcd and acd > abd then a, b = b, a end
	ab, ac, bc = b - a, c - a, c - b
	local right  = ac:Cross(ab).Unit        -- triangle face normal
	local up     = bc:Cross(right).Unit      -- in-plane, ⟂ to the shared side bc
	local back   = bc.Unit
	local height = math.abs(ab:Dot(up))      -- altitude length (same for both halves)
	local function mk(pos, rt, bk, len)
		local w = Instance.new("WedgePart")
		w.Anchored, w.CanCollide = true, true
		w.Material, w.Color = roofMaterial, color
		w.Size = Vector3.new(thick, height, len)
		w.CFrame = CFrame.fromMatrix(pos, rt, up, bk)
		w.Parent = roofFolder
	end
	mk((a + b) / 2,  right,  back, math.abs(ab:Dot(back)))   -- half over side ab
	mk((a + c) / 2, -right, -back, math.abs(ac:Dot(back)))   -- half over side ac
end

-- ================= BUILD: one triangular panel per base edge -> apex =================
for i = 1, N do
	triangle(verts[i], verts[(i % N) + 1], apex, panelThick, roofColor)
end

-- thin beam spanning p1..p2 (decorative trim => CanCollide off)
local function beam(p1, p2, thick, color, name)
	local b = Instance.new("Part")
	b.Anchored, b.CanCollide = true, false
	b.Material, b.Color = roofMaterial, color
	b.Size = Vector3.new(thick, thick, (p2 - p1).Magnitude)
	b.CFrame = CFrame.lookAt((p1 + p2) / 2, p2)
	b.Name = name; b.Parent = roofFolder
end
for i = 1, N do beam(apex, verts[i], ridgeThick, ridgeColor, "Ridge") end                 -- radiating hip ridges
for i = 1, N do beam(verts[i], verts[(i % N) + 1], eaveThick, ridgeColor, "Eave") end      -- eave trim perimeter

-- ================= CUPOLA (apex lantern) =================
if addCupola then
	local lantern = Instance.new("Part")
	lantern.Name = "ApexLamp"; lantern.Anchored, lantern.CanCollide = true, false
	lantern.Material = Enum.Material.Neon
	lantern.Color = Color3.fromRGB(151, 135, 196)            -- midpoint of pink & cyan
	lantern.Transparency = 0.2
	lantern.Size = Vector3.new(4.5, 5.5, 4.5)
	lantern.CFrame = CFrame.new(apex + Vector3.new(0, 2.8, 0))
	lantern.Parent = roofFolder
	local cap = Instance.new("Part")                         -- little dark cap on top
	cap.Name = "CupolaCap"; cap.Anchored, cap.CanCollide = true, false
	cap.Material, cap.Color = roofMaterial, ridgeColor
	cap.Size = Vector3.new(6, 1, 6)
	cap.CFrame = CFrame.new(apex + Vector3.new(0, 5.8, 0))
	cap.Parent = roofFolder
	local pl = Instance.new("PointLight")
	pl.Color, pl.Brightness, pl.Range = Color3.fromRGB(255, 63, 184), 3, 32   -- pink glow
	pl.Parent = lantern
	local sl = Instance.new("SpotLight")                     -- cyan spill onto the floor
	sl.Face = Enum.NormalId.Bottom
	sl.Color, sl.Brightness, sl.Angle = Color3.fromRGB(47, 208, 208), 4, 90
	sl.Range = math.min(apexRise + 30, 110)
	sl.Parent = lantern
end

print(string.format("[StarPavilionRoof] N=%d apothem=%.1f R=%.1f apexRise=%.1f apexY=%.1f parts=%d",
	N, apothem, R, apexRise, apex.Y, #roofFolder:GetChildren()))
