local _, ns = ...

-- Parity B-32 (lead section 452, lane A): a druid who has not learned
-- Teleport: Moonglade, with a quest goal in Moonglade and no flight data,
-- is told where the spell is learned under the step. Before: the no-flight
-- line took the one hint, and the spell was never named. Whole add-on
-- loaded the way the game loads it (ns.offline.addon) on a fake client;
-- the quest, mob and places are made up, the spell is the one row of
-- N.TRAVEL_SPELLS. Not tested in game.

local tests = {}
local Flights, Travel = ns.Nav.Flights, ns.Nav.Travel

local MOONGLADE = 1450
local TELEPORT, TELEPORT_ID = "Teleport: Moonglade", 18960

local function questie()
    local db = {}
    function db.GetQuest(id)
        if id == 303 then return { ObjectiveData = { { Type = "monster", Id = 9002 } } } end
    end
    function db.GetNPC(id)
        if id == 9002 then return { name = "Grove Wolf", spawns = { [493] = { { 50, 50 } } } } end
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [12] = 1411, [493] = MOONGLADE })[area] end
    return db, zones
end

-- opts.class (default DRUID), opts.known (true, false or nil: no answer),
-- opts.here: the map the player stands on (default 1411).
local function start(opts)
    opts = opts or {}
    local here = opts.here or 1411
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setZone(1, here); c.setPosition(here, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(1411, 1000, 500); c.setMapCont(1411, 1)
    c.setMapSize(MOONGLADE, 1000, 1000); c.setMapCont(MOONGLADE, 1)
    if opts.mapName ~= false then c.setMapName(MOONGLADE, opts.mapName or "Moonglade") end
    c.setMapCorners(1411, { cont = 1, ox = 0, oy = 0, ex = 1000, ey = 0, sx = 0, sy = 500 })
    c.setMapCorners(MOONGLADE, { cont = 1, ox = 5000, oy = 0, ex = 6000, ey = 0, sx = 5000, sy = 1000 })
    c.setClass(opts.class or "DRUID"); c.setFaction("Horde"); c.setLevel(20)
    if opts.known ~= nil then
        c.setSpellId(TELEPORT, TELEPORT_ID)
        c.setSpell(TELEPORT_ID, { known = opts.known })
    end
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.setQuestLog({ { id = 303, title = "Grove Wolves", objectives = { { text = "Grove Wolf slain: 0/4" } } } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function has(lines, text)
    for _, l in ipairs(lines or {}) do if l == text then return true end end
    return false
end

-- Owner, lead section 619: the line names the level the spell needs (a
-- cited fact) and no place it is learned at (not verified yet).
local LEARN = TELEPORT .. " needs level 10"

-- Fails before: the line under the quest is the no-flight line; the spell
-- is never named.
tests["travel learn where: a druid without the teleport is told where it is learned"] = function(t)
    local c = start({ known = false })
    local a = c.arrows[1]
    t.eq(a.shown, true)
    t.eq(a.lines[1], "Grove Wolves", "still the quest step")
    t.ok(has(a.lines, LEARN), "the learn line: " .. tostring(LEARN))
    t.ok(not has(a.lines, Flights.NONE), "one hint: the spell, not the no-flight line")
end

tests["travel learn where: a druid with the teleport is told to cast it"] = function(t)
    local c = start({ known = true })
    local a = c.arrows[1]
    t.eq(a.lines[1], "Cast " .. TELEPORT)
    t.ok(not has(a.lines, LEARN), "no learn line")
end

tests["travel learn where: no answer on the spell claims nothing about it"] = function(t)
    local c = start({ known = nil })
    local a = c.arrows[1]
    t.ok(not has(a.lines, LEARN), "no learn line")
    t.ok(has(a.lines, Flights.NONE), "the no-flight line as before")
end

tests["travel learn where: another class is never told to learn it"] = function(t)
    local c = start({ class = "WARRIOR", known = false })
    local a = c.arrows[1]
    t.ok(not has(a.lines, LEARN), "no learn line")
    t.ok(has(a.lines, Flights.NONE), "the no-flight line as before")
end

tests["travel learn where: in Moonglade already, no learn line"] = function(t)
    local c = start({ known = false, here = MOONGLADE })
    local a = c.arrows[1]
    t.ok(not has(a.lines, LEARN), "no learn line")
end

-- Section 619: map 1450 is taken for Moonglade only when the client names
-- it so. Fails before: the spell is tied to 1450 whatever the client says.
tests["travel learn where: no spell line when the client does not name map 1450 Moonglade"] = function(t)
    for _, name in ipairs({ false, "Somewhere Else" }) do
        local c = start({ known = false, mapName = name })
        local a = c.arrows[1]
        t.ok(not has(a.lines, LEARN), "no learn line: " .. tostring(name))
        t.ok(has(a.lines, Flights.NONE), "the no-flight line instead")
        local c2 = start({ known = true, mapName = name })
        t.ok(c2.arrows[1].lines[1] ~= "Cast " .. TELEPORT, "and no cast: " .. tostring(name))
    end
end

return tests
