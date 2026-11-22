-- Fake client for offline tests: same surface as Core/Client.lua, driven by
-- the test. Listed as `dev` in manifest.lua, so it is never in the TOC.
-- Loading this file replaces ns.client with a fake: the offline runner has
-- no game client, and the shared kernel must not look for one.
--
--   local c = ns.make.fakeClient{ now = 50 }
--   c.advance(1.0, 10)      -- one second in ten frames
--   c.fire("SOME_EVENT", 1) -- to everything that listens
--   c.setCombat(true)       -- also fires the combat start / end event
--   c.setLoaded("Name", true); c.setSaved("NameDB", {...}); c.burn(5)
--   c.setMoney(12345); c.setBags{ { free = 3, total = 16, family = 0 } }
--   c.setBagItems{ { item = 2318, count = 4 } }; c.setBank{ ... }
--   c.setBankOpen(true)     -- also fires the bank opened / closed event
--   c.setZone(1, 1411); c.setPosition(1411, 0.5, 0.25); c.setLockdown(true)
-- What a test has not set is unknown (nil), as on a client that won't say.
local _, ns = ...
ns.make = ns.make or {}

-- A copy of a list of flat rows, so a test and the fake share no table.
local function copyRows(rows)
    if type(rows) ~= "table" then return nil end
    local out = {}
    for i = 1, #rows do
        local row = {}
        for k, v in pairs(rows[i]) do row[k] = v end
        out[i] = row
    end
    return out
end

function ns.make.fakeClient(opts)
    opts = opts or {}
    local s = { t = opts.now or 1000, ms = 0, combat = false, bankOpen = false, loaded = {}, saved = {}, listening = {}, frames = 0 }
    local c = { printed = {} }

    local events = ns.make.listeners(
        function(event) s.listening[event] = true end,
        function(event) s.listening[event] = nil end)
    local ticks = ns.make.listeners(
        function() s.frames = 1 end,
        function() s.frames = 0 end)

    -- the client surface
    function c.now() return s.t end
    function c.clockMs() return s.ms end
    function c.print(text) c.printed[#c.printed + 1] = tostring(text) end
    function c.listen(event, fn) return events.add(event, fn) end
    function c.onFrame(fn) return ticks.add("frame", fn) end
    function c.addonLoaded(name) return s.loaded[name] == true end
    function c.inCombat() return s.combat end
    function c.saved(name)
        if type(s.saved[name]) ~= "table" then s.saved[name] = {} end
        return s.saved[name]
    end
    function c.savedExists(name) return type(s.saved[name]) == "table" end
    function c.money() return s.money end
    function c.bags() return copyRows(s.bags) end
    function c.bagItems() return copyRows(s.bagItems) end
    function c.watchBank() end
    function c.bankOpen() return s.bankOpen end
    function c.bankItems()
        if s.bankOpen ~= true then return nil end
        return copyRows(s.bank)
    end
    function c.position()
        if not s.position then return nil end
        return { map = s.position.map, x = s.position.x, y = s.position.y }
    end
    function c.zone()
        if not s.zone then return nil end
        return { cont = s.zone.cont, zone = s.zone.zone }
    end
    function c.combatLockdown()
        if s.lockdownSet then return s.lockdown end
        return s.combat
    end

    -- the test's controls
    -- Moves the clock by `seconds`, drawing `frames` frames (default 1).
    function c.advance(seconds, frames)
        frames = frames or 1
        local t0 = s.t
        for i = 1, frames do
            s.t = t0 + seconds * i / frames
            ticks.call("frame", seconds / frames)
        end
    end
    function c.fire(event, ...) events.call(event, ...) end
    function c.setCombat(on)
        on = on and true or false
        if on == s.combat then return end
        s.combat = on
        events.call(on and "PLAYER_REGEN_DISABLED" or "PLAYER_REGEN_ENABLED")
    end
    function c.setLoaded(name, on) s.loaded[name] = on and true or nil end
    function c.setSaved(name, tbl) s.saved[name] = tbl end
    -- Each takes nil for "unknown".
    function c.setMoney(copper) s.money = copper end
    function c.setBags(rows) s.bags = copyRows(rows) end
    function c.setBagItems(stacks) s.bagItems = copyRows(stacks) end
    -- What the bank holds; bankItems() gives it only while the bank is open.
    function c.setBank(stacks) s.bank = copyRows(stacks) end
    -- true / false fire the bank event; nil is "not known" and fires nothing.
    function c.setBankOpen(on)
        if on == nil then s.bankOpen = nil return end
        on = on and true or false
        if on == s.bankOpen then return end
        s.bankOpen = on
        events.call(on and "BANKFRAME_OPENED" or "BANKFRAME_CLOSED")
    end
    function c.setZone(cont, zone)
        s.zone = (cont ~= nil or zone ~= nil) and { cont = cont, zone = zone } or nil
    end
    function c.setPosition(map, x, y)
        s.position = map and { map = map, x = x, y = y } or nil
    end
    -- Until this is called the lock follows setCombat. nil: not known.
    function c.setLockdown(on)
        s.lockdownSet = true
        if on == nil then s.lockdown = nil else s.lockdown = on and true or false end
    end
    -- Work that takes `ms` milliseconds: moves only the fine clock.
    function c.burn(ms) s.ms = s.ms + ms end
    -- Sorted names of the events something listens to.
    function c.events()
        local out = {}
        for event in pairs(s.listening) do out[#out + 1] = event end
        table.sort(out)
        return out
    end
    -- True while something is subscribed to the frame tick.
    function c.ticking() return s.frames == 1 end

    return c
end

ns.client = ns.make.fakeClient()
