--!strict
-- TopBar
-- Top-center Cash + Gem counters with coin/gem icons and a zone label.
-- Counters animate (tick up) and pop when the value changes.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Format = require(Shared.Modules.Format)
local ZoneConfig = require(Shared.Config.ZoneConfig)

local UIUtil = require(script.Parent.Parent.UIUtil)
local ClientState = require(script.Parent.Parent.ClientState)

local TopBar = {}

local function counter(parent: Instance, order: number, emoji: string, color: Color3)
	local holder = UIUtil.frame({
		Size = UDim2.new(0, 200, 1, 0),
		BackgroundColor3 = UIUtil.Colors.Panel,
		LayoutOrder = order,
		Parent = parent,
	})
	UIUtil.corner(holder, 16)
	UIUtil.stroke(holder, 3, color)

	-- emoji icon (renders without needing an uploaded image asset)
	local iconLabel = UIUtil.label({
		Size = UDim2.new(0, 40, 0, 40),
		Position = UDim2.new(0, 8, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Text = emoji,
		Parent = holder,
	})
	iconLabel.TextXAlignment = Enum.TextXAlignment.Center

	local value = UIUtil.label({
		Size = UDim2.new(1, -56, 1, -10),
		Position = UDim2.new(0, 52, 0, 5),
		Text = "0",
		TextColor3 = color,
		Parent = holder,
	})
	value.TextXAlignment = Enum.TextXAlignment.Left
	return value, holder
end

function TopBar.build(gui: ScreenGui)
	local bar = UIUtil.frame({
		Name = "TopBar",
		Size = UDim2.new(0, 640, 0, 64),
		Position = UDim2.new(0.5, 0, 0, 12),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	local layout = UIUtil.listLayout(bar, 12, Enum.FillDirection.Horizontal)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local cashValue, cashHolder = counter(bar, 1, "💵", UIUtil.Colors.Good)
	local gemValue, gemHolder = counter(bar, 2, "💎", UIUtil.Colors.Gem)

	-- zone label below
	local zoneLabel = UIUtil.label({
		Name = "ZoneLabel",
		Size = UDim2.new(0, 360, 0, 30),
		Position = UDim2.new(0.5, 0, 0, 78),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "Zone 1",
		TextColor3 = UIUtil.Colors.Warn,
		Parent = gui,
	})

	local lastCash, lastGems = -1, -1
	ClientState.onChanged(function(state)
		if not state then return end
		if state.Cash ~= lastCash then
			cashValue.Text = Format.short(state.Cash)
			UIUtil.pop(cashHolder)
			lastCash = state.Cash
		end
		if state.Gems ~= lastGems then
			gemValue.Text = Format.short(state.Gems)
			UIUtil.pop(gemHolder)
			lastGems = state.Gems
		end
		local zone = ZoneConfig.get(state.CurrentZone)
		zoneLabel.Text = ("Zone %d — %s"):format(state.CurrentZone, zone and zone.DisplayName or "?")
	end)
end

return TopBar
