local _, ns = ...
-- The route reads the zone filter (parity row A1-27; lead sections 488, 507,
-- 522 and 541): the quest route keeps the stops of the zones you picked
-- first. A stop in a zone you did not pick is left out and named, with why
-- (the setting off), or comes after your zones (the setting on). Nothing
-- picked: the route is as it was. The settings row is held back until the
-- player can pick zones (lead section 542); its words stay as data, and
-- with no row the setting reads as off. A stop's zone is the map it is on.
-- Whole add-on on a fake client; made-up quests and places. Not tested in
-- game.
-- Red on the base (1a947eb7 with route-a4 6ccc4df8 merged in): the route
-- does not read the picks and there is no T.Zoned.
local tests = {}

local MAP, OTHER = 1436, 1437

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

-- opts: char, account (saved ahead)
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {}); c.setSaved(ns.id.charDB, opts.char or {})
    c.setClass("WARRIOR"); c.setFaction("Alliance"); c.setLevel(18)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog(LOG)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon, addon.problems:count()
end

-- Plans anew each time (the bare word keeps a route that is already planned).
local function route(c)
    local from = #c.printed
    c.slashes[ns.id.slash]("route new")
    c.advance(1, 5)
    local out = {}
    for i = from + 1, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return out
end

local function with(lines, text)
    for _, line in ipairs(lines) do
        if line:find(text, 1, true) then return line end
    end
    return nil
end

local function labels(stops)
    local out = {}
    for i, s in ipairs(stops) do out[i] = s.label end
    return table.concat(out, ",")
end

-- The route's own stop shape: a zone is the map a stop is on.
local function stop(label, map)
    return { label = label, quest = 1, place = { map = map, x = 0.5, y = 0.5 }, leg = 99, secs = 9 }
end

-- Red: there is no T.Zoned (the call raises).
tests["route zones: the picks order the stops; a zone not picked is left out and named, or comes after"] = function(t)
    local T, ZF = ns.Nav.TripRoute, ns.Nav.ZoneFilter
    local stops = { stop("a", MAP), stop("b", OTHER), stop("c", MAP), stop("d", OTHER) }
    local function order(first)
        return function(list, zoneOf) return ZF.Order(list, { [MAP] = true }, first, zoneOf) end
    end
    local kept, out, changed = T.Zoned(stops, order(false))
    t.eq(labels(kept), "a,c", "the setting off: only your zones")
    t.eq(changed, true)
    t.eq(#out, 2)
    t.eq({ out[1].label, out[1].why }, { "b", T.ZONE_LEFT }, "the stop left out is named, with why")
    kept, out, changed = T.Zoned(stops, order(true))
    t.eq(labels(kept), "a,c,b,d", "the setting on: the other zone's stops after yours")
    t.eq(#out, 0)
    t.eq(changed, true)
    kept, out, changed = T.Zoned(stops, function(list, zoneOf) return ZF.Order(list, nil, false, zoneOf) end)
    t.eq(labels(kept), "a,b,c,d", "nothing picked: as planned")
    t.eq(changed, false)
    t.eq(#out, 0)
    kept, out, changed = T.Zoned(stops, nil)
    t.eq({ labels(kept), #out, changed }, { "a,b,c,d", 0, false }, "no zone filter: as planned")
    kept, _, changed = T.Zoned(stops, function() error("zone filter failed (test)") end)
    t.eq({ labels(kept), changed }, { "a,b,c,d", false }, "a zone filter that raises: as planned")
end

-- Lead section 542: the row is held back until zones can be picked; its
-- words are kept, unregistered, for when it comes back.
tests["route zones: no settings row yet; its words are kept as data; the setting reads as off"] = function(t)
    local _, addon = boot()
    local ZF = ns.Nav.ZoneFilter
    t.eq(addon.settings:row(ZF.SETTING), nil, "no settings row")
    t.eq(ZF.ROW_LABEL, "Finish the selected zones first")
    t.ok(type(ZF.ROW_HELP) == "string" and ZF.ROW_HELP:find("selected zones first", 1, true) ~= nil
        and ZF.ROW_HELP:find("left out of the route", 1, true) ~= nil, "the help says both ways")
    t.eq(addon.use("zoneFilter").First(), false, "with no row: a zone not picked is left out")
end

tests["route zones: nothing picked, or this zone picked, the route is as it was"] = function(t)
    local c, addon, base = boot()
    local lines = route(c)
    t.ok(with(lines, "1. Bandages") ~= nil and with(lines, "2. Boars") ~= nil and with(lines, "3. Herbs") ~= nil,
        "nothing picked: all three stops")
    t.eq(addon.use("zoneFilter").SetZoneOn(MAP, true), true, "pick this zone")
    lines = route(c)
    t.ok(with(lines, "1. Bandages") ~= nil and with(lines, "3. Herbs") ~= nil, "this zone picked: all three stops")
    t.eq(with(lines, ns.Nav.TripRoute.ZONE_LEFT), nil, "nothing is left out")
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Red: the route ignores the picks and plans all three stops.
tests["route zones: only another zone picked leaves this zone's stops out, and unpicked it plans them again"] = function(t)
    local c, addon, base = boot()
    local T = ns.Nav.TripRoute
    local zones = addon.use("zoneFilter")
    t.eq(zones.SetZoneOn(OTHER, true), true, "pick another zone only")
    local lines = route(c)
    t.ok(with(lines, T.WHY_ZONES) ~= nil, "the word says no stop is in your zones: " .. tostring(lines[1]))
    t.eq(with(lines, "1. Bandages"), nil, "and plans none")
    t.eq(zones.SetZoneOn(OTHER, false), true, "unpick it")
    lines = route(c)
    t.ok(with(lines, "1. Bandages") ~= nil and with(lines, "3. Herbs") ~= nil, "nothing picked again: all three stops")
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Section 236: a reload keeps the picks; picks made later are read at the next plan.
tests["route zones: the picks are read at each plan, and kept over a reload"] = function(t)
    local c, addon = boot()
    local T = ns.Nav.TripRoute
    t.ok(with(route(c), "1. Bandages") ~= nil, "planned before any pick")
    addon.use("zoneFilter").SetZoneOn(OTHER, true)
    t.ok(with(route(c), T.WHY_ZONES) ~= nil, "a pick made later is read at the next plan")
    local c2 = boot({ account = c.saved(ns.id.accountDB), char = c.saved(ns.id.charDB) })
    t.ok(with(route(c2), T.WHY_ZONES) ~= nil, "after a reload the pick is still read")
end

return tests
