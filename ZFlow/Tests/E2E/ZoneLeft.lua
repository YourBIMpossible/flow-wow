local _, ns = ...

-- End to end (S37): what is still worth doing here before leaving, on the
-- whole add-on with a fake client. The word lists the player's quests with
-- something left on this map; crossing into another zone says once what
-- was left behind. Lines of chat only. Made-up quests and places; not
-- tested in game.

local tests = {}

local MAP, NEXT = 1436, 1437

local function questie()
    local quests = {
        [401] = { ObjectiveData = { { Type = "monster", Id = 9101 } } },
        [402] = { ObjectiveData = { { Type = "monster", Id = 9102 } } },
        [404] = { ObjectiveData = { { Type = "monster", Id = 9104 } } },
    }
    local npcs = {
        [9101] = { name = "Boar", spawns = { [40] = { { 60, 50 } } } },
        [9102] = { name = "Herb Thing", spawns = { [40] = { { 20, 50 } } } },
        [9104] = { name = "Far Thing", spawns = { [11] = { { 20, 50 } } } },
    }
    local db = {}
    function db.GetQuest(id) return quests[id] end
    function db.GetNPC(id) return npcs[id] end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [40] = MAP, [11] = NEXT })[area] end
    return db, zones
end

local BOARS = { id = 401, title = "Boars", objectives = { { text = "Boars slain: 0/4" } } }
local HERBS = { id = 402, title = "Herbs", objectives = { { text = "Herbs: 0/5" } } }
local FAR = { id = 404, title = "Far Things", objectives = { { text = "Far things: 0/1" } } }

local function boot(log)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setFaction("Alliance"); c.setLevel(18)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    c.setMapSize(NEXT, 1000, 1000); c.setMapCont(NEXT, 0)
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog(log or { BOARS, HERBS, FAR })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function said(c, text, from)
    for i = (from or 0) + 1, #(c.printed or {}) do
        if tostring(c.printed[i]):find(text, 1, true) then return c.printed[i] end
    end
    return nil
end

local function cross(c)
    c.setZone(1, NEXT); c.setPosition(NEXT, 0.9, 0.5)
    c.fire("ZONE_CHANGED_NEW_AREA")
    c.advance(1, 5)
end

local function problems(addon)
    local n = 0
    for _, p in ipairs(addon.problems:list()) do n = n + (p.count or 1) end
    return n
end

tests["zone left: the word lists what is left on this map and what is for elsewhere"] = function(t)
    local c, addon = boot()
    local before, base = #c.printed, problems(addon)
    c.slashes[ns.id.slash]("zone")
    t.ok(said(c, "Still worth doing here before you leave: 2 quests", before) ~= nil)
    t.ok(said(c, "Boars: 1 step left here", before) ~= nil)
    t.ok(said(c, "Herbs: 1 step left here", before) ~= nil)
    t.ok(said(c, "1 other quest is for somewhere else (after this zone).", before) ~= nil)
    t.ok(said(c, "route to walk them in order", before) ~= nil, "it says how to walk them")
    t.eq(said(c, "Far Things:", before), nil, "a quest for another map is not listed as here")
    t.eq(problems(addon), base, "nothing new went wrong")
end

tests["zone left: with nothing left here the word says the player can move on"] = function(t)
    local c = boot({ FAR })
    local before = #c.printed
    c.slashes[ns.id.slash]("zone")
    t.ok(said(c, ns.Nav.ZoneLeft.NONE, before) ~= nil)
    t.eq(said(c, "route to walk them", before), nil)
end

tests["zone left: crossing into another zone says once what was left behind"] = function(t)
    local c, addon = boot()
    local before, base = #c.printed, problems(addon)
    t.eq(said(c, "unfinished in the zone behind you"), nil, "nothing is said at login")
    cross(c)
    t.ok(said(c, "You left 2 quests unfinished in the zone behind you: Boars, Herbs.", before) ~= nil)
    local after = #c.printed
    c.fire("ZONE_CHANGED_NEW_AREA"); c.advance(1, 5)
    t.eq(said(c, "unfinished in the zone behind you", after), nil, "not said again in the same zone")
    t.eq(problems(addon), base, "nothing new went wrong")
end

tests["zone left: nothing left behind, or the setting off: nothing is said on leaving"] = function(t)
    local c = boot({ FAR })
    cross(c)
    t.eq(said(c, "unfinished in the zone behind you"), nil, "nothing was left")
    local addon
    c, addon = boot()
    addon.settings:set(ns.Nav.LEAVING_SETTING, false)
    cross(c)
    t.eq(said(c, "unfinished in the zone behind you"), nil, "the setting is off")
end

return tests
