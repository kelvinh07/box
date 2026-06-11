--!strict
-- Hotbar
-- A CUSTOM bottom-center hotbar that visually REPLACES the default Roblox hotbar (the real
-- Tools / Backpack / Character all still live underneath — we only hide the default UI). It
-- mirrors the classic numbered hotbar: up to 9 slots, each with a number label, a transparent
-- ViewportFrame icon (via ToolVisual) and — for egg tools — a count badge; the EQUIPPED slot is
-- highlighted with a thick accent stroke + brighter background.
--
-- Design points (the fiddly parts):
--   * Slots are PERSISTENT per Tool, keyed by the Tool instance, so equipping/unequipping never
--     rebuilds a ViewportFrame — only the highlight + the ordering update. A slot's viewport is
--     built ONCE, the first time its tool appears.
--   * The player's inventory Tools (Backpack + Character, anything with a "Kind" attribute) are
--     kept in a STABLE ordered list: present tools keep their order, new tools append, destroyed
--     tools are pruned. order[1..9] is shown in the hotbar; the rest live only in the Inventory
--     overlay.
--   * Clicking a slot OR pressing its number key TOGGLES it: equipped -> UnequipTools, else
--     EquipTool. Number keys are ignored when gameProcessedEvent is set (so typing in the
--     Inventory search box never equips).
--
-- Server-authoritative: EquipTool/UnequipTools are the equip mechanism; this module never
-- mutates gameplay values, it only reflects the real Backpack/Character + ClientState.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local UIUtil = require(script.Parent.Parent.UIUtil)
local ClientState = require(script.Parent.Parent.ClientState)
local ToolVisual = require(script.Parent.Parent.ToolVisual)

local player = Players.LocalPlayer

local Hotbar = {}

local MAX_SLOTS = 9
local SLOT = 68          -- slot square size
local GAP = 6            -- gap between slots
local Z = 8              -- below the modals/overlay; the persistent HUD layer

-- number-key -> slot index
local KEYS = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8, [Enum.KeyCode.Nine] = 9,
}

----------------------------------------------------------------- state
-- Per-tool slot widget (built ONCE per tool). Keyed by the Tool instance.
type Slot = {
	tool: Tool,
	frame: Frame,
	stroke: UIStroke,
	badge: TextLabel,
	rarity: string?, -- set for egg tools (drives the count badge)
}

local slots: { [Tool]: Slot } = {}
local order: { Tool } = {}        -- STABLE ordered list of the player's inventory tools

local bar: Frame                  -- the hotbar container (holds order[1..9])
local barLayout: UIListLayout

-- live bindings to the current character/backpack (rebound on respawn)
local backpack: Backpack?
local character: Model?
local conns: { RBXScriptConnection } = {}

----------------------------------------------------------------- helpers
local function isInvTool(c: Instance): boolean
	return c:IsA("Tool") and c:GetAttribute("Kind") ~= nil
end

local function humanoid(): Humanoid?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid") or nil
end

local function isEquipped(tool: Tool): boolean
	return tool.Parent ~= nil and tool.Parent == player.Character
end

-- equip / unequip TOGGLE for a tool
local function toggleEquip(tool: Tool)
	local hum = humanoid()
	if not hum then
		return
	end
	if isEquipped(tool) then
		hum:UnequipTools()
	else
		hum:EquipTool(tool)
	end
end

----------------------------------------------------------------- slot widget (built ONCE per tool)
local function buildSlot(tool: Tool): Slot
	local frame = UIUtil.frame({
		Name = "Slot",
		Size = UDim2.new(0, SLOT, 0, SLOT),
		BackgroundColor3 = UIUtil.Colors.Panel,
		BackgroundTransparency = 0.15,
		Parent = bar,
	})
	frame.ZIndex = Z
	UIUtil.corner(frame, 12)
	local stroke = UIUtil.stroke(frame, 3, UIUtil.Colors.Outline)

	-- item icon (built ONCE; reused across equip/unequip)
	local vf = Instance.new("ViewportFrame")
	vf.Name = "Icon"
	vf.BackgroundTransparency = 1
	vf.Size = UDim2.new(1, -8, 1, -8)
	vf.Position = UDim2.new(0.5, 0, 0.5, 0)
	vf.AnchorPoint = Vector2.new(0.5, 0.5)
	vf.ZIndex = Z + 1
	vf.Parent = frame

	-- number label (top-left)
	local num = UIUtil.label({
		Size = UDim2.new(0, 18, 0, 18),
		Position = UDim2.new(0, 3, 0, 1),
		Text = "",
		TextColor3 = UIUtil.Colors.Text,
		Parent = frame,
	})
	num.TextXAlignment = Enum.TextXAlignment.Left
	num.ZIndex = Z + 2
	num.Name = "Num"

	-- egg count badge (bottom-right) — only shown for egg tools
	local badge = UIUtil.label({
		Size = UDim2.new(0, 28, 0, 20),
		Position = UDim2.new(1, -30, 1, -22),
		Text = "",
		TextColor3 = UIUtil.Colors.Text,
		Visible = false,
		Parent = frame,
	})
	badge.TextXAlignment = Enum.TextXAlignment.Right
	badge.ZIndex = Z + 2

	-- whole slot is the click target -> toggle equip
	local btn = Instance.new("TextButton")
	btn.BackgroundTransparency = 1
	btn.Text = ""
	btn.Size = UDim2.new(1, 0, 1, 0)
	btn.ZIndex = Z + 3
	btn.Parent = frame
	btn.MouseButton1Click:Connect(function()
		toggleEquip(tool)
	end)

	local rarity: string? = nil
	local kind = tool:GetAttribute("Kind")
	if kind == "Egg" then
		rarity = tostring(tool:GetAttribute("Rarity") or "Common")
		ToolVisual.renderEgg(vf, rarity :: string)
	elseif kind == "Brainrot" then
		-- mountBrainrot renders now AND retries into this same viewport until the model replicates,
		-- so a slow-to-arrive model still fills the slot instead of staying blank.
		ToolVisual.mountBrainrot(vf, tostring(tool:GetAttribute("BrainrotId")))
	end

	return { tool = tool, frame = frame, stroke = stroke, badge = badge, rarity = rarity }
end

-- get-or-build the persistent slot for a tool
local function slotFor(tool: Tool): Slot
	local s = slots[tool]
	if not s then
		s = buildSlot(tool)
		slots[tool] = s
	end
	return s
end

----------------------------------------------------------------- ordering
-- Rebuild the STABLE ordered list: keep present tools in their current order, append any newly
-- added tool, prune destroyed ones. Returns true if the order changed.
local function rescanOrder(): boolean
	-- gather the current set of inventory tools (Backpack + Character) into BOTH a membership set
	-- (for the prune pass) and a deterministic ORDERED list (container + child order) used for the
	-- append pass. Iterating GetChildren() in a fixed container order (backpack, then character)
	-- gives a stable, reproducible layout — unlike pairs() over an Instance-keyed table, whose
	-- order is unspecified and would scramble slot positions whenever >1 tool is appended at once
	-- (the common case at first join and on respawn).
	local present: { [Tool]: boolean } = {}
	local presentList: { Tool } = {}
	local function gather(container: Instance?)
		if not container then
			return
		end
		for _, c in ipairs(container:GetChildren()) do
			if isInvTool(c) then
				local tool = c :: Tool
				if not present[tool] then
					present[tool] = true
					presentList[#presentList + 1] = tool
				end
			end
		end
	end
	gather(backpack)
	gather(character)

	local changed = false

	-- prune tools no longer present (destroy their persistent slot widget)
	local kept: { Tool } = {}
	for _, tool in ipairs(order) do
		if present[tool] then
			kept[#kept + 1] = tool
		else
			changed = true
			local s = slots[tool]
			if s then
				s.frame:Destroy()
				slots[tool] = nil
			end
		end
	end

	-- append any tools not already in the order, in the deterministic presentList order (stable,
	-- reproducible — NOT pairs(present), whose iteration order is unspecified)
	for _, tool in ipairs(presentList) do
		if table.find(kept, tool) == nil then
			kept[#kept + 1] = tool
			changed = true
		end
	end

	order = kept
	return changed
end

----------------------------------------------------------------- render
-- Place order[1..MAX_SLOTS] into the bar (LayoutOrder), set number labels, refresh egg badges +
-- the equipped highlight. Never rebuilds a viewport.
local function render()
	local state = ClientState.get()
	for i, tool in ipairs(order) do
		local s = slots[tool]
		if s then
			if i <= MAX_SLOTS then
				s.frame.Visible = true
				s.frame.LayoutOrder = i
				local num = s.frame:FindFirstChild("Num") :: TextLabel?
				if num then
					num.Text = tostring(i)
				end
			else
				-- overflow: only the Inventory overlay shows these
				s.frame.Visible = false
			end

			-- egg count badge from the live snapshot
			if s.rarity then
				local count = (state and state.Eggs and state.Eggs[s.rarity]) or 0
				s.badge.Visible = true
				s.badge.Text = "x" .. tostring(count)
			else
				s.badge.Visible = false
			end

			-- equipped highlight
			if isEquipped(tool) then
				s.stroke.Color = UIUtil.Colors.Accent
				s.stroke.Thickness = 4
				s.frame.BackgroundColor3 = UIUtil.Colors.PanelLight
				s.frame.BackgroundTransparency = 0
			else
				s.stroke.Color = UIUtil.Colors.Outline
				s.stroke.Thickness = 3
				s.frame.BackgroundColor3 = UIUtil.Colors.Panel
				s.frame.BackgroundTransparency = 0.15
			end
		end
	end
end

-- full refresh: re-scan the ordered list (building/pruning slot widgets) then render
local function refresh()
	-- ensure persistent slots exist for everything present (build viewports ONCE)
	rescanOrder()
	for _, tool in ipairs(order) do
		slotFor(tool)
	end
	render()
end

----------------------------------------------------------------- binding
local function disconnectAll()
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	table.clear(conns)
end

-- (re)bind to the current Backpack + Character. Called on start + every respawn (the Backpack
-- is recreated, and the Character is new, so every connection must be re-made).
local function bind()
	disconnectAll()
	backpack = player:FindFirstChildOfClass("Backpack")
	character = player.Character

	-- a new Backpack can appear slightly after the character; watch the player for it
	if not backpack then
		conns[#conns + 1] = player.ChildAdded:Connect(function(c)
			if c:IsA("Backpack") and not backpack then
				backpack = c
				conns[#conns + 1] = c.ChildAdded:Connect(refresh)
				conns[#conns + 1] = c.ChildRemoved:Connect(function()
					task.defer(refresh)
				end)
				refresh()
			end
		end)
	else
		conns[#conns + 1] = backpack.ChildAdded:Connect(refresh)
		conns[#conns + 1] = backpack.ChildRemoved:Connect(function()
			task.defer(refresh)
		end)
	end

	if character then
		conns[#conns + 1] = character.ChildAdded:Connect(function(c)
			if c:IsA("Tool") then
				refresh()
			end
		end)
		conns[#conns + 1] = character.ChildRemoved:Connect(function(c)
			if c:IsA("Tool") then
				task.defer(refresh)
			end
		end)
	end

	refresh()
end

----------------------------------------------------------------- disable default backpack UI
-- CoreGui can reject SetCoreGuiEnabled if called too early; retry until it sticks.
local function disableDefaultBackpack()
	task.spawn(function()
		for _ = 1, 30 do
			local ok = pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
			end)
			if ok then
				return
			end
			task.wait(0.5)
		end
	end)
end

----------------------------------------------------------------- public
function Hotbar.start(gui: ScreenGui)
	disableDefaultBackpack()

	bar = UIUtil.frame({
		Name = "Hotbar",
		Size = UDim2.new(0, MAX_SLOTS * SLOT + (MAX_SLOTS - 1) * GAP, 0, SLOT),
		Position = UDim2.new(0.5, 0, 1, -12),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	bar.ZIndex = Z
	-- auto-shrink to the visible (<= MAX_SLOTS) slots so the bar stays centered
	bar.AutomaticSize = Enum.AutomaticSize.X
	bar.Size = UDim2.new(0, 0, 0, SLOT)

	barLayout = UIUtil.listLayout(bar, GAP, Enum.FillDirection.Horizontal)
	barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	barLayout.VerticalAlignment = Enum.VerticalAlignment.Center

	bind()
	player.CharacterAdded:Connect(function()
		-- the Backpack is recreated on respawn; rebind cleanly (slot widgets for now-destroyed
		-- tools get pruned by rescanOrder on the next refresh)
		task.defer(bind)
	end)

	-- number keys 1..9 toggle the matching slot; ignore when the engine already consumed the
	-- input (e.g. typing in the Inventory search box).
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		local idx = KEYS[input.KeyCode]
		if idx and order[idx] then
			toggleEquip(order[idx])
		end
	end)

	-- egg count badges + the equipped highlight track the snapshot; this is a cheap re-render
	-- (no viewport rebuilds).
	ClientState.onChanged(function()
		render()
	end)
end

return Hotbar
