local _, ns = ...

-- The repair stop on the quest arrow (S6, Nav/RepairStep.lua), on the
-- whole add-on loaded on a fake client. The real entry: worn gear read on
-- entering the world (Items/Repair.lua) turns the warning on; the arrow
-- asks ns.use("repairStep").Step, which points at the nearest repair
-- vendor this character has seen ("learned.places.services"), ahead of
-- the quest. Look only: nothing repairs. Made-up places and names. Not
-- tested in game.
--
-- Map 1411 is 1000 x 1000 yards; the player at (0.1, 0.5), the smith at
-- (0.2, 0.5), 100 yards east; the wolves at (0.9, 0.5).

local tests = {}
local RS = ns.RepairStep

local MAP, SMITH = 1411, "Test Smith"

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

local function seen(services)
    return { learned = { places = { services = services } } }
end

local function smith(x)
    return { s1 = { name = SMITH, map = MAP, x = x, y = 0.5, kinds = { repair = true }, seen = 10, n = 1 } }
end

local LOW = { [5] = { cur = 5, max = 100 } }
local FINE = { [5] = { cur = 100, max = 100 } }

-- opts.char: the character table; opts.durability: the readings (nil: not read).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, opts.char or seen(smith(0.2)))
    c.setZone(1, MAP); c.setPosition(MAP, 0.1, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 1)
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setLevel(20)
    c.setDurability(opts.durability)
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

local function said(c, text)
    for _, line in ipairs(c.printed or {}) do
        if tostring(line):find(text, 1, true) then return true end
    end
    return false
end

tests["repair step: worn gear points at the smith seen, ahead of the quest"] = function(t)
    local c = boot({ durability = LOW })
    t.ok(said(c, "An item you wear is at 5% durability"), "the warning is said")
    t.eq(c.arrows[1] and c.arrows[1].shown, true, "the quest arrow is shown")
    t.eq(lines(c)[1], RS.LABEL .. ": " .. SMITH)
    t.ok(hasPrefix(lines(c), "100 yd"), "the distance to the smith")
end

tests["repair step: repaired gear gives the quest back"] = function(t)
    local c = boot({ durability = LOW })
    t.eq(lines(c)[1], RS.LABEL .. ": " .. SMITH, "low first")
    c.setDurability(FINE)
    c.fire("UPDATE_INVENTORY_DURABILITY")
    c.advance(10, 40)
    t.eq(lines(c)[1], "Wolves", "fine: the quest")
    t.ok(not hasPrefix(lines(c), RS.LABEL), "no repair line")
end

tests["repair step: the setting off drops the step"] = function(t)
    local c, addon = boot({ durability = LOW })
    t.eq(lines(c)[1], RS.LABEL .. ": " .. SMITH, "on first")
    addon.settings:set(RS.SETTING, false)
    c.advance(10, 40)
    t.eq(lines(c)[1], "Wolves", "off: the quest")
    addon.settings:set(RS.SETTING, true)
    c.advance(10, 40)
    t.eq(lines(c)[1], RS.LABEL .. ": " .. SMITH, "on again")
end

tests["repair step: no smith seen gives no step, only the warning"] = function(t)
    local c = boot({ durability = LOW, char = {} })
    t.ok(said(c, "An item you wear is at 5% durability"), "the warning is said")
    t.eq(lines(c)[1], "Wolves")
    t.ok(not hasPrefix(lines(c), RS.LABEL), "no repair line")
end

tests["repair step: unknown data says nothing wrong"] = function(t)
    -- Durability not read: never taken as worn.
    local c = boot({ durability = nil })
    t.eq(lines(c)[1], "Wolves", "durability unknown")
    t.ok(not hasPrefix(lines(c), RS.LABEL), "no repair line")
    t.ok(not said(c, "An item you wear is at"), "no warning said")
    -- The smith's place not known: no place is made up.
    c = boot({ durability = LOW, char = seen({ s1 = { name = SMITH, map = MAP, y = 0.5, kinds = { repair = true } } }) })
    t.eq(lines(c)[1], "Wolves", "place unknown")
    t.ok(not hasPrefix(lines(c), RS.LABEL), "no repair line")
end

return tests
