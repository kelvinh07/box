--!strict
-- DigSite (client)
-- The dig areas are GRASS. Wherever an egg is buried, an UNEVEN DIRT PATCH (a
-- little cluster of rotated tan slabs, not a perfect circle) sits on the grass.
-- The EGG that pops out is a real EGG SHAPE (built from stacked balls, since
-- Roblox has no egg primitive) and varies by rarity: bigger (8x/10x/12x/15x) and
-- a different color. Dig length scales too (Common 3 / Uncommon 5 / Rare 7 /
-- Legendary 9 hold-stages). No glow — the dirt stays plain.
--
-- Server-authoritative: the server pre-assigns each spot's rarity (RollEggs) and
-- grants the egg on Dig — the client only renders and animates.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local RarityColors = require(Shared.Config.RarityColors)
local ShovelConfig = require(Shared.Config.ShovelConfig)
local EggConfig = require(Shared.Config.EggConfig)
local Net = require(Shared.Modules.Net)
local Surface = require(Shared.Modules.Surface)
local PixelEgg = require(Shared.Modules.PixelEgg)

local UIUtil = require(script.Parent.UIUtil)
local ClientNet = require(script.Parent.ClientNet)
local ClientState = require(script.Parent.ClientState)
local Sounds = require(script.Parent.Sounds)

local DigSite = {}

local player = Players.LocalPlayer
local screenGui: ScreenGui
local spotsFolder: Folder
local lastDig = 0
local digSpeedMult = 1 -- live shovel multiplier from the snapshot (DigSpeedMult)
local REGROW_SECONDS = 4
local PER_STAGE = ShovelConfig.PerStage -- seconds of hold per pop stage (shared w/ server)

-- Egg sizing is SINGLE-SOURCED in EggConfig so the dug egg, the in-hand tool egg, and the
-- inventory/hotbar icon eggs all share the same height. EGG_HEIGHT_BASE is one "x" of egg
-- height; the dug egg's height = REVEAL_MULT[rarity] * EGG_HEIGHT_BASE (== EggConfig.displayHeight).
local EGG_HEIGHT_BASE = EggConfig.HeightBase -- one "x" of egg height; egg height = mult * this
local PATCH_D = 6.0         -- rough dirt-patch span
local PATCH_PIECES = 3      -- slabs per patch (overlapping => uneven shape)

-- MYSTERY: every egg looks the SAME while still buried (a medium, near-black pixel egg)
-- so its rarity can't be guessed before it's dug up. The real size only appears on reveal.
local MYSTERY_MULT = 11                       -- medium (between the old common 8 and rare 12)
local MYSTERY_COLOR = Color3.fromRGB(34, 34, 42)

-- REVEAL: per-rarity egg SIZE used only AFTER the egg is dug up (color comes from
-- RarityColors). Dig TIME is no longer rarity-based — it's zone-based (ShovelConfig). Sourced
-- from EggConfig so the value is shared with the tool/icon eggs (pure refactor — same numbers).
local REVEAL_MULT = EggConfig.RevealMult

-- The egg is a PIXEL egg: cube "studs" (voxels) filling an egg ellipsoid (built by the
-- shared PixelEgg module). VOX_H = how many voxels tall (higher = finer pixels, more cube
-- parts). Eggs are built lazily (one at a time) so a high count is fine.
local VOX_H = 12

----------------------------------------------------------------- ownership filter
-- The dig sites are now the ONE SHARED central lane (not in a per-player folder), so
-- every client scatters its own mounds on them. All lane dig slabs set a "Zone"
-- attribute, so a tagged BasePart with that attribute is a (shared) dig site.
local function isMine(patch: Instance): boolean
	return patch:IsA("BasePart") and patch:GetAttribute("Zone") ~= nil
end

----------------------------------------------------------------- builders
-- an uneven dirt patch: a few overlapping rotated tan slabs (not a circle)
local function buildDirt(model: Instance, x: number, topY: number, z: number): BasePart
	local primary: BasePart
	for i = 1, PATCH_PIECES do
		local s = PATCH_D * (0.55 + math.random() * 0.5)
		local block = Instance.new("Part")
		block.Name = "Dirt"
		block.Size = Vector3.new(s, 0.55, s * (0.7 + math.random() * 0.5))
		local ox = (math.random() - 0.5) * PATCH_D * 0.45
		local oz = (math.random() - 0.5) * PATCH_D * 0.45
		block.CFrame = CFrame.new(x + ox, topY + 0.25, z + oz) * CFrame.Angles(0, math.rad(math.random() * 180), 0)
		local j = math.random(-12, 12)
		block.Color = Color3.fromRGB(186 + j, 150 + j, 110 + j)
		block.Material = Enum.Material.Plastic
		block.Anchored = true
		block.CanCollide = false
		Surface.applyStuds(block) -- classic studded dirt patches, same look as the world
		block.Parent = model
		if i == 1 then
			primary = block
		end
	end
	return primary
end

-- a PIXEL egg made of cube "studs": voxels filling an egg ellipsoid, parented to
-- a Model that's moved/spun as one unit via PivotTo (driven by a CFrameValue
-- tween — efficient even with many cubes). Built lazily (one at a time). The voxel
-- build itself lives in the SHARED PixelEgg module (the incubators reuse it); here we
-- just wrap it with the CFrameValue "Drive" that animates the dug egg.
local function buildVoxelEgg(model: Instance, x: number, z: number, centerY: number, height: number, color: Color3)
	local eggModel = PixelEgg.build(Vector3.new(x, centerY, z), height, color, VOX_H)
	local core = eggModel.PrimaryPart :: BasePart
	eggModel.Parent = model

	-- CFrameValue drives the whole model via PivotTo (one tween moves all cubes)
	local drive = Instance.new("CFrameValue")
	drive.Name = "Drive"
	drive.Value = core.CFrame
	drive.Parent = eggModel
	drive.Changed:Connect(function(v: CFrame)
		if eggModel.Parent and eggModel.PrimaryPart then
			eggModel:PivotTo(v)
		end
	end)

	return eggModel, drive
end

----------------------------------------------------------------- a single dig spot
local makeDigSpot: (number, number, number, string, number) -> () -- (x, topY, z, id, zone)

local function destroyEgg(spot: any)
	if spot.eggModel then
		spot.eggModel:Destroy()
		spot.eggModel = nil
		spot.cfv = nil
	end
end

-- move the whole pixel egg so its center is at (x, centerY, z), spun by (spin,tilt)
local function placeEgg(spot: any, centerY: number, spin: number, tilt: number, tweenInfo: TweenInfo?)
	if not spot.cfv then return end
	local goal = CFrame.new(spot.x, centerY, spot.z) * CFrame.Angles(0, spin, tilt)
	if tweenInfo then
		TweenService:Create(spot.cfv, tweenInfo, { Value = goal }):Play()
	else
		spot.cfv.Value = goal
	end
end

local function popEgg(spot: any)
	spot.popToken += 1
	local token = spot.popToken
	-- (re)build the MYSTERY pixel egg at the buried position (medium + black)
	destroyEgg(spot)
	spot.eggModel, spot.cfv = buildVoxelEgg(spot.model, spot.x, spot.z, spot.eggBuriedCenterY, spot.height, spot.color)
	-- it rises over the CURRENT zone-based hold duration, so a shovel upgrade shortens the
	-- whole animation live (recomputed here each time you start digging).
	local holdDur = ShovelConfig.zoneDigDuration(spot.zone, digSpeedMult)
	local stages = math.clamp(math.round(holdDur / PER_STAGE), 5, 30)
	local waitPer = holdDur / stages
	local info = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	for i = 1, stages do
		if spot.popToken ~= token then
			return
		end
		local centerY = spot.eggBuriedCenterY + (spot.eggOutCenterY - spot.eggBuriedCenterY) * (i / stages)
		placeEgg(spot, centerY, math.rad(i * 40), math.rad((i % 2 == 0) and 8 or -8), info)
		task.wait(waitPer)
	end
end

local function resetEgg(spot: any)
	spot.popToken += 1
	local token = spot.popToken
	placeEgg(spot, spot.eggBuriedCenterY, 0, 0, TweenInfo.new(0.18, Enum.EasingStyle.Quad))
	task.delay(0.25, function()
		if spot.popToken == token then
			destroyEgg(spot) -- tuck it back under the dirt (remove until next dig)
		end
	end)
end

local function revealEgg(rarity: string)
	local lbl = UIUtil.label({
		Size = UDim2.new(0, 320, 0, 60),
		Position = UDim2.new(0.5, 0, 0.56, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = ("Found a %s Egg!"):format(rarity),
		TextColor3 = RarityColors.tier(rarity),
		Parent = screenGui,
	})
	lbl.ZIndex = 40
	UIUtil.pop(lbl)
	task.delay(1.2, function() lbl:Destroy() end)
end

-- Swap the buried MYSTERY egg for the REAL rarity egg (true colour + size) at the popped
-- position — this is the only moment the rarity is ever shown.
local function revealRarityEgg(spot: any, rarity: string)
	spot.color = RarityColors.tier(rarity)
	spot.height = EGG_HEIGHT_BASE * (REVEAL_MULT[rarity] or REVEAL_MULT.Common)
	spot.eggOutCenterY = spot.topY + 0.4 + 0.5 * spot.height
	destroyEgg(spot)
	spot.eggModel, spot.cfv = buildVoxelEgg(spot.model, spot.x, spot.z, spot.eggOutCenterY, spot.height, spot.color)
end

local function digSpot(spot: any)
	-- client-side debounce floor scales with the shovel mult (server still enforces the real cooldown)
	if os.clock() - lastDig < (0.35 / digSpeedMult) then return end
	lastDig = os.clock()

	local result = ClientNet.invoke("Dig", spot.id)
	if not (result and result.ok) then
		resetEgg(spot)
		return
	end
	Sounds.play("Dig")
	local rarity = result.rarity or "Common"

	spot.active = false
	spot.popToken += 1
	if spot.prompt then spot.prompt.Enabled = false end

	-- REVEAL now (and only now): the egg becomes its real rarity colour + size, then flies up
	revealRarityEgg(spot, rarity)
	revealEgg(rarity)
	placeEgg(spot, spot.eggOutCenterY + 6, 0, 0, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In))

	local x, topY, z = spot.x, spot.topY, spot.z
	local nextId, zone = result.nextId, spot.zone

	task.delay(0.4, function()
		if spot.model then spot.model:Destroy() end
	end)
	task.delay(REGROW_SECONDS, function()
		if nextId then
			makeDigSpot(x, topY, z, nextId, zone) -- the regrown mound is another mystery
		end
	end)
end

function makeDigSpot(x: number, topY: number, z: number, id: string, zone: number)
	-- MYSTERY: same medium, near-black egg for EVERY rarity until it's dug up. The real
	-- size/colour only appears on reveal (revealRarityEgg).
	local height = EGG_HEIGHT_BASE * MYSTERY_MULT

	local model = Instance.new("Model")
	model.Name = "DigSpot"
	-- stamp the mound's lane position so a late-arriving no-dig marker (DigExclusion) can find
	-- & prune any mound that landed inside it (see pruneNear in DigSite.start)
	model:SetAttribute("X", x)
	model:SetAttribute("Z", z)
	model.Parent = spotsFolder

	local patch = buildDirt(model, x, topY, z)

	-- the pixel egg is built lazily when digging starts (popEgg); it rises from
	-- buried (mostly underground) up to rest on the dirt.
	local eggBuriedCenterY = topY - 0.5 * height
	local eggOutCenterY = topY + 0.4 + 0.5 * height

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Dig"
	prompt.ObjectText = "" -- rarity is a MYSTERY until dug up — NO peeking on hover
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	-- Hold time is ZONE-based (same for every rarity, deeper zone = longer) and shovel-
	-- scaled, shared with the server cooldown so they agree even at the fastest shovel.
	prompt.HoldDuration = ShovelConfig.zoneDigDuration(zone, digSpeedMult)
	prompt:SetAttribute("Zone", zone) -- lets the snapshot listener recompute HoldDuration live
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = patch

	local spot = {
		id = id, zone = zone,
		model = model, prompt = prompt,
		height = height, color = MYSTERY_COLOR,
		eggModel = nil, cfv = nil,
		eggBuriedCenterY = eggBuriedCenterY, eggOutCenterY = eggOutCenterY,
		x = x, topY = topY, z = z,
		active = true, popToken = 0,
	}

	prompt.PromptButtonHoldBegan:Connect(function()
		if spot.active then popEgg(spot) end
	end)
	prompt.PromptButtonHoldEnded:Connect(function()
		if spot.active then resetEgg(spot) end
	end)
	prompt.Triggered:Connect(function()
		digSpot(spot)
	end)
end

----------------------------------------------------------------- scatter
local function scatterPatch(patch: Instance)
	if not patch:IsA("BasePart") or not isMine(patch) then
		return
	end
	local center = patch.Position
	local isCylinder = patch.Shape == Enum.PartType.Cylinder
	local topY = center.Y + (isCylinder and patch.Size.X or patch.Size.Y) / 2

	local area
	if isCylinder then
		local r = math.max(patch.Size.Y, patch.Size.Z) / 2
		area = math.pi * r * r
	else
		area = patch.Size.X * patch.Size.Z
	end
	-- The WHOLE zone is the dig site now: for zones 2+ the slab spans the entire zone (cliff-to-cliff,
	-- wall-to-wall), so mounds scatter across ALL of it (minus an edge inset that keeps them clear of
	-- the border cliffs, rebirth walls + the wall rock piles) and simply AVOID decoration via the
	-- DigExclusion markers gathered below. (The old central DigHalf core is gone — every part of the
	-- zone is diggable; the DigHalf attribute is left set server-side but is no longer read.)
	local EDGE_INSET = 16
	local spreadX = math.max(patch.Size.X - EDGE_INSET * 2, 8)
	local spreadZ = math.max(patch.Size.Z - EDGE_INSET * 2, 8)
	-- mound count scales with the (now full-zone) area so the big field reads as a real dig site.
	-- Capped at the server's MAX_ROLL_BATCH (30) — one RollEggs call assigns at most that many.
	local count = math.clamp(math.floor(area / 600 + 0.5), 12, 30)

	local zone = patch:GetAttribute("Zone") or 1

	-- candidate mound positions within the dig core (the no-dig filter is applied at PLACEMENT
	-- below, after RollEggs succeeds, so the tree markers are guaranteed present by then)
	local positions = {}
	for _ = 1, count do
		local x, z
		if isCylinder then
			local radius = (math.max(patch.Size.Y, patch.Size.Z) / 2) * 0.82
			local r = radius * math.sqrt(math.random())
			local theta = math.random() * math.pi * 2
			x = center.X + r * math.cos(theta)
			z = center.Z + r * math.sin(theta)
		else
			x = center.X + (math.random() - 0.5) * spreadX
			z = center.Z + (math.random() - 0.5) * spreadZ
		end
		table.insert(positions, { x = x, z = z })
	end

	-- RollEggs is refused until the player's profile has loaded. In a PUBLISHED game
	-- that profile comes from DataStore (a slow network call with retries), so the
	-- first request can lose the join race and fail -- which left the dig field empty.
	-- Retry QUIETLY until it succeeds (call the remote directly, not via ClientNet, so
	-- a transient "No profile" never toasts). In Studio the profile is instant.
	local rollEggs = Net.getFunction("RollEggs")
	local result
	for _ = 1, 20 do
		local ok, r = pcall(function()
			return rollEggs:InvokeServer(#positions, zone)
		end)
		if ok and r and r.ok and r.eggs then
			result = r
			break
		end
		task.wait(1)
	end
	if not result then
		return
	end

	-- Trees standing inside the dig clearing carry an INVISIBLE no-dig marker (tagged
	-- DigExclusion server-side, with a ClearRadius + Zone): never PLACE a mound within that
	-- radius so dirt patches don't spawn on/under a tree. Gathered HERE (after RollEggs
	-- succeeded => the server finished init + built the markers) so they're present; any
	-- late-replicating marker is still cleaned up by pruneNear (DigSite.start). Only THIS
	-- zone's markers apply.
	local exclusions = {}
	for _, m in ipairs(CollectionService:GetTagged("DigExclusion")) do
		if m:IsA("BasePart") and m:GetAttribute("Zone") == zone then
			local cr = m:GetAttribute("ClearRadius")
			exclusions[#exclusions + 1] = {
				x = m.Position.X,
				z = m.Position.Z,
				r = (typeof(cr) == "number" and cr) or 12,
			}
		end
	end
	local function blocked(x: number, z: number): boolean
		for _, e in ipairs(exclusions) do
			local dx, dz = x - e.x, z - e.z
			if dx * dx + dz * dz < e.r * e.r then
				return true
			end
		end
		return false
	end

	for i, egg in ipairs(result.eggs) do
		local pos = positions[i]
		if pos and not blocked(pos.x, pos.z) then
			-- the server returns the egg's effective ZONE (never its rarity); use it for the
			-- zone-based dig timing so the client matches the server cooldown.
			makeDigSpot(pos.x, topY, pos.z, egg.id, egg.zone or zone)
		end
	end
end

function DigSite.start(gui: ScreenGui)
	screenGui = gui
	spotsFolder = Instance.new("Folder")
	spotsFolder.Name = "LocalDigSpots"
	spotsFolder.Parent = workspace

	for _, patch in ipairs(CollectionService:GetTagged("DigPatch")) do
		task.spawn(scatterPatch, patch)
	end
	CollectionService:GetInstanceAddedSignal("DigPatch"):Connect(function(patch)
		task.wait(0.1)
		scatterPatch(patch)
	end)

	-- A no-dig marker (DigExclusion, around each digsite tree) can replicate AFTER this client
	-- already scattered that forest patch (the server builds the markers a beat after the dig
	-- slabs, across a LoadAsset yield). Prune any mound sitting inside a marker's radius, and
	-- re-prune whenever a marker streams in, so dirt patches never sit on the digsite trees
	-- regardless of replication order (the scatter-time filter handles the markers-ready case).
	-- Markers only ever exist in the forest zone and the zones are ~148 studs apart, so a
	-- mound within a marker's (small) radius is necessarily that zone's mound — distance alone
	-- is a safe match (the mound's own "zone" attr reflects DIG-TIMING, not its lane location).
	local function pruneNear(marker: Instance)
		if not marker:IsA("BasePart") then
			return
		end
		local r = (marker:GetAttribute("ClearRadius") :: number?) or 12
		local mx, mzz = marker.Position.X, marker.Position.Z
		for _, model in ipairs(spotsFolder:GetChildren()) do
			if model:IsA("Model") then
				local x = model:GetAttribute("X") :: number?
				local z = model:GetAttribute("Z") :: number?
				if x and z then
					local dx, dz = x - mx, z - mzz
					if dx * dx + dz * dz < r * r then
						model:Destroy()
					end
				end
			end
		end
	end
	for _, marker in ipairs(CollectionService:GetTagged("DigExclusion")) do
		pruneNear(marker)
	end
	CollectionService:GetInstanceAddedSignal("DigExclusion"):Connect(function(marker)
		task.wait(0.15)
		pruneNear(marker)
	end)

	-- Shovel dig-speed: when the snapshot's DigSpeedMult changes, recompute every existing
	-- prompt's HoldDuration from its cached "Zone". Only re-iterate when the value actually
	-- changed so frequent snapshots don't cause churn.
	ClientState.onChanged(function(state)
		local m = (state and state.DigSpeedMult) or 1
		if m == digSpeedMult then return end
		digSpeedMult = m
		for _, inst in ipairs(spotsFolder:GetDescendants()) do
			if inst:IsA("ProximityPrompt") then
				local zoneAttr = inst:GetAttribute("Zone")
				if zoneAttr then
					inst.HoldDuration = ShovelConfig.zoneDigDuration(zoneAttr :: number, digSpeedMult)
				end
			end
		end
	end)
end

return DigSite
