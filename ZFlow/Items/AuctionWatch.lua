local _, ns = ...

-- The auction watch list (G9, section 393): items the player names, each
-- with an optional price mark, and the last auction price seen for them in
-- the player's own searches (Items/AuctionLog.lua, the one writer of those
-- prices). Read and show only: nothing here searches, bids, buys or posts.
--
--   <slash> watch                         the list, with the last price seen
--   <slash> watch <item> [1g 2s 3c]       adds it (with that mark)
--   <slash> watch <item> off              drops it
-- When the auction window closes (AUCTION_HOUSE_CLOSED), one chat line for
-- each watched item whose last price is at or under its mark.
--
--   copper = AuctionWatch.Mark(text)      nil when text is no coin amount
--   lines  = AuctionWatch.Lines(list, priceOf, nameOf[, under])
--     list    { [itemID] = mark copper, or true for no mark }
--     priceOf(id) -> the last price seen for one, or nil
--     nameOf(id)  -> the item's name, or nil (never shown as a number)
--     under   true: only the items at or under their mark
--   api    = AuctionWatch.Declare(k, diag)
--
-- Saved: char "items.auctionWatch" = the list. Setting items.auctionWatch
-- (bool, account, on by default) for the closing lines; the word always
-- answers. Not tested in game: AUCTION_HOUSE_CLOSED on 16001.

local W = {}
ns.AuctionWatch = W

W.NAME = "auctionWatch"
W.WORD = "watch"
W.SETTING = "items.auctionWatch"
W.PATH = "items.auctionWatch"
W.UNNAMED = "an item not loaded yet"
W.HELP = "<item> [1g 2s 3c]: watch an item's auction price; <item> off drops it; alone: the list. It buys nothing."

local UNIT = { g = 10000, s = 100, c = 1 }

function W.Mark(text)
    if type(text) ~= "string" then return nil end
    local total, any = 0, false
    for word in text:gmatch("%S+") do
        local n, unit = word:match("^(%d+)([gsc])$")
        if not n then return nil end
        total, any = total + tonumber(n) * UNIT[unit], true
    end
    if not any then return nil end
    return total
end

local function coin(copper) return ns.Prices.Coin(copper) or (tostring(copper) .. "c") end

local function sortedIds(list)
    local ids = {}
    for id in pairs(type(list) == "table" and list or {}) do
        if type(id) == "number" then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ids
end

local function nameOr(nameOf, id)
    local ok, name = pcall(nameOf, id)
    if ok and type(name) == "string" and name ~= "" then return name end
    return W.UNNAMED
end

function W.Lines(list, priceOf, nameOf, under)
    local out = {}
    for _, id in ipairs(sortedIds(list)) do
        local mark = list[id]
        if type(mark) ~= "number" then mark = nil end
        local okP, price = pcall(priceOf, id)
        if not okP or type(price) ~= "number" then price = nil end
        local name = nameOr(nameOf, id)
        if under then
            if price and mark and price <= mark then
                out[#out + 1] = string.format("%s was %s each, under your %s.", name, coin(price), coin(mark))
            end
        elseif price == nil then
            out[#out + 1] = name .. ": not seen in your searches yet."
        elseif mark and price <= mark then
            out[#out + 1] = string.format("%s: %s each, under your %s.", name, coin(price), coin(mark))
        elseif mark then
            out[#out + 1] = string.format("%s: %s each, over your %s.", name, coin(price), coin(mark))
        else
            out[#out + 1] = string.format("%s: %s each.", name, coin(price))
        end
    end
    return out
end

function W.Declare(k, diag)
    local api = {}
    local ctx = nil

    local function list()
        local saved = ctx.store:get("char", W.PATH)
        return type(saved) == "table" and saved or {}
    end
    local function priceOf(id)
        local e = ns.AuctionLog.Read(ctx.store, ctx.client, id)
        local h = type(e) == "table" and e.h or nil
        if type(h) ~= "table" or #h < 2 then return nil end
        return h[#h]
    end
    local function nameOf(id)
        local info = ctx.client.itemInfo and ctx.client.itemInfo(id)
        return type(info) == "table" and info.name or nil
    end
    local function say(s) k.client.print(k.id.title .. ": " .. W.WORD .. ": " .. s) end

    local function word(arg)
        if not ctx then return say("not started yet") end
        arg = type(arg) == "string" and arg:match("^%s*(.-)%s*$") or ""
        if arg == "" then
            local lines = W.Lines(list(), priceOf, nameOf)
            if #lines == 0 then return say("nothing watched. watch <item> [price, as 1g 2s 3c] adds one.") end
            for _, line in ipairs(lines) do say(line) end
            return
        end
        -- A chat link has spaces in its name: it runs to its closing |r.
        local item, rest = arg:match("^(|c.-|r)%s*(.-)$")
        if not item then item, rest = arg:match("^(%S+)%s*(.-)$") end
        local id = ns.Items.Id(item)
        if type(id) ~= "number" then return say("name an item: watch <item> [1g 2s 3c].") end
        local saved, copy = list(), {}
        for key, v in pairs(saved) do copy[key] = v end
        local name = nameOr(nameOf, id)
        if rest == "off" then
            copy[id] = nil
            if ctx.store:set("char", W.PATH, copy) then say(name .. " dropped.") end
            return
        end
        local mark = W.Mark(rest)
        if rest ~= "" and mark == nil then return say("a price is coins, as 1g 2s 3c.") end
        copy[id] = mark or true
        if not ctx.store:set("char", W.PATH, copy) then return say("could not save the list.") end
        if mark then return say(string.format("%s, at or under %s.", name, coin(mark))) end
        say(name .. ".")
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[W.WORD] = word
        if type(diag.help) == "table" then diag.help[W.WORD] = W.HELP end
    end

    k:Module({
        name = W.NAME,
        needs = { "client", "store", "settings", "bus" },
        settings = { {
            key = W.SETTING, scope = "account", type = "bool", default = true,
            label = "Say watched auction prices",
            help = "When you close the auction house, say each watched item you saw at or under your price."
                .. " It buys nothing.",
            group = "auctions", synonyms = { "watch", "auction", "price", "ah", "mark" },
        } },
        start = function(c)
            ctx = c
            c.bus:on(W.NAME, "AUCTION_HOUSE_CLOSED", function()
                if c.settings:get(W.SETTING) ~= true then return end
                for _, line in ipairs(W.Lines(list(), priceOf, nameOf, true)) do say(line) end
            end)
        end,
        stop = function() ctx = nil end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.auctionWatch = W.Declare(ns, ns.diag)
