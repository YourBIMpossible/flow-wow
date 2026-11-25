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
--   line   = PriceLookup.PostLine(seen)                 E-35 suggested post, or nil
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
Lookup.USAGE = "say price <item link>, an item name or an item ID."

-- E-42 (§611): a name no item answers to. Said so; no price is made up.
function Lookup.NotFound(text)
    return 'No known item is called "' .. tostring(text) .. '": link it, or use its item ID.'
end

-- E-42: an item name -> its item ID through the client's name read
-- (CLIENT NEED client.itemIdByName; stubbed in Core/ClientFake.lua), or nil.
local function idByName(client, text)
    if type(client) ~= "table" or type(client.itemIdByName) ~= "function" then return nil end
    local ok, id = pcall(client.itemIdByName, text)
    if not ok then return nil end
    return ns.Items.Key(id)
end

local function isCount(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge
end

function Lookup.Find(item, itemInfo, book)
    local key = ns.Items.Key(item)
    if key == nil then return nil end
    local Prices = ns.Prices
    local entry = { key = key }
    local name, quality
    if type(itemInfo) == "function" then
        local ok, f = pcall(itemInfo, item)
        if ok and type(f) == "table" then
            if type(f.name) == "string" and f.name ~= "" then name = f.name end
            if type(f.quality) == "number" then quality = f.quality end
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
    return { key = key, name = name, quality = quality, sell = sell, buy = buy }
end

-- E-35: the suggested post price for an item last seen at `seen` copper
-- each in the player's own searches. The rule is the legacy one, kept in
-- Items/Posting.lua (Posting.Price: a silver under, whole silver, never
-- under one silver). Advice only: nothing posts, and nothing is prefilled.
-- nil when no price is suggested (none seen, or under a silver each).
function Lookup.PostLine(seen)
    if not isCount(seen) then return nil end
    local Posting = ns.Posting
    if type(Posting) ~= "table" or type(Posting.Price) ~= "function" then return nil end
    local ask = Posting.Price(seen)
    if not isCount(ask) then return nil end
    local coin = ns.Prices.Coin
    return "Suggested post: " .. tostring(coin(ask)) .. " each (" .. tostring(coin(seen - ask)) .. " under the "
        .. tostring(coin(seen)) .. " last seen; advice only, nothing is posted)"
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
    local text = trim(rest)
    if text == "" then return { Lookup.USAGE } end
    local item = text
    if ns.Items.Key(text) == nil then
        item = idByName(client, text)
        if item == nil then return { Lookup.NotFound(text) } end
    end
    if type(book) ~= "table" then book = nil end
    local result = Lookup.Find(item, read, book)
    if not result then return { Lookup.NotFound(text) } end
    local lines = ns.ItemPresent.PriceLines(result)
    local log, chart = ns.AuctionLog, ns.PriceChart
    if type(result.key) == "number" and type(log) == "table" and type(chart) == "table"
        and type(client) == "table" and type(client.clock) == "function" then
        local e = log.Read(k.store, client, result.key)
        if e then
            local points = chart.Points(e)
            for _, line in ipairs(chart.TipLines(points, client.clock())) do lines[#lines + 1] = line end
            local last = points[#points]
            if type(last) == "table" then
                local post = Lookup.PostLine(last.price)
                if post then lines[#lines + 1] = post end
            end
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
        if type(diag.help) == "table" then diag.help[Lookup.WORD] = "price <item>: what is known of an item's price, and how it is known" end
    end
    return { run = run }
end

-- The addon's own: the word is added when this file loads.
ns.priceLookup = Lookup.Start(ns, ns.diag)
