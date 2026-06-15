local data = {}

data.RECOVERY_PERCENT_ALIAS = "RecoveryPercent"
data.recoveryPercent = {
    default = 40,
    min = 1,
    max = 100,
    step = 5,
}
data.TIME_PENALTY_SECONDS_ALIAS = "TimePenaltySeconds"
data.timePenaltySeconds = {
    default = 30,
    min = 0,
    max = 120,
    step = 5,
}

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
            type = "int",
            alias = data.TIME_PENALTY_SECONDS_ALIAS,
            default = data.timePenaltySeconds.default,
            min = data.timePenaltySeconds.min,
            max = data.timePenaltySeconds.max,
        },
    }
end

return data
