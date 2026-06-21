--!strict
-- InventoryOrder
-- Single source of truth for WHERE each inventory Tool lives: TWO ordered lists, `hotbar` (up to
-- HOTBAR_SLOTS) and `inv` (the backpack overflow). A tool is in exactly ONE list. New tools fill the
-- hotbar first, then overflow to the backpack. Drag-and-drop moves a tool between the lists in EITHER
-- direction regardless of how full they are — mirroring the default Roblox hotbar/backpack:
--   * hotbar -> inventory works even when the hotbar isn't full / the inventory is empty,
--   * inventory -> hotbar inserts into the hotbar (swapping the occupant out when the hotbar is full).
-- The Hotbar + Inventory UIs each render their own list.
-- ponytail: two contiguous lists (no in-list empty gaps) — enough for "move freely between regions"
-- without per-slot gap bookkeeping; drop target via MouseEnter/Leave hover tokens, not coordinate math.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local M = {}
M.HOTBAR_SLOTS = 10

local hotbar: { Tool } = {}
local inv: { Tool } = {}
local listeners: { () -> () } = {}

local function fire()
	for _, f in ipairs(listeners) do
		task.spawn(f)
	end
end

function M.onChanged(f: () -> ())
	table.insert(listeners, f)
end

function M.getHotbar(): { Tool }
	return hotbar
end

function M.getInventory(): { Tool }
	return inv
end

local function isInvTool(c: Instance): boolean
	return c:IsA("Tool") and c:GetAttribute("Kind") ~= nil
end

local function removeFrom(list: { Tool }, tool: Tool): boolean
	local i = table.find(list, tool)
	if i then
		table.remove(list, i)
		return true
	end
	return false
end

-- Reconcile both lists to the real Tools (Backpack + Character): prune gone, add new (hotbar first
-- while it has room, then inventory). Preserves existing placements + the relative order.
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
	for _, list in ipairs({ hotbar, inv }) do
		for i = #list, 1, -1 do
			if not present[list[i]] then
				table.remove(list, i)
				changed = true
			end
		end
	end
	for _, t in ipairs(found) do
		if not table.find(hotbar, t) and not table.find(inv, t) then
			if #hotbar < M.HOTBAR_SLOTS then
				table.insert(hotbar, t)
			else
				table.insert(inv, t)
			end
			changed = true
		end
	end
	if changed then
		fire()
	end
end

-- Drop `tool` onto hotbar position `slot` (1-based). Reorders within the hotbar, or pulls it in from
-- the inventory — swapping the occupant out to the inventory only when the hotbar is already full.
function M.dropOnHotbar(tool: Tool, slot: number?)
	local wasHotbar = table.find(hotbar, tool) ~= nil
	removeFrom(hotbar, tool)
	removeFrom(inv, tool)
	local target = math.clamp(slot or (#hotbar + 1), 1, M.HOTBAR_SLOTS)
	if not wasHotbar and #hotbar >= M.HOTBAR_SLOTS then
		-- hotbar full: bump whatever sits at `target` into the inventory (a swap)
		local bumped = hotbar[math.min(target, #hotbar)]
		if bumped then
			removeFrom(hotbar, bumped)
			table.insert(inv, 1, bumped)
		end
	end
	table.insert(hotbar, math.clamp(target, 1, #hotbar + 1), tool)
	fire()
end

-- Drop `tool` into the inventory. Works even when the hotbar isn't full / the inventory is empty.
function M.dropOnInventory(tool: Tool)
	if table.find(inv, tool) then
		return
	end
	removeFrom(hotbar, tool)
	table.insert(inv, tool)
	fire()
end

----------------------------------------------------------------- drag-and-drop
-- Current drop-hover, tracked by token (the GuiObject under the cursor) so a stale MouseLeave that
-- arrives after the next element's MouseEnter can't wipe the newer hover.
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
-- moves past the threshold, so a plain click still equips.
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
			ghost.Position = UDim2.fromOffset(m.X + 14, m.Y + 6) -- offset so the cursor stays over the drop region
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		if dragging and candidate then
			if hoverKind == "hotbar" then
				M.dropOnHotbar(candidate, hoverIndex)
			elseif hoverKind == "inventory" then
				M.dropOnInventory(candidate)
			end
		end
		endDrag()
	end)
end

return M
