-- A module that keeps raising errors is switched off by the kernel.
local _, ns = ...

local LIMIT = 5

local function kernel()
    local c = ns.make.fakeClient()
    return ns.Kernel({}, c), c
end

-- A module whose event handler raises when fail[name] is set, and whose tick
-- only counts. calls[name] = { event = n, tick = n }.
local function shaky(k, calls, fail, name, needs)
    calls[name] = { event = 0, tick = 0 }
    return k:Module({
        name = name,
        needs = needs,
        events = { [name:upper() .. "_EVENT"] = function()
            calls[name].event = calls[name].event + 1
            if fail[name] then error(name .. " broke") end
        end },
        ticks = { { every = 1, run = function() calls[name].tick = calls[name].tick + 1 end } },
    })
end

return {
    ["fault: a module is switched off on its fifth error, not its fourth"] = function(t)
        local k, c = kernel()
        local calls, fail = {}, { sell = true }
        shaky(k, calls, fail, "sell")
        k:Load()
        for _ = 1, LIMIT - 1 do c.fire("SELL_EVENT") end
        t.eq(calls.sell.event, 4)
        t.eq({ k:ModuleState("sell") }, { "started" }, "four errors: still on, no reason")
        t.eq(k.problems:count("module"), 0)
        c.fire("SELL_EVENT")
        t.eq(calls.sell.event, 5)
        t.eq(k:ModuleState("sell"), "off", "the fifth error switches it off")
    end,

    ["fault: the handlers and ticks of a switched-off module no longer run"] = function(t)
        local k, c = kernel()
        local calls, fail = {}, { sell = true }
        shaky(k, calls, fail, "sell")
        shaky(k, calls, fail, "fine")
        fail.fine = nil
        k:Load()
        c.advance(1)
        t.eq({ calls.sell.tick, calls.fine.tick }, { 1, 1 })
        for _ = 1, LIMIT do c.fire("SELL_EVENT") end
        t.eq(k:ModuleState("sell"), "off")
        c.fire("SELL_EVENT")
        c.fire("SELL_EVENT")
        c.fire("FINE_EVENT")
        c.advance(1)
        c.advance(1)
        t.eq(calls.sell, { event = 5, tick = 1 }, "no handler and no tick after the fifth error")
        t.eq(calls.fine, { event = 1, tick = 3 }, "another module goes on")
        t.eq(k.use("sell"), nil, "and it is no longer given to others")
        t.eq(k.meter:report().sell.errors, 5, "it stopped raising errors")
    end,

    ["fault: errors from two owners are counted apart"] = function(t)
        local k, c = kernel()
        local calls, fail = {}, { a = true, b = true }
        shaky(k, calls, fail, "a")
        shaky(k, calls, fail, "b")
        k:Load()
        for _ = 1, LIMIT - 1 do
            c.fire("A_EVENT")
            c.fire("B_EVENT")
        end
        t.eq({ k:ModuleState("a"), k:ModuleState("b") }, { "started", "started" }, "eight errors, four each")
        c.fire("A_EVENT")
        t.eq({ k:ModuleState("a"), k:ModuleState("b") }, { "off", "started" })
        c.fire("B_EVENT")
        t.eq(k:ModuleState("b"), "off")
    end,

    ["fault: a success does not reset the count"] = function(t)
        local k, c = kernel()
        local calls, fail = {}, {}
        shaky(k, calls, fail, "sell")
        k:Load()
        for i = 1, LIMIT - 1 do
            fail.sell = true
            c.fire("SELL_EVENT")
            fail.sell = nil
            c.fire("SELL_EVENT")
            c.fire("SELL_EVENT")
            t.eq(k:ModuleState("sell"), "started", "error " .. i .. " of 5, with successes between")
        end
        fail.sell = true
        c.fire("SELL_EVENT")
        t.eq(k:ModuleState("sell"), "off")
        t.eq(calls.sell.event, 13)
    end,

    ["fault: handlers, ticks and scheduler jobs of one module count together"] = function(t)
        local k, c = kernel()
        local ran = { event = 0, tick = 0, job = 0, late = 0 }
        k:Module({
            name = "mixed",
            events = { MIXED_EVENT = function()
                ran.event = ran.event + 1
                error("event broke")
            end },
            ticks = { { every = 1, run = function()
                ran.tick = ran.tick + 1
                error("tick broke")
            end } },
            start = function(ctx)
                ctx.sched:after("mixed", 0.5, function()
                    ran.job = ran.job + 1
                    error("job broke")
                end)
                ctx.sched:after("mixed", 30, function() ran.late = ran.late + 1 end)
            end,
        })
        local other = 0
        k:Module({ name = "other", ticks = { { every = 1, run = function() other = other + 1 end } } })
        k:Load()
        c.fire("MIXED_EVENT")
        c.fire("MIXED_EVENT")
        c.advance(1)                                -- the job and the first tick
        t.eq(ran, { event = 2, tick = 1, job = 1, late = 0 })
        t.eq(k:ModuleState("mixed"), "started", "four errors of three kinds")
        c.advance(1)                                -- the second tick is the fifth error
        local state, reason = k:ModuleState("mixed")
        t.eq(state, "off")
        t.ok(type(reason) == "string" and reason:find("tick broke", 1, true), "the last error is the tick's")
        c.fire("MIXED_EVENT")
        c.advance(40)
        t.eq(ran, { event = 2, tick = 2, job = 1, late = 0 }, "its waiting job is cancelled with it")
        t.ok(other >= 3, "the other module's tick goes on")
    end,

    ["fault: a dependant is turned off with the named reason, and its dependants after it"] = function(t)
        local k, c = kernel()
        local calls, fail = {}, { prices = true }
        shaky(k, calls, fail, "prices")
        shaky(k, calls, fail, "sell", { "prices" })
        shaky(k, calls, fail, "panel", { "sell" })
        shaky(k, calls, fail, "fine")
        k:Load()
        for _ = 1, LIMIT - 1 do c.fire("PRICES_EVENT") end
        t.eq({ k:ModuleState("sell"), k:ModuleState("panel") }, { "started", "started" })
        c.fire("PRICES_EVENT")
        t.eq(k:ModuleState("prices"), "off")
        t.eq({ k:ModuleState("sell") }, { "off", "needs prices, which was switched off" })
        t.eq({ k:ModuleState("panel") }, { "off", "needs sell, which was switched off" })
        t.eq({ k:ModuleState("fine") }, { "started" })
        c.fire("SELL_EVENT")
        c.fire("PANEL_EVENT")
        c.fire("FINE_EVENT")
        c.advance(1)
        t.eq(calls.sell, { event = 0, tick = 0 }, "the dependant's handlers and ticks are cancelled")
        t.eq(calls.panel, { event = 0, tick = 0 })
        t.eq(calls.fine, { event = 1, tick = 1 })
        t.eq(k.use("sell"), nil)
    end,

    ["fault: the reason names the count and the last error, and is readable"] = function(t)
        local k, c = kernel()
        local n = 0
        k:Module({ name = "sell", events = { SELL_EVENT = function()
            n = n + 1
            error("broke at " .. n)
        end } })
        k:Module({ name = "panel", needs = { "sell" } })
        k:Load()
        for _ = 1, LIMIT do c.fire("SELL_EVENT") end
        local state, reason = k:ModuleState("sell")
        t.eq(state, "off")
        t.ok(type(reason) == "string", "a reason is given")
        if type(reason) ~= "string" then return end
        t.ok(reason:find("5 errors", 1, true), reason)
        t.ok(reason:find("broke at 5", 1, true), "the last error text: " .. reason)
        t.ok(not reason:find("broke at 4", 1, true), "and only the last")

        -- The same reason in the problems list and in what diag collects.
        local p = k.problems:list("module")
        t.eq(#p, 2)
        t.eq({ p[1].owner, p[1].text }, { "sell", reason })
        t.eq({ p[2].owner, p[2].text }, { "panel", "needs sell, which was switched off" })
        local found
        for _, row in ipairs(ns.Diag.Collect(k, "test").kernel.problems) do
            if row.kind == "module" and row.owner == "sell" then found = row.text end
        end
        t.eq(found, reason, "diag carries it")
    end,

    ["fault: switched off once; a later error of its own changes nothing"] = function(t)
        local k, c = kernel()
        local n = 0
        -- Two handlers of one module on one event: both are in the emit that
        -- brings the fifth error, and the second must not run after it.
        k:Module({
            name = "sell",
            events = { SELL_EVENT = function()
                n = n + 1
                error("first broke")
            end },
            start = function(ctx)
                ctx.bus:on("sell", "SELL_EVENT", function()
                    n = n + 1
                    error("second broke")
                end)
            end,
        })
        k:Load()
        c.fire("SELL_EVENT")
        c.fire("SELL_EVENT")                        -- four errors
        t.eq({ n, k:ModuleState("sell") }, { 4, "started" })
        c.fire("SELL_EVENT")                        -- the fifth is the first handler's
        local _, reason = k:ModuleState("sell")
        t.eq(n, 5, "the second handler did not run in that emit")
        t.ok(type(reason) == "string" and reason:find("first broke", 1, true), "the reason is the fifth error's")
        t.eq(k.problems:count("module"), 1)
    end,

    ["fault: an owner that is no module is counted and nothing is switched off"] = function(t)
        local k, c = kernel()
        local n = 0
        local calls, fail = {}, {}
        shaky(k, calls, fail, "fine")
        k:Load()
        k.bus:on("loose", "LOOSE", function()
            n = n + 1
            error("loose broke")
        end)
        for _ = 1, LIMIT + 2 do k.bus:emit("LOOSE") end
        t.eq(n, LIMIT + 2, "there is no module to switch off: it goes on, recorded each time")
        t.eq(k.meter:report().loose.errors, LIMIT + 2)
        t.eq(k.problems:count("module"), 0)
        c.fire("FINE_EVENT")
        t.eq(calls.fine.event, 1)
    end,

    ["fault: switched off while the modules start, it is not started after all"] = function(t)
        local k, c = kernel()
        local started, handled = {}, 0
        -- "first" starts before "second" and raises five errors in it.
        k:Module({ name = "first", start = function(ctx)
            started[#started + 1] = "first"
            for _ = 1, LIMIT do ctx.bus:emit("poke") end
        end })
        k:Module({
            name = "second",
            needs = { "first" },
            start = function(ctx)
                started[#started + 1] = "second"
                ctx.bus:on("second", "late", function() handled = handled + 1 end)
            end,
        })
        k:Module({ name = "third", needs = { "second" }, start = function() started[#started + 1] = "third" end })
        k.bus:on("second", "poke", function() error("poke broke") end)
        t.eq(k:Load(), true)
        t.eq(started, { "first" }, "neither it nor its dependant is started")
        local state, reason = k:ModuleState("second")
        t.eq(state, "off")
        t.ok(type(reason) == "string" and reason:find("5 errors", 1, true), "its own reason stands")
        t.eq({ k:ModuleState("third") }, { "off", "needs second, which was switched off" })
        t.eq(k:ModuleState("first"), "started")
        k.bus:emit("late")
        t.eq(handled, 0)
        t.eq(c.ticking(), false)
    end,

    ["fault: switched off during its own start, it stays off"] = function(t)
        local k = kernel()
        k:Module({ name = "self", start = function(ctx)
            ctx.bus:on("self", "poke", function() error("poke broke") end)
            for _ = 1, LIMIT do ctx.bus:emit("poke") end
        end })
        k:Load()
        local state, reason = k:ModuleState("self")
        t.eq(state, "off")
        t.ok(type(reason) == "string" and reason:find("poke broke", 1, true), "the reason is kept")
    end,

    -- KF1: the emit that brings the fifth error stops there for the module
    -- and for what needs it.
    ["fault: in the emit of the fifth error, a later handler of the owner and a dependant's later handler are not called"] = function(t)
        local k, c = kernel()
        local n = { first = 0, dependant = 0, later = 0, other = 0 }
        -- The handlers on SHARED, in the order they are registered:
        -- prices' first (raises), sell's, other's, prices' later.
        k:Module({
            name = "prices",
            events = { SHARED = function()
                n.first = n.first + 1
                error("prices broke")
            end },
            start = function(ctx)
                ctx.bus:on("prices", "SHARED", function() n.later = n.later + 1 end)
            end,
        })
        k:Module({ name = "sell", needs = { "prices" }, events = { SHARED = function() n.dependant = n.dependant + 1 end } })
        k:Module({ name = "other", events = { SHARED = function() n.other = n.other + 1 end } })
        k:Load()
        for _ = 1, LIMIT - 1 do c.fire("SHARED") end
        t.eq(n, { first = 4, dependant = 4, later = 4, other = 4 }, "four errors: every handler still runs")
        t.eq({ k:ModuleState("prices"), k:ModuleState("sell") }, { "started", "started" })
        c.fire("SHARED")
        t.eq(k:ModuleState("prices"), "off")
        t.eq({ k:ModuleState("sell") }, { "off", "needs prices, which was switched off" })
        t.eq(n.first, 5)
        t.eq(n.later, 4, "the owner's later handler is not called in that emit")
        t.eq(n.dependant, 4, "nor the dependant's, later in the same snapshot")
        t.eq(n.other, 5, "a module that needs neither is still called")
        t.eq(#c.printed, 0, "and nothing is said in chat")
        c.fire("SHARED")
        t.eq(n, { first = 5, dependant = 4, later = 4, other = 6 })
        t.eq(#c.printed, 0)
    end,
}
