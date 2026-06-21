--!strict
-- Net
-- Central registry of every RemoteEvent / RemoteFunction.
-- The SERVER calls setupServer() once to create the instances under
-- ReplicatedStorage.Shared. CLIENTS use getEvent()/getFunction() which
-- WaitForChild the corresponding instance.
--
-- SECURITY: every remote here is validated server-side. The client can only
-- *request*; the server decides whether anything actually happens.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = {}

-- server -> client (RemoteEvents)
Net.Events = {
	"PushState",     -- full authoritative player state snapshot
	"Notify",        -- toast / banner messages
	"HatchResult",   -- one hatch outcome (for the reveal animation)
	"FloatingText",  -- "+$" / "+Gem" world/screen popups
	"ScreenShake",   -- juice on hatch
	"OfflineEarnings", -- one-shot "welcome back" payload (cash/gems earned while away)
}

-- client -> server (RemoteFunctions, return success/payload)
Net.Functions = {
	"RequestState",       -- ask server to push current state
	"RollEggs",           -- ask server to pre-assign rarities to dig spots
	"Dig",                -- dig a specific assigned spot -> returns its egg rarity
	"PlaceEgg",           -- put an egg into the next free unlocked incubator
	"DiscardEgg",         -- delete one unwanted egg of a rarity from the backpack
	"CollectIncubator",   -- claim a finished hatch from incubator slot index
	"UnlockIncubator",    -- spend cash to unlock the next incubator (hatch more at once)
	"BuyPlot",            -- buy another brainrot plot
	"BuyLadder",          -- spend cash to unlock the ladder to the 2nd floor
	"UpgradeLuck",        -- spend gems on Luck
	"UpgradeIncubator",   -- spend cash/gems on the Incubator track (was UpgradeHatchSpeed)
	"UpgradeShovel",      -- spend cash/gems on a faster dig shovel
	"LevelBrainrot",      -- level up a single owned brainrot (Cash L2-5 / Gems L6-10)
	"Rebirth",            -- perform a rebirth
	"SellBrainrot",       -- sell an owned brainrot for cash
	"EquipBest",          -- auto-place the best brainrots (by level-1 rate) onto the base podiums
	"TeleportHome",       -- teleport the player back to their own base
	"TeleportZone",       -- teleport the player to the middle of an UNLOCKED dig zone
}

local FOLDER_NAME = "Remotes"

function Net.setupServer()
	local folder = ReplicatedStorage.Shared:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage.Shared
	end
	for _, name in ipairs(Net.Events) do
		if not folder:FindFirstChild(name) then
			local ev = Instance.new("RemoteEvent")
			ev.Name = name
			ev.Parent = folder
		end
	end
	for _, name in ipairs(Net.Functions) do
		if not folder:FindFirstChild(name) then
			local fn = Instance.new("RemoteFunction")
			fn.Name = name
			fn.Parent = folder
		end
	end
	return folder
end

local function folder(): Instance
	return ReplicatedStorage.Shared:WaitForChild(FOLDER_NAME, 30)
end

function Net.getEvent(name: string): RemoteEvent
	return folder():WaitForChild(name, 30) :: RemoteEvent
end

function Net.getFunction(name: string): RemoteFunction
	return folder():WaitForChild(name, 30) :: RemoteFunction
end

return Net
