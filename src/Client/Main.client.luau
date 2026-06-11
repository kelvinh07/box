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
local InventoryClient = require(script.Parent.InventoryClient)

local UI = script.Parent.UI
local Effects = require(UI.Effects)
local TopBar = require(UI.TopBar)
local HUD = require(UI.HUD)
local Hotbar = require(UI.Hotbar)
local Inventory = require(UI.Inventory)
local HomeButton = require(UI.HomeButton)
local ShopsButton = require(UI.ShopsButton)
local Stands = require(UI.Stands)
local CollectionButton = require(UI.CollectionButton)
local RebirthButton = require(UI.RebirthButton)
local Rebirth = require(UI.Rebirth)
local LevelUp = require(UI.LevelUp)

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
-- the custom bottom hotbar (visually REPLACES the default Roblox hotbar/Backpack CoreGui).
startSafe("Hotbar", function() Hotbar.start(screen) end)
-- the custom inventory overlay (replaces the old egg Backpack panel + Collection modal); it
-- builds its own 🎒 button. InventoryClient toggles the world placement prompts by equip.
local inventory
startSafe("Inventory", function() inventory = Inventory.build(screen) end)
startSafe("InventoryClient", function() InventoryClient.start() end)
startSafe("HomeButton", function() HomeButton.build(screen) end)
startSafe("ShopsButton", function() ShopsButton.build(screen) end)

-- modal panels
local rebirth
startSafe("Rebirth", function() rebirth = Rebirth.build(screen) end)

-- left-side Collection icon (next to the 🎒 button) opens the inventory overlay on Brainrots
startSafe("CollectionButton", function()
	CollectionButton.build(screen, function() if inventory then inventory.open("Brainrots") end end)
end)

-- the three stand upgrade panels (opened by walking up to a stand, not the SideNav)
startSafe("Stands", function() Stands.start(screen) end)

-- per-brainrot level-up panel (opened by clicking your brainrot on its podium)
startSafe("LevelUp", function() LevelUp.start(screen) end)

-- left-column Rebirth icon (below Collection) toggles the Rebirth modal; pulses when ready
startSafe("RebirthButton", function()
	RebirthButton.build(screen, function() if rebirth then rebirth.toggle() end end)
end)

print("[HatchABrainrot] Client UI ready.")
