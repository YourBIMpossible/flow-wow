local _, ns = ...
-- Core/Scheduler.lua through its real entry, on the whole add-on loaded on
-- a fake client: a part's out-of-combat tick does not run while the player
-- is in combat and runs once on the first frame after it, not once per
-- missed second; an always tick keeps running in combat. The test part is
-- declared on the real add-on before login, the way every feature file
-- declares its own. Not tested in game.
local tests = {}

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    local addon = ns.offline.addon(c)
    local runs = { calm = 0, always = 0 }
    addon:Module({
        name = "e2eTicks",
        ticks = {
            { every = 1, when = "outOfCombat", run = function() runs.calm = runs.calm + 1 end },
            { every = 1, when = "always", run = function() runs.always = runs.always + 1 end },
        },
    })
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(3, 12)
    return c, addon, runs
end

tests["scheduler combat: both ticks run out of combat"] = function(t)
    local _, addon, runs = boot()
    t.eq(addon:ModuleState("e2eTicks"), "started")
    t.ok(runs.calm > 0, "the out-of-combat tick ran")
    t.ok(runs.always > 0, "the always tick ran")
end

tests["scheduler combat: the out-of-combat tick is held in combat and runs once after it"] = function(t)
    local c, _, runs = boot()
    c.setCombat(true)
    local calm, always = runs.calm, runs.always
    c.advance(4, 4)
    t.eq(runs.calm, calm, "no out-of-combat run during combat")
    t.ok(runs.always > always, "the always tick kept running in combat")
    c.setCombat(false)
    c.advance(0.1, 1)
    t.eq(runs.calm, calm + 1, "one run on the first frame after combat, not one per missed second")
end

tests["scheduler combat: after combat the tick keeps its pace"] = function(t)
    local c, _, runs = boot()
    c.setCombat(true); c.advance(4, 4)
    c.setCombat(false); c.advance(0.1, 1)
    local calm = runs.calm
    c.advance(3, 3)
    t.ok(runs.calm >= calm + 2 and runs.calm <= calm + 3, "about one run a second again")
end

return tests
