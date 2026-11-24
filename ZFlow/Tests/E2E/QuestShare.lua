local _, ns = ...
-- Quest share advice end to end (lead section 354 item 4, P-QUEST
-- groundwork), on the whole add-on loaded on a fake client. In a group, the
-- quests the client says can be shared are named in one advisor prompt.
-- Text only: nothing is shared. Offline: the reads are the fake client
-- ones, not the game. Not tested in game.
local tests = {}

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setClass("MAGE")
    c.setLevel(20)
    c.setQuestLog(opts.log or {})
    if type(c.setQuestShareable) == "function" then
        for id, v in pairs(opts.share or {}) do c.setQuestShareable(id, v) end
    end
    c.setGrouped(opts.grouped)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function prompt(addon)
    local A = ns.QuestAdvice or {}
    for _, p in ipairs(addon.advisor.List()) do
        if A.SHARE_PROMPT ~= nil and p.id == A.SHARE_PROMPT then return p.text end
    end
    return nil
end

local function row(id, title, complete)
    return { id = id, title = title, complete = complete == true, objectives = {} }
end

local LOG = { row(1, "Test wolves"), row(2, "Test boars"), row(3, "Test bears") }
local LINE = "You can share with your group: Test wolves, Test bears. Type " .. ns.id.slash .. " share to offer one."

tests["quest share: in a group the shareable quests are named"] = function(t)
    local _, addon = start({ log = LOG, share = { [1] = true, [2] = false, [3] = true }, grouped = true })
    t.eq(prompt(addon), LINE)
end

tests["quest share: nothing alone, nothing when grouping is not known, nothing unshareable"] = function(t)
    local share = { [1] = true, [3] = true }
    local _, a1 = start({ log = LOG, share = share, grouped = false })
    t.eq(prompt(a1), nil, "alone")
    local _, a2 = start({ log = LOG, share = share, grouped = nil })
    t.eq(prompt(a2), nil, "not known")
    local _, a3 = start({ log = LOG, share = {}, grouped = true })
    t.eq(prompt(a3), nil, "the client does not say any can be shared")
end

tests["quest share: the prompt comes on joining a group and goes on leaving"] = function(t)
    local c, addon = start({ log = LOG, share = { [1] = true, [3] = true }, grouped = false })
    t.eq(prompt(addon), nil)
    c.setGrouped(true)
    c.fire("GROUP_ROSTER_UPDATE")
    c.advance(1, 5)
    t.eq(prompt(addon), LINE, "joined")
    c.setGrouped(false)
    c.fire("GROUP_ROSTER_UPDATE")
    c.advance(1, 5)
    t.eq(prompt(addon), nil, "left")
end

tests["quest share: the setting turns the prompt off and on"] = function(t)
    local A = ns.QuestAdvice or {}
    local c, addon = start({ log = LOG, share = { [1] = true, [3] = true }, grouped = true })
    t.ok(type(A.SHARE_SETTING) == "string", "the setting has a key")
    if type(A.SHARE_SETTING) ~= "string" then return end
    addon.settings:set(A.SHARE_SETTING, false)
    c.advance(1, 5)
    t.eq(prompt(addon), nil, "off")
    addon.settings:set(A.SHARE_SETTING, true)
    c.advance(1, 5)
    t.eq(prompt(addon), LINE, "on again")
end

return tests
