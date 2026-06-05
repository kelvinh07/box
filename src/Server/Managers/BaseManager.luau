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
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local ZoneConfig = require(Shared.Config.ZoneConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Palette = require(Shared.Config.Palette)
local Format = require(Shared.Modules.Format)
local Net = require(Shared.Modules.Net)

local PlayerData = require(script.Parent.PlayerData)
local BrainrotFactory = require(script.Parent.BrainrotFactory)
local MapBuilder = require(script.Parent.MapBuilder)
local EconomyManager = require(script.Parent.EconomyManager)

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
local slotPodiumCount: { [number]: number } = {}                   -- current podium count for the slot
local slotIncubator: { [number]: BasePart } = {}                   -- the incubator base part per slot (for proximity checks)
local slotStairBarrier: { [number]: { part: BasePart, label: TextLabel } } = {}  -- floor-2 staircase gate per slot
-- a GHOST "next plot" podium with a clickable Buy button, shown at the next free
-- podium slot for an OCCUPIED base under MaxPlots (nil otherwise). { podium,label,cost }
local slotGhostPlot: { [number]: any } = {}

-- forward declaration (defined below, called from buildBaseStructure)
local updateStaircase: (slot: number) -> ()

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

local function makePart(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	-- legoish look: glossy plastic + classic Roblox studs on top, inlets underneath
	p.Material = Enum.Material.Plastic
	p.TopSurface = Enum.SurfaceType.Studs
	p.BottomSurface = Enum.SurfaceType.Inlet
	for k, v in pairs(props) do
		(p :: any)[k] = v
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
	slotPodiumCount[slot] = count

	-- rebuild the GHOST next-slot Buy podium: destroy any prior one FIRST, then show
	-- it only for an OCCUPIED base that is still under MaxPlots, at index count+1.
	local prev = slotGhostPlot[slot]
	if prev then
		if prev.podium then
			prev.podium:Destroy()
		end
		slotGhostPlot[slot] = nil
	end
	if slotOccupant[slot] ~= nil and count < GameConfig.MaxPlots then
		buildGhostPlot(slot, count)
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
function BaseManager.placeBrainrot(player: Player, entry: any, skipPush: boolean?)
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

	-- buying the 12th plot opens the floor-2 staircase
	updateStaircase(slot)
end

----------------------------------------------------------------- building shell
local function buildIncubator(cf: CFrame, parent: Instance): BasePart
	local base = makePart({
		Name = "Incubator",
		Size = Vector3.new(6, 5, 5),
		Color = Palette.Incubator,
		Material = Enum.Material.Metal,
		CFrame = cf * CFrame.new(0, 2.5, 0),
		Parent = parent,
	})
	local dome = makePart({
		Name = "Dome",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(4, 4, 4),
		Color = Palette.Glass,
		Material = Enum.Material.Glass,
		Transparency = 0.4,
		CanCollide = false,
		CFrame = base.CFrame * CFrame.new(0, 3, 0),
		Parent = parent,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(150, 230, 255)
	light.Brightness = 3
	light.Range = 14
	light.Parent = dome
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 130, 0, 32)
	bb.StudsOffset = Vector3.new(0, 4.5, 0)
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
	return base
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

	-- grass border (same look as the central dig site)
	makePart({
		Name = "ZoneBorder",
		Size = SEG_SIZE + Vector3.new(12, -0.4, 12),
		Color = Palette.Grass,
		Material = Enum.Material.Grass,
		CFrame = CFrame.new(pos.X, LANE_SEG_Y - 0.2, pos.Z) * rot,
		Parent = parent,
	})

	local dirt = makePart({
		Name = ("Zone%dDig"):format(zone),
		Size = SEG_SIZE,
		-- the dig field's FIRST LAYER is a dark brown earth, deliberately DARKER than
		-- the tan dirt mounds (~RGB 186,150,110) the client scatters on top of it.
		Color = Palette.DigField,
		Material = Enum.Material.Ground,
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
local function buildBuilding(slot: number, origin: CFrame, parent: Instance): BasePart
	local wallColor = Palette.BaseWall
	local trimColor = Palette.BaseTrim
	local SIDE_H = 2 * WALL_H + WALL_T          -- side walls span both floors
	local SIDE_MID = 1 + SIDE_H / 2             -- center Y of a full-height side wall

	-- per-floor window: a glass strip + brick above/below it on each side wall
	local function sideFloor(x: number, baseLY: number)
		-- baseLY = floor surface; wall section spans baseLY .. baseLY + WALL_H
		makePart({ Name = "Wall", Size = Vector3.new(WALL_T, 7, FLOOR.Z), Color = wallColor, Material = Enum.Material.Brick, CFrame = origin * CFrame.new(x, baseLY + 3.5, 0), Parent = parent })
		makePart({ Name = "Wall", Size = Vector3.new(WALL_T, 7, FLOOR.Z), Color = wallColor, Material = Enum.Material.Brick, CFrame = origin * CFrame.new(x, baseLY + WALL_H - 3.5, 0), Parent = parent })
		makePart({ Name = "Window", Size = Vector3.new(WALL_T * 0.5, 8, FLOOR.Z - 5), Color = Palette.Glass, Material = Enum.Material.Glass, Transparency = 0.5, CanCollide = false, CFrame = origin * CFrame.new(x, baseLY + WALL_H / 2, 0), Parent = parent })
	end

	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (FLOOR.X / 2)
		sideFloor(x, 1)            -- floor 1 window section
		sideFloor(x, FLOOR2_Y)     -- floor 2 window section
		-- full-height corner pillars (front + back), spanning both floors
		makePart({ Name = "Pillar", Size = Vector3.new(WALL_T + 1.5, SIDE_H, WALL_T + 1.5), Color = trimColor, Material = Enum.Material.Metal, CFrame = origin * CFrame.new(x, SIDE_MID, -FLOOR.Z / 2), Parent = parent })
		makePart({ Name = "Pillar", Size = Vector3.new(WALL_T + 1.5, SIDE_H, WALL_T + 1.5), Color = trimColor, Material = Enum.Material.Metal, CFrame = origin * CFrame.new(x, SIDE_MID, FLOOR.Z / 2), Parent = parent })
	end

	-- floor-1 slab
	makePart({
		Name = "Platform",
		Size = FLOOR,
		Color = Palette.BaseFloor,
		Material = Enum.Material.SmoothPlastic,
		CFrame = origin,
		Parent = parent,
	})

	-- floor-2 slab at FLOOR2_Y, built as TWO segments (left/right of a back-center
	-- staircase opening) so players can walk up through the gap. The opening spans
	-- the back STAIR_GAP wide and ~STAIR_GAP deep at the +Z back edge.
	do
		local slabMidY = FLOOR2_Y - WALL_T / 2  -- center of the WALL_T-thick slab
		-- left + right strips (run full depth) flanking the central staircase well
		local sideW = (FLOOR.X - STAIR_GAP) / 2
		for _, sx in ipairs({ -1, 1 }) do
			makePart({
				Name = "Floor2Slab",
				Size = Vector3.new(sideW, WALL_T, FLOOR.Z),
				Color = Palette.BaseFloor,
				Material = Enum.Material.SmoothPlastic,
				CFrame = origin * CFrame.new(sx * (STAIR_GAP / 2 + sideW / 2), slabMidY, 0),
				Parent = parent,
			})
		end
		-- center strip in FRONT of the stairwell (connects the two side slabs); the
		-- stairwell OPENING runs from the well entrance back to the back wall so the
		-- whole staircase has headroom and the player emerges onto the side slabs.
		local frontLen = STAIR_ENTRANCE_LZ - (-FLOOR.Z / 2) -- from front edge to well entrance
		makePart({
			Name = "Floor2Slab",
			Size = Vector3.new(STAIR_GAP, WALL_T, frontLen),
			Color = Palette.BaseFloor,
			Material = Enum.Material.SmoothPlastic,
			CFrame = origin * CFrame.new(0, slabMidY, -FLOOR.Z / 2 + frontLen / 2),
			Parent = parent,
		})
	end

	-- roof on top of floor 2 + front header beams (entrance stays open below them)
	local roofY = 1 + SIDE_H + WALL_T / 2
	makePart({ Name = "Roof", Size = Vector3.new(FLOOR.X + 3, WALL_T, FLOOR.Z + 3), Color = trimColor, Material = Enum.Material.Metal, CFrame = origin * CFrame.new(0, roofY, 0), Parent = parent })
	makePart({ Name = "Header", Size = Vector3.new(FLOOR.X, 4, WALL_T), Color = trimColor, Material = Enum.Material.Metal, CFrame = origin * CFrame.new(0, 1 + WALL_H - 2, -FLOOR.Z / 2), Parent = parent })
	makePart({ Name = "Header", Size = Vector3.new(FLOOR.X, 4, WALL_T), Color = trimColor, Material = Enum.Material.Metal, CFrame = origin * CFrame.new(0, FLOOR2_Y + WALL_H - 2, -FLOOR.Z / 2), Parent = parent })

	-- optional low railing along the floor-2 open front (so players don't fall out)
	makePart({ Name = "Floor2Rail", Size = Vector3.new(FLOOR.X, 3, WALL_T * 0.7), Color = trimColor, Material = Enum.Material.Metal, CFrame = origin * CFrame.new(0, FLOOR2_Y + 1.5, -FLOOR.Z / 2), Parent = parent })

	-- the open front is local -Z (toward the dig center); put the incubator just
	-- outside it so players hatch at the front of their base.
	local incubator = buildIncubator(origin * CFrame.new(0, 0, -FLOOR.Z / 2 - 8), parent)

	-- BACK wall at +FLOOR.Z/2, built as TWO segments leaving a centered STAIR_GAP-wide
	-- gap for the staircase doorway. Spans both floors (full SIDE_H height).
	do
		local segW = (FLOOR.X - STAIR_GAP) / 2
		for _, sx in ipairs({ -1, 1 }) do
			makePart({
				Name = "BackWall",
				Size = Vector3.new(segW, SIDE_H, WALL_T),
				Color = wallColor,
				Material = Enum.Material.Brick,
				CFrame = origin * CFrame.new(sx * (STAIR_GAP / 2 + segW / 2), SIDE_MID, FLOOR.Z / 2),
				Parent = parent,
			})
		end
	end

	-- STAIRCASE in the back gap: steps at x=0 rising from the FRONT (low, room side)
	-- toward the BACK wall (high, at floor-2 level), enclosed by stairwell side walls
	-- so the lock can't be bypassed. The player emerges sideways onto the side slabs.
	do
		-- enclosing well side walls at the hole edges (x = +/- STAIR_GAP/2), from the
		-- well entrance back to the back wall, one floor tall.
		local wellLen = FLOOR.Z / 2 - STAIR_ENTRANCE_LZ
		for _, sx in ipairs({ -1, 1 }) do
			makePart({
				Name = "StairWell",
				Size = Vector3.new(WALL_T, WALL_H, wellLen),
				Color = wallColor,
				Material = Enum.Material.Brick,
				CFrame = origin * CFrame.new(sx * (STAIR_GAP / 2), 1 + WALL_H / 2, STAIR_ENTRANCE_LZ + wellLen / 2),
				Parent = parent,
			})
		end
		-- steps: s=1 lowest at the front, climbing toward the back wall up to floor 2
		for s = 1, STAIR_STEPS do
			local lz = STAIR_FRONT_LZ + (s - 1) * STAIR_STEP_D
			makePart({
				Name = "Step",
				Size = Vector3.new(STAIR_GAP, s * STAIR_STEP_H, STAIR_STEP_D),
				Color = trimColor,
				Material = Enum.Material.Metal,
				CFrame = origin * CFrame.new(0, 1 + (s * STAIR_STEP_H) / 2, lz),
				Parent = parent,
			})
		end
	end

	-- STAIRCASE BARRIER: a translucent red collidable wall blocking the bottom of the
	-- staircase doorway until the occupant owns all 12 floor-1 plots. Stored per slot.
	do
		local barrier = makePart({
			Name = "StairBarrier",
			Size = Vector3.new(STAIR_GAP, WALL_H - 2, WALL_T),
			Color = Palette.LockRed,
			Material = Enum.Material.Neon,
			Transparency = 0.5,
			-- blocks the stairwell ENTRANCE at the front (room side) so the well can't be entered
			CFrame = origin * CFrame.new(0, 1 + (WALL_H - 2) / 2, STAIR_ENTRANCE_LZ),
			Parent = parent,
		})
		barrier.CanCollide = true
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.new(0, 170, 0, 40)
		bb.StudsOffset = Vector3.new(0, 2, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 120
		bb.Parent = barrier
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.FredokaOne
		lbl.TextScaled = true
		lbl.Text = "🔒 Own all 12 plots"
		lbl.TextColor3 = Color3.fromRGB(255, 180, 180)
		lbl.TextStrokeTransparency = 0
		lbl.Parent = bb
		slotStairBarrier[slot] = { part = barrier, label = lbl }
	end

	return incubator
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
local FENCE_H = 28 -- jump height is ~7 studs, so this is comfortably un-jumpable
local function buildLaneFences()
	local wallZ = LANE_START + LANE_STEP / 2 -- zone1/2 (k=1) wall center z
	local wallHalfX = REBIRTH_WALL.X / 2
	for _, fence in ipairs({
		{ slot = 9, sign = -1, name = "ZoneFence_Left" },
		{ slot = 10, sign = 1, name = "ZoneFence_Right" },
	}) do
		local wallEnd = Vector3.new(fence.sign * wallHalfX, 0, wallZ) -- end of the wall on this side
		-- anchor the fence at the end-plot footprint CORNER nearest that wall end, so it
		-- meets the building at its edge instead of clipping through the plot interior.
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
		local length = math.sqrt(dx * dx + dz * dz)
		makePart({
			Name = fence.name,
			Size = Vector3.new(2, FENCE_H, math.max(length, 1)),
			Color = Palette.Fence,
			Material = Enum.Material.WoodPlanks,
			CFrame = CFrame.new((best.X + wallEnd.X) / 2, 1 + FENCE_H / 2, (best.Z + wallEnd.Z) / 2)
				* CFrame.Angles(0, math.atan2(dx, dz), 0),
			Parent = laneFolder,
		})
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
end

----------------------------------------------------------------- staircase gating
-- Show/hide the floor-2 staircase barrier for `slot`. The gate is BLOCKED (visible,
-- collidable, label shown) when the slot is empty or its occupant owns < 12 plots;
-- OPEN (invisible, non-collidable, label hidden) once the occupant owns >= 12 plots.
updateStaircase = function(slot: number)
	local rec = slotStairBarrier[slot]
	if not rec then
		return
	end
	local occupant = slotOccupant[slot]
	local plots = 0
	if occupant then
		local profile = PlayerData.get(occupant)
		plots = (profile and profile.Plots) or 0
	end
	local open = plots >= 12

	rec.part.CanCollide = not open
	rec.part.Transparency = open and 1 or 0.5
	rec.label.Visible = not open
end

-- public alias (lets other managers force a staircase refresh if needed)
function BaseManager.updateStaircase(slot: number)
	updateStaircase(slot)
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

	slotIncubator[slot] = buildBuilding(slot, origin, folder)
	rebuildSlotPodiums(slot, GameConfig.StartingPlots)
	buildBaseSign(slot, origin, folder)
	updateStaircase(slot) -- start blocked (slot unoccupied)
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

	BaseManager.updateRebirthGate(player)

	-- open/close the floor-2 staircase based on this occupant's plot count
	updateStaircase(slot)

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

	-- reset the floor-2 staircase to BLOCKED now that the slot is empty
	updateStaircase(slot)

	-- no-op gate refresh kept for API compatibility (shared lane handles gating)
	BaseManager.updateRebirthGate(slot)
end

----------------------------------------------------------------- updaters
-- Rebirth gating is now handled by the ONE shared central lane (buildSharedWall),
-- whose walls never block and rebirth the clicker based on THEIR own CurrentZone.
-- There are no longer any per-slot walls to refresh, so this is a harmless no-op
-- stub kept only because RebirthManager and assignBase still call it.
function BaseManager.updateRebirthGate(_target: Player | number)
end

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
			end
			task.wait(0.5)
		end
	end)
end

function BaseManager.getOrigin(player: Player): CFrame?
	local slot = playerSlot[player]
	if slot then
		return baseOrigin(slot)
	end
	return nil
end

-- World position of the player's incubator (for the "hatch at your incubator"
-- proximity check). Returns nil if the player has no slot / no incubator yet.
function BaseManager.getIncubatorPosition(player: Player): Vector3?
	local slot = playerSlot[player]
	if not slot then
		return nil
	end
	local inc = slotIncubator[slot]
	if not inc then
		return nil
	end
	return inc.Position
end

function BaseManager.init()
	basesFolder = Workspace:FindFirstChild(BASES_FOLDER_NAME) :: Folder
	if basesFolder then
		basesFolder:Destroy()
	end
	basesFolder = Instance.new("Folder")
	basesFolder.Name = BASES_FOLDER_NAME
	basesFolder.Parent = Workspace

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
