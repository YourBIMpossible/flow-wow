-- Dungeon wings as separate runs (FLOW-PARITY B-57, lead section 496 item
-- 1), on the whole add-on loaded on a fake client: each wing of a dungeon
-- has its own quests, bosses and run time, in Nav/DungeonRead.lua and in
-- the dungeon word. Which wing you are in is told from the last boss you
-- killed. Section 236: the kill arriving later; boss names that cannot be
-- read, then can. A made-up Questie with made-up names on the boss ids of
-- R.WINGS; no quest data of any add-on. Offline: the reads are the fake
-- client's, not the game's. Not tested in game.
local _, ns = ...
local tests = {}

local SM, DM, MAP = 796, 1581, 1436

-- state.raise true makes every creature read raise.
local function questie(state)
    local quests = {
        [101] = { name = "Red Silk", level = 18, zoneOrSort = DM },
        [201] = { name = "Library Quest", level = 34, zoneOrSort = SM, objectives = { { { 3974 } } } },
        [202] = { name = "Armory Quest", level = 40, zoneOrSort = SM, objectives = { { { 3975 } } } },
        [203] = { name = "Any Wing Quest", level = 60, zoneOrSort = SM },
        [204] = { name = "Drop Quest", level = 35, zoneOrSort = SM, objectives = { nil, nil, { { 9001 } } } },
    }
    local npcs = {
        [3983] = { name = "Test Interrogator", minLevel = 32, maxLevel = 32 },
        [3974] = { name = "Test Houndmaster", minLevel = 34, maxLevel = 34 },
        [6487] = { name = "Test Arcanist", minLevel = 37, maxLevel = 37 },
        [3975] = { name = "Test Champion", minLevel = 40, maxLevel = 40 },
        [3976] = { name = "Test Commander", minLevel = 42, maxLevel = 42 },
    }
    local db = { QuestPointers = {} }
    for id in pairs(quests) do db.QuestPointers[id] = true end
    function db.GetQuest(id)
        local q = quests[id]
        if not q then return nil end
        return { Id = id, name = q.name, level = q.level, requiredLevel = 10, Starts = { NPC = { 501 } } }
    end
    function db.GetNPC() return { name = "Gryan", friendlyToFaction = "A" } end
    function db.QueryQuestSingle(id, field)
        local q = quests[id]
        if not q then return nil end
        if field == "questLevel" then return q.level end
        return q[field]
    end
    function db.QueryNPCSingle(id, field)
        if state and state.raise then error("creatures not ready (test)") end
        return npcs[id] and npcs[id][field]
    end
    function db.QueryItemSingle(id, field)
        if id == 9001 and field == "npcDrops" then return { 3976 } end
        return nil
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(area) return ({ [40] = MAP })[area] end
    function zones:GetDungeons()
        return { [SM] = { "Scarlet Monastery", {}, nil, { { 40, 42.5, 71.8 } } }, [DM] = { "The Deadmines" } }
    end
    return db, zones
end

-- opts: state (for questie), clock
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setRaceId(1); c.setFaction("Alliance"); c.setLevel(40)
    for id = 201, 204 do c.setQuestDone(id, false) end
    c.setQuestLog({ { id = 201, title = "Library Quest", objectives = { { text = "Slain 0/1", done = false } } },
                    { id = 202, title = "Armory Quest", objectives = { { text = "Slain 0/1", done = false } } } })
    if opts.clock then c.setClock(opts.clock) end
    c.setInstance({ inside = true, kind = "party" })
    c.setInstanceName("Scarlet Monastery")
    local db, zones = questie(opts.state)
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(3, 30)
    return c, addon, addon.problems:count()
end

local function index(c)
    local R = ns.DungeonRead
    local st = R.Start(c)
    while st.state == "building" do R.Step(st, c, R.SLICE) end
    return st
end

local function typed(c, rest)
    local from = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = from + 1, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return out
end

local function has(lines, text)
    for _, line in ipairs(lines) do
        if line == text then return true end
    end
    return false
end

local function kill(c, name)
    c.fire("ENCOUNTER_END", 1001, name, 1, 5, 1)
    c.advance(0.2, 2)
end

local function names(pane)
    local out = {}
    for _, g in ipairs(type(pane) == "table" and type(pane.groups) == "table" and pane.groups or {}) do
        for _, r in ipairs(g.rows) do out[r.name] = true end
    end
    return out
end

-- Red on ea0afeee: there is no R.WingOf, R.Wings (the calls raise).
tests["dungeon wings: the reader files each quest under its wing, and lists a wing's own quests"] = function(t)
    local c = boot()
    local R = ns.DungeonRead
    local st = index(c)
    t.eq(R.WingOf(st, 201), "Library", "a quest for a boss is that boss's wing")
    t.eq(R.WingOf(st, 202), "Armory")
    t.eq(R.WingOf(st, 204), "Cathedral", "an item only a boss drops is that boss's wing")
    t.eq(R.WingOf(st, 203), nil, "no objective and a level outside every wing: not known")
    local wings = R.Wings(st, SM) or {}
    t.eq(#wings, 4)
    t.eq(wings[2] and wings[2].name, "Library")
    t.eq(wings[2] and wings[2].bosses, 2)
    t.eq(wings[2] and wings[2].quests, 1)
    t.eq(R.Wings(st, DM), nil, "a dungeon with no wings")
    local own = names(R.Pane(st, c, SM, "Library"))
    t.eq(own["Library Quest"], true)
    t.eq(own["Any Wing Quest"], true, "a quest whose wing is not known is in every wing")
    t.eq(own["Armory Quest"], nil, "another wing's quest is not")
    t.eq(names(R.Pane(st, c, SM))["Armory Quest"], true, "no wing asked: the whole dungeon")
    t.eq(R.WingTitle(st, SM, "Library"), "Scarlet Monastery (Library)")
    t.eq(R.WingTitle(st, SM, nil), "Scarlet Monastery")
    t.eq(R.WingOfBoss(st, c, SM, "test houndmaster"), "Library", "any case")
    t.eq(R.WingOfBoss(st, c, SM, "Somebody Else"), nil)
    local run = R.Run(st, c, SM, "Armory")
    t.eq(run and run.title, "Scarlet Monastery (Armory)", "a wing is a run of its own")
    t.eq(run and run.wing, "Armory")
end

-- Red on ea0afeee: the summary stays the whole dungeon's after the kill.
tests["dungeon wings: the dungeon word is the wing's once a boss tells which wing this is"] = function(t)
    local c, addon, base = boot()
    local V = ns.DungeonVisit
    local lines = typed(c, "dungeon")
    t.ok(has(lines, ns.id.title .. ": Scarlet Monastery: 2 of its quests in your log: "
        .. "Armory Quest (not done), Library Quest (not done)"), "before a kill, all of it: " .. tostring(lines[1]))
    t.ok(has(lines, "  " .. tostring(V.WING_UNKNOWN)), "and one line says the wing is not known yet")
    kill(c, "Test Houndmaster")
    lines = typed(c, "dungeon")
    t.ok(has(lines, ns.id.title .. ": Scarlet Monastery (Library): 1 of its quests in your log: "
        .. "Library Quest (not done)"),
        "the wing's name and its own quest: " .. tostring(lines[1]))
    t.ok(has(lines, "  Bosses killed this visit (1 of 2 in this wing): Test Houndmaster"), "its own bosses")
    t.ok(not has(lines, "  " .. tostring(V.WING_UNKNOWN)), "the wing is known now")
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Red on ea0afeee: the time is kept under the dungeon's name, not the wing's.
tests["dungeon wings: a wing's run has its own time"] = function(t)
    local c, addon, base = boot({ clock = 1000 })
    kill(c, "Test Champion")
    c.setClock(2500)
    c.setInstance({ inside = false, kind = "none" })
    c.fire("PLAYER_ENTERING_WORLD")
    c.advance(1, 5)
    c.setClock(2500 + ns.DungeonVisit.GRACE + 1)
    c.fire("ZONE_CHANGED_NEW_AREA")
    c.advance(1, 5)
    t.eq(addon.store:get("char", "dungeon.times"), { ["Scarlet Monastery (Armory)"] = 1500 })
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Section 236: a read that raises, then recovers.
tests["dungeon wings: boss names that cannot be read leave the wing not known, then it is told"] = function(t)
    local state = {}
    local c, addon, base = boot({ state = state })
    local V = ns.DungeonVisit
    state.raise = true
    kill(c, "Test Houndmaster")
    local lines = typed(c, "dungeon")
    t.ok(has(lines, "  " .. tostring(V.WING_UNKNOWN)), "not known while the names raise")
    t.ok(has(lines, "  Bosses killed this visit (1): Test Houndmaster"), "the kill is still said")
    state.raise = false
    lines = typed(c, "dungeon")
    t.ok(has(lines, "  Bosses killed this visit (1 of 2 in this wing): Test Houndmaster"), "told once they answer")
    t.eq(addon.problems:count(), base, "no new problem")
end

tests["dungeon wings: the vote, pure"] = function(t)
    local R = ns.DungeonRead
    local wings = {
        { name = "Low", bosses = { [1] = true }, lo = 30, hi = 32 },
        { name = "High", bosses = { [2] = true }, lo = 40, hi = 42 },
    }
    local function wing(objectives, level)
        local w = R.WingFor(objectives, wings, level)
        return w and w.name
    end
    t.eq(wing({ { creatures = { { id = 2, level = 41 } } } }), "High", "a boss")
    t.eq(wing({ { creatures = { { id = 9, level = 31 } } } }), "Low", "a creature of its levels")
    local both = { { creatures = { { id = 9, level = 31 } } }, { creatures = { { id = 2 } } } }
    t.eq(wing(both), "High", "a boss outvotes")
    t.eq(wing({ { creatures = { { id = 9, level = 36 } } } }), nil, "between the wings: not known")
    t.eq(wing({}, 41), "High", "no objective: the quest's level")
    t.eq(wing({}, nil), nil)
    t.eq(R.WingFor({}, {}, 41), nil, "no wings")
end

return tests
