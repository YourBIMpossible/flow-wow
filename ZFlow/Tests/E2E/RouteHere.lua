local _, ns = ...

-- End to end (A2-20, lead section 674): the tracker's "here" data through
-- the whole add-on with a fake client. A quest route is planned with the
-- route word; addon.use("routeHere").Here() gives the steps around the
-- player. Made-up quests and places; not tested in game.

local tests = {}

local MAP = 1436

local function questie()
    local quests = {
        [401] = { ObjectiveData = { { Type = "monster", Id = 9101 } } },
        [402] = { ObjectiveData = { { Type = "monster", Id = 9102 } } },
    }
    local npcs = {
        [9101] = { name = "Boar", spawns = { [40] = { { 52, 50 } } } },
        [9102] = { name = "Herb Thing", spawns = { [40] = { { 10, 90 } } } },
    }
    local db = {}
    function db.GetQuest(id) return quests[id] end
    function db.GetNPC(id) return npcs[id] end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [40] = MAP })[area] end
    return db, zones
end

local BOARS = { id = 401, title = "Boars", objectives = { { text = "Boars slain: 0/4" } } }
local HERBS = { id = 402, title = "Herbs", objectives = { { text = "Herbs: 0/5" } } }

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setFaction("Alliance"); c.setLevel(18)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog({ BOARS, HERBS })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

tests["route here e2e: the planned route's steps around the player, through the boot"] = function(t)
    local c, addon = boot()
    local api = addon.use("routeHere")
    t.ok(api ~= nil, "the module is declared")
    t.eq(api.Here(), nil, "nothing planned: nil")
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
    local got = api.Here()
    t.ok(got ~= nil, "a route is planned")
    t.eq(got.total, 2, "both steps are on the route")
    t.eq(#got.stops, 1, "only the boars, 20 yards off, are here")
    t.eq(got.stops[1].label, "Boars")
    t.eq(got.stops[1].index, 1)
end

return tests
