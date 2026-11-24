local _, ns = ...
-- The bags word (parity row E-05), end to end, on the whole add-on loaded on
-- a fake client: `<slash> bags off` switches the bag marks off and the marks
-- go, `<slash> bags on` brings them back, the bare word says which it is,
-- and anything else prints the usage line and changes nothing. It is the
-- settings row bags.marks (Items/BagMarks.lua), not a second switch.
-- Look only: nothing is used, sold or moved. Made-up items.
-- Offline: the reads are the fake client's, not the game's. Not tested in game.
--
-- Fails before the change: there is no bags word, so the slash command says
-- its own fallback line and the setting stays as it was.
local tests = {}

local INFO = {
    [7001] = { name = "Cracked Pot", quality = 0, sellPrice = 3, classID = 15 },
    [7002] = { name = "Sealed Note", quality = 1, sellPrice = 0, classID = 12 },
}
local BAG = {
    { bag = 0, slot = 1, item = "item:7001:0:0:0:0:0:0:0", count = 4 },
    { bag = 0, slot = 2, item = "item:7002:0:0:0:0:0:0:0", count = 1 },
}
local MARKS = { [0] = { [1] = "sell", [2] = "quest" } }

local atBoot = setmetatable({}, { __mode = "k" })
local function newProblems(addon) return addon.problems:count() - atBoot[addon] end

-- on: the saved setting at login; nil leaves it at its default (on).
local function boot(on)
    local c = ns.make.fakeClient()
    local account = {}
    if on ~= nil then account.settings = { bags = { marks = on } } end
    c.setSaved(ns.id.accountDB, account)
    c.setSaved(ns.id.charDB, {})
    c.setItemInfo(INFO)
    c.setBagItems(BAG)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    c.fire("BAG_UPDATE_DELAYED")
    atBoot[addon] = addon.problems:count()
    return c, addon
end

-- What the word printed, and only that.
local function said(c, rest)
    local from = #c.printed + 1
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = from, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return out
end

local function setting(addon) return addon.settings:get("bags.marks") end
local function drawn(c) return c.bagMarksDrawn and c.bagMarksDrawn() or nil end

local function cmd() return ns.id.slash .. " bags" end
local function onLine()
    return ns.id.title .. ": bag marks are on. Turn them off with " .. cmd() .. " off."
end
local function offLine()
    return ns.id.title .. ": bag marks are off. Turn them on with " .. cmd() .. " on."
end
local function usageLine()
    return ns.id.title .. ": " .. cmd() .. " on or " .. cmd() .. " off switches the marks on your bag slots; "
        .. cmd() .. " alone says which it is."
end

tests["bags word: off switches the setting off and the marks go"] = function(t)
    local c, addon = boot()
    t.eq(setting(addon), true, "on by default")
    t.eq(drawn(c), MARKS, "the marks are drawn first")
    t.eq(said(c, "bags off"), { offLine() })
    t.eq(setting(addon), false, "the same setting row")
    t.eq(addon.store:get("account", "settings.bags.marks"), false, "saved for the account")
    t.eq(drawn(c), {}, "the marks go at once")
    c.fire("BAG_UPDATE_DELAYED")
    t.eq(drawn(c), {}, "and stay away on the next bag change")
    t.eq(#(c.soldSlots or {}), 0, "nothing sold by the add-on")
    t.eq(newProblems(addon), 0, "no new problems")
end

tests["bags word: on switches it back and the marks return"] = function(t)
    local c, addon = boot(false)
    t.eq(setting(addon), false, "saved off")
    t.eq(drawn(c), {}, "no marks while it is off")
    t.eq(said(c, "bags on"), { onLine() })
    t.eq(setting(addon), true)
    t.eq(drawn(c), MARKS, "the marks are back at once")
    t.eq(newProblems(addon), 0, "no new problems")
end

tests["bags word: off then on, typed in capitals too"] = function(t)
    local c, addon = boot()
    t.eq(said(c, "BAGS OFF"), { offLine() })
    t.eq(setting(addon), false)
    t.eq(said(c, "  Bags   On  "), { onLine() })
    t.eq(setting(addon), true)
    t.eq(drawn(c), MARKS)
    t.eq(said(c, "bags on"), { onLine() }, "on again says the same and stays on")
    t.eq(setting(addon), true)
    t.eq(newProblems(addon), 0, "no new problems")
end

tests["bags word: alone it says which it is and changes nothing"] = function(t)
    local c, addon = boot()
    t.eq(said(c, "bags"), { onLine() })
    t.eq(setting(addon), true, "still on")
    t.eq(addon.store:get("account", "settings.bags.marks"), nil, "nothing was written")
    t.eq(drawn(c), MARKS, "the marks are as they were")
    local c2, addon2 = boot(false)
    t.eq(said(c2, "bags"), { offLine() })
    t.eq(setting(addon2), false, "still off")
    t.eq(drawn(c2), {})
    t.eq(newProblems(addon), 0, "no new problems")
    t.eq(newProblems(addon2), 0, "no new problems")
end

tests["bags word: anything else prints the usage line and changes nothing"] = function(t)
    local c, addon = boot()
    for _, rest in ipairs({ "bags maybe", "bags on please", "bags offf", "bags 1" }) do
        t.eq(said(c, rest), { usageLine() }, rest)
        t.eq(setting(addon), true, rest .. ": still on")
        t.eq(addon.store:get("account", "settings.bags.marks"), nil, rest .. ": nothing was written")
        t.eq(drawn(c), MARKS, rest .. ": the marks are as they were")
    end
    local c2, addon2 = boot(false)
    t.eq(said(c2, "bags maybe"), { usageLine() })
    t.eq(setting(addon2), false, "still off")
    t.eq(drawn(c2), {})
    t.eq(newProblems(addon), 0, "no new problems")
    t.eq(newProblems(addon2), 0, "no new problems")
end

tests["bags word: help lists it with a line of its own"] = function(t)
    local c, addon = boot()
    local help = addon.diag.help.bags
    t.eq(type(help), "string", "the word has a help line")
    t.eq(said(c, "help bags"), { ns.id.title .. ": " .. cmd() .. " - " .. tostring(help) })
    t.eq(setting(addon), true, "asking for help changes nothing")
    t.eq(newProblems(addon), 0, "no new problems")
end

return tests
