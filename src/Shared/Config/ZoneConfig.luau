--!strict
-- ZoneConfig
-- Each zone defines its own:
--   DigOdds       - weighted egg rarity table while digging in this zone
--   BrainrotTiers - which brainrot tiers are available to hatch in this zone
--   CashScale     - multiplier applied to all Cash income earned in this zone
--   GemScale      - multiplier applied to all Gem income earned in this zone
--   UnlockRebirths- how many rebirths are required to access this zone
--   DisplayName / GroundColor for the map.
--
-- To add a new zone: append an entry. Everything else (digging, economy,
-- rebirth unlock chain, map building) reads from here automatically.

local ZoneConfig = {}

ZoneConfig.Zones = {
	[1] = {
		DisplayName = "Pizzeria Plains",
		GroundColor = Color3.fromRGB(95, 200, 90),
		UnlockRebirths = 0,
		DigOdds = { Common = 60, Uncommon = 25, Rare = 12, Legendary = 3 },
		BrainrotTiers = { "Common", "Uncommon", "Rare", "Legendary" },
		CashScale = 1,
		GemScale = 1,
	},

	[2] = {
		DisplayName = "Galleria Galattica",
		GroundColor = Color3.fromRGB(150, 90, 220),
		UnlockRebirths = 1,
		DigOdds = { Common = 40, Uncommon = 30, Rare = 22, Legendary = 8 },
		-- Zone 2 unlocks the exclusive Mythic tier on top of the base tiers.
		BrainrotTiers = { "Common", "Uncommon", "Rare", "Legendary", "Mythic" },
		CashScale = 2.5,
		GemScale = 2,
	},

	[3] = {
		DisplayName = "Vulcano Tralalero",
		GroundColor = Color3.fromRGB(240, 80, 60),
		UnlockRebirths = 2,
		DigOdds = { Common = 22, Uncommon = 28, Rare = 32, Legendary = 18 },
		BrainrotTiers = { "Common", "Uncommon", "Rare", "Legendary", "Mythic" },
		CashScale = 6,
		GemScale = 4,
	},
}

ZoneConfig.MaxZone = 3

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
