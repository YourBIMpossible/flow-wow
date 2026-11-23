-- S4 review items PA6, PA8 and PA10 (lead section 178; definitions in
-- WoW/from-plexy/RESEARCH-price-chart.md, the PA table). Fake client only.
-- Not tested in game.
--   PA6  no look is recorded while the faction is not known
--   PA8  one writer: the price lookup reads the auction history, and the
--        price book gets no second copy
--   PA10 the realm table is read once a session and never copied a look
local _, ns = ...

local AL, L = ns.AuctionLog, ns.PriceLookup
local tests = {}
local REALM = "Old Blanchy-Horde"
local INFO = { [2589] = { name = "Linen Cloth", quality = 1, sellPrice = 13 } }
local VENDOR_LINE = "Linen Cloth: a vendor pays 13c each (the item's own sell price)"

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.saved or {})
    c.setSaved(ns.id.charDB, {})
    c.setRealm("Old Blanchy")
    if not opts.noFaction then c.setFaction("Horde") end
    c.setClock(1000)
    c.setItemInfo(INFO)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    local api = AL.Declare(k, d)
    L.Start(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api
end

local function texts(lines)
    local out = {}
    for i, l in ipairs(lines) do out[i] = l.text end
    return out
end

local function history(rk, entries)
    return { learned = { prices = { auctionHistory = { [rk] = entries } } } }
end

-- ------------------------------------------------------------------ PA6

tests["PA6: no look is recorded while the faction is not known"] = function(t)
    local k, c, api = start({ noFaction = true })
    c.auctionResult(2589, { unitPrice = 12 })
    t.eq(api.looks(), 0)
    t.eq(k.store:get("account", AL.PATH), nil, "no realm-? bucket is made")
    t.eq(texts(c.showItemTooltip("item:2589")), {})
    c.setFaction("Horde")
    c.auctionResult(2589, { unitPrice = 12 })
    t.eq(api.looks(), 1)
    t.eq(k.store:get("account", AL.PATH), { [REALM] = { [2589] = { h = { 1000, 12 } } } },
        "once the faction is read, the look goes under the real key")
end

tests["PA6: a faction the client gives as an empty text is not known either"] = function(t)
    local k, c, api = start({ noFaction = true })
    c.setFaction("")
    c.auctionResult(2589, { unitPrice = 12 })
    t.eq(api.looks(), 0)
    t.eq(k.store:get("account", AL.PATH), nil)
end

tests["PA6: an old realm-? bucket is left as it was, not merged"] = function(t)
    local k, c = start({ saved = history("Old Blanchy-?", { [2589] = { h = { 500, 9 } } }) })
    c.auctionResult(2589, { unitPrice = 12 })
    t.eq(k.store:get("account", AL.PATH .. ".Old Blanchy-?"), { [2589] = { h = { 500, 9 } } })
    t.eq(k.store:get("account", AL.PATH .. "." .. REALM), { [2589] = { h = { 1000, 12 } } })
end

-- ------------------------------------------------------------------ PA8

tests["PA8: the price word says the auction price from your own searches"] = function(t)
    local k, c = start()
    c.auctionResult(2589, { unitPrice = 12 })
    c.setClock(1000 + 3 * 86400)
    c.auctionResult(2589, { unitPrice = 15 })
    c.setClock(1000 + 3 * 86400 + 120)
    t.eq(L.Run(k, "2589"), {
        VENDOR_LINE,
        "Auction: 15c each, 2 min ago",
        "Low 12c, high 15c, average 14c: 2 looks over 3 days, up 25%",
    })
end

tests["PA8: no look, or a faction not known, adds no auction line"] = function(t)
    local k = start()
    t.eq(L.Run(k, "2589"), { VENDOR_LINE })
    local k2 = start({ saved = history(REALM, { [2589] = { h = { 1000, 12 } } }), noFaction = true })
    t.eq(L.Run(k2, "2589"), { VENDOR_LINE })
end

tests["PA8: one writer: a look writes no auction price in the price book"] = function(t)
    local k, c = start()
    c.auctionResult(2589, { unitPrice = 12 })
    local book = k.store:get("account", "learned.prices")
    local keys = {}
    for key in pairs(book) do keys[#keys + 1] = key end
    t.eq(keys, { "auctionHistory" })
    t.eq(ns.Prices.Get(book, 2589, "auction").value, nil)
end

tests["PA8: the lookup reads the history and writes nothing"] = function(t)
    local k, c = start({ saved = history(REALM, { [2589] = { h = { 1000, 12 } } }) })
    t.eq(L.Run(k, "2589")[2], "Auction: 12c each, 0 min ago")
    t.eq(c.saved(ns.id.accountDB).learned.prices, { auctionHistory = { [REALM] = { [2589] = { h = { 1000, 12 } } } } })
end

-- ------------------------------------------------------------------ PA10

-- Counts the store reads of the realm table, and every table written to it.
local function measure(k)
    local path = AL.PATH .. "." .. REALM
    local m = { reads = 0, writes = 0, tables = {} }
    local get, set = k.store.get, k.store.set
    k.store.get = function(self, scope, p)
        if p == path then m.reads = m.reads + 1 end
        return get(self, scope, p)
    end
    k.store.set = function(self, scope, p, v)
        if p == path then
            m.writes = m.writes + 1
            m.tables[v] = true
        end
        return set(self, scope, p, v)
    end
    function m.distinct()
        local n = 0
        for _ in pairs(m.tables) do n = n + 1 end
        return n
    end
    return m
end

tests["PA10: 500 items: the realm table is read once and never copied"] = function(t)
    local k, c, api = start()
    local m = measure(k)
    for id = 1, 500 do c.auctionResult(id, { unitPrice = id }) end
    for id = 1, 500 do c.showItemTooltip("item:" .. id) end
    t.eq(api.looks(), 500)
    t.ok(m.reads <= 1, "realm table reads: " .. m.reads)
    t.eq(m.distinct(), 1, "one realm table for all 500 looks, no copy a look")
    local saved = k.store:get("account", AL.PATH .. "." .. REALM)
    local n = 0
    for _ in pairs(saved) do n = n + 1 end
    t.eq(n, 500)
    t.eq(saved[250], { h = { 1000, 250 } })
    t.eq(texts(c.showItemTooltip("item:500")), { "Auction: 5s each, 0 min ago" })
end

tests["PA10: a look saves only its own item; the others are the same tables"] = function(t)
    local k, c = start({ saved = history(REALM, { [7] = { h = { 500, 5 } } }) })
    local seven = k.store:get("account", AL.PATH .. "." .. REALM)[7]
    c.auctionResult(2589, { unitPrice = 12 })
    local after = k.store:get("account", AL.PATH .. "." .. REALM)
    t.ok(after[7] == seven, "item 7 is not rewritten")
    t.eq(after[2589], { h = { 1000, 12 } })
end

tests["PA10: a refused save leaves what was saved as it was"] = function(t)
    local k, c, api = start({ saved = history(REALM, { [7] = { h = { 500, 5 } } }) })
    c.showItemTooltip("item:7")
    k.store.blocked.account = "blocked for the test"
    c.auctionResult(7, { unitPrice = 3 })
    c.auctionResult(2589, { unitPrice = 12 })
    t.eq(api.looks(), 0)
    t.eq(c.saved(ns.id.accountDB).learned.prices.auctionHistory[REALM], { [7] = { h = { 500, 5 } } })
    t.eq(texts(c.showItemTooltip("item:7")), { "Auction: 5c each, 8 min ago" })
end

tests["PA10: the cached table follows a new realm table written in the session"] = function(t)
    local k, c = start()
    c.auctionResult(2589, { unitPrice = 12 })
    t.eq(texts(c.showItemTooltip("item:2589")), { "Auction: 12c each, 0 min ago" })
    t.eq(k.store:set("account", AL.PATH .. "." .. REALM, { [7] = { h = { 1000, 5 } } }), true)
    t.eq(texts(c.showItemTooltip("item:2589")), {})
    t.eq(texts(c.showItemTooltip("item:7")), { "Auction: 5c each, 0 min ago" })
    c.auctionResult(2589, { unitPrice = 14 })
    t.eq(k.store:get("account", AL.PATH .. "." .. REALM), { [7] = { h = { 1000, 5 } }, [2589] = { h = { 1000, 14 } } })
end

return tests
