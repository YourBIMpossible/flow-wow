local _, ns = ...

-- S4 price chart, tooltip only: where the prices come from, and the line on
-- the tooltip. Legacy Flow's Modules/Items/Auction.lua kept, per realm and
-- faction, each item's cheapest buyout for one at each visit to the auction
-- house ({ h = { at, price, ... } }, 48 points, thinned at the far end);
-- Modules/Items/PriceChart.lua drew it. Research:
-- WoW/from-plexy/RESEARCH-price-chart.md.
--
-- Prices come only from searches the player runs in the auction window
-- (client.watchAuctionResults; the L6-F note's option A). Nothing here sends
-- a search, posts, bids or buys. On an item's tooltip: the price now and
-- its history (Items/PriceChart.lua's TipLines), nothing for an item with
-- no look.
--
-- Saved: account "learned.prices.auctionHistory"[realm key][itemID] =
-- { h = { at, price, ... } }, realm key = "<realm>-<faction>" as legacy
-- Flow wrote it (a "." in it becomes "_": the store splits paths on dots).
--
--   AuctionLog.UnitFrom(row) -> copper for one, or nil   (legacy, verbatim)
--   AuctionLog.AddPoint(h, price, at, max, same) -> h     (legacy, verbatim)
--   AuctionLog.RealmKey(realm, faction) -> key, or nil
--   AuctionLog.ProbeLines(present) -> lines for `auction probe`
--   AuctionLog.Declare(k, diag) -> api   (api.looks() -> looks recorded)
--
--   <slash> auction         how many items have prices on this realm
--   <slash> auction probe   which auction calls this client has
local AL = {}
ns.AuctionLog = AL

AL.NAME = "auctionLog"
AL.WORD = "auction"
AL.SETTING = "items.priceChart"
AL.PATH = "learned.prices.auctionHistory"
AL.HIST_MAX = 48     -- points kept an item
AL.SAME_LOOK = 600   -- seconds: looks this close together are one visit (its cheapest counts)
AL.COLOUR = { 1, 0.82, 0 }
AL.HELP = "auction prices seen in your own searches; auction probe: which auction calls this game has"
AL.PROBE = {
    "C_AuctionHouse", "C_AuctionHouse.GetCommoditySearchResultInfo", "C_AuctionHouse.GetItemSearchResultInfo",
    "C_AuctionHouse.GetNumCommoditySearchResults", "C_AuctionHouse.GetNumItemSearchResults",
    "C_AuctionHouse.SendSearchQuery", "C_AuctionHouse.MakeItemKey", "C_AuctionHouse.ReplicateItems",
    "QueryAuctionItems", "GetRealmName",
}

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function AL.UnitFrom(row)
    if type(row) ~= "table" then return nil end
    if finite(row.unitPrice) and row.unitPrice > 0 then return row.unitPrice end
    local buyout, n = row.buyoutAmount, row.quantity or 1
    if finite(buyout) and buyout > 0 and finite(n) and n > 0 then return buyout / n end
    return nil
end

function AL.AddPoint(h, price, at, max, same)
    local n = #h
    if n >= 2 and at >= h[n - 1] and at - h[n - 1] < (same or AL.SAME_LOOK) then
        h[n] = math.min(h[n], price)
        return h
    end
    h[n + 1], h[n + 2] = at, price
    local count = #h / 2
    if count > (max or AL.HIST_MAX) then
        local kept, half = {}, math.floor(count / 2)
        for i = 1, count do
            if i > half or i % 2 == 1 then
                kept[#kept + 1], kept[#kept + 2] = h[i * 2 - 1], h[i * 2]
            end
        end
        for i = #h, 1, -1 do h[i] = nil end
        for i, v in ipairs(kept) do h[i] = v end
    end
    return h
end

function AL.RealmKey(realm, faction)
    if type(realm) ~= "string" or realm == "" then return nil end
    local key = realm .. "-" .. ((type(faction) == "string" and faction ~= "") and faction or "?")
    return (key:gsub("%.", "_"))
end

function AL.ProbeLines(present)
    local have, missing = {}, {}
    for _, name in ipairs(AL.PROBE) do
        if present(name) then have[#have + 1] = name else missing[#missing + 1] = name end
    end
    return {
        "auction probe: has " .. (#have > 0 and table.concat(have, ", ") or "none of them"),
        "auction probe: lacks " .. (#missing > 0 and table.concat(missing, ", ") or "none of them"),
        "Now search one item in the auction window yourself, then type the auction word again: its count should rise.",
    }
end

function AL.Declare(k, diag)
    local api = {}
    local ctx, looks, cancel = nil, 0, nil
    function api.looks() return looks end

    local function realmKey()
        local client = ctx.client
        return AL.RealmKey(client.realm(), client.faction())
    end

    local function entries(rk)
        local saved = rk and ctx.store:get("account", AL.PATH .. "." .. rk)
        return type(saved) == "table" and saved or nil
    end

    local function record(id, row)
        if not ctx or type(id) ~= "number" then return end
        local unit = AL.UnitFrom(row)
        local at = ctx.client.clock()
        local rk = realmKey()
        if not unit or not finite(at) or not rk then return end
        -- The realm's table is copied one level and the item's history in
        -- full, so a refused save leaves what was saved as it was.
        local copy = {}
        for key, e in pairs(entries(rk) or {}) do copy[key] = e end
        local old = copy[id]
        local h = {}
        if type(old) == "table" and type(old.h) == "table" then
            for i, v in ipairs(old.h) do h[i] = v end
        end
        copy[id] = { h = AL.AddPoint(h, math.floor(unit + 0.5), at) }
        if ctx.store:set("account", AL.PATH .. "." .. rk, copy) then looks = looks + 1 end
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[AL.WORD] = function(arg)
            local function say(s) k.client.print(k.id.title .. ": " .. s) end
            if not ctx then say("auction: not started yet") return end
            if type(arg) == "string" and arg:find("probe", 1, true) then
                local present = ctx.client.apiPresent
                if type(present) ~= "function" then say("auction probe: this client cannot be asked") return end
                for _, line in ipairs(AL.ProbeLines(present)) do say(line) end
                return
            end
            local rk = realmKey()
            local n = 0
            for _ in pairs(entries(rk) or {}) do n = n + 1 end
            say(string.format("auction: prices for %d item(s) on %s, from %d search(es) this session.", n,
                rk or "a realm not read", looks))
        end
        if type(diag.help) == "table" then diag.help[AL.WORD] = AL.HELP end
    end

    k:Module({
        name = AL.NAME,
        needs = { "client", "store", "settings" },
        settings = { {
            key = AL.SETTING, scope = "account", type = "bool", default = true,
            label = "Auction price history on item tooltips",
            help = "The cheapest buyout for one you saw in your own auction searches, and how it moved. It buys and posts nothing.",
            group = "Vendor",
        } },
        provides = { Looks = api.looks },
        start = function(c)
            ctx = c
            if type(c.client.watchAuctionResults) == "function" then c.client.watchAuctionResults(record) end
            if type(c.client.onItemTooltip) ~= "function" then return end
            cancel = c.client.onItemTooltip(function(link, add)
                if c.settings:get(AL.SETTING) ~= true or type(add) ~= "function" then return end
                local key = ns.Items.Key(link)
                local saved = type(key) == "number" and entries(realmKey()) or nil
                local e = saved and saved[key]
                if not e then return end
                for _, line in ipairs(ns.PriceChart.TipLines(ns.PriceChart.Points(e), c.client.clock())) do
                    add(line, AL.COLOUR[1], AL.COLOUR[2], AL.COLOUR[3])
                end
            end)
        end,
        stop = function()
            if type(cancel) == "function" then cancel() end
            cancel = nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.auctionLog = AL.Declare(ns, ns.diag)
