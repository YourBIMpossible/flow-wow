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
-- char (saved ahead), clock (what the client's clock says)
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, opts.char or {})
    c.setClass("WARRIOR"); c.setRaceId(1); c.setFaction("Alliance"); c.setLevel(18)
    c.setQuestDone(101, false); c.setQuestDone(102, false)
    local log = opts.log
    if not log then log = { { id = 101, title = "Red Silk", objectives = { { text = "Silk 1/4", done = false } } } } end
    c.setQuestLog(log)
    if opts.clock then c.setClock(opts.clock) end
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
    t.ok(has(lines, "  Last run here: time not known yet."), "no run timed yet: " .. tostring(lines[4]))
    t.eq(#lines, 4)
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
    t.eq(#lines, 3, "nothing left to pick up: no such line")
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

-- Plexy, lead section 504 CHANGES-2: whether you are in a dungeon has three
-- answers. Not known changes nothing. Red on 339e7683: an instance read
-- that gives nothing is read as outside: the run's clock is stopped, the
-- run is closed after the wait, and the word says you are not in a dungeon.
tests["dungeon visit: an instance read that gives nothing changes nothing, and the word says so"] = function(t)
    local c, addon, base = boot({ clock = 1000 })
    local V = ns.DungeonVisit
    c.setInstance(nil)
    c.setClock(1500)
    c.fire("PLAYER_ENTERING_WORLD"); c.fire("ZONE_CHANGED_NEW_AREA")
    c.advance(1, 5)
    local run = addon.store:get("char", "dungeon.run")
    t.eq(run and run.name, "The Deadmines", "the run is still the one you are in")
    t.eq(run and run.left, nil, "its clock is not stopped")
    local lines = typed(c, "dungeon")
    t.eq(lines[1], ns.id.title .. ": " .. tostring(V.CANNOT_TELL), "the word says it cannot tell")
    t.eq(#lines, 1)
    c.setClock(1500 + V.GRACE + 1)
    c.fire("ZONE_CHANGED_NEW_AREA")
    c.advance(1, 5)
    t.eq(addon.store:get("char", "dungeon.times"), nil, "and the run is not closed")
    -- The read answers again, inside: the same run, nothing said twice.
    walkIn(c)
    t.eq(times(c, ns.id.title .. IN_LOG), 1, "the same run: its lines are not said again")
    c.setClock(1000 + 1800)
    walkOut(c)
    c.setClock(1000 + 1800 + V.GRACE + 1)
    c.fire("ZONE_CHANGED_NEW_AREA")
    c.advance(1, 5)
    t.eq(addon.store:get("char", "dungeon.times"), { ["The Deadmines"] = 1800 }, "timed from its real start to its end")
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Red on 339e7683: XP gained while it is not known where you are is counted
-- as questing XP (a sample is kept).
tests["dungeon visit: XP gained while it is not known where you are counts for neither rate"] = function(t)
    local c, addon = boot({ outside = true, clock = 1000, char = { dungeon = { measure = true } } })
    c.setXp({ cur = 100, max = 10000, rested = 0 })
    c.fire("PLAYER_XP_UPDATE", "player")
    c.setInstance(nil)
    c.setClock(1300)
    c.setXp({ cur = 600, max = 10000, rested = 0 })
    c.fire("PLAYER_XP_UPDATE", "player")
    t.eq(addon.store:get("char", "dungeon.xpSamples"), nil, "not a questing sample")
    local c2, addon2 = boot({ clock = 1000 })
    c2.setXp({ cur = 100, max = 10000, rested = 0 })
    c2.fire("PLAYER_XP_UPDATE", "player")
    c2.setInstance(nil)
    c2.setXp({ cur = 600, max = 10000, rested = 0 })
    c2.fire("PLAYER_XP_UPDATE", "player")
    local run = addon2.store:get("char", "dungeon.run")
    t.eq(run and run.noXp, true, "the run in progress no longer has a known XP")
    t.eq(run and run.xp, nil, "and none is added to it")
end

-- B-56 (lead section 490 item 4): run timing.
local function trackerHas(c, text)
    local rec = c.kitWindows().dungeonTracker
    for _, part in ipairs(rec and rec.parts or {}) do
        if tostring(part.text) == text then return true end
    end
    return false
end

-- A run from `from` for `seconds`, then outside long enough for it to end.
local function runFor(c, seconds, from)
    c.setClock(from + seconds)
    walkOut(c)
    c.setClock(from + seconds + ns.DungeonVisit.GRACE + 1)
    c.fire("ZONE_CHANGED_NEW_AREA")
    c.advance(1, 5)
end

-- Red on df47a0fd: no time is kept, the tracker has no such line and the
-- word does not say it.
tests["dungeon timing: a run is timed from entering to leaving and said in the tracker and the word"] = function(t)
    local c, addon, base = boot({ clock = 1000 })
    t.ok(trackerHas(c, "Last run here: time not known yet."), "no run yet: the tracker says not known")
    runFor(c, 32 * 60, 1000)
    t.eq(addon.store:get("char", "dungeon.times"), { ["The Deadmines"] = 32 * 60 })
    walkIn(c)
    t.ok(trackerHas(c, "Last run here: 32 minutes"), "the tracker's one line")
    t.ok(has(typed(c, "dungeon"), "  Last run here: 32 minutes"), "the word says it")
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Red on df47a0fd: nothing is kept (the store answers nil).
tests["dungeon timing: out and back in soon is the same run; a reload inside keeps its start"] = function(t)
    local c = boot({ clock = 1000 })
    c.setClock(1600)
    walkOut(c)
    c.setClock(1700)
    walkIn(c)
    t.eq(times(c, ns.id.title .. IN_LOG), 1, "the same run: its lines are not said again")
    local c2, addon2 = boot({ char = c.saved(ns.id.charDB), clock = 2000 })
    runFor(c2, 800, 2000)
    t.eq(addon2.store:get("char", "dungeon.times"), { ["The Deadmines"] = 1800 }, "from the first entering")
end

-- An unknown time stays unknown.
tests["dungeon timing: a run the clock did not time, or a look inside, keeps no time"] = function(t)
    local c, addon, base = boot()
    runFor(c, 1800, 5000)
    t.eq(addon.store:get("char", "dungeon.times"), nil, "entered with no clock: no time")
    c.setClock(10000)
    walkIn(c)
    t.ok(trackerHas(c, "Last run here: time not known yet."), "still not known")
    runFor(c, 60, 10000)
    t.eq(addon.store:get("char", "dungeon.times"), nil, "a look inside is not a run")
    t.eq(addon.problems:count(), base, "no new problem")
end

-- Section 236: a read that raises, then recovers.
tests["dungeon timing: a clock that raises gives no time, and the next run is timed"] = function(t)
    local c, addon = boot({ clock = 1000 })
    local real = c.clock
    c.clock = function() error("no clock (test)") end
    walkOut(c)
    c.clock = real
    c.setClock(9000)
    c.fire("ZONE_CHANGED_NEW_AREA")
    t.eq(addon.store:get("char", "dungeon.times"), nil, "left with no clock: no time")
    walkIn(c)
    runFor(c, 600, 9000)
    t.eq(addon.store:get("char", "dungeon.times"), { ["The Deadmines"] = 600 }, "the next run is timed")
end

tests["dungeon timing: the steps and the words, pure"] = function(t)
    local V = ns.DungeonVisit
    t.eq(V.TimeText(32 * 60), "32 minutes")
    t.eq(V.TimeText(60), "1 minute")
    t.eq(V.TimeText(3900), "1 hour 5 minutes")
    t.eq(V.TimeText(7200), "2 hours")
    t.eq(V.TimeText(nil), nil)
    t.eq(V.LastLine(nil), V.LAST_UNKNOWN)
    t.eq(V.RunTime({ name = "A", t = 100, left = 400 }), 300)
    t.eq(V.RunTime({ name = "A", left = 400 }), nil, "no start")
    t.eq(V.RunTime({ name = "A", t = 100, left = true }), nil, "no end")
    t.eq({ V.Step(nil, "A", 100) }, { { name = "A", t = 100 }, true })
    t.eq({ V.Step({ name = "A", t = 100, said = true }, "A", 200) }, { { name = "A", t = 100, said = true }, false })
    t.eq({ V.Step({ name = "A", t = 100 }, nil, 500) }, { { name = "A", t = 100, left = 500 }, true })
    t.eq({ V.Step({ name = "A", t = 100, left = 500 }, "A", 600) }, { { name = "A", t = 100 }, true }, "back soon")
    t.eq({ V.Step({ name = "A", t = 100, left = 500 }, nil, 500 + V.GRACE) }, { {}, true, "A", 400 }, "ended")
    t.eq({ V.Step({ name = "A", t = 100, left = 500 }, "B", 600) }, { { name = "B", t = 600 }, true, "A", 400 })
    t.eq({ V.Step({ name = "A", t = 100 }, nil, nil) }, { { name = "A", t = 100, left = true }, true }, "no clock")
    t.eq({ V.Step({}, nil, 100) }, { {}, false })
end

-- R-02 (lead section 777; Plexy's notes): a quest whose hand-in is not
-- known keeps that note in the chat list (DungeonRead's R.DONE_UNKNOWN on
-- the pane row), and a log not read says so instead of "0 of its quests".
-- Fails before: V.Quests dropped the note; the unread log read as empty.
tests["dungeon visit R-02: a hand-in not known keeps its note in the list"] = function(t)
    local V = ns.DungeonVisit
    local R = ns.DungeonRead
    local pane = { groups = { { id = "pickup", rows = { { id = 7, name = "Old Debt", note = R.DONE_UNKNOWN } } } } }
    local _, missing = V.Quests(pane, {}, {})
    t.eq(missing[1] and missing[1].unknown, true)
    local lines = V.QuestLines("Deadmines", {}, missing)
    t.ok(lines[2] and lines[2]:find(R.DONE_UNKNOWN, 1, true) ~= nil, tostring(lines[2]))
end

tests["dungeon visit R-02: a log not read says so, not none of its quests"] = function(t)
    local c, addon = boot()
    c.setQuestLog(nil)
    c.fire("QUEST_LOG_UPDATE")
    c.advance(0.2, 2)
    local api = addon.dungeonVisit
    t.ok(type(api) == "table" and type(api.Lines) == "function", "the visit api")
    if type(api) ~= "table" or type(api.Lines) ~= "function" then return end
    local out = api.Lines()
    local all = table.concat(type(out) == "table" and out or {}, "\n")
    t.ok(all:find(ns.DungeonRead.WHY_NO_LOG[1], 1, true) ~= nil, all)
    t.eq(all:find("0 of its quests", 1, true), nil, all)
end

-- R-04 (lead section 777; Plexy's note): a quest you pick up inside the
-- dungeon is listed too, as Flow's run lines ("Starts inside:", Modules/
-- Nav/Dungeons.lua D.QuestLines :1519-1537; D.EnterSplit :1110-1125 counts
-- every quest not in your log). Fails before: the "inside" group was
-- dropped from the visit's list.
tests["dungeon visit R-04: a quest picked up inside is listed, marked so"] = function(t)
    local V = ns.DungeonVisit
    local pane = { groups = {
        { id = "pickup", rows = { { id = 7, name = "Red Silk" } } },
        { id = "inside", rows = { { id = 8, name = "The Defias Brotherhood" } } },
    } }
    local _, missing = V.Quests(pane, {}, {})
    t.eq(#missing, 2)
    local inside
    for _, m in ipairs(missing) do
        if m.name == "The Defias Brotherhood" then inside = m end
    end
    t.eq(inside and inside.inside, true)
    local lines = V.QuestLines("Deadmines", {}, missing)
    t.ok(lines[2] and lines[2]:find("The Defias Brotherhood (" .. V.STARTS_INSIDE .. ")", 1, true) ~= nil,
        tostring(lines[2]))
end

return tests
