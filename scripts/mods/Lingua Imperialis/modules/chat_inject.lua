--[[
    Name: Lingua Imperialis
    Author: Wobin
    Date: 2026-07-06
    Version: 1.0.0
    Repository:
]]--

local string_find   = string.find
local string_upper  = string.upper
local string_lower  = string.lower
local string_gsub   = string.gsub
local string_format = string.format
local math_floor    = math.floor

local M = {}

local function normalize(s)
	s = string_lower(s)
	s = string_gsub(s, "^%s+", "")
	s = string_gsub(s, "%s+$", "")
	return s
end

local MARKER = "->"

local DEFAULT_RGB = { 106, 190, 48 }

local function clamp255(n)
	n = math_floor((type(n) == "number" and n or 0) + 0.5)
	if n < 0 then
		return 0
	elseif n > 255 then
		return 255
	end
	return n
end

local function build_prefix(r, g, b)
	return string_format("{# color(%d,%d,%d,255)}", clamp255(r), clamp255(g), clamp255(b))
end

local color_prefix = build_prefix(DEFAULT_RGB[1], DEFAULT_RGB[2], DEFAULT_RGB[3])

function M.set_color(rgb)
	if type(rgb) == "table" then
		color_prefix = build_prefix(rgb[1], rgb[2], rgb[3])
	else
		color_prefix = build_prefix(DEFAULT_RGB[1], DEFAULT_RGB[2], DEFAULT_RGB[3])
	end
end

local function build_body(translated, tag_label)
	if tag_label and tag_label ~= "" then
		return MARKER .. " [" .. string_upper(tag_label) .. "] " .. translated
	end
	return MARKER .. " " .. translated
end

function M.format(translated, tag_label)
	if not translated or translated == "" then
		return ""
	end
	return color_prefix .. build_body(translated, tag_label) .. "{#reset()}"
end

function M.append(chat_element, log_index, original_text, translated, tag_label)
	if not chat_element or not log_index or not original_text or not translated or translated == "" then
		return false
	end

	if normalize(original_text) == normalize(translated) then
		return false
	end

	if log_index ~= chat_element._last_message_index then
		return false
	end

	local widgets = chat_element._message_widgets
	local messages = chat_element._messages
	if not widgets or not messages then
		return false
	end

	local widget = widgets[log_index]
	local entry = messages[log_index]
	if not widget or not entry then
		return false
	end

	local content = widget.content
	if not content then
		return false
	end

	local original = content.message
	if not original then
		return false
	end

	if not string_find(original, original_text, 1, true) then
		return false
	end

	if string_find(original, "\n", 1, true) then
		return false
	end

	local body = build_body(translated, tag_label)
	local combined = original .. "\n" .. color_prefix .. body .. "{#reset()}"

	content.message = combined
	content.message_format = combined
	entry.message_text = (entry.message_text or "") .. " " .. body
	content.size = nil

	return true
end

return M
