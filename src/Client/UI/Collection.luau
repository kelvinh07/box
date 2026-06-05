--!strict
-- Collection
-- Brainrot collection viewer. Shows every owned brainrot grouped by tier, each
-- card colored by its variant (Gold/Diamond/Galaxy get a glowing colored border
-- + label) with its live income. Includes a Sell button per brainrot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local RarityColors = require(Shared.Config.RarityColors)
local BrainrotConfig = require(Shared.Config.BrainrotConfig)
local BrainrotMath = require(Shared.Modules.BrainrotMath)
local Format = require(Shared.Modules.Format)

local UIUtil = require(script.Parent.Parent.UIUtil)
local ClientState = require(script.Parent.Parent.ClientState)
local ClientNet = require(script.Parent.Parent.ClientNet)
local Sounds = require(script.Parent.Parent.Sounds)

local Collection = {}

local TIER_ORDER = { "Common", "Uncommon", "Rare", "Legendary", "Mythic" }

local function makeCard(parent: Instance, entry: any, zone: number, order: number)
	local variantColor = RarityColors.variant(entry.variant)
	local tierColor = RarityColors.tier(entry.tier)
	local base = BrainrotConfig.get(entry.base)

	local card = UIUtil.frame({
		Size = UDim2.new(1, -8, 0, 76),
		BackgroundColor3 = UIUtil.Colors.PanelLight,
		LayoutOrder = order,
		Parent = parent,
	})
	card.ZIndex = 22
	UIUtil.corner(card, 12)
	-- variant-colored border = variant rarity language
	UIUtil.stroke(card, entry.variant == "Normal" and 2 or 4, variantColor)

	-- color swatch
	local swatch = UIUtil.frame({
		Size = UDim2.new(0, 56, 0, 56),
		Position = UDim2.new(0, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = base and base.Color or tierColor,
		Parent = card,
	})
	swatch.ZIndex = 23
	UIUtil.corner(swatch, 28)
	UIUtil.stroke(swatch, 3, variantColor)

	local nameLabel = UIUtil.label({
		Size = UDim2.new(0.55, 0, 0, 28),
		Position = UDim2.new(0, 76, 0, 8),
		Text = entry.base,
		TextColor3 = tierColor,
		Parent = card,
	})
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.ZIndex = 23

	local cash, gems = BrainrotMath.income(entry, zone)
	local sub = UIUtil.label({
		Size = UDim2.new(0.55, 0, 0, 30),
		Position = UDim2.new(0, 76, 0, 38),
		Text = ("[%s]  $%s/s%s"):format(
			entry.variant,
			Format.short(cash),
			gems > 0 and ("  +%s💎/s"):format(Format.short(gems)) or ""
		),
		TextColor3 = variantColor,
		Parent = card,
	})
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.ZIndex = 23

	local sell = UIUtil.button({
		Size = UDim2.new(0, 80, 0, 50),
		Position = UDim2.new(1, -90, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Color3.fromRGB(220, 90, 90),
		Text = "Sell",
		TextSize = 22,
		Parent = card,
	})
	sell.ZIndex = 23
	sell.MouseButton1Click:Connect(function()
		local r = ClientNet.invoke("SellBrainrot", entry.id)
		if r and r.ok then Sounds.play("Purchase", 0.8) end
	end)
end

function Collection.build(gui: ScreenGui)
	local modal = UIUtil.modal(gui, "📦 Collection", UDim2.new(0, 600, 0, 540))

	ClientState.onChanged(function(state)
		if not state then return end
		-- rebuild list
		for _, c in ipairs(modal.content:GetChildren()) do
			if c:IsA("Frame") or c:IsA("TextLabel") then
				c:Destroy()
			end
		end

		if #state.Collection == 0 then
			UIUtil.label({
				Size = UDim2.new(1, -8, 0, 60),
				Text = "No brainrots yet — go dig & hatch!",
				LayoutOrder = 1,
				Parent = modal.content,
			})
			return
		end

		-- group by tier
		local order = 0
		for _, tier in ipairs(TIER_ORDER) do
			local entries = {}
			for _, e in ipairs(state.Collection) do
				if e.tier == tier then
					table.insert(entries, e)
				end
			end
			if #entries > 0 then
				order += 1
				local heading = UIUtil.label({
					Size = UDim2.new(1, -8, 0, 34),
					Text = ("%s  (%d)"):format(tier, #entries),
					TextColor3 = RarityColors.tier(tier),
					LayoutOrder = order,
					Parent = modal.content,
				})
				heading.TextXAlignment = Enum.TextXAlignment.Left
				heading.ZIndex = 22
				for _, e in ipairs(entries) do
					order += 1
					makeCard(modal.content, e, state.CurrentZone, order)
				end
			end
		end
	end)

	return modal
end

return Collection
