local deps = ... or {}
local data = deps.data or import("mods/data.lua")
local behaviorDeps = {
    data = data,
    clock = deps.clock,
    thread = deps.thread,
}
local practiceSlow = deps.practiceSlow or import("mods/behaviors/practice_slow.lua", nil, behaviorDeps)
local resurrection = deps.resurrection or import("mods/behaviors/resurrection.lua", nil, behaviorDeps)

local logic = {}

function logic.attach(moduleRef)
    practiceSlow.attach(moduleRef)
    resurrection.attach(moduleRef, {
        onPracticeDeath = function(runtime)
            if runtime.data.read(data.ENABLE_PRACTICE_SLOW_ALIAS) then
                practiceSlow.start(runtime)
            end
        end,
    })
end

return logic
