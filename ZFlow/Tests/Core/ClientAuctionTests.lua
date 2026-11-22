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

    ["client realm: the realm's name, or nil"] = function(t)
        t.eq(ns.make.client({ GetRealmName = function() return "Old Blanchy" end }).realm(), "Old Blanchy")
        t.eq(ns.make.client({ GetRealmName = function() return "" end }).realm(), nil)
        t.eq(ns.make.client({}).realm(), nil)
    end,
}
