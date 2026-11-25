local _, ns = ...
-- Items/CraftProgress.lua (parity row E-57, the data half; lead section
-- 660): how far a run of crafts is and about how long is left. Made-up
-- recipes on a fake client. Offline only: not tested in game.
local tests = {}
local P = ns.CraftProgress

local BANDAGE = 3275

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    local k = ns.Kernel({}, c)
    local api = P.Declare(k)
    local told = 0
    k:Module({ name = "craftProgressWatcher", needs = { "bus" }, start = function(ctx)
        ctx.bus:on("craftProgressWatcher", P.EVENT, function() told = told + 1 end)
    end })
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return c, api, k, function() return told end
end

local function cast(c, id, secs)
    c.setOwnCastSeconds(secs)
    c.fire(P.START, "player", "Cast-1", id)
end

tests["craft progress: seconds left, from one cast's length and how far into it"] = function(t)
    t.eq(P.Left(10, 3, 3, 0), 21)
    t.eq(P.Left(10, 3, 3, 1), 20)
    t.eq(P.Left(10, 3, 3, 99), 18, "never more than one cast into it")
    t.eq(P.Left(10, 10, 3, 0), 0)
    t.eq(P.Left(10, 3, nil, 0), nil, "one cast's length not known: no time")
    t.eq(P.Left(10, 3, 0, 0), nil)
    t.eq(P.Left(nil, 3, 3, 0), nil)
end

tests["craft progress: a span in words"] = function(t)
    t.eq(P.Span(21), "21 s")
    t.eq(P.Span(60), "1 min")
    t.eq(P.Span(90), "1 min 30 s")
    t.eq(P.Span(20.6), "21 s")
    t.eq(P.Span(nil), "0 s")
end

tests["craft progress: the line while making, when made and when stopped"] = function(t)
    local view = { name = "Linen Bandage", done = 3, total = 10, castSecs = 3, castStart = 100 }
    t.eq(P.Text(view, 100), "Making Linen Bandage 3/10 (about 21 s)")
    t.eq(P.Text(view, nil), "Making Linen Bandage 3/10", "no time: no time said")
    view.castSecs = nil
    t.eq(P.Text(view, 100), "Making Linen Bandage 3/10", "a cast's length not known: no time said")
    t.eq(P.Text({ name = "Linen Bandage", done = 10, total = 10, finished = true }, 100), "Made 10 Linen Bandage")
    t.eq(P.Text({ name = "Linen Bandage", done = 3, total = 10, stopped = "interrupted" }, 100),
        "Stopped: Linen Bandage 3/10")
    t.eq(P.Text(nil, 100), "")
end

-- Fails before: there is no module, and Items/CraftQueue.lua has no caller.
tests["craft progress: a run counts each craft the game says succeeded, and says about how long is left"] = function(t)
    local c, api, _, told = start()
    t.eq(api.Current(), nil, "no run")
    t.eq(api.Begin({ { id = BANDAGE, name = "Linen Bandage", count = 10 } }), true)
    t.eq(api.Current().text, "Making Linen Bandage 0/10", "no cast yet: no time said")
    cast(c, BANDAGE, 3)
    t.eq(api.Current().text, "Making Linen Bandage 0/10 (about 30 s)")
    c.advance(1, 1)
    t.eq(api.Current().text, "Making Linen Bandage 0/10 (about 29 s)", "one second into the cast")
    for _ = 1, 3 do c.fire(P.DONE, "player", "Cast-1", BANDAGE) end
    local view = api.Current()
    t.eq(view.done, 3); t.eq(view.total, 10); t.eq(view.made, 3); t.eq(view.all, 10)
    t.eq(view.text, "Making Linen Bandage 3/10 (about 21 s)")
    t.ok(told() >= 5, "each change is told on the bus")
    for _ = 1, 7 do c.fire(P.DONE, "player", "Cast-1", BANDAGE) end
    t.eq(api.Current().finished, true)
    t.eq(api.Current().text, "Made 10 Linen Bandage")
    c.fire(P.DONE, "player", "Cast-1", BANDAGE)
    t.eq(api.Current().done, 10, "a craft after the run is not counted")
end

tests["craft progress: another spell, another unit or no id counts nothing"] = function(t)
    local c, api = start()
    api.Begin({ { id = BANDAGE, name = "Linen Bandage", count = 5 } })
    c.fire(P.DONE, "player", "Cast-1", 133)
    c.fire(P.DONE, "target", "Cast-1", BANDAGE)
    c.fire(P.DONE, "player", "Cast-1", nil)
    t.eq(api.Current().done, 0)
    c.fire(P.BROKEN, "player", "Cast-1", 133)
    t.eq(api.Current().stopped, nil, "another spell interrupted does not stop the run")
end

tests["craft progress: an interrupted craft stops the run, and so does a fight"] = function(t)
    local c, api = start()
    api.Begin({ { id = BANDAGE, name = "Linen Bandage", count = 5 } })
    c.fire(P.DONE, "player", "Cast-1", BANDAGE)
    c.fire(P.BROKEN, "player", "Cast-1", BANDAGE)
    t.eq(api.Current().stopped, "interrupted")
    t.eq(api.Current().text, "Stopped: Linen Bandage 1/5")
    c.fire(P.DONE, "player", "Cast-1", BANDAGE)
    t.eq(api.Current().done, 1, "nothing is counted after the stop")
    api.Begin({ { id = BANDAGE, name = "Linen Bandage", count = 5 } })
    c.fire(P.FIGHT)
    t.eq(api.Current().stopped, "combat")
    t.eq(api.Stop("click"), false, "stopped already")
end

tests["craft progress: one craft is no run, and a new run replaces the old"] = function(t)
    local _, api = start()
    local ok, why = api.Begin({ { id = BANDAGE, name = "Linen Bandage", count = 1 } })
    t.eq(ok, false); t.eq(why, P.TOO_FEW)
    t.eq((api.Begin({})), false)
    t.eq((api.Begin(nil)), false)
    t.eq(api.Current(), nil)
    api.Begin({ { id = BANDAGE, name = "Linen Bandage", count = 5 } })
    api.Begin({ { id = 2657, name = "Copper Bar", count = 3 } })
    t.eq(api.Current().name, "Copper Bar")
    t.eq(api.Current().total, 3)
end

tests["craft progress: a run of two recipes goes on to the second, whose cast length is not known yet"] = function(t)
    local c, api = start()
    api.Begin({ { id = 2657, name = "Copper Bar", count = 2 }, { id = 3304, name = "Tin Bar", count = 2 } })
    cast(c, 2657, 2)
    c.fire(P.DONE, "player", "Cast-1", 2657)
    c.fire(P.DONE, "player", "Cast-1", 2657)
    local view = api.Current()
    t.eq(view.name, "Tin Bar"); t.eq(view.at, 2); t.eq(view.rows, 2)
    t.eq(view.made, 2); t.eq(view.all, 4)
    t.eq(view.text, "Making Tin Bar 0/2", "the first recipe's length is not used for the second")
    c.fire(P.DONE, "player", "Cast-1", 2657)
    t.eq(api.Current().done, 0, "the first recipe's spell no longer counts")
end

tests["craft progress: with no cast length from the client no time is said"] = function(t)
    local c, api = start()
    api.Begin({ { id = BANDAGE, name = "Linen Bandage", count = 4 } })
    cast(c, BANDAGE, nil)
    t.eq(api.Current().text, "Making Linen Bandage 0/4")
    c.ownCastSeconds = nil
    c.fire(P.START, "player", "Cast-2", BANDAGE)
    t.eq(api.Current().text, "Making Linen Bandage 0/4", "a client with no such read")
end

tests["craft progress: the game's own craft call starts a run, where the client tells of it"] = function(t)
    local c, api = start()
    c.craftStarted(BANDAGE, 6, "Linen Bandage")
    t.eq(api.Current().text, "Making Linen Bandage 0/6")
    c.craftStarted(BANDAGE, 1, "Linen Bandage")
    t.eq(api.Current().total, 6, "a single craft starts no run and leaves the last one")
end

tests["craft progress: a client that cannot tell of the craft call still takes Begin"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.onCraftStarted = nil
    local k = ns.Kernel({}, c)
    local api = P.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    t.eq(k.problems:count(), 0)
    t.eq(api.Begin({ { id = BANDAGE, name = "Linen Bandage", count = 2 } }), true)
    t.eq(ns.craftProgress ~= nil, true, "the addon's own is declared")
end

return tests
