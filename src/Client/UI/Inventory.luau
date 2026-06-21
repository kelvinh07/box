--!strict
-- Inventory
-- The custom inventory OVERLAY (the EXPANDED backpack view) that sits on top of the custom
-- hotbar. It browses the UNPLACED items the player owns, grouped under three filter tabs:
--   * All Items  — eggs (per rarity, with count) + every UNPLACED brainrot
--   * Eggs       — just the eggs, rarest first
--   * Brainrots  — every UNPLACED brainrot, rarest first then highest base earning first
--
-- Brainrots PLACED on a base podium are NOT tracked here (they have no Tool to carry); only
-- unplaced brainrots — the ones you can equip + place — appear.
--
-- Each item is a CARD with a transparent ViewportFrame icon (rendered via the shared ToolVisual
-- so it FILLS the card):
--   * Egg card     — a full-detail rarity-tinted PixelEgg + "{Rarity} Egg" + a count badge.
--   * Brainrot card — the brainrot's name (top), the full model render, and its SPECIFIC current
--     $/s (bottom, via BrainrotMath so it reflects level + rebirth) + Equip + Sell.
--
-- Clicking Equip EQUIPS the card's Tool so the player can carry it to an incubator / podium and
-- press E to place it. The real Tool lifecycle lives on the server (InventoryManager); this
-- panel only reflects the snapshot + requests equip/sell.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Shared = ReplicatedStorage.Shared

local EggConfig = require(Shared.Config.EggConfig)
local RarityColors = require(Shared.Config.RarityColors)
local BrainrotConfig = require(Shared.Config.BrainrotConfig)
local BrainrotMath = require(Shared.Modules.BrainrotMath)
local Format = require(Shared.Modules.Format)

local UIUtil = require(script.Parent.Parent.UIUtil)
local ClientState = require(script.Parent.Parent.ClientState)
local ClientNet = require(script.Parent.Parent.ClientNet)
local ToolVisual = require(script.Parent.Parent.ToolVisual)
local InventoryOrder = require(script.Parent.Parent.InventoryOrder)
local Sounds = require(script.Parent.Parent.Sounds)

local player = Players.LocalPlayer

local Inventory = {}

local Z = 30 -- above the modals (20) so the overlay always wins

-- wire a GuiObject as an inventory drop-target (sets the shared hover while the cursor is over it,
-- so a dragged tool released here moves into the inventory overflow)
local function invHover(obj: GuiObject)
	obj.MouseEnter:Connect(function()
		InventoryOrder.setHover(obj, "inventory", nil)
	end)
	obj.MouseLeave:Connect(function()
		InventoryOrder.clearHover(obj)
	end)
end

local function entryById(state: any, id: string): any?
	for _, e in ipairs(state.Collection or {}) do
		if e.id == id then
			return e
		end
	end
	return nil
end

-- the default Roblox "open backpack/inventory" key (grave / backtick) toggles this overlay too,
-- so muscle memory works. One-line change if Roblox ever moves the bind.
local INVENTORY_KEY = Enum.KeyCode.Backquote

-- viewport rendering lives in the shared ToolVisual module (full-detail egg + tightly-framed
-- brainrot model) so the hotbar + this overlay never duplicate the bounds/camera maths.
local renderEgg = ToolVisual.renderEgg
local mountBrainrot = ToolVisual.mountBrainrot

----------------------------------------------------------------- card builders
local CELL = Vector2.new(140, 178)

local function newViewport(parent: Instance): ViewportFrame
	local vf = Instance.new("ViewportFrame")
	vf.BackgroundTransparency = 1 -- transparent icon
	vf.Ambient = Color3.fromRGB(210, 210, 210)
	vf.LightColor = Color3.fromRGB(255, 255, 255)
	vf.LightDirection = Vector3.new(-0.4, -1, -0.3)
	vf.ZIndex = Z + 2
	vf.Parent = parent
	return vf
end

local function baseCard(parent: Instance, order: number, borderColor: Color3): Frame
	local card = UIUtil.frame({
		Size = UDim2.new(0, CELL.X, 0, CELL.Y),
		BackgroundColor3 = UIUtil.Colors.PanelLight,
		LayoutOrder = order,
		Parent = parent,
	})
	card.ZIndex = Z + 1
	UIUtil.corner(card, 12)
	UIUtil.stroke(card, 3, borderColor)
	return card
end

local function makeEggCard(parent: Instance, tool: Tool, rarity: string, count: number, order: number, onEquip: () -> ())
	local card = baseCard(parent, order, RarityColors.tier(rarity))

	local vf = newViewport(card)
	vf.Size = UDim2.new(1, -12, 0, 110)
	vf.Position = UDim2.new(0, 6, 0, 8)
	renderEgg(vf, rarity)

	local name = UIUtil.label({
		Size = UDim2.new(1, -8, 0, 44),
		Position = UDim2.new(0, 4, 1, -52),
		Text = ("%s Egg"):format(rarity),
		TextColor3 = RarityColors.tier(rarity),
		Parent = card,
	})
	name.ZIndex = Z + 2

	-- count badge (top-right)
	local badge = UIUtil.label({
		Size = UDim2.new(0, 40, 0, 26),
		Position = UDim2.new(1, -42, 0, 4),
		Text = ("x%d"):format(count),
		Parent = card,
	})
	badge.ZIndex = Z + 3

	-- whole card: click equips the egg tool; press-and-drag moves it to the hotbar
	local btn = Instance.new("TextButton")
	btn.BackgroundTransparency = 1
	btn.Text = ""
	btn.Size = UDim2.new(1, 0, 1, 0)
	btn.ZIndex = Z + 4
	btn.Parent = card
	btn.MouseButton1Click:Connect(onEquip)
	btn.MouseButton1Down:Connect(function()
		InventoryOrder.armDrag(tool)
	end)
	invHover(btn)
end

local function makeBrainrotCard(parent: Instance, tool: Tool, entry: any, rebirths: number, order: number, onEquip: () -> ())
	local variantColor = RarityColors.variant(entry.variant)
	local card = baseCard(parent, order, variantColor)

	-- full-card drag handle (Z+2, BELOW the Equip/Sell buttons which sit at Z+3): press-and-drag to
	-- move the brainrot to the hotbar; a plain click equips it. Equip/Sell win their own clicks.
	local drag = Instance.new("TextButton")
	drag.Name = "Drag"
	drag.BackgroundTransparency = 1
	drag.Text = ""
	drag.Size = UDim2.new(1, 0, 1, 0)
	drag.ZIndex = Z + 2
	drag.Parent = card
	drag.MouseButton1Down:Connect(function()
		InventoryOrder.armDrag(tool)
	end)
	drag.MouseButton1Click:Connect(onEquip)
	invHover(drag)

	local name = UIUtil.label({
		Size = UDim2.new(1, -8, 0, 22),
		Position = UDim2.new(0, 4, 0, 3),
		Text = entry.base,
		TextColor3 = RarityColors.tier(entry.tier),
		Parent = card,
	})
	name.ZIndex = Z + 2

	-- current level, shown right below the name
	local levelLabel = UIUtil.label({
		Size = UDim2.new(1, -8, 0, 16),
		Position = UDim2.new(0, 4, 0, 25),
		Text = ("Lv %d"):format(entry.level or 1),
		TextColor3 = Color3.fromRGB(255, 235, 130),
		Parent = card,
	})
	levelLabel.ZIndex = Z + 2

	-- a variant-colored swatch sits UNDER the viewport so the card is never blank while the model
	-- replicates in; it's hidden the moment the real model renders (the viewport gets a Camera).
	local swatch = UIUtil.frame({
		Size = UDim2.new(0, 60, 0, 60),
		Position = UDim2.new(0.5, 0, 0, 46),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = (BrainrotConfig.get(entry.base) and BrainrotConfig.get(entry.base).Color) or variantColor,
		Parent = card,
	})
	swatch.ZIndex = Z + 1
	UIUtil.corner(swatch, 30)
	UIUtil.stroke(swatch, 3, variantColor)

	local vf = newViewport(card)
	vf.Size = UDim2.new(1, -16, 0, 80)
	vf.Position = UDim2.new(0, 8, 0, 44)
	-- mountBrainrot renders now AND retries into this same viewport until the model replicates.
	mountBrainrot(vf, entry.id)
	-- hide the placeholder once a real render lands (renderBrainrotById parents a Camera on success)
	vf.ChildAdded:Connect(function(c)
		if c:IsA("Camera") then
			swatch.Visible = false
		end
	end)
	if vf:FindFirstChildOfClass("Camera") then
		swatch.Visible = false
	end

	local cash = select(1, BrainrotMath.income(entry, rebirths))
	local sub = UIUtil.label({
		Size = UDim2.new(1, -8, 0, 24),
		Position = UDim2.new(0, 4, 0, 126),
		Text = ("$%s/s"):format(Format.short(cash)),
		TextColor3 = RarityColors.Cash,
		Parent = card,
	})
	sub.ZIndex = Z + 2

	-- only UNPLACED brainrots reach this card (placed ones are filtered out upstream), so Equip
	-- is always available — it equips the Tool so the player can carry + place it.
	local equip = UIUtil.button({
		Size = UDim2.new(0, 64, 0, 22),
		Position = UDim2.new(0, 6, 0, 150),
		BackgroundColor3 = UIUtil.Colors.Gem,
		Text = "Equip",
		TextSize = 16,
		Parent = card,
	})
	equip.ZIndex = Z + 3
	equip.MouseButton1Click:Connect(onEquip)
	invHover(equip)

	local sell = UIUtil.button({
		Size = UDim2.new(0, 58, 0, 22),
		Position = UDim2.new(1, -64, 0, 150),
		BackgroundColor3 = Color3.fromRGB(220, 90, 90),
		Text = "Sell",
		TextSize = 16,
		Parent = card,
	})
	sell.ZIndex = Z + 3
	sell.MouseButton1Click:Connect(function()
		local r = ClientNet.invoke("SellBrainrot", entry.id)
		if r and r.ok then
			Sounds.play("Purchase", 0.8)
		end
	end)
	invHover(sell)
end

----------------------------------------------------------------- panel
function Inventory.build(gui: ScreenGui)
	local root = UIUtil.frame({
		Name = "InventoryPanel",
		Size = UDim2.new(0, 690, 0, 500),
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
		Size = UDim2.new(0, 280, 0, 48),
		Position = UDim2.new(0, 18, 0, 10),
		Text = "Inventory",
		TextColor3 = UIUtil.Colors.Accent,
		Parent = root,
	})
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = Z + 1

	local close = UIUtil.button({
		Size = UDim2.new(0, 44, 0, 44),
		Position = UDim2.new(1, -54, 0, 10),
		BackgroundColor3 = Color3.fromRGB(220, 70, 80),
		Text = "✕",
		TextSize = 28,
		Parent = root,
	})
	close.ZIndex = Z + 1

	-- search box
	local search = Instance.new("TextBox")
	search.Size = UDim2.new(0, 220, 0, 36)
	search.Position = UDim2.new(1, -290, 0, 14)
	search.BackgroundColor3 = UIUtil.Colors.PanelLight
	search.TextColor3 = UIUtil.Colors.Text
	search.PlaceholderText = "Search..."
	search.Text = ""
	search.Font = UIUtil.Font
	search.TextScaled = true
	search.ClearTextOnFocus = false
	search.ZIndex = Z + 1
	search.Parent = root
	UIUtil.corner(search, 10)
	UIUtil.stroke(search, 2)

	-- "Equip Best" (top bar): asks the server to auto-place the best brainrots (by level-1 rate)
	-- onto the base podiums, returning the rest to the inventory.
	local equipBest = UIUtil.button({
		Name = "EquipBest",
		Size = UDim2.new(0, 150, 0, 40),
		Position = UDim2.new(0, 210, 0, 12),
		BackgroundColor3 = UIUtil.Colors.Good,
		Text = "⭐ Equip Best",
		TextSize = 18,
		Parent = root,
	})
	equipBest.ZIndex = Z + 2
	equipBest.MouseButton1Click:Connect(function()
		local r = ClientNet.invoke("EquipBest")
		if r and r.ok then
			Sounds.play("Purchase", 1.0)
		end
	end)

	-- left filter tabs
	local tabsHolder = UIUtil.frame({
		Size = UDim2.new(0, 120, 1, -76),
		Position = UDim2.new(0, 12, 0, 64),
		BackgroundTransparency = 1,
		Parent = root,
	})
	tabsHolder.ZIndex = Z + 1
	local tabLayout = UIUtil.listLayout(tabsHolder, 8)
	tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	-- grid scroll
	local grid = Instance.new("ScrollingFrame")
	grid.Name = "Grid"
	grid.Size = UDim2.new(1, -156, 1, -76)
	grid.Position = UDim2.new(0, 144, 0, 64)
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 8
	grid.CanvasSize = UDim2.new(0, 0, 0, 0)
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.ZIndex = Z + 1
	grid.Parent = root
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, CELL.X, 0, CELL.Y)
	gridLayout.CellPadding = UDim2.new(0, 10, 0, 10)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = grid
	UIUtil.padding(grid, 4)
	invHover(grid) -- dropping a dragged tool onto empty grid space moves it into the inventory

	local activeFilter = "All"
	local searchText = ""

	-- build the 3 tab buttons; the active one is highlighted
	local tabButtons: { [string]: TextButton } = {}
	local function setActive(filter: string) end -- fwd decl assigned below
	for i, def in ipairs({
		{ key = "All", text = "All Items" },
		{ key = "Eggs", text = "Eggs" },
		{ key = "Brainrots", text = "Brainrots" },
	}) do
		local b = UIUtil.button({
			Name = def.key,
			Size = UDim2.new(1, 0, 0, 46),
			BackgroundColor3 = UIUtil.Colors.PanelLight,
			Text = def.text,
			TextSize = 18,
			LayoutOrder = i,
			Parent = tabsHolder,
		})
		b.ZIndex = Z + 2
		tabButtons[def.key] = b
		b.MouseButton1Click:Connect(function()
			setActive(def.key)
		end)
	end

	-- empty-state label (parented to root, NOT the grid, so the grid layout doesn't size it)
	local empty = UIUtil.label({
		Size = UDim2.new(1, -176, 0, 60),
		Position = UDim2.new(0, 144, 0.45, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Text = "",
		Visible = false,
		Parent = root,
	})
	empty.ZIndex = Z + 2

	local function matches(text: string): boolean
		if searchText == "" then
			return true
		end
		return string.find(string.lower(text), searchText, 1, true) ~= nil
	end

	-- a cheap signature of the INVENTORY CONTENTS (egg counts + each brainrot's id/placed/level/
	-- variant + rebirths-for-income). Used to skip rebuilds when only Cash/Gems changed.
	local lastSig: string? = nil
	local function contentSig(state: any): string
		if not state then
			return ""
		end
		local parts = {}
		for _, r in ipairs(EggConfig.Order) do
			parts[#parts + 1] = tostring((state.Eggs and state.Eggs[r]) or 0)
		end
		for _, e in ipairs(state.Collection or {}) do
			parts[#parts + 1] = table.concat({ e.id, tostring(e.placed), tostring(e.level), tostring(e.variant) }, ":")
		end
		parts[#parts + 1] = "rb" .. tostring(state.Rebirths or 0)
		return table.concat(parts, "|")
	end

	local function refresh()
		local state = ClientState.get()
		lastSig = contentSig(state)
		-- clear old cards
		for _, c in ipairs(grid:GetChildren()) do
			if c:IsA("Frame") or c:IsA("ViewportFrame") then
				c:Destroy()
			end
		end
		empty.Visible = false
		if not state then
			return
		end

		-- show the OVERFLOW only: order[HOTBAR_SLOTS+1 ..]. The hotbar shows the first slots, so an
		-- item is in the hotbar OR here, never both (mirrors the default backpack). Acquisition/slot
		-- order — no rarity sort — so it matches the hotbar fill order + survives drag reordering.
		local function equipTool(tool: Tool)
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum then
				hum:EquipTool(tool)
			end
		end

		local items = InventoryOrder.getInventory()
		local pos = 0
		for _, tool in ipairs(items) do
			local kind = tool:GetAttribute("Kind")
			if kind == "Egg" and (activeFilter == "All" or activeFilter == "Eggs") then
				local rarity = tostring(tool:GetAttribute("Rarity") or "Common")
				if matches(rarity .. " Egg") then
					pos += 1
					makeEggCard(grid, tool, rarity, (state.Eggs and state.Eggs[rarity]) or 0, pos, function()
						equipTool(tool)
					end)
				end
			elseif kind == "Brainrot" and (activeFilter == "All" or activeFilter == "Brainrots") then
				local entry = entryById(state, tostring(tool:GetAttribute("BrainrotId")))
				if entry and matches(entry.base) then
					pos += 1
					makeBrainrotCard(grid, tool, entry, state.Rebirths or 0, pos, function()
						equipTool(tool)
					end)
				end
			end
		end

		if pos == 0 then
			empty.Text = (activeFilter == "Eggs") and "No eggs in your backpack"
				or (activeFilter == "Brainrots") and "No brainrots in your backpack"
				or "Backpack empty — the hotbar holds your items"
			empty.Visible = true
		end
	end

	-- assign the real setActive now that refresh exists
	setActive = function(filter: string)
		activeFilter = filter
		for key, b in pairs(tabButtons) do
			b.BackgroundColor3 = (key == filter) and UIUtil.Colors.Accent or UIUtil.Colors.PanelLight
		end
		title.Text = (filter == "Eggs") and "Eggs" or (filter == "Brainrots") and "Brainrots" or "All Items"
		refresh()
	end

	search:GetPropertyChangedSignal("Text"):Connect(function()
		searchText = string.lower(search.Text)
		if root.Visible then
			refresh()
		end
	end)

	-- only re-render while the panel is open AND the inventory contents actually changed
	-- (ViewportFrames are not free; Cash/Gem pushes happen constantly and must not flicker it)
	ClientState.onChanged(function(state)
		if root.Visible and contentSig(state) ~= lastSig then
			refresh()
		end
	end)

	-- the hotbar/inventory split (and drag reorders) change which tools overflow here — rebuild then
	InventoryOrder.onChanged(function()
		if root.Visible then
			refresh()
		end
	end)

	-- mutually-exclusive popup
	local panelEntry = UIUtil.registerPanel(function()
		root.Visible = false
	end)

	local api = {}
	api.root = root
	function api.open(filter: string?)
		UIUtil.closeOtherPanels(panelEntry)
		root.Visible = true
		setActive(filter or "All")
		UIUtil.pop(root)
	end
	function api.close()
		root.Visible = false
	end
	function api.toggle(filter: string?)
		if root.Visible then
			root.Visible = false
		else
			api.open(filter)
		end
	end
	close.MouseButton1Click:Connect(api.close)

	-- the 🎒 backpack icon button (middle-left) opens the overlay on All Items. Matches the
	-- old Backpack button's look/position so the rest of the left column is unchanged.
	local btn = UIUtil.button({
		Name = "BackpackButton",
		Size = UDim2.new(0, 64, 0, 64),
		Position = UDim2.new(0, 16, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Text = "",
		Parent = gui,
	})
	local stroke = btn:FindFirstChildWhichIsA("UIStroke")
	if stroke then
		stroke.Enabled = false
	end
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Image = "rbxassetid://79259744487571"
	icon.Size = UDim2.new(1, 40, 1, 40)
	icon.Position = UDim2.new(0.5, 0, 0.5, 0)
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = btn.ZIndex + 1
	icon.Parent = btn
	btn.MouseButton1Click:Connect(function()
		api.toggle("All")
	end)

	-- the default Roblox backpack keybind (Backquote) toggles the overlay too. Ignore the input
	-- when gameProcessedEvent is set so it never fires while typing in the search box / chat.
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		if input.KeyCode == INVENTORY_KEY then
			api.toggle("All")
		end
	end)

	return api
end

return Inventory
