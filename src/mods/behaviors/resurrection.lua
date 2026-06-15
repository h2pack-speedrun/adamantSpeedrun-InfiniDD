-- luacheck: globals CurrentRun SessionMapState
local deps = ... or {}
local data = deps.data or import("mods/data.lua")

local behavior = {}

local PRACTICE_LAST_STAND_NAME = "InfiniDD"
local DEATH_COUNTER_OVERLAY_LINE = "deathCounter"
local DEATH_COUNTER_OVERLAY_REGION = "middleRightStack"
local DEATH_COUNTER_OVERLAY_REFRESH_SECONDS = 0.25

local function buildPracticeLastStand(runtime)
    local recoveryFraction = runtime.data.read(data.RECOVERY_PERCENT_ALIAS) / 100
    return {
        Name = PRACTICE_LAST_STAND_NAME,
        Icon = "ExtraLifeReplenish",
        HealFraction = recoveryFraction,
        ManaFraction = recoveryFraction,
    }
end

local function shouldUsePracticeLastStand(host, victim)
    if host.isEnabled() ~= true then
        return false
    end
    if CurrentRun == nil or CurrentRun.Hero == nil or victim ~= CurrentRun.Hero then
        return false
    end
    if CurrentRun.CurrentRoom == nil then
        return false
    end
    return not (SessionMapState and SessionMapState.InfiniteDeathDefiance)
end

local function ensureRoomUsageTable()
    local room = CurrentRun.CurrentRoom
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
        roomPracticeLastStandsUsed = roomUsage[PRACTICE_LAST_STAND_NAME],
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

local function readPracticeDeathCount(runtime)
    local deaths = runtime.cache.currentRun.get(data.PRACTICE_DEATHS_CACHE_ALIAS)
    if deaths == nil then
        return 0
    end
    return deaths.count
end

local function incrementPracticeDeathCount(runtime)
    local deaths = runtime.cache.currentRun.get(data.PRACTICE_DEATHS_CACHE_ALIAS)
    deaths.count = deaths.count + 1
    return deaths.count
end

local function renderDeathCounterOverlay(runtime, overlay)
    local count = readPracticeDeathCount(runtime)
    local label = ""
    local value = ""
    if count > 0 then
        label = "Practice deaths"
        value = tostring(count)
    end

    overlay.setLine(DEATH_COUNTER_OVERLAY_LINE, {
        label = label,
        value = value,
    })
    overlay.refresh(DEATH_COUNTER_OVERLAY_LINE)
end

local function usePracticeLastStand(host, runtime, baseFunc, victim, triggerArgs, onPracticeDeath)
    victim.LastStands = victim.LastStands or {}
    triggerArgs = triggerArgs or {}

    local createdRoomUsageTable = ensureRoomUsageTable()
    local usageSnapshot = snapshotUsageCounts(createdRoomUsageTable)
    local practiceLastStand = buildPracticeLastStand(runtime)
    table.insert(victim.LastStands, practiceLastStand)

    host.logIf("InfiniDD practice Death Defiance triggered.")
    local result = baseFunc(victim, triggerArgs)
    if result ~= true then
        removePracticeLastStand(victim, practiceLastStand)
    end
    restoreUsageCounts(usageSnapshot)
    if result == true then
        incrementPracticeDeathCount(runtime)
        if onPracticeDeath ~= nil then
            onPracticeDeath(runtime)
        end
    end
    return result
end

local function registerDeathCounterOverlay(overlays)
    local function shouldShowDeathCounter(host, runtime)
        return host.isEnabled() == true
            and runtime.data.read(data.SHOW_DEATH_COUNTER_OVERLAY_ALIAS) == true
            and readPracticeDeathCount(runtime) > 0
    end

    overlays.createLine(DEATH_COUNTER_OVERLAY_LINE, {
        componentName = "InfiniDD_DeathCounter",
        region = DEATH_COUNTER_OVERLAY_REGION,
        order = overlays.order.module + 5,
        columnGap = 8,
        visible = function(host, runtime)
            return shouldShowDeathCounter(host, runtime)
        end,
        columns = {
            {
                key = "label",
                minWidth = 130,
                justify = "Right",
                textArgs = {
                    Font = "P22UndergroundSCMedium",
                    Color = { 1.0, 1.0, 1.0, 1.0 },
                },
            },
            {
                key = "value",
                minWidth = 24,
                justify = "Right",
                textArgs = {
                    Font = "P22UndergroundSCMedium",
                    Color = { 1.0, 0.18, 0.18, 1.0 },
                },
            },
        },
    })

    overlays.onInterval("deathCounter", DEATH_COUNTER_OVERLAY_REFRESH_SECONDS, function(_, runtime, overlay)
        renderDeathCounterOverlay(runtime, overlay)
    end, {
        when = function(host, runtime)
            return shouldShowDeathCounter(host, runtime)
        end,
    })
end

function behavior.attach(moduleRef, opts)
    local onPracticeDeath = opts and opts.onPracticeDeath or nil

    registerDeathCounterOverlay(moduleRef.overlays)
    moduleRef.hooks.wrap("CheckLastStand", function(host, runtime, baseFunc, victim, triggerArgs)
        local result = baseFunc(victim, triggerArgs)
        if result ~= false then
            return result
        end
        if not shouldUsePracticeLastStand(host, victim) then
            return result
        end
        return usePracticeLastStand(host, runtime, baseFunc, victim, triggerArgs, onPracticeDeath)
    end)
end

return behavior
