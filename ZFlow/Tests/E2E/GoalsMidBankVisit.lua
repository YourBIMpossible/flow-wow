local _, ns = ...
-- Lead section 219. A goal added or removed with the goal word while the
-- bank window is open: the open bank list and the bank prompt follow it at
-- once, in the same visit, the list drawn once per change. With the bank
-- closed a change draws nothing. The banker word, run after a mid-visit
-- goal add, holds the goal back too. Whole add-on on a fake client, the
-- "goals" source, no test-only source.
-- Offline: the reads are the fake client's, not the game's. Not tested in game.
local tests = {}

local LINEN = 2589
local INFO = {
    [LINEN] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },
}
local BAG = { { item = LINEN, count = 15 }, { item = LINEN, count = 5 } }   -- 20 Linen

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setItemInfo(INFO)
    c.setBagItems(BAG)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function panelOf(c)
    for _, p in ipairs(c.panels) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. "BankList" then return p end
    end
    return nil
end

local function promptOf(addon)
    for _, p in ipairs(addon.advisor.List()) do
        if p.id == addon.BankList.PROMPT_ID then return p.text end
    end
    return nil
end

local function joined(lines) return table.concat(lines or {}, " / ") end

local function has(lines, text)
    for _, l in ipairs(lines or {}) do
        if l == text then return true end
    end
    return false
end

local function word(c, rest)
    c.slashes[ns.id.slash](rest)
end

-- The "To bank" part of what the banker word prints, without the title.
local function banker(c)
    local from = #c.printed
    word(c, "banker")
    local p = ns.id.title .. ": "
    local out, part = {}, "bank"
    for i = from + 1, #c.printed do
        local line = tostring(c.printed[i])
        if line:sub(1, #p) == p then line = line:sub(#p + 1) end
        if line:find("^In your bank") then part = "rest" end
        if part == "bank" then out[#out + 1] = line end
    end
    return out
end

-- The open bank panel's lines, as the player sees them now.
local function shown(c)
    local p = panelOf(c)
    if p and p.shown then return p.lines end
    return nil
end

local KEPT20 = "20 x Linen Cloth: kept for later"
local KEPT12 = "12 x Linen Cloth: kept for later"

tests["goal mid bank visit: added then removed while the bank is open, the open list follows, once each"] = function(t)
    local c, addon = start()
    c.setBankOpen(true)
    local made = addon.bankList.shows()
    t.ok(has(shown(c), KEPT20), "no goal: all 20 to the bank: " .. joined(shown(c)))
    word(c, "goal add " .. LINEN .. " 8")
    t.eq(addon.bankList.shows() - made, 1, "the goal change lists once")
    local lines = shown(c)
    t.ok(has(lines, KEPT12), "same visit: twelve to the bank: " .. joined(lines))
    t.ok(not has(lines, KEPT20), "not all 20: " .. joined(lines))
    t.ok(has(lines, ns.ItemPresent.HELD_HEADER) and has(lines, "8 x Linen Cloth"), "eight held: " .. joined(lines))
    word(c, "goal remove " .. LINEN)
    t.eq(addon.bankList.shows() - made, 2, "the removal lists once")
    lines = shown(c)
    t.ok(has(lines, KEPT20), "goal gone: all 20 again: " .. joined(lines))
    t.ok(not has(lines, "8 x Linen Cloth"), "nothing held: " .. joined(lines))
    c.setBankOpen(false)
end

tests["goal mid bank visit: the bank prompt follows the goal while the bank is open"] = function(t)
    local c, addon = start()
    c.setBankOpen(true)
    t.eq(promptOf(addon), "1 kind of item to put in the bank.", "no goal: one kind to bank")
    word(c, "goal add " .. LINEN .. " 20")
    t.eq(promptOf(addon), nil, "every Linen held: nothing to bank, no prompt")
    word(c, "goal remove " .. LINEN)
    t.eq(promptOf(addon), "1 kind of item to put in the bank.", "goal gone: the prompt is back")
    c.setBankOpen(false)
end

tests["goal mid bank visit: the banker word after a mid-visit goal add holds the 8 back"] = function(t)
    local c = start()
    c.setBankOpen(true)
    word(c, "goal add " .. LINEN .. " 8")
    local said = banker(c)
    t.ok(has(said, KEPT12), "the word: twelve to bank: " .. joined(said))
    t.ok(has(said, "8 x Linen Cloth"), "the word: eight held: " .. joined(said))
    t.eq(said, shown(c), "the word lists what the open panel lists")
    c.setBankOpen(false)
end

-- The banker word asks the reservations each time it is run: a goal added
-- with the bank closed and no bag event is held at the next word.
tests["goal mid bank visit: the banker word reads the goals each time it is run"] = function(t)
    local c = start()
    t.ok(has(banker(c), KEPT20), "no goal: all 20")
    word(c, "goal add " .. LINEN .. " 8")
    local said = banker(c)
    t.ok(has(said, KEPT12) and has(said, "8 x Linen Cloth"), "the next word holds the 8: " .. joined(said))
end

tests["goal mid bank visit: with the bank closed a goal change draws nothing; the next visit has it"] = function(t)
    local c, addon = start()
    c.setBankOpen(true); c.setBankOpen(false)
    local made, kept = addon.bankList.shows(), addon.bankList.last()
    word(c, "goal add " .. LINEN .. " 8")
    t.eq(addon.bankList.shows() - made, 0, "no listing with the bank closed")
    t.ok(addon.bankList.last() == kept, "the last listing is still the visit")
    t.eq(shown(c), nil, "no panel shown")
    c.setBankOpen(true)
    t.eq(addon.bankList.shows() - made, 1, "the next visit lists once")
    t.ok(has(shown(c), KEPT12) and has(shown(c), "8 x Linen Cloth"), "the next visit holds 8: " .. joined(shown(c)))
    c.setBankOpen(false)
end

tests["goal mid bank visit: a goal word that changes nothing does not list again"] = function(t)
    local c, addon = start()
    c.setBankOpen(true)
    local made = addon.bankList.shows()
    word(c, "goal list")
    word(c, "goal remove " .. LINEN)
    word(c, "goal add")
    t.eq(addon.bankList.shows() - made, 0, "no change: no listing")
    t.ok(has(shown(c), KEPT20), "still all 20: " .. joined(shown(c)))
    c.setBankOpen(false)
end

-- Lead section 223 (BR-1, MyBuddy): the bank list started again while the
-- bank window stays open (an interface load at the bank). The start reads
-- whether the bank is open; it does not take a fresh closed. Here the add-on
-- is loaded on a client whose bank is already open, with no bank event
-- after the load.
local function startAt(open)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setItemInfo(INFO)
    c.setBagItems(BAG)
    c.setBankOpen(open)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

tests["goal mid bank visit: started with the bank already open, a goal change lists once"] = function(t)
    local c, addon = startAt(true)
    t.eq(c.bankOpen(), true, "the bank is open at the start")
    local made = addon.bankList.shows()
    word(c, "goal add " .. LINEN .. " 8")
    t.eq(addon.bankList.shows() - made, 1, "the goal change lists once")
    local lines = shown(c)
    t.ok(has(lines, KEPT12) and has(lines, "8 x Linen Cloth"), "twelve to bank, eight held: " .. joined(lines))
    word(c, "goal remove " .. LINEN)
    t.eq(addon.bankList.shows() - made, 2, "the removal lists once")
    t.ok(has(shown(c), KEPT20), "goal gone: all 20 again: " .. joined(shown(c)))
    c.setBankOpen(false)
    word(c, "goal add " .. LINEN .. " 8")
    t.eq(addon.bankList.shows() - made, 2, "the bank closed: a goal change draws nothing")
    t.eq(shown(c), nil, "no panel shown")
end

-- Started with the bank closed, or not known to be open: a goal change
-- draws nothing. Not known stays not known; it is never read as open.
tests["goal mid bank visit: started with the bank closed or not known, a goal change draws nothing"] = function(t)
    for _, open in ipairs({ false, "not known" }) do
        local c, addon = startAt(open == true)
        if open == "not known" then c.setBankOpen(nil) end
        local made, kept = addon.bankList.shows(), addon.bankList.last()
        word(c, "goal add " .. LINEN .. " 8")
        t.eq(addon.bankList.shows() - made, 0, "no listing: " .. tostring(open))
        t.ok(addon.bankList.last() == kept, "the last listing is unchanged: " .. tostring(open))
        t.eq(shown(c), nil, "no panel shown: " .. tostring(open))
    end
end

return tests
