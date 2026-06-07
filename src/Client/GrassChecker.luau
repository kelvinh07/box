--!strict
-- GrassChecker
-- Overlays a 6x6-stud two-green CHECKER on top of the STUDDED grass — WITHOUT hiding the
-- classic stud texture. The grass parts keep `Surface.applyStuds` (real studs, exactly like
-- the dirt/walls/bases); this adds a top-face Texture whose dark cells are #54B312 at
-- partial alpha and whose light cells are fully transparent, so the studs read through BOTH
-- cells. Net look: studded grass with a subtle two-green checker.
--
-- Client-side because EditableImage doesn't replicate; grass parts are tagged "GrassSurface"
-- by the server (MapBuilder/BaseManager). If EditableImage is unavailable, grass is simply
-- the plain studded green (no checker) — a clean fallback.

local AssetService = game:GetService("AssetService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage.Shared.Config.Palette)

local GrassChecker = {}

local TAG = "GrassSurface"
local CELL = 6        -- stud size of each checker square (the requested 6x6)
local IMG = 64        -- editable-image resolution: a 2x2 grid of cells
local HALF = IMG / 2
local B_ALPHA = 0.45  -- dark-cell transparency: low enough to read as a 2nd green, high enough to keep studs visible

local sharedImage: EditableImage? = nil
local sharedTried = false

local function getImage(): EditableImage?
	if sharedTried then
		return sharedImage
	end
	sharedTried = true
	local ok, img = pcall(function()
		return AssetService:CreateEditableImage({ Size = Vector2.new(IMG, IMG) })
	end)
	if not ok or not img then
		warn("[GrassChecker] EditableImage unavailable; grass stays plain studded green.")
		return nil
	end
	-- [A,B / B,A]: the A cells are fully transparent (the studded base green shows), the B
	-- cells are #54B312 at partial alpha (studs still read through). Tiles into a checker.
	local B = Palette.GrassCheckerB
	local OVER = Enum.ImageCombineType.Overwrite
	img:DrawRectangle(Vector2.new(0, 0), Vector2.new(HALF, HALF), B, 1.0, OVER)
	img:DrawRectangle(Vector2.new(HALF, 0), Vector2.new(HALF, HALF), B, B_ALPHA, OVER)
	img:DrawRectangle(Vector2.new(0, HALF), Vector2.new(HALF, HALF), B, B_ALPHA, OVER)
	img:DrawRectangle(Vector2.new(HALF, HALF), Vector2.new(HALF, HALF), B, 1.0, OVER)
	sharedImage = img
	return img
end

local function applyTo(inst: Instance)
	if not inst:IsA("BasePart") then
		return
	end
	if inst:FindFirstChild("GrassChecker") then
		return -- already done
	end
	local img = getImage()
	if not img then
		return
	end
	local tex = Instance.new("Texture")
	tex.Name = "GrassChecker"
	tex.Face = Enum.NormalId.Top
	-- one image == 2 cells, so a tile spanning 2*CELL studs makes each cell CELL studs.
	tex.StudsPerTileU = CELL * 2
	tex.StudsPerTileV = CELL * 2
	tex.TextureContent = Content.fromObject(img)
	tex.Parent = inst
end

function GrassChecker.start()
	for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
		applyTo(inst)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(applyTo)
end

return GrassChecker
