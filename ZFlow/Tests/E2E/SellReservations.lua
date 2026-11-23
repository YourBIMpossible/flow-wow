local _, ns = ...
-- Lead section 209 (item 1). Sell reservations end to end, on the whole
-- add-on loaded on a fake client: a test-only Reservations source -> one
-- evaluation per merchant visit -> what is held in the bags -> the sell
-- list the player is shown. The goals producer is not used (section 210):
-- the source here is the test's own.
-- Offline: the reads are the fake client's, not the game's. Not tested in game.
local tests = {}

local PELT, POTION, BOLT = 4865, 858, 2996
local INFO = {
    [PELT] = { name = "Ruined Pelt", quality = 0, sellPrice = 5, classID = 15 },
    [POTION] = { name = "Lesser Healing Potion", quality = 1, sellPrice = 20, classID = 0 },
}

-- holds: { [itemID] = count }, read each time the source is asked, so a
-- test can change them; calls.n counts how often the source was asked.
-- The claims are ItemPlan's, as in Tests/E2E/BankReservations.lua.
local function holdSource(addon, holds, calls)
    return function(snapshot)
        calls.n = calls.n + 1
        local claims = {}
        for item, count in pairs(holds) do
            local key = addon.Items.Key(item)
            local owner = "goal:test" .. tostring(item)
            local recipes = { ["make:" .. owner] = { makes = BOLT, yield = 1, mats = { [key] = 1 } } }
            local plan = addon.ItemPlan.Build({ recipe = "make:" .. owner, count = count },
                { recipes = recipes, snapshot = snapshot })
            for _, c in ipairs(addon.ItemPlan.Claims(plan, owner, "test")) do
                c.selected = true
                claims[#claims + 1] = c
            end
        end
        return claims
    end
end

-- opts: holds ({ [item] = n }), source (a function instead of holds; false:
-- no source at all), bag (stacks)
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setItemInfo(INFO)
    c.setBagItems(opts.bag or { { item = PELT, count = 3 }, { item = POTION, count = 2 } })
    local addon = ns.offline.addon(c)
    local holds, calls = opts.holds or {}, { n = 0 }
    if opts.source then
        addon.Reservations.Source("test", opts.source)
    elseif opts.source ~= false then
        addon.Reservations.Source("test", holdSource(addon, holds, calls))
    end
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon, holds, calls
end

local function panelOf(c)
    for _, p in ipairs(c.panels) do
        if type(p.spec) == "table" and p.spec.name == ns.id.framePrefix .. "SellList" then return p end
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

local function starts(lines, prefix)
    for _, l in ipairs(lines or {}) do
        if l:sub(1, #prefix) == prefix then return true end
    end
    return false
end

local function finds(lines, text)
    for _, l in ipairs(lines or {}) do
        if l:find(text, 1, true) then return true end
    end
    return false
end

-- The sell panel's lines at a merchant visit.
local function visit(c)
    c.setMerchantOpen(true)
    local p = panelOf(c)
    local lines = p and p.lines or nil
    c.setMerchantOpen(false)
    return lines
end

tests["sell reservations: the held part is kept, only the free part is offered for sale"] = function(t)
    local c = start({ holds = { [PELT] = 2 } })
    local lines = visit(c)
    t.ok(starts(lines, "1 x Ruined Pelt: "), "one of three to sell: " .. joined(lines))
    t.ok(not starts(lines, "3 x Ruined Pelt: "), "not all three: " .. joined(lines))
    t.ok(has(lines, "Ruined Pelt: 2 held for your steps"), "two kept, with why: " .. joined(lines))
end

tests["sell reservations: a hold on every pelt leaves none to sell"] = function(t)
    local c = start({ holds = { [PELT] = 5 } })
    local lines = visit(c)
    t.ok(not finds(lines, "x Ruined Pelt: "), "no pelt offered: " .. joined(lines))
    t.ok(has(lines, "Ruined Pelt: 3 held for your steps"), "never more than the bags hold: " .. joined(lines))
end

tests["sell reservations: no source is none, and the player sees no change"] = function(t)
    local c, addon = start({ source = false })
    t.eq(addon.Reservations.Evaluate(function() return {} end).status, addon.Reservations.NONE,
        "no source: none")
    local lines = visit(c)
    t.ok(starts(lines, "3 x Ruined Pelt: "), "all three offered, as before: " .. joined(lines))
    t.ok(not finds(lines, "held for your steps"), "nothing held: " .. joined(lines))
    t.ok(not finds(lines, "eservations not known"), "no unknown line: " .. joined(lines))
end

tests["sell reservations: a source that offers nothing changes nothing"] = function(t)
    local c = start({ holds = {} })
    local lines = visit(c)
    t.ok(starts(lines, "3 x Ruined Pelt: "), joined(lines))
    t.ok(not finds(lines, "eservations not known"), joined(lines))
end

tests["sell reservations: unavailable gives no sell advice and says reservations are not known"] = function(t)
    local c, addon = start({ source = function() error("goals could not be read") end })
    local lines = visit(c)
    t.ok(lines ~= nil, "the panel was drawn")
    t.ok(has(lines, addon.SellList.RESERVATIONS_UNKNOWN), "says it: " .. joined(lines))
    t.ok(type(addon.SellList.RESERVATIONS_UNKNOWN) == "string"
        and addon.SellList.RESERVATIONS_UNKNOWN:find("eservations not known", 1, true) ~= nil,
        "the words: " .. tostring(addon.SellList.RESERVATIONS_UNKNOWN))
    t.ok(not finds(lines, " x Ruined Pelt: "), "no pelt offered: " .. joined(lines))
    t.ok(not finds(lines, " x Lesser Healing Potion: "), "nothing offered: " .. joined(lines))
    t.ok(not has(lines, ns.ItemPresent.SELL_HEADER), "no sell header: " .. joined(lines))
    t.ok(not has(lines, ns.ItemPresent.NOTHING_TO_SELL), "not told there is nothing to sell either: " .. joined(lines))
end

tests["sell reservations: one evaluation per merchant visit"] = function(t)
    local c, addon, holds, calls = start({ holds = { [PELT] = 2 } })
    local before = calls.n
    c.setMerchantOpen(true)
    t.eq(calls.n - before, 1, "the visit evaluates once")
    -- Asked again in the same visit (the merchant window button): the same
    -- evaluation, not a new one.
    local mid = calls.n
    holds[PELT] = 3
    local ok = addon.sellList.show()
    t.ok(ok, "shown on ask")
    t.eq(calls.n - mid, 0, "no second evaluation in the same visit")
    t.ok(starts(addon.sellList.last(), "1 x Ruined Pelt: "), "the visit's own hold: " .. joined(addon.sellList.last()))
    c.setMerchantOpen(false)
    -- A new visit: a new evaluation, which sees the changed hold.
    local again = calls.n
    c.setMerchantOpen(true)
    t.eq(calls.n - again, 1, "a new visit evaluates once")
    t.ok(not finds(addon.sellList.last(), "x Ruined Pelt: "), "all three held now: " .. joined(addon.sellList.last()))
    c.setMerchantOpen(false)
end

tests["sell reservations: look only - no acting client call"] = function(t)
    local c, addon = start({ holds = { [PELT] = 2 } })
    local acting = { "useContainerItem", "pickupContainerItem", "sell", "buy", "postAuction", "placeBid",
                     "deposit", "withdraw", "splitContainerItem", "deleteCursorItem" }
    local called = {}
    for _, name in ipairs(acting) do
        if type(c[name]) == "function" then
            c[name] = function() called[#called + 1] = name end
        end
    end
    c.setMerchantOpen(true)
    addon.sellList.show()
    c.fire("BAG_UPDATE_DELAYED"); c.advance(1, 5)
    c.setMerchantOpen(false)
    t.eq(called, {}, "no acting call")
end

-- Lead section 213: a list asked for away from a merchant is never made, so
-- it can never show an old held count. Away from a merchant the sell list
-- makes no listing and keeps none; the next visit evaluates once and shows
-- the changed hold. (The bank prompt asks the source on a bag event away
-- from the bank; that is its own evaluation, not the sell list's, so the
-- count of source calls is taken only across the visit.)
tests["sell reservations: away from a merchant nothing is listed; the next visit sees the new hold"] = function(t)
    local c, addon, holds, calls = start({ holds = { [PELT] = 2 } })
    c.setMerchantOpen(true)
    t.ok(starts(addon.sellList.last(), "1 x Ruined Pelt: "), "the first visit: " .. joined(addon.sellList.last()))
    c.setMerchantOpen(false)
    local made, kept = addon.sellList.shows(), addon.sellList.last()
    holds[PELT] = 3
    local ok, why = addon.sellList.show()
    t.eq(ok, false, "asked away from a merchant: no list")
    t.eq(why, addon.SellList.NO_MERCHANT, "and why")
    addon.sellList.refresh()
    c.fire("BAG_UPDATE_DELAYED"); c.advance(1, 5)
    t.eq(addon.sellList.shows() - made, 0, "no listing made away from a merchant")
    t.ok(addon.sellList.last() == kept, "the last listing is still the first visit")
    local before = calls.n
    c.setMerchantOpen(true)
    t.eq(calls.n - before, 1, "the next visit evaluates once")
    t.eq(addon.sellList.shows() - made, 1, "and lists once")
    t.ok(not finds(addon.sellList.last(), "x Ruined Pelt: "), "the new hold, no pelt offered: " .. joined(addon.sellList.last()))
    t.ok(has(addon.sellList.last(), "Ruined Pelt: 3 held for your steps"), "three held now: " .. joined(addon.sellList.last()))
    c.setMerchantOpen(false)
end

return tests
