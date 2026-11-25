-- Tests for ZFlow/Nav/QuestOffers.lua (C-new-1): one talk to a quest giver
-- who does not offer a quest the route would send you to drops that quest
-- from the pick-ups; a word lists and clears the dropped ones; a talk that
-- could not be judged (Questie not ready) is tried again. Made-up NPCs and
-- quests, test only. Not tested in game.
local _, ns = ...

local QO = ns.QuestOffers
local tests = {}

local GIVER_GUID = "Creature-0-1-0-1-777-0000000001"

-- A Questie that knows one giver (npc 777) starting quests 11, 12 and 13.
local function questie(ready)
    local db = {}
    if ready ~= false then
        db.GetNPC = function(id)
            if id == 777 then return { name = "Old Giver", questStarts = { 11, 12, 13 } } end
            return nil
        end
    end
    db.GetQuest = function(id)
        local names = { [11] = "Wolves", [12] = "Boars", [13] = "Letters" }
        if names[id] then return { name = names[id] } end
        return nil
    end
    return db
end

-- opts: char (saved table), offered (what the window shows), ready (Questie
-- answers GetNPC), clock.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setClock(opts.clock or 100000)
    local db = questie(opts.ready)
    c.setQuestieModule("QuestieDB", db)
    c.setServiceNpc(GIVER_GUID, "Old Giver")
    c.setOfferedQuests(opts.offered)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local api = QO.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api, d, db
end

local function saved(c)
    local root = c.saved(ns.id.charDB)
    root = type(root) == "table" and root.learned or nil
    root = type(root) == "table" and root.facts or nil
    return type(root) == "table" and root.notOffered or nil
end

tests["quest offers: the names are the ones agreed"] = function(t)
    t.eq(QO.NAME, "questOffers")
    t.eq(QO.PATH, "learned.facts.notOffered", "where the import from Flow puts the list")
    t.eq(QO.WORD, "offers")
end

tests["quest offers: one talk drops a quest the giver does not offer"] = function(t)
    local k, c, api = start({ offered = { ids = { [11] = true }, titles = { Boars = true } } })
    c.fire("GOSSIP_SHOW")
    t.eq(api.dropped(11), false, "offered by id")
    t.eq(api.dropped(12), false, "offered by title")
    t.eq(api.dropped(13), true, "not on offer: dropped after one talk")
    t.eq(saved(c)[13].firstAt, 100000, "the first talk without it (section 806: Flow's firstAt)")
    t.eq(saved(c)[13].npc, "Old Giver")
    t.eq(k.problems:count(), 0)
end

tests["quest offers: a greeting window counts like gossip"] = function(t)
    local _, c, api = start({ offered = { ids = {}, titles = { Wolves = true, Boars = true } } })
    c.fire("QUEST_GREETING")
    t.eq(api.dropped(13), true)
    t.eq(api.dropped(11), false)
end

tests["quest offers: a window with no list concludes nothing"] = function(t)
    local _, c, api = start({ offered = nil })
    c.fire("GOSSIP_SHOW")
    t.eq(api.dropped(13), false)
    t.eq(saved(c), nil)
end

tests["quest offers: quests done or in the log are not judged"] = function(t)
    local _, c, api = start({ offered = { ids = {}, titles = {} } })
    c.setQuestDone(11, true)
    c.setQuestLog({ { id = 12, title = "Boars", objectives = {} } })
    c.fire("GOSSIP_SHOW")
    t.eq(api.dropped(11), false, "done")
    t.eq(api.dropped(12), false, "in the log")
    t.eq(api.dropped(13), true)
end

tests["quest offers: right after an accept the list is changing, so nothing is judged"] = function(t)
    local _, c, api = start({ offered = { ids = {}, titles = {} } })
    c.fire("QUEST_ACCEPTED")
    c.fire("GOSSIP_SHOW")
    t.eq(api.dropped(13), false)
    c.advance(QO.QUIET + 1)
    c.fire("GOSSIP_SHOW")
    t.eq(api.dropped(13), true)
end

tests["quest offers: offered again later brings the quest back"] = function(t)
    local _, c, api = start({ offered = { ids = {}, titles = {} } })
    c.fire("GOSSIP_SHOW")
    t.eq(api.dropped(13), true)
    c.setOfferedQuests({ ids = { [13] = true }, titles = {} })
    c.fire("GOSSIP_SHOW")
    t.eq(api.dropped(13), false)
end

-- Lead section 806 (section 563, as Flow's Q.NoteOffer and Q:Offered,
-- Modules/Quests/QuestData.lua:342-344, :362-373, :421-430 at origin/local
-- 4ce93c83): one talk without the quest drops it for QO.PAUSE (10 min);
-- missing again at a talk at least QO.GAP later drops it for QO.HIDE (a day).
tests["quest offers: one talk drops it for ten minutes, a second talk for a day"] = function(t)
    local _, c, api = start({ offered = { ids = {}, titles = {} } })
    c.fire("GOSSIP_SHOW")
    t.eq(api.dropped(13), true, "dropped after the first talk")
    c.setClock(100000 + QO.PAUSE + 1)
    t.eq(api.dropped(13), false, "back after ten minutes")
    c.fire("GOSSIP_SHOW")
    t.eq(api.dropped(13), true, "missing again: dropped")
    c.setClock(100000 + QO.PAUSE + 1 + QO.HIDE - 10)
    t.eq(api.dropped(13), true, "for a day")
    c.setClock(100000 + QO.PAUSE + 1 + QO.HIDE + 1)
    t.eq(api.dropped(13), false, "and back after it")
end

tests["quest offers: an entry imported from Flow counts"] = function(t)
    local _, _, api = start({ char = { learned = { facts = { notOffered = { [55] = { firstAt = 99000, hiddenAt = 99500 } } } } } })
    t.eq(api.dropped(55), true)
end

tests["quest offers: pure note and dropped"] = function(t)
    t.eq(QO.PAUSE, 600)
    t.eq(QO.HIDE, 86400)
    t.eq(QO.GAP, 60)
    local list = {}
    t.eq(QO.Note(list, 5, false, 10, "A"), "pause", "first talk without it")
    t.eq(QO.Dropped(list, 5, 10 + QO.PAUSE - 1), true)
    t.eq(QO.Dropped(list, 5, 10 + QO.PAUSE), false)
    t.eq(QO.Note(list, 5, false, 10 + QO.GAP - 1, "A"), nil, "a second talk too soon counts for nothing")
    t.eq(QO.Note(list, 5, false, 10 + QO.GAP, "A"), "day", "missing again at least a minute later")
    t.eq(QO.Dropped(list, 5, 10 + QO.GAP + QO.HIDE - 1), true)
    t.eq(QO.Dropped(list, 5, 10 + QO.GAP + QO.HIDE), false)
    t.eq(QO.Note(list, 5, false, 20 + QO.GAP, "A"), nil, "already dropped for the day: no change")
    t.eq(QO.Note(list, 5, true, 20), "back")
    t.eq(list[5], nil)
    t.eq(QO.Note(list, 6, true, 20), nil, "never dropped: nothing changes")
    t.eq(QO.Dropped(nil, 5, 0), false)
end

tests["quest offers: the word lists and clears, and says how many"] = function(t)
    local _, c, api, d = start({ offered = { ids = {}, titles = {} } })
    c.fire("GOSSIP_SHOW")
    t.eq(type(d.help[QO.WORD]), "string")
    d.commands[QO.WORD]("")
    local listed = table.concat(c.printed, "\n")
    t.ok(listed:find("Letters", 1, true) ~= nil, "the dropped quest is listed by name")
    d.commands[QO.WORD]("clear")
    t.ok(c.printed[#c.printed]:find(string.format(QO.CLEARED, 1), 1, true) ~= nil, c.printed[#c.printed])
    t.eq(api.dropped(13), false)
    t.eq(next(saved(c) or {}), nil, "the saved list is empty")
    d.commands[QO.WORD]("")
    t.ok(c.printed[#c.printed]:find(QO.NONE, 1, true) ~= nil)
end

-- Lead section 812 (Lazy CHANGES-1): clear counts only the quests dropped
-- now, the ones the word lists, but empties the whole saved list, a pause
-- that has run out included.
tests["quest offers: clear counts the quests dropped now and empties the list"] = function(t)
    local _, c, _, d = start({ offered = { ids = {}, titles = {} },
        char = { learned = { facts = { notOffered = { [99] = { firstAt = 1 } } } } } })
    c.fire("GOSSIP_SHOW")
    d.commands[QO.WORD]("clear")
    t.ok(c.printed[#c.printed]:find(string.format(QO.CLEARED, 1), 1, true) ~= nil,
        "one dropped now, the run-out pause not counted: " .. tostring(c.printed[#c.printed]))
    t.eq(next(saved(c) or {}), nil, "the saved list is empty, the old pause too")
end

-- Lead section 820 (Lazy CHANGES-2): the list and the clear count share one
-- helper, so a key the list skips (not a quest number) is never counted.
tests["quest offers: QO.Listed is what both the list and clear count"] = function(t)
    t.eq(type(QO.Listed), "function", "QO.Listed")
    if type(QO.Listed) ~= "function" then return end
    local l = { [5] = { firstAt = 90 }, [3] = { firstAt = 95 }, ["7"] = { firstAt = 95 }, [9] = { firstAt = -1000 } }
    t.eq(QO.Listed(l, 100), { 3, 5 }, "numbers only, dropped now, in order")
    t.eq(QO.Listed(nil, 100), {})
    local _, c, _, d = start({ offered = { ids = {}, titles = {} },
        char = { learned = { facts = { notOffered = { ["77"] = { firstAt = 100000 } } } } } })
    d.commands[QO.WORD]("clear")
    t.ok(c.printed[#c.printed]:find(string.format(QO.CLEARED, 0), 1, true) ~= nil,
        "a key that is no quest number is not counted: " .. tostring(c.printed[#c.printed]))
end

tests["quest offers: a talk Questie could not judge is tried again"] = function(t)
    local k, c, api, _, db = start({ offered = { ids = {}, titles = {} }, ready = false })
    c.fire("GOSSIP_SHOW")
    t.eq(api.dropped(13), false, "Questie not ready: nothing judged yet")
    t.eq(api.waiting(), 1)
    db.GetNPC = questie(true).GetNPC
    c.advance(QO.RETRY + 1)
    t.eq(api.dropped(13), true, "judged on the retry")
    t.eq(api.waiting(), 0)
    t.eq(k.problems:count(), 0)
end

tests["quest offers: retries stop after a few tries"] = function(t)
    local _, c, api = start({ offered = { ids = {}, titles = {} }, ready = false })
    c.fire("GOSSIP_SHOW")
    for _ = 1, QO.TRIES + 2 do c.advance(QO.RETRY + 1) end
    t.eq(api.waiting(), 0, "given up")
    t.eq(api.dropped(13), false)
end

tests["quest offers: the route's pick-ups leave a dropped quest out"] = function(t)
    local item = { kind = "pickup", quest = 13 }
    t.eq(ns.Nav.RoutePickups.Keep(item, function(id) return id == 13 end), false)
    t.eq(ns.Nav.RoutePickups.Keep({ quest = 11 }, function(id) return id == 13 end), true)
    t.eq(ns.Nav.RoutePickups.Keep({ quest = 11 }, nil), true)
end

return tests
