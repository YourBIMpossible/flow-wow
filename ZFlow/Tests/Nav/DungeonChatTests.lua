local _, ns = ...

-- Tests for ZFlow/Nav/DungeonChat.lua (FLOW-PARITY B-47, B-48, B-56): the
-- chat lines on entering a dungeon, the dungeon word's summary and run
-- timing. Pure parts only. Made-up dungeons and quests.

local tests = {}

local function C() return ns.DungeonChat end

tests["dungeon chat: entry lines name the quests in your log and the ones not in it"] = function(t)
    local lines = C().EnterLines("Test Mines", { "Boars", "Herbs" },
        { { name = "Gold Dust" }, { name = "Lost Ring", from = "Old Ma" } })
    t.eq(lines[1], "Test Mines: 2 of its quests in your log: Boars, Herbs")
    t.eq(lines[2], "Not in your log (2): Gold Dust; Lost Ring (Old Ma)")
    t.eq(lines[3], C().ADVICE)
end

tests["dungeon chat: nothing to say for a dungeon with no quests for you"] = function(t)
    t.eq(C().EnterLines("Test Mines", {}, {}), {})
end

tests["dungeon chat: only the first few missing quests are named, then how many more"] = function(t)
    local missing = {}
    for i = 1, 8 do missing[i] = { name = "Q" .. i } end
    local lines = C().EnterLines("Test Mines", {}, missing, 6)
    t.eq(lines[1], "Test Mines: 0 of its quests in your log")
    t.eq(lines[2], "Not in your log (8): Q1; Q2; Q3; Q4; Q5; Q6; and 2 more")
end

tests["dungeon chat: the pane's log rows are had; pick-up and inside rows are missing"] = function(t)
    local pane = { groups = {
        { id = "log", rows = { { name = "Herbs" }, { name = "Boars" } } },
        { id = "pickup", rows = { { name = "Lost Ring" } } },
        { id = "inside", rows = { { name = "Gold Dust" } } },
        { id = "later", rows = { { name = "Too High" } } },
        { id = "notforyou", rows = { { name = "Other Faction" } } },
    } }
    local have, missing = C().FromPane(pane)
    t.eq(have, { "Boars", "Herbs" })
    t.eq(#missing, 2)
    t.eq(missing[1].name, "Gold Dust")
    t.eq(missing[2].name, "Lost Ring")
    local h2, m2 = C().FromPane(nil)
    t.eq(h2, {}); t.eq(m2, {})
end

tests["dungeon chat: a run's time is a running average of the last ten"] = function(t)
    local rec = C().LearnTime(nil, 30)
    t.eq(rec, { avg = 30, n = 1 })
    rec = C().LearnTime(rec, 40)
    t.eq(rec, { avg = 35, n = 2 })
    t.eq(C().LearnTime(rec, 3), rec, "a peek inside does not count")
    t.eq(C().LearnTime(rec, 300), rec, "a night away does not count")
    local long = { avg = 20, n = 10 }
    t.eq(C().LearnTime(long, 30), { avg = 21, n = 10 }, "never more than ten")
end

tests["dungeon chat: entering starts a visit; a death walk back in keeps it"] = function(t)
    local inn = C().Visit(nil, "Test Mines", 1000)
    t.eq(inn, { key = "Test Mines", t = 1000 })
    inn = C().Visit(inn, nil, 2000)
    t.eq(inn, { key = "Test Mines", t = 1000, left = 2000 })
    inn = C().Visit(inn, "Test Mines", 2300)
    t.eq(inn, { key = "Test Mines", t = 1000 }, "back within ten minutes: the same run")
    inn = C().Visit(C().Visit(inn, nil, 3000), "Other Keep", 3100)
    t.eq(inn, { key = "Other Keep", t = 3100 }, "another dungeon: a new visit")
end

tests["dungeon chat: a run is finished ten minutes after leaving, with its minutes"] = function(t)
    local inn = { key = "Test Mines", t = 1000, left = 3400 }
    local minutes, rest = C().Finish(inn, 3600)
    t.eq(minutes, nil, "not yet: they may walk back in")
    t.eq(rest, inn)
    minutes, rest = C().Finish(inn, 4000)
    t.eq(minutes, 40)
    t.eq(rest, nil)
    t.eq((C().Finish({ key = "Test Mines", t = 1000 }, 9999)), nil, "still inside")
    t.eq((C().Finish(nil, 9999)), nil)
end

tests["dungeon chat: the timing line says the usual run, or that none is timed yet"] = function(t)
    t.eq(C().TimeLine({ avg = 32.4, n = 3 }), "Your runs here: about 32 min (3 timed).")
    t.eq(C().TimeLine(nil), C().NOT_TIMED)
end

tests["dungeon chat: this visit's minutes so far"] = function(t)
    t.eq(C().SoFar({ key = "Test Mines", t = 1000 }, "Test Mines", 1000 + 25 * 60), 25)
    t.eq(C().SoFar({ key = "Test Mines", t = 1000 }, "Other Keep", 5000), nil)
    t.eq(C().SoFar(nil, "Test Mines", 5000), nil)
end

return tests
