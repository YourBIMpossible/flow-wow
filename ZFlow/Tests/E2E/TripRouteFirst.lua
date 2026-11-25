local _, ns = ...

-- A1-13 (lead sections 826, 828.1): tripRoute.First(n) on the whole add-on
-- with a fake client. A route planned with the route word; the second step
-- shown goes first, the arrow then walks it; with no route it moves
-- nothing. Made-up quests and places (the same as Tests/E2E/TripEdges.lua);
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

local function shown(addon)
    local v = addon.use("tripRoute").View()
    local out = {}
    for _, s in ipairs(v and v.stops or {}) do out[#out + 1] = s.label end
    return out
end

tests["trip route first: the second step shown goes first on a planned route"] = function(t)
    local c, addon = boot()
    local route = addon.use("tripRoute")
    t.eq(type(route.First), "function", "the module provides First")
    if type(route.First) ~= "function" then return end
    t.eq(route.First(2), false, "no route yet: nothing moves")
    slash(c, "route")
    local before = shown(addon)
    t.ok(#before >= 2, "a route of two steps or more: " .. table.concat(before, ", "))
    if #before < 2 then return end
    t.eq(route.First(2), true)
    local after = shown(addon)
    t.eq(after[1], before[2], "the second step is first now")
    t.eq(after[2], before[1], "the old first comes next")
    t.eq(route.First(1), false, "the first step stays where it is")
    t.eq(route.First(#after + 1), false, "no such step")
end

return tests
