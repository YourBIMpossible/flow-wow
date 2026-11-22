local _, ns = ...
-- S37 "before leaving a zone" (Nav/Leaving.lua), LEDGER 143. Ported from
-- legacy Flow's test "route: finish this zone before leaving it"
-- (Modules/Tests.lua, N.AreaSplit), plus what Z-Flow's places add: a
-- distance across maps is known only through the zone link, and an unknown
-- one never counts as near (F-086).
local N = ns.Nav

-- Map id = zone, as in Flow's test.
local function zoneOf(map) return map end

-- A zone link where maps 1 and 2 sit side by side, 1000 x 1000 yards each:
-- map 2's origin is 1000 yards east of map 1's.
local LINK = {
    [1] = { x = 0, y = 0, w = 1000, h = 1000 },
    [2] = { x = 1000, y = 0, w = 1000, h = 1000 },
}

-- The player stands at the east edge of map 1 (x = 0.999 -> 999 yards east).
local PLAYER = { map = 1, x = 0.999, y = 0.5 }

local function stop(key, map, x, extra)
    local s = { key = key, quest = true, places = { { map = map, x = x, y = 0.5 } } }
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
end

local function list()
    return {
        stop("10", 1, 0.5), stop("11", 1, 0.9),
        stop("12", 1, 0.3, { levelsAbove = 4 }), stop("13", 1, 0.3, { share = 0.6 }),
        stop("20", 2, 0.9),                                   -- deep in the next zone
        stop("21", 2, 0.05),                                  -- 51 yards over the border
        stop("train:class", 2, 0.95, { milestone = true, quest = false }),
        stop("14", 1, 0.6, { deps = { "22" } }), stop("22", 2, 0.8),
    }
end

local T = {}

T["this zone's quests hold you here; the next zone's stop waits"] = function(t)
    local here, away = N.LeavingSplit(list(), 1, PLAYER, zoneOf, LINK)
    t.ok(here and here["10"] and here["11"], "this zone's quests hold you here")
    t.ok(away and away["20"], "the next zone's stop waits")
end

T["too high, too low and optional quests do not hold you here"] = function(t)
    local l = list()
    l[#l + 1] = stop("15", 1, 0.4, { optional = true })
    local here = N.LeavingSplit(l, 1, PLAYER, zoneOf, LINK)
    t.ok(not here["12"], "3+ levels above: does not hold you")
    t.ok(not here["13"], "too low for full XP: does not hold you")
    t.ok(not here["15"], "optional: does not hold you")
end

T["a stop just over the border and the class trainer do not wait"] = function(t)
    local _, away = N.LeavingSplit(list(), 1, PLAYER, zoneOf, LINK)
    t.ok(not away["21"], "51 yards over the border (under N.LEAVING_BRIEF): a short trip, it does not wait")
    t.ok(not away["train:class"], "a milestone does not wait")
end

T["a stop here that needs one over there first cannot hold you"] = function(t)
    local here, away = N.LeavingSplit(list(), 1, PLAYER, zoneOf, LINK)
    t.ok(not here["14"] and away["14"], "it waits with what it depends on")
end

T["dependencies are followed until nothing changes"] = function(t)
    local l = { stop("a", 1, 0.5, { deps = { "b" } }), stop("b", 1, 0.6, { deps = { "x" } }), stop("x", 2, 0.9),
        stop("c", 1, 0.4) }
    local here, away = N.LeavingSplit(l, 1, PLAYER, zoneOf, LINK)
    t.ok(away["b"] and away["a"], "b waits for x, so a waits for b")
    t.ok(here["c"], "c still holds you here")
end

T["nowhere else to go, or nothing here: no rule"] = function(t)
    local here, away, why = N.LeavingSplit({ stop("10", 1, 0.5) }, 1, PLAYER, zoneOf, LINK)
    t.eq({ here, away, why }, { nil, nil, "nothing away" }, "only this zone")
    here, away, why = N.LeavingSplit({ stop("20", 2, 0.9) }, 1, PLAYER, zoneOf, LINK)
    t.eq({ here, away, why }, { nil, nil, "nothing here" }, "only the next zone")
end

T["an unknown zone gives no rule"] = function(t)
    local here, away, why = N.LeavingSplit(list(), nil, PLAYER, zoneOf, LINK)
    t.eq({ here, away, why }, { nil, nil, "no zone" })
end

T["F-086: with no zone link the distance is not known, and the border stop waits"] = function(t)
    local _, away = N.LeavingSplit(list(), 1, PLAYER, zoneOf, nil)
    t.ok(away["21"], "51 yards in fact, but not known: never taken as near")
    local _, away2 = N.LeavingSplit(list(), 1, nil, zoneOf, LINK)
    t.ok(away2["21"], "player position not known: the same")
    local partial = { [1] = LINK[1], [2] = { x = 1000, y = 0 } }   -- map 2 has no size
    local _, away3 = N.LeavingSplit(list(), 1, PLAYER, zoneOf, partial)
    t.ok(away3["21"], "a map with no size in the link: not known")
end

T["only quest stops hold you here; a stop with no place neither holds nor waits"] = function(t)
    local l = { stop("10", 1, 0.5), stop("vendor", 1, 0.2, { quest = false }), stop("20", 2, 0.9),
        { key = "lost", quest = true, places = {} } }
    local here, away = N.LeavingSplit(l, 1, PLAYER, zoneOf, LINK)
    t.ok(here["10"] and not here["vendor"], "a vendor here does not hold you")
    t.ok(not here["lost"] and not away["lost"], "no place: neither")
end

T["zoneOf relates a town map to its zone"] = function(t)
    local function townZone(map) return ({ [101] = 1, [1] = 1, [2] = 2 })[map] end
    local l = { stop("town", 101, 0.5), stop("20", 2, 0.9) }
    local here = N.LeavingSplit(l, 1, PLAYER, townZone, LINK)
    t.ok(here and here["town"], "a stop on a town map of this zone holds you here")
end

T["the inputs are not changed"] = function(t)
    local l = list()
    local before = #l
    N.LeavingSplit(l, 1, PLAYER, zoneOf, LINK)
    t.eq(#l, before, "the list keeps its length")
    t.eq(l[8].deps, { "22" }, "a stop keeps its deps")
    t.eq(PLAYER, { map = 1, x = 0.999, y = 0.5 }, "the player is not changed")
end

T["LeavingHold hands on what goes now, in order, without the waiting stops"] = function(t)
    local l = list()
    local _, away = N.LeavingSplit(l, 1, PLAYER, zoneOf, LINK)
    local now = N.LeavingHold(l, away)
    local keys = {}
    for i, s in ipairs(now) do keys[i] = s.key end
    t.eq(keys, { "10", "11", "12", "13", "21", "train:class" }, "the waiting stops are held back")
    t.eq(#N.LeavingHold(l, nil), #l, "no rule: everything goes now")
end

T["the step and the waiting text"] = function(t)
    t.eq(N.LeavingStep("Elwynn Forest"), { label = "Finishing Elwynn Forest first", text = true })
    local step, why = N.LeavingStep(nil)
    t.eq({ step, why }, { { label = "Finishing this zone first", text = true }, "zone name unknown" })
    t.eq(N.LeavingWaits("Westfall"), "(Westfall, after this zone)")
    t.eq(N.LeavingWaits(nil), "(after this zone)")
end

T["the step label stays within the waypoint label limit"] = function(t)
    local long = string.rep("A", 60)
    local step = N.LeavingStep(long)
    t.ok(#step.label <= N.Waypoint.LABEL_MAX, "never over the limit (got " .. #step.label .. ")")
    t.eq(step.label, "Finishing this zone first", "too long: the plain label, never cut")
end

T["the constants Flow used"] = function(t)
    t.eq(N.LEAVING_BRIEF, 150, "yards for a brief trip over the border")
    t.eq(N.LEAVING_SETTING, "nav.zoneFirst", "the setting row (the lead adds it; on by default)")
end

T["the reason is for diagnostics only: no player text carries it"] = function(t)
    local step, why = N.LeavingStep(nil)
    t.eq(why, "zone name unknown", "the reason comes back as a second value")
    t.ok(not step.label:find("unknown", 1, true), "the label shown to the player never says unknown")
    t.ok(not N.LeavingWaits(nil):find("unknown", 1, true), "nor the waiting text")
    t.eq(step.reason, nil, "the step table carries no reason field a caller could show")
end

return T