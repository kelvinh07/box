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

local UI = script.Parent.UI
local Effects = require(UI.Effects)
local TopBar = require(UI.TopBar)
local HUD = require(UI.HUD)
local Backpack = require(UI.Backpack)
local Shop = require(UI.Shop)
local Collection = require(UI.Collection)
local Rebirth = require(UI.Rebirth)
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

-- persistent HUD
TopBar.build(screen)
HUD.build(screen)
Backpack.build(screen)

-- modal panels
local shop = Shop.build(screen)
local collection = Collection.build(screen)
local rebirth = Rebirth.build(screen)

-- right-side navigation toggles the modals
SideNav.build(screen, {
	{ id = "Shop",       text = "🛒",  color = UIUtil.Colors.Accent, onClick = shop.toggle },
	{ id = "Collection", text = "📦",  color = UIUtil.Colors.Gem,    onClick = collection.toggle },
	{ id = "Rebirth",    text = "🔁",  color = UIUtil.Colors.Warn,   onClick = rebirth.toggle },
})

-- per-client dig mounds over the shared field + your own zone areas
DigSite.start(screen)

-- start receiving authoritative state (also pulls an initial snapshot itself,
-- covering the join-order race between client UI setup and the server's push)
ClientState.start()

print("[HatchABrainrot] Client UI ready.")
