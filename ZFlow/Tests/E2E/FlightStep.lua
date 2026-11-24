local _, ns = ...

-- End to end for Nav/FlightStep.lua (S30): the whole add-on loaded the way
-- the game loads it (ns.offline.addon), on a fake client. A flight master
-- the player's own play recorded and never talked to goes on the quest
-- arrow while it is a short detour away, and under the route word's list.
-- Made-up masters and places; not tested in game. Look only.

local tests = {}

local function S() return ns.Nav.FlightStep end

local MAP = 1411

tests["flight step: pure pick, step and line"] = function(t)
    local goals = {
        { name = "Silva", place = { map = MAP, x = 0.1, y = 0.1 }, yards = 400 },
        { name = "Karos", place = { map = MAP, x = 0.5, y = 0.5 }, yards = 28.4 },
        { name = "Devrak", place = { map = 1412, x = 0.3, y = 0.3 } },
        "x", { name = "", yards = 1, place = {} }, { name = "Odd", yards = 0 / 0, place = {} },
    }
    t.eq(S().Pick(goals, S().DETOUR).name, "Karos")
    t.eq(S().Pick(goals, 10), nil)
    t.eq(S().Pick(nil, 10), nil)
    t.eq(S().Pick({}, 0 / 0), nil)
    local step = S().Of(goals[2], { cont = 1 })
    t.eq(step.kind, "flight")
    t.eq(step.label, "Learn the flight path: Karos")
    t.eq(step.place, { cont = 1, map = MAP, x = 0.5, y = 0.5 })
    t.eq(S().Of({ name = string.rep("N", 60), place = { map = MAP, x = 0, y = 0 } }).label, S().LABEL_SHORT)
    t.eq(S().Of(nil), nil)
    t.eq(S().Line(goals[2]), "Close by: learn the flight path from Karos, about 30 yards away. It is free.")
    t.eq(S().Line(goals[3]), nil)
    t.eq(S().Line(nil), nil)
end

-- ------------------------------------------------------------ whole add-on

-- A stand-in for Questie: quest 101's boars are 50 yd east of the middle.
local function questie()
    local db = {}
    function db.GetQuest(id)
        if id == 101 then return { ObjectiveData = { { Type = "monster", Id = 9001 } } } end
    end
    function db.GetNPC(id)
        if id == 9001 then return { name = "Young Boar", spawns = { [12] = { { 55, 50 } } } } end
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [12] = MAP })[area] end
    return db, zones
end

-- A Horde warrior on map 1411 (1000 by 1000 yards) with the boars quest.
-- Karos, a flight master a Horde character recorded, stands in the middle.
local function boot(x, y, opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true }, learned = { places = { npcs = {
        Karos = { kind = "flight", map = MAP, x = 0.50, y = 0.50, factions = { Horde = true } },
    } } } })
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setLevel(12)
    c.setScreen(1024, 768)
    c.setZone(1, MAP); c.setPosition(MAP, x, y); c.setFacing(0)
    c.setMapSize(MAP, 1000, 1000); c.setMapCont(MAP, 1)
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog({ { id = 101, title = "Boar Trouble", objectives = { { text = "Boars slain: 2/8" } } } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function said(c, text, from)
    for i = (from or 0) + 1, #(c.printed or {}) do
        if tostring(c.printed[i]):find(text, 1, true) then return c.printed[i] end
    end
    return nil
end

local function why(c)
    local n = #c.printed
    c.slashes[ns.id.slash]("arrow why")
    return tostring(c.printed[n + 1])
end

-- The first problem that is the arrow's, the route's or the flight step's
-- (the fake client's missing reads are the same with or without this).
local function problems(addon)
    for _, p in ipairs(addon.problems:list()) do
        local text = (tostring(p.owner) .. " " .. tostring(p.kind) .. " " .. tostring(p.text)):lower()
        if text:find("flight", 1, true) or text:find("arrow", 1, true) or text:find("route", 1, true) then
            return tostring(p.text)
        end
    end
    return nil
end

local function arrowLine(c, text)
    for _, a in ipairs(c.arrows or {}) do
        if a.shown then
            for _, line in ipairs(a.lines or {}) do
                if tostring(line):find(text, 1, true) then return line end
            end
        end
    end
    return nil
end

tests["flight step: a master a short detour away is on the quest arrow before the quests"] = function(t)
    local c, addon = boot(0.52, 0.50)          -- 20 yards from Karos
    t.ok(arrowLine(c, "Learn the flight path: Karos") ~= nil, "the arrow names the step")
    t.ok(why(c):find(S().FROM, 1, true) ~= nil, "the arrow says where the step is from")
    t.eq(problems(addon), nil, "nothing about the flight step or the arrow went wrong")
end

tests["flight step: walking away gives the arrow back to the quests"] = function(t)
    local c = boot(0.52, 0.50)
    c.setPosition(MAP, 0.90, 0.50)             -- 400 yards from Karos
    c.advance(10, 40)
    t.eq(arrowLine(c, "Learn the flight path"), nil)
    t.ok(arrowLine(c, "Boar Trouble") ~= nil, "the quest is back")
    t.ok(why(c):find("your quests", 1, true) ~= nil)
end

tests["flight step: the flight map opening at that master takes the step off"] = function(t)
    local c = boot(0.52, 0.50)
    c.setServiceNpc("Creature-0-0-0-0-1-0", "Karos")
    c.fire("TAXIMAP_OPENED")
    c.advance(10, 40)
    t.eq(arrowLine(c, "Learn the flight path"), nil)
    t.ok(why(c):find("your quests", 1, true) ~= nil)
end

tests["flight step: the setting off keeps it off the arrow and the route"] = function(t)
    local c, addon = boot(0.52, 0.50)
    addon.settings:set(ns.FlightPaths.SETTING, false)
    c.advance(10, 40)
    t.eq(arrowLine(c, "Learn the flight path"), nil)
    local before = #c.printed
    c.slashes[ns.id.slash]("route")
    t.eq(said(c, "learn the flight path", before), nil)
end

tests["flight step: the route word says a master within reach under its list"] = function(t)
    local c, addon = boot(0.80, 0.50)          -- 300 yards: not on the arrow, on the route
    t.eq(arrowLine(c, "Learn the flight path"), nil)
    local before = #c.printed
    c.slashes[ns.id.slash]("route")
    t.ok(said(c, "Route:", before) ~= nil, "the route is listed")
    t.ok(said(c, "Close by: learn the flight path from Karos, about 300 yards away. It is free.", before) ~= nil)
    t.eq(problems(addon), nil, "nothing about the flight step or the arrow went wrong")
    before = #c.printed
    c.slashes[ns.id.slash]("route off")
    t.eq(said(c, "learn the flight path", before), nil, "clearing the route says only that")
end

return tests
