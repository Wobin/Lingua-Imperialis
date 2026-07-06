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
	download_model = false,
	download_model_large = false,
	enabled = true,
	target_iso = "en",
	provider = "mymemory",
	mymemory_email = "",
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
	M.cache.download_model = get_bool("download_model", false)
	M.cache.download_model_large = get_bool("download_model_large", false)
	M.cache.enabled = get_bool("enabled", true)

	local iso = mod:get("target_language")
	M.cache.target_iso = (type(iso) == "string" and iso ~= "" and iso) or "en"

	local email = mod:get("mymemory_email")
	M.cache.mymemory_email = (type(email) == "string" and email) or ""

	local provider = mod:get("provider")
	M.cache.provider = (type(provider) == "string" and provider ~= "" and provider) or "mymemory"

	local ch = M.cache.channels
	ch.HUB = get_bool("channel_hub", true)
	ch.MISSION = get_bool("channel_mission", true)
	ch.PARTY = get_bool("channel_party", true)
end

return M
