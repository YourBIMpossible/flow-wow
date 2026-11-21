-------------------------------------------------------------------------------
-- Flow - Items/Trader.lua
-- Flow Trader: deals on the auction house, each with a button (0.35.352).
--
-- "Look for arbitrage opportunities ... I can just sit there with the auction
-- house open and it will open up, and as it starts to identify opportunities
-- it can have buttons that I just click to execute the trades."
--
-- When Flow reads every listing of the auction house (it does when you open
-- it, at most every 15 minutes), each listing is checked for two things:
--
--   vendor   it's listed for less than a vendor pays for it. Buy it, sell it
--            to any vendor: the gain is certain, and it's small.
--   resell   it's listed at half or less of what this item has usually gone
--            for when Flow looked (the middle of its price history, from at
--            least four visits). Buy it, post it again: the gain is a guess.
--            The auction house keeps 5% of a sale, and that's taken off; the
--            deposit isn't, and nothing says it will sell.
--
-- Only things Flow wouldn't keep for you are offered (not a material your
-- professions use: a thing bought to sell must be one Flow sells). What you
-- buy comes by mail; from your bags the Flow Seller vendors it or Flow
-- Auctions posts it, by the rules they already go by.
--
-- Nothing is bought without a click, and the game wants a click for each
-- payment anyway:
--   Buy      looks the item up now (the scan may be minutes old) and works
--            out how many are still at or under the price, within what you
--            let Flow spend on one trade (a share of your gold);
--   Confirm  asks the game for the price of that many (stackable things), or
--            buys the next auction (single things);
--   Pay      (stackable things) pays the price the game quoted, if it's
--            still within the limit.
-- If the price moved above the limit meanwhile, the trade is dropped.
--
-- The game's auction calls differ between clients: which ones this one has
-- is in /flow trader and the diagnostics, and a missing one greys the button.
-------------------------------------------------------------------------------

local _, ns = ...
local T = {}
ns.trader = T

T.DEAL = 0.5          -- "resell": at this share of the usual price, or less
T.CUT = 0.05          -- the auction house's share of a sale
T.MIN_LOOKS = 4       -- visits an item's usual price needs
T.MIN_GAIN = 50       -- copper: a trade worth less than this isn't listed
T.SHARE = 0.25        -- of your gold, at most, on one trade
T.ROWS = 10

local CA = C_AuctionHouse

function T.On() return not (ns.db and ns.db.trader and ns.db.trader.off) end
local function money(c) return (ns.auction and ns.auction.Money or ns.Money)(c) end

-------------------------------------------------------------------------------
-- Pure parts
-------------------------------------------------------------------------------

-- The middle price of a flat history { at, price, at, price, ... }, and how
-- many visits it's from; nil with fewer than `min`.
function T.Usual(h, min)
    local prices = {}
    for i = 2, #(h or {}), 2 do prices[#prices + 1] = h[i] end
    if #prices < (min or T.MIN_LOOKS) then return nil, #prices end
    table.sort(prices)
    local mid = math.floor((#prices + 1) / 2)
    return (#prices % 2 == 1) and prices[mid] or (prices[mid] + prices[mid + 1]) / 2, #prices
end

-- One listing against an item's two limits. agg: that item's totals so far
-- (nil: none yet). -> agg (made when the listing is a deal), or nil.
--   vendor: what a vendor pays for one; usual: its usual price (either may be nil)
function T.Listing(agg, count, buyout, vendor, usual)
    if not (count and buyout) or count <= 0 or buyout <= 0 then return agg end
    local unit = buyout / count
    local underVendor = vendor and vendor > 0 and unit < vendor
    local underUsual = usual and usual > 0 and unit <= usual * T.DEAL
    if not (underVendor or underUsual) then return agg end
    agg = agg or { vq = 0, vc = 0, dq = 0, dc = 0, vendor = vendor, usual = usual }
    if underVendor then agg.vq, agg.vc = agg.vq + count, agg.vc + buyout end
    if underUsual then agg.dq, agg.dc = agg.dq + count, agg.dc + buyout end
    return agg
end

-- The deals, the most gain first. aggs: { [itemID] = agg }; name(id) -> name;
-- ok(id) -> may this item be traded (false: Flow keeps it for you).
--   -> { { id, name, kind = "vendor" | "resell", qty, cost, gain, limit } }
-- A vendor deal is listed for an item when there is one (certain beats a guess).
function T.Deals(aggs, name, ok, minGain)
    local out = {}
    for id, a in pairs(aggs or {}) do
        if not ok or ok(id) then
            local row
            if a.vq > 0 then
                row = { id = id, kind = "vendor", qty = a.vq, cost = a.vc, gain = a.vendor * a.vq - a.vc, limit = a.vendor }
            elseif a.dq > 0 then
                row = { id = id, kind = "resell", qty = a.dq, cost = a.dc,
                        gain = a.usual * (1 - T.CUT) * a.dq - a.dc, limit = a.usual * T.DEAL, usual = a.usual }
            end
            if row and row.gain >= (minGain or T.MIN_GAIN) then
                row.name = (name and name(id)) or ("item " .. id)
                out[#out + 1] = row
            end
        end
    end
    table.sort(out, function(x, y)
        if x.gain ~= y.gain then return x.gain > y.gain end
        return x.id < y.id
    end)
    return out
end

-- What to buy from an item's listings as they are now. listings: cheapest
-- first, { { unit, qty, auction = id or nil, buyout = n or nil } }; limit:
-- the most to pay for one; budget: copper to spend at most.
-- Stackable things can be bought in part; a single auction is all or nothing.
--   -> { qty, cost, auctions = { { id, buyout } } }
-- max: buy this many at most (a step that needs 8 buys 8; nil: all of them).
function T.Pick(listings, limit, budget, max)
    local pick = { qty = 0, cost = 0, auctions = {} }
    for _, l in ipairs(listings or {}) do
        if not (l.unit and l.qty) or l.unit > limit or l.qty <= 0 then break end
        if max and pick.qty >= max then break end
        local left = (budget or math.huge) - pick.cost
        if l.auction then
            local price = l.buyout or (l.unit * l.qty)
            if price <= left then
                pick.qty, pick.cost = pick.qty + l.qty, pick.cost + price
                pick.auctions[#pick.auctions + 1] = { id = l.auction, buyout = price }
            end
        else
            local n = math.min(l.qty, math.floor(left / l.unit), max and (max - pick.qty) or l.qty)
            if n <= 0 then break end
            pick.qty, pick.cost = pick.qty + n, pick.cost + n * l.unit
        end
    end
    return pick
end

-- What your route has you buy at the auction house (0.35.353). "The route is
-- telling me to go to the auction house and buy 8 Dig Rats ... it'd be really
-- nice if Flow had a button that would search for that item right away, since
-- it's part of my current objective." Those steps head Flow Trader's list,
-- each with the same Buy button.
T.ROUTE_OVER = 3   -- a step's item is bought at up to this many times the price Flow last saw
-- Pure: goals: the route's steps. A buy step has kind "buy", its item in the
-- key ("need:2592") or g.item, "Buy 8 Dig Rat ..." as its words, and what it
-- should cost (g.cost, copper; nil: unknown).
--   -> { { id, name, kind = "route", qty, cost, limit, text } }
function T.RouteNeeds(goals)
    local out, seen = {}, {}
    for _, g in ipairs(goals or {}) do
        if g.kind == "buy" and type(g.key) == "string" then
            local id = tonumber(g.key:match("^need:(%d+)$")) or tonumber(g.item)
            local qty, name = tostring(g.text or ""):match("^Buy (%d+) (.-) at the auction house")
            qty = tonumber(qty)
            if id and qty and qty > 0 and not seen[id] then
                seen[id] = true
                local each = (g.cost and g.cost > 0) and (g.cost / qty) or nil
                out[#out + 1] = { id = id, name = name or ("item " .. id), kind = "route", qty = qty, cost = g.cost,
                                  limit = each and each * T.ROUTE_OVER or math.huge, text = g.text, max = qty }
            end
        end
    end
    return out
end
function T.Needs()
    local N = ns.nav
    if not (N and N.Goals) then return {} end
    local ok, rows = pcall(T.RouteNeeds, N:Goals() or {})
    return ok and rows or {}
end
-- The window's lines: what your route needs, then the deals.
function T.Rows()
    local out = T.Needs()
    for _, d in ipairs(T.deals) do out[#out + 1] = d end
    return out
end

-- Pure: a deal's line.
function T.Line(row, coin)
    coin = coin or money
    if row.kind == "route" then
        return string.format("%d x %s  |cff66ccfffor your route|r%s", row.qty, row.name, row.cost and ("  (about " .. coin(row.cost) .. ")") or "")
    end
    if row.kind == "vendor" then
        return string.format("%d x %s for %s: a vendor pays %s  |cff40ff40+%s|r", row.qty, row.name, coin(row.cost), coin(row.limit * row.qty), coin(row.gain))
    end
    return string.format("%d x %s for %s: usually %s each  |cffffd100about +%s|r", row.qty, row.name, coin(row.cost), coin(row.usual), coin(row.gain))
end

-- Pure: the button of a job at its stage, and whether it can be clicked.
function T.Button(job, id, has)
    if not job or job.id ~= id then return "Buy", has.search end
    if job.stage == "search" or job.stage == "quoting" then return "...", false end
    if job.stage == "ready" then
        if job.commodity then return "Confirm", has.commodity end
        return string.format("Buy %d of %d", (job.done or 0) + 1, #job.auctions), has.item
    end
    if job.stage == "quoted" then return "Pay " .. money(job.total or 0), has.commodity end
    return "Buy", has.search
end

-- Pure: copper to spend on one trade.
function T.Budget(gold, share) return math.floor((gold or 0) * (share or T.SHARE)) end

-------------------------------------------------------------------------------
-- Reading the full list (Auction.lua calls these)
-------------------------------------------------------------------------------
local aggs, vendorOf, usualOf = {}, {}, {}
T.deals, T.readAt = {}, nil

local function vendorPrice(id)
    local v = vendorOf[id]
    if v == nil then
        local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        local ok, name, _, _, _, _, _, _, _, _, _, price = pcall(get, id)
        -- (Not loaded: false for this read; the game is asked, the next read has it.)
        v = (ok and name and tonumber(price)) or false
        if not (ok and name) and C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
        vendorOf[id] = v
    end
    return v or nil
end
local function usualPrice(id)
    local u = usualOf[id]
    if u == nil then
        local prices = ns.auction and ns.auction.Prices and ns.auction:Prices() or {}
        local e = prices[id]
        u = (e and e.h and T.Usual(e.h)) or false
        usualOf[id] = u
    end
    return u or nil
end
function T.ReadStart()
    wipe(aggs); wipe(vendorOf); wipe(usualOf)
end
function T.ReadListing(id, count, buyout)
    aggs[id] = T.Listing(aggs[id], count, buyout, vendorPrice(id), usualPrice(id))
end
local function nameOf(id)
    local ok, name = pcall(function() return ns.api.ItemInfo and ns.api.ItemInfo(id) end)
    return ok and type(name) == "string" and name or nil
end
-- May Flow trade this item for you? Not one it keeps (a material, a quest thing).
function T.Tradable(id)
    local D = ns.disposition
    if not (D and D.DecideId) then return true end
    local ok, v = pcall(D.DecideId, D, id)
    if not ok or type(v) ~= "table" then return true end
    return v.action ~= "keep" and v.action ~= "equip"
end
function T.ReadDone()
    T.deals = T.Deals(aggs, nameOf, T.Tradable)
    T.readAt = time()
    ns:Log("trader", string.format("full scan: %d deal(s)", #T.deals))
    if #T.deals > 0 and T.On() then
        local best = T.deals[1]
        ns:Print(string.format("Flow Trader: %d deal(s) on the auction house; the best: %s", #T.deals, T.Line(best)))
        if T.OpensWithDeals() then T:Show() end
    end
    if T.frame and T.frame:IsShown() then T:Fill() end
end

-------------------------------------------------------------------------------
-- Buying: a click a step
-------------------------------------------------------------------------------
T.job = nil
local ahOpen = false

-- The calls this client has.
function T.Has()
    return {
        search = CA ~= nil and CA.SendSearchQuery ~= nil and CA.MakeItemKey ~= nil,
        commodity = CA ~= nil and CA.StartCommoditiesPurchase ~= nil and CA.ConfirmCommoditiesPurchase ~= nil,
        item = CA ~= nil and CA.PlaceBid ~= nil,
    }
end

local function drop(why)
    if T.job and T.job.stage == "quoted" and CA and CA.CancelCommoditiesPurchase then pcall(CA.CancelCommoditiesPurchase) end
    if why then ns:Print("Flow Trader: " .. why) end
    T.job = nil
    if T.frame and T.frame:IsShown() then T:Fill() end
end

local function budget() return T.Budget(GetMoney and GetMoney() or 0, ns.db.trader and ns.db.trader.share) end

-- The button of a deal was clicked.
function T:Click(row)
    if not (row and ahOpen) then return false end
    local has = T.Has()
    local job = T.job
    if not job or job.id ~= row.id then
        -- Buy: look it up now.
        if not has.search then return false end
        if ns.auction and ns.auction.Busy and ns.auction.Busy() then
            ns:Print("Flow Trader: Flow is still reading prices; try again in a moment.")
            return false
        end
        if job then drop(nil) end
        local okK, key = pcall(CA.MakeItemKey, row.id)
        if not (okK and key) then return false end
        T.job = { id = row.id, name = row.name, kind = row.kind, limit = row.limit, max = row.max, stage = "search", key = key, at = GetTime() }
        local ok, err = pcall(CA.SendSearchQuery, key, {}, false)
        ns:Log("trader", string.format("search %s [%d]: %s", tostring(row.name), row.id, ok and "sent" or tostring(err)))
        if not ok then drop("the game refused the search.") return false end
        local mine = T.job
        C_Timer.After(6, function() if T.job == mine and mine.stage == "search" then drop("no answer from the auction house for " .. tostring(mine.name) .. ".") end end)
        T:Fill()
        return true
    end
    if job.stage == "ready" and job.commodity then
        if not has.commodity then return false end
        local ok, err = pcall(CA.StartCommoditiesPurchase, job.id, job.qty)
        ns:Log("trader", string.format("quote for %d x %s: %s", job.qty, tostring(job.name), ok and "asked" or tostring(err)))
        if not ok then drop("the game refused to quote a price.") return false end
        job.stage = "quoting"
        C_Timer.After(6, function() if T.job == job and job.stage == "quoting" then drop("the game gave no price for " .. tostring(job.name) .. ".") end end)
        T:Fill()
        return true
    elseif job.stage == "quoted" then
        local ok, err = pcall(CA.ConfirmCommoditiesPurchase, job.id, job.qty)
        ns:Log("trader", string.format("pay %s for %d x %s: %s", money(job.total or 0), job.qty, tostring(job.name), ok and "sent" or tostring(err)))
        if not ok then drop("the game refused the purchase.") return false end
        job.stage = "paying"
        T:Fill()
        return true
    elseif job.stage == "ready" then
        if not has.item then return false end
        local a = job.auctions[(job.done or 0) + 1]
        if not a then drop(nil) return false end
        local ok, err = pcall(CA.PlaceBid, a.id, a.buyout)
        ns:Log("trader", string.format("buyout %s for %s: %s", money(a.buyout), tostring(job.name), ok and "sent" or tostring(err)))
        if not ok then drop("the game refused the buyout.") return false end
        job.done = (job.done or 0) + 1
        job.spent = (job.spent or 0) + a.buyout
        if job.done >= #job.auctions then
            ns:Print(string.format("Flow Trader: bought %s for %s. It comes by mail.", tostring(job.name), money(job.spent)))
            T:Bought(job.id)
            T.job = nil
        end
        T:Fill()
        return true
    end
    return false
end

-- A deal that's been taken leaves the list.
function T:Bought(id)
    for i, r in ipairs(T.deals) do if r.id == id then table.remove(T.deals, i) break end end
end

-- The search answered: what's still at or under the limit?
local function results(listings, commodity)
    local job = T.job
    if not (job and job.stage == "search") then return end
    -- (A step on your route may take all your gold: it's what you came for.)
    local pick = T.Pick(listings, job.limit, job.kind == "route" and (GetMoney and GetMoney() or 0) or budget(), job.max)
    if pick.qty <= 0 then
        local first = listings[1]
        drop(first and string.format("%s is at %s each now, over your limit of %s: gone.", tostring(job.name), money(first.unit), money(job.limit))
            or (tostring(job.name) .. " isn't listed any more."))
        T:Bought(job.id)
        if T.frame and T.frame:IsShown() then T:Fill() end
        return
    end
    job.stage, job.commodity, job.qty, job.cost, job.auctions = "ready", commodity, pick.qty, pick.cost, pick.auctions
    ns:Log("trader", string.format("%s: %d at or under %s for %s (%s)", tostring(job.name), pick.qty, money(job.limit), money(pick.cost), commodity and "stackable" or "single"))
    if T.frame and T.frame:IsShown() then T:Fill() end
end
ns:On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
    local job = T.job
    if not (job and job.stage == "search" and CA and CA.GetNumCommoditySearchResults) then return end
    if itemID and itemID ~= job.id then return end
    local okN, n = pcall(CA.GetNumCommoditySearchResults, job.id)
    local list = {}
    for i = 1, math.min(okN and n or 0, 40) do
        local ok, r = pcall(CA.GetCommoditySearchResultInfo, job.id, i)
        if ok and type(r) == "table" and r.unitPrice and r.quantity then list[#list + 1] = { unit = r.unitPrice, qty = r.quantity } end
    end
    results(list, true)
end)
ns:On("ITEM_SEARCH_RESULTS_UPDATED", function()
    local job = T.job
    if not (job and job.stage == "search" and CA and CA.GetNumItemSearchResults) then return end
    local okN, n = pcall(CA.GetNumItemSearchResults, job.key)
    local list = {}
    for i = 1, math.min(okN and n or 0, 40) do
        local ok, r = pcall(CA.GetItemSearchResultInfo, job.key, i)
        if ok and type(r) == "table" and r.auctionID and (r.buyoutAmount or 0) > 0 then
            local qty = r.quantity or 1
            list[#list + 1] = { unit = r.buyoutAmount / qty, qty = qty, auction = r.auctionID, buyout = r.buyoutAmount }
        end
    end
    table.sort(list, function(a, b) return a.unit < b.unit end)
    results(list, false)
end)
ns:On("COMMODITY_PRICE_UPDATED", function(_, total)
    local job = T.job
    if not (job and job.stage == "quoting") then return end
    total = tonumber(total) or 0
    if total <= 0 or total > job.limit * job.qty + 1 then
        drop(string.format("the price of %s moved: %s for %d is over your limit. Not bought.", tostring(job.name), money(total), job.qty))
        return
    end
    job.stage, job.total = "quoted", total
    if T.frame and T.frame:IsShown() then T:Fill() end
end)
ns:On("COMMODITY_PURCHASE_SUCCEEDED", function()
    local job = T.job
    if not (job and job.stage == "paying") then return end
    ns:Print(string.format("Flow Trader: bought %d x %s for %s. It comes by mail.", job.qty, tostring(job.name), money(job.total or 0)))
    T:Bought(job.id)
    T.job = nil
    if T.frame and T.frame:IsShown() then T:Fill() end
end)
ns:On("COMMODITY_PURCHASE_FAILED", function()
    if T.job and (T.job.stage == "paying" or T.job.stage == "quoting") then drop("the purchase of " .. tostring(T.job.name) .. " failed (someone was quicker, or the price changed).") end
end)
ns:On("AUCTION_HOUSE_SHOW", function()
    ahOpen = true
    -- Your route sent you here to buy something: the window opens on it.
    C_Timer.After(0.8, function()
        if ahOpen and T.On() and T.OpensWithDeals() and #T.Needs() > 0 then T:Show() end
    end)
end)
ns:On("AUCTION_HOUSE_CLOSED", function()
    ahOpen = false
    if T.job then drop(nil) end
    if T.frame then T.frame:Hide() end
end)

-------------------------------------------------------------------------------
-- The window
-------------------------------------------------------------------------------
local function build()
    local f = CreateFrame("Frame", "FlowTrader", UIParent)
    f:SetSize(520, 86 + T.ROWS * 22)
    f:SetFrameStrata("DIALOG")
    f:SetPoint("CENTER", UIParent, "CENTER", 420, 40)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.05, 0.05, 0.08, 0.94)
    f.head = ns.theme:TitleBar(f, "Flow Trader", "Interface\\Icons\\INV_Misc_Coin_02")
    f:EnableMouse(true)
    local p = ns.db.trader.point
    if p then f:ClearAllPoints(); f:SetPoint(p[1], UIParent, p[2], p[3], p[4]) end
    ns:MakeMovable(f, setmetatable({}, { __newindex = function(_, key, v)
        if key == "point" then ns.db.trader.point = v end end }), true)
    tinsert(UISpecialFrames, "FlowTrader")
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)   -- (our own: the game's handler can't close an add-on window in a fight)
    f.note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.note:SetPoint("TOPLEFT", 10, -30); f.note:SetPoint("TOPRIGHT", -10, -30)
    f.note:SetJustifyH("LEFT")
    f.rows = {}
    for i = 1, T.ROWS do
        local r = CreateFrame("Frame", nil, f)
        r:SetHeight(20)
        r:SetPoint("TOPLEFT", f.note, "BOTTOMLEFT", 0, -8 - (i - 1) * 22)
        r:SetPoint("TOPRIGHT", f.note, "BOTTOMRIGHT", 0, -8 - (i - 1) * 22)
        r.btn = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        r.btn:SetSize(96, 20)
        r.btn:SetPoint("RIGHT", 0, 0)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT"); r.text:SetPoint("RIGHT", r.btn, "LEFT", -6, 0)
        r.text:SetJustifyH("LEFT"); r.text:SetWordWrap(false)
        r.btn:SetScript("OnClick", function() T:Click(r.deal) end)
        r.btn:SetScript("OnEnter", function(self)
            local d = r.deal
            if not d then return end
            ns.Tip(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(d.name, 1, 1, 1)
            for _, l in ipairs(T.Tip(d, T.job)) do GameTooltip:AddLine(l, 0.8, 0.8, 0.8, true) end
            GameTooltip:Show()
        end)
        r.btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        r:Hide()
        f.rows[i] = r
    end
    f.foot = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.foot:SetPoint("BOTTOMLEFT", 10, 8); f.foot:SetPoint("BOTTOMRIGHT", -10, 8)
    f.foot:SetJustifyH("LEFT")
    f:Hide()
    return f
end

-- Pure: a deal's tooltip.
function T.Tip(d, job)
    local out = {}
    if d.kind == "route" then
        out[#out + 1] = "A step on your route: " .. tostring(d.text or "buy it at the auction house") .. "."
        out[#out + 1] = d.cost and string.format("Flow buys the %d cheapest, at up to %d times the price it last saw (%s each at most).", d.qty, T.ROUTE_OVER, money(d.limit))
            or string.format("Flow buys the %d cheapest. It has seen no price for this, so look at the sum before you pay.", d.qty)
        if job and job.id == d.id and job.stage == "ready" then out[#out + 1] = string.format("Now: %d for %s.", job.qty or 0, money(job.cost or 0)) end
        return out
    end
    if d.kind == "vendor" then
        out[#out + 1] = string.format("Listed under what a vendor pays (%s each). Buy it, sell it to any vendor: the gain is certain.", money(d.limit))
    else
        out[#out + 1] = string.format("Listed at half or less of its usual price here (%s each, from Flow's own looks). Buy it and post it again: a guess, not a promise.", money(d.usual))
        out[#out + 1] = "The auction house's 5% is taken off the gain; the deposit isn't, and it may not sell."
    end
    out[#out + 1] = string.format("Flow pays at most %s each, and spends at most %d%% of your gold on one trade.", money(d.limit), math.floor(((ns.db.trader and ns.db.trader.share) or T.SHARE) * 100))
    if job and job.id == d.id and job.stage == "ready" then
        out[#out + 1] = string.format("Now: %d at or under that, for %s.", job.qty or 0, money(job.cost or 0))
    end
    return out
end

function T:Fill()
    local f = T.frame
    if not f then return end
    local has = T.Has()
    local rows = T.Rows()
    local n = #rows
    local route = 0
    for _, r in ipairs(rows) do if r.kind == "route" then route = route + 1 end end
    if route > 0 then
        f.note:SetText(string.format("Your route has you buy %d thing(s) here: Buy looks it up, then you confirm and pay.%s", route,
            n > route and string.format(" Below: %d deal(s) from Flow's last read.", n - route) or ""))
    elseif not T.readAt then
        f.note:SetText("No full read of the auction house yet this session. Flow reads every listing when you open it (at most every 15 minutes); /flow ah scan asks now.")
    elseif n == 0 then
        f.note:SetText(string.format("No deals in the last read (%s). Flow looks for listings under the vendor's price, and at half an item's usual price or less.", ns.banker and ns.banker.Ago(time() - T.readAt) or "just now"))
    else
        f.note:SetText(string.format("%d deal(s) from the read %s. Each needs your clicks: Buy looks it up again, then you confirm.", n, ns.banker and ns.banker.Ago(time() - T.readAt) or "just now"))
    end
    for i = 1, T.ROWS do
        local r, d = f.rows[i], rows[i]
        r.deal = d
        if d then
            r.text:SetText(T.Line(d))
            local label, can = T.Button(T.job, d.id, has)
            r.btn:SetText(label)
            r.btn:SetEnabled(can and ahOpen and true or false)
            r:Show()
        else
            r:Hide()
        end
    end
    f.foot:SetText(n > T.ROWS and string.format("... and %d more after these.", n - T.ROWS)
        or (not has.search and "This client has no auction search Flow can use: the list is to read, not to click.") or "")
end

function T:Show()
    if not ns.db.trader then return end
    T.frame = T.frame or build()
    T:Fill()
    T.frame:Show()
end
function T:Toggle()
    if T.frame and T.frame:IsShown() then T.frame:Hide() return end
    T:Show()
end
function T._Frame() return T.frame end

ns:Register("gameButton", "auctiontrader", {
    order = 61,
    frames = { "AuctionHouseFrame", "AuctionFrame" },
    label = "Flow Trader",
    x = -170,
    tip = "Listings under a vendor's price, or at half an item's usual price or less, from Flow's last read of the auction house. A button buys each; every payment is your click.",
    isOpen = function() return T.frame ~= nil and T.frame:IsShown() end,
    click = function() T:Toggle() end,
})

ns:OnLoad(function(saved) saved.trader = saved.trader or {} end)

-- Does the window open with the deals it finds? (Your choice, as you saved
-- it: "on" is kept as quiet = false, not dropped, so a later default can't
-- take it from you. Unset: it opens.)
function T.OpensWithDeals() return not (ns.db and ns.db.trader and ns.db.trader.quiet) end
function T.SetOpensWithDeals(on)
    ns.db.trader = ns.db.trader or {}
    ns.db.trader.quiet = not on
end

function T.Lines()
    local has = T.Has()
    local out = { string.format("Flow Trader%s: %d deal(s)%s", T.On() and "" or " (off)", #T.deals,
        T.readAt and (", read " .. (ns.banker and ns.banker.Ago(time() - T.readAt) or "?")) or ", no full read yet this session") }
    out[#out + 1] = string.format("  this client: search %s, buy stackable things %s, buy single auctions %s", has.search and "yes" or "no", has.commodity and "yes" or "no", has.item and "yes" or "no")
    out[#out + 1] = string.format("  at most %d%% of your gold on a trade; resell at %d%% of the usual price or less, from %d visits", math.floor(((ns.db.trader and ns.db.trader.share) or T.SHARE) * 100), T.DEAL * 100, T.MIN_LOOKS)
    for i = 1, math.min(8, #T.deals) do out[#out + 1] = "  " .. T.Line(T.deals[i]):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "") end
    if T.job then out[#out + 1] = string.format("  in hand: %s, %s", tostring(T.job.name), tostring(T.job.stage)) end
    return out
end
ns.commands.trader = function(arg)
    arg = (arg or ""):lower()
    if arg == "on" or arg == "off" then
        ns.db.trader.off = (arg == "off") or nil
        ns:Print("Flow Trader " .. arg)
        return
    end
    if arg == "show" then T:Show() return end
    local share = tonumber(arg:match("^share%s+(%d+)"))
    if share and share >= 1 and share <= 100 then
        ns.db.trader.share = share / 100
        ns:Print(string.format("Flow Trader spends at most %d%% of your gold on one trade.", share))
        return
    end
    for i, l in ipairs(T.Lines()) do if i == 1 then ns:Print(l) else print(l) end end
    print("  /flow trader show   /flow trader share <1-100>   /flow trader on|off")
end
ns:Register("help", "trader", { order = 61, title = "Flow Trader", lines = {
    "When Flow reads the auction house's listings it looks for two kinds of deal: listed under what a vendor pays (a certain, small gain), and listed at half an item's usual price or less (a guess: buy and post again).",
    "The Flow Trader tab on the auction house lists them, each with a button. Buy looks the item up again; then you confirm and pay. Flow never buys without your click, pays at most the limit, and spends at most a quarter of your gold on one trade (/flow trader share).",
    "Only things Flow wouldn't keep for you are offered. What you buy comes by mail; the Flow Seller and Flow Auctions sell it by their usual rules.",
} })

if ns.settings and ns.settings.AddCheck then
    ns.settings:AddCheck({
        group = "loot",
        label = "Flow Trader: open with the deals it finds",
        note = "(at the auction house)",
        tip = "After Flow reads the auction house's listings, the Flow Trader window opens when it found deals: listings under a vendor's price, or at half an item's usual price or less. "
            .. "Off: it stays closed (its tab on the auction house opens it), and Flow still says in chat how many it found.",
        get = T.OpensWithDeals,
        set = T.SetOpensWithDeals,
    })
end
