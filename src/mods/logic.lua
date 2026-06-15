local deps = ... or {}
local behaviorDeps = {
    data = deps.data,
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
            practiceSlow.start(runtime)
        end,
    })
end

return logic
