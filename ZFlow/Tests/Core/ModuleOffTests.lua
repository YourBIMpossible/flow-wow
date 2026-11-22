-- Switching a module off by name (k:SwitchOff), and a module that is
-- switched off while its own start is still running (LEDGER 50, Q2 and Q3).
local _, ns = ...

local function kernel()
    local c = ns.make.fakeClient()
    return ns.Kernel({}, c), c
end

return {
    -- Q3
    ["start: what a module makes after it is switched off in its own start is cut when start returns"] = function(t)
        local k, c = kernel()
        local handled, ran, stops = 0, 0, 0
        k:Module({
            name = "sell",
            start = function(ctx)
                for _ = 1, ns.FAULT_LIMIT do k.fault("sell", "early") end
                ctx.bus:on("sell", "poke", function() handled = handled + 1 end)
                ctx.sched:nextFrame("sell", function() ran = ran + 1 end)
            end,
            stop = function() stops = stops + 1 end,
        })
        k:Load()
        t.eq(k:ModuleState("sell"), "off")
        k.bus:emit("poke")
        c.advance(1, 3)
        t.eq(handled, 0, "the handler made after the switch-off is gone")
        t.eq(ran, 0, "and the job")
        t.eq(stops, 1, "its start returned without error, so its stop runs once")
        k.fault("sell", "again")
        k:SwitchOff("sell", "again")
        t.eq(stops, 1, "once only")
        t.eq(k.problems:count("module"), 1, "one problem, with the first reason")
    end,

    -- Q2: the kernel's own switch, for a module that knows it is broken.
    ["k:SwitchOff: a started module is off at once, with the reason, and stop runs once"] = function(t)
        local k, c = kernel()
        local handled, stops = 0, 0
        k:Module({
            name = "sell",
            events = { SELL_EVENT = function() handled = handled + 1 end },
            stop = function() stops = stops + 1 end,
        })
        k:Load()
        t.ok(type(k.SwitchOff) == "function", "k:SwitchOff exists")
        if type(k.SwitchOff) ~= "function" then return end
        t.eq(k:SwitchOff("sell", "it broke"), true)
        t.eq({ k:ModuleState("sell") }, { "off", "it broke" })
        t.eq(stops, 1)
        c.fire("SELL_EVENT")
        t.eq(handled, 0, "its handlers are cut")
        t.eq(k:SwitchOff("sell", "again"), false, "already off")
        t.eq({ k:ModuleState("sell") }, { "off", "it broke" }, "the first reason stands")
        t.eq(stops, 1, "once only")
        t.eq(k.problems:count("module"), 1)
    end,

    ["k:SwitchOff: a module that needs it goes off too; an unknown name is refused"] = function(t)
        local k = kernel()
        k:Module({ name = "sell" })
        k:Module({ name = "tally", needs = { "sell" } })
        k:Load()
        t.ok(type(k.SwitchOff) == "function", "k:SwitchOff exists")
        if type(k.SwitchOff) ~= "function" then return end
        t.eq(k:SwitchOff("nobody", "why"), false)
        t.eq(k.problems:count("module"), 0)
        t.eq(k:SwitchOff("sell"), true)
        t.eq(k:ModuleState("sell"), "off")
        t.eq(k:ModuleState("tally"), "off")
    end,

    -- SO2
    ["start: switched off by name in its own start, its stop runs once after what it made is cut"] = function(t)
        local k = kernel()
        local handled, seen, stops = 0, nil, 0
        k:Module({
            name = "sell",
            start = function(ctx)
                k:SwitchOff("sell", "cannot go on")
                ctx.bus:on("sell", "poke", function() handled = handled + 1 end)
            end,
            stop = function(ctx)
                stops = stops + 1
                ctx.bus:emit("poke")
                seen = handled
            end,
        })
        k:Load()
        t.eq({ k:ModuleState("sell") }, { "off", "cannot go on" })
        t.eq(stops, 1)
        t.eq(seen, 0, "the handler made after the switch-off was cut before stop ran")
        t.eq(k.problems:count("module"), 1)
    end,

    ["start: a start that raises gets no stop, switched off inside it or not"] = function(t)
        local k = kernel()
        local stops = 0
        k:Module({
            name = "sell",
            start = function() error("start broke") end,
            stop = function() stops = stops + 1 end,
        })
        k:Module({
            name = "bank",
            start = function()
                k:SwitchOff("bank", "cannot go on")
                error("start broke")
            end,
            stop = function() stops = stops + 1 end,
        })
        k:Load()
        local state, reason = k:ModuleState("sell")
        t.eq(state, "off")
        t.ok(type(reason) == "string" and reason:find("start failed", 1, true) == 1, "the start is the reason")
        t.eq(k:ModuleState("bank"), "off")
        t.eq(stops, 0)
    end,

    -- SO1
    ["k:SwitchOff before Load: the module stays off and is not wired or started"] = function(t)
        local k, c = kernel()
        local handled, ticked, started, stops = 0, 0, 0, 0
        k:Module({
            name = "sell",
            events = { SELL_EVENT = function() handled = handled + 1 end },
            ticks = { { every = 1, run = function() ticked = ticked + 1 end } },
            start = function() started = started + 1 end,
            stop = function() stops = stops + 1 end,
        })
        t.eq(k:SwitchOff("sell", "not wanted"), true)
        t.eq(k:Load(), true)
        t.eq({ k:ModuleState("sell") }, { "off", "not wanted" })
        t.eq(k.use("sell"), nil)
        c.fire("SELL_EVENT")
        c.advance(1, 3)
        t.eq({ handled, ticked, started, stops }, { 0, 0, 0, 0 }, "no handler, no tick, no start, no stop")
        t.eq(k.problems:count("module"), 1, "one problem, with the first reason")
    end,

    ["k:SwitchOff before Load: what needs it is off with the needs reason, declared before or after"] = function(t)
        local k, c = kernel()
        local handled, started = 0, 0
        local function dependant(name)
            return {
                name = name,
                needs = { "sell" },
                events = { [name:upper() .. "_EVENT"] = function() handled = handled + 1 end },
                start = function() started = started + 1 end,
            }
        end
        k:Module(dependant("early"))
        k:Module({ name = "sell" })
        k:Module({ name = "fine", start = function() started = started + 1 end })
        t.eq(k:SwitchOff("sell", "not wanted"), true)
        k:Module(dependant("late"))
        k:Load()
        t.eq({ k:ModuleState("early") }, { "off", "needs sell, which was switched off" })
        t.eq({ k:ModuleState("late") }, { "off", "needs sell, which was switched off" })
        t.eq(k:ModuleState("fine"), "started")
        c.fire("EARLY_EVENT")
        c.fire("LATE_EVENT")
        t.eq({ handled, started }, { 0, 1 }, "only the module that needs nothing of it ran")
        t.eq(k.problems:count("module"), 3, "one each")
    end,
}
