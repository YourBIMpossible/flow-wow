local _, ns = ...
-- Quest advice end to end (lead section 354 item 4, P-QUEST groundwork), on
-- the whole add-on loaded on a fake client. A quest that is complete in the
-- log gets one advisor prompt naming it; the prompt goes when the quest
-- leaves the log or the setting is turned off. Text only: nothing is
-- accepted or handed in. Offline: the reads are the fake client ones, not
-- the game. Not tested in game.
local tests = {}

local function start(log)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClass("MAGE")
    c.setLevel(20)
    if log ~= nil then c.setQuestLog(log) end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function prompt(addon)
    local A = ns.QuestAdvice or {}
    for _, p in ipairs(addon.advisor.List()) do
        if A.TURN_IN_PROMPT ~= nil and p.id == A.TURN_IN_PROMPT then return p.text end
    end
    return nil
end

local function row(id, title, complete)
    return { id = id, title = title, complete = complete == true, objectives = {} }
end

tests["quest advice: a complete quest in the log is named as ready to hand in"] = function(t)
    local _, addon = start({ row(1, "Test wolves", true), row(2, "Test boars") })
    t.eq(prompt(addon), "Ready to hand in: Test wolves. Look for the yellow ? over who takes it.")
end

tests["quest advice: no prompt with nothing complete, or with a log not read"] = function(t)
    local _, a1 = start({ row(2, "Test boars") })
    t.eq(prompt(a1), nil, "nothing complete")
    local _, a2 = start(nil)
    t.eq(prompt(a2), nil, "the log not read")
end

tests["quest advice: the prompt follows the log"] = function(t)
    local c, addon = start({ row(1, "Test wolves"), row(2, "Test boars") })
    t.eq(prompt(addon), nil)
    c.setQuestLog({ row(1, "Test wolves", true), row(2, "Test boars", true) })
    c.fire("QUEST_LOG_UPDATE")
    c.advance(1, 5)
    t.eq(prompt(addon), "Ready to hand in: Test wolves, Test boars. Look for the yellow ? over who takes it.", "both complete")
    c.setQuestLog({ row(2, "Test boars", true) })
    c.fire("QUEST_TURNED_IN", 1)
    c.fire("QUEST_LOG_UPDATE")
    c.advance(1, 5)
    t.eq(prompt(addon), "Ready to hand in: Test boars. Look for the yellow ? over who takes it.", "one handed in by the player")
    c.setQuestLog({})
    c.fire("QUEST_REMOVED", 2)
    c.advance(1, 5)
    t.eq(prompt(addon), nil, "the log empty")
end

tests["quest advice: the setting turns the prompt off and on"] = function(t)
    local A = ns.QuestAdvice or {}
    local c, addon = start({ row(1, "Test wolves", true) })
    t.ok(type(A.TURN_IN_SETTING) == "string", "the setting has a key")
    if type(A.TURN_IN_SETTING) ~= "string" then return end
    addon.settings:set(A.TURN_IN_SETTING, false)
    c.advance(1, 5)
    t.eq(prompt(addon), nil, "off")
    addon.settings:set(A.TURN_IN_SETTING, true)
    c.advance(1, 5)
    t.eq(prompt(addon), "Ready to hand in: Test wolves. Look for the yellow ? over who takes it.", "on again")
end

return tests
