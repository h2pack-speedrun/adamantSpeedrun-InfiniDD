local deps = ... or {}
local data = deps.data or import("mods/data.lua")

local ui = {}

local WARNING_TEXT_OPTS = {
    color = { 1.0, 0.18, 0.18, 1.0 },
}
local PRACTICE_WARNING_TEXT = "Practice module active: dying after all DDs are consumed triggers a hidden DD."
local SETTING_LABEL_WIDTH = 160
local SETTING_DROPDOWN_WIDTH = 80

local RECOVERY_PERCENT_OPTS = {
    label = "Recovery",
    tooltip = "Health and magick restored by each practice Death Defiance.",
    labelWidth = SETTING_LABEL_WIDTH,
    controlWidth = SETTING_DROPDOWN_WIDTH,
    valueRange = {
        min = data.recoveryPercent.step,
        max = data.recoveryPercent.max,
        step = data.recoveryPercent.step,
        prepend = data.recoveryPercent.min,
        suffix = "%",
    },
    default = data.recoveryPercent.default,
}

local PRACTICE_SLOW_SECONDS_OPTS = {
    label = "World slow",
    tooltip = "Slow the player, enemies, projectiles, and world objects after a practice Death Defiance.",
    labelWidth = SETTING_LABEL_WIDTH,
    controlWidth = SETTING_DROPDOWN_WIDTH,
    valueRange = {
        min = data.practiceSlowSeconds.min,
        max = data.practiceSlowSeconds.max,
        step = data.practiceSlowSeconds.step,
        suffix = "s",
    },
    default = data.practiceSlowSeconds.default,
}

local function drawPracticeWarning(host, draw)
    if host.isEnabled() == true then
        draw.widgets.text(PRACTICE_WARNING_TEXT, WARNING_TEXT_OPTS)
    end
end

local function drawSettings(host, draw, state)
    drawPracticeWarning(host, draw)
    draw.widgets.dropdown(state.get(data.RECOVERY_PERCENT_ALIAS), RECOVERY_PERCENT_OPTS)
    draw.widgets.dropdown(state.get(data.PRACTICE_SLOW_SECONDS_ALIAS), PRACTICE_SLOW_SECONDS_OPTS)
end

function ui.drawQuickContent(host, uiContext)
    drawSettings(host, uiContext.draw, uiContext.data)
end

function ui.drawTab(host, uiContext)
    drawSettings(host, uiContext.draw, uiContext.data)
end

return ui
