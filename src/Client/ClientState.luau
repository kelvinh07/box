--!strict
-- ClientState
-- Holds the latest authoritative snapshot pushed from the server and fans out
-- change notifications to every UI panel. The client NEVER mutates gameplay
-- values locally — it only reflects what the server says.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Modules.Net)

local ClientState = {}

local current: any = nil
local listeners: { (any) -> () } = {}

function ClientState.get(): any
	return current
end

function ClientState.onChanged(fn: (any) -> ()): () -> ()
	table.insert(listeners, fn)
	if current then
		task.spawn(fn, current)
	end
	return function()
		local i = table.find(listeners, fn)
		if i then
			table.remove(listeners, i)
		end
	end
end

local function set(snapshot: any)
	current = snapshot
	for _, fn in ipairs(listeners) do
		task.spawn(fn, snapshot)
	end
end

function ClientState.start()
	Net.getEvent("PushState").OnClientEvent:Connect(set)
	-- pull an initial snapshot in case we connected after the first push.
	-- Retry a few times to cover the join-order race (profile may still be loading).
	task.spawn(function()
		for _ = 1, 6 do
			if current then
				return
			end
			local ok, snap = pcall(function()
				return Net.getFunction("RequestState"):InvokeServer()
			end)
			if ok and snap then
				set(snap)
				return
			end
			task.wait(1)
		end
	end)
end

return ClientState
