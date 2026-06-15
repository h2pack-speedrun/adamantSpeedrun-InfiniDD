-- luacheck: globals TestInfiniDDLogic CurrentRun unpack
local lu = require("luaunit")
local unpack = table.unpack or unpack

local data = dofile("src/mods/data.lua")
local logic

local function loadBehavior(path, deps)
    return assert(loadfile(path))(deps)
end

TestInfiniDDLogic = {}

local function loadLogic(clock, threadFunc)
    return assert(loadfile("src/mods/logic.lua"))({
        data = data,
        practiceSlow = loadBehavior("src/mods/behaviors/practice_slow.lua", {
            data = data,
            clock = clock,
            thread = threadFunc,
        }),
        resurrection = loadBehavior("src/mods/behaviors/resurrection.lua", {
            data = data,
        }),
    })
end

local function captureHooks()
    local hooks = {}
    local overlays = {
        lines = {},
        intervals = {},
    }
    logic.attach({
        hooks = {
            wrap = function(name, callback)
                hooks[name] = callback
            end,
        },
        overlays = {
            order = {
                module = 1000,
            },
            createLine = function(name, spec)
                overlays.lines[name] = spec
            end,
            onInterval = function(name, seconds, callback, opts)
                overlays.intervals[name] = {
                    seconds = seconds,
                    callback = callback,
                    opts = opts,
                }
            end,
        },
    })
    return hooks, overlays
end

local function createRuntime(recoveryPercent, practiceSlowSeconds, opts)
    opts = opts or {}
    local practiceDeaths = {
        count = 0,
    }
    local values = {
        [data.RECOVERY_PERCENT_ALIAS] = recoveryPercent,
        [data.PRACTICE_SLOW_SECONDS_ALIAS] = practiceSlowSeconds == nil
            and data.practiceSlowSeconds.default
            or practiceSlowSeconds,
        [data.SHOW_DEATH_COUNTER_OVERLAY_ALIAS] = opts.showDeathCounter ~= false,
        [data.ENABLE_PRACTICE_SLOW_ALIAS] = opts.enablePracticeSlow ~= false,
    }
    return {
        data = {
            read = function(alias)
                return values[alias]
            end,
        },
        cache = {
            currentRun = {
                get = function(alias)
                    if alias == data.PRACTICE_DEATHS_CACHE_ALIAS then
                        return practiceDeaths
                    end
                    return nil
                end,
            },
        },
        practiceDeaths = practiceDeaths,
    }
end

local function createHost(enabled)
    return {
        isEnabled = function()
            return enabled
        end,
        logIf = function()
        end,
    }
end

function TestInfiniDDLogic.testStorageDefaultsKeepSlowDurationSeparateFromEnableToggle()
    local storage = data.buildStorage()

    lu.assertEquals(storage[2].alias, data.SHOW_DEATH_COUNTER_OVERLAY_ALIAS)
    lu.assertEquals(storage[2].default, true)
    lu.assertEquals(storage[3].alias, data.ENABLE_PRACTICE_SLOW_ALIAS)
    lu.assertEquals(storage[3].default, true)
    lu.assertEquals(storage[4].alias, data.PRACTICE_SLOW_SECONDS_ALIAS)
    lu.assertEquals(storage[4].default, 3)
    lu.assertEquals(storage[4].min, 1)
end

function TestInfiniDDLogic:setUp()
    self.previousCurrentRun = _G.CurrentRun
    self.previousSessionMapState = _G.SessionMapState
    self.previousGameplaySetElapsedTimeMultiplier = _G.GameplaySetElapsedTimeMultiplier
    self.previousWaitUnmodified = _G.waitUnmodified
    self.previousRoomThreadName = _G.RoomThreadName
    self.clockNow = 100
    self.gameplaySlowCalls = {}
    self.threadCalls = {}
    self.waits = {}
    _G.GameplaySetElapsedTimeMultiplier = function(args)
        self.gameplaySlowCalls[#self.gameplaySlowCalls + 1] = args
    end
    _G.waitUnmodified = function(seconds, threadName)
        self.waits[#self.waits + 1] = {
            seconds = seconds,
            threadName = threadName,
        }
    end
    _G.RoomThreadName = "RoomThread"
    _G.CurrentRun = {
        Hero = {
            LastStands = {},
        },
        CurrentRoom = {
            LastStandsUsed = {},
        },
    }
    _G.SessionMapState = {}
    logic = loadLogic(function()
        return self.clockNow
    end, function(callback, ...)
        self.threadCalls[#self.threadCalls + 1] = {
            callback = callback,
            args = { ... },
        }
    end)
    self.hooks, self.overlays = captureHooks()
    self.checkLastStand = self.hooks.CheckLastStand
end

function TestInfiniDDLogic:tearDown()
    _G.CurrentRun = self.previousCurrentRun
    _G.SessionMapState = self.previousSessionMapState
    _G.GameplaySetElapsedTimeMultiplier = self.previousGameplaySetElapsedTimeMultiplier
    _G.waitUnmodified = self.previousWaitUnmodified
    _G.RoomThreadName = self.previousRoomThreadName
end

function TestInfiniDDLogic:testBaseResultWins()
    local calls = 0
    local result = self.checkLastStand(createHost(true), createRuntime(55), function()
        calls = calls + 1
        return true
    end, CurrentRun.Hero, {})

    lu.assertEquals(result, true)
    lu.assertEquals(calls, 1)
    lu.assertEquals(#CurrentRun.Hero.LastStands, 0)
end

function TestInfiniDDLogic:testDisabledModuleDoesNotInject()
    local calls = 0
    local result = self.checkLastStand(createHost(false), createRuntime(55), function()
        calls = calls + 1
        return false
    end, CurrentRun.Hero, {})

    lu.assertEquals(result, false)
    lu.assertEquals(calls, 1)
    lu.assertEquals(#CurrentRun.Hero.LastStands, 0)
end

function TestInfiniDDLogic:testNonHeroDoesNotInject()
    local enemy = {
        LastStands = {},
    }
    local calls = 0
    local result = self.checkLastStand(createHost(true), createRuntime(55), function()
        calls = calls + 1
        return false
    end, enemy, {})

    lu.assertEquals(result, false)
    lu.assertEquals(calls, 1)
    lu.assertEquals(#enemy.LastStands, 0)
end

function TestInfiniDDLogic:testMissingCurrentRoomDoesNotInject()
    CurrentRun.CurrentRoom = nil

    local calls = 0
    local result = self.checkLastStand(createHost(true), createRuntime(55), function()
        calls = calls + 1
        return false
    end, CurrentRun.Hero, {})

    lu.assertEquals(result, false)
    lu.assertEquals(calls, 1)
    lu.assertEquals(#CurrentRun.Hero.LastStands, 0)
end

function TestInfiniDDLogic:testPracticeDefianceUsesConfiguredRecoveryAndRestoresUsageCounts()
    CurrentRun.Hero.LastStandsUsed = 3
    CurrentRun.CurrentRoom.LastStandsUsed.InfiniDD = 2

    local calls = 0
    local injectedLastStand
    local args = {}
    local result = self.checkLastStand(createHost(true), createRuntime(55), function(victim, triggerArgs)
        calls = calls + 1
        if calls == 1 then
            return false
        end

        injectedLastStand = victim.LastStands[#victim.LastStands]
        table.remove(victim.LastStands)
        CurrentRun.Hero.LastStandsUsed = CurrentRun.Hero.LastStandsUsed + 1
        CurrentRun.CurrentRoom.LastStandsUsed[injectedLastStand.Name] =
            CurrentRun.CurrentRoom.LastStandsUsed[injectedLastStand.Name] + 1
        triggerArgs.LastStandUsed = injectedLastStand
        return true
    end, CurrentRun.Hero, args)

    lu.assertEquals(result, true)
    lu.assertEquals(calls, 2)
    lu.assertEquals(injectedLastStand.Name, "InfiniDD")
    lu.assertEquals(injectedLastStand.Icon, "ExtraLifeReplenish")
    lu.assertEquals(injectedLastStand.HealFraction, 0.55)
    lu.assertEquals(injectedLastStand.ManaFraction, 0.55)
    lu.assertEquals(args.LastStandUsed, injectedLastStand)
    lu.assertEquals(#CurrentRun.Hero.LastStands, 0)
    lu.assertEquals(CurrentRun.Hero.LastStandsUsed, 3)
    lu.assertEquals(CurrentRun.CurrentRoom.LastStandsUsed.InfiniDD, 2)
end

function TestInfiniDDLogic:testPracticeDefianceCleansUpIfSecondBaseCallFails()
    local calls = 0
    local runtime = createRuntime(55, 4)
    local result = self.checkLastStand(createHost(true), runtime, function()
        calls = calls + 1
        return false
    end, CurrentRun.Hero, {})

    lu.assertEquals(result, false)
    lu.assertEquals(calls, 2)
    lu.assertEquals(#CurrentRun.Hero.LastStands, 0)
    lu.assertEquals(runtime.practiceDeaths.count, 0)
    lu.assertEquals(self.gameplaySlowCalls, {})
    lu.assertEquals(self.threadCalls, {})
end

function TestInfiniDDLogic:testPracticeDefianceCountsSuccessfulPracticeDeath()
    local host = createHost(true)
    local runtime = createRuntime(55)
    local calls = 0

    local result = self.checkLastStand(host, runtime, function(victim)
        calls = calls + 1
        if calls == 1 then
            return false
        end

        table.remove(victim.LastStands)
        return true
    end, CurrentRun.Hero, {})

    lu.assertEquals(result, true)
    lu.assertEquals(calls, 2)
    lu.assertEquals(runtime.practiceDeaths.count, 1)
end

function TestInfiniDDLogic:testPracticeDefianceStartsWorldSlowAfterSuccessfulPracticeDeath()
    local host = createHost(true)
    local runtime = createRuntime(55, 4)
    local calls = 0

    local result = self.checkLastStand(host, runtime, function(victim)
        calls = calls + 1
        if calls == 1 then
            return false
        end

        table.remove(victim.LastStands)
        return true
    end, CurrentRun.Hero, {})

    lu.assertEquals(result, true)
    lu.assertEquals(calls, 2)
    lu.assertEquals(runtime.practiceDeaths.count, 1)
    lu.assertEquals(#self.threadCalls, 1)
    lu.assertEquals(self.threadCalls[1].args, { 1, 4 })
    lu.assertEquals(self.gameplaySlowCalls, {
        {
            Name = "InfiniDDPracticeSlow",
            ElapsedTimeMultiplier = 0.1,
            ApplyToPlayerUnits = true,
        },
    })

    self.threadCalls[1].callback(unpack(self.threadCalls[1].args))

    lu.assertEquals(self.waits, {
        {
            seconds = 4,
            threadName = "RoomThread",
        },
    })
    lu.assertEquals(self.gameplaySlowCalls[2], {
        Name = "InfiniDDPracticeSlow",
        ElapsedTimeMultiplier = 0.1,
        ApplyToPlayerUnits = true,
        Reverse = true,
    })
end

function TestInfiniDDLogic:testPracticeDefianceCountsButDoesNotSlowWhenSlowDisabled()
    local host = createHost(true)
    local runtime = createRuntime(55, 4, {
        enablePracticeSlow = false,
    })
    local calls = 0

    local result = self.checkLastStand(host, runtime, function(victim)
        calls = calls + 1
        if calls == 1 then
            return false
        end

        table.remove(victim.LastStands)
        return true
    end, CurrentRun.Hero, {})

    lu.assertEquals(result, true)
    lu.assertEquals(calls, 2)
    lu.assertEquals(runtime.practiceDeaths.count, 1)
    lu.assertEquals(self.gameplaySlowCalls, {})
    lu.assertEquals(self.threadCalls, {})
end

function TestInfiniDDLogic:testBaseLastStandDoesNotStartPracticeWorldSlow()
    local host = createHost(true)
    local runtime = createRuntime(55, 4)
    local calls = 0

    local result = self.checkLastStand(host, runtime, function()
        calls = calls + 1
        return true
    end, CurrentRun.Hero, {})

    lu.assertEquals(result, true)
    lu.assertEquals(calls, 1)
    lu.assertEquals(self.gameplaySlowCalls, {})
    lu.assertEquals(self.threadCalls, {})
end

function TestInfiniDDLogic:testOlderPracticeSlowThreadDoesNotClearNewerSlow()
    local host = createHost(true)
    local calls = 0
    local function baseFunc(victim)
        calls = calls + 1
        if calls % 2 == 1 then
            return false
        end

        table.remove(victim.LastStands)
        return true
    end

    lu.assertTrue(self.checkLastStand(host, createRuntime(55, 4), baseFunc, CurrentRun.Hero, {}))
    lu.assertTrue(self.checkLastStand(host, createRuntime(55, 6), baseFunc, CurrentRun.Hero, {}))
    lu.assertEquals(#self.threadCalls, 2)
    lu.assertEquals(self.threadCalls[1].args, { 1, 4 })
    lu.assertEquals(self.threadCalls[2].args, { 2, 6 })

    self.threadCalls[1].callback(unpack(self.threadCalls[1].args))
    lu.assertEquals(#self.gameplaySlowCalls, 2)

    self.threadCalls[2].callback(unpack(self.threadCalls[2].args))
    lu.assertEquals(#self.gameplaySlowCalls, 3)
    lu.assertEquals(self.gameplaySlowCalls[3], {
        Name = "InfiniDDPracticeSlow",
        ElapsedTimeMultiplier = 0.1,
        ApplyToPlayerUnits = true,
        Reverse = true,
    })
end

function TestInfiniDDLogic:testPracticeSlowOverlayRendersDuringSlowAndClearsAfter()
    local host = createHost(true)
    local runtime = createRuntime(55, 4)
    local calls = 0
    local slowLine = self.overlays.lines.practiceSlow
    local slowInterval = self.overlays.intervals.practiceSlow
    local lines = {}
    local refreshedLines = {}

    lu.assertNotNil(slowLine)
    lu.assertEquals(slowLine.region, "centerLowerStack")
    lu.assertFalse(slowLine.visible(host, runtime))
    lu.assertFalse(slowInterval.opts.when(host, runtime))

    local result = self.checkLastStand(host, runtime, function(victim)
        calls = calls + 1
        if calls == 1 then
            return false
        end

        table.remove(victim.LastStands)
        return true
    end, CurrentRun.Hero, {})

    lu.assertEquals(result, true)
    lu.assertEquals(calls, 2)
    lu.assertTrue(slowLine.visible(host, runtime))
    lu.assertTrue(slowInterval.opts.when(host, runtime))

    local overlay = {
        setLine = function(name, values)
            lines[name] = values
        end,
        refresh = function(name)
            refreshedLines[#refreshedLines + 1] = name
        end,
    }

    self.clockNow = 101.2
    slowInterval.callback(host, runtime, overlay, {
        name = "practiceSlow",
        now = self.clockNow,
    })

    lu.assertEquals(lines.practiceSlow, {
        label = "InfiniDD slow",
        value = "2.8s",
    })
    lu.assertEquals(refreshedLines, { "practiceSlow" })

    self.threadCalls[1].callback(unpack(self.threadCalls[1].args))
    lu.assertTrue(slowLine.visible(host, runtime))
    lu.assertTrue(slowInterval.opts.when(host, runtime))

    self.clockNow = 104.1
    slowInterval.callback(host, runtime, overlay, {
        name = "practiceSlow",
        now = self.clockNow,
    })

    lu.assertEquals(lines.practiceSlow, {
        label = "",
        value = "",
    })
    lu.assertEquals(refreshedLines, { "practiceSlow", "practiceSlow" })
    lu.assertFalse(slowLine.visible(host, runtime))
    lu.assertFalse(slowInterval.opts.when(host, runtime))
end

function TestInfiniDDLogic:testDeathCounterOverlayStaysHiddenBeforeFirstPracticeDeath()
    local runtime = createRuntime(55)
    local line = self.overlays.lines.deathCounter
    lu.assertNotNil(line)
    lu.assertFalse(line.visible(createHost(true), runtime))
    lu.assertFalse(line.visible(createHost(false), runtime))
    lu.assertFalse(self.overlays.intervals.deathCounter.opts.when(createHost(true), runtime))

    local lines = {}
    local refreshedLines = {}
    self.overlays.intervals.deathCounter.callback(createHost(true), runtime, {
        setLine = function(name, values)
            lines[name] = values
        end,
        refresh = function(name)
            refreshedLines[#refreshedLines + 1] = name
        end,
    })

    lu.assertEquals(lines.deathCounter.label, "")
    lu.assertEquals(lines.deathCounter.value, "")
    lu.assertEquals(refreshedLines, { "deathCounter" })
end

function TestInfiniDDLogic:testDeathCounterOverlayRendersCurrentRunCount()
    local host = createHost(true)
    local runtime = createRuntime(55)
    local calls = 0

    local result = self.checkLastStand(host, runtime, function(victim)
        calls = calls + 1
        if calls == 1 then
            return false
        end

        table.remove(victim.LastStands)
        return true
    end, CurrentRun.Hero, {})

    lu.assertEquals(result, true)
    lu.assertEquals(calls, 2)
    lu.assertEquals(runtime.practiceDeaths.count, 1)
    lu.assertTrue(self.overlays.lines.deathCounter.visible(host, runtime))
    lu.assertTrue(self.overlays.intervals.deathCounter.opts.when(host, runtime))

    local lines = {}
    local refreshedLines = {}
    self.overlays.intervals.deathCounter.callback(host, runtime, {
        setLine = function(name, values)
            lines[name] = values
        end,
        refresh = function(name)
            refreshedLines[#refreshedLines + 1] = name
        end,
    })

    lu.assertEquals(lines.deathCounter.label, "Practice deaths")
    lu.assertEquals(lines.deathCounter.value, "1")
    lu.assertEquals(refreshedLines, { "deathCounter" })
end

function TestInfiniDDLogic:testDeathCounterOverlayCanBeHiddenWithoutStoppingCount()
    local host = createHost(true)
    local runtime = createRuntime(55, 4, {
        showDeathCounter = false,
    })
    local calls = 0

    local result = self.checkLastStand(host, runtime, function(victim)
        calls = calls + 1
        if calls == 1 then
            return false
        end

        table.remove(victim.LastStands)
        return true
    end, CurrentRun.Hero, {})

    lu.assertEquals(result, true)
    lu.assertEquals(calls, 2)
    lu.assertEquals(runtime.practiceDeaths.count, 1)
    lu.assertFalse(self.overlays.lines.deathCounter.visible(host, runtime))
    lu.assertFalse(self.overlays.intervals.deathCounter.opts.when(host, runtime))
end
