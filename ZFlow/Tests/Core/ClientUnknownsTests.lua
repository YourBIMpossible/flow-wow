-- What the client could not tell, kept as unknown instead of a made-up
-- answer: combat, a failed event registration, a frame that was not made, a
-- drag callback that failed, a saved entry of the wrong type, a time that
-- could not be read. No game client is involved.
local _, ns = ...

-- A stand-in for the client's globals. Every frame takes SetScript and
-- answers GetPoint; RegisterEvent refuses the names in `refuse`.
local function gameEnv(refuse)
    local env = { frames = {}, UIParent = {} }
    function env.CreateFrame(kind, name)
        local f = { kind = kind, name = name, scripts = {}, events = {} }
        function f:SetScript(script, fn) self.scripts[script] = fn end
        function f:RegisterEvent(event)
            if refuse and refuse[event] then error("unknown event") end
            self.events[event] = true
        end
        function f:UnregisterEvent(event) self.events[event] = nil end
        function f:GetPoint() return "CENTER", env.UIParent, "CENTER", 10, 20 end
        env.frames[#env.frames + 1] = f
        return f
    end
    return env
end

local function started()
    local c = ns.make.fakeClient()
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, d
end

local function printedHas(c, text)
    for i = 1, #c.printed do
        if c.printed[i]:find(text, 1, true) then return true end
    end
    return false
end

return {
    -- SF2 --------------------------------------------------------------
    ["combat: unknown when neither read works"] = function(t)
        t.eq(ns.make.client({}).inCombat(), nil, "no read at all")
        local c = ns.make.client({
            InCombatLockdown = function() error("no") end,
            UnitAffectingCombat = function() error("no") end,
        })
        t.eq(c.inCombat(), nil, "both reads fail")
    end,

    ["combat: either read that works is an answer"] = function(t)
        t.eq(ns.make.client({ InCombatLockdown = function() return false end }).inCombat(), false)
        t.eq(ns.make.client({ InCombatLockdown = function() return true end }).inCombat(), true)
        local c = ns.make.client({
            InCombatLockdown = function() error("no") end,
            UnitAffectingCombat = function() return true end,
        })
        t.eq(c.inCombat(), true, "the fallback answers")
        c = ns.make.client({ UnitAffectingCombat = function() return nil end })
        t.eq(c.inCombat(), false, "the fallback read worked and said no")
    end,

    ["sched: afterCombat waits while combat is unknown"] = function(t)
        local c = ns.make.fakeClient()
        local k = ns.Kernel({}, c)
        k:Load()
        local combat = nil
        c.inCombat = function() return combat end
        local ran = 0
        k.sched:afterCombat("mod", function() ran = ran + 1 end)
        t.eq(ran, 0, "unknown is treated as in combat")
        k.sched:flushCombat()
        t.eq(ran, 0, "and the queue stays while it is unknown")
        combat = false
        k.sched:flushCombat()
        t.eq(ran, 1, "it runs once the client says out of combat")
    end,

    ["sched: an outOfCombat job is held while combat is unknown"] = function(t)
        local c = ns.make.fakeClient()
        local k = ns.Kernel({}, c)
        k:Load()
        local combat = nil
        c.inCombat = function() return combat end
        local ran = 0
        k.sched:every("mod", 1, function() ran = ran + 1 end, { when = "outOfCombat" })
        c.advance(1.5)
        t.eq(ran, 0, "held")
        combat = false
        c.advance(0.1)
        t.eq(ran, 1, "runs on the first frame the client says out of combat")
    end,

    -- SF5, SF6 ---------------------------------------------------------
    ["listen: an event the client refuses is kept as not registered"] = function(t)
        local c = ns.make.client(gameEnv({ NO_SUCH_EVENT = true, ALSO_NOT = true }))
        c.listen("PLAYER_LOGIN", function() end)
        t.eq(c.listenFaults(), { notRegistered = {}, noEventFrame = false, noTickFrame = false })
        c.listen("NO_SUCH_EVENT", function() end)
        local cancel = c.listen("ALSO_NOT", function() end)
        t.eq(c.listenFaults().notRegistered, { "ALSO_NOT", "NO_SUCH_EVENT" }, "sorted by name")
        t.eq(c.listenFaults().noEventFrame, false)
        cancel()
        t.eq(c.listenFaults().notRegistered, { "NO_SUCH_EVENT" }, "nothing listens to it any more")
    end,

    ["listen: no event frame is recorded, and every event with it"] = function(t)
        local c = ns.make.client({})
        t.eq(c.listenFaults(), { notRegistered = {}, noEventFrame = false, noTickFrame = false },
            "nothing asked for yet")
        c.listen("MERCHANT_SHOW", function() end)
        local f = c.listenFaults()
        t.eq(f.noEventFrame, true)
        t.eq(f.notRegistered, { "MERCHANT_SHOW" })
        t.eq(f.noTickFrame, false, "no frame listener was asked for")
        c.onFrame(function() end)
        t.eq(c.listenFaults().noTickFrame, true)
    end,

    ["listen: the fault list handed out is a copy"] = function(t)
        local c = ns.make.client(gameEnv({ NO_SUCH_EVENT = true }))
        c.listen("NO_SUCH_EVENT", function() end)
        c.listenFaults().notRegistered[1] = "CHANGED"
        t.eq(c.listenFaults().notRegistered, { "NO_SUCH_EVENT" })
    end,

    ["diag: a snapshot lists events not registered and a frame not made"] = function(t)
        local c = ns.make.fakeClient()
        local k = ns.Kernel({}, c)
        local K = ns.Diag.Collect(k, "test").kernel
        t.eq(K.eventsNotRegistered, {})
        t.eq(K.eventFrameNotMade, false)
        t.eq(K.tickFrameNotMade, false)
        c.setEventFault("MERCHANT_SHOW", true)
        c.setEventFault("BANKFRAME_OPENED", true)
        c.setEventFrame(false)
        K = ns.Diag.Collect(k, "test").kernel
        t.eq(K.eventsNotRegistered, { "BANKFRAME_OPENED", "MERCHANT_SHOW" })
        t.eq(K.eventFrameNotMade, true)
    end,

    ["diag: the diag command says which events are not registered"] = function(t)
        local _, c = started()
        c.slashes[ns.id.slash]("diag")
        t.eq(printedHas(c, "not registered"), false, "nothing to say when all registered")
        t.eq(printedHas(c, "event frame"), false)
        c.setEventFault("MERCHANT_SHOW", true)
        c.setEventFrame(false)
        c.slashes[ns.id.slash]("diag")
        t.eq(printedHas(c, "events not registered: MERCHANT_SHOW"), true)
        t.eq(printedHas(c, "event frame not made"), true)
    end,

    -- SF4 --------------------------------------------------------------
    ["panel: a failing moved callback is handed to its caller"] = function(t)
        local env = gameEnv()
        local c = ns.make.client(env)
        local h = c.panel({ name = "TestPanel" })
        local got, calls = nil, 0
        h.onMoved(function() error("boom") end, function(err) got, calls = err, calls + 1 end)
        local ok = pcall(env.frames[#env.frames].scripts.OnDragStop)
        t.eq(ok, true, "the client's drag handler does not error")
        t.eq(calls, 1)
        t.eq(type(got) == "string" and got:find("boom", 1, true) ~= nil, true, "with the error text")
    end,

    ["panel: a moved callback that works reports nothing; no sink is no error"] = function(t)
        local env = gameEnv()
        local c = ns.make.client(env)
        local h = c.panel({ name = "TestPanel" })
        local calls, at = 0, nil
        h.onMoved(function(point) at = point end, function() calls = calls + 1 end)
        env.frames[#env.frames].scripts.OnDragStop()
        t.eq(at, { "CENTER", "CENTER", 10, 20 })
        t.eq(calls, 0)
        h.onMoved(function() error("boom") end)
        t.eq(pcall(env.frames[#env.frames].scripts.OnDragStop), true, "still caught")
    end,

    ["panel: the fake hands a failing moved callback to its caller too"] = function(t)
        local c = ns.make.fakeClient()
        local h = c.panel({})
        local got
        h.onMoved(function() error("boom") end, function(err) got = err end)
        t.eq(pcall(h.drag, { "CENTER", "CENTER", 1, 2 }), true)
        t.eq(type(got) == "string" and got:find("boom", 1, true) ~= nil, true)
    end,

    ["devpanel: a drag that fails is a problem"] = function(t)
        local c = ns.make.fakeClient()
        local k = ns.Kernel({}, c)
        local p = ns.DevPanel.Start(k, nil)
        k:Boot()
        c.fire("ADDON_LOADED", ns.id.addon)
        c.fire("PLAYER_LOGIN")
        c.fire("PLAYER_ENTERING_WORLD")
        c.screen = function() error("screen broke") end
        t.eq(pcall(p.panel.drag, { "CENTER", "CENTER", 30, -40 }), true)
        local list = k.problems:list("devpanel")
        t.eq(#list, 1)
        t.eq(list[1].owner, "drag")
        t.eq(tostring(list[1].text):find("screen broke", 1, true) ~= nil, true)
    end,

    -- SF7 --------------------------------------------------------------
    ["store: a saved entry that is no table is a problem before it is replaced"] = function(t)
        local c = ns.make.fakeClient()
        c.setSaved(ns.id.accountDB, { settings = "oops", layout = 5, learned = { a = 1 } })
        local k = ns.Kernel({}, c)
        t.eq(k.store:open(), true, "the scope still opens")
        local db = c.saved(ns.id.accountDB)
        t.eq(db.settings, {})
        t.eq(db.layout, {})
        t.eq(db.learned, { a = 1 }, "a table is left alone")
        local list = k.problems:list("store")
        t.eq(#list, 2)
        local texts = {}
        for i = 1, #list do
            t.eq(list[i].owner, "account", "names the scope")
            texts[#texts + 1] = list[i].text
        end
        table.sort(texts)
        t.eq(texts[1]:find("layout", 1, true) ~= nil and texts[1]:find("number", 1, true) ~= nil, true,
            "names the key and the type: " .. texts[1])
        t.eq(texts[2]:find("settings", 1, true) ~= nil and texts[2]:find("string", 1, true) ~= nil, true,
            "names the key and the type: " .. texts[2])
    end,

    ["store: an entry that is simply missing is no problem"] = function(t)
        local c = ns.make.fakeClient()
        local k = ns.Kernel({}, c)
        k.store:open()
        t.eq(k.problems:count("store"), 0)
        t.eq(c.saved(ns.id.accountDB).settings, {})
        t.eq(c.saved(ns.id.charDB).state, {})
    end,

    -- SF1 --------------------------------------------------------------
    ["time: uptime is the client's time, or nothing"] = function(t)
        t.eq(ns.make.client({ GetTime = function() return 12.5 end }).uptime(), 12.5)
        t.eq(ns.make.client({}).uptime(), nil, "no made-up 0")
        t.eq(ns.make.client({ GetTime = function() error("no") end }).uptime(), nil)
        t.eq(ns.make.client({ GetTime = function() return "soon" end }).uptime(), nil)
        t.eq(ns.make.client({}).now(), 0, "now() is unchanged: the scheduler's clock")
    end,

    ["time: the fake can be a client that cannot read the time"] = function(t)
        local c = ns.make.fakeClient({ now = 500 })
        t.eq(c.uptime(), 500)
        c.setTime(false)
        t.eq(c.uptime(), nil)
        t.eq(c.now(), 0, "as the real client's now() answers")
        c.setTime(true)
        t.eq(c.uptime(), 500)
    end,

    ["reads: the bank is seen without a time when none can be read"] = function(t)
        local c = ns.make.fakeClient({ now = 500 })
        c.setBank({ { item = 2589, count = 40 } })
        c.setTime(false)
        local read = ns.make.resourceRead(c)
        c.setBankOpen(true)
        local bank, seenAt = read.bank()
        t.eq(bank, { [2589] = 40 })
        t.eq(seenAt, nil, "not 0")
        local snap = ns.Resources.Take(read)
        t.eq(snap.bankKnown, true)
        t.eq(snap.bankSeenAt, nil)
    end,

    ["diag: a snapshot has no time when none can be read"] = function(t)
        local c = ns.make.fakeClient({ now = 500 })
        local k = ns.Kernel({}, c)
        t.eq(ns.Diag.Collect(k, "test").at, 500)
        c.setTime(false)
        t.eq(ns.Diag.Collect(k, "test").at, nil)
    end,

    ["diag: timing marks and error rows have no time when none can be read"] = function(t)
        local c = ns.make.fakeClient({ now = 500 })
        c.setTime(false)
        local k = ns.Kernel({}, c)
        local d = ns.Diag.Start(k)
        k:Boot()
        t.eq(d.timing.fileLoad.at, nil)
        c.fire("PLAYER_LOGIN")
        t.eq(d.timing.PLAYER_LOGIN.at, nil)
        c.raise("something broke")
        t.eq(d.timing.errors[1].at, nil)
        t.eq(d.timing.errors[1].text, "something broke")
    end,

    ["diag: a snapshot carries the wall clock when the client has one"] = function(t)
        local c = ns.make.fakeClient({ now = 500 })
        local k = ns.Kernel({}, c)
        if c.clock == nil then
            t.eq(ns.Diag.Collect(k, "test").clock, nil, "no clock on this client: left out")
        end
        c.clock = function() return 1700000000 end
        t.eq(ns.Diag.Collect(k, "test").clock, 1700000000)
        c.clock = function() return nil end
        t.eq(ns.Diag.Collect(k, "test").clock, nil, "unknown stays unknown")
    end,

    ["diag: two openings of one window still count when the time is unknown"] = function(t)
        local _, c = started()
        c.setTime(false)
        local before = c.saved(ns.id.accountDB).diag.count
        c.fire("MERCHANT_SHOW")
        c.fire("MERCHANT_SHOW")
        t.eq(c.saved(ns.id.accountDB).diag.count, before + 2,
            "without a time the two cannot be called the same opening")
    end,
}
