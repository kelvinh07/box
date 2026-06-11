--!strict
-- DiggingManager
-- SERVER-AUTHORITATIVE digging.
--
-- Each dig spot (mound) gets its rarity ASSIGNED BY THE SERVER up front and KEPT SECRET:
-- RollEggs returns only the id (NOT the rarity), so the rarity is a true mystery until
-- you actually dig the egg up — players can't peek at a mound and skip the commons. The
-- dig time is ZONE-based (not rarity-based), so the rarity also can't be inferred from how
-- long it takes.
--
--   RollEggs(count): server rolls `count` luck-weighted rarities, stores them (with the
--                    site's zone) keyed by a server id, returns just the {id} list.
--   Dig(id):         grants the pending egg for `id` (validates proximity + a ZONE-based
--                    cooldown + that the id was assigned), and ONLY NOW reveals its rarity
--                    so the client can show what you dug up; pre-rolls the mound's next egg.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Shared = ReplicatedStorage.Shared

local GameConfig = require(Shared.Config.GameConfig)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local EggConfig = require(Shared.Config.EggConfig)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local ShovelConfig = require(Shared.Config.ShovelConfig)
local Util = require(Shared.Modules.Util)
local Net = require(Shared.Modules.Net)

local PlayerData = require(script.Parent.PlayerData)
local InventoryManager = require(script.Parent.InventoryManager)

local DiggingManager = {}

local lastDig: { [Player]: number } = {}
-- player -> { id -> { rarity, zone } }. The rarity is kept server-side and only revealed
-- on Dig; the zone is stored so the dig cooldown can be zone-based.
local pending: { [Player]: { [string]: { rarity: string, zone: number } } } = {}
local pendingCount: { [Player]: number } = {}
local idCounter = 0

local MAX_PENDING = 150           -- safety cap on un-dug assigned mounds
local MAX_ROLL_BATCH = 30         -- mounds per RollEggs call

----------------------------------------------------------------- proximity
local DIG_MARGIN = 8
local function onDigPatch(player: Player): boolean
	local patches = CollectionService:GetTagged("DigPatch")
	if #patches == 0 then
		return true
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	for _, patch in ipairs(patches) do
		if patch:IsA("BasePart") then
			local dx = math.abs(root.Position.X - patch.Position.X)
			local dz = math.abs(root.Position.Z - patch.Position.Z)
			if dx <= patch.Size.X / 2 + DIG_MARGIN and dz <= patch.Size.Z / 2 + DIG_MARGIN then
				return true
			end
		end
	end
	return false
end

----------------------------------------------------------------- rarity roll
local function luckyOdds(baseOdds: { [string]: number }, luck: number): { [string]: number }
	local out = {}
	for rarity, weight in pairs(baseOdds) do
		local mult = 1
		if rarity == "Uncommon" then
			mult = 1 + 0.30 * luck
		elseif rarity == "Rare" then
			mult = 1 + 1.0 * luck
		elseif rarity == "Legendary" then
			mult = 1 + 2.0 * luck
		end
		out[rarity] = weight * mult
	end
	return out
end

-- Roll a luck-weighted rarity using zone `effZone`'s DigOdds. `effZone` defaults to
-- the player's CurrentZone (used by the Dig regrow path, unchanged). RollEggs passes
-- the dig site's zone so digging at an unlocked higher-zone site uses its odds.
local function rollRarity(profile: any, effZone: number?): string
	local zone = ZoneConfig.get(effZone or profile.CurrentZone) or ZoneConfig.get(1)
	local luck = UpgradeConfig.totalLuck(profile.LuckLevel, profile.Rebirths)
	return Util.weightedPick(luckyOdds(zone.DigOdds, luck)) or "Common"
end

local function assign(player: Player, rarity: string, zone: number): string
	idCounter += 1
	local id = "e" .. idCounter
	pending[player] = pending[player] or {}
	pending[player][id] = { rarity = rarity, zone = zone }
	pendingCount[player] = (pendingCount[player] or 0) + 1
	return id
end

----------------------------------------------------------------- RollEggs
function DiggingManager.rollEggs(player: Player, count: number, zone: number?): any
	local profile = PlayerData.get(player)
	if not profile then
		return { ok = false, reason = "No profile." }
	end
	count = math.clamp(tonumber(count) or 1, 1, MAX_ROLL_BATCH)
	-- the dig site's zone gives BETTER odds when it is an unlocked higher zone, but a
	-- locked higher site clamps down to the player's current zone (no free luck).
	local effZone = math.max(1, math.min(tonumber(zone) or profile.CurrentZone, profile.CurrentZone))

	local out = {}
	for _ = 1, count do
		if (pendingCount[player] or 0) >= MAX_PENDING then
			break
		end
		local rarity = rollRarity(profile, effZone)
		local id = assign(player, rarity, effZone)
		-- return ONLY the id (+ zone for the client's dig timing) — never the rarity, so
		-- the client genuinely cannot reveal/peek it until the egg is dug.
		table.insert(out, { id = id, zone = effZone })
	end
	return { ok = true, eggs = out }
end

----------------------------------------------------------------- Dig
function DiggingManager.dig(player: Player, id: string): any
	local profile = PlayerData.get(player)
	if not profile then
		return { ok = false, reason = "No profile loaded." }
	end

	local bag = pending[player]
	local entry = bag and bag[id]
	if not entry then
		return { ok = false, reason = "Unknown dig spot." }
	end
	local rarity = entry.rarity
	local zone = entry.zone

	local now = os.clock()
	-- ZONE-based, shovel-scaled cooldown. The client gates each mound by the zone's hold
	-- time (deeper zone = longer, shovel = faster); the server MUST enforce that same time
	-- so an exploiter can't pull eggs faster than intended. We mirror the client's
	-- zoneDigDuration(zone, mult) and shave it by CooldownTolerance so latency on a
	-- fully-held dig never gets falsely rejected.
	local mult = ShovelConfig.digSpeedMult(profile.ShovelLevel)
	local cd = ShovelConfig.zoneDigDuration(zone, mult) * ShovelConfig.CooldownTolerance
	if lastDig[player] and (now - lastDig[player]) < cd then
		return { ok = false, reason = "Digging too fast!" }
	end
	if not onDigPatch(player) then
		return { ok = false, reason = "Stand on the dig field!" }
	end

	-- TOTAL backpack cap (scales with rebirths). Count all eggs the player holds
	-- across every rarity; if they're at/over the cap, refuse BEFORE granting so
	-- the pending egg stays assigned and the mound just resets client-side.
	local total = 0
	for _, r in ipairs(EggConfig.Order) do
		total += (profile.Eggs[r] or 0)
	end
	local cap = GameConfig.eggCapacity(profile.Rebirths)
	if total >= cap then
		return { ok = false, reason = "Backpack full! Hatch eggs first." }
	end

	lastDig[player] = now

	-- consume the pending egg and grant it (TOTAL cap above is the real limit;
	-- MaxEggsPerRarity stays as a high secondary clamp)
	bag[id] = nil
	pendingCount[player] = math.max(0, (pendingCount[player] or 1) - 1)
	profile.Eggs[rarity] = math.min(GameConfig.MaxEggsPerRarity, (profile.Eggs[rarity] or 0) + 1)

	PlayerData.markDirty(player)
	PlayerData.push(player)

	-- give the player the egg Tool (or update its count) in their Backpack.
	InventoryManager.sync(player)

	-- pre-roll the mound's NEXT egg (kept secret again) for the same site zone so the
	-- regrown mound is another mystery. We return the rarity of the egg JUST dug (the
	-- reveal) + the next id, but never the next rarity.
	local nextRarity = rollRarity(profile, zone)
	local nextId = assign(player, nextRarity, zone)

	return { ok = true, rarity = rarity, nextId = nextId, zone = zone }
end

function DiggingManager.cleanup(player: Player)
	lastDig[player] = nil
	pending[player] = nil
	pendingCount[player] = nil
end

function DiggingManager.init()
	Net.getFunction("RollEggs").OnServerInvoke = function(player, count, zone)
		return DiggingManager.rollEggs(player, count, zone)
	end
	Net.getFunction("Dig").OnServerInvoke = function(player, id)
		return DiggingManager.dig(player, id)
	end
end

return DiggingManager
