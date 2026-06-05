--!strict
-- EconomyManager
-- Owns all Cash/Gem mutation:
--   * the passive income loop (applies tier base income + variant multipliers +
--     zone scaling for every owned brainrot, every income tick),
--   * buying extra plots (Cash),
--   * selling owned brainrots (refund Cash).
--
-- All amounts are computed by BrainrotMath so the server payout matches the
-- number the client previews.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local GameConfig = require(Shared.Config.GameConfig)
local BrainrotMath = require(Shared.Modules.BrainrotMath)
local Net = require(Shared.Modules.Net)

local PlayerData = require(script.Parent.PlayerData)

local EconomyManager = {}

local BaseManager: any = nil
function EconomyManager.setBaseManager(bm: any)
	BaseManager = bm
end

-- Cash earned by each owned brainrot ACCUMULATES here until the player walks over
-- that brainrot's green pressure plate to collect it. Gems still auto-credit.
-- accrued[player][brainrotId] = uncollected cash
local accrued: { [Player]: { [string]: number } } = {}
local ACCRUE_CAP_CYCLES = 900 -- per-brainrot cash cap (~15 min at 1s ticks)

function EconomyManager.getAccrued(player: Player, id: string): number
	local bag = accrued[player]
	return (bag and bag[id]) or 0
end

function EconomyManager.cleanup(player: Player)
	accrued[player] = nil
end

-- collect one brainrot's accumulated cash (called when its plate is stepped on)
function EconomyManager.collect(player: Player, id: string): number
	local p = PlayerData.get(player)
	local bag = accrued[player]
	if not p or not bag then
		return 0
	end
	local amount = math.floor(bag[id] or 0)
	if amount <= 0 then
		return 0
	end
	bag[id] = 0
	p.Cash += amount
	PlayerData.markDirty(player)
	PlayerData.push(player)
	Net.getEvent("FloatingText"):FireClient(player, { cash = amount, gems = 0 })
	return amount
end

----------------------------------------------------------------- mutators
function EconomyManager.addCash(player: Player, amount: number)
	local p = PlayerData.get(player)
	if not p then return end
	p.Cash += amount
	PlayerData.markDirty(player)
end

function EconomyManager.addGems(player: Player, amount: number)
	local p = PlayerData.get(player)
	if not p then return end
	p.Gems += amount
	PlayerData.markDirty(player)
end

----------------------------------------------------------------- passive income
-- Cash ACCRUES per brainrot (collected at its pressure plate); gems auto-credit.
function EconomyManager.startIncomeLoop()
	task.spawn(function()
		while true do
			task.wait(GameConfig.IncomeTickSeconds)
			for _, player in ipairs(Players:GetPlayers()) do
				local profile = PlayerData.get(player)
				if profile and #profile.Collection > 0 then
					accrued[player] = accrued[player] or {}
					local bag = accrued[player]
					local gems = 0
					for _, entry in ipairs(profile.Collection) do
						local c, g = BrainrotMath.income(entry, profile.CurrentZone)
						local cap = math.max(50, c * ACCRUE_CAP_CYCLES)
						bag[entry.id] = math.min(cap, (bag[entry.id] or 0) + c)
						gems += g
					end

					-- gems are fractional per cycle; accumulate then floor on the player
					profile._gemAccumulator = (profile._gemAccumulator or 0) + gems
					local wholeGems = math.floor(profile._gemAccumulator)
					if wholeGems > 0 then
						profile.Gems += wholeGems
						profile._gemAccumulator -= wholeGems
						PlayerData.markDirty(player)
						PlayerData.push(player)
						Net.getEvent("FloatingText"):FireClient(player, { cash = 0, gems = wholeGems })
					end
				end
			end
		end
	end)
end

----------------------------------------------------------------- buy plot
function EconomyManager.buyPlot(player: Player): any
	local p = PlayerData.get(player)
	if not p then
		return { ok = false, reason = "No profile." }
	end
	if p.Plots >= GameConfig.MaxPlots then
		return { ok = false, reason = "Max plots reached." }
	end
	local plotsBeyondStart = math.max(0, p.Plots - GameConfig.StartingPlots)
	local cost = math.floor(GameConfig.PlotBaseCost * (GameConfig.PlotCostGrowth ^ plotsBeyondStart))
	if p.Cash < cost then
		return { ok = false, reason = "Not enough Cash." }
	end
	p.Cash -= cost
	p.Plots += 1
	if BaseManager then
		BaseManager.rebuildPlots(player)
	end
	PlayerData.markDirty(player)
	PlayerData.push(player)
	return { ok = true }
end

----------------------------------------------------------------- sell brainrot
function EconomyManager.sellBrainrot(player: Player, id: string): any
	local p = PlayerData.get(player)
	if not p then
		return { ok = false, reason = "No profile." }
	end
	local index, entry
	for i, e in ipairs(p.Collection) do
		if e.id == id then
			index, entry = i, e
			break
		end
	end
	if not entry then
		return { ok = false, reason = "Brainrot not found." }
	end
	-- refund = ~30 cycles of its cash income (a meaningful but not free amount)
	local cash = select(1, BrainrotMath.income(entry, p.CurrentZone))
	local refund = math.max(5, math.floor(cash * 30))

	table.remove(p.Collection, index)
	p.Cash += refund
	if accrued[player] then
		accrued[player][id] = nil -- forfeit any uncollected cash on this brainrot
	end

	if BaseManager then
		BaseManager.removeBrainrot(player, id)
	end
	PlayerData.markDirty(player)
	PlayerData.push(player)
	return { ok = true, refund = refund }
end

function EconomyManager.init()
	Net.getFunction("BuyPlot").OnServerInvoke = function(player)
		return EconomyManager.buyPlot(player)
	end
	Net.getFunction("SellBrainrot").OnServerInvoke = function(player, id)
		return EconomyManager.sellBrainrot(player, id)
	end
end

return EconomyManager
