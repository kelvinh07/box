--!strict
-- Rebirth
-- Rebirth is gated PURELY by cumulative LifetimeCash (which never resets). Rebirthing grants
-- a PERMANENT, compounding CASH multiplier (x1.35 each). WARNING: your Cash AND Gem balance
-- reset to 0 and ALL zone walls re-lock (you start back at Zone 1, teleported home). Your
-- brainrots, their levels, and every owned shovel/incubator are KEPT. Validated server-side;
-- the button only un-grays once state.RebirthReady (LifetimeCash >= milestone) is true.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Format = require(Shared.Modules.Format)

local UIUtil = require(script.Parent.Parent.UIUtil)
local ClientState = require(script.Parent.Parent.ClientState)
local ClientNet = require(script.Parent.Parent.ClientNet)
local Sounds = require(script.Parent.Parent.Sounds)

local Rebirth = {}

local REBIRTH_MULT = 1.35 -- must match UpgradeConfig.cashMultiplier growth

-- 0..1 clamp helper for the progress bar fill.
local function clamp01(x: number): number
	if x < 0 then return 0 end
	if x > 1 then return 1 end
	return x
end

function Rebirth.build(gui: ScreenGui)
	local modal = UIUtil.modal(gui, "🔁 Rebirth", UDim2.new(0, 520, 0, 470))

	-- top status line (rebirth count + what rebirth does + the reset WARNING)
	local info = UIUtil.label({
		Size = UDim2.new(1, -16, 0, 120),
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

	-- confirm-step preview (cash multiplier delta + the reset warning) ----------
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
		TextSize = 24,
		LayoutOrder = 5,
		Parent = modal.content,
	})
	rebirthBtn.ZIndex = 22

	-- confirmation overlay (second tap to confirm)
	local confirming = false
	local function resetConfirm()
		confirming = false
		preview.Visible = false
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
		local milestone = state.RebirthMilestone or 0
		local lifetime = state.LifetimeCash or 0
		local cashNow = state.CashMultiplier or 1

		info.Text = string.format(
			"Rebirths: %d   (Cash x%.2f)\n\nRebirth grants a PERMANENT cash multiplier: x%.2f each, compounding.\n⚠ Your Cash AND Gems reset to 0, and ALL zone walls re-lock — you start back at Zone 1 (home).\nKept: your brainrots, their levels, and every shovel/incubator you own.",
			state.Rebirths or 0, cashNow, REBIRTH_MULT
		)

		-- progress bar toward the LifetimeCash milestone
		local frac = milestone > 0 and clamp01(lifetime / milestone) or 1
		fill.Size = UDim2.new(frac, 0, 1, 0)
		fill.BackgroundColor3 = frac >= 1 and UIUtil.Colors.Good or UIUtil.Colors.Warn
		progressLabel.Text = ("Lifetime Cash: $%s / $%s  (%d%%)"):format(
			Format.short(lifetime), Format.short(milestone), math.floor(frac * 100)
		)

		-- confirm-step preview: cash multiplier delta + the explicit reset warning
		preview.Text = string.format(
			"Cash multiplier  x%.2f → x%.2f\n\n⚠ Cash resets to 0\n⚠ Gems reset to 0\n⚠ All zone walls re-lock (back to Zone 1)\n\nBrainrots, levels & equipment are KEPT.",
			cashNow, cashNow * REBIRTH_MULT
		)

		-- button state: only enabled when LifetimeCash has reached the milestone
		if state.RebirthReady then
			if not confirming then
				rebirthBtn.Text = ("REBIRTH  (x%.2f → x%.2f)"):format(cashNow, cashNow * REBIRTH_MULT)
				rebirthBtn.BackgroundColor3 = UIUtil.Colors.Warn
			end
		else
			if confirming then resetConfirm() end
			rebirthBtn.Text = ("Rebirth — requires %s lifetime cash"):format(Format.comma(milestone))
			rebirthBtn.BackgroundColor3 = UIUtil.Colors.PanelLight
		end
	end)

	return modal
end

return Rebirth
