--[[
    Name: Lingua Imperialis
    Author: Wobin
    Date: 2026-07-06
    Version: 1.0.0
    Repository:
]]--

local mod = get_mod("Lingua Imperialis")

local progress_hud = mod:io_dofile("Lingua Imperialis/scripts/mods/Lingua Imperialis/modules/progress_hud")

local math_floor = math.floor

-- ─────────────────────────────────────────────────────────────
-- Pinned release constants (two mutually-exclusive models)
-- ─────────────────────────────────────────────────────────────
local HOST = "github.com"
local USE_HTTPS = true

local CONFIG_SIZE = 233
local VOCAB_SIZE  = 6177383
local SPM_SIZE    = 4852054

local MODELS = {
    small = {
        subdir = "model",
        path   = "/Wobin/Lingua-Imperialis/releases/download/model-v1/",
        sha256 = "398726640cc2a02cc6a35277fa3cf2159ce8a1a66b48aa1b6c8837a47e3dd00c",
        files  = {
            { name = "config.json",             size = CONFIG_SIZE },
            { name = "shared_vocabulary.json",  size = VOCAB_SIZE },
            { name = "sentencepiece.bpe.model", size = SPM_SIZE },
            { name = "model.bin",               size = 622596105 },
        },
    },
    large = {
        subdir = "model-large",
        path   = "/Wobin/Lingua-Imperialis/releases/download/model-large-v1/",
        sha256 = "8ddec65e4b3cfe07d687353743b4721e5e62afcd34cde21f0a68fb8d935ef08b",
        files  = {
            { name = "config.json",             size = CONFIG_SIZE },
            { name = "shared_vocabulary.json",  size = VOCAB_SIZE },
            { name = "sentencepiece.bpe.model", size = SPM_SIZE },
            { name = "model.bin",               size = 1381827201 },
        },
    },
}

local BIN_NAME = "model.bin"

local OTHER = { small = "large", large = "small" }

local _translator = nil

local os_getenv  = Mods.lua.os and Mods.lua.os.getenv
local os_execute = Mods.lua.os and Mods.lua.os.execute
local os_remove  = Mods.lua.os and Mods.lua.os.remove
local io_open    = Mods.lua.io and Mods.lua.io.open

local M = {}

local _active = nil

-- ─────────────────────────────────────────────────────────────
-- Filesystem helpers
-- ─────────────────────────────────────────────────────────────
local function join(dir, name)
    return dir .. "\\" .. name
end

local function file_size(path)
    if not io_open then return nil end
    local f = io_open(path, "rb")
    if not f then return nil end
    local sz = f:seek("end")
    f:close()
    return sz
end

local function ensure_dir(dir)
    if not dir then return end
    if _translator and _translator.mkdir then
        local ok, made = pcall(function() return _translator.mkdir(dir) end)
        if ok and made then return end
    end
    if os_execute then
        os_execute(('mkdir "%s" 2>nul'):format(dir))
    end
end

local function resolve_root()
    if not os_getenv then
        return nil, "Mods.lua.os.getenv unavailable"
    end
    local appdata = os_getenv("APPDATA")
    if not appdata or appdata == "" then
        return nil, "APPDATA not set"
    end
    local root = appdata .. "\\LinguaImperialis"
    ensure_dir(root)
    return root
end

local function resolve_dir(which)
    local m = MODELS[which]
    if not m then
        return nil, "unknown model " .. tostring(which)
    end
    local root, err = resolve_root()
    if not root then
        return nil, err
    end
    local dir = root .. "\\" .. m.subdir
    ensure_dir(dir)
    return dir
end

local function file_complete(path, want_size)
    local sz = file_size(path)
    if not sz then
        return false
    end
    if want_size and want_size > 0 and sz ~= want_size then
        return false
    end
    return true
end

local function model_total_size(which)
    local m = MODELS[which]
    local total = 0
    for i = 1, #m.files do
        total = total + (m.files[i].size or 0)
    end
    return total
end

-- ─────────────────────────────────────────────────────────────
-- Marker (<root>\downloading.txt = "small" | "large")
-- ─────────────────────────────────────────────────────────────
local function marker_path()
    local root = resolve_root()
    if not root then
        return nil
    end
    return root .. "\\downloading.txt"
end

local function write_marker(which)
    local p = marker_path()
    if not p or not io_open then
        return
    end
    local f = io_open(p, "wb")
    if f then
        f:write(which)
        f:close()
    end
end

local function remove_marker()
    local p = marker_path()
    if p and os_remove then
        os_remove(p)
    end
end

local function read_marker()
    local p = marker_path()
    if not p or not io_open then
        return nil
    end
    local f = io_open(p, "rb")
    if not f then
        return nil
    end
    local data = f:read("*a")
    f:close()
    if not data then
        return nil
    end
    local which = data:gsub("%s+", "")
    if MODELS[which] then
        return which
    end
    return nil
end

-- ─────────────────────────────────────────────────────────────
-- Public: translator wiring
-- ─────────────────────────────────────────────────────────────

function M.set_translator(t)
    _translator = t
end

-- ─────────────────────────────────────────────────────────────
-- Public: completeness / marker / state
-- ─────────────────────────────────────────────────────────────

function M.is_complete(which)
    local ok, present = pcall(function()
        local m = MODELS[which]
        if not m then
            return false
        end
        local dir = resolve_dir(which)
        if not dir then
            return false
        end
        for i = 1, #m.files do
            if not file_complete(join(dir, m.files[i].name), m.files[i].size) then
                return false
            end
        end
        return true
    end)
    return (ok and present) and true or false
end

local function verify_sync(which)
    local ok, valid = pcall(function()
        local m = MODELS[which]
        if not m or not M.is_complete(which) then
            return false
        end
        local dir = resolve_dir(which)
        if not dir then
            return false
        end
        local bin = join(dir, BIN_NAME)
        if not _translator or not _translator.sha256 then
            mod:warning("Lingua Imperialis: sha256 binding unavailable - cannot verify model, translation disabled.")
            return false
        end
        progress_hud.set(mod:localize("verifying"))
        local hok, got = pcall(function() return _translator.sha256(bin) end)
        progress_hud.clear()
        if not hok then got = nil end
        if type(got) == "string" then got = got:lower() end
        if got and got == m.sha256 then
            return true
        end
        mod:warning("Lingua Imperialis: %s model.bin checksum mismatch (got %s, want %s)",
            tostring(which), tostring(got), m.sha256)
        return false
    end)
    return (ok and valid) and true or false
end

function M.verify_start(which, translator, on_result)
    local fired = false
    local function done(v)
        if fired then return end
        fired = true
        if on_result then on_result(v and true or false) end
    end
    local ok, err = pcall(function()
        local m = MODELS[which]
        if not m or not M.is_complete(which) then
            done(false)
            return
        end
        local dir = resolve_dir(which)
        if not dir then
            done(false)
            return
        end
        local bin = join(dir, BIN_NAME)
        _translator = translator or _translator
        if not _translator or not _translator.sha256 then
            mod:warning("Lingua Imperialis: sha256 binding unavailable - cannot verify model, translation disabled.")
            done(false)
            return
        end

        if _translator.sha256_start and _translator.sha256_poll then
            if _translator.sha256_start(bin) then
                _active = {
                    phase      = "verify",
                    which      = which,
                    translator = _translator,
                    pinned     = m.sha256,
                    label      = mod:localize("verifying"),
                    on_result  = done,
                }
                progress_hud.set(_active.label)
                return
            end
        end

        done(verify_sync(which))
    end)
    if not ok then
        mod:warning("Lingua Imperialis: verify_start error: %s", tostring(err))
        _active = nil
        done(false)
    end
end

function M.marker_model()
    local ok, which = pcall(read_marker)
    if ok then
        return which
    end
    return nil
end

function M.active()
    return _active ~= nil
end

function M.active_which()
    return _active and _active.which or nil
end

-- ─────────────────────────────────────────────────────────────
-- Deletion
-- ─────────────────────────────────────────────────────────────

function M.delete(which)
    pcall(function()
        local m = MODELS[which]
        if not m then
            return
        end
        local dir = resolve_dir(which)
        if not dir then
            return
        end
        if os_remove then
            for i = 1, #m.files do
                os_remove(join(dir, m.files[i].name))
            end
        end
        if os_execute then
            os_execute(('rmdir "%s" 2>nul'):format(dir))
        end
    end)
end

-- ─────────────────────────────────────────────────────────────
-- Init (present-only; never downloads)
-- ─────────────────────────────────────────────────────────────

function M.init(which, translator, lid_path)
    local ok, ready = pcall(function()
        if not M.is_complete(which) then
            return false
        end
        local dir = resolve_dir(which)
        if not dir then
            return false
        end
        if translator.shutdown then translator.shutdown() end
        if translator.init(dir, lid_path) then
            mod:info("Lingua Imperialis: translator ready (model=%s)", dir)
            return true
        end
        mod:warning("Lingua Imperialis: translator.init failed at %s - translation disabled.", dir)
        return false
    end)
    return (ok and ready) and true or false
end

-- ─────────────────────────────────────────────────────────────
-- Download internals
-- ─────────────────────────────────────────────────────────────

local function completed_before(which, file_index)
    local m = MODELS[which]
    local sum = 0
    for i = 1, file_index - 1 do
        sum = sum + (m.files[i].size or 0)
    end
    return sum
end

local function first_incomplete(which)
    local m = MODELS[which]
    local dir = resolve_dir(which)
    if not dir then
        return nil
    end
    for i = 1, #m.files do
        if not file_complete(join(dir, m.files[i].name), m.files[i].size) then
            return i
        end
    end
    return nil
end

local function fallback_warning(which)
    local m = MODELS[which]
    local dir = resolve_dir(which) or "(cache dir)"
    mod:warning("Lingua Imperialis: translation model download failed - translation disabled (chat still works).")
    mod:warning("Lingua Imperialis: to install manually, download these files:")
    for i = 1, #m.files do
        mod:warning("  https://%s%s%s", HOST, m.path, m.files[i].name)
    end
    mod:warning("Lingua Imperialis: place them into: %s", dir)
end

local function fail(which, on_done)
    progress_hud.clear()
    fallback_warning(which)
    M.delete(which)
    remove_marker()
    _active = nil
    if on_done then
        on_done(false)
    end
end

local function begin_file(which, file_index, translator, lid_path, on_done, label)
    local m = MODELS[which]
    local dir, derr = resolve_dir(which)
    if not dir then
        mod:warning("Lingua Imperialis: cannot resolve model dir: %s", tostring(derr))
        fail(which, on_done)
        return false
    end
    local entry = m.files[file_index]
    local dest = join(dir, entry.name)

    local cur = file_size(dest) or 0
    local resume_from = (cur > 0 and cur < entry.size) and cur or 0

    mod:info("Lingua Imperialis: fetching %s (resume_from=%d) ...", entry.name, resume_from)
    if not translator.download_start(HOST, m.path .. entry.name, USE_HTTPS, dest, resume_from) then
        mod:warning("Lingua Imperialis: download_start failed for %s", entry.name)
        fail(which, on_done)
        return false
    end

    _active = {
        phase      = "download",
        which      = which,
        translator = translator,
        lid_path   = lid_path,
        file_index = file_index,
        on_done    = on_done,
        label      = label,
    }
    progress_hud.set(label)
    return true
end

local function finish_verified(which, translator, lid_path, on_done)
    remove_marker()
    local dir = resolve_dir(which)
    if translator.shutdown then translator.shutdown() end
    local ready = false
    if dir and translator.init(dir, lid_path) then
        mod:info("Lingua Imperialis: translator ready (model=%s)", dir)
        ready = true
    else
        mod:warning("Lingua Imperialis: translator.init failed at %s", tostring(dir))
    end
    if ready then
        local other = OTHER[which]
        if M.is_complete(other) then
            M.delete(other)
        end
    end
    progress_hud.clear()
    if on_done then on_done(ready) end
end

local function verify_and_finish(which, translator, lid_path, on_done)
    M.verify_start(which, translator, function(passed)
        if not passed then
            mod:warning("Lingua Imperialis: %s failed checksum verification", tostring(which))
            fail(which, on_done)
            return
        end
        finish_verified(which, translator, lid_path, on_done)
    end)
end

-- ─────────────────────────────────────────────────────────────
-- Public: start / tick / cancel
-- ─────────────────────────────────────────────────────────────

function M.start(which, translator, lid_path, on_done)
    local ok, err = pcall(function()
        if not MODELS[which] then
            if on_done then on_done(false) end
            return
        end

        _translator = translator
        write_marker(which)

        local idx = first_incomplete(which)
        if not idx then
            verify_and_finish(which, translator, lid_path, on_done)
            return
        end

        local label = mod:localize("download_progress")
        begin_file(which, idx, translator, lid_path, on_done, label)
    end)

    if not ok then
        mod:warning("Lingua Imperialis: model_fetch.start error: %s", tostring(err))
        _active = nil
        remove_marker()
        if on_done then on_done(false) end
    end
end

local VERIFY_TIMEOUT = 120
local DOWNLOAD_STALL_TIMEOUT = 90

function M.tick(now)
    if not _active then
        return
    end
    now = now or 0

    local ok, err = pcall(function()
        local a = _active

        -- ── Verify phase: poll the DLL's worker-thread SHA-256 ────────────────
        if a.phase == "verify" then
            local translator = a.translator
            if a.started == nil then a.started = now end
            if (now - a.started) > VERIFY_TIMEOUT then
                if translator and translator.sha256_cancel then
                    translator.sha256_cancel()
                end
                mod:warning("Lingua Imperialis: %s verify timed out - falling back to online.", tostring(a.which))
                local on_result = a.on_result
                progress_hud.clear()
                _active = nil
                if on_result then on_result(false) end
                return
            end
            local hex, bytes, total, status = translator.sha256_poll()
            if status == 0 then
                local pct = 0
                if total and total > 0 then
                    pct = math_floor((bytes / total) * 100)
                    if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
                    progress_hud.set(("%s %3d%%"):format(a.label, pct))
                else
                    progress_hud.set(a.label)
                end
                return
            end
            local on_result = a.on_result
            local passed = (status == 1) and hex and (hex:lower() == a.pinned) and true or false
            if status == 1 and not passed then
                mod:warning("Lingua Imperialis: %s model.bin checksum mismatch (got %s, want %s)",
                    tostring(a.which), tostring(hex), a.pinned)
            elseif status ~= 1 then
                mod:warning("Lingua Imperialis: %s hash error (status=%s)", tostring(a.which), tostring(status))
            end
            progress_hud.clear()
            _active = nil
            if on_result then on_result(passed) end
            return
        end

        -- ── Download phase ────────────────────────────────────────────────────
        local which = a.which
        local translator = a.translator
        local bytes, total, status = translator.download_poll()

        if status == 0 then
            local cur = bytes or 0
            if a.last_bytes == nil or cur > a.last_bytes then
                a.last_bytes = cur
                a.last_progress_at = now
            elseif a.last_progress_at and (now - a.last_progress_at) > DOWNLOAD_STALL_TIMEOUT then
                if translator and translator.download_cancel then
                    translator.download_cancel()
                end
                mod:warning("Lingua Imperialis: %s download stalled (no progress) - aborting.", tostring(which))
                fail(which, a.on_done)
                return
            end
            local done = completed_before(which, a.file_index) + (bytes or 0)
            local model_total = model_total_size(which)
            local pct = 0
            if model_total > 0 then
                pct = math_floor((done / model_total) * 100)
                if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
            end
            local done_mb = math_floor(done / 1048576 + 0.5)
            local total_mb = math_floor(model_total / 1048576 + 0.5)
            progress_hud.set(("%s %3d%% (%4d/%4d MB)"):format(a.label, pct, done_mb, total_mb))
            return
        end

        if status == 1 then
            local m = MODELS[which]
            local dir = resolve_dir(which)
            local entry = m.files[a.file_index]
            if not (dir and file_complete(join(dir, entry.name), entry.size)) then
                mod:warning("Lingua Imperialis: %s size mismatch after download", entry.name)
                fail(which, a.on_done)
                return
            end

            local nxt = first_incomplete(which)
            if nxt then
                begin_file(which, nxt, translator, a.lid_path, a.on_done, a.label)
                return
            end

            if not M.is_complete(which) then
                mod:warning("Lingua Imperialis: model incomplete after final file")
                fail(which, a.on_done)
                return
            end
            local on_done = a.on_done
            local lid_path = a.lid_path
            _active = nil
            verify_and_finish(which, translator, lid_path, on_done)
            return
        end

        fail(which, a.on_done)
    end)

    if not ok then
        mod:warning("Lingua Imperialis: model_fetch.tick error: %s", tostring(err))
        local a = _active
        _active = nil
        progress_hud.clear()
        remove_marker()
        local cb = a and (a.on_result or a.on_done)
        if cb then cb(false) end
    end
end

function M.cancel()
    pcall(function()
        local a = _active
        if not a then
            return
        end
        if a.phase == "verify" then
            if a.translator and a.translator.sha256_cancel then
                a.translator.sha256_cancel()
            end
            progress_hud.clear()
            _active = nil
            return
        end
        if a.translator and a.translator.download_cancel then
            a.translator.download_cancel()
        end
        M.delete(a.which)
        remove_marker()
        progress_hud.clear()
        _active = nil
    end)
end

return M
