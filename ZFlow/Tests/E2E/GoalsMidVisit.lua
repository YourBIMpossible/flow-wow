local _, ns = ...
-- Lead section 218. A goal added or removed with the goal word while a
-- merchant window is open: the open sell list follows it at once, in the
-- same visit, listed once. Otherwise one evaluation per visit still holds
-- (Tests/E2E/SellReservations.lua). Whole add-on on a fake client, the
-- "goals" source, no test-only source.
-- Offline: the reads are the fake client's, not the game's. Not tested in game.
local tests = {}

local PELT = 4865
local INFO = {
    [PELT] = { name = "Ruined Pelt", quality = 0, sellPrice = 5, classID = 15 },
}
local BAG = { { item = PELT, count = 15 }, { item = PELT, count = 5 } }   -- 20 pelts

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setItemInfo(INFO)
    c.setBagItems(BAG)
    local addon = ns.offline.addon(c)
    c.lists = { SellList = addon.sellList, BankList = addon.bankList }
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

-- The list as the player has it since it moved to the window kit (lead
-- section 303): whether its kit window is shown, and the text lines of the
-- last listing (what the text panel shows on a client that cannot draw the
-- kit). Read each time it is asked, as a panel's own fields were.
local function panelOf(c)
    local id = "SellList"
    if type(c.kitWindows()[id]) ~= "table" then return nil end
    return setmetatable({}, { __index = function(_, field)
        if field == "shown" then return c.kitWindows()[id].shown end
        if field == "lines" then return c.lists[id].last() or {} end
        return nil
    end })
end

local function joined(lines) return table.concat(lines or {}, " / ") end

local function has(lines, text)
    for _, l in ipairs(lines or {}) do
        if l == text then return true end
    end
    return false
end

local function finds(lines, text)
    for _, l in ipairs(lines or {}) do
        if l:find(text, 1, true) then return true end
    end
    return false
end

local function peltRows(lines)
    local out = {}
    for _, l in ipairs(lines or {}) do
        local n = l:match("^(%d+) x Ruined Pelt: ")
        if n then out[#out + 1] = tonumber(n) end
    end
    return out
end

-- The open sell panel's lines, as the player sees them now.
local function shown(c)
    local p = panelOf(c)
    return p and p.shown and p.lines or nil
end

local function word(c, rest) c.slashes[ns.id.slash](rest) end

tests["goal mid visit: added then removed while the merchant is open, the open list follows, once each"] = function(t)
    local c, addon = start()
    c.setMerchantOpen(true)
    t.eq(peltRows(shown(c)), { 20 }, "no goal: all twenty offered: " .. joined(shown(c)))

    local before = addon.sellList.shows()
    word(c, "goal add " .. PELT .. " 8")
    t.eq(addon.sellList.shows() - before, 1, "the goal change lists once")
    t.eq(peltRows(shown(c)), { 12 }, "same visit: twelve offered: " .. joined(shown(c)))
    t.ok(has(shown(c), "Ruined Pelt: 8 held for your steps"), "eight held: " .. joined(shown(c)))

    before = addon.sellList.shows()
    word(c, "goal remove " .. PELT)
    t.eq(addon.sellList.shows() - before, 1, "the removal lists once")
    t.eq(peltRows(shown(c)), { 20 }, "removed: twenty again: " .. joined(shown(c)))
    t.ok(not finds(shown(c), "held for your steps"), "nothing held: " .. joined(shown(c)))
    c.setMerchantOpen(false)
end

tests["goal mid visit: a goal word that changes nothing does not list again"] = function(t)
    local c, addon = start()
    c.setMerchantOpen(true)
    local before = addon.sellList.shows()
    word(c, "goal list")
    word(c, "goal remove " .. PELT)        -- not a goal: nothing changes
    word(c, "goal add")                    -- usage
    t.eq(addon.sellList.shows() - before, 0, "no change, no listing")
    t.eq(peltRows(shown(c)), { 20 }, joined(shown(c)))
    c.setMerchantOpen(false)
end

tests["goal mid visit: a goal added away from a merchant makes no listing; the next visit has it"] = function(t)
    local c, addon = start()
    c.setMerchantOpen(true); c.setMerchantOpen(false)
    local before = addon.sellList.shows()
    word(c, "goal add " .. PELT .. " 8")
    t.eq(addon.sellList.shows() - before, 0, "no merchant: no listing")
    c.setMerchantOpen(true)
    t.eq(peltRows(shown(c)), { 12 }, "next visit: twelve offered: " .. joined(shown(c)))
    c.setMerchantOpen(false)
end

return tests
