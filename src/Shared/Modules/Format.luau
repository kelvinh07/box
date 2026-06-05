--!strict
-- Format
-- Number abbreviation for the chunky currency counters (1.5K, 2.3M, ...).

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

function Format.short(n: number): string
	n = n or 0
	if n < 1000 then
		-- show up to 1 decimal for fractional gem amounts, else whole number
		if n ~= math.floor(n) then
			return string.format("%.1f", n)
		end
		return tostring(math.floor(n))
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

-- mm:ss style countdown
function Format.time(seconds: number): string
	seconds = math.max(0, math.floor(seconds + 0.5))
	if seconds >= 60 then
		return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
	end
	return string.format("%ds", seconds)
end

return Format
