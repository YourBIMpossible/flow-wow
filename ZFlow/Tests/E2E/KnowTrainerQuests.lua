local _, ns = ...
-- KNOW lane, slice 1 (C-07, C-52, C-54), end to end on the whole add-on
-- loaded on a fake client, for each of the nine classes:
--   C-52  opening a trainer lists in chat what can be learned and its cost
--   C-54  the class trainer step has a place before any trainer was opened,
--         from a stand-in for the player's own Questie
--   C-07  the classquests word lists the class quests not done, with the
--         giver and the place
-- Section 236: Questie arriving late, a Questie read that raises and then
-- recovers, and a reload. Made-up quests, people and places. Offline: the
-- reads are the fake client's, not the game's. Not tested in game.
local tests = {}

local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local CLASS_ID = { WARRIOR = 1, PALADIN = 2, HUNTER = 3, ROGUE = 4, PRIEST = 5, SHAMAN = 7, MAGE = 8, WARLOCK = 9,
                   DRUID = 11 }
local CLASS_WORD = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
                     SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }
local MAP, AREA = 1453, 12
local Q_OPEN, Q_DONE, Q_OTHER, Q_ANY = 5001, 5002, 6000, 5003
local GIVER, TRAINER, ENEMY = 7001, 7002, 7003

-- A stand-in for Questie's two modules, for a player of `class`. state.raise
-- true makes every NPC read raise. state.scans counts the times the list of
-- NPCs was gone through for class trainers.
local function questie(class, state)
    local mine = 2 ^ (CLASS_ID[class] - 1)
    local other = 2 ^ (CLASS_ID[class == "MAGE" and "DRUID" or "MAGE"] - 1)
    local quests = {
        [Q_OPEN] = { requiredClasses = mine, name = "Test class quest", questLevel = 12, requiredLevel = 10,
                     startedBy = { { GIVER } } },
        [Q_DONE] = { requiredClasses = mine, name = "Test done quest", questLevel = 4, requiredLevel = 4,
                     startedBy = { { GIVER } } },
        [Q_OTHER] = { requiredClasses = other, name = "Test other class quest", questLevel = 10, requiredLevel = 10 },
        [Q_ANY] = { requiredClasses = 0, name = "Test anyone quest", questLevel = 10, requiredLevel = 10 },
    }
    local npcs = {
        [GIVER] = { name = "Test Giver", spawns = { [AREA] = { { 45.2, 61 } } } },
        [TRAINER] = { name = "Test Trainer", subName = CLASS_WORD[class] .. " Trainer", friendlyToFaction = "A",
                      spawns = { [AREA] = { { 66, 42 } } } },
        [ENEMY] = { name = "Test Enemy Trainer", subName = CLASS_WORD[class] .. " Trainer", friendlyToFaction = "H",
                    spawns = { [AREA] = { { 50, 50 } } } },
    }
    local db = { QuestPointers = {}, NPCPointers = {} }
    for id in pairs(quests) do db.QuestPointers[id] = true end
    for id in pairs(npcs) do db.NPCPointers[id] = true end
    function db.QueryQuestSingle(id, field) return quests[id] and quests[id][field] end
    function db.QueryNPCSingle(id, field)
        if state and id == TRAINER and field == "subName" then state.scans = (state.scans or 0) + 1 end
        if state and state.raise then error("questie not ready") end
        return npcs[id] and npcs[id][field]
    end
    local zones = {}
    function zones.GetUiMapIdByAreaId(a) return ({ [AREA] = MAP })[a] end
    return db, zones
end

-- opts: class, account (saved ahead), questie (false: none), state
local function boot(opts)
    opts = opts or {}
    local class = opts.class or "WARRIOR"
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, {})
    c.setClass(class); c.setFaction("Alliance"); c.setLevel(20)
    c.setPosition(MAP, 0.5, 0.5)
    c.setMapName(MAP, "Test City")
    c.setQuestLog({})
    c.setQuestDone(Q_OPEN, false); c.setQuestDone(Q_DONE, true)
    -- Every spell of the pack is one the player has not learned.
    local id = 100
    local pack
    if type(ns.Packs) == "table" then pack = ns.Packs[class] end
    for name in pairs(type(pack) == "table" and type(pack.spells) == "table" and pack.spells or {}) do
        id = id + 1
        c.setSpellId(name, id)
        c.setSpell(id, { known = false })
    end
    if opts.questie ~= false then
        local db, zones = questie(class, opts.state)
        c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon, addon.problems:count()
end

local function typed(c, rest)
    local from = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = from + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

local function has(lines, text)
    for _, line in ipairs(lines) do
        if tostring(line) == text then return true end
    end
    return false
end

local function openTrainer(c, services)
    local from = #c.printed
    c.setTrainer({ npc = "Seen Trainer", services = services })
    c.fire("TRAINER_SHOW")
    local out = {}
    for i = from + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

local function stepApi(addon)
    local a = addon.use("classTrainerStep")
    if type(a) ~= "table" or type(a.Step) ~= "function" then return nil end
    return a
end

local SERVICES = {
    { name = "Test Strike", rank = "Rank 2", state = "available", cost = 100, level = 4 },
    { name = "Test Shout", state = "available", level = 6 },
    { name = "Test Old", rank = "Rank 1", state = "known", cost = 10, level = 1 },
    { name = "Test Later", rank = "Rank 1", state = "unavailable", cost = 900, level = 30 },
}

for _, class in ipairs(CLASSES) do
    -- C-52. Red on f31dd929: nothing is printed at TRAINER_SHOW, so the
    -- heading is not among the lines (has(...) is false).
    tests["know 1: " .. class .. " opening a trainer lists in chat what can be learned, with cost"] = function(t)
        local c, addon, base = boot({ class = class })
        local lines = openTrainer(c, SERVICES)
        t.ok(has(lines, ns.id.title .. ": you can learn here:"), "the heading")
        t.ok(has(lines, "  Test Strike (Rank 2) - " .. ns.Prices.Coin(100)), "a spell with its rank and cost")
        t.ok(has(lines, "  Test Shout - " .. ns.TrainerList.PRICE_UNKNOWN), "a cost not known is said")
        t.ok(not has(lines, "  Test Old (Rank 1) - " .. ns.Prices.Coin(10)), "a known spell is not listed")
        t.ok(not has(lines, "  Test Later (Rank 1) - " .. ns.Prices.Coin(900)), "one for later is not listed")
        t.eq(addon.problems:count(), base, "no new problem")
    end

    -- C-54. Red on f31dd929: no trainer is saved, so the step has no name
    -- (s.name is nil) and no place.
    tests["know 1: " .. class .. " the class trainer step has a place before any trainer was opened"] = function(t)
        local _, addon, base = boot({ class = class })
        local a = stepApi(addon)
        if not a then return t.ok(false, "no classTrainerStep") end
        local s = a.Step()
        t.ok(s ~= nil and s.count > 0, "a step")
        t.eq(s and s.name, "Test Trainer")
        t.eq(s and s.place, { map = MAP, x = 0.66, y = 0.42 })
        local line = a.Lines()[1]
        t.ok(type(line) == "string" and line:find("Visit your class trainer Test Trainer: ", 1, true) == 1, line)
        t.eq(addon.problems:count(), base, "no new problem")
    end

    -- C-07. Red on f31dd929: the word is not one the slash command knows,
    -- so neither line is printed (has(...) is false).
    tests["know 1: " .. class .. " the classquests word lists the class quests not done, giver and place"] = function(t)
        local c, addon, base = boot({ class = class })
        local lines = typed(c, "classquests")
        t.ok(has(lines, ns.id.title .. ": class quests for your class not done: 1 (done: 1)"), "the count")
        t.ok(has(lines, "  [5001] Test class quest (level 10), from Test Giver in Test City 45.2, 61.0: not done"),
            "the quest, its giver and place")
        t.eq(#lines, 2, "the done quest and the other class's quest are not listed")
        t.eq(addon.problems:count(), base, "no new problem")
    end
end

tests["know 1: a trainer with nothing to learn says so in one line; the setting off says nothing"] = function(t)
    local c, addon = boot()
    local none = openTrainer(c, { SERVICES[3], SERVICES[4] })
    t.ok(has(none, ns.id.title .. ": nothing new to learn here right now."), "one line")
    t.ok(not has(none, ns.id.title .. ": you can learn here:"), "no heading")
    c.fire("TRAINER_CLOSED")
    addon.settings:set(ns.TrainerModule.SETTING_LIST, false)
    t.ok(not has(openTrainer(c, SERVICES), ns.id.title .. ": you can learn here:"), "switched off")
end

tests["know 1: classquests with no Questie says what is missing; a quest in the log is said so"] = function(t)
    local c = boot({ questie = false })
    t.ok(has(typed(c, "classquests"), ns.id.title .. ": the class quest list needs the Questie add-on; none is loaded."),
        "no Questie")
    local c2 = boot()
    c2.setQuestLog({ { id = Q_OPEN, title = "Test class quest", objectives = {} } })
    c2.fire("QUEST_LOG_UPDATE")
    t.ok(has(typed(c2, "classquests"),
        "  [5001] Test class quest (level 10), from Test Giver in Test City 45.2, 61.0: in log"), "in log")
end

tests["know 1: the help word has a line for classquests"] = function(t)
    local c = boot()
    local line = typed(c, "help classquests")[1]
    t.ok(type(line) == "string" and line:find(ns.id.slash .. " classquests - " .. ns.ClassQuestList.HELP, 1, true) ~= nil,
        tostring(line))
end

-- Section 236: data arriving late.
tests["know 1: Questie loading after login gives the step its place then"] = function(t)
    local c, addon = boot({ questie = false })
    local a = stepApi(addon)
    if not a then return t.ok(false, "no classTrainerStep") end
    local s = a.Step()
    t.eq(s and s.name, nil, "no Questie yet: words only")
    local db, zones = questie("WARRIOR")
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    s = a.Step()
    t.eq(s and s.name, "Test Trainer")
end

-- Section 236: a read that raises, then recovers.
tests["know 1: a Questie read that raises is words only, and the place comes once it answers"] = function(t)
    local state = { raise = true }
    local c, addon, base = boot({ state = state })
    local a = stepApi(addon)
    if not a then return t.ok(false, "no classTrainerStep") end
    local s = a.Step()
    t.ok(s ~= nil, "still a step")
    t.eq(s and s.place, nil, "no made-up place")
    t.ok(has(typed(c, "classquests"), "  [5001] Test class quest (level 10): not done"), "no giver while it raises")
    -- Asked again only after the wait: the arrow asks for the step on
    -- every frame, and each ask of Questie reads every NPC it knows.
    state.raise = false
    s = a.Step()
    t.eq(s and s.place, nil, "not asked again at once")
    c.advance(ns.ClassTrainerStep.RETRY + 1, 2)
    s = a.Step()
    t.eq(s and s.place, { map = MAP, x = 0.66, y = 0.42 })
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Red on f79dde51: the arrow asks for the step on every frame, so the three
-- asks were used up in the first frames after login (state.scans was 3) and
-- Questie was never asked again.
tests["know 1: a Questie with no answer yet is not asked on every frame, and is asked again later"] = function(t)
    local state = { raise = true }
    local c, addon = boot({ state = state })
    local a = stepApi(addon)
    if not a then return t.ok(false, "no classTrainerStep") end
    a.Step(); a.Step(); a.Step(); a.Step()
    t.ok((state.scans or 0) <= 1, "one ask in the first seconds, not one a frame: " .. tostring(state.scans))
    state.raise = false
    c.advance(ns.ClassTrainerStep.RETRY + 1, 2)
    local s = a.Step()
    t.eq(s and s.name, "Test Trainer", "asked again after the wait")
    local n = state.scans
    c.advance(ns.ClassTrainerStep.RETRY * 3, 6)
    a.Step()
    t.eq(state.scans, n, "an answer with a trainer is kept: Questie is not asked again")
end

-- Section 236: a reload. The trainer the player opened is kept and wins
-- when it is the nearer one; the chat list is printed again.
tests["know 1: after a reload the opened trainer is kept, and the list prints again"] = function(t)
    local c, addon = boot()
    c.setPosition(MAP, 0.52, 0.5)
    openTrainer(c, { { name = next(ns.Packs.WARRIOR.spells), state = "available", cost = 100 } })
    c.fire("TRAINER_CLOSED")
    c.setPosition(MAP, 0.5, 0.5)
    local a = stepApi(addon)
    if not a then return t.ok(false, "no classTrainerStep") end
    t.eq(a.Step().name, "Seen Trainer", "nearer than Questie's")
    local c2, addon2 = boot({ account = c.saved(ns.id.accountDB) })
    local a2 = stepApi(addon2)
    t.eq(a2 and a2.Step().name, "Seen Trainer", "kept over the reload")
    t.ok(has(openTrainer(c2, SERVICES), ns.id.title .. ": you can learn here:"), "the list again")
end

return tests
