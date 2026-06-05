--!strict
-- RebirthManager
-- Rebirth: requires ALL THREE of (1) LifetimeCash >= the cash milestone,
-- (2) enough Gems for the rebirth cost, and (3) being in the correct (highest
-- unlocked) zone. On success it charges the Gems, RESETS Cash + LifetimeCash to
-- 0, bumps Rebirths, recomputes the permanent compounding multipliers
-- (gems 1.5^rb, cash 1.2^rb, level-cost 1.5^rb), and moves the player to the
-- highest unlocked zone. The Collection (and every brainrot's level) PERSISTS
-- through rebirth, as does the in-progress Incubator.
--
-- The reward is the permanent gem income x1.5 / cash income x1.2 per rebirth
-- (applied in BrainrotMath via the multipliers). There is no luck bonus and no
-- "must unlock a new zone" gate, so rebirths keep going past the last zone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local Format = require(Shared.Modules.Format)
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

	-- (1) must reach the LifetimeCash milestone for the current rebirth count
	local milestone = UpgradeConfig.cashMilestone(p.Rebirths)
	if p.LifetimeCash < milestone then
		return { ok = false, reason = ("Earn $%s to rebirth."):format(Format.short(milestone)) }
	end

	-- (2) must be able to afford the gem cost
	local cost = UpgradeConfig.gemCost(p.Rebirths)
	if p.Gems < cost then
		return { ok = false, reason = ("Need %s Gems to rebirth."):format(Format.short(cost)) }
	end

	-- (3) must be in the correct (highest unlocked) zone
	if p.CurrentZone ~= ZoneConfig.highestUnlocked(p.Rebirths) then
		return { ok = false, reason = "Reach the highest zone to rebirth." }
	end

	-- perform rebirth: charge gems, reset Cash + LifetimeCash, recompute the
	-- permanent compounding multipliers, and advance to the highest unlocked zone.
	-- Collection + brainrot levels and the in-progress Incubator are KEPT.
	p.Gems -= cost
	p.Rebirths += 1
	p.Cash = 0
	p.LifetimeCash = 0
	p.GemMultiplier = UpgradeConfig.gemMultiplier(p.Rebirths)
	p.CashMultiplier = UpgradeConfig.cashMultiplier(p.Rebirths)
	p.LevelCostMultiplier = UpgradeConfig.levelCostMultiplier(p.Rebirths)
	p.CurrentZone = ZoneConfig.highestUnlocked(p.Rebirths)

	if BaseManager then
		BaseManager.rebuildPlots(player)
		BaseManager.updateRebirthGate(player)
		-- refresh the player's zone-gate group so the wall they just broke down lets
		-- them through (and they can still freely return to their base in the lobby)
		BaseManager.applyZoneGate(player)
	end

	PlayerData.markDirty(player)
	PlayerData.push(player)

	Net.getEvent("Notify"):FireClient(player, {
		title = "REBIRTH!",
		text = ("Gems now x%.2f, Cash now x%.2f — permanent!"):format(
			p.GemMultiplier,
			p.CashMultiplier
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
