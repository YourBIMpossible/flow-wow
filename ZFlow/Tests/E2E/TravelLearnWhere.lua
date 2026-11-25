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
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, opts.lists and { learned = { trainerLists = opts.lists } } or {})
    c.setZone(1, here); c.setPosition(here, 0.5, 0.5); c.setFacing(0)
    c.setMapSize(1411, 1000, 500); c.setMapCont(1411, 1)
    c.setMapSize(MOONGLADE, 1000, 1000); c.setMapCont(MOONGLADE, 1)
    if opts.mapName ~= false then c.setMapName(MOONGLADE, opts.mapName or "Moonglade") end
    c.setMapCorners(1411, { cont = 1, ox = 0, oy = 0, ex = 1000, ey = 0, sx = 0, sy = 500 })
    c.setMapCorners(MOONGLADE, { cont = 1, ox = 5000, oy = 0, ex = 6000, ey = 0, sx = 5000, sy = 1000 })
    c.setClass(opts.class or "DRUID"); c.setFaction("Horde"); c.setLevel(opts.level or 5)
    if opts.known ~= nil then
        c.setSpellId(TELEPORT, TELEPORT_ID)
        c.setSpell(TELEPORT_ID, { known = opts.known })
    end
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    if opts.l10n then c.setQuestieModule("l10n", opts.l10n) end
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

-- Lead section 621: a trainer list the player opened that has the spell
-- names that trainer and its cost; nothing but that record says who
-- teaches it. Fails before: the line never names a trainer.
tests["travel learn where: the trainer and cost come from the player's own trainer list"] = function(t)
    local lists = { k = { npc = "Turak Runetotem", shown = { available = true, unavailable = true, known = true },
        complete = true, rows = { { name = TELEPORT, state = "unavailable", level = 10, cost = 300 } } } }
    local c = start({ known = false, lists = lists })
    local want = ns.Nav.TRAVEL_TAUGHT_COST:format(LEARN, "Turak Runetotem", ns.Prices.Coin(300))
    t.ok(has(c.arrows[1].lines, want), "the recorded trainer and cost: " .. want)
    t.ok(not has(c.arrows[1].lines, LEARN), "one line, not two")
end

-- Section 621: no record, no trainer named.
tests["travel learn where: with no trainer list the line names no trainer"] = function(t)
    local c = start({ known = false })
    t.ok(has(c.arrows[1].lines, LEARN), "only the level: " .. LEARN)
    for _, l in ipairs(c.arrows[1].lines) do
        t.eq(l:find("trainer", 1, true), nil, "no trainer claimed: " .. l)
    end
end

-- Lead section 623 item 3: at the spell's level or above, the line no
-- longer says a level is needed. The level is the client's.
-- Fails before: "needs level 10" at level 20.
tests["travel learn where: at level 10 or above the line says not learned yet"] = function(t)
    local c = start({ known = false, level = 20 })
    t.ok(has(c.arrows[1].lines, TELEPORT .. ": not learned yet"), "not learned yet")
    t.ok(not has(c.arrows[1].lines, LEARN), "no level asked of a level 20")
    local c2 = start({ known = false, level = 9 })
    t.ok(has(c2.arrows[1].lines, LEARN), "below it: the level it needs")
end

-- Section 623 item 1: a client in another language. The map's name is
-- checked against the name the player's own Questie gives zone 493 in
-- their language. Fails before: only the English name counts.
tests["travel learn where: a client in another language, Questie names the zone the same"] = function(t)
    local l10n = setmetatable({ zoneLookup = { [1] = { [493] = "Moonglade" } } },
        { __call = function(_, text) return text == "Moonglade" and "Mondlichtung" or text end })
    local c = start({ known = true, mapName = "Mondlichtung", l10n = l10n })
    t.eq(c.arrows[1].lines[1], "Cast " .. TELEPORT, "the names match: the step")
    local c2 = start({ known = true, mapName = "Winterquell", l10n = l10n })
    t.ok(c2.arrows[1].lines[1] ~= "Cast " .. TELEPORT, "another name: no step")
    local c3 = start({ known = true, mapName = "Mondlichtung" })
    t.ok(c3.arrows[1].lines[1] ~= "Cast " .. TELEPORT, "no Questie zone names: only the English name counts")
end

return tests
