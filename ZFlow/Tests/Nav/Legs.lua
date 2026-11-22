-- Tests for ZFlow/Nav/Legs.lua (S34, LEDGER 153): trip timing, the pure
-- part. Ported from legacy Flow 0.35.377 (Modules/Nav/Legs.lua and its
-- tests in Modules/Tests.lua), with Z-Flow's two changes: places are yards
-- on ONE map (not world yards on a continent), and a read the client did
-- not give stays unknown. Research: WoW/from-zen/RESEARCH-S34.md.
-- Every number here is made up by hand. Not tested in game.
-- It only times and remembers: nothing moves or acts for the player.
local _, ns = ...

local N = ns.Nav
local L = N.Legs
local tests = {}

local function near(t, got, want, by, msg)
    t.ok(type(got) == "number" and math.abs(got - want) <= by,
        (msg or "") .. " (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
end

local A, B = { map = 1, x = 0, y = 0 }, { map = 1, x = 300, y = 0 }

-- One look a second later, on foot and out of a fight unless `extra` says so.
local function looker(st, target)
    return function(x, y, extra)
        local s = { map = 1, x = x, y = y, dt = 1, combat = false, taxi = false, mounted = false,
                    dead = false, target = target or B }
        for key, v in pairs(extra or {}) do
            if v == "unknown" then s[key] = nil else s[key] = v end
        end
        return L.Look(st.now, s)
    end
end

local function trip(more)
    local st = { anchor = { map = 1, x = 0, y = 0 }, last = { map = 1, x = 0, y = 0 }, sec = 0, ground = 0 }
    for key, v in pairs(more or {}) do st[key] = v end
    return st
end

tests["legs: the numbers are legacy Flow's"] = function(t)
    t.eq({ L.CELL, L.COARSE, L.ARRIVE, L.MIN_YARDS, L.MIN_SPEED, L.JUMP, L.WANDER },
         { 40, 250, 30, 60, 1.5, 70, 2.5 })
    t.eq({ L.RUN, L.FASTEST, L.SLOWEST, L.COARSE_MIN, L.MAX, L.AGE }, { 7, 0.12, 5, 150, 3000, 30 * 86400 })
end

tests["legs cell: a spot's square as a key"] = function(t)
    t.eq(L.Cell(0, 0), "0:0")
    t.eq(L.Cell(39.9, 40), "0:1")
    t.eq(L.Cell(-1, 81), "-1:2")
    t.eq(L.Cell(610, 10, L.COARSE), "2:0")
end

tests["legs spot: a map place in yards, or nothing"] = function(t)
    t.eq(L.Spot({ map = 1411, x = 0.5, y = 0.25 }, { w = 1000, h = 800 }), { map = 1411, x = 500, y = 200 })
    t.eq(L.Spot({ map = 1411, x = 0.5, y = 0.25 }, nil), nil, "size not known")
    t.eq(L.Spot({ map = 1411, x = 0.5, y = 0.25 }, { w = 0, h = 800 }), nil)
    t.eq(L.Spot({ x = 0.5, y = 0.25 }, { w = 1000, h = 800 }), nil, "no map")
    t.eq(L.Spot({ map = 1411, x = 0 / 0, y = 0.25 }, { w = 1000, h = 800 }), nil)
    t.eq(L.Spot(nil, { w = 1000, h = 800 }), nil)
end

tests["legs look: a trip is timed from one step to the arrival at the next, travelling only"] = function(t)
    local st = { now = {} }
    local look = looker(st)
    t.eq(L.Look(st.now, { map = 1, x = 5, y = 0, dt = 1, taxi = false, target = A }), nil,
        "arriving at a step with no trip before it: nothing learned yet")
    t.eq(st.now.anchor, { map = 1, x = 0, y = 0 }, "but the next trip starts from that step's spot")
    for x = 12, 96, 7 do look(x, 0) end                        -- 13 s running
    for _ = 1, 20 do look(96, 0, { combat = true }) end         -- a fight on the way: not travel
    for _ = 1, 30 do look(96, 0) end                            -- standing still: not travel
    local leg
    for x = 103, 271, 7 do leg = leg or look(x, 0) end          -- 25 s more, arriving within 30 yd
    t.ok(leg ~= nil, "arriving at the next step ends the trip")
    if not leg then return end
    t.eq({ leg.map, leg.ax, leg.ay, leg.bx, leg.by }, { 1, 0, 0, 300, 0 }, "from step to step, not from where you stood")
    near(t, leg.d, 300, 0.001, "its length: the straight line between the two steps")
    t.eq(leg.sec, 38, "its time: the seconds moving, not the fight or the wait")
    t.eq(leg.mode, "foot")
    t.eq(st.now.anchor, { map = 1, x = 300, y = 0 }, "the next trip starts here")
    t.eq(st.now.sec, 0)
end

tests["legs look: a jump no legs or wings explain is no trip"] = function(t)
    local st = { now = trip({ last = { map = 1, x = 10, y = 0 }, sec = 5, ground = 10 }) }
    t.eq(looker(st)(280, 0), nil)
    t.eq(st.now.anchor, nil, "the trip it was part of is dropped")
end

tests["legs look: a flight is a trip, fast and counted whole"] = function(t)
    local st = { now = trip() }
    local look = looker(st)
    t.eq(look(150, 0, { taxi = true }), nil)
    local leg = look(290, 0, { taxi = true })
    t.ok(leg ~= nil, "arrived")
    t.eq({ leg.mode, leg.sec }, { "taxi", 2 })
end

tests["legs look: a long wander teaches nothing, and the step still starts the next trip"] = function(t)
    local st = { now = trip() }
    local look = looker(st)
    for i = 1, 80 do look((i % 2) * 8, 0) end                   -- 640 yd back and forth
    local got
    for x = 8, 272, 8 do got = got or look(x, 0) end
    t.eq(got, nil, "912 yd on the ground for a 300 yd line")
    t.eq(st.now.anchor, { map = 1, x = 300, y = 0 })
end

tests["legs look: dying, or another map, ends the trip unlearned"] = function(t)
    local st = { now = trip() }
    looker(st)(5, 0, { dead = true })
    t.eq(st.now.anchor, nil)
    st.now = trip()
    L.Look(st.now, { map = 2, x = 5, y = 0, dt = 1, taxi = false })
    t.eq(st.now.anchor, nil, "legs are kept per map")
    t.eq(st.now.last, { map = 2, x = 5, y = 0 })
end

tests["legs look: a step on another map is not arrived at"] = function(t)
    local st = { now = trip() }
    local look = looker(st, { map = 2, x = 300, y = 0 })
    local got
    for x = 7, 294, 7 do got = got or look(x, 0) end
    t.eq(got, nil)
    t.eq(st.now.anchor, { map = 1, x = 0, y = 0 }, "the trip goes on")
end

tests["legs look: the flight read not known drops the trip, never 'not flying'"] = function(t)
    local st = { now = trip() }
    local look = looker(st)
    look(7, 0)
    t.eq(look(14, 0, { taxi = "unknown" }), nil)
    t.eq(st.now.anchor, nil, "a flight taken for a run would store a false time")
    t.eq(st.now.last, { map = 1, x = 14, y = 0 }, "where the player is is still followed")
    t.eq(look(290, 0, { taxi = "unknown" }), nil, "and arriving with it unknown starts no trip")
    t.eq(st.now.anchor, nil)
end

tests["legs look: mostly mounted is 'mount'; mounted not known is 'mount' too, never 'foot'"] = function(t)
    local st = { now = trip() }
    local look = looker(st)
    local leg
    for x = 10, 280, 10 do leg = leg or look(x, 0, { mounted = x > 60 }) end
    t.eq(leg.mode, "mount", "21 of 27 looks mounted")
    st.now = trip()
    leg = nil
    for x = 10, 280, 10 do leg = leg or look(x, 0, { mounted = "unknown" }) end
    t.eq(leg.mode, "mount", "a foot time is only one the client said was on foot")
    st.now = trip()
    leg = nil
    for x = 10, 280, 10 do leg = leg or look(x, 0, { mounted = x <= 60 }) end
    t.eq(leg.mode, "foot", "6 of 27 mounted")
end

tests["legs look: no place, no look"] = function(t)
    local st = trip({ sec = 4 })
    t.eq(L.Look(st, nil), nil)
    t.eq(L.Look(st, { map = 1, x = 0 / 0, y = 0, taxi = false }), nil)
    t.eq(L.Look(st, { x = 1, y = 0, taxi = false }), nil)
    t.eq(st.anchor, { map = 1, x = 0, y = 0 }, "nothing changed")
    t.eq(st.sec, 4)
end

tests["legs keep: the quickest time for a trip is kept, with how"] = function(t)
    local store = {}
    local leg = { map = 1, ax = 10, ay = 10, bx = 610, by = 10, sec = 200, d = 600, mode = "foot" }
    local e, best = L.Keep(store, leg, 100)
    t.eq(e, { s = 200, d = 600, n = 1, m = "foot", at = 100, bt = 100, f = 200, ft = 100 })
    t.eq(best, true, "a first trip is the best so far")
    leg.sec = 260
    e, best = L.Keep(store, leg, 200)
    t.eq({ best, e.s, e.n, e.at, e.bt }, { false, 200, 2, 200, 100 }, "a slower one is counted, the quickest stays")
    leg.sec, leg.mode = 150, "mount"
    e, best = L.Keep(store, leg, 300)
    t.eq({ best, e.s, e.m, e.n, e.bt }, { true, 150, "mount", 3, 300 }, "a quicker one replaces it")
    t.eq({ e.f, e.ft }, { 200, 100 }, "the quickest on foot is kept beside it")
    t.eq(L.Count(store), 1)
    t.eq(store[L.Cell(10, 10)][L.Cell(610, 10)], e, "kept under its two squares")
    t.eq({ L.Keep(store, { ax = 1, ay = 1, bx = 5, by = 5, sec = 3, d = 6, mode = "foot" }, 1) }, { nil, false },
        "both ends in one square: not a trip")
    t.eq(L.Count(store), 1)
end

tests["legs keep: seconds to a tenth, yards to a whole"] = function(t)
    local e = L.Keep({}, { ax = 0, ay = 0, bx = 400, by = 0, sec = 12.34, d = 400.4, mode = "taxi" }, 5)
    t.eq({ e.s, e.d, e.m, e.f }, { 12.3, 400, "taxi", nil })
end

tests["legs keep: a best older than 30 days is replaced by the next trip, quicker or not"] = function(t)
    local store = {}
    local leg = { ax = 0, ay = 0, bx = 400, by = 0, sec = 100, d = 400, mode = "foot" }
    L.Keep(store, leg, 1000)
    leg.sec = 130
    local e, best = L.Keep(store, leg, 1000 + L.AGE + 1)
    t.eq({ best, e.s, e.f, e.n }, { true, 130, 130, 2 })
    leg.sec = 140
    e, best = L.Keep(store, leg, 1000 + L.AGE + 2)
    t.eq({ best, e.s }, { false, 130 }, "a fresh best is kept against a slower trip")
end

tests["legs seconds: a character who cannot ride gets only foot or flight times"] = function(t)
    local e = { s = 150, d = 600, n = 3, m = "mount", at = 300, bt = 300, f = 200, ft = 100 }
    t.eq(L.SecondsFor(e), 150)
    t.eq(L.SecondsFor(e, { ride = true }), 150)
    t.eq(L.SecondsFor(e, { ride = false }), 200, "the foot time")
    t.eq(L.SecondsFor({ s = 150, d = 600, m = "mount", bt = 300 }, { ride = false }), nil, "no foot time: not known")
    t.eq(L.SecondsFor({ s = 40, d = 600, m = "taxi", bt = 300 }, { ride = false }), 40, "a flight needs no mount")
    t.eq(L.SecondsFor(e, { now = 300 + L.AGE + 1 }), nil, "a best past its age is left out")
    t.eq(L.SecondsFor(e, { now = 300 + L.AGE }), 150)
    t.eq(L.SecondsFor(nil), nil)
end

tests["legs yards: seconds at a run, for this length, within limits"] = function(t)
    near(t, L.YardsOf({ s = 150, d = 600 }, 580), 150 * L.RUN * (580 / 600), 0.001)
    near(t, L.YardsOf({ s = 1, d = 1000 }, 1000), 1000 * L.FASTEST, 0.001, "never less than a small share of the line")
    near(t, L.YardsOf({ s = 9000, d = 100 }, 100), 100 * L.SLOWEST, 0.001, "never more than a few times it")
    near(t, L.YardsOf({ s = 100, d = 100 }, 300), 100 * L.RUN * 1.4, 0.001, "the length's share is held to 1.4")
    t.eq(L.YardsOf({ s = 100, d = 0 }, 300), nil)
    t.eq(L.YardsOf({ s = 100, d = 100 }, 0), nil)
    t.eq(L.YardsOf(nil, 300), nil)
end

tests["legs lookup: a trip made, either way; then its neighbourhood; else nothing"] = function(t)
    local store, coarse = {}, {}
    local leg = { map = 1, ax = 10, ay = 10, bx = 610, by = 10, sec = 150, d = 600, mode = "mount" }
    local e = L.Keep(store, leg, 100)
    local a, b = { x = 20, y = 20 }, { x = 600, y = 30 }
    local yards, how = L.Lookup(store, coarse, a, b, 580)
    t.eq(how, "exact", "the same two squares: a trip you made")
    near(t, yards, 150 * L.RUN * (580 / 600), 0.001)
    t.eq(select(2, L.Lookup(store, coarse, b, a, 580)), "exact", "and the way back counts the same")
    t.eq({ L.Lookup(store, coarse, { x = 2000, y = 2000 }, { x = 2600, y = 2000 }, 600) }, {}, "never been there")
    t.eq({ L.Lookup(store, coarse, a, b, 20) }, {}, "a few steps: not asked")
    t.eq({ L.Lookup(nil, coarse, a, b, 580) }, {})

    local ratio = L.Ratio(coarse, e, leg.ax, leg.ay, leg.bx, leg.by)
    near(t, ratio, 150 * L.RUN / 600, 0.0001, "how much longer than the straight line it took")
    yards, how = L.Lookup(store, coarse, { x = 100, y = 100 }, { x = 700, y = 120 }, 600)
    t.eq(how, "area", "a trip between the same two neighbourhoods")
    near(t, yards, 600 * ratio, 0.001)
    yards, how = L.Lookup(store, coarse, { x = 700, y = 120 }, { x = 100, y = 100 }, 600)
    t.eq(how, "area", "either way")
    t.eq({ L.Lookup(store, coarse, { x = 100, y = 100 }, { x = 700, y = 120 }, 120) }, {}, "too short for an area")
end

tests["legs lookup: a flight is not the way back, and cannot ride means foot times"] = function(t)
    local store = {}
    L.Keep(store, { ax = 10, ay = 10, bx = 610, by = 10, sec = 30, d = 600, mode = "taxi" }, 100)
    local a, b = { x = 20, y = 20 }, { x = 600, y = 30 }
    t.eq(select(2, L.Lookup(store, {}, a, b, 580)), "exact")
    t.eq({ L.Lookup(store, {}, b, a, 580) }, {}, "a flight goes one way")

    local rode = {}
    L.Keep(rode, { ax = 10, ay = 10, bx = 610, by = 10, sec = 90, d = 600, mode = "mount" }, 100)
    t.eq({ L.Lookup(rode, {}, a, b, 580, { ride = false }) }, {}, "only ridden: not known for this character")
    near(t, (L.Lookup(rode, {}, a, b, 580, { ride = true })), 90 * L.RUN * (580 / 600), 0.001)
end

tests["legs ratio: the best seen between two neighbourhoods, both ways; a flight says nothing"] = function(t)
    local coarse = {}
    t.eq(L.Ratio(coarse, { s = 10, d = 600, m = "taxi" }, 0, 0, 600, 0), nil, "a flight is not the ground between")
    t.eq(L.Ratio(coarse, { s = 10, d = 100, m = "foot" }, 0, 0, 600, 0), nil, "under 150 yd: too short to say")
    t.eq(L.Ratio(coarse, { s = 100, d = 200, m = "foot" }, 0, 0, 200, 0), nil, "one neighbourhood")
    t.eq(next(coarse), nil)
    near(t, L.Ratio(coarse, { s = 200, d = 600, m = "foot" }, 0, 0, 600, 0), 200 * 7 / 600, 0.0001)
    near(t, L.Ratio(coarse, { s = 120, d = 600, m = "mount" }, 600, 0, 0, 0), 1.4, 0.0001)
    near(t, coarse["0:0"]["2:0"], 1.4, 0.0001, "the best is kept")
    near(t, coarse["2:0"]["0:0"], 1.4, 0.0001, "both ways")
    L.Ratio(coarse, { s = 300, d = 600, m = "foot" }, 0, 0, 600, 0)
    near(t, coarse["0:0"]["2:0"], 1.4, 0.0001, "a worse one changes nothing")
end

tests["legs coarse: the neighbourhoods are rebuilt from the legs kept"] = function(t)
    local store = {}
    L.Keep(store, { ax = 10, ay = 10, bx = 610, by = 10, sec = 150, d = 600, mode = "mount" }, 100)
    L.Keep(store, { ax = 10, ay = 10, bx = 90, by = 10, sec = 20, d = 80, mode = "foot" }, 100)
    local coarse = L.Coarse(store)
    near(t, coarse["0:0"]["2:0"], 1.75, 0.0001)
    near(t, coarse["2:0"]["0:0"], 1.75, 0.0001)
    t.eq(coarse["0:0"]["0:0"], nil, "the short one adds nothing")
    t.eq(L.Coarse(nil), {})
    t.eq(L.Coarse({ bad = { key = { s = 1, d = 600, m = "foot" } } }), {}, "a key that is no square is skipped")
end

tests["legs prune: over the limit, the ones used longest ago go"] = function(t)
    local big = {}
    for i = 1, 10 do
        L.Keep(big, { ax = i * 100, ay = 0, bx = i * 100, by = 500, sec = 60, d = 500, mode = "foot" }, i)
    end
    t.eq(L.Count(big), 10)
    t.eq(L.Prune(big, 10), 0, "at the limit: nothing goes")
    t.eq(L.Prune(big, 6), 4)
    t.eq(L.Count(big), 6)
    t.ok(big[L.Cell(1000, 0)] ~= nil, "the newest kept")
    t.eq(big[L.Cell(100, 0)], nil, "the oldest gone, and its empty row with it")
    t.eq(L.Count(nil), 0)
    t.eq(L.Prune(nil, 5), 0)
end

tests["legs: look only - it times and remembers, nothing moves or acts for you"] = function(t)
    for name in pairs(L) do
        local n = tostring(name):lower()
        t.ok(not (n:find("move") or n:find("click") or n:find("cast") or n:find("use") or n:find("fly")),
            "no acting function: " .. n)
    end
end

return tests
