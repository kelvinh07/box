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
local ProximityPromptService = game:GetService("ProximityPromptService")
local PhysicsService = game:GetService("PhysicsService")
local InsertService = game:GetService("InsertService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local ZoneConfig = require(Shared.Config.ZoneConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Palette = require(Shared.Config.Palette)
local RarityColors = require(Shared.Config.RarityColors)
local BrainrotConfig = require(Shared.Config.BrainrotConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local Surface = require(Shared.Modules.Surface)
local Format = require(Shared.Modules.Format)
local BrainrotMath = require(Shared.Modules.BrainrotMath)
local Net = require(Shared.Modules.Net)
local PixelEgg = require(Shared.Modules.PixelEgg)

local PlayerData = require(script.Parent.PlayerData)
local BrainrotFactory = require(script.Parent.BrainrotFactory)
local MapBuilder = require(script.Parent.MapBuilder)
local EconomyManager = require(script.Parent.EconomyManager)
-- IncubationManager uses BaseManager via INJECTION (no top-level require of BaseManager),
-- so requiring it here for the ghost-incubator Buy click does NOT create a cycle.
local IncubationManager = require(script.Parent.IncubationManager)
-- InventoryManager has NO require of BaseManager (it only reads PlayerData + the factories),
-- so requiring it here for the placement-prompt router does NOT create a cycle.
local InventoryManager = require(script.Parent.InventoryManager)

local BaseManager = {}

----------------------------------------------------------------- layout config
local BASES_FOLDER_NAME = "PlayerBases"
local DIGLANE_FOLDER_NAME = "DigLane"
local MAX_SLOTS = 6 -- 6-player lobby (6 bases: 3 per side with a CENTER GAP for the Upgrade Shop); keep in sync with Players.MaxPlayers
-- CollectionService tag the client listens for to wire up the level-up panel, and
-- the click range for the per-brainrot ClickDetector that opens it.
local BRAINROT_TAG = "Brainrot"
local BRAINROT_CLICK_DISTANCE = 24
local LOBBY_RADIUS = 200       -- distance from dig center to each base (pushed back, courtyard room for the shared lane)
-- Per-side plot spacing is (ARC_SPAN_DEG - LOBBY_CENTER_GAP_DEG)/2 split across the 3 plots:
-- keep that band ~60-65° so adjacent same-side plots stay clearly GAPPED (it bunched them up
-- when the band dropped to ~49°). Middle-plaza width is driven by LOBBY_CENTER_GAP_DEG alone.
local ARC_SPAN_DEG = 204       -- how far the ring wraps; widened so each side's 3 plots get a clear little gap again (band back to ~62°). Higher = wider per-side spread (also creeps the tip plots forward toward the lane).
local LOBBY_CENTER_GAP_DEG = 80 -- empty wedge at the back-centre (bulge) — NO base sits here; "parts the seas" so the left trio sits left and the right trio sits right, opening a buildable plaza in the middle (reserved for a center building). Pulled back from 96 (was overdone) but still well above the original 56. Higher = more middle space (but narrows the per-side band, so bump ARC_SPAN_DEG to keep the side gaps).
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
-- wall WIDTH 124 >= dig-site width 120. The zone1/2 wall (k==1) uses this and is ALSO sealed at
-- the sides by buildLaneFences (the ZoneFence barriers), so it stays this width. Deeper walls
-- (k>=2) have NO side fences, so buildSharedWall spans THEM across the full lane (SEALED_WALL_HALF_X)
-- to stop loop-arounds — see buildSharedWall / buildWideWallFrame.
local REBIRTH_WALL = Vector3.new(124, 44, 6)
local SEG_SIZE = Vector3.new(120, 1, 120)     -- every dig square is this size (expanded for immersive zones; was 96)
local LANE_WALL_Y = 1 + REBIRTH_WALL.Y / 2   -- wall center height (sits on the ground)
local LANE_SEG_Y = 1.3                       -- dig-area slab center height
-- The shared dig lane starts near the half-circle CENTER (zone-1 dig site) and the
-- sites march OUTWARD (+Z) from there, a wall midway between each consecutive pair.
local LANE_START = 0                          -- z of the zone-1 dig site (~lobby center)
local LANE_STEP = SEG_SIZE.Z + 28             -- center-to-center between dig sites
-- Zone 1 (the LOBBY dig site) is ENLARGED and pushed toward the lobby (-Z), away from the
-- rebirth wall, to eat the empty courtyard grass. Only zone 1 differs; deeper zones keep
-- SEG_SIZE. Clearances (with the upgrade shops nudged back to SC.Z=-100, front edge ~z=-96):
-- grass border spans z[-90, 60] -> ~6 studs clear of the shops AND of wall-1's framing stones.
local ZONE1_DIG_SIZE = Vector3.new(150, 1, 138) -- bigger than SEG_SIZE (was a small patch in a big field)
local ZONE1_DIG_SHIFT_Z = -15                   -- push toward the lobby, away from the +Z zone wall
local ZONE1_DIG_HALF = 56                       -- moundable core half-extent (scaled up with the bigger slab)

-- LANE SIDE WALLS (see buildLaneSideWalls): two grass-topped DIRT CLIFFS flanking the
-- dig lane, running parallel to it (+Z). They TIGHTEN the playable width (the old
-- map-wide snow border was removed) by sitting just OUTSIDE the forest strip.
-- TUNE these to make the lane wider/thinner: lower INNER_X = thinner lane (but don't go
-- below the forest strip or trees clip through).
local LANE_SIDE_INNER_X = 100   -- inner face X of each wall; pulled IN close to the digsite for a COMPACT lane (well clear of the end-plot inner edge at x~140.5, so the cliff never clips a plot)
local LANE_SIDE_THICK = 20      -- wall thickness in X (semi-thick cliff body)
local LANE_SIDE_BODY_H = 40     -- dirt/mountain cliff height
local LANE_SIDE_CAP_H = 7       -- grass cap height on top
-- Half-width of the FENCE-LESS inter-zone walls (k>=2). The gate ENDS just INSIDE the stone
-- piles (which sit at the border) rather than running all the way through them — so no slab of
-- wall pokes THROUGH the stone out toward the border. The loop-around is still sealed: from the
-- gate end out to the border the (collidable) stone piles + the border cliff block the lane.
-- (Stone piles center at ~LANE_SIDE_INNER_X-7 with inner edge ~-14, so the gate overlaps them.)
local SEALED_WALL_HALF_X = LANE_SIDE_INNER_X - 14  -- = 86 (ends inside the stone, not at the border)
-- NEAR END (z): start RIGHT AT the zone1/2 FENCE LINE (~z72) so the side wall meets the
-- fence/anti-jump barrier ends with NO walk-around gap. (Previously z=100, which left an
-- open grass corner between the fence end and the wall start that players could slip
-- through.) The near stretch runs alongside the outer end-plot fronts; the forest tree
-- strip is pulled IN (buildForestTrees outerX) so trees don't clip the pushed-in wall.
local LANE_SIDE_Z_START = 72
-- The walls pre-extend to frame this MANY zones, not just the current ZoneConfig.MaxZone,
-- so FUTURE zones are already walled. Bump this (and the ground size) as you add zones.
local LANE_SIDE_PLANNED_ZONES = 12 -- frame all 12 zones down the lane (keep in sync with ZoneConfig.MaxZone + the MapBuilder ground size)

-- LOBBY ENCLOSURE WALL (buildLobbyWall): a THREE-TIER dirt-cliff + grass-cap rampart (SAME studded
-- border style as the lane side walls) that SURROUNDS the whole starting lobby. NOT a smooth arc —
-- a faceted horseshoe of STRAIGHT segments with ANGLED (chamfered) corners. Three stepped tiers
-- (short inner -> tall outer) make a natural amphitheater, and per-block height + per-vertex radial
-- JITTER (seeded) breaks up the uniformity so it reads like a natural cliff. The innermost tier's
-- two FRONT segments run along X and butt into the lane border walls' OUTER face PERPENDICULARLY
-- (both sides) WITHOUT poking through to the lane side; the +Z gap between them is the lane opening.
local LOBBY_WALL_THICK = 22
local LOBBY_WALL_CAP_H = 6
-- three stepped terraces (inner -> outer). `off` = radial push beyond the base path. The tiers sit
-- FLUSH (off ~< THICK) so there's NO gap between the 3 layers — one continuous stepped mass. `h` =
-- nominal height (jittered per block). `frontZ` = z of this tier's front runs — all PAST the end
-- plots (which reach z=97) so the wall never sits inside a plot. `front` = wrap the two front runs IN
-- to the lane border walls: inner + middle do (perpendicular join); the OUTER stops short (fades).
local LOBBY_WALL_TERRACES = {
	{ off = 0,  h = 24, frontZ = 110, front = true },  -- innermost: shortest, reaches the lane border
	{ off = 18, h = 52, frontZ = 132, front = true },  -- middle: reaches the lane border (flush behind inner)
	{ off = 36, h = 84, frontZ = 88,  front = false }, -- outermost: tallest, stops short of the lane (fades)
}
-- the terraces are made of CHUNKY blocks (few, wide) with BIG height jumps between them — bold + blocky,
-- not a smooth wall of tiny parts. SUBLEN up + H_JITTER up = the look; R_JITTER stays tiny so the flush
-- tiers don't drift apart into gaps.
local LOBBY_WALL_SUBLEN = 72   -- block length: FEW, wide blocks per terrace (was 26 — far too many)
local LOBBY_WALL_H_JITTER = 14 -- +/- per-block height — BIG steps between adjacent blocks (jagged, bold)
local LOBBY_WALL_R_JITTER = 2  -- tiny in/out wobble (kept so the tiers stay flush — no gaps)
local LOBBY_WALL_SEED = 7321   -- fixed so the jittered layout is identical every build
-- studded STONE rocks SPRINKLED on top of the wall ledges (a light scattering, like the reference).
-- Uses its OWN seeded rng so tuning rocks never changes the approved wall-block layout. Rocks are
-- chosen from all ledge tops and split EVENLY left/right so one side never crowds.
local LOBBY_WALL_ROCK_TOTAL = 16    -- total rocks, split evenly: LOBBY_WALL_ROCK_TOTAL/2 per side
local LOBBY_WALL_ROCK_MIN = 15      -- base WIDTH range (studs) of a rock = 3 overlapping stone blocks
local LOBBY_WALL_ROCK_MAX = 24

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
local slotLevelButtons: { [number]: { [number]: any } } = {}       -- [podiumIndex] = {part,label,click}
local slotSign: { [number]: TextLabel } = {}                       -- the name TextLabel (toggles text)
local slotCeilingHatch: { [number]: BasePart } = {}                -- floor-1 roof hatch over the ladder hole (closed until floor 2 unlocks)
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

-- The bases sit 3-per-side on the inward-facing arc with an EMPTY WEDGE in the middle
-- (LOBBY_CENTER_GAP_DEG, at the back-centre bulge) reserved for the Upgrade Shop building.
-- SLOT_ANGLE[slot] = that slot's arc angle (deg). Slots are assigned CENTRE-OUT, alternating
-- right/left, so early joiners sit nearest the gap/front. TIP_SLOT_* are the outermost (arc-tip)
-- slots the lane fences anchor to.
local SLOT_ANGLE: { [number]: number } = {}
local TIP_SLOT_LEFT, TIP_SLOT_RIGHT = 1, 1
do
	local perSide = math.floor(MAX_SLOTS / 2)
	local gapHalf = LOBBY_CENTER_GAP_DEG / 2
	local edge = ARC_SPAN_DEG / 2
	-- angle magnitudes from the gap edge (inner) out to the arc tip (outer)
	local mags = {}
	for i = 0, perSide - 1 do
		local f = (perSide <= 1) and 0 or i / (perSide - 1)
		mags[#mags + 1] = gapHalf + f * (edge - gapHalf)
	end
	-- assign centre-out, alternating +right / -left
	local slot = 1
	for _, mag in ipairs(mags) do
		SLOT_ANGLE[slot] = mag
		slot += 1
		if slot <= MAX_SLOTS then
			SLOT_ANGLE[slot] = -mag
			slot += 1
		end
	end
	-- tip slots = most-negative (left) / most-positive (right) angle
	for s, a in pairs(SLOT_ANGLE) do
		if a < SLOT_ANGLE[TIP_SLOT_LEFT] then TIP_SLOT_LEFT = s end
		if a > SLOT_ANGLE[TIP_SLOT_RIGHT] then TIP_SLOT_RIGHT = s end
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

-- inward-facing circular arc position; LookVector points TOWARD the dig center,
-- so local +Z (the open front + the dig lane) fans inward toward the courtyard
-- the half-circle opens onto, while local -Z is the solid back of the building.
local function baseOrigin(slot: number): CFrame
	local ang = math.rad(SLOT_ANGLE[slot] or 0)
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
-- The brainrot's slot is a single THICK gray platform (replaces the old purple podium + cyan
-- rim): footprint = the old rim (7x7), thickened to PODIUM_SIZE.Y (~2.3) tall. The brainrot
-- stands on its top; the LEVEL UP sign mounts on its inward side face (buildLevelButton).
local function buildPodium(cf: CFrame, parent: Instance): BasePart
	local podium = makePart({
		Name = "Podium",
		Size = BrainrotFactory.PODIUM_SIZE,
		Color = Palette.BaseTrim, -- solid dark-gray pedestal (brainrot/green plate/red sign pop against it)
		Material = Enum.Material.Plastic, -- matte studded
		CFrame = cf,
		Parent = parent,
	})
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
		bb.StudsOffset = Vector3.new(0, 11, 0) -- above the factory InfoLabel (raised for the bigger models)
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

-- Update a placed brainrot's InfoLabel income line ("[Variant]  $X/s") to its CURRENT income.
-- BrainrotFactory builds that label ONCE at place time, so without this it shows stale level-1
-- income forever (the bug where "$/s" never changes on level up). Idempotent; safe if absent.
local function setBrainrotInfoIncome(model: Model, entry: any, rebirthCount: number)
	local primary = model.PrimaryPart
	if not primary then
		return
	end
	local bb = primary:FindFirstChild("InfoLabel") :: BillboardGui?
	if not bb then
		return
	end
	local income = bb:FindFirstChild("Income") :: TextLabel?
	if not income then
		return
	end
	local cash = select(1, BrainrotMath.income(entry, rebirthCount))
	income.Text = ("[%s]  $%s/s"):format(entry.variant, Format.short(cash))
end

-- a green pressure plate in front of podium `idx`; stepping on it collects cash.
-- `cf` is the plate's world CFrame (its center, already lifted to the floor surface).
local function buildPlate(slot: number, idx: number, cf: CFrame, parent: Instance)
	local plate = makePart({
		Name = ("Plate_%d"):format(idx),
		Size = PLATE,
		Color = Palette.Plate,
		Material = Enum.Material.Plastic, -- matte studded (was Neon — glowed too much)
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

-- per-INDEX podium placement math (shared by real podiums AND the ghost next-slot podium so
-- they line up exactly). Brainrots line the two SIDE walls: 5 per side per floor, flanking
-- the central walkway. Plots 1-10 are floor 1, plots 11-20 are floor 2; within a floor the
-- first 5 hug the left (-X) wall and the next 5 hug the right (+X) wall.
-- Returns (side, lx, lz, baseLY) for podium index `i`.
local function podiumLocalAt(i: number): (number, number, number, number)
	local perFloor = GameConfig.FloorOnePlots        -- 10 per floor
	local half = math.floor(perFloor / 2)             -- 5 per side
	local floor = (i <= perFloor) and 1 or 2
	local j = (i - 1) % perFloor                       -- 0..9 within the floor
	local side = (j < half) and -1 or 1                -- first 5 = left wall, next 5 = right wall
	local row = j % half                               -- 0..4 along the depth
	local lx = side * (FLOOR.X / 2 - 6)                -- podium near the side wall (~+/-26)
	local lz = -28 + row * 14                          -- 5 podiums spread front->back (-28..28)
	local baseLY = (floor == 1) and 1 or FLOOR2_Y      -- floor surface
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
	ghost.Color = Palette.Wall   -- coral "locked" look, distinct from the gray real platforms
	ghost.Material = Enum.Material.Plastic
	ghost.Transparency = 0.5
	ghost.CanCollide = false

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

-- A physical "LEVEL UP" button standing on the INWARD (player-facing) edge of podium `idx`.
-- Its SurfaceGui shows the next-level cost; the gate-updater turns it RED when the occupant
-- can afford it and GRAY when they can't, hides it when no brainrot sits here, and shows
-- "MAX LEVEL" at the cap. Clicking it is handled server-side: it levels the brainrot on this
-- podium (server-validated via EconomyManager.levelBrainrot). `inward` is the world-space
-- direction from the podium toward the central walkway. Parented to the podium so it is
-- destroyed with it on a plot rebuild.
local function buildLevelButton(slot: number, idx: number, podium: BasePart, inward: Vector3)
	-- The LEVEL UP sign mounts flush on the platform's INWARD side face (the side facing the base's
	-- central walkway), vertically centered and a touch smaller than that face. The gate-updater
	-- drives its text ("LEVEL UP" + cost) / color / visibility; `inward` points toward the walkway.
	local SIGN_W = BrainrotFactory.PODIUM_SIZE.Z - 1   -- a bit narrower than the platform's 7-wide side
	local SIGN_H = BrainrotFactory.PODIUM_SIZE.Y - 0.5 -- a bit shorter than the platform's side height
	local SIGN_T = 0.3
	local pos = podium.Position + inward * (BrainrotFactory.PODIUM_SIZE.X / 2 + SIGN_T / 2 + 0.01)

	local btn = Instance.new("Part")
	btn.Name = ("LevelButton_%d"):format(idx)
	btn.Size = Vector3.new(SIGN_W, SIGN_H, SIGN_T)
	btn.CFrame = CFrame.lookAt(pos, pos + inward) -- Front face (-Z) points at the player
	btn.Anchored = true
	btn.CanCollide = false
	btn.CastShadow = false
	btn.Material = Enum.Material.SmoothPlastic
	btn.Color = Color3.fromRGB(108, 108, 118)
	btn.Transparency = 1 -- hidden until the gate-updater reveals it (only when a brainrot sits here)
	btn.Parent = podium

	local surf = Instance.new("SurfaceGui")
	surf.Name = "Face"
	surf.Face = Enum.NormalId.Front
	surf.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surf.PixelsPerStud = 40
	surf.LightInfluence = 0
	surf.MaxDistance = 80
	surf.Parent = btn
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.TextColor3 = Color3.new(1, 1, 1)
	lbl.TextStrokeTransparency = 0
	lbl.Text = ""
	lbl.Parent = surf

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 0 -- enabled by the gate-updater when occupied
	click.Parent = btn
	click.MouseClick:Connect(function(clicker: Player)
		if clicker ~= slotOccupant[slot] then
			return
		end
		local id = brainrotIdAtPodium(slot, idx)
		if not id then
			return
		end
		local r = EconomyManager.levelBrainrot(clicker, id)
		if r and r.ok == false and r.reason then
			Net.getEvent("Notify"):FireClient(clicker, { title = "Level Up", text = r.reason, color = "Legendary" })
		end
	end)

	slotLevelButtons[slot] = slotLevelButtons[slot] or {}
	slotLevelButtons[slot][idx] = { part = btn, label = lbl, click = click }
end

-- (re)build the podium grid + plates for a given slot's plot count
-- Tag carried by every inventory placement prompt (podium + incubator). The client
-- (InventoryClient) finds them by this tag to toggle Enabled/ActionText by the equipped
-- tool; the server prompt router (BaseManager.init) validates + routes the action.
local INV_PROMPT_TAG = "InvPrompt"

-- Attach the "place / swap / remove brainrot" ProximityPrompt to a podium. Starts DISABLED:
-- the client enables it contextually (holding a brainrot, or an occupied podium for Remove).
local function attachPodiumPrompt(slot: number, idx: number, podium: BasePart)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PodiumPrompt"
	prompt.ActionText = "Place"
	prompt.ObjectText = "Brainrot Slot"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 16
	prompt.Enabled = false
	prompt:SetAttribute("PromptKind", "Podium")
	prompt:SetAttribute("Slot", slot)
	prompt:SetAttribute("PodiumIndex", idx)
	prompt:SetAttribute("Occupied", false)
	prompt.Parent = podium
	CollectionService:AddTag(prompt, INV_PROMPT_TAG)
end

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
	slotLevelButtons[slot] = {} -- the button parts are children of the podiums (destroyed above)

	count = math.clamp(count, 0, GameConfig.MaxPlots)
	local origin = baseOrigin(slot)
	for i = 1, count do
		local side, lx, lz, baseLY = podiumLocalAt(i)

		local podium = buildPodium(
			origin * CFrame.new(lx, baseLY + BrainrotFactory.PODIUM_SIZE.Y / 2, lz),
			folder
		)
		table.insert(slotPodiums[slot], podium)
		-- pressure plate just INWARD of the podium (toward the central walkway); offset 7 so it sits
		-- flush in FRONT of the now-wider 7-stud platform instead of tucking under its edge
		buildPlate(slot, i, origin * CFrame.new(lx - side * 7, baseLY + PLATE.Y / 2, lz), folder)
		-- a "LEVEL UP" button on the podium's inward (player-facing) edge
		buildLevelButton(slot, i, podium, origin:VectorToWorldSpace(Vector3.new(-side, 0, 0)).Unit)
		-- the E-prompt to place / swap / remove a brainrot on this podium
		attachPodiumPrompt(slot, i, podium)
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

-- World-space AABB (center, size) of ONLY a model's rendered parts. The imported brainrot
-- models carry an oversized INVISIBLE RootPart whose pivot sits 1–3 studs BELOW the visible
-- animal, so Model:GetBoundingBox()/the pivot can't tell us where the feet are. Measuring the
-- visible parts lets us drop the rendered model's bottom onto the podium and center it on top,
-- instead of floating it up by the RootPart's overhang (the old behavior).
local function visibleAABB(model: Model): (Vector3, Vector3)
	local min: Vector3?, max: Vector3? = nil, nil
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.95 and not (d == model.PrimaryPart and d.Name == "RootPart") then
			local cf, half = d.CFrame, d.Size / 2
			for sx = -1, 1, 2 do
				for sy = -1, 1, 2 do
					for sz = -1, 1, 2 do
						local c = (cf * CFrame.new(sx * half.X, sy * half.Y, sz * half.Z)).Position
						if not min then
							min, max = c, c
						else
							min = Vector3.new(math.min(min.X, c.X), math.min(min.Y, c.Y), math.min(min.Z, c.Z))
							max = Vector3.new(math.max(max.X, c.X), math.max(max.Y, c.Y), math.max(max.Z, c.Z))
						end
					end
				end
			end
		end
	end
	if not min or not max then
		local cf, s = model:GetBoundingBox()
		return cf.Position, s
	end
	return (min + max) / 2, (max - min)
end

-- place a single brainrot model onto a podium for `slot`. `forcedIndex` pins it to a
-- SPECIFIC podium (used when placing/loading a brainrot at its saved `entry.podium`);
-- when nil it falls back to the next free podium.
local function placeBrainrotForSlot(slot: number, player: Player, entry: any, forcedIndex: number?)
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

	local targetIndex = forcedIndex
	if targetIndex then
		-- explicit podium requested: bail if out of range or already taken
		if targetIndex < 1 or targetIndex > #podiums or occupied[targetIndex] then
			return
		end
	else
		for i = 1, #podiums do
			if not occupied[i] then
				targetIndex = i
				break
			end
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

	-- Sit the brainrot ON the podium and translate (only) so its BOTTOM rests on the podium top,
	-- centered. The small sink guarantees contact (no hairline gap) — per design we'd rather it
	-- touch than float.
	--   VERTICAL: ground on the FULL bounding box bottom. These imported models render meshes that
	-- OVERFLOW their visible part-boxes downward (legs / lower body), so a visible-only AABB sits
	-- too high and the model sinks to its middle. The full bbox includes the bounding RootPart/Vfx
	-- parts, which DO bound the true visual extent, so its bottom is the model's real bottom.
	--   HORIZONTAL: still center on the VISIBLE model (the full bbox can be pulled off-center by Vfx).
	local BRAINROT_SINK = 0.2
	local podiumTop = podium.Position.Y + podium.Size.Y / 2 - BRAINROT_SINK
	local fullCf, fullSize = model:GetBoundingBox()
	local center = visibleAABB(model)
	local g = model:GetPivot() -- keep the model's authored orientation; only translate it
	local grounded = Vector3.new(
		podium.Position.X + (g.Position.X - center.X),
		podiumTop + (g.Position.Y - (fullCf.Y - fullSize.Y / 2)),
		podium.Position.Z + (g.Position.Z - center.Z)
	)
	-- translate ONLY: forcing an identity CFrame here would yaw the model about its off-center
	-- RootPart pivot (the imported pivots carry an authored yaw) and slide it off the podium edge.
	model:PivotTo(g.Rotation + grounded)

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

	-- gentle idle SPIN in place — rotates about the vertical axis through the podium center while
	-- staying grounded (the old version added a sin() bob, which is what made them float/bob).
	local spinAxis = Vector3.new(podium.Position.X, grounded.Y, podium.Position.Z)
	local pivotOffset = grounded - spinAxis -- the pivot's horizontal offset from the spin axis
	local baseRot = g.Rotation -- start from the model's authored facing, then yaw on top of it
	task.spawn(function()
		local t = 0
		while model.Parent and model.PrimaryPart do
			t += 0.04
			local rot = CFrame.Angles(0, t, 0)
			model:PivotTo(CFrame.new(spinAxis + rot:VectorToWorldSpace(pivotOffset)) * rot * baseRot)
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

-- Place an owned brainrot onto a SPECIFIC podium index (called by EconomyManager.placeBrainrot
-- after it validates ownership / the podium being free). The data side (entry.placed/podium)
-- is owned by EconomyManager; this only spawns the world model.
function BaseManager.placeBrainrotAt(player: Player, entry: any, podiumIndex: number)
	local slot = playerSlot[player]
	if not slot then
		return
	end
	placeBrainrotForSlot(slot, player, entry, podiumIndex)
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
		local profile = PlayerData.get(player)
		setBrainrotInfoIncome(model, entry, (profile and profile.Rebirths) or 0)
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

	-- only PLACED brainrots sit on podiums (each on its saved entry.podium); the rest are
	-- held in the inventory as Tools.
	for _, entry in ipairs(profile.Collection) do
		if entry.placed and entry.podium then
			placeBrainrotForSlot(slot, player, entry, entry.podium)
		end
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

-- Build ONE incubator unit at floor-XZ `cf`, wrapped in a Model so it can be reparented
-- OUT of Workspace to HIDE it. Clones the imported glass display-case model at
-- ServerStorage.EggIncubatorModel (security-audited, 0 scripts), scaled to stand on the
-- floor; if it's missing (e.g. a place built from src that doesn't ship it) it FALLS BACK to
-- the old procedural metal base + glass-ball dome. Returns a record driven by
-- setIncubatorState. The ClickDetector buys the next incubator when shown as a ghost. The
-- record also carries the glass EGG ANCHOR (eggCF/eggHeight) so a hatching egg is shown
-- INSIDE the case — see updateSlotEggs.
local INCUBATOR_MODEL_NAME = "EggIncubatorModel"
local INCUBATOR_TARGET_H = 9 -- the imported case is scaled to stand ~this tall
local INCUBATOR_EGG_VOX = 10 -- voxel resolution of the in-case egg (chunky pixels, cheap)

-- world-space AABB extents (Vector3) of a single (possibly rotated) BasePart
local function partWorldExtent(p: BasePart): Vector3
	local pcf, s = p.CFrame, p.Size
	local r, u, l = pcf.RightVector, pcf.UpVector, pcf.LookVector
	return Vector3.new(
		math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(l.X) * s.Z,
		math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(l.Y) * s.Z,
		math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(l.Z) * s.Z
	)
end

-- the translucent glass tube of a cloned case (the only see-through part = where the egg goes)
local function findGlass(root: Instance): BasePart?
	local best: BasePart? = nil
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency > 0.1 and d.Transparency < 0.95 then
			if (not best) or d.Size.Magnitude > (best :: BasePart).Size.Magnitude then
				best = d
			end
		end
	end
	return best
end

-- the on-incubator progress-bar colours (match the old HUD: cyan while hatching, green when ready)
local INC_BAR_PROGRESS = Color3.fromRGB(70, 205, 255)
local INC_BAR_READY = Color3.fromRGB(70, 235, 95)
-- in-plane spin of the on-incubator screen GUI (tune if the bar/text ever reads rotated)
local SCREEN_SPIN = CFrame.Angles(0, 0, 0)

-- Mount a progress-bar + countdown SurfaceGui on the TOP face of an invisible "host" part laid
-- right over the incubator's dark front SCREEN plate (`faceCF`/`faceSize` — the black bar the user
-- pointed to). Returns the fill Frame + countdown TextLabel; updateIncubatorProgress drives them.
local function buildProgressScreen(parent: Instance, faceCF: CFrame, faceSize: Vector3): (Frame, TextLabel)
	local host = Instance.new("Part")
	host.Name = "ProgressScreen"
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.Transparency = 1 -- invisible; the dark model plate underneath is the visible "screen"
	host.Size = Vector3.new(faceSize.X, math.max(faceSize.Y, 0.08), faceSize.Z)
	-- float just in front of the dark plate (along its outward normal) so the bar isn't z-fought
	-- or hidden in the bezel recess; SCREEN_SPIN rotates the content in-plane if it reads rotated.
	host.CFrame = faceCF * CFrame.new(0, 0.12, 0) * SCREEN_SPIN
	host.Parent = parent

	local sg = Instance.new("SurfaceGui")
	sg.Name = "Screen"
	sg.Face = Enum.NormalId.Top
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 80
	sg.LightInfluence = 0 -- always readable through the dim incubator glow
	sg.Brightness = 1.5
	sg.Parent = host

	-- progress bar (fills the left ~64% of the screen)
	local bg = Instance.new("Frame")
	bg.Name = "BarBg"
	bg.AnchorPoint = Vector2.new(0, 0.5)
	bg.Position = UDim2.new(0.04, 0, 0.5, 0)
	bg.Size = UDim2.new(0.64, 0, 0.42, 0)
	bg.BackgroundColor3 = Color3.fromRGB(15, 16, 26)
	bg.BorderSizePixel = 0
	bg.Parent = sg
	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(1, 0)
	bgCorner.Parent = bg
	local bgStroke = Instance.new("UIStroke")
	bgStroke.Thickness = 2
	bgStroke.Color = Color3.fromRGB(0, 0, 0)
	bgStroke.Parent = bg

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = INC_BAR_PROGRESS
	fill.BorderSizePixel = 0
	fill.Parent = bg
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	-- countdown seconds, just to the RIGHT of the bar
	local txt = Instance.new("TextLabel")
	txt.Name = "Countdown"
	txt.AnchorPoint = Vector2.new(1, 0.5)
	txt.Position = UDim2.new(0.99, 0, 0.5, 0)
	txt.Size = UDim2.new(0.28, 0, 0.8, 0)
	txt.BackgroundTransparency = 1
	txt.Font = Enum.Font.FredokaOne
	txt.Text = ""
	txt.TextColor3 = Color3.fromRGB(255, 255, 255)
	txt.TextStrokeTransparency = 0
	txt.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	txt.TextScaled = true
	txt.TextXAlignment = Enum.TextXAlignment.Right
	txt.Parent = sg

	return fill, txt
end

local function buildIncubator(slot: number, cf: CFrame, index: number): any
	local home = slotFolder[slot]
	local unit = Instance.new("Model")
	unit.Name = ("IncubatorUnit_%d"):format(index)
	unit.Parent = home

	local glass: BasePart
	local solids: { { p: BasePart, t: number } } = {}
	local screenFaceCF: CFrame? = nil -- the dark front "screen" plate the progress bar mounts on
	local screenFaceSize: Vector3? = nil

	local tmpl = ServerStorage:FindFirstChild(INCUBATOR_MODEL_NAME)
	if tmpl and tmpl:IsA("Model") then
		-- IMPORTED glass display-case: anchor, scale to ~target height, stand on the floor, and
		-- FLIP 180° so its front "screen" faces the player (the user's incubators faced the wall).
		local case = (tmpl :: Model):Clone()
		case.Name = "Case"
		for _, d in ipairs(case:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		local _, s0 = case:GetBoundingBox()
		if s0.Y > 0.01 then
			pcall(function() case:ScaleTo(INCUBATOR_TARGET_H / s0.Y) end)
		end
		case:PivotTo(cf * CFrame.new(0, FLOOR.Y / 2, 0) * CFrame.Angles(0, math.pi, 0)) -- floor + 180° flip
		case.Parent = unit
		glass = findGlass(case) :: BasePart
		for _, d in ipairs(case:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(solids, { p = d, t = d.Transparency })
				d.CanCollide = (d ~= glass) -- glass stays walk-through; the rest are solid
				-- the dark, near-black front "screen" plate (where the progress bar mounts)
				if d.Color.R < 0.3 and d.Color.G < 0.35 and d.Color.B < 0.4 then
					screenFaceCF, screenFaceSize = d.CFrame, d.Size
				end
			end
		end
	else
		-- PROCEDURAL fallback (old look): metal base + glass ball dome + a dark front screen plate.
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
		glass = dome
		solids = { { p = base, t = 0 }, { p = dome, t = 0.4 } }
		local plate = makePart({
			Name = "ScreenPlate",
			Size = Vector3.new(2.6, 0.14, 1.1),
			Color = Color3.fromRGB(20, 22, 34),
			Material = Enum.Material.SmoothPlastic,
			NoStuds = true,
			CanCollide = false,
			CFrame = base.CFrame * CFrame.new(0, -1.4, 2.05) * CFrame.Angles(math.rad(-28), 0, 0),
			Parent = unit,
		})
		screenFaceCF, screenFaceSize = plate.CFrame, plate.Size
	end

	-- EGG ANCHOR: the centre of the glass tube. The egg HEIGHT is a FIXED fit derived from the
	-- glass interior — identical for every incubator and every rarity — so any placed egg is
	-- normalised to the same size (only its colour varies). See updateSlotEggs.
	local ge = partWorldExtent(glass)
	local eggHeight = math.min(ge.Y * 0.6, math.min(ge.X, ge.Z) * 0.92)
	local eggCF = CFrame.new(glass.Position)

	-- DIM, near-neutral glow: just enough to read the egg's true rarity colour through the
	-- glass without the case acting like a bright lamp (the user wanted incubation toned down).
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 250, 235)
	light.Brightness = 0.5
	light.Range = 9
	light.Parent = glass

	-- floating label, anchored just above the case
	local caseCF, caseSize = unit:GetBoundingBox()
	local labelAnchor = Instance.new("Part")
	labelAnchor.Name = "LabelAnchor"
	labelAnchor.Size = Vector3.new(1, 1, 1)
	labelAnchor.Transparency = 1
	labelAnchor.Anchored = true
	labelAnchor.CanCollide = false
	labelAnchor.CanQuery = false
	labelAnchor.CFrame = CFrame.new(glass.Position.X, caseCF.Position.Y + caseSize.Y / 2 + 2, glass.Position.Z)
	labelAnchor.Parent = unit
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 150, 0, 40)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 140
	bb.Parent = labelAnchor
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.Text = "🥚 INCUBATOR"
	lbl.TextColor3 = Color3.fromRGB(150, 230, 255)
	lbl.TextStrokeTransparency = 0
	lbl.Parent = bb

	-- on-incubator progress bar + countdown (mounted on the dark front screen plate, if present)
	local progFill: Frame? = nil
	local progText: TextLabel? = nil
	if screenFaceCF and screenFaceSize then
		progFill, progText = buildProgressScreen(unit, screenFaceCF, screenFaceSize)
	end

	-- ClickDetector: GHOST → buys the next incubator; REAL + READY → collects the hatched brainrot
	-- (the old bottom-right COLLECT button is gone — progress + collect now live on the incubator).
	local rec
	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 0
	click.Parent = glass
	click.MouseClick:Connect(function(clicker: Player)
		if not rec or clicker ~= slotOccupant[slot] then
			return
		end
		local res
		if rec.mode == "ghost" then
			res = IncubationManager.unlockIncubator(clicker)
		elseif rec.mode == "real" and rec.ready then
			res = IncubationManager.collect(clicker, index)
		end
		if res and res.ok == false and res.reason then
			Net.getEvent("Notify"):FireClient(clicker, { title = "Incubator", text = res.reason, color = "Legendary" })
		end
	end)

	-- the E-prompt to place a HELD egg into this incubator. Starts disabled; the client
	-- enables it only while the player holds an egg tool. Server routes to IncubationManager.placeEgg.
	local eggPrompt = Instance.new("ProximityPrompt")
	eggPrompt.Name = "IncubatorPrompt"
	eggPrompt.ActionText = "Place Egg"
	eggPrompt.ObjectText = "Incubator"
	eggPrompt.KeyboardKeyCode = Enum.KeyCode.E
	eggPrompt.RequiresLineOfSight = false
	eggPrompt.MaxActivationDistance = 18
	eggPrompt.Enabled = false
	eggPrompt:SetAttribute("PromptKind", "Incubator")
	eggPrompt:SetAttribute("Slot", slot)
	eggPrompt:SetAttribute("IncubatorIndex", index)
	eggPrompt.Parent = glass
	CollectionService:AddTag(eggPrompt, INV_PROMPT_TAG)

	rec = {
		model = unit, home = home, index = index, pos = cf.Position,
		glass = glass, glassT = glass.Transparency, solids = solids,
		light = light, label = lbl, click = click,
		eggCF = eggCF, eggHeight = eggHeight, eggModel = nil, eggRarity = nil,
		mode = "hidden", ready = false, progFill = progFill, progText = progText,
	}
	return rec
end

-- Drive an incubator unit's look: "real" (unlocked, solid + glowing), "ghost" (buyable,
-- translucent + Buy label + clickable) or "hidden" (reparented out of Workspace). The
-- hatching egg itself is shown/hidden separately by updateSlotEggs.
local function setIncubatorState(rec: any, state: string, cost: number?, canAfford: boolean?)
	rec.mode = state
	if state ~= "real" then
		-- leaving the active state: drop the collect-ready flag + clear the on-model progress bar
		rec.ready = false
		if rec.progFill then rec.progFill.Size = UDim2.new(0, 0, 1, 0) end
		if rec.progText then rec.progText.Text = "" end
	end
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
		for _, s in ipairs(rec.solids) do
			s.p.Transparency = s.t
			s.p.CanCollide = (s.p ~= rec.glass)
		end
		rec.light.Enabled = true
		-- the floating label + the ClickDetector range for REAL incubators are owned by
		-- updateIncubatorProgress (idle / hatching / ready-to-collect) — don't set them here.
	else -- ghost
		for _, s in ipairs(rec.solids) do
			s.p.Transparency = math.max(s.t, 0.7)
			s.p.CanCollide = false
		end
		rec.glass.Transparency = 0.92
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
	-- zone1/2 (k==1) keeps the normal gate width (its sides are sealed by buildLaneFences).
	-- deeper boundaries (k>=2): the gate ends just INSIDE the stone piles (no wall pokes through the
	-- stone toward the border); the collidable stone piles + border cliff seal the rest of the lane.
	local wallWidth = (k == 1) and REBIRTH_WALL.X or (2 * SEALED_WALL_HALF_X)
	local wall = makePart({
		Name = ("RebirthWall_%d"):format(k),
		Size = Vector3.new(wallWidth, REBIRTH_WALL.Y, REBIRTH_WALL.Z),
		Color = Palette.ZoneWall,
		Material = Enum.Material.Plastic,
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
	surf.MaxDistance = 0 -- 0 = NO distance limit: the wall text is readable from anywhere, not only up close
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

	-- BIGGER text, no arrow: the zone name on top + the cost to break below
	local title = mkLabel(0.1, 0.38)
	title.TextColor3 = Color3.fromRGB(255, 220, 120)
	title.Text = ZoneConfig.get(k + 1).DisplayName
	local line = mkLabel(0.55, 0.3)
	line.Text = ("$%s to break"):format(Format.short(ZoneConfig.unlockCash(k + 1)))

	-- Clicking the wall in front of your CURRENT zone spends CASH to break it and advance
	-- into zone k+1 (zone progression is decoupled from rebirth). Walls re-lock on rebirth
	-- (which resets CurrentZone to 1). Only the occupant of zone k can break wall k.
	click.MouseClick:Connect(function(clicker: Player)
		local profile = PlayerData.get(clicker)
		if not profile or profile.CurrentZone ~= k then
			return
		end
		local nextZone = k + 1
		if nextZone > ZoneConfig.MaxZone then
			return
		end
		local cost = ZoneConfig.unlockCash(nextZone)
		if profile.Cash < cost then
			Net.getEvent("Notify"):FireClient(clicker, {
				title = "Wall Locked",
				text = ("Need $%s to break this wall."):format(Format.short(cost)),
				color = "Legendary",
			})
			return
		end
		profile.Cash -= cost
		profile.CurrentZone = nextZone
		PlayerData.markDirty(clicker)
		PlayerData.push(clicker)
		BaseManager.applyZoneGate(clicker) -- regroup so the just-broken wall now lets them pass
		Net.getEvent("Notify"):FireClient(clicker, {
			title = "Zone Unlocked!",
			text = ("Welcome to %s!"):format(ZoneConfig.get(nextZone).DisplayName),
			color = "Legendary",
		})
	end)
end

-- a physical dig area for `zone` at world position `pos`, styled exactly like the
-- central green dig square (same size + grass) with a "DigPatch" slab + sign.
-- `segOverride` / `digHalfOverride` let the LOBBY dig site (zone 1) be bigger than the
-- standard SEG_SIZE / 40-stud core (see the ZONE1_DIG_* constants); nil => the defaults.
local function buildZoneArea(zone: number, pos: Vector3, farDir: Vector3, parent: Instance, segOverride: Vector3?, digHalfOverride: number?)
	local zoneData = ZoneConfig.get(zone)
	if not zoneData then
		return
	end
	local seg = segOverride or SEG_SIZE
	local digHalf = digHalfOverride or 40

	-- rotate the pad/border to line up squarely with the lane direction
	local yaw = math.atan2(farDir.X, farDir.Z)
	local rot = CFrame.Angles(0, yaw, 0)

	local theme = zoneData.Theme
	local isForest = theme == "Forest"
	-- grassy themes keep a green dig plate (mounds sit on grass). Cherry Blossom uses a solid PINK floor
	-- (solidFloor below) with the petal carpet on top, so it is NOT grassy.
	local isGrassy = isForest or theme == "Park" -- Park is a grassy zone (grass floor + checker)
	-- Themes with a SOLID-colour floor that FILLS the whole lane segment (no checker): Desert (sand)
	-- and The Glaziers (ice). nil for grass/forest zones (which keep the small green checker frame).
	local solidFloor: Color3? = nil
	if theme == "Desert" then
		solidFloor = Palette.Sand
	elseif theme == "Glaciers" then
		solidFloor = Palette.Ice
	elseif theme == "Cavern" then
		solidFloor = Palette.CavernFloor -- #1B3444 dark cavern floor (glowing decor pops against it)
	elseif theme == "CherryBlossom" then
		solidFloor = Palette.CherryFloor -- solid PINK floor; the petal carpet adds texture on top
	elseif theme == "Haunted" then
		solidFloor = Palette.HauntedFloor -- #6B5D2F murky olive graveyard floor (zone 7)
	elseif theme == "City" then
		solidFloor = Palette.CityRoad -- dark asphalt — the two-way road floor (zone 8)
	end

	-- Dig plate colour: FOREST = grassy clearing, solid-floor zones = their sand/ice colour, else =
	-- dark brown earth (darker than the tan client mounds). The client scatters tan dirt mounds on top.
	local digColor = (isGrassy and Palette.Grass) or solidFloor or Palette.DigField

	if zone == 1 then
		-- LOBBY (zone 1): KEEP the original framed dig plate — a SEG_SIZE pad sitting in the lobby
		-- grass with a slightly-larger grass frame under it (the lobby has shops / spawn / a path
		-- around it, so the dig site stays a defined pad here, not the whole open lobby).
		local borderSize = solidFloor
			and Vector3.new(2 * LANE_SIDE_INNER_X + 2, 0.6, LANE_STEP - 4)
			or (seg + Vector3.new(12, -0.4, 12))
		local zoneBorder = makePart({
			Name = "ZoneBorder",
			Size = borderSize,
			Color = solidFloor or Palette.Grass,
			CFrame = CFrame.new(pos.X, LANE_SEG_Y - 0.2, pos.Z) * rot,
			Parent = parent,
		})
		if not solidFloor then
			CollectionService:AddTag(zoneBorder, "GrassSurface")
		end
		local dirt = makePart({
			Name = ("Zone%dDig"):format(zone),
			Size = seg,
			Color = digColor,
			CFrame = CFrame.new(pos.X, LANE_SEG_Y, pos.Z) * rot,
			Parent = parent,
		})
		CollectionService:AddTag(dirt, "DigPatch")
		dirt:SetAttribute("Zone", zone)
		dirt:SetAttribute("DigHalf", digHalf)
		if isGrassy then
			CollectionService:AddTag(dirt, "GrassSurface")
		end
	else
		-- ZONES 2+: the WHOLE zone is ONE uniform floor AND the dig site — a single slab spanning
		-- cliff-to-cliff (±LANE_SIDE_INNER_X) and wall-to-wall (LANE_STEP), at one level. There is no
		-- separate raised "dig square" any more: the client (DigSite.scatterPatch) scatters mounds
		-- across the ENTIRE slab and simply avoids decoration via the DigExclusion markers. This is
		-- why every themed decoration that stands on the floor now drops a no-dig marker.
		local floorSize = Vector3.new(2 * LANE_SIDE_INNER_X + 2, SEG_SIZE.Y, LANE_STEP - 4)
		local dirt = makePart({
			Name = ("Zone%dDig"):format(zone),
			Size = floorSize,
			Color = digColor,
			CFrame = CFrame.new(pos.X, LANE_SEG_Y, pos.Z) * rot,
			Parent = parent,
		})
		CollectionService:AddTag(dirt, "DigPatch")
		dirt:SetAttribute("Zone", zone)
		-- LEGACY: DigHalf used to bound the mound core; the whole slab is diggable now (kept for back-compat).
		dirt:SetAttribute("DigHalf", digHalf)
		if isGrassy then
			-- match the surrounding grass: studded + the 6x6 two-green checker overlay
			CollectionService:AddTag(dirt, "GrassSurface")
		end
		-- solid-floor zones (Desert / Glaciers / Cavern / Cherry) leave the floor a flat colour (no checker)
	end

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
	-- a PHYSICAL name plate mounted on the FRONT TOP FRAME (the floor-1 header), facing the
	-- courtyard, so everyone can read whose base it is. assignBase/freeBase set its text.
	local plate = makePart({
		Name = "NamePlate",
		Size = Vector3.new(FLOOR.X * 0.62, 5, 0.6),
		Color = Palette.BaseTrim,
		Material = Enum.Material.Metal,
		NoStuds = true,
		CFrame = origin * CFrame.new(0, 1 + WALL_H - 2, -FLOOR.Z / 2 - WALL_T / 2 - 0.3),
		Parent = parent,
	})
	local sg = Instance.new("SurfaceGui")
	sg.Name = "NameGui"
	sg.Face = Enum.NormalId.Front -- the part's -Z face = the building front (faces the courtyard)
	sg.CanvasSize = Vector2.new(900, 130)
	sg.LightInfluence = 0
	sg.Parent = plate
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.Text = ("OPEN PLOT %d"):format(slot)
	lbl.TextColor3 = Color3.fromRGB(120, 220, 255)
	lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	lbl.TextStrokeTransparency = 0.3
	lbl.Parent = sg
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
	local accent = Palette.Cyan -- matte (non-neon) accent for the walkway + wall trim

	local f2 = Instance.new("Folder")
	f2.Name = "Floor2"
	f2.Parent = parent
	slotFloor2[slot] = f2

	-- a SOLID side wall for one floor (NO windows) + a matte accent baseboard stripe.
	-- `dest` routes the parts to floor 1 (parent) or floor 2 (f2).
	local function sideWall(x: number, baseLY: number, dest: Instance)
		makePart({ Name = "Wall", Size = Vector3.new(WALL_T, WALL_H, FLOOR.Z), Color = wallColor, Material = Enum.Material.Brick, CFrame = origin * CFrame.new(x, baseLY + WALL_H / 2, 0), Parent = dest })
		makePart({ Name = "WallTrim", Size = Vector3.new(WALL_T + 0.4, 1.4, FLOOR.Z), Color = accent, CFrame = origin * CFrame.new(x, baseLY + 0.7, 0), Parent = dest })
	end

	-- side walls + corner pillars, split per floor so the upper halves can hide.
	local pillarH = WALL_H + WALL_T
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (FLOOR.X / 2)
		sideWall(x, 1, parent)       -- floor 1
		sideWall(x, FLOOR2_Y, f2)    -- floor 2 (walls hidden until ladder)
		for _, lz in ipairs({ -FLOOR.Z / 2, FLOOR.Z / 2 }) do
			makePart({ Name = "Pillar", Size = Vector3.new(WALL_T + 1.5, pillarH, WALL_T + 1.5), Color = trimColor, Material = Enum.Material.Metal, CFrame = origin * CFrame.new(x, 1 + pillarH / 2, lz), Parent = parent })
			makePart({ Name = "Pillar", Size = Vector3.new(WALL_T + 1.5, pillarH, WALL_T + 1.5), Color = trimColor, Material = Enum.Material.Metal, CFrame = origin * CFrame.new(x, FLOOR2_Y + pillarH / 2, lz), Parent = f2 })
		end
	end

	-- floor slab + a central WALK PATH runway down the middle (front opening -> back wall),
	-- flanking the two podium rows. Matte studded — a clean accent, not a glow.
	local function walkway(baseLY: number, dest: Instance)
		-- run from near the front opening to JUST BEFORE the ladder hole, so the floor-2
		-- walkway never covers the hole (which would block climbing up to floor 2).
		local backZ = LADDER_HOLE_FRONT_LZ - 2
		local frontZ = -FLOOR.Z / 2 + 2
		local len = backZ - frontZ
		local cz = (backZ + frontZ) / 2
		makePart({ Name = "WalkPath", Size = Vector3.new(12, 0.3, len), Color = trimColor, CFrame = origin * CFrame.new(0, baseLY + 0.15, cz), Parent = dest })
		for _, ex in ipairs({ -1, 1 }) do
			makePart({ Name = "WalkEdge", Size = Vector3.new(0.7, 0.34, len), Color = accent, CFrame = origin * CFrame.new(ex * 6, baseLY + 0.17, cz), Parent = dest })
		end
	end
	makePart({ Name = "Platform", Size = FLOOR, Color = Palette.BaseFloor, Material = Enum.Material.Plastic, CFrame = origin, Parent = parent })
	walkway(1, parent)      -- floor-1 runway (always visible)
	walkway(FLOOR2_Y, f2)   -- floor-2 runway (revealed with floor 2)

	-- FLOOR-2 FLOOR SLAB = a permanent ROOF over floor 1 (ALWAYS visible). It carries the
	-- back-center ladder hole; a removable HATCH (toggled in refreshBaseProgression) keeps
	-- the roof solid until the ladder is bought, then opens so the player can climb up.
	local slabMidY = FLOOR2_Y - WALL_T / 2
	local sideW = FLOOR.X / 2 - LADDER_HOLE_HALF_X
	for _, sx in ipairs({ -1, 1 }) do
		makePart({ Name = "Floor1Ceiling", Size = Vector3.new(sideW, WALL_T, FLOOR.Z), Color = Palette.BaseFloor, Material = Enum.Material.Plastic, CFrame = origin * CFrame.new(sx * (LADDER_HOLE_HALF_X + sideW / 2), slabMidY, 0), Parent = parent })
	end
	local frontLen = LADDER_HOLE_FRONT_LZ - (-FLOOR.Z / 2) -- front edge to the hole
	makePart({ Name = "Floor1Ceiling", Size = Vector3.new(2 * LADDER_HOLE_HALF_X, WALL_T, frontLen), Color = Palette.BaseFloor, Material = Enum.Material.Plastic, CFrame = origin * CFrame.new(0, slabMidY, -FLOOR.Z / 2 + frontLen / 2), Parent = parent })
	-- the closable hatch filling the back-center ladder hole (roof complete while locked)
	local holeLen = FLOOR.Z / 2 - LADDER_HOLE_FRONT_LZ
	slotCeilingHatch[slot] = makePart({ Name = "CeilingHatch", Size = Vector3.new(2 * LADDER_HOLE_HALF_X, WALL_T, holeLen), Color = trimColor, Material = Enum.Material.Metal, CFrame = origin * CFrame.new(0, slabMidY, LADDER_HOLE_FRONT_LZ + holeLen / 2), Parent = parent })

	-- top roof (above floor 2) + headers + floor-2 rail — floor-2 structure (gated by ladder),
	-- EXCEPT the floor-1 front header (always visible — it carries the name plate).
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
	local level = profile and profile.CurrentZone or 1
	local group = ZONE_PROG .. math.clamp(level, 1, ZoneConfig.MaxZone)
	char:SetAttribute("ZoneGroup", group)
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") then
			pcall(function() part.CollisionGroup = group end)
		end
	end
	-- ALSO group any part that streams in AFTER this call. A respawn fires CharacterAdded
	-- before every limb/accessory exists; a missed part stays in "Default", which the zone
	-- walls DO block — so a player who has unlocked the next zone could still get STUCK at the
	-- wall on that one part. The hook reads the live ZoneGroup attribute so it stays correct
	-- across rebirths. (Hooked once per character.)
	if not char:GetAttribute("__zoneGateHooked") then
		char:SetAttribute("__zoneGateHooked", true)
		char.DescendantAdded:Connect(function(d)
			if d:IsA("BasePart") then
				local g = char:GetAttribute("ZoneGroup")
				if g then
					pcall(function() d.CollisionGroup = g end)
				end
			end
		end)
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

-- the LOBBY DIG-SITE broken fence is SHORTER than the lane fence (a low border, not a wall)
-- and its FRONT run has a GAP where the shop's dirt path walks in.
local DIG_FENCE_H = 8           -- shorter dig-site fence (vs FENCE_VIS_H=14)
local DIG_FENCE_GAP_HALF = 9    -- half-width of the front-fence opening at the dig centre (path enters here)

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
	-- anchor each side fence to the END plot on that side (the arc tips). The tip slots are found
	-- from SLOT_ANGLE (most-negative = left, most-positive = right), so this stays correct as the
	-- slot count / gap layout changes.
	for _, fence in ipairs({
		{ slot = TIP_SLOT_LEFT, sign = -1, name = "ZoneFence_Left" },
		{ slot = TIP_SLOT_RIGHT, sign = 1, name = "ZoneFence_Right" },
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

-- A THIN, BROKEN post-and-rail fence: thinner boards than the lane fence, with random MISSING
-- posts, LEANING posts (pivoting from the ground), broken-short tops, and GAPPY rails — so the
-- dig site reads as a derelict / actively-excavated pit. Seeded RNG keeps the broken pattern
-- stable across rebuilds. Local +Z is the run direction; non-collidable (decorative only).
local function buildBrokenFence(baseCF: CFrame, length: number, parent: Instance, seed: number, visH: number?)
	local rng = Random.new(seed)
	local H = visH or FENCE_VIS_H -- nominal post height for THIS fence
	local POST_W, RAIL_W = 1.0, 0.5 -- thinner boards (the lane fence uses 1.8 / 0.9)
	local n = math.max(2, math.floor(length / 5) + 1) -- a post roughly every 5 studs
	local present, topH = {}, {}
	for i = 0, n - 1 do
		local lz = -length / 2 + (i / (n - 1)) * length
		present[i] = rng:NextNumber() > 0.18 -- ~18% of posts knocked out (gaps)
		if present[i] then
			local broken = rng:NextNumber() < 0.25 -- some snapped off short
			local h = H * (broken and (0.4 + rng:NextNumber() * 0.35) or (0.88 + rng:NextNumber() * 0.12))
			topH[i] = h
			makePart({
				Name = "DigFencePost",
				Size = Vector3.new(POST_W, h, POST_W),
				Color = Palette.Fence,
				CanCollide = false,
				-- pivot the lean from the GROUND (translate to base, rotate, then raise by h/2)
				CFrame = baseCF * CFrame.new(0, 0, lz)
					* CFrame.Angles((rng:NextNumber() - 0.5) * 0.45, 0, (rng:NextNumber() - 0.5) * 0.3)
					* CFrame.new(0, h / 2, 0),
				Parent = parent,
			})
		end
	end
	for _, frac in ipairs({ 0.36, 0.72 }) do -- two rail courses, built segment-by-segment
		for i = 0, n - 2 do
			if present[i] and present[i + 1] and rng:NextNumber() > 0.25 then -- ~25% of segments broken out
				local z1 = -length / 2 + (i / (n - 1)) * length
				local z2 = -length / 2 + ((i + 1) / (n - 1)) * length
				local ry = math.min(H * frac + (rng:NextNumber() - 0.5) * 1.2, math.min(topH[i], topH[i + 1]) - 0.6)
				makePart({
					Name = "DigFenceRail",
					Size = Vector3.new(RAIL_W, 0.9, (z2 - z1) + 0.2),
					Color = Palette.Fence,
					CanCollide = false,
					CFrame = baseCF * CFrame.new(0, ry, (z1 + z2) / 2) * CFrame.Angles((rng:NextNumber() - 0.5) * 0.12, 0, 0),
					Parent = parent,
				})
			end
		end
	end
end

-- A THIN, BROKEN fence around the Zone-1 (lobby) dig site on THREE sides: the front (-Z, lobby
-- side) and both flanks (±X). The +Z side is left OPEN — that's where the zone-1/2 rebirth wall
-- sits and players pass through to the next zone. The gaps/leaning boards make it read like an
-- active excavation site; non-collidable so it never blocks digging or walking in.
local function buildZone1DigFence()
	local cx = MapBuilder.DigCenter.X
	local digCz = LANE_START + ZONE1_DIG_SHIFT_Z -- dig-patch centre Z
	local halfX, halfZ = ZONE1_DIG_SIZE.X / 2, ZONE1_DIG_SIZE.Z / 2
	local MARGIN = 3 -- sit the fence this far out on the grass, just past the brown pit edge
	local fx = halfX + MARGIN
	local frontZ = digCz - halfZ - MARGIN -- the -Z (lobby) edge we fence
	local openZ = digCz + halfZ -- the +Z edge nearest the zone wall — left OPEN
	-- FRONT fence in TWO runs with a centred GAP where the shop's dirt path walks in.
	local segLen = fx - DIG_FENCE_GAP_HALF -- each front run: from ±gap out to ±fx
	if segLen > 2 then
		local segMid = (fx + DIG_FENCE_GAP_HALF) / 2 -- |x| centre of each front run
		buildBrokenFence(CFrame.new(cx - segMid, 1, frontZ) * CFrame.Angles(0, math.rad(90), 0), segLen, laneFolder, 101, DIG_FENCE_H) -- front-left
		buildBrokenFence(CFrame.new(cx + segMid, 1, frontZ) * CFrame.Angles(0, math.rad(90), 0), segLen, laneFolder, 112, DIG_FENCE_H) -- front-right
	end
	local sideLen, sideMidZ = openZ - frontZ, (openZ + frontZ) / 2
	buildBrokenFence(CFrame.new(cx - fx, 1, sideMidZ), sideLen, laneFolder, 202, DIG_FENCE_H) -- left
	buildBrokenFence(CFrame.new(cx + fx, 1, sideMidZ), sideLen, laneFolder, 303, DIG_FENCE_H) -- right
end

-- TWO grass-topped DIRT CLIFFS flanking the dig lane, running parallel to it (+Z),
-- just outside the forest strip. They replace the old map-wide snow border on these
-- sides and TIGHTEN the playable width. They DON'T block bases: they start past the
-- front-most bases (the arc tips at ~z+52) and run to just past the last dig site.
-- Body = studded Dirt "mountain", cap = studded Grass — both via makePart so they get
-- the classic chunky studs. Collidable, so they actually contain the lane.
local function buildLaneSideWalls()
	local cx = MapBuilder.DigCenter.X
	local zStart = LANE_START + LANE_SIDE_Z_START -- pushed past the front-most bases so it never clips a plot
	-- extend to frame PLANNED zones (room for FUTURE zones beyond MaxZone), not just MaxZone
	local zEnd = LANE_START + (LANE_SIDE_PLANNED_ZONES - 1) * LANE_STEP + SEG_SIZE.Z / 2 + 24
	local length = zEnd - zStart
	local midZ = (zStart + zEnd) / 2
	local centerX = LANE_SIDE_INNER_X + LANE_SIDE_THICK / 2
	for _, sign in ipairs({ -1, 1 }) do
		local wx = cx + sign * centerX
		-- dirt/mountain cliff body
		makePart({
			Name = "LaneWallDirt",
			Size = Vector3.new(LANE_SIDE_THICK, LANE_SIDE_BODY_H, length),
			Color = Palette.Dirt,
			CanCollide = true,
			CFrame = CFrame.new(wx, 1 + LANE_SIDE_BODY_H / 2, midZ),
			Parent = laneFolder,
		})
		-- grass cap on top (slightly oversized so it reads as a grassy ledge overhang);
		-- tagged so the checker overlays its top face (studs stay on the sides)
		local grassCap = makePart({
			Name = "LaneWallGrass",
			Size = Vector3.new(LANE_SIDE_THICK + 4, LANE_SIDE_CAP_H, length + 4),
			Color = Palette.Grass,
			CanCollide = true,
			CFrame = CFrame.new(wx, 1 + LANE_SIDE_BODY_H + LANE_SIDE_CAP_H / 2, midZ),
			Parent = laneFolder,
		})
		CollectionService:AddTag(grassCap, "GrassSurface")
	end
end

-- The THREE-TIER lobby rampart (see the LOBBY_WALL_* notes). A faceted horseshoe of straight
-- segments + angled corners wraps the OUTSIDE of the base ring as three FLUSH stepped tiers (short
-- inner -> tall outer) — one continuous stepped mass, no gaps between layers. Each tier is built
-- from a FEW chunky blocks with BIG per-block height jumps (jagged, bold) for a natural cliff look.
-- The inner + middle tiers run their FRONT segments along X and butt into the lane border walls'
-- OUTER face perpendicularly (both sides, past the end plots) so they never sit inside a plot or
-- cross to the lane side; the TALLEST outer tier stops short of the lane for a fading / mountain-end
-- taper. Seeded so the layout is identical every build (LOBBY_WALL_SEED).
local function buildLobbyWall()
	local rng = Random.new(LOBBY_WALL_SEED)
	local rockRng = Random.new(LOBBY_WALL_SEED + 4242) -- SEPARATE stream so rocks never shift the wall blocks
	local laneX = LANE_SIDE_INNER_X + LANE_SIDE_THICK / 2   -- 110 — lane wall centre x
	local connX = laneX + LANE_SIDE_THICK / 2               -- 120 — lane wall OUTER face: connect HERE so the wall doesn't poke through to the lane side

	-- a slightly varied studded stone colour for a sprinkled rock (own rng — see above)
	local function jitterStone(): Color3
		local j = (rockRng:NextNumber() - 0.5) * 0.08
		local c = Palette.Stone
		return Color3.new(math.clamp(c.R + j, 0, 1), math.clamp(c.G + j, 0, 1), math.clamp(c.B + j, 0, 1))
	end

	-- candidate rock spots (one per wall-block top); rocks are chosen from these AFTER all blocks
	-- exist, balanced left/right, so neither side gets crowded.
	local rockSpots: { { x: number, z: number, y: number, angle: number } } = {}

	-- build ONE rock on the ledge at (rx, rz, topY): a WIDE LOW base + two smaller, taller bumps
	-- => a chunky, stepped, rectangular boulder with texture. Squared to the wall by `angle`.
	local function placeRock(rx: number, rz: number, topY: number, angle: number)
		local bw = rockRng:NextNumber(LOBBY_WALL_ROCK_MIN, LOBBY_WALL_ROCK_MAX)
		local bd = bw * rockRng:NextNumber(0.8, 1.1)
		for bi = 1, 3 do
			local wide = (bi == 1)
			local pw = math.max(4, bw * (wide and rockRng:NextNumber(0.85, 1.0) or rockRng:NextNumber(0.45, 0.75)))
			local pd = math.max(4, bd * (wide and rockRng:NextNumber(0.85, 1.0) or rockRng:NextNumber(0.45, 0.75)))
			local ph = wide and rockRng:NextNumber(4, 6) or rockRng:NextNumber(7, 12) -- base low, bumps tall
			local ox = (rockRng:NextNumber() - 0.5) * bw * (wide and 0.1 or 0.5)       -- base centred; bumps offset to peek out
			local oz = (rockRng:NextNumber() - 0.5) * bd * (wide and 0.1 or 0.5)
			makePart({
				Name = "LobbyWallRock",
				Size = Vector3.new(pw, ph, pd),
				Color = jitterStone(),
				CanCollide = false,
				CFrame = CFrame.new(rx + ox, topY + ph / 2, rz + oz)
					* CFrame.Angles(0, angle + (rockRng:NextNumber() - 0.5) * 0.25, 0),
				Parent = laneFolder,
			})
		end
	end

	-- the faceted horseshoe's SIDE + BACK vertices (right-upper around the back to left-upper). These
	-- are pushed OUT radially per terrace; the FRONT runs (lane-border joins) are added per terrace.
	local mids = {
		Vector3.new(290, 0, -30),    -- right upper side (angled corner)
		Vector3.new(255, 0, -185),   -- right lower side
		Vector3.new(125, 0, -288),   -- right back corner
		Vector3.new(-125, 0, -288),  -- left back corner
		Vector3.new(-255, 0, -185),  -- left lower side
		Vector3.new(-290, 0, -30),   -- left upper side (angled corner)
	}
	local FRONT_X = 256  -- |x| of each front-side vertex BEFORE the per-terrace push (clears the end plots, which reach x=248)

	-- one dirt block + grass cap of a terrace, centred at `center`, turned by `angle`, `len` long, `h` tall
	local function block(center: Vector3, angle: number, len: number, h: number)
		local cf = CFrame.new(center.X, 0, center.Z) * CFrame.Angles(0, angle, 0) -- local Z = along the run
		makePart({
			Name = "LobbyWallDirt",
			Size = Vector3.new(LOBBY_WALL_THICK, h, len),
			Color = Palette.Dirt,
			CanCollide = true,
			CFrame = cf * CFrame.new(0, 1 + h / 2, 0),
			Parent = laneFolder,
		})
		local cap = makePart({
			Name = "LobbyWallGrass",
			Size = Vector3.new(LOBBY_WALL_THICK + 4, LOBBY_WALL_CAP_H, len + 1),
			Color = Palette.Grass,
			CanCollide = true,
			CFrame = cf * CFrame.new(0, 1 + h + LOBBY_WALL_CAP_H / 2, 0),
			Parent = laneFolder,
		})
		CollectionService:AddTag(cap, "GrassSurface")
	end

	-- a terrace run through `pts` at nominal height `nominalH`: each segment is chopped into ~SUBLEN
	-- blocks whose heights wobble (jagged top); blocks overlap (len + THICK) so there are no seams.
	local function run(pts: { Vector3 }, nominalH: number)
		for i = 1, #pts - 1 do
			local p, q = pts[i], pts[i + 1]
			local dx, dz = q.X - p.X, q.Z - p.Z
			local segLen = math.sqrt(dx * dx + dz * dz)
			if segLen >= 1 then
				local angle = math.atan2(dx, dz)
				local ux, uz = dx / segLen, dz / segLen
				local nb = math.max(1, math.floor(segLen / LOBBY_WALL_SUBLEN + 0.5))
				local bl = segLen / nb
				for b = 0, nb - 1 do
					local t = bl * (b + 0.5)
					local center = Vector3.new(p.X + ux * t, 0, p.Z + uz * t)
					local h = math.max(8, nominalH + rng:NextNumber(-LOBBY_WALL_H_JITTER, LOBBY_WALL_H_JITTER))
					block(center, angle, bl + LOBBY_WALL_THICK, h)
					-- record this ledge top as a candidate rock spot, JITTERED along + across the ledge so the
					-- chosen rocks don't sit on a regular grid (they read as randomly scattered)
					local jA = (rockRng:NextNumber() - 0.5) * bl * 0.85
					local jX = (rockRng:NextNumber() - 0.5) * LOBBY_WALL_THICK * 0.35
					rockSpots[#rockSpots + 1] = {
						x = center.X + ux * jA + uz * jX,
						z = center.Z + uz * jA - ux * jX,
						y = 1 + h + LOBBY_WALL_CAP_H,
						angle = angle,
					}
				end
			end
		end
	end

	-- build one terrace: push the side/back vertices OUT by terr.off (+ radial wobble); the front-side
	-- vertices sit at +/-(FRONT_X + off) at the tier's frontZ; if terr.front, a perpendicular run joins
	-- each side to the lane border wall (connX) — otherwise the tier just ends at its front-side (fade).
	local function buildTerrace(terr)
		local off, fz = terr.off, terr.frontZ
		local fx = FRONT_X + off
		local pts = {}
		if terr.front then pts[#pts + 1] = Vector3.new(connX, 0, fz) end  -- right lane-border join
		pts[#pts + 1] = Vector3.new(fx, 0, fz)                            -- right front-side
		for _, v in ipairs(mids) do
			local r = math.sqrt(v.X * v.X + v.Z * v.Z)
			local s = (r + off + rng:NextNumber(-LOBBY_WALL_R_JITTER, LOBBY_WALL_R_JITTER)) / r
			pts[#pts + 1] = Vector3.new(v.X * s, 0, v.Z * s)
		end
		pts[#pts + 1] = Vector3.new(-fx, 0, fz)                           -- left front-side
		if terr.front then pts[#pts + 1] = Vector3.new(-connX, 0, fz) end -- left lane-border join
		run(pts, terr.h)
	end

	for _, terr in ipairs(LOBBY_WALL_TERRACES) do
		buildTerrace(terr)
	end

	-- pick rocks BALANCED left/right (x<0 vs x>0) from all ledge tops, so neither side crowds.
	local leftSpots, rightSpots = {}, {}
	for _, s in ipairs(rockSpots) do
		if s.x < 0 then leftSpots[#leftSpots + 1] = s else rightSpots[#rightSpots + 1] = s end
	end
	local function shuffle(t)
		for i = #t, 2, -1 do
			local j = rockRng:NextInteger(1, i)
			t[i], t[j] = t[j], t[i]
		end
	end
	shuffle(leftSpots)
	shuffle(rightSpots)
	local perSide = math.floor(LOBBY_WALL_ROCK_TOTAL / 2)
	for i = 1, math.min(perSide, #leftSpots) do
		local s = leftSpots[i]
		placeRock(s.x, s.z, s.y, s.angle)
	end
	for i = 1, math.min(perSide, #rightSpots) do
		local s = rightSpots[i]
		placeRock(s.x, s.z, s.y, s.angle)
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

-- frame BOTH ends of a wall at lane-z `wz` with stone piles. `pileX` is the |x| the piles
-- CENTER on; defaults to just past the normal wall end (~66, near the dig site). Pass a larger
-- value (the wide fence-less walls) to sit the piles OUT against the map borders.
local function buildWallFrame(wz: number, pileX: number?)
	local x = MapBuilder.DigCenter.X
	local px = pileX or (REBIRTH_WALL.X / 2 + 4) -- default ~66: just past the normal wall end
	local pileH = REBIRTH_WALL.Y + 12            -- rise a bit above the 44-tall wall
	for _, sign in ipairs({ -1, 1 }) do
		buildRockPile(Vector3.new(x + sign * px, 0, wz), pileH)
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
		CanCollide = true, -- SOLID: players can't walk through trees
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
			CanCollide = true, -- SOLID canopy too, so the whole tree blocks the player
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
					d.CanCollide = true -- SOLID: players can't walk through trees
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
local function placeTree(x: number, z: number, targetH: number, parent: Instance, collide: boolean?)
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
	-- trees default to SOLID; pass collide=false for decoration that shouldn't block walking
	if collide == false then
		for _, d in ipairs(tree:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanCollide = false
			end
		end
	end
	tree.Parent = parent
end

-- Drop an INVISIBLE "no-dig" marker at (x,z): the client (DigSite.scatterPatch) never scatters a
-- dirt mound within `radius` of it, so eggs never spawn on top of digsite decor (trees/cacti/rocks).
-- Defined HERE (above the forest tree builders) so every decoration builder can mark its footprint.
local DIG_EXCLUSION_TAG = "DigExclusion"
local function addDigExclusion(x: number, z: number, radius: number, zone: number)
	local marker = makePart({
		Name = "DigExclusion",
		Size = Vector3.new(1, 1, 1),
		Transparency = 1,
		NoStuds = true,
		CanCollide = false,
		CastShadow = false,
		CFrame = CFrame.new(x, 1.5, z),
		Parent = laneFolder,
	})
	marker:SetAttribute("ClearRadius", radius)
	marker:SetAttribute("Zone", zone)
	CollectionService:AddTag(marker, DIG_EXCLUSION_TAG)
end

-- a FEW small trees sprinkled in the forest dig clearing's grassy rim, placed in a ring at radius
-- `RING`. The whole zone is diggable, so each is ringed by a no-dig exclusion so mounds never spawn
-- on them. Non-collidable so they never block the player running between mounds.
local function buildForestClearingTrees(zone: number, centerZ: number)
	local cx = MapBuilder.DigCenter.X
	local RING = 54 -- mid-zone ring between the centre and the side tree strips
	-- corner + a couple edge anchors (unit offsets); jitter is tiny so none drift far
	local spots = {
		{ 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 }, -- 4 corners
		{ 1, 0.2 }, { -1, -0.2 },                    -- 2 edge-ish (sprinkle)
	}
	for _, s in ipairs(spots) do
		local x = cx + s[1] * RING + (decorRng:NextNumber() - 0.5) * 4
		local z = centerZ + s[2] * RING + (decorRng:NextNumber() - 0.5) * 4
		placeTree(x, z, decorRng:NextInteger(13, 18) + decorRng:NextNumber(), laneFolder, false)
		addDigExclusion(x, z, 11, zone)
	end
end

-- scatter trees in the LEFT and RIGHT strips flanking a Forest zone (between the central dig area
-- and the border cliffs). The whole zone is diggable now, so each SOLID tree drops a no-dig marker
-- so a mound never spawns under its trunk. NEVER on the lane.
local function buildForestTrees(zone: number, zLo: number, zHi: number)
	local cx = MapBuilder.DigCenter.X
	local innerX = SEG_SIZE.X / 2 + 6 -- = 66: the side tree strip starts here
	local outerX = innerX + 18        -- thin strip; trees stay INSIDE the compacted lane wall (cap inner ~x98)
	local step = 16
	for _, sign in ipairs({ -1, 1 }) do
		local gx = innerX
		while gx <= outerX do
			local gz = zLo
			while gz <= zHi do
				if decorRng:NextNumber() < 0.7 then -- gaps => natural forest edge
					local x = cx + sign * (gx + (decorRng:NextNumber() - 0.5) * step * 0.8)
					local z = gz + (decorRng:NextNumber() - 0.5) * step * 0.8
					placeTree(x, z, decorRng:NextInteger(12, 18) + decorRng:NextNumber(), laneFolder)
					addDigExclusion(x, z, 10, zone) -- keep mounds off the solid trunks
				end
				gz = gz + step
			end
			gx = gx + step
		end
	end
end

------------------------------------------------------------- forest ground cover
-- A FEW small trees standing among the dig mounds. Each gets an INVISIBLE no-dig marker (tagged
-- DigExclusion, with a ClearRadius + Zone) so the client (DigSite.scatterPatch) never drops a dirt
-- mound on/near the tree. NON-collidable so a tree among the mounds never traps a digging player.
local function buildForestDigsiteTrees(zone: number, centerZ: number)
	local cx = MapBuilder.DigCenter.X
	-- offsets spread around the central area, kept from clumping at the centre
	local spots = { { 21, 13 }, { -17, 23 }, { 24, -19 }, { -23, -15 } }
	for _, s in ipairs(spots) do
		local x = cx + s[1] + (decorRng:NextNumber() - 0.5) * 6
		local z = centerZ + s[2] + (decorRng:NextNumber() - 0.5) * 6
		placeTree(x, z, decorRng:NextInteger(11, 15) + decorRng:NextNumber(), laneFolder, false)
		addDigExclusion(x, z, 13, zone) -- no-dig zone so mounds never spawn on the tree
	end
end

-- a tiny clump of 2-3 thin grass blades, grouped under a Model named "grass" (a couple
-- studs tall, vibrant green, non-collidable), standing on the surface at (x, z).
local function buildGrassTuft(x: number, z: number, surfaceY: number)
	local clump = Instance.new("Model")
	clump.Name = "grass"
	local primary: BasePart? = nil
	for _ = 1, decorRng:NextInteger(2, 3) do
		local h = 1.2 + decorRng:NextNumber() * 0.9 -- ~1.2-2.1 studs
		local blade = makePart({
			Name = "Blade",
			NoStuds = true, -- too small to read studs
			Size = Vector3.new(0.35, h, 0.35),
			Color = jitterColor(Palette.TreeLeaf, 0.12),
			CanCollide = false,
			CastShadow = false,
			CFrame = CFrame.new(x + (decorRng:NextNumber() - 0.5) * 1.3, surfaceY + h / 2, z + (decorRng:NextNumber() - 0.5) * 1.3)
				* CFrame.Angles(math.rad(decorRng:NextInteger(-12, 12)), math.rad(decorRng:NextInteger(0, 359)), math.rad(decorRng:NextInteger(-12, 12))),
			Parent = clump,
		})
		primary = primary or blade
	end
	clump.PrimaryPart = primary
	clump.Parent = laneFolder
end

-- a small flower: a thin green stem topped by a vibrant NEON bloom (a couple studs tall,
-- non-collidable). Bloom colour drawn from the vibrant palette.
local FLOWER_COLORS = { Palette.Pink, Palette.Gold, Palette.Cyan, Palette.Purple, Palette.LockRed }
local function buildFlower(x: number, z: number, surfaceY: number)
	local flower = Instance.new("Model")
	flower.Name = "Flower"
	local stemH = 1.0 + decorRng:NextNumber() * 0.8
	local stem = makePart({
		Name = "Stem",
		NoStuds = true,
		Size = Vector3.new(0.25, stemH, 0.25),
		Color = jitterColor(Palette.TreeLeaf, 0.08),
		CanCollide = false,
		CastShadow = false,
		CFrame = CFrame.new(x, surfaceY + stemH / 2, z),
		Parent = flower,
	})
	flower.PrimaryPart = stem
	makePart({
		Name = "Bloom",
		NoStuds = true,
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.95, 0.95, 0.95),
		Color = FLOWER_COLORS[decorRng:NextInteger(1, #FLOWER_COLORS)],
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		CFrame = CFrame.new(x, surfaceY + stemH + 0.25, z),
		Parent = flower,
	})
	flower.Parent = laneFolder
end

-- Scatter tiny grass tufts + small flowers RANDOMLY across the whole Forest zone (the
-- grassy clearing + the flanking strips), kept inside the lane walls. Surface-snapped via a
-- downward ray against the ground / dig plates ONLY (so they never perch on a tree canopy).
-- Forest-zone only (called from decorateLane for Theme == "Forest").
local function scatterForestGroundCover(zone: number, centerZ: number)
	local cx = MapBuilder.DigCenter.X
	local halfX = LANE_SIDE_INNER_X - 8 -- stay just inside the lane walls
	local halfZ = LANE_STEP / 2 - 6     -- the zone's z half-extent (clear of the rebirth walls)

	-- raycast only against flat surfaces (ground + dig slabs), never trees/rocks/decor
	local surfaces: { Instance } = {}
	local world = Workspace:FindFirstChild("World")
	local ground = world and world:FindFirstChild("Ground")
	if ground then
		surfaces[#surfaces + 1] = ground
	end
	for _, p in ipairs(laneFolder:GetChildren()) do
		if p:IsA("BasePart") and (p.Name == ("Zone%dDig"):format(zone) or p.Name == "ZoneBorder") then
			surfaces[#surfaces + 1] = p
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = surfaces
	local function surfaceYAt(x: number, z: number): number
		local hit = Workspace:Raycast(Vector3.new(x, 40, z), Vector3.new(0, -60, 0), params)
		return hit and hit.Position.Y or 1
	end

	for _ = 1, 90 do
		local x = cx + (decorRng:NextNumber() - 0.5) * 2 * halfX
		local z = centerZ + (decorRng:NextNumber() - 0.5) * 2 * halfZ
		buildGrassTuft(x, z, surfaceYAt(x, z))
	end
	for _ = 1, 30 do
		local x = cx + (decorRng:NextNumber() - 0.5) * 2 * halfX
		local z = centerZ + (decorRng:NextNumber() - 0.5) * 2 * halfZ
		buildFlower(x, z, surfaceYAt(x, z))
	end
end

------------------------------------------------------------- desert ground cover (zone 3)
-- a blocky studded CACTUS standing on the surface at (x,z): a tall trunk + 1-2 saguaro arms
-- (out then up). Heights vary a LOT (some very tall). NON-collidable like the forest digsite
-- trees so a cactus standing among the mounds never traps a digging player.
local function buildCactus(x: number, z: number, surfaceY: number)
	local cactus = Instance.new("Model")
	cactus.Name = "Cactus"
	local trunkW = 3 + decorRng:NextNumber() * 1.5
	local height = decorRng:NextInteger(16, 34) + decorRng:NextNumber() -- varying; some TOO tall
	local trunk = makePart({
		Name = "Cactus",
		Size = Vector3.new(trunkW, height, trunkW),
		Color = jitterColor(Palette.Cactus, 0.05),
		CanCollide = false,
		CFrame = CFrame.new(x, surfaceY + height / 2, z),
		Parent = cactus,
	})
	cactus.PrimaryPart = trunk
	for _ = 1, decorRng:NextInteger(1, 2) do
		local side = (decorRng:NextNumber() < 0.5) and 1 or -1
		local alongX = decorRng:NextNumber() < 0.5
		local attachH = surfaceY + height * (0.4 + decorRng:NextNumber() * 0.3)
		local outLen = 3 + decorRng:NextNumber() * 4
		local upLen = height * (0.22 + decorRng:NextNumber() * 0.28)
		local aw = trunkW * 0.72
		local hx = alongX and (x + side * (outLen / 2 + trunkW / 2 - 0.5)) or x
		local hz = alongX and z or (z + side * (outLen / 2 + trunkW / 2 - 0.5))
		makePart({ -- horizontal segment (out from the trunk)
			Name = "CactusArm",
			Size = alongX and Vector3.new(outLen, aw, aw) or Vector3.new(aw, aw, outLen),
			Color = jitterColor(Palette.Cactus, 0.05),
			CanCollide = false,
			CFrame = CFrame.new(hx, attachH, hz),
			Parent = cactus,
		})
		local vx = alongX and (x + side * (outLen + trunkW / 2 - 0.5)) or x
		local vz = alongX and z or (z + side * (outLen + trunkW / 2 - 0.5))
		makePart({ -- vertical segment (the arm bends up)
			Name = "CactusArm",
			Size = Vector3.new(aw, upLen, aw),
			Color = jitterColor(Palette.Cactus, 0.05),
			CanCollide = false,
			CFrame = CFrame.new(vx, attachH + upLen / 2, vz),
			Parent = cactus,
		})
	end
	cactus.Parent = laneFolder
end

-- a single chunky #695B33 desert rock on the surface at (x,z). Returns its footprint size.
local function buildDesertRock(x: number, z: number, surfaceY: number): number
	local s = decorRng:NextInteger(7, 13)
	makePart({
		Name = "DesertRock",
		Size = Vector3.new(s, s * 0.8, s * 0.9),
		Color = jitterColor(Palette.DesertRock, 0.05),
		CanCollide = false,
		CFrame = CFrame.new(x, surfaceY + s * 0.4 - 0.4, z)
			* CFrame.Angles(math.rad(decorRng:NextInteger(0, 28)), math.rad(decorRng:NextInteger(0, 360)), math.rad(decorRng:NextInteger(0, 28))),
		Parent = laneFolder,
	})
	return s
end

-- DESERT theme decor: scatter several varying-height cacti + a few #695B33 rocks across the
-- digsite, spread out (min-spacing). Each gets a no-dig marker so dirt mounds never overlap them.
local function buildDesertDigsiteDecor(zone: number, centerZ: number)
	local cx = MapBuilder.DigCenter.X
	local surfaceY = LANE_SEG_Y + SEG_SIZE.Y / 2 -- top of the dig plate
	-- spread the decor across the WHOLE zone now (clear of the side cliffs + the rebirth walls)
	local SPREAD_X = LANE_SIDE_INNER_X - 14 -- ~86: across the lane width, off the cliffs
	local SPREAD_Z = LANE_STEP / 2 - 16     -- ~58: down the zone, off the walls
	local placed: { { x: number, z: number } } = {}
	-- pick a scattered (x,z) at least `gap` from already-placed decor; nil if it can't after tries
	local function pick(gap: number): (number?, number?)
		for _ = 1, 16 do
			local x = cx + (decorRng:NextNumber() - 0.5) * 2 * SPREAD_X
			local z = centerZ + (decorRng:NextNumber() - 0.5) * 2 * SPREAD_Z
			local ok = true
			for _, p in ipairs(placed) do
				if (x - p.x) ^ 2 + (z - p.z) ^ 2 < gap * gap then
					ok = false
					break
				end
			end
			if ok then
				placed[#placed + 1] = { x = x, z = z }
				return x, z
			end
		end
		return nil, nil
	end
	for _ = 1, 11 do -- cacti (different heights, scattered across the zone)
		local x, z = pick(18)
		if x and z then
			buildCactus(x, z, surfaceY)
			addDigExclusion(x, z, 11, zone)
		end
	end
	for _ = 1, 5 do -- a few desert rocks
		local x, z = pick(18)
		if x and z then
			local s = buildDesertRock(x, z, surfaceY)
			addDigExclusion(x, z, math.max(10, s / 2 + 5), zone)
		end
	end
end

------------------------------------------------------------- glacier ground cover (zone 4)
-- a jagged STUDDED ice spike (Minecraft-style spire): a stack of boxes tapering to a point, each
-- level slightly offset so it reads as a rough crystal. Heights vary a LOT (some very tall).
-- NON-collidable like the other digsite decor so it never traps a digging player. Returns base width.
local function buildIceSpike(x: number, z: number, surfaceY: number): number
	local spike = Instance.new("Model")
	spike.Name = "IceSpike"
	local height = decorRng:NextInteger(10, 40) + decorRng:NextNumber() -- varying; some very tall
	local levels = math.clamp(math.floor(height / 5), 3, 9)
	local baseW = 3.5 + decorRng:NextNumber() * 3.5
	local y = surfaceY
	for i = 0, levels - 1 do
		local t = i / levels
		local w = baseW * (1 - t * 0.82) -- taper toward a point
		local segH = height / levels
		makePart({
			Name = "IceSpike",
			Size = Vector3.new(w, segH * 1.03, w),
			Color = jitterColor(Palette.IceSpike, 0.03),
			CanCollide = false,
			CastShadow = false,
			CFrame = CFrame.new(
				x + (decorRng:NextNumber() - 0.5) * baseW * 0.28,
				y + segH / 2,
				z + (decorRng:NextNumber() - 0.5) * baseW * 0.28
			) * CFrame.Angles(0, math.rad(decorRng:NextInteger(0, 18)), 0),
			Parent = spike,
		})
		y = y + segH
	end
	spike.Parent = laneFolder
	return baseW
end

-- one small, cute blocky PENGUIN standing on the surface at (x,z): dark body + white belly, orange
-- beak/feet, little eyes + wings. Smooth (NoStuds — it's a creature), non-collidable. ~4.5 studs tall.
local function buildPenguin(x: number, z: number, surfaceY: number)
	local penguin = Instance.new("Model")
	penguin.Name = "Penguin"
	local BODY = Color3.fromRGB(42, 47, 64)    -- dark blue-black
	local BELLY = Color3.fromRGB(245, 248, 255) -- white
	local BEAK = Color3.fromRGB(255, 150, 40)  -- orange
	local base = CFrame.new(x, surfaceY, z) * CFrame.Angles(0, math.rad(decorRng:NextInteger(0, 359)), 0)
	local function part(name: string, size: Vector3, color: Color3, lx: number, ly: number, lz: number)
		return makePart({
			Name = "Penguin",
			NoStuds = true,
			CanCollide = false,
			CastShadow = false,
			Size = size,
			Color = color,
			CFrame = base * CFrame.new(lx, ly, lz),
			Parent = penguin,
		})
	end
	local body = part("body", Vector3.new(2.4, 2.8, 2.0), BODY, 0, 1.5, 0)
	penguin.PrimaryPart = body
	part("belly", Vector3.new(1.7, 2.1, 0.5), BELLY, 0, 1.4, 0.9)
	part("head", Vector3.new(2.0, 1.7, 1.7), BODY, 0, 3.6, 0)
	part("eyeL", Vector3.new(0.42, 0.42, 0.3), BELLY, -0.5, 3.9, 0.8)
	part("eyeR", Vector3.new(0.42, 0.42, 0.3), BELLY, 0.5, 3.9, 0.8)
	part("beak", Vector3.new(0.6, 0.5, 0.6), BEAK, 0, 3.45, 0.95)
	part("wingL", Vector3.new(0.5, 2.1, 1.4), BODY, -1.35, 1.7, 0)
	part("wingR", Vector3.new(0.5, 2.1, 1.4), BODY, 1.35, 1.7, 0)
	part("footL", Vector3.new(0.8, 0.4, 1.1), BEAK, -0.55, 0.2, 0.6)
	part("footR", Vector3.new(0.8, 0.4, 1.1), BEAK, 0.55, 0.2, 0.6)
	penguin.Parent = laneFolder
end

-- GLACIERS theme decor: scatter ice spikes (varying heights) + ONE small penguin across the digsite,
-- spread out (min-spacing). Each gets a no-dig marker so dirt mounds never overlap them.
local function buildGlacierDigsiteDecor(zone: number, centerZ: number)
	local cx = MapBuilder.DigCenter.X
	local surfaceY = LANE_SEG_Y + SEG_SIZE.Y / 2 -- top of the dig plate
	-- spread the decor across the WHOLE zone now (clear of the side cliffs + the rebirth walls)
	local SPREAD_X = LANE_SIDE_INNER_X - 14 -- ~86: across the lane width, off the cliffs
	local SPREAD_Z = LANE_STEP / 2 - 16     -- ~58: down the zone, off the walls
	local placed: { { x: number, z: number } } = {}
	local function pick(gap: number): (number?, number?)
		for _ = 1, 16 do
			local x = cx + (decorRng:NextNumber() - 0.5) * 2 * SPREAD_X
			local z = centerZ + (decorRng:NextNumber() - 0.5) * 2 * SPREAD_Z
			local ok = true
			for _, p in ipairs(placed) do
				if (x - p.x) ^ 2 + (z - p.z) ^ 2 < gap * gap then
					ok = false
					break
				end
			end
			if ok then
				placed[#placed + 1] = { x = x, z = z }
				return x, z
			end
		end
		return nil, nil
	end
	for _ = 1, 14 do -- ice spikes (different heights, scattered across the zone)
		local x, z = pick(14)
		if x and z then
			local baseW = buildIceSpike(x, z, surfaceY)
			addDigExclusion(x, z, math.max(8, baseW / 2 + 5), zone)
		end
	end
	local px, pz = pick(14) -- one small penguin
	if px and pz then
		buildPenguin(px, pz, surfaceY)
		addDigExclusion(px, pz, 6, zone)
	end
end

------------------------------------------------------------- CRYSTAL CAVERNS (zone 5)
-- Glowing crystal-cavern decor that pops against the dark #1B3444 floor (Theme == "Cavern").
-- A picked-from-the-rainbow palette for the grass / mushrooms / wall crystals.
local CAVERN_RAINBOW = {
	Color3.fromRGB(255, 64, 64),  -- red
	Color3.fromRGB(255, 150, 40), -- orange
	Color3.fromRGB(255, 238, 70), -- yellow
	Color3.fromRGB(70, 255, 120), -- green
	Color3.fromRGB(55, 235, 255), -- cyan
	Color3.fromRGB(90, 140, 255), -- blue
	Color3.fromRGB(195, 95, 255), -- purple
	Color3.fromRGB(255, 95, 215), -- magenta
}
local function cavernRainbow(): Color3
	return CAVERN_RAINBOW[decorRng:NextInteger(1, #CAVERN_RAINBOW)]
end

-- a coloured PointLight so the decor casts a glow pool onto the dark floor (like the reference)
local function addGlow(part: BasePart, color: Color3, brightness: number, range: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = part
end

-- ONE crystal shard: a tapered stack of NEON box segments growing from `root` ALONG `dir`
-- (so it can erupt sideways from the ground or jut out of a wall). Optional glow at its tip.
local function buildCrystalShard(parent: Instance, root: Vector3, dir: Vector3, color: Color3, length: number, withLight: boolean)
	dir = dir.Unit
	local segs = 4
	local baseW = 2.6 + decorRng:NextNumber() * 1.1
	local acc = 0
	for i = 0, segs - 1 do
		local t = i / segs
		local w = baseW * (1 - t * 0.74) -- taper toward the point
		local segL = length / segs
		local center = root + dir * (acc + segL / 2)
		makePart({
			Name = "Crystal",
			NoStuds = true, -- crystalline, not studded
			Size = Vector3.new(w, w, segL * 1.05),
			Color = jitterColor(color:Lerp(Color3.new(0, 0, 0), 0.12), 0.05), -- deepened so the facets read
			Material = Enum.Material.Neon,
			CanCollide = true, -- SOLID crystal — can't be walked or jumped through
			CastShadow = false,
			-- align the segment's length (local Z) with `dir`; random roll = faceted look
			CFrame = CFrame.lookAt(center, center + dir) * CFrame.Angles(0, 0, math.rad(decorRng:NextInteger(0, 90))),
			Parent = parent,
		})
		acc = acc + segL
	end
	if withLight then
		local glow = makePart({
			Name = "CrystalGlow",
			Size = Vector3.new(0.4, 0.4, 0.4),
			Transparency = 1,
			NoStuds = true,
			CanCollide = false,
			CastShadow = false,
			CFrame = CFrame.new(root + dir * (length * 0.55)),
			Parent = parent,
		})
		addGlow(glow, color, 1.0, 12) -- dimmer halo so the crystal's own shape reads
	end
end

-- THE MAIN ATTRACTION: one grouped crystal — RED / BLUE / GREEN shards erupting from the SAME
-- root at a sideways angle, splitting into three directions (120° apart). Each shard glows.
local function buildCrystalCluster(x: number, z: number, surfaceY: number)
	local model = Instance.new("Model")
	model.Name = "CrystalCluster"
	local root = Vector3.new(x, surfaceY + 0.2, z)
	-- a dark rocky lump the crystals erupt from
	local rock = makePart({
		Name = "CrystalBase",
		Shape = Enum.PartType.Ball,
		NoStuds = true,
		Size = Vector3.new(5.5, 3.6, 5.5),
		Color = Palette.Stone,
		Material = Enum.Material.Slate,
		CanCollide = true, -- solid base of the crystal cluster
		CastShadow = false,
		CFrame = CFrame.new(x, surfaceY + 0.3, z),
		Parent = model,
	})
	model.PrimaryPart = rock
	local colors = {
		Color3.fromRGB(255, 55, 55),  -- red
		Color3.fromRGB(70, 130, 255), -- blue
		Color3.fromRGB(70, 255, 110), -- green
	}
	local baseYaw = decorRng:NextNumber() * math.pi * 2
	for i, col in ipairs(colors) do
		local yaw = baseYaw + (i - 1) * (2 * math.pi / 3) + (decorRng:NextNumber() - 0.5) * 0.5
		local tilt = math.rad(28 + decorRng:NextInteger(0, 16)) -- ~28-44° above horizontal (sideways)
		local dir = Vector3.new(math.cos(yaw) * math.cos(tilt), math.sin(tilt), math.sin(yaw) * math.cos(tilt))
		buildCrystalShard(model, root, dir, col, 12 + decorRng:NextNumber() * 4, true)
	end
	model.Parent = laneFolder
end

-- a BIG glowing mushroom — TALLER than a player, with a wide cap that overhangs the stem so a
-- player can stand under it (like the reference). Soft-glow stem + a bright rainbow NEON cap
-- dotted with pale glowing spots. A dimmer halo so the mushroom's own form reads.
local function buildGlowMushroom(x: number, z: number, surfaceY: number)
	local model = Instance.new("Model")
	model.Name = "GlowMushroom"
	local cap = cavernRainbow()
	local totalH = 9 + decorRng:NextNumber() * 4 -- ~9-13 studs: clears a ~5-stud player + overhang
	local stemH = totalH * 0.58
	local stemW = 1.7 + decorRng:NextNumber() * 0.9
	local stem = makePart({
		Name = "Stem",
		NoStuds = true,
		Size = Vector3.new(stemW, stemH, stemW),
		Color = Color3.fromRGB(170, 182, 215), -- soft pale glow (dimmer than the cap)
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		CFrame = CFrame.new(x, surfaceY + stemH / 2, z),
		Parent = model,
	})
	model.PrimaryPart = stem
	local capW = stemW * 3.4 + decorRng:NextNumber() * 2 -- WIDE cap that overhangs the stem
	local capH = capW * 0.5
	local capY = surfaceY + stemH + capH * 0.18
	local capPart = makePart({
		Name = "Cap",
		NoStuds = true,
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(capW, capH, capW), -- flattened ball = rounded dome
		Color = cap:Lerp(Color3.new(0, 0, 0), 0.2), -- deepened so the dome + pale spots read (not a blinding blob)
		Material = Enum.Material.Neon,
		CanCollide = false,
		CastShadow = false,
		CFrame = CFrame.new(x, capY, z),
		Parent = model,
	})
	-- pale glowing spots dotted over the dome (reference look), snapped to the cap surface
	for _ = 1, decorRng:NextInteger(5, 8) do
		local ang = decorRng:NextNumber() * math.pi * 2
		local rad = (0.12 + decorRng:NextNumber() * 0.32) * (capW / 2)
		local rNorm = rad / (capW / 2)
		local sy = capY + (capH / 2) * math.sqrt(math.max(0, 1 - rNorm * rNorm)) * 0.9
		local spotW = 0.5 + decorRng:NextNumber() * 0.7
		makePart({
			Name = "CapSpot",
			NoStuds = true,
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(spotW, spotW * 0.5, spotW),
			Color = Color3.fromRGB(245, 250, 255),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			CFrame = CFrame.new(x + math.cos(ang) * rad, sy, z + math.sin(ang) * rad),
			Parent = model,
		})
	end
	addGlow(capPart, cap, 0.9, 12) -- dimmer halo so the mushroom's shape reads
	model.Parent = laneFolder
end

-- a tuft of LONG, DROOPY glowing reed blades (a single random rainbow colour per tuft). Each
-- blade is two segments that bend over so it arcs/droops instead of standing straight up.
local function buildGlowGrass(x: number, z: number, surfaceY: number)
	local clump = Instance.new("Model")
	clump.Name = "GlowGrass"
	local col = cavernRainbow():Lerp(Color3.new(0, 0, 0), 0.12) -- toned down a touch (less blinding)
	local primary: BasePart? = nil
	-- one leaning neon segment from `base` toward `yaw`, `tilt` off vertical; returns its top point
	local function seg(base: Vector3, yaw: number, tilt: number, len: number, w: number): Vector3
		local rot = CFrame.Angles(0, yaw, 0) * CFrame.Angles(tilt, 0, 0)
		local up = rot.UpVector
		local center = base + up * (len / 2)
		local blade = makePart({
			Name = "Blade",
			NoStuds = true,
			Size = Vector3.new(w, len * 1.04, w),
			Color = jitterColor(col, 0.06),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			CFrame = CFrame.new(center) * rot,
			Parent = clump,
		})
		primary = primary or blade
		return base + up * len
	end
	for _ = 1, decorRng:NextInteger(3, 5) do
		local yaw = decorRng:NextNumber() * math.pi * 2
		local base = Vector3.new(x + (decorRng:NextNumber() - 0.5) * 1.9, surfaceY, z + (decorRng:NextNumber() - 0.5) * 1.9)
		-- lower segment leans a little; upper segment droops MORE so the blade arcs over
		local tilt1 = math.rad(14 + decorRng:NextInteger(0, 14))
		local top = seg(base, yaw, tilt1, 2.6 + decorRng:NextNumber() * 1.7, 0.3)
		local tilt2 = tilt1 + math.rad(38 + decorRng:NextInteger(0, 30))
		seg(top, yaw, tilt2, 2.2 + decorRng:NextNumber() * 1.8, 0.24)
	end
	clump.PrimaryPart = primary
	clump.Parent = laneFolder
end

-- crystals jutting out of the two border cliffs INTO the zone (random rainbow), at varied
-- heights along each wall, angled inward + slightly down. Stay well clear of the dig core.
local function buildWallCrystals(zone: number, centerZ: number)
	local cx = MapBuilder.DigCenter.X
	local wallTopY = 1 + LANE_SIDE_BODY_H -- top of the dirt cliff body
	local halfZ = LANE_STEP / 2 - 16
	for _, sign in ipairs({ -1, 1 }) do
		for _ = 1, decorRng:NextInteger(3, 5) do
			local z = centerZ + (decorRng:NextNumber() - 0.5) * 2 * halfZ
			local y = 7 + decorRng:NextNumber() * math.max(6, wallTopY - 16) -- up the wall face
			local root = Vector3.new(cx + sign * (LANE_SIDE_INNER_X - 1), y, z) -- embed 1 stud into the cliff
			local dir = Vector3.new(
				-sign * (0.8 + decorRng:NextNumber() * 0.2), -- inward (toward centre)
				-0.1 - decorRng:NextNumber() * 0.3, -- slightly down
				(decorRng:NextNumber() - 0.5) * 0.6 -- some z spread
			)
			local model = Instance.new("Model")
			model.Name = "WallCrystal"
			buildCrystalShard(model, root, dir, cavernRainbow(), 7 + decorRng:NextNumber() * 4.5, decorRng:NextNumber() < 0.4)
			model.Parent = laneFolder
		end
	end
end

-- CRYSTAL CAVERNS decor: the one main crystal cluster + tall glowing mushrooms + glowing grass
-- scattered around the RIM (kept OUT of the central dig-mound core), plus crystals on the walls.
local function buildCavernDecor(zone: number, centerZ: number)
	local cx = MapBuilder.DigCenter.X
	local halfX = LANE_SIDE_INNER_X - 12 -- stay clear of the cliffs
	local halfZ = LANE_STEP / 2 - 12     -- stay clear of the rebirth walls
	local CORE = 48 -- keep all floor decor OUTSIDE the central dig-mound core (DigHalf 40 + margin)

	-- surface-snap raycast against the floor ONLY (ground + this zone's dig plate / border)
	local surfaces: { Instance } = {}
	local world = Workspace:FindFirstChild("World")
	local ground = world and world:FindFirstChild("Ground")
	if ground then
		surfaces[#surfaces + 1] = ground
	end
	for _, p in ipairs(laneFolder:GetChildren()) do
		if p:IsA("BasePart") and (p.Name == ("Zone%dDig"):format(zone) or p.Name == "ZoneBorder") then
			surfaces[#surfaces + 1] = p
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = surfaces
	local function surfaceYAt(x: number, z: number): number
		local hit = Workspace:Raycast(Vector3.new(x, 40, z), Vector3.new(0, -60, 0), params)
		return hit and hit.Position.Y or (LANE_SEG_Y + SEG_SIZE.Y / 2)
	end

	-- min-spacing picker that only returns positions OUTSIDE the dig core
	local placed: { { x: number, z: number } } = {}
	local function pickRim(gap: number): (number?, number?)
		for _ = 1, 20 do
			local x = cx + (decorRng:NextNumber() - 0.5) * 2 * halfX
			local z = centerZ + (decorRng:NextNumber() - 0.5) * 2 * halfZ
			if math.abs(x - cx) > CORE or math.abs(z - centerZ) > CORE then
				local ok = true
				for _, p in ipairs(placed) do
					if (x - p.x) ^ 2 + (z - p.z) ^ 2 < gap * gap then
						ok = false
						break
					end
				end
				if ok then
					placed[#placed + 1] = { x = x, z = z }
					return x, z
				end
			end
		end
		return nil, nil
	end

	-- 1) THE main crystal (red/blue/green), off to one side of the rim
	local mx = cx + (decorRng:NextNumber() < 0.5 and -1 or 1) * (54 + decorRng:NextNumber() * 12)
	local mz = centerZ + (decorRng:NextNumber() - 0.5) * 2 * (halfZ - 26)
	buildCrystalCluster(mx, mz, surfaceYAt(mx, mz))
	placed[#placed + 1] = { x = mx, z = mz }
	addDigExclusion(mx, mz, 16, zone)

	-- 2) tall glowing mushrooms (~player height) around the rim
	for _ = 1, 6 do
		local x, z = pickRim(15)
		if x and z then
			buildGlowMushroom(x, z, surfaceYAt(x, z))
			addDigExclusion(x, z, 5, zone)
		end
	end

	-- 3) glowing grass / plants (random rainbow) scattered around the rim
	for _ = 1, 46 do
		local x, z = pickRim(5)
		if x and z then
			buildGlowGrass(x, z, surfaceYAt(x, z))
		end
	end

	-- 4) crystals jutting from the border walls into the zone
	buildWallCrystals(zone, centerZ)
end

-- frame every rebirth wall with rock piles + add per-zone theme decor (trees / cacti / ice).
local function decorateLane()
	-- NOTE: the Cherry-blossom decor builders are declared INSIDE decorateLane (not at module
	-- scope) on purpose. BaseManager's main chunk is near Luau's hard 200-locals-per-function cap;
	-- declaring these at the top level overflowed it ("Out of local registers"), which made the
	-- whole module fail to load and the map never build. Keeping them function-local fixes that.
------------------------------------------------------------- CHERRY BLOSSOM (zone 6)
local CHERRY_PINK = Color3.fromRGB(255, 150, 200)
local CHERRY_PINK2 = Color3.fromRGB(255, 122, 184)
local CHERRY_WOOD = Palette.TreeTrunk -- plank / lantern-cap wood
local LANTERN_RED = Color3.fromRGB(214, 48, 52)

-- world-space VISIBLE bbox (min, max) of a model — ignores invisible/oversized helper parts so an
-- imported model grounds on its real trunk, not a stray root part (see imported-model scale caveat).
local function visibleAABB(model: Model): (Vector3, Vector3)
	local mn = Vector3.new(math.huge, math.huge, math.huge)
	local mx = Vector3.new(-math.huge, -math.huge, -math.huge)
	local found = false
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.95 then
			found = true
			local cf, sz = d.CFrame, d.Size
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
		local _, sz = model:GetBoundingBox()
		local p = model:GetPivot().Position
		return p - sz / 2, p + sz / 2
	end
	return mn, mx
end

-- procedural sakura fallback (used only if ServerStorage.CherryModel is missing from the build)
local function buildProceduralCherry(x: number, z: number, surfaceY: number, height: number)
	local tree = Instance.new("Model")
	tree.Name = "CherryTree"
	local trunkH = height * 0.5
	local trunk = makePart({
		Name = "Trunk", Size = Vector3.new(2.4, trunkH, 2.4), Color = Palette.TreeTrunk,
		CanCollide = false, CastShadow = false, CFrame = CFrame.new(x, surfaceY + trunkH / 2, z), Parent = tree,
	})
	tree.PrimaryPart = trunk
	local canopyY = surfaceY + trunkH
	for _ = 1, 6 do
		local r = height * (0.3 + decorRng:NextNumber() * 0.14)
		makePart({
			Name = "Blossom", Shape = Enum.PartType.Ball, NoStuds = true,
			Size = Vector3.new(r, r * 0.85, r), Color = jitterColor(CHERRY_PINK, 0.06),
			CanCollide = false, CastShadow = false,
			CFrame = CFrame.new(x + (decorRng:NextNumber() - 0.5) * height * 0.45, canopyY + (decorRng:NextNumber() - 0.25) * height * 0.3, z + (decorRng:NextNumber() - 0.5) * height * 0.45),
			Parent = tree,
		})
	end
	tree.Parent = laneFolder
end

-- place one cherry tree: clone the SANITIZED ServerStorage.CherryModel, ground it on its VISIBLE
-- base, anchor + make non-collidable (so it never traps a digging player). Procedural fallback.
local function placeCherryTree(x: number, z: number, surfaceY: number, scale: number?)
	local SS = game:GetService("ServerStorage")
	local template = SS:FindFirstChild("CherryModel")
	if not (template and template:IsA("Model")) then
		buildProceduralCherry(x, z, surfaceY, decorRng:NextInteger(20, 28) * (scale or 1))
		return
	end
	local tree = template:Clone()
	if scale and scale ~= 1 then
		pcall(function() tree:ScaleTo(scale) end) -- bigger sakura (pcall: never let a scale quirk break the build)
	end
	tree:PivotTo(tree:GetPivot() * CFrame.Angles(0, math.rad(decorRng:NextInteger(0, 359)), 0))
	local mn, mx = visibleAABB(tree)
	local center = (mn + mx) / 2
	tree:PivotTo(tree:GetPivot() + Vector3.new(x - center.X, surfaceY - mn.Y, z - center.Z))
	for _, d in ipairs(tree:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CastShadow = false
		end
	end
	tree.Name = "CherryTree"
	tree.Parent = laneFolder
end

-- a flat pink petal patch lying on the floor at a jittered micro-height (so overlapping patches
-- never z-fight). Many of these carpet the zone so the green grass barely shows through.
local function buildPetalPatch(x: number, z: number, surfaceY: number)
	local s = decorRng:NextNumber(8.0, 13.0)
	makePart({
		Name = "Petals", NoStuds = true,
		Size = Vector3.new(s, 0.2, s * decorRng:NextNumber(0.75, 1.1)),
		Color = jitterColor((decorRng:NextNumber() < 0.5) and CHERRY_PINK or CHERRY_PINK2, 0.05),
		CanCollide = false, CastShadow = false,
		-- lie nearly flat (tiny 0.1-0.2 height jitter ONLY to avoid coplanar z-fighting; no piling)
		CFrame = CFrame.new(x, surfaceY + 0.1 + decorRng:NextNumber() * 0.1, z) * CFrame.Angles(0, math.rad(decorRng:NextInteger(0, 359)), 0),
		Parent = laneFolder,
	})
end

-- THREE wood planks jutting from EACH border wall (the ±X lane cliffs) within the zone, each with
-- a dim red lantern hanging off its lane-side end. Light brightness kept low ("not THAT bright").
local function buildCherryPlankLanterns(centerZ: number)
	local cx = MapBuilder.DigCenter.X
	local wallX = LANE_SIDE_INNER_X   -- inner cliff face (±100)
	local PLANK_LEN, PLANK_Y = 11, 34 -- protrude 11 studs into the lane; mounted HIGH (34) up the wall
	for _, sign in ipairs({ -1, 1 }) do
		for _, dz in ipairs({ -46, 0, 46 }) do
			local z = centerZ + dz
			local outerX = cx + sign * (wallX - PLANK_LEN)      -- plank's lane-side end (lantern hangs here)
			local plankCx = cx + sign * (wallX - PLANK_LEN / 2) -- plank centre
			makePart({ -- the plank (horizontal wood beam from the wall)
				Name = "CherryPlank", Size = Vector3.new(PLANK_LEN, 1, 1.8), Color = CHERRY_WOOD,
				CFrame = CFrame.new(plankCx, PLANK_Y, z), Parent = laneFolder,
			})
			local lanternCy = PLANK_Y - 6.5
			for _, sxo in ipairs({ -0.7, 0.7 }) do -- two short hanging strings
				makePart({
					Name = "LanternString", NoStuds = true, Material = Enum.Material.SmoothPlastic,
					Size = Vector3.new(0.2, 4.6, 0.2), Color = Color3.fromRGB(40, 30, 20),
					CanCollide = false, CastShadow = false,
					CFrame = CFrame.new(outerX, PLANK_Y - 2.3, z + sxo), Parent = laneFolder,
				})
			end
			local lantern = makePart({ -- upright cylindrical red lantern (soft Neon)
				Name = "CherryLantern", NoStuds = true, Material = Enum.Material.Neon, Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(4.5, 3.2, 3.2), Color = LANTERN_RED, CanCollide = false, CastShadow = false,
				CFrame = CFrame.new(outerX, lanternCy, z) * CFrame.Angles(0, 0, math.rad(90)), Parent = laneFolder,
			})
			for _, capDy in ipairs({ 2.0, -2.0 }) do -- wood caps top + bottom
				makePart({
					Name = "LanternCap", NoStuds = true, Size = Vector3.new(3.4, 0.6, 3.4), Color = CHERRY_WOOD,
					CanCollide = false, CastShadow = false, CFrame = CFrame.new(outerX, lanternCy + capDy, z), Parent = laneFolder,
				})
			end
			local light = Instance.new("PointLight") -- DIM red glow
			light.Color = LANTERN_RED
			light.Brightness = 1.1
			light.Range = 14
			light.Shadows = false
			light.Parent = lantern
		end
	end
end

-- WOOD-PLANK border walls: clad the inner face of both lane cliffs (within this zone) with a row of
-- vertical wood planks (two alternating tones) so the border reads as a wooden plank wall.
local function buildCherryWoodWalls(centerZ: number)
	local cx = MapBuilder.DigCenter.X
	local wallX = LANE_SIDE_INNER_X                  -- inner cliff face (±100)
	local wallH = LANE_SIDE_BODY_H + LANE_SIDE_CAP_H - 1.5 -- just under the grass-cap top (avoids a coplanar z-fight there)
	local z0, z1 = centerZ - (LANE_STEP / 2 - 3), centerZ + (LANE_STEP / 2 - 3)
	local woodA, woodB = Palette.Fence, Color3.fromRGB(150, 84, 40)
	local PLANK_W = 5
	for _, sign in ipairs({ -1, 1 }) do
		local i, z = 0, z0
		while z <= z1 do
			makePart({
				Name = "CherryWoodWall",
				-- THICK plank (7): its back embeds INTO the dirt cliff so the cliff face is hidden inside it
				-- (no near-coplanar surfaces) -> no z-fighting / flicker on either wall.
				Size = Vector3.new(7, wallH, PLANK_W - 0.4),
				Color = (i % 2 == 0) and woodA or woodB,
				CFrame = CFrame.new(cx + sign * (wallX - 0.5), 1 + wallH / 2, z),
				Parent = laneFolder,
			})
			i += 1
			z += PLANK_W
		end
	end
end

-- CHERRY BLOSSOM theme: sakura trees (clear of the dig mounds via no-dig rings), a pink-petal carpet
-- over the whole zone (grass barely showing), + plank-hung dim red lanterns on both border walls.
local function buildCherryBlossomDecor(zone: number, centerZ: number)
	local cx = MapBuilder.DigCenter.X
	local digSurfaceY = LANE_SEG_Y + SEG_SIZE.Y / 2

	-- raycast only against flat surfaces (ground + this zone's dig plate + border), never decor
	local surfaces: { Instance } = {}
	local world = Workspace:FindFirstChild("World")
	local ground = world and world:FindFirstChild("Ground")
	if ground then
		surfaces[#surfaces + 1] = ground
	end
	for _, p in ipairs(laneFolder:GetChildren()) do
		if p:IsA("BasePart") and (p.Name == ("Zone%dDig"):format(zone) or p.Name == "ZoneBorder") then
			surfaces[#surfaces + 1] = p
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = surfaces
	local function surfaceYAt(x: number, z: number): number
		local hit = Workspace:Raycast(Vector3.new(x, 60, z), Vector3.new(0, -120, 0), params)
		return hit and hit.Position.Y or LANE_SEG_Y
	end

	local halfX = LANE_SIDE_INNER_X - 6
	local halfZ = LANE_STEP / 2 - 6

	-- 1) PETAL CARPET — GRID-TILED so the leaves FULLY cover the floor (overlapping patches, no gaps;
	--    the grass underneath is completely hidden — no floor recolour needed).
	local STEP, pHX, pHZ = 6, LANE_SIDE_INNER_X - 2, LANE_STEP / 2 - 3
	local gz = centerZ - pHZ
	while gz <= centerZ + pHZ do
		local gxx = cx - pHX
		while gxx <= cx + pHX do
			local px = gxx + (decorRng:NextNumber() - 0.5) * 3
			local pz = gz + (decorRng:NextNumber() - 0.5) * 3
			buildPetalPatch(px, pz, surfaceYAt(px, pz))
			gxx += STEP
		end
		gz += STEP
	end

	-- 2) CHERRY TREES, kept OFF the dig mounds: a ring outside the DigHalf(40) core + a few inside
	--    the core each ringed by a no-dig exclusion so mounds never spawn on them.
	local placed: { { x: number, z: number } } = {}
	local function farEnough(x: number, z: number, gap: number): boolean
		for _, p in ipairs(placed) do
			if (x - p.x) ^ 2 + (z - p.z) ^ 2 < gap * gap then
				return false
			end
		end
		return true
	end
	for _ = 1, 4 do -- FEWER, BIGGER outer-rim trees (radius 52-90, between the mound core and the walls)
		for _ = 1, 14 do
			local ang = decorRng:NextNumber() * math.pi * 2
			local rad = 52 + decorRng:NextNumber() * 38
			local x = cx + math.cos(ang) * rad
			local z = centerZ + math.sin(ang) * rad
			if math.abs(x - cx) < halfX and math.abs(z - centerZ) < halfZ and farEnough(x, z, 34) then
				placed[#placed + 1] = { x = x, z = z }
				placeCherryTree(x, z, surfaceYAt(x, z), 1.45)
				addDigExclusion(x, z, 18, zone) -- whole slab is diggable now → keep mounds off the trunk
				break
			end
		end
	end
	for _, s in ipairs({ { 25, 17 }, { -23, -19 } }) do -- 2 bigger trees inside the dig core
		local x = cx + s[1] + (decorRng:NextNumber() - 0.5) * 6
		local z = centerZ + s[2] + (decorRng:NextNumber() - 0.5) * 6
		placeCherryTree(x, z, digSurfaceY, 1.45)
		addDigExclusion(x, z, 19, zone)
	end

	-- 3) WOOD-PLANK border walls + protruding planks with dim red lanterns (3 per side)
	buildCherryWoodWalls(centerZ)
	buildCherryPlankLanterns(centerZ)
end

------------------------------------------------------------- HAUNTED HOLLOW (zone 7)
-- a bare, gnarled DEAD TREE: a leaf-less grey-brown trunk with a few crooked branches forking up
-- and out. NON-collidable (like the other digsite decor) so it never traps a digging player.
local function buildDeadTree(x: number, z: number, surfaceY: number)
	local model = Instance.new("Model")
	model.Name = "DeadTree"
	local h = decorRng:NextInteger(12, 18) + decorRng:NextNumber()
	local tw = 1.5 + decorRng:NextNumber() * 0.9
	local trunk = makePart({
		Name = "DeadTrunk",
		Size = Vector3.new(tw, h, tw),
		Color = jitterColor(Palette.DeadWood, 0.06),
		CanCollide = false,
		CastShadow = false,
		CFrame = CFrame.new(x, surfaceY + h / 2, z) * CFrame.Angles(math.rad(decorRng:NextInteger(-4, 4)), 0, math.rad(decorRng:NextInteger(-4, 4))),
		Parent = model,
	})
	model.PrimaryPart = trunk
	-- one crooked branch (+ a chance of a smaller fork at its tip) growing from a point up the trunk
	local function branch(bp: Vector3, dir: Vector3, len: number, w: number)
		local center = bp + dir * (len / 2)
		makePart({
			Name = "DeadBranch",
			Size = Vector3.new(w, w, len * 1.03),
			Color = jitterColor(Palette.DeadWood, 0.05),
			CanCollide = false,
			CastShadow = false,
			CFrame = CFrame.lookAt(center, bp + dir),
			Parent = model,
		})
	end
	for _ = 1, decorRng:NextInteger(4, 6) do
		local yaw = decorRng:NextNumber() * math.pi * 2
		local tilt = math.rad(decorRng:NextInteger(34, 62)) -- up from horizontal (reaching skyward)
		local dir = Vector3.new(math.cos(yaw) * math.cos(tilt), math.sin(tilt), math.sin(yaw) * math.cos(tilt))
		local bp = Vector3.new(x, surfaceY + h * (0.5 + decorRng:NextNumber() * 0.45), z)
		local len = 4 + decorRng:NextNumber() * 4
		local w = 0.6 + decorRng:NextNumber() * 0.5
		branch(bp, dir, len, w)
		if decorRng:NextNumber() < 0.6 then -- a smaller twig forking off the branch tip
			local tip = bp + dir * len
			local yaw2 = yaw + (decorRng:NextNumber() - 0.5) * 1.5
			local tilt2 = tilt + math.rad(decorRng:NextInteger(-12, 22))
			local dir2 = Vector3.new(math.cos(yaw2) * math.cos(tilt2), math.sin(tilt2), math.sin(yaw2) * math.cos(tilt2))
			branch(tip, dir2, 2.5 + decorRng:NextNumber() * 2.5, w * 0.7)
		end
	end
	model.Parent = laneFolder
end

-- one carved JACK-O'-LANTERN with a GLOWING face. `expr` (1/2/3) picks a different expression:
-- 1 = classic toothy grin, 2 = angry slanted eyes, 3 = surprised round "O". Non-collidable.
local function buildJackOLantern(x: number, z: number, surfaceY: number, expr: number)
	local model = Instance.new("Model")
	model.Name = "JackOLantern"
	local w = 9 + decorRng:NextNumber() * 3 -- 9-12 wide (big, chunky pumpkin)
	local bodyH = w * 0.82
	local depth = w * 0.9
	local r = w * 0.14 -- vertical-edge rounding radius (makes it a SEMI-rectangular rounded box)
	-- mostly face the lobby (-Z, the way the player walks in) with a little random yaw
	local base = CFrame.new(x, surfaceY + bodyH / 2, z) * CFrame.Angles(0, math.rad(decorRng:NextInteger(-20, 20)), 0)
	local pumpkinColor = jitterColor(Palette.Pumpkin, 0.04)
	local function bodyPart(size: Vector3, cf: CFrame, color: Color3?): BasePart
		return makePart({
			Name = "Pumpkin", NoStuds = true, Size = size, Color = color or pumpkinColor,
			CanCollide = false, CastShadow = false, CFrame = cf, Parent = model,
		})
	end
	-- SEMI-RECTANGULAR body: a squat ROUNDED BOX (two crossed slabs + 4 vertical corner cylinders).
	-- The crucial part is the FLAT FRONT face — so the carved face sits flush IN it (a sphere made the
	-- features float off the curving surface). Front face = the wide slab's -Z face at z = -depth/2.
	local body = bodyPart(Vector3.new(w - 2 * r, bodyH, depth), base) -- spans the FLAT front
	model.PrimaryPart = body
	bodyPart(Vector3.new(w, bodyH, depth - 2 * r), base) -- spans the full width (rounds front/back edges)
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			makePart({
				Name = "Pumpkin", Shape = Enum.PartType.Cylinder, NoStuds = true,
				Size = Vector3.new(bodyH, 2 * r, 2 * r), Color = pumpkinColor,
				CanCollide = false, CastShadow = false,
				CFrame = base * CFrame.new(sx * (w / 2 - r), 0, sz * (depth / 2 - r)) * CFrame.Angles(0, 0, math.rad(90)),
				Parent = model,
			})
		end
	end
	-- pumpkin RIBS: a couple of darker vertical grooves flanking the face (sells the pumpkin shape)
	local ribColor = jitterColor(Palette.Pumpkin:Lerp(Color3.new(0, 0, 0), 0.2), 0.03)
	for _, rs in ipairs({ -1, 1 }) do
		bodyPart(Vector3.new(0.55, bodyH * 0.96, 0.7), base * CFrame.new(rs * (w / 2 - r - 0.4), 0, -depth / 2 - 0.05), ribColor)
	end
	-- a short crooked stem on top
	makePart({
		Name = "Stem",
		NoStuds = true,
		Size = Vector3.new(w * 0.15, w * 0.4, w * 0.15),
		Color = jitterColor(Palette.DeadWood, 0.05),
		CanCollide = false,
		CastShadow = false,
		CFrame = base * CFrame.new(0, bodyH / 2, 0) * CFrame.Angles(math.rad(10), 0, math.rad(7)),
		Parent = model,
	})
	-- GLOWING face CARVED INTO the FLAT FRONT: every feature sits flush in the front face (all at the
	-- same z = -depth/2, body sunk inward) so they read as glowing cut-outs, never floating blocks.
	-- `s` scales the face layout to the pumpkin size.
	local GLOW = Color3.fromRGB(255, 214, 90)
	local frontZ = -depth / 2
	local s = w / 6 -- face layout scale (the literals below are tuned at w≈6)
	local function face(lx: number, ly: number, sx: number, sy: number, roll: number, ball: boolean?)
		lx, ly, sx, sy = lx * s, ly * s, sx * s, sy * s
		local thick = 1.2
		local cz = frontZ - 0.06 + thick / 2 -- outer face 0.06 proud of the flat front, body sunk inward
		makePart({
			Name = "Face",
			Shape = ball and Enum.PartType.Ball or Enum.PartType.Block,
			NoStuds = true,
			Size = Vector3.new(sx, sy, thick),
			Color = GLOW,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CastShadow = false,
			CFrame = base * CFrame.new(lx, ly, cz) * CFrame.Angles(0, 0, math.rad(roll)),
			Parent = model,
		})
	end
	-- a jagged toothy grin: a row of neon teeth across, with alternating heights
	local function grin(yMid: number, span: number, n: number)
		for i = 1, n do
			local t = (i - 0.5) / n
			local lx = -span / 2 + t * span
			local th = 0.7 + ((i % 2 == 0) and 0.5 or 0.0)
			face(lx, yMid + ((i % 2 == 0) and -0.1 or 0.15), 0.55, th, 0)
		end
	end
	if expr == 2 then
		-- ANGRY: slanted brows-down eyes + a small clenched grin
		face(-1.25, 0.7, 1.7, 0.95, 28)
		face(1.25, 0.7, 1.7, 0.95, -28)
		face(0, 0.05, 0.7, 0.7, 45) -- diamond nose
		grin(-1.05, 3.0, 5)
	elseif expr == 3 then
		-- SURPRISED: round eyes + a round "O" mouth
		face(-1.2, 0.75, 1.2, 1.2, 0, true)
		face(1.2, 0.75, 1.2, 1.2, 0, true)
		face(0, 0.05, 0.55, 0.55, 0, true) -- round nose
		face(0, -1.15, 1.7, 1.7, 0, true)  -- O mouth
	else
		-- CLASSIC: triangle-ish diamond eyes + diamond nose + a wide jagged grin
		face(-1.2, 0.7, 1.35, 1.35, 45)
		face(1.2, 0.7, 1.35, 1.35, 45)
		face(0, 0.0, 0.8, 0.8, 45) -- diamond nose
		grin(-1.1, 3.4, 6)
	end
	-- inner glow so the whole pumpkin glows from within (spooky)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 150, 40)
	light.Brightness = 2.4
	light.Range = w + 6
	light.Shadows = false
	light.Parent = body
	model.Parent = laneFolder
end

-- COBWEB STRINGS: pale silk strands strung in a sagging PARABOLA from the LEFT border cliff to the
-- RIGHT border cliff (border-to-border), high overhead so they arch across the whole zone. A few at
-- different depths/heights, with a couple of hanging droop strands for a tattered cobweb feel.
local function buildCobwebStrands(centerZ: number)
	local cx = MapBuilder.DigCenter.X
	local half = LANE_SIDE_INNER_X -- anchor into both cliff inner faces (±100)
	-- one thin silk segment between two world points
	local function strand(p1: Vector3, p2: Vector3, wdt: number)
		local center = (p1 + p2) / 2
		local len = (p2 - p1).Magnitude
		makePart({
			Name = "Cobweb",
			NoStuds = true,
			Material = Enum.Material.SmoothPlastic,
			Size = Vector3.new(wdt, wdt, len),
			Color = Palette.Web,
			Transparency = 0.2,
			CanCollide = false,
			CastShadow = false,
			CFrame = CFrame.lookAt(center, p2),
			Parent = laneFolder,
		})
	end
	-- one sagging parabola at lane offset `dz`, top-anchored at `yTop`, dipping `sag` in the middle
	local function parabola(dz: number, yTop: number, sag: number, wdt: number)
		local SAMPLES = 16
		local prev: Vector3? = nil
		local pts: { Vector3 } = {}
		for i = 0, SAMPLES do
			local t = i / SAMPLES
			local px = -half + t * 2 * half -- -half .. +half
			local norm = px / half          -- -1 .. 1
			local py = yTop - sag * (1 - norm * norm)
			local pt = Vector3.new(cx + px, py, centerZ + dz)
			pts[#pts + 1] = pt
			if prev then
				strand(prev, pt, wdt)
			end
			prev = pt
		end
		-- a couple of tattered droop strands hanging straight down from mid-span sample points
		for _ = 1, 2 do
			local p = pts[decorRng:NextInteger(6, 12)]
			strand(p, p - Vector3.new(0, 3 + decorRng:NextNumber() * 4, 0), wdt * 0.85)
		end
	end
	-- three strings down the zone at staggered heights so they read as separate cobwebs
	parabola(-46, 28, 12, 0.35)
	parabola(0, 34, 16, 0.4)
	parabola(46, 26, 11, 0.35)
end

-- HAUNTED HOLLOW decor: dead trees + a few jack-o-lanterns scattered across the zone (each ringed by
-- a no-dig marker), plus cobweb strings strung border-to-border overhead.
local function buildHauntedDecor(zone: number, centerZ: number)
	local cx = MapBuilder.DigCenter.X
	local surfaceY = LANE_SEG_Y + SEG_SIZE.Y / 2 -- top of the (full-zone) floor
	local SPREAD_X = LANE_SIDE_INNER_X - 14 -- ~86: across the lane width, off the cliffs
	local SPREAD_Z = LANE_STEP / 2 - 16     -- ~58: down the zone, off the walls
	local placed: { { x: number, z: number } } = {}
	local function pick(gap: number): (number?, number?)
		for _ = 1, 16 do
			local x = cx + (decorRng:NextNumber() - 0.5) * 2 * SPREAD_X
			local z = centerZ + (decorRng:NextNumber() - 0.5) * 2 * SPREAD_Z
			local ok = true
			for _, p in ipairs(placed) do
				if (x - p.x) ^ 2 + (z - p.z) ^ 2 < gap * gap then
					ok = false
					break
				end
			end
			if ok then
				placed[#placed + 1] = { x = x, z = z }
				return x, z
			end
		end
		return nil, nil
	end
	for _ = 1, 8 do -- dead trees scattered around the zone
		local x, z = pick(20)
		if x and z then
			buildDeadTree(x, z, surfaceY)
			addDigExclusion(x, z, 9, zone)
		end
	end
	for i = 1, 3 do -- 3 jack-o-lanterns (now bigger), each a different expression
		local x, z = pick(24)
		if x and z then
			buildJackOLantern(x, z, surfaceY, i)
			addDigExclusion(x, z, 10, zone)
		end
	end
	-- cobweb strings strung in parabolas from border cliff to border cliff, overhead
	buildCobwebStrands(centerZ)
end

------------------------------------------------------------- CITY (zone 8)
-- A real-looking city STREET hiding the border cliffs: thick-cardboard building FACADES (bakery /
-- deli / towers …) packed along both border walls, at least as tall as the walls, + an asphalt
-- TWO-WAY ROAD on the floor running toward the next zone.
local CITY_WALLS = {
	Color3.fromRGB(198, 96, 82),   -- brick red
	Color3.fromRGB(214, 198, 168), -- tan stone
	Color3.fromRGB(150, 166, 186), -- blue-grey concrete
	Color3.fromRGB(120, 152, 176), -- steel blue
	Color3.fromRGB(206, 174, 122), -- sandstone
	Color3.fromRGB(176, 184, 196), -- light concrete
	Color3.fromRGB(120, 174, 152), -- mint
}
local CITY_AWNINGS = {
	Color3.fromRGB(214, 64, 64), Color3.fromRGB(64, 150, 220),
	Color3.fromRGB(80, 184, 92), Color3.fromRGB(236, 172, 60),
}
local CITY_SHOPS = { "BAKERY", "DELI", "CAFE", "MARKET", "PIZZA", "BANK", "HOTEL", "BOOKS", "DINER", "TOYS", "SUBS", "FLORIST" }

-- a flat ROAD MARKING slab lying just above the asphalt floor (non-collidable), optional yaw.
local function roadMark(x: number, z: number, sx: number, sz: number, color: Color3, surfaceY: number, yawDeg: number?)
	local cf = CFrame.new(MapBuilder.DigCenter.X + x, surfaceY + 0.12, z)
	if yawDeg then
		cf = cf * CFrame.Angles(0, math.rad(yawDeg), 0)
	end
	makePart({
		Name = "RoadMark", NoStuds = true, Material = Enum.Material.SmoothPlastic,
		Size = Vector3.new(sx, 0.2, sz), Color = color, CanCollide = false, CastShadow = false,
		CFrame = cf, Parent = laneFolder,
	})
end

-- a forward CHEVRON arrow (points +Z, toward the next zone) centred at (x, z)
local function roadArrow(x: number, z: number, surfaceY: number)
	roadMark(x, z, 0.9, 6, Palette.RoadWhite, surfaceY)               -- shaft
	for _, s in ipairs({ -1, 1 }) do
		roadMark(x + s * 1.05, z + 2.0, 0.9, 4.2, Palette.RoadWhite, surfaceY, s * 38) -- chevron arms
	end
end

-- a CITY SIGN board with shop text mounted on a building front, facing the zone centre.
local function buildCitySign(faceX: number, y: number, z: number, sign: number, text: string)
	local board = makePart({
		Name = "CitySign", NoStuds = true, Material = Enum.Material.SmoothPlastic,
		Size = Vector3.new(0.5, 2.8, 8.5), Color = Color3.fromRGB(34, 34, 42),
		CanCollide = false, CFrame = CFrame.new(faceX, y, z), Parent = laneFolder,
	})
	local sg = Instance.new("SurfaceGui")
	sg.Name = "SignGui"
	sg.Face = (sign > 0) and Enum.NormalId.Left or Enum.NormalId.Right -- the face toward zone centre
	sg.CanvasSize = Vector2.new(900, 240)
	sg.LightInfluence = 0
	sg.Parent = board
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.FredokaOne
	lbl.TextScaled = true
	lbl.Text = text
	lbl.TextColor3 = Color3.fromRGB(255, 240, 180)
	lbl.TextStrokeTransparency = 0.2
	lbl.Parent = sg
end

-- one THICK-CARDBOARD building facade against a side cliff (sign = -1 left / +1 right), centred at z.
local function buildCityBuilding(sign: number, z: number, w: number, h: number, color: Color3, shop: string)
	local cx = MapBuilder.DigCenter.X
	local D = 7 -- cardboard thickness — reads as a real 3D building, not a flat poster
	local bodyX = cx + sign * (LANE_SIDE_INNER_X - D / 2) -- body centre (back flush with the cliff face)
	local frontX = cx + sign * (LANE_SIDE_INNER_X - D)    -- inner (zone-facing) wall face
	local faceX = frontX - sign * 0.18                    -- a hair proud of the front (windows/trim/sign)
	-- body + a darker roof parapet lip
	makePart({ Name = "CityBuilding", Size = Vector3.new(D, h, w), Color = color, CFrame = CFrame.new(bodyX, 1 + h / 2, z), Parent = laneFolder })
	makePart({ Name = "CityParapet", Size = Vector3.new(D + 0.8, 2, w + 0.8), Color = color:Lerp(Color3.new(0, 0, 0), 0.28), CFrame = CFrame.new(bodyX, 1 + h + 1, z), Parent = laneFolder })
	-- ground-floor storefront band (darker) + door + flanking shop windows + awning + sign
	local groundH = 9
	makePart({ Name = "CityStorefront", Size = Vector3.new(D + 0.3, groundH, w), Color = color:Lerp(Color3.new(0, 0, 0), 0.42), CFrame = CFrame.new(bodyX, 1 + groundH / 2, z), Parent = laneFolder })
	makePart({ Name = "CityDoor", NoStuds = true, Size = Vector3.new(0.3, groundH - 2.5, 3), Color = Color3.fromRGB(58, 44, 36), CanCollide = false, CFrame = CFrame.new(faceX, 1 + (groundH - 2.5) / 2, z), Parent = laneFolder })
	for _, dz in ipairs({ -1, 1 }) do
		makePart({ Name = "CityShopWin", NoStuds = true, Material = Enum.Material.Glass, Transparency = 0.3,
			Size = Vector3.new(0.3, groundH - 4, w * 0.26), Color = Color3.fromRGB(150, 210, 230), CanCollide = false,
			CFrame = CFrame.new(faceX, 1 + (groundH - 4) / 2 + 0.6, z + dz * (w * 0.28)), Parent = laneFolder })
	end
	makePart({ Name = "CityAwning", NoStuds = true, Material = Enum.Material.SmoothPlastic,
		Size = Vector3.new(3.0, 0.5, w * 0.92), Color = CITY_AWNINGS[decorRng:NextInteger(1, #CITY_AWNINGS)],
		CanCollide = false, CFrame = CFrame.new(frontX - sign * 1.4, 1 + groundH + 0.3, z), Parent = laneFolder })
	buildCitySign(faceX, 1 + groundH + 2.4, z, sign, shop)
	-- upper-floor WINDOW grid (some lit), painted on the front face
	local cols = math.max(2, math.floor(w / 7))
	local rows = math.max(1, math.floor((h - groundH - 5) / 5))
	local colStep = w / cols
	for r = 0, rows - 1 do
		for c = 0, cols - 1 do
			local wy = 1 + groundH + 3.5 + r * 5
			local wz = z - w / 2 + colStep * (c + 0.5)
			local lit = decorRng:NextNumber() < 0.45
			makePart({
				Name = "CityWindow", NoStuds = true,
				Material = lit and Enum.Material.Neon or Enum.Material.SmoothPlastic,
				Size = Vector3.new(0.3, 2.8, colStep * 0.5),
				Color = lit and Color3.fromRGB(255, 232, 150) or Color3.fromRGB(70, 96, 124),
				CanCollide = false, CastShadow = false,
				CFrame = CFrame.new(faceX, wy, wz), Parent = laneFolder,
			})
		end
	end
end

-- the CITY street: paint the two-way road + pack BOTH border walls with cardboard building facades.
local function buildCityDecor(zone: number, centerZ: number)
	local cx = MapBuilder.DigCenter.X
	local surfaceY = LANE_SEG_Y + SEG_SIZE.Y / 2
	local wallTop = 1 + LANE_SIDE_BODY_H + LANE_SIDE_CAP_H -- ~48: every building reaches AT LEAST this
	local z0 = centerZ - (LANE_STEP / 2 - 2)
	local z1 = centerZ + (LANE_STEP / 2 - 2)
	local roadLen = z1 - z0

	-- ROAD markings (run along the lane / +Z toward the next zone): double-yellow centre, white solid
	-- edges, dashed lane dividers, and forward arrows in each lane.
	roadMark(-1.1, centerZ, 0.7, roadLen, Palette.RoadYellow, surfaceY)
	roadMark(1.1, centerZ, 0.7, roadLen, Palette.RoadYellow, surfaceY)
	for _, sidex in ipairs({ -1, 1 }) do
		roadMark(sidex * 74, centerZ, 0.8, roadLen, Palette.RoadWhite, surfaceY) -- solid edge line
		local dz = z0 + 5 -- dashed lane divider
		while dz < z1 do
			roadMark(sidex * 38, dz, 0.6, 5, Palette.RoadWhite, surfaceY)
			dz = dz + 11
		end
		roadArrow(sidex * 19, centerZ - 22, surfaceY) -- forward arrows, one per lane × 2
		roadArrow(sidex * 19, centerZ + 26, surfaceY)
		roadArrow(sidex * 56, centerZ + 2, surfaceY)
		-- SIDEWALK strip in front of the buildings (light concrete, slightly raised)
		makePart({ Name = "CitySidewalk", Size = Vector3.new(16, 1, roadLen), Color = Palette.CitySidewalk,
			CFrame = CFrame.new(cx + sidex * (LANE_SIDE_INNER_X - 8), surfaceY + 0.3, centerZ), Parent = laneFolder })
	end

	-- BUILDINGS: fill each side wall edge-to-edge with varied facades, each ≥ the wall height
	for _, sign in ipairs({ -1, 1 }) do
		local z = z0 + 2
		while z < z1 - 8 do
			local w = decorRng:NextInteger(14, 24)
			if z + w > z1 - 2 then w = (z1 - 2) - z end
			if w < 9 then break end
			local h = wallTop + decorRng:NextInteger(2, 26) -- AT LEAST the wall height; some skyscrapers
			buildCityBuilding(sign, z + w / 2, w, h,
				CITY_WALLS[decorRng:NextInteger(1, #CITY_WALLS)], CITY_SHOPS[decorRng:NextInteger(1, #CITY_SHOPS)])
			z = z + w + decorRng:NextInteger(0, 1)
		end
	end
end

------------------------------------------------------------- PARK (zone 9)
local PARK_BRICK = Color3.fromRGB(184, 78, 54)   -- red paver brick
local PARK_BRICK2 = Color3.fromRGB(202, 100, 72) -- lighter red paver (variation)
local PATH_MORTAR = Color3.fromRGB(150, 150, 156) -- grey cement showing between the bricks
local PATH_CURB = Color3.fromRGB(150, 58, 44)     -- darker red brick curb (the taller edge outline)
local F_STONE = Color3.fromRGB(198, 200, 206) -- light fountain stone
local F_STONE2 = Color3.fromRGB(150, 154, 162)
local F_WATER = Color3.fromRGB(120, 205, 240)
local F_COL = Color3.fromRGB(124, 76, 76) -- maroon column

-- the central fountain. Prefers the IMPORTED model (ServerStorage.StuddedFountain) — clones it,
-- anchors + grounds it at the zone centre; falls back to a procedural deep-pool studded fountain
-- (used until StuddedFountain is exported into src/ServerStorage + mapped in default.project.json).
local function buildParkFountain(fx: number, fz: number, surfaceY: number): number
	local imported = game:GetService("ServerStorage"):FindFirstChild("StuddedFountain")
	if imported and imported:IsA("Model") then
		local m = imported:Clone()
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		local cf, size = m:GetBoundingBox()
		m:PivotTo(m:GetPivot() + Vector3.new(fx - cf.X, surfaceY - (cf.Y - size.Y / 2), fz - cf.Z))
		m.Name = "ParkFountain"
		m.Parent = laneFolder
		return math.max(size.X, size.Z) / 2
	end

	-- PROCEDURAL FALLBACK
	local model = Instance.new("Model")
	model.Name = "ParkFountain"
	model.Parent = laneFolder
	local OUT, RIMH, wallT = 26, 8, 3 -- outer footprint / deep rim / wall thickness
	local inner = OUT - wallT * 2
	-- base slab + 4 rim walls (square ring)
	makePart({ Name = "FountainBase", Size = Vector3.new(OUT + 2, 1, OUT + 2), Color = F_STONE2, CFrame = CFrame.new(fx, surfaceY + 0.5, fz), Parent = model })
	local cy = surfaceY + 1 + RIMH / 2
	makePart({ Name = "FountainRim", Size = Vector3.new(OUT, RIMH, wallT), Color = F_STONE, CFrame = CFrame.new(fx, cy, fz - (inner / 2 + wallT / 2)), Parent = model })
	makePart({ Name = "FountainRim", Size = Vector3.new(OUT, RIMH, wallT), Color = F_STONE, CFrame = CFrame.new(fx, cy, fz + (inner / 2 + wallT / 2)), Parent = model })
	makePart({ Name = "FountainRim", Size = Vector3.new(wallT, RIMH, inner), Color = F_STONE, CFrame = CFrame.new(fx - (inner / 2 + wallT / 2), cy, fz), Parent = model })
	makePart({ Name = "FountainRim", Size = Vector3.new(wallT, RIMH, inner), Color = F_STONE, CFrame = CFrame.new(fx + (inner / 2 + wallT / 2), cy, fz), Parent = model })
	-- basin floor (low) + a DEEP translucent water volume filling the basin
	makePart({ Name = "FountainFloor", Size = Vector3.new(inner, 1, inner), Color = F_STONE2, CFrame = CFrame.new(fx, surfaceY + 1.5, fz), Parent = model })
	makePart({ Name = "FountainWater", NoStuds = true, Material = Enum.Material.Glass, Transparency = 0.35,
		Size = Vector3.new(inner - 0.5, RIMH - 1.5, inner - 0.5), Color = F_WATER, CanCollide = false,
		CFrame = CFrame.new(fx, surfaceY + 2 + (RIMH - 1.5) / 2, fz), Parent = model })
	-- central pedestal + tiered column with white caps
	local pedH = RIMH + 1
	makePart({ Name = "FountainPed", Size = Vector3.new(8, pedH, 8), Color = F_COL, CFrame = CFrame.new(fx, surfaceY + 1 + pedH / 2, fz), Parent = model })
	local tierY = surfaceY + 1 + pedH
	for _, t in ipairs({ { 6, 3 }, { 4, 3 }, { 2.5, 3 } }) do
		local w, h = t[1], t[2]
		makePart({ Name = "FountainTier", Size = Vector3.new(w, h, w), Color = F_COL, CFrame = CFrame.new(fx, tierY + h / 2, fz), Parent = model })
		makePart({ Name = "FountainCap", Size = Vector3.new(w + 1, 0.8, w + 1), Color = Palette.Snow, CFrame = CFrame.new(fx, tierY + h + 0.4, fz), Parent = model })
		tierY = tierY + h + 0.8
	end
	-- water-spray emitter factory
	local function spray(part: BasePart, rate: number, speed: number)
		local pe = Instance.new("ParticleEmitter")
		pe.Color = ColorSequence.new(F_WATER)
		pe.Lifetime = NumberRange.new(0.7, 1.2)
		pe.Rate = rate
		pe.Speed = NumberRange.new(speed, speed + 3)
		pe.SpreadAngle = Vector2.new(12, 12)
		pe.Acceleration = Vector3.new(0, -34, 0)
		pe.Size = NumberSequence.new(0.85)
		pe.LightEmission = 0.4
		pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		pe.EmissionDirection = Enum.NormalId.Top
		pe.Parent = part
	end
	-- 4 cube spouts (tilted out+up) spraying into the pool, + a top spray
	local spoutY = surfaceY + 1 + pedH + 1.5
	for _, d in ipairs({ Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }) do
		local sp = makePart({ Name = "FountainSpout", Size = Vector3.new(2, 2, 2), Color = Palette.Snow,
			CFrame = CFrame.new(fx + d.X * 4.5, spoutY, fz + d.Z * 4.5) * CFrame.Angles(math.rad(d.Z * 34), 0, math.rad(-d.X * 34)),
			Parent = model })
		spray(sp, 16, 9)
	end
	local top = makePart({ Name = "FountainTop", Size = Vector3.new(1.6, 1.6, 1.6), Color = Palette.Snow, CFrame = CFrame.new(fx, tierY + 1, fz), Parent = model })
	spray(top, 22, 12)
	return OUT
end

-- a small wooden PARK BENCH centred at (bx,bz), seat facing yaw.
local function buildParkBench(bx: number, bz: number, surfaceY: number, faceYaw: number)
	local model = Instance.new("Model")
	model.Name = "ParkBench"
	model.Parent = laneFolder
	local base = CFrame.new(bx, surfaceY, bz) * CFrame.Angles(0, faceYaw, 0)
	makePart({ Name = "BenchSeat", Size = Vector3.new(8, 0.5, 2.6), Color = Palette.Fence, CFrame = base * CFrame.new(0, 2.2, 0), Parent = model })
	makePart({ Name = "BenchBack", Size = Vector3.new(8, 2.4, 0.5), Color = Palette.Fence, CFrame = base * CFrame.new(0, 3.4, -1.05), Parent = model })
	for _, sx in ipairs({ -1, 1 }) do
		makePart({ Name = "BenchLeg", Size = Vector3.new(0.6, 2.2, 2.4), Color = Palette.BaseTrim, CFrame = base * CFrame.new(sx * 3.4, 1.1, 0), Parent = model })
	end
end

-- a REFINED brick path: small red brick pavers on a grey-cement (mortar) base, outlined on the inner
-- AND outer edges by a slightly TALLER red-brick curb. Built from many SMALL pieces so the ring around
-- the fountain reads smooth + circular. Runs down the lane and splits into a ring around the fountain.
local function buildParkPath(fx: number, centerZ: number, halfZ: number, ringR: number, surfaceY: number)
	local PW = 10                  -- path width
	local baseTop = surfaceY + 0.4 -- pavers sit on top of the mortar base
	-- one brick (red paver by default, or a custom colour for curbs); h taller => raised curb
	local function brick(x: number, z: number, yaw: number, sizeX: number, sizeZ: number, h: number, color: Color3?)
		makePart({ Name = "PathBrick", Size = Vector3.new(sizeX, h, sizeZ),
			Color = color or ((decorRng:NextNumber() < 0.5) and PARK_BRICK or PARK_BRICK2),
			CFrame = CFrame.new(x, baseTop + h / 2, z) * CFrame.Angles(0, yaw, 0), Parent = laneFolder })
	end
	-- grey mortar base slab (the cement the bricks sit in; shows through the gaps)
	local function mortar(x: number, z: number, sx: number, sz: number, yaw: number?)
		local cf = CFrame.new(x, surfaceY + 0.2, z)
		if yaw then cf = cf * CFrame.Angles(0, yaw, 0) end
		makePart({ Name = "PathMortar", Size = Vector3.new(sx, 0.45, sz), Color = PATH_MORTAR, CFrame = cf, Parent = laneFolder })
	end

	-- STRAIGHT section (along Z at x=fx) between z0..z1: mortar + running-bond pavers + 2 curb rails
	local function straight(z0: number, z1: number)
		if z1 - z0 < 1 then return end
		mortar(fx, (z0 + z1) / 2, PW, z1 - z0)
		local cellX, cellZ = 3.2, 2.0
		local iz, z = 0, z0 + cellZ / 2
		while z < z1 - 0.3 do
			local off = (iz % 2 == 0) and 0 or cellX / 2 -- running bond: stagger alternate rows
			local x = fx - PW / 2 + cellX / 2 - off
			while x < fx + PW / 2 - 0.3 do
				if x > fx - PW / 2 + 0.3 then
					brick(x, z, 0, cellX * 0.84, cellZ * 0.78, 0.5)
				end
				x = x + cellX
			end
			z = z + cellZ
			iz = iz + 1
		end
		for _, sx in ipairs({ -1, 1 }) do -- taller curb rails outlining both edges
			brick(fx + sx * (PW / 2 - 0.2), (z0 + z1) / 2, 0, 1.3, z1 - z0, 1.1, PATH_CURB)
		end
	end
	straight(centerZ - halfZ, centerZ - ringR)
	straight(centerZ + ringR, centerZ + halfZ)

	-- RING around the fountain (the path splits to go around it)
	do -- smooth grey mortar base ring
		local n = 52
		for i = 0, n - 1 do
			local a = (i / n) * math.pi * 2
			mortar(fx + math.cos(a) * ringR, centerZ + math.sin(a) * ringR, PW + 0.6, (2 * math.pi * ringR / n) + 1.2, a + math.pi / 2)
		end
	end
	-- 3 concentric paver bands of small tangential bricks (staggered) => smooth circular paving
	for bi, r in ipairs({ ringR - PW * 0.3, ringR, ringR + PW * 0.3 }) do
		local n = math.max(20, math.floor(2 * math.pi * r / 3.2))
		local seg = (2 * math.pi * r) / n
		local stagger = (bi % 2 == 0) and (math.pi / n) or 0
		for i = 0, n - 1 do
			local a = (i / n) * math.pi * 2 + stagger
			brick(fx + math.cos(a) * r, centerZ + math.sin(a) * r, a + math.pi / 2, PW * 0.27, seg * 0.82, 0.5)
		end
	end
	-- inner + outer taller curb rings (the elegant outline)
	for _, cr in ipairs({ ringR - PW / 2 + 0.2, ringR + PW / 2 - 0.2 }) do
		local n = math.max(40, math.floor(2 * math.pi * cr / 2.6))
		local seg = (2 * math.pi * cr) / n
		for i = 0, n - 1 do
			local a = (i / n) * math.pi * 2
			brick(fx + math.cos(a) * cr, centerZ + math.sin(a) * cr, a + math.pi / 2, 1.3, seg + 0.5, 1.1, PATH_CURB)
		end
	end
end

-- PARK decor: central fountain + brick path + scattered forest flowers/grass + 2 benches + 3 trees.
local function buildParkDecor(zone: number, centerZ: number)
	local cx = MapBuilder.DigCenter.X
	local surfaceY = LANE_SEG_Y + SEG_SIZE.Y / 2
	local halfX = LANE_SIDE_INNER_X - 8
	local halfZ = LANE_STEP / 2 - 8

	local fOut = buildParkFountain(cx, centerZ, surfaceY)
	addDigExclusion(cx, centerZ, fOut / 2 + 6, zone)
	local ringR = fOut / 2 + 7
	buildParkPath(cx, centerZ, halfZ, ringR, surfaceY)

	-- forest flowers + grass tufts across the grass (off the fountain ring + the central path)
	local function freeSpot(x: number, z: number): boolean
		local dx, dz = x - cx, z - centerZ
		return (dx * dx + dz * dz) > (ringR + 4) ^ 2 and math.abs(dx) > 6
	end
	for _ = 1, 80 do
		local x = cx + (decorRng:NextNumber() - 0.5) * 2 * halfX
		local z = centerZ + (decorRng:NextNumber() - 0.5) * 2 * halfZ
		if freeSpot(x, z) then buildGrassTuft(x, z, surfaceY) end
	end
	for _ = 1, 28 do
		local x = cx + (decorRng:NextNumber() - 0.5) * 2 * halfX
		local z = centerZ + (decorRng:NextNumber() - 0.5) * 2 * halfZ
		if freeSpot(x, z) then buildFlower(x, z, surfaceY) end
	end

	-- 2 benches: bottom-left + top-right quadrant, each facing the fountain
	local function bench(bx: number, bz: number)
		buildParkBench(bx, bz, surfaceY, math.atan2(cx - bx, centerZ - bz))
		addDigExclusion(bx, bz, 6, zone)
	end
	bench(cx - halfX * 0.55, centerZ - halfZ * 0.5)
	bench(cx + halfX * 0.55, centerZ + halfZ * 0.5)

	-- 3 trees of different heights around the zone
	for _, t in ipairs({ { cx - halfX * 0.62, centerZ + halfZ * 0.55, 30 }, { cx + halfX * 0.6, centerZ - halfZ * 0.58, 22 }, { cx - halfX * 0.18, centerZ + halfZ * 0.8, 17 } }) do
		placeTree(t[1], t[2], t[3], laneFolder)
		addDigExclusion(t[1], t[2], 10, zone)
	end
end

	for k = 1, ZoneConfig.MaxZone - 1 do
		local wz = LANE_START + (k - 1) * LANE_STEP + LANE_STEP / 2
		if k == 1 then
			buildWallFrame(wz) -- zone1/2: stones frame the narrow wall ends, near the dig site
		else
			-- wide fence-less walls: push the (original-size) stone piles OUT so they cover the wall
			-- right up to / slightly INTO the border cliff — no light-gray wall sliver shows between
			-- the stone and the border. Outer edge lands ~x102-108 (into the dirt body 100-120, still
			-- well short of the grass beyond at 122). pile half-extent ~15, so center ≈ border inner - 7.
			buildWallFrame(wz, LANE_SIDE_INNER_X - 7)
		end
	end
	for z = 1, ZoneConfig.MaxZone do
		local data = ZoneConfig.get(z)
		if data and data.Theme == "Forest" then
			local pz = LANE_START + (z - 1) * LANE_STEP
			-- trees FLANKING the dig area (in the side strips), each ringed by a no-dig exclusion
			buildForestTrees(z, pz - LANE_STEP / 2 + 30, pz + LANE_STEP / 2 - 14)
			-- + a few trees sprinkled in the clearing's grassy rim (also no-dig ringed)
			buildForestClearingTrees(z, pz)
			-- + a few trees standing INSIDE the digsite itself, each ringed by an invisible
			--   no-dig zone so mounds never spawn on them
			buildForestDigsiteTrees(z, pz)
			-- + tiny grass tufts & small flowers scattered across the whole forest zone
			scatterForestGroundCover(z, pz)
		elseif data and data.Theme == "Desert" then
			-- cacti (varying heights) + a few #695B33 rocks scattered across the digsite, each
			-- ringed by a no-dig zone so dirt mounds never overlap them
			buildDesertDigsiteDecor(z, LANE_START + (z - 1) * LANE_STEP)
		elseif data and data.Theme == "Glaciers" then
			-- ice spikes (varying heights) + one small penguin scattered across the digsite, each
			-- ringed by a no-dig zone so dirt mounds never overlap them
			buildGlacierDigsiteDecor(z, LANE_START + (z - 1) * LANE_STEP)
		elseif data and data.Theme == "Cavern" then
			-- CRYSTAL CAVERNS: the main red/blue/green crystal + glowing mushrooms / grass around
			-- the rim + crystals jutting from the walls (all clear of the central dig-mound core)
			buildCavernDecor(z, LANE_START + (z - 1) * LANE_STEP)
		elseif data and data.Theme == "CherryBlossom" then
			-- CHERRY BLOSSOM: sakura trees (clear of mounds) + a pink-petal carpet + plank-hung
			-- dim red lanterns on both border walls.
			buildCherryBlossomDecor(z, LANE_START + (z - 1) * LANE_STEP)
		elseif data and data.Theme == "Haunted" then
			-- HAUNTED HOLLOW: dead trees + jack-o-lanterns scattered around the zone (no-dig ringed)
			-- + cobweb strings strung border-to-border overhead in sagging parabolas.
			buildHauntedDecor(z, LANE_START + (z - 1) * LANE_STEP)
		elseif data and data.Theme == "City" then
			-- CITY: a two-way asphalt road toward the next zone + thick-cardboard building facades
			-- (bakery / deli / towers …) lining both border walls, taller than the walls.
			buildCityDecor(z, LANE_START + (z - 1) * LANE_STEP)
		elseif data and data.Theme == "Park" then
			-- PARK: central deep-pool fountain + a brick path splitting around it + forest
			-- flowers/grass + 2 benches + 3 varied-height trees.
			buildParkDecor(z, LANE_START + (z - 1) * LANE_STEP)
		end
	end
end

-- TEMP dev ladder: a bright climbable truss up the OUTER face of the +X border cliff near the
-- lobby (~z106), so you can climb up and view your build from above. Remove when no longer needed.
local function buildDevViewLadder()
	local cx = MapBuilder.DigCenter.X
	local wallOuterX = LANE_SIDE_INNER_X + LANE_SIDE_THICK -- +X cliff outer body face (~120)
	local topY = 1 + LANE_SIDE_BODY_H + LANE_SIDE_CAP_H    -- top of the grass cap (~48)
	local truss = Instance.new("TrussPart")
	truss.Name = "DevViewLadder"
	truss.Anchored = true
	truss.CanCollide = true
	truss.Size = Vector3.new(2, topY, 2) -- ground (y=1) up to just above the cap top
	truss.Color = Palette.Gold
	truss.Material = Enum.Material.Metal
	truss.CFrame = CFrame.new(cx + wallOuterX + 1, 1 + topY / 2, LANE_START + 106)
	truss.Parent = laneFolder
end

local function buildSharedLane()
	local x = MapBuilder.DigCenter.X
	-- dig sites march OUTWARD (+Z) starting near the half-circle center (LANE_START):
	for z = 1, ZoneConfig.MaxZone do
		local pz = LANE_START + (z - 1) * LANE_STEP
		if z == 1 then
			-- the LOBBY dig site: bigger + pushed toward the lobby (away from the +Z wall)
			buildZoneArea(1, Vector3.new(x, 0, pz + ZONE1_DIG_SHIFT_Z), Vector3.new(0, 0, 1), laneFolder, ZONE1_DIG_SIZE, ZONE1_DIG_HALF)
		else
			buildZoneArea(z, Vector3.new(x, 0, pz), Vector3.new(0, 0, 1), laneFolder)   -- dir +Z (lane runs outward)
		end
	end
	-- walls exactly midway between consecutive dig sites; Front (-Z) faces the bases:
	for k = 1, ZoneConfig.MaxZone - 1 do
		local wz = LANE_START + (k - 1) * LANE_STEP + LANE_STEP / 2
		buildSharedWall(k, CFrame.new(x, LANE_WALL_Y, wz), laneFolder)
	end

	-- close the zone1/2 lane sides so the central wall can't simply be walked around
	buildLaneFences()

	-- decorative fence around the lobby dig site (3 sides; open toward the zone wall)
	buildZone1DigFence()

	-- grass-topped dirt cliffs flanking the whole lane to tighten the playable width
	buildLaneSideWalls()

	-- the big dirt-cliff wall enclosing the whole starting lobby (opens toward the +Z lane)
	buildLobbyWall()

	-- TEMP: a climbable ladder up the border cliff near the lobby (view the build from above)
	buildDevViewLadder()

	-- frame the walls with studded rock + add per-zone theme decorations (trees)
	decorateLane()
end

----------------------------------------------------------------- in-case hatching egg
-- Show / hide the in-progress hatching EGG inside each of a slot's REAL incubators. The egg
-- is the game's signature PIXEL egg (shared PixelEgg builder, same as the dug eggs), tinted
-- by the incubating egg's rarity (RarityColors.tier) but ALWAYS built at the incubator's
-- FIXED fit-height — so every rarity shows up the same SIZE inside the glass, only the COLOUR
-- differs. Rebuilds only when the shown rarity actually changes, so the 0.5s gate-updater
-- tick (and the explicit place/collect calls) are cheap.
local function updateSlotEggs(slot: number)
	local incs = slotIncubators[slot]
	if not incs then
		return
	end
	local occupant = slotOccupant[slot]
	local profile = occupant and PlayerData.get(occupant) or nil
	local unlocked = (profile and profile.IncubatorsUnlocked) or 0
	for i, rec in ipairs(incs) do
		local desired: string? = nil
		if profile and i <= unlocked then
			local inc = profile.Incubators and profile.Incubators[i]
			if inc then
				desired = inc.rarity
			end
		end
		if rec.eggRarity ~= desired then
			if rec.eggModel then
				rec.eggModel:Destroy()
				rec.eggModel = nil
			end
			rec.eggRarity = desired
			if desired then
				local egg = PixelEgg.build(rec.eggCF.Position, rec.eggHeight, RarityColors.tier(desired), INCUBATOR_EGG_VOX)
				egg.Name = "HatchingEgg"
				egg.Parent = rec.model
				rec.eggModel = egg
			end
		end
	end
end

-- Drive each REAL incubator's on-model progress bar + countdown from the occupant's profile.
-- (Replaces the old bottom-right HUD panel.) Empty → blank; hatching → cyan bar fills + "m:ss";
-- ready → green full bar + "DONE", the floating label switches to a collect hint, and the
-- ClickDetector turns ON so clicking the incubator collects the hatched brainrot.
local function updateIncubatorProgress(slot: number)
	local incs = slotIncubators[slot]
	if not incs then
		return
	end
	local occupant = slotOccupant[slot]
	local profile = occupant and PlayerData.get(occupant) or nil
	local unlocked = (profile and profile.IncubatorsUnlocked) or 0
	local now = Workspace:GetServerTimeNow()
	for i, rec in ipairs(incs) do
		if rec.mode == "real" and rec.progFill and rec.progText then
			local default = ("🥚 INCUBATOR %d"):format(i)
			local inc = (profile and i <= unlocked and profile.Incubators) and profile.Incubators[i] or nil
			if not inc then
				rec.progFill.Size = UDim2.new(0, 0, 1, 0)
				if rec.progText.Text ~= "" then rec.progText.Text = "" end
				rec.ready = false
				if rec.click.MaxActivationDistance ~= 0 then rec.click.MaxActivationDistance = 0 end
				if rec.label.Text ~= default then
					rec.label.Text = default
					rec.label.TextColor3 = Color3.fromRGB(150, 230, 255)
				end
			else
				local remaining = inc.endTime - now
				local dur = math.max(inc.duration or 1, 0.01)
				rec.progFill.Size = UDim2.new(1 - math.clamp(remaining / dur, 0, 1), 0, 1, 0)
				if remaining <= 0 then
					rec.progFill.BackgroundColor3 = INC_BAR_READY
					if rec.progText.Text ~= "DONE" then rec.progText.Text = "DONE" end
					rec.ready = true
					if rec.click.MaxActivationDistance ~= 28 then rec.click.MaxActivationDistance = 28 end
					if rec.label.Text ~= "✅ Click to collect!" then
						rec.label.Text = "✅ Click to collect!"
						rec.label.TextColor3 = Color3.fromRGB(150, 255, 150)
					end
				else
					rec.progFill.BackgroundColor3 = INC_BAR_PROGRESS
					local t = Format.time(remaining)
					if rec.progText.Text ~= t then rec.progText.Text = t end
					rec.ready = false
					if rec.click.MaxActivationDistance ~= 0 then rec.click.MaxActivationDistance = 0 end
					if rec.label.Text ~= default then
						rec.label.Text = default
						rec.label.TextColor3 = Color3.fromRGB(150, 230, 255)
					end
				end
			end
		end
	end
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

	-- floor 2 WALLS/roof visibility (reparent in/out of Workspace). The floor-2 FLOOR slab
	-- is NOT in here — it's always present as floor 1's roof; only the walls are gated.
	local f2 = slotFloor2[slot]
	local floor2Shown = occupant ~= nil and ladderUnlocked
	if f2 then
		local target = floor2Shown and slotFolder[slot] or hiddenHolder
		if f2.Parent ~= target then
			f2.Parent = target
		end
	end
	-- keep floor 1 fully ROOFED until floor 2 opens: the hatch fills the ladder hole while
	-- locked, then opens (transparent + walk-through) so the player can climb up.
	local hatch = slotCeilingHatch[slot]
	if hatch then
		hatch.Transparency = floor2Shown and 1 or 0
		hatch.CanCollide = not floor2Shown
	end

	-- show/hide the hatching egg inside each real incubator
	updateSlotEggs(slot)
end

-- public: force a refresh for a player's slot (called after incubator/ladder purchases)
function BaseManager.refreshBaseProgression(player: Player)
	local slot = playerSlot[player]
	if slot then
		refreshBaseProgression(slot)
	end
end

-- public: refresh just the in-case hatching eggs for a player (called by IncubationManager
-- the moment an egg is placed or collected, so the display updates instantly).
function BaseManager.refreshIncubatorEggs(player: Player)
	local slot = playerSlot[player]
	if slot then
		updateSlotEggs(slot)
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
	slotLevelButtons[slot] = {}

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

	-- load the player's PLACED brainrots onto their saved podiums (unplaced ones stay in
	-- the inventory as Tools — InventoryManager.sync rebuilds those on join).
	if profile then
		for _, entry in ipairs(profile.Collection) do
			if entry.placed and entry.podium then
				placeBrainrotForSlot(slot, player, entry, entry.podium)
			end
		end
	end

	-- reveal this occupant's incubators / ladder / floor 2 per their saved progression
	refreshBaseProgression(slot)

	local origin = baseOrigin(slot)
	-- spawn spot: inside the front of their (empty) base, facing the lane (the open front)
	local spawnCF = origin * CFrame.new(0, 4, 6)
	local function onCharacter(char: Model)
		local hrp = char:WaitForChild("HumanoidRootPart", 10)
		if not hrp then
			return
		end
		-- Place them at their base and HOLD it briefly: the engine also places freshly-spawned
		-- characters at the lobby SpawnLocation, and a single PivotTo can lose that race (leaving
		-- the player out in the lobby). Re-applying for ~0.4s reliably wins it.
		for _ = 1, 8 do
			char:PivotTo(spawnCF)
			task.wait(0.05)
		end
	end
	if player.Character then
		task.spawn(onCharacter, player.Character)
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

	-- reset the name plate back to the neutral OPEN PLOT state
	local sign = slotSign[slot]
	if sign then
		sign.Text = ("OPEN PLOT %d"):format(slot)
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
	-- fast, lightweight loop ONLY for the on-incubator progress bars + countdowns (smoother than
	-- the 0.5s gate loop below). Each tick reads the occupant's in-progress hatches.
	task.spawn(function()
		while true do
			for slot = 1, MAX_SLOTS do
				if slotOccupant[slot] then
					pcall(updateIncubatorProgress, slot)
				end
			end
			task.wait(0.12)
		end
	end)

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
						local entryById: { [string]: any } = {}
						for _, entry in ipairs(profile.Collection) do
							entryById[entry.id] = entry
						end
						for id, model in pairs(models) do
							local entry = entryById[id]
							setBrainrotLevelLabel(model, (entry and entry.level) or 1)
							if entry then
								-- keep the billboard $/s current (level ups + rebirth multiplier changes)
								setBrainrotInfoIncome(model, entry, profile.Rebirths)
							end
						end
					end
				end

				-- update each podium's LEVEL UP button: next-level cost + RED (can afford) /
				-- GRAY (can't); hidden when no brainrot sits there; "MAX LEVEL" at the cap.
				local lbtns = slotLevelButtons[slot]
				if lbtns then
					local lprofile = occupant and PlayerData.get(occupant)
					for idx, b in pairs(lbtns) do
						local id = (occupant and lprofile) and brainrotIdAtPodium(slot, idx) or nil
						local entry
						if id then
							for _, e in ipairs(lprofile.Collection) do
								if e.id == id then entry = e break end
							end
						end
						if entry then
							local level = entry.level or 1
							if level >= BrainrotConfig.MaxLevel then
								b.label.Text = "MAX LEVEL"
								b.part.Color = Color3.fromRGB(70, 80, 95)
								b.part.Transparency = 0
								b.click.MaxActivationDistance = 0
							else
								local baseCost = BrainrotConfig.levelUpCost(level + 1)
								local cost = math.floor(baseCost * UpgradeConfig.levelCostMultiplier(lprofile.Rebirths))
								local afford = (lprofile.Cash or 0) >= cost
								b.label.Text = ("⬆ LEVEL UP\n$%s"):format(Format.short(cost))
								b.part.Color = afford and Color3.fromRGB(225, 55, 55) or Color3.fromRGB(108, 108, 118)
								b.part.Transparency = 0
								b.click.MaxActivationDistance = 32
							end
						else
							b.label.Text = ""
							b.part.Transparency = 1
							b.click.MaxActivationDistance = 0
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

				-- keep each podium prompt's Occupied attribute synced so the client can show
				-- "Place" (empty) vs "Swap"/"Remove" (occupied). Cheap: SetAttribute to the same
				-- value is a no-op for replication.
				local promptPodiums = slotPodiums[slot]
				if promptPodiums then
					for idx, podium in ipairs(promptPodiums) do
						local prompt = podium:FindFirstChild("PodiumPrompt")
						if prompt then
							prompt:SetAttribute("Occupied", brainrotIdAtPodium(slot, idx) ~= nil)
						end
					end
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

-- Teleport the player to the MIDDLE of a dig zone (1..MaxZone), but ONLY if they've
-- unlocked it (zone <= CurrentZone, their highest CASH-unlocked zone) — otherwise this
-- would bypass the zone walls. Mirrors teleportHome's PivotTo approach.
function BaseManager.teleportZone(player: Player, zone: number): any
	if type(zone) ~= "number" then
		return { ok = false, reason = "Invalid zone." }
	end
	zone = math.floor(zone)
	if zone < 1 or zone > ZoneConfig.MaxZone then
		return { ok = false, reason = "Invalid zone." }
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not char or not hrp then
		return { ok = false, reason = "No character to teleport." }
	end
	local profile = PlayerData.get(player)
	local highest = profile and profile.CurrentZone or 1
	if zone > highest then
		return { ok = false, reason = "Requirement not met!" }
	end
	-- zone z's dig site sits at z = LANE_START + (z-1)*LANE_STEP on the lane axis (DigCenter.X);
	-- drop the player a few studs above the dig slab's top surface.
	local x = MapBuilder.DigCenter.X
	local surfaceY = LANE_SEG_Y + SEG_SIZE.Y / 2
	local pz = LANE_START + (zone - 1) * LANE_STEP
	char:PivotTo(CFrame.new(x, surfaceY + 5, pz))
	return { ok = true }
end

function BaseManager.init()
	-- the Home button (client) asks the server to put it back at its base
	Net.getFunction("TeleportHome").OnServerInvoke = function(player)
		return BaseManager.teleportHome(player)
	end
	-- the Teleport menu (client) asks the server to drop it in the middle of an unlocked zone
	Net.getFunction("TeleportZone").OnServerInvoke = function(player, zone)
		return BaseManager.teleportZone(player, zone)
	end

	-- PLACEMENT PROMPT ROUTER (server-authoritative). Incubator prompts hatch the HELD egg;
	-- podium prompts place / swap / remove the HELD brainrot. Only the base OWNER may act on
	-- their own base. The held egg/brainrot is read from the player's equipped Tool — never
	-- trusted from the client — and each manager re-validates ownership.
	local function notify(player: Player, title: string, text: string)
		Net.getEvent("Notify"):FireClient(player, { title = title, text = text, color = "Legendary" })
	end
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
		if not CollectionService:HasTag(prompt, INV_PROMPT_TAG) then
			return
		end
		local slot = prompt:GetAttribute("Slot")
		if playerSlot[player] ~= slot then
			return -- only the base owner can place into their own base
		end
		local kind = prompt:GetAttribute("PromptKind")
		if kind == "Incubator" then
			local rarity = InventoryManager.getEquippedEgg(player)
			if not rarity then
				notify(player, "Incubator", "Equip an egg first!")
				return
			end
			local res = IncubationManager.placeEgg(player, rarity)
			if res and res.ok == false and res.reason then
				notify(player, "Incubator", res.reason)
			end
		elseif kind == "Podium" then
			local podiumIndex = prompt:GetAttribute("PodiumIndex")
			if typeof(podiumIndex) ~= "number" then
				return
			end
			local heldId = InventoryManager.getEquippedBrainrot(player)
			local occupied = brainrotIdAtPodium(slot, podiumIndex) ~= nil
			local res
			if occupied then
				if heldId then
					res = EconomyManager.swapBrainrot(player, podiumIndex, heldId)
				else
					res = EconomyManager.unplaceBrainrot(player, podiumIndex)
				end
			else
				if not heldId then
					notify(player, "Base", "Equip a brainrot to place!")
					return
				end
				res = EconomyManager.placeBrainrot(player, heldId, podiumIndex)
			end
			if res and res.ok == false and res.reason then
				notify(player, "Base", res.reason)
			end
		end
	end)

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
