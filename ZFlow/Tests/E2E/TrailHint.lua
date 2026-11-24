local _, ns = ...

-- End to end (G38, lead dispatch section 391 item 3 / section 395): the
-- whole add-on loaded the way the game loads it (ns.offline.addon), on a
-- fake client. The player walks into a made-up cave on map 1411 (1000 x
-- 500 yards), comes out, sets a waypoint inside it, and the quest arrow
-- says in plain words to follow the path walked; from far away it says to
-- walk to the entrance first. Not tested in game. Look only.

local tests = {}
local MAP = 1411

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, {})
    c.setScreen(1024, 768)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 500); c.setMapCont(MAP, 1)
    c.setClass("WARRIOR"); c.setFaction("Horde")
    c.setIndoors(false)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function at(c, x, y)
    c.setPosition(MAP, x / 1000, y / 500)
    c.advance(1.1, 2)
end

local function walkIn(c)
    for x = 500, 548, 12 do at(c, x, 250) end
    c.setIndoors(true)
    at(c, 548, 250)
    for y = 238, 190, -12 do at(c, 548, y) end
    c.setIndoors(false)
    at(c, 548, 190)
end

local function says(c, text)
    local a = c.arrows[1]
    for _, l in ipairs(type(a) == "table" and a.lines or {}) do
        if l == text then return true end
    end
    return false
end

tests["trail hint e2e: the arrow says to follow the cave path, or to walk to the entrance"] = function(t)
    local c = start()
    local T = ns.Nav.Trails
    walkIn(c)
    at(c, 500, 250)
    c.slashes[ns.id.slash]("way 54.8 38")
    c.advance(2, 8)
    t.eq(c.arrows[1].shown, true)
    t.ok(says(c, T.ON_TRAIL), "on the trail: " .. table.concat(c.arrows[1].lines or {}, " | "))
    at(c, 100, 250)
    c.advance(2, 8)
    t.ok(says(c, T.TO_ENTRANCE), "far away: " .. table.concat(c.arrows[1].lines or {}, " | "))
    t.ok(not says(c, T.ON_TRAIL), "the follow line is gone")
end

return tests
