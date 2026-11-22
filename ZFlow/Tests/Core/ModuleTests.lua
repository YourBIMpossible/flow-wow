-- Kinds, modules, the three load phases, the load guard and boot.
local _, ns = ...

local function kernel()
    local c = ns.make.fakeClient()
    return ns.Kernel({}, c), c
end

-- A module that logs its start and has one client event and one tick.
local function noisy(k, log, name, needs)
    return k:Module({
        name = name,
        needs = needs,
        events = { [name:upper() .. "_EVENT"] = function() log[#log + 1] = name .. " event" end },
        ticks = { { every = 1, run = function() log[#log + 1] = name .. " tick" end } },
        start = function() log[#log + 1] = name .. " start" end,
    })
end

return {
    ["kinds: a row that fits its field table registers"] = function(t)
        local k = kernel()
        t.eq(k:Kind({ name = "activity", row = { order = "number", plan = "function", note = "string?", data = "any" } }), "activity")
        local row = { order = 1, plan = function() end, data = false }
        t.ok(k:Register("activity", "mining", row) == row)
        t.ok(k:Get("activity", "mining") == row)
        t.eq(k:Get("activity", "nothing"), nil)
        t.eq(k:Get("nokind", "mining"), nil)
        t.eq(k.problems:count(), 0)
    end,

    ["kinds: a bad row fails that row and is recorded"] = function(t)
        local k = kernel()
        k:Kind({ name = "activity", row = { order = "number", plan = "function", note = "string?" } })
        t.eq(k:Register("activity", "a", { plan = function() end }), nil)
        t.eq(k:Register("activity", "b", { order = "1", plan = function() end }), nil)
        t.eq(k:Register("activity", "c", { order = 1, plan = function() end, note = 5 }), nil)
        t.eq(k:Register("activity", "d", "not a table"), nil)
        t.eq(k:Register("activity", {}, { order = 1, plan = function() end }), nil)
        t.ok(k:Register("activity", "good", { order = 1, plan = function() end }), "a good row after bad ones registers")
        local p = k.problems:list("register")
        t.eq(#p, 5)
        t.eq({ p[1].owner, p[1].text }, { "activity:a", "missing order" })
        t.eq({ p[2].owner, p[2].text }, { "activity:b", "order must be a number" })
        t.eq({ p[3].owner, p[3].text }, { "activity:c", "note must be a string" })
        t.eq(p[4].text, "the row is not a table")
        t.eq(k:Get("activity", "a"), nil)
    end,

    ["kinds: a duplicate key is recorded and the first row stands"] = function(t)
        local k = kernel()
        k:Kind({ name = "slash", row = { run = "function" } })
        local first = { run = function() end }
        t.ok(k:Register("slash", "sell", first))
        t.eq(k:Register("slash", "sell", { run = function() end }), nil)
        t.ok(k:Get("slash", "sell") == first)
        local p = k.problems:list("register")
        t.eq(#p, 1)
        t.eq({ p[1].owner, p[1].text }, { "slash:sell", "duplicate key" })
    end,

    ["kinds: a row check may be a function; unknown and duplicate kinds are recorded"] = function(t)
        local k = kernel()
        k:Kind({ name = "even", row = function(row, key)
            if row.n % 2 ~= 0 then return false, key .. " is odd" end
            return true
        end })
        k:Kind({ name = "strict", row = function() error("check broke") end })
        k:Kind({ name = "free" })
        t.ok(k:Register("even", "two", { n = 2 }))
        t.eq(k:Register("even", "three", { n = 3 }), nil)
        t.eq(k:Register("strict", "x", {}), nil, "a failing check refuses the row instead of raising")
        t.ok(k:Register("free", 7, {}), "no row rule: any table, number keys allowed")
        t.eq(k:Register("nokind", "x", {}), nil)
        local p = k.problems:list("register")
        t.eq(#p, 3)
        t.eq(p[1].text, "three is odd")
        t.ok(p[2].text:find("check broke", 1, true), p[2].text)
        t.eq({ p[3].owner, p[3].text }, { "nokind:x", "unknown kind" })

        t.eq(k:Kind({ name = "even" }), nil)
        t.eq(k:Kind({ row = {} }), nil)
        t.eq(k:Kind({ name = "odd", row = "number" }), nil)
        t.eq(k:Kind({ name = "odd", row = { n = 5 } }), nil)
        t.eq(k.problems:count("kind"), 4)
    end,

    ["kinds: Each walks rows in registration order"] = function(t)
        local k = kernel()
        k:Kind({ name = "step" })
        k:Register("step", "c", { n = 1 })
        k:Register("step", "a", { n = 2 })
        k:Register("step", "b", { n = 3 })
        local seen = {}
        for key, row in k:Each("step") do seen[#seen + 1] = key .. row.n end
        t.eq(seen, { "c1", "a2", "b3" })
        local none = 0
        for _ in k:Each("nokind") do none = none + 1 end
        t.eq(none, 0)
    end,

    ["modules: three phases, declare then wire then start"] = function(t)
        local k, c = kernel()
        local log = {}
        t.eq(k.phase, "declare")
        k:Module({
            name = "early",
            events = { ["late:hello"] = function(ctx, word) log[#log + 1] = ctx.name .. " heard " .. word end },
            start = function() log[#log + 1] = "early start in " .. k.phase end,
        })
        k:Module({
            name = "late",
            start = function(ctx)
                -- every module is wired before any module starts
                ctx.bus:emit("late:hello", "hi")
                log[#log + 1] = "late start"
            end,
        })
        k.bus:on("test", "kernel:started", function() log[#log + 1] = "started in " .. k.phase end)
        t.eq(k:ModuleState("early"), "declared")
        t.eq(log, {}, "declaring runs nothing")
        t.eq(c.events(), {})
        t.eq(k:Load(), true)
        t.eq(log, { "early start in start", "early heard hi", "late start", "started in running" })
        t.eq(k.phase, "running")
        t.eq(k:ModuleState("early"), "started")
        t.eq(k:Load(), true, "a second Load does nothing")
        t.eq(#log, 4)
    end,

    ["modules: start order follows needs, not file order"] = function(t)
        local k = kernel()
        local log = {}
        noisy(k, log, "c", { "b", "store" })
        noisy(k, log, "b", { "a" })
        noisy(k, log, "a", { "client", "store", "settings", "bus", "sched" })
        k:Load()
        t.eq(log, { "a start", "b start", "c start" })
        t.eq(k.problems:count(), 0, "kernel services are always there to need")
    end,

    ["modules: events and ticks get the module context; use returns provides"] = function(t)
        local k, c = kernel()
        local got = {}
        k:Module({ name = "prices", provides = { Of = function(n) return n * 2 end } })
        k:Module({
            name = "sell",
            needs = { "prices" },
            settings = { { key = "sell.on", scope = "char", type = "bool", default = true, label = "On" } },
            events = { MERCHANT_SHOW = function(ctx, a, b) got[#got + 1] = { ctx.name, a, b, ctx.use("prices").Of(4) } end },
            ticks = { { every = 2, run = function(ctx) got[#got + 1] = { ctx.name, ctx.settings:get("sell.on") } end } },
            start = function(ctx)
                got[#got + 1] = ctx.store == k.store and ctx.client == c and ctx.bus == k.bus and ctx.sched == k.sched
                    and ctx.id == ns.id
            end,
        })
        t.eq(k.settings:get("sell.on"), true, "setting rows are declared with the module")
        t.eq(k.use("prices").Of(3), 6, "use resolves before load too")
        k:Load()
        c.fire("MERCHANT_SHOW", "x", "y")
        c.advance(2)
        t.eq(got, { true, { "sell", "x", "y", 8 }, { "sell", true } })
        t.eq(k.use("sell"), {}, "a module with no provides gives an empty table")
        t.eq(k.use("nothing"), nil)
    end,

    ["modules: a missing need is reported by name; that module is off, the rest start"] = function(t)
        local k, c = kernel()
        local log = {}
        noisy(k, log, "lonely", { "ghost" })
        noisy(k, log, "fine")
        noisy(k, log, "follower", { "lonely" })
        t.eq(k:Load(), true)
        t.eq(log, { "fine start" })
        t.eq({ k:ModuleState("lonely") }, { "off", "needs ghost, which is missing" })
        t.eq({ k:ModuleState("follower") }, { "off", "needs lonely, which did not start" })
        t.eq(k:ModuleState("fine"), "started")
        t.eq(k.use("lonely"), nil)
        local p = k.problems:list("module")
        t.eq(#p, 2)
        t.eq({ p[1].owner, p[1].text }, { "lonely", "needs ghost, which is missing" })
        t.eq({ p[2].owner, p[2].text }, { "follower", "needs lonely, which did not start" })
        t.eq(c.events(), { "FINE_EVENT" }, "an off module has no events")
        c.fire("LONELY_EVENT")
        c.advance(1)
        t.eq(log, { "fine start", "fine tick" }, "and no ticks")
    end,

    ["modules: a cycle of needs is reported by name; those modules are off, the rest start"] = function(t)
        local k, c = kernel()
        local log = {}
        noisy(k, log, "a", { "b" })
        noisy(k, log, "b", { "c" })
        noisy(k, log, "c", { "a" })
        noisy(k, log, "self", { "self" })
        noisy(k, log, "outside", { "a" })
        noisy(k, log, "fine")
        t.eq(k:Load(), true)
        t.eq(log, { "fine start" })
        local cycle = "needs form a cycle: a -> b -> c -> a"
        t.eq({ k:ModuleState("a") }, { "off", cycle })
        t.eq({ k:ModuleState("b") }, { "off", cycle })
        t.eq({ k:ModuleState("c") }, { "off", cycle })
        t.eq({ k:ModuleState("self") }, { "off", "needs form a cycle: self -> self" })
        t.eq({ k:ModuleState("outside") }, { "off", "needs a, which did not start" })
        t.eq(k:ModuleState("fine"), "started")
        t.eq(k.problems:count("module"), 5)
        t.eq(c.events(), { "FINE_EVENT" })
    end,

    ["modules: a failing start turns that module and its followers off"] = function(t)
        local k, c = kernel()
        local log = {}
        k:Module({
            name = "broken",
            events = { BROKEN_EVENT = function() log[#log + 1] = "broken event" end },
            ticks = { { every = 1, run = function() log[#log + 1] = "broken tick" end } },
            start = function() error("start broke") end,
        })
        noisy(k, log, "follower", { "broken" })
        noisy(k, log, "fine")
        t.eq(k:Load(), true)
        local state, reason = k:ModuleState("broken")
        t.eq(state, "off")
        t.ok(reason:find("start failed", 1, true) and reason:find("start broke", 1, true), reason)
        t.eq({ k:ModuleState("follower") }, { "off", "needs broken, which did not start" })
        t.eq(k:ModuleState("fine"), "started")
        t.eq(k.problems:count("start"), 1)
        t.eq(k.problems:list("start")[1].owner, "broken")
        t.eq(c.events(), { "FINE_EVENT" })
        c.fire("BROKEN_EVENT")
        c.fire("FOLLOWER_EVENT")
        c.advance(1)
        t.eq(log, { "fine start", "fine tick" })
    end,

    ["modules: a bad, duplicate or late module is recorded, not raised"] = function(t)
        local k = kernel()
        t.ok(k:Module({ name = "one" }))
        t.eq(k:Module({ name = "one" }), nil)
        t.eq(k:Module("not a table"), nil)
        t.eq(k:Module({}), nil)
        t.eq(k:Module({ name = "store" }), nil)
        t.eq(k:Module({ name = "x", needs = "one" }), nil)
        t.eq(k:Module({ name = "x", start = "go" }), nil)
        t.eq(k:Module({ name = "x", events = { THING = "fn" } }), nil)
        t.eq(k:Module({ name = "x", ticks = { { run = function() end } } }), nil)
        t.eq(k:Module({ name = "x", ticks = { { every = 1, run = function() end, when = "visible" } } }), nil)
        k:Load()
        t.eq(k:Module({ name = "late" }), nil)
        local p = k.problems:list("module")
        t.eq(#p, 10)
        t.eq({ p[1].owner, p[1].text }, { "one", "duplicate module" })
        t.eq({ p[10].owner, p[10].text }, { "late", "declared after load" })
        t.eq(k:ModuleState("x"), nil)
        t.eq(k:ModuleState("one"), "started")
    end,

    ["guard: decides from the client alone"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(ns.Guard.Decide(c, ns.id), { paused = false })
        c.setLoaded("Flow", true)
        local verdict = ns.Guard.Decide(c, ns.id)
        t.eq(verdict.paused, true)
        t.eq(verdict.panel.text, "Flow is also enabled. Z-Flow is paused.")
        t.eq(#verdict.panel.actions, 2)
        t.eq(verdict.panel.actions[1].id, "import")
        t.eq(verdict.panel.actions[2].id, "disable-flow-and-reload")
        t.eq(type(verdict.panel.actions[1].label), "string")
        t.eq(type(verdict.panel.actions[2].label), "string")
        for key, value in pairs(verdict.panel) do
            t.ok(type(value) == "string" or type(value) == "table", key .. " is plain data")
        end
        c.setLoaded("Flow", false)
        t.eq(ns.Guard.Decide(c, ns.id).paused, false)
        c.setLoaded("FlowExtras", true)
        t.eq(ns.Guard.Decide(c, ns.id).paused, false, "only the predecessor itself pauses")
    end,

    ["guard: the predecessor's saved table also counts as loaded"] = function(t)
        local c = ns.make.fakeClient()
        c.setSaved("FlowDB", {})
        local verdict = ns.Guard.Decide(c, ns.id)
        t.eq(verdict.paused, true)
        t.eq(verdict.panel.text, "Flow is also enabled. Z-Flow is paused.")
    end,

    ["guard: paused, the kernel registers no events and no ticks and starts nothing"] = function(t)
        local k, c = kernel()
        local log = {}
        noisy(k, log, "a")
        noisy(k, log, "b", { "a" })
        k.bus:on("test", "PLAYER_LEVEL_UP", function() log[#log + 1] = "bus" end)
        k.sched:every("test", 1, function() log[#log + 1] = "tick" end)
        k.sched:afterCombat("test", function() log[#log + 1] = "afterCombat" end)
        c.setLoaded("Flow", true)
        t.eq(k:Load(), false)
        t.eq(k.paused, true)
        t.eq(k.phase, "paused")
        t.eq(k.pausePanel.text, "Flow is also enabled. Z-Flow is paused.")
        t.eq({ k.pausePanel.actions[1].id, k.pausePanel.actions[2].id }, { "import", "disable-flow-and-reload" })
        t.eq(c.events(), {}, "no client event is listened to")
        t.eq(c.ticking(), false, "no frame tick")
        c.fire("A_EVENT"); c.fire("PLAYER_LEVEL_UP"); c.fire("PLAYER_LOGIN")
        c.setCombat(true); c.setCombat(false)
        c.advance(5, 5)
        t.eq(log, {}, "nothing ran")
        t.eq(k:ModuleState("a"), "declared")
        t.eq(k.store.opened, false, "saved data is not opened")
        t.eq(c.savedExists("ZFlowDB"), false, "and no saved table is made")
        t.eq(k:Load(), false, "still paused on a second Load")
        t.eq(c.events(), {})
    end,

    ["guard: not paused, paused is false and there is no panel"] = function(t)
        local k = kernel()
        t.eq(k.paused, false)
        k:Load()
        t.eq(k.paused, false)
        t.eq(k.pausePanel, nil)
    end,

    ["boot: the kernel loads at login, and only once"] = function(t)
        local k, c = kernel()
        local log = {}
        noisy(k, log, "a")
        k:Boot()
        t.eq(c.events(), { "PLAYER_LOGIN" }, "before login the only listener is the kernel's own")
        t.eq(k.phase, "declare")
        c.fire("PLAYER_LOGIN")
        t.eq(k.phase, "running")
        t.eq(log, { "a start" })
        t.eq(c.events(), { "A_EVENT" }, "the login listener is dropped")
        c.fire("PLAYER_LOGIN")
        t.eq(log, { "a start" })
    end,

    ["boot: the guard decides at login, whatever loaded first"] = function(t)
        local k, c = kernel()
        local log = {}
        noisy(k, log, "a")
        k:Boot()
        c.setLoaded("Flow", true)
        c.fire("PLAYER_LOGIN")
        t.eq(k.paused, true)
        t.eq(log, {})
        t.eq(c.events(), {}, "paused: even the login listener is gone")
        t.eq(c.ticking(), false)
    end,
}
