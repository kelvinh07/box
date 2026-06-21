--!strict
-- Effects
-- All the "juice": toast notifications, floating "+$/+Gem" popups, the hatch
-- reveal card with particle burst, and camera screen-shake. Driven by server
-- RemoteEvents (Notify / FloatingText / HatchResult / ScreenShake).

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Net = require(Shared.Modules.Net)
local Format = require(Shared.Modules.Format)
local RarityColors = require(Shared.Config.RarityColors)
local BrainrotConfig = require(Shared.Config.BrainrotConfig)

local UIUtil = require(script.Parent.Parent.UIUtil)
local Sounds = require(script.Parent.Parent.Sounds)

local Effects = {}

local screenGui: ScreenGui

----------------------------------------------------------------- toasts
local function showToast(data: any)
	local color = RarityColors.tier(data.color or "Common") or UIUtil.Colors.Accent
	local toast = UIUtil.frame({
		Size = UDim2.new(0, 420, 0, 90),
		Position = UDim2.new(0.5, 0, 0.18, -120),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = UIUtil.Colors.Panel,
		Parent = screenGui,
	})
	toast.ZIndex = 80
	UIUtil.corner(toast, 16)
	UIUtil.stroke(toast, 4, color)

	local title = UIUtil.label({
		Size = UDim2.new(1, -16, 0.45, 0),
		Position = UDim2.new(0, 8, 0, 6),
		Text = data.title or "Notice",
		TextColor3 = color,
		Parent = toast,
	})
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 81
	local body = UIUtil.label({
		Size = UDim2.new(1, -16, 0.45, 0),
		Position = UDim2.new(0, 8, 0.5, 0),
		Text = data.text or "",
		Parent = toast,
	})
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.ZIndex = 81

	UIUtil.pop(toast)
	TweenService:Create(toast, TweenInfo.new(0.4), { Position = UDim2.new(0.5, 0, 0.18, 0) }):Play()
	task.delay(3, function()
		local t = TweenService:Create(toast, TweenInfo.new(0.4), {
			Position = UDim2.new(0.5, 0, 0.18, -120),
			BackgroundTransparency = 1,
		})
		t.Completed:Connect(function() toast:Destroy() end)
		t:Play()
	end)
end

----------------------------------------------------------------- floating + text
local function floatingText(data: any)
	local parts = {}
	if data.cash and data.cash > 0 then
		table.insert(parts, { text = "+$" .. Format.short(data.cash), color = UIUtil.Colors.Good })
	end
	if data.gems and data.gems > 0 then
		table.insert(parts, { text = "+" .. Format.short(data.gems) .. "💎", color = UIUtil.Colors.Gem })
	end
	for i, part in ipairs(parts) do
		local lbl = UIUtil.label({
			Size = UDim2.new(0, 160, 0, 50),
			Position = UDim2.new(0.5, math.random(-120, 120), 0.62, (i - 1) * -40),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Text = part.text,
			TextColor3 = part.color,
			Parent = screenGui,
		})
		lbl.ZIndex = 50
		local goal = lbl.Position + UDim2.new(0, 0, -0.12, 0)
		local t = TweenService:Create(lbl, TweenInfo.new(1.1, Enum.EasingStyle.Quad), {
			Position = goal,
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		t.Completed:Connect(function() lbl:Destroy() end)
		t:Play()
	end
end

----------------------------------------------------------------- hatch reveal
local function hatchReveal(entry: any)
	Sounds.play("Hatch")
	local tierColor = RarityColors.tier(entry.tier)
	local variantColor = RarityColors.variant(entry.variant)

	local card = UIUtil.frame({
		Size = UDim2.new(0, 360, 0, 360),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = UIUtil.Colors.Panel,
		Parent = screenGui,
	})
	card.ZIndex = 60
	UIUtil.corner(card, 24)
	UIUtil.stroke(card, 6, variantColor)
	UIUtil.gradient(card, UIUtil.Colors.PanelLight, UIUtil.Colors.Panel)

	local burst = UIUtil.label({
		Size = UDim2.new(1, 0, 0, 50),
		Position = UDim2.new(0, 0, 0.06, 0),
		Text = "✨ HATCHED! ✨",
		TextColor3 = variantColor,
		Parent = card,
	})
	burst.ZIndex = 61

	-- big colored "blob" representing the brainrot
	local base = BrainrotConfig.get(entry.base)
	local blob = UIUtil.frame({
		Size = UDim2.new(0, 150, 0, 150),
		Position = UDim2.new(0.5, 0, 0.42, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = base and base.Color or tierColor,
		Parent = card,
	})
	blob.ZIndex = 61
	UIUtil.corner(blob, 75)
	UIUtil.stroke(blob, 5, variantColor)

	local nameLabel = UIUtil.label({
		Size = UDim2.new(1, -20, 0, 44),
		Position = UDim2.new(0, 10, 0.68, 0),
		Text = entry.base,
		TextColor3 = tierColor,
		Parent = card,
	})
	nameLabel.ZIndex = 61
	local variantLabel = UIUtil.label({
		Size = UDim2.new(1, -20, 0, 38),
		Position = UDim2.new(0, 10, 0.82, 0),
		Text = ("%s  •  %s"):format(entry.variant, entry.tier),
		TextColor3 = variantColor,
		Parent = card,
	})
	variantLabel.ZIndex = 61

	UIUtil.pop(card)
	-- spin the blob
	task.spawn(function()
		local r = 0
		while card.Parent do
			r += 6
			blob.Rotation = math.sin(math.rad(r)) * 8
			task.wait(0.03)
		end
	end)

	task.delay(2.2, function()
		local t = TweenService:Create(card, TweenInfo.new(0.3), {
			Size = UDim2.new(0, 0, 0, 0),
			BackgroundTransparency = 1,
		})
		t.Completed:Connect(function() card:Destroy() end)
		t:Play()
	end)
end

----------------------------------------------------------------- offline earnings
-- "Welcome back" screen shown once on join: how much Cash/Gems the player earned while away.
-- Deliberately shows ONLY the amounts (never the offline time). Server sends this via the
-- OfflineEarnings remote (see EconomyManager.applyOfflineEarnings).
local function offlineEarnings(data: any)
	local cash = (data and data.cash) or 0
	local gems = (data and data.gems) or 0
	if cash <= 0 and gems <= 0 then
		return
	end
	Sounds.play("Purchase")

	-- dim backdrop that blocks input behind the card until it's collected
	local backdrop = UIUtil.frame({
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		Parent = screenGui,
	})
	backdrop.ZIndex = 90

	local card = UIUtil.frame({
		Size = UDim2.new(0, 380, 0, 320),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = UIUtil.Colors.Panel,
		Parent = screenGui,
	})
	card.ZIndex = 91
	UIUtil.corner(card, 24)
	UIUtil.stroke(card, 6, UIUtil.Colors.Accent)
	UIUtil.gradient(card, UIUtil.Colors.PanelLight, UIUtil.Colors.Panel)

	local title = UIUtil.label({
		Size = UDim2.new(1, -20, 0, 52),
		Position = UDim2.new(0, 10, 0.05, 0),
		Text = "👋 WELCOME BACK!",
		TextColor3 = UIUtil.Colors.Accent,
		Parent = card,
	})
	title.ZIndex = 92

	local sub = UIUtil.label({
		Size = UDim2.new(1, -30, 0, 30),
		Position = UDim2.new(0, 15, 0.27, 0),
		Text = "While you were away you earned:",
		TextScaled = false,
		TextSize = 20,
		Parent = card,
	})
	sub.ZIndex = 92

	-- earning lines, stacked + centered (only the currencies that are > 0)
	local lines = UIUtil.frame({
		Size = UDim2.new(1, -30, 0, 110),
		Position = UDim2.new(0.5, 0, 0.55, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = card,
	})
	lines.ZIndex = 92
	UIUtil.listLayout(lines, 6)
	if cash > 0 then
		local c = UIUtil.label({
			Size = UDim2.new(1, 0, 0, 50),
			Text = "+$" .. Format.short(cash),
			TextColor3 = UIUtil.Colors.Good,
			Parent = lines,
		})
		c.ZIndex = 92
	end
	if gems > 0 then
		local g = UIUtil.label({
			Size = UDim2.new(1, 0, 0, 50),
			Text = "+" .. Format.short(gems) .. " 💎",
			TextColor3 = UIUtil.Colors.Gem,
			Parent = lines,
		})
		g.ZIndex = 92
	end

	local btn = UIUtil.button({
		Size = UDim2.new(0, 200, 0, 56),
		Position = UDim2.new(0.5, 0, 0.86, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = UIUtil.Colors.Good,
		Text = "Collect",
		Parent = card,
	})
	btn.ZIndex = 92
	btn.MouseButton1Click:Connect(function()
		local t = TweenService:Create(card, TweenInfo.new(0.25), {
			Size = UDim2.new(0, 0, 0, 0),
			BackgroundTransparency = 1,
		})
		t.Completed:Connect(function()
			card:Destroy()
			backdrop:Destroy()
		end)
		t:Play()
	end)

	UIUtil.pop(card)
end

----------------------------------------------------------------- screen shake
local function screenShake(variant: string?)
	local cam = Workspace.CurrentCamera
	if not cam then return end
	local intensity = (variant == "Galaxy" and 2.0)
		or (variant == "Diamond" and 1.4)
		or (variant == "Gold" and 1.0)
		or 0.6
	local elapsed = 0
	local conn
	conn = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		if elapsed > 0.4 then
			conn:Disconnect()
			return
		end
		local mag = intensity * (1 - elapsed / 0.4)
		cam.CFrame = cam.CFrame * CFrame.new(
			(math.random() - 0.5) * mag,
			(math.random() - 0.5) * mag,
			0
		)
	end)
end

----------------------------------------------------------------- public
function Effects.build(gui: ScreenGui)
	screenGui = gui
	Net.getEvent("Notify").OnClientEvent:Connect(showToast)
	Net.getEvent("FloatingText").OnClientEvent:Connect(floatingText)
	Net.getEvent("HatchResult").OnClientEvent:Connect(hatchReveal)
	Net.getEvent("ScreenShake").OnClientEvent:Connect(screenShake)
	Net.getEvent("OfflineEarnings").OnClientEvent:Connect(offlineEarnings)
end

-- exposed so other panels can throw a quick toast on remote failure
function Effects.toast(title: string, text: string, color: string?)
	showToast({ title = title, text = text, color = color })
end

return Effects
