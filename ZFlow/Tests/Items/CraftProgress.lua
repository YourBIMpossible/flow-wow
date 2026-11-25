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

-- The player's cast as the client.casting read gives it (a CLIENT NEED,
-- the one Rotation/CastEdge.lua names): start and end in milliseconds on
-- the clock client.now() reads. secs nil: the read answers no times.
local function cast(c, id, secs)
    local from = c.now()
    if secs then
        c.casting = function() return from * 1000, (from + secs) * 1000, false end
    else
        c.casting = function() return nil end
    end
    c.fire(P.START, "player", "Cast-1", id)
end

-- The cast is over: the read says nothing is being cast.
local function idle(c) c.casting = function() return nil end end

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
    for _ = 1, 3 do
        c.fire(P.DONE, "player", "Cast-1", BANDAGE)
        cast(c, BANDAGE, 3)
    end
    local view = api.Current()
    t.eq(view.done, 3); t.eq(view.total, 10); t.eq(view.made, 3); t.eq(view.all, 10)
    t.eq(view.text, "Making Linen Bandage 3/10 (about 21 s)")
    t.ok(told() >= 5, "each change is told on the bus")
    for _ = 1, 7 do
        c.fire(P.DONE, "player", "Cast-1", BANDAGE)
        cast(c, BANDAGE, 3)
    end
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
    cast(c, 2657, 2)
    c.fire(P.DONE, "player", "Cast-1", 2657)
    cast(c, 3304, nil)
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
    c.casting = nil
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

-- Zen-3's review of E-57 (lead section 664), as Flow's CB.Stalled
-- (Modules/Crafting/CraftBar.lua:73-78, its watch :170-180): a run that
-- goes quiet is over. Running out of reagents, closing the window or
-- walking away fires no interrupt. Fails before: no P.Stalled, and the run
-- says "Making" for ever.
tests["craft progress: the stall rule, pure"] = function(t)
    local view = { done = 3, total = 10, lastAt = 100 }
    t.eq(P.Stalled(view, 102, false), false, "within the idle time")
    t.eq(P.Stalled(view, 100 + P.IDLE + 0.1, false), true, "nothing made for longer: over")
    t.eq(P.Stalled(view, 200, true), false, "a cast going: not over")
    t.eq(P.Stalled(view, 105, false, 10), false, "its own idle time")
    t.eq(P.Stalled({ done = 10, total = 10, lastAt = 100, finished = true }, 200, false), false, "finished")
    t.eq(P.Stalled({ done = 3, total = 10, lastAt = 100, stopped = "x" }, 200, false), false, "stopped")
    t.eq(P.Stalled({ done = 3, total = 10 }, 200, false), false, "no time kept: not said to be over")
    t.eq(P.Stalled(view, nil, false), false, "no time now")
    t.eq(P.Stalled(nil, 200, false), false)
end

tests["craft progress: a run with nothing cast for a while is over, without any interrupt"] = function(t)
    local c, api = start()
    api.Begin({ { id = BANDAGE, name = "Linen Bandage", count = 10 } })
    cast(c, BANDAGE, 3)
    c.advance(3, 3)
    c.fire(P.DONE, "player", "Cast-1", BANDAGE)
    idle(c)
    c.advance(1, 2)
    t.eq(api.Current().stopped, nil, "a moment between casts")
    c.advance(P.IDLE + 1, 6)
    t.eq(api.Current().stopped, "stalled", "out of reagents, the window closed: over")
    t.eq(api.Current().text, "Stopped: Linen Bandage 1/10")
end

tests["craft progress: a long cast is no stall, while the game says it is casting"] = function(t)
    local c, api = start()
    api.Begin({ { id = BANDAGE, name = "Linen Bandage", count = 3 } })
    cast(c, BANDAGE, 10)
    c.advance(8, 16)
    t.eq(api.Current().stopped, nil)
end

-- The low note: an interrupt whose spell the game does not name is not
-- read as the run's; the stall rule ends the run instead.
tests["craft progress: an interrupt that names no spell ends the run by the stall rule"] = function(t)
    local c, api = start()
    api.Begin({ { id = BANDAGE, name = "Linen Bandage", count = 4 } })
    cast(c, BANDAGE, 3)
    c.fire(P.BROKEN, "player", "Cast-1", nil)
    idle(c)
    t.eq(api.Current().stopped, nil, "not said to be ours")
    c.advance(P.IDLE + 1, 6)
    t.eq(api.Current().stopped, "stalled")
end

tests["craft progress: with no casting read a cast seen starting is waited for until its end"] = function(t)
    local c, api = start()
    api.Begin({ { id = BANDAGE, name = "Linen Bandage", count = 4 } })
    c.casting = nil
    c.fire(P.START, "player", "Cast-1", BANDAGE)
    c.advance(P.IDLE + 1, 6)
    t.eq(api.Current().stopped, nil, "its length not known: the run is not called over")
    c.fire(P.DONE, "player", "Cast-1", BANDAGE)
    c.advance(P.IDLE + 1, 6)
    t.eq(api.Current().stopped, "stalled", "nothing started since: over")
end

-- Zen-3's review: the game's craft call must not replace a run going for
-- the same recipe (one begun through Begin with several rows).
tests["craft progress: the game's craft call for the recipe being made does not replace the run"] = function(t)
    local c, api = start()
    api.Begin({ { id = 2657, name = "Copper Bar", count = 2 }, { id = 3304, name = "Tin Bar", count = 2 } })
    c.craftStarted(2657, 2, "Copper Bar")
    t.eq(api.Current().rows, 2, "still the two-recipe run")
    c.craftStarted(3304, 5, "Tin Bar")
    t.eq(api.Current().rows, 1, "another recipe: a new run")
    t.eq(api.Current().name, "Tin Bar")
    api.Stop("click")
    c.craftStarted(3304, 5, "Tin Bar")
    t.eq(api.Current().stopped, nil, "a stopped run is no run going: the call starts one")
end

return tests
