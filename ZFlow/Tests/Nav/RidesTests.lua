-- Rides (S33): N.RideStep over hand-written tables. Ported from legacy Flow
-- 0.35.377 Modules/Nav/Rides.lua. Made-up npc places, test only. Not
-- tested in game.
local _, ns = ...

local N = ns.Nav

local MOONGLADE, TB = 1450, 1456
local IN_MOONGLADE = { position = { map = MOONGLADE, x = 0.5, y = 0.5 } }
local STEP_TB = { map = TB, x = 0.4, y = 0.4 }

local T = {}

T["data: the two druid rides as legacy Flow has them"] = function(t)
    local by = {}
    for _, r in ipairs(N.RIDES) do by[r.name] = r end
    t.eq(by["Bunthen Plainswind"].from, MOONGLADE)
    t.eq(by["Bunthen Plainswind"].faction, "Horde")
    t.eq(by["Bunthen Plainswind"].how, "he flies druids to Thunder Bluff, free")
    t.eq(by["Silva Fil'naveth"].faction, "Alliance")
    t.eq(by["Silva Fil'naveth"].class, "DRUID")
    t.eq(by["Bunthen Plainswind"].land, nil, "legacy landing coordinates are not ported")
end

T["ride: out of Moonglade for a Horde druid"] = function(t)
    local step, why = N.RideStep(N.RIDES, STEP_TB, IN_MOONGLADE, "DRUID", "Horde", {})
    t.eq(why, nil)
    t.eq(step, { label = "Talk to Bunthen Plainswind", text = true, ride = "Bunthen Plainswind",
                 detail = "he flies druids to Thunder Bluff, free" })
end

T["ride: the npc's place comes only from learned places on this map"] = function(t)
    local npcs = { ["Bunthen Plainswind"] = { map = MOONGLADE, x = 0.44, y = 0.45 } }
    local step = N.RideStep(N.RIDES, STEP_TB, IN_MOONGLADE, "DRUID", "Horde", npcs)
    t.eq(step.point, { map = MOONGLADE, x = 0.44, y = 0.45 })
    npcs["Bunthen Plainswind"] = { map = 1411, x = 0.44, y = 0.45 }
    t.eq(N.RideStep(N.RIDES, STEP_TB, IN_MOONGLADE, "DRUID", "Horde", npcs).point, nil, "another map: no point")
    npcs["Bunthen Plainswind"] = { map = MOONGLADE, x = 2, y = 0.45 }
    t.eq(N.RideStep(N.RIDES, STEP_TB, IN_MOONGLADE, "DRUID", "Horde", npcs).point, nil, "x out of 0..1: no point")
end

T["no ride: other faction, other class, unknown class or faction"] = function(t)
    local function why(class, faction) return select(2, N.RideStep(N.RIDES, STEP_TB, IN_MOONGLADE, class, faction, {})) end
    t.eq(N.RideStep(N.RIDES, STEP_TB, IN_MOONGLADE, "DRUID", "Alliance", {}).ride, "Silva Fil'naveth", "Alliance gets their own")
    t.eq(why("MAGE", "Horde"), "no ride")
    t.eq(why(nil, "Horde"), "class unknown")
    t.eq(why("DRUID", nil), "faction unknown")
end

T["no ride: step in the same zone, player elsewhere, no target, position unknown"] = function(t)
    local function why(target, here) return select(2, N.RideStep(N.RIDES, target, here, "DRUID", "Horde", {})) end
    t.eq(why({ map = MOONGLADE, x = 0.1, y = 0.1 }, IN_MOONGLADE), "same map")
    t.eq(why(STEP_TB, { position = { map = 1411, x = 0.5, y = 0.5 } }), "no ride")
    t.eq(why({ x = 0.5 }, IN_MOONGLADE), "no target")
    t.eq(why(STEP_TB, {}), "position unknown")
end

return T
