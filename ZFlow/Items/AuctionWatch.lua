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
--   <slash> ah watch <item> [1.36g] | ah unwatch <item> | ah   (E-31)
-- E-31: a search result for a watched item at or under its mark says one
-- line and plays the alert sound, once an item a visit.
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
W.HELP = "<item> [price]: watch an item's auction price (amounts end in g, s or c, as 1.36g); <item> off drops it; alone: the list. It buys nothing."
-- E-31 (lead 682): the `ah` word, the legacy add-on's words for the same list
-- (Flow d78839f7 Modules/Items/Auction.lua:205-235): ah watch, ah unwatch, ah.
-- Its "scan" sends searches, an auction-house action: not here.
W.AH = "ah"
W.AH_HELP = "watch <item> [price] | unwatch <item> | alone: the watch list. It buys nothing."
W.AH_USAGE = "ah watch <item> [price] | ah unwatch <item> | ah (the list). It buys nothing."
-- E-33: bare ah frames the list as the legacy /flow ah did (Auction.lua:479-489):
-- a heading, each watched item with its last price ("not yet" there), an
-- "(empty)" line when none, then the words. No age, no cap, as there.
W.AH_HEAD = "auction watch list, last price seen:"
W.AH_EMPTY = "nothing watched."

local UNIT = { g = 10000, s = 100, c = 1 }

-- E-31 (lead 681): also the short form the add-on prints ("1.36g", "5.52s",
-- "52c", "13.6g"; Items/Prices.lua Coin), read as the legacy AH.ParseMoney
-- reads it (Flow d78839f7 Modules/Items/Auction.lua:40-52): spaces and case do
-- not count, a plain number is gold, amounts add up ("1g50s"). Anything
-- else, a malformed number among it, is no mark.
function W.Mark(text)
    if type(text) ~= "string" then return nil end
    text = text:lower():gsub("%s", "")
    if text == "" then return nil end
    if text:match("^[%d%.]+$") then
        local gold = tonumber(text)
        if gold == nil then return nil end
        return math.floor(gold * UNIT.g + 0.5)
    end
    if text:gsub("[%d%.]+[gsc]", "") ~= "" then return nil end
    local total = 0
    for num, unit in text:gmatch("([%d%.]+)([gsc])") do
        local n = tonumber(num)
        if n == nil then return nil end
        total = total + n * UNIT[unit]
    end
    return math.floor(total + 0.5)
end

local function coin(copper) return ns.Prices.Coin(copper) or ns.Prices.UnknownText("auction") end

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

-- E-33: the lines bare ah says, around the list's own lines.
function W.AhLines(lines)
    local out = { W.AH_HEAD }
    local any = false
    for _, line in ipairs(type(lines) == "table" and lines or {}) do
        out[#out + 1] = line
        any = true
    end
    if not any then out[#out + 1] = W.AH_EMPTY end
    out[#out + 1] = W.AH_USAGE
    return out
end

-- E-31: the chat line when a watched item is seen at or under its mark.
function W.AlertLine(name, unit, mark)
    return string.format("%s is on the auction house for %s each, at or under your %s.", name, coin(unit), coin(mark))
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
            if #lines == 0 then return say("nothing watched. watch <item> [price] adds one; an amount ends in g, s or c.") end
            for _, line in ipairs(lines) do say(line) end
            return
        end
        -- A chat link has spaces in its name: it runs to its closing |r.
        local item, rest = arg:match("^(|c.-|r)%s*(.-)$")
        if not item then item, rest = arg:match("^(%S+)%s*(.-)$") end
        local id = ns.Items.Id(item)
        if type(id) ~= "number" then return say("name an item: watch <item> [price].") end
        local saved, copy = list(), {}
        for key, v in pairs(saved) do copy[key] = v end
        local name = nameOr(nameOf, id)
        if rest == "off" then
            copy[id] = nil
            if ctx.store:set("char", W.PATH, copy) then say(name .. " dropped.") end
            return
        end
        local mark = W.Mark(rest)
        if rest ~= "" and mark == nil then return say("a price is amounts that end in g, s or c.") end
        copy[id] = mark or true
        if not ctx.store:set("char", W.PATH, copy) then return say("could not save the list.") end
        if mark then return say(string.format("%s, at or under %s.", name, coin(mark))) end
        say(name .. ".")
    end

    local function ah(arg)
        arg = type(arg) == "string" and arg:match("^%s*(.-)%s*$") or ""
        local cmd, rest = arg:match("^(%S*)%s*(.-)$")
        cmd = cmd:lower()
        if cmd == "" then
            if not ctx then return say("not started yet") end
            for _, line in ipairs(W.AhLines(W.Lines(list(), priceOf, nameOf))) do say(line) end
            return
        end
        if cmd == "watch" then return word(rest) end
        if cmd == "unwatch" then
            if rest == "" then return say(W.AH_USAGE) end
            return word(rest .. " off")
        end
        say(W.AH_USAGE)
    end

    -- E-31 (lead 682): the alert, as the legacy alertIfCheap
    -- (Flow d78839f7 Modules/Items/Auction.lua:80-86): one chat line and
    -- PlaySound(SOUNDKIT.RAID_WARNING), here client.playAlert (the same
    -- sound; it plays nothing, and no number is guessed, when the game names
    -- none). Once an item a visit: the legacy add-on alerted once an item a
    -- page read (:140-154); results here come row by row, so a visit to the
    -- auction house is the scan, and closing the window starts the next one.
    local alerted = {}
    local function seen(id, row)
        if not ctx or type(id) ~= "number" or alerted[id] then return end
        local mark = list()[id]
        if type(mark) ~= "number" then return end
        local unit = ns.AuctionLog.UnitFrom(row)
        if type(unit) ~= "number" or unit > mark then return end
        alerted[id] = true
        say(W.AlertLine(nameOr(nameOf, id), unit, mark))
        if type(ctx.client.playAlert) == "function" then pcall(ctx.client.playAlert) end
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[W.WORD] = word
        if type(diag.help) == "table" then diag.help[W.WORD] = W.HELP end
        if diag.commands[W.AH] == nil then
            diag.commands[W.AH] = ah
            if type(diag.help) == "table" then diag.help[W.AH] = W.AH_HELP end
        end
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
            alerted = {}
            if type(c.client.watchAuctionResults) == "function" then c.client.watchAuctionResults(seen) end
            c.bus:on(W.NAME, "AUCTION_HOUSE_CLOSED", function()
                alerted = {}
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
