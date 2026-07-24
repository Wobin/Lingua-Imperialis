--[[
    Name: Lingua Imperialis
    Author: Wobin
    Date: 2026-07-06
    Version: 1.0.0
    Repository:
]]--


local mod = get_mod("Lingua Imperialis")

local math_floor = math.floor
local rawget = rawget
local pcall = pcall

local Vector3 = rawget(_G, "Vector3")

local M = {}

local state = mod:persistent_table("progress_hud")

local UIRenderer, _font_type, _font_options
local _ui_ready = false

local _render_settings = {}
local _empty_scenegraph = {}

local _text_box = { 0, 0 }
local _text_pos = { 0, 0, 952 }
local _shadow_pos = { 0, 0, 951 }

local BACKDROP_COLOR = { 150, 0, 0, 0 }
local TEXT_COLOR = { 255, 220, 235, 220 }
local SHADOW_COLOR = { 255, 0, 0, 0 }

local _ui_tried = false

local function _resolve_ui_body()
    UIRenderer = require("scripts/managers/ui/ui_renderer")
    local UIFonts = require("scripts/managers/ui/ui_fonts")
    local UIFontSettings = require("scripts/managers/ui/ui_font_settings")
    _font_type = UIFontSettings.hud_body.font_type
    _font_options = UIFonts.get_font_options_by_style({
        text_horizontal_alignment = "left",
        text_vertical_alignment = "center",
        drop_shadow = true,
    }, {})
end

local function _resolve_ui()
    if _ui_ready or _ui_tried then
        return _ui_ready
    end
    _ui_tried = true
    local ok, err = pcall(_resolve_ui_body)
    if ok and UIRenderer then
        _ui_ready = true
    else
        mod:warning("Lingua Imperialis: progress_hud UI resolve failed: %s", tostring(err))
    end
    return _ui_ready
end

local function _draw(self, ui_renderer, input_service, dt)
    local text = state.text
    if text == nil then
        return
    end

    local engine_rs = self._render_settings
    local resolution = rawget(_G, "RESOLUTION_LOOKUP")
    local scale = (engine_rs and engine_rs.scale) or (resolution and resolution.scale) or ui_renderer.scale or 1
    local res_w = (resolution and (resolution.width or resolution.res_w or resolution[1])) or 1920
    local res_h = (resolution and (resolution.height or resolution.res_h or resolution[2])) or 1080
    local screen_width = res_w / scale
    local screen_height = res_h / scale

    _render_settings.scale = scale
    _render_settings.inverse_scale = (engine_rs and engine_rs.inverse_scale) or (1 / scale)
    _render_settings.start_layer = 950
    _render_settings.alpha_multiplier = 1
    _render_settings.material_flags = 0

    UIRenderer.begin_pass(ui_renderer, _empty_scenegraph, input_service, dt, _render_settings)

    local margin = 40
    local bar_w = 520
    local bar_h = 40
    local bar_x = screen_width - bar_w - margin
    local bar_y = screen_height - bar_h - margin

    UIRenderer.draw_rect(ui_renderer, Vector3(bar_x, bar_y, 950), Vector3(bar_w, bar_h, 1), BACKDROP_COLOR)

    local inset = 14
    local font_size = math_floor(22 * scale + 0.5)
    _text_box[1] = bar_w - inset * 2
    _text_box[2] = bar_h
    _text_pos[1] = bar_x + inset
    _text_pos[2] = bar_y
    _shadow_pos[1] = bar_x + inset + 1
    _shadow_pos[2] = bar_y + 1
    UIRenderer.draw_text(ui_renderer, text, font_size, _font_type, _shadow_pos, _text_box, SHADOW_COLOR, _font_options)
    UIRenderer.draw_text(ui_renderer, text, font_size, _font_type, _text_pos, _text_box, TEXT_COLOR, _font_options)

    UIRenderer.end_pass(ui_renderer)
end

local function _register()
    if state.hooked then
        return
    end
    state.hooked = true
    local ok, err = pcall(function()
        local UIConstantElements = require("scripts/managers/ui/ui_constant_elements")
        mod:hook_safe(UIConstantElements, "draw",
            function(self, dt, t, input_service)
                if state.text == nil then
                    return
                end
                local ui_renderer = self and self._ui_renderer
                if not ui_renderer then
                    return
                end
                if not _resolve_ui() then
                    return
                end
                if not state.logged_draw then
                    state.logged_draw = true
                    mod:info("Lingua Imperialis: progress_hud first draw (renderer ok, text=%q)", tostring(state.text))
                end
                local drew_ok, draw_err = pcall(_draw, self, ui_renderer, input_service, dt)
                if not drew_ok and not state.logged_err then
                    state.logged_err = true
                    mod:warning("Lingua Imperialis: progress_hud draw error: %s", tostring(draw_err))
                end
            end)
    end)
    if not ok then
        state.hooked = nil
        mod:warning("Lingua Imperialis: progress_hud hook registration failed: %s", tostring(err))
    end
end

_register()

function M.set(text)
    state.text = (text ~= nil and text ~= "" and text) or nil
end

function M.clear()
    state.text = nil
end

function M.on_unload()
    state.hooked = nil
    state.logged_draw = nil
    state.logged_err = nil
    state.text = nil
end

return M
