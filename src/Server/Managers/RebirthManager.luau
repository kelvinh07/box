--!strict
-- RebirthManager
-- Rebirth is gated PURELY by cumulative LifetimeCash (which NEVER resets). On rebirth:
--   * Cash resets to 0 and the GEM BALANCE resets to 0 (LifetimeCash is untouched).
--   * Rebirths++ and the permanent compounding CASH multiplier becomes 1.35^Rebirths
--     (there is NO gem multiplier — gem income is fixed per brainrot).
--   * ALL zone walls re-lock: CurrentZone resets to 1 and the player is teleported home.
--   * KEPT: the whole Collection (+ levels), every owned shovel/incubator/luck tier, plots.
--
-- The reward is the permanent x1.35-per-rebirth cash multiplier (applied in BrainrotMath).
-- Triggered ONLY from the Rebirth UI (the 🔄 icon) now — the zone walls are cash-purchases.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local UpgradeConfig = require(Shared.Config.UpgradeConfig)
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

	-- gated PURELY by cumulative LifetimeCash reaching the NEXT rebirth's milestone
	local milestone = UpgradeConfig.cashMilestone(p.Rebirths)
	if p.LifetimeCash < milestone then
		return { ok = false, reason = ("Reach $%s lifetime cash to rebirth."):format(Format.comma(milestone)) }
	end

	-- perform rebirth: reset Cash + GEM BALANCE (NOT LifetimeCash), re-lock all walls, bump
	-- Rebirths, recompute the permanent cash multiplier. Collection + brainrot levels and all
	-- owned shovel/incubator/luck tiers + plots are KEPT.
	p.Rebirths += 1
	p.Cash = 0
	p.Gems = 0
	p._gemAccumulator = 0
	p.CashMultiplier = UpgradeConfig.cashMultiplier(p.Rebirths) -- 1.35^rb
	p.GemMultiplier = UpgradeConfig.gemMultiplier(p.Rebirths)   -- always 1 (no gem bonus)
	p.LevelCostMultiplier = UpgradeConfig.levelCostMultiplier(p.Rebirths)
	p.CurrentZone = 1 -- walls re-lock; start back at zone 1

	if BaseManager then
		BaseManager.rebuildPlots(player)
		BaseManager.applyZoneGate(player) -- re-group so the re-locked walls block again
		BaseManager.teleportHome(player)  -- send them home, behind the walls
	end

	PlayerData.markDirty(player)
	PlayerData.push(player)

	Net.getEvent("Notify"):FireClient(player, {
		title = "REBIRTH!",
		text = ("Cash income now x%.2f — permanent! Walls reset; climb again."):format(p.CashMultiplier),
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
