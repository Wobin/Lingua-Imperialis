--[[
    Name: Lingua Imperialis
    Author: Wobin
    Date: 2026-07-06
    Version: 1.0.0
    Repository:
]]--

local ffi = Mods.lua.ffi
local bit = rawget(_G, "bit")

local ffi_new    = ffi.new
local ffi_string = ffi.string
local ffi_cast   = ffi.cast
local bit_bor    = bit.bor
local math_min   = math.min

if not pcall(ffi.typeof, "LinguaHttp_CDEF") then
ffi.cdef([[
    typedef struct { int unused; } LinguaHttp_CDEF;

    void* WinHttpOpen(const uint16_t* pszAgentW, uint32_t dwAccessType,
                      const uint16_t* pszProxyW, const uint16_t* pszProxyBypassW,
                      uint32_t dwFlags);
    void* WinHttpConnect(void* hSession, const uint16_t* pswzServerName,
                         uint16_t nServerPort, uint32_t dwReserved);
    void* WinHttpOpenRequest(void* hConnect, const uint16_t* pwszVerb,
                             const uint16_t* pwszObjectName, const uint16_t* pwszVersion,
                             const uint16_t* pwszReferrer, const uint16_t** ppwszAcceptTypes,
                             uint32_t dwFlags);
    int WinHttpSendRequest(void* hRequest, const uint16_t* lpszHeaders,
                           uint32_t dwHeadersLength, void* lpOptional, uint32_t dwOptionalLength,
                           uint32_t dwTotalLength, uintptr_t dwContext);
    int WinHttpReceiveResponse(void* hRequest, void* lpReserved);
    int WinHttpQueryDataAvailable(void* hRequest, uint32_t* lpdwNumberOfBytesAvailable);
    int WinHttpReadData(void* hRequest, void* lpBuffer, uint32_t dwNumberOfBytesToRead,
                        uint32_t* lpdwNumberOfBytesRead);
    int WinHttpQueryHeaders(void* hRequest, uint32_t dwInfoLevel, const uint16_t* pwszName,
                            void* lpBuffer, uint32_t* lpdwBufferLength, uint32_t* lpdwIndex);
    int WinHttpCloseHandle(void* hInternet);

    int      MultiByteToWideChar(uint32_t CodePage, uint32_t dwFlags, const char* lpMultiByteStr,
                                 int cbMultiByte, uint16_t* lpWideCharStr, int cchWideChar);
    uint32_t GetLastError(void);
]])
end

local winhttp  = ffi.load("winhttp")
local kernel32 = ffi.load("kernel32")

local WINHTTP_ACCESS_TYPE_DEFAULT_PROXY = 0
local WINHTTP_FLAG_SECURE                = 0x00800000
local WINHTTP_QUERY_CONTENT_LENGTH       = 5
local WINHTTP_QUERY_FLAG_NUMBER          = 0x20000000
local CP_UTF8                            = 65001
local READ_BUFFER_SIZE                   = 65536

local M = {}

local function to_wide(s)
    local needed = kernel32.MultiByteToWideChar(CP_UTF8, 0, s, -1, nil, 0)
    if needed <= 0 then
        return nil
    end
    local buf = ffi_new("uint16_t[?]", needed)
    local written = kernel32.MultiByteToWideChar(CP_UTF8, 0, s, -1, buf, needed)
    if written <= 0 then
        return nil
    end
    return buf
end

local function perform(host, path, use_https, on_chunk, on_progress)
    local w_agent = to_wide("Lingua Imperialis/1.0")
    local w_host  = to_wide(host)
    local w_path  = to_wide(path)
    local w_get   = to_wide("GET")
    if not (w_agent and w_host and w_path and w_get) then
        return false, "to_wide: UTF-16 conversion failed", 0, nil
    end

    local h_session, h_connect, h_request

    local function cleanup()
        if h_request then winhttp.WinHttpCloseHandle(h_request); h_request = nil end
        if h_connect then winhttp.WinHttpCloseHandle(h_connect); h_connect = nil end
        if h_session then winhttp.WinHttpCloseHandle(h_session); h_session = nil end
    end

    local function fail(stage)
        local code = kernel32.GetLastError()
        cleanup()
        return false, ("%s: WinHTTP error %d"):format(stage, tonumber(code)), 0, nil
    end

    h_session = winhttp.WinHttpOpen(w_agent, WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, nil, nil, 0)
    if h_session == nil then
        return fail("WinHttpOpen")
    end

    local port = use_https and 443 or 80
    h_connect = winhttp.WinHttpConnect(h_session, w_host, port, 0)
    if h_connect == nil then
        return fail("WinHttpConnect")
    end

    local req_flags = use_https and WINHTTP_FLAG_SECURE or 0
    h_request = winhttp.WinHttpOpenRequest(h_connect, w_get, w_path, nil, nil, nil, req_flags)
    if h_request == nil then
        return fail("WinHttpOpenRequest")
    end

    if winhttp.WinHttpSendRequest(h_request, nil, 0, nil, 0, 0, 0) == 0 then
        return fail("WinHttpSendRequest")
    end

    if winhttp.WinHttpReceiveResponse(h_request, nil) == 0 then
        return fail("WinHttpReceiveResponse")
    end

    local content_length = nil
    do
        local len_buf  = ffi_new("uint32_t[1]")
        local len_size = ffi_new("uint32_t[1]", 4)
        local info     = bit_bor(WINHTTP_QUERY_CONTENT_LENGTH, WINHTTP_QUERY_FLAG_NUMBER)
        if winhttp.WinHttpQueryHeaders(h_request, info, nil,
                ffi_cast("void*", len_buf), ffi_cast("uint32_t*", len_size), nil) ~= 0 then
            content_length = tonumber(len_buf[0])
            if content_length == 0 then
                content_length = nil
            end
        end
    end

    local avail_ptr = ffi_new("uint32_t[1]")
    local read_ptr  = ffi_new("uint32_t[1]")
    local buffer    = ffi_new("uint8_t[?]", READ_BUFFER_SIZE)
    local total     = 0

    while true do
        if winhttp.WinHttpQueryDataAvailable(h_request, avail_ptr) == 0 then
            return fail("WinHttpQueryDataAvailable")
        end
        local avail = tonumber(avail_ptr[0])
        if avail == 0 then
            break
        end

        local to_read = math_min(avail, READ_BUFFER_SIZE)
        if winhttp.WinHttpReadData(h_request, buffer, to_read, read_ptr) == 0 then
            return fail("WinHttpReadData")
        end
        local got = tonumber(read_ptr[0])
        if got == 0 then
            break
        end

        on_chunk(ffi_string(buffer, got))
        total = total + got
        if on_progress then
            on_progress(total, content_length)
        end
    end

    cleanup()
    return true, nil, total, content_length
end

function M.get(host, path, use_https)
    local parts = {}
    local ok, err = perform(host, path, use_https, function(chunk)
        parts[#parts + 1] = chunk
    end, nil)
    if not ok then
        return false, err
    end
    return true, table.concat(parts)
end

function M.download(host, path, use_https, out_path, on_progress)
    local f, ferr = io.open(out_path, "wb")
    if not f then
        return false, ("io.open: %s"):format(tostring(ferr))
    end

    local write_err
    local ok, err = perform(host, path, use_https, function(chunk)
        if not write_err then
            local wok, werr = f:write(chunk)
            if not wok then
                write_err = werr or "file write failed"
            end
        end
    end, on_progress)

    f:close()

    if write_err then
        return false, ("write: %s"):format(tostring(write_err))
    end
    if not ok then
        return false, err
    end
    return true, nil
end

return M
