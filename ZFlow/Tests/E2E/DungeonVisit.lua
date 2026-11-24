-- The dungeon word (FLOW-PARITY B-48, lead section 490 item 2), end to end
-- on the whole add-on loaded on a fake client: inside a dungeon it says the
-- dungeon's name, your quests for it (done or not), the ones to pick up,
-- and the bosses killed this visit; outside it says so. Section 236:
-- Questie arriving late, a dungeon list that raises and then answers.
-- A made-up Questie; no quest data of any add-on. Offline: the reads are
-- the fake client's, not the game's. Chat words only. Not tested in game.
local _, ns = ...
local tests = {}

local DM = 1581

-- state.badList true makes Questie's dungeon list raise.
local function questie(state)
    local quests = {
        [101] = { Id = 101, name = "Red Silk", level = 18, requiredLevel = 14, zoneOrSort = DM,
            Starts = { NPC = { 501 } } },
        [102] = { Id = 102, name = "Collecting Memories", level = 18, requiredLevel = 14, zoneOrSort = DM,
            Starts = { NPC = { 501 } } },
    }
    local db = { QuestPointers = { [101] = true, [102] = true } }
    function db.GetQuest(id) return quests[id] end
    function db.GetNPC() return { name = "Gryan", friendlyToFaction = "A" } end
    function db.QueryQuestSingle(id, field)
        local q = quests[id]
        if not q then return nil end
        if field == "questLevel" then return q.level end
        return q[field]
    end
    local zones = {}
    function zones:GetDungeons()
        if state and state.badList then error("no list (test)") end
        return { [DM] = { "The Deadmines" } }
    end
    return db, zones
end

-- opts: outside, name (false: the client gives none), questie (false: none),
-- state (for questie), log, refused (event names the client does not take)
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR"); c.setRaceId(1); c.setFaction("Alliance"); c.setLevel(18)
    c.setQuestDone(101, false); c.setQuestDone(102, false)
    local log = opts.log
    if not log then log = { { id = 101, title = "Red Silk", objectives = { { text = "Silk 1/4", done = false } } } } end
    c.setQuestLog(log)
    for _, e in ipairs(opts.refused or {}) do c.setEventFault(e, true) end
    if opts.outside then
        c.setInstance({ inside = false, kind = "none" })
    else
        c.setInstance({ inside = true, kind = "party" })
        if opts.name ~= false then c.setInstanceName(opts.name or "The Deadmines") end
    end
    if opts.questie ~= false then
        local db, zones = questie(opts.state)
        c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(3, 30)
    return c, addon, addon.problems:count()
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

-- Red on fec10ab2: the word is not one the slash command knows, so none of
-- the three lines is said (has(...) is false).
tests["dungeon word: inside, the name, your quests done or not, what to pick up, the kills"] = function(t)
    local c, addon, base = boot()
    local lines = typed(c, "dungeon")
    t.ok(has(lines, ns.id.title .. ": The Deadmines: 1 of its quests in your log: Red Silk (not done)"),
        "the name and the quest in your log: " .. tostring(lines[1]))
    t.ok(has(lines, "  Not in your log (1): Collecting Memories (Gryan)"), "the one to pick up: " .. tostring(lines[2]))
    t.ok(has(lines, "  No boss killed yet this visit."), "no kill yet: " .. tostring(lines[3]))
    t.eq(#lines, 3)
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Red on fec10ab2: nothing is said.
tests["dungeon word: a boss killed is named, and a finished quest says to hand it in"] = function(t)
    local c = boot({ log = { { id = 101, title = "Red Silk", objectives = { { text = "Silk 4/4", done = true } } },
                             { id = 102, title = "Collecting Memories", complete = true, objectives = {} } } })
    c.fire("ENCOUNTER_END", 1001, "Rhahk'Zor", 1, 5, 1)
    c.advance(0.2, 2)
    local lines = typed(c, "dungeon")
    t.ok(has(lines, ns.id.title .. ": The Deadmines: 2 of its quests in your log: "
        .. "Collecting Memories (done, hand it in), Red Silk (done, hand it in)"), tostring(lines[1]))
    t.ok(has(lines, "  Bosses killed this visit (1): Rhahk'Zor"), tostring(lines[2]))
    t.eq(#lines, 2, "nothing left to pick up: no such line")
end

-- Red on fec10ab2: nothing is said.
tests["dungeon word: outside a dungeon it says so; the help word has its line"] = function(t)
    local c = boot({ outside = true })
    local V = ns.DungeonVisit or {}
    local lines = typed(c, "dungeon")
    t.eq(lines[1], ns.id.title .. ": " .. tostring(V.OUTSIDE):format(ns.id.slash))
    t.eq(#lines, 1)
    local help = typed(c, "help dungeon")[1]
    t.ok(type(help) == "string" and help:find(ns.id.slash .. " dungeon - " .. tostring(V.HELP), 1, true) ~= nil,
        tostring(help))
end

-- Red on fec10ab2: nothing is said.
tests["dungeon word: no Questie, a name Questie does not have, no name, kills not reported"] = function(t)
    local V = ns.DungeonVisit or {}
    local c = boot({ questie = false })
    local lines = typed(c, "dungeon")
    t.eq(lines[1], ns.id.title .. ": The Deadmines: " .. ns.DungeonStates.WHY.noQuestie[1])
    t.eq(lines[2], "  No boss killed yet this visit.", "the kills are still said")
    local c2 = boot({ name = "Somewhere Else" })
    t.eq(typed(c2, "dungeon")[1], ns.id.title .. ": Somewhere Else: " .. tostring(V.NOT_KNOWN))
    local c3 = boot({ name = false })
    t.eq(typed(c3, "dungeon")[1], ns.id.title .. ": " .. tostring(V.NO_NAME))
    local c4 = boot({ refused = { "ENCOUNTER_END", "BOSS_KILL" } })
    t.ok(has(typed(c4, "dungeon"), "  " .. tostring(V.NO_REPORT)), "kills not reported is said")
end

-- Red on fec10ab2: there is no ns.DungeonVisit (the call raises).
tests["dungeon word: the lines, pure"] = function(t)
    local V = ns.DungeonVisit
    t.eq(V.Summary("Test Keep", {}, {}, {}, true),
        { "Test Keep: 0 of its quests in your log", "No boss killed yet this visit." })
    local missing = {}
    for i = 1, 7 do missing[i] = { name = "Quest " .. i } end
    missing[1].from = "Giver"
    local lines = V.Summary("Test Keep", { { name = "A", done = true }, { name = "B", done = false } }, missing,
        { { name = "Boss One" }, { id = 5 } }, true)
    t.eq(lines[1], "Test Keep: 2 of its quests in your log: A (done, hand it in), B (not done)")
    t.eq(lines[2], "Not in your log (7): Quest 1 (Giver); Quest 2; Quest 3; Quest 4; Quest 5; Quest 6; and 1 more")
    t.eq(lines[3], "Bosses killed this visit (2): Boss One, a boss")
    t.eq(V.KillLine({ { name = "Boss One" } }, false), V.NO_REPORT)
    local have, miss = V.Quests({ groups = {
        { id = "log", rows = { { id = 2, name = "Zed" }, { id = 1, name = "Abe" } } },
        { id = "pickup", rows = { { id = 3, name = "Pick" } } },
        { id = "later", rows = { { id = 4, name = "Later" } } } } },
        { [3] = { giverName = "Giver" } },
        { { id = 1, objectives = { { done = true }, { done = false } } }, { id = 2, complete = true } })
    t.eq(have, { { name = "Abe", done = false }, { name = "Zed", done = true } })
    t.eq(miss, { { name = "Pick", from = "Giver" } })
end

-- Section 236: data arriving late.
tests["dungeon word: Questie loading after login is read on the next ask"] = function(t)
    local c, addon, base = boot({ questie = false })
    t.eq(typed(c, "dungeon")[1], ns.id.title .. ": The Deadmines: " .. ns.DungeonStates.WHY.noQuestie[1])
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    typed(c, "dungeon")
    c.advance(3, 30)
    t.ok(has(typed(c, "dungeon"), ns.id.title .. ": The Deadmines: 1 of its quests in your log: Red Silk (not done)"),
        "the quests once Questie is there")
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Section 236: a read that raises, then recovers.
tests["dungeon word: a dungeon list that raises is said in words, then read again once it answers"] = function(t)
    local state = { badList = true }
    local c, addon, base = boot({ state = state })
    local lines = typed(c, "dungeon")
    t.ok(type(lines[1]) == "string" and lines[1]:find(ns.id.title .. ": The Deadmines: ", 1, true) == 1,
        "words, not an error: " .. tostring(lines[1]))
    t.ok(not has(lines, ns.id.title .. ": The Deadmines: 1 of its quests in your log: Red Silk (not done)"),
        "no quests while the list raises")
    state.badList = false
    typed(c, "dungeon")
    c.advance(3, 30)
    t.ok(has(typed(c, "dungeon"), ns.id.title .. ": The Deadmines: 1 of its quests in your log: Red Silk (not done)"),
        "the quests once the list answers")
    t.eq(addon.problems:count(), base, "no new problem")
end

return tests
