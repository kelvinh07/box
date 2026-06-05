--!strict
-- Shop
-- Gem upgrades (Luck, Hatch Speed) + Cash plot purchases. Reads live costs/level
-- from the server snapshot; all purchases are validated server-side.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local Format = require(Shared.Modules.Format)

local UIUtil = require(script.Parent.Parent.UIUtil)
local ClientState = require(script.Parent.Parent.ClientState)
local ClientNet = require(script.Parent.Parent.ClientNet)
local Sounds = require(script.Parent.Parent.Sounds)

local Shop = {}

-- one upgrade/purchase row
local function row(parent: Instance, order: number)
	local card = UIUtil.frame({
		Size = UDim2.new(1, -8, 0, 92),
		BackgroundColor3 = UIUtil.Colors.PanelLight,
		LayoutOrder = order,
		Parent = parent,
	})
	card.ZIndex = 22
	UIUtil.corner(card, 14)
	UIUtil.stroke(card, 2)

	local title = UIUtil.label({
		Size = UDim2.new(0.62, 0, 0, 30),
		Position = UDim2.new(0, 12, 0, 8),
		Text = "",
		Parent = card,
	})
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 23

	local desc = UIUtil.label({
		Size = UDim2.new(0.62, 0, 0, 44),
		Position = UDim2.new(0, 12, 0, 40),
		Text = "",
		TextColor3 = Color3.fromRGB(200, 205, 220),
		Parent = card,
	})
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.ZIndex = 23

	local btn = UIUtil.button({
		Size = UDim2.new(0.34, 0, 0, 70),
		Position = UDim2.new(0.64, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = UIUtil.Colors.Good,
		Text = "BUY",
		TextSize = 24,
		Parent = card,
	})
	btn.ZIndex = 23

	return title, desc, btn
end

function Shop.build(gui: ScreenGui)
	local modal = UIUtil.modal(gui, "🛒 Shop", UDim2.new(0, 560, 0, 520))

	-- LUCK
	local luckTitle, luckDesc, luckBtn = row(modal.content, 1)
	luckBtn.MouseButton1Click:Connect(function()
		local r = ClientNet.invoke("UpgradeLuck")
		if r and r.ok then Sounds.play("Purchase") end
	end)

	-- HATCH SPEED
	local hsTitle, hsDesc, hsBtn = row(modal.content, 2)
	hsBtn.MouseButton1Click:Connect(function()
		local r = ClientNet.invoke("UpgradeHatchSpeed")
		if r and r.ok then Sounds.play("Purchase") end
	end)

	-- BUY PLOT
	local plotTitle, plotDesc, plotBtn = row(modal.content, 3)
	plotBtn.MouseButton1Click:Connect(function()
		local r = ClientNet.invoke("BuyPlot")
		if r and r.ok then Sounds.play("Purchase") end
	end)

	ClientState.onChanged(function(state)
		if not state then return end

		-- Luck
		local luckLvl = state.LuckLevel
		luckTitle.Text = ("🍀 Luck  (Lv %d/%d)"):format(luckLvl, UpgradeConfig.Luck.MaxLevel)
		if luckLvl >= UpgradeConfig.Luck.MaxLevel then
			luckDesc.Text = ("MAX! Total luck +%d%%"):format(math.floor(state.TotalLuck * 100))
			luckBtn.Text = "MAX"
			luckBtn.BackgroundColor3 = UIUtil.Colors.Outline
		else
			local nextCost = UpgradeConfig.Luck.Levels[luckLvl + 1].GemCost
			luckDesc.Text = ("Better rare eggs & variants.\nNext: +%d%% luck")
				:format(math.floor(UpgradeConfig.Luck.Levels[luckLvl + 1].Value * 100))
			luckBtn.Text = ("%s 💎"):format(Format.short(nextCost))
			luckBtn.BackgroundColor3 = state.Gems >= nextCost and UIUtil.Colors.Gem or UIUtil.Colors.Outline
		end

		-- Hatch Speed
		local hsLvl = state.HatchSpeedLevel
		hsTitle.Text = ("⚡ Hatch Speed  (Lv %d/%d)"):format(hsLvl, UpgradeConfig.HatchSpeed.MaxLevel)
		if hsLvl >= UpgradeConfig.HatchSpeed.MaxLevel then
			hsDesc.Text = ("MAX! -%d%% incubation (cap)"):format(math.floor(state.HatchReduction * 100))
			hsBtn.Text = "MAX"
			hsBtn.BackgroundColor3 = UIUtil.Colors.Outline
		else
			local nextCost = UpgradeConfig.HatchSpeed.Levels[hsLvl + 1].GemCost
			local nextRed = UpgradeConfig.HatchSpeed.Levels[hsLvl + 1].Reduction
			hsDesc.Text = ("Faster hatching (cap 50%%).\nNext: -%d%% time"):format(math.floor(nextRed * 100))
			hsBtn.Text = ("%s 💎"):format(Format.short(nextCost))
			hsBtn.BackgroundColor3 = state.Gems >= nextCost and UIUtil.Colors.Gem or UIUtil.Colors.Outline
		end

		-- Plots
		plotTitle.Text = ("🏠 Plots  (%d/%d)"):format(state.Plots, state.MaxPlots)
		if state.Plots >= state.MaxPlots then
			plotDesc.Text = "All plots owned!"
			plotBtn.Text = "MAX"
			plotBtn.BackgroundColor3 = UIUtil.Colors.Outline
		else
			plotDesc.Text = "Display & earn from more brainrots."
			plotBtn.Text = ("$%s"):format(Format.short(state.NextPlotCost))
			plotBtn.BackgroundColor3 = state.Cash >= state.NextPlotCost and UIUtil.Colors.Good or UIUtil.Colors.Outline
		end
	end)

	return modal
end

return Shop
