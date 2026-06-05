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

-- 1. remotes
Net.setupServer()

-- 2. world
MapBuilder.build()

-- 3. init managers (order: data + base first, then ones that depend on them)
PlayerData.init()
BaseManager.init()

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

	-- faster movement: set WalkSpeed on every spawn (and on the current character)
	player.CharacterAdded:Connect(function(char)
		applyWalkSpeed(char)
	end)
	if player.Character then
		applyWalkSpeed(player.Character)
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
game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		PlayerData.save(player)
	end
	task.wait(1)
end)

print("[HatchABrainrot] Server ready.")
