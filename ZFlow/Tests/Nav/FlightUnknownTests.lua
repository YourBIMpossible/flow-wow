-- Flight masters the player has not learned yet (parity row B-08, the data
-- half; lead section 611). Questie's flight masters (the one pass of
-- Nav/ProfStep.lua N.ProfPlace, owned by Nav/ProfFeed.lua) on the player's
-- continent and of the player's faction, without those whose flight point
-- this character knows: the points saved from the flight maps it opened
-- (char "learned.flights.nodes", Nav/Flights.lua), as the predecessor's
-- Modules/Nav/MapFlights.lua (MF.Pins) and FlightPaths.lua (FP.Learned).
-- Unknown stays unknown: no saved point on the continent, no Questie, no
-- continent or no faction is nil and a reason, never "all unknown".
-- Data only: no pin, no window, no word. Look only.
-- Every name, place and number is made up, test only. Not seen in game.
--
-- Red before the code: no N.FlightUnknown, no PP.List, no List on the feed.
local _, ns = ...

local T = {}

local MAP, NEXT_MAP, SEA_MAP, LOST_MAP = 1411, 1412, 1453, 1460
local AREA, NEXT_AREA, SEA_AREA, LOST_AREA = 31, 32, 33, 34
local AREAS = { [AREA] = MAP, [NEXT_AREA] = NEXT_MAP, [SEA_AREA] = SEA_MAP, [LOST_AREA] = LOST_MAP }
local VENDOR, FLIGHT, REPAIR = 4, 8, 16384
-- Map 1411 is 1000 by 500 yards with its top left at the world's 0, 0;
-- map 1412 lies east of it; map 1453 is on another continent; map 1460
-- has no corners (the client does not place it in the world).
local CORNERS = {
    [MAP] = { cont = 1, ox = 0, oy = 0, ex = 1000, ey = 0, sx = 0, sy = 500 },
    [NEXT_MAP] = { cont = 1, ox = 1000, oy = 0, ex = 2000, ey = 0, sx = 1000, sy = 500 },
    [SEA_MAP] = { cont = 2, ox = 0, oy = 0, ex = 1000, ey = 0, sx = 0, sy = 500 },
}
-- A flight point this character knows, 10 yards from "Near Wing".
local NODES = { ["Near Town"] = { cont = 1, wx = 210, wy = 250 } }
local ROWS = {
    [1] = { name = "Near Wing", flags = FLIGHT, side = "H", x = 20 },
    [2] = { name = "Far Wing", flags = FLIGHT + VENDOR, side = "AH", x = 90 },
    [3] = { name = "Their Wing", flags = FLIGHT, side = "A", x = 70 },
    [4] = { name = "Sea Wing", flags = FLIGHT, side = "H", area = SEA_AREA, x = 30 },
    [5] = { name = "Next Wing", flags = FLIGHT, side = "H", area = NEXT_AREA, x = 30 },
    [6] = { name = "Smith Made Up", flags = REPAIR, side = "H", x = 60 },
}

-- A stand-in for Questie's two modules (as Tests/Nav/ServiceQuestieTests.lua).
-- rows = { [id] = { name, flags, side, area, x } } (y is 50); state.scans
-- counts the passes over its NPCs.
local function questie(state, rows)
    local npcs, first = {}, nil
    for id, r in pairs(rows) do
        npcs[id] = { name = r.name, npcFlags = r.flags, friendlyToFaction = r.side,
                     spawns = { [r.area or AREA] = { { r.x, 50 } } } }
        if first == nil or id < first then first = id end
    end
    local db = { QuestPointers = {}, NPCPointers = {} }
    for id in pairs(npcs) do db.NPCPointers[id] = true end
    function db.QueryQuestSingle() return nil end
    function db.QueryNPCSingle(id, field)
        if id == first and field == "npcFlags" then state.scans = (state.scans or 0) + 1 end
        return npcs[id] and npcs[id][field]
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(a) return AREAS[a] end
    return db, zones
end

local function parts(t, a)
    local N = type(a.Nav) == "table" and a.Nav or {}
    local PP, FU = N.ProfPlace, N.FlightUnknown
    local ok = type(PP) == "table" and type(PP.List) == "function" and type(FU) == "table"
        and type(FU.Of) == "function" and type(FU.Learned) == "function" and type(FU.Placed) == "function"
        and type(FU.KnowsOn) == "function" and type(FU.NAME) == "string"
        and type(FU.READING) == "string" and type(FU.NO_QUESTIE) == "string" and type(FU.NO_KNOWN) == "string"
        and type(FU.NO_CONTINENT) == "string" and type(FU.NO_FACTION) == "string"
    t.ok(ok, "N.ProfPlace.List and N.FlightUnknown with its rules and reasons are there")
    if not ok then return nil end
    return FU, PP, N
end

-- The whole add-on on a fake client: a Horde player in the middle of map
-- 1411. opts: rows (Questie's NPCs; nil: no Questie), state, nodes (the
-- character's saved flight points), talked, combat, faction (false: not
-- known), noCorners (the player's map is not placed in the world).
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setSaved(ns.id.charDB, { learned = { flights = { nodes = opts.nodes, talked = opts.talked } } })
    c.setScreen(1024, 768)
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(MAP, 1000, 500)
    c.setMapCont(MAP, 1); c.setMapCont(NEXT_MAP, 1); c.setMapCont(SEA_MAP, 2)
    for map, corners in pairs(CORNERS) do
        if not (opts.noCorners and map == MAP) then c.setMapCorners(map, corners) end
    end
    c.setClass("WARRIOR"); c.setLevel(20)
    if opts.faction ~= false then c.setFaction("Horde") end
    if opts.combat then c.setCombat(true) end
    if opts.rows then
        local db, zones = questie(opts.state or {}, opts.rows)
        c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

-- The module's one call, or nil when the module is not there.
local function listOf(t, addon)
    local FU = parts(t, addon)
    if not FU then return nil end
    local api = addon.use(FU.NAME)
    local ok = type(api) == "table" and type(api.List) == "function"
    t.ok(ok, "the module provides List")
    if not ok then return nil end
    return api.List, FU
end

local function names(list)
    local out = {}
    for i, e in ipairs(type(list) == "table" and list or {}) do out[i] = e.name end
    return out
end

-- ---------------------------------------------------------------- pure

T["flight unknown: the feed's list is every flight master of the faction, a copy with no side"] = function(t)
    local _, PP = parts(t, ns)
    if not PP then return end
    local found = PP.Scan(questie({}, ROWS))
    t.eq(names(PP.List("flight", found, "Horde")), { "Near Wing", "Far Wing", "Sea Wing", "Next Wing" },
        "every one the Horde can use, on any map, in the order of the pass")
    t.eq(names(PP.List("flight", found, "Alliance")), { "Far Wing", "Their Wing" }, "and the Alliance's")
    local list = PP.List("flight", found, "Horde")
    t.eq(list and list[2], { name = "Far Wing", map = MAP, x = 0.9, y = 0.5 }, "name and place, nothing more")
    t.ok(list and list[2] ~= found.flight[2], "a copy: the kept place is not handed out")
    t.eq(PP.List("flight", nil, "Horde"), nil, "no answer from Questie yet: nil, not an empty list")
    t.eq(PP.List("innkeeper", found, "Horde"), {}, "read, and none of that kind: an empty list")
    t.eq(PP.List("trainer", found, "Horde"), nil, "a kind that is no service")
end

T["flight unknown: a flight master is known by a saved point within the same-place yards, on that continent"] = function(t)
    local FU = parts(t, ns)
    if not FU then return end
    local fm = { name = "Near Wing", cont = 1, wx = 200, wy = 250 }
    t.eq(FU.Learned(fm, { nodes = NODES }), true, "a point 10 yards off")
    t.eq(FU.Learned(fm, { nodes = { a = { cont = 1, wx = 200 + FU.SAME, wy = 250 } } }), true, "at the limit")
    t.eq(FU.Learned(fm, { nodes = { a = { cont = 1, wx = 201 + FU.SAME, wy = 250 } } }), false, "a yard past it")
    t.eq(FU.Learned(fm, { nodes = { a = { cont = 2, wx = 200, wy = 250 } } }), false,
        "the same numbers on another continent")
    t.eq(FU.Learned(fm, { nodes = {} }), false, "no point")
    t.eq(FU.Learned(fm, {}), false, "nothing known")
    t.eq(FU.Learned(fm, { talked = { ["Near Wing"] = true } }), true, "their flight map was opened")
    t.eq(FU.Learned(fm, { talked = { ["Far Wing"] = true } }), false, "another's was")
    t.eq(FU.KnowsOn(NODES, 1), true, "a point is saved on continent 1")
    t.eq(FU.KnowsOn(NODES, 2), false, "none on continent 2")
    t.eq(FU.KnowsOn(nil, 1), false, "none saved at all")
end

T["flight unknown: masters are put in the world by their map's corners, one not placed is left out"] = function(t)
    local FU = parts(t, ns)
    if not FU then return end
    local placed, left = FU.Placed({
        { name = "Near Wing", map = MAP, x = 0.2, y = 0.5 },
        { name = "Next Wing", map = NEXT_MAP, x = 0.3, y = 0.5 },
        { name = "Lost Wing", map = LOST_MAP, x = 0.3, y = 0.5 },
        { name = "Carrier", map = MAP, x = 0.4, y = 0.5 },
    }, function(map) return CORNERS[map] end, function(name) return name == "Carrier" end)
    t.eq(names(placed), { "Near Wing", "Next Wing" }, "the two the world places, not the one that carries you itself")
    t.eq(placed[1] and { placed[1].cont, placed[1].wx, placed[1].wy }, { 1, 200, 250 })
    t.eq(placed[2] and { placed[2].cont, placed[2].wx, placed[2].wy }, { 1, 1300, 250 })
    t.eq(placed[1] and { placed[1].map, placed[1].x, placed[1].y }, { MAP, 0.2, 0.5 }, "its map place is kept")
    t.eq(left, 1, "one left out for a map with no place in the world")
end

T["flight unknown: the list is the ones not known on the continent, nearest first, a name once"] = function(t)
    local FU = parts(t, ns)
    if not FU then return end
    local me = { cont = 1, wx = 500, wy = 250 }
    local masters = {
        { name = "Next Wing", map = NEXT_MAP, x = 0.3, y = 0.5, cont = 1, wx = 1300, wy = 250 },
        { name = "Near Wing", map = MAP, x = 0.2, y = 0.5, cont = 1, wx = 200, wy = 250 },
        { name = "Far Wing", map = MAP, x = 0.95, y = 0.5, cont = 1, wx = 950, wy = 250 },
        { name = "Far Wing", map = MAP, x = 0.9, y = 0.5, cont = 1, wx = 900, wy = 250 },
        { name = "Sea Wing", map = SEA_MAP, x = 0.5, y = 0.5, cont = 2, wx = 500, wy = 250 },
    }
    local list, why = FU.Of(masters, { nodes = NODES }, me)
    t.eq(why, nil)
    t.eq(names(list), { "Far Wing", "Next Wing" }, "not the known one, not the one across the sea")
    t.eq(list and list[1], { name = "Far Wing", map = MAP, x = 0.9, y = 0.5, cont = 1, wx = 900, wy = 250, yards = 400 },
        "the nearer of its two places, with how far")
    t.eq(list and list[2] and list[2].yards, 800)
    t.ok(list and list[1] ~= masters[4], "a copy")
    t.eq(names(FU.Of(masters, { nodes = NODES, talked = { ["Next Wing"] = true } }, me)), { "Far Wing" },
        "one whose flight map was opened is known too")
    -- A name with two places: one of them by a known point makes it known.
    local two = {
        { name = "Twin Wing", map = MAP, x = 0.9, y = 0.5, cont = 1, wx = 900, wy = 250 },
        { name = "Twin Wing", map = MAP, x = 0.2, y = 0.5, cont = 1, wx = 200, wy = 250 },
    }
    t.eq(FU.Of(two, { nodes = NODES }, me), {}, "known by its other place: not listed at all")
    t.eq(FU.Of({}, { nodes = NODES }, me), {}, "Questie has none: an empty list, known to be empty")
end

T["flight unknown: with the known points not known the answer is nil and a reason, never every master"] = function(t)
    local FU = parts(t, ns)
    if not FU then return end
    local me = { cont = 1, wx = 500, wy = 250 }
    local masters = { { name = "Far Wing", map = MAP, x = 0.9, y = 0.5, cont = 1, wx = 900, wy = 250 } }
    local list, why = FU.Of(masters, {}, me)
    t.eq(list, nil, "no point saved: not known")
    t.eq(why, FU.NO_KNOWN)
    list, why = FU.Of(masters, { nodes = {} }, me)
    t.eq(list, nil, "an empty table saved: not known")
    t.eq(why, FU.NO_KNOWN)
    list, why = FU.Of(masters, { nodes = { a = { cont = 2, wx = 0, wy = 0 } } }, me)
    t.eq(list, nil, "points only on another continent: this one's are not known")
    t.eq(why, FU.NO_KNOWN)
    list, why = FU.Of(masters, { nodes = { a = { cont = 2, wx = 0, wy = 0 } }, talked = { ["Other"] = true } }, me)
    t.eq(list, nil, "a talked note alone does not say which points are known here")
    t.eq(why, FU.NO_KNOWN)
    list, why = FU.Of(masters, { nodes = NODES }, nil)
    t.eq(list, nil, "where the player is, not known")
    t.eq(why, FU.NO_CONTINENT)
    list, why = FU.Of(nil, { nodes = NODES }, me)
    t.eq(list, nil, "no list from Questie")
    t.eq(why, FU.NO_QUESTIE)
end

-- ------------------------------------------------------------ the module

T["flight unknown: the module lists the unknown ones of the faction on the continent, after one pass"] = function(t)
    local state = {}
    local c, addon = boot({ state = state, rows = ROWS, nodes = NODES })
    local list, FU = listOf(t, addon)
    if not list then return end
    local first, why = list()
    t.eq(first, nil, "asked: no answer yet, nothing is read in the ask")
    t.eq(why, FU.READING, "and it says Questie's list is still being read")
    t.eq(state.scans, nil, "not gone through in the ask itself")
    c.advance(1, 20)
    local got, after = list()
    t.eq(after, nil)
    t.eq(names(got), { "Far Wing", "Next Wing" },
        "not the known one, the other faction's, the one across the sea, or a smith")
    local far = got and got[1] or {}
    t.eq({ far.map, far.x, far.y, far.cont }, { MAP, 0.9, 0.5, 1 }, "its place")
    t.eq(far.yards and math.floor(far.yards + 0.5), 400, "400 yards east")
    t.eq(got and got[2] and got[2].map, NEXT_MAP)
    t.eq(got and got[2] and got[2].yards and math.floor(got[2].yards + 0.5), 800, "on the next map, 800 yards")
    -- Asked again and again, with the nearest flight master asked for too:
    -- still the one pass.
    for _ = 1, 5 do
        list()
        addon.Nav.Nearest("flight", c, addon.store, addon.use)
        c.advance(6, 24)
    end
    t.eq(state.scans, 1, "one pass over Questie's NPCs for all of that")
    t.eq(names((list())), { "Far Wing", "Next Wing" }, "and the same answer")
    t.eq(addon.store:get("char", "learned.flights.nodes"), NODES, "nothing saved is changed by asking")
end

T["flight unknown: a flight master whose flight map this character opened is not listed"] = function(t)
    local c, addon = boot({ rows = ROWS, nodes = NODES, talked = { ["Far Wing"] = true } })
    local list = listOf(t, addon)
    if not list then return end
    list()
    c.advance(1, 20)
    t.eq(names((list())), { "Next Wing" })
end

T["flight unknown: no flight point saved for this continent is nil and a reason, and Questie is not read"] = function(t)
    local state = {}
    local c, addon = boot({ state = state, rows = ROWS })
    local list, FU = listOf(t, addon)
    if not list then return end
    local got, why = list()
    t.eq(got, nil, "which points this character knows is not known: no list, never every master")
    t.eq(why, FU.NO_KNOWN)
    c.advance(5, 20)
    got, why = list()
    t.eq(got, nil, "still none later")
    t.eq(why, FU.NO_KNOWN)
    t.eq(state.scans, nil, "Questie's NPCs are not gone through for an answer that cannot be given")
    local c2, addon2 = boot({ rows = ROWS, nodes = { ["Sea Town"] = { cont = 2, wx = 300, wy = 250 } } })
    local list2 = listOf(t, addon2)
    if not list2 then return end
    list2()
    c2.advance(1, 20)
    got, why = list2()
    t.eq(got, nil, "points saved only on another continent: this one's are not known")
    t.eq(why, FU.NO_KNOWN)
end

T["flight unknown: no Questie is nil and a reason"] = function(t)
    local c, addon = boot({ nodes = NODES })
    local list, FU = listOf(t, addon)
    if not list then return end
    local got, why = list()
    t.eq(got, nil)
    t.eq(why, FU.NO_QUESTIE, "nothing to wait for")
    c.advance(5, 20)
    got, why = list()
    t.eq(got, nil, "nor later")
    t.eq(why, FU.NO_QUESTIE)
end

T["flight unknown: in combat Questie is not read, and the answer is still being read"] = function(t)
    local state = {}
    local c, addon = boot({ state = state, rows = ROWS, nodes = NODES, combat = true })
    local list, FU = listOf(t, addon)
    if not list then return end
    list()
    c.advance(5, 20)
    local got, why = list()
    t.eq(got, nil)
    t.eq(why, FU.READING)
    t.eq(state.scans, nil, "in combat: Questie's NPCs are not gone through")
    c.setCombat(false)
    c.advance(1, 20)
    t.eq(names((list())), { "Far Wing", "Next Wing" }, "out of combat: the list")
    t.eq(state.scans, 1)
end

T["flight unknown: the continent or the faction not known is nil and a reason"] = function(t)
    local state = {}
    local c, addon = boot({ state = state, rows = ROWS, nodes = NODES, noCorners = true })
    local list, FU = listOf(t, addon)
    if not list then return end
    local got, why = list()
    t.eq(got, nil, "the player's map has no place in the world")
    t.eq(why, FU.NO_CONTINENT)
    -- The client says where the player is in the world: enough.
    c.setWorldPosition(1, 500, 250)
    list()
    c.advance(1, 20)
    t.eq(names((list())), { "Next Wing" },
        "with the world place: the one on a map the world places (this map's own are left out, not guessed)")
    local c2, addon2 = boot({ state = state, rows = ROWS, nodes = NODES, faction = false })
    local list2 = listOf(t, addon2)
    if not list2 then return end
    c2.advance(1, 20)
    got, why = list2()
    t.eq(got, nil, "which faction the player is, not known: no list")
    t.eq(why, FU.NO_FACTION)
end

return T
