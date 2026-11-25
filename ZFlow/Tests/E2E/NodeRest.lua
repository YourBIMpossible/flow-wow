local _, ns = ...

-- End to end (lead section 481, parity row A1-21): of the nodes you
-- gathered, one you just looted rests and one you stood at with nothing on
-- it is skipped; Next() goes on to the next nearest. On the whole add-on
-- with a fake client; made-up nodes. Not tested in game.
-- Fails before: there is no nodeRest module, so nothing rests.

local tests = {}

local MAP = 1411
local NODES = {
    { x = 0.5, y = 0.5, id = 1618, name = "Peacebloom", prof = "Herbalism", n = 1, at = 1 },
    { x = 0.6, y = 0.5, id = 1617, name = "Silverleaf", prof = "Herbalism", n = 1, at = 1 },
}

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { learned = { nodes = { [MAP] = NODES } } })
    c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setLevel(20)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 500)
    c.setProfessions({ "Herbalism" })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(1, 2)
    return c, addon
end

local function nextName(addon)
    local mod = addon.use("nodeRest")
    local r = mod and mod.Next()
    return r and r.node and r.node.name or nil
end

tests["node rest e2e: the nearest node first, a looted one rests"] = function(t)
    local c, addon = boot()
    t.eq(nextName(addon), "Peacebloom")
    c.fire("LOOT_OPENED")
    t.eq(nextName(addon), "Silverleaf", "the looted node rests")
    c.advance(ns.Nav.NodeRest.REST + 1, 10)
    t.eq(nextName(addon), "Peacebloom", "grown back")
end

tests["node rest e2e: standing at an empty node skips it"] = function(t)
    local c, addon = boot()
    c.advance(2, 2)
    t.eq(nextName(addon), "Peacebloom", "not long enough yet")
    c.advance(4, 4)
    t.eq(nextName(addon), "Silverleaf", "nothing there: on to the next")
end

-- Zen's review of 9f6d556e (lead section 606), as Flow Nav.lua:4551: no
-- watching in combat. Standing by a node in a fight says nothing about it.
-- Fails before: five seconds by the node in combat rests it.
tests["node rest e2e: standing at a node in combat does not rest it"] = function(t)
    local c, addon = boot()
    c.setCombat(true)
    c.advance(5, 5)
    t.eq(nextName(addon), "Peacebloom", "in combat: not watched, so not resting")
    c.setCombat(false)
    c.advance(2, 2)
    t.eq(nextName(addon), "Peacebloom", "combat over: the watch starts again from nothing")
    c.advance(4, 4)
    t.eq(nextName(addon), "Silverleaf", "then four seconds out of combat skip it, as before")
end

tests["node rest e2e: a node far away is never rested by standing"] = function(t)
    local c, addon = boot()
    c.setPosition(MAP, 0.3, 0.5)
    c.advance(10, 10)
    t.eq(nextName(addon), "Peacebloom")
end

tests["node rest e2e: the pure reads"] = function(t)
    local NR = ns.Nav.NodeRest
    t.eq(NR.Empty(14, 0, 4), true)
    t.eq(NR.Empty(16, 0, 10), false)
    t.eq(NR.Resting({ a = 100 }, "a", 100 + NR.REST), false)
    t.eq(NR.Resting({ a = 100 }, "a", 101), true)
end

return tests
