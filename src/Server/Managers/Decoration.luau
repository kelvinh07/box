--!strict
-- Decoration
-- Purely COSMETIC low-poly scatter + a dirt path. Built AFTER MapBuilder/BaseManager/
-- StandManager so it reads their finished geometry straight from the world.
--
-- POLY GRASS tufts + POLY FLOWERS are scattered across the WHOLE starting zone's open
-- grass — anywhere the ground (or a terrace grass-cap) is exposed. A downward raycast
-- against ONLY the grass surfaces gives the true sit height (so decor sits correctly on
-- the flat lobby AND on the stepped terrace), and KEEP-OUT rectangles derived from the
-- zone-1 dig slab, the shop pavilion, every base/plot, and the dirt path exclude those
-- footprints — so nothing ever lands ON the dig site, in the shop, in a plot, or on the path.
--
-- The DIRT PATH (shop front -> dig-site near edge) is a SINGLE raised, thick studded slab
-- (not overlapping segments, which z-fight) sitting clearly above the grass.

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Palette = require(Shared.Config.Palette)
local Surface = require(Shared.Modules.Surface)

local Decoration = {}

local rng = Random.new(20260611)

-- vibrant petal + grass tones (from Palette)
local PETALS = {
	Palette.Pink, Palette.Gold, Palette.Purple, Palette.Cyan,
	Color3.fromRGB(255, 95, 95), Color3.fromRGB(250, 250, 250),
}
local GRASS_TONES = { Palette.Grass, Palette.TreeLeaf, Color3.fromRGB(150, 240, 70) }
local FLOWER_CENTER = Color3.fromRGB(255, 210, 70)

-- starting-zone scatter region (the lobby + zone-1, framed by the terrace & the zone1/2 fence)
local REGION = { x1 = -295, x2 = 295, z1 = -295, z2 = 50 }
local GRID = 24       -- nominal spacing between scatter candidates
local JITTER = 10     -- per-candidate random offset
local PLACE_CHANCE = 0.72
local FLOWER_CHANCE = 0.24

-- raised dirt path + border
local PATH_WIDTH = 15
local PATH_THICK = 1.4
local PATH_TOP_Y = 1.7 -- top surface height (grass top is ~1.0, so it reads clearly raised)
local BORDER_W = 9     -- width of the dirt walkpath border framing the dig site

local scatterSub: Folder = nil :: any -- grass/flowers go here (excluded from the height raycast)
local pathFolder: Folder = nil :: any

----------------------------------------------------------------- keep-out (2D footprints)
type Rect = { x1: number, x2: number, z1: number, z2: number }
local keepOut: { Rect } = {}

local function addKeepOut(cx: number, cz: number, halfX: number, halfZ: number, margin: number)
	table.insert(keepOut, {
		x1 = cx - halfX - margin, x2 = cx + halfX + margin,
		z1 = cz - halfZ - margin, z2 = cz + halfZ + margin,
	})
end

local function blocked(x: number, z: number): boolean
	for _, r in ipairs(keepOut) do
		if x > r.x1 and x < r.x2 and z > r.z1 and z < r.z2 then
			return true
		end
	end
	return false
end

----------------------------------------------------------------- low-poly builders
local function blade(base: Vector3, h: number, yaw: number, tilt: number, col: Color3)
	local w = Instance.new("WedgePart")
	w.Anchored = true
	w.CanCollide = false
	w.CastShadow = false
	w.Material = Enum.Material.SmoothPlastic
	w.Color = col
	w.Size = Vector3.new(0.5, h, 1.2)
	w.CFrame = CFrame.new(base)
		* CFrame.Angles(0, yaw, 0)
		* CFrame.Angles(math.rad(tilt), 0, 0)
		* CFrame.new(0, h / 2, 0)
	w.Parent = scatterSub
end

-- a poly GRASS tuft: a fan of 4-6 tapered blades rising from `pos`
local function grassTuft(pos: Vector3)
	for _ = 1, rng:NextInteger(4, 6) do
		blade(pos, rng:NextNumber(2.2, 4.2), rng:NextNumber(0, math.pi * 2), rng:NextNumber(6, 24), GRASS_TONES[rng:NextInteger(1, #GRASS_TONES)])
	end
end

-- a poly FLOWER: thin stem + 5 petals + a center bud
local function flower(pos: Vector3)
	local stemH = rng:NextNumber(2.2, 3.4)
	local baseCF = CFrame.new(pos)
		* CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
		* CFrame.Angles(math.rad(rng:NextNumber(0, 9)), 0, 0)

	local stem = Instance.new("Part")
	stem.Anchored = true
	stem.CanCollide = false
	stem.CastShadow = false
	stem.Material = Enum.Material.SmoothPlastic
	stem.Color = Palette.TreeLeaf
	stem.Size = Vector3.new(0.35, stemH, 0.35)
	stem.CFrame = baseCF * CFrame.new(0, stemH / 2, 0)
	stem.Parent = scatterSub

	local headCF = baseCF * CFrame.new(0, stemH, 0)
	local col = PETALS[rng:NextInteger(1, #PETALS)]
	for k = 1, 5 do
		local ang = (k - 1) * (2 * math.pi / 5)
		local petal = Instance.new("Part")
		petal.Anchored = true
		petal.CanCollide = false
		petal.CastShadow = false
		petal.Material = Enum.Material.SmoothPlastic
		petal.Color = col
		petal.Size = Vector3.new(1.05, 0.28, 0.62)
		petal.CFrame = headCF * CFrame.Angles(0, ang, 0) * CFrame.new(0.72, 0.04, 0) * CFrame.Angles(0, 0, math.rad(20))
		petal.Parent = scatterSub
	end

	local bud = Instance.new("Part")
	bud.Anchored = true
	bud.CanCollide = false
	bud.CastShadow = false
	bud.Shape = Enum.PartType.Ball
	bud.Material = Enum.Material.SmoothPlastic
	bud.Color = FLOWER_CENTER
	bud.Size = Vector3.new(0.82, 0.82, 0.82)
	bud.CFrame = headCF * CFrame.new(0, 0.12, 0)
	bud.Parent = scatterSub
end

local function scatter(pos: Vector3)
	if rng:NextNumber() < FLOWER_CHANCE then
		flower(pos)
	else
		grassTuft(pos)
	end
end

-- a raised, thick, studded DIRT slab (shared by the shop path + the dig-site border); its top
-- sits at PATH_TOP_Y, clearly above the ~1.0 grass, so it never z-fights the ground
local function dirtSlab(name: string, cx: number, cz: number, sx: number, sz: number): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = true
	p.CastShadow = false
	p.Material = Enum.Material.Plastic
	p.Color = Palette.Dirt
	p.Size = Vector3.new(sx, PATH_THICK, sz)
	p.CFrame = CFrame.new(cx, PATH_TOP_Y - PATH_THICK / 2, cz)
	Surface.applyStuds(p)
	p.Parent = pathFolder
	return p
end

----------------------------------------------------------------- geometry discovery
local function findZone1Dig(): BasePart?
	for _, p in ipairs(CollectionService:GetTagged("DigPatch")) do
		if p:IsA("BasePart") and p:GetAttribute("Zone") == 1 then
			return p
		end
	end
	return nil
end

-- world-space AABB (min, max) of every BasePart under `inst`; nil if it has none
local function aabbOf(inst: Instance): (Vector3?, Vector3?)
	local mn = Vector3.new(math.huge, math.huge, math.huge)
	local mx = Vector3.new(-math.huge, -math.huge, -math.huge)
	local found = false
	for _, p in ipairs(inst:GetDescendants()) do
		if p:IsA("BasePart") then
			found = true
			local cf, sz = p.CFrame, p.Size
			local hx, hy, hz = sz.X / 2, sz.Y / 2, sz.Z / 2
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz2 in ipairs({ -1, 1 }) do
						local w = cf:PointToWorldSpace(Vector3.new(sx * hx, sy * hy, sz2 * hz))
						mn = Vector3.new(math.min(mn.X, w.X), math.min(mn.Y, w.Y), math.min(mn.Z, w.Z))
						mx = Vector3.new(math.max(mx.X, w.X), math.max(mx.Y, w.Y), math.max(mx.Z, w.Z))
					end
				end
			end
		end
	end
	if not found then
		return nil, nil
	end
	return mn, mx
end

----------------------------------------------------------------- build
function Decoration.init()
	local existing = Workspace:FindFirstChild("Decor")
	if existing then
		existing:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "Decor"
	root.Parent = Workspace
	scatterSub = Instance.new("Folder")
	scatterSub.Name = "Scatter"
	scatterSub.Parent = root
	pathFolder = Instance.new("Folder")
	pathFolder.Name = "DirtPath"
	pathFolder.Parent = root
	keepOut = {}

	-- ---- discover geometry + register footprint keep-outs ----
	local digCX, digCZ, digHX, digHZ = 0, -15, 75, 69
	local dig = findZone1Dig()
	if dig then
		digCX, digCZ = dig.Position.X, dig.Position.Z
		digHX, digHZ = dig.Size.X / 2, dig.Size.Z / 2
	end
	addKeepOut(digCX, digCZ, digHX, digHZ, 5) -- never ON the dig site

	local shopFrontZ = -155
	local stands = Workspace:FindFirstChild("Stands")
	local shop = stands and stands:FindFirstChild("ShopBuilding")
	if shop then
		local mn, mx = aabbOf(shop)
		if mn and mx then
			addKeepOut((mn.X + mx.X) / 2, (mn.Z + mx.Z) / 2, (mx.X - mn.X) / 2, (mx.Z - mn.Z) / 2, 5)
			shopFrontZ = mx.Z
		end
	end

	local bases = Workspace:FindFirstChild("PlayerBases")
	if bases then
		for _, b in ipairs(bases:GetChildren()) do
			local mn, mx = aabbOf(b)
			if mn and mx then
				addKeepOut((mn.X + mx.X) / 2, (mn.Z + mx.Z) / 2, (mx.X - mn.X) / 2, (mx.Z - mn.Z) / 2, 3)
			end
		end
	end

	-- ---- DIRT BORDER WALKPATH framing 3 sides of the dig site (+Z left OPEN for the zone wall) ----
	local pitFront = digCZ - digHZ -- -Z (lobby) edge
	local pitBack = digCZ + digHZ -- +Z (zone-wall) edge — left open
	local pitLeft, pitRight = digCX - digHX, digCX + digHX
	local sideCZ = (pitFront + pitBack) / 2
	local sideLen = pitBack - pitFront
	-- front strip spans the full pit width incl. the two front corners
	dirtSlab("BorderFront", digCX, pitFront - BORDER_W / 2, (digHX + BORDER_W) * 2, BORDER_W)
	-- flanks run from the front edge back to the open +Z edge (butt-join the front strip at pitFront)
	dirtSlab("BorderLeft", pitLeft - BORDER_W / 2, sideCZ, BORDER_W, sideLen)
	dirtSlab("BorderRight", pitRight + BORDER_W / 2, sideCZ, BORDER_W, sideLen)
	addKeepOut(digCX, pitFront - BORDER_W / 2, digHX + BORDER_W, BORDER_W / 2, 1)
	addKeepOut(pitLeft - BORDER_W / 2, sideCZ, BORDER_W / 2, sideLen / 2, 1)
	addKeepOut(pitRight + BORDER_W / 2, sideCZ, BORDER_W / 2, sideLen / 2, 1)

	-- ---- main shop -> dig DIRT PATH: one raised slab; butt-joins the front border's outer edge ----
	local pz1 = shopFrontZ + 2
	local pz2 = pitFront - BORDER_W -- meet the front border's outer (-Z) edge so the two butt-join
	local pathLen = math.abs(pz2 - pz1)
	local pathCZ = (pz1 + pz2) / 2
	dirtSlab("PathSlab", digCX, pathCZ, PATH_WIDTH, pathLen)
	-- darker dirt pebbles bedded into the top (distinct heights -> no z-fight) for texture
	for _ = 1, 9 do
		local peb = Instance.new("Part")
		peb.Anchored = true
		peb.CanCollide = false
		peb.CastShadow = false
		peb.Material = Enum.Material.Plastic
		peb.Color = Palette.DigField
		local s = rng:NextNumber(1.6, 3.0)
		peb.Size = Vector3.new(s, 0.8, s)
		peb.CFrame = CFrame.new(digCX + rng:NextNumber(-PATH_WIDTH / 2 + 1, PATH_WIDTH / 2 - 1), PATH_TOP_Y, pz1 + (pz2 - pz1) * rng:NextNumber(0.04, 0.96))
			* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
		Surface.applyStuds(peb)
		peb.Parent = pathFolder
	end
	-- keep grass/flowers off the path
	addKeepOut(digCX, pathCZ, PATH_WIDTH / 2, pathLen / 2, 3)

	-- ---- collect grass surfaces for the height raycast (ground + terrace/lane caps) ----
	local grassParts: { Instance } = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("BasePart") and CollectionService:HasTag(d, "GrassSurface") then
			table.insert(grassParts, d)
		end
	end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Include
	rayParams.FilterDescendantsInstances = grassParts
	local DOWN = Vector3.new(0, -600, 0)

	-- ---- BROAD SCATTER across the starting zone's open grass ----
	for gx = REGION.x1, REGION.x2, GRID do
		for gz = REGION.z1, REGION.z2, GRID do
			if rng:NextNumber() < PLACE_CHANCE then
				local x = gx + rng:NextNumber(-JITTER, JITTER)
				local z = gz + rng:NextNumber(-JITTER, JITTER)
				if not blocked(x, z) then
					-- sit on whatever grass is here (flat ground OR a terrace cap); skip if no grass
					local hit = Workspace:Raycast(Vector3.new(x, 400, z), DOWN, rayParams)
					if hit then
						scatter(hit.Position)
					end
				end
			end
		end
	end
end

return Decoration
