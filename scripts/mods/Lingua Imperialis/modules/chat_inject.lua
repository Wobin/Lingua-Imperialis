--[[
    Name: Lingua Imperialis
    Author: Wobin
    Date: 2026-07-06
    Version: 1.0.0
    Repository:
]]--

local string_find = string.find

local M = {}

local MARKER = "->"

function M.append(chat_element, log_index, original_text, translated, tag_label)
	if not chat_element or not log_index or not original_text or not translated or translated == "" then
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

	local combined
	if tag_label and tag_label ~= "" then
		combined = original .. "\n" .. MARKER .. " [" .. tag_label .. "] " .. translated
	else
		combined = original .. "\n" .. MARKER .. " " .. translated
	end

	content.message = combined
	content.message_format = combined
	entry.message_text = (entry.message_text or "") .. " " .. MARKER .. " " .. translated
	content.size = nil

	return true
end

return M
