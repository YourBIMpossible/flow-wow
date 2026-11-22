-- Bus and Scheduler, driven by the fake client's events and clock.
local _, ns = ...

-- A kernel whose bus and scheduler are live (the guard passed, no modules).
local function running()
    local c = ns.make.fakeClient()
    local k = ns.Kernel({}, c)
    k:Load()
    return k, c
end

return {
    ["bus: emit reaches every handler with the arguments, in order"] = function(t)
        local k = running()
        local log = {}
        k.bus:on("a", "thing:happened", function(x, y) log[#log + 1] = { "a", x, y } end)
        k.bus:on("b", "thing:happened", function(x, y) log[#log + 1] = { "b", x, y } end)
        k.bus:on("b", "other", function() log[#log + 1] = "other" end)
        t.eq(k.bus:emit("thing:happened", 1, "two"), 2)
        t.eq(log, { { "a", 1, "two" }, { "b", 1, "two" } })
        t.eq(k.bus:emit("nobody:listens"), 0)
    end,

    ["bus: off by owner, by owner and event, and by the returned cancel"] = function(t)
        local k = running()
        local n = { a1 = 0, a2 = 0, b1 = 0 }
        k.bus:on("a", "one", function() n.a1 = n.a1 + 1 end)
        local cancel = k.bus:on("a", "two", function() n.a2 = n.a2 + 1 end)
        k.bus:on("b", "one", function() n.b1 = n.b1 + 1 end)
        k.bus:off("a", "one")
        k.bus:emit("one"); k.bus:emit("two")
        t.eq(n, { a1 = 0, a2 = 1, b1 = 1 })
        cancel()
        cancel()
        k.bus:emit("two")
        t.eq(n.a2, 1)
        k.bus:on("b", "two", function() n.b1 = n.b1 + 10 end)
        k.bus:off("b")
        k.bus:emit("one"); k.bus:emit("two")
        t.eq(n, { a1 = 0, a2 = 1, b1 = 1 })
    end,

    ["bus: a handler error is caught, recorded with owner and event, others still run"] = function(t)
        local k = running()
        local ran = {}
        k.bus:on("first", "thing", function() ran[#ran + 1] = "first" end)
        k.bus:on("broken", "thing", function() error("handler broke") end)
        k.bus:on("last", "thing", function() ran[#ran + 1] = "last" end)
        t.eq(k.bus:emit("thing"), 3)
        t.eq(ran, { "first", "last" })
        local p = k.problems:list("handler")
        t.eq(#p, 1)
        t.eq(p[1].owner, "broken")
        t.eq(p[1].detail, "thing")
        t.ok(p[1].text:find("handler broke", 1, true), p[1].text)
        k.bus:emit("thing")
        t.eq(#k.problems:list("handler"), 1, "the same error is one problem")
        t.eq(k.problems:list("handler")[1].count, 2, "counted twice")
        t.eq(#ran, 4)
    end,

    ["bus: client events come from the client; internal names never reach it"] = function(t)
        local k, c = running()
        local got = {}
        k.bus:on("bags", "BAG_UPDATE", function(bag) got[#got + 1] = bag end)
        k.bus:on("bags", "BAG_UPDATE", function(bag) got[#got + 1] = bag * 10 end)
        k.bus:on("bags", "bags:changed", function() end)
        t.eq(c.events(), { "BAG_UPDATE" }, "asked for once; the internal name is not asked for")
        c.fire("BAG_UPDATE", 2)
        t.eq(got, { 2, 20 })
        k.bus:off("bags")
        t.eq(c.events(), {}, "dropped with the last handler")
        c.fire("BAG_UPDATE", 3)
        t.eq(#got, 2)
    end,

    ["bus: nothing is asked of the client until the bus is enabled"] = function(t)
        local c = ns.make.fakeClient()
        local k = ns.Kernel({}, c)
        local n = 0
        k.bus:on("x", "PLAYER_LEVEL_UP", function() n = n + 1 end)
        t.eq(c.events(), {})
        c.fire("PLAYER_LEVEL_UP")
        t.eq(n, 0)
        k.bus:enable()
        t.eq(c.events(), { "PLAYER_LEVEL_UP" })
        c.fire("PLAYER_LEVEL_UP")
        t.eq(n, 1)
    end,

    ["bus: a bad registration is recorded, not raised"] = function(t)
        local k = running()
        local cancel = k.bus:on("x", "thing", "not a function")
        k.bus:on(nil, "thing", function() end)
        k.bus:on("x", "", function() end)
        cancel()
        t.eq(k.problems:count("bus"), 3)
        t.eq(k.bus:emit("thing"), 0)
    end,

    ["sched: every runs on its interval off the client clock"] = function(t)
        local k, c = running()
        local n = 0
        t.eq(c.ticking(), false, "no frame tick without work")
        local cancel = k.sched:every("mod", 1, function() n = n + 1 end)
        t.eq(c.ticking(), true)
        c.advance(0.5)
        t.eq(n, 0)
        c.advance(0.5)
        t.eq(n, 1)
        c.advance(3, 30)
        t.eq(n, 4)
        c.advance(10)
        t.eq(n, 5, "one long frame is one run, not a burst")
        cancel()
        t.eq(c.ticking(), false, "the frame tick is dropped with the last job")
        c.advance(5, 5)
        t.eq(n, 5)
    end,

    ["sched: after runs once"] = function(t)
        local k, c = running()
        local n = 0
        k.sched:after("mod", 0.5, function() n = n + 1 end)
        c.advance(0.4)
        t.eq(n, 0)
        c.advance(0.2)
        t.eq(n, 1)
        c.advance(5, 5)
        t.eq(n, 1)
        t.eq(c.ticking(), false)
        local cancel = k.sched:after("mod", 1, function() n = n + 1 end)
        cancel()
        c.advance(5, 5)
        t.eq(n, 1, "cancelled before it was due")
    end,

    ["sched: nextFrame runs on the next frame, once"] = function(t)
        local k, c = running()
        local log = {}
        k.sched:nextFrame("mod", function()
            log[#log + 1] = "outer"
            k.sched:nextFrame("mod", function() log[#log + 1] = "inner" end)
        end)
        t.eq(log, {})
        c.advance(0.01)
        t.eq(log, { "outer" }, "a job added during a frame waits for the next")
        c.advance(0.01)
        t.eq(log, { "outer", "inner" })
        c.advance(0.01, 3)
        t.eq(#log, 2)
        t.eq(c.ticking(), false)
    end,

    ["sched: afterCombat runs now out of combat, else when combat ends"] = function(t)
        local k, c = running()
        local log = {}
        k.sched:afterCombat("mod", function() log[#log + 1] = "now" end)
        t.eq(log, { "now" })
        c.setCombat(true)
        k.sched:afterCombat("mod", function() log[#log + 1] = "queued" end)
        local cancel = k.sched:afterCombat("mod", function() log[#log + 1] = "cancelled" end)
        cancel()
        c.advance(5, 5)
        t.eq(log, { "now" }, "held while in combat")
        c.setCombat(false)
        t.eq(log, { "now", "queued" })
        c.setCombat(true)
        c.setCombat(false)
        t.eq(#log, 2, "once")
        t.eq(c.events(), {}, "the combat-end listener is dropped when the queue is empty")
    end,

    ["sched: an outOfCombat tick is held in combat and runs on the first frame after"] = function(t)
        local k, c = running()
        local always, calm = 0, 0
        k.sched:every("mod", 1, function() always = always + 1 end)
        k.sched:every("mod", 1, function() calm = calm + 1 end, { when = "outOfCombat" })
        c.advance(1)
        t.eq({ always, calm }, { 1, 1 })
        c.setCombat(true)
        c.advance(3, 3)
        t.eq({ always, calm }, { 4, 1 })
        c.setCombat(false)
        c.advance(0.01)
        t.eq({ always, calm }, { 4, 2 })
    end,

    ["sched: a job error is recorded against its owner and the rest still run"] = function(t)
        local k, c = running()
        local n = 0
        k.sched:every("broken", 1, function() error("tick broke") end)
        k.sched:every("fine", 1, function() n = n + 1 end)
        c.advance(2, 2)
        t.eq(n, 2)
        local p = k.problems:list("tick")
        t.eq(#p, 1)
        t.eq(p[1].owner, "broken")
        t.ok(p[1].text:find("tick broke", 1, true), p[1].text)
        t.eq(p[1].count, 2)
    end,

    ["sched: report gives calls and time per owner"] = function(t)
        local k, c = running()
        k.sched:every("slow", 1, function() c.burn(5) end)
        k.sched:every("quick", 0.5, function() c.burn(1) end)
        k.sched:every("bad", 1, function() c.burn(2); error("x") end)
        k.bus:on("slow", "thing", function() c.burn(10) end)
        c.advance(2, 4)
        k.bus:emit("thing")
        local r = k.sched:report()
        t.eq(r.slow, { calls = 3, ms = 20, errors = 0 }, "two ticks and one event handler")
        t.eq(r.quick, { calls = 4, ms = 4, errors = 0 })
        t.eq(r.bad, { calls = 2, ms = 4, errors = 2 })
        r.slow.calls = 99
        t.eq(k.sched:report().slow.calls, 3, "the report is a copy")
    end,

    ["sched: off cancels everything of one owner"] = function(t)
        local k, c = running()
        local n = { a = 0, b = 0 }
        k.sched:every("a", 1, function() n.a = n.a + 1 end)
        k.sched:after("a", 1, function() n.a = n.a + 1 end)
        k.sched:nextFrame("a", function() n.a = n.a + 1 end)
        k.sched:every("b", 1, function() n.b = n.b + 1 end)
        c.setCombat(true)
        k.sched:afterCombat("a", function() n.a = n.a + 1 end)
        k.sched:off("a")
        c.setCombat(false)
        c.advance(2, 2)
        t.eq(n, { a = 0, b = 2 })
    end,

    ["sched: nothing runs and nothing is asked of the client until enabled"] = function(t)
        local c = ns.make.fakeClient()
        local k = ns.Kernel({}, c)
        local n = 0
        k.sched:every("mod", 1, function() n = n + 1 end)
        k.sched:afterCombat("mod", function() n = n + 100 end)
        t.eq(c.ticking(), false)
        t.eq(c.events(), {})
        c.advance(3, 3)
        t.eq(n, 0)
        k.sched:enable()
        t.eq(n, 100, "the afterCombat queue runs once enabled, out of combat")
        t.eq(c.ticking(), true)
        c.advance(1)
        t.eq(n, 101)
    end,

    ["sched: a bad job is recorded, not raised"] = function(t)
        local k, c = running()
        k.sched:every("mod", 0, function() end)
        k.sched:every("mod", "soon", function() end)
        k.sched:every("mod", 1, function() end, { when = "visible" })
        k.sched:every("mod", 1, "not a function")
        k.sched:after("mod", -1, function() end)
        k.sched:after(nil, 1, function() end)
        k.sched:nextFrame("mod", nil)
        local recorded = 0
        for _, p in ipairs(k.problems:list("sched")) do recorded = recorded + p.count end
        t.eq(recorded, 7, "one record per bad job (repeats of one problem are counted)")
        t.eq(c.ticking(), false)
    end,
}
