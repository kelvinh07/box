--!strict
-- AdminManager
-- Handles admin chat commands (server-authoritative — a command only does
-- anything for a player who passes AdminConfig.isAdmin). Commands:
--   /test  -> fill the caller's Cash and Gems to AdminConfig.Max* (for testing).
--
-- init() is wired by Bootstrap; it hooks Player.Chatted for current + future
-- players. Mutations go through PlayerData (markDirty + push) like every other
-- manager, so the change persists and the client UI reflects it immediately.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local AdminConfig = require(Shared.Config.AdminConfig)
local Net = require(Shared.Modules.Net)

local PlayerData = require(script.Parent.PlayerData)

local AdminManager = {}

-- /test: max out the caller's Cash and Gems.
local function cmdTest(player: Player)
	local p = PlayerData.get(player)
	if not p then
		return
	end
	p.Cash = AdminConfig.MaxCash
	p.Gems = AdminConfig.MaxGems
	PlayerData.markDirty(player)
	PlayerData.push(player)
	Net.getEvent("Notify"):FireClient(player, {
		title = "ADMIN",
		text = "Cash & Gems maxed out.",
		color = "Legendary",
	})
end

local function onChatted(player: Player, message: string)
	if not AdminConfig.isAdmin(player) then
		return
	end
	-- first whitespace-delimited token, lowercased ("/test", "/TEST", "/test foo" -> "/test")
	local cmd = string.lower(string.match(message, "^%s*(%S+)") or "")
	if cmd == "/test" then
		cmdTest(player)
	end
end

local function hook(player: Player)
	player.Chatted:Connect(function(message)
		onChatted(player, message)
	end)
end

function AdminManager.init()
	for _, player in ipairs(Players:GetPlayers()) do
		hook(player)
	end
	Players.PlayerAdded:Connect(hook)
end

return AdminManager
