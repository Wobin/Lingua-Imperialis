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
    int         dt_mkdir(const char* path);
    int         dt_download_start(const char* host, const char* path, int use_https,
                                  const char* out_path, long long resume_from);
    int         dt_download_poll(long long* out_bytes, long long* out_total, int* out_status);
    void        dt_download_cancel(void);
    int         dt_sha256(const char* path, char* out_hex, int out_len);
    int         dt_sha256_start(const char* path);
    int         dt_sha256_poll(char* out_hex, int out_len, long long* out_bytes,
                               long long* out_total, int* out_status);
    void        dt_sha256_cancel(void);
    int         dt_http_get_start(const char* host, const char* path);
    int         dt_http_get_poll(char* out_body, int out_len, int* out_status);
    void        dt_http_get_cancel(void);
]])
end

local M = { available = false }
local C

local jid  = ffi_new("int[1]")
local stat = ffi_new("int[1]")
local src  = ffi_new("char[16]")
local buf  = ffi_new("char[2048]")

local dl_bytes  = ffi_new("int64_t[1]")
local dl_total  = ffi_new("int64_t[1]")
local dl_status = ffi_new("int[1]")

local sha_buf   = ffi_new("char[65]")
local sha_bytes = ffi_new("int64_t[1]")
local sha_total = ffi_new("int64_t[1]")
local sha_status = ffi_new("int[1]")

local http_buf    = ffi_new("char[65536]")
local http_status = ffi_new("int[1]")

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
    if not M.available then return false, "dll not loaded" end
    local ok, rc = pcall(C.dt_init, model_dir, lid_path)
    if not ok then
        return false, tostring(rc)
    end
    return rc == 0, tonumber(rc)
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

function M.mkdir(path)
    if not M.available then return false end
    local ok, rc = pcall(C.dt_mkdir, path)
    return ok and rc == 0
end

function M.download_start(host, path, use_https, out_path, resume_from)
    if not M.available then return false end
    local ok, rc = pcall(C.dt_download_start, host, path,
        use_https and 1 or 0, out_path, resume_from or 0)
    return ok and rc == 0
end

function M.download_poll()
    if not M.available then return 0, -1, -1 end
    local ok = pcall(C.dt_download_poll, dl_bytes, dl_total, dl_status)
    if not ok then return 0, -1, -1 end
    return tonumber(dl_bytes[0]), tonumber(dl_total[0]), dl_status[0]
end

function M.download_cancel()
    if not M.available then return end
    pcall(C.dt_download_cancel)
end

function M.sha256(path)
    if not M.available then return nil end
    local ok, rc = pcall(C.dt_sha256, path, sha_buf, 65)
    if ok and rc == 0 then return ffi_string(sha_buf) end
    return nil
end

function M.sha256_start(path)
    if not M.available then return false end
    local ok, rc = pcall(C.dt_sha256_start, path)
    return ok and rc == 0
end

function M.sha256_poll()
    if not M.available then return nil, 0, -1, -1 end
    local ok = pcall(C.dt_sha256_poll, sha_buf, 65, sha_bytes, sha_total, sha_status)
    if not ok then return nil, 0, -1, -1 end
    local st = sha_status[0]
    local hex = (st == 1) and ffi_string(sha_buf) or nil
    return hex, tonumber(sha_bytes[0]), tonumber(sha_total[0]), st
end

function M.sha256_cancel()
    if not M.available then return end
    pcall(C.dt_sha256_cancel)
end

function M.http_get_start(host, path)
    if not M.available then return false end
    local ok, rc = pcall(C.dt_http_get_start, host, path)
    return ok and rc == 0
end

function M.http_get_poll()
    if not M.available then return nil, -1 end
    local ok = pcall(C.dt_http_get_poll, http_buf, 65536, http_status)
    if not ok then return nil, -1 end
    local st = http_status[0]
    local body = (st == 1) and ffi_string(http_buf) or nil
    return body, st
end

function M.http_get_cancel()
    if not M.available then return end
    pcall(C.dt_http_get_cancel)
end

return M
