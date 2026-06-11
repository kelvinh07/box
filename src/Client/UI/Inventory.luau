--!strict
-- Inventory
-- The custom inventory OVERLAY that sits on top of the Roblox toolbar/Backpack. It browses
-- everything the player owns, grouped under three filter tabs:
--   * All Items  — eggs (per rarity, with count) + every owned brainrot
--   * Eggs       — just the eggs, rarest first
--   * Brainrots  — every owned brainrot, rarest first then highest base earning first
--
-- Each item is a CARD with a transparent ViewportFrame icon:
--   * Egg card     — a rarity-tinted PixelEgg + "{Rarity} Egg" + a count badge.
--   * Brainrot card — the brainrot's name (top), a render of the model, and its SPECIFIC
--     current $/s (bottom, via BrainrotMath so it reflects level + rebirth). A "PLACED" tag
--     marks brainrots currently on a podium; a small Sell button is always available.
--
-- Clicking a card EQUIPS its Tool (egg, or an UNPLACED brainrot) so the player can carry it to
-- an incubator / podium and press E to place it. Placed brainrots have no Tool, so clicking
-- them just previews (you remove them by interacting with the podium in-world).
--
-- The real Tool lifecycle lives on the server (InventoryManager); this panel only reflects the
-- snapshot + requests equip/sell.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local EggConfig = require(Shared.Config.EggConfig)
local RarityColors = require(Shared.Config.RarityColors)
local BrainrotConfig = require(Shared.Config.BrainrotConfig)
local VariantConfig = require(Shared.Config.VariantConfig)
local BrainrotMath = require(Shared.Modules.BrainrotMath)
local PixelEgg = require(Shared.Modules.PixelEgg)
local Format = require(Shared.Modules.Format)

local UIUtil = require(script.Parent.Parent.UIUtil)
local ClientState = require(script.Parent.Parent.ClientState)
local ClientNet = require(script.Parent.Parent.ClientNet)
local Sounds = require(script.Parent.Parent.Sounds)

local player = Players.LocalPlayer

local Inventory = {}

-- highest -> lowest rarity (drives both the egg order and brainrot tie-break grouping)
local TIER_RANK = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6 }

local Z = 30 -- above the modals (20) so the overlay always wins

----------------------------------------------------------------- viewport helpers
-- world-space (center, size) of an instance's VISIBLE BaseParts
local function computeBounds(inst: Instance): (Vector3, Vector3)
	local minv: Vector3?, maxv: Vector3? = nil, nil
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
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
		return Vector3.zero, Vector3.one
	end
	return (minv + maxv) / 2, (maxv - minv)
end

-- Mount a built model into a transparent ViewportFrame + frame a camera on it. Strips
-- labels/lights/particles so only the geometry renders.
local function frameViewport(vf: ViewportFrame, holder: Model)
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

	local center, size = computeBounds(holder)
	local cam = Instance.new("Camera")
	cam.Parent = vf
	vf.CurrentCamera = cam
	local span = math.max(size.X, size.Y, size.Z)
	if span <= 0 then span = 6 end
	local dist = span * 1.7
	cam.CFrame = CFrame.lookAt(center + Vector3.new(dist * 0.35, dist * 0.3, dist), center)
end

-- Find a replicated model for a brainrot id: its inventory Tool (Backpack/Character) or its
-- placed podium model in Workspace. Returns nil if none is replicated yet.
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

-- Build a brainrot ViewportFrame icon. Returns false if no source model is replicated (caller
-- shows a colored swatch fallback instead).
local function renderBrainrot(vf: ViewportFrame, id: string): boolean
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
	frameViewport(vf, holder)
	return true
end

local function renderEgg(vf: ViewportFrame, rarity: string)
	local holder = Instance.new("Model")
	local egg = PixelEgg.build(Vector3.zero, 4, RarityColors.tier(rarity), 6)
	egg.Parent = holder
	frameViewport(vf, holder)
end

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

local function makeEggCard(parent: Instance, rarity: string, count: number, order: number, onEquip: () -> ())
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

	-- whole card is the click target (equip the egg tool)
	local btn = Instance.new("TextButton")
	btn.BackgroundTransparency = 1
	btn.Text = ""
	btn.Size = UDim2.new(1, 0, 1, 0)
	btn.ZIndex = Z + 4
	btn.Parent = card
	btn.MouseButton1Click:Connect(onEquip)
end

local function makeBrainrotCard(parent: Instance, entry: any, rebirths: number, order: number, onEquip: () -> ())
	local variantColor = RarityColors.variant(entry.variant)
	local card = baseCard(parent, order, variantColor)

	local name = UIUtil.label({
		Size = UDim2.new(1, -8, 0, 26),
		Position = UDim2.new(0, 4, 0, 4),
		Text = entry.base,
		TextColor3 = RarityColors.tier(entry.tier),
		Parent = card,
	})
	name.ZIndex = Z + 2

	local vf = newViewport(card)
	vf.Size = UDim2.new(1, -16, 0, 92)
	vf.Position = UDim2.new(0, 8, 0, 32)
	if not renderBrainrot(vf, entry.id) then
		-- fallback: a variant-colored swatch if the model isn't replicated yet
		vf:Destroy()
		local swatch = UIUtil.frame({
			Size = UDim2.new(0, 70, 0, 70),
			Position = UDim2.new(0.5, 0, 0, 36),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = (BrainrotConfig.get(entry.base) and BrainrotConfig.get(entry.base).Color) or variantColor,
			Parent = card,
		})
		swatch.ZIndex = Z + 2
		UIUtil.corner(swatch, 35)
		UIUtil.stroke(swatch, 3, variantColor)
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

	if entry.placed then
		local tag = UIUtil.label({
			Size = UDim2.new(0, 64, 0, 20),
			Position = UDim2.new(0.5, 0, 0, 150),
			AnchorPoint = Vector2.new(0.5, 0),
			Text = "PLACED",
			TextColor3 = UIUtil.Colors.Good,
			Parent = card,
		})
		tag.ZIndex = Z + 3
	else
		-- click-to-equip is only for UNPLACED brainrots (placed ones have no Tool)
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
	end

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
end

----------------------------------------------------------------- equip helper
local function equipBy(predicate: (Tool) -> boolean)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not hum then
		return
	end
	local function find(container: Instance?): Tool?
		if not container then
			return nil
		end
		for _, c in ipairs(container:GetChildren()) do
			if c:IsA("Tool") and predicate(c) then
				return c
			end
		end
		return nil
	end
	local tool = find(player:FindFirstChild("Backpack")) or find(char)
	if tool then
		hum:EquipTool(tool)
	end
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

		local order = 0
		local any = false

		-- EGGS: rarest -> least (EggConfig.Order is low->high, so iterate in reverse)
		if activeFilter == "All" or activeFilter == "Eggs" then
			for i = #EggConfig.Order, 1, -1 do
				local rarity = EggConfig.Order[i]
				local count = (state.Eggs and state.Eggs[rarity]) or 0
				if count > 0 and matches(rarity .. " Egg") then
					order += 1
					any = true
					makeEggCard(grid, rarity, count, order, function()
						equipBy(function(t)
							return t:GetAttribute("Kind") == "Egg" and t:GetAttribute("Rarity") == rarity
						end)
					end)
				end
			end
		end

		-- BRAINROTS: tier DESC, then base earning (tierCash * variant.CashMult) DESC
		if activeFilter == "All" or activeFilter == "Brainrots" then
			local list = {}
			for _, e in ipairs(state.Collection or {}) do
				if matches(e.base) then
					table.insert(list, e)
				end
			end
			table.sort(list, function(a, b)
				local ra, rb = TIER_RANK[a.tier] or 0, TIER_RANK[b.tier] or 0
				if ra ~= rb then
					return ra > rb
				end
				local tierCashA = select(1, BrainrotConfig.tierIncome(a.tier))
				local tierCashB = select(1, BrainrotConfig.tierIncome(b.tier))
				local va = VariantConfig.get(a.variant)
				local vb = VariantConfig.get(b.variant)
				local baseA = tierCashA * (va and va.CashMult or 1)
				local baseB = tierCashB * (vb and vb.CashMult or 1)
				return baseA > baseB
			end)
			for _, e in ipairs(list) do
				order += 1
				any = true
				local entry = e
				makeBrainrotCard(grid, entry, state.Rebirths or 0, order, function()
					equipBy(function(t)
						return t:GetAttribute("Kind") == "Brainrot" and t:GetAttribute("BrainrotId") == entry.id
					end)
				end)
			end
		end

		if not any then
			empty.Text = (activeFilter == "Eggs") and "No eggs — go dig!"
				or (activeFilter == "Brainrots") and "No brainrots yet — hatch an egg!"
				or "Nothing here yet — go dig & hatch!"
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

	return api
end

return Inventory
