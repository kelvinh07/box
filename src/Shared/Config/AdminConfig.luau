--!strict
-- AdminConfig
-- The admin allow-list + the values the admin /test command grants.
--
-- Admins are matched by NUMERIC UserId (stable — never changes) OR by username
-- (case-insensitive; convenient, but usernames CAN change, so prefer UserIds).
-- Find a UserId at roblox.com/users/<id>/profile or via
-- Players:GetUserIdFromNameAsync(name).

local AdminConfig = {}

-- Roblox UserIds with admin powers.
AdminConfig.UserIds = {
	[296559455] = true, -- kelvinisco
}

-- Usernames with admin powers (compared case-insensitively). Convenience fallback;
-- UserId is preferred because a username can be changed.
AdminConfig.Usernames = {
	["kelvinisco"] = true,
}

-- Values the /test command fills Cash and Gems to. Huge but well inside a Lua
-- double's exact-integer range (2^53), so every cost in the game is trivially
-- affordable and Format.short renders it as "1T".
AdminConfig.MaxCash = 1e12 -- 1 trillion
AdminConfig.MaxGems = 1e12

-- Is this player an admin? UserId match first, then case-insensitive username.
function AdminConfig.isAdmin(player: Player): boolean
	if AdminConfig.UserIds[player.UserId] then
		return true
	end
	return AdminConfig.Usernames[string.lower(player.Name)] == true
end

return AdminConfig
