--!strict
-- Rebirth
-- Rebirth panel with a clear progress readout and a confirmation step. Rebirth
-- resets Cash + collection, costs Gems, unlocks the next zone, and grants a
-- permanent luck bonus. Everything is validated server-side.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Format = require(Shared.Modules.Format)
local UpgradeConfig = require(Shared.Config.UpgradeConfig)

local UIUtil = require(script.Parent.Parent.UIUtil)
local ClientState = require(script.Parent.Parent.ClientState)
local ClientNet = require(script.Parent.Parent.ClientNet)
local Sounds = require(script.Parent.Parent.Sounds)

local Rebirth = {}

function Rebirth.build(gui: ScreenGui)
	local modal = UIUtil.modal(gui, "🔁 Rebirth", UDim2.new(0, 520, 0, 420))

	local info = UIUtil.label({
		Size = UDim2.new(1, -16, 0, 160),
		Text = "",
		TextWrapped = true,
		LayoutOrder = 1,
		Parent = modal.content,
	})
	info.TextYAlignment = Enum.TextYAlignment.Top
	info.ZIndex = 22

	local rebirthBtn = UIUtil.button({
		Size = UDim2.new(1, -16, 0, 70),
		BackgroundColor3 = UIUtil.Colors.Warn,
		Text = "REBIRTH",
		TextSize = 30,
		LayoutOrder = 2,
		Parent = modal.content,
	})
	rebirthBtn.ZIndex = 22

	-- confirmation overlay (second tap to confirm)
	local confirming = false
	local function resetConfirm()
		confirming = false
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
		local atMaxZone = state.HighestZone >= state.MaxZone
		info.Text = string.format(
			"Rebirths: %d\nCurrent Zone: %d / %d\n\nMilestone: $%s  (you: $%s)\nCost: %s 💎\n\nResets Cash & brainrots.\nUnlocks the next zone.\nPermanent +%d%% luck per rebirth.",
			state.Rebirths,
			state.CurrentZone, state.MaxZone,
			Format.short(state.RebirthMilestone), Format.short(state.Cash),
			Format.short(cost),
			math.floor(UpgradeConfig.Rebirth.LuckBonusPerRebirth * 100)
		)

		if atMaxZone and not state.RebirthReady then
			rebirthBtn.Text = "MAX ZONE REACHED"
			rebirthBtn.BackgroundColor3 = UIUtil.Colors.Outline
		elseif state.RebirthReady and state.Gems >= cost then
			if not confirming then
				rebirthBtn.Text = "REBIRTH"
				rebirthBtn.BackgroundColor3 = UIUtil.Colors.Warn
			end
		elseif state.RebirthReady and state.Gems < cost then
			rebirthBtn.Text = ("Need %s 💎"):format(Format.short(cost))
			rebirthBtn.BackgroundColor3 = UIUtil.Colors.Outline
		else
			rebirthBtn.Text = ("Reach $%s first"):format(Format.short(state.RebirthMilestone))
			rebirthBtn.BackgroundColor3 = UIUtil.Colors.Outline
		end
	end)

	return modal
end

return Rebirth
