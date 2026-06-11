--!strict
-- InventoryManager
-- Keeps the player's Backpack (the Roblox toolbar) in sync with their profile:
--   * one EGG tool per egg rarity with count > 0
--   * one BRAINROT tool per Collection entry with placed == false
--
-- Tools are RECONCILED, not rebuilt: each tool is keyed by a stable signature
-- ("Egg:<rarity>" / "Brainrot:<id>"). sync() ADDS missing tools and DESTROYS tools whose key
-- is no longer wanted, but LEAVES a still-valid tool untouched — so the currently-equipped tool
-- (which lives in the Character, not the Backpack) is never destroyed+recreated mid-equip.
--
-- This module is SERVER-authoritative and is the single owner of inventory Tool lifecycle. It is
-- deliberately FREE of cycles: it requires only data/config + the factories, never BaseManager /
-- EconomyManager / IncubationManager (those call INTO sync()).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local PlayerData = require(script.Parent.PlayerData)
local ToolFactory = require(script.Parent.ToolFactory)
local EggConfig = require(Shared.Config.EggConfig)

local InventoryManager = {}

----------------------------------------------------------------- keys
-- Stable signature for a tool, derived purely from its attributes (so it survives reparenting
-- between Backpack and Character). Returns nil for any non-inventory tool.
local function toolKey(tool: Instance): string?
	if not tool:IsA("Tool") then
		return nil
	end
	local kind = tool:GetAttribute("Kind")
	if kind == "Egg" then
		local rarity = tool:GetAttribute("Rarity")
		if typeof(rarity) == "string" then
			return "Egg:" .. rarity
		end
	elseif kind == "Brainrot" then
		local id = tool:GetAttribute("BrainrotId")
		if typeof(id) == "string" then
			return "Brainrot:" .. id
		end
	end
	return nil
end

-- Collect every inventory tool the player currently has (Backpack + Character), keyed by
-- signature. Non-inventory tools (none today, but be defensive) are ignored.
local function collectExisting(player: Player): { [string]: Tool }
	local out: { [string]: Tool } = {}
	local function scan(container: Instance?)
		if not container then
			return
		end
		for _, child in ipairs(container:GetChildren()) do
			local key = toolKey(child)
			if key then
				out[key] = child :: Tool
			end
		end
	end
	scan(player:FindFirstChild("Backpack"))
	scan(player.Character)
	return out
end

----------------------------------------------------------------- sync
-- Reconcile the player's tools to match their profile. Safe to call any time; no-op if the
-- profile isn't loaded yet.
function InventoryManager.sync(player: Player)
	local profile = PlayerData.get(player)
	if not profile then
		return
	end
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then
		-- Backpack may not exist yet (very early join) — nothing to sync into.
		return
	end

	-- 1) build the DESIRED key set from the profile.
	local desired: { [string]: boolean } = {}
	local eggs = profile.Eggs or {}
	for _, rarity in ipairs(EggConfig.Order) do
		local count = eggs[rarity]
		if typeof(count) == "number" and count > 0 then
			desired["Egg:" .. rarity] = true
		end
	end
	local collection = profile.Collection or {}
	for _, entry in ipairs(collection) do
		if entry.placed ~= true and typeof(entry.id) == "string" then
			desired["Brainrot:" .. entry.id] = true
		end
	end

	-- 2) what exists right now (Backpack + Character).
	local existing = collectExisting(player)

	-- 3) DESTROY tools that are no longer wanted (count hit 0, brainrot placed/sold).
	for key, tool in pairs(existing) do
		if not desired[key] then
			tool:Destroy()
		end
	end

	-- 4) ADD any desired tool that doesn't already exist (leave still-valid ones alone, so an
	--    equipped tool is never interrupted).
	local rebirths = profile.Rebirths or 0
	for _, rarity in ipairs(EggConfig.Order) do
		local key = "Egg:" .. rarity
		if desired[key] and not existing[key] then
			ToolFactory.buildEggTool(rarity).Parent = backpack
		end
	end
	for _, entry in ipairs(collection) do
		if entry.placed ~= true and typeof(entry.id) == "string" then
			local key = "Brainrot:" .. entry.id
			if not existing[key] then
				ToolFactory.buildBrainrotTool(entry, rebirths).Parent = backpack
			end
		end
	end
end

----------------------------------------------------------------- equipped queries
-- The rarity of the egg tool the player currently HOLDS (a Tool parented to the Character),
-- or nil if they're not holding an egg.
function InventoryManager.getEquippedEgg(player: Player): string?
	local char = player.Character
	if not char then
		return nil
	end
	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("Kind") == "Egg" then
			local rarity = child:GetAttribute("Rarity")
			if typeof(rarity) == "string" then
				return rarity
			end
		end
	end
	return nil
end

-- The BrainrotId of the brainrot tool the player currently HOLDS, or nil if none.
function InventoryManager.getEquippedBrainrot(player: Player): string?
	local char = player.Character
	if not char then
		return nil
	end
	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Tool") and child:GetAttribute("Kind") == "Brainrot" then
			local id = child:GetAttribute("BrainrotId")
			if typeof(id) == "string" then
				return id
			end
		end
	end
	return nil
end

----------------------------------------------------------------- lifecycle
-- Destroy every inventory tool the player has (on leave; nothing persists in the Backpack).
function InventoryManager.cleanup(player: Player)
	local existing = collectExisting(player)
	for _, tool in pairs(existing) do
		tool:Destroy()
	end
end

-- No remotes/handlers of its own — placement is routed by BaseManager's prompt router, which
-- calls getEquipped*; the various managers call sync() after they mutate the profile. Bootstrap
-- drives sync() on join + CharacterAdded.
function InventoryManager.init() end

return InventoryManager
