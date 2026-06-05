--!strict
-- SideNav
-- Right-side vertical stack of chunky buttons that toggle the modal panels
-- (Shop, Collection, Rebirth). A small badge pulses on the Rebirth button when
-- a rebirth is available.

local UIUtil = require(script.Parent.Parent.UIUtil)
local ClientState = require(script.Parent.Parent.ClientState)

local SideNav = {}

-- buttons: array of { text, color, onClick }
function SideNav.build(gui: ScreenGui, buttons: { any })
	local holder = UIUtil.frame({
		Name = "SideNav",
		Size = UDim2.new(0, 88, 0, #buttons * 84),
		Position = UDim2.new(1, -12, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	UIUtil.listLayout(holder, 10)

	local rebirthBtn: TextButton? = nil
	for i, def in ipairs(buttons) do
		local btn = UIUtil.button({
			Size = UDim2.new(0, 84, 0, 74),
			BackgroundColor3 = def.color,
			Text = def.text,
			TextSize = 30,
			LayoutOrder = i,
			Parent = holder,
		})
		btn.MouseButton1Click:Connect(def.onClick)
		if def.id == "Rebirth" then
			rebirthBtn = btn
		end
	end

	-- pulse the rebirth button when ready
	if rebirthBtn then
		ClientState.onChanged(function(state)
			if not state then return end
			local stroke = rebirthBtn:FindFirstChildWhichIsA("UIStroke")
			if stroke then
				if state.RebirthReady then
					stroke.Color = UIUtil.Colors.Good
					stroke.Thickness = 5
				else
					stroke.Color = UIUtil.Colors.Outline
					stroke.Thickness = 3
				end
			end
		end)
	end
end

return SideNav
