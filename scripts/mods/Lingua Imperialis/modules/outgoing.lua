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

local IGNORE_TOKENS = {}
for token in ([[
gg ggs gg1 gz gj gl hf glhf wp ez ty tyvm thx tx np brb afk
lol lel lmao lmfao rofl kek xd xdd omg omfg wtf wth ffs rip
o7 kk cya ns nt pog poggers sadge based ggwp gogo go
]]):gmatch("%S+") do
    IGNORE_TOKENS[token] = true
end

local string_lower = string.lower
local string_gsub = string.gsub
local string_find = string.find

function M.is_ignorable(text)
    if type(text) ~= "string" then
        return false
    end

    local body = text:match("^%s*(.-)%s*$")
    if body == "" then
        return true
    end

    if not string_find(body, "[%a\128-\255]") then
        return true
    end

    for word in body:gmatch("%S+") do
        local w = string_lower(string_gsub(word, "[%p]+", ""))
        if w ~= "" and not IGNORE_TOKENS[w] then
            return false
        end
    end

    return true
end

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
local NO_INDEX = {}
local _kb = nil

local _probe_kb, _probe_a, _probe_b

local function _probe_vk()
    return _probe_kb.button(_probe_a) + _probe_kb.button(_probe_b)
end

local function _probe_names()
    return _probe_kb.button_index(_probe_a), _probe_kb.button_index(_probe_b)
end

local function resolve_indices(kb, key)
    local cached = _indices[key]
    if cached ~= nil then
        return cached ~= NO_INDEX and cached or nil
    end

    local vk = MODIFIER_VK[key] or MODIFIER_VK.shift
    _probe_kb, _probe_a, _probe_b = kb, vk[1], vk[2]
    if pcall(_probe_vk) then
        _indices[key] = vk
        return vk
    end

    local names = MODIFIER_NAMES[key] or MODIFIER_NAMES.shift
    _probe_a, _probe_b = names[1], names[2]
    local ok, left, right = pcall(_probe_names)
    if not ok or not (left or right) then
        _indices[key] = NO_INDEX
        return nil
    end

    local t = { left or right, right or left }
    _indices[key] = t
    return t
end

local function modifier_held(key)
    local kb = _kb or rawget(_G, "Keyboard")
    if not kb then
        return false
    end
    _kb = kb

    local idx = resolve_indices(kb, key)
    if not idx then
        return false
    end

    _probe_kb, _probe_a, _probe_b = kb, idx[1], idx[2]
    local ok, sum = pcall(_probe_vk)

    return ok and sum > 0
end

local function wants_translation(cache)
    local mode = cache.modifier_mode
    if mode ~= "skip" and mode ~= "force" then
        return true
    end

    local held = modifier_held(cache.modifier_key)
    local translate
    if mode == "force" then
        translate = held
    else
        translate = not held
    end

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

local function note_sent(text)
    if mod._note_sent then
        mod._note_sent(text)
    end
end

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

    note_sent(text)

    local sent_ok, send_err = pcall(pending.func, pending.self, pending.channel, text)
    if not sent_ok then
        mod:warning("Lingua Imperialis: outgoing send failed, message dropped: %s", tostring(send_err))
    end

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
                    or M.is_ignorable(message_body)
                    or not wants_translation(cache) then
                    note_sent(message_body)
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
                    note_sent(message_body)
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
            note_sent(p.text)
            local sent_ok, send_err = pcall(p.func, p.self, p.channel, p.text)
            if not sent_ok then
                mod:warning("Lingua Imperialis: held message dropped on unload: %s", tostring(send_err))
            end
        end
    end
    _pendings = {}
end

return M
