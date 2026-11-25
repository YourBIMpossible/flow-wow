local _, ns = ...

-- End to end (A2-05): low-level (grey) pick-ups are kept off the route
-- unless the low-level quests setting, default off, is on. The whole add-on
-- on a fake client with a made-up Questie. Made-up quests and places; not
-- tested in game.

local tests = {}

local MAP = 1436

local function questie()
    local quests = {
        [401] = { ObjectiveData = { { Type = "monster", Id = 9101 } } },
        [621] = { Id = 621, name = "Old Errand", level = 8, requiredLevel = 4, Starts = { NPC = { 9201 } } },
        [622] = { Id = 622, name = "Fresh Task", level = 18, requiredLevel = 12, Starts = { NPC = { 9201 } } },
    }
    local npcs = {
        [9101] = { name = "Boar", spawns = { [40] = { { 60, 50 } } } },
        [9201] = { name = "Marshal", friendlyToFaction = "AH", spawns = { [40] = { { 52, 50 } } } },
    }
    local db = { QuestPointers = {} }
    for id in pairs(quests) do db.QuestPointers[id] = true end
    function db.GetQuest(id) return quests[id] end
    function db.GetNPC(id) return npcs[id] end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [40] = MAP })[area] end
    return db, zones
end

local LOG = { { id = 401, title = "Boars", objectives = { { text = "Boars slain: 0/4" } } } }

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setRaceId(1); c.setFaction("Alliance"); c.setLevel(18)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog(LOG)
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

local function route(c)
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
end

tests["low quests: the setting row defaults off"] = function(t)
    local _, addon = boot()
    t.eq(addon.settings:get(ns.Nav.LowQuests.SETTING), false)
    t.eq(addon.use("lowQuests").On(), false)
end

tests["low quests: off, a grey pick-up is left off the route"] = function(t)
    local c = boot()
    route(c)
    t.ok(said(c, "Old Errand") == nil, "the grey quest is not offered")
    t.ok(said(c, "Pick up: Fresh Task (Marshal)") ~= nil, "a quest at your level is offered")
end

tests["low quests: on, the grey pick-up is on the route"] = function(t)
    local c, addon = boot()
    addon.settings:set(ns.Nav.LowQuests.SETTING, true)
    t.eq(addon.use("lowQuests").On(), true)
    route(c)
    t.ok(said(c, "Pick up: Old Errand (Marshal)") ~= nil, "on: the grey quest is offered")
    t.ok(said(c, "Pick up: Fresh Task (Marshal)") ~= nil, "on: the usual quest still is")
end

return tests
