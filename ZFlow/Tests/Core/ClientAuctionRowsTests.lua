-- The rows of an auction search (S2): watchAuctionRows(). The real client
-- over a hand-built environment (env stands in for the game's globals), as
-- ClientAuctionTests.lua builds it. Every row is written by hand.
-- Not tested in game.
local _, ns = ...

local COMMODITY, ITEM = "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED"

-- Frames that take events; env.send(name, ...) is the client raising one.
-- rows[what] lists the rows the client has delivered for a search; asked
-- keeps the row numbers read. opts.noCount: the client cannot say how many.
local function auctionEnv(rows, opts)
    opts = opts or {}
    local env = { frames = {}, asked = {} }
    function env.CreateFrame()
        local f = { scripts = {}, events = {} }
        function f:SetScript(script, fn) self.scripts[script] = fn end
        function f:RegisterEvent(name) self.events[name] = true end
        function f:UnregisterEvent(name) self.events[name] = nil end
        env.frames[#env.frames + 1] = f
        return f
    end
    function env.taken(name)
        for _, f in ipairs(env.frames) do
            if f.events[name] then return true end
        end
        return false
    end
    function env.send(name, ...)
        for _, f in ipairs(env.frames) do
            if f.events[name] and f.scripts.OnEvent then f.scripts.OnEvent(f, name, ...) end
        end
    end
    local function list(what) return rows[type(what) == "table" and what.itemID or what] or {} end
    local function row(what, i)
        env.asked[#env.asked + 1] = i
        return list(what)[i]
    end
    local function count(what) return opts.count or #list(what) end
    env.C_AuctionHouse = {
        GetCommoditySearchResultInfo = row,
        GetItemSearchResultInfo = row,
        GetNumCommoditySearchResults = not opts.noCount and count or nil,
        GetNumItemSearchResults = not opts.noCount and count or nil,
    }
    return env
end

local function watch(env)
    local got = {}
    local c = ns.make.client(env)
    local ok = c.watchAuctionRows(function(id, rows) got[#got + 1] = { id = id, rows = rows } end)
    return c, got, ok
end

return {
    ["client auction rows: every priced row delivered for a commodity, in the order given"] = function(t)
        local env = auctionEnv({ [2589] = { { unitPrice = 50, quantity = 20 }, { unitPrice = 30, quantity = 5 },
            { quantity = 3 }, { unitPrice = 40, quantity = 1 } } })
        local _, got, ok = watch(env)
        t.eq(ok, true)
        t.eq(env.taken(COMMODITY), true)
        env.send(COMMODITY, 2589)
        t.eq(got, { { id = 2589, rows = { { unit = 50, qty = 20 }, { unit = 30, qty = 5 }, { unit = 40, qty = 1 } } } },
            "a row with no price is left out")
        t.eq(env.asked, { 1, 2, 3, 4 })
    end,

    ["client auction rows: an item search, priced by buyout over quantity"] = function(t)
        local env = auctionEnv({ [7] = { { buyoutAmount = 300, quantity = 3 }, { buyoutAmount = 90, quantity = 1 },
            { buyoutAmount = 80 } } })
        local _, got = watch(env)
        t.eq(env.taken(ITEM), true)
        env.send(ITEM, { itemID = 7 })
        t.eq(got, { { id = 7, rows = { { unit = 100, qty = 3 }, { unit = 90, qty = 1 }, { unit = 80 } } } },
            "a count not given is left out, never made up")
    end,

    ["client auction rows: row 1 alone when the client cannot say how many, and never past 50"] = function(t)
        local env = auctionEnv({ [2589] = { { unitPrice = 50, quantity = 2 }, { unitPrice = 10, quantity = 2 } } },
            { noCount = true })
        local _, got = watch(env)
        env.send(COMMODITY, 2589)
        t.eq(env.asked, { 1 })
        t.eq(got[1].rows, { { unit = 50, qty = 2 } })
        local rows = {}
        for i = 1, 60 do rows[i] = { unitPrice = i, quantity = 1 } end
        local many = auctionEnv({ [1] = rows }, { count = 500 })
        local _, all = watch(many)
        many.send(COMMODITY, 1)
        t.eq(#many.asked, 50)
        t.eq(#all[1].rows, 50)
        t.eq(all[1].rows[50], { unit = 50, qty = 1 })
    end,

    ["client auction rows: hidden values are left out; a hidden item is not told"] = function(t)
        local env = auctionEnv({
            [2589] = { { unitPrice = 999, buyoutAmount = 40, quantity = 2 }, { unitPrice = 30, quantity = 999 },
                { unitPrice = 999 } },
            [999] = { { unitPrice = 5, quantity = 1 } },
        })
        env.issecretvalue = function(v) return v == 999 end
        local _, got = watch(env)
        env.send(COMMODITY, 2589)
        t.eq(got, { { id = 2589, rows = { { unit = 20, qty = 2 }, { unit = 30 } } } },
            "a hidden price: the buyout prices it; a hidden count is left out; nothing readable, no row")
        env.send(COMMODITY, 999)
        t.eq(#got, 1, "a hidden item ID: nothing told")
    end,

    ["client auction rows: a count that is not a real count is left out"] = function(t)
        local env = auctionEnv({ [1] = { { unitPrice = 5, quantity = 0 }, { unitPrice = 6, quantity = -2 },
            { unitPrice = 7, quantity = "3" }, { unitPrice = 8, quantity = 2.5 } } })
        local _, got = watch(env)
        env.send(COMMODITY, 1)
        t.eq(got[1].rows, { { unit = 5 }, { unit = 6 }, { unit = 7 }, { unit = 8 } })
    end,

    ["client auction rows: nothing priced is told as no rows; no auction house, no event asked for"] = function(t)
        local env = auctionEnv({ [2589] = { { quantity = 1 } } })
        local _, got = watch(env)
        env.send(COMMODITY, 2589)
        t.eq(got, { { id = 2589, rows = {} } }, "a search that shows nothing priced takes an old deal away")
        env.send(ITEM, 7)
        env.send(ITEM, setmetatable({}, { __index = function() error("key boom") end }))
        t.eq(#got, 1, "an item search with no readable key tells nothing")
        local bare = auctionEnv({})
        bare.C_AuctionHouse = nil
        local _, _, ok = watch(bare)
        t.eq(ok, nil)
        t.eq(bare.taken(COMMODITY), false)
        t.eq(ns.make.client(auctionEnv({})).watchAuctionRows("not a function"), nil)
    end,

    ["client auction rows: a watcher that raises does not stop the others"] = function(t)
        local env = auctionEnv({ [2589] = { { unitPrice = 30, quantity = 1 } } })
        local c = ns.make.client(env)
        local got = {}
        t.eq(c.watchAuctionRows(function() error("watcher boom") end), true)
        t.eq(c.watchAuctionRows(function(id, rows) got[#got + 1] = { id = id, rows = rows } end), true)
        t.ok(pcall(env.send, COMMODITY, 2589), "the event does not raise")
        t.eq(got, { { id = 2589, rows = { { unit = 30, qty = 1 } } } })
    end,

    ["client auction rows: the cheapest-row watcher is told as before, beside it"] = function(t)
        local env = auctionEnv({ [2589] = { { unitPrice = 50, quantity = 20 }, { unitPrice = 30, quantity = 5 } } })
        local c = ns.make.client(env)
        local cheapest, all = {}, {}
        t.eq(c.watchAuctionResults(function(id, r) cheapest[#cheapest + 1] = { id = id, row = r } end), true)
        t.eq(c.watchAuctionRows(function(id, rows) all[#all + 1] = { id = id, rows = rows } end), true)
        env.send(COMMODITY, 2589)
        t.eq(cheapest, { { id = 2589, row = { unitPrice = 30, quantity = 5 } } })
        t.eq(all, { { id = 2589, rows = { { unit = 50, qty = 20 }, { unit = 30, qty = 5 } } } })
    end,

    ["client auction rows: the fake client tells its row watchers what a test gives it"] = function(t)
        local c = ns.make.fakeClient()
        local got = {}
        t.eq(c.watchAuctionRows(function(id, rows) got[#got + 1] = { id = id, rows = rows } end), true)
        t.eq(c.watchAuctionRows("no"), nil)
        c.auctionRows(7, { { unit = 5, qty = 2 } })
        t.eq(got, { { id = 7, rows = { { unit = 5, qty = 2 } } } })
        local closed = ns.make.fakeClient()
        closed.setAuctionHouse(false)
        t.eq(closed.watchAuctionRows(function() end), nil)
    end,
}
