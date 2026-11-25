local _, ns = ...
-- Rotation/FoodWord.lua (parity row D-13; lead section 668): the word
-- `<slash> food` lists the Well Fed foods you carry, the pick and when.
-- Made-up items on the fake client. Offline only: not tested in game.
local tests = {}
local FW = ns.FoodWord

local RIBS = 9101
local LINES = { "Spiced Wolf Ribs", "Use: Restores 552 health over 21 sec. If you spend at least 10 seconds "
    .. "eating you will become well fed and gain 6 Stamina and Spirit for 15 min." }

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {}); c.setSaved(ns.id.charDB, {})
    c.setClass("WARRIOR")
    c.setPlayerBuffs(opts.buffs or {})
    c.setBagItems(opts.bags or { { item = RIBS, count = 2 } })
    c.setItemInfo({ [RIBS] = { name = "Spiced Wolf Ribs", classID = 0, subclassID = 5 } })
    c.setItemLines(RIBS, LINES)
    local k = ns.Kernel({}, c)
    local diag = ns.Diag.Start(k)
    FW.Declare(k, diag)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    return c, k, diag
end

-- Fails before: there is no such word.
tests["food word: the foods you carry, the pick marked, under the title"] = function(t)
    local c, k, diag = start()
    t.eq(type(diag.commands[FW.WORD]), "function")
    t.eq(diag.help[FW.WORD], FW.HELP)
    c.printed = {}
    diag.commands[FW.WORD]("")
    t.ok(c.printed[1] and c.printed[1]:find(k.id.title .. ": Well Fed food for ", 1, true) == 1, tostring(c.printed[1]))
    t.ok(c.printed[2] and c.printed[2]:find("  * Spiced Wolf Ribs: 6 Spirit, 6 Stamina; score ", 1, true) == 1,
        tostring(c.printed[2]))
    t.eq(k.problems:count(), 0)
end

tests["food word: Well Fed on you is said, and nothing in the bags is said"] = function(t)
    local c, _, diag = start({ buffs = { ["Well Fed"] = 600 } })
    c.printed = {}
    diag.commands[FW.WORD]("")
    t.eq(c.printed[#c.printed], ns.BuffFood.WHY_FED)
    local c2, _, diag2 = start({ bags = {} })
    c2.printed = {}
    diag2.commands[FW.WORD]("")
    t.ok(c2.printed[1]:find(ns.BuffFood.WHY_NONE, 1, true) ~= nil, c2.printed[1])
end

tests["food word: bags not read are said to be not read, never empty"] = function(t)
    local c, _, diag = start()
    c.setBagItems(nil)
    c.printed = {}
    diag.commands[FW.WORD]("")
    t.ok(c.printed[1]:find(FW.UNREAD, 1, true) ~= nil, c.printed[1])
end

return tests
