--!strict
-- ShopsButton
-- A transparent icon button at the TOP of the left column (above the Teleport button).
-- Clicking it opens the ROBUX SHOP popup. The popup is intentionally EMPTY for now (just a
-- placeholder) — real Robux products get added later. Icon/size match the other left icons.
--
-- NOTE: ScreenGui uses ZIndexBehavior.Global, so popup content must sit at ZIndex >= the modal
-- panel/content (20/21) or it renders BEHIND the panel and looks empty.

local UIUtil = require(script.Parent.Parent.UIUtil)

local ShopsButton = {}

local ICON = "rbxassetid://77842674120153"

function ShopsButton.build(gui: ScreenGui)
	-- the icon button (transparent, no box; icon fills + overflows like the other left icons)
	local btn = UIUtil.button({
		Name = "ShopsButton",
		Size = UDim2.new(0, 64, 0, 64),
		-- the Backpack button is at (0,16, 0.5,0); sit 170px ABOVE it (above Teleport @ -85)
		Position = UDim2.new(0, 16, 0.5, -170),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1, -- no colored box; just the icon
		Text = "",
		Parent = gui,
	})
	local s = btn:FindFirstChildWhichIsA("UIStroke")
	if s then s.Enabled = false end

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

	-- the ROBUX SHOP popup — EMPTY for now (products added later)
	local modal = UIUtil.modal(gui, "🛒 Shop", UDim2.new(0, 460, 0, 480))

	-- light placeholder so the empty panel doesn't read as broken (remove when products land)
	local placeholder = UIUtil.label({
		Size = UDim2.new(1, -16, 0, 40),
		Text = "Coming soon!",
		TextColor3 = UIUtil.Colors.Text,
		LayoutOrder = 1,
		Parent = modal.content,
	})
	placeholder.ZIndex = 22

	btn.MouseButton1Click:Connect(function()
		modal.toggle()
	end)
end

return ShopsButton
