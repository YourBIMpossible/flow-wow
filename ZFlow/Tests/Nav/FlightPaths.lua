local _, ns = ...

-- Tests for ZFlow/Nav/FlightPaths.lua (S30, LEDGER 143): flight paths to
-- learn. Ported from Flow's Modules/Nav/FlightPaths.lua; see
-- WoW/from-zen/RESEARCH-S30.md. Hand-written places only. Advice only:
-- nothing talks to an NPC or takes a flight.

local FP = ns.FlightPaths
local tests = {}

local SIZE = { w = 1000, h = 1000 }          -- a map 1000 yards square
local function size() return SIZE end

local function npcs()
    return {
        ["Karos"] = { map = 1411, x = 0.50, y = 0.50, roles = { flight = true }, factions = { Horde = true }, seen = 10 },
        ["Devrak"] = { map = 1413, x = 0.20, y = 0.20, kind = "flight", factions = { Horde = true } },
        ["Thor"] = { map = 1411, x = 0.10, y = 0.10, roles = { flight = true }, factions = { Alliance = true } },
        ["Unknown Side"] = { map = 1411, x = 0.30, y = 0.30, roles = { flight = true } },
        ["Smith"] = { map = 1411, x = 0.52, y = 0.52, roles = { repair = true }, factions = { Horde = true } },
        ["Nowhere"] = { map = 1411, x = 7, y = 0.5, roles = { flight = true }, factions = { Horde = true } },
        ["Silva"] = { map = 1411, x = 0.60, y = 0.60, roles = { flight = true }, factions = { Horde = true } },
    }
end

local function names(list)
    local out = {}
    for i, fm in ipairs(list) do out[i] = fm.name end
    return out
end

-- ------------------------------------------------------------------ Waits
-- Flow Modules/Nav/FlightPaths.lua:32-39.

tests["flight paths: a 'no flight path here' note holds until a level is gained"] = function(t)
    t.eq(FP.Waits(nil, 10), false, "no note")
    t.eq(FP.Waits(true, 10), false, "an older note with no level no longer holds")
    t.eq(FP.Waits({ level = 10 }, 10), true, "the same level: still held back")
    t.eq(FP.Waits({ level = 10 }, 11), false, "a level gained: asked once more")
    t.eq(FP.Waits({ level = 10 }, nil), true, "level not known: not released on a guess")
end

-- ------------------------------------------------------------------ Masters

tests["flight paths: the candidates are learned flight masters of your faction"] = function(t)
    local list = FP.Masters(npcs(), "Horde", function(name) return name == "Silva" end)
    t.eq(names(list), { "Devrak", "Karos" }, "by name; no other faction, no unknown side, no repairer, no bad place, no ride")
    t.eq(list[2], { name = "Karos", map = 1411, x = 0.50, y = 0.50, seen = 10 })
    t.eq(FP.Masters(npcs(), nil), {}, "faction not known: no candidates")
    t.eq(FP.Masters(nil, "Horde"), {}, "no places saved")
    t.eq(#FP.Masters(npcs(), "Horde"), 3, "with no ride list, Silva is a candidate")
end

-- ------------------------------------------------------------------ Learned
-- Flow :40-54.

tests["flight paths: learned once you opened that master's flight map"] = function(t)
    local fm = { name = "Karos", map = 1411, x = 0.5, y = 0.5 }
    t.eq(FP.Learned(fm, { talked = { Karos = true } }), true)
    t.eq(FP.Learned(fm, { talked = { Devrak = true } }), false)
    t.eq(FP.Learned(fm, {}), false, "nothing known: not learned")
    t.eq(FP.Learned(fm, nil), false)
end

tests["flight paths: held back while its no-path note holds"] = function(t)
    local fm = { name = "Karos", map = 1411, x = 0.5, y = 0.5 }
    t.eq(FP.Learned(fm, { none = { Karos = { level = 12 } }, level = 12 }), true)
    t.eq(FP.Learned(fm, { none = { Karos = { level = 12 } }, level = 13 }), false)
end

tests["flight paths: learned when a flight master you used stands within 250 yards"] = function(t)
    local fm = { name = "Karos", map = 1411, x = 0.5, y = 0.5 }
    local function seen(x, y, map, kinds)
        return { ["Creature-1"] = { name = "Other Name", map = map or 1411, x = x, y = y, kinds = kinds or { flight = true } } }
    end
    t.eq(FP.SAME, 250)
    t.eq(FP.Learned(fm, { seen = seen(0.6, 0.5), size = size }), true, "100 yards away")
    t.eq(FP.Learned(fm, { seen = seen(0.9, 0.5), size = size }), false, "400 yards away")
    t.eq(FP.Learned(fm, { seen = seen(0.6, 0.5, 1413), size = size }), false, "another map")
    t.eq(FP.Learned(fm, { seen = seen(0.6, 0.5, nil, { vendor = true }), size = size }), false, "not a flight master")
    t.eq(FP.Learned(fm, { seen = seen(0.6, 0.5) }), false, "map size not known: distance is not guessed")
    local same = { k = { name = "Karos", map = 1411, x = 0.9, y = 0.9, kinds = { flight = true } } }
    t.eq(FP.Learned(fm, { seen = same }), true, "the same name is the same master, size or no size")
end

-- ------------------------------------------------------------------ Goals
-- Flow :56-85.

tests["flight paths: one goal for each master not learned, worded as Flow words it"] = function(t)
    local goals = FP.Goals(FP.Masters(npcs(), "Horde"), { talked = { Devrak = true } }, nil)
    t.eq(names(goals), { "Karos", "Silva" })
    local g = goals[1]
    t.eq(g.key, "flightpath:Karos")
    t.eq(g.kind, "flight")
    t.eq(g.text, "Learn the flight path: Karos")
    t.eq(g.place, { map = 1411, x = 0.50, y = 0.50 })
    t.eq(g.optional, true, "where you are is not known: only when it is on the way")
    t.eq(g.weight, 1)
    t.eq(g.details[1], "You don't have this flight path yet. Talk to Karos once: it's free, and later trips through here are shorter for it.")
end

tests["flight paths: a master on your map within 800 yards is a step in its own right"] = function(t)
    local masters = FP.Masters(npcs(), "Horde")
    local near = FP.Goals(masters, {}, { map = 1411, x = 0.5, y = 0.9, size = SIZE })   -- 400 yd from Karos
    local karos
    for _, g in ipairs(near) do if g.name == "Karos" then karos = g end end
    t.eq(FP.HERE, 800)
    t.eq(karos.optional, nil, "close: not only 'when on the way'")
    t.eq(karos.weight, 0.8)
    t.eq(karos.yards, 400)
    local far = FP.Goals(masters, {}, { map = 1411, x = 0.5, y = 0.9 })                 -- no size
    t.eq(far[1].optional, true, "distance not known: optional, never 'close' on a guess")
    t.eq(far[1].yards, nil)
    local other = FP.Goals(masters, {}, { map = 1413, x = 0.2, y = 0.2, size = SIZE })
    for _, g in ipairs(other) do
        if g.name == "Karos" then t.eq(g.optional, true, "on another map: optional") end
    end
end

tests["flight paths: the nearest on your map first, and no more than the limit"] = function(t)
    local many = {}
    for i = 1, 40 do
        many[#many + 1] = { name = string.format("M%02d", i), map = 1411, x = i / 100, y = 0.5 }
    end
    local goals = FP.Goals(many, {}, { map = 1411, x = 0.402, y = 0.5, size = SIZE })
    t.eq(FP.MAX, 30)
    t.eq(#goals, 30)
    t.eq(goals[1].name, "M40", "2 yards away")
    t.eq(goals[2].name, "M39", "then 12 yards away")
    local dup = FP.Goals({ { name = "A", map = 1, x = 0.1, y = 0.1 }, { name = "A", map = 1, x = 0.2, y = 0.2 } }, {}, nil)
    t.eq(#dup, 1, "a name once")
end

-- ------------------------------------------------------------------ Step

tests["flight paths: the step is the nearest goal on your map, in the guide's shape"] = function(t)
    local here = { map = 1411, x = 0.52, y = 0.52, size = SIZE }
    local goals = FP.Goals(FP.Masters(npcs(), "Horde"), {}, here)
    local step = FP.Step(goals, here, { cont = 1 })
    t.eq(step.label, "Learn the flight path: Karos")
    t.eq(step.place, { cont = 1, map = 1411, x = 0.50, y = 0.50 })
    t.eq(step.radius, FP.NEAR)
    t.eq(step.kind, "flight")
    t.eq(FP.Step(goals, { map = 9999, x = 0.5, y = 0.5 }, nil), nil, "nothing on your map: no step")
    t.eq(FP.Step({}, here, nil), nil)
    t.eq(FP.Step(goals, nil, nil), nil, "where you are is not known: no step")
    local long = { { name = string.rep("x", 60), key = "k", kind = "flight", place = { map = 1411, x = 0.5, y = 0.5 },
                     text = "Learn the flight path: " .. string.rep("x", 60) } }
    t.eq(FP.Step(long, here, nil).label, nil, "a label over the waypoint limit is left out, never cut")
end

-- ------------------------------------------------------------------ module

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { learned = { places = { npcs = npcs() } } })
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setFaction("Horde")
    c.setZone(1, 1411)
    c.setPosition(1411, 0.52, 0.52)
    c.setMapSize(1411, 1000, 1000)
    if type(c.setLevel) == "function" then c.setLevel(12) else c.level = function() return 12 end end
    local npc = nil
    c.serviceNpc = function() return npc end
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    if opts.setting ~= nil then
        k:Setting({ key = FP.SETTING, scope = "char", type = "bool", default = true, label = "Flight paths to learn" })
    end
    local api = FP.Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    if opts.setting == false then k.settings:set(FP.SETTING, false) end
    return k, c, api, function(name) npc = name and { name = name } or nil end
end

local function flights(c)
    local s = c.saved(ns.id.charDB)
    local learned = type(s) == "table" and s.learned or nil
    return type(learned) == "table" and type(learned.flights) == "table" and learned.flights or {}
end

tests["flight paths module: it provides the goals and the step"] = function(t)
    local k, _, api = start()
    t.eq((k:ModuleState(FP.NAME)), "started")
    local provided = k.use(FP.NAME)
    t.ok(type(provided.Goals) == "function" and type(provided.Step) == "function")
    t.eq(names(api.goals()), { "Karos", "Silva", "Devrak" }, "the two on your map nearest first, then the rest")
    t.eq(api.step().label, "Learn the flight path: Karos")
end

tests["flight paths module: opening a flight map marks that master learned"] = function(t)
    local _, c, api, at = start()
    at("Karos")
    c.fire("TAXIMAP_OPENED")
    t.eq((flights(c).talked or {}).Karos, true, "saved for this character")
    t.eq(names(api.goals()), { "Silva", "Devrak" }, "and gone from the goals at once")
end

tests["flight paths module: a talk with no flight map within 3 seconds is noted, once per level"] = function(t)
    local _, c, api, at = start()
    at("Karos")
    c.fire("GOSSIP_SHOW")
    c.advance(FP.WAIT + 0.5, 8)
    local note = (flights(c).none or {}).Karos
    t.ok(type(note) == "table" and note.level == 12, "noted with your level")
    t.eq(c.printed[#c.printed], ns.id.title .. ": Karos has no flight path for you yet. It will be suggested again when you have gained a level.")
    t.eq(names(api.goals()), { "Silva", "Devrak" }, "held back at this level")
    c.level = function() return 13 end
    if type(c.setLevel) == "function" then c.setLevel(13) end
    t.eq(names(api.goals())[1], "Karos", "a level gained: suggested again")
end

tests["flight paths module: a flight map inside the wait cancels the note"] = function(t)
    local _, c, _, at = start()
    at("Karos")
    c.fire("GOSSIP_SHOW")
    c.advance(1, 2)
    c.fire("TAXIMAP_OPENED")
    c.advance(FP.WAIT + 0.5, 8)
    t.eq((flights(c).none or {}).Karos, nil, "no note: they do have a flight path")
    t.eq(#c.printed, 0)
end

-- Review of 211e99b (medium, F-086): a flight map did open; that the NPC
-- read failed at that moment is not "they have no flight path".
tests["flight paths module: a flight map with the NPC not read still cancels the note"] = function(t)
    local _, c, api, at = start()
    at("Karos")
    c.fire("GOSSIP_SHOW")
    c.advance(1, 2)
    at(nil)                                   -- the NPC read gives nothing now
    c.fire("TAXIMAP_OPENED")
    c.advance(FP.WAIT + 0.5, 8)
    t.eq((flights(c).none or {}).Karos, nil, "no 'no flight path' note: a flight map opened")
    t.eq(#c.printed, 0, "and no chat line")
    t.eq((flights(c).talked or {}).Karos, nil, "nor is anyone marked learned on a guess")
    at("Karos")
    t.eq(api.goals()[1].name, "Karos", "the goal simply stays")
end

tests["flight paths module: talking to someone who is no goal notes nothing"] = function(t)
    local _, c, _, at = start()
    at("Smith")
    c.fire("MERCHANT_SHOW")
    c.advance(FP.WAIT + 0.5, 8)
    t.eq(flights(c).none, nil)
    at(nil)
    c.fire("QUEST_GREETING")
    c.advance(FP.WAIT + 0.5, 8)
    t.eq(flights(c).none, nil, "no NPC read: nothing guessed")
end

tests["flight paths module: nav.flightPaths off gives no goals and writes nothing"] = function(t)
    local _, c, api, at = start({ setting = false })
    t.eq(api.goals(), {})
    t.eq(api.step(), nil)
    at("Karos")
    c.fire("GOSSIP_SHOW")
    c.advance(FP.WAIT + 0.5, 8)
    t.eq(flights(c).none, nil)
    t.eq(FP.SETTING, "nav.flightPaths")
end

tests["flight paths: advice only - nothing takes a flight or talks for you"] = function(t)
    for name in pairs(FP) do
        local n = tostring(name):lower()
        t.ok(not (n:find("take") or n:find("fly$") or n:find("interact") or n:find("click")), "no acting function: " .. n)
    end
end

return tests
