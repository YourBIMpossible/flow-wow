local _, ns = ...

-- Merchant prices read when the window opens (Items/PriceWatch.lua, through
-- Items/PriceObserve.lua), end to end, on the whole add-on loaded on a fake
-- client. The real entry: MERCHANT_SHOW (c.setMerchantOpen(true)). Nothing
-- is printed by the reading; what the player sees is the price word
-- (<slash> price <item>) saying what a merchant sells it for, and the
-- price kept for the next session. Only reads: nothing is bought, sold or
-- equipped. Made-up merchant rows. Not tested in game.

local tests = {}

local THREAD, FLUX, VIAL = 2320, 2880, 3371
local INFO = {
    [THREAD] = { name = "Coarse Thread", quality = 1, sellPrice = 2, classID = 7 },
    [FLUX] = { name = "Weak Flux", quality = 1, sellPrice = 25, classID = 7 },
    [VIAL] = { name = "Empty Vial", quality = 1, sellPrice = 1, classID = 7 },
}
local NOW = 1700000000

-- opts.clock: false for a client that gives no clock; opts.account: saved.
local function boot(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.account or {})
    c.setSaved(ns.id.charDB, {})
    c.setScreen(1024, 768)
    if opts.clock ~= false then c.setClock(NOW) end
    c.setItemInfo(INFO)
    c.setBagItems({ { item = THREAD, count = 1 } })
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

local function T(text) return ns.id.title .. ": " .. text end

local function say(c, text)
    for i = #c.printed, 1, -1 do c.printed[i] = nil end
    c.slashes[ns.id.slash](text)
    local out = {}
    for i, l in ipairs(c.printed) do out[i] = l end
    return out
end

local function visit(c, rows)
    c.setMerchant(rows)
    c.setMerchantOpen(true)
    c.setMerchantOpen(false)
end

local function vendorBook(c)
    local a = c.saved(ns.id.accountDB)
    return a.learned and a.learned.prices and a.learned.prices.vendor or nil
end

local function noneActs(t, c)
    t.eq(#c.soldSlots, 0, "nothing sold")
    t.eq(c.equipCalls, 0, "nothing equipped")
end

tests["price watch e2e: opening a merchant keeps its prices"] = function(t)
    local c = boot()
    visit(c, {
        { index = 1, item = THREAD, price = 50, stack = 5 },
        { index = 2, item = FLUX, price = 100, stack = 1 },
    })
    t.eq(say(c, "price " .. THREAD)[2], T("A merchant sells it for 10c each, 5 at a time (merchant window)"))
    t.eq(say(c, "price " .. FLUX)[2], T("A merchant sells it for 1s each (merchant window)"))
    local book = vendorBook(c)
    t.eq(book and book[FLUX] and book[FLUX].seenAt, NOW, "dated with the client clock")
    noneActs(t, c)
end

tests["price watch e2e: the price is kept for the next session"] = function(t)
    local c = boot()
    visit(c, { { index = 1, item = FLUX, price = 100, stack = 1 } })
    local c2 = boot({ account = c.saved(ns.id.accountDB) })
    t.eq(say(c2, "price " .. FLUX)[2], T("A merchant sells it for 1s each (merchant window)"))
end

tests["price watch e2e: a later visit's price replaces the older one"] = function(t)
    local c = boot()
    visit(c, { { index = 1, item = FLUX, price = 100, stack = 1 } })
    c.setClock(NOW + 60)
    visit(c, { { index = 1, item = FLUX, price = 120, stack = 1 } })
    t.eq(say(c, "price " .. FLUX)[2], T("A merchant sells it for 1s 20c each (merchant window)"))
end

tests["price watch e2e: unknown prices are left out, never kept as 0"] = function(t)
    local c = boot()
    visit(c, {
        { index = 1, item = THREAD, price = 0, stack = 1 },           -- paid in something else
        { index = 2, item = FLUX, price = 100, stack = 1, other = true }, -- not in coin
        { index = 3, item = VIAL, price = nil, stack = 1 },          -- price not read
        { index = 4, item = nil, price = 30, stack = 1 },            -- item not read
    })
    t.eq(#say(c, "price " .. THREAD), 1, "no merchant line for a 0 price")
    t.eq(#say(c, "price " .. FLUX), 1, "no merchant line for a price not in coin")
    t.eq(#say(c, "price " .. VIAL), 1, "no merchant line for a price not read")
    local book = vendorBook(c)
    t.ok(book == nil or next(book) == nil, "nothing kept")
    -- No clock: nothing can be dated, so nothing is kept.
    local c2 = boot({ clock = false })
    visit(c2, { { index = 1, item = FLUX, price = 100, stack = 1 } })
    t.eq(#say(c2, "price " .. FLUX), 1, "no clock: no merchant line")
    -- A window that cannot be read keeps nothing.
    local c3 = boot()
    visit(c3, nil)
    t.eq(#say(c3, "price " .. FLUX), 1, "an unread window: no merchant line")
    noneActs(t, c3)
end

return tests
