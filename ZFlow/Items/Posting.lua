local _, ns = ...

-- S3 slices 1-3: what in your bags is worth the auction house, the price to
-- ask and the gain over a vendor; slice 2 puts that advice on the item
-- tooltip (setting auction.postAdvice); slice 3 counts the auctions that
-- came back unsold, from the game's own lines (CHAT_MSG_SYSTEM), and a sale
-- clears the count, as legacy did. A count is a floor ("at least"): a line
-- missed (another addon, a reload, a fight) is not counted. Legacy Flow's Modules/Items/Posting.lua
-- (0.35.214) and Disposition's WorthAuction, its pure rules ported
-- verbatim. Research: WoW/from-plexy/RESEARCH-posting.md.
--
-- ADVICE ONLY (§156 §8). Nothing here posts, confirms, cancels, picks a
-- duration or moves items: the player posts, if at all, in the game's own
-- auction window. Prices come only from the player's own searches
-- (Items/AuctionLog.lua); an item with no seen price is not listed.
--
--   Posting.Price(seen, undercut, min) -> copper each to ask, or nil
--   Posting.Verdict(each, vendor, count, lost, deposit, cut) -> "post"|"vendor", left
--   Posting.WorthAuction(ahPrice, vendorPrice) -> bool
--   Posting.Candidate(decision, item) -> bool   (also the trader's, S2)
--   Posting.List(bag, decide, seen) -> rows
--   Posting.Lines(rows, now, title, max, unsold) -> lines
--                    unsold: itemID -> how many came back unsold, or nil
--   Posting.TipLine(row, now, unsold) -> text, r, g, b; or nil
--   Posting.Note(record, outcome) -> the new { expired, sold }, or nil
--   Posting.Declare(k, diag) -> api   (api.runs(), api.tipBuilds())
--
--   <slash> auctions   the list
local Po = {}
ns.Posting = Po

Po.NAME = "posting"
Po.WORD = "auctions"
Po.HELP = "what in your bags is worth the auction house, from prices in your own searches; it posts nothing"
Po.UNDERCUT = 100   -- one silver under the cheapest seen
Po.MIN = 100        -- the game takes whole silver: nothing under one
Po.CUT = 0.05       -- the house's cut of a sale
Po.FEE = 0.30       -- legacy's listing fee, of the vendor price ("not checked on WoW: Forever")
Po.MAX = 10         -- rows shown (legacy P.ROWS)
Po.TRADE_GOODS = 7  -- unused trade goods go to the auction house (legacy 0.35.362)
Po.SETTING = "auction.postAdvice"
-- Said by the auctions word when the reservations can't be worked out
-- (lead section 220, SR-2): nothing is offered then.
Po.RESERVATIONS_UNKNOWN = "Reservations not known: nothing is offered for the auction house, as what your goals hold is not known."
Po.UNSOLD = "learned.auction.unsold"   -- char: itemID -> { expired, sold }
Po.TIP_CACHE = 5    -- seconds one bag read serves a run of tooltips
Po.COLOUR = { 1, 0.82, 0 }

-- Keep rules that are only a fallback: what they keep may still be offered.
local GENERIC = { notGear = true }

local function isCount(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge
end

-- Legacy P.Price, verbatim: the price each to ask, in whole silver,
-- `undercut` under what was seen, never under one silver. nil: no price
-- seen, or under a silver each (the game takes no copper prices).
function Po.Price(seen, undercut, min)
    seen = tonumber(seen)
    min = min or Po.MIN
    if not seen or seen < min then return nil end
    local ask = math.floor((seen - (undercut or Po.UNDERCUT)) / 100) * 100
    if ask < min then ask = math.floor(seen / 100) * 100 end
    return math.max(min, ask)
end

-- Legacy P.Verdict, verbatim: keep posting, or give up? each: the price
-- asked; vendor: the vendor's price each; count: how many; lost: deposits
-- lost on unsold auctions of it so far; deposit: the next one.
function Po.Verdict(each, vendor, count, lost, deposit, cut)
    local gain = ((each or 0) * (1 - (cut or Po.CUT)) - (vendor or 0)) * (count or 1)
    local left = gain - (lost or 0) - (deposit or 0)
    if left <= 0 then return "vendor", left end
    return "post", left
end

-- Legacy D.WorthAuction, verbatim: after the cut and the listing fee, at
-- least twice the vendor's price and a silver more than it.
function Po.WorthAuction(ahPrice, vendorPrice)
    if type(ahPrice) ~= "number" or ahPrice <= 0 then return false end
    vendorPrice = vendorPrice or 0
    local net = ahPrice * (1 - Po.CUT) - vendorPrice * Po.FEE
    return net >= vendorPrice * 2 and net - vendorPrice >= 100
end

-- May the item be offered at all? A sell decision, or a keep from the
-- generic fallback (nothing matched, or "not gear"); never a keep from a
-- choice, a fact, a quest, a set, a tool or a held count, never a failed
-- check, never equip, never a bound item.
function Po.Candidate(decision, item)
    if type(decision) ~= "table" then return false end
    if type(item) == "table" and item.bound == true then return false end
    if decision.action == "sell" then return true end
    if decision.action ~= "keep" or decision.failed then return false end
    return decision.rule == nil or GENERIC[decision.rule] == true
end

-- bag: entries as Bank.Entries makes them; decide(item) -> a decision;
-- seen(key) -> { price =, at = } (the latest look), or nil.
function Po.List(bag, decide, seen)
    local out = {}
    if type(bag) ~= "table" or type(decide) ~= "function" or type(seen) ~= "function" then return out end
    for _, item in ipairs(bag) do
        if type(item) == "table" and item.key ~= nil then
            local okD, d = pcall(decide, item)
            local okS, s = false, nil
            if okD and Po.Candidate(d, item) then okS, s = pcall(seen, item.key) end
            local price = okS and type(s) == "table" and s.price or nil
            local each = isCount(price) and Po.Price(price) or nil
            if each and (Po.WorthAuction(price, item.sellPrice) or item.classID == Po.TRADE_GOODS) then
                local count = isCount(item.count) and item.count or 1
                local vendor = isCount(item.sellPrice) and item.sellPrice or 0
                local _, left = Po.Verdict(each, vendor, count, 0, 0)
                out[#out + 1] = { id = item.key, name = item.name, count = count, each = each, seen = price,
                                  seenAt = isCount(s.at) and s.at or nil, vendor = vendor,
                                  gain = math.floor(left + 0.5) }
            end
        end
    end
    table.sort(out, function(a, b)
        if a.each * a.count ~= b.each * b.count then return a.each * a.count > b.each * b.count end
        return tostring(a.id) < tostring(b.id)
    end)
    return out
end

local function coin(n) return ns.Prices.Coin(n) or "?" end

local function unsoldText(n)
    if isCount(n) and n > 0 then return " (unsold at least " .. n .. "x)" end
    return ""
end

-- One expired or sold line for an item: a sale clears the unsold count
-- (legacy P.Note). nil when the outcome is neither.
function Po.Note(rec, outcome)
    if outcome ~= "sold" and outcome ~= "expired" then return nil end
    local expired = type(rec) == "table" and isCount(rec.expired) and rec.expired or 0
    local sold = type(rec) == "table" and isCount(rec.sold) and rec.sold or 0
    if outcome == "sold" then return { expired = 0, sold = sold + 1 } end
    return { expired = expired + 1, sold = sold }
end

-- The tooltip line for a listed row; nil without a price.
function Po.TipLine(row, now, unsold)
    if type(row) ~= "table" or not isCount(row.each) or not isCount(row.seen) then return nil end
    local text = "Auction: ask " .. coin(row.each) .. " each (" .. coin(row.seen - row.each) .. " under "
        .. coin(row.seen)
    if isCount(now) and isCount(row.seenAt) and now >= row.seenAt then
        text = text .. ", seen " .. ns.PriceChart.Span(now - row.seenAt) .. " ago"
    end
    return text .. ")" .. unsoldText(unsold), Po.COLOUR[1], Po.COLOUR[2], Po.COLOUR[3]
end

function Po.Lines(rows, now, title, max, unsold)
    title = tostring(title)
    local foot = "Posting is yours, in the auction window: " .. title .. " posts nothing."
    if type(rows) ~= "table" or #rows == 0 then return { title .. " Auctions: 0 thing(s) to post", foot } end
    max = isCount(max) and max or Po.MAX
    local lines = { title .. " Auctions: " .. #rows .. " thing(s) worth the auction house (from prices in your own searches)" }
    for i = 1, math.min(#rows, max) do
        local r = rows[i]
        local name = ns.ItemPresent.Name(r.id, type(r.name) == "string" and { [r.id] = r.name } or nil)
        local seenText = coin(r.seen)
        if isCount(r.seenAt) and isCount(now) and now >= r.seenAt then
            seenText = seenText .. ", " .. ns.PriceChart.Span(now - r.seenAt) .. " ago"
        end
        local gain = (r.gain or 0) >= 0 and ("+" .. coin(r.gain or 0)) or ("-" .. coin(-r.gain))
        local id = ns.Items.Id(r.id) or r.id
        lines[#lines + 1] = string.format("%s x %s: ask %s each (seen %s; a vendor pays %s; about %s over vendoring, the deposit not counted)%s",
            tostring(r.count), name, coin(r.each), seenText, coin(r.vendor), gain,
            unsoldText(type(unsold) == "table" and unsold[id] or nil))
    end
    if #rows > max then lines[#lines + 1] = "and " .. (#rows - max) .. " more." end
    lines[#lines + 1] = foot
    return lines
end

function Po.Declare(k, diag)
    local api = {}
    local ctx, runs = nil, 0
    local tipRows, tipAt, builds = nil, nil, 0
    local cancelTip, cancelSystem
    function api.runs() return runs end
    function api.tipBuilds() return builds end

    -- The latest look at an item in the player's own searches on this realm.
    local function seenOn(store, client)
        local rk = ns.AuctionLog.RealmKey(client.realm(), client.faction())
        local saved = rk and store:get("account", ns.AuctionLog.PATH .. "." .. rk)
        return function(key)
            local id = ns.Items.Id(key)
            local e = type(saved) == "table" and id and saved[id] or nil
            if not e then return nil end
            local points = ns.PriceChart.Points(e)
            return points[#points]
        end
    end

    -- The rows now, and whether the reservations were known. What a goal
    -- holds is kept (Disposition's held count), so it is never a candidate;
    -- reservations unavailable: no rows at all (SR-2).
    local function rowsNow(c, store)
        local r = ns.SellList.Current(ctx.use)
        if type(r) ~= "table" or r.status == ns.Reservations.UNAVAILABLE then return {}, false end
        local bag = ns.Bank.Entries(c.bagItems(), c.itemInfo)
        local context = ns.BankList.Context(store, ns.SellList.Held(r))
        return Po.List(bag, function(item) return ns.Disposition.Decide(item, context) end, seenOn(store, c)), true
    end

    -- itemID -> how many came back unsold since the last sale.
    local function unsoldCounts(store)
        local out = {}
        local saved = store:get("char", Po.UNSOLD)
        if type(saved) ~= "table" then return out end
        for id, rec in pairs(saved) do
            if type(rec) == "table" and isCount(rec.expired) and rec.expired > 0 then out[id] = rec.expired end
        end
        return out
    end

    -- A run of tooltips shares one bag read for TIP_CACHE seconds.
    local function tipList(c, store)
        local now = c.clock()
        if tipRows and isCount(now) and isCount(tipAt) and now >= tipAt and now - tipAt <= Po.TIP_CACHE then
            return tipRows
        end
        tipRows, tipAt = (rowsNow(c, store)), now
        builds = builds + 1
        return tipRows
    end

    -- A sold or expired line: the item is found by its name among the bags
    -- and the items with a seen price on this realm. Saved only when the
    -- name is one item; a name that matches none, or two, is passed over.
    local function outcome(c, store, line)
        local kind, name = c.auctionOutcome(line)
        if (kind ~= "sold" and kind ~= "expired") or type(name) ~= "string" or name == "" then return end
        local found = {}
        local function consider(id, itemName)
            if id ~= nil and itemName == name then found[id] = true end
        end
        for _, item in ipairs(ns.Bank.Entries(c.bagItems(), c.itemInfo) or {}) do
            if type(item) == "table" then consider(ns.Items.Id(item.key), item.name) end
        end
        local rk = ns.AuctionLog.RealmKey(c.realm(), c.faction())
        local priced = rk and store:get("account", ns.AuctionLog.PATH .. "." .. rk)
        if type(priced) == "table" then
            for id in pairs(priced) do
                local info = c.itemInfo(id)
                consider(id, type(info) == "table" and info.name or nil)
            end
        end
        local only, n = nil, 0
        for id in pairs(found) do only, n = id, n + 1 end
        if n ~= 1 then return end
        local saved = store:get("char", Po.UNSOLD)
        local t = {}
        if type(saved) == "table" then for key, v in pairs(saved) do t[key] = v end end
        local rec = Po.Note(t[only], kind)
        if not rec then return end
        t[only] = rec
        store:set("char", Po.UNSOLD, t)
    end

    local function run()
        local client = k.client
        if not ctx then client.print(k.id.title .. ": " .. Po.WORD .. ": not started yet") return end
        runs = runs + 1
        local store = ctx.store
        local ok, lines = pcall(function()
            local c = ctx.client
            local rows, known = rowsNow(c, store)
            if not known then return { k.id.title .. ": " .. Po.RESERVATIONS_UNKNOWN } end
            return Po.Lines(rows, c.clock(), k.id.title, nil, unsoldCounts(store))
        end)
        if not ok or type(lines) ~= "table" then
            client.print(k.id.title .. ": " .. Po.WORD .. ": could not be listed this time.")
            return
        end
        for _, line in ipairs(lines) do client.print(line) end
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[Po.WORD] = run
        if type(diag.help) == "table" then diag.help[Po.WORD] = Po.HELP end
    end

    k:Module({
        name = Po.NAME,
        needs = { "client", "store", "settings" },
        settings = { {
            key = Po.SETTING, scope = "account", type = "bool", default = true,
            label = "Auction advice on item tooltips",
            help = "For a thing in your bags worth the auction house: the price to ask, from your own searches, "
                .. "and how often it came back unsold (at least). It posts nothing.",
            group = "auctions", synonyms = { "auction", "post", "listing", "price", "ah" },
        } },
        start = function(c)
            ctx = c
            local client = c.client
            if type(client.onItemTooltip) == "function" then
                cancelTip = client.onItemTooltip(function(link, add)
                    if type(add) ~= "function" or c.settings:get(Po.SETTING) ~= true then return end
                    local ok, text, r, g, b = pcall(function()
                        local id = ns.Items.Id(link)
                        if id == nil then return nil end
                        for _, row in ipairs(tipList(client, c.store)) do
                            if ns.Items.Id(row.id) == id then
                                return Po.TipLine(row, client.clock(), unsoldCounts(c.store)[id])
                            end
                        end
                        return nil
                    end)
                    if ok and type(text) == "string" then add(text, r, g, b) end
                end)
            end
            if type(client.onSystemMessage) == "function" and type(client.auctionOutcome) == "function" then
                cancelSystem = client.onSystemMessage(function(line) pcall(outcome, client, c.store, line) end)
            end
        end,
        stop = function()
            if type(cancelTip) == "function" then cancelTip() end
            if type(cancelSystem) == "function" then cancelSystem() end
            cancelTip, cancelSystem, tipRows, tipAt, ctx = nil, nil, nil, nil, nil
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.posting = Po.Declare(ns, ns.diag)
