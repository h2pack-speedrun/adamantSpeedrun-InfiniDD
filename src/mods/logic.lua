-- luacheck: globals CurrentRun SessionMapState AddSimSpeedChange RemoveSimSpeedChange
local deps = ... or {}
local data = deps.data or import("mods/data.lua")
local clock = deps.clock or os.clock

local logic = {}

local PRACTICE_LAST_STAND_NAME = "InfiniDD"
local PENALTY_SPEED_CHANGE_NAME = "InfiniDDPenalty"
local PENALTY_OVERLAY_LINE = "penalty"
local PENALTY_OVERLAY_REGION = "centerLowerStack"
local PENALTY_OVERLAY_REFRESH_SECONDS = 0.1
local PENALTY_SIM_SPEED = {
    Fraction = 0,
    LerpTime = 0.001,
    Priority = true,
}
local PENALTY_CLEAR_SPEED = {
    LerpTime = 0.001,
}
local penaltyState = {
    active = false,
    endsAt = nil,
    needsOverlayRefresh = false,
    prewarm = true,
    remainingSeconds = 0,
    token = 0,
}

local function clampRecoveryPercent(value)
    local percent = math.floor(tonumber(value) or data.recoveryPercent.default)
    if percent < data.recoveryPercent.min then
        return data.recoveryPercent.min
    end
    if percent > data.recoveryPercent.max then
        return data.recoveryPercent.max
    end
    return percent
end

local function clampTimePenaltySeconds(value)
    local seconds = math.floor(tonumber(value) or data.timePenaltySeconds.default)
    if seconds < data.timePenaltySeconds.min then
        return data.timePenaltySeconds.min
    end
    if seconds > data.timePenaltySeconds.max then
        return data.timePenaltySeconds.max
    end
    return seconds
end

local function buildPracticeLastStand(runtime)
    local recoveryFraction = clampRecoveryPercent(runtime.data.read(data.RECOVERY_PERCENT_ALIAS)) / 100
    return {
        Name = PRACTICE_LAST_STAND_NAME,
        Icon = "ExtraLifeReplenish",
        HealFraction = recoveryFraction,
        ManaFraction = recoveryFraction,
    }
end

local function isCurrentHero(victim)
    return CurrentRun ~= nil and CurrentRun.Hero ~= nil and victim == CurrentRun.Hero
end

local function hasCurrentRoom()
    return CurrentRun ~= nil and CurrentRun.CurrentRoom ~= nil
end

local function shouldUsePracticeLastStand(host, victim)
    if host.isEnabled() ~= true then
        return false
    end
    if not isCurrentHero(victim) then
        return false
    end
    if not hasCurrentRoom() then
        return false
    end
    return not (SessionMapState and SessionMapState.InfiniteDeathDefiance)
end

local function ensureRoomUsageTable()
    local room = CurrentRun and CurrentRun.CurrentRoom or nil
    if room == nil then
        return false
    end
    if room.LastStandsUsed == nil then
        room.LastStandsUsed = {}
        return true
    end
    return false
end

local function snapshotUsageCounts(createdRoomUsageTable)
    local roomUsage = CurrentRun.CurrentRoom.LastStandsUsed
    return {
        heroLastStandsUsed = CurrentRun.Hero.LastStandsUsed,
        roomPracticeLastStandsUsed = roomUsage and roomUsage[PRACTICE_LAST_STAND_NAME] or nil,
        createdRoomUsageTable = createdRoomUsageTable,
    }
end

local function restoreUsageCounts(snapshot)
    CurrentRun.Hero.LastStandsUsed = snapshot.heroLastStandsUsed

    if snapshot.createdRoomUsageTable then
        CurrentRun.CurrentRoom.LastStandsUsed = nil
        return
    end

    local roomUsage = CurrentRun.CurrentRoom.LastStandsUsed
    if roomUsage ~= nil then
        roomUsage[PRACTICE_LAST_STAND_NAME] = snapshot.roomPracticeLastStandsUsed
    end
end

local function removePracticeLastStand(victim, practiceLastStand)
    for index = #victim.LastStands, 1, -1 do
        if victim.LastStands[index] == practiceLastStand then
            table.remove(victim.LastStands, index)
            return
        end
    end
end

local function currentPenaltyRemaining()
    local remainingSeconds = tonumber(penaltyState.remainingSeconds) or 0
    if penaltyState.active == true and penaltyState.endsAt ~= nil then
        remainingSeconds = math.max(0, penaltyState.endsAt - clock())
    end
    return remainingSeconds
end

local function renderPenaltyOverlay(overlay)
    local text = ""
    if penaltyState.active == true then
        text = string.format("InfiniDD penalty: %.2fs", currentPenaltyRemaining())
    end
    overlay.setLine(PENALTY_OVERLAY_LINE, {
        text = text,
    })
    overlay.refreshRegion(PENALTY_OVERLAY_REGION)
end

local function isPenaltySpeedChange(event)
    local args = event and event.args or nil
    return args and args[1] == PENALTY_SPEED_CHANGE_NAME
end

local function finishTimePenalty(token)
    if penaltyState.token ~= token then
        return
    end
    if penaltyState.active ~= true then
        return
    end

    penaltyState.active = false
    penaltyState.endsAt = nil
    penaltyState.needsOverlayRefresh = true
    penaltyState.remainingSeconds = 0
    RemoveSimSpeedChange(PENALTY_SPEED_CHANGE_NAME, PENALTY_CLEAR_SPEED)
end

local function startTimePenalty(seconds)
    if seconds <= 0 then
        return
    end

    penaltyState.token = penaltyState.token + 1
    local now = clock()
    penaltyState.active = true
    penaltyState.endsAt = now + seconds
    penaltyState.needsOverlayRefresh = false
    penaltyState.prewarm = false
    penaltyState.remainingSeconds = seconds

    AddSimSpeedChange(PENALTY_SPEED_CHANGE_NAME, PENALTY_SIM_SPEED)
end

local function usePracticeLastStand(host, runtime, baseFunc, victim, triggerArgs)
    victim.LastStands = victim.LastStands or {}
    triggerArgs = triggerArgs or {}

    local createdRoomUsageTable = ensureRoomUsageTable()
    local usageSnapshot = snapshotUsageCounts(createdRoomUsageTable)
    local practiceLastStand = buildPracticeLastStand(runtime)
    local penaltySeconds = clampTimePenaltySeconds(runtime.data.read(data.TIME_PENALTY_SECONDS_ALIAS))
    table.insert(victim.LastStands, practiceLastStand)

    host.logIf("InfiniDD practice Death Defiance triggered.")
    local result = baseFunc(victim, triggerArgs)
    if result ~= true then
        removePracticeLastStand(victim, practiceLastStand)
    end
    restoreUsageCounts(usageSnapshot)
    if result == true then
        startTimePenalty(penaltySeconds)
    end
    return result
end

local function registerPenaltyOverlay(overlays)
    overlays.createLine(PENALTY_OVERLAY_LINE, {
        componentName = "InfiniDD_Penalty",
        region = PENALTY_OVERLAY_REGION,
        order = overlays.order.module + 5,
        columnGap = 8,
        visible = function(host)
            return host.isEnabled() == true and (penaltyState.active == true or penaltyState.prewarm == true)
        end,
        columns = {
            {
                key = "text",
                minWidth = 180,
                justify = "Right",
                textArgs = {
                    Font = "P22UndergroundSCMedium",
                    Color = { 1.0, 0.18, 0.18, 1.0 },
                },
            },
        },
    })

    overlays.afterHook("AddSimSpeedChange", function(_, _, overlay, event)
        if isPenaltySpeedChange(event) and penaltyState.active == true then
            renderPenaltyOverlay(overlay)
        end
    end)

    overlays.afterHook("RemoveSimSpeedChange", function(_, _, overlay, event)
        if isPenaltySpeedChange(event) then
            renderPenaltyOverlay(overlay)
        end
    end)

    overlays.onInterval("penalty", PENALTY_OVERLAY_REFRESH_SECONDS, function(_, _, overlay)
        if penaltyState.active == true and currentPenaltyRemaining() <= 0 then
            finishTimePenalty(penaltyState.token)
        end
        renderPenaltyOverlay(overlay)
        if penaltyState.active ~= true then
            penaltyState.needsOverlayRefresh = false
        end
    end, {
        when = function()
            return penaltyState.active == true
                or penaltyState.needsOverlayRefresh == true
                or penaltyState.prewarm == true
        end,
    })
end

function logic.attach(moduleRef)
    registerPenaltyOverlay(moduleRef.overlays)

    moduleRef.hooks.wrap("CheckLastStand", function(host, runtime, baseFunc, victim, triggerArgs)
        local result = baseFunc(victim, triggerArgs)
        if result ~= false then
            return result
        end
        if not shouldUsePracticeLastStand(host, victim) then
            return result
        end
        return usePracticeLastStand(host, runtime, baseFunc, victim, triggerArgs)
    end)
end

return logic
