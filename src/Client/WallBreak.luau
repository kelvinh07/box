--!strict
-- WallBreak (client)
-- The zone walls are ONE shared server part each, so the server can't make a wall vanish for
-- just one player. When THIS player breaks a wall (CASH purchase -> their HighestZone rises),
-- we play a quick crack + shatter and HIDE the wall LOCALLY (LocalTransparencyModifier + local
-- texture/GUI hide) and spawn CLIENT-LOCAL debris. Because that's client-side, other players
-- still see the wall solid until THEY break it.
--
-- On REBIRTH the walls re-lock (HighestZone drops back to 1), so any wall now at/above the
-- player's frontier is RE-SHOWN (un-hidden) and can be broken again.
--
-- Walls are named "RebirthWall_k" (k = 1..MaxZone-1) under Workspace.DigLane. Wall k sits
-- between zone k and zone k+1, so a player whose highest zone is H has broken walls 1..H-1.

local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local ClientState = require(script.Parent.ClientState)

local WallBreak = {}

local laneFolder: Instance?
local broken: { [number]: boolean } = {}
local firstHighest: number? = nil
local savedTransparency: { [Instance]: number } = {} -- original Texture/Decal transparency

local function getWall(k: number): BasePart?
	if not laneFolder then
		return nil
	end
	local w = laneFolder:FindFirstChild("RebirthWall_" .. k)
	return (w and w:IsA("BasePart")) and w or nil
end

-- hide the shared wall for THIS client only: the part faces (LocalTransparencyModifier),
-- its studs (child Textures), its info GUI, and its click detector.
local function hideWallLocal(wall: BasePart)
	wall.LocalTransparencyModifier = 1
	for _, d in ipairs(wall:GetDescendants()) do
		if d:IsA("Texture") or d:IsA("Decal") then
			if savedTransparency[d] == nil then
				savedTransparency[d] = d.Transparency
			end
			d.Transparency = 1
		elseif d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
			d.Enabled = false
		elseif d:IsA("ClickDetector") then
			d.MaxActivationDistance = 0
		end
	end
end

-- reverse of hideWallLocal: bring the (re-locked) wall back to solid for this client.
local function unhideWallLocal(wall: BasePart)
	wall.LocalTransparencyModifier = 0
	for _, d in ipairs(wall:GetDescendants()) do
		if d:IsA("Texture") or d:IsA("Decal") then
			d.Transparency = savedTransparency[d] or 0
		elseif d:IsA("SurfaceGui") or d:IsA("BillboardGui") then
			d.Enabled = true
		elseif d:IsA("ClickDetector") then
			d.MaxActivationDistance = 30
		end
	end
end

-- 3-frame crack on the wall's front face, then shatter into client-local debris + hide.
local function shatterWall(wall: BasePart)
	local color = wall.Color
	local size = wall.Size
	local cf = wall.CFrame
	local frontZ = -size.Z / 2 - 0.15 -- just in front of the Front (-Z) face (toward the player)

	-- crack lines appear in 3 quick waves
	local cracks: { BasePart } = {}
	local function crackWave(n: number)
		for _ = 1, n do
			local crack = Instance.new("Part")
			crack.Anchored = true
			crack.CanCollide = false
			crack.CastShadow = false
			crack.Material = Enum.Material.SmoothPlastic
			crack.Color = Color3.fromRGB(20, 16, 16)
			crack.Size = Vector3.new(0.35, math.random(8, 22), 0.35)
			local rx = (math.random() - 0.5) * (size.X - 8)
			local ry = (math.random() - 0.5) * (size.Y - 8)
			crack.CFrame = cf * CFrame.new(rx, ry, frontZ) * CFrame.Angles(0, 0, math.rad(math.random(0, 180)))
			crack.Parent = Workspace
			table.insert(cracks, crack)
		end
	end
	crackWave(4)
	task.wait(0.08)
	crackWave(5)
	task.wait(0.08)
	crackWave(5)
	task.wait(0.1)

	-- shatter: hide the real wall + cracks, burst a grid of debris chunks outward
	hideWallLocal(wall)
	for _, c in ipairs(cracks) do
		c:Destroy()
	end

	local nx, ny = 4, 3
	for ix = 1, nx do
		for iy = 1, ny do
			local chunk = Instance.new("Part")
			chunk.Anchored = false
			chunk.CanCollide = false
			chunk.CastShadow = false
			chunk.Material = Enum.Material.SmoothPlastic
			chunk.Color = color
			chunk.Size = Vector3.new((size.X / nx) * 0.92, (size.Y / ny) * 0.92, size.Z)
			local lx = -size.X / 2 + (ix - 0.5) * (size.X / nx)
			local ly = -size.Y / 2 + (iy - 0.5) * (size.Y / ny)
			chunk.CFrame = cf * CFrame.new(lx, ly, 0)
			chunk.Parent = Workspace
			-- burst toward the player (front, -Z) + outward, with an upward pop
			local dir = cf:VectorToWorldSpace(
				Vector3.new((math.random() - 0.5) * 1.6, math.random() * 1.2 + 0.2, -1)
			).Unit
			chunk.AssemblyLinearVelocity = dir * (math.random() * 28 + 22)
			chunk.AssemblyAngularVelocity = Vector3.new(
				math.random(-9, 9), math.random(-9, 9), math.random(-9, 9)
			)
			TweenService:Create(chunk, TweenInfo.new(1.2), { Transparency = 1 }):Play()
			Debris:AddItem(chunk, 1.35)
		end
	end
end

local function breakWall(k: number, animate: boolean)
	if broken[k] then
		return
	end
	local wall = getWall(k)
	if not wall then
		return -- not replicated yet; we retry on the next state update
	end
	broken[k] = true
	if animate then
		task.spawn(shatterWall, wall)
	else
		hideWallLocal(wall)
	end
end

-- re-show a wall that re-locked on rebirth (frontier dropped back below it).
local function restoreWall(k: number)
	if not broken[k] then
		return
	end
	broken[k] = false
	local wall = getWall(k)
	if wall then
		unhideWallLocal(wall)
	end
end

function WallBreak.start()
	laneFolder = Workspace:WaitForChild("DigLane", 20)

	ClientState.onChanged(function(state)
		if not state then
			return
		end
		local highest = state.HighestZone or 1
		-- remember the highest zone we were ALREADY past when we first synced: those walls
		-- were broken in a prior session, so hide them instantly (no animation).
		if firstHighest == nil then
			firstHighest = highest
		end
		-- a player at highest zone H has broken walls 1..H-1
		for k = 1, highest - 1 do
			if not broken[k] then
				breakWall(k, k >= (firstHighest :: number)) -- animate only walls crossed THIS session
			end
		end
		-- re-lock (un-hide) any broken wall now at/above the current frontier (e.g. after rebirth)
		for k in pairs(broken) do
			if k >= highest then
				restoreWall(k)
			end
		end
	end)
end

return WallBreak
