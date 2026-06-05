--!strict
-- Stands
-- The three upgrade panels, each opened INSTANTLY by walking up to its in-world
-- stand and pressing E. This replaces the old central Shop modal — plots are now
-- bought at the base ghost-podium, and the gem/cash upgrades live here:
--   🪓 Shovel Shop  (Cash/Gems → dig speed),  🔥 Incubator (Cash/Gems → hatch
--   speed),  🍀 Luck (Gems → luck).
--
-- Each panel shows the FULL tier progression (a card per tier) so the player can
-- see what's coming, plus one BUY button that purchases the NEXT tier. Tiers can
-- cost EITHER Cash ($) or Gems (💎) — the card + BUY button show the right icon and
-- check affordability against the matching currency. All purchases are validated
-- server-side; the panel just reflects the snapshot.

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

-- A tier as the panels consume it: a display name, an effect string, and a cost
-- with its currency. Built per-panel from the relevant config below.
type Tier = {
	name: string,
	effect: string,
	cost: number,
	currency: string, -- "Cash" | "Gems"
}

-- the per-currency cost string ("$1.5K" vs "300 💎")
local function costText(cost: number, currency: string): string
	if currency == "Gems" then
		return ("%s 💎"):format(Format.short(cost))
	end
	return ("$%s"):format(Format.short(cost))
end

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

	-- cost (right) — shows '$' for Cash tiers, '💎' for Gem tiers
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

------------------------------------------------------------------- generic panel
-- Builds one upgrade panel from a list of Tiers. `getLevel(state)` reads the
-- player's current tier from the snapshot; `remote` is the purchase remote.
-- Each tier carries its own currency, so the BUY button checks affordability
-- against Cash or Gems as appropriate and shows the matching icon.
local function buildPanel(
	gui: ScreenGui,
	title: string,
	tiers: { Tier },
	getLevel: (any) -> number,
	remote: string
)
	local modal = UIUtil.modal(gui, title, UDim2.new(0, 560, 0, 540))
	local maxLevel = #tiers

	local cards: { Frame } = {}
	local statuses: { TextLabel } = {}
	for i = 1, maxLevel do
		local tier = tiers[i]
		local card, name, effect, cost, status = tierCard(modal.content, i)
		name.Text = ("%d. %s"):format(i, tier.name)
		effect.Text = tier.effect
		cost.Text = costText(tier.cost, tier.currency)
		cost.TextColor3 = tier.currency == "Gems" and UIUtil.Colors.Gem or UIUtil.Colors.Good
		cards[i] = card
		statuses[i] = status
	end

	local btn = buyButton(modal.content, maxLevel + 1)
	btn.MouseButton1Click:Connect(function()
		local r = ClientNet.invoke(remote)
		if r and r.ok then Sounds.play("Purchase") end
	end)

	ClientState.onChanged(function(state)
		if not state then return end
		local level = getLevel(state)
		for i = 1, maxLevel do
			paintTier(cards[i], statuses[i], i, level)
		end
		if level >= maxLevel then
			btn.Text = "MAX"
			btn.BackgroundColor3 = UIUtil.Colors.PanelLight
			return
		end
		local nextTier = tiers[level + 1]
		local have = nextTier.currency == "Gems" and state.Gems or state.Cash
		local affordable = have >= nextTier.cost
		btn.Text = ("Buy %s  %s"):format(nextTier.name, costText(nextTier.cost, nextTier.currency))
		if affordable then
			btn.BackgroundColor3 = nextTier.currency == "Gems" and UIUtil.Colors.Gem or UIUtil.Colors.Good
		else
			-- cannot afford: a muted panel tone (NOT the near-black outline color)
			btn.BackgroundColor3 = UIUtil.Colors.PanelLight
		end
	end)

	return modal
end

------------------------------------------------------------------- tier sources
-- Shovel: 9 tiers from ShovelConfig (Cash 1-5, Gems 6-9), effect = dig multiplier.
local function shovelTiers(): { Tier }
	local out: { Tier } = {}
	for i = 1, ShovelConfig.MaxLevel do
		local lvl = ShovelConfig.Levels[i]
		out[i] = {
			name = lvl.Name,
			effect = ("Dig x%s"):format(lvl.DigSpeedMult),
			cost = lvl.Cost,
			currency = lvl.Currency,
		}
	end
	return out
end

-- Incubator: 9 named tiers from UpgradeConfig.Incubator (Cash 1-5, Gems 6-9),
-- effect = incubation-time reduction.
local function incubatorTiers(): { Tier }
	local out: { Tier } = {}
	for i = 1, UpgradeConfig.Incubator.MaxLevel do
		local lvl = UpgradeConfig.Incubator.Levels[i]
		out[i] = {
			name = lvl.Name,
			effect = ("-%d%% time"):format(math.floor(lvl.Reduction * 100)),
			cost = lvl.Cost,
			currency = lvl.Currency,
		}
	end
	return out
end

-- Luck: 9 tiers from UpgradeConfig.Luck (all Gems), effect = +luck value.
local function luckTiers(): { Tier }
	local out: { Tier } = {}
	for i = 1, UpgradeConfig.Luck.MaxLevel do
		local lvl = UpgradeConfig.Luck.Levels[i]
		out[i] = {
			name = ("Luck Lv %d"):format(i),
			effect = ("+%d%% luck"):format(math.floor(lvl.Value * 100)),
			cost = lvl.GemCost,
			currency = "Gems",
		}
	end
	return out
end

------------------------------------------------------------------- start
-- Builds the three panels (all start hidden) and wires the proximity listener so
-- a single E press on a tagged stand opens the matching panel instantly.
function Stands.start(gui: ScreenGui)
	local shovelModal = buildPanel(gui, "🪓 Shovel Shop", shovelTiers(), function(s)
		return s.ShovelLevel
	end, "UpgradeShovel")

	local incubatorModal = buildPanel(gui, "🔥 Incubator", incubatorTiers(), function(s)
		return s.IncubatorLevel
	end, "UpgradeIncubator")

	local luckModal = buildPanel(gui, "🍀 Luck", luckTiers(), function(s)
		return s.LuckLevel
	end, "UpgradeLuck")

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, plr: Player)
		if plr ~= LocalPlayer then return end
		local t = prompt:GetAttribute("StandType")
		if t == "Shovel" then
			shovelModal.setVisible(true)
		elseif t == "Incubator" then
			incubatorModal.setVisible(true)
		elseif t == "Luck" then
			luckModal.setVisible(true)
		end
	end)
end

return Stands
