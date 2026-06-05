--!strict
-- ClientNet
-- Thin wrapper around RemoteFunction calls. Invokes on the server and, if the
-- server rejects the action, shows the reason as a toast. The server is the
-- authority — this just surfaces its verdict.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage.Shared.Modules.Net)

local ClientNet = {}

local Effects: any = nil
function ClientNet.setEffects(e: any)
	Effects = e
end

-- Returns the server result table. Toasts on failure automatically.
function ClientNet.invoke(funcName: string, ...): any
	local ok, result = pcall(function(...)
		return Net.getFunction(funcName):InvokeServer(...)
	end, ...)
	if not ok then
		if Effects then
			Effects.toast("Error", "Server did not respond.", "Common")
		end
		return { ok = false, reason = "no response" }
	end
	if typeof(result) == "table" and result.ok == false and Effects then
		Effects.toast("Can't do that", result.reason or "Action failed.", "Legendary")
	end
	return result
end

return ClientNet
