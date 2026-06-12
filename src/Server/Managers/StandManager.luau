--!strict
-- StandManager
-- Builds the central OPEN-AIR WOODEN SHOP in the middle plaza: a pavilion (no walls — airflow)
-- with a raised plank FLOOR, 4 corner PILLARS, top eave beams + corner braces, and a HIP ROOF.
-- It faces +Z (toward the dig lane / zone walls). Inside it stations two upgrade vendors and a
-- back row of daily-reward / robux features:
--   • LEFT  (-X) : 🪓 Shovel vendor   -> StandType "Shovel"
--   • RIGHT (+X) : 🔥 Incubator vendor -> StandType "Incubator"
--   • BACK  (-Z) : 🎁 Daily Reward + 💎 Robux Shop (VISUAL placeholders — extend later)
--
-- The VENDORS are JUST the character extracted from the imported ServerStorage.ShopModel (the
-- market-stall shed is discarded) plus an INSTANT ProximityPrompt (press E, no hold) carrying a
-- `StandType` attribute the CLIENT reads to open the matching upgrade panel — there is NO
-- server-side open handler (opening is UI). If ShopModel is missing, a procedural bacon-hair
-- vendor is used instead. Idempotent: init() rebuilds the Stands folder each call.
--
-- TEXTURE: every wood part uses the world's CLASSIC STUDS+INLETS overlay (Surface.applyStuds via
-- the default Plastic material) in BROWN wood colours — matching the rest of the build, NOT the
-- smooth WoodPlanks material.

local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local Surface = require(ReplicatedStorage.Shared.Modules.Surface)

local StandManager = {}

local STANDS_FOLDER_NAME = "Stands"
local SHOP_MODEL_NAME = "ShopModel" -- imported model we pull the vendor CHARACTER out of
local VENDOR_SCALE = 2 -- shopkeeper size multiplier (grounded on the booth floor; roomy under the eave)

-- ===================== OPEN PAVILION (central shop) =====================
-- Centered on PAV_CX/PAV_CZ in the parted-plot plaza, FRONT (open, +Z) toward the dig lane.
-- Footprint clears the side plots (nearest inner-plot corner ~x74) and the lobby wall behind
-- (~z-235). Floor is a raised plank platform; the structure is otherwise OPEN (airflow).
local PAV_CX = 0
local PAV_CZ = -195 -- pavilion center Z: pushed back toward the lobby-wall TERRACE (its near-centre front face is ~z-275) while keeping a courtyard gap — the shop's back extent lands at ~z-235.
local PAV_HALF_W = 44 -- floor half-width (X) -> 88 wide (bigger shop — more width)
local PAV_HALF_L = 36 -- floor half-length (Z) -> 72 long (bigger shop — a bit more length)
local FLOOR_TOP = 2 -- raised floor TOP Y (1-stud step up from the ground)
local EAVE_Y = 34 -- pillar top / roof eave height (longer pillars -> raised ceiling + higher roof)
local ROOF_OVERHANG = 3 -- roof eave extends this far past the floor edge
local PILLAR_INSET = 1.5 -- pillars sit this far in from the floor corners
-- SHINGLE-ROW HIP ROOF: a 4-sided hip of even horizontal shingle courses (alternating brown bands).
local ROOF_RISE = 20 -- apex height above the eave (lower = broader/flatter roof)

-- CORNER STALLS: two booths in the FRONT corners. Each REUSES the pavilion's main corner pillar as
-- its OUTER pillar, adds 3 more FULL-SIZE (4x4) pillars inward to finish the square, and is wrapped
-- by a waist-high SOLID plank fence on all sides. NO separate roof — the main pavilion roof covers it.
local STALL_S = 20                                                  -- stall side length (inward from the corner pillar) — BIGGER booth
local STALL_FENCE_H = 4                                             -- plank fence (counter) height — a touch taller for the bigger booth
local STALL_CX = (PAV_HALF_W - PILLAR_INSET) - STALL_S / 2          -- |X| of each stall / vendor centre
local STALL_CZ = PAV_CZ + (PAV_HALF_L - PILLAR_INSET) - STALL_S / 2 -- Z of each stall / vendor centre

-- FRONT-CORNER L-WINDOWS: each FRONT corner pillar is SPLIT (a bottom + a top stub) by a horizontal
-- WINDOW band that wraps the corner (an L in plan — one leg down each wall) so the corner stall is
-- visible from outside. The opening is trimmed with SLENDER (thinner-than-pillar) timber framing.
local CORNER_WIN_LEG = STALL_S                    -- window leg length along each wall from the corner (= stall span)
local CORNER_WIN_SILL = FLOOR_TOP + STALL_FENCE_H -- window bottom Y = stall fence (counter) top
local CORNER_WIN_TOP = 22                         -- window top Y (a plank header bridges above, up to the eave)
local CORNER_FRAME_T = 1.6                        -- slender framing cross-section (vs the 4-stud main pillars)

-- INTERACTION CIRCLE: a glowing white ring on the booth floor; the client auto-opens that shop's panel
-- when the player steps inside it. A little bigger than the STALL_S booth box.
local SHOP_ZONE_RADIUS = 16 -- interaction circle radius (visual ring + auto-open trigger)

-- enclosing PLANK WALLS + a centred double-door opening in the FRONT (where the dirt path enters)
local DOOR_HALF = 13   -- half-width of the front double-door opening (even wider — 26 wide)
local DOOR_TOP = 18    -- top of the door opening; a plank header fills above it

-- BROWN WOOD colours (Plastic material -> Surface.applyStuds gives the studs+inlets look)
local WOOD_MED = Palette.Fence -- warm brown: floor + roof panels (#B06430)
local WOOD_DARK = Palette.TreeTrunk -- dark brown: pillars / beams / rafters (#784A2C)

-- Build an anchored part with the classic studded legoish look (Surface.applyStuds overlays the
-- real Roblox studs texture on every face). Default material is Plastic so wood gets STUDDED.
-- Glow/glass/see-through parts auto-skip; pass NoStuds=true to force-skip (e.g. NPC limbs, glow).
local function makePart(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = true
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

-- A box beam spanning p1..p2 (square cross-section `thick`), studded. Used for rafters/braces.
local function beam(p1: Vector3, p2: Vector3, thick: number, color: Color3, parent: Instance, name: string?): BasePart
	local len = (p2 - p1).Magnitude
	return makePart({
		Name = name or "Beam",
		Size = Vector3.new(thick, thick, len),
		Color = color,
		CFrame = CFrame.lookAt((p1 + p2) / 2, p2),
		Parent = parent,
	})
end

-- Build one ROOF SLOPE as even horizontal SHINGLE COURSES between an eave edge (eL..eR) and the
-- apex. Each course is a FLAT axis-aligned plank (so the studs tile cleanly); courses are coplanar
-- (one flat slope), taper toward the apex (the hip), and alternate colour like real shingles. Basis
-- is derived from geometry (no slope-sign guesswork); `normal` is forced to point up/out.
local function buildSlopeShingles(eL: Vector3, eR: Vector3, apex: Vector3, parent: Instance)
	local eaveMid = (eL + eR) / 2
	local eaveVec = eR - eL
	local eaveLen = eaveVec.Magnitude
	local eaveDir = eaveVec.Unit
	local up = apex - eaveMid
	local upLen = up.Magnitude
	local normal = eaveDir:Cross(up).Unit
	if normal.Y < 0 then
		normal = -normal
	end
	local N = 7
	local rowDepth = upLen / N + 1.8 -- slight overlap between courses
	for i = 0, N - 1 do
		local tc = (i + 0.5) / N
		local rowLen = math.max(eaveLen * (1 - tc), 2)
		makePart({
			Name = "Shingle",
			Size = Vector3.new(rowLen, 1, rowDepth),
			Color = (i % 2 == 0) and WOOD_MED or WOOD_DARK,
			CFrame = CFrame.fromMatrix(eaveMid + up * tc, eaveDir, normal),
			Parent = parent,
		})
	end
end

-- A camera-facing FredokaOne label floating at a world point (vendor name tags).
local function floatingLabel(text: string, pos: Vector3, parent: Instance, width: number?): BasePart
	local anchor = makePart({ Name = "Label", Size = Vector3.new(1, 1, 1), Transparency = 1, CanCollide = false, NoStuds = true, CFrame = CFrame.new(pos), Parent = parent })
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, width or 200, 0, 46)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 80
	bb.Parent = anchor
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.Text = text
	lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
	lbl.TextStrokeTransparency = 0
	lbl.Parent = bb
	return anchor
end

-- A wood SIGN BOARD with the text rendered ON the wood (SurfaceGui), same style as the plot
-- name-plates. `faceDir` is which way (+Z/-Z) the text should read toward. Studded brown board.
local function woodSign(text: string, size: Vector3, pos: Vector3, faceDir: number, parent: Instance): BasePart
	local board = makePart({ Name = "SignBoard", Size = size, Color = WOOD_DARK, CFrame = CFrame.new(pos), Parent = parent })
	local sg = Instance.new("SurfaceGui")
	sg.Name = "SignGui"
	sg.Face = faceDir >= 0 and Enum.NormalId.Back or Enum.NormalId.Front -- +Z face = Back, -Z face = Front
	sg.CanvasSize = Vector2.new(1000, 220)
	sg.LightInfluence = 0
	sg.Parent = board
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.Text = text
	lbl.TextColor3 = Color3.fromRGB(120, 220, 255)
	lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	lbl.TextStrokeTransparency = 0.3
	lbl.Parent = sg
	return board
end

----------------------------------------------------------------- bacon-hair NPC (fallback vendor)
local SKIN = Color3.fromRGB(245, 205, 48)
local BACON = Color3.fromRGB(122, 73, 42)

local function buildBaconNPC(parent: Instance, namePrefix: string): Model
	local model = Instance.new("Model")
	model.Name = ("%sVendor"):format(namePrefix)
	local torso = makePart({ Name = "Torso", Size = Vector3.new(2, 2, 1), Color = Palette.BaseFloor, CanCollide = false, NoStuds = true, CFrame = CFrame.new(0, 0, 0), Parent = model })
	model.PrimaryPart = torso
	local head = makePart({ Name = "Head", Size = Vector3.new(2, 1, 1), Color = SKIN, CanCollide = false, NoStuds = true, CFrame = CFrame.new(0, 1.5, 0), Parent = model })
	for _, sx in ipairs({ -1, 1 }) do
		makePart({ Name = "Eye", Size = Vector3.new(0.18, 0.22, 0.12), Color = Color3.fromRGB(15, 15, 15), CanCollide = false, NoStuds = true, CFrame = head.CFrame * CFrame.new(sx * 0.32, 0.1, 0.52), Parent = model })
		makePart({ Name = "Arm", Size = Vector3.new(1, 2, 1), Color = SKIN, CanCollide = false, NoStuds = true, CFrame = CFrame.new(sx * 1.5, 0, 0), Parent = model })
		makePart({ Name = "Leg", Size = Vector3.new(1, 2, 1), Color = SKIN, CanCollide = false, NoStuds = true, CFrame = CFrame.new(sx * 0.5, -2, 0), Parent = model })
	end
	local hairTufts = {
		{ size = Vector3.new(1.2, 0.9, 1.0), lz = -0.15, ly = 0.7, tilt = -0.25 },
		{ size = Vector3.new(1.0, 0.8, 1.0), lz = -0.85, ly = 0.55, tilt = -0.55 },
		{ size = Vector3.new(0.85, 0.7, 0.9), lz = -1.45, ly = 0.3, tilt = -0.85 },
	}
	for i, t in ipairs(hairTufts) do
		local wedge = Instance.new("WedgePart")
		wedge.Name = ("Hair%d"):format(i)
		wedge.Anchored = true
		wedge.CanCollide = false
		wedge.Material = Enum.Material.Plastic
		wedge.Color = BACON
		wedge.Size = t.size
		wedge.CFrame = head.CFrame * CFrame.new(0, t.ly, t.lz) * CFrame.Angles(t.tilt, math.pi, 0)
		wedge.Parent = model
	end
	model.Parent = parent
	return model
end

-- A fresh CLONE of the imported shop template (anchored), or nil if absent.
local function getShopTemplate(): Model?
	local tmpl = ServerStorage:FindFirstChild(SHOP_MODEL_NAME)
	if tmpl and tmpl:IsA("Model") then
		return tmpl:Clone()
	end
	return nil
end

-- Uniformly SCALE an anchored, posed model about a fixed world point: each part's Size and its offset
-- from `pivot` scale by `scale`, orientation preserved. Robust for rigged/imported characters where
-- Model:ScaleTo can misbehave (invisible oversized roots, scatter). Pivot at the feet keeps it grounded.
local function scaleModelAbout(model: Instance, scale: number, pivot: Vector3)
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Size = p.Size * scale
			local cf = p.CFrame
			p.CFrame = (cf - cf.Position) + (pivot + (cf.Position - pivot) * scale)
		end
	end
end

----------------------------------------------------------------- a vendor (character + prompt only)
-- Stations ONLY the vendor CHARACTER (extracted from ShopModel, shed discarded) standing on the
-- floor facing +Z, with a name tag and an INSTANT StandType ProximityPrompt. No stall/booth.
local function buildVendor(standType: string, title: string, pos: Vector3, parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = ("%sStand"):format(standType)
	folder.Parent = parent

	local vendor: Model? = nil
	local shop = getShopTemplate()
	if shop then
		local npc = shop:FindFirstChild("Npc")
		if npc and npc:IsA("Model") then
			npc.Parent = folder -- pull the CHARACTER out; discard the rest of the shed
			for _, d in ipairs(npc:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
				end
			end
			local hum = npc:FindFirstChildOfClass("Humanoid")
			if hum then
				hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None -- no name/health bars
			end
			vendor = npc
		end
		shop:Destroy()
	end
	if not vendor then
		vendor = buildBaconNPC(folder, standType)
	end
	local v = vendor :: Model
	v.Name = ("%sVendor"):format(standType)

	-- orient facing +Z (toward the courtyard / incoming players), then drop feet onto the floor.
	local flat = Vector3.new(pos.X, 0, pos.Z)
	v:PivotTo(CFrame.lookAt(flat, flat + Vector3.new(0, 0, 10)))
	local cf, sz = v:GetBoundingBox()
	v:PivotTo(v:GetPivot() + Vector3.new(0, FLOOR_TOP - (cf.Y - sz.Y / 2), 0))

	-- BIG shopkeeper: scale up about the feet so it stays grounded on the booth floor
	if VENDOR_SCALE ~= 1 then
		scaleModelAbout(v, VENDOR_SCALE, Vector3.new(pos.X, FLOOR_TOP, pos.Z))
	end
	local _, sz2 = v:GetBoundingBox()

	-- name tag above the (scaled) head
	floatingLabel(title, Vector3.new(pos.X, FLOOR_TOP + sz2.Y + 1.6, pos.Z), folder, 200)

	-- invisible interact volume + instant prompt (client opens the panel off StandType)
	local interact = makePart({ Name = "Interact", Size = Vector3.new(6, 7, 5), Transparency = 1, CanCollide = false, NoStuds = true, CFrame = CFrame.new(pos.X, FLOOR_TOP + 3.5, pos.Z), Parent = folder })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenPrompt"
	prompt.ActionText = "Open"
	prompt.ObjectText = title
	prompt.HoldDuration = 0
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = SHOP_ZONE_RADIUS
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("StandType", standType)
	prompt:SetAttribute("ZoneRadius", SHOP_ZONE_RADIUS) -- client auto-opens this shop when inside the ring
	prompt.Parent = interact
end

----------------------------------------------------------------- back features (placeholders)
local function buildDailyReward(parent: Instance)
	local cx, cz = PAV_CX - PAV_HALF_W / 2, PAV_CZ - PAV_HALF_L / 2 -- back-left quadrant (Q2) centre
	makePart({ Name = "DailyPodium", Size = Vector3.new(11, 2, 7), Color = WOOD_MED, CFrame = CFrame.new(cx, FLOOR_TOP + 1, cz), Parent = parent })
	makePart({ Name = "DailyGift", Size = Vector3.new(5, 5, 5), Color = Palette.Pink, Material = Enum.Material.Neon, CanCollide = false, NoStuds = true, CFrame = CFrame.new(cx, FLOOR_TOP + 4.5, cz), Parent = parent })
	makePart({ Name = "Ribbon", Size = Vector3.new(5.2, 1.1, 1.2), Color = Palette.Gold, Material = Enum.Material.Neon, CanCollide = false, NoStuds = true, CFrame = CFrame.new(cx, FLOOR_TOP + 4.5, cz), Parent = parent })
	makePart({ Name = "Ribbon", Size = Vector3.new(1.2, 1.1, 5.2), Color = Palette.Gold, Material = Enum.Material.Neon, CanCollide = false, NoStuds = true, CFrame = CFrame.new(cx, FLOOR_TOP + 4.5, cz), Parent = parent })
	makePart({ Name = "Bow", Size = Vector3.new(1.8, 1.6, 1.8), Color = Palette.Gold, Material = Enum.Material.Neon, CanCollide = false, NoStuds = true, CFrame = CFrame.new(cx, FLOOR_TOP + 7.8, cz), Parent = parent })
	floatingLabel("🎁 DAILY REWARD", Vector3.new(cx, FLOOR_TOP + 11, cz), parent, 230)
end

local function buildRobuxShop(parent: Instance)
	local cx, cz = PAV_CX + PAV_HALF_W / 2, PAV_CZ - PAV_HALF_L / 2 -- back-right quadrant (Q1) centre
	makePart({ Name = "RobuxCounter", Size = Vector3.new(16, 2, 7), Color = WOOD_MED, CFrame = CFrame.new(cx, FLOOR_TOP + 1, cz), Parent = parent })
	for i = -1, 1 do
		local px = cx + i * 5
		makePart({ Name = "RobuxPedestal", Size = Vector3.new(2.6, 3, 2.6), Color = Palette.Podium, Material = Enum.Material.Neon, CanCollide = false, NoStuds = true, CFrame = CFrame.new(px, FLOOR_TOP + 3.5, cz), Parent = parent })
		makePart({ Name = "RobuxToken", Size = Vector3.new(2, 2, 2), Color = Palette.Lime, Material = Enum.Material.Neon, CanCollide = false, NoStuds = true, CFrame = CFrame.new(px, FLOOR_TOP + 6, cz) * CFrame.Angles(0, math.rad(35), 0), Parent = parent })
	end
	floatingLabel("💎 ROBUX SHOP", Vector3.new(cx, FLOOR_TOP + 11, cz), parent, 230)
end

----------------------------------------------------------------- the open pavilion
-- One front-corner STALL (sign = -1 left / +1 right). The OUTER pillar is the existing main corner
-- pillar; add 3 more FULL-SIZE (4x4, full-height) pillars inward to finish the square, then wrap a
-- waist-high SOLID plank fence around all four sides. No roof (the main pavilion roof covers it).

-- A glowing WHITE interaction RING on the floor (many TINY Neon segments), marking the auto-open zone.
-- Each segment is oriented along the circle's TANGENT (via lookAt) and overlaps the next, so the line
-- reads as a continuous smooth circle rather than dashes.
local function buildShopRing(parent: Instance, cx: number, cz: number, radius: number)
	local ring = Instance.new("Folder")
	ring.Name = "ShopZoneRing"
	ring.Parent = parent
	local y = FLOOR_TOP + 0.2
	local circumference = 2 * math.pi * radius
	local N = math.max(120, math.ceil(circumference / 0.7)) -- tiny segments, ~0.7 studs apart
	local segLen = circumference / N + 0.5 -- generous overlap so there are NO gaps
	for i = 0, N - 1 do
		local a = (i / N) * math.pi * 2
		local pos = Vector3.new(cx + math.cos(a) * radius, y, cz + math.sin(a) * radius)
		local tangent = Vector3.new(-math.sin(a), 0, math.cos(a))
		local seg = Instance.new("Part")
		seg.Name = "RingSeg"
		seg.Anchored = true
		seg.CanCollide = false
		seg.CastShadow = false
		seg.Material = Enum.Material.Neon -- self-lit white = the "slight glow"
		seg.Color = Color3.fromRGB(255, 255, 255)
		seg.Size = Vector3.new(0.5, 0.2, segLen) -- X=radial thickness, Z=length along the tangent
		seg.CFrame = CFrame.lookAt(pos, pos + tangent)
		seg.Parent = ring
	end
	return ring
end

local function buildCornerStall(parent: Instance, sign: number)
	local pilX = PAV_HALF_W - PILLAR_INSET          -- main-pillar |X|
	local ox, ix = sign * pilX, sign * (pilX - STALL_S) -- outer (= the main pillar) + inner pillar X
	local oz = PAV_CZ + (PAV_HALF_L - PILLAR_INSET) -- front pillar-row Z (outer-front = the main pillar)
	local bz = oz - STALL_S                         -- back pillar-row Z
	local pillarH = EAVE_Y - FLOOR_TOP
	local function pillar(x: number, z: number)
		makePart({ Name = "StallPillar", Size = Vector3.new(4, pillarH, 4), Color = WOOD_DARK, CFrame = CFrame.new(x, (FLOOR_TOP + EAVE_Y) / 2, z), Parent = parent })
	end
	-- INNER-FRONT corner SPLIT (bottom + top stub) like the building's outer corner, so the booth gets a
	-- matching L-shaped framed WINDOW on its inner side (the corner that faces into the shop).
	local botH = CORNER_WIN_SILL - FLOOR_TOP
	local topY = 35.5 -- extend the corner post up to just under the sloped roof (underside ~35.75 here)
	local topH = topY - CORNER_WIN_TOP
	makePart({ Name = "StallPillar", Size = Vector3.new(4, botH, 4), Color = WOOD_DARK, CFrame = CFrame.new(ix, FLOOR_TOP + botH / 2, oz), Parent = parent })
	makePart({ Name = "StallPillar", Size = Vector3.new(4, topH, 4), Color = WOOD_DARK, CFrame = CFrame.new(ix, topY - topH / 2, oz), Parent = parent })
	pillar(ox, bz) -- outer-back
	pillar(ix, bz) -- inner-back   (the outer-FRONT pillar IS the main pavilion pillar — not rebuilt)
	-- waist-high SOLID plank fence around all 4 sides (pillar-centre to pillar-centre)
	local fy = FLOOR_TOP + STALL_FENCE_H / 2
	local midX, midZ = (ox + ix) / 2, (oz + bz) / 2
	makePart({ Name = "StallFence", Size = Vector3.new(STALL_S, STALL_FENCE_H, 0.9), Color = WOOD_MED, CFrame = CFrame.new(midX, fy, oz), Parent = parent }) -- front
	makePart({ Name = "StallFence", Size = Vector3.new(STALL_S, STALL_FENCE_H, 0.9), Color = WOOD_MED, CFrame = CFrame.new(midX, fy, bz), Parent = parent }) -- back
	makePart({ Name = "StallFence", Size = Vector3.new(0.9, STALL_FENCE_H, STALL_S), Color = WOOD_MED, CFrame = CFrame.new(ox, fy, midZ), Parent = parent }) -- outer
	makePart({ Name = "StallFence", Size = Vector3.new(0.9, STALL_FENCE_H, STALL_S), Color = WOOD_MED, CFrame = CFrame.new(ix, fy, midZ), Parent = parent }) -- inner
	-- FRAME ALL FOUR SIDES the same way: a slender sill rail (atop the fence) + a lintel beam on each side.
	local t = CORNER_FRAME_T
	for _, y in ipairs({ CORNER_WIN_SILL, CORNER_WIN_TOP }) do
		makePart({ Name = "WindowFrame", Size = Vector3.new(STALL_S, t, t), Color = WOOD_DARK, CFrame = CFrame.new(midX, y, oz), Parent = parent }) -- front
		makePart({ Name = "WindowFrame", Size = Vector3.new(STALL_S, t, t), Color = WOOD_DARK, CFrame = CFrame.new(midX, y, bz), Parent = parent }) -- back
		makePart({ Name = "WindowFrame", Size = Vector3.new(t, t, STALL_S), Color = WOOD_DARK, CFrame = CFrame.new(ix, y, midZ), Parent = parent }) -- inner
		makePart({ Name = "WindowFrame", Size = Vector3.new(t, t, STALL_S), Color = WOOD_DARK, CFrame = CFrame.new(ox, y, midZ), Parent = parent }) -- outer
	end
	-- FILL THE TOP with header PLANKS above the window on ALL FOUR sides, so the whole booth box is a
	-- framed window on every side (matching the exterior corners).
	local function headerWall(x1: number, z1: number, x2: number, z2: number)
		local dx, dz = x2 - x1, z2 - z1
		local len = math.sqrt(dx * dx + dz * dz)
		local n = math.max(1, math.floor(len / 5 + 0.5))
		local bl = len / n
		local ux, uz = dx / len, dz / len
		local angle = math.atan2(dx, dz)
		local hh = EAVE_Y - CORNER_WIN_TOP
		for i = 0, n - 1 do
			local tt = bl * (i + 0.5)
			makePart({ Name = "ShopWall", Size = Vector3.new(1.5, hh, bl + 0.15), Color = WOOD_MED, CFrame = CFrame.new(x1 + ux * tt, CORNER_WIN_TOP + hh / 2, z1 + uz * tt) * CFrame.Angles(0, angle, 0), Parent = parent })
		end
	end
	headerWall(ix, oz, ix, bz) -- inner side
	headerWall(ox, oz, ox, bz) -- outer side
	headerWall(ix, oz, ox, oz) -- front side
	headerWall(ix, bz, ox, bz) -- back side (the one the shopkeeper's back faces)
	-- glowing interaction ring on the floor, a bit bigger than the booth box
	buildShopRing(parent, midX, midZ, SHOP_ZONE_RADIUS)
end

-- a run of vertical PLANK boards (two alternating wood tones) from (ax,az) to (bx,bz), spanning y0..y1.
local function plankRun(parent: Instance, ax: number, az: number, bx: number, bz: number, y0: number, y1: number)
	local dx, dz = bx - ax, bz - az
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 0.5 then
		return
	end
	local angle = math.atan2(dx, dz) -- run direction (local +Z runs along the wall)
	local n = math.max(1, math.floor(len / 5 + 0.5))
	local bl = len / n
	local ux, uz = dx / len, dz / len
	local h = y1 - y0
	for i = 0, n - 1 do
		local t = bl * (i + 0.5)
		makePart({ Name = "ShopWall", Size = Vector3.new(1.5, h, bl + 0.15), Color = WOOD_MED, CFrame = CFrame.new(ax + ux * t, y0 + h / 2, az + uz * t) * CFrame.Angles(0, angle, 0), Parent = parent })
	end
end

-- Like plankRun, but leaves a horizontal WINDOW band [sillY..lintY] OPEN: it builds the planks BELOW
-- the sill (y0..sillY) and the header ABOVE the lintel (lintY..y1), skipping the middle.
local function windowedRun(parent: Instance, ax: number, az: number, bx: number, bz: number, y0: number, y1: number, sillY: number, lintY: number)
	if sillY > y0 then
		plankRun(parent, ax, az, bx, bz, y0, sillY) -- wall below the window
	end
	if y1 > lintY then
		plankRun(parent, ax, az, bx, bz, lintY, y1) -- header plank above the window
	end
end

-- Slender timber FRAME around one front-corner L-window (sign = -1 left / +1 right): a thin
-- full-height mullion post at the INNER end of each leg ("the pillar, but thinner") + a sill and a
-- lintel bar capping the opening. The chunky SPLIT corner pillar frames the corner itself. `proud`
-- is the signed offset off the wall face — POSITIVE = exterior trim, NEGATIVE = interior trim — so
-- calling it with ±0.8 frames the window the SAME on both the inside and the outside.
local function buildCornerWindowFrame(parent: Instance, sign: number, proud: number)
	local R = PAV_CX + sign * PAV_HALF_W -- this corner's outer wall edge (±44)
	local F = PAV_CZ + PAV_HALF_L        -- front wall edge
	local W = CORNER_WIN_LEG
	local t = CORNER_FRAME_T
	local midY = (FLOOR_TOP + EAVE_Y) / 2
	local fullH = EAVE_Y - FLOOR_TOP
	-- thin full-height mullion posts at each leg's INNER end
	makePart({ Name = "WindowFrame", Size = Vector3.new(t, fullH, t), Color = WOOD_DARK, CFrame = CFrame.new(R - sign * W, midY, F + proud), Parent = parent }) -- front leg inner
	makePart({ Name = "WindowFrame", Size = Vector3.new(t, fullH, t), Color = WOOD_DARK, CFrame = CFrame.new(R + sign * proud, midY, F - W), Parent = parent }) -- side leg inner
	-- sill (bottom) + lintel (top) bars along each leg (front leg runs in X, side leg runs in Z)
	for _, y in ipairs({ CORNER_WIN_SILL, CORNER_WIN_TOP }) do
		makePart({ Name = "WindowFrame", Size = Vector3.new(W + t, t, t), Color = WOOD_DARK, CFrame = CFrame.new(R - sign * W / 2, y, F + proud), Parent = parent }) -- front leg
		makePart({ Name = "WindowFrame", Size = Vector3.new(t, t, W + t), Color = WOOD_DARK, CFrame = CFrame.new(R + sign * proud, y, F - W / 2), Parent = parent }) -- side leg
	end
end

-- enclose the pavilion with PLANK walls: solid back, an L-WINDOW leg wrapping each FRONT corner
-- (revealing the corner stalls), a centred DOUBLE-DOOR opening in the front, and a plank header
-- bridging both the door and (via windowedRun) every window.
local function buildShopWalls(parent: Instance)
	local L, R = PAV_CX - PAV_HALF_W, PAV_CX + PAV_HALF_W -- ±44 (left/right edges)
	local F, B = PAV_CZ + PAV_HALF_L, PAV_CZ - PAV_HALF_L -- front / back edges
	local y0, y1 = FLOOR_TOP, EAVE_Y
	local sill, lint = CORNER_WIN_SILL, CORNER_WIN_TOP
	local W = CORNER_WIN_LEG
	plankRun(parent, L, B, R, B, y0, y1) -- back (solid)
	-- LEFT / RIGHT walls: a window leg near the FRONT corner, solid the rest of the way back
	windowedRun(parent, L, F, L, F - W, y0, y1, sill, lint) -- left, front-corner window leg
	plankRun(parent, L, F - W, L, B, y0, y1)                -- left, solid rest
	windowedRun(parent, R, F, R, F - W, y0, y1, sill, lint) -- right, front-corner window leg
	plankRun(parent, R, F - W, R, B, y0, y1)                -- right, solid rest
	-- FRONT wall: a window leg at each corner, solid up to the centred double-door, + a door header
	windowedRun(parent, L, F, L + W, F, y0, y1, sill, lint)                      -- front, left-corner window leg
	plankRun(parent, L + W, F, PAV_CX - DOOR_HALF, F, y0, y1)                    -- front, left of door (solid)
	plankRun(parent, PAV_CX + DOOR_HALF, F, R - W, F, y0, y1)                    -- front, right of door (solid)
	windowedRun(parent, R - W, F, R, F, y0, y1, sill, lint)                      -- front, right-corner window leg
	plankRun(parent, PAV_CX - DOOR_HALF, F, PAV_CX + DOOR_HALF, F, DOOR_TOP, y1) -- header over the door
end

local function buildPavilion(parent: Instance): Model
	local pav = Instance.new("Model")
	pav.Name = "ShopBuilding"
	pav.Parent = parent

	-- FLOOR (raised plank platform)
	makePart({ Name = "Floor", Size = Vector3.new(PAV_HALF_W * 2, 1, PAV_HALF_L * 2), Color = WOOD_MED, CFrame = CFrame.new(PAV_CX, FLOOR_TOP - 0.5, PAV_CZ), Parent = pav })

	-- 4 CORNER PILLARS — the two FRONT corners (sz = +1) are SPLIT into a bottom + a top stub by the
	-- L-windows that wrap them; the back corners stay single full-height pillars.
	local px = PAV_HALF_W - PILLAR_INSET
	local pz = PAV_HALF_L - PILLAR_INSET
	local pillarTops = {}
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local cx, cz = PAV_CX + sx * px, PAV_CZ + sz * pz
			if sz == 1 then
				-- the window band passes THROUGH the pillar -> two parts (bottom stub + top stub)
				local botH = CORNER_WIN_SILL - FLOOR_TOP
				local topH = EAVE_Y - CORNER_WIN_TOP
				makePart({ Name = "Pillar", Size = Vector3.new(4, botH, 4), Color = WOOD_DARK, CFrame = CFrame.new(cx, FLOOR_TOP + botH / 2, cz), Parent = pav })
				makePart({ Name = "Pillar", Size = Vector3.new(4, topH, 4), Color = WOOD_DARK, CFrame = CFrame.new(cx, EAVE_Y - topH / 2, cz), Parent = pav })
			else
				makePart({ Name = "Pillar", Size = Vector3.new(4, EAVE_Y - FLOOR_TOP, 4), Color = WOOD_DARK, CFrame = CFrame.new(cx, (FLOOR_TOP + EAVE_Y) / 2, cz), Parent = pav })
			end
			table.insert(pillarTops, Vector3.new(cx, EAVE_Y, cz))
		end
	end

	-- EAVE BEAMS connecting the pillar tops (a top plate frame just below the roof)
	local beamY = EAVE_Y - 1
	makePart({ Name = "Plate", Size = Vector3.new(px * 2 + 4, 2, 3), Color = WOOD_DARK, CFrame = CFrame.new(PAV_CX, beamY, PAV_CZ - pz), Parent = pav })
	makePart({ Name = "Plate", Size = Vector3.new(px * 2 + 4, 2, 3), Color = WOOD_DARK, CFrame = CFrame.new(PAV_CX, beamY, PAV_CZ + pz), Parent = pav })
	makePart({ Name = "Plate", Size = Vector3.new(3, 2, pz * 2 + 4), Color = WOOD_DARK, CFrame = CFrame.new(PAV_CX - px, beamY, PAV_CZ), Parent = pav })
	makePart({ Name = "Plate", Size = Vector3.new(3, 2, pz * 2 + 4), Color = WOOD_DARK, CFrame = CFrame.new(PAV_CX + px, beamY, PAV_CZ), Parent = pav })

	-- KNEE BRACES (small diagonals at each pillar top, inward) for the aesthetic timber look
	for _, top in ipairs(pillarTops) do
		local inward = Vector3.new(PAV_CX - top.X, 0, PAV_CZ - top.Z).Unit
		local a = top + Vector3.new(0, -4.5, 0)
		local b = top + inward * 5 + Vector3.new(0, 0.5, 0)
		beam(a, b, 1.6, WOOD_DARK, pav, "Brace")
	end

	-- SHINGLE-ROW HIP ROOF: a 4-sided hip (front/back/left/right slopes) rising to ONE central apex,
	-- each slope built from even horizontal shingle COURSES (alternating brown bands), framed by hip
	-- rafters down the 4 corners + a small apex cap. Lower/broader profile than the star roof.
	local Ax = PAV_HALF_W + ROOF_OVERHANG
	local Bz = PAV_HALF_L + ROOF_OVERHANG
	local apex = Vector3.new(PAV_CX, EAVE_Y + ROOF_RISE, PAV_CZ)
	local cFL = Vector3.new(PAV_CX - Ax, EAVE_Y, PAV_CZ + Bz)
	local cFR = Vector3.new(PAV_CX + Ax, EAVE_Y, PAV_CZ + Bz)
	local cBL = Vector3.new(PAV_CX - Ax, EAVE_Y, PAV_CZ - Bz)
	local cBR = Vector3.new(PAV_CX + Ax, EAVE_Y, PAV_CZ - Bz)
	buildSlopeShingles(cFL, cFR, apex, pav) -- +Z (front)
	buildSlopeShingles(cBL, cBR, apex, pav) -- -Z (back)
	buildSlopeShingles(cFL, cBL, apex, pav) -- -X (left)
	buildSlopeShingles(cFR, cBR, apex, pav) -- +X (right)
	for _, c in ipairs({ cFL, cFR, cBL, cBR }) do -- hip rafters down the 4 corners
		beam(c, apex, 1.6, WOOD_DARK, pav, "Rafter")
	end
	makePart({ Name = "ApexCap", Size = Vector3.new(3.5, 3.5, 3.5), Color = WOOD_DARK, CFrame = CFrame.new(apex), Parent = pav })

	-- HANGING "SHOP" SIGN: a board hung OUTSIDE the front planks, tucked under the roof OVERHANG, by
	-- two chains up to the eave. Text on the wood (faces +Z / the lane); players walk under it. It sits
	-- in FRONT of the wall (PAV_HALF_L + 2) so the planks/door-header no longer block it.
	local signZ = PAV_CZ + PAV_HALF_L + 2 -- just in front of the front-wall planks (outer face ~PAV_HALF_L+0.75)
	local beamBottomY = EAVE_Y -- chains run up to the eave / roof overhang
	local signCY = EAVE_Y - 7 -- board centre (raised — short chains hang it just under the eave)
	local signTopY = signCY + 3.5 -- top edge of the 7-tall board
	woodSign("SHOP", Vector3.new(30, 7, 1.2), Vector3.new(PAV_CX, signCY, signZ), 1, pav)
	for _, sx in ipairs({ -1, 1 }) do -- two chains from the board's top corners up to the eave overhang
		makePart({
			Name = "SignChain",
			Size = Vector3.new(0.5, beamBottomY - signTopY, 0.5),
			Color = Color3.fromRGB(70, 74, 84),
			Material = Enum.Material.Metal,
			NoStuds = true,
			CanCollide = false,
			CFrame = CFrame.new(PAV_CX + sx * 12, (beamBottomY + signTopY) / 2, signZ),
			Parent = pav,
		})
	end

	-- BACK features
	buildDailyReward(pav)
	buildRobuxShop(pav)

	-- enclose the whole shop in plank walls (centred double-door + an L-window wrapping each front corner),
	-- then frame each corner window the SAME inside AND outside (both corners)
	buildShopWalls(pav)
	for _, sign in ipairs({ -1, 1 }) do
		buildCornerWindowFrame(pav, sign, 0.8) -- exterior trim
		buildCornerWindowFrame(pav, sign, -0.8) -- interior trim (same framework on the inside)
	end

	-- FRONT-CORNER stalls (reuse each main corner pillar + 3 full pillars + a waist-high plank fence)
	buildCornerStall(pav, -1)
	buildCornerStall(pav, 1)

	return pav
end

----------------------------------------------------------------- init
function StandManager.init()
	local existing = Workspace:FindFirstChild(STANDS_FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = STANDS_FOLDER_NAME
	folder.Parent = Workspace

	buildPavilion(folder)

	-- the two vendors (character + E-prompt only), front-centre, facing the courtyard (+Z).
	-- Shovel LEFT (-X), Incubator RIGHT (+X).
	-- vendors stand in the CENTRE of the two FRONT quadrants: Shovel = front-left (Q3),
	-- Incubator = front-right (Q4). (Daily/Robux fill the two back quadrants Q2/Q1.)
	-- vendors stand INSIDE their front-corner stalls (in the corner by the main pillar)
	buildVendor("Shovel", "🪓 SHOVEL", Vector3.new(PAV_CX - STALL_CX, FLOOR_TOP, STALL_CZ), folder)
	buildVendor("Incubator", "🔥 INCUBATOR", Vector3.new(PAV_CX + STALL_CX, FLOOR_TOP, STALL_CZ), folder)
end

return StandManager
