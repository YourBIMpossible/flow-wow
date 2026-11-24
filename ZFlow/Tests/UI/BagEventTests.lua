-- The bag-change event (F5 item 3): the sell list and the bank prompt
-- follow the bags without a window being closed and opened again. Fake
-- client; the event name is a first guess, not tested in game.
local _, ns = ...

local S, B = ns.SellList, ns.BankList

local INFO = {
    [97] = { name = "Broken Fang", quality = 0, sellPrice = 4 },
    [6948] = { name = "Hearthstone", quality = 1, sellPrice = 0 },
    [2318] = { name = "Light Leather", quality = 1, sellPrice = 15, classID = 7 },
    [2589] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },
    [858] = { name = "Lesser Healing Potion", quality = 1, sellPrice = 20, classID = 0 },
}

local FANGS = "3 x Broken Fang: 4c each, 12c (the item's own sell price)"

local function has(lines, text)
    for _, l in ipairs(lines or {}) do
        if l == text then return true end
    end
    return false
end

-- declare(k): declares what the test is about; its answers come back after
-- the kernel and the client.
local function start(bag, declare)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setBagItems(bag)
    c.setItemInfo(INFO)
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    ns.Reservations.Declare(k)
    local api, extra = declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api, extra
end

local function sellList(k) return S.Declare(k) end

local function bankWithAdvisor(k)
    local advisor = ns.Advisor.Declare(k)
    return B.Declare(k), advisor
end

local function bankPrompt(advisor)
    for _, p in ipairs(advisor.List()) do
        if p.id == B.PROMPT_ID then return p end
    end
    return nil
end

return {
    ["bag event: both modules listen for the same event"] = function(t)
        t.eq(S.BAG_EVENT, "BAG_UPDATE_DELAYED")
        t.eq(B.BAG_EVENT, S.BAG_EVENT)
    end,

    ["bag event: the open sell list is made again from the bags"] = function(t)
        local k, c, api = start({ { item = 97, count = 3 }, { item = 6948, count = 1 } }, sellList)
        c.setMerchantOpen(true)
        t.eq(api.shows(), 1)
        t.ok(has(api.last(), FANGS), "the fangs are listed")
        c.setBagItems({ { item = 6948, count = 1 } })       -- the player sold the fangs
        c.fire(S.BAG_EVENT)
        t.eq(api.shows(), 2, "listed again")
        t.ok(not has(api.last(), FANGS), "the fangs are gone from the list")
        t.eq(k.problems:count(), 0)
    end,

    ["bag event: with no merchant window nothing is listed"] = function(t)
        local k, c, api = start({ { item = 97, count = 3 } }, sellList)
        c.fire(S.BAG_EVENT)
        t.eq(api.shows(), 0)
        for _, p in ipairs(c.panels) do t.ok(not p.shown, "no panel is shown") end
        t.eq(c.kitWindows().SellList.shown, false, "and the sell list's window is not shown")
        c.setMerchantOpen(true)
        c.setMerchantOpen(false)
        local before = api.shows()
        c.fire(S.BAG_EVENT)
        t.eq(api.shows(), before, "closed again: the event lists nothing")
        t.eq(k.problems:count(), 0)
    end,

    -- Raised only at the bank and naming the items now (sections 340/341).
    ["bag event: the bank prompt follows the bags at the bank, none away from it"] = function(t)
        local k, c, _, advisor = start({ { item = 2589, count = 20 }, { item = 2318, count = 4 } }, bankWithAdvisor)
        t.eq(bankPrompt(advisor), nil, "away from the bank: none")
        c.fire(B.BAG_EVENT)
        t.eq(bankPrompt(advisor), nil, "a bag change away from the bank: still none")
        c.setBankOpen(true)
        local p = bankPrompt(advisor)
        t.ok(p ~= nil, "registered at the bank")
        if not p then return end
        t.eq(p.text, "Put in your bank for later: Linen Cloth x20, Light Leather x4")
        c.setBagItems({ { item = 2318, count = 4 } })
        c.fire(B.BAG_EVENT)
        p = bankPrompt(advisor)
        t.eq(p and p.text, "Put in your bank for later: Light Leather x4")
        c.setBagItems({ { item = 858, count = 5 } })
        c.fire(B.BAG_EVENT)
        t.eq(bankPrompt(advisor), nil, "nothing left to bank: the prompt is gone")
        t.eq(k.problems:count(), 0)
    end,

    ["bag event: the bank list is not shown or listed by a bag change"] = function(t)
        local _, c, api = start({ { item = 2589, count = 20 } }, bankWithAdvisor)
        -- Panels other features show at login (the first-run intro) are not
        -- the bag event's: only a panel the bag change itself shows counts.
        local before = {}
        for i, p in ipairs(c.panels) do before[i] = p.shown end
        c.fire(B.BAG_EVENT)
        t.eq(api.shows(), 0)
        for i, p in ipairs(c.panels) do
            t.ok(not p.shown or before[i], "no panel is shown by the bag change")
        end
        t.eq(c.kitWindows().BankList.shown, false, "and the bank list's window is not shown")
    end,
}
