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
local DiggingManager = require(Managers.DiggingManager)
local IncubationManager = require(Managers.IncubationManager)
local EconomyManager = require(Managers.EconomyManager)
local InventoryManager = require(Managers.InventoryManager)
local UpgradeManager = require(Managers.UpgradeManager)
local RebirthManager = require(Managers.RebirthManager)
local StandManager = require(Managers.StandManager)
local LeaderboardManager = require(Managers.LeaderboardManager)
local AdminManager = require(Managers.AdminManager)

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
-- inventory tools (Backpack/toolbar) — after the managers that mutate Eggs/Collection exist; it
-- owns the Tool lifecycle and is called by those managers + on join/respawn below.
InventoryManager.init()
UpgradeManager.init()
RebirthManager.init()
-- admin chat commands (/test) — the handler only acts for players in AdminConfig
AdminManager.init()

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

-- the player should NOT cast a shadow. Turn CastShadow off on every body part (and any
-- accessory/clothing part that loads in afterwards).
local function removeCharacterShadow(char: Model)
	local function strip(d: Instance)
		if d:IsA("BasePart") then
			d.CastShadow = false
		end
	end
	for _, d in ipairs(char:GetDescendants()) do
		strip(d)
	end
	char.DescendantAdded:Connect(strip)
end

local function onJoin(player: Player)
	PlayerData.load(player)
	BaseManager.assignBase(player)

	-- faster movement + the zone-gate collision group + no player shadow, every spawn. The
	-- Backpack is recreated on respawn (tools reset), so RE-SYNC the inventory tools each
	-- CharacterAdded (deferred so the new Backpack exists).
	player.CharacterAdded:Connect(function(char)
		applyWalkSpeed(char)
		removeCharacterShadow(char)
		BaseManager.applyZoneGate(player)
		task.defer(function()
			InventoryManager.sync(player)
		end)
	end)
	if player.Character then
		applyWalkSpeed(player.Character)
		removeCharacterShadow(player.Character)
		BaseManager.applyZoneGate(player)
	end

	-- give the client a moment to set up its remotes/UI then push state + seed the inventory
	-- tools (defer so the Backpack exists after the profile load + base assignment).
	task.defer(function()
		PlayerData.push(player)
		InventoryManager.sync(player)
	end)
end

local function onLeave(player: Player)
	PlayerData.release(player)
	BaseManager.freeBase(player)
	DiggingManager.cleanup(player)
	EconomyManager.cleanup(player)
	InventoryManager.cleanup(player)
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
