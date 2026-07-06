--[[
    Name: Lingua Imperialis
    Author: Wobin
    Date: 2026-07-06
    Version: 1.0.0
    Repository:
]]--

local ffi = Mods.lua.ffi

local ffi_load   = ffi.load
local ffi_new    = ffi.new
local ffi_string = ffi.string

if not pcall(ffi.typeof, "LinguaTranslate_CDEF") then
ffi.cdef([[
    typedef struct { int unused; } LinguaTranslate_CDEF;
    int         dt_init(const char* model_dir, const char* lid_model_path);
    void        dt_shutdown(void);
    int         dt_submit(const char* utf8_text, const char* target_iso);
    int         dt_poll(int* out_job_id, char* out_src_iso, int src_iso_len,
                        char* out_text, int out_text_len, int* out_status);
    const char* dt_version(void);
]])
end

local M = { available = false }
local C

local jid  = ffi_new("int[1]")
local stat = ffi_new("int[1]")
local src  = ffi_new("char[16]")
local buf  = ffi_new("char[2048]")

function M.load(dll_path)
    if M.available then return true end
    local ok, lib = pcall(ffi_load, dll_path or "dtranslate")
    if ok and lib then
        C = lib
        M.available = true
        return true
    end
    return false
end

function M.init(model_dir, lid_path)
    if not M.available then return false end
    local ok, rc = pcall(C.dt_init, model_dir, lid_path)
    return ok and rc == 0
end

function M.shutdown()
    if not M.available then return end
    pcall(C.dt_shutdown)
end

function M.submit(text, target_iso)
    if not M.available then return nil end
    local ok, id = pcall(C.dt_submit, text, target_iso)
    if ok and id > 0 then return id end
    return nil
end

function M.poll()
    if not M.available then return nil end
    local ok, rc = pcall(C.dt_poll, jid, src, 16, buf, 2048, stat)
    if ok and rc == 1 then
        return jid[0], ffi_string(src), ffi_string(buf), stat[0]
    end
    return nil
end

function M.version()
    if not M.available then return nil end
    local ok, v = pcall(C.dt_version)
    if ok and v ~= nil then return ffi_string(v) end
    return nil
end

return M
