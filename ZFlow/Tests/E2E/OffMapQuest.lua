local _, ns = ...

-- End to end (owner's execution directive, 2026-11-23): the whole add-on
-- loaded the way the game loads it (ns.offline.addon), on a fake client,
-- for a quest whose only place is on another map. Quest log -> Questie
-- stand-in -> QuestRead/QuestSource -> Travel (crossings) -> the quest
-- arrow's lines and needle. Made-up places; not tested in game.

local tests = {}
local Q, Travel, Arrow = ns.Nav.QuestSource, ns.Nav.Travel, ns.Arrow

local function questie()
    local db = {}
    function db.GetQuest(id)
        if id == 303 then return { ObjectiveData = { { Type = "monster", Id = 9002 } } } end
    end
    function db.GetNPC(id)
        if id == 9002 then return { name = "Far Wolf", spawns = { [40] = { { 50, 50 } } } } end
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [12] = 1411, [40] = 1420 })[area] end
    return db, zones
end

local function zeppelin()
    return { key = "zep", how = "zeppelin", faction = "Horde",
             a = { cont = 1, map = 1411, x = 0.5, y = 0.1, name = "Durotar tower" },
             b = { cont = 0, map = 1420, x = 0.6, y = 0.6, name = "Tirisfal tower" } }
end

-- A Horde warrior facing north in the middle of map 1411 (continent 1),
-- with the wolves quest; its wolves are only on map 1420, on continent
-- opts.cont (default 0, another continent). opts.saved: the account DB.
-- opts.noQuestie: Questie not there at login.
local function start(opts)
    opts = opts or {}
    local cont2 = opts.cont or 0
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.saved or {})
    c.setZone(1, 1411); c.setPosition(1411, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(1411, 1000, 500); c.setMapCont(1411, 1)
    c.setMapSize(1420, 1000, 1000); c.setMapCont(1420, cont2)
    c.setMapCorners(1411, { cont = 1, ox = 1000, oy = 2000, ex = 0, ey = -1000, sx = -500, sy = 0 })
    c.setMapCorners(1420, { cont = cont2, ox = 1000, oy = 1000, ex = 0, ey = -1000, sx = -1000, sy = 0 })
    c.setClass("WARRIOR"); c.setFaction("Horde")
    if not opts.noQuestie then
        local db, zones = questie()
        c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    end
    c.setQuestLog({ { id = 303, title = "Wolves", objectives = { { text = "Wolves slain: 0/4" } } } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function has(lines, text)
    for _, l in ipairs(lines or {}) do if l == text then return true end end
    return false
end

tests["off-map quest, same continent: the needle turns and the yards are said"] = function(t)
    local c = start({ cont = 1 })
    local a = c.arrows[1]
    t.eq(a.shown, true)
    -- Section 208: no flight point known, so the line of section 286.
    t.eq(a.lines, { "Wolves", "Wolves slain: 0/4", ns.Nav.Flights.NONE, "1415 yd SE" })
    t.ok(type(a.drawn) == "table" and type(a.drawn.turn) == "number" and a.drawn.turn ~= 0, "needle turned")
end

tests["off-map quest, other continent, zeppelin learned: the boarding place first"] = function(t)
    local c = start({ saved = { learned = { places = { crossings = { zeppelin() } } } } })
    local a = c.arrows[1]
    t.eq(a.shown, true)
    t.eq(a.lines, { "Zeppelin to Tirisfal tower", "Then: Wolves", "200 yd N" })
    t.eq(a.drawn.turn, 0, "facing north, the tower due north")
end

-- Regression (lead section 187): with no crossing learned the arrow said
-- only "direction unknown" under the quest; now it says why.
tests["off-map quest, other continent, nothing learned: says another continent"] = function(t)
    local c = start()
    local a = c.arrows[1]
    t.eq(a.shown, true)
    t.eq(a.lines, { "Wolves", "Wolves slain: 0/4", Travel.FAR })
    t.ok(not has(a.lines, Arrow.UNKNOWN_TURN), "no bare 'direction unknown'")
end

tests["off-map quest: the quest-arrow setting off, no quest step"] = function(t)
    local c, addon = start({ cont = 1 })
    local ok, why = addon.settings:set(Q.SETTING, false)
    t.ok(ok, "setting taken: " .. tostring(why))
    t.eq(addon.settings:get(Q.SETTING), false)
    c.advance(1, 4)
    local a = c.arrows[1]
    -- A hidden arrow keeps the lines it last drew; what the player sees is shown.
    t.ok(not a.shown or not has(a.lines, "Wolves"), "the quest is not on the arrow")
    -- Back on: the quest is on the arrow again.
    addon.settings:set(Q.SETTING, true)
    c.advance(1, 4)
    t.ok(a.shown and has(a.lines, "Wolves"), "on again, the quest is back")
end

tests["off-map quest: Questie arriving after login, the place is found then"] = function(t)
    local c = start({ cont = 1, noQuestie = true })
    t.ok(has(c.arrows[1].lines, Q.UNKNOWN_PLACE) or has(c.arrows[1].lines, Q.ELSEWHERE)
         or not c.arrows[1].shown, "no place made up")
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.fire("QUEST_LOG_UPDATE")
    c.advance(30, 120)
    t.ok(has(c.arrows[1].lines, "1415 yd SE"), "now the yards")
end

return tests
