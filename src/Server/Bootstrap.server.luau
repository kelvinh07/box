--!strict
-- Bootstrap (Server)
-- Single entry point: creates remotes, builds the world, wires every manager,
-- and handles player join/leave lifecycle. Runs in ServerScriptService.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Net = require(Shared.Modules.Net)
local GameConfig = require(Shared.Config.GameConfig)

local Managers = script.Parent.Managers
local PlayerData = require(Managers.PlayerData)
local MapBuilder = require(Managers.MapBuilder)
local BaseManager = require(Managers.BaseManager)
local BrainrotFactory = require(Managers.BrainrotFactory)
local DiggingManager = require(Managers.DiggingManager)
local IncubationManager = require(Managers.IncubationManager)
local EconomyManager = require(Managers.EconomyManager)
local UpgradeManager = require(Managers.UpgradeManager)
local RebirthManager = require(Managers.RebirthManager)
local StandManager = require(Managers.StandManager)
local LeaderboardManager = require(Managers.LeaderboardManager)

-- 1. remotes
Net.setupServer()

-- 2. world
MapBuilder.build()

-- 3. init managers (order: data + base first, then ones that depend on them)
PlayerData.init()
BaseManager.init()
-- shared upgrade stands + bacon-hair vendors near the lobby spawn (after the
-- world/bases exist; only depends on MapBuilder.build having run)
StandManager.init()
-- in-world leaderboards mounted on the two zone1/2 fences (needs BaseManager.init's
-- fences to already exist)
LeaderboardManager.init()

-- inject BaseManager into managers that need to touch podium models
IncubationManager.setBaseManager(BaseManager)
EconomyManager.setBaseManager(BaseManager)
RebirthManager.setBaseManager(BaseManager)

-- the physical rebirth-gate portal triggers a server-validated rebirth
BaseManager.setRebirthHandler(function(player)
	return RebirthManager.rebirth(player)
end)

DiggingManager.init()
IncubationManager.init()
EconomyManager.init()
UpgradeManager.init()
RebirthManager.init()

-- RequestState lets the client pull a fresh snapshot on demand
Net.getFunction("RequestState").OnServerInvoke = function(player)
	return PlayerData.snapshot(player)
end

-- 4. background loops
PlayerData.startAutosave()
EconomyManager.startIncomeLoop()
BaseManager.startGateUpdater()

-- 5. player lifecycle
-- apply the configured walk speed to a (possibly newly-spawned) character
local function applyWalkSpeed(char: Model)
	local h = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid")
	h.WalkSpeed = GameConfig.PlayerWalkSpeed
end

local function onJoin(player: Player)
	PlayerData.load(player)
	BaseManager.assignBase(player)

	-- faster movement + the zone-gate collision group on every spawn (and current char)
	player.CharacterAdded:Connect(function(char)
		applyWalkSpeed(char)
		BaseManager.applyZoneGate(player)
	end)
	if player.Character then
		applyWalkSpeed(player.Character)
		BaseManager.applyZoneGate(player)
	end

	-- give the client a moment to set up its remotes/UI then push state
	task.defer(function()
		PlayerData.push(player)
	end)
end

local function onLeave(player: Player)
	PlayerData.release(player)
	BaseManager.freeBase(player)
	DiggingManager.cleanup(player)
	EconomyManager.cleanup(player)
end

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onJoin, player)
end
Players.PlayerAdded:Connect(onJoin)
Players.PlayerRemoving:Connect(onLeave)

-- final save on server shutdown
-- Roblox force-closes the server after ~30s. Save every player in PARALLEL (one
-- coroutine each, so the SetAsync calls overlap instead of running back-to-back)
-- and poll until all of them finish or a 25s deadline passes, so the later
-- players don't lose their last session (e.g. a just-completed rebirth).
game:BindToClose(function()
	local players = Players:GetPlayers()
	local remaining = #players
	if remaining == 0 then
		return
	end
	for _, player in ipairs(players) do
		task.spawn(function()
			pcall(PlayerData.save, player)
			remaining -= 1
		end)
	end
	local deadline = os.clock() + 25
	while remaining > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)

print("[HatchABrainrot] Server ready.")
