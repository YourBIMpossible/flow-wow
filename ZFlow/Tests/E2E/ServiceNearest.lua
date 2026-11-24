local _, ns = ...

-- The nearest service seen (G36, Nav/ServiceNearest.lua), on the whole
-- add-on loaded on a fake client. The real entry: worn gear turns the
-- repair warning on, and the arrow's repair stop (Nav/RepairStep.lua) asks
-- N.Nearest("repair") for the smith to point at, from this character's
-- saved places ("learned.places.services") and the client's position and
-- map size. Made-up places and names. Not tested in game.
--
-- Map 1411 is 1000 x 200 yards, so the nearest by yards is not the nearest
-- by shares of the map. The player at (0.5, 0.5):
--   Near Smith (0.5, 0.9): 0.4 of the map north-south, 80 yards
--   Side Smith (0.6, 0.5): 0.1 of the map east-west, 100 yards
--   Other Smith on map 1420 at the player's own shares: never chosen.

local tests = {}
local RS = ns.RepairStep

local MAP, OTHER = 1411, 1420

local function questie()
    local db = {}
    function db.GetQuest(id)
        if id == 303 then return { ObjectiveData = { { Type = "monster", Id = 9002 } } } end
    end
    function db.GetNPC(id)
        if id == 9002 then return { name = "Near Wolf", spawns = { [12] = { { 90, 50 } } } } end
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [12] = MAP })[area] end
    return db, zones
end

local function place(name, map, x, y, kinds)
    return { name = name, map = map, x = x, y = y, kinds = kinds or { repair = true }, seen = 10, n = 1 }
end

local ALL = {
    a = place("Side Smith", MAP, 0.6, 0.5),
    b = place("Near Smith", MAP, 0.5, 0.9),
    c = place("Other Smith", OTHER, 0.5, 0.5),
}

-- opts.services: the saved places; opts.noSize: the map size not known.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, { learned = { places = { services = opts.services or ALL } } })
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    if not opts.noSize then c.setMapSize(MAP, 1000, 200) end
    c.setMapCont(MAP, 1)
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setLevel(20)
    c.setDurability({ [5] = { cur = 5, max = 100 } })
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog({ { id = 303, title = "Wolves", objectives = { { text = "Wolves slain: 0/4" } } } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function lines(c)
    local a = c.arrows[1]
    return a and a.lines or {}
end

local function hasPrefix(list, prefix)
    for _, l in ipairs(list) do
        if type(l) == "string" and l:sub(1, #prefix) == prefix then return true end
    end
    return false
end

tests["nearest service: the smith nearest in yards, on the player's map"] = function(t)
    local c = boot()
    t.eq(lines(c)[1], RS.LABEL .. ": Near Smith")
    t.ok(hasPrefix(lines(c), "80 yd"), "80 yards to it")
end

tests["nearest service: a smith on another map is never chosen"] = function(t)
    local c = boot({ services = { c = place("Other Smith", OTHER, 0.5, 0.5) } })
    t.eq(lines(c)[1], "Wolves", "the quest, not the far smith")
    t.ok(not hasPrefix(lines(c), RS.LABEL), "no repair line")
end

tests["nearest service: a place of another kind is not a smith"] = function(t)
    local c = boot({ services = { v = place("Bread Seller", MAP, 0.51, 0.5, { vendor = true }) } })
    t.eq(lines(c)[1], "Wolves")
    t.ok(not hasPrefix(lines(c), RS.LABEL), "no repair line")
end

tests["nearest service: a smith with no name is the plain stop"] = function(t)
    local c = boot({ services = { m = place(nil, MAP, 0.6, 0.5) } })
    t.eq(lines(c)[1], RS.LABEL)
end

tests["nearest service: unknown data says nothing wrong"] = function(t)
    -- The map size not known: nearest by shares of the map, no yards made up.
    local c = boot({ noSize = true })
    t.eq(lines(c)[1], RS.LABEL .. ": Side Smith", "by shares")
    t.ok(not hasPrefix(lines(c), "80 yd"), "no yards from an unknown size")
    -- A saved place with no position: skipped, the next one is chosen.
    c = boot({ services = { a = { name = "Lost Smith", map = MAP, kinds = { repair = true } },
                            b = place("Near Smith", MAP, 0.5, 0.9) } })
    t.eq(lines(c)[1], RS.LABEL .. ": Near Smith", "the known one")
end

return tests
