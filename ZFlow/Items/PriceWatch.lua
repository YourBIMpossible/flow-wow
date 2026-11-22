local _, ns = ...

-- PriceWatch: the module that reads a merchant window when it opens.
--
-- On each MERCHANT_SHOW (through the kernel's bus) the open window is read
-- once into the saved price book, dated with the client's wall clock:
-- PriceObserve.FromClient(client, PriceObserve.Book(store), client.clock()).
-- Nothing is printed. With no book or no clock nothing is recorded, and the
-- report kept here says why.
--
--   PriceWatch.Show(client, store) -> report     one reading; what the module runs
--   PriceWatch.Declare(k)          -> api        declares the module on kernel k
--     api.last()   the report of the last show, nil before the first
--     api.shows()  how many shows were read since the start
--   ns.use(PriceWatch.NAME) -> { Last = api.last, Shows = api.shows }
--
--   report = what PriceObserve.FromClient gives ({ ok, reason, recorded,
--            skipped }) plus seenAt, the date stamped (nil when not known).
--
-- The date is client.clock(): the same clock in every session, so a reading
-- of a later session is never taken for an older one. client.now() starts
-- again with the client and is not used.
--
-- This only reads. Nothing here or in what it calls buys, sells or clicks.
-- Not tested in game: MERCHANT_SHOW and the clock read are first guesses.

local PriceWatch = ns.PriceWatch or {}
ns.PriceWatch = PriceWatch

PriceWatch.NAME = "priceWatch"
PriceWatch.EVENT = "MERCHANT_SHOW"

local NO_DATE_READ = "this client has no clock read"
local NO_OBSERVE = "the price reading is not loaded"

-- One reading of the open merchant window into the store's price book.
function PriceWatch.Show(client, store)
    local Observe = ns.PriceObserve
    if type(Observe) ~= "table" then
        return { ok = false, reason = NO_OBSERVE, recorded = {}, skipped = {} }
    end
    local seenAt
    if type(client) == "table" and type(client.clock) == "function" then
        seenAt = client.clock()
        if type(seenAt) ~= "number" or seenAt ~= seenAt then seenAt = nil end
    elseif type(client) == "table" and type(client.merchantItems) == "function" then
        return { ok = false, reason = NO_DATE_READ, recorded = {}, skipped = {} }
    end
    local report = Observe.FromClient(client, Observe.Book(store), seenAt)
    report.seenAt = seenAt
    return report
end

-- Declares the module on kernel k. Usable at once: before the first show
-- last() is nil and shows() is 0.
function PriceWatch.Declare(k)
    local api = {}
    local last, shows = nil, 0
    function api.last() return last end
    function api.shows() return shows end
    k:Module({
        name = PriceWatch.NAME,
        needs = { "client", "store", "bus" },
        provides = { Last = api.last, Shows = api.shows },
        -- The handler is registered here, after watchMerchant(), and not in
        -- `events`: the client then hears the event before this does, so
        -- the window is known to be open when it is read. That order holds
        -- only while priceWatch is the only subscriber of that bus event:
        -- the client listener is attached by the first bus:on for the
        -- event, so an earlier subscriber (any module, or `events`) would
        -- attach it before watchMerchant() and this would run first.
        start = function(ctx)
            if type(ctx.client.watchMerchant) == "function" then ctx.client.watchMerchant() end
            ctx.bus:on(PriceWatch.NAME, PriceWatch.EVENT, function()
                shows = shows + 1
                last = PriceWatch.Show(ctx.client, ctx.store)
            end)
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.priceWatch = PriceWatch.Declare(ns)
