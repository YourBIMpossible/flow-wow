local _, ns = ...

-- Tests for ZFlow/Items/PriceWatch.lua: the module over the fake client,
-- one run over the real client with a hand-built environment, and the
-- client's clock read. Not tested in game.

local W = ns.PriceWatch
local P = ns.Prices
local tests = {}

local function stock()
    return {
        { index = 1, item = "item:2318", price = 60, stack = 1, other = false },
        { index = 2, item = "item:2320", price = 50, stack = 5 },
    }
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for key, value in pairs(v) do out[key] = copy(value) end
    return out
end

-- opts: saved, date (false: the client will not say), rows, predecessor,
-- wrap (a function that gives the client the kernel is built over).
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, opts.saved or {})
    if opts.date ~= false then c.setClock(opts.date or 5000) end
    c.setMerchant(opts.rows or stock())
    if opts.predecessor then c.setLoaded(ns.id.predecessor, true) end
    local k = ns.Kernel({}, opts.wrap and opts.wrap(c) or c)
    ns.Diag.Start(k)
    local w = W.Declare(k)
    k:Boot()
    return k, c, w
end

local function login(c)
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
end

-- The saved price book, or an empty one when nothing was saved.
local function book(c)
    local saved = c.saved(ns.id.accountDB)
    local learned = type(saved) == "table" and saved.learned or nil
    local prices = type(learned) == "table" and learned.prices or nil
    return type(prices) == "table" and prices or {}
end

tests["price watch: the module is listed in the kernel and starts at login"] = function(t)
    local k, c, w = start()
    t.eq((k:ModuleState(W.NAME)), "declared")
    t.eq(w.last(), nil)
    t.eq(w.shows(), 0)
    login(c)
    t.eq((k:ModuleState(W.NAME)), "started")
    local provided = k.use(W.NAME)
    t.ok(type(provided) == "table" and provided.Last == w.last and provided.Shows == w.shows,
        "the kept report is not what the module provides")
    t.eq(w.last(), nil, "a report before any show")
    t.eq(book(c), {}, "something was recorded before any show")
    t.ok(type(ns.priceWatch) == "table" and type(ns.priceWatch.last) == "function", "the addon's own is not declared")
    t.ok(ns:ModuleState(W.NAME) ~= nil, "the addon's kernel does not list the module")
end

tests["price watch: a merchant show gives observed book entries"] = function(t)
    local k, c, w = start()
    login(c)
    local said = #c.printed
    c.setMerchantOpen(true)
    t.eq(w.shows(), 1)
    local report = w.last()
    t.eq(report.ok, true, tostring(report.reason))
    t.eq(report.reason, nil)
    t.eq(report.seenAt, 5000)
    t.eq(report.recorded, { { index = 1, key = 2318, value = 60 }, { index = 2, key = 2320, value = 10 } })
    t.eq(book(c), { vendor = {
        [2318] = { value = 60, basis = "observed", source = "merchant window", seenAt = 5000, per = 1 },
        [2320] = { value = 10, basis = "observed", source = "merchant window", seenAt = 5000, per = 5 },
    } })
    t.eq(P.Get(book(c), 2320, "vendor").basis, "observed")
    t.eq(#c.printed, said, "something was printed")
    t.eq((k:ModuleState(W.NAME)), "started")
end

tests["price watch: a second show without new rows changes nothing"] = function(t)
    local _, c, w = start()
    login(c)
    c.setMerchantOpen(true)
    local before = copy(book(c))
    c.setMerchantOpen(false)
    c.setMerchantOpen(true)
    t.eq(w.shows(), 2)
    t.eq(book(c), before, "the same rows on the same date changed the book")
    t.eq(#w.last().recorded, 2)

    -- A merchant with nothing on sale, and a window that cannot be read.
    c.setMerchantOpen(false)
    c.setClock(6000)
    c.setMerchant({})
    c.setMerchantOpen(true)
    t.eq(book(c), before, "an empty window changed the book")
    t.eq(w.last().ok, true)
    t.eq(w.last().reason, "nothing with a price in coin was read")
    c.setMerchantOpen(false)
    c.setMerchant(nil)
    c.setMerchantOpen(true)
    t.eq(book(c), before, "a window that could not be read changed the book")
    t.eq(w.last().ok, false)
    t.eq(w.last().reason, "the merchant window could not be read")
    t.eq(w.shows(), 4)
end

tests["price watch: the same rows on a later date move only the date"] = function(t)
    local _, c, w = start()
    login(c)
    c.setMerchantOpen(true)
    c.setMerchantOpen(false)
    c.setClock(7000)
    c.setMerchantOpen(true)
    t.eq(w.last().seenAt, 7000)
    t.eq(book(c), { vendor = {
        [2318] = { value = 60, basis = "observed", source = "merchant window", seenAt = 7000, per = 1 },
        [2320] = { value = 10, basis = "observed", source = "merchant window", seenAt = 7000, per = 5 },
    } })
end

tests["price watch: the window is read once per show, and never when it closes"] = function(t)
    local reads = 0
    local _, c = start({ wrap = function(real)
        return setmetatable({}, { __index = function(_, name)
            if name ~= "merchantItems" then return real[name] end
            return function()
                reads = reads + 1
                return real.merchantItems()
            end
        end })
    end })
    login(c)
    t.eq(reads, 0, "the window was read before any show")
    c.setMerchantOpen(true)
    t.eq(reads, 1)
    c.setMerchantOpen(false)
    t.eq(reads, 1, "the window was read when it closed")
    c.setMerchantOpen(true)
    t.eq(reads, 2)
    c.advance(5, 10)
    t.eq(reads, 2, "the window was read on a timer")
end

tests["price watch: no date records nothing and the kept report says why"] = function(t)
    local k, c, w = start({ date = false })
    login(c)
    c.setMerchantOpen(true)
    t.eq(w.shows(), 1)
    t.eq(w.last().ok, false)
    t.eq(w.last().reason, "no date for the reading")
    t.eq(w.last().seenAt, nil)
    t.eq(w.last().recorded, {})
    t.eq(book(c), {}, "a reading with no date was recorded")
    t.eq((k:ModuleState(W.NAME)), "started", "no date is not an error of the module")
    -- The uptime clock is there (1000 on the fake) and was not used in its place.
    t.eq(c.now(), 1000)
    c.setMerchantOpen(false)
    c.setClock(5000)
    c.setMerchantOpen(true)
    t.eq(w.last().ok, true, "the next show, with a date, was not read")
    t.eq(P.Get(book(c), 2318, "vendor").seenAt, 5000)
end

tests["price watch: no book records nothing and the kept report says why"] = function(t)
    local saved = { learned = { prices = "broken" } }
    local k, c, w = start({ saved = saved })
    login(c)
    c.setMerchantOpen(true)
    t.eq(w.last().ok, false)
    t.eq(w.last().reason, "no price book")
    t.eq(w.last().recorded, {})
    t.eq(saved.learned.prices, "broken", "what was saved there was replaced")
    t.eq((k:ModuleState(W.NAME)), "started")
end

tests["price watch: one reading, without the kernel"] = function(t)
    local c = ns.make.fakeClient()
    c.setMerchant(stock())
    c.setMerchantOpen(true)
    c.setClock(5000)
    local saved = {}
    local store = { table = function() return saved end }
    local report = W.Show(c, store)
    t.eq(report.ok, true, tostring(report.reason))
    t.eq(report.seenAt, 5000)
    t.eq(P.Get(saved, 2318, "vendor").value, 60)

    local asked = 0
    local noBook = setmetatable({}, { __index = function(_, name)
        if name == "merchantItems" then
            return function()
                asked = asked + 1
                return c.merchantItems()
            end
        end
        return c[name]
    end })
    t.eq(W.Show(noBook, { table = function() return nil end }).reason, "no price book")
    t.eq(W.Show(noBook, nil).reason, "no price book")
    c.setClock(nil)
    t.eq(W.Show(noBook, store).reason, "no date for the reading")
    c.setClock("today")
    t.eq(W.Show(noBook, store).reason, "no date for the reading")
    t.eq(asked, 0, "the window was read with no book or no date to take it")
    t.eq(W.Show({ merchantItems = c.merchantItems }, store).reason, "this client has no clock read")
    t.eq(W.Show(nil, store).reason, "this client has no merchant read")
    t.eq(W.Show({}, store).ok, false)
end

tests["price watch: beside the predecessor nothing is watched or recorded"] = function(t)
    local k, c, w = start({ predecessor = true })
    login(c)
    c.setMerchantOpen(true)
    t.eq((k:ModuleState(W.NAME)), "declared")
    t.eq(w.shows(), 0)
    t.eq(w.last(), nil)
    t.eq(book(c), {})
end

tests["price watch: no buy or sell name is looked up"] = function(t)
    local asked = {}
    local _, c, w = start({ wrap = function(real)
        return setmetatable({}, { __index = function(_, name)
            asked[name] = true
            return real[name]
        end })
    end })
    login(c)
    t.eq(asked.watchMerchant, true, "the module did not start the merchant watch")
    for name in pairs(asked) do asked[name] = nil end
    c.setMerchantOpen(true)
    t.eq(#w.last().recorded, 2, "the read did not go through the watcher")
    t.eq(asked.merchantItems, true)
    t.eq(asked.clock, true)
    for name in pairs(asked) do
        local lower = tostring(name):lower()
        for _, word in ipairs({ "buy", "sell", "pickup", "repair", "click" }) do
            t.ok(not lower:find(word, 1, true), "a client function was asked for: " .. tostring(name))
        end
    end
    for name in pairs(c) do
        local lower = tostring(name):lower()
        t.ok(not lower:find("buy", 1, true) and not lower:find("sell", 1, true),
            "the fake client has a buy or sell function: " .. tostring(name))
    end
end

-- A hand-built game environment: frames for events, a merchant selling
-- one item, a wall clock, and buy / sell functions that count calls.
local function gameEnv()
    local env = { frames = {}, acted = 0 }
    function env.CreateFrame()
        local f = { scripts = {}, events = {} }
        function f:SetScript(name, fn) self.scripts[name] = fn end
        function f:RegisterEvent(event) self.events[event] = true end
        function f:UnregisterEvent(event) self.events[event] = nil end
        env.frames[#env.frames + 1] = f
        return f
    end
    function env.fire(event, ...)
        for _, f in ipairs(env.frames) do
            if f.events[event] and f.scripts.OnEvent then f.scripts.OnEvent(f, event, ...) end
        end
    end
    env.time = function() return 1700000000 end
    env.GetMerchantNumItems = function() return 1 end
    env.GetMerchantItemLink = function() return "item:2318" end
    env.GetMerchantItemInfo = function() return "name", 1, 60, 1, -1, true, true, false end
    return env
end

tests["price watch: over the real client the window is known open when the show is read"] = function(t)
    local real = gameEnv()
    local acts = { "BuyMerchantItem", "BuybackItem", "PickupMerchantItem", "SellCursorItem",
        "UseContainerItem", "PickupContainerItem", "RepairAllItems", "ShowMerchantSellCursor" }
    for _, name in ipairs(acts) do real[name] = function() real.acted = real.acted + 1 end end
    local asked = {}
    local env = setmetatable({}, {
        __index = function(_, name)
            asked[name] = true
            return real[name]
        end,
        __newindex = function(_, name, value) real[name] = value end,
    })
    local c = ns.make.client(env)
    local k = ns.Kernel({}, c)
    local w = W.Declare(k)
    k:Boot()
    real.fire("ADDON_LOADED", ns.id.addon)
    real.fire("PLAYER_LOGIN")
    t.eq((k:ModuleState(W.NAME)), "started")
    for name in pairs(asked) do asked[name] = nil end
    real.fire("MERCHANT_SHOW")
    t.eq(w.shows(), 1)
    t.eq(w.last().ok, true, tostring(w.last().reason))
    t.eq(w.last().seenAt, 1700000000)
    local saved = real[ns.id.accountDB]
    local prices = type(saved) == "table" and type(saved.learned) == "table" and saved.learned.prices or {}
    t.eq(P.Get(prices, 2318, "vendor"),
        { value = 60, basis = "observed", source = "merchant window", seenAt = 1700000000, per = 1 })
    t.eq(real.acted, 0, "a buy, sell or pick-up function was called")
    for _, name in ipairs(acts) do
        t.eq(asked[name], nil, name .. " was looked up")
    end
    real.fire("MERCHANT_CLOSED")
    t.eq(w.shows(), 1, "the close was read as a show")
end

tests["client: the wall clock is time(), or not known"] = function(t)
    local env = {}
    local c = ns.make.client(env)
    t.eq(c.clock(), nil, "a client with no clock gave a time")
    env.time = function() return 1700000000 end
    t.eq(c.clock(), 1700000000)
    env.GetTime = function() return 12.5 end
    t.eq(c.clock(), 1700000000, "the uptime clock was taken for the wall clock")
    for _, bad in ipairs({ 0, -5, "1700000000", 0 / 0, math.huge, true }) do
        env.time = function() return bad end
        t.eq(c.clock(), nil, "taken for a time: " .. tostring(bad))
    end
    env.time = function() return nil end
    t.eq(c.clock(), nil)
    env.time = function() error("no") end
    t.eq(c.clock(), nil)
end

tests["fake client: the wall clock is what the test set, and not known before"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(c.clock(), nil)
    c.setClock(5000)
    t.eq(c.clock(), 5000)
    c.advance(10)
    t.eq(c.clock(), 5000, "the wall clock moved with the uptime clock")
    c.setClock(nil)
    t.eq(c.clock(), nil)
end

return tests
