local _, ns = ...
-- Lead section 209 (item 1). Sell reservations end to end, on the whole
-- add-on loaded on a fake client: a test-only Reservations source -> one
-- evaluation per merchant visit -> what is held in the bags -> the sell
-- list the player is shown. The goals producer is not used (section 210):
-- the source here is the test's own.
-- Offline: the reads are the fake client's, not the game's. Not tested in game.
local tests = {}
-- Item names carry the game's quality colour (Items/Present.lua, Tint; the
-- colour itself is tested in Tests/Items/ItemColourTests.lua). These tests are
-- about the words, so they read them with the colour taken off.
local plain = ns.ItemPresent.Plain

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
-- no source at all), bag (stacks), char (the character's saved data), env
-- (the fake client's raw names), prepare (fn(c), run before the add-on is
-- built on c)
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient({ env = opts.env })
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, opts.char or {})
    c.setItemInfo(INFO)
    c.setBagItems(opts.bag or { { item = PELT, count = 3 }, { item = POTION, count = 2 } })
    if opts.prepare then opts.prepare(c) end
    local addon = ns.offline.addon(c)
    c.lists = { SellList = addon.sellList, BankList = addon.bankList }
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
        if plain(l) == text then return true end
    end
    return false
end

local function starts(lines, prefix)
    for _, l in ipairs(lines or {}) do
        if plain(l):sub(1, #prefix) == prefix then return true end
    end
    return false
end

local function finds(lines, text)
    for _, l in ipairs(lines or {}) do
        if plain(l):find(text, 1, true) then return true end
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

-- SR-6 (lead section 220): look only, with every acting call in place
-- BEFORE the add-on is built on the client, so a call from any product path
-- (start, login, the visit, the button, the bag event, the goal word) is
-- counted. Two ways an add-on on this client could act:
--   * the client's raw call into the game's names (c.raw over the fake's
--     env): each acting game function is put in the env and counts its calls;
--   * a client function: none acts today. One named for each act is put on
--     the client and counts its calls; so does every function already on the
--     client whose name holds an acting word (MyBuddy ST-8: one ClientFake
--     gains later is counted too); and any other name the add-on looks up on
--     the client that names an act is noted (a lookup hook on the client).
local ACTING_GAME = { "UseContainerItem", "PickupContainerItem", "SplitContainerItem", "SellCursorItem",
    "ShowMerchantSellCursor", "BuyMerchantItem", "BuybackItem", "PickupMerchantItem", "RepairAllItems",
    "DeleteCursorItem", "PickupItem", "UseItemByName", "EquipItemByName", "PlaceAuctionBid", "PostAuction",
    "StartAuction" }
local ACTING_CLIENT = { "useContainerItem", "pickupContainerItem", "splitContainerItem", "sellCursorItem",
    "sellItem", "sell", "buy", "buyMerchantItem", "pickupMerchantItem", "repairAll", "deleteCursorItem",
    "useItem", "postAuction", "placeBid", "deposit", "withdraw" }
local ACTING_WORDS = { "sell", "buy", "pickup", "usecontainer", "useitem", "split", "delete", "deposit",
    "withdraw", "bid", "postauction", "repairall", "cursor" }

-- Whether a name holds one of the acting words, in any case.
local function acting(name)
    local low = name:lower()
    for _, word in ipairs(ACTING_WORDS) do
        if low:find(word, 1, true) then return true end
    end
    return false
end

tests["sell reservations: look only - no acting call from any path, stubbed before the add-on is built"] = function(t)
    local called, looked = {}, {}
    local function record(name) return function() called[#called + 1] = name end end
    local env = {
        C_Container = { UseContainerItem = record("C_Container.UseContainerItem"),
                        PickupContainerItem = record("C_Container.PickupContainerItem"),
                        SplitContainerItem = record("C_Container.SplitContainerItem") },
        C_MerchantFrame = { SellAllJunkItems = record("C_MerchantFrame.SellAllJunkItems"),
                            BuyItem = record("C_MerchantFrame.BuyItem") },
    }
    for _, name in ipairs(ACTING_GAME) do env[name] = record(name) end
    local function prepare(c)
        -- MyBuddy ST-8: a client function that names an act but is not in
        -- ACTING_CLIENT (as if ClientFake gained one later). It must be
        -- counted too; the check after the run calls it to prove that.
        c.zzSellAllJunk = function() end
        for _, name in ipairs(ACTING_CLIENT) do c[name] = record("client." .. name) end
        -- Every function already on the client whose name holds an acting
        -- word is counted as well, whatever list it is in (ST-8). Only keys
        -- already there are set inside the walk, which Lua allows.
        for name, value in pairs(c) do
            if type(name) == "string" and type(value) == "function" and acting(name) then
                c[name] = record("client." .. name)
            end
        end
        setmetatable(c, { __index = function(_, name)
            if type(name) == "string" and acting(name) then looked[#looked + 1] = name end
            return nil
        end })
    end
    -- A goal saved for the character (the real goals producer, no test
    -- source): 2 of the 3 pelts held, so a sell list with an offer is shown.
    local c, addon = start({ source = false, env = env, prepare = prepare,
        char = { settings = { goals = { { item = PELT, count = 2 } } } } })
    c.setMerchantOpen(true)
    local lines = addon.sellList.last()
    t.ok(starts(lines, "1 x Ruined Pelt: "), "the visit listed an offer: " .. joined(lines))
    t.ok(has(lines, "Ruined Pelt: 2 held for your steps"), "the goal held two: " .. joined(lines))
    t.ok(addon.sellList.show(), "shown on ask")
    c.fire("BAG_UPDATE_DELAYED"); c.advance(1, 5)
    c.slashes[ns.id.slash]("goal add " .. PELT .. " 3")
    t.ok(has(addon.sellList.last(), "Ruined Pelt: 3 held for your steps"),
        "the goal word relisted the visit: " .. joined(addon.sellList.last()))
    c.advance(1, 5)
    c.setMerchantOpen(false)
    t.eq(called, {}, "no acting call")
    t.eq(looked, {}, "no acting name looked up on the client")
    -- ST-8: the client function that names an act and is in no list is
    -- counted when called, so a later one on ClientFake cannot act unseen.
    c.zzSellAllJunk()
    t.eq(called, { "client.zzSellAllJunk" }, "an acting-named client function outside the list is counted")
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
    -- MyBuddy SR2-1: at the merchant the same two calls do list again, so
    -- that they list nothing away from it (below) is the away guard, not a
    -- refresh or bag event that does nothing at all.
    local atVisit = addon.sellList.shows()
    addon.sellList.refresh()
    t.eq(addon.sellList.shows() - atVisit, 1, "refresh at the merchant lists again")
    c.fire("BAG_UPDATE_DELAYED"); c.advance(1, 5)
    t.eq(addon.sellList.shows() - atVisit, 2, "a bag event at the merchant lists again")
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

for name, fn in pairs(tests) do
    tests[name] = function(t)
        return fn(setmetatable({ eq = function(got, want, msg) return t.eq(plain(got), plain(want), msg) end },
            { __index = t }))
    end
end

return tests
