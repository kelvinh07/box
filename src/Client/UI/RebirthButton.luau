--!strict
-- RebirthButton
-- A transparent icon button at the BOTTOM of the left column (below the Collection icon).
-- Clicking it toggles the Rebirth modal. When a rebirth is available (state.RebirthReady)
-- the icon gently pulses to draw attention. Image/size match the other left-column icons.

local TweenService = game:GetService("TweenService")

local UIUtil = require(script.Parent.Parent.UIUtil)
local ClientState = require(script.Parent.Parent.ClientState)

local RebirthButton = {}

local ICON = "rbxassetid://131288789741903"

function RebirthButton.build(gui: ScreenGui, onClick: () -> ())
	local btn = UIUtil.button({
		Name = "RebirthButton",
		Size = UDim2.new(0, 64, 0, 64),
		-- below Collection (Collection sits +85 below the Backpack center)
		Position = UDim2.new(0, 16, 0.5, 170),
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

	-- gentle "rebirth ready" pulse on the icon
	local pulse = Instance.new("UIScale")
	pulse.Parent = img
	local pulseTween: Tween? = nil
	ClientState.onChanged(function(state)
		if not state then return end
		if state.RebirthReady then
			if not pulseTween then
				pulse.Scale = 1
				pulseTween = TweenService:Create(
					pulse,
					TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Scale = 1.12 }
				)
				;(pulseTween :: Tween):Play()
			end
		elseif pulseTween then
			pulseTween:Cancel()
			pulseTween = nil
			pulse.Scale = 1
		end
	end)

	btn.MouseButton1Click:Connect(onClick)
end

return RebirthButton
