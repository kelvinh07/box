--!strict
-- Main (Client)
-- Entry point in StarterPlayerScripts. Builds the entire UI in code, wires the
-- effects/network helpers, and starts listening for server state. No StarterGui
-- instances required — everything is generated here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- make sure shared remotes exist before any UI tries to use them
ReplicatedStorage:WaitForChild("Shared")

local UIUtil = require(script.Parent.UIUtil)
local ClientState = require(script.Parent.ClientState)
local ClientNet = require(script.Parent.ClientNet)
local DigSite = require(script.Parent.DigSite)
local WallBreak = require(script.Parent.WallBreak)
local GrassChecker = require(script.Parent.GrassChecker)

local UI = script.Parent.UI
local Effects = require(UI.Effects)
local TopBar = require(UI.TopBar)
local HUD = require(UI.HUD)
local Backpack = require(UI.Backpack)
local HomeButton = require(UI.HomeButton)
local Stands = require(UI.Stands)
local Collection = require(UI.Collection)
local Rebirth = require(UI.Rebirth)
local LevelUp = require(UI.LevelUp)
local SideNav = require(UI.SideNav)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- root ScreenGui
local screen = Instance.new("ScreenGui")
screen.Name = "HatchABrainrotUI"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = true
screen.ZIndexBehavior = Enum.ZIndexBehavior.Global
screen.Parent = playerGui

-- effects first (so ClientNet can toast through it)
Effects.build(screen)
ClientNet.setEffects(Effects)

-- Start every subsystem in ISOLATION: a failure in one panel (e.g. a stale/broken
-- upgrade panel) must never abort the rest of the client — above all it must not
-- stop digging or state sync. Each piece runs in its own pcall and just warns on
-- failure, so the core gameplay loop always comes up.
local function startSafe(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn(("[HatchABrainrot] %s failed to start: %s"):format(name, tostring(err)))
	end
end

-- CORE LOOP FIRST: authoritative state + the dig field, before any optional UI.
startSafe("ClientState", function() ClientState.start() end)
startSafe("DigSite", function() DigSite.start(screen) end)
startSafe("WallBreak", function() WallBreak.start() end)
startSafe("GrassChecker", function() GrassChecker.start() end)

-- persistent HUD
startSafe("TopBar", function() TopBar.build(screen) end)
startSafe("HUD", function() HUD.build(screen) end)
startSafe("Backpack", function() Backpack.build(screen) end)
startSafe("HomeButton", function() HomeButton.build(screen) end)

-- modal panels
local collection, rebirth
startSafe("Collection", function() collection = Collection.build(screen) end)
startSafe("Rebirth", function() rebirth = Rebirth.build(screen) end)

-- the three stand upgrade panels (opened by walking up to a stand, not the SideNav)
startSafe("Stands", function() Stands.start(screen) end)

-- per-brainrot level-up panel (opened by clicking your brainrot on its podium)
startSafe("LevelUp", function() LevelUp.start(screen) end)

-- right-side navigation toggles the modals (guarded in case a panel above failed)
startSafe("SideNav", function()
	SideNav.build(screen, {
		{ id = "Collection", text = "📦",  color = UIUtil.Colors.Gem,  onClick = function() if collection then collection.toggle() end end },
		{ id = "Rebirth",    text = "🔄",  color = Color3.fromRGB(220, 55, 65), onClick = function() if rebirth then rebirth.toggle() end end },
	})
end)

print("[HatchABrainrot] Client UI ready.")
