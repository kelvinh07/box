--!strict
-- Backpack
-- A toggleable egg backpack: a 🎒 button pinned middle-left opens a panel listing
-- the eggs you hold (one slot per rarity). Clicking a rarity tries to hatch it via
-- PlaceEgg (the server requires you to be at your incubator and toasts otherwise).
-- A capacity line shows Total: X / CAP and turns red / "MAXED!" when full.
--
-- Replaces the old always-on egg tray that used to live in the HUD.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local EggConfig = require(Shared.Config.EggConfig)
local RarityColors = require(Shared.Config.RarityColors)

local UIUtil = require(script.Parent.Parent.UIUtil)
local ClientState = require(script.Parent.Parent.ClientState)
local ClientNet = require(script.Parent.Parent.ClientNet)
local Sounds = require(script.Parent.Parent.Sounds)

local Backpack = {}

local PANEL_W = 260
local SLOT_H = 56
local TITLE_H = 30
local CAP_H = 28

function Backpack.build(gui: ScreenGui)
	-- panel sized to fit the title + one slot per rarity + the capacity line
	local panelH = TITLE_H + #EggConfig.Order * (SLOT_H + 6) + CAP_H + 24

	local panel = UIUtil.frame({
		Name = "BackpackPanel",
		Size = UDim2.new(0, PANEL_W, 0, panelH),
		-- left-middle, just to the right of the 🎒 button (button is at x=16, ~64 wide)
		Position = UDim2.new(0, 92, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Visible = false,
		Parent = gui,
	})
	UIUtil.corner(panel, 16)
	UIUtil.stroke(panel, 3)

	local title = UIUtil.label({
		Size = UDim2.new(1, -16, 0, TITLE_H),
		Position = UDim2.new(0, 8, 0, 6),
		Text = "🎒 Eggs (click to hatch)",
		Parent = panel,
	})
	title.TextXAlignment = Enum.TextXAlignment.Left

	-- vertical list of rarity slots
	local list = UIUtil.frame({
		Size = UDim2.new(1, -16, 0, #EggConfig.Order * (SLOT_H + 6)),
		Position = UDim2.new(0, 8, 0, TITLE_H + 8),
		BackgroundTransparency = 1,
		Parent = panel,
	})
	local layout = UIUtil.listLayout(list, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local slots: { [string]: TextButton } = {}
	for i, rarity in ipairs(EggConfig.Order) do
		local slot = UIUtil.button({
			Name = rarity,
			Size = UDim2.new(1, 0, 0, SLOT_H),
			BackgroundColor3 = RarityColors.tier(rarity),
			Text = ("%s\n0"):format(rarity:sub(1, 4)),
			TextSize = 22,
			LayoutOrder = i,
			Parent = list,
		})
		slot.MouseButton1Click:Connect(function()
			local result = ClientNet.invoke("PlaceEgg", rarity)
			if result and result.ok then
				Sounds.play("Purchase", 1.2)
			end
		end)
		slots[rarity] = slot
	end

	-- capacity line at the bottom
	local capLabel = UIUtil.label({
		Size = UDim2.new(1, -16, 0, CAP_H),
		Position = UDim2.new(0, 8, 1, -CAP_H - 8),
		Text = "Total: 0 / 5",
		Parent = panel,
	})

	-- reflect server state
	ClientState.onChanged(function(state)
		if not state then return end
		for rarity, slot in pairs(slots) do
			local count = (state.Eggs and state.Eggs[rarity]) or 0
			slot.Text = ("%s\n%d"):format(rarity:sub(1, 4), count)
			slot.AutoButtonColor = false
			slot.BackgroundTransparency = count > 0 and 0 or 0.55
		end

		local total = state.EggCount or 0
		local cap = state.EggCapacity or 0
		if total >= cap then
			capLabel.Text = ("Total: %d / %d  MAXED!"):format(total, cap)
			capLabel.TextColor3 = Color3.fromRGB(255, 90, 90)
		else
			capLabel.Text = ("Total: %d / %d"):format(total, cap)
			capLabel.TextColor3 = UIUtil.Colors.Text
		end
	end)

	-- the 🎒 button: middle-left, toggles the panel
	local btn = UIUtil.button({
		Name = "BackpackButton",
		Size = UDim2.new(0, 64, 0, 64),
		Position = UDim2.new(0, 16, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = UIUtil.Colors.Warn,
		Text = "🎒",
		TextSize = 34,
		Parent = gui,
	})
	btn.MouseButton1Click:Connect(function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			UIUtil.pop(panel)
		end
	end)
end

return Backpack
