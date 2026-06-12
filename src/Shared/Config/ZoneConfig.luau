--!strict
-- ZoneConfig
-- Each zone defines its own:
--   DigOdds       - weighted egg rarity table while digging in this zone
--   BrainrotTiers - which brainrot tiers are available to hatch in this zone
--   CashScale     - LEGACY: no longer used by income (see note below)
--   GemScale      - LEGACY: no longer used by income (see note below)
--   UnlockRebirths- how many rebirths are required to access this zone
--   DisplayName / GroundColor for the map.
--   Theme         - decoration style BaseManager.decorateLane applies around the dig
--                   site (e.g. "Forest" => trees flanking the lane). Zone 1 ("The
--                   Burrow") is the home/plot area and has NO theme decorations.
--
-- NOTE: income is no longer scaled by zone. CashScale/GemScale are KEPT for
-- reference but are UNUSED by income — the per-zone economy boost has been
-- REPLACED by the permanent, compounding rebirth multipliers (cash 1.2^rb,
-- gems 1.5^rb) applied in BrainrotMath. The fields remain so existing data /
-- tooling that reads them keeps working.
--
-- To add a new zone: append an entry. Everything else (digging, economy,
-- rebirth unlock chain, map building) reads from here automatically.

local ZoneConfig = {}

ZoneConfig.Zones = {
	[1] = {
		DisplayName = "The Burrow",
		GroundColor = Color3.fromRGB(95, 200, 90),
		UnlockRebirths = 0,
		-- home / plot & player-interaction area: NO theme decorations.
		Theme = "Burrow",
		DigOdds = { Common = 60, Uncommon = 24, Rare = 11, Epic = 4, Legendary = 1, Mythic = 0 },
		BrainrotTiers = { "Common", "Uncommon", "Rare", "Legendary" },
		CashScale = 1,
		GemScale = 1,
	},

	[2] = {
		DisplayName = "Forest",
		GroundColor = Color3.fromRGB(80, 180, 75),
		UnlockRebirths = 1,
		-- trees flank the lane on both sides of the dig site (BaseManager.decorateLane).
		Theme = "Forest",
		DigOdds = { Common = 40, Uncommon = 28, Rare = 20, Epic = 8, Legendary = 3, Mythic = 1 },
		-- Zone 2 unlocks the exclusive Mythic tier on top of the base tiers.
		BrainrotTiers = { "Common", "Uncommon", "Rare", "Legendary", "Mythic" },
		CashScale = 2.5,
		GemScale = 2,
	},

	[3] = {
		DisplayName = "Desert",
		GroundColor = Color3.fromRGB(170, 130, 70),
		UnlockRebirths = 2,
		-- DESERT: sand checker floor + scattered cacti/rocks (BaseManager.decorateLane "Desert" branch).
		Theme = "Desert",
		DigOdds = { Common = 22, Uncommon = 26, Rare = 28, Epic = 15, Legendary = 7, Mythic = 2 },
		BrainrotTiers = { "Common", "Uncommon", "Rare", "Legendary", "Mythic" },
		CashScale = 6,
		GemScale = 4,
	},

	-- Zones 4-8 are the NEW lane segments. They reuse the zone2/3-style wall + stone frame
	-- automatically (BaseManager builds every k>=2 wall the same way). Names/themes/odds here are
	-- sensible PLACEHOLDERS — rename / retheme / rebalance freely; no theme triggers flanking decor
	-- yet (only "Forest" does), so each is just a dig pad framed by a light-gray wall + stone piles.
	[4] = {
		DisplayName = "The Glaciers",
		GroundColor = Color3.fromRGB(90, 185, 215),
		UnlockRebirths = 3,
		-- GLACIERS: solid #D6FFFA ice floor + scattered ice spikes + a penguin (decorateLane "Glaciers").
		Theme = "Glaciers",
		DigOdds = { Common = 15, Uncommon = 23, Rare = 30, Epic = 20, Legendary = 9, Mythic = 3 },
		BrainrotTiers = { "Common", "Uncommon", "Rare", "Legendary", "Mythic" },
		CashScale = 10,
		GemScale = 6,
	},

	[5] = {
		DisplayName = "Crystal Caverns",
		GroundColor = Color3.fromRGB(180, 120, 240),
		UnlockRebirths = 4,
		Theme = "Cavern",
		DigOdds = { Common = 10, Uncommon = 20, Rare = 32, Epic = 24, Legendary = 10, Mythic = 4 },
		BrainrotTiers = { "Common", "Uncommon", "Rare", "Legendary", "Mythic" },
		CashScale = 16,
		GemScale = 9,
	},

	[6] = {
		DisplayName = "Cherry Blossom",
		GroundColor = Color3.fromRGB(120, 205, 95),
		UnlockRebirths = 5,
		-- CHERRY BLOSSOM: grass floor blanketed in pink petals (grass barely showing), sakura trees
		-- placed clear of the dig pads, + plank-and-red-lantern decor on the border walls.
		Theme = "CherryBlossom",
		DigOdds = { Common = 7, Uncommon = 16, Rare = 34, Epic = 27, Legendary = 11, Mythic = 5 },
		BrainrotTiers = { "Common", "Uncommon", "Rare", "Legendary", "Mythic" },
		CashScale = 25,
		GemScale = 14,
	},

	[7] = {
		DisplayName = "Sky Kingdom",
		GroundColor = Color3.fromRGB(200, 240, 255),
		UnlockRebirths = 6,
		Theme = "Sky",
		DigOdds = { Common = 5, Uncommon = 13, Rare = 34, Epic = 30, Legendary = 12, Mythic = 6 },
		BrainrotTiers = { "Common", "Uncommon", "Rare", "Legendary", "Mythic" },
		CashScale = 40,
		GemScale = 20,
	},

	[8] = {
		DisplayName = "Cosmic Void",
		GroundColor = Color3.fromRGB(230, 110, 255),
		UnlockRebirths = 7,
		Theme = "Cosmic",
		DigOdds = { Common = 3, Uncommon = 10, Rare = 33, Epic = 33, Legendary = 14, Mythic = 7 },
		BrainrotTiers = { "Common", "Uncommon", "Rare", "Legendary", "Mythic" },
		CashScale = 60,
		GemScale = 30,
	},
}

ZoneConfig.MaxZone = 8

-- CASH cost to BREAK the wall INTO each zone (zone progression is now decoupled from rebirth).
-- Zone 1 is the starting zone (free). Cash RESETS on rebirth, so these are per-run costs; the
-- curve uses INCREASING ratios so each successive zone takes a bit longer to reach than the last.
-- Beyond the table: previous * UnlockCashGrowth (floored). Tuned STARTER values — edit freely.
ZoneConfig.UnlockCash = {
	[1] = 0,
	[2] = 1500,
	[3] = 8000,
	[4] = 42000,
	[5] = 240000,
	[6] = 1400000,
	[7] = 8800000,
	[8] = 58000000,
}
ZoneConfig.UnlockCashGrowth = 7

-- Cash needed to break into `zone`. Zone <= 1 is free (starting zone).
function ZoneConfig.unlockCash(zone: number): number
	if zone <= 1 then
		return 0
	end
	local c = ZoneConfig.UnlockCash[zone]
	if c then
		return c
	end
	local value = ZoneConfig.UnlockCash[ZoneConfig.MaxZone]
	for _ = ZoneConfig.MaxZone + 1, zone do
		value = math.floor(value * ZoneConfig.UnlockCashGrowth)
	end
	return value
end

function ZoneConfig.get(zone: number)
	return ZoneConfig.Zones[zone]
end

-- Highest zone a player with `rebirths` rebirths is allowed to enter.
function ZoneConfig.highestUnlocked(rebirths: number): number
	local best = 1
	for zoneId, data in pairs(ZoneConfig.Zones) do
		if rebirths >= data.UnlockRebirths and zoneId > best then
			best = zoneId
		end
	end
	return best
end

return ZoneConfig
