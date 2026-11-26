local _, ns = ...

-- E-new-8 (lead section 809a): gear you could disenchant, but whose price
-- seen in your own auction searches is clearly worth more, gets a line on
-- its tooltip saying so. Look only: nothing is posted, bought, sold or
-- disenchanted. There is no disenchant rule of our own yet (Items/BagMarks.lua
-- says so), so this is a line beside the keep-or-sell line, not a verdict.
--
-- The rule is Flow's (branch w1-safety, commit ff05c4eb,
-- Modules/Items/Disposition.lua:880-900, D.AuctionBeatsDisenchant and the
-- unneededGear rule): gear of quality 2 or better, the player knows
-- Enchanting, the item is tradeable, and
--     net = seen * (1 - CUT) - vendor * FEE
--     net >= vendor * OVER  and  net >= MIN
-- CUT and FEE are Disposition.lua:489's AH_CUT and AH_FEE (the same as
-- Items/Posting.lua's). Flow never knew what the dust and shards are worth,
-- so "clearly" is a margin over the vendor price, not a comparison with a
-- disenchant value; we have no such value either and make none up.
--
--   ok   = AuctionOverDE.Beats(seen, vendor)
--   text = AuctionOverDE.Line(facts)     pure; nil: no line
--   api  = AuctionOverDE.Declare(k)      api.hooked()
--
--   facts { quality, classID, sellPrice (a vendor's price for one),
--           seen (copper for one, the latest look in your own searches),
--           enchanting (true, false or nil = not known),
--           bound (true, false or nil = not known) }
--
-- Flow advised only on bound == false. Here a stack whose binding the client
-- does not give still gets the line, worded to hold only if it is tradeable.
-- CLIENT NEED: client.bagItems() rows carry bound = true or false.
-- Shown under the keep-or-sell tooltip setting (Items/DispositionTip.lua).

local A = {}
ns.AuctionOverDE = A

A.NAME = "auctionOverDisenchant"
A.CUT = 0.05     -- the house's cut of a sale (Flow D.AH_CUT)
A.FEE = 0.30     -- the listing fee, of the vendor price (Flow D.AH_FEE)
A.OVER = 3       -- times the vendor price (Flow D.AH_OVER_DE)
A.MIN = 10000    -- copper, 1 gold (Flow D.AH_OVER_DE_MIN)
A.QUALITY = 2    -- green and better
A.GEAR = { [2] = true, [4] = true }   -- item classes: weapons, armour
A.ENCHANTING = "Enchanting"
A.COLOUR = { 1, 0.82, 0 }

local function isCount(n)
    return type(n) == "number" and n == n and n >= 0 and n < math.huge
end

function A.Beats(seen, vendor)
    if not isCount(seen) or seen <= 0 then return false end
    local v = 0
    if isCount(vendor) then v = vendor end
    local net = seen * (1 - A.CUT) - v * A.FEE
    return net >= v * A.OVER and net >= A.MIN
end

function A.Line(f)
    if type(f) ~= "table" then return nil end
    if f.enchanting ~= true or f.bound == true then return nil end
    if not isCount(f.quality) or f.quality < A.QUALITY then return nil end
    if A.GEAR[f.classID] ~= true then return nil end
    if not A.Beats(f.seen, f.sellPrice) then return nil end
    local text = "Worth more at the auction house than disenchanted: "
        .. ns.Prices.Coin(f.seen) .. " in your own searches"
    -- Only a plain false is a known tradeable item.
    if f.bound ~= false then text = text .. ", if tradeable" end
    return text
end

-- The latest look at an item in your own searches on this realm, or nil.
local function seenPrice(store, client, id)
    local e = ns.AuctionLog.Read(store, client, id)
    if not e then return nil end
    local points = ns.PriceChart.Points(e)
    local last = points[#points]
    if type(last) ~= "table" then return nil end
    return last.price
end

-- Whether you know Enchanting: nil when the client gives no read.
local function knowsEnchanting(client)
    if type(client.professions) ~= "function" then return nil end
    local ok, have = pcall(client.professions)
    if not ok or type(have) ~= "table" then return nil end
    return have[A.ENCHANTING] == true
end

-- The bag stack of this item, or nil when it is not in your bags.
local function bagStack(client, id)
    if type(client.bagItems) ~= "function" then return nil end
    local ok, rows = pcall(client.bagItems)
    if not ok or type(rows) ~= "table" then return nil end
    for _, row in ipairs(rows) do
        if type(row) == "table" and ns.Items.Id(row.item) == id then return row end
    end
    return nil
end

function A.Declare(k)
    local api = {}
    local cancel, hooked = nil, false
    function api.hooked() return hooked end

    local function lineFor(ctx, link)
        local client = ctx.client
        local id = ns.Items.Id(link)
        if id == nil or type(client.itemInfo) ~= "function" then return nil end
        local stack = bagStack(client, id)
        if not stack then return nil end
        local info = client.itemInfo(link)
        if type(info) ~= "table" then return nil end
        local bound = nil
        if type(stack.bound) == "boolean" then bound = stack.bound end
        return A.Line({
            quality = info.quality, classID = info.classID, sellPrice = info.sellPrice,
            seen = seenPrice(ctx.store, client, id),
            enchanting = knowsEnchanting(client), bound = bound,
        })
    end

    k:Module({
        name = A.NAME,
        needs = { "client", "store", "settings" },
        start = function(ctx)
            if type(ctx.client.onItemTooltip) ~= "function" then return end
            local got = ctx.client.onItemTooltip(function(link, add)
                if type(add) ~= "function" or ctx.settings:get(ns.DispositionTip.SETTING) == false then return end
                local ok, text = pcall(lineFor, ctx, link)
                if ok and type(text) == "string" then add(text, A.COLOUR[1], A.COLOUR[2], A.COLOUR[3]) end
            end)
            if type(got) == "function" then cancel, hooked = got, true end
        end,
        stop = function()
            if cancel then cancel() end
            cancel, hooked = nil, false
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.auctionOverDE = A.Declare(ns)
