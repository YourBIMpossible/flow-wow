local _, ns = ...

-- Tests for S32 (Nav/CrossingWords.lua): the dock a learned boat or
-- zeppelin was taken from, the place it landed, and how long the player
-- waited on the dock, all from the player's own trips, said as one line
-- under the crossing step. Unknown data says nothing. Made-up places;
-- fake client. Not tested in game. Look only: nothing boards or clicks.

local N = ns.Nav
local tests = {}

tests["words: the place name is the sub-zone, else the zone, else nothing"] = function(t)
    t.eq(N.CrossingName({ zone = "Wetlands", sub = "Menethil Harbor" }), "Menethil Harbor")
    t.eq(N.CrossingName({ zone = "Darkshore" }), "Darkshore")
    t.eq(N.CrossingName({}), nil)
    t.eq(N.CrossingName(nil), nil)
end

tests["words: the take line names the dock and the landing"] = function(t)
    t.eq(N.CrossingTake("boat", "Menethil Harbor", "Auberdine"),
        "Take the boat at Menethil Harbor's dock to Auberdine.")
    t.eq(N.CrossingTake("zeppelin", "Orgrimmar", "Tirisfal Glades"),
        "Take the zeppelin at Orgrimmar's tower to Tirisfal Glades.")
    t.eq(N.CrossingTake("boat", "Durotar dock", "Tirisfal dock"),
        "Take the boat at Durotar dock to Tirisfal dock.", "no dock twice")
    t.eq(N.CrossingTake(nil, "Menethil Harbor", "Auberdine"),
        "Take the boat or zeppelin at Menethil Harbor to Auberdine.", "how not known: not guessed")
end

tests["words: no take line without both names"] = function(t)
    t.eq(N.CrossingTake("boat", nil, "Auberdine"), nil)
    t.eq(N.CrossingTake("boat", "Menethil Harbor", ""), nil)
end

tests["words: the wait line from the longest wait seen, in whole minutes"] = function(t)
    t.eq(N.CrossingWaitLine("boat", 180), "The boat leaves about every 3 minutes: wait on the dock.")
    t.eq(N.CrossingWaitLine("zeppelin", 50), "The zeppelin leaves about every 1 minute: wait on the tower.")
    t.eq(N.CrossingWaitLine(nil, 200), "It leaves about every 3 minutes: wait where you board.")
end

tests["words: no wait line for a wait not known, too short or too long"] = function(t)
    t.eq(N.CrossingWaitLine("boat", nil), nil)
    t.eq(N.CrossingWaitLine("boat", N.CROSSING_WAIT_MIN - 1), nil)
    t.eq(N.CrossingWaitLine("boat", N.CROSSING_WAIT_MAX + 1), nil, "away from the keys: not a wait")
    t.eq(N.CrossingWaitLine("boat", 0 / 0), nil)
end

tests["words: the hint joins them; nothing when the names are not known"] = function(t)
    t.eq(N.CrossingHint("boat", "Menethil Harbor", "Auberdine", 180),
        "Take the boat at Menethil Harbor's dock to Auberdine. The boat leaves about every 3 minutes: wait on the dock.")
    t.eq(N.CrossingHint("boat", "Menethil Harbor", "Auberdine", nil),
        "Take the boat at Menethil Harbor's dock to Auberdine.")
    t.eq(N.CrossingHint("boat", nil, "Auberdine", 180), nil)
end

tests["still: one spot keeps its start; a move ends the run with its seconds"] = function(t)
    local run = N.CrossingStill(nil, { cont = 0, map = 1437, x = 0.1, y = 0.5 }, 100, "Menethil Harbor")
    local again, ended = N.CrossingStill(run, { cont = 0, map = 1437, x = 0.1, y = 0.5 }, 280, "Menethil Harbor")
    t.eq(ended, nil)
    t.eq(again.since, 100)
    local moved, gone = N.CrossingStill(again, { cont = 0, map = 1437, x = 0.12, y = 0.5 }, 281, "Menethil Harbor")
    t.eq(moved.since, 281)
    t.eq(gone, { cont = 0, map = 1437, x = 0.1, y = 0.5, name = "Menethil Harbor", secs = 181 })
end

tests["name trip: a new crossing gets both names and the wait on the boarding end"] = function(t)
    local before = { cont = 0, map = 1437, x = 0.1, y = 0.5 }
    local list = { { key = "seen:1437:1439", seen = 1, a = { cont = 0, map = 1437, x = 0.1, y = 0.5 },
                     b = { cont = 1, map = 1439, x = 0.3, y = 0.4 } } }
    local out = N.CrossingNameTrip(nil, list, "seen:1437:1439", before,
        { cont = 0, name = "Menethil Harbor", secs = 180 }, "Auberdine")
    t.eq(out[1].a.name, "Menethil Harbor")
    t.eq(out[1].a.wait, 180)
    t.eq(out[1].b.name, "Auberdine")
    t.eq(out[1].b.wait, nil)
    t.eq(list[1].a.name, nil, "the list handed in is not changed")
end

tests["name trip: a corrected crossing keeps its names and its longest wait"] = function(t)
    local old = { { key = "k", seen = 1, a = { cont = 0, map = 1437, x = 0.1, y = 0.5, name = "Menethil Harbor", wait = 200 },
                    b = { cont = 1, map = 1439, x = 0.3, y = 0.4, name = "Auberdine" } } }
    local list = { { key = "k", seen = 2, corrected = true, a = { cont = 0, map = 1437, x = 0.1, y = 0.5, name = "Menethil Harbor" },
                     b = { cont = 1, map = 1439, x = 0.3, y = 0.4, name = "Auberdine" } } }
    local out = N.CrossingNameTrip(old, list, "k", { cont = 0, map = 1437, x = 0.1, y = 0.5 },
        { cont = 0, name = "Wetlands", secs = 90 }, "Darkshore")
    t.eq(out[1].a.name, "Menethil Harbor", "a name once seen is kept")
    t.eq(out[1].a.wait, 200, "the longest wait is kept")
    t.eq(out[1].b.name, "Auberdine")
end

tests["name trip: the return trip keeps the wait of the other end"] = function(t)
    local old = { { key = "k", seen = 1, a = { cont = 0, map = 1437, x = 0.1, y = 0.5, name = "Menethil Harbor", wait = 200 },
                    b = { cont = 1, map = 1439, x = 0.3, y = 0.4, name = "Auberdine" } } }
    local list = { { key = "k", seen = 2, a = { cont = 0, map = 1437, x = 0.1, y = 0.5, name = "Menethil Harbor" },
                     b = { cont = 1, map = 1439, x = 0.3, y = 0.4, name = "Auberdine" } } }
    local out = N.CrossingNameTrip(old, list, "k", { cont = 1, map = 1439, x = 0.3, y = 0.4 }, nil, "Menethil Harbor")
    t.eq(out[1].a.wait, 200)
    t.eq(out[1].b.wait, nil)
end

tests["steps: a learned crossing with names carries the hint; a handed-in one does not"] = function(t)
    local me = { cont = 0, map = 1437, x = 0.1, y = 0.6 }
    local target = { cont = 1, map = 1439, x = 0.3, y = 0.5 }
    local function step(cr)
        local s = N.CrossingSteps({ list = { cr }, me = me, faction = "Alliance",
            waiting = { [1] = { steps = { { place = target } }, targets = { target } } } })
        return s[1] or {}
    end
    local learned = { key = "k", seen = 2, a = { cont = 0, map = 1437, x = 0.1, y = 0.5, name = "Menethil Harbor", wait = 180 },
                      b = { cont = 1, map = 1439, x = 0.3, y = 0.4, name = "Auberdine" } }
    t.eq(step(learned).hint,
        "Take the boat or zeppelin at Menethil Harbor to Auberdine. It leaves about every 3 minutes: wait where you board.")
    local handed = { key = "h", how = "boat", a = learned.a, b = learned.b }
    t.eq(step(handed).hint, nil)
    local unnamed = { key = "u", seen = 2, a = { cont = 0, map = 1437, x = 0.1, y = 0.5 }, b = { cont = 1, map = 1439, x = 0.3, y = 0.4 } }
    t.eq(step(unnamed).hint, nil, "unknown names: nothing said")
end

return tests
