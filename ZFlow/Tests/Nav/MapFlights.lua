local _, ns = ...

-- Tests for ZFlow/Nav/MapFlights.lua (S31, LEDGER 143): the pure rules of
-- the flight marks on the world map, ported from Flow's
-- Modules/Nav/MapFlights.lua (see WoW/from-zen/RESEARCH-S31.md).
-- Hand-written world spots only. Nothing is drawn here and nothing acts.

local MF = ns.MapFlights
local tests = {}

local function known()
    return {
        ["Crossroads, The Barrens"] = { cont = 1, wx = 1000, wy = 1000 },
        ["Orgrimmar, Durotar"] = { cont = 1, wx = 3000, wy = 1000 },
        ["Bad"] = "x",
    }
end

local function masters()
    return {
        { name = "Devrak", cont = 1, wx = 1100, wy = 1000, map = 1413, x = 0.5, y = 0.3 },   -- 100 yd from Crossroads
        { name = "Karos", cont = 1, wx = 5000, wy = 5000, map = 1411, x = 0.5, y = 0.5 },    -- by no path you have
        { name = "Karos", cont = 1, wx = 5001, wy = 5000, map = 1411, x = 0.5, y = 0.5 },    -- the same name again
        { name = "Talked", cont = 1, wx = 7000, wy = 7000, map = 1411, x = 0.1, y = 0.1 },
        { name = "Nowhere" },
    }
end

local function byName(pins, name)
    for _, p in ipairs(pins) do
        if p.name == name then return p end
    end
    return nil
end

local function names(pins)
    local out = {}
    for i, p in ipairs(pins) do out[i] = p.name end
    return out
end

-- Flow :55-104.
tests["map flights: a pin for each path you have and each master not learned"] = function(t)
    local pins = MF.Pins(known(), masters(), function(fm) return fm.name == "Talked" end, { Karos = true }, nil)
    t.eq(names(pins), { "Karos", "Crossroads, The Barrens", "Orgrimmar, Durotar" }, "new first, then the ones you have, by name")
    local have = byName(pins, "Crossroads, The Barrens")
    t.eq(have.kind, "have")
    t.eq(have.npc, "Devrak", "the master standing by it is its master")
    t.eq(have.map, 1413)
    local new = byName(pins, "Karos")
    t.eq(new.kind, "new")
    t.eq(new.onRoute, true)
    t.eq(new.npc, "Karos")
    t.eq(byName(pins, "Devrak"), nil, "a master within 250 yards of a path you have is not one to learn")
    t.eq(byName(pins, "Talked"), nil, "one you learned by talking is not shown as new")
    t.eq(byName(pins, "Nowhere"), nil, "no place: no pin")
    t.eq(MF.SAME, 250)
end

tests["map flights: the two of your next step's flight are marked and drawn last"] = function(t)
    local air = { from = "Orgrimmar, Durotar", to = "Crossroads, The Barrens" }
    local pins = MF.Pins(known(), masters(), nil, nil, air)
    t.eq(pins[#pins - 1].role, "to", "by name among the two")
    t.eq(pins[#pins].role, "from")
    t.eq(pins[1].kind, "new")
    t.eq(MF.RoleLabel("from"), "Fly from here")
    t.eq(MF.RoleLabel("to"), "Land here: next step")
    t.eq(MF.RoleLabel(nil), nil)
    t.eq(MF.Pins(nil, nil), {}, "nothing known: no pins")
end

-- Flow :108-123.
tests["map flights: the words on a pin"] = function(t)
    local title, lines = MF.TipLines({ name = "Crossroads, The Barrens", kind = "have", npc = "Devrak" })
    t.eq(title, "Crossroads, The Barrens")
    t.eq(lines, { "Flight master: Devrak", "You have this flight path: you can fly here." })
    local _, from = MF.TipLines({ name = "A", kind = "have", role = "from" }, nil, "4 min")
    t.eq(from[2], "Fly from here: your next step is quicker by air, 4 min in all.")
    local _, plain = MF.TipLines({ name = "A", kind = "have", role = "from" })
    t.eq(plain[2], "Fly from here: your next step is quicker by air.", "no time known: none claimed")
    local _, to = MF.TipLines({ name = "A", kind = "have", role = "to" }, "Kill 8 boars")
    t.eq(to[2], "Land here for your next step: Kill 8 boars.")
    local _, new = MF.TipLines({ name = "Karos", kind = "new", onRoute = true })
    t.eq(new, {
        "Flight master. You don't have this flight path yet: talk to them once (it's free), and later trips through here are shorter.",
        "It's a step on your route (Flight paths to learn).",
    })
end

-- Flow :242-252.
tests["map flights: one click picks a master, the next click clears"] = function(t)
    t.eq(MF.Click(nil, "A"), { from = "A" })
    t.eq(MF.Click({ from = "A" }, "B"), {}, "any master while one is picked: nothing picked")
    t.eq(MF.Click({ from = "A" }, "A"), {})
    t.eq(MF.Click({ from = "A" }, nil), { from = "A" }, "no name: unchanged")
end

-- Flow :276-299.
tests["map flights: what a flight between two pins says"] = function(t)
    local a = { name = "Crossroads, The Barrens", kind = "have", cont = 1 }
    local b = { name = "Orgrimmar, Durotar", kind = "have", cont = 1 }
    local n = { name = "Karos", kind = "new", cont = 1, npc = "Karos" }
    local far = { name = "Ironforge, Dun Morogh", kind = "have", cont = 2 }
    t.eq(MF.CanFly(a, b), true)
    t.eq(MF.CanFly(a, n), false)
    t.eq(MF.CanFly(a, far), false)
    t.eq(MF.CanFly(a, nil), false)
    t.eq(MF.Short("Crossroads, The Barrens"), "Crossroads")
    t.eq(MF.Short(nil), "?")
    local text, can = MF.FlightText(a, b, 83)
    t.eq({ text, can }, { "Crossroads to Orgrimmar: 83 s (your last flight)", true })
    t.eq((MF.FlightText(a, b, nil, 90)), "Crossroads to Orgrimmar: about 90 s", "an estimate is labelled")
    t.eq((MF.FlightText(a, b)), "Crossroads to Orgrimmar: flight time not known yet", "unknown stays unknown")
    local no, cant = MF.FlightText(a, n)
    t.eq({ no, cant }, { "Crossroads to Karos: you can't fly it yet (learn the flight path at Karos first)", false })
    t.eq((MF.FlightText(a, far)), "Crossroads to Ironforge: not on one continent")
    t.eq((MF.FlightText(a, b, 83, nil, function(s) return s .. " sec" end)), "Crossroads to Orgrimmar: 83 sec (your last flight)")
end

-- Flow :254-272.
tests["map flights: the line the mouse is on or near"] = function(t)
    t.eq(MF.SegDist(5, 3, 0, 0, 10, 0), 3, "beside the middle")
    t.eq(MF.SegDist(13, 4, 0, 0, 10, 0), 5, "past the end: to the end")
    t.eq(MF.SegDist(3, 4, 0, 0, 0, 0), 5, "a line of no length is a point")
    local lines = { { name = "far", ax = 0, ay = 100, bx = 10, by = 100 }, { name = "near", ax = 0, ay = 0, bx = 10, by = 0 } }
    t.eq(MF.LineAt(lines, 5, 3, 14), "near")
    t.eq(MF.LineAt(lines, 5, 50, 14), nil, "nothing within reach")
    t.eq(MF.LINE_REACH, 14)
end

tests["map flights: look only - nothing in here flies, clicks or changes the map"] = function(t)
    for name in pairs(MF) do
        local n = tostring(name):lower()
        t.ok(not (n:find("take") or n:find("^fly$") or n:find("setmap") or n:find("hook")), "no acting function: " .. n)
    end
end

-- Lead section 785 (B-12-andor): the and-or forms of MF.Pins and
-- MF.TipLines are plain ifs now; each nil case keeps its answer.
tests["map flights: nil and odd inputs give the same answers as before"] = function(t)
    local home = { ["Home"] = { cont = 1, wx = 0, wy = 0 } }
    t.eq(#MF.Pins(nil, nil), 0, "no paths, no masters")
    local far = { { name = "Far", cont = 1, wx = MF.SAME + 1, wy = 0 } }
    t.eq(#MF.Pins(home, far, nil, nil, nil, nil), 2, "same nil: MF.SAME, so Far is its own master")
    t.eq(#MF.Pins(home, far, nil, nil, nil, MF.SAME + 5), 1, "a wider same: Far is Home's master")
    t.eq(#MF.Pins(home, "not a list"), 1, "masters not a list: none")
    local odd = { "not a master", { cont = 1, wx = 9000, wy = 0 } }
    t.eq(#MF.Pins(nil, odd), 0, "a master that is no table or has no name: left out")
    local new = { { name = "New", cont = 1, wx = 9000, wy = 0 } }
    t.eq(MF.Pins(nil, new, function() error("no") end)[1].kind, "new", "learned raising: not learned")
    t.eq(#MF.Pins(nil, new, function() return true end), 0, "learned: not shown as new")
    t.eq(MF.Pins(nil, new, function() return nil end)[1].kind, "new", "learned nil: not learned")
    t.eq(MF.Pins(nil, new)[1].onRoute, nil, "no route list: onRoute nil")
    t.eq(MF.Pins(nil, new, nil, { New = "yes" })[1].onRoute, true, "on the route: true")
    t.eq(MF.Pins(nil, new, nil, { Other = true })[1].onRoute, nil)
    local _, from = MF.TipLines({ name = "A", kind = "have", role = "from" }, nil, nil)
    t.eq(from[#from], "Fly from here: your next step is quicker by air.", "no air time: none claimed")
    _, from = MF.TipLines({ name = "A", kind = "have", role = "from" }, nil, "4 min")
    t.eq(from[#from], "Fly from here: your next step is quicker by air, 4 min in all.")
    local _, to = MF.TipLines({ name = "A", kind = "have", role = "to" }, nil, nil)
    t.eq(to[#to], "Land here for your next step.", "no step text")
    _, to = MF.TipLines({ name = "A", kind = "have", role = "to" }, "Kill boars", nil)
    t.eq(to[#to], "Land here for your next step: Kill boars.")
end

return tests
