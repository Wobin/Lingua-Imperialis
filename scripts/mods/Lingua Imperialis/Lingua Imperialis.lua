--[[
    Name: Lingua Imperialis
    Author: Wobin
    Date: 2026-07-08
    Version: 1.1.0
    Repository:
]]--

local mod = get_mod("Lingua Imperialis")
mod.version = "1.1.0"

local translator      = mod:io_dofile("Lingua Imperialis/scripts/mods/Lingua Imperialis/modules/translator")
local chat_inject     = mod:io_dofile("Lingua Imperialis/scripts/mods/Lingua Imperialis/modules/chat_inject")
local settings        = mod:io_dofile("Lingua Imperialis/scripts/mods/Lingua Imperialis/modules/settings")
local model_fetch     = mod:io_dofile("Lingua Imperialis/scripts/mods/Lingua Imperialis/modules/model_fetch")
local online_backend  = mod:io_dofile("Lingua Imperialis/scripts/mods/Lingua Imperialis/modules/online_backend")
local progress_hud = mod:io_dofile("Lingua Imperialis/scripts/mods/Lingua Imperialis/modules/progress_hud")
local outgoing        = mod:io_dofile("Lingua Imperialis/scripts/mods/Lingua Imperialis/modules/outgoing")

local string_upper = string.upper
local Localize = nil


mod._offline_ready = false
mod._target_iso = "en"
mod._pending = {}
mod._TEST = {}
mod._last_engine = nil

function mod._engine()
	return settings.cache.provider == "offline" and "offline" or "online"
end

mod._suppress_setting = false

local MOD_REL = "../mods/Lingua Imperialis"
local DLL_PATH = MOD_REL .. "/bin/dtranslate.dll"
local LID_PATH = MOD_REL .. "/assets/lid.176.ftz"

local WHICH_ID = { small = "download_model", large = "download_model_large" }
local OTHER    = { small = "large", large = "small" }

local function guarded_set(id, value)
	mod._suppress_setting = true
	mod:set(id, value)
	mod._suppress_setting = false
end

local function make_on_done(which)
	return function(ok)
		if ok then
			mod._offline_ready = true
			return
		end
		guarded_set(WHICH_ID[which], false)
		mod._offline_ready = false
		local other = OTHER[which]
		model_fetch.verify_start(other, translator, function(passed)
			if passed and model_fetch.init(other, translator, LID_PATH) then
				guarded_set(WHICH_ID[other], true)
				mod._offline_ready = true
			else
				guarded_set(WHICH_ID[other], false)
				mod._offline_ready = false
			end
		end)
	end
end

local CACHE_CAP = 128
local _cache = {}
local _cache_keys = {}
local _cache_head = 0
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
	if _cache_count >= CACHE_CAP then
		local slot = _cache_head
		local old_key = _cache_keys[slot]
		if old_key ~= nil then
			_cache[old_key] = nil
		end
		_cache_keys[slot] = text
		_cache_head = (_cache_head + 1) % CACHE_CAP
	else
		local slot = (_cache_head + _cache_count) % CACHE_CAP
		_cache_keys[slot] = text
		_cache_count = _cache_count + 1
	end
end

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

local COM_WHEEL_KEYS = {
	"loc_communication_wheel_need_ammo",
	"loc_communication_wheel_need_health",
	"loc_communication_wheel_thanks",
}

local function build_com_wheel_filter()
	mod._com_wheel_filter = {}
	if not Localize then
		return
	end
	for i = 1, #COM_WHEEL_KEYS do
		local ok, s = pcall(Localize, COM_WHEEL_KEYS[i])
		if ok and type(s) == "string" and s ~= "" then
			mod._com_wheel_filter[s] = true
		end
	end
end


function mod._on_incoming(chat_element, text, log_index, channel_tag)
	if not text or text == "" then
		return
	end

	if not settings.cache.enabled then
		return
	end

	if mod._com_wheel_filter and mod._com_wheel_filter[text] then
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

	local engine = mod._engine()
	if engine == "offline" then
		if mod._offline_ready then
			local job = translator.submit(text, mod._target_iso or "en")
			if job then
				mod._pending[job] = { element = chat_element, idx = log_index, text = text, at = mod._clock or 0 }
			end
		end
	elseif engine == "online" and translator.available then
		online_backend.enqueue(chat_element, log_index, text)
	end
end

local function src_to_tag(src)
	if type(src) ~= "string" or src == "" then
		return nil
	end
	local primary = src:match("^(%a+)")
	if not primary or primary == "" then
		return nil
	end
	return string_upper(primary)
end

local function offline_submit_outgoing(text, target, pending)
	if not mod._offline_ready then
		return false
	end
	local job = translator.submit(text, target)
	if not job then
		return false
	end
	mod._pending[job] = { outgoing = pending, at = mod._clock or 0 }
	return true
end

local function online_on_result(element, idx, original, translated, src)
	if element and element.li_outgoing then
		outgoing.deliver(element.pending, translated)
		return
	end
	if element == mod._TEST then
		mod:echo(chat_inject.format(translated, src_to_tag(src)))
		return
	end
	local tag = src_to_tag(src)
	chat_inject.append(element, idx, original, translated, tag)
	cache_put(original, translated, tag)
end

function mod.update(dt)
	mod._clock = (mod._clock or 0) + (dt or 0)
	local now = mod._clock

	outgoing.update(now)

	if model_fetch.active() then
		model_fetch.tick(now)
		return
	end

	local engine = mod._engine()

	-- ── Engine-switch reconcile: on a change, drop the opposite backend's work
	-- so a stale queue can never fire under the newly selected engine. ──────
	if engine ~= mod._last_engine then
		if engine == "offline" then
			pcall(function() online_backend.clear() end)
		else
			mod._pending = {}
		end
		mod._last_engine = engine
	end

	-- ── OFFLINE poll loop: run only when offline is selected, a model is loaded,
	-- and there are offline pending jobs. ───────────────────────────────────
	if engine == "offline" and mod._offline_ready and next(mod._pending) ~= nil then
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

		pcall(function()
			for _ = 1, 8 do
				local id, src_iso, txt, status = translator.poll()
				if not id then
					break
				end

				local p = mod._pending[id]
				mod._pending[id] = nil

				if p then
					if p.outgoing then
							if status == 1 and txt and txt ~= "" then
								outgoing.deliver(p.outgoing, txt)
							else
								outgoing.deliver(p.outgoing, nil)
							end
						elseif p.test then
						if status == 1 and txt and txt ~= "" then
							mod:echo(chat_inject.format(txt, src_iso))
						elseif status == 2 then
							mod:echo(string.format("detected %q, skipped (%s)", src_iso or "?", (txt ~= "" and txt) or "same language / unmapped"))
						elseif status == -1 then
							mod:echo("translation error")
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
		end)
	end

	-- ── ONLINE driver: runs only while the online engine is selected. ───────
	if engine == "online" then
		online_backend.tick(translator, settings.cache.provider, now, settings.cache.target_iso, settings.cache.mymemory_email, online_on_result)
	end
end

mod:command("li_translate", "Lingua Imperialis: translate a test string", function(...)
	local text = table.concat({ ... }, " ")
	if text == "" then
		mod:echo("usage: /li_translate <text>")
		return
	end
	if mod._engine() == "offline" then
		if not mod._offline_ready then
			mod:echo("offline model not ready - download a 600M or 1.3B model first")
			return
		end
		local job = translator.submit(text, mod._target_iso or "en")
		if not job then
			mod:echo("submit failed (translator busy or rejected input)")
			return
		end
		mod._pending[job] = { test = true, text = text, at = mod._clock or 0 }
	elseif translator.available then
		online_backend.enqueue(mod._TEST, 0, text)
	else
		mod:echo("translator unavailable (dtranslate.dll not loaded)")
	end
end)

function mod.on_all_mods_loaded()
	mod:info(mod.version)

	settings.refresh()
	chat_inject.set_color(settings.cache.translation_rgb)
	mod._target_iso = settings.cache.target_iso or "en"

	Localize = Managers.localization and function(...) return Managers.localization:localize(...) end or nil
	build_com_wheel_filter()

	local chat_hook_ok = pcall(function()
		mod:hook_safe(require(CHAT_ELEMENT_PATH), "_add_message", function(self, message, sender, channel)
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
	end)
	if not chat_hook_ok then
		mod:warning("Lingua Imperialis: chat hook registration failed - auto-translation disabled")
	end

	outgoing.setup({
		settings = settings,
		translator = translator,
		online_backend = online_backend,
		offline_submit = offline_submit_outgoing,
	})
	if not outgoing.init() then
		mod:warning("Lingua Imperialis: outgoing chat hook registration failed - outgoing translation disabled")
	end

	if not translator.load(DLL_PATH) then
		mod:warning("Lingua Imperialis: dtranslate.dll failed to load; translation disabled")
		return
	end

	model_fetch.set_translator(translator)

	local function enable_async(which)
		model_fetch.verify_start(which, translator, function(passed)
			if passed and model_fetch.init(which, translator, LID_PATH) then
				mod._offline_ready = true
				guarded_set(WHICH_ID[which], true)
				guarded_set(WHICH_ID[OTHER[which]], false)
			else
				mod:warning("Lingua Imperialis: installed %s model failed verification - falling back to online translation.", tostring(which))
				guarded_set(WHICH_ID.small, false)
				guarded_set(WHICH_ID.large, false)
				mod._offline_ready = false
			end
		end)
	end

	local marker = model_fetch.marker_model()

	if marker and not model_fetch.is_complete(marker) then
		guarded_set(WHICH_ID[marker], true)
		guarded_set(WHICH_ID[OTHER[marker]], false)
		model_fetch.start(marker, translator, LID_PATH, make_on_done(marker))
	elseif model_fetch.is_complete("small") then
		enable_async("small")
	elseif model_fetch.is_complete("large") then
		enable_async("large")
	else
		guarded_set(WHICH_ID.small, false)
		guarded_set(WHICH_ID.large, false)
		mod._offline_ready = false
	end
end

function mod.on_setting_changed(id)
	settings.refresh()
	chat_inject.set_color(settings.cache.translation_rgb)
	mod._target_iso = settings.cache.target_iso or "en"

	if id == "provider" and settings.cache.provider == "offline" and not mod._offline_ready then
		pcall(function()
			local msg = mod:localize("need_model")
			if mod.notify then
				mod:notify(msg)
			else
				mod:echo(msg)
			end
		end)
	end

	if mod._suppress_setting then
		return
	end

	local which
	if id == "download_model" then
		which = "small"
	elseif id == "download_model_large" then
		which = "large"
	else
		return
	end

	local ok, err = pcall(function()
		local want = settings.cache[id] and true or false
		local other = OTHER[which]

		if want then
			if model_fetch.active() and model_fetch.active_which() == which then
				return
			end
			if model_fetch.active() then
				model_fetch.cancel()
			end
			guarded_set(WHICH_ID[other], false)
			model_fetch.verify_start(which, translator, function(passed)
				if passed then
					mod._offline_ready = model_fetch.init(which, translator, LID_PATH)
				else
					if model_fetch.is_complete(which) then
						model_fetch.delete(which)
					end
					model_fetch.start(which, translator, LID_PATH, make_on_done(which))
				end
			end)
		else
			if model_fetch.is_complete(which) then
				mod._offline_ready = false
				translator.shutdown()
			elseif model_fetch.active() and model_fetch.active_which() == which then
				model_fetch.cancel()
			end
		end
	end)

	if not ok then
		mod:warning("Lingua Imperialis: %s change failed: %s", tostring(id), tostring(err))
	end
end

function mod.on_unload(exit_game)
	pcall(function() outgoing.clear() end)
	pcall(function() online_backend.clear() end)
	if mod._offline_ready then
		translator.shutdown()
		mod._offline_ready = false
	end
end
