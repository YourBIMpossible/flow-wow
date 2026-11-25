local _, ns = ...
-- Parity row R-05 (lead section 777): a running average of your time in
-- each dungeon, as Flow's Modules/Nav/Dungeons.lua: D.LearnTime (:398-406:
-- the last 10 runs, runs under 5 or over 240 minutes left out) and the run
-- itself (:2028-2037: from going in to coming out, counted once you have
-- been out 10 minutes). An old saved time stays readable: a plain number
-- (one run) or Flow's { avg, n } (Import/FromFlow.lua puts Flow's times
-- at learned.facts.dungeonTimes). Made-up dungeons. Not tested in game.
-- Fails before: no such file.
local tests = {}

local function DT() return ns.Nav and ns.Nav.DungeonTime end

tests["dungeon time: a running average of the last ten runs, as Flow's"] = function(t)
    t.eq(type(DT()), "table", "loaded")
    if type(DT()) ~= "table" then return end
    t.eq(DT().LearnTime(nil, 30), { avg = 30, n = 1 })
    t.eq(DT().LearnTime({ avg = 30, n = 1 }, 40), { avg = 35, n = 2 })
    t.eq(DT().LearnTime({ avg = 30, n = 10 }, 40), { avg = 31, n = 10 }, "ten at most: the new run weighs a tenth")
    t.eq(DT().LearnTime({ avg = 30, n = 2 }, 4), { avg = 30, n = 2 }, "a peek inside does not count")
    t.eq(DT().LearnTime({ avg = 30, n = 2 }, 241), { avg = 30, n = 2 }, "a night away does not count")
    t.eq(DT().LearnTime(nil, nil), nil)
end

tests["dungeon time: an old saved time is read either way"] = function(t)
    if type(DT()) ~= "table" then return t.ok(false, "not loaded") end
    t.eq(DT().Read(25), { avg = 25, n = 1 }, "a plain number: one run")
    t.eq(DT().Read({ avg = 33, n = 4 }), { avg = 33, n = 4 }, "Flow's shape")
    t.eq(DT().Read({ avg = 33 }), { avg = 33, n = 1 })
    t.eq(DT().Read("x"), nil)
    t.eq(DT().Read(nil), nil)
    t.eq(DT().Line({ avg = 32.6, n = 3 }), DT().ABOUT:format(33))
    t.eq(DT().Line(nil), nil)
end

tests["dungeon time: a run is from going in to coming out, counted after ten minutes out"] = function(t)
    if type(DT()) ~= "table" then return t.ok(false, "not loaded") end
    local st, done = DT().Step(nil, true, "Deadmines", 1000)
    t.eq({ st.key, st.t, st.left, done }, { "Deadmines", 1000, nil, nil }, "in")
    st, done = DT().Step(st, false, nil, 1000 + 40 * 60)
    t.eq({ st.left, done }, { 1000 + 40 * 60, nil }, "out: not counted yet")
    st, done = DT().Step(st, true, "Deadmines", 1000 + 45 * 60)
    t.eq({ st.left, done }, { nil, nil }, "back in within ten minutes: the same run")
    st, done = DT().Step(st, false, nil, 1000 + 50 * 60)
    st, done = DT().Step(st, false, nil, 1000 + 59 * 60)
    t.eq(done, nil, "nine minutes out")
    st, done = DT().Step(st, false, nil, 1000 + 61 * 60)
    t.eq(done, { key = "Deadmines", minutes = 50 }, "ten out: counted, in to out")
    t.eq(st, {}, "and the visit is over")
    local s2 = DT().Step(nil, true, "Wailing Caverns", 0)
    s2 = DT().Step(s2, false, nil, 20 * 60)
    local s3, d3 = DT().Step(s2, true, "Deadmines", 25 * 60)
    t.eq(d3, { key = "Wailing Caverns", minutes = 20 }, "another dungeon: the last run counts")
    t.eq(s3.key, "Deadmines")
    t.eq({ DT().Step(nil, false, nil, 5) }, { {} }, "outside, no visit: nothing")
end

tests["dungeon time module: kept per character, learned on leaving, and read"] = function(t)
    if type(DT()) ~= "table" then return t.ok(false, "not loaded") end
    local c = ns.make.fakeClient()
    local k = ns.Kernel({}, c)
    local api = DT().Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.setClock(1000)
    c.setInstance({ inside = true, kind = "party" }); c.setInstanceName("Deadmines")
    c.fire("PLAYER_ENTERING_WORLD")
    c.setClock(1000 + 30 * 60)
    c.setInstance({ inside = false, kind = "none" }); c.setInstanceName("Eastern Kingdoms")
    c.fire("PLAYER_ENTERING_WORLD")
    c.setClock(1000 + 41 * 60)
    c.advance(DT().EVERY + 1, 2)
    t.eq(api.Time("Deadmines"), { avg = 30, n = 1 })
    t.eq(api.Line("Deadmines"), DT().ABOUT:format(30))
    k.store:set("char", DT().PATH, { Gnomeregan = 45 })
    t.eq(api.Time("Gnomeregan"), { avg = 45, n = 1 }, "an old plain time")
    k.store:set("char", DT().FLOW_PATH, { [133] = { avg = 70, n = 5 } })
    t.eq(api.Time("Nowhere", 133), { avg = 70, n = 5 }, "Flow's imported time, by its dungeon key")
end

return tests
