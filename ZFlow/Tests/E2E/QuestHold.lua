local _, ns = ...

-- End to end (C-12): elite pick-ups are held off the route while solo, with
-- a setting that defaults on. The whole add-on on a fake client with a
-- made-up Questie (its IsGroupQuest read). Made-up quests and places; not
-- tested in game.

local tests = {}

local MAP = 1436

local function questie()
    local quests = {
        [401] = { ObjectiveData = { { Type = "monster", Id = 9101 } } },
        [611] = { Id = 611, name = "Ogre Den", level = 18, requiredLevel = 12, Starts = { NPC = { 9201 } } },
        [612] = { Id = 612, name = "Old Mill", level = 18, requiredLevel = 12, Starts = { NPC = { 9201 } } },
        [613] = { Id = 613, name = "Odd Rumor", level = 18, requiredLevel = 12, Starts = { NPC = { 9201 } } },
    }
    local elite = { [611] = true, [612] = false }
    local npcs = {
        [9101] = { name = "Boar", spawns = { [40] = { { 60, 50 } } } },
        [9201] = { name = "Marshal", friendlyToFaction = "AH", spawns = { [40] = { { 52, 50 } } } },
    }
    local db = { QuestPointers = {} }
    for id in pairs(quests) do db.QuestPointers[id] = true end
    function db.GetQuest(id) return quests[id] end
    function db.GetNPC(id) return npcs[id] end
    function db.IsGroupQuest(id)
        if id == 613 then error("no tag yet") end
        return elite[id]
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [40] = MAP })[area] end
    return db, zones
end

local LOG = { { id = 401, title = "Boars", objectives = { { text = "Boars slain: 0/4" } } } }

local function boot(grouped)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setRaceId(1); c.setFaction("Alliance"); c.setLevel(18)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 0)
    c.setGrouped(grouped)
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

tests["quest hold: the setting row defaults on"] = function(t)
    local _, addon = boot(false)
    t.eq(addon.settings:get(ns.Nav.QuestHold.SETTING), true)
    t.eq(addon.use("questHold").On(), true)
end

tests["quest hold: solo, an elite pick-up is held; plain and unknown-tag ones are not"] = function(t)
    local c = boot(false)
    route(c)
    t.ok(said(c, "Ogre Den") == nil, "the elite quest is held")
    t.ok(said(c, "Pick up: Old Mill (Marshal)") ~= nil, "a plain quest is offered")
    t.ok(said(c, "Pick up: Odd Rumor (Marshal)") ~= nil, "an unknown tag is not held")
end

tests["quest hold: grouped, the elite pick-up is offered"] = function(t)
    local c = boot(true)
    route(c)
    t.ok(said(c, "Pick up: Ogre Den (Marshal)") ~= nil, "grouped: not held")
end

tests["quest hold: setting off, the elite pick-up is offered"] = function(t)
    local c, addon = boot(false)
    addon.settings:set(ns.Nav.QuestHold.SETTING, false)
    t.eq(addon.use("questHold").On(), false)
    route(c)
    t.ok(said(c, "Pick up: Ogre Den (Marshal)") ~= nil, "off: not held")
end

tests["quest hold: solo, a hard quest in the log is held through the module"] = function(t)
    local _, addon = boot(false)
    local H = addon.use("questHold")
    t.eq((H.Held({ level = 21, elite = false, myLevel = 18 })), true)
    t.eq((H.Held({ level = 18, elite = true, myLevel = 18 })), true)
    t.eq((H.Held({ level = 18, elite = nil, myLevel = 18 })), false)
end

return tests
