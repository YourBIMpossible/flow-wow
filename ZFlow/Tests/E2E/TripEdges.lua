local _, ns = ...

-- End to end (lead section 375 item 4): trip and route edge cases on the
-- whole add-on with a fake client. A quest abandoned mid-route, a quest
-- handed in out of order, and an empty route. Made-up quests and places;
-- not tested in game.

local tests = {}

local MAP = 1436

local function questie()
    local quests = {
        [401] = { ObjectiveData = { { Type = "monster", Id = 9101 } } },
        [402] = { ObjectiveData = { { Type = "monster", Id = 9102 } } },
        [403] = { ObjectiveData = {}, Finisher = { NPC = { 9103 } } },
        [404] = { ObjectiveData = {}, Finisher = { NPC = { 9104 } } },
    }
    local npcs = {
        [9101] = { name = "Boar", spawns = { [40] = { { 60, 50 } } } },
        [9102] = { name = "Herb Thing", spawns = { [40] = { { 20, 50 } } } },
        [9103] = { name = "Smith", spawns = { [40] = { { 55, 50 } } } },
        [9104] = { name = "Postman", spawns = { [40] = { { 80, 50 } } } },
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
local BANDAGES = { id = 403, title = "Bandages", complete = true,
                   objectives = { { text = "Linen: 4/4", done = true } } }
local LETTERS = { id = 404, title = "Letters", complete = true,
                  objectives = { { text = "Letters: 2/2", done = true } } }

local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setFaction("Alliance"); c.setLevel(18)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    if opts.questie ~= false then
        local db, zones = questie()
        c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    end
    c.setQuestLog(opts.log or { BANDAGES, BOARS, HERBS })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

-- The slash handler (Core/Diag.lua) lowers the whole line: labels typed lower.
local function slash(c, text)
    c.slashes[ns.id.slash](text)
    c.advance(1, 5)
end

local function count(c, text)
    local n = 0
    for _, line in ipairs(c.printed or {}) do
        if tostring(line):find(text, 1, true) then n = n + 1 end
    end
    return n
end

local function first(c)
    local a = c.arrows[1]
    return a and a.lines and a.lines[1]
end

local function problems(addon)
    local n = 0
    for _, p in ipairs(addon.problems:list()) do n = n + (p.count or 1) end
    return n
end

local function tripList(addon)
    local v = addon.store:get("char", ns.Nav.Trip.PATH)
    return type(v) == "table" and type(v.stops) == "table" and v.stops or {}
end

local function leftLine(label)
    return ns.Nav.TripRoute.LEFT:format(label)
end

local function labels(addon)
    local cur = addon.use("tripRoute").Current()
    local out = {}
    for _, s in ipairs(cur and cur.stops or {}) do out[#out + 1] = s.label end
    return out
end

-- 1. A quest abandoned mid-route.
tests["trip edges: a quest abandoned mid-route leaves the quest route with one line"] = function(t)
    local c, addon = boot()
    local before = problems(addon)
    slash(c, "route")
    t.eq(first(c), "Bandages")
    c.setQuestLog({ BOARS, HERBS })
    c.advance(5, 60)
    t.eq(first(c), "Boars", "the arrow moves to the next stop")
    t.eq(count(c, leftLine("Bandages")), 1, "one line says so")
    c.printed = {}
    slash(c, "route")
    t.eq(count(c, "Bandages"), 0, "no longer listed")
    t.eq(count(c, "Boars"), 1, "Boars still listed")
    t.eq(problems(addon), before, "nothing errors")
end

tests["trip edges: a quest abandoned mid-trip leaves the route and the trip list"] = function(t)
    local c, addon = boot({ log = { BANDAGES, LETTERS } })
    local before = problems(addon)
    slash(c, "trip add giver bandages")
    slash(c, "trip add giver letters")
    t.eq(#tripList(addon), 2)
    slash(c, "trip go")
    t.eq(first(c), "Hand in: Bandages")
    c.setQuestLog({ LETTERS })
    c.advance(5, 60)
    t.eq(first(c), "Hand in: Letters", "the arrow moves to the next stop")
    t.eq(count(c, leftLine("Hand in: Bandages")), 1, "one line says so")
    local list = tripList(addon)
    t.eq(#list, 1, "gone from the trip list too")
    t.eq(list[1] and list[1].label, "Hand in: Letters")
    t.eq(problems(addon), before, "nothing errors")
end

-- 2. A quest handed in out of order.
tests["trip edges: a later trip stop's quest handed in first leaves; the afters hold"] = function(t)
    local c, addon = boot({ log = { BANDAGES, LETTERS } })
    local before = problems(addon)
    c.setPosition(MAP, 0.3, 0.5)
    c.advance(1, 5)
    slash(c, "trip add here camp")
    c.setPosition(MAP, 0.5, 0.5)
    c.advance(1, 5)
    slash(c, "trip add giver bandages")
    slash(c, "trip add giver letters")
    slash(c, "trip after 2 1")
    slash(c, "trip after 3 2")
    slash(c, "trip go")
    t.eq(labels(addon), { "camp", "Hand in: Bandages", "Hand in: Letters" })
    -- Letters handed in before Bandages, on the way to camp.
    c.setQuestLog({ BANDAGES })
    c.advance(5, 60)
    t.eq(first(c), "camp", "still camp first")
    t.eq(count(c, leftLine("Hand in: Letters")), 1)
    t.eq(labels(addon), { "camp", "Hand in: Bandages" }, "no stop points at a finished quest")
    c.setPosition(MAP, 0.3, 0.5)
    c.advance(2, 20)
    t.eq(first(c), "Hand in: Bandages", "after camp: bandages, as its after says")
    local list = tripList(addon)
    t.eq(#list, 2)
    t.eq(list[2] and list[2].label, "Hand in: Bandages")
    t.eq(list[2] and type(list[2].after), "table", "bandages still comes after camp")
    t.eq(problems(addon), before, "nothing errors")
end

tests["trip edges: a later quest route stop handed in first leaves; the rest keep their order"] = function(t)
    local c, addon = boot()
    local before = problems(addon)
    slash(c, "route")
    t.eq(labels(addon), { "Bandages", "Boars", "Herbs" })
    c.setQuestLog({ BANDAGES, HERBS })
    c.advance(5, 60)
    t.eq(first(c), "Bandages", "the current stop stays")
    t.eq(count(c, leftLine("Boars")), 1)
    t.eq(labels(addon), { "Bandages", "Herbs" })
    t.eq(problems(addon), before, "nothing errors")
end

-- 3. An empty route.
tests["trip edges: route, trip go and tracker with nothing planned each say one line"] = function(t)
    local c, addon = boot({ questie = false })
    local before = problems(addon)
    local normal = first(c)
    c.printed = {}
    slash(c, "route")
    t.eq(#c.printed, 1)
    t.eq(count(c, ns.Nav.TripRoute.WHY_NONE), 1)
    t.eq(first(c), normal, "the arrow keeps its normal step")
    c.printed = {}
    slash(c, "trip go")
    t.eq(#c.printed, 1)
    t.eq(count(c, ns.Nav.Trip.EMPTY), 1)
    t.eq(first(c), normal)
    c.printed = {}
    slash(c, "tracker")
    t.eq(#c.printed, 1)
    t.eq(count(c, ns.RouteTracker.EMPTY[1]), 1)
    t.eq(first(c), normal)
    t.eq(problems(addon), before, "nothing errors")
end

return tests
