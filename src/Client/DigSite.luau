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
local Net = require(Shared.Modules.Net)
local Surface = require(Shared.Modules.Surface)

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

local EGG_HEIGHT_BASE = 0.6 -- one "x" of egg height; egg height = mult * this
local PATCH_D = 6.0         -- rough dirt-patch span
local PATCH_PIECES = 3      -- slabs per patch (overlapping => uneven shape)
-- `stages` (hold-to-dig length) is sourced from ShovelConfig.Stages so the client
-- and the server's rarity-aware cooldown stay in lockstep; `mult` is render-only
-- (egg visual size) and stays local.
local RARITY = {
	Common    = { stages = ShovelConfig.Stages.Common,    mult = 8 },
	Uncommon  = { stages = ShovelConfig.Stages.Uncommon,  mult = 10 },
	Rare      = { stages = ShovelConfig.Stages.Rare,      mult = 12 },
	Legendary = { stages = ShovelConfig.Stages.Legendary, mult = 15 },
	Mythic    = { stages = ShovelConfig.Stages.Mythic,    mult = 15 },
}

-- The egg is a PIXEL egg: cube "studs" (voxels) filling an egg ellipsoid.
-- width = height * ratio; VOX_H = how many voxels tall (higher = finer pixels,
-- more cube parts). Eggs are built lazily (one at a time) so a high count is fine.
local EGG_WIDTH_RATIO = 0.72
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
		block.Material = Enum.Material.SmoothPlastic
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
-- tween — efficient even with many cubes). Built lazily (one at a time).
local function buildVoxelEgg(model: Instance, x: number, z: number, centerY: number, height: number, color: Color3)
	local eggModel = Instance.new("Model")
	eggModel.Name = "Egg"

	local core = Instance.new("Part")
	core.Name = "EggCore"
	core.Size = Vector3.new(0.2, 0.2, 0.2)
	core.Transparency = 1
	core.Anchored = true
	core.CanCollide = false
	core.CFrame = CFrame.new(x, centerY, z)
	core.Parent = eggModel
	eggModel.PrimaryPart = core

	local rx, ry, rz = (height * EGG_WIDTH_RATIO) / 2, height / 2, (height * EGG_WIDTH_RATIO) / 2
	local vox = height / VOX_H
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
					cube.CFrame = CFrame.new(x + px, centerY + py, z + pz)
					cube.Parent = eggModel
				end
			end
		end
	end

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
local makeDigSpot: (number, number, number, string, string) -> ()

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
	-- (re)build the pixel egg at the buried position
	destroyEgg(spot)
	spot.eggModel, spot.cfv = buildVoxelEgg(spot.model, spot.x, spot.z, spot.eggBuriedCenterY, spot.height, spot.color)
	local info = TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	for i = 1, spot.stages do
		if spot.popToken ~= token then
			return
		end
		local centerY = spot.eggBuriedCenterY + (spot.eggOutCenterY - spot.eggBuriedCenterY) * (i / spot.stages)
		placeEgg(spot, centerY, math.rad(i * 40), math.rad((i % 2 == 0) and 8 or -8), info)
		task.wait(PER_STAGE)
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
	revealEgg(result.rarity)

	spot.active = false
	spot.popToken += 1
	if spot.prompt then spot.prompt.Enabled = false end

	-- the egg flies up (collected), then the whole spot is cleared
	placeEgg(spot, spot.eggOutCenterY + 6, 0, 0, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.In))

	local x, topY, z = spot.x, spot.topY, spot.z
	local nextId, nextRarity = result.nextId, result.nextRarity or "Common"

	task.delay(0.4, function()
		if spot.model then spot.model:Destroy() end
	end)
	task.delay(REGROW_SECONDS, function()
		if nextId then
			makeDigSpot(x, topY, z, nextId, nextRarity)
		end
	end)
end

function makeDigSpot(x: number, topY: number, z: number, id: string, rarity: string)
	local cfg = RARITY[rarity] or RARITY.Common
	local rarityColor = RarityColors.tier(rarity)
	local height = EGG_HEIGHT_BASE * cfg.mult

	local model = Instance.new("Model")
	model.Name = "DigSpot"
	model.Parent = spotsFolder

	local patch = buildDirt(model, x, topY, z)

	-- the pixel egg is built lazily when digging starts (popEgg); it rises from
	-- buried (mostly underground) up to rest on the dirt.
	local eggBuriedCenterY = topY - 0.5 * height
	local eggOutCenterY = topY + 0.4 + 0.5 * height

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Dig"
	prompt.ObjectText = (rarity ~= "Common") and rarity or ""
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	-- Hold time is the SINGLE shared formula (floored at 0.3s) so the client prompt
	-- and the server cooldown agree even at the fastest shovel.
	prompt.HoldDuration = ShovelConfig.holdDuration(rarity, digSpeedMult)
	prompt:SetAttribute("Rarity", rarity) -- lets the snapshot listener recompute HoldDuration live
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = patch

	local spot = {
		id = id, rarity = rarity, stages = cfg.stages,
		model = model, prompt = prompt,
		height = height, color = rarityColor,
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
	local count = math.clamp(math.floor(area / 300 + 0.5), 5, 14)

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
			x = center.X + (math.random() - 0.5) * patch.Size.X * 0.8
			z = center.Z + (math.random() - 0.5) * patch.Size.Z * 0.8
		end
		table.insert(positions, { x = x, z = z })
	end

	local zone = patch:GetAttribute("Zone") or 1
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
	for i, egg in ipairs(result.eggs) do
		local pos = positions[i]
		if pos then
			makeDigSpot(pos.x, topY, pos.z, egg.id, egg.rarity)
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

	-- Shovel dig-speed: when the snapshot's DigSpeedMult changes, recompute every
	-- existing prompt's HoldDuration from its cached "Stages". Only re-iterate when
	-- the value actually changed so frequent snapshots don't cause churn.
	ClientState.onChanged(function(state)
		local m = (state and state.DigSpeedMult) or 1
		if m == digSpeedMult then return end
		digSpeedMult = m
		for _, inst in ipairs(spotsFolder:GetDescendants()) do
			if inst:IsA("ProximityPrompt") then
				local rarityAttr = inst:GetAttribute("Rarity")
				if rarityAttr then
					inst.HoldDuration = ShovelConfig.holdDuration(rarityAttr :: string, digSpeedMult)
				end
			end
		end
	end)
end

return DigSite
