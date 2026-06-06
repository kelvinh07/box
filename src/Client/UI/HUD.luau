--!strict
-- HUD
-- The always-on incubators panel (bottom-right): one row per UNLOCKED incubator (up to
-- MaxIncubators), each with a live progress bar + countdown + its own COLLECT button.
-- You unlock more incubators (to hatch more at once) by buying them in-world at your base.
-- The egg inventory lives in the toggleable Backpack panel; digging is the "E to Dig"
-- world prompt (see DigSite).

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Format = require(Shared.Modules.Format)

local UIUtil = require(script.Parent.Parent.UIUtil)
local ClientState = require(script.Parent.Parent.ClientState)
local ClientNet = require(script.Parent.Parent.ClientNet)
local Sounds = require(script.Parent.Parent.Sounds)

local HUD = {}

local MAX_ROWS = 4   -- build all, show/hide by IncubatorsUnlocked
local TITLE_H = 28
local ROW_H = 46
local PAD = 8

type Row = { frame: Frame, fill: Frame, text: TextLabel, collect: TextButton }

local function buildIncubators(gui: ScreenGui)
	local panel = UIUtil.frame({
		Name = "Incubators",
		Size = UDim2.new(0, 320, 0, TITLE_H + MAX_ROWS * (ROW_H + 6) + PAD * 2),
		Position = UDim2.new(1, -16, 1, -16),
		AnchorPoint = Vector2.new(1, 1),
		Parent = gui,
	})
	UIUtil.corner(panel, 16)
	UIUtil.stroke(panel, 3, UIUtil.Colors.Gem)

	local title = UIUtil.label({
		Size = UDim2.new(1, -12, 0, TITLE_H),
		Position = UDim2.new(0, 8, 0, 4),
		Text = "🔮 Incubators",
		TextColor3 = UIUtil.Colors.Gem,
		Parent = panel,
	})
	title.TextXAlignment = Enum.TextXAlignment.Left

	local rows: { Row } = {}
	for i = 1, MAX_ROWS do
		local idx = i -- capture for the collect closure
		local row = UIUtil.frame({
			Name = ("Inc%d"):format(i),
			Size = UDim2.new(1, -16, 0, ROW_H),
			Position = UDim2.new(0, 8, 0, TITLE_H + PAD + (i - 1) * (ROW_H + 6)),
			BackgroundColor3 = UIUtil.Colors.Outline,
			Parent = panel,
		})
		UIUtil.corner(row, 10)

		-- progress bar (fills the left part of the row)
		local barBg = UIUtil.frame({
			Size = UDim2.new(1, -104, 1, -12),
			Position = UDim2.new(0, 8, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = Color3.fromRGB(28, 30, 44),
			Parent = row,
		})
		UIUtil.corner(barBg, 9)
		local fill = UIUtil.frame({
			Size = UDim2.new(0, 0, 1, 0),
			BackgroundColor3 = UIUtil.Colors.Gem,
			Parent = barBg,
		})
		UIUtil.corner(fill, 9)
		local text = UIUtil.label({
			Size = UDim2.fromScale(1, 1),
			Text = ("Inc %d — empty"):format(i),
			TextSize = 18,
			Parent = barBg,
		})
		text.ZIndex = 5

		-- COLLECT button (right side; shown only when this incubator is ready)
		local collect = UIUtil.button({
			Size = UDim2.new(0, 88, 1, -12),
			Position = UDim2.new(1, -8, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundColor3 = UIUtil.Colors.Good,
			Text = "COLLECT",
			TextSize = 18,
			Visible = false,
			Parent = row,
		})
		collect.MouseButton1Click:Connect(function()
			local result = ClientNet.invoke("CollectIncubator", idx)
			if result and result.ok then
				Sounds.play("Sparkle")
			end
		end)

		rows[i] = { frame = row, fill = fill, text = text, collect = collect }
	end

	RunService.Heartbeat:Connect(function()
		local state = ClientState.get()
		local unlocked = (state and state.IncubatorsUnlocked) or 1
		local incs = (state and state.Incubators) or {}
		local now = workspace:GetServerTimeNow()

		for i = 1, MAX_ROWS do
			local r = rows[i]
			if i > unlocked then
				r.frame.Visible = false
			else
				r.frame.Visible = true
				local inc = incs[i]
				if not inc then
					r.fill.Size = UDim2.new(0, 0, 1, 0)
					r.text.Text = ("Inc %d — empty"):format(i)
					r.collect.Visible = false
				else
					local remaining = inc.endTime - now
					local progress = 1 - math.clamp(remaining / math.max(inc.duration, 0.01), 0, 1)
					r.fill.Size = UDim2.new(progress, 0, 1, 0)
					if remaining <= 0 then
						r.text.Text = ("%s — READY!"):format(inc.rarity)
						r.fill.BackgroundColor3 = UIUtil.Colors.Good
						r.collect.Visible = true
					else
						r.text.Text = ("%s — %s"):format(inc.rarity, Format.time(remaining))
						r.fill.BackgroundColor3 = UIUtil.Colors.Gem
						r.collect.Visible = false
					end
				end
			end
		end

		-- shrink the panel to just the unlocked rows
		panel.Size = UDim2.new(0, 320, 0, TITLE_H + unlocked * (ROW_H + 6) + PAD * 2)
	end)
end

function HUD.build(gui: ScreenGui)
	buildIncubators(gui)
end

return HUD
