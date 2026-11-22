-- Client boundary: the only file that touches the game client. Everything
-- else calls ns.client.* (or the client handed to its kernel), so the same
-- code runs offline against Core/ClientFake.lua.
--
-- Nothing here has been run in the game. Every client name is looked up in
-- `env` when it is needed and a missing one never errors: the call returns
-- the documented fallback instead. Names marked "first guess" are not
-- confirmed to exist on interface 16001.
local _, ns = ...
ns.make = ns.make or {}

-- Keeps handler lists per key; `first(key)` runs when a key gets its first
-- handler and `last(key)` when it loses its last one.
local function Listeners(first, last)
    local lists = {}
    local L = {}
    function L.add(key, fn)
        local list = lists[key]
        if not list then
            list = {}
            lists[key] = list
            first(key)
        end
        local entry = { fn = fn }
        list[#list + 1] = entry
        return function()
            if entry.dead then return end
            entry.dead = true
            local cur = lists[key]
            if not cur then return end
            for i = #cur, 1, -1 do
                if cur[i] == entry then table.remove(cur, i) end
            end
            if #cur == 0 then
                lists[key] = nil
                last(key)
            end
        end
    end
    function L.call(key, ...)
        local list = lists[key]
        if not list then return end
        local snapshot = {}
        for i = 1, #list do snapshot[i] = list[i] end
        for i = 1, #snapshot do
            if not snapshot[i].dead then snapshot[i].fn(...) end
        end
    end
    return L
end
ns.make.listeners = Listeners

-- The real client. `env` is the table the client's globals live in (_G in
-- the game; a hand-built table in tests).
function ns.make.client(env)
    local c = {}
    local eventFrame, tickFrame
    local events, ticks

    local function call(fn, ...)
        if type(fn) ~= "function" then return false end
        return pcall(fn, ...)
    end

    local function newFrame()
        local ok, f = call(env.CreateFrame, "Frame")
        if ok and f then return f end
        return nil
    end

    events = Listeners(function(event)
        if not eventFrame then
            eventFrame = newFrame()
            if eventFrame then
                eventFrame:SetScript("OnEvent", function(_, name, ...) events.call(name, ...) end)
            end
        end
        -- pcall: registering an event name this client does not have errors.
        if eventFrame then pcall(eventFrame.RegisterEvent, eventFrame, event) end
    end, function(event)
        if eventFrame then pcall(eventFrame.UnregisterEvent, eventFrame, event) end
    end)

    ticks = Listeners(function()
        tickFrame = tickFrame or newFrame()
        if tickFrame then
            tickFrame:SetScript("OnUpdate", function(_, elapsed) ticks.call("frame", elapsed or 0) end)
        end
    end, function()
        if tickFrame then tickFrame:SetScript("OnUpdate", nil) end
    end)

    -- Seconds since the client started (0 when the client has no GetTime).
    function c.now()
        local ok, t = call(env.GetTime)
        return ok and tonumber(t) or 0
    end

    -- Milliseconds, fine-grained, for timing work. debugprofilestop is a
    -- first guess on 16001; falls back to GetTime, which only moves per frame.
    function c.clockMs()
        local ok, ms = call(env.debugprofilestop)
        if ok and tonumber(ms) then return tonumber(ms) end
        return c.now() * 1000
    end

    function c.print(text)
        call(env.print, tostring(text))
    end

    -- fn(...) is called with the event's arguments. Returns a cancel function.
    function c.listen(event, fn)
        return events.add(event, fn)
    end

    -- fn(elapsedSeconds) every drawn frame. Returns a cancel function.
    function c.onFrame(fn)
        return ticks.add("frame", fn)
    end

    -- True when the named addon is loaded. C_AddOns.IsAddOnLoaded is a first
    -- guess on 16001 (Flow's Splash.lua uses the same call); the bare global
    -- is the older form of it.
    function c.addonLoaded(name)
        local group = env.C_AddOns
        local fn = (type(group) == "table" and group.IsAddOnLoaded) or env.IsAddOnLoaded
        local ok, loaded = call(fn, name)
        return (ok and loaded) and true or false
    end

    -- InCombatLockdown is the protected-action lock; UnitAffectingCombat is
    -- the fallback when it is absent.
    function c.inCombat()
        local ok, locked = call(env.InCombatLockdown)
        if ok then return locked and true or false end
        local ok2, fighting = call(env.UnitAffectingCombat, "player")
        return (ok2 and fighting) and true or false
    end

    -- The saved-variable table of that name, created empty when the client
    -- has not loaded one. Never cached by callers: the client replaces the
    -- global when it loads saved data.
    function c.saved(name)
        local t = env[name]
        if type(t) ~= "table" then
            t = {}
            env[name] = t
        end
        return t
    end

    -- True when a table of that name already exists; creates nothing.
    function c.savedExists(name)
        return type(env[name]) == "table"
    end

    return c
end

ns.client = ns.make.client(_G)
