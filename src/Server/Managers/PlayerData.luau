--!strict
-- PlayerData
-- Authoritative player profiles: DataStore load/save with retries, in-memory
-- session cache, default profile, and pushing the state snapshot to the client.
--
-- Other managers read/mutate via PlayerData.get(player), then call
-- PlayerData.markDirty(player) and PlayerData.push(player).

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local Net = require(Shared.Modules.Net)

local PlayerData = {}

local store: DataStore? = nil
local cache: { [Player]: any } = {}
local dirty: { [Player]: boolean } = {}

-- We always TRY to use the DataStore. If GetDataStore fails (or reads fail
-- because Studio API access is off), we fall back to non-persistent profiles
-- gracefully — the game still runs, it just won't save. See init()/load().
local USE_DATASTORE = true

----------------------------------------------------------------- default profile
local function defaultProfile()
	return {
		Cash = GameConfig.StartingCash,
		Gems = GameConfig.StartingGems,
		Rebirths = 0,
		LuckLevel = 0,
		HatchSpeedLevel = 0,
		CurrentZone = 1,
		Plots = GameConfig.StartingPlots,
		Eggs = { Common = 0, Uncommon = 0, Rare = 0, Legendary = 0 },
		Incubator = nil, -- { rarity, endTime, duration } | nil
		Collection = {},  -- array of { id, base, tier, variant }
		Version = 1,
	}
end

-- Make sure older saves get any new fields.
local function reconcile(profile: any)
	local def = defaultProfile()
	for k, v in pairs(def) do
		if profile[k] == nil then
			profile[k] = v
		end
	end
	if typeof(profile.Eggs) ~= "table" then
		profile.Eggs = def.Eggs
	end
	for _, r in ipairs({ "Common", "Uncommon", "Rare", "Legendary" }) do
		profile.Eggs[r] = profile.Eggs[r] or 0
	end
	if typeof(profile.Collection) ~= "table" then
		profile.Collection = {}
	end
	return profile
end

----------------------------------------------------------------- datastore helpers
local function retry(fn: () -> any): (boolean, any)
	local attempts = 0
	while attempts < GameConfig.DataStoreRetries do
		attempts += 1
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(("[PlayerData] DataStore attempt %d failed: %s"):format(attempts, tostring(result)))
		task.wait(GameConfig.DataStoreRetryWait)
	end
	return false, nil
end

local function key(player: Player): string
	return "player_" .. tostring(player.UserId)
end

----------------------------------------------------------------- public API

function PlayerData.init()
	if USE_DATASTORE then
		local ok, s = pcall(function()
			return DataStoreService:GetDataStore(GameConfig.DataStoreName)
		end)
		if ok then
			store = s
		else
			warn("[PlayerData] Could not get DataStore; running without persistence.")
		end
	end
end

function PlayerData.load(player: Player)
	local profile = defaultProfile()

	if store then
		local ok, data = retry(function()
			return (store :: DataStore):GetAsync(key(player))
		end)
		if ok and typeof(data) == "table" then
			profile = reconcile(data)
		elseif not ok then
			-- Could not load. Use a fresh profile but mark NOT dirty and DO NOT
			-- save on leave, so we never overwrite real data with defaults.
			warn(("[PlayerData] Load failed for %s; using temporary profile (will NOT save)."):format(player.Name))
			profile = defaultProfile()
			profile.__doNotSave = true
		end
	end

	-- Clamp the current zone to what the player has unlocked.
	local highest = ZoneConfig.highestUnlocked(profile.Rebirths)
	if profile.CurrentZone > highest then
		profile.CurrentZone = highest
	end

	cache[player] = profile
	dirty[player] = false
	return profile
end

function PlayerData.get(player: Player): any
	return cache[player]
end

function PlayerData.markDirty(player: Player)
	dirty[player] = true
end

function PlayerData.save(player: Player): boolean
	local profile = cache[player]
	if not profile then
		return false
	end
	if profile.__doNotSave then
		return false
	end
	if not store then
		return false
	end
	-- strip transient fields before saving
	local toSave = {}
	for k, v in pairs(profile) do
		if not tostring(k):match("^__") then
			toSave[k] = v
		end
	end
	local ok = retry(function()
		(store :: DataStore):SetAsync(key(player), toSave)
		return true
	end)
	if ok then
		dirty[player] = false
	end
	return ok
end

function PlayerData.release(player: Player)
	PlayerData.save(player)
	cache[player] = nil
	dirty[player] = nil
end

-- Build the snapshot the client UI consumes. Pure derived data lives here so
-- the client never has to recompute economy rules.
function PlayerData.snapshot(player: Player): any?
	local p = cache[player]
	if not p then
		return nil
	end

	local plotsBeyondStart = math.max(0, p.Plots - GameConfig.StartingPlots)
	local nextPlotCost = math.floor(
		GameConfig.PlotBaseCost * (GameConfig.PlotCostGrowth ^ plotsBeyondStart)
	)

	-- TOTAL eggs held across all rarities + the rebirth-scaled capacity (for the
	-- backpack UI cap line).
	local eggCount = 0
	for _, r in ipairs({ "Common", "Uncommon", "Rare", "Legendary" }) do
		eggCount += (p.Eggs[r] or 0)
	end

	return {
		Cash = p.Cash,
		Gems = p.Gems,
		Rebirths = p.Rebirths,
		LuckLevel = p.LuckLevel,
		HatchSpeedLevel = p.HatchSpeedLevel,
		CurrentZone = p.CurrentZone,
		HighestZone = ZoneConfig.highestUnlocked(p.Rebirths),
		MaxZone = ZoneConfig.MaxZone,
		Plots = p.Plots,
		MaxPlots = GameConfig.MaxPlots,
		Eggs = p.Eggs,
		EggCount = eggCount,
		EggCapacity = GameConfig.eggCapacity(p.Rebirths),
		Incubator = p.Incubator,
		Collection = p.Collection,
		-- derived
		TotalLuck = UpgradeConfig.totalLuck(p.LuckLevel, p.Rebirths),
		HatchReduction = UpgradeConfig.hatchReduction(p.HatchSpeedLevel),
		NextPlotCost = nextPlotCost,
		RebirthGemCost = UpgradeConfig.rebirthGemCost(p.Rebirths),
		RebirthMilestone = UpgradeConfig.Rebirth.CashMilestone,
		RebirthReady = p.Cash >= UpgradeConfig.Rebirth.CashMilestone
			and ZoneConfig.highestUnlocked(p.Rebirths + 1) > ZoneConfig.highestUnlocked(p.Rebirths),
	}
end

function PlayerData.push(player: Player)
	local snap = PlayerData.snapshot(player)
	if snap then
		Net.getEvent("PushState"):FireClient(player, snap)
	end
end

-- Periodic autosave for everyone in the session.
function PlayerData.startAutosave()
	task.spawn(function()
		while true do
			task.wait(GameConfig.AutoSaveSeconds)
			for player, _ in pairs(cache) do
				if dirty[player] then
					PlayerData.save(player)
				end
			end
		end
	end)
end

return PlayerData
