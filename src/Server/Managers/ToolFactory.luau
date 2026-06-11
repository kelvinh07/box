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

-- World-space CENTER of ONLY the model's VISIBLE geometry. The imported brainrot models carry an
-- oversized INVISIBLE RootPart (their PrimaryPart) that is OFF-center from the rendered animal, so
-- pivoting on it makes a model hang/clip well off the hand. We measure the real geometry instead
-- (matches BrainrotFactory.visibleBounds, skipping the RootPart + transparent VFX) and return the
-- CENTER of that AABB so the held model can be CENTRED on the hand: at ~character size it then sits
-- at the avatar's body height (its bottom stays above the feet, so it never clips the floor, and it
-- doesn't float up above the head the way a bottom-at-hand offset did). Returns nil if nothing
-- visible (caller falls back to the pivot).
local function visibleCenter(model: Model): Vector3?
	local min: Vector3?, max: Vector3? = nil, nil
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.95 and not (d == model.PrimaryPart and d.Name == "RootPart") then
			local cf, half = d.CFrame, d.Size / 2
			for sx = -1, 1, 2 do
				for sy = -1, 1, 2 do
					for sz = -1, 1, 2 do
						local c = (cf * CFrame.new(sx * half.X, sy * half.Y, sz * half.Z)).Position
						if not min then
							min, max = c, c
						else
							min = Vector3.new(math.min(min.X, c.X), math.min(min.Y, c.Y), math.min(min.Z, c.Z))
							max = Vector3.new(math.max(max.X, c.X), math.max(max.Y, c.Y), math.max(max.Z, c.Z))
						end
					end
				end
			end
		end
	end
	if not min or not max then
		return nil
	end
	-- center of the visible AABB (X/Y/Z midpoints)
	return Vector3.new((min.X + max.X) / 2, (min.Y + max.Y) / 2, (min.Z + max.Z) / 2)
end

-- Weld every BasePart of `model` to `handle`, after making them unanchored/massless/non-collide.
-- The model is moved so its VISIBLE-geometry CENTER sits at the handle position (NOT its off-center
-- invisible RootPart pivot). At ~average-character size the centred model holds at the avatar's body
-- height — its bottom stays above the feet (no floor clip) and it doesn't tower above the head the
-- way a bottom-at-hand offset did.
local function weldModelToHandle(model: Model, handle: Part)
	local center = visibleCenter(model)
	if center then
		-- translate the whole model so its visible center lands on the handle position (a pure
		-- world-space shift; orientation is preserved).
		local delta = handle.Position - center
		model:PivotTo(model:GetPivot() + delta)
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
	local egg = PixelEgg.build(handle.Position, EggConfig.displayHeight(rarity), color, EggConfig.ToolVoxH)
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
