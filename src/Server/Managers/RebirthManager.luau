--!strict
-- RebirthManager
-- Rebirth: unlocks at a Cash milestone, costs Gems, RESETS Cash + brainrot
-- collection, unlocks the next Zone, and grants a permanent Luck bonus
-- (applied automatically via UpgradeConfig.totalLuck which reads Rebirths).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(Shared.Modules.Net)

local PlayerData = require(script.Parent.PlayerData)

local RebirthManager = {}

local BaseManager: any = nil
function RebirthManager.setBaseManager(bm: any)
	BaseManager = bm
end

function RebirthManager.rebirth(player: Player): any
	local p = PlayerData.get(player)
	if not p then
		return { ok = false, reason = "No profile." }
	end

	-- must hit the cash milestone
	if p.Cash < UpgradeConfig.Rebirth.CashMilestone then
		return { ok = false, reason = "Reach the Cash milestone first." }
	end

	-- a rebirth must actually unlock a new zone (don't waste gems otherwise)
	local before = ZoneConfig.highestUnlocked(p.Rebirths)
	local after = ZoneConfig.highestUnlocked(p.Rebirths + 1)
	if after <= before then
		return { ok = false, reason = "No further zones to unlock." }
	end

	local cost = UpgradeConfig.rebirthGemCost(p.Rebirths)
	if p.Gems < cost then
		return { ok = false, reason = ("Need %d Gems to rebirth."):format(cost) }
	end

	-- perform rebirth
	p.Gems -= cost
	p.Rebirths += 1
	p.Cash = GameConfig.StartingCash
	p.Collection = {}
	p.Incubator = nil
	p._gemAccumulator = 0
	-- move the player up to the newly unlocked zone
	p.CurrentZone = ZoneConfig.highestUnlocked(p.Rebirths)

	if BaseManager then
		BaseManager.rebuildPlots(player)
		BaseManager.updateRebirthGate(player)
	end

	PlayerData.markDirty(player)
	PlayerData.push(player)

	Net.getEvent("Notify"):FireClient(player, {
		title = "REBIRTH!",
		text = ("Unlocked %s — permanent +%d%% luck!"):format(
			ZoneConfig.get(p.CurrentZone).DisplayName,
			math.floor(UpgradeConfig.Rebirth.LuckBonusPerRebirth * 100)
		),
		color = "Legendary",
	})

	return { ok = true, rebirths = p.Rebirths, zone = p.CurrentZone }
end

function RebirthManager.init()
	Net.getFunction("Rebirth").OnServerInvoke = function(player)
		return RebirthManager.rebirth(player)
	end
end

return RebirthManager
