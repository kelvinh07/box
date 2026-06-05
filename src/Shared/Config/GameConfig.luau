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
-- digs with a RARITY-AWARE cooldown derived from ShovelConfig.holdDuration (so rarer
-- eggs take longer on the server too). Kept only as a reference/fallback flat value;
-- it is no longer the active rate limit in DiggingManager.
GameConfig.DigCooldown = 0.8

-- How fast players walk (applied to the Humanoid on spawn).
GameConfig.PlayerWalkSpeed = 35

-- Starting state for a brand new player.
GameConfig.StartingCash = 50
GameConfig.StartingGems = 0
GameConfig.StartingPlots = 3

-- Plot purchasing: Cash cost scales with how many plots you already own.
-- Plots 1-12 are floor 1, plots 13-24 are floor 2 of the base building.
-- The Nth purchased slot BEYOND StartingPlots(=3) follows the table below; past
-- the 6th extra slot the cost DOUBLES every slot. See GameConfig.plotCost.
GameConfig.MaxPlots = 24
GameConfig.PlotCostTable = { 100, 300, 800, 2000, 5000, 12000 } -- Nth extra slot, 1..6

-- Cash cost of the NEXT plot given how many plots the player already owns.
-- With n = currentPlots - StartingPlots + 1 (the index of the slot being bought):
--   n <= 6 -> PlotCostTable[n]
--   n  > 6 -> 12000 * 2^(n-6)   (7th 24000, 8th 48000, ...)
function GameConfig.plotCost(currentPlots: number): number
	local n = currentPlots - GameConfig.StartingPlots + 1
	if n < 1 then
		n = 1
	end
	if n <= 6 then
		return GameConfig.PlotCostTable[n]
	end
	return 12000 * 2 ^ (n - 6)
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

-- Floating "+$" / "+Gem" popups are throttled so we don't spam the client.
GameConfig.PopupAccumulateSeconds = 1

return GameConfig
