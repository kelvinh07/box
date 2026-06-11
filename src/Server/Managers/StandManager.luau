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

	-- name tag above the head
	floatingLabel(title, Vector3.new(pos.X, FLOOR_TOP + sz.Y + 1.6, pos.Z), folder, 200)

	-- invisible interact volume + instant prompt (client opens the panel off StandType)
	local interact = makePart({ Name = "Interact", Size = Vector3.new(6, 7, 5), Transparency = 1, CanCollide = false, NoStuds = true, CFrame = CFrame.new(pos.X, FLOOR_TOP + 3.5, pos.Z), Parent = folder })
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenPrompt"
	prompt.ActionText = "Open"
	prompt.ObjectText = title
	prompt.HoldDuration = 0
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 11
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("StandType", standType)
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
local function buildPavilion(parent: Instance): Model
	local pav = Instance.new("Model")
	pav.Name = "ShopBuilding"
	pav.Parent = parent

	-- FLOOR (raised plank platform)
	makePart({ Name = "Floor", Size = Vector3.new(PAV_HALF_W * 2, 1, PAV_HALF_L * 2), Color = WOOD_MED, CFrame = CFrame.new(PAV_CX, FLOOR_TOP - 0.5, PAV_CZ), Parent = pav })

	-- 4 CORNER PILLARS
	local px = PAV_HALF_W - PILLAR_INSET
	local pz = PAV_HALF_L - PILLAR_INSET
	local pillarTops = {}
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			local cx, cz = PAV_CX + sx * px, PAV_CZ + sz * pz
			makePart({ Name = "Pillar", Size = Vector3.new(4, EAVE_Y - FLOOR_TOP, 4), Color = WOOD_DARK, CFrame = CFrame.new(cx, (FLOOR_TOP + EAVE_Y) / 2, cz), Parent = pav })
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

	-- HANGING "SHOP" SIGN: a board suspended BELOW the front eave beam by two chains (was mounted
	-- above the frame). Text on the wood (faces +Z / the lane); players walk under it.
	local signZ = PAV_CZ + pz -- front eave-beam line
	local beamBottomY = EAVE_Y - 2 -- bottom of the front eave plate (centre EAVE_Y-1, 2 tall)
	local signCY = EAVE_Y - 11 -- board centre (hangs ~11 below the eave)
	local signTopY = signCY + 3.5 -- top edge of the 7-tall board
	woodSign("SHOP", Vector3.new(30, 7, 1.2), Vector3.new(PAV_CX, signCY, signZ), 1, pav)
	for _, sx in ipairs({ -1, 1 }) do -- two chains from the board's top corners up to the beam
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
	buildVendor("Shovel", "🪓 SHOVEL", Vector3.new(PAV_CX - PAV_HALF_W / 2, FLOOR_TOP, PAV_CZ + PAV_HALF_L / 2), folder)
	buildVendor("Incubator", "🔥 INCUBATOR", Vector3.new(PAV_CX + PAV_HALF_W / 2, FLOOR_TOP, PAV_CZ + PAV_HALF_L / 2), folder)
end

return StandManager
