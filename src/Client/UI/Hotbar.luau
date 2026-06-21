--!strict
-- Hotbar
-- A CUSTOM bottom-center hotbar (slots 1..9 then 0 = 10 slots) that visually REPLACES the default
-- Roblox hotbar. The item ORDER + which region each tool lives in (hotbar vs inventory overflow) is
-- owned by the shared InventoryOrder module, so an item is in exactly ONE place and can be dragged
-- between the hotbar and the inventory overlay. This module renders order[1..HOTBAR_SLOTS] as slots
-- and handles equip (click or number key) + acts as a drag source / drop region.
--
-- Server-authoritative: EquipTool/UnequipTools are the equip mechanism; this only reflects the real
-- Backpack/Character + ClientState.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local UIUtil = require(script.Parent.Parent.UIUtil)
local ClientState = require(script.Parent.Parent.ClientState)
local ToolVisual = require(script.Parent.Parent.ToolVisual)
local InventoryOrder = require(script.Parent.Parent.InventoryOrder)

local player = Players.LocalPlayer

local Hotbar = {}

local MAX_SLOTS = InventoryOrder.HOTBAR_SLOTS
local SLOT = 68
local GAP = 6
local Z = 8

-- number-key -> slot index (1..9, then 0 for slot 10)
local KEYS = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8, [Enum.KeyCode.Nine] = 9,
	[Enum.KeyCode.Zero] = 10,
}

type Slot = { tool: Tool, frame: Frame, stroke: UIStroke, badge: TextLabel, rarity: string? }
local slots: { [Tool]: Slot } = {}
local bar: Frame

----------------------------------------------------------------- equip
local function humanoid(): Humanoid?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid") or nil
end

local function isEquipped(tool: Tool): boolean
	return tool.Parent == player.Character
end

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

	local vf = Instance.new("ViewportFrame")
	vf.Name = "Icon"
	vf.BackgroundTransparency = 1
	vf.Size = UDim2.new(1, -8, 1, -8)
	vf.Position = UDim2.new(0.5, 0, 0.5, 0)
	vf.AnchorPoint = Vector2.new(0.5, 0.5)
	vf.ZIndex = Z + 1
	vf.Parent = frame

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

	-- whole slot: click TOGGLES equip; press-and-drag (MouseButton1Down) starts a drag
	local btn = Instance.new("TextButton")
	btn.BackgroundTransparency = 1
	btn.Text = ""
	btn.Size = UDim2.new(1, 0, 1, 0)
	btn.ZIndex = Z + 3
	btn.Parent = frame
	btn.MouseButton1Click:Connect(function()
		toggleEquip(tool)
	end)
	btn.MouseButton1Down:Connect(function()
		InventoryOrder.armDrag(tool)
	end)

	-- drop-hover: report this slot's CURRENT index (the SlotIndex attribute, kept live in render)
	frame.MouseEnter:Connect(function()
		InventoryOrder.setHover(frame, "hotbar", frame:GetAttribute("SlotIndex") :: number?)
	end)
	frame.MouseLeave:Connect(function()
		InventoryOrder.clearHover(frame)
	end)

	local rarity: string? = nil
	local kind = tool:GetAttribute("Kind")
	if kind == "Egg" then
		rarity = tostring(tool:GetAttribute("Rarity") or "Common")
		ToolVisual.renderEgg(vf, rarity :: string)
	elseif kind == "Brainrot" then
		ToolVisual.mountBrainrot(vf, tostring(tool:GetAttribute("BrainrotId")))
	end

	return { tool = tool, frame = frame, stroke = stroke, badge = badge, rarity = rarity }
end

local function slotFor(tool: Tool): Slot
	local s = slots[tool]
	if not s then
		s = buildSlot(tool)
		slots[tool] = s
	end
	return s
end

----------------------------------------------------------------- render
local function render()
	local state = ClientState.get()
	local ord = InventoryOrder.get()
	local inHotbar: { [Tool]: boolean } = {}

	for i = 1, math.min(#ord, MAX_SLOTS) do
		local tool = ord[i]
		inHotbar[tool] = true
		local s = slotFor(tool)
		s.frame.LayoutOrder = i
		s.frame:SetAttribute("SlotIndex", i)
		local num = s.frame:FindFirstChild("Num") :: TextLabel?
		if num then
			num.Text = (i == 10) and "0" or tostring(i)
		end

		if s.rarity then
			s.badge.Visible = true
			s.badge.Text = "x" .. tostring((state and state.Eggs and state.Eggs[s.rarity]) or 0)
		else
			s.badge.Visible = false
		end

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

	-- destroy widgets for tools no longer in the hotbar (overflowed into the inventory via drag, or
	-- removed) — the Inventory overlay owns the overflow cards.
	for tool, s in pairs(slots) do
		if not inHotbar[tool] then
			s.frame:Destroy()
			slots[tool] = nil
		end
	end
end

----------------------------------------------------------------- disable default backpack UI
local function disableDefaultBackpack()
	task.spawn(function()
		for _ = 1, 30 do
			if pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
			end) then
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
		Position = UDim2.new(0.5, 0, 1, -12),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	bar.ZIndex = Z
	bar.AutomaticSize = Enum.AutomaticSize.X -- shrink to the visible slots so the bar stays centered
	bar.Size = UDim2.new(0, 0, 0, SLOT)

	local barLayout = UIUtil.listLayout(bar, GAP, Enum.FillDirection.Horizontal)
	barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	barLayout.VerticalAlignment = Enum.VerticalAlignment.Center

	-- dropping onto the bar's empty area (a fallback when not over a specific slot) appends to the
	-- hotbar end; per-slot MouseEnter (above) overrides this with a precise slot index.
	bar.MouseEnter:Connect(function()
		InventoryOrder.setHover(bar, "hotbar", math.min(#InventoryOrder.get() + 1, MAX_SLOTS))
	end)
	bar.MouseLeave:Connect(function()
		InventoryOrder.clearHover(bar)
	end)

	InventoryOrder.onChanged(render)
	ClientState.onChanged(render) -- egg badges + equipped highlight track the snapshot
	render()

	-- number keys 1..9,0 toggle the matching slot; ignored when the engine consumed the input
	-- (e.g. typing in the Inventory search box).
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end
		local idx = KEYS[input.KeyCode]
		local ord = InventoryOrder.get()
		if idx and ord[idx] then
			toggleEquip(ord[idx])
		end
	end)
end

return Hotbar
