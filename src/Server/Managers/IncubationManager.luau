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
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Util = require(Shared.Modules.Util)
local Net = require(Shared.Modules.Net)

local PlayerData = require(script.Parent.PlayerData)

local IncubationManager = {}

-- BaseManager is injected after construction to avoid a require cycle.
local BaseManager: any = nil
function IncubationManager.setBaseManager(bm: any)
	BaseManager = bm
end

-- Pick one { tier, variant } group from an egg's POOL (EggConfig.poolGroups), weighted by
-- the variant's rarity (Normal common ... Diamond rare) and nudged toward the rarer variants
-- by Luck. The egg fully determines what can hatch — zone no longer filters the brainrot.
local function pickPoolGroup(eggRarity: string, luck: number): { tier: string, variant: string }?
	local groups = EggConfig.poolGroups(eggRarity)
	if #groups == 0 then
		return nil
	end
	local weights: { [number]: number } = {}
	for i, g in ipairs(groups) do
		local vdata = VariantConfig.get(g.variant)
		local bias = VariantConfig.LuckBias[g.variant] or 0
		weights[i] = (vdata and vdata.Weight or 1) * (1 + luck * bias)
	end
	local idx = Util.weightedPick(weights)
	return groups[idx] or groups[1]
end

-- You can only hatch while standing near ONE OF your incubators.
local INCUBATOR_RANGE = 24

-- how many of this player's incubators currently hold an egg (pending hatches).
local function pendingCount(profile: any): number
	local n = 0
	for i = 1, GameConfig.MaxIncubators do
		if profile.Incubators[i] ~= nil then
			n += 1
		end
	end
	return n
end

------------------------------------------------------------------ PlaceEgg
function IncubationManager.placeEgg(player: Player, rarity: string): any
	local profile = PlayerData.get(player)
	if not profile then
		return { ok = false, reason = "No profile." }
	end

	-- proximity: must be within range (flat XZ) of ANY of THEIR incubators. If
	-- BaseManager has no positions yet, skip the check so nothing breaks.
	if BaseManager then
		local positions = BaseManager.getIncubatorPositions(player)
		if positions and #positions > 0 then
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if not root then
				return { ok = false, reason = "Go to your incubators to hatch!" }
			end
			local near = false
			for _, pos in ipairs(positions) do
				local dx = root.Position.X - pos.X
				local dz = root.Position.Z - pos.Z
				if (dx * dx + dz * dz) <= (INCUBATOR_RANGE * INCUBATOR_RANGE) then
					near = true
					break
				end
			end
			if not near then
				return { ok = false, reason = "Go to your incubators to hatch!" }
			end
		end
	end

	if not EggConfig.exists(rarity) then
		return { ok = false, reason = "Unknown egg." }
	end

	-- find the first FREE unlocked incubator slot
	local unlocked = profile.IncubatorsUnlocked or 1
	local slot
	for i = 1, unlocked do
		if profile.Incubators[i] == nil then
			slot = i
			break
		end
	end
	if not slot then
		return { ok = false, reason = "All incubators are busy!" }
	end

	if (profile.Eggs[rarity] or 0) <= 0 then
		return { ok = false, reason = "You don't have that egg." }
	end

	local egg = EggConfig.get(rarity)
	if profile.Cash < egg.HatchCost then
		return { ok = false, reason = "Not enough Cash to hatch." }
	end

	-- check there's room before committing: each pending hatch reserves a plot too, so
	-- you can't over-commit more eggs than you have free plots.
	if (#profile.Collection + pendingCount(profile)) >= profile.Plots then
		return { ok = false, reason = "All plots are full!" }
	end

	-- commit
	profile.Eggs[rarity] -= 1
	profile.Cash -= egg.HatchCost

	-- 0.5s hatch floor: hatching is never instant, even at the top incubator tier.
	local reduction = UpgradeConfig.incubatorReduction(profile.IncubatorLevel)
	local duration = math.max(0.5, egg.Incubation * (1 - reduction))

	profile.Incubators[slot] = {
		rarity = rarity,
		-- GetServerTimeNow() is synchronized between server & all clients, so the
		-- client countdown matches the server exactly. It also persists across
		-- sessions (it tracks wall-clock time).
		endTime = Workspace:GetServerTimeNow() + duration,
		duration = duration,
	}

	PlayerData.markDirty(player)
	PlayerData.push(player)

	-- show the egg inside the glass case immediately
	if BaseManager and BaseManager.refreshIncubatorEggs then
		BaseManager.refreshIncubatorEggs(player)
	end
	return { ok = true, slot = slot, duration = duration }
end

------------------------------------------------------------------ Collect
function IncubationManager.collect(player: Player, index: number?): any
	local profile = PlayerData.get(player)
	if not profile then
		return { ok = false, reason = "No profile." }
	end
	local slot = math.floor(tonumber(index) or 1)
	if slot < 1 or slot > GameConfig.MaxIncubators then
		return { ok = false, reason = "Invalid incubator." }
	end
	local inc = profile.Incubators[slot]
	if not inc then
		return { ok = false, reason = "Nothing is incubating." }
	end
	if Workspace:GetServerTimeNow() < inc.endTime then
		return { ok = false, reason = "Still hatching!" }
	end
	if #profile.Collection >= profile.Plots then
		return { ok = false, reason = "All plots are full — sell or buy a plot." }
	end

	local luck = UpgradeConfig.totalLuck(profile.LuckLevel, profile.Rebirths)
	local group = pickPoolGroup(inc.rarity, luck)
	if not group then
		return { ok = false, reason = "No brainrot available." }
	end
	local names = BrainrotConfig.namesByTier(group.tier)
	local baseName = Util.choice(names)
	if not baseName then
		return { ok = false, reason = "No brainrot available." }
	end

	local entry = {
		id = Util.uid(),
		base = baseName,
		tier = group.tier,         -- base brainrot tier (drives income + label colour)
		variant = group.variant,   -- Normal / Gold / Diamond, set by the egg's pool
		level = 1, -- brainrots start at level 1; levels persist through rebirth
	}
	table.insert(profile.Collection, entry)
	profile.Incubators[slot] = nil

	-- spawn the physical podium model
	if BaseManager then
		BaseManager.placeBrainrot(player, entry)
	end

	PlayerData.markDirty(player)
	PlayerData.push(player)

	-- remove the egg from the glass case now that it has hatched
	if BaseManager and BaseManager.refreshIncubatorEggs then
		BaseManager.refreshIncubatorEggs(player)
	end

	-- tell the client to play the reveal
	Net.getEvent("HatchResult"):FireClient(player, entry)
	Net.getEvent("ScreenShake"):FireClient(player, variant)

	return { ok = true, entry = entry }
end

------------------------------------------------------------------ Unlock incubator
-- Spend CASH to unlock the next incubator (lets you hatch one more egg at a time),
-- up to GameConfig.MaxIncubators. Mirrors the brainrot-plot purchase flow.
function IncubationManager.unlockIncubator(player: Player): any
	local profile = PlayerData.get(player)
	if not profile then
		return { ok = false, reason = "No profile." }
	end
	local have = profile.IncubatorsUnlocked or 1
	if have >= GameConfig.MaxIncubators then
		return { ok = false, reason = "All incubators unlocked!" }
	end
	local cost = GameConfig.incubatorUnlockCost(have)
	if not cost then
		return { ok = false, reason = "All incubators unlocked!" }
	end
	if profile.Cash < cost then
		return { ok = false, reason = "Not enough Cash." }
	end
	profile.Cash -= cost
	profile.IncubatorsUnlocked = have + 1

	-- reveal the newly-unlocked incubator (+ the next ghost) in the world
	if BaseManager and BaseManager.refreshBaseProgression then
		BaseManager.refreshBaseProgression(player)
	end

	PlayerData.markDirty(player)
	PlayerData.push(player)
	return { ok = true, unlocked = profile.IncubatorsUnlocked }
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
	Net.getFunction("CollectIncubator").OnServerInvoke = function(player, index)
		return IncubationManager.collect(player, index)
	end
	Net.getFunction("UnlockIncubator").OnServerInvoke = function(player)
		return IncubationManager.unlockIncubator(player)
	end
	Net.getFunction("DiscardEgg").OnServerInvoke = function(player, rarity)
		return IncubationManager.discardEgg(player, rarity)
	end
end

return IncubationManager
