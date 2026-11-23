local _, ns = ...

-- PriceLookup (L6-H, G10): `<slash> price <item>` says what Z-Flow knows of
-- an item's price, and how it knows (F-085):
--   an observed price  (the item's own sell price, or one seen and saved)
--   else a labelled estimate that names its source
--   else "price unknown—check vendor". Unknown stays unknown: never a 0.
--
-- It only reads (the item read, the saved price book and the auction
-- history) and prints. A lookup writes nothing and asks no merchant, auction
-- or other player. The auction lines come from Items/AuctionLog.lua, the one
-- writer of auction prices (PA8): your own searches on this realm and
-- faction, nothing when the faction is not known.
--
--   result = PriceLookup.Find(item, itemInfo, book)     pure; nil: not an item
--   lines  = PriceLookup.Run(k, rest)                   what to say, no title
--   PriceLookup.Start(k, diag) -> { run = fn }          adds the word
--
--   result = { key, name (nil when not read),
--              sell = what a vendor pays for one: { unit, basis, source },
--                     or { unsellable = true } when the game says it can't
--                     be sold (ItemSell's rule, the same as the sell list)
--              buy  = what a merchant charges for one, from the saved
--                     merchant-window readings: { unit, basis, source, per } }
--   itemInfo  the client's item read (CLIENT NEED client.itemInfo), or nil
--   book      the saved price book (account learned.prices), or nil

local Lookup = {}
ns.PriceLookup = Lookup

Lookup.WORD = "price"
Lookup.USAGE = "say price <item link> (or an item ID)."

local function isCount(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge
end

function Lookup.Find(item, itemInfo, book)
    local key = ns.Items.Key(item)
    if key == nil then return nil end
    local Prices = ns.Prices
    local entry = { key = key }
    local name
    if type(itemInfo) == "function" then
        local ok, f = pcall(itemInfo, item)
        if ok and type(f) == "table" then
            if type(f.name) == "string" and f.name ~= "" then name = f.name end
            if isCount(f.sellPrice) then entry.sellPrice = f.sellPrice end
        end
    end
    local sell = ns.ItemSell.PriceOf(entry, book) or { unsellable = true }
    local p = Prices.Get(book, key, ns.PriceObserve.KIND)
    local buy = { unit = nil, basis = Prices.UNKNOWN, source = nil }
    if isCount(p.value) and p.value > 0 then
        if p.basis == Prices.OBSERVED then
            buy = { unit = p.value, basis = p.basis, source = p.source, per = p.per }
        elseif p.basis == Prices.ESTIMATED and type(p.source) == "string" and p.source ~= "" then
            buy = { unit = p.value, basis = p.basis, source = p.source, per = p.per }
        end
    end
    return { key = key, name = name, sell = sell, buy = buy }
end

local function trim(text)
    return (tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function Lookup.Run(k, rest)
    local client = k.client
    local read
    if type(client) == "table" and type(client.itemInfo) == "function" then
        -- By item ID: the slash command lower-cases a link, and the client
        -- may not read one in that form.
        read = function(item) return client.itemInfo(ns.Items.Id(item) or item) end
    end
    local book = k.store:get("account", "learned.prices")
    local result = Lookup.Find(trim(rest), read, type(book) == "table" and book or nil)
    if not result then return { Lookup.USAGE } end
    local lines = ns.ItemPresent.PriceLines(result)
    local log, chart = ns.AuctionLog, ns.PriceChart
    if type(result.key) == "number" and type(log) == "table" and type(chart) == "table"
        and type(client) == "table" and type(client.clock) == "function" then
        local e = log.Read(k.store, client, result.key)
        if e then
            for _, line in ipairs(chart.TipLines(chart.Points(e), client.clock())) do lines[#lines + 1] = line end
        end
    end
    return lines
end

function Lookup.Start(k, diag)
    local function run(rest)
        local lines = Lookup.Run(k, rest)
        for i = 1, #lines do k.client.print(k.id.title .. ": " .. lines[i]) end
    end
    if diag and type(diag.commands) == "table" then
        diag.commands[Lookup.WORD] = run
    end
    return { run = run }
end

-- The addon's own: the word is added when this file loads.
ns.priceLookup = Lookup.Start(ns, ns.diag)
