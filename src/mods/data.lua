local data = {}

data.RECOVERY_PERCENT_ALIAS = "RecoveryPercent"
data.SHOW_DEATH_COUNTER_OVERLAY_ALIAS = "ShowDeathCounterOverlay"
data.ENABLE_PRACTICE_SLOW_ALIAS = "EnablePracticeSlow"
data.PRACTICE_SLOW_SECONDS_ALIAS = "PracticeSlowSeconds"
data.recoveryPercent = {
    default = 40,
    min = 1,
    max = 100,
    step = 5,
}
data.practiceSlowSeconds = {
    default = 3,
    min = 1,
    max = 10,
    step = 1,
}
data.PRACTICE_DEATHS_CACHE_ALIAS = "PracticeDeaths"

function data.buildStorage()
    return {
        {
            type = "int",
            alias = data.RECOVERY_PERCENT_ALIAS,
            default = data.recoveryPercent.default,
            min = data.recoveryPercent.min,
            max = data.recoveryPercent.max,
        },
        {
            type = "bool",
            alias = data.SHOW_DEATH_COUNTER_OVERLAY_ALIAS,
            default = true,
        },
        {
            type = "bool",
            alias = data.ENABLE_PRACTICE_SLOW_ALIAS,
            default = true,
        },
        {
            type = "int",
            alias = data.PRACTICE_SLOW_SECONDS_ALIAS,
            default = data.practiceSlowSeconds.default,
            min = data.practiceSlowSeconds.min,
            max = data.practiceSlowSeconds.max,
        },
    }
end

function data.buildCache()
    return {
        [data.PRACTICE_DEATHS_CACHE_ALIAS] = {
            domain = "currentRun",
            key = "PracticeDeaths",
            factory = function()
                return {
                    count = 0,
                }
            end,
        },
    }
end

return data
