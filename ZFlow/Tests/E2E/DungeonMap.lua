-- The Dungeon Quests window's Map tab (lead section 303 item 8 (f)), end to
-- end on the whole add-on loaded on a fake client: the entrance Questie
-- lists for the picked dungeon, and Show on map setting the same waypoint
-- the Quests tab sets (the player's own, Nav/Waypoint.lua). A dungeon with
-- no entrance says so and its button is off. A made-up Questie. Not tested
-- in game.
local _, ns = ...
local tests = {}

local ID = "dungeons"
local DM, SFK = 1581, 209

local function questie()
    local quests = {
        [101] = { Id = 101, name = "Red Silk", level = 18, requiredLevel = 14, zoneOrSort = DM,
            Starts = { NPC = { 501 } } },
        [201] = { Id = 201, name = "Arugal Must Die", level = 27, requiredLevel = 18, zoneOrSort = SFK,
            Starts = { NPC = { 501 } } },
    }
    local db = { QuestPointers = { [101] = true, [201] = true } }
    function db.GetQuest(id) return quests[id] end
    function db.GetNPC() return { name = "Gryan", friendlyToFaction = "AH" } end
    function db.QueryQuestSingle(id, field)
        local q = quests[id]
        if not q then return nil end
        if field == "questLevel" then return q.level end
        return q[field]
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [40] = 1436 })[area] end
    function zones:GetDungeons()
        return { [DM] = { "The Deadmines", {}, nil, { { 40, 42.5, 71.8 } } }, [SFK] = { "Shadowfang Keep" } }
    end
    return db, zones
end

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setRaceId(1); c.setFaction("Alliance"); c.setLevel(18)
    c.setQuestDone(101, false); c.setQuestDone(201, false)
    c.setZone(1, 1436); c.setPosition(1436, 0.5, 0.5)
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(2, 10)
    c.slashes[ns.id.slash]("dungeons")
    c.advance(2, 20)
    return c, addon
end

local function texts(c)
    local out = {}
    for _, p in ipairs(c.kitWindows()[ID].parts or {}) do
        if p.text ~= nil then out[#out + 1] = tostring(p.text) end
    end
    return table.concat(out, " | ")
end

local function waypoint(addon)
    local slot = addon.store:get("char", ns.Nav.Waypoint.PATH)
    local wp = type(slot) == "table" and slot.waypoint or nil
    return wp and { wp.map, wp.x, wp.y, wp.label } or nil
end

tests["dungeon map: the Map tab shows the entrance and sets the same waypoint as the Quests tab"] = function(t)
    local c, addon = boot()
    c.kitSelect(ID, "dungeons", 1)
    t.eq(c.kitSelect(ID, "tabs", 3), true, "the Map tab")
    t.ok(texts(c):find("Entrance", 1, true) ~= nil, texts(c))
    t.eq(c.kitClick(ID, "showOnMap"), true, "the button is on the Map tab")
    local fromMap = waypoint(addon)
    t.eq(fromMap, { 1436, 0.425, 0.718, "The Deadmines" })
    local c2, addon2 = boot()
    c2.kitSelect(ID, "dungeons", 1)
    c2.kitClick(ID, "showOnMap")
    t.eq(waypoint(addon2), fromMap, "the Quests tab sets the same one")
end

tests["dungeon map: a dungeon with no entrance says so and its button does nothing"] = function(t)
    local c, addon = boot()
    c.kitSelect(ID, "dungeons", 2)
    c.kitSelect(ID, "tabs", 3)
    t.ok(texts(c):find(ns.DungeonRead.WHY_NO_ENTRANCE[1], 1, true) ~= nil, texts(c))
    t.eq(c.kitClick(ID, "showOnMap"), false, "the button is off")
    t.eq(waypoint(addon), nil, "no waypoint set")
end

return tests
