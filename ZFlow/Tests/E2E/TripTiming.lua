local _, ns = ...

-- End to end (S34 trip timing; set-up from Tests/E2E/TripRoute.lua): the whole add-on on a fake client. The
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
    if opts.size ~= false then c.setMapSize(MAP, 1000, 1000) end; c.setMapCont(MAP, 0)
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

tests["trip timing: each route step says about how long its leg takes"] = function(t)
    local c = boot()
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
    local one = said(c, "1. Bandages")
    t.ok(one ~= nil and one:find("50 yd - under a minute", 1, true) ~= nil, tostring(one))
    local three = said(c, "3. Herbs")
    t.ok(three ~= nil and three:find("400 yd - about 1 minute", 1, true) ~= nil, tostring(three))
end

tests["trip timing: an unknown map size says no time, only that the distance is not known"] = function(t)
    local c = boot({ size = false })
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
    local one = said(c, ns.Nav.TripRoute.NO_DISTANCE)
    t.ok(one ~= nil, "a step says its distance is not known")
    t.ok(one == nil or one:find("minute", 1, true) == nil, tostring(one))
end

return tests
