local _, ns = ...

-- Parity row A1-27 (lead section 488): the zone filter, selected zones
-- first. Pure order and words, and the zoneFilter module on the whole
-- add-on with a fake client (the picks kept per character; the settings
-- row held back, lead section 507). Made-up zones. Not tested in game.
-- Fails before: there is no Nav/ZoneFilter.lua.

local tests = {}

local function stop(label, zone) return { label = label, zone = zone } end
local function zoneOf(s) return s.zone end
local function labels(list)
    local out = {}
    for i, s in ipairs(list) do out[i] = s.label end
    return table.concat(out, ",")
end
local STOPS = { stop("a", 1), stop("b", 2), stop("c", 1), stop("d", 3), stop("e", nil) }

tests["zone filter: nothing picked, every stop stays in its order"] = function(t)
    local ZF = ns.Nav.ZoneFilter
    local ordered, summary, left = ZF.Order(STOPS, nil, false, zoneOf)
    t.eq(labels(ordered), "a,b,c,d,e")
    t.eq(left, 0)
    t.eq(summary[1].zone, 1, "most steps first")
    t.eq(summary[1].steps, 2)
end

tests["zone filter: off, a zone not picked is left out; a stop with no zone stays"] = function(t)
    local ZF = ns.Nav.ZoneFilter
    local ordered, summary, left = ZF.Order(STOPS, { [1] = true }, false, zoneOf)
    t.eq(labels(ordered), "a,c,e")
    t.eq(left, 2)
    local names = { "The Barrens", "Stonetalon Mountains", "Ashenvale" }
    local function nameOf(z) return names[z] end
    t.eq(ZF.Line(summary[1], nameOf), "The Barrens: 2 steps")
    t.eq(ZF.Line(summary[2], nameOf), "Stonetalon Mountains: 1 step - LEFT OUT")
end

tests["zone filter: on, the picked zones come first and the others after"] = function(t)
    local ZF = ns.Nav.ZoneFilter
    local ordered, summary, left = ZF.Order(STOPS, { [1] = true, [3] = true }, true, zoneOf)
    t.eq(labels(ordered), "a,c,d,e,b")
    t.eq(left, 0)
    local later
    for _, z in ipairs(summary) do if z.zone == 2 then later = z end end
    t.eq(ZF.Line(later, function() return "Ashenvale" end), "Ashenvale: 1 step - after your zones")
end

tests["zone filter: an empty pick table is not picked yet: every zone is yours"] = function(t)
    local ZF = ns.Nav.ZoneFilter
    local ordered, _, left = ZF.Order(STOPS, {}, false, zoneOf)
    t.eq(labels(ordered), "a,b,c,d,e", "as with nil")
    t.eq(left, 0)
end

tests["zone filter e2e: picks are kept; the module orders by them; the row is held back"] = function(t)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setLevel(10)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(2, 8)
    local ZF = ns.Nav.ZoneFilter
    -- Lead section 541: the row is back, with the route that reads it
    -- (Tests/E2E/TripRouteZones.lua).
    t.ok(addon.settings:row(ZF.SETTING) ~= nil, "the settings row ships with the route's hook")
    local mod = addon.use("zoneFilter")
    t.eq(mod.First(), false, "off by default: left out, not after")
    t.eq(mod.Selected(), nil, "nothing picked yet")
    t.ok(mod.SetZoneOn(2, true), "pick zone 2")
    t.eq(mod.Selected(), { [2] = true })
    t.eq(labels((mod.Order(STOPS, zoneOf))), "b,e", "only zone 2 and the stop with no zone")
    t.ok(mod.SetZoneOn(2, false), "unpick")
    t.eq(mod.Selected(), nil, "an empty pick is not picked yet")
    t.eq(labels((mod.Order(STOPS, zoneOf))), "a,b,c,d,e", "every zone again")
end

return tests
