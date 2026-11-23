-- The auction reads of the client (S4, PA1): realm() and
-- watchAuctionResults(). The real client over a hand-built environment
-- (env stands in for the game's globals). Every row is written by hand.
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
    local ok = c.watchAuctionResults(function(id, r) got[#got + 1] = { id = id, row = r } end)
    return c, got, ok
end

return {
    ["client auction: the cheapest for one among the rows delivered, for a commodity"] = function(t)
        local env = auctionEnv({ [2589] = { { unitPrice = 50, quantity = 20 }, { unitPrice = 30, quantity = 5 },
            { unitPrice = 40, quantity = 1 } } })
        local _, got, ok = watch(env)
        t.eq(ok, true)
        t.eq(env.taken(COMMODITY), true)
        env.send(COMMODITY, 2589)
        t.eq(got, { { id = 2589, row = { unitPrice = 30, quantity = 5 } } })
        t.eq(env.asked, { 1, 2, 3 })
    end,

    ["client auction: an item search is priced by buyout over quantity"] = function(t)
        local env = auctionEnv({ [7] = { { buyoutAmount = 300, quantity = 3 }, { buyoutAmount = 90, quantity = 1 } } })
        local _, got = watch(env)
        env.send(ITEM, { itemID = 7 })
        t.eq(got, { { id = 7, row = { buyoutAmount = 90, quantity = 1 } } })
    end,

    ["client auction: row 1 alone when the client cannot say how many, and never past 50"] = function(t)
        local env = auctionEnv({ [2589] = { { unitPrice = 50 }, { unitPrice = 10 } } }, { noCount = true })
        local _, got = watch(env)
        env.send(COMMODITY, 2589)
        t.eq(env.asked, { 1 })
        t.eq(got[1].row, { unitPrice = 50 })
        local many = auctionEnv({}, { count = 500 })
        watch(many)
        many.send(COMMODITY, 1)
        t.eq(#many.asked, 50)
    end,

    ["client auction: nothing priced, nothing told; no auction house, no event asked for"] = function(t)
        local env = auctionEnv({ [2589] = { { quantity = 1 } } })
        local _, got = watch(env)
        env.send(COMMODITY, 2589)
        t.eq(got, {})
        local bare = auctionEnv({})
        bare.C_AuctionHouse = nil
        local _, _, ok = watch(bare)
        t.eq(ok, nil)
        t.eq(bare.taken(COMMODITY), false)
    end,

    -- PA2: more of the real client's watchAuctionResults, over the same
    -- hand-built environment.
    ["client auction: a second watcher shares the one event, and each is told once"] = function(t)
        local env = auctionEnv({ [2589] = { { unitPrice = 30 } } })
        local c = ns.make.client(env)
        local a, b = {}, {}
        t.eq(c.watchAuctionResults(function(id) a[#a + 1] = id end), true)
        t.eq(c.watchAuctionResults(function(id) b[#b + 1] = id end), true, "already followed: true")
        local listening = 0
        for _, f in ipairs(env.frames) do
            if f.events[COMMODITY] then listening = listening + 1 end
        end
        t.eq(listening, 1, "the event is asked for once")
        env.send(COMMODITY, 2589)
        t.eq(a, { 2589 })
        t.eq(b, { 2589 })
    end,

    ["client auction: a watcher that raises does not stop the others"] = function(t)
        local env = auctionEnv({ [2589] = { { unitPrice = 30 } } })
        local c = ns.make.client(env)
        local got = {}
        c.watchAuctionResults(function() error("watcher boom") end)
        c.watchAuctionResults(function(id, r) got[#got + 1] = { id = id, row = r } end)
        t.ok(pcall(env.send, COMMODITY, 2589), "the event does not raise")
        t.eq(got, { { id = 2589, row = { unitPrice = 30 } } })
    end,

    ["client auction: hidden values are left out; a hidden item is not told"] = function(t)
        local env = auctionEnv({
            [2589] = { { unitPrice = 999, buyoutAmount = 40, quantity = 2 } },
            [999] = { { unitPrice = 5 } },
        })
        env.issecretvalue = function(v) return v == 999 end
        local _, got = watch(env)
        env.send(COMMODITY, 2589)
        t.eq(got, { { id = 2589, row = { buyoutAmount = 40, quantity = 2 } } }, "the hidden price is dropped, the buyout prices it")
        env.send(COMMODITY, 999)
        t.eq(#got, 1, "a hidden item ID: nothing told")
    end,

    ["client auction: a row that cannot be read is passed over, not the search"] = function(t)
        local env = auctionEnv({})
        local rows = {
            { unitPrice = 50 },
            "raise",
            setmetatable({}, { __index = function() error("field boom") end }),
            { unitPrice = "10", buyoutAmount = 60, quantity = 2 },
        }
        env.C_AuctionHouse.GetCommoditySearchResultInfo = function(_, i)
            if rows[i] == "raise" then error("row boom") end
            return rows[i]
        end
        env.C_AuctionHouse.GetNumCommoditySearchResults = function() return #rows end
        local _, got = watch(env)
        env.send(COMMODITY, 2589)
        t.eq(got, { { id = 2589, row = { buyoutAmount = 60, quantity = 2 } } },
            "a raising row and a raising field are skipped; a price that is not a number is dropped")
    end,

    ["client auction: an item search with no readable key tells nothing"] = function(t)
        local env = auctionEnv({ [7] = { { unitPrice = 5 } } })
        local _, got = watch(env)
        env.send(ITEM, 7)
        env.send(ITEM, setmetatable({}, { __index = function() error("key boom") end }))
        t.eq(got, {})
        env.send(ITEM, { itemID = 7 })
        t.eq(got, { { id = 7, row = { unitPrice = 5 } } })
    end,

    ["client auction: a count that is not a whole number is read safely"] = function(t)
        local nan = auctionEnv({ [1] = { { unitPrice = 5 }, { unitPrice = 4 } } }, { count = 0 / 0 })
        watch(nan)
        nan.send(COMMODITY, 1)
        t.eq(nan.asked, { 1 }, "not a number: row 1 alone")
        local part = auctionEnv({ [1] = { { unitPrice = 5 }, { unitPrice = 4 }, { unitPrice = 3 } } }, { count = 2.7 })
        local _, got = watch(part)
        part.send(COMMODITY, 1)
        t.eq(part.asked, { 1, 2 }, "a fraction is rounded down")
        t.eq(got[1].row, { unitPrice = 4 })
    end,

    ["client auction: a hidden, zero or raising count reads row 1 alone"] = function(t)
        local hid = auctionEnv({ [1] = { { unitPrice = 5 }, { unitPrice = 4 } } }, { count = 777 })
        hid.issecretvalue = function(v) return v == 777 end
        watch(hid)
        hid.send(COMMODITY, 1)
        t.eq(hid.asked, { 1 }, "hidden count")
        local zero = auctionEnv({ [1] = { { unitPrice = 5 } } }, { count = 0 })
        watch(zero)
        zero.send(COMMODITY, 1)
        t.eq(zero.asked, { 1 }, "under one")
        local boom = auctionEnv({ [1] = { { unitPrice = 5 }, { unitPrice = 4 } } })
        boom.C_AuctionHouse.GetNumCommoditySearchResults = function() error("count boom") end
        local _, got = watch(boom)
        boom.send(COMMODITY, 1)
        t.eq(boom.asked, { 1 }, "a count that raises")
        t.eq(got[1].row, { unitPrice = 5 })
    end,

    ["client auction: a row with no price for one tells nothing"] = function(t)
        local env = auctionEnv({
            [1] = { { unitPrice = "x", buyoutAmount = 777 } },
            [2] = { { buyoutAmount = 50, quantity = 0 } },
        })
        env.issecretvalue = function(v) return v == 777 end
        local _, got = watch(env)
        env.send(COMMODITY, 1)
        env.send(COMMODITY, 2)
        t.eq(got, {}, "hidden or not-number prices; a buyout over a quantity of 0")
    end,

    ["client auction: an item key whose ID is hidden tells nothing"] = function(t)
        local env = auctionEnv({ [777] = { { unitPrice = 5 } } })
        env.issecretvalue = function(v) return v == 777 end
        local _, got = watch(env)
        env.send(ITEM, { itemID = 777 })
        t.eq(got, {})
    end,

    ["client auction: a client with one search read follows only its event"] = function(t)
        local com = auctionEnv({ [1] = { { unitPrice = 5 } } })
        com.C_AuctionHouse.GetItemSearchResultInfo = nil
        local _, _, ok = watch(com)
        t.eq(ok, true)
        t.eq(com.taken(COMMODITY), true)
        t.eq(com.taken(ITEM), false)
        local item = auctionEnv({ [7] = { { unitPrice = 5 } } })
        item.C_AuctionHouse.GetCommoditySearchResultInfo = nil
        local _, got, okI = watch(item)
        t.eq(okI, true)
        t.eq(item.taken(COMMODITY), false)
        t.eq(item.taken(ITEM), true)
        item.send(ITEM, { itemID = 7 })
        t.eq(got, { { id = 7, row = { unitPrice = 5 } } })
    end,

    ["client auction: a watcher added during a tell waits for the next one"] = function(t)
        local env = auctionEnv({ [1] = { { unitPrice = 5 } } })
        local c = ns.make.client(env)
        local late, added = {}, false
        c.watchAuctionResults(function()
            if added then return end
            added = true
            c.watchAuctionResults(function(id) late[#late + 1] = id end)
        end)
        env.send(COMMODITY, 1)
        t.eq(late, {}, "not told in the tell that added it")
        env.send(COMMODITY, 1)
        t.eq(late, { 1 })
    end,

    ["client auction: equal prices for one keep the first row"] = function(t)
        local env = auctionEnv({ [1] = { { unitPrice = 30, quantity = 5 }, { unitPrice = 30, quantity = 7 } } })
        local _, got = watch(env)
        env.send(COMMODITY, 1)
        t.eq(got, { { id = 1, row = { unitPrice = 30, quantity = 5 } } })
    end,

    ["client auction: no watcher function, nothing followed"] = function(t)
        local env = auctionEnv({})
        local c = ns.make.client(env)
        t.eq(c.watchAuctionResults(nil), nil)
        t.eq(c.watchAuctionResults("not a function"), nil)
        t.eq(env.taken(COMMODITY), false)
        t.eq(env.taken(ITEM), false)
    end,

    ["client realm: the realm's name, or nil"] = function(t)
        t.eq(ns.make.client({ GetRealmName = function() return "Old Blanchy" end }).realm(), "Old Blanchy")
        t.eq(ns.make.client({ GetRealmName = function() return "" end }).realm(), nil)
        t.eq(ns.make.client({}).realm(), nil)
    end,
}
