--!strict
-- InventoryOrder
-- Single source of truth for WHERE each inventory Tool lives. The player's tools (real Roblox Tools
-- in Backpack/Character) are kept in ONE contiguous ordered list: order[1..HOTBAR_SLOTS] is the
-- hotbar, order[HOTBAR_SLOTS+1 ..] is the inventory overflow. So an item is in exactly ONE place
-- (hotbar OR inventory, never both), the hotbar fills first as items are acquired, and the rest
-- overflow to the backpack — mirroring Roblox's default hotbar/backpack. Drag-and-drop moves a tool
-- between the two regions (reorders the list); the Hotbar + Inventory UIs just render their slice.
-- ponytail: contiguous list (no empty hotbar gaps); drop target via MouseEnter/Leave hover tokens
-- instead of screen-coordinate + GuiInset math.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local M = {}
M.HOTBAR_SLOTS = 10

local order: { Tool } = {}
local listeners: { () -> () } = {}

local function fire()
	for _, f in ipairs(listeners) do
		task.spawn(f)
	end
end

function M.onChanged(f: () -> ())
	table.insert(listeners, f)
end

function M.get(): { Tool }
	return order
end

local function isInvTool(c: Instance): boolean
	return c:IsA("Tool") and c:GetAttribute("Kind") ~= nil
end

-- Rebuild the order: keep present tools in their current positions, append newly-added tools
-- (Backpack then Character — deterministic so first-join/respawn isn't scrambled), prune gone ones.
local function rescan()
	local present: { [Tool]: boolean } = {}
	local found: { Tool } = {}
	local function gather(cont: Instance?)
		if not cont then
			return
		end
		for _, c in ipairs(cont:GetChildren()) do
			if isInvTool(c) and not present[c] then
				present[c] = true
				found[#found + 1] = c :: Tool
			end
		end
	end
	gather(player:FindFirstChildOfClass("Backpack"))
	gather(player.Character)

	local changed = false
	local kept: { Tool } = {}
	for _, t in ipairs(order) do
		if present[t] then
			kept[#kept + 1] = t
		else
			changed = true
		end
	end
	for _, t in ipairs(found) do
		if not table.find(kept, t) then
			kept[#kept + 1] = t
			changed = true
		end
	end
	order = kept
	if changed then
		fire()
	end
end

-- Move `tool` to position `target` (1-based), shifting the rest. Used by drag-drop.
function M.move(tool: Tool, target: number)
	local from = table.find(order, tool)
	if not from then
		return
	end
	table.remove(order, from)
	target = math.clamp(target, 1, #order + 1)
	table.insert(order, target, tool)
	fire()
end

----------------------------------------------------------------- drag-and-drop
-- Current drop-hover, tracked by token (the GuiObject under the cursor) so a slot's MouseLeave that
-- arrives AFTER the next slot's MouseEnter can't wipe the newer hover.
local hoverToken: Instance? = nil
local hoverKind: string? = nil
local hoverIndex: number? = nil

function M.setHover(token: Instance, kind: string, index: number?)
	hoverToken, hoverKind, hoverIndex = token, kind, index
end

function M.clearHover(token: Instance)
	if hoverToken == token then
		hoverToken, hoverKind, hoverIndex = nil, nil, nil
	end
end

local screen: ScreenGui? = nil
local candidate: Tool? = nil
local startPos: Vector2? = nil
local dragging = false
local ghost: TextLabel? = nil
local DRAG_THRESHOLD = 6

-- Called by a draggable UI element on MouseButton1Down. Becomes a real drag only once the cursor
-- moves past the threshold (so a plain click still equips); a click-in-place never starts a drag.
function M.armDrag(tool: Tool)
	candidate = tool
	startPos = UserInputService:GetMouseLocation()
	dragging = false
end

local function endDrag()
	if ghost then
		ghost:Destroy()
		ghost = nil
	end
	candidate, startPos, dragging = nil, nil, false
end

function M.start(screenGui: ScreenGui)
	screen = screenGui

	local conns: { RBXScriptConnection } = {}
	local function bind()
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
		table.clear(conns)
		rescan()
		local bp = player:FindFirstChildOfClass("Backpack")
		if bp then
			conns[#conns + 1] = bp.ChildAdded:Connect(rescan)
			conns[#conns + 1] = bp.ChildRemoved:Connect(function()
				task.defer(rescan)
			end)
		end
		local char = player.Character
		if char then
			conns[#conns + 1] = char.ChildAdded:Connect(function(c)
				if c:IsA("Tool") then
					rescan()
				end
			end)
			conns[#conns + 1] = char.ChildRemoved:Connect(function(c)
				if c:IsA("Tool") then
					task.defer(rescan)
				end
			end)
		end
	end
	-- the Backpack can appear a moment after the player; rebind whenever it (or a new character) shows
	player.ChildAdded:Connect(function(c)
		if c:IsA("Backpack") then
			task.defer(bind)
		end
	end)
	player.CharacterAdded:Connect(function()
		task.defer(bind)
	end)
	bind()

	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseMovement then
			return
		end
		if candidate and not dragging and startPos then
			if (UserInputService:GetMouseLocation() - startPos).Magnitude > DRAG_THRESHOLD then
				dragging = true
				local g = Instance.new("TextLabel")
				g.Name = "DragGhost"
				g.Size = UDim2.fromOffset(140, 32)
				g.BackgroundColor3 = Color3.fromRGB(30, 32, 48)
				g.BackgroundTransparency = 0.15
				g.TextColor3 = Color3.new(1, 1, 1)
				g.Font = Enum.Font.FredokaOne
				g.TextScaled = true
				g.Text = (candidate :: Tool).Name
				g.Active = false -- never sink input / steal hover from the region under the cursor
				g.ZIndex = 1000
				g.Parent = screen
				ghost = g
			end
		end
		if dragging and ghost then
			local m = UserInputService:GetMouseLocation()
			-- offset from the cursor so the cursor itself stays over the drop region (not the ghost)
			ghost.Position = UDim2.fromOffset(m.X + 14, m.Y + 6)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if dragging and candidate then
			if hoverKind == "hotbar" and hoverIndex then
				M.move(candidate, hoverIndex)
			elseif hoverKind == "inventory" then
				M.move(candidate, M.HOTBAR_SLOTS + 1)
			end
		end
		endDrag()
	end)
end

return M
