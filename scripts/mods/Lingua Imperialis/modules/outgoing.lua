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
    _deps.online_backend.enqueue(ctx, 0, pending.text, pending.target)
    return true
end

function M.init()
    return pcall(function()
        mod:hook(require("scripts/managers/chat/chat_manager"), "send_channel_message",
            function(func, self, channel_handle, message_body)
                local cache = _deps and _deps.settings and _deps.settings.cache

                if not cache
                    or not mod:is_enabled()
                    or not cache.outgoing_enabled
                    or type(message_body) ~= "string"
                    or message_body:match("^%s*$") then
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

                if not dispatch(pending) then
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
