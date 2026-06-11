--!strict
-- HomeButton (Teleport menu)
-- A transparent icon button on the LEFT, stacked just ABOVE the 🎒 Backpack button.
-- Clicking it opens a TELEPORT popup:
--   * "🏠 Home" ALWAYS at the very top — teleports you to your own base.
--   * Every UNLOCKED zone ("Zone N - Name") — teleports you to the MIDDLE of that zone.
--     (Zone 1 has no requirement, so it is always unlocked.)
--   * Your NEXT zone (the one you're about to unlock) is shown under a translucent grey
--     cover; clicking it toasts "Requirement not met!". Zones beyond the next are hidden.
-- No hover tooltip. The icon is transparent (no box) and sized like the Collection button.
--
-- NOTE: ScreenGui uses ZIndexBehavior.Global, so EVERY row must sit at a ZIndex >= the
-- modal panel/content (20/21) or it renders BEHIND the panel and looks empty.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared
local ZoneConfig = require(Shared.Config.ZoneConfig)

local UIUtil = require(script.Parent.Parent.UIUtil)
local ClientState = require(script.Parent.Parent.ClientState)
local ClientNet = require(script.Parent.Parent.ClientNet)
local Sounds = require(script.Parent.Parent.Sounds)

local HomeButton = {}

local ICON = "rbxassetid://78228091733935"
local ROW_Z = 22   -- above the modal content (21)
local COVER_Z = 24 -- above the row + its text

function HomeButton.build(gui: ScreenGui)
	-- the icon button (transparent, no box; icon fills + overflows to match the Collection button)
	local btn = UIUtil.button({
		Name = "HomeButton",
		Size = UDim2.new(0, 64, 0, 64),
		Position = UDim2.new(0, 16, 0.5, -85), -- 85px ABOVE the Backpack button
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
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
	img.ScaleType = Enum.ScaleType.Fit
	img.ZIndex = btn.ZIndex + 1
	img.Parent = btn

	-- the TELEPORT popup
	local modal = UIUtil.modal(gui, "🧭 Teleport", UDim2.new(0, 460, 0, 480))

	-- Home row — ALWAYS at the top, always available
	local homeRow = UIUtil.button({
		Size = UDim2.new(1, -8, 0, 52),
		BackgroundColor3 = UIUtil.Colors.Good,
		Text = "🏠  Home  (your base)",
		TextSize = 24,
		LayoutOrder = 0,
		Parent = modal.content,
	})
	homeRow.ZIndex = ROW_Z
	homeRow.MouseButton1Click:Connect(function()
		local res = ClientNet.invoke("TeleportHome")
		if res and res.ok then
			Sounds.play("Sparkle")
			modal.setVisible(false)
		end
	end)

	-- one row per zone (Visible/cover toggled from server state)
	local zoneRows: { [number]: { row: TextButton, cover: Frame } } = {}
	for z = 1, ZoneConfig.MaxZone do
		local data = ZoneConfig.get(z)
		local row = UIUtil.button({
			Size = UDim2.new(1, -8, 0, 52),
			BackgroundColor3 = UIUtil.Colors.PanelLight,
			Text = ("Zone %d - %s"):format(z, data.DisplayName),
			TextSize = 22,
			LayoutOrder = z,
			Visible = false, -- shown once we know the player's progress
			Parent = modal.content,
		})
		row.ZIndex = ROW_Z

		-- translucent grey cover for the NEXT (locked) zone; the name still reads through it
		local cover = UIUtil.frame({
			Name = "Cover",
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundColor3 = Color3.fromRGB(35, 35, 40),
			BackgroundTransparency = 0.45,
			Visible = false,
			Parent = row,
		})
		cover.ZIndex = COVER_Z
		UIUtil.corner(cover, 14)

		row.MouseButton1Click:Connect(function()
			-- server validates: unlocked -> teleport; locked -> toasts "Requirement not met!"
			local res = ClientNet.invoke("TeleportZone", z)
			if res and res.ok then
				Sounds.play("Sparkle")
				modal.setVisible(false)
			end
		end)

		zoneRows[z] = { row = row, cover = cover }
	end

	-- reflect each zone's state from the server snapshot:
	--   unlocked (z <= highest)      -> plain, clickable
	--   next zone (z == highest + 1) -> visible, grey cover, 🔒 prefix
	--   beyond next                  -> hidden
	ClientState.onChanged(function(state)
		if not state then return end
		local highest = state.HighestZone or 1
		for z, parts in pairs(zoneRows) do
			local data = ZoneConfig.get(z)
			if z <= highest then
				parts.row.Visible = true
				parts.cover.Visible = false
				parts.row.Text = ("Zone %d - %s"):format(z, data.DisplayName)
			elseif z == highest + 1 then
				parts.row.Visible = true
				parts.cover.Visible = true
				parts.row.Text = ("🔒 Zone %d - %s"):format(z, data.DisplayName)
			else
				parts.row.Visible = false
				parts.cover.Visible = false
			end
		end
	end)

	btn.MouseButton1Click:Connect(function()
		modal.toggle()
	end)
end

return HomeButton
