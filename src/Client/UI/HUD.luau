--!strict
-- HUD
-- The always-on incubator panel (bottom-right): live progress bar + countdown +
-- COLLECT. The egg inventory now lives in the toggleable Backpack panel (see
-- UI/Backpack). (Digging is done in the world via the "E to Dig" prompt — see DigSite.)

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Format = require(Shared.Modules.Format)

local UIUtil = require(script.Parent.Parent.UIUtil)
local ClientState = require(script.Parent.Parent.ClientState)
local ClientNet = require(script.Parent.Parent.ClientNet)
local Sounds = require(script.Parent.Parent.Sounds)

local HUD = {}

----------------------------------------------------------------- incubator
local function buildIncubator(gui: ScreenGui)
	local panel = UIUtil.frame({
		Name = "Incubator",
		Size = UDim2.new(0, 300, 0, 120),
		Position = UDim2.new(1, -16, 1, -16),
		AnchorPoint = Vector2.new(1, 1),
		Parent = gui,
	})
	UIUtil.corner(panel, 16)
	UIUtil.stroke(panel, 3, UIUtil.Colors.Gem)

	local title = UIUtil.label({
		Size = UDim2.new(1, -12, 0, 26),
		Position = UDim2.new(0, 6, 0, 4),
		Text = "🔮 Incubator",
		TextColor3 = UIUtil.Colors.Gem,
		Parent = panel,
	})
	title.TextXAlignment = Enum.TextXAlignment.Left

	-- progress bar
	local barBg = UIUtil.frame({
		Size = UDim2.new(1, -16, 0, 26),
		Position = UDim2.new(0, 8, 0, 34),
		BackgroundColor3 = UIUtil.Colors.Outline,
		Parent = panel,
	})
	UIUtil.corner(barBg, 13)
	local barFill = UIUtil.frame({
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = UIUtil.Colors.Gem,
		Parent = barBg,
	})
	UIUtil.corner(barFill, 13)
	local barText = UIUtil.label({
		Size = UDim2.fromScale(1, 1),
		Text = "Empty",
		Parent = barBg,
	})
	barText.ZIndex = 5

	local collectBtn = UIUtil.button({
		Size = UDim2.new(1, -16, 0, 40),
		Position = UDim2.new(0, 8, 0, 70),
		BackgroundColor3 = UIUtil.Colors.Good,
		Text = "COLLECT",
		TextSize = 26,
		Visible = false,
		Parent = panel,
	})
	collectBtn.MouseButton1Click:Connect(function()
		local result = ClientNet.invoke("CollectIncubator")
		if result and result.ok then
			Sounds.play("Sparkle")
		end
	end)

	-- live countdown driven by Heartbeat (incubator endTime comes from server)
	RunService.Heartbeat:Connect(function()
		local state = ClientState.get()
		local inc = state and state.Incubator
		if not inc then
			barFill.Size = UDim2.new(0, 0, 1, 0)
			barText.Text = "Empty — dig & hatch an egg"
			collectBtn.Visible = false
			return
		end
		local remaining = inc.endTime - workspace:GetServerTimeNow()
		local progress = 1 - math.clamp(remaining / math.max(inc.duration, 0.01), 0, 1)
		barFill.Size = UDim2.new(progress, 0, 1, 0)
		if remaining <= 0 then
			barText.Text = ("%s — READY!"):format(inc.rarity)
			barFill.BackgroundColor3 = UIUtil.Colors.Good
			collectBtn.Visible = true
		else
			barText.Text = ("%s — %s"):format(inc.rarity, Format.time(remaining))
			barFill.BackgroundColor3 = UIUtil.Colors.Gem
			collectBtn.Visible = false
		end
	end)
end

function HUD.build(gui: ScreenGui)
	buildIncubator(gui)
end

return HUD
