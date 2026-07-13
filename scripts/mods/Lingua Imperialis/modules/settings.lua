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
	outgoing_enabled = false,
	outgoing_iso = "en",
	modifier_key = "shift",
	modifier_mode = "skip",
	notify_untranslated = true,
	provider = "mymemory",
	translation_rgb = { 106, 190, 48 },
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

local function get_iso(id)
	local v = mod:get(id)
	if type(v) ~= "string" or v == "" then
		return "en"
	end
	if v == "zh" then
		mod:set(id, "zh-CN", false)
		return "zh-CN"
	end
	return v
end

function M.refresh()
	M.cache.download_model = get_bool("download_model", false)
	M.cache.download_model_large = get_bool("download_model_large", false)
	M.cache.enabled = get_bool("enabled", true)

	M.cache.target_iso = get_iso("target_language")

	M.cache.outgoing_enabled = get_bool("outgoing_enabled", false)

	M.cache.outgoing_iso = get_iso("outgoing_language")

	local mod_key = mod:get("outgoing_modifier_key")
	M.cache.modifier_key = (type(mod_key) == "string" and mod_key ~= "" and mod_key) or "shift"

	local mod_mode = mod:get("outgoing_modifier_mode")
	M.cache.modifier_mode = (type(mod_mode) == "string" and mod_mode ~= "" and mod_mode) or "skip"

	M.cache.notify_untranslated = get_bool("outgoing_notify_untranslated", true)

	local provider = mod:get("provider")
	M.cache.provider = (type(provider) == "string" and provider ~= "" and provider) or "mymemory"

	local rgb = M.cache.translation_rgb
	local defaults = { 106, 190, 48 }
	local ids = { "translation_colour_R", "translation_colour_G", "translation_colour_B" }
	for i = 1, 3 do
		local v = mod:get(ids[i])
		rgb[i] = (type(v) == "number") and v or defaults[i]
	end

	local ch = M.cache.channels
	ch.HUB = get_bool("channel_hub", true)
	ch.MISSION = get_bool("channel_mission", true)
	ch.PARTY = get_bool("channel_party", true)
end

return M
