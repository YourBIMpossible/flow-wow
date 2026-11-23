-- S2 follow-up (lead section 179, from Plexy's S2 review): R4 (b), R1, R2
-- and R7. Fake client and a hand-built environment only; not tested in game.
--   R4 (b) a resell deal is judged on a commodity search only; a vendor deal
--          on both kinds of search
--   R1     the usual price is made from visits older than AuctionLog.SAME_LOOK
--   R2     the deal keeps when it was seen; its tooltip line says how long ago
--   R7     the fake client's auctionRows keeps a watcher's error to itself
local _, ns = ...

local T, AL = ns.Trader, ns.AuctionLog
local tests = {}
local coin = ns.Prices.Coin
local REALM = "Old Blanchy-Horde"
local INFO = {
    [2589] = { name = "Linen Cloth", quality = 1, sellPrice = 13, classID = 7 },
    [4306] = { name = "Silk Cloth", quality = 1, sellPrice = 150, classID = 7 },
}
local LINEN_ROWS = { { unit = 100, qty = 10 }, { unit = 200, qty = 10 }, { unit = 300, qty = 5 } }
local FOUR = { 1000, 400, 2000, 400, 3000, 400, 4000, 400 }

-- opts.log: AuctionLog is declared too; opts.h: the saved visits of 2589.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setRealm("Old Blanchy")
    c.setFaction("Horde")
    c.setClock(5000)
    c.setItemInfo(INFO)
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    if opts.log then AL.Declare(k, d) end
    local api = T.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    local h = {}
    for i, v in ipairs(opts.h or FOUR) do h[i] = v end
    k.store:set("account", AL.PATH .. "." .. REALM, { [2589] = { h = h } })
    return k, c, api
end

local function kinds(api)
    local out = {}
    for _, row in ipairs(api.deals()) do out[#out + 1] = row.id .. " " .. row.kind end
    return out
end

-- ------------------------------------------------------------------ R4

tests["R4: a resell deal needs a commodity search"] = function(t)
    local _, c, api = start()
    c.auctionRows(2589, LINEN_ROWS, "item")
    t.eq(kinds(api), {}, "an item search judges no resell deal")
    c.auctionRows(2589, LINEN_ROWS, "commodity")
    t.eq(kinds(api), { "2589 resell" })
end

tests["R4: a vendor deal is judged on both kinds of search"] = function(t)
    local _, c, api = start()
    c.auctionRows(4306, { { unit = 100, qty = 3 } }, "item")
    t.eq(kinds(api), { "4306 vendor" })
    c.auctionRows(4306, { { unit = 300, qty = 3 } }, "item")
    t.eq(kinds(api), {})
    c.auctionRows(4306, { { unit = 100, qty = 3 } }, "commodity")
    t.eq(kinds(api), { "4306 vendor" })
end

tests["R4: an item search takes a resell deal off the list"] = function(t)
    local _, c, api = start()
    c.auctionRows(2589, LINEN_ROWS, "commodity")
    t.eq(kinds(api), { "2589 resell" })
    c.auctionRows(2589, LINEN_ROWS, "item")
    t.eq(kinds(api), {}, "the list follows the last search")
end

tests["R4: a search of a kind not known judges no resell deal"] = function(t)
    local _, c, api = start()
    c.auctionRows(2589, LINEN_ROWS, "other")
    t.eq(kinds(api), {})
    c.auctionRows(4306, { { unit = 100, qty = 3 } }, "other")
    t.eq(kinds(api), { "4306 vendor" })
end

tests["R4: the real client says which kind of search it was"] = function(t)
    local env = { frames = {} }
    function env.CreateFrame()
        local f = { scripts = {}, events = {} }
        function f:SetScript(script, fn) self.scripts[script] = fn end
        function f:RegisterEvent(name) self.events[name] = true end
        function f:UnregisterEvent(name) self.events[name] = nil end
        env.frames[#env.frames + 1] = f
        return f
    end
    local function send(name, ...)
        for _, f in ipairs(env.frames) do
            if f.events[name] and f.scripts.OnEvent then f.scripts.OnEvent(f, name, ...) end
        end
    end
    local rows = { [2589] = { { unitPrice = 30, quantity = 1 } }, [7] = { { buyoutAmount = 90, quantity = 1 } } }
    local function list(what) return rows[type(what) == "table" and what.itemID or what] or {} end
    env.C_AuctionHouse = {
        GetCommoditySearchResultInfo = function(what, i) return list(what)[i] end,
        GetItemSearchResultInfo = function(what, i) return list(what)[i] end,
        GetNumCommoditySearchResults = function(what) return #list(what) end,
        GetNumItemSearchResults = function(what) return #list(what) end,
    }
    local c = ns.make.client(env)
    local got = {}
    t.eq(c.watchAuctionRows(function(id, _, kind) got[#got + 1] = id .. " " .. tostring(kind) end), true)
    send("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
    send("ITEM_SEARCH_RESULTS_UPDATED", { itemID = 7 })
    t.eq(got, { "2589 commodity", "7 item" })
end

tests["R4: the fake client plays a commodity search when no kind is given"] = function(t)
    local c = ns.make.fakeClient()
    local got = {}
    c.watchAuctionRows(function(id, _, kind) got[#got + 1] = id .. " " .. tostring(kind) end)
    c.auctionRows(7, {})
    c.auctionRows(8, {}, "item")
    t.eq(got, { "7 commodity", "8 item" })
end

-- ------------------------------------------------------------------ R1

tests["R1: the usual price is made from visits older than SAME_LOOK"] = function(t)
    local now = 5000
    local before = now - AL.SAME_LOOK
    t.eq({ T.Usual({ 1000, 400, 2000, 400, 3000, 400, 4999, 100 }, nil, before) }, { nil, 3 },
        "this visit is not one of the four")
    t.eq({ T.Usual({ 1000, 400, 2000, 400, 3000, 400, before, 400 }, nil, before) }, { 400, 4 },
        "a visit SAME_LOOK old counts")
    t.eq({ T.Usual({ 1000, 400, 2000, 400, 3000, 400, 4000, 400, 4999, 100 }, nil, before) }, { 400, 4 },
        "four older visits: the new low price is not in the middle")
    t.eq({ T.Usual({ 1, 100, 2, 200, 3, 300, 4, 400 }) }, { 250, 4 }, "no time given: every visit, as before")
end

tests["R1: three earlier visits and this one make no usual price"] = function(t)
    local _, c, api = start({ log = true, h = { 1000, 400, 2000, 400, 3000, 400 } })
    c.auctionResult(2589, { unitPrice = 100 })
    c.auctionRows(2589, LINEN_ROWS)
    t.eq(kinds(api), {}, "the deal price is not the fourth visit")
end

tests["R1: four earlier visits and this one: the deal is judged on the four"] = function(t)
    local _, c, api = start({ log = true })
    c.auctionResult(2589, { unitPrice = 100 })
    c.auctionRows(2589, LINEN_ROWS)
    t.eq(kinds(api), { "2589 resell" })
    t.eq(api.deals()[1].usual, 400)
end

-- ------------------------------------------------------------------ R2

tests["R2: the deal keeps when it was seen"] = function(t)
    local _, c, api = start()
    c.auctionRows(2589, LINEN_ROWS)
    t.eq(api.deals()[1].at, 5000)
    c.setClock(5300)
    c.auctionRows(2589, LINEN_ROWS)
    t.eq(api.deals()[1].at, 5300, "seen again: the later time")
end

tests["R2: the tooltip line says how long ago the deal was seen"] = function(t)
    local row = { kind = "resell", qty = 2, cost = 300, usual = 400, at = 1000 }
    t.eq({ T.TipLine(row, coin, 1000 + 120) },
        { "Deal: listed at 1s 50c each, usually 4s (seen 2 min ago)", 1, 0.82, 0 })
    local v = { kind = "vendor", qty = 1, cost = 100, limit = 150, at = 1000 }
    t.eq(T.TipLine(v, coin, 1000 + 3 * 3600), "Deal: listed at 1s each, under a vendor's 1s 50c (seen 3 h ago)")
    t.eq(T.TipLine(v, coin), "Deal: listed at 1s each, under a vendor's 1s 50c", "no time: no age")
    t.eq(T.TipLine(v, coin, 999), "Deal: listed at 1s each, under a vendor's 1s 50c", "a time before the deal: no age")
end

tests["R2: the item tooltip shows the age"] = function(t)
    local _, c = start()
    c.auctionRows(2589, LINEN_ROWS)
    c.setClock(5000 + 180)
    t.eq(c.showItemTooltip(2589),
        { { text = "Deal: listed at 1s 50c each, usually 4s (seen 3 min ago)", r = 1, g = 0.82, b = 0 } })
end

-- ------------------------------------------------------------------ R7

tests["R7: a fake row watcher that raises does not stop the others"] = function(t)
    local c = ns.make.fakeClient()
    local got = {}
    c.watchAuctionRows(function() error("watcher boom") end)
    c.watchAuctionRows(function(id) got[#got + 1] = id end)
    t.ok(pcall(c.auctionRows, 7, {}), "auctionRows does not raise")
    t.eq(got, { 7 })
end

return tests
