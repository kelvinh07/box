--!strict
-- Collection (a POKÉDEX of every brainrot)
-- Four VARIANT tabs on the RIGHT (Normal / Gold / Diamond / Galaxy). Each tab shows ALL brainrots in
-- a grid: any you have NOT hatched in that variant render as a black SILHOUETTE (locked); the moment
-- you hatch one, the real model + its variant colors are revealed. Every cell shows the brainrot's
-- NAME and the VERSION (variant). Unlock state is read from the server snapshot's Collection.
--
-- The brainrot models are rendered in ViewportFrames via ToolVisual.mountBrainrotPreview, which clones
-- the read-only models the server exposes in ReplicatedStorage.BrainrotModels.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local RarityColors = require(Shared.Config.RarityColors)
local BrainrotConfig = require(Shared.Config.BrainrotConfig)
local VariantConfig = require(Shared.Config.VariantConfig)

local UIUtil = require(script.Parent.Parent.UIUtil)
local ClientState = require(script.Parent.Parent.ClientState)
local ToolVisual = require(script.Parent.Parent.ToolVisual)

local Collection = {}

local Z = 20
local CELL = Vector2.new(130, 152)
local TIER_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
local LOCKED_NAME = Color3.fromRGB(120, 122, 134)
local LOCKED_VER = Color3.fromRGB(90, 92, 104)

-- every brainrot, grouped by tier (sorted within tier) -> a stable dex order
local DEX: { { base: string, tier: string } } = {}
for _, tier in ipairs(TIER_ORDER) do
	for _, name in ipairs(BrainrotConfig.namesByTier(tier)) do
		table.insert(DEX, { base = name, tier = tier })
	end
end

local function newViewport(parent: Instance): ViewportFrame
	local vf = Instance.new("ViewportFrame")
	vf.BackgroundTransparency = 1
	vf.ZIndex = Z + 3
	vf.Parent = parent
	return vf
end

-- one dex cell: model preview (top) + name + version (bottom)
local function makeCell(parent: Instance, base: string, tier: string, variant: string, unlocked: boolean, order: number)
	local tierColor = RarityColors.tier(tier)
	local variantColor = RarityColors.variant(variant)

	local card = UIUtil.frame({
		Size = UDim2.new(0, CELL.X, 0, CELL.Y),
		BackgroundColor3 = unlocked and UIUtil.Colors.PanelLight or Color3.fromRGB(28, 30, 42),
		LayoutOrder = order,
		Parent = parent,
	})
	card.ZIndex = Z + 1
	UIUtil.corner(card, 12)
	UIUtil.stroke(card, unlocked and 3 or 2, unlocked and variantColor or UIUtil.Colors.Outline)

	-- a dim backdrop behind the (transparent) viewport so the cell never reads as fully empty
	local back = UIUtil.frame({
		Size = UDim2.new(1, -12, 0, 92),
		Position = UDim2.new(0, 6, 0, 6),
		BackgroundColor3 = unlocked and variantColor:Lerp(Color3.new(0, 0, 0), 0.7) or Color3.fromRGB(16, 17, 24),
		Parent = card,
	})
	back.ZIndex = Z + 2
	UIUtil.corner(back, 10)

	local vf = newViewport(card)
	vf.Size = UDim2.new(1, -12, 0, 92)
	vf.Position = UDim2.new(0, 6, 0, 6)
	ToolVisual.mountBrainrotPreview(vf, base, variant, not unlocked)

	local name = UIUtil.label({
		Size = UDim2.new(1, -8, 0, 28),
		Position = UDim2.new(0, 4, 0, 100),
		Text = base,
		TextColor3 = unlocked and tierColor or LOCKED_NAME,
		Parent = card,
	})
	name.TextWrapped = true
	name.ZIndex = Z + 4

	local ver = UIUtil.label({
		Size = UDim2.new(1, -8, 0, 22),
		Position = UDim2.new(0, 4, 0, 128),
		Text = variant,
		TextColor3 = unlocked and variantColor or LOCKED_VER,
		Parent = card,
	})
	ver.ZIndex = Z + 4
end

function Collection.build(gui: ScreenGui)
	local root = UIUtil.frame({
		Name = "CollectionPanel",
		Size = UDim2.new(0, 720, 0, 540),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = UIUtil.Colors.Panel,
		Visible = false,
		Parent = gui,
	})
	root.ZIndex = Z
	UIUtil.corner(root, 20)
	UIUtil.stroke(root, 5, UIUtil.Colors.Accent)
	UIUtil.gradient(root, UIUtil.Colors.PanelLight, UIUtil.Colors.Panel)

	local title = UIUtil.label({
		Size = UDim2.new(0, 300, 0, 48),
		Position = UDim2.new(0, 18, 0, 10),
		Text = "📕 Collection",
		TextColor3 = UIUtil.Colors.Accent,
		Parent = root,
	})
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = Z + 1

	-- "12 / 36  Gold" progress counter (right of the title, before the close button)
	local progress = UIUtil.label({
		Size = UDim2.new(0, 200, 0, 36),
		Position = UDim2.new(1, -270, 0, 16),
		Text = "",
		Parent = root,
	})
	progress.TextXAlignment = Enum.TextXAlignment.Right
	progress.ZIndex = Z + 1

	local close = UIUtil.button({
		Size = UDim2.new(0, 44, 0, 44),
		Position = UDim2.new(1, -54, 0, 10),
		BackgroundColor3 = Color3.fromRGB(220, 70, 80),
		Text = "✕",
		TextSize = 28,
		Parent = root,
	})
	close.ZIndex = Z + 1

	-- right-side VARIANT tabs
	local tabsHolder = UIUtil.frame({
		Size = UDim2.new(0, 116, 1, -76),
		Position = UDim2.new(1, -128, 0, 64),
		BackgroundTransparency = 1,
		Parent = root,
	})
	tabsHolder.ZIndex = Z + 1
	UIUtil.listLayout(tabsHolder, 10)

	-- the grid of every brainrot for the active variant
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Size = UDim2.new(1, -152, 1, -76)
	grid.Position = UDim2.new(0, 12, 0, 64)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 8
	grid.CanvasSize = UDim2.new(0, 0, 0, 0)
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.ZIndex = Z + 1
	grid.Parent = root
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, CELL.X, 0, CELL.Y)
	gridLayout.CellPadding = UDim2.new(0, 8, 0, 8)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid
	UIUtil.padding(grid, 4)

	local activeVariant = "Normal"

	-- unlocked["Gold"]["Tim Cheese"] = true, built from the snapshot's Collection
	local function unlockedSet(state: any): { [string]: { [string]: boolean } }
		local set: { [string]: { [string]: boolean } } = {}
		for _, v in ipairs(VariantConfig.Order) do
			set[v] = {}
		end
		if state and state.Collection then
			for _, e in ipairs(state.Collection) do
				local bucket = set[e.variant]
				if bucket then
					bucket[e.base] = true
				end
			end
		end
		return set
	end

	local function refresh()
		local owned = unlockedSet(ClientState.get())[activeVariant] or {}
		for _, c in ipairs(grid:GetChildren()) do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		local count = 0
		for i, d in ipairs(DEX) do
			local has = owned[d.base] == true
			if has then
				count += 1
			end
			makeCell(grid, d.base, d.tier, activeVariant, has, i)
		end
		progress.Text = ("%d / %d  %s"):format(count, #DEX, activeVariant)
	end

	-- the four variant tab buttons (each carries its variant color as a stroke accent)
	local tabButtons: { [string]: TextButton } = {}
	local setActive: (variant: string) -> ()
	for i, variant in ipairs(VariantConfig.Order) do
		local b = UIUtil.button({
			Name = variant,
			Size = UDim2.new(1, 0, 0, 58),
			BackgroundColor3 = UIUtil.Colors.PanelLight,
			Text = variant,
			TextSize = 18,
			LayoutOrder = i,
			Parent = tabsHolder,
		})
		b.ZIndex = Z + 2
		local s = b:FindFirstChildWhichIsA("UIStroke")
		if s then
			s.Color = RarityColors.variant(variant)
			s.Thickness = 3
		end
		tabButtons[variant] = b
		b.MouseButton1Click:Connect(function()
			setActive(variant)
		end)
	end

	setActive = function(variant: string)
		activeVariant = variant
		for v, b in pairs(tabButtons) do
			b.BackgroundColor3 = (v == variant) and UIUtil.Colors.Accent or UIUtil.Colors.PanelLight
		end
		refresh()
	end

	-- a signature of the UNLOCK set (which {base,variant} are owned) — rebuild only when it changes,
	-- so the constant Cash/Gem pushes never re-render 36 viewports.
	local lastSig: string? = nil
	local function unlockSig(state: any): string
		if not state or not state.Collection then
			return ""
		end
		local seen: { [string]: boolean } = {}
		for _, e in ipairs(state.Collection) do
			seen[e.base .. "|" .. tostring(e.variant)] = true
		end
		local keys = {}
		for k in pairs(seen) do
			table.insert(keys, k)
		end
		table.sort(keys)
		return table.concat(keys, ",")
	end

	ClientState.onChanged(function(state)
		local sig = unlockSig(state)
		if sig ~= lastSig then
			lastSig = sig
			if root.Visible then
				refresh()
			end
		end
	end)

	local panelEntry = UIUtil.registerPanel(function()
		root.Visible = false
	end)

	local api = {}
	api.root = root
	function api.open()
		UIUtil.closeOtherPanels(panelEntry)
		root.Visible = true
		lastSig = unlockSig(ClientState.get())
		setActive(activeVariant)
		UIUtil.pop(root)
	end
	function api.close()
		root.Visible = false
	end
	function api.toggle()
		if root.Visible then
			api.close()
		else
			api.open()
		end
	end
	function api.setVisible(v: boolean)
		if v then
			api.open()
		else
			api.close()
		end
	end
	close.MouseButton1Click:Connect(api.close)

	return api
end

return Collection
