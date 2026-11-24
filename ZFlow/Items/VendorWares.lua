local _, ns = ...

-- VendorWares (queue item A5, G20/G7): which vendor sold what, and where.
-- The price book (Items/PriceObserve.lua) keeps a vendor price without the
-- vendor, so the profession plan could only say "from a vendor". This saves,
-- for each item a merchant window showed, the vendor's name and where the
-- player stood, so the plan (Items/ProfSources.lua) can name the vendor and
-- give the arrow a place. The same pattern as Nav/ServiceSeen.lua: only what
-- this client showed, nothing authored, nothing printed. It only reads; it
-- opens no window, talks to no one and buys nothing.
--
-- Saved per character (a vendor of the other side is no use to this one),
-- char "learned.vendorWares"[itemKey][vendorName] = { map, x, y, seen }
-- itemKey is Items.Key of the row's link. map, x, y are client.position()
-- at MERCHANT_SHOW: beside the vendor, not on it. seen is client.clock(),
-- left out when the clock is not known.
--
-- Bounds: an item keeps VendorWares.PER_ITEM vendors (the one seen longest
-- ago goes first), and a new item past VendorWares.MAX items is not
-- written. With no vendor name or no position nothing is written at all. A
-- store that refuses the write is left as it was.
--
--   VendorWares.Read(client, store) -> report   one merchant window read
--     report = { ok, reason (when not ok), npc, recorded (how many items) }
--   VendorWares.Of(wares, item, here) -> { npc, map, x, y, seen } or nil
--     the vendor to send the player to: the nearest on the map the player
--     is on, else the one seen last. here = { map, x, y } or nil.
--   VendorWares.Declare(k) -> api;  api.last() the last report
--   ns.use(VendorWares.NAME) -> { Last = api.last }
--
-- Not tested in game: MERCHANT_SHOW, client.serviceNpc() naming the open
-- merchant and client.merchantItems() are the reads PriceWatch and
-- ServiceSeen already use, and are first guesses there too.

local VendorWares = ns.VendorWares or {}
ns.VendorWares = VendorWares

VendorWares.NAME = "vendorWares"
VendorWares.EVENT = "MERCHANT_SHOW"
VendorWares.PATH = "learned.vendorWares"
VendorWares.MAX = 600
VendorWares.PER_ITEM = 3

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function text(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

local function ask(client, read)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    return client[read]()
end

local function refuse(report, reason)
    report.ok, report.reason = false, reason
    return report
end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- The vendor of an item seen longest ago; one with no date goes first.
local function oldest(vendors)
    local name, at
    for npc, e in pairs(vendors) do
        local seen = type(e) == "table" and finite(e.seen) and e.seen or -math.huge
        if name == nil or seen < at or (seen == at and tostring(npc) < tostring(name)) then
            name, at = npc, seen
        end
    end
    return name
end

function VendorWares.Read(client, store)
    local report = { ok = false, recorded = 0 }
    -- Every read comes before the first write.
    local npc = ask(client, "serviceNpc")
    local name = type(npc) == "table" and text(npc.name) or nil
    if not name then return refuse(report, "the vendor is not known") end
    report.npc = name
    local pos = ask(client, "position")
    if type(pos) ~= "table" or not (finite(pos.map) and finite(pos.x) and finite(pos.y)) then
        return refuse(report, "the position is not known")
    end
    local rows = ask(client, "merchantItems")
    if type(rows) ~= "table" then return refuse(report, "the wares cannot be read") end
    local now = ask(client, "clock")
    if not finite(now) then now = nil end
    local keyOf = ns.Items and ns.Items.Key
    if type(keyOf) ~= "function" then return refuse(report, "the item keys are not loaded") end

    if type(store) ~= "table" or type(store.get) ~= "function" or type(store.set) ~= "function" then
        return refuse(report, "the wares cannot be saved")
    end
    local old = store:get("char", VendorWares.PATH)
    if old ~= nil and type(old) ~= "table" then return refuse(report, "the wares cannot be saved") end

    -- A copy is built and saved whole, so a refused write changes nothing.
    local wares = {}
    for item, vendors in pairs(old or {}) do
        if type(vendors) == "table" then
            local copy = {}
            for who, e in pairs(vendors) do copy[who] = e end
            wares[item] = copy
        end
    end
    local items = count(wares)
    for _, row in ipairs(rows) do
        local key = type(row) == "table" and keyOf(row.item) or nil
        if key ~= nil then
            local vendors = wares[key]
            if vendors == nil and items < VendorWares.MAX then
                vendors = {}
                wares[key] = vendors
                items = items + 1
            end
            if vendors ~= nil then
                if vendors[name] == nil then
                    while count(vendors) >= VendorWares.PER_ITEM do vendors[oldest(vendors)] = nil end
                end
                local e = { map = pos.map, x = pos.x, y = pos.y, seen = now }
                if now == nil and type(vendors[name]) == "table" then e.seen = vendors[name].seen end
                vendors[name] = e
                report.recorded = report.recorded + 1
            end
        end
    end
    if report.recorded == 0 then return refuse(report, "nothing to save") end
    if store:set("char", VendorWares.PATH, wares) ~= true then
        report.recorded = 0
        return refuse(report, "the wares cannot be saved")
    end
    report.ok = true
    return report
end

function VendorWares.Of(wares, item, here)
    if type(wares) ~= "table" or item == nil then return nil end
    local vendors = wares[item]
    if type(vendors) ~= "table" then return nil end
    local onMap = type(here) == "table" and finite(here.map) and finite(here.x) and finite(here.y)
    local best, bestNear, bestD, bestSeen
    for npc, e in pairs(vendors) do
        if text(npc) and type(e) == "table" and finite(e.map) and finite(e.x) and finite(e.y) then
            local near = onMap and e.map == here.map
            local d = near and ((e.x - here.x) ^ 2 + (e.y - here.y) ^ 2) or math.huge
            local seen = finite(e.seen) and e.seen or -math.huge
            local better
            if best == nil then
                better = true
            elseif near ~= bestNear then
                better = near
            elseif near and d ~= bestD then
                better = d < bestD
            elseif seen ~= bestSeen then
                better = seen > bestSeen
            else
                better = npc < best.npc
            end
            if better then
                best = { npc = npc, map = e.map, x = e.x, y = e.y, seen = e.seen }
                bestNear, bestD, bestSeen = near, d, seen
            end
        end
    end
    return best
end

-- Declares the module on kernel k. Usable at once: before the first
-- merchant window last() is nil.
function VendorWares.Declare(k)
    local api = {}
    local last
    function api.last() return last end
    k:Module({
        name = VendorWares.NAME,
        needs = { "client", "store", "bus" },
        provides = { Last = api.last },
        -- Registered here, after the client's own watch, and not in
        -- `events`, so the client hears the window open before this reads
        -- it (the same order as Nav/ServiceSeen.lua).
        start = function(ctx)
            if type(ctx.client.watchMerchant) == "function" then ctx.client.watchMerchant() end
            ctx.bus:on(VendorWares.NAME, VendorWares.EVENT, function()
                last = VendorWares.Read(ctx.client, ctx.store)
            end)
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.vendorWares = VendorWares.Declare(ns)
