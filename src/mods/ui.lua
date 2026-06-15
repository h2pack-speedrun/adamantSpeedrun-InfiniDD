local deps = ... or {}
local data = deps.data or import("mods/data.lua")

local ui = {}

local WARNING_TEXT_OPTS = {
    color = { 1.0, 0.18, 0.18, 1.0 },
}
local PRACTICE_WARNING_TEXT = "Practice module active: lethal hits trigger synthetic Death Defiances."

local RECOVERY_DISPLAY_VALUES = {}
for value = data.recoveryPercent.min, data.recoveryPercent.max do
    RECOVERY_DISPLAY_VALUES[value] = tostring(value) .. "%"
end
local TIME_PENALTY_DISPLAY_VALUES = {
    [0] = "Off",
}
for value = data.timePenaltySeconds.min + data.timePenaltySeconds.step, data.timePenaltySeconds.max,
    data.timePenaltySeconds.step do
    TIME_PENALTY_DISPLAY_VALUES[value] = tostring(value) .. "s"
end

local RECOVERY_PERCENT_OPTS = {
    label = "Recovery",
    tooltip = "Health and magick restored by each practice Death Defiance.",
    min = data.recoveryPercent.min,
    max = data.recoveryPercent.max,
    step = data.recoveryPercent.step,
    default = data.recoveryPercent.default,
    valueWidth = 42,
    displayValues = RECOVERY_DISPLAY_VALUES,
}
local TIME_PENALTY_OPTS = {
    label = "Time penalty",
    tooltip = "Real-time delay applied after each practice Death Defiance.",
    min = data.timePenaltySeconds.min,
    max = data.timePenaltySeconds.max,
    step = data.timePenaltySeconds.step,
    default = data.timePenaltySeconds.default,
    valueWidth = 48,
    displayValues = TIME_PENALTY_DISPLAY_VALUES,
}

local function drawPracticeWarning(host, draw)
    if host.isEnabled() == true then
        draw.widgets.text(PRACTICE_WARNING_TEXT, WARNING_TEXT_OPTS)
    end
end

local function drawSettings(host, draw, state)
    drawPracticeWarning(host, draw)
    draw.widgets.stepper(state.get(data.RECOVERY_PERCENT_ALIAS), RECOVERY_PERCENT_OPTS)
    draw.widgets.stepper(state.get(data.TIME_PENALTY_SECONDS_ALIAS), TIME_PENALTY_OPTS)
end

function ui.drawQuickContent(host, uiContext)
    drawSettings(host, uiContext.draw, uiContext.data)
end

function ui.drawTab(host, uiContext)
    drawSettings(host, uiContext.draw, uiContext.data)
end

return ui
