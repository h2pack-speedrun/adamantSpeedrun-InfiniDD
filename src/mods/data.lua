local data = {}

data.RECOVERY_PERCENT_ALIAS = "RecoveryPercent"
data.recoveryPercent = {
    default = 40,
    min = 1,
    max = 100,
    step = 5,
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
