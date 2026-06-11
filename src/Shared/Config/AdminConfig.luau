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

-- Values the /test command fills Cash and Gems to (admins only — kelvinisco is in the
-- allow-list above). Well inside a Lua double's exact-integer range (2^53), so it persists
-- and Format.short renders it cleanly (e.g. "100M").
AdminConfig.MaxCash = 100000000 -- 100 million
AdminConfig.MaxGems = 100000000 -- 100 million

-- Is this player an admin? UserId match first, then case-insensitive username.
function AdminConfig.isAdmin(player: Player): boolean
	if AdminConfig.UserIds[player.UserId] then
		return true
	end
	return AdminConfig.Usernames[string.lower(player.Name)] == true
end

return AdminConfig
