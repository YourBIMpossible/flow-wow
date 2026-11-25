-- Tests for ZFlow/Nav/Travel.lua (S33 + S35 wiring, LEDGER 156): the step
-- the arrow is given when the way to the chosen step is a cast, the
-- hearthstone, a ride or a gate. Pure rule first, then the module and the
-- arrow over the fake client. Every place and name is made up by hand or is
-- one Nav/TravelSpells.lua and Nav/Rides.lua already carry. Not tested in game.
-- It only says what to do: nothing casts, talks, flies or walks for the player.
local _, ns = ...

local N, A = ns.Nav, ns.Arrow
local T = N.Travel
local tests = {}

local MOONGLADE, DUROTAR, ORGRIMMAR = 1450, 1411, 1454
local SPELL = "Teleport: Moonglade"

local function boars(map)
    return { label = "Kill boars", place = { cont = 1, map = map or MOONGLADE, x = 0.4, y = 0.6 } }
end

-- ------------------------------------------------------------ the pure rule

tests["travel via: nothing applies, the step is handed back as it is"] = function(t)
    local step = boars()
    local out, how = N.TravelVia(step, {}, false)
    t.ok(out == step, "the same table")
    t.eq(how, nil)
    t.eq((N.TravelVia(step, nil, false)), step)
    t.eq({ N.TravelVia(nil, {}, false) }, {}, "no step: nothing")
    t.eq((N.TravelVia("x", {}, false)), "x", "not a step: handed back")
end

tests["travel via: a spell the player knows comes first, the step is said next"] = function(t)
    local step = boars()
    local spell = { label = "Cast " .. SPELL, text = true, spell = SPELL }
    local hearth = { label = "Hearth to Nighthaven", text = true, saves = 900 }
    local out, how = N.TravelVia(step, { spell = spell, hearth = hearth }, false)
    t.eq(how, "spell")
    t.eq(out, { label = "Cast " .. SPELL, still = true, detail = "Then: Kill boars", via = "spell" })
    t.eq(step, boars(), "the chosen step is not changed")
end

-- Lead section 403 (b): a spell to learn is no shortcut, but the player is
-- told where to learn it, as a line under the step (its hint).
local LEARN = { label = "Learn " .. SPELL, text = true, spell = SPELL, learn = true, detail = "your class trainer" }

tests["travel via: a spell to learn is no shortcut; where to learn it is said under the step"] = function(t)
    local step = boars()
    local out, how = N.TravelVia(step, { spell = LEARN }, false)
    t.eq(how, nil, "not a way: no how")
    t.eq(out, { label = "Kill boars", place = boars().place, hint = "Learn " .. SPELL .. " (your class trainer)" })
    t.eq(step, boars(), "the chosen step is not changed")
end

-- Parity B-32: with no place of its own, the class trainer (legacy
-- Modules/Nav/TravelSpells.lua:89).
tests["travel via: a spell to learn with no place of its own is learned at the class trainer"] = function(t)
    local learn = { label = "Learn " .. SPELL, text = true, spell = SPELL, learn = true }
    t.eq(N.TravelVia(boars(), { spell = learn }, false).hint, "Learn " .. SPELL .. " (" .. T.LEARN_AT .. ")")
end

tests["travel via: the learn line gives way to a real way and walking, and comes before the no-flight line"] = function(t)
    local hearth = { label = "Hearth to Nighthaven", text = true, saves = 900 }
    local out, how = N.TravelVia(boars(), { spell = LEARN, hearth = hearth }, false)
    t.eq(how, "hearth", "the stone is still the action")
    t.eq(out.hint, nil)
    local hinted = N.TravelVia(boars(), { spell = LEARN, flightHint = "No flight learned to there yet" }, false)
    t.eq(hinted.hint, "Learn " .. SPELL .. " (your class trainer)", "parity B-32: the spell before the no-flight line")
    local flightOnly = N.TravelVia(boars(), { flightHint = "No flight learned to there yet" }, false)
    t.eq(flightOnly.hint, "No flight learned to there yet", "no spell to learn: the flight's line as it was")
    local walked = N.TravelVia(boars(), { spell = LEARN }, true)
    t.eq(walked.hint, nil, "walking: no travel line")
    local had = boars(); had.hint = "Through the cave"
    t.eq(N.TravelVia(had, { spell = LEARN }, false).hint, "Through the cave", "a step's own hint stays")
end

tests["travel via: the hearthstone only when its saving is a known number above 0"] = function(t)
    local step = boars(DUROTAR)
    local out, how = N.TravelVia(step, { hearth = { label = "Hearth to Razor Hill", text = true, saves = 400 } }, false)
    t.eq(how, "hearth")
    t.eq(out, { label = "Hearth to Razor Hill", still = true, detail = "Then: Kill boars", via = "hearth" })
    local none = N.TravelVia(step, { hearth = { label = "Hearth to Razor Hill", text = true } }, false)
    t.ok(none == step, "saving not known: not claimed")
    local zero = N.TravelVia(step, { hearth = { label = "Hearth to Razor Hill", text = true, saves = 0 } }, false)
    t.ok(zero == step)
end

tests["travel via: a ride points at its master when their place is known"] = function(t)
    local step = boars(DUROTAR)
    local ride = { label = "Talk to Bunthen Plainswind", text = true, ride = "Bunthen Plainswind",
                   detail = "he flies druids to Thunder Bluff, free", point = { map = MOONGLADE, x = 0.44, y = 0.45 } }
    local out, how = N.TravelVia(step, { ride = ride, cont = 1 }, false)
    t.eq(how, "ride")
    t.eq(out, { label = "Talk to Bunthen Plainswind", detail = "he flies druids to Thunder Bluff, free",
                place = { cont = 1, map = MOONGLADE, x = 0.44, y = 0.45 }, radius = T.NEAR, via = "ride" })
    ride.point = nil
    out = N.TravelVia(step, { ride = ride, cont = 1 }, false)
    t.eq(out, { label = "Talk to Bunthen Plainswind", detail = "he flies druids to Thunder Bluff, free",
                still = true, via = "ride" }, "place not known: said in words, no place made up")
end

tests["travel via: a known gate takes the arrow, the step is said next"] = function(t)
    local step = boars(ORGRIMMAR)
    local gate = { kind = "gate", label = "Way to Orgrimmar", place = { cont = 1, map = DUROTAR, x = 0.5, y = 0.1 }, radius = 10 }
    local out, how = N.TravelVia(step, { gate = gate }, false)
    t.eq(how, "gate")
    t.eq(out, { kind = "gate", label = "Way to Orgrimmar", place = { cont = 1, map = DUROTAR, x = 0.5, y = 0.1 },
                radius = 10, detail = "Then: Kill boars", via = "gate" })
    t.eq(gate.detail, nil, "the gate step handed in is not changed")
end

tests["travel via: a walled place with no gate known keeps the step and says so under it"] = function(t)
    local step = boars(ORGRIMMAR)
    local gate = { kind = "gate", label = N.GATE_UNKNOWN, text = true, detail = "Orgrimmar: behind walls, gates only" }
    local out, how = N.TravelVia(step, { gate = gate }, false)
    t.eq(how, "gate unknown")
    t.eq(out, { label = "Kill boars", place = step.place, detail = N.GATE_UNKNOWN })
    t.ok(out ~= step and step.detail == nil, "a copy: the chosen step is not changed")
    local own = boars(ORGRIMMAR)
    own.detail = "0/8 boars"
    local kept, why = N.TravelVia(own, { gate = gate }, false)
    t.ok(kept == own, "a step with a line of its own keeps it")
    t.eq(why, "gate unknown")
end

tests["travel via: walk there instead drops the cast, the stone and the ride, never the gate"] = function(t)
    local step = boars()
    local spell = { label = "Cast " .. SPELL, text = true, spell = SPELL }
    local hearth = { label = "Hearth to Nighthaven", text = true, saves = 900 }
    local ride = { label = "Talk to Bunthen Plainswind", text = true, ride = "Bunthen Plainswind" }
    local out, how = N.TravelVia(step, { spell = spell, hearth = hearth, ride = ride }, true)
    t.ok(out == step)
    t.eq(how, nil)
    local gate = { kind = "gate", label = "Way to Orgrimmar", place = { cont = 1, map = DUROTAR, x = 0.5, y = 0.1 }, radius = 10 }
    out, how = N.TravelVia(step, { spell = spell, gate = gate }, true)
    t.eq(how, "gate", "the gate is the walk")
    t.eq(out.label, "Way to Orgrimmar")
end

tests["travel via: the order is spell, hearthstone, ride, gate"] = function(t)
    local step = boars()
    local hearth = { label = "Hearth to Nighthaven", text = true, saves = 900 }
    local ride = { label = "Talk to Bunthen Plainswind", text = true, ride = "Bunthen Plainswind" }
    local gate = { kind = "gate", label = "Way to Orgrimmar", place = { cont = 1, map = DUROTAR, x = 0.5, y = 0.1 }, radius = 10 }
    t.eq(select(2, N.TravelVia(step, { hearth = hearth, ride = ride, gate = gate }, false)), "hearth")
    t.eq(select(2, N.TravelVia(step, { ride = ride, gate = gate }, false)), "ride")
end

tests["travel via: a step with no label gets no 'then' line"] = function(t)
    local step = { place = { cont = 1, map = MOONGLADE, x = 0.4, y = 0.6 } }
    local out = N.TravelVia(step, { spell = { label = "Cast " .. SPELL, text = true, spell = SPELL } }, false)
    t.eq(out, { label = "Cast " .. SPELL, still = true, via = "spell" })
end

-- --------------------------------------------------------------- the module

-- A druid in Durotar (1411, 1000 by 1000 yards). opts: knows (true, false,
-- "unknown"), gates (saved list; false: no gates module), npcs, map (where
-- the player is), arrow (true: the arrows run too), pin (the map pin), own
-- (the player's own waypoint).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {
        layout = { arrowIntroSeen = true },
        learned = { places = { gates = opts.gates, npcs = opts.npcs } },
    })
    if opts.own then c.setSaved(ns.id.charDB, { state = { nav = { waypoint = opts.own } } }) end
    c.setScreen(1024, 768)
    c.setZone(1, opts.map or DUROTAR)
    c.setFacing(0)
    c.setPosition(opts.map or DUROTAR, 0.5, 0.5)
    c.setMapSize(opts.map or DUROTAR, 1000, 1000)
    c.setClass("DRUID")
    c.setFaction("Horde")
    if opts.pin then c.setWaypoint(opts.pin.map, opts.pin.x, opts.pin.y) end
    if opts.knows ~= "unknown" then
        c.setSpellId(SPELL, 18960)
        c.setSpell(18960, { known = opts.knows ~= false })
    end
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local a = opts.arrow and A.Start(k, d) or nil
    if opts.gates ~= false then N.Gates.Declare(k) end
    local api = T.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api, a
end

local function say(c, text) c.slashes[ns.id.slash](T.WORD .. (text and (" " .. text) or "")) end
local function last(c) return c.printed[#c.printed] or "" end
local function has(text, part) return tostring(text):find(part, 1, true) ~= nil end

tests["travel module: started, and it provides Via"] = function(t)
    local k = start()
    t.eq(T.NAME, "travel")
    t.eq(T.WORD, "walk")
    t.eq((k:ModuleState(T.NAME)), "started")
    t.ok(type(k.use(T.NAME).Via) == "function")
    t.eq(k.problems:count(), 0)
end

tests["travel module: a druid who knows the spell is told to cast it"] = function(t)
    local k, _, api = start()
    local out, how = api.via(boars())
    t.eq(how, "spell")
    t.eq(out, { label = "Cast " .. SPELL, still = true, detail = "Then: Kill boars", via = "spell" })
    t.eq((k.use(T.NAME).Via(boars())).via, "spell", "the same through the kernel")
end

tests["travel module: spell not known: the step and where to learn it; the client did not say: the step stays"] = function(t)
    local _, _, api = start({ knows = false })
    local step = boars()
    local out, how = api.via(step)
    t.eq(how, nil, "not known: walk")
    t.eq(out.label, "Kill boars")
    t.eq(out.hint, "Learn " .. SPELL .. " (your class trainer, from level 10)", "where to learn it is said")
    local _, _, api2 = start({ knows = "unknown" })
    t.ok(api2.via(step) == step, "no answer is never taken as known")
end

tests["travel module: a step on the player's own map is left alone"] = function(t)
    local _, _, api = start()
    local step = boars(DUROTAR)
    local out, how = api.via(step)
    t.ok(out == step)
    t.eq(how, nil)
end

tests["travel module: a place in yards, or no place, is left alone"] = function(t)
    local _, _, api = start()
    local yards = { label = "Kill boars", place = { cont = 1, zone = 14, x = 100, y = 200 } }
    t.ok(api.via(yards) == yards)
    local words = { label = "Kill boars", still = true }
    t.ok(api.via(words) == words)
    t.eq((api.via(nil)), nil)
end

tests["travel module: a learned gate takes the arrow to a walled map"] = function(t)
    local gates = { { a = DUROTAR, b = ORGRIMMAR, ax = 0.50, ay = 0.10, bx = 0.45, by = 0.60, cont = 1, wx = 1030, wy = 1000 } }
    local _, _, api = start({ gates = gates })
    local out, how = api.via(boars(ORGRIMMAR))
    t.eq(how, "gate")
    t.eq(out, { kind = "gate", label = "Way to Orgrimmar", place = { cont = 1, map = DUROTAR, x = 0.50, y = 0.10 },
                radius = N.Gates.NEAR, detail = "Then: Kill boars", via = "gate" })
end

tests["travel module: no gate known says so; with no gates module the step stays"] = function(t)
    local _, _, api = start()
    local out, how = api.via(boars(ORGRIMMAR))
    t.eq(how, "gate unknown")
    t.eq(out.detail, N.GATE_UNKNOWN)
    t.eq(out.place.map, ORGRIMMAR, "the step's own place, none made up")
    local _, _, bare = start({ gates = false })
    local step = boars(ORGRIMMAR)
    t.ok(bare.via(step) == step)
end

tests["travel module: in Moonglade the way out is the ride's master"] = function(t)
    local npcs = { ["Bunthen Plainswind"] = { map = MOONGLADE, x = 0.44, y = 0.45 } }
    local _, _, api = start({ map = MOONGLADE, npcs = npcs })
    local out, how = api.via(boars(DUROTAR))
    t.eq(how, "ride")
    t.eq(out.label, "Talk to Bunthen Plainswind")
    t.eq(out.place, { cont = 1, map = MOONGLADE, x = 0.44, y = 0.45 })
    t.eq(out.radius, T.NEAR)
end

tests["travel module: the walk word skips the shortcut for this step, and gives it back"] = function(t)
    local _, c, api = start()
    local step = boars()
    t.eq(select(2, api.via(step)), "spell")
    say(c)
    t.ok(has(last(c), ns.id.title), "said under the addon's own name")
    t.ok(has(last(c), "walk"), last(c))
    t.ok(api.via(step) == step, "walking: the step itself")
    local other = { label = "Talk to Rabine", place = { cont = 1, map = MOONGLADE, x = 0.5, y = 0.3 } }
    t.eq(select(2, api.via(other)), "spell", "another step still gets the shortcut")
    api.via(step)
    say(c)
    t.eq(select(2, api.via(step)), "spell", "said again: the shortcut is back")
end

tests["travel module: the walk word with no shortcut on says so and changes nothing"] = function(t)
    local _, c, api = start()
    local step = boars(DUROTAR)
    api.via(step)
    say(c)
    t.ok(has(last(c), "no shortcut"), last(c))
    t.ok(api.via(step) == step)
end

tests["travel module: the arrow shows the cast in place of the map pin's direction"] = function(t)
    local k, c = start({ arrow = true, pin = { map = MOONGLADE, x = 0.4, y = 0.6 } })
    t.eq(c.arrows[1].shown, true)
    t.eq(c.arrows[1].lines, { "Cast " .. SPELL, "Then: " .. N.WAYPOINT_LABEL })
    t.eq(k.problems:count(), 0)
end

tests["travel module: the arrow shows where to learn the spell under the map pin's step"] = function(t)
    local k, c = start({ arrow = true, knows = false, pin = { map = MOONGLADE, x = 0.4, y = 0.6 } })
    local lines = c.arrows[1].lines
    t.eq(lines[1], N.WAYPOINT_LABEL)
    t.eq(lines[2], "Learn " .. SPELL .. " (your class trainer, from level 10)", "the learn line under the step")
    t.eq(k.problems:count(), 0)
end

tests["travel module: reaching a gate does not clear the player's own waypoint"] = function(t)
    local gates = { { a = DUROTAR, b = ORGRIMMAR, ax = 0.50, ay = 0.50, bx = 0.45, by = 0.60, cont = 1, wx = 1030, wy = 1000 } }
    local W = N.Waypoint
    local own = { map = ORGRIMMAR, x = 0.3, y = 0.3, label = "Bank" }
    local k, c = start({ arrow = true, gates = gates, own = own })
    c.advance(A.RELAYOUT * 4, 4)
    t.eq(c.arrows[1].lines[1], "Way to Orgrimmar", "the gate, where the player stands")
    t.eq(c.arrows[1].lines[2], "Then: Bank")
    local slot = k.store:get(W.SCOPE, W.PATH)
    t.ok(type(slot) == "table" and slot.waypoint ~= nil, "at the gate: the waypoint is kept")
    for _, line in ipairs(c.printed) do
        t.ok(not has(line, "waypoint reached"), line)
    end
end

tests["travel module: a map pin on the player's own map is drawn as before"] = function(t)
    local k, c = start({ arrow = true, pin = { map = DUROTAR, x = 0.5, y = 0.4 } })
    t.eq(c.arrows[1].lines, { N.WAYPOINT_LABEL, "100 yd N" })
    t.eq(k.problems:count(), 0)
end

tests["travel: look only - nothing casts, talks, flies or clicks for you"] = function(t)
    for name in pairs(T) do
        local n = tostring(name):lower()
        t.ok(not (n:find("cast") or n:find("click") or n:find("use") or n:find("take") or n:find("fly")),
            "no acting function: " .. n)
    end
end

return tests
