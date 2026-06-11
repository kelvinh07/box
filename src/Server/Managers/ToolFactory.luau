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
local EggConfig = require(Shared.Config.EggConfig)
local BrainrotFactory = require(script.Parent.BrainrotFactory)

local ToolFactory = {}

-- Handle is small + invisible; the visible model is welded on top of it.
local HANDLE_SIZE = Vector3.new(1.4, 1.4, 1.4)

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

-- World-space GRIP POINT for a held brainrot: the VOLUME-WEIGHTED CENTROID (≈ center of mass) of the
-- model's VISIBLE geometry, skipping the oversized invisible RootPart + transparent VFX (matches
-- BrainrotFactory.visibleBounds). Gripping the centroid of the BULK — rather than the AABB centre —
-- means a model with a thin protrusion (a giraffe's neck, a horn) is gripped in its BODY instead of
-- high up the bounding box, so EVERY brainrot reads as carried from the MIDDLE rather than "from the
-- top". Returns nil if nothing visible (caller falls back to the pivot).
local function visibleGrip(model: Model): Vector3?
	local sum = Vector3.zero
	local totalVol = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.95 and not (d == model.PrimaryPart and d.Name == "RootPart") then
			local vol = d.Size.X * d.Size.Y * d.Size.Z
			sum += d.Position * vol
			totalVol += vol
		end
	end
	if totalVol <= 0 then
		return nil
	end
	return sum / totalVol
end

-- Weld every BasePart of `model` to `handle`, after making them unanchored/massless/non-collide.
-- The model is re-oriented 180° about the vertical axis through its grip point so the brainrot faces
-- AWAY from the player (we see its back, like it's held out facing forward), and its grip point — the
-- bulk centroid (visibleGrip) — is moved onto the handle so every brainrot is carried from the MIDDLE
-- of its body, at the avatar's body height (bottom stays above the feet, so no floor clip).
local function weldModelToHandle(model: Model, handle: Part)
	local grip = visibleGrip(model)
	if grip then
		-- M maps the grip point onto the handle and yaws the model 180° about the vertical axis through
		-- the grip: for any world point x, x -> handle.Position + Rot180Y * (x - grip).
		local M = CFrame.new(handle.Position) * CFrame.Angles(0, math.pi, 0) * CFrame.new(-grip)
		model:PivotTo(M * model:GetPivot())
	else
		model:PivotTo(handle.CFrame) -- nothing visible (shouldn't happen): fall back to the pivot.
	end
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

	-- a rarity-tinted pixel egg welded to the handle — SAME SIZE as the in-world dug egg
	-- (height = EggConfig.displayHeight(rarity)) but a LOWER voxel resolution (EggConfig.ToolVoxH)
	-- so the welded, replicated in-hand assembly stays cheap (the dug egg can afford voxH 12 since
	-- it's anchored + client-local + built lazily). voxH only trades cube count for pixel fineness,
	-- so the silhouette matches. PixelEgg builds an ANCHORED model centred at the given point (here
	-- the handle), so we weld each cube to the handle and drop the transparent EggCore.
	local color = RarityColors.tier(rarity)
	local height = EggConfig.displayHeight(rarity)
	-- Build the egg so its BOTTOM edge sits at the handle (offset the centre up by half the height):
	-- the hand then grips the BOTTOM of the egg so it reads as HELD, instead of being skewered through
	-- the centre (which clipped the egg into the player's arm).
	local egg = PixelEgg.build(handle.Position + Vector3.new(0, height / 2, 0), height, color, EggConfig.ToolVoxH)
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
