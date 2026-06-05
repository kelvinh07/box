--!strict
-- Sounds
-- Tiny SFX helper. Asset ids live in AssetConfig.Sounds (swap them for your own
-- Creator Store sounds). Sounds are created once and reused.

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetConfig = require(ReplicatedStorage.Shared.Config.AssetConfig)

local Sounds = {}
local pool: { [string]: Sound } = {}

local function get(name: string): Sound?
	if pool[name] then
		return pool[name]
	end
	local id = AssetConfig.Sounds[name]
	if not id then
		return nil
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = 0.5
	s.Parent = SoundService
	pool[name] = s
	return s
end

function Sounds.play(name: string, pitch: number?)
	local s = get(name)
	if s then
		s.PlaybackSpeed = pitch or 1
		s:Play()
	end
end

return Sounds
