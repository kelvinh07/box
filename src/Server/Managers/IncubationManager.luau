--!strict
-- IncubationManager
-- Handles placing an egg into the incubator and collecting the hatched brainrot.
--
--   PlaceEgg:         spends the egg from inventory, charges the Cash hatch cost,
--                     starts a timer of max(0.5, incubation * (1 - reduction)).
--   CollectIncubator: once the timer is up, rolls a base brainrot (from the egg
--                     tier, available in the current zone) + a variant (luck-
--                     weighted), and adds it to the collection (at level 1) on a
--                     free plot.
--
-- The incubator reduction comes from UpgradeConfig.incubatorReduction; the 0.5s
-- hatch floor below guarantees hatching is NEVER instant, no matter the tier.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Shared = ReplicatedStorage.Shared

local EggConfig = require(Shared.Config.EggConfig)
local BrainrotConfig = require(Shared.Config.BrainrotConfig)
local VariantConfig = require(Shared.Config.VariantConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local Util = require(Shared.Modules.Util)
local Net = require(Shared.Modules.Net)

local PlayerData = require(script.Parent.PlayerData)

local IncubationManager = {}

-- BaseManager is injected after construction to avoid a require cycle.
local BaseManager: any = nil
function IncubationManager.setBaseManager(bm: any)
	BaseManager = bm
end

-- Roll a variant, luck-weighted.
local function rollVariant(luck: number): string
	local weights = {}
	for variant, data in pairs(VariantConfig.Variants) do
		local bias = VariantConfig.LuckBias[variant] or 0
		weights[variant] = data.Weight * (1 + luck * bias)
	end
	return Util.weightedPick(weights) or "Normal"
end

local rng = Random.new()

local function zoneAllowsTier(zoneData: any, tier: string): boolean
	for _, t in ipairs(zoneData.BrainrotTiers) do
		if t == tier then
			return true
		end
	end
	return false
end

-- Pick a base brainrot of `tier` that is allowed in the current `zone`.
-- In zones that unlock the exclusive Mythic tier, a Legendary egg has a
-- luck-boosted chance to "ascend" into a Mythic brainrot instead — this is the
-- only way Mythic brainrots are obtained, keeping them zone 2+ exclusive.
local function rollBase(tier: string, zone: number, luck: number): string?
	local zoneData = ZoneConfig.get(zone) or ZoneConfig.get(1)

	if tier == "Legendary" and zoneAllowsTier(zoneData, "Mythic") then
		local mythicChance = math.clamp(0.40 + 0.10 * luck, 0, 0.85)
		if rng:NextNumber() < mythicChance then
			tier = "Mythic"
		end
	end

	if not zoneAllowsTier(zoneData, tier) then
		-- fall back to the highest tier the zone *does* allow
		tier = zoneData.BrainrotTiers[#zoneData.BrainrotTiers]
	end

	local names = BrainrotConfig.namesByTier(tier)
	return Util.choice(names)
end

-- You can only hatch while standing near YOUR incubator.
local INCUBATOR_RANGE = 24

------------------------------------------------------------------ PlaceEgg
function IncubationManager.placeEgg(player: Player, rarity: string): any
	local profile = PlayerData.get(player)
	if not profile then
		return { ok = false, reason = "No profile." }
	end

	-- proximity: must be within range (flat XZ) of THEIR incubator. If BaseManager
	-- has no position yet (no incubator), skip the check so nothing breaks.
	if BaseManager then
		local incPos = BaseManager.getIncubatorPosition(player)
		if incPos then
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if not root then
				return { ok = false, reason = "Go to your incubator to hatch!" }
			end
			local dx = root.Position.X - incPos.X
			local dz = root.Position.Z - incPos.Z
			if (dx * dx + dz * dz) > (INCUBATOR_RANGE * INCUBATOR_RANGE) then
				return { ok = false, reason = "Go to your incubator to hatch!" }
			end
		end
	end

	if not EggConfig.exists(rarity) then
		return { ok = false, reason = "Unknown egg." }
	end
	if profile.Incubator then
		return { ok = false, reason = "Incubator is busy!" }
	end
	if (profile.Eggs[rarity] or 0) <= 0 then
		return { ok = false, reason = "You don't have that egg." }
	end

	local egg = EggConfig.get(rarity)
	if profile.Cash < egg.HatchCost then
		return { ok = false, reason = "Not enough Cash to hatch." }
	end

	-- check there's room before committing
	if #profile.Collection >= profile.Plots then
		return { ok = false, reason = "All plots are full!" }
	end

	-- commit
	profile.Eggs[rarity] -= 1
	profile.Cash -= egg.HatchCost

	-- 0.5s hatch floor: hatching is never instant, even at the top incubator tier.
	local reduction = UpgradeConfig.incubatorReduction(profile.IncubatorLevel)
	local duration = math.max(0.5, egg.Incubation * (1 - reduction))

	profile.Incubator = {
		rarity = rarity,
		-- GetServerTimeNow() is synchronized between server & all clients, so the
		-- client countdown matches the server exactly. It also persists across
		-- sessions (it tracks wall-clock time).
		endTime = Workspace:GetServerTimeNow() + duration,
		duration = duration,
	}

	PlayerData.markDirty(player)
	PlayerData.push(player)
	return { ok = true, duration = duration }
end

------------------------------------------------------------------ Collect
function IncubationManager.collect(player: Player): any
	local profile = PlayerData.get(player)
	if not profile then
		return { ok = false, reason = "No profile." }
	end
	local inc = profile.Incubator
	if not inc then
		return { ok = false, reason = "Nothing is incubating." }
	end
	if Workspace:GetServerTimeNow() < inc.endTime then
		return { ok = false, reason = "Still hatching!" }
	end
	if #profile.Collection >= profile.Plots then
		return { ok = false, reason = "All plots are full — sell or buy a plot." }
	end

	local egg = EggConfig.get(inc.rarity)
	local tier = egg.BrainrotTier
	local luck = UpgradeConfig.totalLuck(profile.LuckLevel, profile.Rebirths)

	local baseName = rollBase(tier, profile.CurrentZone, luck)
	if not baseName then
		return { ok = false, reason = "No brainrot available." }
	end
	local baseData = BrainrotConfig.get(baseName)
	local variant = rollVariant(luck)

	local entry = {
		id = Util.uid(),
		base = baseName,
		tier = baseData.Tier,
		variant = variant,
		level = 1, -- brainrots start at level 1; levels persist through rebirth
	}
	table.insert(profile.Collection, entry)
	profile.Incubator = nil

	-- spawn the physical podium model
	if BaseManager then
		BaseManager.placeBrainrot(player, entry)
	end

	PlayerData.markDirty(player)
	PlayerData.push(player)

	-- tell the client to play the reveal
	Net.getEvent("HatchResult"):FireClient(player, entry)
	Net.getEvent("ScreenShake"):FireClient(player, variant)

	return { ok = true, entry = entry }
end

------------------------------------------------------------------ Discard
-- Delete ONE unwanted egg of `rarity` from the backpack (no hatch, no refund).
-- Server-authoritative: validates the rarity + that the player actually holds one.
function IncubationManager.discardEgg(player: Player, rarity: string): any
	local profile = PlayerData.get(player)
	if not profile then
		return { ok = false, reason = "No profile." }
	end
	if not EggConfig.exists(rarity) then
		return { ok = false, reason = "Unknown egg." }
	end
	if (profile.Eggs[rarity] or 0) <= 0 then
		return { ok = false, reason = "No egg to delete." }
	end
	profile.Eggs[rarity] = math.max(0, (profile.Eggs[rarity] or 0) - 1)
	PlayerData.markDirty(player)
	PlayerData.push(player)
	return { ok = true, rarity = rarity }
end

function IncubationManager.init()
	Net.getFunction("PlaceEgg").OnServerInvoke = function(player, rarity)
		return IncubationManager.placeEgg(player, rarity)
	end
	Net.getFunction("CollectIncubator").OnServerInvoke = function(player)
		return IncubationManager.collect(player)
	end
	Net.getFunction("DiscardEgg").OnServerInvoke = function(player, rarity)
		return IncubationManager.discardEgg(player, rarity)
	end
end

return IncubationManager
