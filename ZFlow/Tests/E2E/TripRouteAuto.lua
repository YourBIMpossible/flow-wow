local _, ns = ...
-- The route on the map with no command (owner's report, lead section 562
-- item 7: "There's no route on the map."). As in Flow, the quest route is
-- planned by itself from the quest log and planned again when a step
-- changes; it is there again after a restart with no word. It is shown on
-- the world map and in the Router; the arrow keeps its own pick until the
-- player plans with the route word. Off with the Router's setting
-- (nav.routePanel) or the routes' setting. Whole add-on on a fake client;
-- made-up quests and places. Not tested in game.
-- Red on aa3dd5a8: with no word there is no route (View() is nil) and the
-- map gets no route lines.
local tests = {}

local MAP = 1436

local function questie()
    local quests = {
        [401] = { ObjectiveData = { { Type = "monster", Id = 9101 } } },
        [402] = { ObjectiveData = { { Type = "monster", Id = 9102 } } },
        [403] = { ObjectiveData = {}, Finisher = { NPC = { 9103 } } },
        [404] = { ObjectiveData = { { Type = "monster", Id = 9104 } } },
    }
    local npcs = {
        [9101] = { name = "Boar", spawns = { [40] = { { 60, 50 } } } },
        [9102] = { name = "Herb Thing", spawns = { [40] = { { 20, 50 } } } },
        [9103] = { name = "Smith", spawns = { [40] = { { 55, 50 } } } },
        [9104] = { name = "Wolf", spawns = { [40] = { { 40, 40 } } } },
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

-- opts: questie (false: none), account, char (saved ahead)
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {}); c.setSaved(ns.id.charDB, opts.char or {})
    c.setClass("WARRIOR"); c.setFaction("Alliance"); c.setLevel(18)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    if opts.questie ~= false then
        local db, zones = questie()
        c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    end
    c.setQuestLog(opts.log or LOG)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon, addon.problems:count()
end

local function trip(addon) return addon.use(ns.Nav.TripRoute.NAME) end

local function labels(addon)
    local view = trip(addon).View()
    if type(view) ~= "table" then return nil end
    local out = {}
    for _, s in ipairs(view.stops) do out[#out + 1] = tostring(s.label) end
    table.sort(out)
    return table.concat(out, ",")
end

local function first(c)
    local a = c.arrows[1]
    return a and a.lines and a.lines[1]
end

local function said(c, text)
    for _, line in ipairs(c.printed or {}) do
        if tostring(line):find(text, 1, true) then return line end
    end
    return nil
end

-- Red on aa3dd5a8: View() is nil and no line is drawn.
tests["route auto: with no word the quest route is planned and drawn on the world map"] = function(t)
    local c, addon, base = boot()
    t.eq(labels(addon), "Bandages,Boars,Herbs", "planned by itself from the quest log")
    c.setWorldMap(MAP)
    c.advance(1, 8)
    local set = c.routeLineSets and c.routeLineSets[1]
    t.ok(set ~= nil and set.shown == true and #set.lines > 0, "the route is drawn on the map")
    t.eq(said(c, "1. Bandages"), nil, "nothing is said in chat")
    t.eq(first(c), "Boars", "the arrow keeps its own pick")
    t.eq(trip(addon).Current(), nil, "not a route the arrow walks")
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Red on aa3dd5a8: View() is nil after the reload.
tests["route auto: after a restart the route is there again with no word"] = function(t)
    local c = boot()
    local _, addon2 = boot({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    t.eq(labels(addon2), "Bandages,Boars,Herbs", "planned again at login")
end

-- Red on aa3dd5a8: no route to change.
tests["route auto: a quest taken or a step done plans the route again by itself"] = function(t)
    local c, addon = boot()
    t.eq(labels(addon), "Bandages,Boars,Herbs")
    c.setQuestLog({ LOG[1], LOG[2], LOG[3], { id = 404, title = "Wolves", objectives = { { text = "Wolves: 0/6" } } } })
    c.fire("QUEST_LOG_UPDATE")
    c.advance(4, 8)
    t.eq(labels(addon), "Bandages,Boars,Herbs,Wolves", "a new quest's step is on the route")
    c.setQuestLog({ { id = 401, title = "Boars", objectives = { { text = "Boars slain: 4/4", done = true } } },
                    LOG[2], LOG[3] })
    c.fire("QUEST_LOG_UPDATE")
    c.advance(4, 8)
    t.eq(labels(addon), "Bandages,Herbs", "a done step and an abandoned quest leave it")
end

tests["route auto: the Router's setting off, or the routes' setting off, shows no route"] = function(t)
    local c, addon = boot()
    t.ok(labels(addon) ~= nil, "planned")
    addon.settings:set(ns.RouteList.SETTING, false)
    c.advance(4, 8)
    t.eq(labels(addon), nil, "the Router's setting off: no route")
    addon.settings:set(ns.RouteList.SETTING, true)
    c.advance(4, 8)
    t.ok(labels(addon) ~= nil, "on again: planned again")
    addon.settings:set(ns.Nav.TripRoute.SETTING, false)
    c.advance(4, 8)
    t.eq(labels(addon), nil, "the routes' setting off: no route")
end

-- The word still plans a route the arrow walks; "route off" keeps it off
-- for the session.
tests["route auto: the route word makes the arrow walk it; route off keeps it off"] = function(t)
    local c, addon = boot()
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
    t.ok(said(c, "1. Bandages") ~= nil, "the word says the list")
    t.eq(first(c), "Bandages", "and the arrow walks it")
    t.ok(trip(addon).Current() ~= nil, "a route the arrow walks")
    c.slashes[ns.id.slash]("route off")
    c.advance(10, 20)
    t.eq(labels(addon), nil, "off: not planned again by itself this session")
    t.eq(first(c), "Boars", "the arrow's own pick again")
    c.slashes[ns.id.slash]("route new")
    c.advance(1, 5)
    t.ok(labels(addon) ~= nil, "planned again by the word")
end

-- Section 236: data arriving late.
tests["route auto: Questie loading after login: the route is planned once it answers"] = function(t)
    local c, addon, base = boot({ questie = false })
    t.eq(labels(addon), nil, "no places yet: no route")
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.advance(10, 10)
    t.eq(labels(addon), "Bandages,Boars,Herbs", "planned once Questie answers")
    t.eq(addon.problems:count(), base, "no new problem")
end

tests["route auto: the log signature changes with a step done, not with a count"] = function(t)
    local T = ns.Nav.TripRoute
    local a = T.LogSignature({ { id = 1, objectives = { { text = "x 1/4" } } } })
    t.eq(T.LogSignature({ { id = 1, objectives = { { text = "x 2/4" } } } }), a, "a count going up")
    t.ok(T.LogSignature({ { id = 1, objectives = { { text = "x 4/4", done = true } } } }) ~= a, "a step done")
    t.ok(T.LogSignature({ { id = 1, complete = true, objectives = {} } }) ~= a, "complete")
    t.eq(T.LogSignature({ { id = 2 }, { id = 1 } }), T.LogSignature({ { id = 1 }, { id = 2 } }), "any order")
    t.eq(T.LogSignature(nil), nil)
end

return tests
