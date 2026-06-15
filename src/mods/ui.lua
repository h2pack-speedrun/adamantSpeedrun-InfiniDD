local deps = ... or {}
local data = deps.data or import("mods/data.lua")

local ui = {}

local WARNING_TEXT_OPTS = {
    color = { 1.0, 0.18, 0.18, 1.0 },
}
local PRACTICE_WARNING_TEXT = "Practice module active: dying after all DDs are consumed triggers a hidden DD."
local SETTING_LABEL_WIDTH = 160
local SETTING_DROPDOWN_WIDTH = 80

local function buildSteppedValues(firstValue, maxValue, step, extraFirstValue)
    local values = {}
    if extraFirstValue ~= nil then
        values[#values + 1] = extraFirstValue
    end
    for value = firstValue, maxValue, step do
        if value ~= extraFirstValue then
            values[#values + 1] = value
        end
    end
    return values
end

local RECOVERY_VALUES = buildSteppedValues(
    data.recoveryPercent.step,
    data.recoveryPercent.max,
    data.recoveryPercent.step,
    data.recoveryPercent.min
)
local RECOVERY_DISPLAY_VALUES = {}
for _, value in ipairs(RECOVERY_VALUES) do
    RECOVERY_DISPLAY_VALUES[value] = tostring(value) .. "%"
end
local TIME_PENALTY_VALUES = buildSteppedValues(
    data.timePenaltySeconds.min,
    data.timePenaltySeconds.max,
    data.timePenaltySeconds.step
)
local TIME_PENALTY_DISPLAY_VALUES = {}
for _, value in ipairs(TIME_PENALTY_VALUES) do
    TIME_PENALTY_DISPLAY_VALUES[value] = tostring(value) .. "s"
end
TIME_PENALTY_DISPLAY_VALUES[0] = "Off"

local RECOVERY_PERCENT_OPTS = {
    label = "Recovery",
    tooltip = "Health and magick restored by each practice Death Defiance.",
    labelWidth = SETTING_LABEL_WIDTH,
    controlWidth = SETTING_DROPDOWN_WIDTH,
    values = RECOVERY_VALUES,
    default = data.recoveryPercent.default,
    displayValues = RECOVERY_DISPLAY_VALUES,
}
local TIME_PENALTY_OPTS = {
    label = "Time penalty",
    tooltip = "Real-time delay applied after each practice Death Defiance.",
    labelWidth = SETTING_LABEL_WIDTH,
    controlWidth = SETTING_DROPDOWN_WIDTH,
    values = TIME_PENALTY_VALUES,
    default = data.timePenaltySeconds.default,
    displayValues = TIME_PENALTY_DISPLAY_VALUES,
}

local function drawPracticeWarning(host, draw)
    if host.isEnabled() == true then
        draw.widgets.text(PRACTICE_WARNING_TEXT, WARNING_TEXT_OPTS)
    end
end

local function drawSettings(host, draw, state)
    drawPracticeWarning(host, draw)
    draw.widgets.dropdown(state.get(data.RECOVERY_PERCENT_ALIAS), RECOVERY_PERCENT_OPTS)
    draw.widgets.dropdown(state.get(data.TIME_PENALTY_SECONDS_ALIAS), TIME_PENALTY_OPTS)
end

function ui.drawQuickContent(host, uiContext)
    drawSettings(host, uiContext.draw, uiContext.data)
end

function ui.drawTab(host, uiContext)
    drawSettings(host, uiContext.draw, uiContext.data)
end

return ui
