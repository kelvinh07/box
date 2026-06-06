--!strict
-- HomeButton
-- A 🏠 button on the LEFT, stacked just above the 🎒 Backpack button. Clicking it asks
-- the server (TeleportHome remote) to put the player back at their OWN base. Hovering the
-- icon shows a "Teleport Home" tooltip.

local UIUtil = require(script.Parent.Parent.UIUtil)
local ClientNet = require(script.Parent.Parent.ClientNet)
local Sounds = require(script.Parent.Parent.Sounds)

local HomeButton = {}

function HomeButton.build(gui: ScreenGui)
	local btn = UIUtil.button({
		Name = "HomeButton",
		Size = UDim2.new(0, 64, 0, 64),
		-- the Backpack button is at (0,16, 0.5,0); sit 72px above it (small gap)
		Position = UDim2.new(0, 16, 0.5, -72),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = UIUtil.Colors.Good,
		Text = "🏠",
		TextSize = 34,
		Parent = gui,
	})

	-- hover tooltip to the RIGHT of the button
	local tip = UIUtil.frame({
		Name = "Tooltip",
		Size = UDim2.new(0, 156, 0, 34),
		Position = UDim2.new(1, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = UIUtil.Colors.Panel,
		Visible = false,
		Parent = btn,
	})
	tip.ZIndex = 50
	UIUtil.corner(tip, 10)
	UIUtil.stroke(tip, 2, UIUtil.Colors.Good)
	local tipLbl = UIUtil.label({
		Size = UDim2.new(1, -12, 1, 0),
		Position = UDim2.new(0, 6, 0, 0),
		Text = "Teleport Home",
		Parent = tip,
	})
	tipLbl.ZIndex = 51

	btn.MouseEnter:Connect(function()
		tip.Visible = true
	end)
	btn.MouseLeave:Connect(function()
		tip.Visible = false
	end)

	btn.MouseButton1Click:Connect(function()
		local res = ClientNet.invoke("TeleportHome")
		if res and res.ok then
			Sounds.play("Sparkle")
		end
	end)
end

return HomeButton
