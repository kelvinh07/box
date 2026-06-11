--!strict
-- BrainrotFactory
-- Builds the physical model for an owned brainrot.
--   * If AssetConfig has a Creator Store asset id for the brainrot, it inserts
--     that model via InsertService, anchors + scales it to sit on a podium.
--   * Otherwise it builds a chunky, brightly-colored PROCEDURAL placeholder so
--     the game is fully playable with zero asset ids filled in.
-- Variant glow (Gold/Diamond/Galaxy) is layered on top via PointLight +
-- ParticleEmitter using the variant color language.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Shared = ReplicatedStorage.Shared

local BrainrotConfig = require(Shared.Config.BrainrotConfig)
local VariantConfig = require(Shared.Config.VariantConfig)
local AssetConfig = require(Shared.Config.AssetConfig)
local RarityColors = require(Shared.Config.RarityColors)
local BrainrotMath = require(Shared.Modules.BrainrotMath)
local Format = require(Shared.Modules.Format)

local BrainrotFactory = {}

-- The brainrot's platform/pedestal. A single THICK gray block (BaseManager.buildPodium) — the
-- footprint matches the old cyan rim (7x7) and it's THICKENED to ~2.3 tall (a touch under the
-- LEVEL UP sign's height) so the LEVEL UP sign can mount on its inward side face.
local PODIUM_SIZE = Vector3.new(7, 2.3, 7)

----------------------------------------------------------------- placeholder
-- A chunky stylized "brainrot": rounded body + eyes + little feet. Intentionally
-- low-fidelity but bold and readable from far away.
local function buildPlaceholder(name: string, color: Color3, scale: number): Model
	local model = Instance.new("Model")
	model.Name = name

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(4, 4, 4) * scale
	body.Color = color
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.Parent = model
	model.PrimaryPart = body

	-- eyes (whites + pupils) for a goofy face
	for i = -1, 1, 2 do
		local eye = Instance.new("Part")
		eye.Shape = Enum.PartType.Ball
		eye.Size = Vector3.new(1.1, 1.1, 1.1) * scale
		eye.Color = Color3.new(1, 1, 1)
		eye.Material = Enum.Material.SmoothPlastic
		eye.Anchored = true
		eye.CanCollide = false
		eye.CFrame = body.CFrame * CFrame.new(0.8 * i * scale, 0.6 * scale, -1.8 * scale)
		eye.Parent = model

		local pupil = Instance.new("Part")
		pupil.Shape = Enum.PartType.Ball
		pupil.Size = Vector3.new(0.5, 0.5, 0.5) * scale
		pupil.Color = Color3.new(0, 0, 0)
		pupil.Material = Enum.Material.SmoothPlastic
		pupil.Anchored = true
		pupil.CanCollide = false
		pupil.CFrame = eye.CFrame * CFrame.new(0, 0, -0.45 * scale)
		pupil.Parent = model
	end

	-- little feet
	for i = -1, 1, 2 do
		local foot = Instance.new("Part")
		foot.Size = Vector3.new(1, 0.8, 1.6) * scale
		foot.Color = color:Lerp(Color3.new(0, 0, 0), 0.3)
		foot.Material = Enum.Material.SmoothPlastic
		foot.Anchored = true
		foot.CanCollide = false
		foot.CFrame = body.CFrame * CFrame.new(1.1 * i * scale, -2.1 * scale, -0.5 * scale)
		foot.Parent = model
	end

	return model
end

----------------------------------------------------------------- creator store
local function tryInsert(assetId: number, name: string): Model?
	local ok, result = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or not result then
		warn(("[BrainrotFactory] Failed to insert asset %d for %s — using placeholder."):format(assetId, name))
		return nil
	end
	-- LoadAsset returns a Model container; grab the first Model inside.
	local container = result :: Instance
	local found: Model? = nil
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Model") then
			found = child
			break
		end
	end
	if found then
		found.Parent = nil
		container:Destroy()
		-- anchor everything so it sits still on the podium
		for _, d in ipairs(found:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
			end
		end
		if not found.PrimaryPart then
			local anyPart = found:FindFirstChildWhichIsA("BasePart", true)
			found.PrimaryPart = anyPart
		end
		return found
	end
	container:Destroy()
	return nil
end

-- The display target for a model's VISIBLE longest axis after scaling. The podium top is only
-- 7 wide, so this intentionally OVERFLOWS it — per design we'd rather a model spill over the
-- podium edge than read as a tiny floating speck (was 7, measured off the inflated bbox below).
local DISPLAY_MAX_AXIS = 10

-- World-space (center, size) of ONLY the rendered parts. The imported animal models each carry an
-- oversized INVISIBLE RootPart (their PrimaryPart) that balloons Model:GetBoundingBox() — that
-- made the old normalizeSize divide by a too-big number and shrink the visible animal to a
-- fraction of the podium. We skip the RootPart + any transparent VFX and measure real geometry.
local function visibleBounds(model: Model): (Vector3, Vector3)
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
		local cf, s = model:GetBoundingBox() -- nothing visible (shouldn't happen): fall back to the full bbox
		return cf.Position, s
	end
	return (min + max) / 2, max - min
end

-- Scale the model so its VISIBLE longest axis is DISPLAY_MAX_AXIS * scale.
-- We deliberately DO NOT use Model:ScaleTo here. These imported animals are rigged (Motor6D joints
-- whose stored transforms don't match the authored part CFrames), and ScaleTo rebuilds the model
-- through those joints — which scatters several models to 1000+ studs and paradoxically SHRINKS
-- others (this is why some brainrots read tiny). Since the display models are anchored + inert,
-- the joints don't matter, so we scale every part manually about the visible center instead.
local function normalizeSize(model: Model, scale: number)
	local center, size = visibleBounds(model)
	local maxAxis = math.max(size.X, size.Y, size.Z)
	if maxAxis <= 0 then return end
	local factor = (DISPLAY_MAX_AXIS * scale) / maxAxis
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local pos = d.Position
			local rot = d.CFrame - pos -- rotation-only CFrame
			d.Size *= factor
			d.CFrame = rot + (center + (pos - center) * factor)
			local mesh = d:FindFirstChildWhichIsA("DataModelMesh") -- SpecialMesh/BlockMesh/etc.
			if mesh then
				mesh.Scale *= factor
				mesh.Offset *= factor
			end
		elseif d:IsA("Attachment") then
			d.Position *= factor
		end
	end
end

----------------------------------------------------------------- imported animal models
-- The imported "Animals" models live in ServerStorage.BrainrotModels, named exactly like the
-- BrainrotConfig keys. Clone the matching one, anchored + non-colliding, ready for the podium.
local function cloneRealModel(name: string): Model?
	local folder = ServerStorage:FindFirstChild("BrainrotModels")
	local src = folder and folder:FindFirstChild(name)
	if not src or not src:IsA("Model") then
		return nil
	end
	local m = src:Clone()
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	if not m.PrimaryPart then
		m.PrimaryPart = (m:FindFirstChild("RootPart") :: BasePart?) or m:FindFirstChildWhichIsA("BasePart", true)
	end
	return m
end

-- Recolor a variant VERSION of a model: Gold -> gold, Diamond -> diamond-cyan, Galaxy ->
-- purple (Normal is left as its real textured self). We clear mesh textures so the recolor
-- shows as a solid, unmistakable gold/diamond/galaxy statue.
local VARIANT_MATERIAL = {
	Gold    = Enum.Material.Metal, -- metallic gold
	Diamond = Enum.Material.Glass, -- cyan crystal
	Galaxy  = Enum.Material.Glass, -- purple crystal (Neon washed the shape into a pink blob)
}
local function recolorVariant(model: Model, variant: string)
	if variant == "Normal" then
		return
	end
	local color = RarityColors.variant(variant) -- Gold=gold, Diamond=cyan, Galaxy=purple
	local mat = VARIANT_MATERIAL[variant]
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Color = color
			if mat then
				d.Material = mat
			end
			if d:IsA("MeshPart") then
				d.TextureID = ""
			end
			local sa = d:FindFirstChildWhichIsA("SurfaceAppearance")
			if sa then
				sa:Destroy()
			end
		end
	end
end

----------------------------------------------------------------- glow
local function applyGlow(model: Model, variant: string)
	local data = VariantConfig.get(variant)
	if not data or not data.Glow then
		return
	end
	local color = RarityColors.variant(variant)
	local primary = model.PrimaryPart
	if not primary then return end

	-- a SUBTLE glow only — bright lights washed the gold/diamond models out so you couldn't
	-- see the character. Keep it low so the recolored model still reads clearly.
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 1
	light.Range = 7
	light.Parent = primary

	local attach = Instance.new("Attachment")
	attach.Parent = primary

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Color = ColorSequence.new(color)
	sparkles.LightEmission = 0.4
	sparkles.Size = NumberSequence.new(0.45)
	sparkles.Lifetime = NumberRange.new(0.6, 1.2)
	sparkles.Rate = (variant == "Galaxy") and 16 or 8
	sparkles.Speed = NumberRange.new(1, 3)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Texture = "rbxassetid://6334482272" -- generic spark
	sparkles.Parent = primary

	-- (Galaxy is now a solid PURPLE recolor via recolorVariant — no rainbow shimmer.)
end

----------------------------------------------------------------- label
local function buildLabel(model: Model, entry: any, rebirthCount: number)
	local primary = model.PrimaryPart
	if not primary then return end

	local bb = Instance.new("BillboardGui")
	bb.Name = "InfoLabel"
	bb.Size = UDim2.new(0, 220, 0, 64)
	bb.StudsOffset = Vector3.new(0, 8, 0) -- clears the bigger (DISPLAY_MAX_AXIS) model below it
	bb.AlwaysOnTop = true
	bb.MaxDistance = 120
	bb.Parent = primary

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Name"
	nameLabel.Size = UDim2.new(1, 0, 0.55, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextScaled = true
	nameLabel.Text = entry.base
	nameLabel.TextColor3 = RarityColors.tier(entry.tier)
	nameLabel.TextStrokeTransparency = 0
	nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	nameLabel.Parent = bb

	local variantLabel = Instance.new("TextLabel")
	variantLabel.Name = "Income" -- BaseManager refreshes this line's $/s after the brainrot levels up
	variantLabel.Size = UDim2.new(1, 0, 0.45, 0)
	variantLabel.Position = UDim2.new(0, 0, 0.55, 0)
	variantLabel.BackgroundTransparency = 1
	variantLabel.Font = Enum.Font.FredokaOne
	variantLabel.TextScaled = true
	local cash = select(1, BrainrotMath.income(entry, rebirthCount))
	variantLabel.Text = ("[%s]  $%s/s"):format(entry.variant, Format.short(cash))
	variantLabel.TextColor3 = RarityColors.variant(entry.variant)
	variantLabel.TextStrokeTransparency = 0
	variantLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	variantLabel.Parent = bb
end

----------------------------------------------------------------- public
-- Returns a fully-built, anchored brainrot model (not yet parented/positioned).
-- `rebirthCount` feeds the income label via BrainrotMath (income is keyed off the
-- rebirth multipliers, not the zone), so the displayed $/s matches the payout.
function BrainrotFactory.build(entry: any, rebirthCount: number): Model
	local base = BrainrotConfig.get(entry.base)
	local scale = base and base.Scale or 1
	local color = base and base.Color or Color3.fromRGB(200, 200, 200)

	-- 1) the imported animal model (ServerStorage.BrainrotModels); else 2) a Creator Store asset
	-- id; else 3) a procedural placeholder so the game still works if a model is missing.
	local model: Model? = cloneRealModel(entry.base)
	if model then
		normalizeSize(model, scale)
	else
		local assetId = AssetConfig.brainrotAssetId(entry.base)
		if assetId then
			model = tryInsert(assetId, entry.base)
			if model then
				normalizeSize(model, scale)
			end
		end
		if not model then
			model = buildPlaceholder(entry.base, color, scale)
		end
	end

	recolorVariant(model, entry.variant) -- Gold/Diamond/Galaxy recolor (Normal keeps real textures)
	applyGlow(model, entry.variant)
	buildLabel(model, entry, rebirthCount)
	model:SetAttribute("BrainrotId", entry.id)
	return model
end

----------------------------------------------------------------- handheld (Tool)
-- Build a hand-held version of a brainrot (for a Tool the player carries in their
-- inventory/Backpack). Same recolor language + FULL podium SIZE as build() (it scales with the
-- identical normalizeSize(model, scale), so the in-hand model matches the podium display), but
-- WITHOUT the podium glow or the info billboard (a held tool shouldn't carry the floating name),
-- and with every part UNANCHORED + MASSLESS + non-colliding so it can be welded to a Tool Handle
-- and held without dragging the character around.
function BrainrotFactory.buildHandheld(entry: any): Model
	local base = BrainrotConfig.get(entry.base)
	local scale = base and base.Scale or 1
	local color = base and base.Color or Color3.fromRGB(200, 200, 200)

	-- 1) the imported animal model; else 2) a Creator Store asset; else 3) procedural placeholder.
	local model: Model? = cloneRealModel(entry.base)
	if model then
		normalizeSize(model, scale)
	else
		local assetId = AssetConfig.brainrotAssetId(entry.base)
		if assetId then
			model = tryInsert(assetId, entry.base)
			if model then
				normalizeSize(model, scale)
			end
		end
		if not model then
			model = buildPlaceholder(entry.base, color, scale)
		end
	end

	recolorVariant(model, entry.variant) -- Gold/Diamond/Galaxy recolor (Normal keeps real textures)

	-- a held tool must be free-moving: unanchor, make weightless, no collisions.
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.Massless = true
			d.CanCollide = false
		end
	end
	if not model.PrimaryPart then
		model.PrimaryPart = (model:FindFirstChild("RootPart") :: BasePart?) or model:FindFirstChildWhichIsA("BasePart", true)
	end
	model:SetAttribute("BrainrotId", entry.id)
	return model
end

BrainrotFactory.PODIUM_SIZE = PODIUM_SIZE

return BrainrotFactory
