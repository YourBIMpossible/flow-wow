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
        t.eq(stops, 0, "it never started, so there is nothing to stop")
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
}
