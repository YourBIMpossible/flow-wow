-- Crossing to another continent (S32), over hand-written places. No game
-- client is involved and no place here is a real one.
local _, ns = ...

local N = ns.Nav

-- Two made-up continents, 7 and 8. Map 70 and 71 are on 7; 80 and 81 on 8.
local SIZES = { [70] = { w = 1000, h = 1000 }, [71] = { w = 2000, h = 1000 }, [80] = { w = 1000, h = 500 } }
local function mapSize(map) return SIZES[map] end
local function at(cont, map, x, y, name) return { cont = cont, map = map, x = x, y = y, name = name } end

local function given()
    return {
        { key = "north", how = "zeppelin", faction = "Horde",
          a = at(7, 70, 0.5, 0.1, "Tower"), b = at(8, 80, 0.2, 0.2, "Far Tower") },
        { key = "south", how = "boat",
          a = at(7, 70, 0.5, 0.9, "Dock"), b = at(8, 80, 0.8, 0.8, "Far Dock") },
    }
end

return {
    ["the numbers are the ones legacy used"] = function(t)
        t.eq(N.CROSSING_WEIGHT, 2.5)
        t.eq(N.CROSSING_NEAR, 250)
        t.eq(N.CROSSING_CLOSE, 800)
        t.eq(N.CROSSING_W_NOW, 0.5)
        t.eq(N.CROSSING_W_NEAR, 1.1)
        t.eq(N.CROSSING_PLACES, "learned.places.crossings")
        t.eq(N.CROSSING_SETTING, "nav.crossings")
    end,

    ["apart: yards on one map, not known across maps"] = function(t)
        local apart = N.CrossingApart(mapSize)
        t.eq(apart(at(7, 70, 0.1, 0.5), at(7, 70, 0.4, 0.5)), 300)
        t.eq(apart(at(7, 71, 0.1, 0.5), at(7, 71, 0.4, 0.5)), 600, "the width of that map")
        t.eq(apart(at(7, 70, 0.1, 0.5), at(7, 71, 0.4, 0.5)), nil, "two maps: not known, never guessed")
        t.eq(apart(at(8, 81, 0.1, 0.5), at(8, 81, 0.4, 0.5)), nil, "size not known")
        t.eq(apart(at(7, 70, 0.1, 0.5), nil), nil)
        t.eq(apart(at(7, 70, 0.1, 0.5), { cont = 7, map = 70, x = 2, y = 0.5 }), nil, "not a share of the map")
        local broken = N.CrossingApart(function() error("no") end)
        t.eq(broken(at(7, 70, 0.1, 0.5), at(7, 70, 0.4, 0.5)), nil, "a size read that fails is not known")
    end,

    ["apart: world yards relate two maps of one continent"] = function(t)
        local apart = N.CrossingApart(mapSize)
        local a = { cont = 7, map = 70, x = 0.1, y = 0.5, wx = 100, wy = 200 }
        local b = { cont = 7, map = 71, x = 0.4, y = 0.5, wx = 400, wy = 600 }
        t.eq(apart(a, b), 500)
        b.cont = 8
        t.eq(apart(a, b), nil, "another continent")
    end,

    ["usable: your faction or anyone, both ends known, on two continents"] = function(t)
        local list = given()
        t.eq(N.CrossingUsable(list[1], "Horde"), true)
        t.eq(N.CrossingUsable(list[1], "Alliance"), false)
        t.eq(N.CrossingUsable(list[1], nil), false, "faction not known: not taken as yours")
        t.eq(N.CrossingUsable(list[2], "Alliance"), true)
        t.eq(N.CrossingUsable(list[2], nil), true)
        t.eq(N.CrossingUsable(nil, "Horde"), false)
        t.eq(N.CrossingUsable({ key = "x", a = at(7, 70, 0.5, 0.5) }, "Horde"), false, "one end only")
        t.eq(N.CrossingUsable({ key = "x", a = at(7, 70, 0.5, 0.5), b = at(7, 71, 0.5, 0.5) }, "Horde"), false, "one continent")
        t.eq(N.CrossingUsable({ key = "x", a = at(7, 70, 0.5, 0.5), b = at(nil, 80, 0.5, 0.5) }, "Horde"), false, "continent not known")
    end,

    ["usable: a trip seen once is not yet a crossing"] = function(t)
        local cr = { key = "seen:70:80", seen = 1, a = at(7, 70, 0.5, 0.5), b = at(8, 80, 0.5, 0.5) }
        t.eq(N.CrossingUsable(cr, "Horde"), false)
        cr.seen = N.CROSSING_SURE
        t.eq(N.CrossingUsable(cr, "Horde"), true)
        t.eq(N.CROSSING_SURE, 2)
    end,

    ["best: the crossing that makes the whole trip shortest"] = function(t)
        local apart = N.CrossingApart(mapSize)
        local me = at(7, 70, 0.5, 0.2)
        -- the step is beside the far dock: the walk to the tower is short but the far side is long
        local best = N.CrossingBest(given(), me, { at(8, 80, 0.8, 0.8) }, apart, "Horde")
        t.eq(best.key, "south")
        t.eq(best.from.name, "Dock")
        t.eq(best.to.name, "Far Dock")
        t.eq(best.toBoard, 700)
        t.eq(best.toStep, 0)
        t.eq(best.yards, 700)
        t.eq(best.toCont, 8)
        local other = N.CrossingBest(given(), me, { at(8, 80, 0.2, 0.2) }, apart, "Horde")
        t.eq(other.key, "north")
        t.eq(other.yards, 100)
    end,

    ["best: a crossing works both ways"] = function(t)
        local apart = N.CrossingApart(mapSize)
        local best = N.CrossingBest(given(), at(8, 80, 0.8, 0.8), { at(7, 70, 0.5, 0.9) }, apart, "Alliance")
        t.eq(best.key, "south")
        t.eq(best.from.name, "Far Dock")
        t.eq(best.to.name, "Dock")
        t.eq(best.toCont, 7)
    end,

    ["best: another faction's crossing is not offered"] = function(t)
        local apart = N.CrossingApart(mapSize)
        local best = N.CrossingBest(given(), at(7, 70, 0.5, 0.1), { at(8, 80, 0.2, 0.2) }, apart, "Alliance")
        t.eq(best.key, "south")
    end,

    ["best: none, and why"] = function(t)
        local apart = N.CrossingApart(mapSize)
        local best, why = N.CrossingBest(given(), { map = 70, x = 0.5, y = 0.5 }, { at(8, 80, 0.2, 0.2) }, apart, "Horde")
        t.eq(best, nil)
        t.eq(why, "position unknown")
        best, why = N.CrossingBest({}, at(7, 70, 0.5, 0.5), { at(8, 80, 0.2, 0.2) }, apart, "Horde")
        t.eq(best, nil)
        t.eq(why, "no crossings")
        best, why = N.CrossingBest(nil, at(7, 70, 0.5, 0.5), { at(8, 80, 0.2, 0.2) }, apart, "Horde")
        t.eq(why, "no crossings")
        best, why = N.CrossingBest(given(), at(7, 70, 0.5, 0.5), {}, apart, "Horde")
        t.eq(best, nil)
        t.eq(why, "no place to aim for")
        best, why = N.CrossingBest(given(), at(7, 70, 0.5, 0.5), { at(9, 90, 0.2, 0.2) }, apart, "Horde")
        t.eq(best, nil)
        t.eq(why, "no crossing joins")
    end,

    ["best: a distance that is not known is never taken as short"] = function(t)
        local apart = N.CrossingApart(mapSize)
        -- the player is on map 71: how far either boarding place is, is not known
        local me = at(7, 71, 0.5, 0.5)
        local best = N.CrossingBest(given(), me, { at(8, 80, 0.8, 0.8) }, apart, "Horde")
        t.eq(best.key, "south", "the far side is known for both: the shorter far side")
        t.eq(best.toBoard, nil)
        t.eq(best.toStep, 0)
        t.eq(best.yards, nil, "the whole is not known and not claimed")
        -- nothing known at all: the first by key, said as not known
        local dark = N.CrossingBest(given(), me, { at(8, 81, 0.5, 0.5) }, apart, "Horde")
        t.eq(dark.key, "north")
        t.eq(dark.yards, nil)
        t.eq(dark.toStep, nil)
        -- a known whole wins over a not known one
        local list = given()
        list[1].b = at(8, 81, 0.2, 0.2, "Far Tower")
        local known = N.CrossingBest(list, at(7, 70, 0.5, 0.1), { at(8, 80, 0.8, 0.8) }, apart, "Horde")
        t.eq(known.key, "south")
        t.eq(known.yards, 800)
    end,

    ["best: the same input gives the same answer whatever the order of the list"] = function(t)
        local apart = N.CrossingApart(mapSize)
        local list = given()
        local turned = { list[2], list[1] }
        local me, targets = at(7, 71, 0.5, 0.5), { at(8, 81, 0.5, 0.5) }
        t.eq(N.CrossingBest(list, me, targets, apart, "Horde").key, "north")
        t.eq(N.CrossingBest(turned, me, targets, apart, "Horde").key, "north")
    end,

    ["weight: first beside it with the stone ready, last when far"] = function(t)
        t.eq(N.CrossingWeight(100, true), 0.5)
        t.eq(N.CrossingWeight(100, false), 1.1)
        t.eq(N.CrossingWeight(100, nil), 1.1, "stone not known: not taken as ready")
        t.eq(N.CrossingWeight(800, true), 0.5, "the edge counts as close")
        t.eq(N.CrossingWeight(801, true), 2.5)
        t.eq(N.CrossingWeight(nil, true), 2.5, "distance not known: not taken as close")
    end,

    ["when: one line for each weight"] = function(t)
        t.ok(N.CrossingWhen(0.5):find("comes first", 1, true) ~= nil)
        t.ok(N.CrossingWhen(1.1):find("by its distance", 1, true) ~= nil)
        t.ok(N.CrossingWhen(2.5):find("after what is left to do here", 1, true) ~= nil)
        t.ok(N.CrossingWhen(nil):find("after what is left to do here", 1, true) ~= nil)
    end,

    ["text: the words of the step"] = function(t)
        t.eq(N.CrossingText("zeppelin", "Far Tower", 3, "the East"), "Zeppelin to Far Tower (3 steps wait in the East)")
        t.eq(N.CrossingText("boat", "Far Dock", 1, "the East"), "Boat to Far Dock (1 step waits in the East)")
        t.eq(N.CrossingText(nil, "Far Dock", 2, nil), "Crossing to Far Dock (2 steps wait on another continent)")
        t.eq(N.CrossingText("boat", nil, 2, nil), "Boat to another continent (2 steps wait there)")
    end,

    ["label: short, never cut"] = function(t)
        t.eq(N.CrossingLabel("zeppelin", "Far Tower"), "Zeppelin to Far Tower")
        t.eq(N.CrossingLabel("boat", "Far Dock"), "Boat to Far Dock")
        t.eq(N.CrossingLabel(nil, "Far Dock"), "Crossing to Far Dock")
        t.eq(N.CrossingLabel("boat", nil), N.CROSSING_PLAIN)
        t.eq(N.CrossingLabel("boat", string.rep("x", 60)), N.CROSSING_PLAIN, "too long: the plain words, not a cut name")
        t.ok(#N.CROSSING_PLAIN <= N.Waypoint.LABEL_MAX)
    end,

    ["steps: one a continent, at the boarding place"] = function(t)
        local steps, unjoined = N.CrossingSteps({
            list = given(), me = at(7, 70, 0.5, 0.2), faction = "Horde",
            apart = N.CrossingApart(mapSize), hearthReady = true,
            contNames = { [8] = "the East" },
            waiting = { [8] = {
                steps = { { label = "Hand in the letter", quest = 11 }, { label = "Buy rope" }, { label = "Find the camp", quest = 12 } },
                targets = { at(8, 80, 0.2, 0.2) },
            } },
        })
        t.eq(#steps, 1)
        t.eq(#unjoined, 0)
        local s = steps[1]
        t.eq(s.kind, "crossing")
        t.eq(s.key, "cross:8")
        t.eq(s.crossing, "north")
        t.eq(s.toCont, 8)
        t.eq(s.label, "Zeppelin to Far Tower")
        t.eq(s.text, "Zeppelin to Far Tower (3 steps wait in the East)")
        t.eq(s.place.cont, 7)
        t.eq(s.place.map, 70)
        t.eq(s.place.x, 0.5)
        t.eq(s.place.y, 0.1)
        t.eq(s.lands.map, 80)
        t.eq(s.weight, 0.5, "100 yards from it, the stone ready")
        t.eq(s.forQuests[11], true)
        t.eq(s.forQuests[12], true)
        t.eq(s.forQuests[13], nil)
        t.eq(s.details[1], "3 steps of yours are in the East, where the route cannot take you on foot:")
        t.eq(s.details[2], "- Hand in the letter")
        t.eq(s.details[4], "- Find the camp")
        t.eq(s.details[5], "Board at Tower; it lands at Far Tower.")
        t.ok(s.details[6]:find("comes first", 1, true) ~= nil)
    end,

    ["steps: the place is a copy, the list is not changed"] = function(t)
        local list = given()
        local steps = N.CrossingSteps({
            list = list, me = at(7, 70, 0.5, 0.2), faction = "Horde", apart = N.CrossingApart(mapSize),
            waiting = { [8] = { steps = { { label = "One" } }, targets = { at(8, 80, 0.2, 0.2) } } },
        })
        steps[1].place.x = 0.99
        t.eq(list[1].a.x, 0.5)
        t.eq(steps[1].details[1], "1 step of yours is on another continent, where the route cannot take you on foot:")
        t.eq(steps[1].weight, 1.1, "stone not said to be ready")
    end,

    ["steps: more than five waiting are counted, not all listed"] = function(t)
        local waiting = { steps = {}, targets = { at(8, 80, 0.2, 0.2) } }
        for i = 1, 8 do waiting.steps[i] = { label = "Step " .. i } end
        local steps = N.CrossingSteps({
            list = given(), me = at(7, 70, 0.5, 0.2), faction = "Horde", apart = N.CrossingApart(mapSize),
            waiting = { [8] = waiting },
        })
        t.eq(steps[1].details[6], "- Step 5")
        t.eq(steps[1].details[7], "- and 3 more")
    end,

    ["steps: what no crossing reaches says what is missing"] = function(t)
        local apart = N.CrossingApart(mapSize)
        local steps, unjoined = N.CrossingSteps({
            list = given(), me = at(7, 70, 0.5, 0.2), faction = "Horde", apart = apart,
            contNames = { [9] = "the West" },
            waiting = { [9] = { steps = { { label = "One" }, { label = "Two" } }, targets = { at(9, 90, 0.5, 0.5) } } },
        })
        t.eq(#steps, 0)
        t.eq(unjoined[1], "2 steps in the West cannot be routed: no known crossing joins your continent to that one")
        steps, unjoined = N.CrossingSteps({
            list = {}, me = at(7, 70, 0.5, 0.2), faction = "Horde", apart = apart,
            waiting = { [8] = { steps = { { label = "One" } }, targets = { at(8, 80, 0.5, 0.5) } } },
        })
        t.eq(#steps, 0)
        t.eq(unjoined[1], "1 step on another continent cannot be routed: no crossing you can use is known yet")
        steps, unjoined = N.CrossingSteps({
            list = given(), me = at(7, 70, 0.5, 0.2), faction = "Horde", apart = apart,
            waiting = { [8] = { steps = { { label = "One" } }, targets = {} } },
        })
        t.eq(#steps, 0)
        t.eq(unjoined[1], "1 step on another continent cannot be routed: those steps have no place on the map to aim for")
    end,

    ["steps: off, or no position, gives none and says why"] = function(t)
        local input = {
            list = given(), me = at(7, 70, 0.5, 0.2), faction = "Horde", apart = N.CrossingApart(mapSize), on = false,
            waiting = { [8] = { steps = { { label = "One" } }, targets = { at(8, 80, 0.2, 0.2) } } },
        }
        local steps, unjoined, why = N.CrossingSteps(input)
        t.eq(#steps, 0)
        t.eq(#unjoined, 0)
        t.eq(why, "off")
        input.on, input.me = nil, nil
        steps, unjoined, why = N.CrossingSteps(input)
        t.eq(#steps, 0)
        t.eq(why, "position unknown")
        steps, unjoined, why = N.CrossingSteps(nil)
        t.eq(#steps, 0)
        t.eq(why, "position unknown")
    end,

    ["steps: two continents come in the same order every time"] = function(t)
        local list = given()
        list[3] = { key = "west", a = at(7, 70, 0.1, 0.5, "Pier"), b = at(9, 90, 0.5, 0.5, "West Pier") }
        local steps = N.CrossingSteps({
            list = list, me = at(7, 70, 0.5, 0.2), faction = "Horde", apart = N.CrossingApart(mapSize),
            waiting = {
                [9] = { steps = { { label = "One" } }, targets = { at(9, 90, 0.5, 0.5) } },
                [8] = { steps = { { label = "Two" } }, targets = { at(8, 80, 0.2, 0.2) } },
            },
        })
        t.eq(#steps, 2)
        t.eq(steps[1].key, "cross:8")
        t.eq(steps[2].key, "cross:9")
        t.eq(steps[2].label, "Crossing to West Pier")
        t.eq(N.CrossingStepFor(9, steps).crossing, "west")
        t.eq(N.CrossingStepFor(5, steps), nil)
        t.eq(N.CrossingStepFor(9, nil), nil)
    end,

    ["seen: a trip beside a known boarding place corrects both ends"] = function(t)
        local list = given()
        local out, key, what = N.CrossingSeen(list, at(7, 70, 0.52, 0.12), at(8, 80, 0.25, 0.22), { apart = N.CrossingApart(mapSize) })
        t.eq(key, "north")
        t.eq(what, "corrected")
        t.eq(out[1].a.x, 0.52)
        t.eq(out[1].a.y, 0.12)
        t.eq(out[1].b.x, 0.25)
        t.eq(out[1].a.name, "Tower", "the name it had is kept")
        t.eq(out[1].corrected, true)
        t.eq(out[1].how, "zeppelin")
        t.eq(list[1].a.x, 0.5, "the list handed in is not changed")
        t.eq(out[2].a.y, 0.9, "the other crossing is as it was")
    end,

    ["seen: the way back corrects the same crossing"] = function(t)
        local out, key = N.CrossingSeen(given(), at(8, 80, 0.78, 0.8), at(7, 70, 0.5, 0.88), { apart = N.CrossingApart(mapSize) })
        t.eq(key, "south")
        t.eq(out[2].b.x, 0.78)
        t.eq(out[2].a.y, 0.88)
    end,

    ["seen: two crossings at one tower, the landing says which"] = function(t)
        local list = given()
        list[2].a = at(7, 70, 0.5, 0.12, "Tower")
        local _, key = N.CrossingSeen(list, at(7, 70, 0.5, 0.11), at(8, 80, 0.8, 0.78), { apart = N.CrossingApart(mapSize) })
        t.eq(key, "south")
        _, key = N.CrossingSeen(list, at(7, 70, 0.5, 0.11), at(8, 80, 0.2, 0.25), { apart = N.CrossingApart(mapSize) })
        t.eq(key, "north")
    end,

    ["seen: a trip from nowhere known is kept as seen once"] = function(t)
        local apart = N.CrossingApart(mapSize)
        local out, key, what = N.CrossingSeen({}, at(7, 70, 0.3, 0.3, "Here"), at(8, 80, 0.6, 0.6, "There"), { apart = apart })
        t.eq(key, "seen:70:80")
        t.eq(what, "new")
        t.eq(#out, 1)
        t.eq(out[1].seen, 1)
        t.eq(out[1].how, nil, "what carried you is not known")
        t.eq(out[1].a.name, "Here")
        t.eq(out[1].b.name, "There")
        t.eq(N.CrossingUsable(out[1], "Horde"), false)
        -- the same trip again, a little off: now it is a crossing
        local again, key2, what2 = N.CrossingSeen(out, at(7, 70, 0.32, 0.3), at(8, 80, 0.6, 0.62), { apart = apart })
        t.eq(key2, "seen:70:80")
        t.eq(what2, "corrected")
        t.eq(#again, 1)
        t.eq(again[1].seen, 2)
        t.eq(again[1].a.x, 0.32)
        t.eq(N.CrossingUsable(again[1], "Horde"), true)
        -- and the way back counts for it too
        local back = N.CrossingSeen(again, at(8, 80, 0.6, 0.6), at(7, 70, 0.3, 0.3), { apart = apart })
        t.eq(#back, 1)
        t.eq(back[1].seen, 3)
    end,

    ["seen: a second trip between the same maps from elsewhere is its own entry"] = function(t)
        local apart = N.CrossingApart(mapSize)
        local out = N.CrossingSeen({}, at(7, 70, 0.3, 0.3), at(8, 80, 0.6, 0.6), { apart = apart })
        local two, key = N.CrossingSeen(out, at(7, 70, 0.9, 0.9), at(8, 80, 0.1, 0.1), { apart = apart })
        t.eq(#two, 2)
        t.eq(key, "seen:70:80:2")
        t.eq(two[1].seen, 1)
    end,

    ["seen: a hearthstone trip is not a crossing"] = function(t)
        local apart = N.CrossingApart(mapSize)
        local bind = { map = 80, x = 0.6, y = 0.6 }
        local out, key, what = N.CrossingSeen({}, at(7, 70, 0.3, 0.3), at(8, 80, 0.61, 0.6), { apart = apart, bind = bind })
        t.eq(#out, 0)
        t.eq(key, nil)
        t.eq(what, "hearthstone")
        -- the bind place on a map whose size is not known: on that map is enough to say no
        out, key, what = N.CrossingSeen({}, at(7, 70, 0.3, 0.3), at(8, 81, 0.1, 0.1), { apart = apart, bind = { map = 81, x = 0.9, y = 0.9 } })
        t.eq(key, nil)
        t.eq(what, "hearthstone")
        -- far from the bind place on a known map: a trip like any other
        out, key, what = N.CrossingSeen({}, at(7, 70, 0.3, 0.3), at(8, 80, 0.1, 0.1), { apart = apart, bind = bind })
        t.eq(what, "new")
    end,

    ["seen: no continent change, or one not known, is nothing"] = function(t)
        local apart = N.CrossingApart(mapSize)
        local list = given()
        local out, key, what = N.CrossingSeen(list, at(7, 70, 0.5, 0.1), at(7, 71, 0.5, 0.1), { apart = apart })
        t.eq(key, nil)
        t.eq(what, "no change")
        t.eq(out, list, "the same list back")
        out, key, what = N.CrossingSeen(list, at(7, 70, 0.5, 0.1), at(nil, 80, 0.5, 0.1), { apart = apart })
        t.eq(what, "no change")
        out, key, what = N.CrossingSeen(list, nil, at(8, 80, 0.5, 0.1), { apart = apart })
        t.eq(what, "no change")
        out, key, what = N.CrossingSeen(list, at(7, 70, 0.5, 0.1), { cont = 8, map = 80 }, { apart = apart })
        t.eq(what, "no change")
    end,

    ["seen: told not to learn new ones, only known ones are corrected"] = function(t)
        local apart = N.CrossingApart(mapSize)
        local out, key, what = N.CrossingSeen(given(), at(7, 70, 0.1, 0.5), at(8, 80, 0.5, 0.5), { apart = apart, learnNew = false })
        t.eq(key, nil)
        t.eq(what, "not near a known crossing")
        t.eq(#out, 2)
    end,

    ["seen: the list of learned trips does not grow without end"] = function(t)
        local list = {}
        for i = 1, N.CROSSING_MAX do
            list[i] = { key = "seen:" .. i .. ":80", seen = 1, a = at(7, i, 0.5, 0.5), b = at(8, 80, 0.5, 0.5) }
        end
        local out, key, what = N.CrossingSeen(list, at(7, 70, 0.3, 0.3), at(8, 80, 0.6, 0.6), { apart = N.CrossingApart(mapSize) })
        t.eq(key, nil)
        t.eq(what, "full")
        t.eq(#out, N.CROSSING_MAX)
    end,

    ["lines: what the player is told when asking"] = function(t)
        local list = given()
        list[1].corrected = true
        list[3] = { key = "seen:70:80", seen = 1, a = at(7, 70, 0.3, 0.3, "Here"), b = at(8, 80, 0.6, 0.6, "There") }
        local lines = N.CrossingLines(list, { { text = "Boat to Far Dock (1 step waits in the East)" } }, {}, true, "Horde")
        t.eq(lines[1], "crossings you can use: 2")
        t.eq(lines[2], "  north: zeppelin Tower <-> Far Tower (corrected from a trip of yours)")
        t.eq(lines[3], "  south: boat Dock <-> Far Dock")
        t.eq(lines[4], "  seen once, not yet used: Here <-> There")
        t.eq(lines[5], "  on your route: Boat to Far Dock (1 step waits in the East)")
        t.eq(lines[6], nil)
        local none = N.CrossingLines({}, {}, {}, false, "Horde")
        t.eq(none[1], "crossings you can use: 0 (off)")
        t.eq(none[2], "  nothing of yours waits on another continent")
        local stuck = N.CrossingLines({}, {}, { "1 step on another continent cannot be routed: x" }, true, "Horde")
        t.eq(stuck[2], "  1 step on another continent cannot be routed: x")
        t.eq(stuck[3], nil)
    end,
}
