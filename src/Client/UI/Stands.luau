--!strict
-- Stands
-- The three upgrade panels, each opened INSTANTLY by walking up to its in-world
-- stand and pressing E. This replaces the old central Shop modal — plots are now
-- bought at the base ghost-podium, and the gem/cash upgrades live here:
--   🪓 Shovel Shop  (Cash → dig speed),  🔥 Hatch Nests (Gems → hatch speed),
--   🍀 Luck (Gems → luck).
--
-- Each panel shows the FULL named tier progression (a card per tier) so the player
-- can see what's coming, plus one BUY button that purchases the NEXT tier. All
-- purchases are validated server-side; the panel just reflects the snapshot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage.Shared
local UpgradeConfig = require(Shared.Config.UpgradeConfig)
local ShovelConfig = require(Shared.Config.ShovelConfig)
local Format = require(Shared.Modules.Format)

local UIUtil = require(script.Parent.Parent.UIUtil)
local ClientState = require(script.Parent.Parent.ClientState)
local ClientNet = require(script.Parent.Parent.ClientNet)
local Sounds = require(script.Parent.Parent.Sounds)

local LocalPlayer = Players.LocalPlayer

local Stands = {}

------------------------------------------------------------------- tier card
-- One row describing a single tier. Returns the card plus its name/effect/cost
-- labels and a small "owned/next" status pill so the panel can keep them in sync.
local function tierCard(parent: Instance, order: number): (Frame, TextLabel, TextLabel, TextLabel, TextLabel)
	local card = UIUtil.frame({
		Size = UDim2.new(1, -8, 0, 56),
		BackgroundColor3 = UIUtil.Colors.PanelLight,
		LayoutOrder = order,
		Parent = parent,
	})
	card.ZIndex = 22
	UIUtil.corner(card, 12)
	UIUtil.stroke(card, 2)

	-- name (left)
	local name = UIUtil.label({
		Size = UDim2.new(0.40, 0, 1, -10),
		Position = UDim2.new(0, 12, 0, 5),
		Text = "",
		Parent = card,
	})
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.ZIndex = 23

	-- effect (middle)
	local effect = UIUtil.label({
		Size = UDim2.new(0.30, 0, 1, -10),
		Position = UDim2.new(0.40, 0, 0, 5),
		Text = "",
		TextColor3 = Color3.fromRGB(200, 205, 220),
		Parent = card,
	})
	effect.TextXAlignment = Enum.TextXAlignment.Left
	effect.ZIndex = 23

	-- cost (right)
	local cost = UIUtil.label({
		Size = UDim2.new(0.22, 0, 1, -10),
		Position = UDim2.new(0.70, 0, 0, 5),
		Text = "",
		Parent = card,
	})
	cost.TextXAlignment = Enum.TextXAlignment.Right
	cost.ZIndex = 23

	-- status pill (far right): ✓ owned / ➤ next / blank
	local status = UIUtil.label({
		Size = UDim2.new(0.07, 0, 1, -10),
		Position = UDim2.new(0.93, 0, 0, 5),
		Text = "",
		Parent = card,
	})
	status.ZIndex = 23

	return card, name, effect, cost, status
end

-- recolor a tier card by its state relative to the player's current level
local function paintTier(card: Frame, status: TextLabel, index: number, level: number)
	if index <= level then
		-- owned
		card.BackgroundColor3 = Color3.fromRGB(36, 58, 40)
		status.Text = "✓"
		status.TextColor3 = UIUtil.Colors.Good
	elseif index == level + 1 then
		-- next buyable
		card.BackgroundColor3 = Color3.fromRGB(58, 52, 30)
		status.Text = "➤"
		status.TextColor3 = UIUtil.Colors.Warn
	else
		-- locked / future
		card.BackgroundColor3 = UIUtil.Colors.PanelLight
		status.Text = ""
		status.TextColor3 = UIUtil.Colors.Text
	end
end

-- a chunky BUY button pinned as the last item in the scrolling tier list
local function buyButton(parent: Instance, order: number): TextButton
	local btn = UIUtil.button({
		Size = UDim2.new(1, -8, 0, 64),
		BackgroundColor3 = UIUtil.Colors.Good,
		Text = "BUY",
		TextSize = 26,
		LayoutOrder = order,
		Parent = parent,
	})
	btn.ZIndex = 23
	return btn
end

------------------------------------------------------------------- panels
-- Shovel (Cash → dig speed)
local function buildShovel(gui: ScreenGui)
	local modal = UIUtil.modal(gui, "🪓 Shovel Shop", UDim2.new(0, 560, 0, 540))

	local cards: { Frame } = {}
	local statuses: { TextLabel } = {}
	for i = 1, ShovelConfig.MaxLevel do
		local lvl = ShovelConfig.Levels[i]
		local card, name, effect, cost, status = tierCard(modal.content, i)
		name.Text = ("%d. %s"):format(i, lvl.Name)
		effect.Text = ("Dig x%s"):format(lvl.DigSpeedMult)
		cost.Text = ("$%s"):format(Format.short(lvl.CashCost))
		cards[i] = card
		statuses[i] = status
	end

	local btn = buyButton(modal.content, ShovelConfig.MaxLevel + 1)
	btn.MouseButton1Click:Connect(function()
		local r = ClientNet.invoke("UpgradeShovel")
		if r and r.ok then Sounds.play("Purchase") end
	end)

	ClientState.onChanged(function(state)
		if not state then return end
		local level = state.ShovelLevel
		for i = 1, ShovelConfig.MaxLevel do
			paintTier(cards[i], statuses[i], i, level)
		end
		if level >= ShovelConfig.MaxLevel then
			btn.Text = "MAX"
			btn.BackgroundColor3 = UIUtil.Colors.Outline
		else
			local nextLvl = ShovelConfig.Levels[level + 1]
			btn.Text = ("Buy %s  $%s"):format(nextLvl.Name, Format.short(nextLvl.CashCost))
			btn.BackgroundColor3 = state.Cash >= nextLvl.CashCost and UIUtil.Colors.Good or UIUtil.Colors.Outline
		end
	end)

	return modal
end

-- Hatch Speed (Gems → incubation reduction)
local function buildHatchSpeed(gui: ScreenGui)
	local modal = UIUtil.modal(gui, "🔥 Hatch Nests", UDim2.new(0, 560, 0, 540))

	local cards: { Frame } = {}
	local statuses: { TextLabel } = {}
	for i = 1, UpgradeConfig.HatchSpeed.MaxLevel do
		local lvl = UpgradeConfig.HatchSpeed.Levels[i]
		local card, name, effect, cost, status = tierCard(modal.content, i)
		name.Text = ("%d. %s"):format(i, lvl.Name)
		effect.Text = ("-%d%% time"):format(math.floor(lvl.Reduction * 100))
		cost.Text = ("%s 💎"):format(Format.short(lvl.GemCost))
		cards[i] = card
		statuses[i] = status
	end

	local btn = buyButton(modal.content, UpgradeConfig.HatchSpeed.MaxLevel + 1)
	btn.MouseButton1Click:Connect(function()
		local r = ClientNet.invoke("UpgradeHatchSpeed")
		if r and r.ok then Sounds.play("Purchase") end
	end)

	ClientState.onChanged(function(state)
		if not state then return end
		local level = state.HatchSpeedLevel
		for i = 1, UpgradeConfig.HatchSpeed.MaxLevel do
			paintTier(cards[i], statuses[i], i, level)
		end
		if level >= UpgradeConfig.HatchSpeed.MaxLevel then
			btn.Text = "MAX"
			btn.BackgroundColor3 = UIUtil.Colors.Outline
		else
			local nextLvl = UpgradeConfig.HatchSpeed.Levels[level + 1]
			btn.Text = ("Buy %s  %s 💎"):format(nextLvl.Name, Format.short(nextLvl.GemCost))
			btn.BackgroundColor3 = state.Gems >= nextLvl.GemCost and UIUtil.Colors.Gem or UIUtil.Colors.Outline
		end
	end)

	return modal
end

-- Luck (Gems → luck value)
local function buildLuck(gui: ScreenGui)
	local modal = UIUtil.modal(gui, "🍀 Luck", UDim2.new(0, 560, 0, 540))

	local cards: { Frame } = {}
	local statuses: { TextLabel } = {}
	for i = 1, UpgradeConfig.Luck.MaxLevel do
		local lvl = UpgradeConfig.Luck.Levels[i]
		local card, name, effect, cost, status = tierCard(modal.content, i)
		name.Text = ("Luck Lv %d"):format(i)
		effect.Text = ("+%d%% luck"):format(math.floor(lvl.Value * 100))
		cost.Text = ("%s 💎"):format(Format.short(lvl.GemCost))
		cards[i] = card
		statuses[i] = status
	end

	local btn = buyButton(modal.content, UpgradeConfig.Luck.MaxLevel + 1)
	btn.MouseButton1Click:Connect(function()
		local r = ClientNet.invoke("UpgradeLuck")
		if r and r.ok then Sounds.play("Purchase") end
	end)

	ClientState.onChanged(function(state)
		if not state then return end
		local level = state.LuckLevel
		for i = 1, UpgradeConfig.Luck.MaxLevel do
			paintTier(cards[i], statuses[i], i, level)
		end
		if level >= UpgradeConfig.Luck.MaxLevel then
			btn.Text = "MAX"
			btn.BackgroundColor3 = UIUtil.Colors.Outline
		else
			local nextLvl = UpgradeConfig.Luck.Levels[level + 1]
			btn.Text = ("Buy Lv %d  %s 💎"):format(level + 1, Format.short(nextLvl.GemCost))
			btn.BackgroundColor3 = state.Gems >= nextLvl.GemCost and UIUtil.Colors.Gem or UIUtil.Colors.Outline
		end
	end)

	return modal
end

------------------------------------------------------------------- start
-- Builds the three panels (all start hidden) and wires the proximity listener so
-- a single E press on a tagged stand opens the matching panel instantly.
function Stands.start(gui: ScreenGui)
	local shovelModal = buildShovel(gui)
	local hatchModal = buildHatchSpeed(gui)
	local luckModal = buildLuck(gui)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, plr: Player)
		if plr ~= LocalPlayer then return end
		local t = prompt:GetAttribute("StandType")
		if t == "Shovel" then
			shovelModal.setVisible(true)
		elseif t == "HatchSpeed" then
			hatchModal.setVisible(true)
		elseif t == "Luck" then
			luckModal.setVisible(true)
		end
	end)
end

return Stands
