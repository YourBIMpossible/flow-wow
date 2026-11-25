local _, ns = ...

-- End to end (lead section 708, Twin's CHANGES-1 item 1): Nav/DungeonFirst.lua
-- loads through the manifest with the whole add-on, and its two rules are
-- reached from the booted add-on's own table. Made-up stops; not tested in
-- game.

local tests = {}

tests["dungeon first e2e: the module loads with the add-on and its rules answer"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    local DF
    if type(addon.Nav) == "table" then DF = addon.Nav.DungeonFirst end
    t.ok(type(DF) == "table", "loaded through the manifest")
    if type(DF) ~= "table" then return end
    local route = { { label = "Boars", quest = 1 }, { label = "Herbs", quest = 2 } }
    local run = { { label = "Pick up: Silk", kind = "giver", quest = 9 }, { label = "Mines", kind = "entrance" } }
    local first = DF.First(route, run)
    t.eq(first[1].label, "Pick up: Silk")
    t.eq(first[3].label, "Boars")
    local inside = DF.Inside(route, function(id) return ({ [2] = 5 })[id] end, 5, true)
    t.eq(#inside, 1)
    t.eq(inside[1].label, "Herbs")
end

return tests
