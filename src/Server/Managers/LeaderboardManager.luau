--!strict
-- LeaderboardManager
-- Two in-world leaderboards near the zone1/2 fences, each a BIG 3D STONE TOMBSTONE
-- statue (rectangular slab + rounded top, studded stone) with the rankings ENGRAVED into
-- its face in the "Ghostbum" font (no flat screen panel — text sits directly on the stone):
--   LEFT  tomb (by ZoneFence_Left)  -> "🏆 MOST REBIRTHS"  (players by rebirth count)
--   RIGHT tomb (by ZoneFence_Right) -> "💎 RAREST BRAINROT" (players by their rarest owned
--                                       brainrot, with that player's live $/s)
-- Rebuilt from the live player profiles every REFRESH seconds. $/s uses the SAME
-- BrainrotMath the economy pays out.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local RarityColors = require(Shared.Config.RarityColors)
local Palette = require(Shared.Config.Palette)
local BrainrotMath = require(Shared.Modules.BrainrotMath)
local Format = require(Shared.Modules.Format)
local Surface = require(Shared.Modules.Surface)

local PlayerData = require(script.Parent.PlayerData)

local LeaderboardManager = {}

local REFRESH = 4 -- seconds between recomputes
local TOP_N = 6   -- ranks engraved per tomb

-- the leaderboard font (new FontFace system; not in the legacy Enum.Font)
local GHOST_FONT = Font.fromName("Ghostbum")
-- engraved-text colours: dark carved letters with a faint light edge so they read as
-- chiselled INTO the stone rather than printed on a screen.
local ENGRAVE = Color3.fromRGB(34, 36, 46)
local ENGRAVE_EDGE = Color3.fromRGB(196, 202, 216)

-- "rarest" ordering: tier dominates, variant breaks ties.
local TIER_RANK = { Common = 1, Uncommon = 2, Rare = 3, Legendary = 4, Mythic = 5 }
local VARIANT_RANK = { Normal = 1, Gold = 2, Diamond = 3, Galaxy = 4 }

type Board = { rows: { TextLabel } }
local leftBoard: Board? = nil
local rightBoard: Board? = nil

----------------------------------------------------------------- tombstone build
-- Build a big 3D STONE TOMBSTONE in front of `fence`, facing the players approaching the
-- wall, with the rankings engraved into its front face in the Ghostbum font.
local function buildTombstone(fence: BasePart, titleText: string, accent: Color3): Board
	local cf = fence.CFrame
	local normal = cf.RightVector
	if normal.Z > 0 then
		normal = -normal -- always face SOUTH, toward the players approaching the wall
	end

	local bodyW, bodyH, depth = 19, 23, 2.5 -- half size
	local groundY = 1
	-- stand it on the ground just in FRONT (south) of the fence
	local frontOut = fence.Size.X / 2 + depth / 2 + 1
	local base = cf.Position + normal * frontOut
	local bodyCenterY = groundY + bodyH / 2
	local bodyPos = Vector3.new(base.X, bodyCenterY, base.Z)
	local faceCF = CFrame.lookAt(bodyPos, bodyPos + normal) -- Front (-Z) faces the players

	local tomb = Instance.new("Model")
	tomb.Name = "LeaderboardTomb"

	-- rectangular slab body
	local body = Instance.new("Part")
	body.Name = "TombBody"
	body.Anchored = true
	body.CanCollide = true
	body.Material = Enum.Material.SmoothPlastic
	body.Color = Palette.Stone
	body.Size = Vector3.new(bodyW, bodyH, depth)
	body.CFrame = faceCF
	body.Parent = tomb
	Surface.applyStuds(body)

	-- rounded top: a cylinder whose round face is parallel to the body front (sits on the
	-- slab top so its upper half forms the classic headstone dome).
	local top = Instance.new("Part")
	top.Name = "TombTop"
	top.Anchored = true
	top.CanCollide = true
	top.Shape = Enum.PartType.Cylinder
	top.Material = Enum.Material.SmoothPlastic
	top.Color = Palette.Stone
	top.Size = Vector3.new(depth, bodyW, bodyW) -- length = depth, diameter = width
	top.CFrame = faceCF * CFrame.new(0, bodyH / 2, 0) * CFrame.Angles(0, math.rad(90), 0)
	top.Parent = tomb
	Surface.applyStuds(top)

	-- a small plinth at the base
	local plinth = Instance.new("Part")
	plinth.Name = "TombBase"
	plinth.Anchored = true
	plinth.CanCollide = true
	plinth.Material = Enum.Material.SmoothPlastic
	plinth.Color = Palette.BaseTrim
	plinth.Size = Vector3.new(bodyW + 3, 1.5, depth + 2.5)
	plinth.CFrame = faceCF * CFrame.new(0, -bodyH / 2 + 0.75, 0)
	plinth.Parent = tomb
	Surface.applyStuds(plinth)

	-- engraved face: a SurfaceGui with NO opaque background (text sits on the stone)
	local surf = Instance.new("SurfaceGui")
	surf.Name = "Engraving"
	surf.Face = Enum.NormalId.Front
	-- doubled (vs the 18 used at full size) so the engraving keeps the same pixel canvas
	-- resolution on the now half-size stone -- the text layout fits unchanged.
	surf.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surf.PixelsPerStud = 36
	surf.LightInfluence = 0
	surf.MaxDistance = 300
	surf.Parent = body

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -20, 0, 96)
	title.Position = UDim2.new(0, 10, 0, 10)
	title.BackgroundTransparency = 1
	title.FontFace = GHOST_FONT
	title.TextScaled = true
	title.TextColor3 = accent
	title.TextStrokeColor3 = ENGRAVE
	title.TextStrokeTransparency = 0.2
	title.Text = titleText
	title.Parent = surf

	local list = Instance.new("Frame")
	list.Size = UDim2.new(1, -24, 1, -120)
	list.Position = UDim2.new(0, 12, 0, 110)
	list.BackgroundTransparency = 1
	list.Parent = surf
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local rows: { TextLabel } = {}
	for i = 1, TOP_N do
		local row = Instance.new("TextLabel")
		row.Size = UDim2.new(1, 0, 0, 70)
		row.BackgroundTransparency = 1 -- engraved into the stone, not a panel
		row.FontFace = GHOST_FONT
		row.TextScaled = true
		row.TextColor3 = ENGRAVE
		row.TextStrokeColor3 = ENGRAVE_EDGE
		row.TextStrokeTransparency = 0.4
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Text = ""
		row.Visible = false
		row.LayoutOrder = i
		row.Parent = list
		rows[i] = row
	end

	tomb.Parent = fence
	return { rows = rows }
end

local function setRow(row: TextLabel, text: string, color: Color3?)
	if text == "" then
		row.Visible = false
		return
	end
	row.Text = text
	row.TextColor3 = color or ENGRAVE
	-- variant-coloured (painted) engravings get a dark edge; default dark engravings a light edge
	row.TextStrokeColor3 = color and ENGRAVE or ENGRAVE_EDGE
	row.Visible = true
end

----------------------------------------------------------------- data
-- the player's rarest owned brainrot (entry) + its numeric rank (-1 if none)
local function rarestOf(collection: { any }): (any?, number)
	local best, bestRank = nil, -1
	for _, e in ipairs(collection) do
		local r = (TIER_RANK[e.tier] or 0) * 10 + (VARIANT_RANK[e.variant] or 0)
		if r > bestRank then
			bestRank = r
			best = e
		end
	end
	return best, bestRank
end

local function incomePerSec(profile: any): number
	local total = 0
	for _, e in ipairs(profile.Collection) do
		local cash = BrainrotMath.income(e, profile.Rebirths)
		total += cash
	end
	return total
end

local function refresh()
	local data: { any } = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local p = PlayerData.get(plr)
		if p then
			local best, rank = rarestOf(p.Collection)
			table.insert(data, {
				name = plr.DisplayName,
				rebirths = p.Rebirths or 0,
				best = best,
				rank = rank,
				ips = incomePerSec(p),
			})
		end
	end

	-- LEFT: most rebirths
	if leftBoard then
		local arr = table.clone(data)
		table.sort(arr, function(a, b)
			return a.rebirths > b.rebirths
		end)
		for i, row in ipairs(leftBoard.rows) do
			local d = arr[i]
			if d then
				setRow(row, ("%d.  %s    %d 🔄"):format(i, d.name, d.rebirths))
			else
				setRow(row, "")
			end
		end
	end

	-- RIGHT: rarest brainrot (ties broken by income), shown with that player's $/s
	if rightBoard then
		local arr = table.clone(data)
		table.sort(arr, function(a, b)
			if a.rank ~= b.rank then
				return a.rank > b.rank
			end
			return a.ips > b.ips
		end)
		for i, row in ipairs(rightBoard.rows) do
			local d = arr[i]
			if d and d.best then
				setRow(
					row,
					("%d.  %s   %s %s   $%s/s"):format(i, d.name, d.best.variant, d.best.tier, Format.short(d.ips)),
					RarityColors.variant(d.best.variant)
				)
			elseif d then
				setRow(row, ("%d.  %s   (no brainrots)"):format(i, d.name))
			else
				setRow(row, "")
			end
		end
	end
end

----------------------------------------------------------------- init
function LeaderboardManager.init()
	local lane = Workspace:WaitForChild("DigLane", 15)
	if not lane then
		warn("[LeaderboardManager] DigLane folder not found; boards not built.")
		return
	end
	local left = lane:WaitForChild("ZoneFence_Left", 10)
	local right = lane:WaitForChild("ZoneFence_Right", 10)
	if left and left:IsA("BasePart") then
		leftBoard = buildTombstone(left, "🏆 MOST REBIRTHS", Color3.fromRGB(255, 215, 90))
	end
	if right and right:IsA("BasePart") then
		rightBoard = buildTombstone(right, "💎 RAREST BRAINROT", Color3.fromRGB(120, 220, 255))
	end

	task.spawn(function()
		while true do
			local ok, err = pcall(refresh)
			if not ok then
				warn("[LeaderboardManager] refresh failed: " .. tostring(err))
			end
			task.wait(REFRESH)
		end
	end)
end

return LeaderboardManager
