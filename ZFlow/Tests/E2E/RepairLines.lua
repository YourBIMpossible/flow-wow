local _, ns = ...
-- The repair warning's chat line (Items/Repair.lua) taking the repair
-- step's words (Nav/RepairStep.lua, RS.Lines), on the whole add-on loaded
-- on a fake client: a player whose gear is worn and who has seen a repair
-- vendor on this map is told that vendor and how far, not "No repair
-- vendor is known yet." With none seen, the warning's own words stand.
-- Look only: nothing repairs. Made-up places and names. Not tested in game.
--
-- Map 1411 is 1000 x 1000 yards; the player at (0.1, 0.5), the smith at
-- (0.2, 0.5), 100 yards east.
local tests = {}

local MAP, SMITH = 1411, "Test Smith"
local LOW = { [5] = { cur = 5, max = 100 } }

local function boot(char)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, char)
    c.setZone(1, MAP); c.setPosition(MAP, 0.1, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 1)
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setLevel(20)
    c.setDurability(LOW)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function seenSmith()
    return { learned = { places = { services = {
        s1 = { name = SMITH, map = MAP, x = 0.2, y = 0.5, kinds = { repair = true }, seen = 10, n = 1 },
    } } } }
end

local function warningLine(c)
    for _, line in ipairs(c.printed or {}) do
        if tostring(line):find("An item you wear is at", 1, true) then return tostring(line) end
    end
    return nil
end

tests["repair lines: a smith seen on this map is named in the warning, with the distance"] = function(t)
    local c = boot(seenSmith())
    local line = warningLine(c)
    t.ok(line ~= nil, "the warning is said")
    t.ok(line and line:find("Nearest repair vendor you have seen: " .. SMITH .. ", about 100 yd.", 1, true) ~= nil,
        "the smith and the distance")
    t.ok(line and line:find(ns.Repair.NO_VENDOR, 1, true) == nil, "not told that none is known")
end

tests["repair lines: the warning is said once, not again while the gear stays low"] = function(t)
    local c = boot(seenSmith())
    c.setPosition(MAP, 0.15, 0.5)
    c.fire("UPDATE_INVENTORY_DURABILITY")
    c.advance(1, 4)
    local n = 0
    for _, line in ipairs(c.printed or {}) do
        if tostring(line):find("An item you wear is at", 1, true) then n = n + 1 end
    end
    t.eq(n, 1)
end

tests["repair lines: no smith seen keeps the warning's own words"] = function(t)
    local c = boot({})
    local line = warningLine(c)
    t.ok(line ~= nil, "the warning is said")
    t.ok(line and line:find(ns.Repair.NO_VENDOR, 1, true) ~= nil, "none known yet")
    t.ok(line and line:find("Nearest repair vendor you have seen", 1, true) == nil)
end

tests["repair lines: the repair step off still names the smith seen in the warning"] = function(t)
    -- nav.repairStep turns the arrow step off, never the warning.
    local c = ns.make.fakeClient()
    local addon
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, seenSmith())
    c.setZone(1, MAP); c.setPosition(MAP, 0.1, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 1)
    c.setDurability({ [5] = { cur = 100, max = 100 } })
    addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(2, 8)
    addon.settings:set(ns.RepairStep.SETTING, false)
    c.setDurability(LOW)
    c.fire("UPDATE_INVENTORY_DURABILITY")
    c.advance(1, 4)
    local line = warningLine(c)
    t.ok(line and line:find(SMITH, 1, true) ~= nil, "the warning names the smith")
end

return tests
