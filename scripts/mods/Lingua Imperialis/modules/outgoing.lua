--[[
    Name: Lingua Imperialis
    Author: Wobin
    Date: 2026-07-09
    Version: 1.1.0
    Repository:
]]--

local mod = get_mod("Lingua Imperialis")

local M = {}

local DEADLINE = 5

local _deps = nil
local _pendings = {}

local _shift_indices = nil

local function shift_held()
    local kb = rawget(_G, "Keyboard")
    if not kb then
        return false
    end

    if not _shift_indices then
        local ok, left, right = pcall(function()
            return kb.button_index("left shift"), kb.button_index("right shift")
        end)
        if not ok then
            return false
        end
        local t = {}
        if left then t[#t + 1] = left end
        if right then t[#t + 1] = right end
        if #t == 0 then
            return false
        end
        _shift_indices = t
    end

    for i = 1, #_shift_indices do
        local idx = _shift_indices[i]
        if idx and kb.button(idx) > 0.5 then
            return true
        end
    end

    return false
end

local function wants_translation(mode)
    if mode == "force" then
        return shift_held()
    elseif mode == "skip" then
        return not shift_held()
    end
    return true
end

function M.setup(deps)
    _deps = deps
end

function M.deliver(pending, translated)
    if not pending or pending.sent then
        return
    end
    pending.sent = true
    local text = translated
    if type(text) ~= "string" or text == "" then
        text = pending.text
    end
    pcall(pending.func, pending.self, pending.channel, text)
end

local function dispatch(pending)
    if mod._engine() == "offline" then
        return _deps.offline_submit and _deps.offline_submit(pending.text, pending.target, pending) or false
    end

    local translator = _deps.translator
    if not (translator and translator.available) then
        return false
    end

    local ctx = { li_outgoing = true, pending = pending }
    return _deps.online_backend.enqueue(ctx, 0, pending.text, pending.target) and true or false
end

function M.init()
    return pcall(function()
        mod:hook(require("scripts/managers/chat/chat_manager"), "send_channel_message",
            function(func, self, channel_handle, message_body)
                local cache = _deps and _deps.settings and _deps.settings.cache

                if not cache
                    or not mod:is_enabled()
                    or not cache.enabled
                    or not cache.outgoing_enabled
                    or type(message_body) ~= "string"
                    or message_body:match("^%s*$")
                    or not wants_translation(cache.shift_enter_mode) then
                    return func(self, channel_handle, message_body)
                end

                local pending = {
                    func = func,
                    self = self,
                    channel = channel_handle,
                    text = message_body,
                    target = cache.outgoing_iso or "en",
                    deadline = (mod._clock or 0) + DEADLINE,
                    sent = false,
                }

                local ok, dispatched = pcall(dispatch, pending)
                if not ok or not dispatched then
                    return func(self, channel_handle, message_body)
                end

                _pendings[#_pendings + 1] = pending
            end)
    end)
end

function M.update(clock)
    local i = 1
    while i <= #_pendings do
        local p = _pendings[i]
        if p.sent then
            table.remove(_pendings, i)
        elseif clock > p.deadline then
            M.deliver(p, nil)
            table.remove(_pendings, i)
        else
            i = i + 1
        end
    end
end

function M.clear()
    for i = 1, #_pendings do
        local p = _pendings[i]
        if not p.sent then
            p.sent = true
            pcall(p.func, p.self, p.channel, p.text)
        end
    end
    _pendings = {}
end

return M
