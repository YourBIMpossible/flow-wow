-- spec.stop: what a module does when the kernel switches it off (KF2).
local _, ns = ...

local function kernel()
    local c = ns.make.fakeClient()
    return ns.Kernel({}, c), c
end

-- A module that notes each stop, and raises on its event while fail[name].
local function mod(k, log, fail, name, needs, more)
    local spec = {
        name = name,
        needs = needs,
        events = { [name:upper() .. "_EVENT"] = function()
            if fail[name] then error(name .. " broke") end
        end },
        stop = function(ctx)
            log[#log + 1] = name
            log.ctx = ctx
        end,
    }
    for key, value in pairs(more or {}) do spec[key] = value end
    return k:Module(spec)
end

return {
    ["stop: called once when the module is switched off after its errors"] = function(t)
        local k, c = kernel()
        local log, fail = {}, { sell = true }
        mod(k, log, fail, "sell")
        k:Load()
        for _ = 1, ns.FAULT_LIMIT - 1 do c.fire("SELL_EVENT") end
        t.eq(#log, 0, "not before it is switched off")
        c.fire("SELL_EVENT")
        t.eq(k:ModuleState("sell"), "off")
        t.eq({ log[1], #log }, { "sell", 1 })
        t.ok(type(log.ctx) == "table" and log.ctx.name == "sell", "it is given the module's ctx")
        t.eq(k.meter:report().sell.calls, ns.FAULT_LIMIT + 1, "run as work of the module")
        c.fire("SELL_EVENT")
        k.fault("sell", "again")
        t.eq(#log, 1, "once only")
    end,

    ["stop: the bus and the scheduler are cut before it runs"] = function(t)
        local k, c = kernel()
        local fail, seen = { sell = true }, {}
        local handled, ticked = 0, 0
        mod(k, {}, fail, "sell", nil, {
            ticks = { { every = 1, run = function() ticked = ticked + 1 end } },
            start = function(ctx)
                ctx.bus:on("sell", "poke", function() handled = handled + 1 end)
            end,
            stop = function(ctx)
                ctx.bus:emit("poke")
                seen.handled = handled
                seen.state = k:ModuleState("sell")
            end,
        })
        k:Load()
        for _ = 1, ns.FAULT_LIMIT do c.fire("SELL_EVENT") end
        t.eq(seen, { handled = 0, state = "off" }, "its own handler is already gone, and it is off")
        c.advance(1)
        c.advance(1)
        t.eq(ticked, 0, "and no tick after")
    end,

    ["stop: called for a dependant switched off with what it needs, and theirs, once each"] = function(t)
        local k, c = kernel()
        local log, fail = {}, { prices = true }
        mod(k, log, fail, "prices")
        mod(k, log, fail, "sell", { "prices" })
        mod(k, log, fail, "panel", { "sell" })
        mod(k, log, fail, "fine")
        k:Load()
        for _ = 1, ns.FAULT_LIMIT do c.fire("PRICES_EVENT") end
        t.eq({ k:ModuleState("sell") }, { "off", "needs prices, which was switched off" })
        local names = { log[1], log[2], log[3], log[4] }
        table.sort(names)
        t.eq(names, { "panel", "prices", "sell" }, "each once; the other module not at all")
        t.eq(k:ModuleState("fine"), "started")
    end,

    ["stop: an error in it is a recorded problem, not thrown, and the dependants are still switched off"] = function(t)
        local k, c = kernel()
        local log, fail = {}, { prices = true }
        mod(k, log, fail, "prices", nil, { stop = function() error("stop broke") end })
        mod(k, log, fail, "sell", { "prices" })
        k:Load()
        for _ = 1, ns.FAULT_LIMIT - 1 do c.fire("PRICES_EVENT") end
        local before = k.problems:count()
        local ok = pcall(c.fire, "PRICES_EVENT")
        t.ok(ok, "nothing is thrown")
        t.eq(k:ModuleState("prices"), "off")
        t.eq({ k:ModuleState("sell") }, { "off", "needs prices, which was switched off" })
        t.eq({ log[1], #log }, { "sell", 1 }, "the dependant's stop still runs")
        local p = k.problems:list("stop")
        t.eq(#p, 1)
        t.ok(p[1] ~= nil and p[1].owner == "prices" and tostring(p[1].text):find("stop broke", 1, true) ~= nil,
            "named, with the error")
        t.eq(k.problems:count(), before + 3, "two switch-offs and the stop error; the handler's error is listed already")
        local _, reason = k:ModuleState("prices")
        t.ok(type(reason) == "string" and reason:find("prices broke", 1, true) ~= nil, "the reason stays the switch-off's")
    end,

    ["stop: never called for a module that never started; once for one switched off in a start that returned"] = function(t)
        local k = kernel()
        local log = {}
        mod(k, log, {}, "lost", { "nothing" })                      -- a missing need
        mod(k, log, {}, "failing", nil, { start = function() error("start broke") end })
        mod(k, log, {}, "after", { "failing" })                     -- what it needs did not start
        mod(k, log, {}, "self", nil, { start = function(ctx)        -- off during its own start
            ctx.bus:on("self", "poke", function() error("poke broke") end)
            for _ = 1, ns.FAULT_LIMIT do ctx.bus:emit("poke") end
        end })
        k:Load()
        t.eq({ k:ModuleState("lost"), k:ModuleState("failing"), k:ModuleState("after"), (k:ModuleState("self")) },
            { "off", "off", "off", "off" })
        t.eq({ log[1], #log }, { "self", 1 }, "only the one whose start returned without error (SO2)")
        t.eq(k.problems:count("stop"), 0)
    end,

    ["stop: not called beside the predecessor, and a stop that is no function is refused"] = function(t)
        local c = ns.make.fakeClient()
        c.setLoaded(ns.id.predecessor, true)
        local k = ns.Kernel({}, c)
        local log = {}
        mod(k, log, {}, "sell")
        k:Load()
        t.eq(k.paused, true)
        t.eq(#log, 0)

        local k2 = kernel()
        t.eq(k2:Module({ name = "bad", stop = "no" }), nil)
        t.eq(k2:ModuleState("bad"), nil)
        t.eq(k2.problems:count("module"), 1)
    end,
}
