local _, ns = ...
-- The inn for the set-hearthstone stop is chosen from the route's own stops
-- (Twin's plan, lead sections 545 and 552, note 3). It was chosen from the
-- first point of every spot Questie places for a quest in the log, done or
-- not, a stop or not, all taken as this map's: an objective already done
-- and the turn-in of a quest not finished counted as places you would go.
-- Now the inn near most of where the route goes is the one. Whole add-on on
-- a fake client; made-up quests and places. Look only: nothing is set. Not
-- tested in game.
-- Red on f13d3468: the West Inn is chosen (four spots you will not walk to
-- lie by it), and there is no T.InnSpots.
local tests = {}

local MAP = 1436
local WEST, EAST = "Set hearthstone: West Inn", "Set hearthstone: East Inn"

-- Two quests, each with a first objective that is done (by the west inn), a
-- second still to do (by the east inn), and a turn-in by the west inn.
local function questie()
    local quests = {
        [401] = { ObjectiveData = { { Type = "monster", Id = 9101 }, { Type = "monster", Id = 9102 } },
                  Finisher = { NPC = { 9105 } } },
        [402] = { ObjectiveData = { { Type = "monster", Id = 9103 }, { Type = "monster", Id = 9104 } },
                  Finisher = { NPC = { 9106 } } },
    }
    local npcs = {
        [9101] = { name = "West Boar", spawns = { [40] = { { 15, 50 } } } },
        [9102] = { name = "East Boar", spawns = { [40] = { { 60, 50 } } } },
        [9103] = { name = "West Herb", spawns = { [40] = { { 14, 50 } } } },
        [9104] = { name = "East Herb", spawns = { [40] = { { 62, 50 } } } },
        [9105] = { name = "West Smith", spawns = { [40] = { { 16, 50 } } } },
        [9106] = { name = "West Cook", spawns = { [40] = { { 15, 52 } } } },
    }
    local db = {}
    function db.GetQuest(id) return quests[id] end
    function db.GetNPC(id) return npcs[id] end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [40] = MAP })[area] end
    return db, zones
end

local LOG = {
    { id = 401, title = "Boars", objectives = { { text = "West boars: 4/4", done = true }, { text = "East boars: 0/4" } } },
    { id = 402, title = "Herbs", objectives = { { text = "West herbs: 5/5", done = true }, { text = "East herbs: 0/5" } } },
}

local function inn(name, x)
    return { name = name, map = MAP, x = x, y = 0.5, kinds = { innkeeper = true } }
end

-- inns: the seen inns ({ key = inn }), or nil for none
local function boot(inns)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, inns and { learned = { places = { services = inns } } } or {})
    c.setClass("WARRIOR"); c.setFaction("Alliance"); c.setLevel(18)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog(LOG)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    c.slashes[ns.id.slash]("route")
    c.advance(1, 5)
    return c, addon, addon.problems:count()
end

local function labels(addon)
    local trip = addon.use(ns.Nav.TripRoute.NAME)
    local view = type(trip) == "table" and trip.View() or nil
    local out = {}
    for _, s in ipairs(type(view) == "table" and view.stops or {}) do out[#out + 1] = tostring(s.label) end
    return out
end

local function has(list, text)
    for _, v in ipairs(list) do
        if v == text then return true end
    end
    return false
end

-- Red on f13d3468: the West Inn is chosen.
tests["route inn: the inn near where the route goes is chosen, not the one near spots it will not walk to"] = function(t)
    local _, addon, base = boot({ w = inn("West Inn", 0.15), e = inn("East Inn", 0.61) })
    local stops = labels(addon)
    t.eq(has(stops, EAST), true, "the east inn, by both stops still to do: " .. table.concat(stops, " | "))
    t.eq(has(stops, WEST), false, "not the west inn, by the done objectives and the turn-ins of unfinished quests")
    t.eq(has(stops, "Boars") and has(stops, "Herbs"), true, "the quest stops are still planned")
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Red on f13d3468: the West Inn is a stop though the route never goes near it.
tests["route inn: an inn the route does not go near is no stop"] = function(t)
    local _, addon = boot({ w = inn("West Inn", 0.15) })
    local stops = labels(addon)
    t.eq(has(stops, WEST), false, "no set-hearthstone stop: " .. table.concat(stops, " | "))
    t.eq(#stops, 2, "the two quest stops only")
end

tests["route inn: no seen inn, no set-hearthstone stop, as before"] = function(t)
    local _, addon, base = boot(nil)
    local stops = labels(addon)
    t.eq(#stops, 2, "the two quest stops: " .. table.concat(stops, " | "))
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Red on f13d3468: there is no T.InnSpots (the call raises).
tests["route inn: the places the inn is chosen from are the route's quest stops, pure"] = function(t)
    local T = ns.Nav.TripRoute
    local stops = {
        { quest = 1, place = { map = MAP, x = 0.6, y = 0.5 } },
        { quest = 2, turnIn = true, place = { map = MAP, x = 0.62, y = 0.5 } },
        { kind = "pickup", quest = 3, place = { map = MAP, x = 0.3, y = 0.5 } },
        { quest = 4, cast = true, place = { map = MAP + 1, x = 0.15, y = 0.5 } },
        { kind = "sell", place = { map = MAP, x = 0.1, y = 0.5 } },
        { kind = "repair", place = { map = MAP, x = 0.1, y = 0.5 } },
        { kind = "hearth", place = { map = MAP, x = 0.1, y = 0.5 } },
        { quest = 5 },
    }
    t.eq(T.InnSpots(stops), {
        { map = MAP, x = 0.6, y = 0.5 }, { map = MAP, x = 0.62, y = 0.5 }, { map = MAP, x = 0.3, y = 0.5 },
        { map = MAP + 1, x = 0.15, y = 0.5 },
    }, "quest stops and pick-ups with their own map; never a town stop; never a stop with no place")
    t.eq(T.InnSpots(nil), {})
    t.eq(T.InnSpots({}), {})
end

return tests
