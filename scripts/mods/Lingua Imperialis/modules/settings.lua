--[[
    Name: Lingua Imperialis
    Author: Wobin
    Date: 2026-07-06
    Version: 1.0.0
    Repository:
]]--

local mod = get_mod("Lingua Imperialis")

local M = {}

M.cache = {
	enabled = true,
	target_iso = "en",
	channels = {
		HUB = true,
		MISSION = true,
		PARTY = true,
	},
}

local function get_bool(id, fallback)
	local v = mod:get(id)
	if v == nil then
		return fallback
	end
	return v and true or false
end

function M.refresh()
	M.cache.enabled = get_bool("enabled", true)

	local iso = mod:get("target_language")
	M.cache.target_iso = (type(iso) == "string" and iso ~= "" and iso) or "en"

	local ch = M.cache.channels
	ch.HUB = get_bool("channel_hub", true)
	ch.MISSION = get_bool("channel_mission", true)
	ch.PARTY = get_bool("channel_party", true)
end

return M
