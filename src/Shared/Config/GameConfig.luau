--!strict
-- GameConfig
-- Global tunables that don't belong to a more specific config module.
-- One place to balance the whole economy / loop timing.

local GameConfig = {}

-- Passive income runs on a fixed tick (seconds). All base incomes in the
-- configs are expressed "per cycle" == per this many seconds.
GameConfig.IncomeTickSeconds = 1

-- How often we auto-save player data.
GameConfig.AutoSaveSeconds = 60

-- Dig cooldown (seconds) between successful digs. SUPERSEDED: the server now gates
-- digs with a ZONE-based cooldown derived from ShovelConfig.zoneDigDuration (deeper zones
-- dig slower, shovels dig faster; rarity no longer affects dig time). Kept only as a
-- reference/fallback flat value; it is no longer the active rate limit in DiggingManager.
GameConfig.DigCooldown = 0.8

-- How fast players walk (applied to the Humanoid on spawn).
GameConfig.PlayerWalkSpeed = 35

-- Starting state for a brand new player.
GameConfig.StartingCash = 50
GameConfig.StartingGems = 0
GameConfig.StartingPlots = 3

-- Plot purchasing: Cash cost scales with how many plots you already own.
-- Plots 1-12 are floor 1, plots 13-24 are floor 2 of the base building (12 brainrot
-- slots per floor; floor 2 has NO incubators). The Nth purchased slot BEYOND
-- StartingPlots(=3) follows the table below; past the 6th extra slot the cost grows by
-- PlotCostGrowth (a steeper-than-doubling curve) every slot. See GameConfig.plotCost.
GameConfig.MaxPlots = 24
GameConfig.PlotCostTable = { 100, 300, 800, 2000, 5000, 12000 } -- Nth extra slot, 1..6
-- Each slot past the 6th extra costs this much MORE than the previous one (was 2 = a flat
-- double; raised so every later slot — especially the 12 floor-2 slots — ramps harder).
GameConfig.PlotCostGrowth = 2.5

-- Floor 1 holds the first 12 plots; floor 2 holds plots 13-24. The floor-2 staircase
-- is now a LADDER on the back wall that must be UNLOCKED (bought) after the player owns
-- all 12 floor-1 plots; only then does the 2nd floor become visible/buildable.
GameConfig.FloorOnePlots = 12

-- INCUBATORS: a player starts with 1 and can unlock up to MaxIncubators, each letting
-- them hatch one more egg AT THE SAME TIME. Unlocks are paid with CASH and escalate so
-- they pace with floor-1 progression (the 12 floor-1 plots cost ~188k cash total).
GameConfig.MaxIncubators = 4
-- Cash to unlock the 2nd / 3rd / 4th incubator (index = how many you currently have).
GameConfig.IncubatorUnlockCosts = { 15000, 60000, 200000 }

-- Cash cost to unlock the next incubator given how many the player already has, or nil
-- if they're already at MaxIncubators.
function GameConfig.incubatorUnlockCost(currentCount: number): number?
	if currentCount >= GameConfig.MaxIncubators then
		return nil
	end
	return GameConfig.IncubatorUnlockCosts[currentCount]
end

-- Cash cost to unlock the LADDER to the 2nd floor (after owning all 12 floor-1 plots).
GameConfig.LadderCost = 300000

-- Cash cost of the NEXT plot given how many plots the player already owns.
-- With n = currentPlots - StartingPlots + 1 (the index of the slot being bought):
--   n <= 6 -> PlotCostTable[n]   (cheap floor-1 onboarding: 100..12000)
--   n  > 6 -> 12000 * PlotCostGrowth^(n-6)   (each later slot ramps harder than a double)
function GameConfig.plotCost(currentPlots: number): number
	local n = currentPlots - GameConfig.StartingPlots + 1
	if n < 1 then
		n = 1
	end
	if n <= 6 then
		return GameConfig.PlotCostTable[n]
	end
	return math.floor(12000 * GameConfig.PlotCostGrowth ^ (n - 6))
end

-- Egg inventory cap per rarity (prevents griefing / runaway saves).
GameConfig.MaxEggsPerRarity = 99

-- TOTAL egg backpack cap: scales with rebirths. Starts at EggCapacityBase, grows
-- by EggCapacityPerRebirth per rebirth, and is hard-capped at EggCapacityMax.
GameConfig.EggCapacityBase = 5
GameConfig.EggCapacityPerRebirth = 5
GameConfig.EggCapacityMax = 50

-- Total eggs a player can hold given their rebirth count.
--   rebirth 0 = 5, 1 = 10, ... clamped at EggCapacityMax (50).
function GameConfig.eggCapacity(rebirths: number): number
	return math.clamp(
		GameConfig.EggCapacityBase + GameConfig.EggCapacityPerRebirth * rebirths,
		GameConfig.EggCapacityBase,
		GameConfig.EggCapacityMax
	)
end

-- DataStore
GameConfig.DataStoreName = "HatchABrainrot_v1"
GameConfig.DataStoreRetries = 4
GameConfig.DataStoreRetryWait = 2

return GameConfig
