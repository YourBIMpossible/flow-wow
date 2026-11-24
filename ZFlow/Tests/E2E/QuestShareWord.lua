local _, ns = ...
-- G50 (CAPABILITY-RECONCILE 2026-11-24), ACTING: the share word, on the
-- whole add-on loaded on a fake client. The player types the word; one
-- quest the client says can be shared is offered to the group, and a line
-- says which. One quest for each word typed, never by itself. Offline: the
-- share call is the fake client's, not the game's. Not tested in game.
local tests = {}

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClass("MAGE")
    c.setLevel(20)
    c.setQuestLog(opts.log or {})
    for id, v in pairs(opts.share or {}) do c.setQuestShareable(id, v) end
    c.setGrouped(opts.grouped)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function said(c, rest)
    local from = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = from + 1, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return table.concat(out, "\n")
end

local function prompt(addon)
    for _, p in ipairs(addon.advisor.List()) do
        if p.id == ns.QuestAdvice.SHARE_PROMPT then return p.text end
    end
    return nil
end

local function row(id, title, complete)
    return { id = id, title = title, complete = complete == true, objectives = {} }
end

local LOG = { row(1, "Test wolves"), row(2, "Test boars"), row(3, "Test bears") }
local SHARE = { [1] = true, [2] = false, [3] = true }
local T = ns.id.title .. ": "
local AGAIN = ns.id.slash .. " share"
local FIRST = T .. 'sharing "Test wolves" with your group. 1 more: type ' .. AGAIN .. " again."

tests["share word: the advice line says the word to type"] = function(t)
    local c, addon = start({ log = LOG, share = SHARE, grouped = true })
    t.eq(prompt(addon), "You can share with your group: Test wolves, Test bears. Type " .. AGAIN .. " to offer one.")
    t.eq(c.sharedQuests, {}, "the line alone shares nothing")
end

tests["share word: each word typed offers one quest, in log order, and says which"] = function(t)
    local c = start({ log = LOG, share = SHARE, grouped = true })
    t.eq(said(c, "share"), FIRST)
    t.eq(c.sharedQuests, { 1 })
    t.eq(said(c, "share"), T .. 'sharing "Test bears" with your group. That was the last one.')
    t.eq(c.sharedQuests, { 1, 3 })
    t.eq(said(c, "share"), FIRST, "all offered: it starts over")
    t.eq(c.sharedQuests, { 1, 3, 1 })
end

tests["share word: nothing is shared without the word"] = function(t)
    local c = start({ log = LOG, share = SHARE, grouped = false })
    c.setGrouped(true)
    c.fire("GROUP_ROSTER_UPDATE")
    c.fire("QUEST_LOG_UPDATE")
    c.advance(30, 60)
    t.eq(c.sharedQuests, {})
end

tests["share word: alone, or not known to be in a group: a line, and nothing shared"] = function(t)
    for _, grouped in ipairs({ false, "unset" }) do
        local known = nil
        if grouped ~= "unset" then known = grouped end
        local c = start({ log = LOG, share = SHARE, grouped = known })
        t.eq(said(c, "share"), T .. "you are not in a group, so there is no one to share with.")
        t.eq(c.sharedQuests, {})
    end
end

tests["share word: no quest the client says can be shared: a line, and nothing shared"] = function(t)
    local c = start({ log = LOG, share = { [2] = false }, grouped = true })
    t.eq(said(c, "share"), T .. "no quest in your log can be shared.")
    local done = start({ log = { row(1, "Test wolves", true) }, share = { [1] = true }, grouped = true })
    t.eq(said(done, "share"), T .. "no quest in your log can be shared.", "a complete quest is not offered")
    t.eq(c.sharedQuests, {})
    t.eq(done.sharedQuests, {})
end

tests["share word: the game refusing is said, and the same quest is offered at the next word"] = function(t)
    local c, addon = start({ log = LOG, share = SHARE, grouped = true })
    local problems = #addon.problems:list()
    c.setShareRefuse("raised")
    t.eq(said(c, "share"), T .. 'could not share "Test wolves": the game refused.')
    c.setShareRefuse(nil)
    t.eq(said(c, "share"), FIRST)
    t.eq(#addon.problems:list(), problems, "no new problem line")
end

tests["share word: leaving the group forgets what was offered"] = function(t)
    local c = start({ log = LOG, share = SHARE, grouped = true })
    said(c, "share")
    c.setGrouped(false)
    said(c, "share")
    c.setGrouped(true)
    t.eq(said(c, "share"), FIRST)
end

tests["share word: another word after it says what the word does; help lists it"] = function(t)
    local c, addon = start({ log = LOG, share = SHARE, grouped = true })
    t.eq(said(c, "share all"), T .. AGAIN .. " offers one quest from your log to your group.")
    t.eq(c.sharedQuests, {})
    t.eq(addon.diag.help[ns.QuestShare.WORD], ns.QuestShare.HELP, "in the help list")
end

return tests
