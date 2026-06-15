-- luacheck: globals TestInfiniDDLogic CurrentRun AddSimSpeedChange RemoveSimSpeedChange
local lu = require("luaunit")

local data = dofile("src/mods/data.lua")
local testNow = 100
local logic

TestInfiniDDLogic = {}

local function loadLogic()
    return assert(loadfile("src/mods/logic.lua"))({
        data = data,
        clock = function()
            return testNow
        end,
    })
end

local function captureHooks()
    local hooks = {}
    local overlays = {
        afterHooks = {},
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
            afterHook = function(path, callback)
                overlays.afterHooks[path] = callback
            end,
        },
    })
    return hooks, overlays
end

local function createRuntime(recoveryPercent, timePenaltySeconds)
    local values = {
        [data.RECOVERY_PERCENT_ALIAS] = recoveryPercent,
        [data.TIME_PENALTY_SECONDS_ALIAS] = timePenaltySeconds or 0,
    }
    return {
        data = {
            read = function(alias)
                return values[alias]
            end,
        },
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

function TestInfiniDDLogic:setUp()
    self.previousCurrentRun = _G.CurrentRun
    self.previousSessionMapState = _G.SessionMapState
    self.previousAddSimSpeedChange = _G.AddSimSpeedChange
    self.previousRemoveSimSpeedChange = _G.RemoveSimSpeedChange
    testNow = 100
    _G.CurrentRun = {
        Hero = {
            LastStands = {},
        },
        CurrentRoom = {
            LastStandsUsed = {},
        },
    }
    _G.SessionMapState = {}
    self.addedSimSpeeds = {}
    self.removedSimSpeeds = {}
    _G.AddSimSpeedChange = function(name, args)
        self.addedSimSpeeds[#self.addedSimSpeeds + 1] = {
            name = name,
            args = args,
        }
    end
    _G.RemoveSimSpeedChange = function(name, args)
        self.removedSimSpeeds[#self.removedSimSpeeds + 1] = {
            name = name,
            args = args,
        }
    end
    logic = loadLogic()
    self.hooks, self.overlays = captureHooks()
    self.checkLastStand = self.hooks.CheckLastStand
end

function TestInfiniDDLogic:tearDown()
    _G.CurrentRun = self.previousCurrentRun
    _G.SessionMapState = self.previousSessionMapState
    _G.AddSimSpeedChange = self.previousAddSimSpeedChange
    _G.RemoveSimSpeedChange = self.previousRemoveSimSpeedChange
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
    local result = self.checkLastStand(createHost(true), createRuntime(55), function()
        calls = calls + 1
        return false
    end, CurrentRun.Hero, {})

    lu.assertEquals(result, false)
    lu.assertEquals(calls, 2)
    lu.assertEquals(#CurrentRun.Hero.LastStands, 0)
end

function TestInfiniDDLogic:testPracticeDefianceStartsConfiguredPenaltyAfterSuccessfulCheck()
    local host = createHost(true)
    local runtime = createRuntime(55, 3)
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
    lu.assertEquals(self.addedSimSpeeds[1].name, "InfiniDDPenalty")
    lu.assertEquals(self.addedSimSpeeds[1].args.Fraction, 0)
    lu.assertEquals(self.addedSimSpeeds[1].args.LerpTime, 0.001)
    lu.assertEquals(#self.removedSimSpeeds, 0)
end

function TestInfiniDDLogic:testPenaltyOverlayPrewarmsBlankLineBeforeFirstPenalty()
    local line = self.overlays.lines.penalty
    lu.assertNotNil(line)
    lu.assertTrue(line.visible(createHost(true)))
    lu.assertFalse(line.visible(createHost(false)))
    lu.assertTrue(self.overlays.intervals.penalty.opts.when())

    local lines = {}
    local refreshedRegions = {}
    self.overlays.intervals.penalty.callback(createHost(true), createRuntime(55, 3), {
        setLine = function(name, values)
            lines[name] = values
        end,
        refreshRegion = function(region)
            refreshedRegions[#refreshedRegions + 1] = region
        end,
    })

    lu.assertEquals(lines.penalty.text, "")
    lu.assertEquals(refreshedRegions, { "centerLowerStack" })
end

function TestInfiniDDLogic:testPenaltyOverlayRendersFromSimSpeedHooksAndIntervalFinishesPenalty()
    local host = createHost(true)
    local runtime = createRuntime(55, 3)
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
    lu.assertEquals(self.addedSimSpeeds[1].name, "InfiniDDPenalty")

    local lines = {}
    local refreshedRegions = {}
    self.overlays.afterHooks.AddSimSpeedChange(host, runtime, {
        setLine = function(name, values)
            lines[name] = values
        end,
        refreshRegion = function(region)
            refreshedRegions[#refreshedRegions + 1] = region
        end,
    }, {
        args = {
            "InfiniDDPenalty",
            self.addedSimSpeeds[1].args,
        },
    })

    lu.assertEquals(lines.penalty.text, "InfiniDD penalty: 3.00s")
    lu.assertEquals(refreshedRegions, { "centerLowerStack" })

    testNow = 101.23
    self.overlays.intervals.penalty.callback(host, runtime, {
        setLine = function(name, values)
            lines[name] = values
        end,
        refreshRegion = function(region)
            refreshedRegions[#refreshedRegions + 1] = region
        end,
    })
    lu.assertEquals(lines.penalty.text, "InfiniDD penalty: 1.77s")
    lu.assertEquals(#self.removedSimSpeeds, 0)

    testNow = 103.01
    self.overlays.intervals.penalty.callback(host, runtime, {
        setLine = function(name, values)
            lines[name] = values
        end,
        refreshRegion = function(region)
            refreshedRegions[#refreshedRegions + 1] = region
        end,
    })
    lu.assertEquals(lines.penalty.text, "")
    lu.assertEquals(self.removedSimSpeeds[1].name, "InfiniDDPenalty")
    lu.assertEquals(self.removedSimSpeeds[1].args.LerpTime, 0.001)
    lu.assertEquals(refreshedRegions[#refreshedRegions], "centerLowerStack")
end

function TestInfiniDDLogic:testZeroPenaltyDoesNotChangeSimulationSpeed()
    local host = createHost(true)
    local runtime = createRuntime(55, 0)
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
    lu.assertEquals(#self.addedSimSpeeds, 0)
    lu.assertEquals(#self.removedSimSpeeds, 0)
end

function TestInfiniDDLogic:testPenaltyOverlayGetsFinalRefreshAfterCountdownEnds()
    local host = createHost(true)
    local runtime = createRuntime(55, 1)
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

    local interval = self.overlays.intervals.penalty
    lu.assertNotNil(interval)
    lu.assertTrue(interval.opts.when(createHost(false)))

    testNow = 101.01
    local refreshedRegions = {}
    interval.callback(nil, nil, {
        setLine = function()
        end,
        refreshRegion = function(region)
            refreshedRegions[#refreshedRegions + 1] = region
        end,
    })

    lu.assertEquals(refreshedRegions, { "centerLowerStack" })
    lu.assertEquals(self.removedSimSpeeds[1].name, "InfiniDDPenalty")
    lu.assertFalse(interval.opts.when(host))
end
