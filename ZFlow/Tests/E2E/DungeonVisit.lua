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
-- state (for questie), log, refused (event names the client does not take),
-- char (saved ahead)
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, opts.char or {})
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

-- B-47 (lead section 490 item 3): the quest lines said once on entering.
local IN_LOG = ": The Deadmines: 1 of its quests in your log: Red Silk (not done)"
local PICK_UP = "  Not in your log (1): Collecting Memories (Gryan)"

local function times(c, text)
    local n = 0
    for _, line in ipairs(c.printed) do
        if tostring(line) == text then n = n + 1 end
    end
    return n
end

local function walkIn(c, name)
    c.setInstance({ inside = true, kind = "party" })
    c.setInstanceName(name or "The Deadmines")
    c.fire("PLAYER_ENTERING_WORLD")
    c.advance(3, 30)
end

local function walkOut(c)
    c.setInstance({ inside = false, kind = "none" })
    c.fire("PLAYER_ENTERING_WORLD")
    c.advance(1, 5)
end

-- Red on 1066f1cc: nothing is said on entering (times(...) is 0).
tests["dungeon entering: walking in says your quests for it, once"] = function(t)
    local c, addon, base = boot({ outside = true })
    t.eq(times(c, ns.id.title .. IN_LOG), 0, "nothing outside")
    walkIn(c)
    t.eq(times(c, ns.id.title .. IN_LOG), 1, "the quests in your log")
    t.eq(times(c, PICK_UP), 1, "the ones to pick up")
    c.fire("ZONE_CHANGED_NEW_AREA"); c.fire("QUEST_LOG_UPDATE")
    c.advance(1, 5)
    t.eq(times(c, ns.id.title .. IN_LOG), 1, "not said again inside")
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Red on 1066f1cc: nothing is said.
tests["dungeon entering: not said again on a reload in the same run; said again after leaving"] = function(t)
    local c = boot()
    t.eq(times(c, ns.id.title .. IN_LOG), 1, "said at login inside")
    local c2 = boot({ char = c.saved(ns.id.charDB) })
    t.eq(times(c2, ns.id.title .. IN_LOG), 0, "the reload says nothing")
    t.eq(times(c2, PICK_UP), 0)
    walkOut(c2)
    walkIn(c2)
    t.eq(times(c2, ns.id.title .. IN_LOG), 1, "a new run says it again")
end

tests["dungeon entering: nothing with the tracker setting off, or for a dungeon with no quest for you"] = function(t)
    local c, addon = boot({ outside = true })
    addon.settings:set(ns.DungeonTracker.SETTING, false)
    walkIn(c)
    t.eq(times(c, ns.id.title .. IN_LOG), 0, "switched off")
    t.eq(times(c, PICK_UP), 0)
    local c2 = boot({ outside = true })
    walkIn(c2, "Somewhere Else")
    local named = 0
    for _, line in ipairs(c2.printed) do
        if tostring(line):find("Somewhere Else", 1, true) then named = named + 1 end
    end
    t.eq(named, 0, "a dungeon Questie does not have: nothing is said of it")
end

-- Section 236: data arriving late; a read that raises, then recovers.
-- Red on 1066f1cc: nothing is ever said.
tests["dungeon entering: the lines wait for Questie, and for a dungeon list that raised"] = function(t)
    local c, addon, base = boot({ questie = false })
    t.eq(times(c, ns.id.title .. IN_LOG), 0, "no Questie: nothing yet")
    local db, zones = questie()
    c.setQuestieModule("QuestieDB", db); c.setQuestieModule("ZoneDB", zones)
    c.fire("QUEST_LOG_UPDATE")
    c.advance(3, 30)
    t.eq(times(c, ns.id.title .. IN_LOG), 1, "said once Questie is there")
    t.eq(addon.problems:count(), base, "no new problem")
    local state = { badList = true }
    local c2, addon2, base2 = boot({ state = state })
    t.eq(times(c2, ns.id.title .. IN_LOG), 0, "the list raises: nothing yet")
    state.badList = false
    c2.fire("QUEST_LOG_UPDATE")
    c2.advance(3, 30)
    t.eq(times(c2, ns.id.title .. IN_LOG), 1, "said once the list answers")
    t.eq(addon2.problems:count(), base2, "no new problem")
end

return tests
