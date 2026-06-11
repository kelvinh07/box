--!strict
-- TopBar
-- BOTTOM-LEFT currency stack in the chunky reference-game style: a GEM counter sitting ON TOP
-- of a LARGER CASH counter, each just an icon + a big outlined number with NO background panel.
-- Counters pop (scale-bounce) when their value changes. The zone label stays at top-center, and
-- the permanent rebirth CASH multiplier (e.g. "x1.35") sits BOTTOM-RIGHT in green.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Format = require(Shared.Modules.Format)
local ZoneConfig = require(Shared.Config.ZoneConfig)

local UIUtil = require(script.Parent.Parent.UIUtil)
local ClientState = require(script.Parent.Parent.ClientState)

local TopBar = {}

-- one-shot scale bounce on a UIScale (works regardless of TextScaled, unlike scaling Size)
local function popScale(scale: UIScale)
	scale.Scale = 1
	local up = TweenService:Create(scale, TweenInfo.new(0.08), { Scale = 1.16 })
	up.Completed:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.13, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end)
	up:Play()
end

-- One currency line: [emoji icon][big number with a chunky black outline], left-aligned, no
-- background. `height` drives the icon box + (capped) text size, so the cash line is built bigger
-- than the gem line. `centerY` is the row's vertical center inside the stack (AnchorPoint 0,0.5 so
-- the pop scales from the left edge). Returns the value label + the row's UIScale (for popping).
local function currencyRow(parent: Instance, name: string, emoji: string, color: Color3, height: number, centerY: number): (TextLabel, UIScale)
	local row = UIUtil.frame({
		Name = name,
		Size = UDim2.new(1, 0, 0, height),
		Position = UDim2.new(0, 0, 0, centerY),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
		Parent = parent,
	})
	local scale = Instance.new("UIScale")
	scale.Parent = row

	-- emoji icon (no uploaded asset needed; emoji render in their own colours so no stroke)
	local icon = UIUtil.label({
		Size = UDim2.new(0, height, 0, height),
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Text = emoji,
		Parent = row,
	})
	icon.TextScaled = false
	icon.TextSize = math.floor(height * 0.85)
	icon.TextStrokeTransparency = 1

	local value = UIUtil.label({
		Size = UDim2.new(1, -(height + 10), 1, 0),
		Position = UDim2.new(0, height + 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		Text = "0",
		TextColor3 = color,
		Parent = row,
	})
	value.TextXAlignment = Enum.TextXAlignment.Left
	-- cap the font so a SHORT value doesn't balloon; TextScaled still shrinks long values to fit.
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = math.floor(height * 0.92)
	cap.Parent = value
	-- chunky black outline like the reference games (replaces the thin default text stroke)
	value.TextStrokeTransparency = 1
	local outline = UIUtil.stroke(value, math.max(2, math.floor(height / 11)), UIUtil.Colors.Outline)
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	return value, scale
end

function TopBar.build(gui: ScreenGui)
	-- bottom-left stack, no background panel. Cash sits at the very bottom, gem just above it.
	local stack = UIUtil.frame({
		Name = "CurrencyStack",
		Size = UDim2.new(0, 380, 0, 110),
		Position = UDim2.new(0, 18, 1, -16),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = 1,
		Parent = gui,
	})

	-- GEM on top (smaller) ▸ CASH below (larger). Heights: gem 40, gap 6, cash 62 (=108 total).
	local gemValue, gemScale = currencyRow(stack, "Gem", "💎", UIUtil.Colors.Gem, 40, 20)
	local cashValue, cashScale = currencyRow(stack, "Cash", "💵", UIUtil.Colors.Good, 62, 77)

	-- zone label stays at top-center (only the cash/gem moved off the top; this fills the gap)
	local zoneLabel = UIUtil.label({
		Name = "ZoneLabel",
		Size = UDim2.new(0, 360, 0, 34),
		Position = UDim2.new(0.5, 0, 0, 12),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "Zone 1",
		TextColor3 = UIUtil.Colors.Warn,
		Parent = gui,
	})

	-- BOTTOM-RIGHT: permanent rebirth CASH multiplier, GREEN, e.g. "x1.35". Pops on change.
	local multLabel = UIUtil.label({
		Name = "CashMultiplier",
		Size = UDim2.new(0, 150, 0, 52),
		Position = UDim2.new(1, -18, 1, -16),
		AnchorPoint = Vector2.new(1, 1),
		Text = "x1.00",
		TextColor3 = UIUtil.Colors.Good,
		Parent = gui,
	})
	multLabel.TextXAlignment = Enum.TextXAlignment.Right
	local multCap = Instance.new("UITextSizeConstraint")
	multCap.MaxTextSize = 44
	multCap.Parent = multLabel
	local multScale = Instance.new("UIScale")
	multScale.Parent = multLabel

	local lastCash, lastGems, lastMult = -1, -1, -1
	ClientState.onChanged(function(state)
		if not state then return end
		if state.Cash ~= lastCash then
			cashValue.Text = "$" .. Format.short(state.Cash)
			popScale(cashScale)
			lastCash = state.Cash
		end
		if state.Gems ~= lastGems then
			gemValue.Text = Format.short(state.Gems)
			popScale(gemScale)
			lastGems = state.Gems
		end
		local mult = state.CashMultiplier or 1
		if mult ~= lastMult then
			multLabel.Text = ("x%.2f"):format(mult)
			popScale(multScale)
			lastMult = mult
		end
		local zone = ZoneConfig.get(state.CurrentZone)
		zoneLabel.Text = ("Zone %d — %s"):format(state.CurrentZone, zone and zone.DisplayName or "?")
	end)
end

return TopBar
