-- Tests for where to quest next (ZFlow/Nav/WhereNext.lua; Flow-parity row
-- A2-14): the zones on the player's continent with quests the player can
-- take at their level, counted from the player's own Questie. Data only.
-- Made-up quests, givers, areas and maps, test only. Not tested in game.
local _, ns = ...

local tests = {}

local function X() return ns.Nav.WhereNext end

-- Areas (Questie's numbers) to maps, and the maps' continents and names.
local AREAS = { [12] = 1429, [40] = 1436, [17] = 1413 }
local CONTS = { [1429] = 0, [1436] = 0, [1413] = 1 }
local NAMES = { [1429] = "Near Wood", [1436] = "West Fall", [1413] = "Dry Plain" }
-- A races mask with no bit of race 1 in it (bits 2, 5, 6, 8).
local OTHER_SIDE = 178

-- The quests of the stand-in Questie, for a level 20 player of race 1 and
-- class 1. Counted: 1, 2, 14 (area 12), 5, 8 (area 40), 11 (area 17).
local function quests()
    return {
        [1] = { questLevel = 20, requiredLevel = 18, zoneOrSort = 12 },
        [2] = { questLevel = 23, requiredLevel = 21, zoneOrSort = 12 },
        [3] = { questLevel = 24, requiredLevel = 18, zoneOrSort = 12 },
        [4] = { questLevel = 15, requiredLevel = 10, zoneOrSort = 12 },
        [5] = { questLevel = 16, requiredLevel = 10, zoneOrSort = 40 },
        [6] = { questLevel = 20, requiredRaces = OTHER_SIDE, zoneOrSort = 12 },
        [7] = { questLevel = 20, requiredClasses = 2, zoneOrSort = 12 },
        [8] = { questLevel = 20, requiredClasses = 1, zoneOrSort = -81, startedBy = { { 501 } } },
        [9] = { questLevel = 20, zoneOrSort = 12 },
        [10] = { questLevel = 20, zoneOrSort = 12 },
        [11] = { questLevel = 20, zoneOrSort = 17 },
        [12] = { questLevel = 20, zoneOrSort = 999 },
        [13] = { questLevel = 22, requiredLevel = 22, zoneOrSort = 12 },
        [14] = { questLevel = 20, requiredLevel = 0, zoneOrSort = 12 },
    }
end

local function npcs()
    return { [501] = { spawns = { [40] = { { 50, 50 } }, [77] = { { 10, 10 } } } } }
end

-- A stand-in for Questie's two modules. count.reads: quests asked for
-- their level; count.other: every other quest read.
local function questie(list, givers, count)
    local db = { QuestPointers = {} }
    for id in pairs(list) do db.QuestPointers[id] = true end
    function db.QueryQuestSingle(id, field)
        if count then
            if field == "questLevel" then count.reads = count.reads + 1 else count.other = count.other + 1 end
        end
        return list[id] and list[id][field]
    end
    function db.QueryNPCSingle(id, field)
        return givers and givers[id] and givers[id][field]
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return AREAS[area] end
    return db, zones
end

-- A plain client for the reader. st is read when asked, so a test may
-- change it afterwards.
local function clientOf(st)
    local c = {}
    function c.questieModule(name) return st.questie and st.questie[name] end
    function c.level() return st.level end
    function c.class() return st.class end
    function c.raceId() return st.raceId end
    function c.inCombat() return st.combat == true end
    function c.now() return st.t end
    function c.position()
        if st.map == nil then return nil end
        return { map = st.map, x = 0.5, y = 0.5 }
    end
    function c.mapCont(map) return CONTS[map] end
    function c.mapName(map) return NAMES[map] end
    function c.questLog() return st.log end
    function c.questDone(id)
        if st.done == nil then return nil end
        return st.done[id] == true
    end
    return c
end

local function state(db, zones, over)
    local st = { level = 20, class = "WARRIOR", raceId = 1, map = 1429, t = 100,
        questie = { QuestieDB = db, ZoneDB = zones },
        log = { { id = 9, title = "In The Log", objectives = {} } },
        done = { [10] = true } }
    for k, v in pairs(over or {}) do st[k] = v end
    return st
end

local function settle(reader, client)
    local n = 0
    while reader.work(client) and n < 1000 do n = n + 1 end
    return n
end

local function ctx(over)
    local c = { level = 20, log = {}, me = { raceId = 1, classId = 1 },
        done = function() return false end }
    for k, v in pairs(over or {}) do c[k] = v end
    return c
end

local function q(over)
    local out = { id = 700, level = 20, minLevel = 18 }
    for k, v in pairs(over or {}) do out[k] = v end
    return out
end

-- ------------------------------------------------------------------ pure

tests["where next: the level window is Flow's, 4 under to 3 over"] = function(t)
    local W = X()
    t.eq(W.BELOW, 4)
    t.eq(W.ABOVE, 3)
    t.eq(W.InWindow(20, 18, 20), true)
    t.eq(W.InWindow(16, 10, 20), true)
    t.eq(W.InWindow(23, 10, 20), true)
    t.eq(W.InWindow(15, 10, 20), false)
    t.eq(W.InWindow(24, 10, 20), false)
end

tests["where next: a quest you must be more than one level higher for does not count"] = function(t)
    local W = X()
    t.eq(W.InWindow(22, 21, 20), true)
    t.eq(W.InWindow(22, 22, 20), false)
    t.eq(W.InWindow(20, nil, 20), true)
end

tests["where next: a quest with no level, or with the player's level not known, does not count"] = function(t)
    local W = X()
    t.eq(W.InWindow(0, 0, 20), false)
    t.eq(W.InWindow(-1, 0, 20), false)
    t.eq(W.InWindow(nil, 0, 20), false)
    t.eq(W.InWindow(20, 0, nil), false)
end

tests["where next: another race's, faction's or class's quest is not for you"] = function(t)
    local W = X()
    local me = { raceId = 1, classId = 1 }
    t.eq(W.ForMe({ requiredRaces = OTHER_SIDE }, me), false)
    t.eq(W.ForMe({ requiredClasses = 2 }, me), false)
    t.eq(W.ForMe({ requiredRaces = 1, requiredClasses = 1 }, me), true)
    t.eq(W.ForMe({ requiredRaces = 0, requiredClasses = 0 }, me), true)
    t.eq(W.ForMe({}, me), true)
end

tests["where next: with the race or class not known the mask rules nothing out"] = function(t)
    local W = X()
    t.eq(W.ForMe({ requiredRaces = OTHER_SIDE }, {}), true)
    t.eq(W.ForMe({ requiredClasses = 2 }, {}), true)
end

tests["where next: a quest in the window, for you, not taken and not done is one you can take"] = function(t)
    local W = X()
    local ok, why = W.Takes(q(), ctx())
    t.eq(ok, true)
    t.eq(why, nil)
end

tests["where next: too high or too low is not one you can take"] = function(t)
    local W = X()
    t.eq((W.Takes(q({ level = 24 }), ctx())), false)
    t.eq((W.Takes(q({ level = 15 }), ctx())), false)
    t.eq((W.Takes(q({ level = 22, minLevel = 22 }), ctx())), false)
end

tests["where next: in the log or done is not one you can take"] = function(t)
    local W = X()
    t.eq((W.Takes(q(), ctx({ log = { [700] = true } }))), false)
    t.eq((W.Takes(q(), ctx({ done = function(id) return id == 700 end }))), false)
end

tests["where next: not for your race or class is not one you can take"] = function(t)
    local W = X()
    t.eq((W.Takes(q({ requiredRaces = OTHER_SIDE }), ctx())), false)
    t.eq((W.Takes(q({ requiredClasses = 2 }), ctx())), false)
end

tests["where next: done not known still counts, and says so"] = function(t)
    local W = X()
    local ok, why = W.Takes(q(), ctx({ done = function() return nil end }))
    t.eq(ok, true)
    t.eq(why, W.DONE_UNKNOWN)
    ok, why = W.Takes(q(), ctx({ done = false }))
    t.eq(ok, true)
    t.eq(why, W.DONE_UNKNOWN)
end

tests["where next: an event quest counts only while Questie says its event is on"] = function(t)
    local W = X()
    local mod = { eventQuests = { { "Feast", 700 }, { "Feast", 701 }, { questId = 702 } }, activeQuests = { [701] = true } }
    local ev = W.Events(mod)
    t.eq(W.Offered(700, ev), false)
    t.eq(W.Offered(701, ev), true)
    t.eq(W.Offered(702, ev), false)
    t.eq(W.Offered(703, ev), true)
    t.eq(W.Offered(700, nil), true)
    t.eq(W.Events(nil), nil)
    t.eq((W.Takes(q(), ctx({ events = ev }))), false)
    t.eq((W.Takes(q({ id = 701 }), ctx({ events = ev }))), true)
end

tests["where next: a quest's area is its own, else the lowest area its giver stands in"] = function(t)
    local W = X()
    t.eq(W.AreaOf(12, { [40] = {} }), 12)
    t.eq(W.AreaOf(-81, { [40] = {}, [33] = {} }), 33)
    t.eq(W.AreaOf(0, { [40] = {} }), 40)
    t.eq(W.AreaOf(nil, nil), nil)
    t.eq(W.AreaOf(-81, {}), nil)
end

tests["where next: zones are ranked most quests first, then by map"] = function(t)
    local W = X()
    local list = W.Rank({ [30] = 2, [10] = 5, [20] = 2, [40] = 1 })
    t.eq(list, { { map = 10, count = 5 }, { map = 20, count = 2 }, { map = 30, count = 2 }, { map = 40, count = 1 } })
    t.eq(W.Rank({ [30] = 2, [10] = 5, [40] = 1 }, 2), { { map = 10, count = 5 }, { map = 30, count = 2 } })
    t.eq(W.Rank(nil), {})
end

tests["where next: zones of another continent, or of one not known, are left out"] = function(t)
    local W = X()
    local ranked = { { map = 1429, count = 3 }, { map = 1413, count = 2 }, { map = 5, count = 1 } }
    local list = W.OnCont(ranked, 0, function(map) return CONTS[map] end)
    t.eq(list, { { map = 1429, count = 3 } })
    t.eq(W.OnCont(ranked, 1, function(map) return CONTS[map] end), { { map = 1413, count = 2 } })
    t.eq(W.OnCont(ranked, nil, function(map) return CONTS[map] end), {})
end

-- ------------------------------------------------------------------ scan

local function scanCtx()
    return ctx({ log = { [9] = true }, done = function(id) return id == 10 end })
end

tests["where next: the scan counts each zone's quests you can take"] = function(t)
    local W = X()
    local db, zones = questie(quests(), npcs())
    local pass = W.ScanStart(db, scanCtx())
    t.ok(pass ~= nil, "a pass")
    if not pass then return end
    t.eq(W.ScanStep(pass, zones, nil), true)
    t.eq(pass.counts, { [1429] = 3, [1436] = 2, [1413] = 1 })
    t.eq(pass.seen, 14)
    t.eq(pass.noZone, 1)
    t.eq(pass.doneKnown, true)
end

tests["where next: the scan asks ZoneDB both ways Questie writes its calls"] = function(t)
    local W = X()
    local db = questie(quests(), npcs())
    local zones = {}
    function zones:GetUiMapIdByAreaId(area) return AREAS[area] end
    local pass = W.ScanStart(db, scanCtx())
    t.ok(pass ~= nil, "a pass")
    if not pass then return end
    W.ScanStep(pass, zones, nil)
    t.eq(pass.counts, { [1429] = 3, [1436] = 2, [1413] = 1 })
end

tests["where next: a done answer not known is kept as not known"] = function(t)
    local W = X()
    local db, zones = questie(quests(), npcs())
    local pass = W.ScanStart(db, ctx({ log = { [9] = true }, done = function() return nil end }))
    t.ok(pass ~= nil, "a pass")
    if not pass then return end
    W.ScanStep(pass, zones, nil)
    t.eq(pass.doneKnown, false)
    t.eq(pass.counts[1429], 4)
end

tests["where next: no quest list, no quick read or no level gives no pass"] = function(t)
    local W = X()
    local db = questie(quests(), npcs())
    t.eq(W.ScanStart(nil, scanCtx()), nil)
    t.eq(W.ScanStart({ QueryQuestSingle = db.QueryQuestSingle }, scanCtx()), nil)
    t.eq(W.ScanStart({ QuestPointers = db.QuestPointers }, scanCtx()), nil)
    t.eq(W.ScanStart(db, ctx({ level = false })), nil)
end

tests["where next: most quests cost one read; none costs more than the bound"] = function(t)
    local W = X()
    local count = { reads = 0, other = 0 }
    local list = {}
    for id = 1, 50 do list[id] = { questLevel = 60, zoneOrSort = 12 } end
    local db, zones = questie(list, npcs(), count)
    local pass = W.ScanStart(db, scanCtx())
    t.ok(pass ~= nil, "a pass")
    if not pass then return end
    W.ScanStep(pass, zones, nil)
    t.eq(count.reads, 50)
    t.eq(count.other, 0)
    count.reads, count.other = 0, 0
    db, zones = questie({ [8] = quests()[8] }, npcs(), count)
    pass = W.ScanStart(db, scanCtx())
    W.ScanStep(pass, zones, nil)
    t.eq(count.reads, 1)
    t.ok(count.other <= W.READS - 2, "the other quest reads of one quest: " .. count.other)
end

-- ---------------------------------------------------------------- reader

tests["where next reader: the answer is the zones on your continent, most quests first"] = function(t)
    local W = X()
    local db, zones = questie(quests(), npcs())
    local st = state(db, zones)
    local reader, client = W.Reader(), clientOf(st)
    local list, why = reader.zones(client)
    t.eq(list, nil)
    t.eq(why, W.WHY_READING)
    settle(reader, client)
    local info
    list, why, info = reader.zones(client)
    t.eq(why, nil)
    t.eq(list, { { map = 1429, name = "Near Wood", count = 3 }, { map = 1436, name = "West Fall", count = 2 } })
    t.eq(info, { level = 20, doneKnown = true, logKnown = true, raceKnown = true, classKnown = true, noZone = 1 })
    st.map = 1413
    list = reader.zones(client)
    t.eq(list, { { map = 1413, name = "Dry Plain", count = 1 } })
end

tests["where next reader: no Questie, or the level or continent not known, is nil and a reason"] = function(t)
    local W = X()
    local db, zones = questie(quests(), npcs())
    local st = state(db, zones, { questie = false })
    local reader, client = W.Reader(), clientOf(st)
    local list, why = reader.zones(client)
    t.eq(list, nil)
    t.eq(why, W.WHY_NO_QUESTIE)
    t.eq(reader.work(client), false)
    st.questie = { QuestieDB = db, ZoneDB = zones }
    st.level = nil
    list, why = reader.zones(client)
    t.eq(list, nil)
    t.eq(why, W.WHY_NO_LEVEL)
    t.eq(reader.work(client), false)
    st.level = 20
    st.map = nil
    reader.zones(client)
    settle(reader, client)
    list, why = reader.zones(client)
    t.eq(list, nil)
    t.eq(why, W.WHY_NO_CONT)
    st.map = 5
    list, why = reader.zones(client)
    t.eq(list, nil)
    t.eq(why, W.WHY_NO_CONT)
end

tests["where next reader: asking reads nothing; the pass is a part a call, only once asked for"] = function(t)
    local W = X()
    local step = W.STEP
    t.ok(type(step) == "number" and step >= 1, "STEP says how many quests a call")
    if type(step) ~= "number" or step < 1 then return end
    local list = {}
    for id = 1, step * 2 + 1 do list[id] = { questLevel = 60, zoneOrSort = 12 } end
    list[step * 2 + 1] = { questLevel = 20, zoneOrSort = 12 }
    local count = { reads = 0, other = 0 }
    local db, zones = questie(list, npcs(), count)
    local reader, client = W.Reader(), clientOf(state(db, zones))
    t.eq(reader.work(client), false, "not asked for yet: no work")
    t.eq(count.reads, 0, "and nothing read")
    t.eq(reader.zones(client), nil, "asked: no answer yet")
    t.eq(count.reads + count.other, 0, "asking reads nothing itself")
    local most, calls = 0, 0
    while calls < 20 do
        local was = count.reads
        local more = reader.work(client)
        calls = calls + 1
        if count.reads - was > most then most = count.reads - was end
        if not more then break end
    end
    t.ok(most <= step, "no call went through more than STEP quests: " .. most)
    t.eq(count.reads, step * 2 + 1, "every quest was gone through once")
    t.ok(calls >= 4, "over four calls or more: " .. calls)
    local found = reader.zones(client)
    t.eq(found, { { map = 1429, name = "Near Wood", count = 1 } })
end

tests["where next reader: one pass, and its answer is kept"] = function(t)
    local W = X()
    local count = { reads = 0, other = 0 }
    local db, zones = questie(quests(), npcs(), count)
    local st = state(db, zones)
    local reader, client = W.Reader(), clientOf(st)
    reader.zones(client)
    settle(reader, client)
    local first = reader.zones(client)
    t.eq(count.reads, 14)
    local other = count.other
    for i = 1, 30 do
        st.t = 100 + i * 60
        t.eq(reader.work(client), false, "no more work")
        t.ok(reader.zones(client) == first, "the same answer, kept")
    end
    t.eq(count.reads, 14)
    t.eq(count.other, other)
end

tests["where next reader: nothing is read in combat"] = function(t)
    local W = X()
    local count = { reads = 0, other = 0 }
    local db, zones = questie(quests(), npcs(), count)
    local st = state(db, zones, { combat = true })
    local reader, client = W.Reader(), clientOf(st)
    reader.zones(client)
    t.eq(settle(reader, client), 0)
    t.eq(count.reads, 0)
    st.combat = false
    settle(reader, client)
    t.eq(count.reads, 14)
end

tests["where next reader: a new level is read again, once"] = function(t)
    local W = X()
    local count = { reads = 0, other = 0 }
    local db, zones = questie(quests(), npcs(), count)
    local st = state(db, zones)
    local reader, client = W.Reader(), clientOf(st)
    reader.zones(client)
    settle(reader, client)
    st.level = 21
    local list, why = reader.zones(client)
    t.eq(list, nil)
    t.eq(why, W.WHY_READING)
    settle(reader, client)
    local info
    list, why, info = reader.zones(client)
    t.eq(why, nil)
    t.eq(count.reads, 28)
    t.eq(info and info.level, 21)
    -- At 21 quest 3 (level 24) and quest 13 (from level 22) count too, and
    -- quest 5 (level 16) no longer does.
    t.eq(list, { { map = 1429, name = "Near Wood", count = 5 }, { map = 1436, name = "West Fall", count = 1 } })
end

tests["where next reader: Questie still loading is tried again, no sooner than RETRY, TRIES times in all"] = function(t)
    local W = X()
    local count = { reads = 0, other = 0 }
    local empty = { [1] = {}, [2] = {}, [3] = {} }
    local db, zones = questie(empty, npcs(), count)
    local st = state(db, zones)
    local reader, client = W.Reader(), clientOf(st)
    reader.zones(client)
    settle(reader, client)
    t.eq(count.reads, 3)
    settle(reader, client)
    t.eq(count.reads, 3, "not again at once")
    for i = 1, 40 do
        st.t = 100 + i * (W.RETRY + 1)
        settle(reader, client)
    end
    t.eq(count.reads, 3 * W.TRIES)
    local list, why = reader.zones(client)
    t.eq(list, nil)
    t.eq(why, W.WHY_NO_DATA)
end

tests["where next reader: a later try that finds quests is the answer"] = function(t)
    local W = X()
    local list = { [1] = {}, [14] = {} }
    local db, zones = questie(list, npcs())
    local st = state(db, zones)
    local reader, client = W.Reader(), clientOf(st)
    reader.zones(client)
    settle(reader, client)
    local found, why = reader.zones(client)
    t.eq(found, nil)
    t.eq(why, W.WHY_READING)
    list[1], list[14] = quests()[1], quests()[14]
    st.t = st.t + W.RETRY + 1
    settle(reader, client)
    found = reader.zones(client)
    t.eq(found, { { map = 1429, name = "Near Wood", count = 2 } })
end

tests["where next reader: the log not known is said, and a map with no name has none"] = function(t)
    local W = X()
    local db, zones = questie({ [11] = quests()[11], [9] = quests()[9] }, npcs())
    local st = state(db, zones)
    st.log, st.done, st.class, st.raceId = nil, nil, nil, nil
    local reader, client = W.Reader(), clientOf(st)
    client.mapName = nil
    reader.zones(client)
    settle(reader, client)
    local list, _, info = reader.zones(client)
    t.eq(list, { { map = 1429, count = 1 } })
    t.eq(info, { level = 20, doneKnown = false, logKnown = false, raceKnown = false, classKnown = false, noZone = 0 })
end

-- ---------------------------------------------------------------- module

local function start(list, opts)
    opts = opts or {}
    local count = { reads = 0, other = 0 }
    local db, zones = questie(list, npcs(), count)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setLevel(20)
    c.setClass("WARRIOR")
    c.setRaceId(1)
    c.setPosition(1429, 0.5, 0.5)
    for map, cont in pairs(CONTS) do
        c.setMapCont(map, cont)
        c.setMapName(map, NAMES[map])
    end
    c.setQuestLog({ { id = 9, title = "In The Log", objectives = {} } })
    for id in pairs(list) do c.setQuestDone(id, id == 10) end
    if not opts.noQuestie then
        c.setQuestieModule("QuestieDB", db)
        c.setQuestieModule("ZoneDB", zones)
    end
    local k = ns.Kernel({}, c)
    X().Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, count
end

tests["whereNext module: started; it reads nothing until asked"] = function(t)
    local W = X()
    local k, c, count = start(quests())
    t.eq(W.NAME, "whereNext")
    t.eq((k:ModuleState(W.NAME)), "started")
    c.advance(5, 50)
    t.eq(count.reads, 0)
    t.eq(k.problems:count(), 0)
end

tests["whereNext module: Zones is nil while reading, then the list, read over frames by its own tick"] = function(t)
    local W = X()
    local k, c, count = start(quests())
    local list, why = k.use(W.NAME).Zones()
    t.eq(list, nil)
    t.eq(why, W.WHY_READING)
    t.eq(count.reads, 0)
    c.advance(1, 10)
    local info
    list, why, info = k.use(W.NAME).Zones()
    t.eq(why, nil)
    t.eq(list, { { map = 1429, name = "Near Wood", count = 3 }, { map = 1436, name = "West Fall", count = 2 } })
    t.eq(info and info.doneKnown, true)
    t.eq(count.reads, 14)
    c.advance(5, 50)
    t.eq(count.reads, 14)
    t.eq(k.problems:count(), 0)
end

tests["whereNext module: no frame goes through more than STEP quests"] = function(t)
    local W = X()
    local list = {}
    for id = 1, W.STEP * 2 + 5 do list[id] = { questLevel = 60, zoneOrSort = 12 } end
    local k, c, count = start(list)
    k.use(W.NAME).Zones()
    local most = 0
    for _ = 1, 10 do
        local was = count.reads
        c.advance(0.1, 1)
        if count.reads - was > most then most = count.reads - was end
    end
    t.ok(most >= 1 and most <= W.STEP, "the most quests in one frame: " .. most)
    t.eq(count.reads, W.STEP * 2 + 5)
end

tests["whereNext module: the pass waits for combat to end"] = function(t)
    local W = X()
    local k, c, count = start(quests())
    c.setCombat(true)
    k.use(W.NAME).Zones()
    c.advance(5, 50)
    t.eq(count.reads, 0)
    t.eq((k.use(W.NAME).Zones()), nil)
    c.setCombat(false)
    c.advance(1, 10)
    t.eq(count.reads, 14)
    t.ok(k.use(W.NAME).Zones() ~= nil, "the answer after combat")
end

tests["whereNext module: without Questie the answer is nil and a reason"] = function(t)
    local W = X()
    local k, c, count = start(quests(), { noQuestie = true })
    local list, why = k.use(W.NAME).Zones()
    t.eq(list, nil)
    t.eq(why, W.WHY_NO_QUESTIE)
    c.advance(1, 10)
    t.eq(count.reads, 0)
end

return tests
