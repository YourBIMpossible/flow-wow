local _, ns = ...

-- End to end (P-TRIP, S39/S43/S40): the whole add-on on a fake client. The
-- quest route from the quest log and a made-up Questie, listed by the slash
-- word and walked by the quest arrow; spots learned from the player's own
-- play when Questie is not there; the dungeon run planned from the Dungeon
-- Quests window. Made-up quests and places; not tested in game.

local tests = {}

local MAP = 1436

local function questie()
    local quests = {
        [401] = { ObjectiveData = { { Type = "monster", Id = 9101 } } },
        [402] = { ObjectiveData = { { Type = "monster", Id = 9102 } } },
        [403] = { ObjectiveData = {}, Finisher = { NPC = { 9103 } } },
    }
    local npcs = {
        [9101] = { name = "Boar", spawns = { [40] = { { 60, 50 } } } },
        [9102] = { name = "Herb Thing", spawns = { [40] = { { 20, 50 } } } },
        [9103] = { name = "Smith", spawns = { [40] = { { 55, 50 } } } },
    }
    local db = {}
    function db.GetQuest(id) return quests[id] end
    function db.GetNPC(id) return npcs[id] end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [40] = MAP })[area] end
    return db, zones
end

local LOG = {
    { id = 401, title = "Boars", objectives = { { text = "Boars slain: 0/4" } } },
    { id = 402, title = "Herbs", objectives = { { text = "Herbs: 0/5" } } },
    { id = 403, title = "Bandages", complete = true, objectives = { { text = "Linen: 4/4", done = true } } },
}

local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setFaction("Alliance"); c.setLevel(18)
    c.setZone(1, MAP); c.setPosition(MAP, opts.x or 0.5, opts.y or 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    if opts.questie ~= false then
        local db, zones = questie()
        c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    end
    c.setQuestLog(opts.log or LOG)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function said(c, text)
    for _, line in ipairs(c.printed or {}) do
        if tostring(line):find(text, 1, true) then return line end
    end
    return nil
end

local function first(c)
    local a = c.arrows[1]
    return a and a.lines and a.lines[1]
end

tests["trip route: the slash word lists the quest route in order and the arrow walks it"] = function(t)
    local c = boot()
    t.eq(first(c), "Boars", "before a route: the quest arrow's own pick")
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
    local one = said(c, "1. Bandages")
    t.ok(one ~= nil and one:find("Smith", 1, true) ~= nil and one:find("50 yd", 1, true) ~= nil, tostring(one))
    t.ok(said(c, "2. Boars") ~= nil, "Boars second")
    t.ok(said(c, "3. Herbs") ~= nil, "Herbs last")
    t.eq(first(c), "Bandages", "the arrow points at the route's first stop")
    c.slashes[ns.id.slash]("route skip")
    c.advance(1, 5)
    t.eq(first(c), "Boars", "skipped to the next stop")
    c.slashes[ns.id.slash]("route off")
    c.advance(1, 5)
    t.eq(first(c), "Boars", "the quest arrow's own pick again")
end

tests["trip route: a stop whose objective is done drops out by itself"] = function(t)
    local c = boot()
    c.slashes[ns.id.slash]("route")
    c.slashes[ns.id.slash]("route skip")
    c.advance(1, 5)
    t.eq(first(c), "Boars")
    c.setQuestLog({ { id = 401, title = "Boars", objectives = { { text = "Boars slain: 4/4", done = true } } },
                    LOG[2], LOG[3] })
    c.advance(5, 60)
    t.eq(first(c), "Herbs", "the done objective is no longer a stop")
end

tests["trip route: without Questie, a spot learned where the count went up is used"] = function(t)
    local log = { { id = 501, title = "Rats", objectives = { { text = "Rats slain: 0/5" } } } }
    local c, addon = boot({ questie = false, log = log, x = 0.3, y = 0.7 })
    c.setQuestLog({ { id = 501, title = "Rats", objectives = { { text = "Rats slain: 1/5" } } } })
    c.advance(3, 20)
    local book = addon.store:get("account", ns.Nav.QuestSpots.PATH)
    local spot = type(book) == "table" and book[501] and book[501][1] and book[501][1][1]
    t.eq(spot and { spot.map, spot.x, spot.y }, { MAP, 0.3, 0.7 }, "learned where the player stood")
    c.setPosition(MAP, 0.5, 0.5)
    c.advance(1, 5)
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
    local line = said(c, "1. Rats")
    t.ok(line ~= nil and line:find("283 yd", 1, true) ~= nil, tostring(line))
    t.eq(first(c), "Rats")
end

tests["trip route: the setting rows are there"] = function(t)
    local _, addon = boot()
    local route = addon.settings:row(ns.Nav.TripRoute.SETTING)
    local learn = addon.settings:row(ns.Nav.QuestSpots.SETTING)
    t.eq(route and route.group, "travel.route")
    t.eq(learn and learn.group, "travel.route")
    t.eq(route and route.default, true)
    t.eq(learn and learn.default, true)
end

-- Lead section 372: Live checks a turn-in stop on the route again; one no
-- longer ready leaves the route as a held line and comes back when ready.
tests["trip route: a turn-in no longer ready is held with its reason and comes back"] = function(t)
    local c = boot()
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
    t.eq(first(c), "Bandages")
    c.setQuestLog({ LOG[1], LOG[2], { id = 403, title = "Bandages", objectives = { { text = "Linen: 3/4" } } } })
    c.advance(5, 60)
    t.eq(first(c), "Boars", "the held turn-in is not walked")
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
    local T = ns.Nav.TripRoute
    local held = said(c, T.HELD_LINE:format(T.HELD_NOT_COMPLETE))
    t.ok(held ~= nil and held:find("Bandages", 1, true) ~= nil, tostring(held))
    c.setQuestLog(LOG)
    c.advance(5, 60)
    t.eq(first(c), "Bandages", "ready again: back on the route")
end

-- S40: the dungeon run from the Dungeon Quests window.
local DM = 1581

local function dungeonQuestie()
    local quests = {
        [101] = { Id = 101, name = "Red Silk", level = 18, requiredLevel = 14, zoneOrSort = DM,
            Starts = { NPC = { 501 } } },
    }
    local npcs = { [501] = { name = "Gryan", friendlyToFaction = "A", spawns = { [40] = { { 30, 40 } } } } }
    local db = { QuestPointers = { [101] = true } }
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
        return { [DM] = { "The Deadmines", {}, nil, { { 40, 42.5, 71.8 } } } }
    end
    return db, zones
end

local function bootDungeon()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setRaceId(1); c.setFaction("Alliance"); c.setLevel(18)
    c.setQuestDone(101, false)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    local db, zones = dungeonQuestie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog({})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    c.slashes[ns.id.slash]("dungeons")
    c.advance(2, 20)
    return c, addon
end

tests["dungeon run: R.Run gives the givers to pick up from, then the entrance"] = function(t)
    local c = bootDungeon()
    local R = ns.DungeonRead
    local st = R.Start(c)
    while st.state == "building" do R.Step(st, c, R.SLICE) end
    local run, why = R.Run(st, c, DM)
    t.ok(run ~= nil, why and why[1])
    local steps = run and run.steps or {}
    t.eq(#steps, 2)
    t.eq(steps[1] and steps[1].kind, "giver")
    t.ok(steps[1] and steps[1].label:find("Red Silk", 1, true) ~= nil, steps[1] and steps[1].label)
    t.eq(steps[1] and steps[1].detail, "Gryan")
    t.eq(steps[1] and steps[1].place, { map = MAP, x = 0.3, y = 0.4 })
    t.eq(steps[2] and steps[2].kind, "entrance")
    t.eq(steps[2] and steps[2].place, { map = MAP, x = 0.425, y = 0.718 })
    local none, noWhy = R.Run(st, c, 99999)
    t.eq(none, nil)
    t.ok(type(noWhy) == "table" and type(noWhy[1]) == "string", "why lines")
end

tests["dungeon run: Plan the run hands the run to the arrow, which walks it"] = function(t)
    local c = bootDungeon()
    t.eq(c.kitSelect("dungeons", "dungeons", 1), true)
    t.eq(c.kitClick("dungeons", "planRun"), true, "the button is there and live")
    c.advance(1, 5)
    local line = first(c)
    t.ok(line ~= nil and line:find("Red Silk", 1, true) ~= nil, tostring(line))
    c.setPosition(MAP, 0.3, 0.4)
    c.advance(2, 20)
    t.eq(first(c), "The Deadmines", "at the giver: on to the entrance")
end

-- S43 (lead dispatch section 391 item 4): the route step says how many are still needed.
local function paws(text, done)
    return { { id = 401, title = "Paws", objectives = { { text = text, done = done } } } }
end

local function lineWith(c, text)
    local a = c.arrows[1]
    for _, l in ipairs(a and a.lines or {}) do
        if tostring(l):find(text, 1, true) then return l end
    end
    return nil
end

tests["trip route: the step says how many are still needed, live from the quest log"] = function(t)
    local c = boot({ log = paws("Gnoll Paw: 4/8") })
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
    t.ok(said(c, "1. Paws - You still need 4 of Gnoll Paw.") ~= nil, "the route list")
    t.eq(first(c), "Paws")
    t.eq(lineWith(c, "You still need"), "You still need 4 of Gnoll Paw.", "under the arrow")
    c.setQuestLog(paws("Gnoll Paw: 7/8"))
    c.advance(3, 30)
    t.eq(lineWith(c, "You still need"), "You still need 1 Gnoll Paw.", "one left: singular, read again")
    c.setQuestLog(paws("Gnoll Paw: 8/8", true))
    c.advance(3, 30)
    t.eq(lineWith(c, "You still need"), nil, "done: no need line")
end

tests["trip route: an unreadable count says no number at all"] = function(t)
    local c = boot({ log = paws(nil) })
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
    t.eq(first(c), "Paws")
    t.eq(lineWith(c, "need"), nil, "no need line when the count cannot be read")
    for _, line in ipairs(c.printed or {}) do
        t.ok(not tostring(line):find("still need", 1, true), tostring(line))
    end
end

return tests
