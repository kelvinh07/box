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

-- Dig cooldown (seconds) between successful digs. Kept below the shortest
-- hold-to-dig time (Common = ~0.96s) so a fully-held dig always succeeds.
GameConfig.DigCooldown = 0.8

-- How fast players walk (applied to the Humanoid on spawn).
GameConfig.PlayerWalkSpeed = 35

-- Starting state for a brand new player.
GameConfig.StartingCash = 50
GameConfig.StartingGems = 0
GameConfig.StartingPlots = 3

-- Plot purchasing: cost scales with how many plots you already own.
-- Plots 1-12 are floor 1, plots 13-24 are floor 2 of the base building.
GameConfig.MaxPlots = 24
GameConfig.PlotBaseCost = 250         -- cost of the 4th plot
GameConfig.PlotCostGrowth = 1.8       -- multiplier per additional plot

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
