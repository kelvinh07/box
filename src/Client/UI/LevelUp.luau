--!strict
-- LevelUp
-- A modal that opens when the LOCAL player clicks one of their brainrots on its
-- podium. The server tags every placed brainrot model "Brainrot", stamps a
-- BrainrotId attribute, and parents a ClickDetector to it; this client module
-- listens for those tagged models, connects each ClickDetector.MouseClick
-- locally (ClickDetector fires client-side for the clicker), looks the brainrot
-- up in the snapshot Collection, and shows a level-up panel.
--
-- The panel previews the income gain from the NEXT level and shows the exact
-- cost (Cash for levels 2-5, Gems for 6-10), scaled by the rebirth
-- levelCostMultiplier. Leveling is validated server-side via the LevelBrainrot
-- remote; the panel just reflects the snapshot and re-renders on every push.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage.Shared
local RarityColors = require(Shared.Config.RarityColors)
local BrainrotConfig = require(Shared.Config.BrainrotConfig)
local BrainrotMath = require(Shared.Modules.BrainrotMath)
local Format = require(Shared.Modules.Format)
local Util = require(Shared.Modules.Util)

local UIUtil = require(script.Parent.Parent.UIUtil)
local ClientState = require(script.Parent.Parent.ClientState)
local ClientNet = require(script.Parent.Parent.ClientNet)
local Sounds = require(script.Parent.Parent.Sounds)

local BRAINROT_TAG = "Brainrot"

local LevelUp = {}

-- the BrainrotId currently shown in the open panel (nil = panel closed)
local openId: string? = nil

-- find the owning entry for a brainrot id in the latest snapshot
local function findEntry(state: any, id: string): any?
	if not state or not state.Collection then
		return nil
	end
	for _, e in ipairs(state.Collection) do
		if e.id == id then
			return e
		end
	end
	return nil
end

-- the per-currency cost string ("$1.5K" vs "300 💎")
local function costText(cost: number, currency: string): string
	if currency == "Gems" then
		return ("%s 💎"):format(Format.short(cost))
	end
	return ("$%s"):format(Format.short(cost))
end

function LevelUp.start(gui: ScreenGui)
	local modal = UIUtil.modal(gui, "⬆️ Level Up", UDim2.new(0, 480, 0, 430))

	-- name + current level
	local nameLabel = UIUtil.label({
		Size = UDim2.new(1, -16, 0, 40),
		Text = "",
		LayoutOrder = 1,
		Parent = modal.content,
	})
	nameLabel.ZIndex = 22

	local levelLabel = UIUtil.label({
		Size = UDim2.new(1, -16, 0, 34),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 235, 130),
		LayoutOrder = 2,
		Parent = modal.content,
	})
	levelLabel.ZIndex = 22

	-- current income
	local nowLabel = UIUtil.label({
		Size = UDim2.new(1, -16, 0, 32),
		Text = "",
		LayoutOrder = 3,
		Parent = modal.content,
	})
	nowLabel.ZIndex = 22

	-- next-level income preview
	local nextLabel = UIUtil.label({
		Size = UDim2.new(1, -16, 0, 32),
		Text = "",
		TextColor3 = UIUtil.Colors.Good,
		LayoutOrder = 4,
		Parent = modal.content,
	})
	nextLabel.ZIndex = 22

	-- LEVEL UP button (also doubles as the cost / status readout)
	local btn = UIUtil.button({
		Size = UDim2.new(1, -16, 0, 70),
		BackgroundColor3 = UIUtil.Colors.Good,
		Text = "LEVEL UP",
		TextSize = 28,
		LayoutOrder = 5,
		Parent = modal.content,
	})
	btn.ZIndex = 22

	-- Render the panel for `openId` from a snapshot. Closes the panel if the
	-- brainrot no longer exists (e.g. it was sold).
	local function render(state: any)
		if not openId then
			return
		end
		local entry = findEntry(state, openId)
		if not entry then
			-- the brainrot is gone — close out
			openId = nil
			modal.setVisible(false)
			return
		end

		local level = entry.level or 1
		local rebirths = state.Rebirths or 0
		nameLabel.Text = entry.base
		nameLabel.TextColor3 = RarityColors.tier(entry.tier)
		levelLabel.Text = ("Level %d / %d"):format(level, BrainrotConfig.MaxLevel)

		local cashNow, gemNow = BrainrotMath.income(entry, rebirths)
		nowLabel.Text = ("Now: $%s/s%s"):format(
			Format.short(cashNow),
			gemNow > 0 and ("  +%s💎/s"):format(Format.short(gemNow)) or ""
		)

		if level >= BrainrotConfig.MaxLevel then
			nextLabel.Text = "Max level reached!"
			nextLabel.TextColor3 = UIUtil.Colors.Warn
			btn.Text = "MAX LEVEL"
			btn.BackgroundColor3 = UIUtil.Colors.PanelLight
			return
		end

		-- preview the NEXT level's income off a shallow copy with level+1
		local previewEntry = Util.shallowCopy(entry)
		previewEntry.level = level + 1
		local cashNext, gemNext = BrainrotMath.income(previewEntry, rebirths)
		nextLabel.TextColor3 = UIUtil.Colors.Good
		nextLabel.Text = ("Next (Lv %d): $%s/s%s"):format(
			level + 1,
			Format.short(cashNext),
			gemNext > 0 and ("  +%s💎/s"):format(Format.short(gemNext)) or ""
		)

		-- exact cost = floor(base cost * levelCostMultiplier), currency per target level
		local baseCost, currency = BrainrotConfig.levelUpCost(level + 1)
		local mult = state.LevelCostMultiplier or 1
		local cost = math.floor(baseCost * mult)
		local have = currency == "Gems" and (state.Gems or 0) or (state.Cash or 0)
		local affordable = have >= cost

		btn.Text = ("LEVEL UP  %s"):format(costText(cost, currency))
		if affordable then
			btn.BackgroundColor3 = currency == "Gems" and UIUtil.Colors.Gem or UIUtil.Colors.Good
		else
			-- cannot afford: muted panel tone (NOT the near-black outline color)
			btn.BackgroundColor3 = UIUtil.Colors.PanelLight
		end
	end

	btn.MouseButton1Click:Connect(function()
		if not openId then
			return
		end
		local state = ClientState.get()
		local entry = findEntry(state, openId)
		if not entry then
			return
		end
		if (entry.level or 1) >= BrainrotConfig.MaxLevel then
			return
		end
		local r = ClientNet.invoke("LevelBrainrot", openId)
		if r and r.ok then
			Sounds.play("Purchase")
		end
	end)

	-- keep the open panel in sync with every server push
	ClientState.onChanged(render)

	-- open the panel for a clicked brainrot id
	local function openFor(id: string)
		local state = ClientState.get()
		if not findEntry(state, id) then
			return
		end
		openId = id
		render(state)
		modal.setVisible(true)
	end

	-- wire a single brainrot model's ClickDetector (once)
	local wired: { [Instance]: boolean } = {}
	local function wireModel(model: Instance)
		if wired[model] then
			return
		end
		local click = model:FindFirstChildWhichIsA("ClickDetector", true)
		if not click then
			-- The server tags the model BEFORE the ClickDetector child has
			-- replicated, so the detector frequently isn't here yet. Poll briefly
			-- (~5s) for it to arrive instead of giving up forever; the wired[model]
			-- guard and the re-check at the top of wireModel prevent double-wiring.
			task.spawn(function()
				for _ = 1, 50 do
					if wired[model] or model.Parent == nil then
						return
					end
					if model:FindFirstChildWhichIsA("ClickDetector", true) then
						wireModel(model)
						return
					end
					task.wait(0.1)
				end
			end)
			return
		end
		wired[model] = true
		click.MouseClick:Connect(function()
			local id = model:GetAttribute("BrainrotId")
			if typeof(id) == "string" then
				openFor(id)
			end
		end)
		model.AncestryChanged:Connect(function(_, parent)
			if not parent then
				wired[model] = nil
			end
		end)
	end

	for _, model in ipairs(CollectionService:GetTagged(BRAINROT_TAG)) do
		wireModel(model)
	end
	CollectionService:GetInstanceAddedSignal(BRAINROT_TAG):Connect(function(model)
		wireModel(model)
	end)
end

return LevelUp
