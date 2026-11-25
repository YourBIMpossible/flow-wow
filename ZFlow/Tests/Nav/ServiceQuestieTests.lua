-- Nearest service from the player's own Questie (parity rows A2-10 and the
-- data half of A1-41; lead section 611). The one pass over Questie's NPCs
-- (Nav/ProfStep.lua N.ProfPlace, owned by Nav/ProfFeed.lua) also keeps the
-- vendors, repair vendors, flight masters and innkeepers by their npcFlags,
-- and N.Nearest (Nav/ServiceNearest.lua) asks the feed for Questie's
-- nearest of a kind: on the player's map the nearer of a saved place and
-- Questie's wins (a tie: the saved one), as in Flow's Services.lua; with
-- none on this map, Questie's nearest on the continent. A place from
-- Questie is marked unvisited and is never said to be seen or used.
-- No Questie, nothing found, the other faction's, across the sea: as it
-- was. A mailbox is no NPC: Questie is never asked. Look only.
-- Every name, place and number is made up, test only. Not seen in game.
--
-- Red before the code: no such lists, no PP.Service, and N.Nearest asks
-- nobody.
local _, ns = ...

local T = {}

local MAP, NEXT_MAP, SEA_MAP = 1411, 1412, 1453
local AREA, NEXT_AREA, SEA_AREA = 31, 32, 33
local AREAS = { [AREA] = MAP, [NEXT_AREA] = NEXT_MAP, [SEA_AREA] = SEA_MAP }
local VENDOR, FLIGHT, INN, BANKER, AUCTION, REPAIR = 4, 8, 128, 256, 4096, 16384
local SMITH = "Smith Made Up"
local LOW = { [5] = { cur = 5, max = 100 } }

-- A stand-in for Questie's two modules. rows = { [id] = { name, flags,
-- side, area, x } } (y is 50); state.scans counts the passes over its
-- NPCs, state.names the reads of a name.
local function questie(state, rows, own)
    local npcs, first = {}, nil
    for id, r in pairs(rows) do
        npcs[id] = { name = r.name, npcFlags = r.flags, friendlyToFaction = r.side,
                     spawns = { [r.area or AREA] = { { r.x, 50 } } } }
        if first == nil or id < first then first = id end
    end
    local db = { QuestPointers = {}, NPCPointers = {}, npcFlags = own }
    for id in pairs(npcs) do db.NPCPointers[id] = true end
    function db.QueryQuestSingle() return nil end
    function db.QueryNPCSingle(id, field)
        if id == first and field == "npcFlags" then state.scans = (state.scans or 0) + 1 end
        if field == "name" then state.names = (state.names or 0) + 1 end
        return npcs[id] and npcs[id][field]
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(a) return AREAS[a] end
    return db, zones
end

local function parts(t, a)
    local N = type(a.Nav) == "table" and a.Nav or {}
    local PP = N.ProfPlace
    local ok = type(PP) == "table" and type(PP.Service) == "function" and type(N.Nearest) == "function"
        and type(N.READING) == "string"
    t.ok(ok, "N.ProfPlace.Service, N.Nearest and N.READING are there")
    if not ok then return nil end
    return N, PP
end

local function smith(x, name)
    return { name = name or "Smith Saved", map = MAP, x = x, y = 0.5, kinds = { repair = true }, seen = 10, n = 1 }
end

-- The whole add-on on a fake client: a Horde player in the middle of map
-- 1411, 1000 by 500 yards. opts: rows (Questie's NPCs; nil: no Questie),
-- state, own (Questie's own flag list), services (the character's saved
-- places), durability, combat.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, { learned = { places = { services = opts.services } } })
    c.setScreen(1024, 768)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 500)
    c.setMapCont(MAP, 1); c.setMapCont(NEXT_MAP, 1); c.setMapCont(SEA_MAP, 2)
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setLevel(20)
    c.setDurability(opts.durability)
    if opts.combat then c.setCombat(true) end
    if opts.rows then
        local db, zones = questie(opts.state or {}, opts.rows, opts.own)
        c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

-- N.Nearest of the loaded add-on, once Questie had its frames.
local function nearest(c, addon, kind)
    local N = addon.Nav
    N.Nearest(kind, c, addon.store, addon.use)
    c.advance(1, 20)
    return N.Nearest(kind, c, addon.store, addon.use)
end

-- ------------------------------------------------------------- the pass

T["service questie: the pass keeps vendors, repair vendors, flight masters and innkeepers by flag"] = function(t)
    local _, PP = parts(t, ns)
    if not PP then return end
    local state = {}
    local found, n = PP.Scan(questie(state, {
        [1] = { name = "Seller", flags = VENDOR, side = "H", x = 60 },
        [2] = { name = SMITH, flags = VENDOR + REPAIR, side = "AH", x = 70 },
        [3] = { name = "Wing Hand", flags = FLIGHT, side = "H", x = 20 },
        [4] = { name = "Host", flags = INN + VENDOR, side = "A", x = 30 },
        [5] = { name = "Teacher", flags = 16, side = "H", x = 40 },
        [6] = { name = "Wolf", x = 45 },
    }))
    t.eq(found.vendor and #found.vendor, 3, "three with the vendor bit")
    t.eq(found.repair, { { name = SMITH, map = MAP, x = 0.7, y = 0.5, side = "AH" } }, "the repair bit")
    t.eq(found.flight, { { name = "Wing Hand", map = MAP, x = 0.2, y = 0.5, side = "H" } }, "the flight master bit")
    t.eq(found.innkeeper, { { name = "Host", map = MAP, x = 0.3, y = 0.5, side = "A" } }, "the innkeeper bit")
    t.eq(found.banker, {}, "no banker among them")
    t.eq(n, 6, "six places in all: one for each list an NPC is in")
    t.eq(state.names, 4, "a name is read only of an NPC that is kept")
end

T["service questie: a list is made only once an NPC of that kind is met"] = function(t)
    local _, PP = parts(t, ns)
    if not PP then return end
    local found = PP.Scan(questie({}, { [1] = { name = "Teacher", flags = 16, side = "H", x = 40 } }))
    t.eq(found, { trainer = {}, banker = {}, auction = {} }, "none met: the answer as it was")
    t.eq(PP.Scan(nil, nil), { trainer = {}, banker = {}, auction = {} }, "no Questie: the same")
end

T["service questie: Questie's own flag list comes before the first game's numbers"] = function(t)
    local _, PP = parts(t, ns)
    if not PP then return end
    local rows = {
        [1] = { name = "By Own List", flags = 1024, side = "H", x = 60 },
        [2] = { name = "By Old Number", flags = REPAIR, side = "H", x = 70 },
        [3] = { name = "Wing Hand", flags = FLIGHT, side = "H", x = 20 },
    }
    local found = PP.Scan(questie({}, rows, { REPAIR = 1024 }))
    t.eq(found.repair, { { name = "By Own List", map = MAP, x = 0.6, y = 0.5, side = "H" } }, "its own repair bit")
    t.eq(found.flight and #found.flight, 1, "a kind its list does not name keeps the first game's number")
end

-- --------------------------------------------------------------- pure

T["service questie: Questie's nearest of a kind, this map first, then the continent, by faction"] = function(t)
    local _, PP = parts(t, ns)
    if not PP then return end
    local found = PP.Scan(questie({}, {
        [1] = { name = "Far Smith", flags = REPAIR, side = "H", x = 90 },
        [2] = { name = SMITH, flags = REPAIR, side = "AH", x = 60 },
        [3] = { name = "Their Smith", flags = REPAIR, side = "A", x = 51 },
        [4] = { name = "Next Host", flags = INN, side = "H", area = NEXT_AREA, x = 30 },
        [5] = { name = "Sea Wing", flags = FLIGHT, side = "H", area = SEA_AREA, x = 30 },
    }))
    local known = {
        here = { map = MAP, x = 0.5, y = 0.5, faction = "Horde", size = { w = 1000, h = 500 } },
        contOf = function(map) return ({ [MAP] = 1, [NEXT_MAP] = 1, [SEA_MAP] = 2 })[map] end,
        questie = function() return found end,
    }
    t.eq(PP.Service("repair", known), { name = SMITH, map = MAP, x = 0.6, y = 0.5 },
        "the nearest the player's faction can use, not the nearer one of the other")
    t.eq(PP.Service("innkeeper", known), { name = "Next Host", map = NEXT_MAP, x = 0.3, y = 0.5 },
        "none on this map: one on the continent")
    t.eq(PP.Service("flight", known), nil, "across the sea: no place")
    t.eq(PP.Service("vendor", known), nil, "none of that kind: no place")
    t.eq(PP.Service("mailbox", known), nil, "a mailbox is no NPC")
    t.eq(PP.Service("trainer", known), nil, "a kind that is no service")
    known.questie = nil
    t.eq(PP.Service("repair", known), nil, "no Questie: no place")
end

-- ------------------------------------------------------------ N.Nearest

T["service questie: nothing saved, and Questie's repair vendor is the nearest, marked unvisited"] = function(t)
    local state = {}
    local c, addon = boot({ state = state, rows = {
        [1] = { name = SMITH, flags = VENDOR + REPAIR, side = "H", x = 60 },
        [2] = { name = "Their Smith", flags = REPAIR, side = "A", x = 51 },
    } })
    local N = parts(t, addon)
    if not N then return end
    local first, why = N.Nearest("repair", c, addon.store, addon.use)
    t.eq(first, nil, "asked: no answer yet, nothing is read in the ask")
    t.eq(why, N.READING, "and it says Questie's list is still being gone through")
    t.eq(state.scans, nil, "not gone through in the ask itself")
    c.advance(1, 20)
    local got, after = N.Nearest("repair", c, addon.store, addon.use)
    t.eq(got and got.name, SMITH, "Questie's smith of the player's faction")
    t.eq(got and got.kind, "repair")
    t.eq(got and { got.map, got.x, got.y, got.cont }, { MAP, 0.6, 0.5, 1 }, "its place, on the player's continent")
    t.eq(got and got.yards, 100, "100 yards east")
    t.eq(got and got.unvisited, true, "marked as not visited")
    t.eq(got and got.seen, nil, "never said to be seen")
    t.ok(got and got.key ~= nil, "with a key of its own")
    t.eq(after, nil, "nothing more to wait for")
    t.eq(addon.store:get("char", N.SERVICES), nil, "and nothing is saved by asking")
end

T["service questie: on this map the nearer of a saved place and Questie's wins, a tie goes to the saved one"] = function(t)
    local rows = { [1] = { name = SMITH, flags = REPAIR, side = "H", x = 60 } }
    local c, addon = boot({ rows = rows, services = { s1 = smith(0.55) } })
    local N = parts(t, addon)
    if not N then return end
    local got = nearest(c, addon, "repair")
    t.eq(got and got.key, "s1", "the saved smith 50 yards off, not Questie's at 100")
    t.eq(got and got.unvisited, nil, "a saved place is not marked")
    t.eq(got and got.seen, 10)
    local c2, addon2 = boot({ rows = rows, services = { s1 = smith(0.4) } })
    local tie = nearest(c2, addon2, "repair")
    t.eq(tie and tie.key, "s1", "both 100 yards off: the saved one")
    local c3, addon3 = boot({ rows = rows, services = { s1 = smith(0.9) } })
    local far = nearest(c3, addon3, "repair")
    t.eq(far and far.name, SMITH, "the saved one 400 yards off: Questie's at 100 is the nearest")
    t.eq(far and far.unvisited, true)
end

T["service questie: Questie's NPC the character has used is the saved place, not an unvisited one"] = function(t)
    local c, addon = boot({ rows = { [1] = { name = SMITH, flags = REPAIR, side = "H", x = 60 } },
        services = { far = smith(0.9), s1 = smith(0.62, SMITH) } })
    local N = parts(t, addon)
    if not N then return end
    local got = nearest(c, addon, "repair")
    t.eq(got and got.key, "s1", "the same name on the same map: the place saved for it")
    t.eq(got and got.unvisited, nil)
    t.eq(got and got.x, 0.62, "where the character used it")
end

T["service questie: the other faction's, one across the sea, and no Questie give what was given before"] = function(t)
    local state = {}
    local c, addon = boot({ state = state, rows = {
        [1] = { name = "Their Smith", flags = REPAIR, side = "A", x = 60 },
        [2] = { name = "Sea Smith", flags = REPAIR, side = "H", area = SEA_AREA, x = 60 },
    } })
    local N = parts(t, addon)
    if not N then return end
    t.eq(nearest(c, addon, "repair"), nil, "nothing saved and none the player can use here: nil")
    t.eq(state.scans, 1, "Questie was gone through, and gave none")
    local c2, addon2 = boot({ services = { s1 = smith(0.9) } })
    local N2 = addon2.Nav
    local got, why = N2.Nearest("repair", c2, addon2.store, addon2.use)
    t.eq(got, N2.NearestOf("repair", addon2.store:get("char", N2.SERVICES),
        { map = MAP, x = 0.5, y = 0.5, cont = 1, size = { w = 1000, h = 500 } }), "no Questie: the saved place, as before")
    t.eq(why, nil, "and nothing is waited for")
    local c3, addon3 = boot({})
    t.eq(addon3.Nav.Nearest("repair", c3, addon3.store, addon3.use), nil, "no Questie and nothing saved: nil")
end

T["service questie: with none on this map, Questie's on another map of the continent"] = function(t)
    local c, addon = boot({ rows = {
        [1] = { name = "Next Smith", flags = REPAIR, side = "H", area = NEXT_AREA, x = 30 },
        [2] = { name = "Sea Smith", flags = REPAIR, side = "H", area = SEA_AREA, x = 30 },
    } })
    local N = parts(t, addon)
    if not N then return end
    local got = nearest(c, addon, "repair")
    t.eq(got and got.name, "Next Smith", "the one on this continent")
    t.eq(got and got.map, NEXT_MAP)
    t.eq(got and got.unvisited, true)
    t.eq(got and got.yards, nil, "how far is not known across maps: left out, never 0")
end

T["service questie: a mailbox never asks Questie"] = function(t)
    local state = {}
    local c, addon = boot({ state = state, rows = { [1] = { name = SMITH, flags = VENDOR + REPAIR, side = "H", x = 60 } },
        services = { box = { map = MAP, x = 0.5, y = 0.25, kinds = { mailbox = true } } } })
    local N = parts(t, addon)
    if not N then return end
    local got, why = N.Nearest("mailbox", c, addon.store, addon.use)
    t.eq(got and got.key, "box", "the saved mailbox")
    t.eq(why, nil)
    c.advance(30, 120)
    t.eq(state.scans, nil, "Questie's NPCs were not gone through at all")
    local c2, addon2 = boot({ state = state, rows = { [1] = { name = SMITH, flags = VENDOR, side = "H", x = 60 } } })
    t.eq(addon2.Nav.Nearest("mailbox", c2, addon2.store, addon2.use), nil, "none saved: nil")
    c2.advance(30, 120)
    t.eq(state.scans, nil, "still not gone through")
end

T["service questie: the pass runs once for every kind, and never in combat"] = function(t)
    local state = {}
    local c, addon = boot({ state = state, combat = true, rows = {
        [1] = { name = SMITH, flags = VENDOR + REPAIR, side = "H", x = 60 },
        [2] = { name = "Wing Hand", flags = FLIGHT, side = "H", x = 20 },
        [3] = { name = "Host", flags = INN, side = "H", x = 30 },
        [4] = { name = "Coin Keeper", flags = BANKER, side = "H", x = 40 },
        [5] = { name = "Crier", flags = AUCTION, side = "H", x = 45 },
    } })
    local N = parts(t, addon)
    if not N then return end
    t.eq(nearest(c, addon, "repair"), nil, "in combat: nothing yet")
    t.eq(state.scans, nil, "in combat: Questie's NPCs are not gone through")
    c.setCombat(false)
    local names = { vendor = SMITH, repair = SMITH, flight = "Wing Hand", innkeeper = "Host",
                    banker = "Coin Keeper", auction = "Crier" }
    for kind, name in pairs(names) do
        local got = nearest(c, addon, kind)
        t.eq(got and got.name, name, kind)
        t.eq(got and got.unvisited, true, kind .. ": from Questie")
    end
    for _ = 1, 5 do
        for kind in pairs(names) do N.Nearest(kind, c, addon.store, addon.use) end
        c.advance(6, 24)
    end
    t.eq(state.scans, 1, "one pass over Questie's NPCs for all of that")
end

-- -------------------------------------------------------------- callers

T["service questie: the repair step gets a place from Questie when none is saved, with no command typed"] = function(t)
    local c, addon = boot({ durability = LOW, rows = { [1] = { name = SMITH, flags = VENDOR + REPAIR, side = "H", x = 60 } } })
    local RS = addon.RepairStep
    local ok = parts(t, addon) ~= nil and type(RS) == "table" and type(RS.FROM_QUESTIE) == "string"
        and type(RS.LISTED) == "string" and type(RS.SEEN) == "string"
    t.ok(ok, "the repair step has its lines for a place from Questie")
    if not ok then return end
    local api = addon.use(RS.NAME)
    -- The nearest is kept RS.KEEP seconds: asked again after that.
    c.advance(RS.KEEP + 1, 44)
    local step = api.Step()
    t.eq(step and step.kind, RS.KIND)
    t.eq(step and step.place, { cont = 1, map = MAP, x = 0.6, y = 0.5 }, "Questie's repair vendor")
    t.eq(step and step.name, SMITH)
    t.eq(step and step.yards, 100)
    t.eq(step and step.unvisited, true, "marked as not visited")
    t.ok(step and step.from ~= "seen", "not said to be seen")
    t.eq(step and step.detail, RS.FROM_QUESTIE, "the arrow's line says where it is from")
    local where = SMITH .. ", about 100 yd"
    local lines = api.Lines()
    local listed, seen = false, false
    for _, line in ipairs(lines) do
        if line == RS.LISTED:format(where) then listed = true end
        if line == RS.SEEN:format(where) then seen = true end
    end
    t.eq(listed, true, "its line is the one for a place from Questie")
    t.eq(seen, false, "never the line for a place the player has seen")
end

T["service questie: a saved repair vendor nearer than Questie's keeps the repair step as it was"] = function(t)
    local c, addon = boot({ durability = LOW, services = { s1 = smith(0.55) },
        rows = { [1] = { name = SMITH, flags = REPAIR, side = "H", x = 60 } } })
    local RS = addon.RepairStep
    if not parts(t, addon) then return end
    c.advance(RS.KEEP + 1, 44)
    local step = addon.use(RS.NAME).Step()
    t.eq(step and step.name, "Smith Saved")
    t.eq(step and step.from, "seen")
    t.eq(step and step.unvisited, nil)
    t.eq(step and step.detail, nil)
end

T["service questie: the stop word and the way word take Questie's place, marked as from Questie"] = function(t)
    local c, addon = boot({ rows = { [1] = { name = SMITH, flags = VENDOR + REPAIR, side = "H", x = 60 } } })
    local E = addon.Errand
    local ok = parts(t, addon) ~= nil and type(E) == "table" and type(E.FROM_QUESTIE) == "string"
    t.ok(ok, "the errand has its line for a place from Questie")
    if not ok then return end
    local slash = c.slashes[ns.id.slash]
    slash("stop repair")
    local api = addon.use(E.NAME)
    t.eq(api.Stop(), nil, "the first ask: Questie's list is not gone through yet, no stop")
    c.advance(1, 20)
    slash("stop repair")
    local stop = api.Stop()
    t.eq(stop and stop.name, SMITH)
    t.eq(stop and stop.unvisited, true)
    local step = api.Step()
    t.eq(step and step.place, { cont = 1, map = MAP, x = 0.6, y = 0.5 })
    t.eq(step and step.detail, E.FROM_QUESTIE, "the arrow's line says where it is from")
    slash("way vendor")
    local W = ns.Nav.Waypoint
    local slot = addon.store:get(W.SCOPE, W.PATH)
    local wp = type(slot) == "table" and slot.waypoint or nil
    t.eq(wp and { wp.map, wp.x, wp.y }, { MAP, 0.6, 0.5 }, "a waypoint at Questie's vendor")
end

T["service questie: a stop from a saved place has no line about Questie"] = function(t)
    local c, addon = boot({ services = { s1 = smith(0.55) } })
    local E = addon.Errand
    if not parts(t, addon) then return end
    c.slashes[ns.id.slash]("stop repair")
    local api = addon.use(E.NAME)
    t.eq(api.Stop() and api.Stop().key, "s1")
    t.eq(api.Step() and api.Step().detail, nil)
end

return T
