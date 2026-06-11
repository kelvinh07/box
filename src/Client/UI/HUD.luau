--!strict
-- HUD
-- (Intentionally empty.) The incubator status used to live in a bottom-right panel here —
-- a progress bar + countdown + COLLECT button per incubator. That has been MOVED ONTO the
-- incubator models themselves: each incubator now shows its own progress bar + countdown on
-- its front screen, and you COLLECT a finished hatch by CLICKING the incubator. See
-- `Server/Managers/BaseManager.luau` (buildProgressScreen / updateIncubatorProgress and the
-- incubator ClickDetector). `HUD.build` is kept as a no-op so Main.client's call still works.

local HUD = {}

function HUD.build(_gui: ScreenGui)
	-- no on-screen HUD panel anymore (incubator status is on the incubators themselves)
end

return HUD
