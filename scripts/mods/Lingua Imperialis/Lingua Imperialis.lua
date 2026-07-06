--[[
    Name: Lingua Imperialis
    Author: Wobin
    Date: 2026-07-06
    Version: 1.0.0
    Repository:
]]--

local mod = get_mod("Lingua Imperialis")
mod.version = "1.0.0"

local translator  = mod:io_dofile("Lingua Imperialis/scripts/mods/Lingua Imperialis/modules/translator")
local chat_inject = mod:io_dofile("Lingua Imperialis/scripts/mods/Lingua Imperialis/modules/chat_inject")
local settings    = mod:io_dofile("Lingua Imperialis/scripts/mods/Lingua Imperialis/modules/settings")

local string_upper = string.upper
local string_find = string.find
local Localize = nil


mod._ready = false
mod._target_iso = "en"
mod._pending = {}

local CACHE_CAP = 128
local _cache = {}
local _cache_keys = {}
local _cache_head = 1
local _cache_count = 0

local function cache_get(text)
	return _cache[text]
end

local function cache_put(text, translated, tag)
	if _cache[text] ~= nil then
		if translated == nil and _cache[text].txt ~= nil then
			return
		end
		_cache[text].txt = translated
		_cache[text].tag = tag
		return
	end
	_cache[text] = { txt = translated, tag = tag }
	local tail = _cache_head + _cache_count
	_cache_keys[tail] = text
	_cache_count = _cache_count + 1
	if _cache_count > CACHE_CAP then
		local old_key = _cache_keys[_cache_head]
		if old_key ~= nil then
			_cache[old_key] = nil
			_cache_keys[_cache_head] = nil
		end
		_cache_head = _cache_head + 1
		_cache_count = _cache_count - 1
	end
end

local MOD_REL = "../mods/Lingua Imperialis"
local DLL_PATH = MOD_REL .. "/bin/dtranslate.dll"
local LID_PATH = MOD_REL .. "/assets/lid.176.ftz"
local MODEL_DIR = "C:/Program Files (x86)/Steam/steamapps/common/Warhammer 40,000 DARKTIDE/tools/src/lingua-imperialis-native/model-int8"

local CHAT_ELEMENT_PATH = "scripts/ui/constant_elements/elements/chat/constant_element_chat"

local function is_own(self, sender, channel)
	if not sender or not channel or not channel.tag then
		return false
	end
	local ok, own = pcall(function()
		local channel_name = self:_channel_name(channel.tag, false, channel.channel_name)
		return Localize("loc_chat_own_player", true, { channel_name = channel_name })
	end)
	return ok and own == sender
end


function mod._on_incoming(chat_element, text, log_index, channel_tag)
	if not text or text == "" then
		return
	end

	if not settings.cache.enabled then
		return
	end

	if channel_tag then
		local tag = string_upper(channel_tag)
		local channels = settings.cache.channels
		if channels[tag] ~= nil and channels[tag] == false then
			return
		end
	end

	local cached = cache_get(text)
	if cached then
		if cached.txt then
			chat_inject.append(chat_element, log_index, text, cached.txt, cached.tag)
		end
		return
	end

	if not mod._ready then
		return
	end

	local job = translator.submit(text, mod._target_iso or "en")
	if job then
		mod._pending[job] = { element = chat_element, idx = log_index, text = text, at = mod._clock or 0 }
	end
end

function mod.update(dt)
	if not mod._ready then
		return
	end

	if not settings.cache.enabled then
		return
	end

	mod._clock = (mod._clock or 0) + (dt or 0)
	local now = mod._clock
	local ok = pcall(function()
		for id, p in pairs(mod._pending) do
			if type(p) == "table" and p.at and (now - p.at) > 15 then
				mod._pending[id] = nil
			end
		end
	end)
	if not ok then
		mod._pending = {}
	end

	for _ = 1, 8 do
		local id, src_iso, txt, status = translator.poll()
		if not id then
			break
		end

		local p = mod._pending[id]
		mod._pending[id] = nil

		if p then
			if p.test then
				if status == 1 and txt and txt ~= "" then
					mod:echo(string.format("[li] %s -> %q", src_iso or "?", txt))
				elseif status == 2 then
					mod:echo(string.format("[li] detected %q, skipped (%s)", src_iso or "?", (txt ~= "" and txt) or "same language / unmapped"))
				elseif status == -1 then
					mod:echo("[li] translation error")
				end
			elseif status == 1 and txt and txt ~= "" then
				local tag = string_upper(src_iso or "")
				chat_inject.append(p.element, p.idx, p.text, txt, tag)
				cache_put(p.text, txt, tag)
			elseif status == 2 or status == -1 then
				cache_put(p.text, nil, nil)
			elseif status == 1 then
				cache_put(p.text, nil, nil)
			end
		end
	end
end

mod:command("li_translate", "Lingua Imperialis: translate a test string", function(...)
	local text = table.concat({ ... }, " ")
	if text == "" then
		mod:echo("[li] usage: /li_translate <text>")
		return
	end
	if not mod._ready then
		mod:echo("[li] translator not ready (model still loading or failed) - see console")
		return
	end
	local job = translator.submit(text, mod._target_iso or "en")
	if not job then
		mod:echo("[li] submit failed (translator busy or rejected input)")
		return
	end
	mod._pending[job] = { test = true, text = text, at = mod._clock or 0 }
end)

function mod.on_all_mods_loaded()
	mod:info(mod.version)

	settings.refresh()
	mod._target_iso = settings.cache.target_iso or "en"

	Localize = Managers.localization and function(...) return Managers.localization:localize(...) end or nil

	mod:hook_safe(CHAT_ELEMENT_PATH, "_add_message", function(self, message, sender, channel)
		if not self or not channel then
			return
		end
		local idx = self._last_message_index
		if not idx or idx == 0 then
			return
		end
		if is_own(self, sender, channel) then
			return
		end
		mod._on_incoming(self, message, idx, channel.tag)
	end)

	if translator.load(DLL_PATH) then
		if translator.init(MODEL_DIR, LID_PATH) then
			mod._ready = true
			mod:info("Lingua Imperialis: translator ready (model=%s)", MODEL_DIR)
		else
			mod:warning("Lingua Imperialis: translator.init failed - is the model present at %s ?", MODEL_DIR)
		end
	else
		mod:warning("Lingua Imperialis: dtranslate.dll failed to load; translation disabled")
	end
end

function mod.on_setting_changed(id)
	settings.refresh()
	mod._target_iso = settings.cache.target_iso or "en"
end

function mod.on_unload(exit_game)
	if mod._ready then
		translator.shutdown()
		mod._ready = false
	end
end
