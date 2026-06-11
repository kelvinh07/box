--!strict
-- GrassChecker
-- Overlays a SUBTLE 6x6-stud two-GREEN CHECKER on top of the STUDDED grass — WITHOUT hiding the
-- classic studs. Grass parts (tagged "GrassSurface" by the server) keep Surface.applyStuds; this
-- adds a top-face Texture whose off-diagonal cells are Palette.GrassCheckerB at partial alpha and
-- whose diagonal cells are fully transparent, so the studs read through both.
--
-- Client-side because EditableImage doesn't replicate. If EditableImage is unavailable, the grass is
-- simply the plain studded green (clean fallback).

local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)

local GrassChecker = {}

local CELL = 6        -- stud size of each checker square
local IMG = 64        -- editable-image resolution: a 2x2 grid of cells
local HALF = IMG / 2

-- one checker per tagged surface type. offTransparency = how see-through the OVERLAY (darker)
-- cells are: 0.45 = subtle (grass, studs read through).
local CHECKERS = {
	{ tag = "GrassSurface", texName = "GrassChecker", overlay = Palette.GrassCheckerB, offTransparency = 0.45 },
}

local images: { [string]: EditableImage? } = {}
local imageTried: { [string]: boolean } = {}

local function getImage(cfg): EditableImage?
	if imageTried[cfg.tag] then
		return images[cfg.tag]
	end
	imageTried[cfg.tag] = true
	local ok, img = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(IMG, IMG) })
	end)
	if not ok or not img then
		warn("[GrassChecker] EditableImage unavailable; " .. cfg.tag .. " stays plain.")
		return nil
	end
	-- [transparent, overlay / overlay, transparent]: diagonal cells let the studded BASE colour
	-- show; off-diagonal cells are the overlay colour (semi for grass, opaque for desert).
	local B = cfg.overlay
	local OVER = Enum.ImageCombineType.Overwrite
	img:DrawRectangle(Vector2.new(0, 0), Vector2.new(HALF, HALF), B, 1.0, OVER)
	img:DrawRectangle(Vector2.new(HALF, 0), Vector2.new(HALF, HALF), B, cfg.offTransparency, OVER)
	img:DrawRectangle(Vector2.new(0, HALF), Vector2.new(HALF, HALF), B, cfg.offTransparency, OVER)
	img:DrawRectangle(Vector2.new(HALF, HALF), Vector2.new(HALF, HALF), B, 1.0, OVER)
	images[cfg.tag] = img
	return img
end

local function applyTo(cfg, inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	if inst:FindFirstChild(cfg.texName) then
		return -- already done
	end
	local img = getImage(cfg)
	if not img then
		return
	end
	local tex = Instance.new("Texture")
	tex.Name = cfg.texName
	tex.Face = Enum.NormalId.Top
	-- one image == 2 cells, so a tile spanning 2*CELL studs makes each cell CELL studs.
	tex.StudsPerTileU = CELL * 2
	tex.StudsPerTileV = CELL * 2
	tex.TextureContent = Content.fromObject(img)
	tex.Parent = inst
end

function GrassChecker.start()
	for _, cfg in ipairs(CHECKERS) do
		local config = cfg
		for _, inst in ipairs(CollectionService:GetTagged(config.tag)) do
			applyTo(config, inst)
		end
		CollectionService:GetInstanceAddedSignal(config.tag):Connect(function(inst)
			applyTo(config, inst)
		end)
	end
end

return GrassChecker
