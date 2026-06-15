-- luacheck: globals GameplaySetElapsedTimeMultiplier waitUnmodified RoomThreadName thread
local deps = ... or {}
local data = deps.data or import("mods/data.lua")
local clock = deps.clock or function()
    return os.clock()
end
local startThread = deps.thread or function(callback, ...)
    return thread(callback, ...)
end

local behavior = {}

local PRACTICE_SLOW_NAME = "InfiniDDPracticeSlow"
local PRACTICE_SLOW_MULTIPLIER = 0.1
local PRACTICE_SLOW_OVERLAY_LINE = "practiceSlow"
local PRACTICE_SLOW_OVERLAY_REGION = "centerLowerStack"
local PRACTICE_SLOW_OVERLAY_REFRESH_SECONDS = 0.05

local practiceSlowState = {
    active = false,
    clearRequested = false,
    startedAt = 0,
    duration = 0,
    generation = 0,
}

local function clampInteger(value, spec)
    local integer = math.floor(tonumber(value) or spec.default)
    if integer < spec.min then
        return spec.min
    end
    if integer > spec.max then
        return spec.max
    end
    return integer
end

local function readPracticeSlowSeconds(runtime)
    return clampInteger(runtime.data.read(data.PRACTICE_SLOW_SECONDS_ALIAS), data.practiceSlowSeconds)
end

local function formatPracticeSlowRemaining(remainingSeconds)
    local tenths = math.ceil((math.max(0, remainingSeconds) * 10) - 0.001)
    if tenths < 0 then
        tenths = 0
    end
    return string.format("%.1fs", tenths / 10)
end

local function readPracticeSlowRemaining(now)
    local elapsed = math.max(0, (tonumber(now) or clock()) - practiceSlowState.startedAt)
    return math.max(0, practiceSlowState.duration - elapsed)
end

local function isPracticeSlowOverlayVisible()
    return practiceSlowState.active == true or practiceSlowState.clearRequested == true
end

local function renderPracticeSlowOverlay(now, overlay)
    if practiceSlowState.active then
        overlay.setLine(PRACTICE_SLOW_OVERLAY_LINE, {
            label = "InfiniDD slow",
            value = formatPracticeSlowRemaining(readPracticeSlowRemaining(now)),
        })
    else
        overlay.setLine(PRACTICE_SLOW_OVERLAY_LINE, {
            label = "",
            value = "",
        })
        practiceSlowState.clearRequested = false
    end
    overlay.refreshRegion(PRACTICE_SLOW_OVERLAY_REGION)
end

local function applyPracticeSlow()
    GameplaySetElapsedTimeMultiplier({
        Name = PRACTICE_SLOW_NAME,
        ElapsedTimeMultiplier = PRACTICE_SLOW_MULTIPLIER,
        ApplyToPlayerUnits = true,
    })
end

local function clearPracticeSlow()
    GameplaySetElapsedTimeMultiplier({
        Name = PRACTICE_SLOW_NAME,
        ElapsedTimeMultiplier = PRACTICE_SLOW_MULTIPLIER,
        ApplyToPlayerUnits = true,
        Reverse = true,
    })
end

local function finishPracticeSlow(generation, duration)
    waitUnmodified(duration, RoomThreadName)
    if generation ~= practiceSlowState.generation then
        return
    end
    clearPracticeSlow()
    practiceSlowState.active = false
    practiceSlowState.clearRequested = true
end

function behavior.start(runtime)
    local duration = readPracticeSlowSeconds(runtime)
    if duration <= 0 then
        return
    end

    practiceSlowState.generation = practiceSlowState.generation + 1
    practiceSlowState.active = true
    practiceSlowState.clearRequested = false
    practiceSlowState.startedAt = clock()
    practiceSlowState.duration = duration

    applyPracticeSlow()
    startThread(finishPracticeSlow, practiceSlowState.generation, duration)
end

function behavior.attach(moduleRef)
    local overlays = moduleRef.overlays
    overlays.createLine(PRACTICE_SLOW_OVERLAY_LINE, {
        componentName = "InfiniDD_PracticeSlow",
        region = PRACTICE_SLOW_OVERLAY_REGION,
        order = overlays.order.module + 4,
        columnGap = 10,
        visible = function()
            return isPracticeSlowOverlayVisible()
        end,
        columns = {
            {
                key = "label",
                minWidth = 130,
                justify = "Right",
                textArgs = {
                    Font = "P22UndergroundSCMedium",
                    Color = { 1.0, 1.0, 1.0, 1.0 },
                    FontSize = 22,
                },
            },
            {
                key = "value",
                minWidth = 54,
                justify = "Right",
                textArgs = {
                    Font = "P22UndergroundSCMedium",
                    Color = { 1.0, 0.18, 0.18, 1.0 },
                    FontSize = 22,
                },
            },
        },
    })

    overlays.onInterval("practiceSlow", PRACTICE_SLOW_OVERLAY_REFRESH_SECONDS, function(_, _, overlay, event)
        renderPracticeSlowOverlay(event and event.now or nil, overlay)
    end, {
        when = function()
            return isPracticeSlowOverlayVisible()
        end,
    })
end

return behavior
