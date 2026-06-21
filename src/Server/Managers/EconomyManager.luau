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
local InventoryManager = require(script.Parent.InventoryManager)

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
						-- income ONLY for PLACED brainrots (on a podium); inventory
						-- brainrots sit idle until placed on a plot.
						if entry.placed then
							local c, g = BrainrotMath.income(entry, profile.Rebirths)
							local cap = math.max(50, c * ACCRUE_CAP_CYCLES)
							bag[entry.id] = math.min(cap, (bag[entry.id] or 0) + c)
							gems += g
						end
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

----------------------------------------------------------------- offline earnings
-- Total LIVE earning rate (cash/sec, gem/sec) across the player's PLACED brainrots. Uses
-- BrainrotMath — the single source of truth — so every multiplier (variant, per-brainrot level,
-- rebirth) is already baked in, exactly matching the live income loop.
function EconomyManager.totalRate(player: Player): (number, number)
	local p = PlayerData.get(player)
	if not p then
		return 0, 0
	end
	local cash, gems = 0, 0
	for _, entry in ipairs(p.Collection) do
		if entry.placed then
			local c, g = BrainrotMath.income(entry, p.Rebirths)
			cash += c
			gems += g
		end
	end
	return cash, gems
end

-- Called when a player LEAVES: log their offline earning rate (live rate × OfflineEarningFactor)
-- and the logoff timestamp, so the next join can pay out time-away earnings.
function EconomyManager.recordLogoff(player: Player)
	local p = PlayerData.get(player)
	if not p then
		return
	end
	local cash, gems = EconomyManager.totalRate(player)
	p.OfflineCashRate = cash * GameConfig.OfflineEarningFactor
	p.OfflineGemRate = gems * GameConfig.OfflineEarningFactor
	p.LastLogoffTime = os.time()
	PlayerData.markDirty(player)
end

-- Called on JOIN: grant earnings for the time the player was away — logged offline rate × seconds
-- offline, with the offline time CAPPED at the player's MaxOfflineSeconds. Credits Cash/Gems (and
-- LifetimeCash for the cash portion, matching how collected income is credited) and stashes a
-- one-shot payload for the client's "welcome back" screen (sent via PlayerData.flushOfflineEarnings).
function EconomyManager.applyOfflineEarnings(player: Player)
	local p = PlayerData.get(player)
	if not p then
		return
	end
	local last = p.LastLogoffTime or 0
	if last <= 0 then
		return -- brand new player / never logged off before
	end
	local elapsed = os.time() - last
	-- consume the stamp up front so a re-load / re-request can never double-grant.
	p.LastLogoffTime = 0
	if elapsed <= 0 then
		PlayerData.markDirty(player)
		return
	end
	local cap = p.MaxOfflineSeconds or GameConfig.MaxOfflineSeconds
	local seconds = math.min(elapsed, cap)
	local cash = math.floor((p.OfflineCashRate or 0) * seconds)
	local gems = math.floor((p.OfflineGemRate or 0) * seconds)
	if cash <= 0 and gems <= 0 then
		PlayerData.markDirty(player)
		return
	end
	p.Cash += cash
	p.LifetimeCash += cash
	p.Gems += gems
	p.__pendingOffline = { cash = cash, gems = gems } -- one-shot; stripped from saves (__ prefix)
	PlayerData.markDirty(player)
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

	local wasPlaced = entry.placed == true

	table.remove(p.Collection, index)
	p.Cash += refund
	if accrued[player] then
		accrued[player][id] = nil -- forfeit any uncollected cash on this brainrot
	end

	-- only a PLACED brainrot has a world model to destroy + a podium to free.
	if wasPlaced and BaseManager then
		BaseManager.removeBrainrot(player, id)
	end
	-- sync removes the sold brainrot's inventory Tool (if it was unplaced).
	InventoryManager.sync(player)
	PlayerData.markDirty(player)
	PlayerData.push(player)
	return { ok = true, refund = refund }
end

----------------------------------------------------------------- place / unplace / swap
-- Move an owned, UNPLACED brainrot onto a specific base podium so it starts earning.
function EconomyManager.placeBrainrot(player: Player, brainrotId: string, podiumIndex: number): any
	local p = PlayerData.get(player)
	if not p then
		return { ok = false, reason = "No profile." }
	end

	local podium = math.floor(tonumber(podiumIndex) or 0)
	if podium < 1 or podium > (p.Plots or 0) then
		return { ok = false, reason = "Invalid podium." }
	end

	local entry
	for _, e in ipairs(p.Collection) do
		if e.id == brainrotId then
			entry = e
			break
		end
	end
	if not entry then
		return { ok = false, reason = "Brainrot not found." }
	end
	if entry.placed then
		return { ok = false, reason = "Already placed." }
	end

	-- no two placed brainrots may share a podium.
	for _, e in ipairs(p.Collection) do
		if e.placed and e.podium == podium then
			return { ok = false, reason = "That podium is occupied." }
		end
	end

	entry.placed = true
	entry.podium = podium
	if BaseManager then
		BaseManager.placeBrainrotAt(player, entry, podium)
	end
	InventoryManager.sync(player)
	PlayerData.markDirty(player)
	PlayerData.push(player)
	return { ok = true }
end

-- Take the placed brainrot off `podiumIndex` and return it to the inventory.
function EconomyManager.unplaceBrainrot(player: Player, podiumIndex: number): any
	local p = PlayerData.get(player)
	if not p then
		return { ok = false, reason = "No profile." }
	end
	local podium = math.floor(tonumber(podiumIndex) or 0)

	local entry
	for _, e in ipairs(p.Collection) do
		if e.placed and e.podium == podium then
			entry = e
			break
		end
	end
	if not entry then
		return { ok = false, reason = "Nothing on that podium." }
	end

	entry.placed = false
	entry.podium = nil
	if accrued[player] then
		accrued[player][entry.id] = nil -- forfeit uncollected cash; it no longer earns
	end
	if BaseManager then
		BaseManager.removeBrainrot(player, entry.id)
	end
	InventoryManager.sync(player)
	PlayerData.markDirty(player)
	PlayerData.push(player)
	return { ok = true }
end

-- Swap whatever is on `podiumIndex` for the (owned, unplaced) newBrainrotId: the old
-- one goes back to the inventory, the new one takes the podium.
function EconomyManager.swapBrainrot(player: Player, podiumIndex: number, newBrainrotId: string): any
	local p = PlayerData.get(player)
	if not p then
		return { ok = false, reason = "No profile." }
	end

	-- validate the incoming brainrot is owned + unplaced BEFORE we unplace the old one.
	local newEntry
	for _, e in ipairs(p.Collection) do
		if e.id == newBrainrotId then
			newEntry = e
			break
		end
	end
	if not newEntry then
		return { ok = false, reason = "Brainrot not found." }
	end
	if newEntry.placed then
		return { ok = false, reason = "Already placed." }
	end

	local podium = math.floor(tonumber(podiumIndex) or 0)
	if podium < 1 or podium > (p.Plots or 0) then
		return { ok = false, reason = "Invalid podium." }
	end

	-- if a brainrot currently occupies the podium, unplace it back to the inventory.
	local occupant
	for _, e in ipairs(p.Collection) do
		if e.placed and e.podium == podium then
			occupant = e
			break
		end
	end
	if occupant then
		local res = EconomyManager.unplaceBrainrot(player, podium)
		if not res.ok then
			return res
		end
	end

	return EconomyManager.placeBrainrot(player, newBrainrotId, podium)
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

----------------------------------------------------------------- equip best
-- Auto-fill the base podiums with the player's BEST brainrots. "Best" ranks by each brainrot's
-- earnings AT LEVEL 1 (its tier+variant; current level is ignored, per design). The top `Plots`
-- brainrots end up placed:
--   * a best brainrot already on a podium STAYS in its exact slot (untouched),
--   * a placed brainrot that doesn't make the cut is returned to the inventory,
--   * a best brainrot sitting in the inventory is placed into a freed/empty slot.
function EconomyManager.equipBest(player: Player): any
	local p = PlayerData.get(player)
	if not p then
		return { ok = false, reason = "No profile." }
	end
	local plots = p.Plots or 0

	-- level-1 earnings rate (level-independent; rebirth=0 keeps the ranking pure). Reuses BrainrotMath
	-- so the number matches the rest of the game.
	local function rate(e: any): number
		return (select(1, BrainrotMath.income({ id = e.id, base = e.base, tier = e.tier, variant = e.variant, level = 1 }, 0)))
	end

	-- rank a COPY (don't reorder the stored Collection); the top `plots` are the "best" set
	local ranked = table.clone(p.Collection)
	table.sort(ranked, function(a, b)
		return rate(a) > rate(b)
	end)
	local keep = math.min(plots, #ranked)
	local best: { [string]: boolean } = {}
	for i = 1, keep do
		best[ranked[i].id] = true
	end

	-- 1) un-place any PLACED brainrot that isn't in the best set (return it to the inventory)
	for _, e in ipairs(p.Collection) do
		if e.placed and not best[e.id] then
			e.placed = false
			e.podium = nil
			if accrued[player] then
				accrued[player][e.id] = nil
			end
			if BaseManager then
				BaseManager.removeBrainrot(player, e.id)
			end
		end
	end

	-- 2) the podiums still occupied are the KEPT best brainrots — they stay in their same slot
	local used: { [number]: boolean } = {}
	for _, e in ipairs(p.Collection) do
		if e.placed and e.podium then
			used[e.podium] = true
		end
	end
	local free: { number } = {}
	for i = 1, plots do
		if not used[i] then
			free[#free + 1] = i
		end
	end

	-- 3) place the best brainrots that aren't placed yet into the free slots
	local fi = 1
	for i = 1, keep do
		local e = ranked[i]
		if not e.placed then
			local podium = free[fi]
			if podium then
				fi += 1
				e.placed = true
				e.podium = podium
				if BaseManager then
					BaseManager.placeBrainrotAt(player, e, podium)
				end
			end
		end
	end

	InventoryManager.sync(player)
	PlayerData.markDirty(player)
	PlayerData.push(player)
	return { ok = true }
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
	Net.getFunction("EquipBest").OnServerInvoke = function(player)
		return EconomyManager.equipBest(player)
	end
end

return EconomyManager
