--!strict
-- UIUtil
-- Helpers for the chunky, bold, rounded "brainrot game" UI look: rounded
-- corners, thick outlines, gradients, scale-bounce tweens. Everything is built
-- in code so no .rbxmx assets are required.

local TweenService = game:GetService("TweenService")

local UIUtil = {}

UIUtil.Font = Enum.Font.FredokaOne
UIUtil.Colors = {
	Panel      = Color3.fromRGB(28, 30, 46),
	PanelLight = Color3.fromRGB(44, 47, 70),
	Accent     = Color3.fromRGB(255, 90, 175),
	Good       = Color3.fromRGB(70, 235, 95),
	Gem        = Color3.fromRGB(70, 205, 255),
	Warn       = Color3.fromRGB(255, 180, 40),
	Text       = Color3.fromRGB(255, 255, 255),
	Outline    = Color3.fromRGB(15, 16, 26),
}

function UIUtil.corner(parent: Instance, radius: number?): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 12)
	c.Parent = parent
	return c
end

function UIUtil.stroke(parent: Instance, thickness: number?, color: Color3?): UIStroke
	local s = Instance.new("UIStroke")
	s.Thickness = thickness or 3
	s.Color = color or UIUtil.Colors.Outline
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function UIUtil.gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end

function UIUtil.padding(parent: Instance, px: number)
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.Parent = parent
	return p
end

function UIUtil.frame(props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = UIUtil.Colors.Panel
	f.BorderSizePixel = 0
	for k, v in pairs(props) do
		(f :: any)[k] = v
	end
	return f
end

function UIUtil.label(props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = UIUtil.Font
	l.TextColor3 = UIUtil.Colors.Text
	l.TextStrokeTransparency = 0.4
	l.TextStrokeColor3 = UIUtil.Colors.Outline
	l.TextScaled = true
	for k, v in pairs(props) do
		(l :: any)[k] = v
	end
	return l
end

-- A chunky rounded button with outline + hover/press bounce + click sound hook.
function UIUtil.button(props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.BackgroundColor3 = UIUtil.Colors.Accent
	b.BorderSizePixel = 0
	b.Font = UIUtil.Font
	b.TextColor3 = UIUtil.Colors.Text
	b.TextStrokeTransparency = 0.3
	b.TextStrokeColor3 = UIUtil.Colors.Outline
	b.TextScaled = true
	b.AutoButtonColor = false
	for k, v in pairs(props) do
		(b :: any)[k] = v
	end
	UIUtil.corner(b, 14)
	UIUtil.stroke(b, 3)

	local baseSize = b.Size
	local function tweenScale(scale: number)
		local goal = UDim2.new(
			baseSize.X.Scale * scale, baseSize.X.Offset * scale,
			baseSize.Y.Scale * scale, baseSize.Y.Offset * scale
		)
		TweenService:Create(b, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Size = goal }):Play()
	end
	b.MouseEnter:Connect(function() tweenScale(1.06) end)
	b.MouseLeave:Connect(function() tweenScale(1.0) end)
	b.MouseButton1Down:Connect(function() tweenScale(0.94) end)
	b.MouseButton1Up:Connect(function() tweenScale(1.06) end)

	return b
end

-- one-shot scale "pop" for feedback
function UIUtil.pop(gui: GuiObject)
	local base = gui.Size
	local big = UDim2.new(base.X.Scale * 1.18, base.X.Offset * 1.18, base.Y.Scale * 1.18, base.Y.Offset * 1.18)
	local t1 = TweenService:Create(gui, TweenInfo.new(0.08), { Size = big })
	t1.Completed:Connect(function()
		TweenService:Create(gui, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = base }):Play()
	end)
	t1:Play()
end

-- A centered modal panel with a title bar, close button and a scrolling content
-- area. Returns the modal frame, the content frame, and show/hide/toggle helpers.
function UIUtil.modal(gui: Instance, title: string, size: UDim2?): any
	local root = UIUtil.frame({
		Name = title .. "Modal",
		Size = size or UDim2.new(0, 520, 0, 480),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = UIUtil.Colors.Panel,
		Visible = false,
		Parent = gui,
	})
	root.ZIndex = 20
	UIUtil.corner(root, 22)
	UIUtil.stroke(root, 5, UIUtil.Colors.Accent)
	UIUtil.gradient(root, UIUtil.Colors.PanelLight, UIUtil.Colors.Panel)

	local header = UIUtil.label({
		Size = UDim2.new(1, -70, 0, 50),
		Position = UDim2.new(0, 16, 0, 10),
		Text = title,
		TextColor3 = UIUtil.Colors.Accent,
		Parent = root,
	})
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.ZIndex = 21

	local close = UIUtil.button({
		Size = UDim2.new(0, 44, 0, 44),
		Position = UDim2.new(1, -52, 0, 10),
		BackgroundColor3 = Color3.fromRGB(220, 70, 80),
		Text = "✕",
		TextSize = 28,
		Parent = root,
	})
	close.ZIndex = 21

	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -24, 1, -76)
	content.Position = UDim2.new(0, 12, 0, 66)
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.ScrollBarThickness = 8
	content.CanvasSize = UDim2.new(0, 0, 0, 0)
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ZIndex = 21
	content.Parent = root
	UIUtil.listLayout(content, 10)
	UIUtil.padding(content, 6)

	local api = {}
	api.root = root
	api.content = content
	function api.setVisible(v: boolean)
		root.Visible = v
		if v then
			UIUtil.pop(root)
		end
	end
	function api.toggle()
		api.setVisible(not root.Visible)
	end
	close.MouseButton1Click:Connect(function()
		api.setVisible(false)
	end)
	return api
end

function UIUtil.listLayout(parent: Instance, padding: number?, dir: Enum.FillDirection?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, padding or 8)
	l.FillDirection = dir or Enum.FillDirection.Vertical
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = parent
	return l
end

return UIUtil
