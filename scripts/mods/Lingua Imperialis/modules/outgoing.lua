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

local MODIFIER_VK = {
    shift = { 160, 161 },
    ctrl  = { 162, 163 },
    alt   = { 164, 165 },
}

local MODIFIER_NAMES = {
    shift = { "left shift", "right shift" },
    ctrl  = { "left ctrl",  "right ctrl"  },
    alt   = { "left alt",   "right alt"   },
}

local _indices = {}

local function resolve_indices(kb, key)
    local cached = _indices[key]
    if cached then
        return cached
    end

    local vk = MODIFIER_VK[key] or MODIFIER_VK.shift
    if pcall(function() return kb.button(vk[1]) + kb.button(vk[2]) end) then
        _indices[key] = vk
        return vk
    end

    local names = MODIFIER_NAMES[key] or MODIFIER_NAMES.shift
    local ok, left, right = pcall(function()
        return kb.button_index(names[1]), kb.button_index(names[2])
    end)
    if not ok or not (left or right) then
        return nil
    end

    local t = { left or right, right or left }
    _indices[key] = t
    return t
end

local function modifier_held(key)
    local kb = rawget(_G, "Keyboard")
    if not kb then
        return false
    end

    local idx = resolve_indices(kb, key)
    if not idx then
        return false
    end

    local ok, sum = pcall(function()
        return kb.button(idx[1]) + kb.button(idx[2])
    end)

    return ok and sum > 0
end

local function wants_translation(cache)
    local mode = cache.modifier_mode
    if mode ~= "skip" and mode ~= "force" then
        return true
    end

    local held = modifier_held(cache.modifier_key)
    local translate = (mode == "force") and held or (not held)

    if mod.debug_modifier then
        mod:info("[modifier] key=%s mode=%s held=%s -> translate=%s",
            tostring(cache.modifier_key), tostring(mode), tostring(held), tostring(translate))
    end

    return translate
end

function M.setup(deps)
    _deps = deps
end

M.REASON = {
    NOOP    = "untranslated_noop",
    FAILED  = "untranslated_failed",
    TIMEOUT = "untranslated_timeout",
}

local function notify_fallback(reason)
    if not reason then
        return
    end
    local cache = _deps and _deps.settings and _deps.settings.cache
    if not cache or not cache.notify_untranslated then
        return
    end
    pcall(function()
        mod:echo(mod:localize(reason))
    end)
end

function M.deliver(pending, translated, reason)
    if not pending or pending.sent then
        return
    end
    pending.sent = true

    local text = translated
    local ok = type(text) == "string" and text ~= ""
    if not ok then
        text = pending.text
    end

    if mod.debug_modifier then
        mod:info("[outgoing] deliver translated=%s (%s) reason=%s waited=%.2fs",
            tostring(ok), ok and "TRANSLATED" or "FELL BACK TO ORIGINAL", tostring(reason),
            (mod._clock or 0) - ((pending.deadline or 0) - DEADLINE))
    end

    pcall(pending.func, pending.self, pending.channel, text)

    if not ok then
        notify_fallback(reason)
    end
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
                    or not wants_translation(cache) then
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
            M.deliver(p, nil, M.REASON.TIMEOUT)
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
