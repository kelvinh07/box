--!strict
-- StandManager
-- Three SHARED upgrade SHOPS placed next to the lobby-center spawn pad. Each carries an
-- INSTANT ProximityPrompt (press E, no hold) with a `StandType` attribute the CLIENT reads
-- to open the matching upgrade panel — there is NO server-side open handler (opening is UI).
--
--   🪓 Shovel    (Cash)  — speeds up digging       -> StandType "Shovel"
--   🔥 Incubator (Gems)  — shortens hatch timers    -> StandType "Incubator"
--   🍀 Luck      (Gems)  — better dig rarity odds    -> StandType "Luck"
--
-- Each shop is a CLONE of the imported model at ServerStorage.ShopModel (security-audited,
-- scripts stripped), scaled + stood on the ground, with its built-in floating title
-- retitled to the stand name and its white/blue recolored per stand (shop 1 keeps
-- white+blue, shop 2 = red+purple, shop 3 = purple+black). If ServerStorage.ShopModel is
-- absent (e.g. a place built from src that doesn't ship it), it falls back to a procedural
-- booth + bacon-hair vendor. Idempotent: init() rebuilds the Stands folder each call.
--
-- NOTE: ServerStorage.ShopModel is NOT in src/ (it's an imported mesh). To ship it in a
-- `rojo build`, save it to a .rbxmx under src/ and map it in default.project.json.

local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Palette = require(ReplicatedStorage.Shared.Config.Palette)
local Surface = require(ReplicatedStorage.Shared.Modules.Surface)

local StandManager = {}

local STANDS_FOLDER_NAME = "Stands"

-- The shop MODEL template lives in ServerStorage.ShopModel — the user's imported model,
-- SECURITY-AUDITED clean (no malicious code) and with its scripts stripped. buildStand
-- clones it per stand. If it's missing (e.g. a place built from src that doesn't ship the
-- model), buildStand falls back to the procedural booth so the game still works.
local SHOP_MODEL_NAME = "ShopModel"
local SHOP_TARGET_H = 12 -- the model is scaled so it stands ~this tall
-- the procedural-fallback floating title only shows within this many studs
local TITLE_MAX_DIST = 32

-- the imported shop's two recolorable base colours (sampled from the model: a near-white
-- and the classic bright-blue). recolorShop remaps these; wood / NPC / grey are left alone.
local SHOP_WHITE = Color3.fromRGB(191, 179, 184)
local SHOP_BLUE = Color3.fromRGB(13, 105, 172)

local function colorClose(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) < 0.06 and math.abs(a.G - b.G) < 0.06 and math.abs(a.B - b.B) < 0.06
end

-- remap the shop's WHITE parts -> `primary` and BLUE parts -> `secondary`.
local function recolorShop(model: Model, primary: Color3, secondary: Color3)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if colorClose(d.Color, SHOP_WHITE) then
				d.Color = primary
			elseif colorClose(d.Color, SHOP_BLUE) then
				d.Color = secondary
			end
		end
	end
end

-- set the shop model's built-in floating title (the ShopGui BillboardGui's TextLabel).
local function setShopTitle(model: Model, text: string)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("TextLabel") and d:FindFirstAncestorWhichIsA("BillboardGui") then
			d.Text = text
		end
	end
end

-- a fresh CLONE of the imported shop template (anchored), or nil if it isn't present.
local function getShopTemplate(): Model?
	local tmpl = ServerStorage:FindFirstChild(SHOP_MODEL_NAME)
	if tmpl and tmpl:IsA("Model") then
		local clone = tmpl:Clone()
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		return clone
	end
	return nil
end

-- The lobby-center spawn pad sits at world (0, 1.6, -70) (a 14x14 neon square). The
-- ground part top is Y=1 (ground center 0, size 2). Stands sit ON the ground (Y=1),
-- arced around the spawn pad but clear of it. NOTE: there is NO base at x=0 — the ring
-- has MAX_SLOTS=10 (even), so the two center-most bases straddle x=0 at roughly
-- (+/-40.4, -195.9), with their OPEN FRONTS reaching INWARD to about z=-150. The
-- stand cluster here only reaches to z=-96 (the HatchSpeed NPC), clearing those base
-- fronts by ~55 studs. KEEP the stands' -Z extent above ~z=-150 or you will push them
-- into the slot-1/2 buildings. +Z is "toward the courtyard / dig lane"; NPCs face that way.
local SC = Vector3.new(0, 0, -70)
local GROUND_TOP = 1
-- Safe back limit: the nearest base fronts sit near z=-150 (see note above), so the
-- stand cluster must stay clear of (i.e. greater than) this Z.
local NEAREST_BASE_FRONT_Z = -150

-- Build an anchored part with the classic studded legoish look (Surface.applyStuds
-- overlays the real Roblox studs texture on every face). Glow/glass/wood/see-through
-- parts auto-skip; pass `NoStuds = true` to force-skip (e.g. the NPC avatar limbs).
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

----------------------------------------------------------------- bacon-hair NPC
-- A procedural classic R6 avatar: yellow skin (head/arms/legs), a shirt-colored
-- torso, two tiny black eyes on the head front, and the iconic reddish-brown
-- "Bacon Hair" — a few angled wedge tufts stacked on the head pointing BACK.
-- Built in LOCAL space facing local +Z (eyes on +Z), torso centered at the origin,
-- then PivotTo(cf) is applied by the caller. PrimaryPart = torso.
local SKIN = Color3.fromRGB(245, 205, 48)
local BACON = Color3.fromRGB(122, 73, 42)

local function buildBaconNPC(cf: CFrame, parent: Instance, namePrefix: string): Model
	local model = Instance.new("Model")
	model.Name = ("%sVendor"):format(namePrefix)

	-- Torso (PrimaryPart) centered at local origin. R6 torso = 2 x 2 x 1.
	local torso = makePart({
		Name = "Torso",
		Size = Vector3.new(2, 2, 1),
		Color = Palette.BaseFloor, -- vibrant blue-gray "shirt" color
		CanCollide = false,
		NoStuds = true, -- avatars stay smooth
		CFrame = CFrame.new(0, 0, 0),
		Parent = model,
	})
	model.PrimaryPart = torso

	-- Head (~2 x 1 x 1) sits on top of the torso.
	local head = makePart({
		Name = "Head",
		Size = Vector3.new(2, 1, 1),
		Color = SKIN,
		CanCollide = false,
		NoStuds = true,
		CFrame = CFrame.new(0, 1.5, 0),
		Parent = model,
	})

	-- two tiny black eyes on the head FRONT (local +Z face).
	for _, sx in ipairs({ -1, 1 }) do
		makePart({
			Name = "Eye",
			Size = Vector3.new(0.18, 0.22, 0.12),
			Color = Color3.fromRGB(15, 15, 15),
			CanCollide = false,
			NoStuds = true,
			CFrame = head.CFrame * CFrame.new(sx * 0.32, 0.1, 0.52),
			Parent = model,
		})
	end

	-- Arms (1 x 2 x 1) flank the torso; Legs (1 x 2 x 1) below it.
	for _, sx in ipairs({ -1, 1 }) do
		makePart({
			Name = "Arm",
			Size = Vector3.new(1, 2, 1),
			Color = SKIN,
			CanCollide = false,
			NoStuds = true,
			CFrame = CFrame.new(sx * 1.5, 0, 0),
			Parent = model,
		})
		makePart({
			Name = "Leg",
			Size = Vector3.new(1, 2, 1),
			Color = SKIN,
			CanCollide = false,
			NoStuds = true,
			CFrame = CFrame.new(sx * 0.5, -2, 0),
			Parent = model,
		})
	end

	-- BACON HAIR: reddish-brown wedge tufts on top of the head, sweeping toward the
	-- BACK (local -Z). A few stacked/angled wedges approximate the classic "Pal Hair".
	local hairTufts = {
		{ size = Vector3.new(1.2, 0.9, 1.0), lz = -0.15, ly = 0.7, tilt = -0.25 },
		{ size = Vector3.new(1.0, 0.8, 1.0), lz = -0.85, ly = 0.55, tilt = -0.55 },
		{ size = Vector3.new(0.85, 0.7, 0.9), lz = -1.45, ly = 0.3, tilt = -0.85 },
		{ size = Vector3.new(0.7, 0.6, 0.8), lz = -1.9, ly = 0.0, tilt = -1.05 },
	}
	for i, t in ipairs(hairTufts) do
		local wedge = Instance.new("WedgePart")
		wedge.Name = ("Hair%d"):format(i)
		wedge.Anchored = true
		wedge.CanCollide = false
		wedge.Material = Enum.Material.Plastic
		wedge.Color = BACON
		wedge.Size = t.size
		-- WedgePart slopes down toward +Z; rotate 180° about Y so the slope sweeps to
		-- the BACK (-Z), then tilt back a touch for the layered bacon look.
		wedge.CFrame = head.CFrame
			* CFrame.new(0, t.ly, t.lz)
			* CFrame.Angles(t.tilt, math.pi, 0)
		wedge.Parent = model
	end

	model.Parent = parent
	model:PivotTo(cf)
	return model
end

----------------------------------------------------------------- a stand booth
-- A chunky booth: a counter/base block, a back signboard, and a colored awning on
-- top, plus a floating title and an INSTANT ProximityPrompt on the front counter.
-- `face` is the world point the booth/NPC look toward (the courtyard, +Z).
local function buildStand(
	standType: string,
	title: string,
	accent: Color3,
	primary: Color3?,
	secondary: Color3?,
	groundPos: Vector3,
	parent: Instance
)
	local folder = Instance.new("Folder")
	folder.Name = ("%sStand"):format(standType)
	folder.Parent = parent

	-- orient so the FRONT (local +Z, the counter/prompt side) faces the courtyard.
	local facePoint = Vector3.new(groundPos.X, groundPos.Y, groundPos.Z + 20)
	local base = CFrame.lookAt(groundPos, facePoint)

	-- the part the ProximityPrompt lives on (the shop's front, or the booth counter)
	local promptParent: BasePart
	-- whether the shop model supplied its OWN floating title (so we don't add a second one)
	local modelTitled = false

	local shop = getShopTemplate()
	if shop then
		-- IMPORTED shop model: scale to ~SHOP_TARGET_H, stand on the ground at groundPos, face +Z.
		shop.Name = "Shop"
		local _, s0 = shop:GetBoundingBox()
		if s0.Y > 0.01 then
			pcall(function() shop:ScaleTo(SHOP_TARGET_H / s0.Y) end)
		end
		shop:PivotTo(base) -- pivot to groundPos, facing +Z
		local cf, sz = shop:GetBoundingBox()
		shop:PivotTo(shop:GetPivot() + Vector3.new(0, GROUND_TOP - (cf.Y - sz.Y / 2), 0)) -- drop onto the ground
		-- per-stand recolor (nil colours => keep the original white/blue, e.g. the first shop)
		if primary and secondary then
			recolorShop(shop, primary, secondary)
		end
		-- retitle the model's OWN floating title to the stand name it replaces
		setShopTitle(shop, standType:upper())
		modelTitled = true
		shop.Parent = folder
		-- invisible interaction block at the front so the E prompt always works
		promptParent = makePart({
			Name = "Interact",
			Size = Vector3.new(7, 5, 2),
			Transparency = 1,
			CanCollide = false,
			NoStuds = true,
			CFrame = base * CFrame.new(0, GROUND_TOP + 2.5, 3),
			Parent = folder,
		})
	else
		-- PROCEDURAL fallback booth (counter / sign / posts / awning) + bacon vendor.
		promptParent = makePart({
			Name = "Counter",
			Size = Vector3.new(8, 4, 2.5),
			Color = accent,
			Material = Enum.Material.WoodPlanks,
			CFrame = base * CFrame.new(0, GROUND_TOP + 2, 0),
			Parent = folder,
		})
		makePart({ Name = "Sign", Size = Vector3.new(8.5, 5, 0.6), Color = Palette.BaseFloor, Material = Enum.Material.WoodPlanks, CFrame = base * CFrame.new(0, GROUND_TOP + 7, -3.2), Parent = folder })
		for _, sx in ipairs({ -1, 1 }) do
			makePart({ Name = "Post", Size = Vector3.new(0.6, 9, 0.6), Color = Palette.BaseTrim, Material = Enum.Material.Wood, CFrame = base * CFrame.new(sx * 4, GROUND_TOP + 4.5, 0.8), Parent = folder })
		end
		makePart({ Name = "Awning", Size = Vector3.new(9.5, 0.5, 5), Color = accent, Material = Enum.Material.Fabric, CFrame = base * CFrame.new(0, GROUND_TOP + 9, 0.6) * CFrame.Angles(math.rad(-18), 0, 0), Parent = folder })
		local npcPos = Vector3.new(groundPos.X, GROUND_TOP + 3, groundPos.Z - 4)
		buildBaconNPC(CFrame.lookAt(npcPos, Vector3.new(npcPos.X, npcPos.Y, npcPos.Z + 20)), folder, standType)
	end

	-- floating title (PROCEDURAL fallback ONLY — the imported shop model carries its own
	-- ShopGui title, already retitled above). Visible within TITLE_MAX_DIST studs.
	if not modelTitled then
		local titlePart = makePart({
			Name = "Title",
			Size = Vector3.new(1, 1, 1),
			Transparency = 1,
			CanCollide = false,
			NoStuds = true,
			CFrame = base * CFrame.new(0, GROUND_TOP + 12, 0),
			Parent = folder,
		})
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.new(0, 190, 0, 44)
		bb.AlwaysOnTop = true
		bb.MaxDistance = TITLE_MAX_DIST
		bb.Parent = titlePart
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.FredokaOne
		lbl.TextScaled = true
		lbl.Text = title
		lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
		lbl.TextStrokeTransparency = 0
		lbl.Parent = bb
	end

	-- INSTANT ProximityPrompt; the client reads StandType to open the matching panel.
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "OpenPrompt"
	prompt.ActionText = "Open"
	prompt.ObjectText = title
	prompt.HoldDuration = 0
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("StandType", standType)
	prompt.Parent = promptParent
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

	-- a small arc around the spawn pad (14x14 at SC), clear of the pad. The Incubator
	-- stand reaches furthest toward -Z (its NPC at ~z=-96); the nearest base fronts sit
	-- near z=-150 (see header note), so the cluster clears them by ~55 studs. Each faces
	-- +Z (toward the courtyard/dig lane).
	-- per-shop recolor of the imported model's white/blue: shop #1 keeps the original
	-- white+blue (nil/nil); shop #2 -> red + purple; shop #3 -> purple + black.
	-- entry = { standType, fallbackTitle, accent, primaryColor?, secondaryColor?, groundPos }
	local RED = Color3.fromRGB(230, 45, 45)
	local PURPLE = Palette.Purple
	local BLACK = Color3.fromRGB(35, 35, 40)
	local stands = {
		{ "Shovel", "🪓 SHOVEL SHOP", Palette.Pink, nil, nil, Vector3.new(SC.X - 34, 0, SC.Z) },
		{ "Incubator", "🔥 INCUBATOR", Palette.Cyan, RED, PURPLE, Vector3.new(SC.X, 0, SC.Z - 22) },
		{ "Luck", "🍀 LUCK", Palette.Lime, PURPLE, BLACK, Vector3.new(SC.X + 34, 0, SC.Z) },
	}
	-- guard: if a future edit pushes any stand's footprint past the nearest base fronts,
	-- warn instead of silently colliding with the slot-1/2 buildings.
	local STAND_BACK_REACH = 4
	for _, s in ipairs(stands) do
		local groundPos = s[6] :: Vector3
		if groundPos.Z - STAND_BACK_REACH <= NEAREST_BASE_FRONT_Z then
			warn(("[StandManager] %s stand reaches z=%.1f, past the nearest base fronts (~z=%d); it may overlap slots 1/2.")
				:format(tostring(s[1]), groundPos.Z - STAND_BACK_REACH, NEAREST_BASE_FRONT_Z))
		end
		buildStand(s[1] :: string, s[2] :: string, s[3] :: Color3, s[4] :: Color3?, s[5] :: Color3?, groundPos, folder)
	end
end

return StandManager
