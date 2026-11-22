-- The quest reads (S43), over the fake client: the quest log, and the places
-- asked of a fake Questie module written here by hand. No game client and
-- no Questie is involved; nothing here is Questie data. Not seen in game.
local _, ns = ...

local N = ns.Nav
local Q = N.QuestSource

-- Areas the fake zone module knows: 12 is map 1411, 40 is map 1412.
local AREA = { [12] = 1411, [40] = 1412 }

-- A hand-written stand-in for Questie's modules. GetQuest is written with a
-- dot and the rest with a colon, as both are met in Questie.
local function questie(opts)
    opts = opts or {}
    local calls = { n = 0 }
    local quests = {
        [101] = {
            ObjectiveData = {
                { Type = "monster", Id = 9001, Text = "Boars slain" },
                { Type = "item", Id = 7001, Text = "Tusks" },
            },
            Finisher = { NPC = { 9100 } },
        },
        [202] = { ObjectiveData = { { Type = "object", Id = 5001 } }, finishedBy = { { 9100 }, nil } },
        [303] = { ObjectiveData = { { Type = "monster", Id = 9002 } }, Finisher = { GameObject = { 5002 } } },
        [404] = { ObjectiveData = { { Type = "event", Coordinates = { [12] = { { 20, 80 } } } } } },
    }
    local npcs = {
        [9001] = { name = "Young Boar", spawns = { [12] = { { 50, 30 }, { 50, 10 }, { -1, -1 } }, [40] = { { 5, 5 } } } },
        [9002] = { name = "Far Wolf", spawns = { [40] = { { 50, 50 } } } },
        [9003] = { name = "Tusk Boar", spawns = { [12] = { { 55, 50 } } } },
        [9100] = { name = "Marshal Dughan", spawns = { [12] = { { 50, 60 } } } },
    }
    local objects = {
        [5001] = { name = "Old Crate", spawns = { [12] = { { 40, 50 } } } },
        [5002] = { name = "Wanted Board", spawns = { [40] = { { 10, 10 } } } },
    }
    local items = { [7001] = { npcDrops = { 9003 }, objectDrops = { 5001 } } }

    local db = {}
    function db.GetQuest(id)
        calls.n = calls.n + 1
        if opts.fail then error("questie broke") end
        return quests[id]
    end
    function db:GetNPC(id)
        if opts.failNPC then error("questie broke") end
        return npcs[id]
    end
    function db:GetObject(id) return objects[id] end
    function db:GetItem(id) return items[id] end
    local zones = {}
    function zones:GetUiMapIdByAreaId(area) return AREA[area] end

    local mods = { QuestieDB = db, ZoneDB = zones }
    if opts.empty then mods.QuestieDB = {} end
    return function(name) return mods[name] end, calls
end

local function client(log, module)
    local c = ns.make.fakeClient()
    c.setZone(1, 1411)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    if log ~= nil then c.questLog = function() return log end end
    if module ~= nil then c.questieModule = module end
    return c
end

local function boars()
    return { id = 101, title = "Boar Trouble", objectives = {
        { text = "Boars slain: 2/8", done = false },
        { text = "Tusks: 0/5", done = false },
    } }
end
local function crates() return { id = 202, title = "Crates", complete = true, objectives = { { text = "Crate: 1/1", done = true } } } end
local function wolves() return { id = 303, title = "Wolves", objectives = { { text = "Wolves slain: 0/4" } } } end

local T = {}

T["quest read: the log as the client gives it, made plain"] = function(t)
    local c = client({
        { id = 101, title = "Boar Trouble", objectives = { { text = "Boars slain: 2/8" }, { text = "", done = true }, "junk" } },
        { title = "no id" }, { id = 5 }, { id = 6, title = "" }, "junk",
        { id = 202, title = "Crates", complete = true, failed = 1 },
    })
    t.eq(N.QuestLogRows(c), {
        { id = 101, title = "Boar Trouble", complete = false, failed = false, objectives = {
            { text = "Boars slain: 2/8", done = false }, { done = true }, { done = false } } },
        { id = 202, title = "Crates", complete = true, failed = false, objectives = {} },
    })
end

T["quest read: no log read, a failing read, an answer that is no table: nil"] = function(t)
    t.eq(N.QuestLogRows(client()), nil)
    local c = client()
    c.questLog = function() error("no") end
    t.eq(N.QuestLogRows(c), nil)
    c.questLog = function() return "x" end
    t.eq(N.QuestLogRows(c), nil)
    t.eq(N.QuestLogRows(nil), nil)
end

T["quest read: no Questie, or a Questie not loaded yet: no places"] = function(t)
    local rows = { boars() }
    t.eq(N.QuestiePlaces(client(rows), rows, 1411), nil, "the client has no such read")
    t.eq(N.QuestiePlaces(client(rows, function() return nil end), rows, 1411), nil, "no module")
    t.eq(N.QuestiePlaces(client(rows, (questie({ empty = true }))), rows, 1411), nil, "the module is there, empty")
    t.eq(N.QuestiePlaces(client(rows, function() error("no") end), rows, 1411), nil, "the read fails")
end

T["quest read: a creature objective: its points on this map, as shares"] = function(t)
    local rows = { boars() }
    local places = N.QuestiePlaces(client(rows, (questie())), rows, 1411)
    t.eq(places[101].objectives[1], {
        points = { { map = 1411, x = 0.5, y = 0.3 }, { map = 1411, x = 0.5, y = 0.1 } }, elsewhere = false,
    }, "the point at -1, -1 and the one on the other map are left out")
end

T["quest read: an item objective: where what drops it is"] = function(t)
    local rows = { boars() }
    local places = N.QuestiePlaces(client(rows, (questie())), rows, 1411)
    t.eq(places[101].objectives[2].points, { { map = 1411, x = 0.55, y = 0.5 }, { map = 1411, x = 0.4, y = 0.5 } })
end

T["quest read: the turn-in, with who takes it"] = function(t)
    local rows = { boars(), crates() }
    local places = N.QuestiePlaces(client(rows, (questie())), rows, 1411)
    t.eq(places[101].turnIn, { points = { { map = 1411, x = 0.5, y = 0.6 } }, elsewhere = false, name = "Marshal Dughan" })
    t.eq(places[202].turnIn, { points = { { map = 1411, x = 0.5, y = 0.6 } }, elsewhere = false, name = "Marshal Dughan" },
        "the raw finishedBy form")
end

T["quest read: a place on another map only is said to be elsewhere, with no point"] = function(t)
    local rows = { wolves() }
    local places = N.QuestiePlaces(client(rows, (questie())), rows, 1411)
    t.eq(places[303].objectives[1], { points = {}, elsewhere = true })
    t.eq(places[303].turnIn, { points = {}, elsewhere = true, name = "Wanted Board" })
    local there = N.QuestiePlaces(client(rows, (questie())), rows, 1412)
    t.eq(there[303].objectives[1].points, { { map = 1412, x = 0.5, y = 0.5 } })
end

T["quest read: an objective that carries its own place"] = function(t)
    local rows = { { id = 404, title = "Scout", objectives = { { text = "Scout the camp" } } } }
    local places = N.QuestiePlaces(client(rows, (questie())), rows, 1411)
    t.eq(places[404].objectives[1].points, { { map = 1411, x = 0.2, y = 0.8 } })
    t.eq(places[404].turnIn, { points = {}, elsewhere = false }, "no finisher known: nothing is made up")
end

T["quest read: a quest Questie does not know has no entry"] = function(t)
    local rows = { { id = 999, title = "Unknown", objectives = { { text = "x" } } } }
    t.eq(N.QuestiePlaces(client(rows, (questie())), rows, 1411), {})
end

T["quest read: a Questie error is no place, and nothing is thrown"] = function(t)
    local rows = { boars() }
    t.eq(N.QuestiePlaces(client(rows, (questie({ fail = true }))), rows, 1411), {})
    local places = N.QuestiePlaces(client(rows, (questie({ failNPC = true }))), rows, 1411)
    t.eq(places[101].objectives[1], { points = {}, elsewhere = false })
    t.eq(places[101].objectives[2].points, { { map = 1411, x = 0.4, y = 0.5 } }, "the object still answers")
end

T["quest read: no more points are kept than the cap"] = function(t)
    local many = {}
    for i = 1, N.QUEST_POINTS_MAX + 50 do many[i] = { 50, 30 } end
    local db = {}
    function db.GetQuest() return { ObjectiveData = { { Type = "event", Coordinates = { [12] = many } } } } end
    local zones = {}
    function zones:GetUiMapIdByAreaId(area) return AREA[area] end
    local rows = { { id = 1, title = "Many", objectives = { { text = "x" } } } }
    local c = client(rows, function(name) return ({ QuestieDB = db, ZoneDB = zones })[name] end)
    t.eq(#N.QuestiePlaces(c, rows, 1411)[1].objectives[1].points, N.QUEST_POINTS_MAX)
end

T["quest watch: no Questie: the quest in words, location unknown"] = function(t)
    local w = N.QuestWatch(client({ boars() }))
    t.eq(w.step().lines, { "Boar Trouble", "Boars slain: 2/8", Q.UNKNOWN_PLACE })
    t.eq(w.step().place, nil)
end

T["quest watch: a Questie error: location unknown"] = function(t)
    local w = N.QuestWatch(client({ boars() }, (questie({ fail = true }))))
    t.eq(w.step().lines, { "Boar Trouble", "Boars slain: 2/8", Q.UNKNOWN_PLACE })
end

T["quest watch: no quest log read: no step"] = function(t)
    t.eq(N.QuestWatch(client(nil, (questie()))).step(), nil)
    t.eq(N.QuestWatch(client({}, (questie()))).step(), nil, "an empty log")
end

T["quest watch: with Questie, the nearest objective, with the continent of the zone"] = function(t)
    local w = N.QuestWatch(client({ boars(), crates() }, (questie())))
    local step = w.step()
    t.eq(step.label, "Boar Trouble")
    t.eq(step.detail, "Tusks: 0/5", "the boar that drops tusks is 50 yd east; the nearest boar is 100 yd north")
    t.eq(step.place, { cont = 1, map = 1411, x = 0.55, y = 0.5 })
end

T["quest watch: objective before turn-in, then the turn-in"] = function(t)
    local log = { crates(), boars() }
    local c = client(log, (questie()))
    local w = N.QuestWatch(c)
    t.eq(w.step().quest, 101)
    log[2].objectives[1].done, log[2].objectives[2].done = true, true
    t.eq(w.step().quest, 101, "the log is not read again until it is said to have changed")
    w.refresh()
    local step = w.step()
    t.eq(step.quest, 202)
    t.eq(step.turnIn, true)
    t.eq(step.detail, "Turn in: Marshal Dughan")
    t.eq(step.place, { cont = 1, map = 1411, x = 0.5, y = 0.6 })
end

T["quest watch: an objective on another map is words only"] = function(t)
    local c = client({ wolves() }, (questie()))
    local w = N.QuestWatch(c)
    local step = w.step()
    t.eq(step.place, nil)
    t.eq(step.lines, { "Wolves", "Wolves slain: 0/4", Q.ELSEWHERE })
    c.setPosition(1412, 0.5, 0.4)
    t.eq(w.step().place, { cont = 1, map = 1412, x = 0.5, y = 0.5 }, "on that map the places are read again")
end

T["quest watch: Questie is asked once, not on every step"] = function(t)
    local module, calls = questie()
    local w = N.QuestWatch(client({ boars() }, module))
    w.step()
    local n = calls.n
    t.ok(n >= 1, "it was asked")
    for _ = 1, 50 do w.step() end
    t.eq(calls.n, n)
end

T["quest watch: a Questie that is ready later is found without an event"] = function(t)
    local module = questie({ empty = true })
    local ready = questie()
    local now = module
    local w = N.QuestWatch(client({ boars() }, function(name) return now(name) end))
    t.eq(w.step().place, nil)
    now = ready
    local step
    for _ = 1, N.QUEST_RETRY_STEPS + 1 do step = w.step() end
    t.ok(step.place ~= nil, "pointed at once Questie answers")
end

T["quest watch: the player is nowhere known: words only, nothing thrown"] = function(t)
    local c = client({ boars() }, (questie()))
    c.setPosition(nil)
    t.eq(N.QuestWatch(c).step().lines, { "Boar Trouble", "Boars slain: 2/8", Q.UNKNOWN_PLACE })
end

return T
