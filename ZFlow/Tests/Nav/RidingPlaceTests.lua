-- Riding step, a place from the player's own Questie (A2-08, lead section
-- 602): the riding step (Nav/RidingStep.lua) had a place only from a
-- riding trainer whose window the player opened, on the player's map. With
-- none, it now asks the profession feed (Nav/ProfFeed.lua, the one owner
-- of the Questie reader) for the riding trainer NAMED for the player's
-- race in Nav/RidingNames.lua (approximate, from Flow), on this map, else
-- on another map of this continent. The names are the table's; every
-- place, map and number here is made up, test only. No Questie, the race
-- not read, the name not found, the other faction's, or across the sea:
-- the step as it was. Look only. Not seen in game.
--
-- Red before the code: no table, no NPC is read by its name, and the step
-- asks nobody.
local _, ns = ...

local T = {}

local HERE_MAP, NEXT_MAP, OVERSEA_MAP = 1453, 1429, 1411
local AREA, NEXT_AREA, OVERSEA_AREA = 31, 32, 33
local MINE, OTHER, EXTRA = 9101, 9102, 9103
local HUMAN, DWARF = 1, 3
local AREAS = { [AREA] = HERE_MAP, [NEXT_AREA] = NEXT_MAP, [OVERSEA_AREA] = OVERSEA_MAP }

-- The parts asked for, of one add-on table (the shared one, or a whole
-- add-on loaded again).
local function parts(t, a)
    local N = type(a.Nav) == "table" and a.Nav or {}
    local R, PP, RN = a.RidingStep, N.ProfPlace, N.RidingNames
    local ok = type(R) == "table" and type(PP) == "table" and type(RN) == "table"
        and type(R.Named) == "function" and type(R.Elsewhere) == "function"
        and type(R.ASK) == "string" and type(R.LISTED) == "string"
        and type(RN.mount) == "table" and type(RN.RACE) == "table"
    t.ok(ok, "the riding names, the step's Named and Elsewhere, and the kind it asks for")
    if not ok then return nil end
    return R, PP, RN
end

-- A stand-in for Questie's two modules. rows = { [id] = { name, area, x,
-- side, flags } }; state.scans counts the times its NPCs were gone through
-- (as Tests/E2E/ProfPlaceArrow.lua), state.names the reads of a name.
local function questie(state, rows)
    local npcs, first = {}, nil
    for id, r in pairs(rows) do
        npcs[id] = { name = r.name, npcFlags = r.flags, friendlyToFaction = r.side,
                     spawns = { [r.area] = { { r.x, 50 } } } }
        if first == nil or id < first then first = id end
    end
    local db = { QuestPointers = {}, NPCPointers = {} }
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

local function known(found)
    return {
        here = { map = HERE_MAP, x = 0.5, y = 0.5, faction = "Alliance" },
        contOf = function(map) return ({ [HERE_MAP] = 1, [NEXT_MAP] = 1, [OVERSEA_MAP] = 2 })[map] end,
        questie = function() return found end,
    }
end

-- ------------------------------------------------------------------ pure

T["riding place: the trainer named for a race, by the race number the client gives"] = function(t)
    local R, _, RN = parts(t, ns)
    if not R then return end
    local human, dwarf = R.Named(HUMAN), R.Named(DWARF)
    t.ok(type(human) == "string" and human ~= "", "a name for race 1")
    t.eq(human, RN.mount[RN.RACE[HUMAN]].trainer, "the table's own, for that race")
    t.ok(dwarf ~= nil and dwarf ~= human, "another race, another trainer")
    t.eq(R.Named(nil), nil, "the race not read: no name")
    t.eq(R.Named(999), nil, "a race the table does not have: no name")
end

T["riding place: an NPC asked for by its name is collected in the one pass, no other"] = function(t)
    local R, PP = parts(t, ns)
    if not R then return end
    local state = {}
    local found, n = PP.Scan(questie(state, {
        [MINE] = { name = R.Named(HUMAN), area = AREA, x = 80, side = "A", flags = 16 },
        [OTHER] = { name = "Just A Trainer", area = AREA, x = 60, side = "A", flags = 16 },
        [EXTRA] = { name = "Just A Wolf", area = AREA, x = 55 },
    }))
    t.eq(found.named, { [R.Named(HUMAN)] = { { name = R.Named(HUMAN), map = HERE_MAP, x = 0.8, y = 0.5, side = "A" } } },
        "the one asked for by name, with its place")
    t.eq(n, 1, "one place in all")
    t.eq(found.trainer, {}, "no profession trainer among them")
    t.eq(state.scans, 1, "one pass")
    t.eq(state.names, 2, "a name is read only of an NPC with a flag: not of the wolf")
end

T["riding place: no NPC asked for by name is met, and the answer is as it was"] = function(t)
    local R, PP = parts(t, ns)
    if not R then return end
    local found = PP.Scan(questie({}, {
        [OTHER] = { name = "Just A Trainer", area = AREA, x = 60, side = "A", flags = 16 },
    }))
    t.eq(found, { trainer = {}, banker = {}, auction = {} }, "nothing more in the answer")
end

T["riding place: the named trainer on this map, else on this continent, never the other faction's"] = function(t)
    local R, PP = parts(t, ns)
    if not R then return end
    local mine, theirs = R.Named(HUMAN), R.Named(DWARF)
    local found = PP.Scan(questie({}, {
        [MINE] = { name = mine, area = AREA, x = 80, side = "A", flags = 16 },
        [OTHER] = { name = theirs, area = AREA, x = 51, side = "A", flags = 16 },
    }))
    local to, from = PP.Pick({ kind = R.ASK, name = mine }, nil, known(found))
    t.eq(to, { name = mine, map = HERE_MAP, x = 0.8, y = 0.5 }, "the one named, not the nearer one of another race")
    t.eq(from, PP.QUESTIE, "and it says the place is Questie's")
    t.eq(PP.Of({ kind = R.ASK, name = mine }, nil, known(found)), { map = HERE_MAP, x = 0.8, y = 0.5 },
        "Of gives the same place, bare")
    t.eq(PP.Pick({ kind = R.ASK }, nil, known(found)), nil, "no name asked for: no place")
    local near = PP.Scan(questie({}, { [MINE] = { name = mine, area = NEXT_AREA, x = 30, side = "AH", flags = 16 } }))
    t.eq(PP.Pick({ kind = R.ASK, name = mine }, nil, known(near)), { name = mine, map = NEXT_MAP, x = 0.3, y = 0.5 },
        "none on this map: the one on another map of this continent")
    local sea = PP.Scan(questie({}, { [MINE] = { name = mine, area = OVERSEA_AREA, x = 30, side = "A", flags = 16 } }))
    t.eq(PP.Pick({ kind = R.ASK, name = mine }, nil, known(sea)), nil, "across the sea: no place")
    local horde = PP.Scan(questie({}, { [MINE] = { name = mine, area = AREA, x = 80, side = "H", flags = 16 } }))
    t.eq(PP.Pick({ kind = R.ASK, name = mine }, nil, known(horde)), nil, "the other faction's: no place")
    t.eq(PP.Pick({ kind = R.ASK, name = mine }, nil, known(nil)), nil, "no Questie: no place")
end

T["riding place: the step in words takes the named trainer's place and says where it is from"] = function(t)
    local R, PP = parts(t, ns)
    if not R then return end
    local mine = R.Named(HUMAN)
    local found = PP.Scan(questie({}, { [MINE] = { name = mine, area = AREA, x = 80, side = "A", flags = 16 } }))
    local k = known(found)
    local function place(ask) return PP.Pick(ask, nil, k) end
    local function words() return R.Of(R.Due(40, {}), nil, nil, 100) end
    local step = R.Elsewhere(words(), mine, place)
    t.eq(step.place, { map = HERE_MAP, x = 0.8, y = 0.5 }, "the place Questie gives")
    t.eq(step.name, mine, "with the name")
    t.eq(step.listed, true, "marked as one from the list")
    t.eq(step.detail, R.LISTED, "the arrow's own line says where the name is from")
    local said = false
    for _, line in ipairs(R.Lines(step)) do
        if line == R.LISTED then said = true end
    end
    t.ok(said, "and the words say it too")
    t.eq(step.cost, nil, "no price is made up")
    -- Nothing to go by: the step as it was.
    t.eq(R.Elsewhere(words(), nil, place), words(), "no name: unchanged")
    t.eq(R.Elsewhere(words(), mine, function() return nil end), words(), "no place known: unchanged")
    t.eq(R.Elsewhere(words(), mine, function() error("not there") end), words(), "the ask failing: unchanged")
    t.eq(R.Elsewhere(words(), mine, nil), words(), "nobody to ask: unchanged")
    -- A trainer the player has seen on this map is not replaced.
    local npcs = { ["Seen Rider"] = { map = HERE_MAP, x = 0.2, y = 0.2, roles = { ridingTrainer = true } } }
    local seen = R.Of(R.Due(40, {}), { map = HERE_MAP, x = 0.5, y = 0.5 }, npcs, 100)
    local asked = 0
    local same = R.Elsewhere(seen, mine, function(ask)
        asked = asked + 1
        return place(ask)
    end)
    t.eq(same.name, "Seen Rider", "the one seen stays")
    t.eq(same.listed, nil, "nothing marked")
    t.eq(asked, 0, "and nobody is asked")
end

-- ---------------------------------------------------------------- module

-- The whole add-on on a fake client (as Tests/E2E/RidingStep.lua). opts:
-- race (a race number; nil: not read), rows (the made-up Questie's NPCs;
-- nil: no Questie), state, level, account, faction.
local function boot(opts)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR")
    c.setLevel(opts.level or 40)
    c.setFaction(opts.faction or "Alliance")
    if opts.race then c.setRaceId(opts.race) end
    c.setMoney(150000)
    c.setPosition(HERE_MAP, 0.5, 0.5)
    c.setMapSize(HERE_MAP, 1000, 500)
    c.setMapCont(HERE_MAP, 1); c.setMapCont(NEXT_MAP, 1); c.setMapCont(OVERSEA_MAP, 2)
    c.setSkillRanks({ Defense = { rank = 200, max = 200 } })
    if opts.rows then
        local db, zones = questie(opts.state or {}, opts.rows)
        c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

-- The step once Questie had its frames.
local function settled(c, addon)
    local api = addon.use("ridingStep")
    api.Step()
    c.advance(1, 20)
    return api.Step(), api
end

-- The names of a whole add-on loaded again: its own table's.
local function rows(t, over)
    local R = parts(t, ns)
    if not R then return nil end
    local out = {
        [MINE] = { name = R.Named(HUMAN), area = AREA, x = 80, side = "A", flags = 16 },
        [OTHER] = { name = R.Named(DWARF), area = AREA, x = 51, side = "A", flags = 16 },
    }
    for id, r in pairs(over or {}) do out[id] = r or nil end
    return out, R.Named(HUMAN)
end

T["riding place module: the trainer named for the player's race is pointed at, another race's is not"] = function(t)
    local list, mine = rows(t)
    if not list then return end
    local state = {}
    local c, addon = boot({ race = HUMAN, rows = list, state = state })
    local R = parts(t, addon)
    if not R then return end
    local step, api = settled(c, addon)
    t.eq(step and step.kind, R.KIND, "the same kind of step")
    t.eq(step and step.place, { map = HERE_MAP, x = 0.8, y = 0.5 }, "the trainer named for race 1, farther as it is")
    t.eq(step and step.name, mine, "with the name")
    t.eq(step and step.listed, true, "marked as one from the list")
    t.eq(step and step.detail, R.LISTED, "and the arrow's line says so")
    t.eq(state.scans, 1, "Questie's NPCs were gone through once")
    for _ = 1, 5 do
        api.Step()
        api.Lines()
        c.advance(6, 24)
    end
    t.eq(state.scans, 1, "still once, after many asks and frames")
    t.eq(api.Step().place, { map = HERE_MAP, x = 0.8, y = 0.5 }, "and the step keeps its place")
    -- The same Questie, a player of the other race: the other trainer.
    local c2, addon2 = boot({ race = DWARF, rows = list })
    local theirs = settled(c2, addon2)
    t.eq(theirs and theirs.place, { map = HERE_MAP, x = 0.51, y = 0.5 }, "race 3 is pointed at its own")
end

T["riding place module: only another race's trainer is known, and the step stays in words"] = function(t)
    local list = rows(t, { [MINE] = false })
    if not list then return end
    local c, addon = boot({ race = HUMAN, rows = list })
    local R = parts(t, addon)
    if not R then return end
    local step, api = settled(c, addon)
    t.ok(step ~= nil, "the step is still offered")
    t.eq(step and step.place, nil, "no place")
    t.eq(step and step.name, nil, "no name")
    t.eq(step and step.listed, nil, "nothing marked")
    t.eq(api.Lines(), R.Lines(R.Of(R.Due(40, {}), nil, nil, 150000)), "the words as with nothing known")
end

T["riding place module: the race not read, and Questie is not gone through at all"] = function(t)
    local list = rows(t)
    if not list then return end
    local state = {}
    local c, addon = boot({ rows = list, state = state })
    local R = parts(t, addon)
    if not R then return end
    local step, api = settled(c, addon)
    t.eq(step and step.place, nil, "no place")
    t.eq(api.Lines(), R.Lines(R.Of(R.Due(40, {}), nil, nil, 150000)), "the words as before")
    c.advance(30, 120)
    t.eq(state.scans, nil, "nothing was asked of Questie")
end

T["riding place module: no Questie leaves the step as it was"] = function(t)
    if not parts(t, ns) then return end
    local c, addon = boot({ race = HUMAN })
    local R = parts(t, addon)
    if not R then return end
    local step, api = settled(c, addon)
    t.ok(step ~= nil, "the step is still offered")
    t.eq(step and step.place, nil, "no place: none is made up")
    t.eq(step and step.label, R.LABEL, "the plain label")
    t.eq(step and step.detail, nil, "no line more")
    t.eq(api.Lines(), R.Lines(R.Of(R.Due(40, {}), nil, nil, 150000)), "the words as before")
end

T["riding place module: the other faction's, or one across the sea, is not pointed at"] = function(t)
    local list, mine = rows(t)
    if not list then return end
    list[MINE] = { name = mine, area = AREA, x = 80, side = "H", flags = 16 }
    local c, addon = boot({ race = HUMAN, rows = list })
    t.eq(settled(c, addon).place, nil, "the other faction's: no place")
    list[MINE] = { name = mine, area = OVERSEA_AREA, x = 80, side = "A", flags = 16 }
    local c2, addon2 = boot({ race = HUMAN, rows = list })
    t.eq(settled(c2, addon2).place, nil, "across the sea: no place")
    list[MINE] = { name = mine, area = NEXT_AREA, x = 30, side = "A", flags = 16 }
    local c3, addon3 = boot({ race = HUMAN, rows = list })
    t.eq(settled(c3, addon3).place, { map = NEXT_MAP, x = 0.3, y = 0.5 }, "another map of this continent: pointed at")
end

T["riding place module: a riding trainer the player has seen on this map still wins"] = function(t)
    local list = rows(t)
    if not list then return end
    local state = {}
    local npcs = { ["Seen Rider"] = { map = HERE_MAP, x = 0.2, y = 0.2, roles = { ridingTrainer = true } } }
    local c, addon = boot({ race = HUMAN, rows = list, state = state,
                            account = { learned = { places = { npcs = npcs } } } })
    local step = settled(c, addon)
    t.eq(step and step.place, { map = HERE_MAP, x = 0.2, y = 0.2 }, "the one seen")
    t.eq(step and step.name, "Seen Rider")
    t.eq(step and step.listed, nil, "not marked as from the list")
    c.advance(30, 120)
    t.eq(state.scans, nil, "and Questie was not gone through at all")
end

T["riding place module: nothing due, and Questie is never read"] = function(t)
    local list = rows(t)
    if not list then return end
    local state = {}
    local c, addon = boot({ race = HUMAN, rows = list, state = state, level = 39 })
    t.eq(addon.use("ridingStep").Step(), nil, "level 39: no step")
    c.advance(30, 120)
    t.eq(state.scans, nil, "and Questie was not gone through")
end

return T
