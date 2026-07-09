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

    local ok_bare, via_bare = pcall(function() return cjson end)
    if ok_bare and type(via_bare) == "table" and via_bare.decode then
        return via_bare, "global"
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

local _queue = {}
local _qhead = 1
local _qtail = 0
local _inflight = nil
local _translator = nil
local _quota_logged = false

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

local function build_request(provider, text, target, email)
    if provider == "google" then
        local path = "/translate_a/single?client=gtx&sl=auto&tl=" .. target
            .. "&dt=t&q=" .. url_encode(text)
        return GOOGLE_HOST, path
    end

    local path = "/get?q=" .. url_encode(text) .. "&langpair=Autodetect|" .. target
    if type(email) == "string" and email ~= "" then
        path = path .. "&de=" .. url_encode(email)
    end
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

function M.enqueue(element, idx, text, target)
    if not element or not idx or not text or text == "" then
        return
    end
    _qtail = _qtail + 1
    _queue[_qtail] = { element = element, idx = idx, text = text, target = target }
end

local function queue_empty()
    return _qhead > _qtail
end

local function pop()
    local job = _queue[_qhead]
    _queue[_qhead] = nil
    _qhead = _qhead + 1
    if _qhead > _qtail then
        _qhead = 1
        _qtail = 0
    end
    return job
end

function M.active()
    return _inflight ~= nil
end

function M.clear()
    pcall(function()
        if _translator and _translator.http_get_cancel then
            _translator.http_get_cancel()
        end
    end)
    _queue = {}
    _qhead = 1
    _qtail = 0
    _inflight = nil
end

-- ─────────────────────────────────────────────────────────────
-- Public: per-frame driver
-- ─────────────────────────────────────────────────────────────

local INFLIGHT_TIMEOUT = 20

local function tick_body(translator, provider, now, target_iso, email, on_result)
    -- ── A request is live: poll it. ──────────────────────────────────────
    if _inflight then
        if now - (_inflight.started or now) > INFLIGHT_TIMEOUT then
            if translator.http_get_cancel then
                translator.http_get_cancel()
            end
            _inflight = nil
            return
        end

        local body, status = translator.http_get_poll()
        if status == 0 then
            return
        end

        local job = _inflight
        _inflight = nil

        if status ~= 1 then
            return
        end

        local translated, response_status, quota, src = parse_by_provider(job.provider, body)

        if quota then
            if not _quota_logged then
                _quota_logged = true
                mod:warning("%s", mod:localize("rate_limit"))
            end
            return
        end

        if response_status ~= nil and response_status ~= 200 then
            return
        end

        if not translated or translated == "" then
            return
        end

        if translated == job.text then
            return
        end

        if on_result then
            on_result(job.element, job.idx, job.text, translated, src)
        end
        return
    end

    -- ── Idle + work waiting: start the next GET. ─────────────────────────
    if queue_empty() then
        return
    end

    local job = pop()
    if not job then
        return
    end

    local prov = (type(provider) == "string" and provider ~= "" and provider) or "mymemory"
    local target = job.target or ((type(target_iso) == "string" and target_iso ~= "" and target_iso) or "en")
    local host, path = build_request(prov, job.text, target, email)

    local started = translator.http_get_start(host, path)
    if started then
        job.provider = prov
        job.started = now
        _inflight = job
    end
end

function M.tick(translator, provider, now, target_iso, email, on_result)
    if not translator or not translator.available then
        return
    end
    _translator = translator

    local ok, err = pcall(tick_body, translator, provider, now, target_iso, email, on_result)
    if not ok then
        mod:warning("Lingua Imperialis: online_backend.tick error: %s", tostring(err))
        _inflight = nil
    end
end

return M
