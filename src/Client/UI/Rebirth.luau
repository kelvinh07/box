--!strict
-- Rebirth
-- Rebirth panel with a LifetimeCash progress bar and a confirmation step.
-- Rebirthing charges Gems and, FOREVER after, multiplies your income: gems ×1.5
-- and cash ×1.2 per rebirth (compounding). Cash + LifetimeCash reset to 0, but
-- your Collection and brainrot levels PERSIST. Everything is validated
-- server-side; the button only un-grays once the server reports all three
-- requirements met (state.RebirthReady): LifetimeCash milestone, Gem cost, and
-- being in the correct zone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Format = require(Shared.Modules.Format)

local UIUtil = require(script.Parent.Parent.UIUtil)
local ClientState = require(script.Parent.Parent.ClientState)
local ClientNet = require(script.Parent.Parent.ClientNet)
local Sounds = require(script.Parent.Parent.Sounds)

local Rebirth = {}

-- 0..1 clamp helper for the progress bar fill.
local function clamp01(x: number): number
	if x < 0 then return 0 end
	if x > 1 then return 1 end
	return x
end

function Rebirth.build(gui: ScreenGui)
	local modal = UIUtil.modal(gui, "🔁 Rebirth", UDim2.new(0, 520, 0, 470))

	-- top status line (rebirth count + reward summary)
	local info = UIUtil.label({
		Size = UDim2.new(1, -16, 0, 92),
		Text = "",
		TextWrapped = true,
		LayoutOrder = 1,
		Parent = modal.content,
	})
	info.TextYAlignment = Enum.TextYAlignment.Top
	info.ZIndex = 22

	-- LifetimeCash progress toward the milestone --------------------------------
	local progressLabel = UIUtil.label({
		Size = UDim2.new(1, -16, 0, 30),
		Text = "",
		LayoutOrder = 2,
		Parent = modal.content,
	})
	progressLabel.TextXAlignment = Enum.TextXAlignment.Left
	progressLabel.ZIndex = 22

	local bar = UIUtil.frame({
		Size = UDim2.new(1, -16, 0, 30),
		BackgroundColor3 = UIUtil.Colors.Outline,
		LayoutOrder = 3,
		Parent = modal.content,
	})
	bar.ZIndex = 22
	UIUtil.corner(bar, 12)
	UIUtil.stroke(bar, 2)

	local fill = UIUtil.frame({
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = UIUtil.Colors.Good,
		Parent = bar,
	})
	fill.ZIndex = 23
	UIUtil.corner(fill, 12)

	-- confirm-step preview (multipliers + cost + milestone + tagline) -----------
	local preview = UIUtil.label({
		Size = UDim2.new(1, -16, 0, 120),
		Text = "",
		TextWrapped = true,
		LayoutOrder = 4,
		Parent = modal.content,
	})
	preview.TextYAlignment = Enum.TextYAlignment.Top
	preview.ZIndex = 22
	preview.Visible = false

	local rebirthBtn = UIUtil.button({
		Size = UDim2.new(1, -16, 0, 70),
		BackgroundColor3 = UIUtil.Colors.Warn,
		Text = "REBIRTH",
		TextSize = 30,
		LayoutOrder = 5,
		Parent = modal.content,
	})
	rebirthBtn.ZIndex = 22

	-- confirmation overlay (second tap to confirm)
	local confirming = false
	local function resetConfirm()
		confirming = false
		preview.Visible = false
		rebirthBtn.Text = "REBIRTH"
		rebirthBtn.BackgroundColor3 = UIUtil.Colors.Warn
	end

	rebirthBtn.MouseButton1Click:Connect(function()
		local state = ClientState.get()
		if not state or not state.RebirthReady then
			return
		end
		if not confirming then
			confirming = true
			preview.Visible = true
			rebirthBtn.Text = "⚠️ TAP AGAIN TO CONFIRM"
			rebirthBtn.BackgroundColor3 = Color3.fromRGB(220, 70, 80)
			task.delay(3, function()
				if confirming then resetConfirm() end
			end)
			return
		end
		resetConfirm()
		local r = ClientNet.invoke("Rebirth")
		if r and r.ok then
			Sounds.play("Rebirth")
		end
	end)

	ClientState.onChanged(function(state)
		if not state then return end
		local cost = state.RebirthGemCost
		local milestone = state.RebirthMilestone
		local lifetime = state.LifetimeCash

		-- reward summary (NO collection reset / NO luck — those are gone)
		info.Text = string.format(
			"Rebirths: %d\n\nRebirth multiplies your income FOREVER:\n  Gems ×1.5  •  Cash ×1.2  per rebirth.\nCash resets, but your brainrots & their levels stay.",
			state.Rebirths
		)

		-- progress bar toward the LifetimeCash milestone
		local frac = milestone > 0 and clamp01(lifetime / milestone) or 1
		fill.Size = UDim2.new(frac, 0, 1, 0)
		fill.BackgroundColor3 = frac >= 1 and UIUtil.Colors.Good or UIUtil.Colors.Warn
		progressLabel.Text = ("Lifetime Cash: $%s / $%s  (%d%%)"):format(
			Format.short(lifetime), Format.short(milestone), math.floor(frac * 100)
		)

		-- confirm-step preview: multiplier deltas, gem cost, milestone, tagline
		local gemNow = state.GemMultiplier
		local cashNow = state.CashMultiplier
		preview.Text = string.format(
			"Gems x%.2f → x%.2f\nCash x%.2f → x%.2f\nCost: %s 💎\nLifetime Cash: $%s / $%s\n\nRebirth now to earn Gems 1.5x faster",
			gemNow, gemNow * 1.5,
			cashNow, cashNow * 1.2,
			Format.short(cost),
			Format.short(lifetime), Format.short(milestone)
		)

		-- button state: only enabled when ALL THREE requirements are met
		if state.RebirthReady then
			if not confirming then
				rebirthBtn.Text = "REBIRTH"
				rebirthBtn.BackgroundColor3 = UIUtil.Colors.Warn
			end
		else
			if confirming then resetConfirm() end
			-- explain the FIRST unmet requirement
			if lifetime < milestone then
				rebirthBtn.Text = ("Reach $%s lifetime"):format(Format.short(milestone))
			elseif state.Gems < cost then
				rebirthBtn.Text = ("Need %s 💎"):format(Format.short(cost))
			else
				rebirthBtn.Text = "Go to the correct zone"
			end
			rebirthBtn.BackgroundColor3 = UIUtil.Colors.PanelLight
		end
	end)

	return modal
end

return Rebirth
