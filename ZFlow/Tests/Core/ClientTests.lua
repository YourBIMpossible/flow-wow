-- Identity, the real client boundary over a hand-built environment, and the
-- fake client. No game client is involved: `env` stands in for its globals.
local _, ns = ...

-- A stand-in for the client's globals with one kind of frame.
local function gameEnv()
    local env = { frames = {}, clock = 12.5, printed = {} }
    function env.CreateFrame(kind)
        local f = { kind = kind, scripts = {}, events = {} }
        function f:SetScript(name, fn) self.scripts[name] = fn end
        function f:RegisterEvent(event)
            if event == "NO_SUCH_EVENT" then error("unknown event") end
            self.events[event] = true
        end
        function f:UnregisterEvent(event) self.events[event] = nil end
        env.frames[#env.frames + 1] = f
        return f
    end
    function env.GetTime() return env.clock end
    function env.print(text) env.printed[#env.printed + 1] = text end
    return env
end

return {
    ["identity: every identity string is in ns.id"] = function(t)
        local id = ns.id
        t.eq(id.addon, "ZFlow")
        t.eq(id.title, "Z-Flow")
        t.eq(id.framePrefix, "ZFlow")
        t.eq(id.slash, "/zflow")
        t.eq(id.commPrefix, "ZFlow")
        t.eq(id.bindingHeader, "ZFLOW")
        t.eq(id.accountDB, "ZFlowDB")
        t.eq(id.charDB, "ZFlowCharDB")
        t.eq(id.predecessor, "Flow")
    end,

    ["offline: the shared kernel sits on the fake client and loaded clean"] = function(t)
        t.eq(type(ns.client.advance), "function", "ns.client is the fake")
        t.eq(ns.problems:count(), 0, "no problem recorded while the manifest loaded")
        t.eq(type(ns.Setting), "function")
        t.eq(type(ns.Module), "function")
        t.eq(type(ns.use), "function")
    end,

    ["client: an environment with nothing in it never errors"] = function(t)
        local c = ns.make.client({})
        t.eq(c.now(), 0)
        t.eq(c.clockMs(), 0)
        t.eq(c.addonLoaded("Anything"), false)
        t.eq(c.inCombat(), false)
        c.print("hello")
        local ran = false
        local cancel = c.listen("PLAYER_LOGIN", function() ran = true end)
        local cancelFrame = c.onFrame(function() ran = true end)
        cancel()
        cancelFrame()
        t.eq(ran, false)
    end,

    ["client: time, the fine clock and print"] = function(t)
        local env = gameEnv()
        local c = ns.make.client(env)
        t.eq(c.now(), 12.5)
        t.eq(c.clockMs(), 12500, "falls back to GetTime in milliseconds")
        env.debugprofilestop = function() return 77 end
        t.eq(c.clockMs(), 77)
        c.print(5)
        t.eq(env.printed, { "5" })
    end,

    ["client: listen registers the event once and cancel drops it"] = function(t)
        local env = gameEnv()
        local c = ns.make.client(env)
        t.eq(#env.frames, 0, "no frame until something listens")
        local got = {}
        local stopA = c.listen("BAG_UPDATE", function(...) got[#got + 1] = { "a", ... } end)
        local stopB = c.listen("BAG_UPDATE", function(...) got[#got + 1] = { "b", ... } end)
        t.eq(#env.frames, 1)
        local f = env.frames[1]
        t.eq(f.events, { BAG_UPDATE = true })
        f.scripts.OnEvent(f, "BAG_UPDATE", 3)
        t.eq(got, { { "a", 3 }, { "b", 3 } })
        stopA()
        t.eq(f.events, { BAG_UPDATE = true }, "still one listener")
        stopB()
        t.eq(f.events, {}, "unregistered with the last listener")
        stopB()
        f.scripts.OnEvent(f, "BAG_UPDATE", 4)
        t.eq(#got, 2, "nothing runs after cancel")
    end,

    ["client: an event name the client refuses does not error"] = function(t)
        local env = gameEnv()
        local c = ns.make.client(env)
        local cancel = c.listen("NO_SUCH_EVENT", function() end)
        t.eq(env.frames[1].events, {})
        cancel()
        t.ok(true, "listen and cancel both returned")
    end,

    ["client: the frame tick runs only while something is subscribed"] = function(t)
        local env = gameEnv()
        local c = ns.make.client(env)
        local seen = {}
        local stop = c.onFrame(function(elapsed) seen[#seen + 1] = elapsed end)
        local f = env.frames[1]
        t.eq(type(f.scripts.OnUpdate), "function")
        f.scripts.OnUpdate(f, 0.02)
        t.eq(seen, { 0.02 })
        stop()
        t.eq(f.scripts.OnUpdate, nil, "OnUpdate cleared")
    end,

    ["client: addon loaded, by either form of the query"] = function(t)
        local env = gameEnv()
        local c = ns.make.client(env)
        env.IsAddOnLoaded = function(name) return name == "Old" end
        t.eq(c.addonLoaded("Old"), true)
        t.eq(c.addonLoaded("Other"), false)
        env.C_AddOns = { IsAddOnLoaded = function(name) return name == "New" end }
        t.eq(c.addonLoaded("New"), true)
        t.eq(c.addonLoaded("Old"), false, "the namespaced call wins when present")
        env.C_AddOns = { IsAddOnLoaded = function() error("boom") end }
        t.eq(c.addonLoaded("New"), false, "a failing query is false, not an error")
    end,

    ["client: combat state"] = function(t)
        local env = gameEnv()
        local c = ns.make.client(env)
        env.UnitAffectingCombat = function(unit) return unit == "player" end
        t.eq(c.inCombat(), true, "falls back to UnitAffectingCombat")
        env.InCombatLockdown = function() return false end
        t.eq(c.inCombat(), false, "InCombatLockdown wins when present")
    end,

    ["client: saved tables"] = function(t)
        local env = gameEnv()
        local c = ns.make.client(env)
        t.eq(c.savedExists("SomeDB"), false)
        t.eq(env.SomeDB, nil, "asking creates nothing")
        local db = c.saved("SomeDB")
        t.ok(db == env.SomeDB, "created in the environment")
        t.eq(c.savedExists("SomeDB"), true)
        local loaded = { a = 1 }
        env.SomeDB = loaded
        t.ok(c.saved("SomeDB") == loaded, "the client's replacement is seen")
    end,

    ["fake client: the clock moves only when told"] = function(t)
        local c = ns.make.fakeClient({ now = 50 })
        t.eq(c.now(), 50)
        local frames = {}
        local stop = c.onFrame(function(elapsed) frames[#frames + 1] = { c.now(), elapsed } end)
        t.eq(c.ticking(), true)
        c.advance(1, 2)
        t.eq(frames, { { 50.5, 0.5 }, { 51, 0.5 } })
        stop()
        t.eq(c.ticking(), false)
        c.advance(1)
        t.eq(#frames, 2)
        t.eq(c.now(), 52)
        t.eq(c.clockMs(), 0)
        c.burn(4)
        t.eq(c.clockMs(), 4)
    end,

    ["fake client: events, combat, loaded addons, saved tables, print"] = function(t)
        local c = ns.make.fakeClient()
        local log = {}
        local stop = c.listen("SOME_EVENT", function(a, b) log[#log + 1] = { a, b } end)
        c.listen("PLAYER_REGEN_DISABLED", function() log[#log + 1] = "in" end)
        c.listen("PLAYER_REGEN_ENABLED", function() log[#log + 1] = "out" end)
        t.eq(c.events(), { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "SOME_EVENT" })
        c.fire("SOME_EVENT", 1, 2)
        stop()
        c.fire("SOME_EVENT", 3, 4)
        t.eq(c.inCombat(), false)
        c.setCombat(true)
        c.setCombat(true)
        t.eq(c.inCombat(), true)
        c.setCombat(false)
        t.eq(log, { { 1, 2 }, "in", "out" })
        t.eq(c.events(), { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" })

        t.eq(c.addonLoaded("Flow"), false)
        c.setLoaded("Flow", true)
        t.eq(c.addonLoaded("Flow"), true)

        t.eq(c.savedExists("XDB"), false)
        local given = { n = 1 }
        c.setSaved("XDB", given)
        t.ok(c.saved("XDB") == given)
        c.print("line")
        t.eq(c.printed, { "line" })
    end,
}
