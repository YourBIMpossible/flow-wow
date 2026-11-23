local _, ns = ...
-- Lead section 220, MyBuddy SR-1, SR-2, SR-5: the loot note and the
-- auctions list follow the reservations as the sell list does. A goal that
-- holds an item keeps it out of sell advice; reservations that cannot be
-- worked out give no sell advice on any path. The whole add-on on a fake
-- client (ns.offline.addon); made-up realm, prices and goals. Look only:
-- nothing loots, sells, posts or clicks. Not tested in game.
local tests = {}

local PELT = 4865
local INFO = { [PELT] = { name = "Ruined Pelt", quality = 0, sellPrice = 5, classID = 15 } }
local BAG = { { item = PELT, count = 15 }, { item = PELT, count = 5 } }   -- 20 pelts
local REALM, FACTION, NOW = "Realm1", "Horde", 1700000000

-- goals: settings.goals for the character (nil: none saved). bagsUnread:
-- the bag read answers nil. priced: the player's own search saw the pelt
-- at 5000 copper on this realm. source: a reservation source registered
-- as "test" before login (a function of the snapshot, as Reservations.Source).
local function start(goals, bagsUnread, priced, source)
    local c = ns.make.fakeClient()
    local account = {}
    if priced then
        account.learned = { prices = { auctionHistory = {
            [REALM .. "-" .. FACTION] = { [PELT] = { h = { NOW - 60, 5000 } } } } } }
    end
    c.setSaved(ns.id.accountDB, account)
    c.setSaved(ns.id.charDB, goals ~= nil and { settings = { goals = goals } } or {})
    c.setItemInfo(INFO)
    c.setRealm(REALM); c.setFaction(FACTION); c.setClock(NOW)
    if not bagsUnread then c.setBagItems(BAG) end
    -- "you:<item>:<count>" is the player's own loot line.
    c.setOwnLoot(function(text)
        local item, count = tostring(text):match("^you:(item:%d+):(%d+)$")
        if not item then return nil end
        return item, tonumber(count)
    end)
    local addon = ns.offline.addon(c)
    if source then addon.Reservations.Source("test", source) end
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function printedSince(c, from)
    local out = {}
    for i = from + 1, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return out
end

local function finds(lines, text)
    for _, l in ipairs(lines or {}) do
        if l:find(text, 1, true) then return true end
    end
    return false
end

local function loot(c)
    local from = #c.printed
    c.fire(ns.LootNote.EVENT, "you:item:" .. PELT .. ":2")
    return printedSince(c, from)
end

local function auctions(c)
    local from = #c.printed
    c.slashes[ns.id.slash]("auctions")
    return printedSince(c, from)
end

-- SR-1 ------------------------------------------------------------------------

tests["loot reservations SR-1: with no goal the looted junk is noted"] = function(t)
    local c = start(nil)
    local said = loot(c)
    t.ok(finds(said, "Ruined Pelt"), "the note, so the tests below can fail: " .. table.concat(said, " / "))
end

tests["loot reservations SR-1: a goal holding the looted item gives no sell note"] = function(t)
    local c = start({ { item = PELT, count = 20 } })
    local said = loot(c)
    t.ok(not finds(said, "Ruined Pelt"), "held for a goal: not called junk to sell: " .. table.concat(said, " / "))
end

tests["loot reservations SR-1: reservations unavailable (bags unread, goal saved) gives no note"] = function(t)
    local c, addon = start({ { item = PELT, count = 8 } }, true)
    t.eq(addon.reservations.Current().status, addon.Reservations.UNAVAILABLE)
    local said = loot(c)
    t.ok(not finds(said, "Ruined Pelt"), "unavailable: no sell advice: " .. table.concat(said, " / "))
end

tests["loot reservations SR-1: FromClient takes the evaluation; unavailable or none given is no note"] = function(t)
    local client = {
        ownLoot = function() return "item:" .. PELT, 2 end,
        itemInfo = function() return INFO[PELT] end,
    }
    local N, R = ns.LootNote, ns.Reservations
    t.ok(N.FromClient(client, nil, "x", { status = R.NONE }) ~= nil, "nothing reserved: noted")
    t.eq(N.FromClient(client, nil, "x", { status = R.UNAVAILABLE }), nil, "unavailable: no note")
    t.eq(N.FromClient(client, nil, "x", nil), nil, "no evaluation given: as unavailable")
    t.eq(N.FromClient(client, nil, "x", "odd"), nil, "not an evaluation: as unavailable")
end

-- SR-2 ------------------------------------------------------------------------

tests["loot reservations SR-2: the auctions list offers a priced pelt with no goal"] = function(t)
    local c = start(nil, false, true)
    local said = auctions(c)
    t.ok(finds(said, "Ruined Pelt"), "offered, so the tests below can fail: " .. table.concat(said, " / "))
end

tests["loot reservations SR-2: a pelt held for a goal is not offered for the auction house"] = function(t)
    local c = start({ { item = PELT, count = 20 } }, false, true)
    local said = auctions(c)
    t.ok(not finds(said, "Ruined Pelt"), "held: not offered: " .. table.concat(said, " / "))
end

tests["loot reservations SR-2: reservations unavailable: the auctions list offers nothing and says why"] = function(t)
    local c = start({ { item = PELT, count = 8 } }, true, true)
    local said = auctions(c)
    t.ok(not finds(said, "Ruined Pelt"), "nothing offered: " .. table.concat(said, " / "))
    t.ok(finds(said, ns.Posting.RESERVATIONS_UNKNOWN), "the reason: " .. table.concat(said, " / "))
end

-- Section 225 (ZLR-1): the test above can't fail on the offer, since with
-- the bags unread there is no pelt to offer anyway. Here the bags are read
-- and priced, so the pelt would be offered; only the reservations are
-- unavailable, forced by a source that raises. Fails if the auctions list
-- offers while the reservations are unavailable.
tests["loot reservations SR-2: bags read, reservations unavailable (a source raises): nothing offered"] = function(t)
    local c, addon = start(nil, false, true, function() error("made-up boom") end)
    t.eq(addon.reservations.Current().status, addon.Reservations.UNAVAILABLE, "the source raised")
    local said = auctions(c)
    t.ok(not finds(said, "Ruined Pelt"), "nothing offered: " .. table.concat(said, " / "))
    t.ok(finds(said, ns.Posting.RESERVATIONS_UNKNOWN), "the reason: " .. table.concat(said, " / "))
    t.ok(not finds(loot(c), "Ruined Pelt"), "and no loot note")
end

-- LR-1 ------------------------------------------------------------------------

-- Section 225 (LR-1). Fails before the repair: the reservations were worked
-- out for every loot line, another player's and a throttled repeat too.
tests["loot reservations LR-1: only a loot line that can be noted works out the reservations"] = function(t)
    local calls = 0
    local c = start(nil, false, false, function() calls = calls + 1; return {} end)
    local from = calls
    c.fire(ns.LootNote.EVENT, "someone:item:" .. PELT .. ":2")
    t.eq(calls - from, 0, "another player's loot: no evaluation")
    t.ok(finds(loot(c), "Ruined Pelt"), "your own loot is noted")
    t.eq(calls - from, 1, "one evaluation for it")
    t.eq(loot(c), {}, "the same item again at once: kept quiet")
    t.eq(calls - from, 1, "kept quiet: no evaluation")
    c.advance(ns.LootNote.REPEAT_S + 1)
    t.ok(finds(loot(c), "Ruined Pelt"), "after REPEAT_S it is noted again")
    t.eq(calls - from, 2, "and worked out again")
end

-- SR-5 ------------------------------------------------------------------------

tests["loot reservations SR-5: SellList.Current is unavailable when the module raises or answers no table"] = function(t)
    local S, R = ns.SellList, ns.Reservations
    local function use(mod) return function() return mod end end
    t.eq(S.Current(use({ Current = function() error("made-up boom") end })).status, R.UNAVAILABLE, "Current raises")
    t.eq(S.Current(use({ Current = function() return "odd" end })).status, R.UNAVAILABLE, "Current answers no table")
    t.eq(S.Current(use(nil)).status, R.UNAVAILABLE, "no module")
    t.eq(S.Current(function() error("made-up boom") end).status, R.UNAVAILABLE, "use itself raises")
    t.eq(S.Current(use({ Current = function() return { status = R.NONE } end })).status, R.NONE, "an answer is kept")
end

return tests
