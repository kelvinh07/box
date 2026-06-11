--!strict
-- Format
-- Number abbreviation for the chunky currency counters (1.5K, 2.3M, ...).

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function Format.short(n: number): string
	n = n or 0
	if n < 1000 then
		-- sub-1000 values ALWAYS render as a whole integer (round half-up); no decimals.
		-- Cash is already integer from BrainrotMath; this also cleans any fractional
		-- value (e.g. a gem sub-total) so nothing ever shows "$0.2/s".
		return tostring(math.floor(n + 0.5))
	end
	local idx = 1
	while n >= 1000 and idx < #SUFFIXES do
		n /= 1000
		idx += 1
	end
	-- trim trailing .0
	local s = string.format("%.1f", n)
	s = s:gsub("%.0$", "")
	return s .. SUFFIXES[idx]
end

-- Whole number with thousands separators (e.g. 51800 -> "51,800"). Rounds half-up; no
-- decimals. Used where the EXACT figure matters (e.g. the rebirth lifetime-cash requirement).
function Format.comma(n: number): string
	n = math.floor((n or 0) + 0.5)
	local sign = ""
	if n < 0 then
		sign = "-"
		n = -n
	end
	local s = tostring(n)
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	out = out:gsub("^,", "")
	return sign .. out
end

-- mm:ss style countdown
function Format.time(seconds: number): string
	seconds = math.max(0, math.floor(seconds + 0.5))
	if seconds >= 60 then
		return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
	end
	return string.format("%ds", seconds)
end

return Format
