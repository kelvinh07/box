--!strict
-- UpgradeManager
-- Gem-purchased Luck and Hatch Speed upgrades. Both are 5-tier, escalating gem
-- cost. Hatch Speed's effect is capped at 50% inside UpgradeConfig.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local Net = require(Shared.Modules.Net)

local PlayerData = require(script.Parent.PlayerData)

local UpgradeManager = {}

local function buy(player: Player, kind: "Luck" | "HatchSpeed"): any
	local p = PlayerData.get(player)
	if not p then
		return { ok = false, reason = "No profile." }
	end

	local cfg = UpgradeConfig[kind]
	local levelField = kind == "Luck" and "LuckLevel" or "HatchSpeedLevel"
	local current = p[levelField]

	if current >= cfg.MaxLevel then
		return { ok = false, reason = "Already max level." }
	end

	local nextLevel = current + 1
	local cost = cfg.Levels[nextLevel].GemCost
	if p.Gems < cost then
		return { ok = false, reason = "Not enough Gems." }
	end

	p.Gems -= cost
	p[levelField] = nextLevel

	PlayerData.markDirty(player)
	PlayerData.push(player)
	return { ok = true, level = nextLevel }
end

function UpgradeManager.init()
	Net.getFunction("UpgradeLuck").OnServerInvoke = function(player)
		return buy(player, "Luck")
	end
	Net.getFunction("UpgradeHatchSpeed").OnServerInvoke = function(player)
		return buy(player, "HatchSpeed")
	end
end

return UpgradeManager
