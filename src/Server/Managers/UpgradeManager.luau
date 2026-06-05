--!strict
-- UpgradeManager
-- The three per-tier upgrade tracks, each with a per-tier currency split:
--   * Shovel    (ShovelConfig)        — tiers 1-5 Cash, 6-9 Gems; raises dig speed.
--   * Incubator (UpgradeConfig.Incubator, was "HatchSpeed") — 1-5 Cash, 6-9 Gems;
--                                        raises the incubation-time reduction.
--   * Luck      (UpgradeConfig.Luck)   — all 9 tiers Gems; shifts dig/variant odds.
--
-- All escalating costs + the currency for each tier live in the config modules;
-- this manager only validates currency/ownership/cap and charges the player.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local ShovelConfig = require(Shared.Config.ShovelConfig)
local Net = require(Shared.Modules.Net)

local PlayerData = require(script.Parent.PlayerData)

local UpgradeManager = {}

-- Charge `cost` of `currency` ("Cash" | "Gems") from profile `p`, if affordable.
-- Returns true on success; false (no mutation) if the player can't afford it.
local function charge(p: any, currency: string, cost: number): boolean
	if currency == "Gems" then
		if p.Gems < cost then
			return false
		end
		p.Gems -= cost
	else
		if p.Cash < cost then
			return false
		end
		p.Cash -= cost
	end
	return true
end

-- CASH/GEMS shovel: per-tier currency, raises ShovelLevel (dig speed). Cap 9.
function UpgradeManager.buyShovel(player: Player): any
	local p = PlayerData.get(player)
	if not p then
		return { ok = false, reason = "No profile." }
	end

	if p.ShovelLevel >= ShovelConfig.MaxLevel then
		return { ok = false, reason = "Max shovel tier." }
	end

	local nextLevel = p.ShovelLevel + 1
	local cost, currency = ShovelConfig.cost(nextLevel)
	if not charge(p, currency, cost) then
		return { ok = false, reason = "Not enough " .. currency .. "." }
	end
	p.ShovelLevel = nextLevel

	PlayerData.markDirty(player)
	PlayerData.push(player)
	return { ok = true, level = nextLevel }
end

-- CASH/GEMS incubator (was "HatchSpeed"): per-tier currency, raises IncubatorLevel
-- (incubation-time reduction). Cap 9.
function UpgradeManager.buyIncubator(player: Player): any
	local p = PlayerData.get(player)
	if not p then
		return { ok = false, reason = "No profile." }
	end

	if p.IncubatorLevel >= UpgradeConfig.Incubator.MaxLevel then
		return { ok = false, reason = "Max incubator tier." }
	end

	local nextLevel = p.IncubatorLevel + 1
	local tier = UpgradeConfig.Incubator.Levels[nextLevel]
	if not charge(p, tier.Currency, tier.Cost) then
		return { ok = false, reason = "Not enough " .. tier.Currency .. "." }
	end
	p.IncubatorLevel = nextLevel

	PlayerData.markDirty(player)
	PlayerData.push(player)
	return { ok = true, level = nextLevel }
end

-- GEM luck: all 9 tiers cost Gems, raises LuckLevel (dig/variant odds). Cap 9.
function UpgradeManager.buyLuck(player: Player): any
	local p = PlayerData.get(player)
	if not p then
		return { ok = false, reason = "No profile." }
	end

	if p.LuckLevel >= UpgradeConfig.Luck.MaxLevel then
		return { ok = false, reason = "Already max level." }
	end

	local nextLevel = p.LuckLevel + 1
	local cost = UpgradeConfig.Luck.Levels[nextLevel].GemCost
	if not charge(p, "Gems", cost) then
		return { ok = false, reason = "Not enough Gems." }
	end
	p.LuckLevel = nextLevel

	PlayerData.markDirty(player)
	PlayerData.push(player)
	return { ok = true, level = nextLevel }
end

function UpgradeManager.init()
	Net.getFunction("UpgradeLuck").OnServerInvoke = function(player)
		return UpgradeManager.buyLuck(player)
	end
	Net.getFunction("UpgradeIncubator").OnServerInvoke = function(player)
		return UpgradeManager.buyIncubator(player)
	end
	Net.getFunction("UpgradeShovel").OnServerInvoke = function(player)
		return UpgradeManager.buyShovel(player)
	end
end

return UpgradeManager
