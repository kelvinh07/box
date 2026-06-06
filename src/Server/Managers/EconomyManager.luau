--!strict
-- EconomyManager
-- Owns all Cash/Gem mutation:
--   * the passive income loop (applies tier base income + variant multipliers +
--     the per-brainrot level + the permanent rebirth multipliers for every owned
--     brainrot, every income tick),
--   * buying extra plots (Cash),
--   * selling owned brainrots (refund Cash),
--   * leveling up a single owned brainrot (Cash L2-5 / Gems L6-10).
--
-- All amounts are computed by BrainrotMath so the server payout matches the
-- number the client previews. Income is keyed off profile.Rebirths (the rebirth
-- multipliers replaced the old per-zone scaling).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local GameConfig = require(Shared.Config.GameConfig)
local BrainrotConfig = require(Shared.Config.BrainrotConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
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
	-- LifetimeCash tracks Cash EARNED via income (drives the rebirth milestone);
	-- credit it here but NOT on sell refunds.
	p.LifetimeCash += amount
	PlayerData.markDirty(player)
	PlayerData.push(player)
	Net.getEvent("FloatingText"):FireClient(player, { cash = amount, gems = 0 })
	return amount
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
						local c, g = BrainrotMath.income(entry, profile.Rebirths)
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
	-- the 2nd floor (plots 13-24) is gated behind buying the LADDER first
	if p.Plots >= GameConfig.FloorOnePlots and not p.LadderUnlocked then
		return { ok = false, reason = "Unlock the ladder to the 2nd floor first!" }
	end
	local cost = GameConfig.plotCost(p.Plots)
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

----------------------------------------------------------------- buy ladder
-- Spend CASH to unlock the ladder to the 2nd floor. Requires owning all 12 floor-1
-- plots first. On success the 2nd floor becomes visible/buildable for everyone.
function EconomyManager.buyLadder(player: Player): any
	local p = PlayerData.get(player)
	if not p then
		return { ok = false, reason = "No profile." }
	end
	if p.LadderUnlocked then
		return { ok = false, reason = "Ladder already unlocked." }
	end
	if p.Plots < GameConfig.FloorOnePlots then
		return { ok = false, reason = "Own all 12 plots first!" }
	end
	if p.Cash < GameConfig.LadderCost then
		return { ok = false, reason = "Not enough Cash." }
	end
	p.Cash -= GameConfig.LadderCost
	p.LadderUnlocked = true
	-- rebuildPlots (NOT just refreshBaseProgression) so the floor-2 "Buy Plot" ghost
	-- podium gets created now that the ladder is unlocked — otherwise there's no podium
	-- to click and players can't buy any 2nd-floor slots. It also reveals floor 2.
	if BaseManager and BaseManager.rebuildPlots then
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
	-- refund = ~30 cycles of its cash income (a meaningful but not free amount).
	-- NOTE: a sell refund is NOT income, so we do NOT add it to LifetimeCash.
	local cash = select(1, BrainrotMath.income(entry, p.Rebirths))
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

----------------------------------------------------------------- level brainrot
-- Level up a single owned brainrot by one. Levels 2-5 cost Cash, 6-10 cost Gems;
-- the base cost is scaled by the rebirth levelCostMultiplier (1.5^Rebirths).
-- Levels persist through rebirth and are capped at BrainrotConfig.MaxLevel.
function EconomyManager.levelBrainrot(player: Player, id: string): any
	local p = PlayerData.get(player)
	if not p then
		return { ok = false, reason = "No profile." }
	end

	local entry
	for _, e in ipairs(p.Collection) do
		if e.id == id then
			entry = e
			break
		end
	end
	if not entry then
		return { ok = false, reason = "Brainrot not found." }
	end

	local current = entry.level or 1
	if current >= BrainrotConfig.MaxLevel then
		return { ok = false, reason = "Already max level." }
	end

	local target = current + 1
	local baseCost, currency = BrainrotConfig.levelUpCost(target)
	local cost = math.floor(baseCost * UpgradeConfig.levelCostMultiplier(p.Rebirths))

	if currency == "Gems" then
		if p.Gems < cost then
			return { ok = false, reason = "Not enough Gems." }
		end
		p.Gems -= cost
	else
		if p.Cash < cost then
			return { ok = false, reason = "Not enough Cash." }
		end
		p.Cash -= cost
	end

	entry.level = target

	-- refresh the brainrot's plot label ("Lv N" / income) now that it leveled.
	-- BaseManager.refreshBrainrotLabel is wired in step 4; guard so this manager
	-- works whether or not that method exists yet.
	if BaseManager and type(BaseManager.refreshBrainrotLabel) == "function" then
		BaseManager.refreshBrainrotLabel(player, entry)
	end

	PlayerData.markDirty(player)
	PlayerData.push(player)
	return { ok = true, level = target, cost = cost, currency = currency }
end

function EconomyManager.init()
	Net.getFunction("BuyPlot").OnServerInvoke = function(player)
		return EconomyManager.buyPlot(player)
	end
	Net.getFunction("BuyLadder").OnServerInvoke = function(player)
		return EconomyManager.buyLadder(player)
	end
	Net.getFunction("SellBrainrot").OnServerInvoke = function(player, id)
		return EconomyManager.sellBrainrot(player, id)
	end
	Net.getFunction("LevelBrainrot").OnServerInvoke = function(player, id)
		return EconomyManager.levelBrainrot(player, id)
	end
end

return EconomyManager
