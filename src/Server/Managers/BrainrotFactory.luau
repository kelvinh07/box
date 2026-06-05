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
local Shared = ReplicatedStorage.Shared

local BrainrotConfig = require(Shared.Config.BrainrotConfig)
local VariantConfig = require(Shared.Config.VariantConfig)
local AssetConfig = require(Shared.Config.AssetConfig)
local RarityColors = require(Shared.Config.RarityColors)
local BrainrotMath = require(Shared.Modules.BrainrotMath)
local Format = require(Shared.Modules.Format)

local BrainrotFactory = {}

local PODIUM_SIZE = Vector3.new(6, 1, 6)

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

-- Normalize any model to ~ uniform display size and center it.
local function normalizeSize(model: Model, scale: number)
	local _, size = model:GetBoundingBox()
	local maxAxis = math.max(size.X, size.Y, size.Z)
	if maxAxis <= 0 then return end
	local target = 4.5 * scale
	local factor = target / maxAxis
	if model.PrimaryPart then
		model:ScaleTo(factor)
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

	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 4
	light.Range = 14
	light.Parent = primary

	local attach = Instance.new("Attachment")
	attach.Parent = primary

	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Color = ColorSequence.new(color)
	sparkles.LightEmission = 1
	sparkles.Size = NumberSequence.new(0.6)
	sparkles.Lifetime = NumberRange.new(0.6, 1.2)
	sparkles.Rate = (variant == "Galaxy") and 30 or 12
	sparkles.Speed = NumberRange.new(1, 3)
	sparkles.SpreadAngle = Vector2.new(180, 180)
	sparkles.Texture = "rbxassetid://6334482272" -- generic spark
	sparkles.Parent = primary

	if data.Rainbow then
		-- galaxy: animate a rainbow shimmer on the body color
		task.spawn(function()
			local hue = 0
			while primary.Parent do
				hue = (hue + 0.01) % 1
				primary.Color = Color3.fromHSV(hue, 0.8, 1)
				task.wait(0.05)
			end
		end)
	end
end

----------------------------------------------------------------- label
local function buildLabel(model: Model, entry: any, zone: number)
	local primary = model.PrimaryPart
	if not primary then return end

	local bb = Instance.new("BillboardGui")
	bb.Name = "InfoLabel"
	bb.Size = UDim2.new(0, 220, 0, 64)
	bb.StudsOffset = Vector3.new(0, 4.5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 120
	bb.Parent = primary

	local nameLabel = Instance.new("TextLabel")
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
	variantLabel.Size = UDim2.new(1, 0, 0.45, 0)
	variantLabel.Position = UDim2.new(0, 0, 0.55, 0)
	variantLabel.BackgroundTransparency = 1
	variantLabel.Font = Enum.Font.FredokaOne
	variantLabel.TextScaled = true
	local cash = select(1, BrainrotMath.income(entry, zone))
	variantLabel.Text = ("[%s]  $%s/s"):format(entry.variant, Format.short(cash))
	variantLabel.TextColor3 = RarityColors.variant(entry.variant)
	variantLabel.TextStrokeTransparency = 0
	variantLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	variantLabel.Parent = bb
end

----------------------------------------------------------------- public
-- Returns a fully-built, anchored brainrot model (not yet parented/positioned).
function BrainrotFactory.build(entry: any, zone: number): Model
	local base = BrainrotConfig.get(entry.base)
	local scale = base and base.Scale or 1
	local color = base and base.Color or Color3.fromRGB(200, 200, 200)

	local model: Model? = nil
	local assetId = AssetConfig.brainrotAssetId(entry.base)
	if assetId then
		model = tryInsert(assetId, entry.base)
		if model then
			normalizeSize(model, scale)
		end
	end
	if not model then
		-- FALLBACK PLACEHOLDER — swap in a Creator Store asset id in AssetConfig.
		model = buildPlaceholder(entry.base, color, scale)
	end

	applyGlow(model, entry.variant)
	buildLabel(model, entry, zone)
	model:SetAttribute("BrainrotId", entry.id)
	return model
end

BrainrotFactory.PODIUM_SIZE = PODIUM_SIZE

return BrainrotFactory
