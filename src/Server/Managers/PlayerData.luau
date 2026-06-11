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
local ShovelConfig = require(Shared.Config.ShovelConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local EggConfig = require(Shared.Config.EggConfig)
local Net = require(Shared.Modules.Net)
local Format = require(Shared.Modules.Format)

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
		LifetimeCash = 0,           -- CUMULATIVE cash ever earned; NEVER resets; gates rebirth (milestone)
		Rebirths = 0,
		GemMultiplier = 1,          -- derived from Rebirths: 1.5^Rebirths
		CashMultiplier = 1,         -- derived from Rebirths: 1.2^Rebirths
		LevelCostMultiplier = 1,    -- derived from Rebirths: 1.5^Rebirths
		LuckLevel = 0,
		IncubatorLevel = 0,         -- was HatchSpeedLevel
		ShovelLevel = 0,
		CurrentZone = 1,
		Plots = GameConfig.StartingPlots,
		Eggs = { Common = 0, Uncommon = 0, Rare = 0, Legendary = 0 },
		-- MULTI-INCUBATION: up to GameConfig.MaxIncubators (4). IncubatorsUnlocked is how
		-- many the player has (cash-bought, starts at 1); Incubators[i] holds the egg
		-- currently hatching in incubator i ({ rarity, endTime, duration } | nil).
		IncubatorsUnlocked = 1,
		Incubators = {}, -- sparse array [1..MaxIncubators]
		-- the 2nd-floor LADDER is a paid unlock (after owning all 12 floor-1 plots).
		LadderUnlocked = false,
		Collection = {},  -- array of { id, base, tier, variant, level }
		Version = 1,
	}
end

-- Make sure older saves get any new fields.
local function reconcile(profile: any)
	-- Migrate the renamed HatchSpeedLevel -> IncubatorLevel BEFORE defaulting,
	-- so an old save's value isn't lost to the IncubatorLevel=0 default.
	if profile.IncubatorLevel == nil and profile.HatchSpeedLevel ~= nil then
		profile.IncubatorLevel = profile.HatchSpeedLevel
	end
	profile.HatchSpeedLevel = nil

	-- Migrate the OLD single Incubator -> the multi-incubator array's first slot.
	if profile.Incubators == nil then
		profile.Incubators = {}
		if typeof(profile.Incubator) == "table" then
			profile.Incubators[1] = profile.Incubator
		end
	end
	profile.Incubator = nil

	local def = defaultProfile()
	for k, v in pairs(def) do
		if profile[k] == nil then
			profile[k] = v
		end
	end

	-- Normalize the multi-incubator fields.
	if typeof(profile.Incubators) ~= "table" then
		profile.Incubators = {}
	end
	profile.IncubatorsUnlocked = math.clamp(profile.IncubatorsUnlocked or 1, 1, GameConfig.MaxIncubators)
	profile.LadderUnlocked = profile.LadderUnlocked == true
	if typeof(profile.Eggs) ~= "table" then
		profile.Eggs = def.Eggs
	end
	for _, r in ipairs(EggConfig.Order) do
		profile.Eggs[r] = profile.Eggs[r] or 0
	end
	if typeof(profile.Collection) ~= "table" then
		profile.Collection = {}
	end
	-- Every brainrot carries a level (1..10); old entries default to 1.
	for _, entry in ipairs(profile.Collection) do
		entry.level = entry.level or 1
	end
	-- The income/level-cost multipliers are derived from Rebirths. Reconcile any
	-- missing/stale derived value straight from the rebirth count.
	profile.GemMultiplier = UpgradeConfig.gemMultiplier(profile.Rebirths)
	profile.CashMultiplier = UpgradeConfig.cashMultiplier(profile.Rebirths)
	profile.LevelCostMultiplier = UpgradeConfig.levelCostMultiplier(profile.Rebirths)
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

-- The default Tab player list reads a `leaderstats` folder on the Player: a StringValue
-- "Cash" (current total cash, formatted) and an IntValue "Rebirths".
local function setupLeaderstats(player: Player, profile: any)
	local existing = player:FindFirstChild("leaderstats")
	if existing then
		existing:Destroy()
	end
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local cash = Instance.new("StringValue")
	cash.Name = "Cash"
	cash.Value = "$" .. Format.short(profile.Cash or 0)
	cash.Parent = ls
	local rb = Instance.new("IntValue")
	rb.Name = "Rebirths"
	rb.Value = profile.Rebirths or 0
	rb.Parent = ls
	ls.Parent = player
end

local function updateLeaderstats(player: Player, profile: any)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		return
	end
	local cash = ls:FindFirstChild("Cash")
	if cash and cash:IsA("StringValue") then
		cash.Value = "$" .. Format.short(profile.Cash or 0)
	end
	local rb = ls:FindFirstChild("Rebirths")
	if rb and rb:IsA("IntValue") then
		rb.Value = profile.Rebirths or 0
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

	-- CurrentZone is now the player's highest CASH-UNLOCKED zone (broken walls persist across
	-- sessions; only a rebirth re-locks them by resetting this to 1). Just clamp it on load.
	profile.CurrentZone = math.clamp(profile.CurrentZone or 1, 1, ZoneConfig.MaxZone)

	cache[player] = profile
	dirty[player] = false
	setupLeaderstats(player, profile)
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

	local nextPlotCost = GameConfig.plotCost(p.Plots)

	-- TOTAL eggs held across all rarities + the rebirth-scaled capacity (for the
	-- backpack UI cap line).
	local eggCount = 0
	for _, r in ipairs(EggConfig.Order) do
		eggCount += (p.Eggs[r] or 0)
	end

	return {
		Cash = p.Cash,
		Gems = p.Gems,
		LifetimeCash = p.LifetimeCash,
		Rebirths = p.Rebirths,
		GemMultiplier = p.GemMultiplier,
		CashMultiplier = p.CashMultiplier,
		LevelCostMultiplier = p.LevelCostMultiplier,
		LuckLevel = p.LuckLevel,
		IncubatorLevel = p.IncubatorLevel,
		ShovelLevel = p.ShovelLevel,
		DigSpeedMult = ShovelConfig.digSpeedMult(p.ShovelLevel),
		CurrentZone = p.CurrentZone,
		HighestZone = p.CurrentZone, -- highest CASH-unlocked zone (gates the teleport menu + walls)
		MaxZone = ZoneConfig.MaxZone,
		Plots = p.Plots,
		MaxPlots = GameConfig.MaxPlots,
		Eggs = p.Eggs,
		EggCount = eggCount,
		EggCapacity = GameConfig.eggCapacity(p.Rebirths),
		-- multi-incubation: how many are unlocked + each slot's live hatch state
		IncubatorsUnlocked = p.IncubatorsUnlocked,
		Incubators = p.Incubators,
		MaxIncubators = GameConfig.MaxIncubators,
		NextIncubatorCost = GameConfig.incubatorUnlockCost(p.IncubatorsUnlocked),
		-- 2nd-floor ladder gating
		LadderUnlocked = p.LadderUnlocked,
		LadderCost = GameConfig.LadderCost,
		FloorOnePlots = GameConfig.FloorOnePlots,
		Collection = p.Collection,  -- each entry carries .level
		-- derived
		TotalLuck = UpgradeConfig.totalLuck(p.LuckLevel, p.Rebirths),
		IncubatorReduction = UpgradeConfig.incubatorReduction(p.IncubatorLevel),
		NextPlotCost = nextPlotCost,
		RebirthMilestone = UpgradeConfig.cashMilestone(p.Rebirths),
		-- Rebirth is gated PURELY by cumulative LifetimeCash now (no gem cost, no zone check).
		RebirthReady = p.LifetimeCash >= UpgradeConfig.cashMilestone(p.Rebirths),
		-- Cash to break the wall into the NEXT zone (0 once at the last zone).
		NextZoneCost = ZoneConfig.unlockCash(p.CurrentZone + 1),
	}
end

function PlayerData.push(player: Player)
	local p = cache[player]
	if p then
		updateLeaderstats(player, p)
	end
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
