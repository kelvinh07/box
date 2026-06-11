--!strict
-- InventoryClient
-- Toggles the world placement ProximityPrompts (tagged "InvPrompt" by BaseManager) based on
-- what Tool the LOCAL player is currently holding. The SERVER still validates + routes every
-- trigger — this is purely local UX so prompts only appear when they're actionable:
--   * Incubator prompt  -> shown only while holding an EGG ("Place Egg").
--   * Podium prompt      -> if the podium is OCCUPIED: always shown ("Swap" when holding a
--     brainrot, else "Remove"); if EMPTY: shown only while holding a brainrot ("Place").
--
-- Setting .Enabled / .ActionText locally only affects THIS client's view — exactly what we want.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer

local InventoryClient = {}

local TAG = "InvPrompt"
local equippedKind: string? = nil -- "Egg" | "Brainrot" | nil

local function refreshPrompt(prompt: Instance)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	local kind = prompt:GetAttribute("PromptKind")
	if kind == "Incubator" then
		prompt.Enabled = (equippedKind == "Egg")
	elseif kind == "Podium" then
		local occupied = prompt:GetAttribute("Occupied") == true
		if occupied then
			prompt.Enabled = true
			prompt.ActionText = (equippedKind == "Brainrot") and "Swap" or "Remove"
		else
			prompt.Enabled = (equippedKind == "Brainrot")
			prompt.ActionText = "Place"
		end
	end
end

local function refreshAll()
	for _, p in ipairs(CollectionService:GetTagged(TAG)) do
		refreshPrompt(p)
	end
end

-- recompute the held-tool kind from the character's currently-equipped Tool
local function updateEquipped(char: Model)
	local kind: string? = nil
	for _, c in ipairs(char:GetChildren()) do
		if c:IsA("Tool") then
			kind = c:GetAttribute("Kind") :: string?
			break
		end
	end
	if kind ~= equippedKind then
		equippedKind = kind
		refreshAll()
	end
end

local function watchCharacter(char: Model)
	equippedKind = nil
	char.ChildAdded:Connect(function(c)
		if c:IsA("Tool") then
			updateEquipped(char)
		end
	end)
	char.ChildRemoved:Connect(function(c)
		if c:IsA("Tool") then
			-- defer so the Tool is fully removed before we re-scan
			task.defer(updateEquipped, char)
		end
	end)
	updateEquipped(char)
end

function InventoryClient.start()
	if player.Character then
		watchCharacter(player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)

	-- keep newly-built prompts (e.g. after buying a plot) in sync, and react to a podium's
	-- Occupied attribute flipping (place/remove/swap).
	local function hookPrompt(p: Instance)
		if p:IsA("ProximityPrompt") then
			refreshPrompt(p)
			p:GetAttributeChangedSignal("Occupied"):Connect(function()
				refreshPrompt(p)
			end)
		end
	end
	for _, p in ipairs(CollectionService:GetTagged(TAG)) do
		hookPrompt(p)
	end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(hookPrompt)

	refreshAll()
end

return InventoryClient
