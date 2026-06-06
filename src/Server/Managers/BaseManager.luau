--!strict
-- BaseManager
-- Each SLOT gets a BASE BUILDING (floor, side walls with windows, roof, open
-- front facing the central courtyard) arranged in a rounded lobby ring around the
-- central dig square. Inside, brainrots spin on podiums; in front of each is a
-- GREEN PRESSURE PLATE — walk across it to collect that brainrot's accumulated
-- cash. The dig lane runs INWARD toward the courtyard, with REBIRTH WALL gates
-- between zones (click when you qualify).
--
-- All 10 base structures are pre-built once at init and stay visible whether a
-- slot is occupied or not. Joining a player only marks them the slot occupant,
-- renames the sign, rebuilds podiums to their plot count if needed, and loads
-- their brainrots onto the podiums.
--
-- Bases sit on a circular arc, pushed back, FACING INWARD toward the courtyard the
-- half-circle opens onto, so the dig lane fans inward toward/through the center.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local InsertService = game:GetService("InsertService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local ZoneConfig = require(Shared.Config.ZoneConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Palette = require(Shared.Config.Palette)
local Surface = require(Shared.Modules.Surface)
local Format = require(Shared.Modules.Format)
local Net = require(Shared.Modules.Net)

local PlayerData = require(script.Parent.PlayerData)
local BrainrotFactory = require(script.Parent.BrainrotFactory)
local MapBuilder = require(script.Parent.MapBuilder)
local EconomyManager = require(script.Parent.EconomyManager)
-- IncubationManager uses BaseManager via INJECTION (no top-level require of BaseManager),
-- so requiring it here for the ghost-incubator Buy click does NOT create a cycle.
local IncubationManager = require(script.Parent.IncubationManager)

local BaseManager = {}

----------------------------------------------------------------- layout config
local BASES_FOLDER_NAME = "PlayerBases"
local DIGLANE_FOLDER_NAME = "DigLane"
local MAX_SLOTS = 10
-- CollectionService tag the client listens for to wire up the level-up panel, and
-- the click range for the per-brainrot ClickDetector that opens it.
local BRAINROT_TAG = "Brainrot"
local BRAINROT_CLICK_DISTANCE = 24
local LOBBY_RADIUS = 200       -- distance from dig center to each base (pushed back, courtyard room for the shared lane)
local ARC_SPAN_DEG = 210       -- how far the ring wraps (>180 = nice and round)
-- Bigger, two-floor building. Wider sides (+16) and a much deeper back (+50)
-- vs the old 48x42 footprint. The building faces the dig center (open front =
-- local -Z); the back (+Z) is pushed out the most.
local FLOOR = Vector3.new(64, 2, 92)
local WALL_H = 22                       -- PER-FLOOR wall height
local WALL_T = 2
local FLOOR2_Y = 1 + WALL_H + WALL_T    -- local Y of the floor-2 slab TOP surface
local PLATE = Vector3.new(7, 0.4, 5)
local STAIR_GAP = 16                    -- width of the centered back staircase doorway
-- Staircase geometry (shared by the floor-2 slab opening, the steps, the stairwell
-- side walls and the lock barrier so they always line up). The stairs rise from the
-- FRONT (low step, room side) up to the BACK wall (high step at floor-2 level), and
-- the player emerges sideways onto the side slabs at the top.
local STAIR_STEPS = 12
local STAIR_STEP_H = (FLOOR2_Y - 1) / STAIR_STEPS   -- ~2 high per step
local STAIR_STEP_D = 2                              -- ~2 deep per step
local STAIR_FRONT_LZ = FLOOR.Z / 2 - STAIR_STEPS * STAIR_STEP_D - 1 -- lowest step lz (~21)
local STAIR_ENTRANCE_LZ = STAIR_FRONT_LZ - STAIR_STEP_D             -- well entrance / barrier (~19)
-- The dig progression is ONE unified STRAIGHT LANE that extends INWARD from the
-- base toward the courtyard center, all equal-size squares evenly spaced with
-- walls between them:
--   base(open front) -> [Zone 1 entry dig] -> wall -> [Zone 2 dig] -> wall -> [Zone 3 dig]
-- Every dig site is the SAME SIZE (68x68); walls sit exactly midway between them.
local REBIRTH_WALL = Vector3.new(100, 44, 6)  -- wall WIDTH 100 >= dig-site width 96, fully separating sites (was 76,36,4)
local SEG_SIZE = Vector3.new(96, 1, 96)       -- every dig square is this size (bigger; was 68)
local LANE_WALL_Y = 1 + REBIRTH_WALL.Y / 2   -- wall center height (sits on the ground)
local LANE_SEG_Y = 1.3                       -- dig-area slab center height
-- The shared dig lane starts near the half-circle CENTER (zone-1 dig site) and the
-- sites march OUTWARD (+Z) from there, a wall midway between each consecutive pair.
local LANE_START = 0                          -- z of the zone-1 dig site (~lobby center)
local LANE_STEP = SEG_SIZE.Z + 28             -- center-to-center between dig sites

----------------------------------------------------------------- state
local basesFolder: Folder
local laneFolder: Folder
-- which player currently occupies each slot (nil = empty); structures persist
local slotOccupant: { [number]: Player? } = {}
local playerSlot: { [Player]: number } = {}
-- per-SLOT state, built ONCE per slot and reused across occupants
local slotFolder: { [number]: Folder } = {}
local slotPodiums: { [number]: { BasePart } } = {}
local slotModels: { [number]: { [string]: Model } } = {}           -- occupant brainrot models
local slotPlates: { [number]: { [number]: any } } = {}             -- [podiumIndex] = {plate,label,debounce}
local slotSign: { [number]: TextLabel } = {}                       -- the name TextLabel (toggles text)
-- the 4 incubator records per slot (built once); each: { base, dome, light, label, click, pos, index }
local slotIncubators: { [number]: { any } } = {}
-- the back-wall LADDER to floor 2 per slot: { truss, click, label, billboard }
local slotLadder: { [number]: any } = {}
-- the per-slot FLOOR-2 structure folder (reparented out of Workspace while hidden)
local slotFloor2: { [number]: Folder } = {}
-- a ServerStorage holder that hidden floor-2 structures + locked incubators live in
-- (out of Workspace => invisible to everyone & non-collidable). Set in init().
local hiddenHolder: Folder
-- a GHOST "next plot" podium with a clickable Buy button, shown at the next free
-- podium slot for an OCCUPIED base under MaxPlots (nil otherwise). { podium,label,cost }
local slotGhostPlot: { [number]: any } = {}

-- forward declaration (defined below, called from buildBaseStructure / assign / free)
local refreshBaseProgression: (slot: number) -> ()

local rebirthHandler: ((Player) -> any)? = nil
function BaseManager.setRebirthHandler(fn: (Player) -> any)
	rebirthHandler = fn
end

-- center-first arc ordering so the first player(s) to join sit near the middle
local SLOT_ARCINDEX: { [number]: number } = {}
do
	local mid = (MAX_SLOTS - 1) / 2
	local idxs = {}
	for i = 0, MAX_SLOTS - 1 do
		idxs[#idxs + 1] = i
	end
	table.sort(idxs, function(a, b)
		return math.abs(a - mid) < math.abs(b - mid)
	end)
	for slot = 1, MAX_SLOTS do
		SLOT_ARCINDEX[slot] = idxs[slot]
	end
end

----------------------------------------------------------------- helpers
local function nextFreeSlot(): number
	local i = 1
	while slotOccupant[i] ~= nil do
		i += 1
	end
	return i
end

-- Build an anchored part with the classic studded legoish look (Surface.applyStuds
-- overlays the real Roblox studs texture on every face). Glow/glass/wood/see-through
-- parts auto-skip; pass `NoStuds = true` to force-skip (e.g. NPC limbs).
local function makePart(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
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

-- inward-facing circular arc position; LookVector points TOWARD the dig center,
-- so local +Z (the open front + the dig lane) fans inward toward the courtyard
-- the half-circle opens onto, while local -Z is the solid back of the building.
local function baseOrigin(slot: number): CFrame
	local arcIndex = SLOT_ARCINDEX[slot] or 0
	local frac = (MAX_SLOTS == 1) and 0.5 or arcIndex / (MAX_SLOTS - 1)
	local ang = math.rad(-ARC_SPAN_DEG / 2 + frac * ARC_SPAN_DEG)
	local c = MapBuilder.DigCenter
	local baseY = 1.5 -- low so the floor is an easy step up from the ground
	local radial = Vector3.new(math.sin(ang), 0, -math.cos(ang))
	local pos = Vector3.new(c.X, baseY, c.Z) + radial * LOBBY_RADIUS
	return CFrame.lookAt(pos, Vector3.new(c.X, baseY, c.Z)) -- face the dig center (inward)
end

-- Cost to buy the NEXT plot given the slot's current plot count. Delegates to the
-- single GameConfig.plotCost helper (also used by EconomyManager.buyPlot / snapshot)
-- so the ghost's displayed cost matches exactly what the player is charged.
local function plotCostFor(plots: number): number
	return GameConfig.plotCost(plots)
end

----------------------------------------------------------------- podiums + plates
local function buildPodium(cf: CFrame, parent: Instance): BasePart
	local podium = makePart({
		Name = "Podium",
		Size = BrainrotFactory.PODIUM_SIZE,
		Color = Palette.Podium,
		Material = Enum.Material.Neon,
		CFrame = cf,
		Parent = parent,
	})
	local rim = makePart({
		Name = "Rim",
		Size = BrainrotFactory.PODIUM_SIZE + Vector3.new(1, -0.6, 1),
		Color = Palette.PodiumRim,
		Material = Enum.Material.Neon,
		CFrame = cf * CFrame.new(0, -0.2, 0),
		Parent = podium,
	})
	rim.CanCollide = false
	return podium
end

-- which owned brainrot (id) currently sits on podium `idx` in this slot
local function brainrotIdAtPodium(slot: number, idx: number): string?
	local models = slotModels[slot]
	if not models then
		return nil
	end
	for _, m in pairs(models) do
		if m:GetAttribute("PodiumIndex") == idx then
			return m:GetAttribute("BrainrotId") :: string?
		end
	end
	return nil
end

-- Build (or update) the "Lv N" billboard on a brainrot model so its current level
-- is always readable on the podium. Idempotent: reuses an existing LevelLabel.
local function setBrainrotLevelLabel(model: Model, level: number)
	local primary = model.PrimaryPart
	if not primary then
		return
	end
	local bb = primary:FindFirstChild("LevelLabel") :: BillboardGui?
	if not bb then
		bb = Instance.new("BillboardGui")
		bb.Name = "LevelLabel"
		bb.Size = UDim2.new(0, 90, 0, 28)
		bb.StudsOffset = Vector3.new(0, 7.5, 0) -- above the factory InfoLabel
		bb.AlwaysOnTop = true
		bb.MaxDistance = 120
		bb.Parent = primary
		local lbl = Instance.new("TextLabel")
		lbl.Name = "Text"
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.FredokaOne
		lbl.TextScaled = true
		lbl.TextColor3 = Color3.fromRGB(255, 235, 130)
		lbl.TextStrokeTransparency = 0
		lbl.Parent = bb
	end
	local text = bb:FindFirstChild("Text") :: TextLabel?
	if text then
		text.Text = ("Lv %d"):format(level)
	end
end

-- a green pressure plate in front of podium `idx`; stepping on it collects cash.
-- `cf` is the plate's world CFrame (its center, already lifted to the floor surface).
local function buildPlate(slot: number, idx: number, cf: CFrame, parent: Instance)
	local plate = makePart({
		Name = ("Plate_%d"):format(idx),
		Size = PLATE,
		Color = Palette.Plate,
		Material = Enum.Material.Neon,
		CFrame = cf,
		Parent = parent,
	})
	plate.CanCollide = false

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 120, 0, 38)
	bb.StudsOffset = Vector3.new(0, 2.6, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 90
	bb.Parent = plate
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.Text = ""
	lbl.TextColor3 = Color3.fromRGB(150, 255, 150)
	lbl.TextStrokeTransparency = 0
	lbl.Parent = bb

	local rec = { plate = plate, label = lbl, debounce = false }
	slotPlates[slot][idx] = rec

	plate.Touched:Connect(function(hit: BasePart)
		if rec.debounce then
			return
		end
		local occupant = slotOccupant[slot]
		if not occupant then
			return
		end
		local plr = Players:GetPlayerFromCharacter(hit.Parent)
		if plr ~= occupant then
			return
		end
		local id = brainrotIdAtPodium(slot, idx)
		if not id or EconomyManager.getAccrued(occupant, id) < 1 then
			return
		end
		rec.debounce = true
		EconomyManager.collect(occupant, id)
		-- quick green flash on the plate
		plate.Color = Color3.fromRGB(180, 255, 180)
		TweenService:Create(plate, TweenInfo.new(0.4), { Color = Palette.Plate }):Play()
		task.delay(0.6, function()
			rec.debounce = false
		end)
	end)
end

-- per-INDEX podium placement math (shared by real podiums AND the ghost next-slot
-- podium so they line up exactly). Brainrots line the side (window) walls: 6 per
-- side per floor. Plots 1-12 are floor 1, plots 13-24 are floor 2; within a floor
-- the first 6 hug the left (-X) window wall and the next 6 hug the right (+X) wall.
-- Returns (side, lx, lz, baseLY) for podium index `i`.
local function podiumLocalAt(i: number): (number, number, number, number)
	local floor = (i <= 12) and 1 or 2
	local j = (i - 1) % 12             -- 0..11 within the floor
	local side = (j < 6) and -1 or 1   -- first 6 = left wall, next 6 = right wall
	local row = j % 6                  -- 0..5 along the depth
	local lx = side * (FLOOR.X / 2 - 6)             -- podium near the side/window wall (~+/-26)
	local lz = -32 + row * 13                       -- 6 podiums spread along the depth
	local baseLY = (floor == 1) and 1 or FLOOR2_Y   -- floor surface
	return side, lx, lz, baseLY
end

-- a GHOST "next plot" podium with a clickable Buy button at the next free index
-- (count+1). Distinct reddish/grey, semi-transparent, non-colliding. Clicking it
-- routes to EconomyManager.buyPlot for the slot occupant (server-validated).
local function buildGhostPlot(slot: number, count: number)
	local folder = slotFolder[slot]
	if not folder then
		return
	end
	local origin = baseOrigin(slot)
	local _, lx, lz, baseLY = podiumLocalAt(count + 1)
	local cost = plotCostFor(count)

	local ghost = buildPodium(origin * CFrame.new(lx, baseLY + BrainrotFactory.PODIUM_SIZE.Y / 2, lz), folder)
	ghost.Name = "GhostPodium"
	ghost.Color = Palette.Wall   -- coral "locked" look, distinct from the vivid-purple real podiums
	ghost.Material = Enum.Material.SmoothPlastic
	ghost.Transparency = 0.5
	ghost.CanCollide = false
	local rim = ghost:FindFirstChild("Rim")
	if rim and rim:IsA("BasePart") then
		rim.Color = Palette.Wall
		rim.Transparency = 0.5
	end

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 150, 0, 52)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 90
	bb.Parent = ghost
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.Text = ("🔒 Buy Plot\n$%s"):format(Format.short(cost))
	lbl.TextColor3 = Color3.fromRGB(255, 230, 150)
	lbl.TextStrokeTransparency = 0
	lbl.Parent = bb

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 32
	click.Parent = ghost

	click.MouseClick:Connect(function(clicker: Player)
		if clicker ~= slotOccupant[slot] then
			return
		end
		local res = EconomyManager.buyPlot(clicker)
		if res and res.ok == false and res.reason then
			Net.getEvent("Notify"):FireClient(clicker, {
				title = "Plot Locked", text = res.reason, color = "Legendary",
			})
		end
	end)

	slotGhostPlot[slot] = { podium = ghost, label = lbl, cost = cost }
end

-- (re)build the podium grid + plates for a given slot's plot count
local function rebuildSlotPodiums(slot: number, count: number)
	local folder = slotFolder[slot]
	if not folder then
		return
	end

	for _, podium in ipairs(slotPodiums[slot] or {}) do
		podium:Destroy()
	end
	slotPodiums[slot] = {}
	for _, model in pairs(slotModels[slot] or {}) do
		model:Destroy()
	end
	slotModels[slot] = {}
	for _, rec in pairs(slotPlates[slot] or {}) do
		if rec.plate then
			rec.plate:Destroy()
		end
	end
	slotPlates[slot] = {}

	count = math.clamp(count, 0, GameConfig.MaxPlots)
	local origin = baseOrigin(slot)
	for i = 1, count do
		local side, lx, lz, baseLY = podiumLocalAt(i)

		local podium = buildPodium(
			origin * CFrame.new(lx, baseLY + BrainrotFactory.PODIUM_SIZE.Y / 2, lz),
			folder
		)
		table.insert(slotPodiums[slot], podium)
		-- pressure plate just INWARD of the podium (toward the central walkway)
		buildPlate(slot, i, origin * CFrame.new(lx - side * 6, baseLY + PLATE.Y / 2, lz), folder)
	end

	-- rebuild the GHOST next-slot Buy podium: destroy any prior one FIRST, then show
	-- it only for an OCCUPIED base that is still under MaxPlots, at index count+1.
	local prev = slotGhostPlot[slot]
	if prev then
		if prev.podium then
			prev.podium:Destroy()
		end
		slotGhostPlot[slot] = nil
	end
	-- show the ghost Buy podium for an OCCUPIED base under MaxPlots, EXCEPT once the
	-- player has filled floor 1 (12 plots) and not yet bought the ladder — there the
	-- next purchase is the LADDER, not a floor-2 plot.
	if slotOccupant[slot] ~= nil and count < GameConfig.MaxPlots then
		local occProfile = PlayerData.get(slotOccupant[slot])
		local ladderUnlocked = occProfile and occProfile.LadderUnlocked or false
		if count < GameConfig.FloorOnePlots or ladderUnlocked then
			buildGhostPlot(slot, count)
		end
	end
end

-- place a single brainrot model onto the next free podium for `slot`
local function placeBrainrotForSlot(slot: number, player: Player, entry: any)
	local profile = PlayerData.get(player)
	local podiums = slotPodiums[slot]
	if not profile or not podiums then
		return
	end
	slotModels[slot] = slotModels[slot] or {}
	if slotModels[slot][entry.id] then
		return
	end

	local occupied: { [number]: boolean } = {}
	for _, model in pairs(slotModels[slot]) do
		local idx = model:GetAttribute("PodiumIndex")
		if idx then
			occupied[idx] = true
		end
	end

	local targetIndex
	for i = 1, #podiums do
		if not occupied[i] then
			targetIndex = i
			break
		end
	end
	if not targetIndex then
		return
	end

	local podium = podiums[targetIndex]
	-- income on the factory label is keyed off the rebirth multipliers, so pass the
	-- player's rebirth count (NOT the zone) to keep the $/s matching the payout.
	local model = BrainrotFactory.build(entry, profile.Rebirths)
	model:SetAttribute("PodiumIndex", targetIndex)
	-- BrainrotId is set by BrainrotFactory.build; set it again defensively so the
	-- client can always read it off the model regardless of the build path.
	model:SetAttribute("BrainrotId", entry.id)
	model.Parent = slotFolder[slot]
	local _, modelSize = model:GetBoundingBox()
	local topY = podium.Position.Y + podium.Size.Y / 2 + modelSize.Y / 2
	model:PivotTo(CFrame.new(podium.Position.X, topY, podium.Position.Z))

	-- show the brainrot's current level ("Lv N") on its billboard
	setBrainrotLevelLabel(model, entry.level or 1)

	-- tag the model + add a ClickDetector so the CLIENT can open the level-up panel.
	-- The server only WIRES the detector (tag + BrainrotId attribute + ClickDetector);
	-- the client connects ClickDetector.MouseClick locally and reads the entry from
	-- its snapshot, then invokes the LevelBrainrot remote.
	-- Create+parent the ClickDetector BEFORE tagging so the detector is already
	-- present when the tag-added signal replicates to the client (avoids a race
	-- where the client wires the tag but finds no detector yet).
	if model.PrimaryPart then
		local click = Instance.new("ClickDetector")
		click.Name = "LevelClick"
		click.MaxActivationDistance = BRAINROT_CLICK_DISTANCE
		click.Parent = model.PrimaryPart
	end
	CollectionService:AddTag(model, BRAINROT_TAG)

	-- gentle idle spin/float
	task.spawn(function()
		local t = 0
		while model.Parent and model.PrimaryPart do
			t += 0.06
			local baseCf = CFrame.new(podium.Position.X, topY, podium.Position.Z)
			model:PivotTo(baseCf * CFrame.Angles(0, t, 0) * CFrame.new(0, math.sin(t * 2) * 0.3, 0))
			task.wait(0.06)
		end
	end)

	slotModels[slot][entry.id] = model
end

----------------------------------------------------------------- place / remove brainrot (public)
function BaseManager.placeBrainrot(player: Player, entry: any)
	local slot = playerSlot[player]
	if not slot then
		return
	end
	placeBrainrotForSlot(slot, player, entry)
end

function BaseManager.removeBrainrot(player: Player, id: string)
	local slot = playerSlot[player]
	if not slot then
		return
	end
	local models = slotModels[slot]
	if models and models[id] then
		models[id]:Destroy()
		models[id] = nil
	end
end

-- Refresh a single placed brainrot's "Lv N" billboard after it levels up (called
-- by EconomyManager.levelBrainrot). No-op if the model isn't placed for the player.
function BaseManager.refreshBrainrotLabel(player: Player, entry: any)
	local slot = playerSlot[player]
	if not slot then
		return
	end
	local models = slotModels[slot]
	local model = models and models[entry.id]
	if model then
		setBrainrotLevelLabel(model, entry.level or 1)
	end
end

-- (re)build the podium grid + plates for a player's plot count, then re-place
-- their brainrots (called from EconomyManager.buyPlot and RebirthManager).
function BaseManager.rebuildPlots(player: Player)
	local profile = PlayerData.get(player)
	local slot = playerSlot[player]
	if not profile or not slot then
		return
	end

	rebuildSlotPodiums(slot, profile.Plots)

	for _, entry in ipairs(profile.Collection) do
		placeBrainrotForSlot(slot, player, entry)
	end

	-- refresh ladder / floor-2 / incubator visibility after a plot change
	refreshBaseProgression(slot)
end

----------------------------------------------------------------- building shell
-- back-of-base layout: 4 incubators in a row near the back wall + a centered LADDER.
local INCUBATOR_XS = { -22, -8, 8, 22 }       -- 4 spots spread across the back
local INCUBATOR_LZ = FLOOR.Z / 2 - 7          -- inside, just in front of the back wall
local LADDER_H = FLOOR2_Y + 3 - 1             -- floor 1 (y=1) up to a bit above floor 2
local LADDER_HOLE_HALF_X = 3.5                -- half-width of the floor-2 climb-through hole
local LADDER_HOLE_FRONT_LZ = FLOOR.Z / 2 - 9  -- hole runs from here back to the back wall

-- Build ONE incubator unit (base + glass dome) at floor-XZ `cf`, wrapped in a Model so it
-- can be reparented out of Workspace to HIDE it (studs are decals, so transparency alone
-- wouldn't hide them). Returns a record driven by setIncubatorState. The ClickDetector
-- buys the next incubator when shown as a ghost.
local function buildIncubator(slot: number, cf: CFrame, index: number): any
	local home = slotFolder[slot]
	local unit = Instance.new("Model")
	unit.Name = ("IncubatorUnit_%d"):format(index)
	unit.Parent = home

	local base = makePart({
		Name = "Incubator",
		Size = Vector3.new(5, 4.5, 4),
		Color = Palette.Incubator,
		Material = Enum.Material.Metal,
		CFrame = cf * CFrame.new(0, 2.25, 0),
		Parent = unit,
	})
	local dome = makePart({
		Name = "Dome",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3.4, 3.4, 3.4),
		Color = Palette.Glass,
		Material = Enum.Material.Glass,
		Transparency = 0.4,
		CanCollide = false,
		CFrame = base.CFrame * CFrame.new(0, 2.6, 0),
		Parent = unit,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(150, 230, 255)
	light.Brightness = 3
	light.Range = 12
	light.Parent = dome
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 150, 0, 40)
	bb.StudsOffset = Vector3.new(0, 4, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 140
	bb.Parent = base
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.Text = "🥚 INCUBATOR"
	lbl.TextColor3 = Color3.fromRGB(150, 230, 255)
	lbl.TextStrokeTransparency = 0
	lbl.Parent = bb

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 0 -- enabled only in the ghost (buy) state
	click.Parent = base
	click.MouseClick:Connect(function(clicker: Player)
		if clicker ~= slotOccupant[slot] then
			return
		end
		local res = IncubationManager.unlockIncubator(clicker)
		if res and res.ok == false and res.reason then
			Net.getEvent("Notify"):FireClient(clicker, { title = "Incubator", text = res.reason, color = "Legendary" })
		end
	end)

	return { model = unit, home = home, base = base, dome = dome, light = light, label = lbl, click = click, index = index, pos = base.Position }
end

-- Drive an incubator unit's look: "real" (unlocked, solid + glowing), "ghost" (next to
-- buy, translucent + Buy label + clickable) or "hidden" (reparented out of Workspace).
local function setIncubatorState(rec: any, state: string, cost: number?, canAfford: boolean?)
	if state == "hidden" then
		if rec.model.Parent ~= hiddenHolder then
			rec.model.Parent = hiddenHolder
		end
		return
	end
	if rec.model.Parent ~= rec.home then
		rec.model.Parent = rec.home
	end
	if state == "real" then
		rec.base.Transparency = 0
		rec.base.CanCollide = true
		rec.base.Color = Palette.Incubator
		rec.dome.Transparency = 0.4
		rec.light.Enabled = true
		rec.label.Text = ("🥚 INCUBATOR %d"):format(rec.index)
		rec.label.TextColor3 = Color3.fromRGB(150, 230, 255)
		rec.click.MaxActivationDistance = 0
	else -- ghost
		rec.base.Transparency = 0.5
		rec.base.CanCollide = false
		rec.base.Color = Palette.Wall
		rec.dome.Transparency = 0.85
		rec.light.Enabled = false
		rec.label.Text = ("🔒 Buy Incubator\n$%s"):format(Format.short(cost or 0))
		rec.label.TextColor3 = canAfford and Color3.fromRGB(150, 255, 150) or Color3.fromRGB(255, 200, 150)
		rec.click.MaxActivationDistance = 28
	end
end

-- Build the back-wall LADDER (a climbable truss) to floor 2 for `slot`. Driven by
-- refreshBaseProgression: hidden < 12 plots, a buyable ghost at 12 plots, climbable once
-- the ladder is bought. The Buy click routes to EconomyManager.buyLadder.
local function buildLadder(slot: number, origin: CFrame): any
	local home = slotFolder[slot]
	local truss = Instance.new("TrussPart")
	truss.Name = "Ladder"
	truss.Anchored = true
	truss.Color = Palette.BaseTrim
	truss.Size = Vector3.new(2, LADDER_H, 2)
	truss.CFrame = origin * CFrame.new(0, 1 + LADDER_H / 2, FLOOR.Z / 2 - 2.5)
	truss.Transparency = 1
	truss.CanCollide = false
	truss.Parent = home

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 180, 0, 52)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 130
	bb.Parent = truss
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.Text = ""
	lbl.TextColor3 = Color3.fromRGB(255, 230, 150)
	lbl.TextStrokeTransparency = 0
	lbl.Parent = bb

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 0
	click.Parent = truss
	click.MouseClick:Connect(function(clicker: Player)
		if clicker ~= slotOccupant[slot] then
			return
		end
		local res = EconomyManager.buyLadder(clicker)
		if res and res.ok == false and res.reason then
			Net.getEvent("Notify"):FireClient(clicker, { title = "Ladder", text = res.reason, color = "Legendary" })
		end
	end)

	return { truss = truss, label = lbl, billboard = bb, click = click }
end

-- a SHARED per-zone rebirth gate on the one central lane. Wall #k sits between the
-- zone-k and zone-(k+1) dig sites. It PHYSICALLY BLOCKS players who have not yet
-- unlocked zone k+1 (via the "ZoneGate"..k collision group — see setupZoneCollision)
-- and lets unlocked players walk straight through, so rebirthing "breaks down the
-- wall" for you. Clicking it tries to rebirth the CLICKER, but only when THEY are
-- currently in zone k. Its SurfaceGui shows a GENERIC shared label.
local function buildSharedWall(k: number, cf: CFrame, parent: Instance)
	local wall = makePart({
		Name = ("RebirthWall_%d"):format(k),
		Size = REBIRTH_WALL,
		Color = Palette.Wall,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.05,
		CFrame = cf,
		Parent = parent,
	})
	-- blocks players below the zone-k+1 threshold; unlocked players pass through it
	wall.CanCollide = true
	pcall(function()
		wall.CollisionGroup = ("ZoneGate%d"):format(k)
	end)

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 30
	click.Parent = wall

	local surf = Instance.new("SurfaceGui")
	surf.Name = "WallInfo"
	surf.Face = Enum.NormalId.Front -- Front (-Z under identity rotation) faces the half-circle / approaching players
	surf.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surf.PixelsPerStud = 18
	surf.LightInfluence = 0
	surf.MaxDistance = 120
	surf.Parent = wall

	local function mkLabel(yScale: number, hScale: number): TextLabel
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(0.92, 0, hScale, 0)
		l.Position = UDim2.new(0.04, 0, yScale, 0)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextColor3 = Color3.new(1, 1, 1)
		l.TextStrokeTransparency = 0.35
		l.Parent = surf
		return l
	end

	local title = mkLabel(0.16, 0.24)
	title.TextColor3 = Color3.fromRGB(255, 220, 120)
	title.Text = ("➡ %s"):format(ZoneConfig.get(k + 1).DisplayName)
	local line = mkLabel(0.5, 0.18)
	line.Text = "Rebirth to unlock"

	click.MouseClick:Connect(function(clicker: Player)
		if not rebirthHandler then
			return
		end
		local profile = PlayerData.get(clicker)
		-- only the wall in front of the clicker's CURRENT zone advances them
		if not profile or profile.CurrentZone ~= k then
			return
		end
		local result = rebirthHandler(clicker)
		if result and result.ok == false and result.reason then
			Net.getEvent("Notify"):FireClient(clicker, {
				title = "Wall Locked", text = result.reason, color = "Legendary",
			})
		end
	end)
end

-- a physical dig area for `zone` at world position `pos`, styled exactly like the
-- central green dig square (same size + grass) with a "DigPatch" slab + sign.
local function buildZoneArea(zone: number, pos: Vector3, farDir: Vector3, parent: Instance)
	local zoneData = ZoneConfig.get(zone)
	if not zoneData then
		return
	end

	-- rotate the pad/border to line up squarely with the lane direction
	local yaw = math.atan2(farDir.X, farDir.Z)
	local rot = CFrame.Angles(0, yaw, 0)

	-- grass border (same studded look as the central dig site)
	makePart({
		Name = "ZoneBorder",
		Size = SEG_SIZE + Vector3.new(12, -0.4, 12),
		Color = Palette.Grass,
		CFrame = CFrame.new(pos.X, LANE_SEG_Y - 0.2, pos.Z) * rot,
		Parent = parent,
	})

	local dirt = makePart({
		Name = ("Zone%dDig"):format(zone),
		Size = SEG_SIZE,
		-- the dig field's FIRST LAYER is a dark brown earth, deliberately DARKER than
		-- the tan dirt mounds (~RGB 186,150,110) the client scatters on top of it.
		Color = Palette.DigField,
		CFrame = CFrame.new(pos.X, LANE_SEG_Y, pos.Z) * rot,
		Parent = parent,
	})
	CollectionService:AddTag(dirt, "DigPatch")
	dirt:SetAttribute("Zone", zone)

	local signPart = makePart({
		Name = "ZoneSign",
		Size = Vector3.new(1, 1, 1),
		Transparency = 1,
		CFrame = CFrame.new(pos.X, 9, pos.Z),
		Parent = parent,
	})
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 170, 0, 38)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 200
	bb.Parent = signPart
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.Text = (zone == 1) and "⛏️ DIG HERE FOR EGGS!" or ("⛏️ %s"):format(zoneData.DisplayName)
	lbl.TextColor3 = zoneData.GroundColor
	lbl.TextStrokeTransparency = 0
	lbl.Parent = bb
end

-- the slot's name sign over the open front. Stored so its text can toggle between
-- "OPEN PLOT N" (unoccupied) and "<player>'s Base" (occupied).
local function buildBaseSign(slot: number, origin: CFrame, parent: Instance)
	local signPart = makePart({
		Name = "Sign",
		Size = Vector3.new(1, 1, 1),
		Transparency = 1,
		CFrame = origin * CFrame.new(0, 1 + WALL_H + 3, -FLOOR.Z / 2),
		Parent = parent,
	})
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 190, 0, 40)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 200
	bb.Parent = signPart
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.Text = ("🟢 OPEN PLOT %d"):format(slot)
	lbl.TextColor3 = Color3.fromRGB(120, 220, 255)
	lbl.TextStrokeTransparency = 0
	lbl.Parent = bb
	slotSign[slot] = lbl
end

-- the two-floor building shell: tall side walls (windows on each floor), floor-2
-- slab with a back-center staircase opening, roof, split back wall with a centered
-- staircase doorway, the staircase itself, and a removable staircase barrier.
-- Returns the incubator's base part (placed just outside the open front).
-- Build a slot's building. Floor-1 structure goes to `parent`; ALL floor-2 structure
-- goes into a "Floor2" folder that refreshBaseProgression reparents out of Workspace to
-- HIDE it until the occupant buys the ladder. Also builds the 4 back incubators + the
-- centered back-wall ladder. Populates slotIncubators / slotLadder / slotFloor2.
local function buildBuilding(slot: number, origin: CFrame, parent: Instance)
	local wallColor = Palette.BaseWall
	local trimColor = Palette.BaseTrim

	local f2 = Instance.new("Folder")
	f2.Name = "Floor2"
	f2.Parent = parent
	slotFloor2[slot] = f2

	-- per-floor side window section (glass strip + brick above/below). `dest` routes the
	-- parts to floor 1 (parent) or floor 2 (f2).
	local function sideFloor(x: number, baseLY: number, dest: Instance)
		makePart({ Name = "Wall", Size = Vector3.new(WALL_T, 7, FLOOR.Z), Color = wallColor, Material = Enum.Material.Brick, CFrame = origin * CFrame.new(x, baseLY + 3.5, 0), Parent = dest })
		makePart({ Name = "Wall", Size = Vector3.new(WALL_T, 7, FLOOR.Z), Color = wallColor, Material = Enum.Material.Brick, CFrame = origin * CFrame.new(x, baseLY + WALL_H - 3.5, 0), Parent = dest })
		makePart({ Name = "Window", Size = Vector3.new(WALL_T * 0.5, 8, FLOOR.Z - 5), Color = Palette.Glass, Material = Enum.Material.Glass, Transparency = 0.5, CanCollide = false, CFrame = origin * CFrame.new(x, baseLY + WALL_H / 2, 0), Parent = dest })
	end

	-- side walls + corner pillars, split per floor so the upper halves can hide.
	local pillarH = WALL_H + WALL_T
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (FLOOR.X / 2)
		sideFloor(x, 1, parent)       -- floor 1
		sideFloor(x, FLOOR2_Y, f2)    -- floor 2 (hidden until ladder)
		for _, lz in ipairs({ -FLOOR.Z / 2, FLOOR.Z / 2 }) do
			makePart({ Name = "Pillar", Size = Vector3.new(WALL_T + 1.5, pillarH, WALL_T + 1.5), Color = trimColor, Material = Enum.Material.Metal, CFrame = origin * CFrame.new(x, 1 + pillarH / 2, lz), Parent = parent })
			makePart({ Name = "Pillar", Size = Vector3.new(WALL_T + 1.5, pillarH, WALL_T + 1.5), Color = trimColor, Material = Enum.Material.Metal, CFrame = origin * CFrame.new(x, FLOOR2_Y + pillarH / 2, lz), Parent = f2 })
		end
	end

	-- floor-1 slab
	makePart({ Name = "Platform", Size = FLOOR, Color = Palette.BaseFloor, Material = Enum.Material.SmoothPlastic, CFrame = origin, Parent = parent })

	-- floor-2 slab (in f2) with a back-center HOLE the ladder climbs through.
	do
		local slabMidY = FLOOR2_Y - WALL_T / 2
		local sideW = FLOOR.X / 2 - LADDER_HOLE_HALF_X
		for _, sx in ipairs({ -1, 1 }) do
			makePart({ Name = "Floor2Slab", Size = Vector3.new(sideW, WALL_T, FLOOR.Z), Color = Palette.BaseFloor, Material = Enum.Material.SmoothPlastic, CFrame = origin * CFrame.new(sx * (LADDER_HOLE_HALF_X + sideW / 2), slabMidY, 0), Parent = f2 })
		end
		local frontLen = LADDER_HOLE_FRONT_LZ - (-FLOOR.Z / 2) -- front edge to the hole
		makePart({ Name = "Floor2Slab", Size = Vector3.new(2 * LADDER_HOLE_HALF_X, WALL_T, frontLen), Color = Palette.BaseFloor, Material = Enum.Material.SmoothPlastic, CFrame = origin * CFrame.new(0, slabMidY, -FLOOR.Z / 2 + frontLen / 2), Parent = f2 })
	end

	-- roof + headers + floor-2 rail (roof, upper header & rail are floor-2)
	local roofY = 1 + 2 * WALL_H + WALL_T + WALL_T / 2
	makePart({ Name = "Roof", Size = Vector3.new(FLOOR.X + 3, WALL_T, FLOOR.Z + 3), Color = trimColor, Material = Enum.Material.Metal, CFrame = origin * CFrame.new(0, roofY, 0), Parent = f2 })
	makePart({ Name = "Header", Size = Vector3.new(FLOOR.X, 4, WALL_T), Color = trimColor, Material = Enum.Material.Metal, CFrame = origin * CFrame.new(0, 1 + WALL_H - 2, -FLOOR.Z / 2), Parent = parent })
	makePart({ Name = "Header", Size = Vector3.new(FLOOR.X, 4, WALL_T), Color = trimColor, Material = Enum.Material.Metal, CFrame = origin * CFrame.new(0, FLOOR2_Y + WALL_H - 2, -FLOOR.Z / 2), Parent = f2 })
	makePart({ Name = "Floor2Rail", Size = Vector3.new(FLOOR.X, 3, WALL_T * 0.7), Color = trimColor, Material = Enum.Material.Metal, CFrame = origin * CFrame.new(0, FLOOR2_Y + 1.5, -FLOOR.Z / 2), Parent = f2 })

	-- SOLID back wall, split floor 1 (visible) / floor 2 (in f2)
	makePart({ Name = "BackWall", Size = Vector3.new(FLOOR.X, WALL_H, WALL_T), Color = wallColor, Material = Enum.Material.Brick, CFrame = origin * CFrame.new(0, 1 + WALL_H / 2, FLOOR.Z / 2), Parent = parent })
	makePart({ Name = "BackWall", Size = Vector3.new(FLOOR.X, WALL_H, WALL_T), Color = wallColor, Material = Enum.Material.Brick, CFrame = origin * CFrame.new(0, FLOOR2_Y + WALL_H / 2, FLOOR.Z / 2), Parent = f2 })

	-- 4 incubators across the back + the centered back-wall ladder to floor 2
	slotIncubators[slot] = {}
	for i, lx in ipairs(INCUBATOR_XS) do
		slotIncubators[slot][i] = buildIncubator(slot, origin * CFrame.new(lx, 0, INCUBATOR_LZ), i)
	end
	slotLadder[slot] = buildLadder(slot, origin)
end

-- the ONE SHARED dig progression LANE: a single straight line down the half-circle
-- axis of symmetry (x = MapBuilder.DigCenter.X). The whole lane sits OUTSIDE the
-- half-circle on the +Z OPENING side (the end plots sit at +Z; the bulge/center is
-- at -Z), pushed WAY back past the opening. Dig sites march OUTWARD (+Z), site 1
-- closest to the opening, with walls midway between them. EVERY player uses this one
-- lane and must break each wall to advance:
--   half-circle opening -> Zone 1 dig -> wall -> Zone 2 dig -> wall -> Zone 3 dig
----------------------------------------------------------------- zone collision gating
-- Players physically can't cross a rebirth wall into a zone they haven't unlocked.
-- Collision groups: wall k is in "ZoneGate"..k; each player is in "ZoneProg"..(their
-- highest unlocked zone). A player passes gate k iff their progress > k (i.e. they've
-- unlocked zone k+1). The lobby/bases sit SOUTH of every wall, so gating only blocks
-- FORWARD travel into locked zones — a player can always walk home, and a freshly
-- rebirthed player's group is refreshed so they're never trapped on the far side.
local ZONE_GATE = "ZoneGate" -- + k
local ZONE_PROG = "ZoneProg" -- + progress level
local function setupZoneCollision()
	local function reg(name: string)
		pcall(function() PhysicsService:RegisterCollisionGroup(name) end)
	end
	for k = 1, ZoneConfig.MaxZone - 1 do reg(ZONE_GATE .. k) end
	for p = 1, ZoneConfig.MaxZone do reg(ZONE_PROG .. p) end
	-- progress p passes gate k iff p > k (make those pairs NON-collidable)
	for p = 1, ZoneConfig.MaxZone do
		for k = 1, ZoneConfig.MaxZone - 1 do
			if p > k then
				pcall(function()
					PhysicsService:CollisionGroupSetCollidable(ZONE_PROG .. p, ZONE_GATE .. k, false)
				end)
			end
		end
	end
end

-- Put a player's character into the collision group for their unlocked progress so
-- the zone walls block/pass them correctly. Called on every spawn and after rebirth.
function BaseManager.applyZoneGate(player: Player)
	local char = player.Character
	if not char then
		return
	end
	local profile = PlayerData.get(player)
	local level = profile and ZoneConfig.highestUnlocked(profile.Rebirths) or 1
	local group = ZONE_PROG .. math.clamp(level, 1, ZoneConfig.MaxZone)
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			pcall(function() part.CollisionGroup = group end)
		end
	end
end

-- un-jumpable side FENCES at the zone1/2 boundary: a solid wall from each lane-
-- flanking END plot (slots 9 & 10) to the matching end of the zone1/2 wall, so a
-- player can't walk AROUND the wall to skip into zone 2. Always collidable (default
-- group) — only the central wall is the per-player gate.
-- The lane-flanking side barriers at the zone1/2 boundary. TWO layers:
--   1) a TALL INVISIBLE collidable wall (named ZoneFence_*) so a player can NEVER jump
--      or glitch over to skip into zone 2 (jump height ~7 studs; this barrier is 60 tall).
--   2) a VISIBLE studded fence in front of it -- the asset 4831942116 tiled along the span
--      when the game owner can load it, else a procedural studded picket fence.
-- LeaderboardManager finds the ZoneFence_* reference part to place its tombstone.
local FENCE_VIS_H = 14      -- visible fence height
local FENCE_BARRIER_H = 60  -- tall invisible anti-jump/glitch wall
local FENCE_ASSET = 4831942116

local fenceTemplate: Model? = nil
local fenceTried = false
local function getFenceTemplate(): Model?
	if fenceTried then
		return fenceTemplate
	end
	fenceTried = true
	local ok, asset = pcall(function()
		return InsertService:LoadAsset(FENCE_ASSET)
	end)
	if ok and asset then
		local obj = asset:FindFirstChildWhichIsA("Model") or asset:FindFirstChildWhichIsA("BasePart")
		if obj then
			local clone = obj:Clone()
			local model: Model
			if clone:IsA("Model") then
				model = clone
			else
				model = Instance.new("Model")
				clone.Parent = model
			end
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CastShadow = false
				end
			end
			fenceTemplate = model
		end
		asset:Destroy()
	end
	return fenceTemplate
end

-- a procedural STUDDED picket fence of `length` centered on `baseCF` (sitting on the
-- ground, local +Z = run direction): posts every ~7 studs + two horizontal rails.
local function buildProceduralFence(baseCF: CFrame, length: number, parent: Instance)
	local spacing = 7
	local nPosts = math.max(2, math.floor(length / spacing) + 1)
	for i = 0, nPosts - 1 do
		local lz = -length / 2 + (i / (nPosts - 1)) * length
		makePart({
			Name = "FencePost",
			Size = Vector3.new(1.8, FENCE_VIS_H, 1.8),
			Color = Palette.Fence,
			CanCollide = false,
			CFrame = baseCF * CFrame.new(0, FENCE_VIS_H / 2, lz),
			Parent = parent,
		})
	end
	for _, ry in ipairs({ FENCE_VIS_H * 0.34, FENCE_VIS_H * 0.72 }) do
		makePart({
			Name = "FenceRail",
			Size = Vector3.new(0.9, 1.6, length),
			Color = Palette.Fence,
			CanCollide = false,
			CFrame = baseCF * CFrame.new(0, ry, 0),
			Parent = parent,
		})
	end
end

-- tile the loaded fence asset along the span, else the procedural studded fence.
local function buildFenceDecor(baseCF: CFrame, length: number, parent: Instance)
	local tmpl = getFenceTemplate()
	if not tmpl then
		buildProceduralFence(baseCF, length, parent)
		return
	end
	local _, size = tmpl:GetBoundingBox()
	local seg = math.max(size.X, size.Z, 4) -- longest horizontal extent == one section
	local n = math.max(1, math.floor(length / seg + 0.5))
	local step = length / n
	for i = 1, n do
		local clone = tmpl:Clone()
		local _, s0 = clone:GetBoundingBox()
		if s0.Y > 0.01 then
			pcall(function() clone:ScaleTo(FENCE_VIS_H / s0.Y) end)
		end
		local _, s = clone:GetBoundingBox()
		local lz = -length / 2 + (i - 0.5) * step
		-- run the section's long axis along local Z and stand it on the ground
		clone:PivotTo(baseCF * CFrame.new(0, s.Y / 2, lz) * CFrame.Angles(0, math.rad(90), 0))
		clone.Parent = parent
	end
end

local function buildLaneFences()
	local wallZ = LANE_START + LANE_STEP / 2 -- zone1/2 (k=1) wall center z
	local wallHalfX = REBIRTH_WALL.X / 2
	for _, fence in ipairs({
		{ slot = 9, sign = -1, name = "ZoneFence_Left" },
		{ slot = 10, sign = 1, name = "ZoneFence_Right" },
	}) do
		local wallEnd = Vector3.new(fence.sign * wallHalfX, 0, wallZ) -- end of the wall on this side
		-- anchor at the end-plot footprint CORNER nearest that wall end, so it meets the
		-- building at its edge instead of clipping through the plot interior.
		local origin = baseOrigin(fence.slot)
		local best = wallEnd
		local bestD = math.huge
		for _, lx in ipairs({ -1, 1 }) do
			for _, lz in ipairs({ -1, 1 }) do
				local c = (origin * CFrame.new(lx * FLOOR.X / 2, 0, lz * FLOOR.Z / 2)).Position
				local d = (Vector3.new(c.X, 0, c.Z) - wallEnd).Magnitude
				if d < bestD then
					bestD = d
					best = c
				end
			end
		end
		local dx, dz = wallEnd.X - best.X, wallEnd.Z - best.Z
		local length = math.max(math.sqrt(dx * dx + dz * dz), 1)
		local angle = math.atan2(dx, dz)
		local midX, midZ = (best.X + wallEnd.X) / 2, (best.Z + wallEnd.Z) / 2

		-- 1) tall INVISIBLE collidable barrier (the anti jump/glitch wall + ref part)
		makePart({
			Name = fence.name,
			Size = Vector3.new(2, FENCE_BARRIER_H, length),
			Transparency = 1,
			NoStuds = true,
			CanCollide = true,
			CFrame = CFrame.new(midX, 1 + FENCE_BARRIER_H / 2, midZ) * CFrame.Angles(0, angle, 0),
			Parent = laneFolder,
		})

		-- 2) visible studded fence at the base (asset tiled if loadable, else procedural)
		buildFenceDecor(CFrame.new(midX, 1, midZ) * CFrame.Angles(0, angle, 0), length, laneFolder)
	end
end

----------------------------------------------------------------- zone decorations
-- Vibrant, STUDDED rock piles that frame each rebirth wall (a tall cliff-like pile at
-- both wall ends) + per-zone THEME decor (Forest => trees flanking the dig site). Built
-- once with the lane; pulls colours from Palette and studs via makePart, like everything.
local FOREST_TREE_ASSET = 17280628013 -- user-supplied low-poly tree model

-- Decorations (trees, rocks, colour jitter) are placed with a FIXED-SEED RNG so the
-- layout is IDENTICAL on every server start / rebuild instead of re-scattering each run
-- (the module reloads fresh each server start, so this seed restarts the same sequence).
-- The build order is deterministic, so the same draws land in the same spots every time.
local DECOR_SEED = 90210
local decorRng = Random.new(DECOR_SEED)

local function jitterColor(c: Color3, amt: number): Color3
	local j = (decorRng:NextNumber() - 0.5) * amt
	return Color3.new(
		math.clamp(c.R + j, 0, 1),
		math.clamp(c.G + j, 0, 1),
		math.clamp(c.B + j, 0, 1)
	)
end

-- a tall, chunky STUDDED stone pile rising from the ground at `base`, framing a wall
-- end: wider at the bottom, tapering up past the wall top, with a few base boulders.
local function buildRockPile(base: Vector3, height: number)
	local levels = 6
	local y = 1
	for i = 0, levels - 1 do
		local t = i / (levels - 1)
		local w = 24 - t * 13
		local d = 18 - t * 9
		local h = (height / levels) * 1.25
		makePart({
			Name = "ZoneRock",
			Size = Vector3.new(w, h, d),
			Color = jitterColor(Palette.Stone, 0.06),
			CanCollide = true,
			CFrame = CFrame.new(base.X + (decorRng:NextNumber() - 0.5) * 6, y + h / 2 - 1, base.Z + (decorRng:NextNumber() - 0.5) * 6)
				* CFrame.Angles(0, math.rad(decorRng:NextInteger(-20, 20)), 0),
			Parent = laneFolder,
		})
		y = y + h * 0.74
	end
	for _ = 1, 3 do
		local s = decorRng:NextInteger(6, 11)
		makePart({
			Name = "ZoneRock",
			Size = Vector3.new(s, s * 0.8, s * 0.9),
			Color = jitterColor(Palette.Stone, 0.06),
			CanCollide = true,
			CFrame = CFrame.new(base.X + (decorRng:NextNumber() - 0.5) * 18, 1 + s * 0.3, base.Z + (decorRng:NextNumber() - 0.5) * 16)
				* CFrame.Angles(math.rad(decorRng:NextInteger(0, 35)), math.rad(decorRng:NextInteger(0, 360)), math.rad(decorRng:NextInteger(0, 30))),
			Parent = laneFolder,
		})
	end
end

-- frame BOTH ends of the rebirth wall at lane-z `wz` with stone piles.
local function buildWallFrame(wz: number)
	local x = MapBuilder.DigCenter.X
	local endX = REBIRTH_WALL.X / 2    -- wall ends at +/-50
	local pileH = REBIRTH_WALL.Y + 12  -- rise a bit above the 44-tall wall
	for _, sign in ipairs({ -1, 1 }) do
		buildRockPile(Vector3.new(x + sign * (endX + 4), 0, wz), pileH)
	end
end

------------------------------------------------------------- trees (Forest theme)
local treeTemplate: Model? = nil
local treeTried = false

-- a procedural STUDDED pine, the fallback when the asset can't be loaded (it loads in a
-- published game if the game owner owns the asset, but not for an unauthorized account).
local function buildProceduralTree(): Model
	local model = Instance.new("Model")
	model.Name = "Tree"
	local trunkH = 7
	-- FLAT colours (no jitterColor) on purpose: jitter would draw from decorRng, and the
	-- procedural pine only runs when the asset fails to load — so a flaky LoadAsset would
	-- change how many draws each tree consumes and DESYNC the whole layout between runs.
	-- Keeping this path draw-free makes tree placement identical every server start.
	local trunk = makePart({
		Name = "Trunk",
		Size = Vector3.new(2.6, trunkH, 2.6),
		Color = Palette.TreeTrunk,
		CanCollide = false,
		CFrame = CFrame.new(0, trunkH / 2, 0),
		Parent = model,
	})
	model.PrimaryPart = trunk
	for _, ti in ipairs({
		{ w = 13, h = 7, y = trunkH + 1 },
		{ w = 10, h = 6, y = trunkH + 6 },
		{ w = 6.5, h = 5, y = trunkH + 10.5 },
	}) do
		makePart({
			Name = "Leaves",
			Size = Vector3.new(ti.w, ti.h, ti.w),
			Color = Palette.TreeLeaf,
			CanCollide = false,
			CFrame = CFrame.new(0, ti.y, 0) * CFrame.Angles(0, math.rad(45), 0),
			Parent = model,
		})
	end
	return model
end

-- try once to load the real tree asset; nil => callers use the procedural pine.
local function getTreeTemplate(): Model?
	if treeTried then
		return treeTemplate
	end
	treeTried = true
	local ok, asset = pcall(function()
		return InsertService:LoadAsset(FOREST_TREE_ASSET)
	end)
	if ok and asset then
		local obj = asset:FindFirstChildWhichIsA("Model") or asset:FindFirstChildWhichIsA("BasePart")
		if obj then
			local clone = obj:Clone()
			local model: Model
			if clone:IsA("Model") then
				model = clone
			else
				model = Instance.new("Model")
				clone.Parent = model
			end
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CastShadow = false
				end
			end
			treeTemplate = model
		end
		asset:Destroy()
	end
	return treeTemplate
end

-- place ONE tree (real asset clone if available, else procedural) standing on the
-- ground at (x, z), scaled to ~targetH studs tall and randomly spun about Y.
local function placeTree(x: number, z: number, targetH: number, parent: Instance)
	local tmpl = getTreeTemplate()
	local tree: Model = (tmpl and tmpl:Clone()) or buildProceduralTree()
	tree.Name = "Tree"
	local _, size0 = tree:GetBoundingBox()
	if size0.Y > 0.01 then
		pcall(function() tree:ScaleTo(targetH / size0.Y) end)
	end
	-- drop the bounding-box base to the ground (y=1), centered at (x,z)
	local cf, size = tree:GetBoundingBox()
	local center = Vector3.new(x, 1 + size.Y / 2, z)
	tree:PivotTo(tree:GetPivot() + (center - cf.Position))
	-- spin about the vertical axis through its center
	local rot = CFrame.new(center) * CFrame.Angles(0, math.rad(decorRng:NextInteger(0, 359)), 0) * CFrame.new(center):Inverse()
	tree:PivotTo(rot * tree:GetPivot())
	tree.Parent = parent
end

-- scatter trees in the LEFT and RIGHT strips flanking a Forest dig site, within the
-- z range between its walls and clear of the 96-wide dig square. NEVER on the lane.
local function buildForestTrees(zLo: number, zHi: number)
	local cx = MapBuilder.DigCenter.X
	local innerX = SEG_SIZE.X / 2 + 12 -- clear of the dig square + margin
	local outerX = innerX + 64         -- strip ~64 studs wide
	local step = 19
	for _, sign in ipairs({ -1, 1 }) do
		local gx = innerX
		while gx <= outerX do
			local gz = zLo
			while gz <= zHi do
				if decorRng:NextNumber() < 0.7 then -- gaps => natural forest edge
					local x = cx + sign * (gx + (decorRng:NextNumber() - 0.5) * step * 0.8)
					local z = gz + (decorRng:NextNumber() - 0.5) * step * 0.8
					placeTree(x, z, decorRng:NextInteger(16, 26) + decorRng:NextNumber(), laneFolder)
				end
				gz = gz + step
			end
			gx = gx + step
		end
	end
end

-- frame every rebirth wall with rock piles + add per-zone theme decor (trees).
local function decorateLane()
	for k = 1, ZoneConfig.MaxZone - 1 do
		buildWallFrame(LANE_START + (k - 1) * LANE_STEP + LANE_STEP / 2)
	end
	for z = 1, ZoneConfig.MaxZone do
		local data = ZoneConfig.get(z)
		if data and data.Theme == "Forest" then
			local pz = LANE_START + (z - 1) * LANE_STEP
			buildForestTrees(pz - LANE_STEP / 2 + 14, pz + LANE_STEP / 2 - 14)
		end
	end
end

local function buildSharedLane()
	local x = MapBuilder.DigCenter.X
	-- dig sites march OUTWARD (+Z) starting near the half-circle center (LANE_START):
	for z = 1, ZoneConfig.MaxZone do
		local pz = LANE_START + (z - 1) * LANE_STEP
		buildZoneArea(z, Vector3.new(x, 0, pz), Vector3.new(0, 0, 1), laneFolder)   -- dir +Z (lane runs outward)
	end
	-- walls exactly midway between consecutive dig sites; Front (-Z) faces the bases:
	for k = 1, ZoneConfig.MaxZone - 1 do
		local wz = LANE_START + (k - 1) * LANE_STEP + LANE_STEP / 2
		buildSharedWall(k, CFrame.new(x, LANE_WALL_Y, wz), laneFolder)
	end

	-- close the zone1/2 lane sides so the central wall can't simply be walked around
	buildLaneFences()

	-- frame the walls with studded rock + add per-zone theme decorations (trees)
	decorateLane()
end

----------------------------------------------------------------- base progression
-- Drive ALL of a slot's progression-gated visuals from its occupant's profile:
--   * incubators:  1..IncubatorsUnlocked are REAL; the next is a buyable GHOST; the rest
--                  are HIDDEN (so you only ever see the next one you can unlock).
--   * ladder:      HIDDEN until 12 plots; a buyable GHOST at 12 plots; climbable once bought.
--   * floor 2:     reparented OUT of Workspace (hidden from everyone) until the ladder is
--                  bought, then reparented back in (visible to the whole lobby).
-- Empty slots hide everything past the first incubator.
refreshBaseProgression = function(slot: number)
	local occupant = slotOccupant[slot]
	local profile = occupant and PlayerData.get(occupant) or nil
	local plots = (profile and profile.Plots) or 0
	local unlocked = (profile and profile.IncubatorsUnlocked) or 0
	local ladderUnlocked = (profile and profile.LadderUnlocked) or false
	local cash = (profile and profile.Cash) or 0

	-- incubators
	local incs = slotIncubators[slot]
	if incs then
		for i, rec in ipairs(incs) do
			if not occupant then
				setIncubatorState(rec, "hidden")
			elseif i <= unlocked then
				setIncubatorState(rec, "real")
			elseif i == unlocked + 1 then
				local cost = GameConfig.incubatorUnlockCost(unlocked) or 0
				setIncubatorState(rec, "ghost", cost, cash >= cost)
			else
				setIncubatorState(rec, "hidden")
			end
		end
	end

	-- ladder
	local ladder = slotLadder[slot]
	if ladder then
		if not occupant or plots < GameConfig.FloorOnePlots then
			ladder.truss.Transparency = 1
			ladder.truss.CanCollide = false
			ladder.label.Text = ""
			ladder.click.MaxActivationDistance = 0
		elseif not ladderUnlocked then
			ladder.truss.Transparency = 0.4
			ladder.truss.CanCollide = false -- not climbable until bought
			ladder.label.Text = ("🔒 Buy Ladder\n$%s"):format(Format.short(GameConfig.LadderCost))
			ladder.label.TextColor3 = (cash >= GameConfig.LadderCost) and Color3.fromRGB(150, 255, 150) or Color3.fromRGB(255, 200, 150)
			ladder.click.MaxActivationDistance = 30
		else
			ladder.truss.Transparency = 0
			ladder.truss.CanCollide = true
			ladder.label.Text = ""
			ladder.click.MaxActivationDistance = 0
		end
	end

	-- floor 2 visibility (reparent in/out of Workspace)
	local f2 = slotFloor2[slot]
	if f2 then
		local show = occupant ~= nil and ladderUnlocked
		local target = show and slotFolder[slot] or hiddenHolder
		if f2.Parent ~= target then
			f2.Parent = target
		end
	end
end

-- public: force a refresh for a player's slot (called after incubator/ladder purchases)
function BaseManager.refreshBaseProgression(player: Player)
	local slot = playerSlot[player]
	if slot then
		refreshBaseProgression(slot)
	end
end

----------------------------------------------------------------- build full base structure (once per slot)
-- Build the FULL permanent base structure for `slot`: building shell + podiums +
-- pressure plates + name sign. Visible whether the slot is occupied or not. The dig
-- progression is no longer per-base — it is the ONE shared central lane built once
-- in init (buildSharedLane). Podium count for an unoccupied slot uses StartingPlots.
local function buildBaseStructure(slot: number)
	local origin = baseOrigin(slot)
	local folder = Instance.new("Folder")
	folder.Name = ("Plot_%d"):format(slot)
	folder.Parent = basesFolder
	slotFolder[slot] = folder
	slotModels[slot] = {}
	slotPodiums[slot] = {}
	slotPlates[slot] = {}

	buildBuilding(slot, origin, folder) -- populates slotIncubators / slotLadder / slotFloor2
	rebuildSlotPodiums(slot, GameConfig.StartingPlots)
	buildBaseSign(slot, origin, folder)
	refreshBaseProgression(slot) -- start with everything past incubator 1 hidden (unoccupied)
end

----------------------------------------------------------------- assign / free
function BaseManager.assignBase(player: Player)
	local slot = nextFreeSlot()
	slotOccupant[slot] = player
	playerSlot[player] = slot

	-- mark the slot occupied: update the name sign (gold)
	local sign = slotSign[slot]
	if sign then
		sign.Text = ("%s's Base"):format(player.DisplayName)
		sign.TextColor3 = Color3.fromRGB(255, 220, 120)
	end

	-- rebuild podiums to the player's plot count. Always rebuild on assign (even when
	-- the count is unchanged) so the GHOST next-slot Buy podium — only built for an
	-- occupied slot — appears now that this slot has an occupant.
	local profile = PlayerData.get(player)
	local plots = profile and profile.Plots or GameConfig.StartingPlots
	rebuildSlotPodiums(slot, plots)

	-- load the player's brainrots onto the podiums
	if profile then
		for _, entry in ipairs(profile.Collection) do
			placeBrainrotForSlot(slot, player, entry)
		end
	end

	-- reveal this occupant's incubators / ladder / floor 2 per their saved progression
	refreshBaseProgression(slot)

	local origin = baseOrigin(slot)
	local function onCharacter(char: Model)
		local hrp = char:WaitForChild("HumanoidRootPart", 10)
		if hrp then
			task.wait(0.2)
			-- building faces inward; spawn inside facing the lane (the open front)
			char:PivotTo(origin * CFrame.new(0, 4, 6))
		end
	end
	if player.Character then
		onCharacter(player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)

	return origin
end

function BaseManager.freeBase(player: Player)
	local slot = playerSlot[player]
	if not slot then
		return
	end

	-- destroy ONLY the occupant's brainrot models; KEEP building/podiums/plates
	for _, model in pairs(slotModels[slot] or {}) do
		model:Destroy()
	end
	slotModels[slot] = {}

	-- an empty plot shows no Buy button: destroy + clear the ghost next-slot podium
	local ghost = slotGhostPlot[slot]
	if ghost then
		if ghost.podium then
			ghost.podium:Destroy()
		end
		slotGhostPlot[slot] = nil
	end

	-- reset the name sign back to the neutral OPEN PLOT state
	local sign = slotSign[slot]
	if sign then
		sign.Text = ("🟢 OPEN PLOT %d"):format(slot)
		sign.TextColor3 = Color3.fromRGB(120, 220, 255)
	end

	slotOccupant[slot] = nil
	playerSlot[player] = nil

	-- hide incubators (past #1) / ladder / floor 2 now that the slot is empty
	refreshBaseProgression(slot)
end

----------------------------------------------------------------- updaters
-- keeps the pressure-plate "ready to collect" labels AND each placed brainrot's
-- "Lv N" billboard in sync across ALL occupied slots (rebirth gating is now handled
-- by the shared lane, no per-slot walls)
function BaseManager.startGateUpdater()
	task.spawn(function()
		while true do
			for slot = 1, MAX_SLOTS do
				local occupant = slotOccupant[slot]
				local plates = slotPlates[slot]
				if plates then
					if occupant then
						for idx, rec in pairs(plates) do
							local id = brainrotIdAtPodium(slot, idx)
							if id then
								local amt = EconomyManager.getAccrued(occupant, id)
								rec.label.Text = (amt >= 1) and ("$%s\n▼ COLLECT"):format(Format.short(amt)) or ""
							else
								rec.label.Text = ""
							end
						end
					else
						-- unoccupied slot: keep plate labels blank
						for _, rec in pairs(plates) do
							rec.label.Text = ""
						end
					end
				end

				-- refresh each placed brainrot's "Lv N" label from the occupant's
				-- Collection entry level (keeps podium labels correct after leveling
				-- or a rebirth re-place).
				local models = slotModels[slot]
				if occupant and models then
					local profile = PlayerData.get(occupant)
					if profile then
						local levelById: { [string]: number } = {}
						for _, entry in ipairs(profile.Collection) do
							levelById[entry.id] = entry.level or 1
						end
						for id, model in pairs(models) do
							setBrainrotLevelLabel(model, levelById[id] or 1)
						end
					end
				end

				-- tint the ghost Buy label by affordability (green = can afford, soft-red = not)
				local ghost = slotGhostPlot[slot]
				if ghost and ghost.label and occupant then
					local profile = PlayerData.get(occupant)
					local cash = (profile and profile.Cash) or 0
					ghost.label.TextColor3 = (cash >= ghost.cost)
						and Color3.fromRGB(150, 255, 150)
						or Color3.fromRGB(255, 170, 150)
				end

				-- keep incubator-ghost + ladder Buy affordability tints live for occupants
				if occupant then
					refreshBaseProgression(slot)
				end
			end
			task.wait(0.5)
		end
	end)
end

-- World positions of the player's UNLOCKED incubators (for the "hatch at an incubator"
-- proximity check). Returns nil if the player has no slot / no incubators yet.
function BaseManager.getIncubatorPositions(player: Player): { Vector3 }?
	local slot = playerSlot[player]
	if not slot then
		return nil
	end
	local incs = slotIncubators[slot]
	local profile = PlayerData.get(player)
	if not incs or not profile then
		return nil
	end
	local unlocked = profile.IncubatorsUnlocked or 1
	local positions: { Vector3 } = {}
	for i = 1, math.min(unlocked, #incs) do
		positions[#positions + 1] = incs[i].pos
	end
	return positions
end

-- Teleport the player back to their OWN base (the same spot assignBase spawns them at).
function BaseManager.teleportHome(player: Player): any
	local slot = playerSlot[player]
	if not slot then
		return { ok = false, reason = "You don't have a base yet." }
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not char or not hrp then
		return { ok = false, reason = "No character to teleport." }
	end
	char:PivotTo(baseOrigin(slot) * CFrame.new(0, 4, 6))
	return { ok = true }
end

function BaseManager.init()
	-- the Home button (client) asks the server to put it back at its base
	Net.getFunction("TeleportHome").OnServerInvoke = function(player)
		return BaseManager.teleportHome(player)
	end

	basesFolder = Workspace:FindFirstChild(BASES_FOLDER_NAME) :: Folder
	if basesFolder then
		basesFolder:Destroy()
	end
	basesFolder = Instance.new("Folder")
	basesFolder.Name = BASES_FOLDER_NAME
	basesFolder.Parent = Workspace

	-- ServerStorage holder for HIDDEN floor-2 structures + locked incubators (out of
	-- Workspace => invisible to all clients & non-collidable until revealed).
	local existingHidden = ServerStorage:FindFirstChild("HiddenBaseParts")
	if existingHidden then
		existingHidden:Destroy()
	end
	hiddenHolder = Instance.new("Folder")
	hiddenHolder.Name = "HiddenBaseParts"
	hiddenHolder.Parent = ServerStorage

	-- dedicated folder for the ONE shared central dig lane
	local existingLane = Workspace:FindFirstChild(DIGLANE_FOLDER_NAME)
	if existingLane then
		existingLane:Destroy()
	end
	laneFolder = Instance.new("Folder")
	laneFolder.Name = DIGLANE_FOLDER_NAME
	laneFolder.Parent = Workspace

	-- pre-build the FULL base structure for every slot, occupied or not
	for slot = 1, MAX_SLOTS do
		buildBaseStructure(slot)
	end

	-- register the zone-gate collision groups BEFORE the walls (they set their own
	-- CollisionGroup), then build the SINGLE shared dig lane down the axis (x = 0)
	setupZoneCollision()
	buildSharedLane()
end

return BaseManager
