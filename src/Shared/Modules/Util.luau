--!strict
-- Util
-- Small shared helpers: weighted random picking + unique id generation.

local Util = {}

local rng = Random.new()

-- Pick a key from a { [key] = weight } table using weighted probability.
function Util.weightedPick(weights: { [string]: number }): string?
	local total = 0
	for _, w in pairs(weights) do
		total += math.max(0, w)
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber() * total
	local acc = 0
	for key, w in pairs(weights) do
		acc += math.max(0, w)
		if roll <= acc then
			return key
		end
	end
	-- floating point fallback: return last key
	local last
	for key in pairs(weights) do
		last = key
	end
	return last
end

function Util.choice(list: { any }): any
	if #list == 0 then
		return nil
	end
	return list[rng:NextInteger(1, #list)]
end

-- Compact, collision-resistant id for collection entries.
local counter = 0
function Util.uid(): string
	counter += 1
	return string.format("%d-%d", os.clock() * 1000 // 1, counter)
end

function Util.shallowCopy(t: { [any]: any }): { [any]: any }
	local out = {}
	for k, v in pairs(t) do
		out[k] = v
	end
	return out
end

return Util
