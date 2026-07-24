--[[
    Name: Lingua Imperialis
    Author: Wobin
    Date: 2026-07-07
    Version: 1.0.0
    Repository:
]]--

local mod = get_mod("Lingua Imperialis")

local string_format = string.format
local string_byte   = string.byte
local table_concat  = table.concat
local tonumber      = tonumber

local M = {}

local function resolve_cjson()
    local via_rawget = rawget(_G, "cjson")
    if type(via_rawget) == "table" and via_rawget.decode then
        return via_rawget, "rawget(_G)"
    end

    local mods = rawget(_G, "Mods")
    if type(mods) == "table" and type(mods.lua) == "table"
        and type(mods.lua.cjson) == "table" and mods.lua.cjson.decode then
        return mods.lua.cjson, "Mods.lua"
    end

    local ok_req, req = pcall(require, "cjson")
    if ok_req and type(req) == "table" and req.decode then
        return req, "require"
    end

    return nil, "none"
end

local cjson, cjson_source = resolve_cjson()
M.cjson_source = cjson_source

local MYMEMORY_HOST = "api.mymemory.translated.net"
local GOOGLE_HOST   = "translate.googleapis.com"

local MAX_QUEUE = 32
local MYMEMORY_MAX_BYTES = 480
local QUOTA_COOLDOWN = 300

M.NOOP = "li_noop"

local _inflight = nil
local _translator = nil
local _quota_logged = false
local _quota_until = 0

local function new_queue()
    return { items = {}, head = 1, tail = 0 }
end

local _queue = new_queue()
local _pqueue = new_queue()

local function q_empty(q)
    return q.head > q.tail
end

local function q_count(q)
    return q.tail - q.head + 1
end

local function q_push(q, job)
    q.tail = q.tail + 1
    q.items[q.tail] = job
end

local function q_peek(q)
    return q.items[q.head]
end

local function q_advance(q)
    q.items[q.head] = nil
    q.head = q.head + 1
    if q.head > q.tail then
        q.head = 1
        q.tail = 0
    end
end

local function idle()
    return _inflight == nil and q_empty(_pqueue) and q_empty(_queue)
end

local function url_encode(text)
    return (text:gsub("[^%w%-_%.~]", function(c)
        return string_format("%%%02X", string_byte(c))
    end))
end

local function parse_response(body)
    if type(body) ~= "string" or body == "" then
        return nil, nil, false
    end
    if not (cjson and cjson.decode) then
        return nil, nil, false
    end

    local ok, decoded = pcall(cjson.decode, body)
    if not ok or type(decoded) ~= "table" then
        return nil, nil, false
    end

    local status = tonumber(decoded.responseStatus)
    local quota = decoded.quotaFinished == true
    local translated = nil
    local src = nil
    local data = decoded.responseData
    if type(data) == "table" then
        if type(data.translatedText) == "string" then
            translated = data.translatedText
        end
        if type(data.detectedLanguage) == "string" then
            src = data.detectedLanguage
        end
    end
    return translated, status, quota, src
end

local function parse_google(body)
    if type(body) ~= "string" or body == "" then
        return nil, nil, false
    end
    if not (cjson and cjson.decode) then
        return nil, nil, false
    end

    local ok, decoded = pcall(cjson.decode, body)
    if not ok or type(decoded) ~= "table" or type(decoded[1]) ~= "table" then
        return nil, nil, false
    end

    local sentences = decoded[1]
    local parts = {}
    local count = 0
    for i = 1, #sentences do
        local seg = sentences[i]
        if type(seg) == "table" and type(seg[1]) == "string" then
            count = count + 1
            parts[count] = seg[1]
        end
    end
    if count == 0 then
        return nil, nil, false
    end
    local src = type(decoded[3]) == "string" and decoded[3] or nil
    return table_concat(parts), nil, false, src
end

local function build_request(provider, text, target)
    if provider == "google" then
        local path = "/translate_a/single?client=gtx&sl=auto&tl=" .. target
            .. "&dt=t&q=" .. url_encode(text)
        return GOOGLE_HOST, path
    end

    local path = "/get?q=" .. url_encode(text) .. "&langpair=Autodetect%7C" .. target
    return MYMEMORY_HOST, path
end

local function parse_by_provider(provider, body)
    if provider == "google" then
        return parse_google(body)
    end
    return parse_response(body)
end

-- ─────────────────────────────────────────────────────────────
-- Public: queue
-- ─────────────────────────────────────────────────────────────

local function finish(job, on_result, translated, src)
    if job and on_result then
        on_result(job.element, job.idx, job.text, translated, src)
    end
end

function M.enqueue(element, idx, text, target)
    if not element or not idx or not text or text == "" then
        return false
    end

    local job = { element = element, idx = idx, text = text, target = target }

    local q = (type(element) == "table" and element.li_outgoing) and _pqueue or _queue
    if q_count(q) >= MAX_QUEUE then
        return false
    end

    q_push(q, job)
    return true
end

function M.active()
    return _inflight ~= nil
end

function M.clear(on_result)
    if _translator and _translator.http_get_cancel then
        _translator.http_get_cancel()
    end

    if _inflight then
        local job = _inflight
        _inflight = nil
        finish(job, on_result, nil, nil)
    end

    for _, q in ipairs({ _pqueue, _queue }) do
        while not q_empty(q) do
            local job = q_peek(q)
            q_advance(q)
            finish(job, on_result, nil, nil)
        end
    end

    _pqueue = new_queue()
    _queue = new_queue()
end

-- ─────────────────────────────────────────────────────────────
-- Public: per-frame driver
-- ─────────────────────────────────────────────────────────────

local INFLIGHT_TIMEOUT = 20

local function tick_body(translator, provider, now, target_iso, on_result)
    -- ── A request is live: poll it. ──────────────────────────────────────
    if _inflight then
        if now - (_inflight.started or now) > INFLIGHT_TIMEOUT then
            if translator.http_get_cancel then
                translator.http_get_cancel()
            end
            local job = _inflight
            _inflight = nil
            finish(job, on_result, nil, nil)
            return
        end

        local body, status = translator.http_get_poll()
        if status == 0 then
            return
        end

        local job = _inflight
        _inflight = nil

        if status ~= 1 then
            finish(job, on_result, nil, nil)
            return
        end

        local translated, response_status, quota, src = parse_by_provider(job.provider, body)

        if quota then
            if not _quota_logged then
                _quota_logged = true
                mod:warning("%s", mod:localize("rate_limit"))
            end
            _quota_until = now + QUOTA_COOLDOWN
            finish(job, on_result, nil, nil)
            M.clear(on_result)
            return
        end

        if response_status ~= nil and response_status ~= 200 then
            finish(job, on_result, nil, nil)
            return
        end

        if not translated or translated == "" then
            finish(job, on_result, nil, nil)
            return
        end

        if translated == job.text then
            finish(job, on_result, nil, M.NOOP)
            return
        end

        finish(job, on_result, translated, src)
        return
    end

    if now < _quota_until then
        return
    end

    if _quota_until > 0 then
        _quota_until = 0
        _quota_logged = false
    end

    -- ── Idle + work waiting: start the next GET. Outgoing (priority) first. ──
    local q = (not q_empty(_pqueue)) and _pqueue or _queue
    if q_empty(q) then
        return
    end

    local job = q_peek(q)
    if not job then
        q_advance(q)
        return
    end

    local prov = (type(provider) == "string" and provider ~= "" and provider) or "mymemory"
    local target = job.target or ((type(target_iso) == "string" and target_iso ~= "" and target_iso) or "en")

    if prov ~= "google" and #job.text > MYMEMORY_MAX_BYTES then
        q_advance(q)
        finish(job, on_result, nil, nil)
        return
    end

    local host, path = build_request(prov, job.text, target)

    if translator.http_get_start(host, path) then
        q_advance(q)
        job.provider = prov
        job.started = now
        _inflight = job
    end
end

function M.tick(translator, provider, now, target_iso, on_result)
    if not translator or not translator.available then
        return
    end
    _translator = translator

    if idle() then
        return
    end

    local ok, err = pcall(tick_body, translator, provider, now, target_iso, on_result)
    if not ok then
        mod:warning("Lingua Imperialis: online_backend.tick error: %s", tostring(err))
        local job = _inflight
        _inflight = nil
        if job then
            pcall(finish, job, on_result, nil, nil)
        end
    end
end

return M
