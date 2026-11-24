local _, ns = ...
-- Core/Module.lua, Core/Bus.lua and Core/Report.lua through their real
-- entry, on the whole add-on loaded on a fake client: a part whose event
-- handler keeps failing is switched off at the fault limit, its stop runs
-- once, a part that needs it goes off too, the rest of the add-on keeps
-- running, and /zflow diag lists each error and why each part went off.
-- A part with a need that does not exist is off from the start; the others
-- start. The two test parts are declared on the real add-on before login,
-- the way every feature file declares its own. PLAYER_GUILD_UPDATE is used
-- because no Z-Flow file listens to it. Not tested in game.
local tests = {}

local FAULTY, NEEDER, LOST = "e2eFaulty", "e2eNeedsFaulty", "e2eLostNeed"
local EVENT = "PLAYER_GUILD_UPDATE"

local function boot(declare)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    local addon = ns.offline.addon(c)
    local seen = declare(addon)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon, seen
end

local function faultyPair(addon)
    local seen = { calls = 0, stops = {}, neederCalls = 0 }
    addon:Module({
        name = FAULTY,
        events = { [EVENT] = function()
            seen.calls = seen.calls + 1
            error("boom", 0)
        end },
        stop = function() seen.stops[FAULTY] = (seen.stops[FAULTY] or 0) + 1 end,
    })
    addon:Module({
        name = NEEDER,
        needs = { FAULTY },
        events = { [EVENT] = function() seen.neederCalls = seen.neederCalls + 1 end },
        stop = function() seen.stops[NEEDER] = (seen.stops[NEEDER] or 0) + 1 end,
    })
    return seen
end

local function diagKernel(c)
    c.slashes[ns.id.slash]("diag")
    local snaps = c.saved(ns.id.accountDB).diag.snaps
    return snaps[#snaps].kernel
end

local function problem(kernel, kind, owner)
    for _, p in ipairs(kernel.problems or {}) do
        if p.kind == kind and p.owner == owner then return p end
    end
    return nil
end

tests["module faults: both parts start, and one failing event does not switch anything off"] = function(t)
    local c, addon, seen = boot(faultyPair)
    t.eq(addon:ModuleState(FAULTY), "started")
    t.eq(addon:ModuleState(NEEDER), "started")
    c.fire(EVENT)
    t.eq(seen.calls, 1, "the failing handler ran")
    t.eq(seen.neederCalls, 1, "the other handler still ran")
    t.eq(addon:ModuleState(FAULTY), "started", "one error is below the limit")
end

tests["module faults: at the fault limit the part goes off, its stop runs once, and its needer goes off"] = function(t)
    local c, addon, seen = boot(faultyPair)
    local limit = addon.FAULT_LIMIT
    for _ = 1, limit + 3 do c.fire(EVENT) end
    t.eq(seen.calls, limit, "no handler call after the switch-off")
    local state, why = addon:ModuleState(FAULTY)
    t.eq(state, "off")
    t.eq(why, "switched off after " .. limit .. " errors; last: boom")
    local nState, nWhy = addon:ModuleState(NEEDER)
    t.eq(nState, "off", "the part that needs it goes off too")
    t.eq(nWhy, "needs " .. FAULTY .. ", which was switched off")
    t.eq(seen.stops, { [FAULTY] = 1, [NEEDER] = 1 }, "each stop ran once")
end

tests["module faults: the rest of the add-on keeps running after a part is switched off"] = function(t)
    local c, addon = boot(faultyPair)
    for _ = 1, addon.FAULT_LIMIT do c.fire(EVENT) end
    t.eq(addon:ModuleState("autoEvidence"), "started", "a real part is still running")
    t.eq(addon.phase, "running")
    local before = #c.printed
    c.slashes[ns.id.slash]("diag")
    t.ok(#c.printed > before, "the slash command still answers")
end

tests["module faults: /zflow diag lists the errors once with their count, and why each part went off"] = function(t)
    local c, addon = boot(faultyPair)
    local limit = addon.FAULT_LIMIT
    for _ = 1, limit do c.fire(EVENT) end
    local kernel = diagKernel(c)
    local errors = problem(kernel, "handler", FAULTY)
    t.ok(errors ~= nil, "the handler errors are listed")
    t.eq(errors and errors.text, "boom")
    t.eq(errors and errors.count, limit, "one row, counted, not one row per error")
    local off = problem(kernel, "module", FAULTY)
    t.eq(off and off.text, "switched off after " .. limit .. " errors; last: boom")
    local needer = problem(kernel, "module", NEEDER)
    t.eq(needer and needer.text, "needs " .. FAULTY .. ", which was switched off")
    t.eq(kernel.meter[FAULTY] and kernel.meter[FAULTY].errors, limit, "the timing row counts the errors")
end

tests["module faults: a part whose need does not exist is off from the start; the others start"] = function(t)
    local c, addon = boot(function(a)
        a:Module({ name = LOST, needs = { "e2eNoSuchPart" }, start = function() error("must not start", 0) end })
        return {}
    end)
    local state, why = addon:ModuleState(LOST)
    t.eq(state, "off")
    t.eq(why, "needs e2eNoSuchPart, which is missing")
    t.eq(addon:ModuleState("autoEvidence"), "started", "a real part started")
    local p = problem(diagKernel(c), "module", LOST)
    t.eq(p and p.text, "needs e2eNoSuchPart, which is missing")
end

return tests
