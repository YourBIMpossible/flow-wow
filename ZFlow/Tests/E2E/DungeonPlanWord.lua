-- The dungeons word with a name (FLOW-PARITY B-49, lead section 496 item
-- 2), on the whole add-on loaded on a fake client: it plans that dungeon's
-- run from chat by the code of the window's Plan the run button, says the
-- planned stops, and for a name it does not know lists the close matches.
-- Without a name it opens the window as before. Section 236: asked before
-- the quests are read; a dungeon list that raises, then answers.
-- A made-up Questie; no quest data of any add-on. Offline: the reads are
-- the fake client's, not the game's. Not tested in game.
local _, ns = ...
local tests = {}

local MAP = 1436
local DM, KEEP, DEPTHS = 1581, 209, 9001

-- state.badList true makes Questie's dungeon list raise.
local function questie(state)
    local quests = {
        [101] = { Id = 101, name = "Red Silk", level = 18, requiredLevel = 14, zoneOrSort = DM,
            Starts = { NPC = { 501 } } },
        [102] = { Id = 102, name = "Keep Quest", level = 22, requiredLevel = 14, zoneOrSort = KEEP,
            Starts = { NPC = { 501 } } },
        [103] = { Id = 103, name = "Depths Quest", level = 24, requiredLevel = 14, zoneOrSort = DEPTHS,
            Starts = { NPC = { 501 } } },
    }
    local npcs = { [501] = { name = "Gryan", friendlyToFaction = "A", spawns = { [40] = { { 30, 40 } } } } }
    local db = { QuestPointers = { [101] = true, [102] = true, [103] = true } }
    function db.GetQuest(id) return quests[id] end
    function db.GetNPC(id) return npcs[id] end
    function db.QueryQuestSingle(id, field)
        local q = quests[id]
        if not q then return nil end
        if field == "questLevel" then return q.level end
        return q[field]
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [40] = MAP })[area] end
    function zones:GetDungeons()
        if state and state.badList then error("no list (test)") end
        return { [DM] = { "The Deadmines", {}, nil, { { 40, 42.5, 71.8 } } },
                 [KEEP] = { "Test Keep", {}, nil, { { 40, 10, 10 } } },
                 [DEPTHS] = { "Test Keep Depths", {}, nil, { { 40, 20, 20 } } } }
    end
    return db, zones
end

local function boot(state)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setRaceId(1); c.setFaction("Alliance"); c.setLevel(18)
    for id = 101, 103 do c.setQuestDone(id, false) end
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    local db, zones = questie(state)
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog({})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon, addon.problems:count()
end

local function typed(c, rest)
    local from = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = from + 1, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return out
end

-- The word, asked until the quests are read (the first ask starts the read).
local function asked(c, rest)
    typed(c, rest)
    c.advance(3, 30)
    local lines = typed(c, rest)
    c.advance(1, 5)
    return lines
end

local function with(lines, text)
    for _, line in ipairs(lines) do
        if line:find(text, 1, true) then return line end
    end
    return nil
end

local function first(c)
    local a = c.arrows[1]
    return a and a.lines and a.lines[1]
end

-- Red on 9af56aa0: the word with a name opens the window and says nothing.
tests["dungeons word: a name plans that run, as the button does, and says the stops"] = function(t)
    local c, addon, base = boot()
    local lines = asked(c, "dungeons the deadmines")
    t.eq(lines[1], ns.id.title .. ": The Deadmines: " .. ns.Nav.TripRoute.RUN_SAID:format(2))
    t.eq(lines[2], "  1. Pick up: Red Silk - Gryan", "the first stop")
    t.eq(lines[3], "  2. The Deadmines - Dungeon entrance", "then the entrance")
    local line = first(c)
    t.ok(line ~= nil and line:find("Red Silk", 1, true) ~= nil, "the arrow walks it: " .. tostring(line))
    local rec = c.kitWindows().dungeons
    t.ok(rec == nil or rec.shown ~= true, "the window is not opened")
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Red on 9af56aa0: nothing is said.
tests["dungeons word: part of a name is enough when one dungeon has it"] = function(t)
    local c = boot()
    local lines = asked(c, "dungeons deadm")
    t.eq(lines[1], ns.id.title .. ": The Deadmines: " .. ns.Nav.TripRoute.RUN_SAID:format(2))
    local same = asked(c, "dungeons test keep")
    t.ok(with(same, ns.id.title .. ": Test Keep: ") ~= nil, "a whole name wins: " .. tostring(same[1]))
end

-- Red on 9af56aa0: nothing is said.
tests["dungeons word: an unknown name lists the close matches"] = function(t)
    local c, addon, base = boot()
    local W = ns.DungeonWindow
    local lines = asked(c, "dungeons keep")
    t.eq(lines[1], ns.id.title .. ": no dungeon called \"keep\".")
    t.eq(lines[2], "  Close matches: Test Keep, Test Keep Depths")
    local words = asked(c, "dungeons depths of doom")
    t.eq(words[2], "  Close matches: Test Keep Depths", "one of its words is in a name")
    local none = asked(c, "dungeons zzz")
    t.eq(none[1], ns.id.title .. ": no dungeon called \"zzz\".")
    t.eq(none[2], "  " .. tostring(W.SEE_ALL):format(ns.id.slash))
    local trip = addon.use(ns.Nav.TripRoute.NAME)
    -- The route planned by itself (section 562 item 7, on zflow) may be
    -- there; the word plans nothing the player walks.
    t.eq(trip and trip.Step(), nil, "nothing is planned")
    t.eq(addon.problems:count(), base, "no new problem")
end

tests["dungeons word: with no name it opens the window, as before"] = function(t)
    local c = boot()
    local lines = typed(c, "dungeons")
    c.advance(1, 5)
    local rec = c.kitWindows().dungeons
    t.ok(rec ~= nil and rec.shown == true, "the window is open")
    t.eq(#lines, 0, "and nothing is said in chat")
end

-- Section 236: asked before the quests are read; a list that raises, then answers.
tests["dungeons word: asked too early it says the quests are being read, then plans"] = function(t)
    local c, addon, base = boot()
    local early = typed(c, "dungeons deadmines")
    t.eq(early[1], ns.id.title .. ": " .. ns.DungeonRead.WHY_BUILDING[1])
    c.advance(3, 30)
    t.ok(with(typed(c, "dungeons deadmines"), "Pick up: Red Silk") ~= nil, "planned once they are read")
    t.eq(addon.problems:count(), base, "no new problem")
    local state = { badList = true }
    local c2, addon2, base2 = boot(state)
    local bad = typed(c2, "dungeons deadmines")
    t.ok(type(bad[1]) == "string" and with(bad, "Pick up: Red Silk") == nil, "words, and no run: " .. tostring(bad[1]))
    state.badList = false
    t.ok(with(asked(c2, "dungeons deadmines"), "Pick up: Red Silk") ~= nil, "planned once the list answers")
    t.eq(addon2.problems:count(), base2, "no new problem")
end

tests["dungeons word: the name finder, pure"] = function(t)
    local R = ns.DungeonRead
    local st = { byKey = {
        [1] = { key = 1, name = "Alpha Keep", ids = { 1 }, minQ = 10 },
        [2] = { key = 2, name = "Alpha Keep Vault", ids = { 2 }, minQ = 20 },
        [3] = { key = 3, name = "Beta Mine", ids = { 3 }, minQ = 30 },
        [4] = { key = 4, name = "Empty Hall", ids = {}, minQ = 40 },
    } }
    local d = R.Find(st, "  ALPHA keep ")
    t.eq(d and d.key, 1, "a whole name, any case, spaces trimmed")
    d = R.Find(st, "vault")
    t.eq(d and d.key, 2, "the one dungeon that has the text")
    local none, _, close = R.Find(st, "alpha")
    t.eq(none, nil)
    t.eq(#close, 2, "two have it: both are close matches")
    none, _, close = R.Find(st, "empty")
    t.eq(none, nil, "a dungeon with no quest is not listed")
    t.eq(#close, 0)
    none, _, close = R.Find(st, "")
    t.eq(none, nil)
    t.eq(#close, 0)
end

return tests
