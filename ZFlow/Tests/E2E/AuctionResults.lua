local _, ns = ...

-- End to end (lead sections 187, 189): the whole add-on (ns.offline.addon)
-- on a fake client, told the results of auction searches the player ran
-- (client.watchAuctionResults, PA2). What the player sees is the auction
-- word's line. Which row of a search counts (a hidden or raising count, a
-- hidden item key, equal prices) is Core/Client.lua's own reading: those
-- cases stay in Tests/Core/ClientAuctionTests.lua, since the fake client
-- stands in for that reading here. Made-up realm and items. Look only:
-- nothing searches, posts, bids or buys. Not tested in game.

local tests = {}

-- opts.faction: false for not known. opts.saved: the account table.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.saved or {})
    c.setScreen(1024, 768)
    c.setClock(1700000000)
    c.setRealm("Realm1")
    if opts.faction ~= false then c.setFaction("Horde") end
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function word(c)
    for i = #c.printed, 1, -1 do c.printed[i] = nil end
    c.slashes[ns.id.slash]("auction")
    return c.printed[#c.printed]
end

local function line(items, realm, searches)
    return ns.id.title .. ": " .. string.format("auction: prices for %d item(s) on %s, from %d search(es) this session.",
        items, realm, searches)
end

tests["auction e2e: a search result becomes a price the auction word counts"] = function(t)
    local c = start()
    t.eq(word(c), line(0, "Realm1-Horde", 0))
    c.auctionResult(2589, { unitPrice = 30, quantity = 5 })
    c.auctionResult(2592, { buyoutAmount = 500, quantity = 10 })
    t.eq(word(c), line(2, "Realm1-Horde", 2))
end

tests["auction e2e: a row with no price for one records nothing"] = function(t)
    local c = start()
    c.auctionResult(1, { unitPrice = "x" })
    c.auctionResult(2, { buyoutAmount = 50, quantity = 0 })
    c.auctionResult(3, { unitPrice = 0 })
    c.auctionResult("4", { unitPrice = 5 })
    t.eq(word(c), line(0, "Realm1-Horde", 0))
end

tests["auction e2e: with the faction not known nothing is recorded"] = function(t)
    local c = start({ faction = false })
    c.auctionResult(2589, { unitPrice = 30 })
    t.eq(word(c), line(0, "a realm not read", 0))
end

tests["auction e2e: the prices are still there after a reload"] = function(t)
    local c = start()
    c.auctionResult(2589, { unitPrice = 30 })
    local c2 = start({ saved = c.saved(ns.id.accountDB) })
    t.eq(word(c2), line(1, "Realm1-Horde", 0), "one item kept; no search this session")
end

return tests
