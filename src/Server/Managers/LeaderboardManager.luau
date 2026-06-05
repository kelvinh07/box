--!strict
-- LeaderboardManager
-- Two in-world leaderboards mounted on the zone1/2 fences:
--   LEFT  fence (ZoneFence_Left)  -> "🏆 MOST REBIRTHS"  (players by rebirth count)
--   RIGHT fence (ZoneFence_Right) -> "💎 RAREST BRAINROT" (players by their rarest
--                                     owned brainrot, with that player's live $/s)
-- Each board is a south-facing SurfaceGui sign rebuilt from the live player profiles
-- every REFRESH seconds. Income $/s uses the SAME BrainrotMath the economy pays out.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local RarityColors = require(Shared.Config.RarityColors)
local BrainrotMath = require(Shared.Modules.BrainrotMath)
local Format = require(Shared.Modules.Format)

local PlayerData = require(script.Parent.PlayerData)

local LeaderboardManager = {}

local REFRESH = 4 -- seconds between recomputes
local TOP_N = 8   -- ranks shown per board

-- "rarest" ordering: tier dominates, variant breaks ties.
local TIER_RANK = { Common = 1, Uncommon = 2, Rare = 3, Legendary = 4, Mythic = 5 }
local VARIANT_RANK = { Normal = 1, Gold = 2, Diamond = 3, Galaxy = 4 }

type Board = { rows: { TextLabel } }
local leftBoard: Board? = nil
local rightBoard: Board? = nil

----------------------------------------------------------------- board UI
-- Build a flat, upright leaderboard sign at `fence` whose Front (-Z) face points
-- SOUTH toward the players approaching the wall, so it's always readable head-on.
local function buildBoard(fence: BasePart, titleText: string, accent: Color3): Board
	-- Mount the sign FLUSH on the fence's player-facing (southward) large face, offset
	-- just OUTSIDE it and oriented to the fence, so it sits ON the fence instead of
	-- clipping INTO it. The fence's thickness axis (RightVector) is its face normal.
	local cf = fence.CFrame
	local normal = cf.RightVector
	if normal.Z > 0 then
		normal = -normal -- always face SOUTH, toward the players approaching the wall
	end
	local boardThick = 1
	local out = fence.Size.X / 2 + boardThick / 2 + 0.05
	local center = cf.Position + normal * out
	local signPos = Vector3.new(center.X, 16, center.Z)

	local sign = Instance.new("Part")
	sign.Name = "LeaderboardSign"
	sign.Anchored = true
	sign.CanCollide = false
	sign.Size = Vector3.new(40, 30, boardThick)
	sign.Color = Color3.fromRGB(16, 18, 30)
	sign.Material = Enum.Material.SmoothPlastic
	sign.CFrame = CFrame.lookAt(signPos, signPos + normal) -- Front (-Z, the SurfaceGui face) points outward
	sign.Parent = fence

	local surf = Instance.new("SurfaceGui")
	surf.Name = "Board"
	surf.Face = Enum.NormalId.Front
	surf.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surf.PixelsPerStud = 16
	surf.LightInfluence = 0
	surf.MaxDistance = 300
	surf.Parent = sign

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(16, 18, 30)
	bg.BorderSizePixel = 0
	bg.Parent = surf
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 5
	stroke.Color = accent
	stroke.Parent = bg

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -16, 0, 96)
	title.Position = UDim2.new(0, 8, 0, 8)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.TextScaled = true
	title.TextColor3 = accent
	title.TextStrokeTransparency = 0.4
	title.Text = titleText
	title.Parent = bg

	local list = Instance.new("Frame")
	list.Size = UDim2.new(1, -16, 1, -112)
	list.Position = UDim2.new(0, 8, 0, 104)
	list.BackgroundTransparency = 1
	list.Parent = bg
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local rows: { TextLabel } = {}
	for i = 1, TOP_N do
		local row = Instance.new("TextLabel")
		row.Size = UDim2.new(1, 0, 0, 54)
		row.BackgroundColor3 = Color3.fromRGB(30, 33, 50)
		row.BackgroundTransparency = 0.2
		row.BorderSizePixel = 0
		row.Font = Enum.Font.FredokaOne
		row.TextScaled = true
		row.TextColor3 = Color3.fromRGB(235, 238, 250)
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Text = ""
		row.Visible = false
		row.LayoutOrder = i
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 10)
		pad.PaddingRight = UDim.new(0, 10)
		pad.Parent = row
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = row
		row.Parent = list
		rows[i] = row
	end

	return { rows = rows }
end

local function setRow(row: TextLabel, text: string, color: Color3?)
	if text == "" then
		row.Visible = false
		return
	end
	row.Text = text
	row.TextColor3 = color or Color3.fromRGB(235, 238, 250)
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
		leftBoard = buildBoard(left, "🏆 MOST REBIRTHS", Color3.fromRGB(255, 215, 90))
	end
	if right and right:IsA("BasePart") then
		rightBoard = buildBoard(right, "💎 RAREST BRAINROT", Color3.fromRGB(120, 220, 255))
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
