--!strict
-- ToolVisual
-- The ONE place both the Hotbar and the Inventory overlay use to render an inventory item
-- (an egg or a brainrot) into a transparent ViewportFrame "icon". Centralising it means the
-- bounds/camera-framing maths + the "find a replicated source model" logic live in a single
-- module instead of being duplicated per panel.
--
-- The eggs render as the SHARED full-detail PixelEgg (same height + voxel resolution as the
-- in-world dug egg, sourced from EggConfig). Brainrots render the REAL replicated model — its
-- inventory Tool (Backpack/Character) or, failing that, its placed podium model in Workspace —
-- cloned and tightly framed so it FILLS the card. Callers that get `false` back from
-- renderBrainrotById show a colored swatch fallback (the model hasn't replicated yet).
--
-- ViewportFrames are not free: callers build a per-item icon ONCE and reuse it; this module
-- only does the (one-time) build + framing.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local EggConfig = require(Shared.Config.EggConfig)
local RarityColors = require(Shared.Config.RarityColors)
local PixelEgg = require(Shared.Modules.PixelEgg)

local player = Players.LocalPlayer

local ToolVisual = {}

local FOV = 40                                   -- camera field of view (degrees)
local DIR = Vector3.new(0.35, 0.25, 1).Unit      -- look direction (slightly above + to the side)
local FILL = 0.85                                -- fraction of the viewport the model should fill

----------------------------------------------------------------- bounds
-- world-space (center, size) of an instance's VISIBLE, REAL geometry. Mirrors
-- BrainrotFactory.visibleBounds: the imported brainrot models carry an OVERSIZED invisible
-- "RootPart" (the PrimaryPart) plus near-transparent VFX parts; measuring those wrecks the
-- framing, so we SKIP any BasePart named "RootPart" and anything with Transparency >= 0.95.
local function computeBounds(inst: Instance): (Vector3, Vector3)
	local minv: Vector3?, maxv: Vector3? = nil, nil
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "RootPart" and d.Transparency < 0.95 then
			local cf, h = d.CFrame, d.Size / 2
			for sx = -1, 1, 2 do
				for sy = -1, 1, 2 do
					for sz = -1, 1, 2 do
						local p = (cf * CFrame.new(sx * h.X, sy * h.Y, sz * h.Z)).Position
						if not minv then
							minv, maxv = p, p
						else
							minv = Vector3.new(math.min(minv.X, p.X), math.min(minv.Y, p.Y), math.min(minv.Z, p.Z))
							maxv = Vector3.new(math.max(maxv.X, p.X), math.max(maxv.Y, p.Y), math.max(maxv.Z, p.Z))
						end
					end
				end
			end
		end
	end
	if not minv or not maxv then
		return Vector3.zero, Vector3.zero
	end
	return (minv + maxv) / 2, (maxv - minv)
end

----------------------------------------------------------------- frame
-- Mount a built model into a transparent ViewportFrame, strip labels/lights/particles, add a
-- camera, and frame it so the model FILLS ~85% of the viewport (TIGHT framing). The distance is
-- computed from the model's span + the camera FOV so any size model fills the same fraction.
function ToolVisual.frame(vf: ViewportFrame, holder: Model)
	for _, d in ipairs(holder:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		elseif d:IsA("BillboardGui") or d:IsA("SurfaceGui") or d:IsA("ClickDetector")
			or d:IsA("ProximityPrompt") or d:IsA("ParticleEmitter") or d:IsA("Light") then
			d:Destroy()
		end
	end
	holder.Parent = vf

	vf.BackgroundTransparency = 1
	vf.Ambient = Color3.fromRGB(220, 220, 220)
	vf.LightColor = Color3.fromRGB(255, 255, 255)
	vf.LightDirection = Vector3.new(-0.4, -1, -0.3)

	local center, size = computeBounds(holder)
	local span = math.max(size.X, size.Y, size.Z)
	if span <= 0 then
		span = 6
	end

	local cam = Instance.new("Camera")
	cam.FieldOfView = FOV
	-- distance so the model's span subtends ~FILL of the vertical FOV (the *1/FILL term),
	-- with a small extra margin so corners never clip
	local halfFov = math.rad(FOV / 2)
	local dist = (span * 0.5) / math.tan(halfFov) / FILL * 1.15
	cam.CFrame = CFrame.lookAt(center + DIR * dist, center)
	cam.Parent = vf
	vf.CurrentCamera = cam
end

----------------------------------------------------------------- egg
function ToolVisual.renderEgg(vf: ViewportFrame, rarity: string)
	local holder = Instance.new("Model")
	local egg = PixelEgg.build(Vector3.zero, EggConfig.displayHeight(rarity), RarityColors.tier(rarity), 12)
	egg.Parent = holder
	ToolVisual.frame(vf, holder)
end

----------------------------------------------------------------- brainrot
-- Find a replicated model for a brainrot id: its inventory Tool (Backpack/Character first, since
-- it's the freshest source) or its placed podium model in Workspace. Returns nil if neither is
-- replicated yet.
local function findBrainrotSource(id: string): Instance?
	local function scanTools(container: Instance?): Instance?
		if not container then
			return nil
		end
		for _, c in ipairs(container:GetChildren()) do
			if c:IsA("Tool") and c:GetAttribute("Kind") == "Brainrot" and c:GetAttribute("BrainrotId") == id then
				return c
			end
		end
		return nil
	end
	local fromTool = scanTools(player:FindFirstChild("Backpack")) or scanTools(player.Character)
	if fromTool then
		return fromTool
	end
	for _, m in ipairs(CollectionService:GetTagged("Brainrot")) do
		if m:GetAttribute("BrainrotId") == id then
			return m
		end
	end
	return nil
end

-- Render a brainrot by id into the viewport. Returns false (so the caller / mountBrainrot can
-- retry) when there is nothing real to show yet — either no source model is replicated, or the
-- cloned source has NO visible geometry (its parts haven't replicated in). On false it leaves the
-- viewport CLEAN (no stale Camera) so a later retry actually re-runs the framing.
function ToolVisual.renderBrainrotById(vf: ViewportFrame, id: string): boolean
	-- clear any prior attempt (old Camera + holder) so repeated attempts don't stack
	for _, c in ipairs(vf:GetChildren()) do
		c:Destroy()
	end
	vf.CurrentCamera = nil

	local src = findBrainrotSource(id)
	if not src then
		return false
	end
	local holder = Instance.new("Model")
	local clone = src:Clone()
	if clone:IsA("Model") then
		clone.Parent = holder
	else
		-- a Tool: lift its BaseParts into the holder model
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Parent = holder
			end
		end
		clone:Destroy()
	end

	-- guard against an EMPTY clone (parts not replicated yet): measure the REAL visible geometry
	-- (RootPart + transparent VFX excluded) and bail with NO camera so the retry loop fires.
	local _, size = computeBounds(holder)
	if math.max(size.X, size.Y, size.Z) <= 0 then
		holder:Destroy()
		return false
	end

	ToolVisual.frame(vf, holder)
	return true
end

-- Fire-and-forget retry wrapper: render the brainrot NOW; if it can't yet (source / geometry not
-- replicated), spin a short retry loop into the SAME viewport (it never creates a new slot). This
-- absorbs slow replication — by the time the parts arrive a retry succeeds and stops the loop.
function ToolVisual.mountBrainrot(vf: ViewportFrame, id: string)
	if ToolVisual.renderBrainrotById(vf, id) then
		return
	end
	task.spawn(function()
		for _ = 1, 12 do
			task.wait(0.25)
			if vf.Parent == nil then
				return
			end
			if ToolVisual.renderBrainrotById(vf, id) then
				return
			end
		end
	end)
end

----------------------------------------------------------------- dex preview (any brainrot+variant)
-- The Collection "dex" needs to render EVERY brainrot — even ones the player doesn't own — so it
-- can't use the owned-source lookup above. Instead it clones the read-only base model the server
-- exposes in ReplicatedStorage.BrainrotModels and applies the look itself: a flat BLACK silhouette
-- when LOCKED, else the variant recolor (Gold metal / Diamond cyan-glass / Galaxy purple-glass;
-- Normal keeps its real textures) — mirroring BrainrotFactory.recolorVariant.
local VARIANT_MATERIAL = {
	Gold = Enum.Material.Metal,
	Diamond = Enum.Material.Glass,
	Galaxy = Enum.Material.Glass,
}
local SILHOUETTE = Color3.fromRGB(18, 18, 24)

local function previewSource(base: string): Model?
	local folder = ReplicatedStorage:FindFirstChild("BrainrotModels")
	local m = folder and folder:FindFirstChild(base)
	return (m and m:IsA("Model")) and m or nil
end

-- Render a brainrot (by base name + variant) into the viewport. `locked` => black silhouette.
-- Returns false (so a retry can fire) until ReplicatedStorage.BrainrotModels has replicated in.
function ToolVisual.renderBrainrotPreview(vf: ViewportFrame, base: string, variant: string, locked: boolean): boolean
	for _, c in ipairs(vf:GetChildren()) do
		c:Destroy()
	end
	vf.CurrentCamera = nil

	local src = previewSource(base)
	if not src then
		return false
	end
	local holder = Instance.new("Model")
	local clone = src:Clone()
	clone.Parent = holder

	for _, d in ipairs(holder:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.95 and d.Name ~= "RootPart" then
			if locked then
				d.Color = SILHOUETTE
				d.Material = Enum.Material.SmoothPlastic
				if d:IsA("MeshPart") then
					d.TextureID = ""
				end
				local sa = d:FindFirstChildWhichIsA("SurfaceAppearance")
				if sa then sa:Destroy() end
			elseif variant ~= "Normal" then
				d.Color = RarityColors.variant(variant)
				local mat = VARIANT_MATERIAL[variant]
				if mat then d.Material = mat end
				if d:IsA("MeshPart") then
					d.TextureID = ""
				end
				local sa = d:FindFirstChildWhichIsA("SurfaceAppearance")
				if sa then sa:Destroy() end
			end
		end
	end

	-- guard against an EMPTY clone (parts not replicated yet): no visible geometry -> retry.
	local _, size = computeBounds(holder)
	if math.max(size.X, size.Y, size.Z) <= 0 then
		holder:Destroy()
		return false
	end

	ToolVisual.frame(vf, holder)
	return true
end

-- Fire-and-forget retry wrapper (same pattern as mountBrainrot): render now; if the source model
-- isn't replicated yet, spin a short retry loop into the SAME viewport.
function ToolVisual.mountBrainrotPreview(vf: ViewportFrame, base: string, variant: string, locked: boolean)
	if ToolVisual.renderBrainrotPreview(vf, base, variant, locked) then
		return
	end
	task.spawn(function()
		for _ = 1, 16 do
			task.wait(0.25)
			if vf.Parent == nil then
				return
			end
			if ToolVisual.renderBrainrotPreview(vf, base, variant, locked) then
				return
			end
		end
	end)
end

----------------------------------------------------------------- dispatch
-- Dispatch a real Tool to the right renderer by its "Kind" attribute. Returns false only for the
-- brainrot path when the source model hasn't replicated yet (eggs always succeed).
function ToolVisual.renderTool(vf: ViewportFrame, tool: Instance): boolean
	local kind = tool:GetAttribute("Kind")
	if kind == "Egg" then
		ToolVisual.renderEgg(vf, tostring(tool:GetAttribute("Rarity") or "Common"))
		return true
	elseif kind == "Brainrot" then
		return ToolVisual.renderBrainrotById(vf, tostring(tool:GetAttribute("BrainrotId")))
	end
	return false
end

return ToolVisual
