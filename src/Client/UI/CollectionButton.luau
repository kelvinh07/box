--!strict
-- CollectionButton
-- An icon button on the LEFT, stacked just BELOW the 🎒 Backpack button (mirrors the 🏠
-- HomeButton above it). Clicking it toggles the Collection modal; hovering shows a
-- "see your brainrots" tooltip. The button itself is transparent (no colored box) so
-- only the icon shows, and the icon FILLS the 64x64 footprint to match the 🎒 / 🏠 icons.

local UIUtil = require(script.Parent.Parent.UIUtil)

local CollectionButton = {}

local ICON = "rbxassetid://129149615576198"

function CollectionButton.build(gui: ScreenGui, onClick: () -> ())
	local btn = UIUtil.button({
		Name = "CollectionButton",
		Size = UDim2.new(0, 64, 0, 64),
		-- the Backpack button is at (0,16, 0.5,0); sit 85px BELOW it (mirrors HomeButton above)
		Position = UDim2.new(0, 16, 0.5, 85),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1, -- no colored box; just the icon
		Text = "",
		Parent = gui,
	})
	-- drop the outline too so only the icon shows
	local s = btn:FindFirstChildWhichIsA("UIStroke")
	if s then s.Enabled = false end

	-- the icon fills the button and slightly OVERFLOWS it so it reads a touch bigger
	-- than the 🎒 / 🏠 icons (centered, so the overflow grows evenly on all sides)
	local img = Instance.new("ImageLabel")
	img.Name = "Icon"
	img.BackgroundTransparency = 1
	img.Image = ICON
	img.Size = UDim2.new(1, 40, 1, 40)
	img.Position = UDim2.new(0.5, 0, 0.5, 0)
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.ScaleType = Enum.ScaleType.Fit -- keeps the PNG's aspect ratio
	img.ZIndex = btn.ZIndex + 1
	img.Parent = btn

	-- hover tooltip to the RIGHT of the button
	local tip = UIUtil.frame({
		Name = "Tooltip",
		Size = UDim2.new(0, 196, 0, 34),
		Position = UDim2.new(1, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = UIUtil.Colors.Panel,
		Visible = false,
		Parent = btn,
	})
	tip.ZIndex = 50
	UIUtil.corner(tip, 10)
	UIUtil.stroke(tip, 2, UIUtil.Colors.Gem)
	local tipLbl = UIUtil.label({
		Size = UDim2.new(1, -12, 1, 0),
		Position = UDim2.new(0, 6, 0, 0),
		Text = "see your brainrots",
		Parent = tip,
	})
	tipLbl.ZIndex = 51

	btn.MouseEnter:Connect(function()
		tip.Visible = true
	end)
	btn.MouseLeave:Connect(function()
		tip.Visible = false
	end)

	btn.MouseButton1Click:Connect(onClick)
end

return CollectionButton
