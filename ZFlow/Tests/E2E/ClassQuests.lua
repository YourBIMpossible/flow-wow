local _, ns = ...
-- Class quests end to end (lead section 242, DRUID-2), on the whole add-on
-- loaded on a fake client. A Druid at the level a class-quest form is taught
-- is told to ask the class trainer, in words only. When the form is learned
-- and one quest has just left the quest log, that quest is kept for the
-- account with the spell it gave, so a later Druid on the account is told
-- the quest by its title. No quest id comes from a table: each is one the
-- player held. Offline: the reads are the fake client ones, not the game.
-- Not tested in game.
local tests = {}

local BEAR = 5487
local QUEST, OTHER = 9001, 9002
local TITLE, OTHER_TITLE = "Test class quest", "Test other quest"
local ASK = "Bear Form: ask your class trainer at level 10"

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, {})
    c.setClass(opts.class or "DRUID")
    c.setLevel(opts.level or 10)
    c.setSpellId("Bear Form", BEAR)
    c.setSpell(BEAR, { known = opts.knowsBear == true })
    if opts.log ~= false then c.setQuestLog(opts.log or {}) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function prompt(addon)
    local M = ns.ClassQuests or {}
    for _, p in ipairs(addon.advisor.List()) do
        if p.id == M.PROMPT then return p.text end
    end
    return nil
end

local function kept(c)
    local account = c.saved(ns.id.accountDB)
    local learned = type(account.learned) == "table" and account.learned or {}
    local quests = type(learned.classQuests) == "table" and learned.classQuests or {}
    return quests.DRUID
end

local function row(id, title, complete)
    return { id = id, title = title, complete = complete == true, objectives = {} }
end

-- The quest is handed in: it leaves the log and the form is learned, in
-- either order.
local function handIn(c, logAfter, learnFirst)
    local function learn()
        c.setSpell(BEAR, { known = true })
        c.learnSpell({ id = BEAR, name = "Bear Form" })
    end
    if learnFirst then learn() end
    c.setQuestLog(logAfter)
    c.fire("QUEST_TURNED_IN", QUEST)
    c.fire("QUEST_LOG_UPDATE")
    if not learnFirst then learn() end
    c.advance(1, 5)
end

tests["class quests: a druid at level 10 is told to ask the class trainer, in words only"] = function(t)
    local _, addon = start()
    t.eq(prompt(addon), ASK)
end

tests["class quests: nothing before the level, nothing once the form is known, nothing for another class"] = function(t)
    local _, a1 = start({ level = 9 })
    t.eq(prompt(a1), nil, "level 9")
    local _, a2 = start({ knowsBear = true })
    t.eq(prompt(a2), nil, "the form known")
    local _, a3 = start({ class = "MAGE" })
    t.eq(prompt(a3), nil, "a mage")
end

tests["class quests: the quest that left the log when the form was learned is kept for the account"] = function(t)
    local c, addon = start({ log = { row(QUEST, TITLE, true), row(OTHER, OTHER_TITLE) } })
    t.eq(prompt(addon), ASK)
    handIn(c, { row(OTHER, OTHER_TITLE) })
    t.eq(kept(c), { [QUEST] = { title = TITLE, spell = "Bear Form" } })
    t.eq(prompt(addon), nil, "the form is learned")
end

-- Section 236: data arriving late. The spell is learned before the log
-- update says the quest has gone; the quest is still matched.
tests["class quests: the form learned before the log update still finds its quest"] = function(t)
    local c = start({ log = { row(QUEST, TITLE, true), row(OTHER, OTHER_TITLE) } })
    handIn(c, { row(OTHER, OTHER_TITLE) }, true)
    t.eq(kept(c), { [QUEST] = { title = TITLE, spell = "Bear Form" } })
end

tests["class quests: two quests gone at once keep nothing; unknown stays unknown"] = function(t)
    local c = start({ log = { row(QUEST, TITLE, true), row(OTHER, OTHER_TITLE, true) } })
    handIn(c, {})
    t.eq(kept(c), nil)
end

tests["class quests: a quest gone with a spell that no class quest gives keeps nothing"] = function(t)
    local c = start({ log = { row(QUEST, TITLE, true) } })
    c.setQuestLog({})
    c.fire("QUEST_LOG_UPDATE")
    c.learnSpell({ id = 8921, name = "Moonfire" })
    c.advance(1, 5)
    t.eq(kept(c), nil)
end

-- Section 236: a reload in the middle. A later Druid on the same account
-- reads the kept quest back and is told it by its title.
tests["class quests: a reload, then another druid on the account is told the quest by title"] = function(t)
    local c = start({ log = { row(QUEST, TITLE, true) } })
    handIn(c, {})
    local account = c.saved(ns.id.accountDB)
    local _, a2 = start({ account = account })
    t.eq(prompt(a2), "Bear Form: ask your class trainer for " .. TITLE)
    local _, a3 = start({ account = account, log = { row(QUEST, TITLE) } })
    t.eq(prompt(a3), "Bear Form: " .. TITLE .. " is in your quest log")
end

-- Section 236: a read that fails then recovers. The log can not be read at
-- login; the words still show, and once the log answers the quest is found.
tests["class quests: a log that can not be read at first, then recovers"] = function(t)
    local c, addon = start({ log = false })
    t.eq(prompt(addon), ASK, "words with no log")
    c.setQuestLog({ row(QUEST, TITLE, true) })
    c.fire("QUEST_LOG_UPDATE")
    handIn(c, {})
    t.eq(kept(c), { [QUEST] = { title = TITLE, spell = "Bear Form" } })
end

return tests
