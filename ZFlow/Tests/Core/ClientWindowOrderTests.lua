-- bankOpen() and merchantOpen() inside the window's own events: whoever
-- listens, and in whatever order the listeners were added, the client
-- already knows the window's state when the first of them runs. The same
-- rule trainer() got in CR1. The real client over a hand-built
-- environment; ClientFake is not used.
local _, ns = ...

-- Frames that take events. No BankFrame and no MerchantFrame: the only
-- way to know a window's state here is the event.
local function windowEnv()
    local env = { frames = {} }
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
            if f.events[event] then f.scripts.OnEvent(f, event, ...) end
        end
    end
    return env
end

local BANK = { open = "BANKFRAME_OPENED", closed = "BANKFRAME_CLOSED", watch = "watchBank", read = "bankOpen" }
local MERCHANT = { open = "MERCHANT_SHOW", closed = "MERCHANT_CLOSED", watch = "watchMerchant", read = "merchantOpen" }

-- What the read says inside a listener of `event`: "nil" for not known, so
-- a missing answer is told apart from a listener that never ran.
local function record(c, w, event)
    local seen = {}
    c.listen(event, function()
        local v = c[w.read]()
        seen[#seen + 1] = v == nil and "nil" or v
    end)
    return seen
end

local function openBeforeWatch(t, w)
    local env = windowEnv()
    local c = ns.make.client(env)
    local seen = record(c, w, w.open)
    c[w.watch]()
    env.fire(w.open)
    t.eq(#seen, 1, "the listener ran once")
    t.eq(seen[1], true, "open inside the first " .. w.open)
    env.fire(w.closed)
    t.eq(c[w.read](), false, "closed")
    env.fire(w.open)
    t.eq(#seen, 2)
    t.eq(seen[2], true, "open inside the second " .. w.open)
end

local function closedBeforeWatch(t, w)
    local env = windowEnv()
    local c = ns.make.client(env)
    local seen = record(c, w, w.closed)
    c[w.watch]()
    env.fire(w.open)
    t.eq(c[w.read](), true)
    env.fire(w.closed)
    t.eq(#seen, 1)
    t.eq(seen[1], false, "closed inside " .. w.closed)
end

local function neverWatched(t, w)
    local env = windowEnv()
    local c = ns.make.client(env)
    local opened = record(c, w, w.open)
    local closed = record(c, w, w.closed)
    env.fire(w.open)
    t.eq(opened[1], true, "open inside " .. w.open .. " with no watch call")
    env.fire(w.closed)
    t.eq(closed[1], false, "closed inside " .. w.closed .. " with no watch call")
    t.eq(c[w.read](), false)
end

local function afterWatch(t, w)
    local env = windowEnv()
    local c = ns.make.client(env)
    c[w.watch]()
    local opened = record(c, w, w.open)
    local closed = record(c, w, w.closed)
    env.fire(w.open)
    t.eq(opened[1], true)
    env.fire(w.closed)
    t.eq(closed[1], false)
end

local function watchTakesEvents(t, w)
    local env = windowEnv()
    local c = ns.make.client(env)
    t.eq(#env.frames, 0, "no frame until something listens")
    t.eq(c[w.read](), nil, "no event and no frame: not known")
    t.eq(#env.frames, 0, "reading does not start listening")
    c[w.watch]()
    t.eq(env.frames[1].events[w.open], true)
    t.eq(env.frames[1].events[w.closed], true)
    env.fire(w.open)
    t.eq(c[w.read](), true, "known from the event with no other listener")
    env.fire(w.closed)
    t.eq(c[w.read](), false)
end

return {
    ["bank: a listener added before watchBank sees the bank open inside BANKFRAME_OPENED"] = function(t)
        openBeforeWatch(t, BANK)
    end,
    ["bank: a listener added before watchBank sees the bank closed inside BANKFRAME_CLOSED"] = function(t)
        closedBeforeWatch(t, BANK)
    end,
    ["bank: a listener sees the window's state with no watchBank call at all"] = function(t)
        neverWatched(t, BANK)
    end,
    ["bank: a listener added after watchBank still sees the window's state"] = function(t)
        afterWatch(t, BANK)
    end,
    ["bank: watchBank alone makes the client take both events"] = function(t)
        watchTakesEvents(t, BANK)
    end,

    ["merchant: a listener added before watchMerchant sees the window open inside MERCHANT_SHOW"] = function(t)
        openBeforeWatch(t, MERCHANT)
    end,
    ["merchant: a listener added before watchMerchant sees the window closed inside MERCHANT_CLOSED"] = function(t)
        closedBeforeWatch(t, MERCHANT)
    end,
    ["merchant: a listener sees the window's state with no watchMerchant call at all"] = function(t)
        neverWatched(t, MERCHANT)
    end,
    ["merchant: a listener added after watchMerchant still sees the window's state"] = function(t)
        afterWatch(t, MERCHANT)
    end,
    ["merchant: watchMerchant alone makes the client take both events"] = function(t)
        watchTakesEvents(t, MERCHANT)
    end,

    ["one window's events say nothing about the other"] = function(t)
        local env = windowEnv()
        local c = ns.make.client(env)
        c.watchBank()
        c.watchMerchant()
        env.fire("BANKFRAME_OPENED")
        t.eq(c.bankOpen(), true)
        t.eq(c.merchantOpen(), nil, "the merchant window is still not known")
        env.fire("MERCHANT_SHOW")
        env.fire("BANKFRAME_CLOSED")
        t.eq(c.bankOpen(), false)
        t.eq(c.merchantOpen(), true)
    end,
}
