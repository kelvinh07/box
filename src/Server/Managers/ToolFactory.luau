--!strict
-- ToolFactory
-- Builds the real Roblox Tool instances that live in a player's Backpack/toolbar:
--   * Egg tools   — one per egg rarity the player holds (shows a pixel egg in-hand).
--   * Brainrot tools — one per UNPLACED owned brainrot (shows the brainrot in-hand).
--
-- Tools are server-built (handhelds use ServerStorage models the client can't see) and synced
-- into Backpack by InventoryManager. Every tool carries attributes so the prompt router, the
-- client overlay, and the client prompt-enabler can identify it without parsing names:
--   Egg tool      -> Kind="Egg",      Rarity=<rarity>
--   Brainrot tool -> Kind="Brainrot", BrainrotId=<id>, Variant=<v>, Tier=<t>
--
-- Each tool has a real Handle named exactly "Handle" (RequiresHandle=true); the visible model
-- is welded to that Handle via WeldConstraints, with every part unanchored + massless +
-- non-colliding so the character carries it cleanly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local PixelEgg = require(Shared.Modules.PixelEgg)
local RarityColors = require(Shared.Config.RarityColors)
local BrainrotFactory = require(script.Parent.BrainrotFactory)

local ToolFactory = {}

-- Handle is small + invisible; the visible model is welded on top of it.
local HANDLE_SIZE = Vector3.new(1.4, 1.4, 1.4)

-- Pixel egg height for the in-hand display (small enough to read in the toolbar).
local EGG_HANDHELD_HEIGHT = 2.4

----------------------------------------------------------------- helpers
-- Make a fresh invisible Handle part for a tool.
local function makeHandle(): Part
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = HANDLE_SIZE
	handle.Transparency = 1
	handle.CanCollide = false
	handle.CanQuery = false
	handle.Massless = true
	handle.Anchored = false
	return handle
end

-- Weld a single loose BasePart to `handle`, after making it unanchored/massless/non-collide.
-- (Never weld the handle to itself — callers skip it.)
local function weldPartToHandle(part: BasePart, handle: Part)
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = part
	weld.Parent = part
end

-- Weld every BasePart of `model` to `handle`, after making them unanchored/massless/non-collide.
-- The model is pivoted so it sits on the handle before welding.
local function weldModelToHandle(model: Model, handle: Part)
	model:PivotTo(handle.CFrame) -- centre the visible model on the handle so it reads in-hand.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			weldPartToHandle(d, handle)
		end
	end
end

----------------------------------------------------------------- egg tool
-- Build the Tool for an egg rarity. One per rarity with count > 0 (count lives in the profile,
-- not on the tool — the tool is identity-only, so a count change needs no rebuild).
function ToolFactory.buildEggTool(rarity: string): Tool
	local tool = Instance.new("Tool")
	tool.Name = rarity .. " Egg"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute("Kind", "Egg")
	tool:SetAttribute("Rarity", rarity)

	local handle = makeHandle()
	handle.Parent = tool

	-- a small, rarity-tinted pixel egg welded to the handle. PixelEgg builds an ANCHORED model
	-- centred at the given point (here the handle), so we weld each cube to the handle and drop
	-- the transparent EggCore (no need for it once welded).
	local color = RarityColors.tier(rarity)
	local egg = PixelEgg.build(handle.Position, EGG_HANDHELD_HEIGHT, color, 6)
	for _, d in ipairs(egg:GetChildren()) do
		if d:IsA("BasePart") and d.Name ~= "EggCore" then
			d.Parent = tool
			weldPartToHandle(d, handle)
		end
	end
	egg:Destroy()

	return tool
end

----------------------------------------------------------------- brainrot tool
-- Build the Tool for an UNPLACED brainrot entry. One per entry (keyed by entry.id).
function ToolFactory.buildBrainrotTool(entry: any, rebirthCount: number): Tool
	local tool = Instance.new("Tool")
	tool.Name = entry.base
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute("Kind", "Brainrot")
	tool:SetAttribute("BrainrotId", entry.id)
	tool:SetAttribute("Variant", entry.variant)
	tool:SetAttribute("Tier", entry.tier)

	local handle = makeHandle()
	handle.Parent = tool

	local model = BrainrotFactory.buildHandheld(entry)
	model.Parent = tool
	weldModelToHandle(model, handle)

	return tool
end

return ToolFactory
