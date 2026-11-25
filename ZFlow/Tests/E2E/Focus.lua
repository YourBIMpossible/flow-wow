local _, ns = ...

-- End to end (lead section 477, parity rows A1-44, A1-45, A1-47, A1-48):
-- the custom route's quest lines. A picked quest's line is the quests
-- before it not done, the quest, and those Questie chains after it;
-- `/zflow focus` lists the lines and `focus clear` clears them; a line
-- whose quests are all done leaves with a chat line. On the whole add-on
-- with a fake client and a made-up Questie; made-up quests. Not tested in
-- game.
-- Fails before: "focus" is no word, so nothing is listed or cleared.

local tests = {}

local MAP = 1411
local QUESTS = {
    [701] = { Id = 701, name = "First Steps", nextQuestInChain = 702 },
    [702] = { Id = 702, name = "Second Steps", preQuestSingle = { 701 }, nextQuestInChain = 703 },
    [703] = { Id = 703, name = "Last Steps", preQuestSingle = { 702 } },
    [801] = { Id = 801, name = "Lone Errand" },
    [901] = { Id = 901, name = "Gated Errand", preQuestSingle = { 999 } },
}

local function boot(lines, log)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, lines and { state = { nav = { focus = lines } } } or {})
    c.setZone(1, MAP); c.setPosition(MAP, 0.5, 0.5); c.setMapSize(MAP, 1000, 500); c.setMapCont(MAP, 1)
    c.setClass("WARRIOR"); c.setFaction("Horde"); c.setLevel(20)
    c.setQuestLog(log or {})
    local db = { QuestPointers = {} }
    function db.GetQuest(id) return QUESTS[id] end
    c.setQuestieModule("QuestieDB", db)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

-- rest: a word to say first, after forgetting what was printed before. With
-- no word, what was printed since the test last emptied c.printed.
local function said(c, rest)
    if rest then
        c.printed = {}
        c.slashes[ns.id.slash](rest)
    end
    local out, prefix = {}, ns.id.title .. ": "
    for _, line in ipairs(c.printed) do
        local s = tostring(line)
        if s:sub(1, #prefix) == prefix then s = s:sub(#prefix + 1) end
        out[#out + 1] = s
    end
    return out
end

tests["focus e2e: /zflow focus lists the picked quest's whole line"] = function(t)
    local c = boot({ { quest = 702 } })
    t.eq(said(c, "focus"), {
        "custom route lines: 1",
        "  1. Last Steps: quests 701, 702, 703",
        "  " .. ns.id.slash .. " focus clear",
    })
end

tests["focus e2e: focus clear empties the custom route"] = function(t)
    local c = boot({ { quest = 702 } })
    t.eq(said(c, "focus clear"), { "custom route cleared" })
    t.eq(said(c, "focus")[1], "custom route lines: 0")
end

tests["focus e2e: adding a quest says its line; a quest already in a line adds nothing"] = function(t)
    local c, addon = boot()
    local focus = addon.use and addon.use("focus") or ns.focus
    c.printed = {}
    t.eq(focus.Add(801), "Lone Errand")
    t.eq(said(c), { "Custom route: Lone Errand. Its steps are your route now." })
    t.eq(focus.Add(801), nil)
end

tests["focus e2e: remove this step and what follows; remove the whole line"] = function(t)
    local c, addon = boot({ { quest = 702 }, { quest = 801 } })
    local focus = addon.use and addon.use("focus") or ns.focus
    t.eq(focus.RemoveFrom(702), true)
    t.eq(said(c, "focus")[2], "  1. Last Steps: quests 701 (ends before 702)")
    t.eq(focus.RemoveLine(801), true)
    t.eq(said(c, "focus")[1], "custom route lines: 1")
end

tests["focus e2e: a line whose quests are all done leaves with a chat line"] = function(t)
    local c = boot({ { quest = 801, title = "Lone Errand" } })
    c.printed = {}
    c.setQuestDone(801, true)
    c.advance(3, 6)
    t.eq(said(c), { "Custom route: Lone Errand is done.", "Custom route finished: back to your usual route." })
end

tests["focus e2e: a line needing a quest the data lacks says it is blocked"] = function(t)
    local c = boot({ { quest = 901 } })
    local got = said(c, "focus")
    t.eq(got[2], "  1. Gated Errand: quests 901")
    t.eq(got[3], "     blocked: needs quest(s) 999 first, which the quest data doesn't have (not routed)")
end

tests["focus e2e: a quest still in the log keeps its line"] = function(t)
    local c = boot({ { quest = 801 } }, { { id = 801, title = "Lone Errand", objectives = {} } })
    c.setQuestDone(801, true)
    c.advance(3, 6)
    t.eq(said(c, "focus")[1], "custom route lines: 1")
end

tests["focus e2e: the title of the line that holds a quest, for the menu's Remove rows"] = function(t)
    local _, addon = boot({ { quest = 702 } })
    local focus = addon.use and addon.use("focus") or ns.focus
    t.eq(focus.TitleOf(701), "Last Steps")
    t.eq(focus.TitleOf(801), nil, "a quest on no line has no title")
end

return tests
