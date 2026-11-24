local _, ns = ...

-- End to end (S25): the whole add-on on a fake client. The export word
-- keeps its lines in this character's saved data and export dump prints
-- them; a planned quest route is in the export under a route heading.
-- Made-up quests and places; not tested in game.

local tests = {}

local MAP = 1436

local function questie()
    local quests = {
        [401] = { ObjectiveData = { { Type = "monster", Id = 9101 } } },
        [403] = { ObjectiveData = {}, Finisher = { NPC = { 9103 } } },
    }
    local npcs = {
        [9101] = { name = "Boar", spawns = { [40] = { { 60, 50 } } } },
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
    { id = 403, title = "Bandages", complete = true, objectives = { { text = "Linen: 4/4", done = true } } },
}

local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setFaction("Alliance"); c.setLevel(18)
    c.setClock(1700000000)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog(LOG)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon)
    if opts.login ~= false then
        c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
        c.advance(10, 40)
    end
    return c, addon
end

local function said(c, text)
    for _, line in ipairs(c.printed or {}) do
        if tostring(line):find(text, 1, true) then return line end
    end
    return nil
end

local function word(c, rest)
    c.printed = {}
    c.slashes[ns.id.slash](rest)
    c.advance(1, 5)
end

local function savedLines(addon)
    if type(addon) ~= "table" or type(addon.store) ~= "table" then return nil end
    local e = addon.store:get("char", ns.Export.PATH)
    return type(e) == "table" and e.lines or nil
end

tests["export: the word saves the lines and export dump prints them"] = function(t)
    local c, addon = boot()
    word(c, "export")
    local line = said(c, ns.id.title .. ": export: ")
    t.ok(line ~= nil and line:find("lines (your class, quests and professions), saved for this character", 1, true) ~= nil,
        tostring(line))
    t.ok(said(c, "E^you^") == nil, "export alone prints no records")
    local lines = savedLines(addon)
    t.ok(type(lines) == "table" and #lines > 0, "the lines are in this character's saved data")
    t.ok(lines and lines[1]:find("^E%^export%^v=1") ~= nil, tostring(lines and lines[1]))
    t.ok(lines and lines[#lines]:find("^E%^end%^lines=") ~= nil, tostring(lines and lines[#lines]))
    word(c, "EXPORT DUMP")
    t.ok(said(c, "E^export^v=1") ~= nil, "dump prints the first record")
    t.ok(said(c, "E^you^class=WARRIOR") ~= nil, "dump prints the you record")
    t.ok(said(c, "E^quest^id=401") ~= nil, "dump prints a quest")
    t.ok(said(c, "E^route^") == nil, "no route planned: no route lines")
    t.ok(said(c, "E^stop^") == nil, "no route planned: no stop lines")
end

tests["export: a planned route is exported under a route heading"] = function(t)
    local c, addon = boot()
    word(c, "route")
    t.ok(said(c, "1. Bandages") ~= nil, "the route is planned")
    word(c, "export dump")
    local head = said(c, "E^route^")
    t.ok(head ~= nil and head:find("stops=2", 1, true) ~= nil and head:find("text=Route: 2 stops", 1, true) ~= nil,
        tostring(head))
    local one = said(c, "E^stop^i=1^text=")
    t.ok(one ~= nil and one:find("Bandages", 1, true) ~= nil, tostring(one))
    local two = said(c, "E^stop^i=2^text=")
    t.ok(two ~= nil and two:find("Boars", 1, true) ~= nil, tostring(two))
    local lines = savedLines(addon) or {}
    local stops = 0
    for _, l in ipairs(lines) do
        if l:find("^E%^stop%^") then stops = stops + 1 end
    end
    t.eq(stops, 2, "the saved lines carry the stops too")
    word(c, "route off")
    word(c, "export dump")
    t.ok(said(c, "E^route^") == nil, "the route cleared: no route lines")
end

tests["export: before login it says not started"] = function(t)
    local c, addon = boot({ login = false })
    local run = c.slashes[ns.id.slash]
    t.ok(run ~= nil, "the slash is there once loaded")
    if not run then return end
    c.printed = {}
    run("export")
    t.ok(said(c, ns.id.title .. ": export: not started yet") ~= nil, "not started")
    t.eq(savedLines(addon), nil, "nothing saved")
end

return tests
