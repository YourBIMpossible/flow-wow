local _, ns = ...
-- G57 lite mode on the whole add-on loaded on a fake client: the player
-- types the word, reloads, and the extras in Lite.OFF are off while the
-- rest runs; the word again and a reload bring them back. Offline: the
-- fake client, not the game. No game setting is changed.
local tests = {}

local function boot(account)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, account or {})
    c.setSaved(ns.id.charDB, {})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(2, 4)
    return c, addon
end

local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

tests["lite mode: on after a reload, the extras are off and the arrow still runs; off brings them back"] = function(t)
    local c, addon = boot()
    local L = addon.Lite
    t.ok(type(L) == "table", "the lite file is loaded")
    for _, name in ipairs(L.OFF) do
        local _, why = addon:ModuleState(name)
        t.ok(why ~= L.REASON, name .. " is not left off while lite is off")
    end
    local out = said(c, "lite")
    t.eq(out[1], addon.id.title .. ": Lite mode is off: every feature runs.")
    out = said(c, "LITE ON")
    t.eq(out[1], addon.id.title .. ": " .. L.RELOAD)
    local account = c.saved(addon.id.accountDB)
    t.eq(account.settings.perf.lite, true, "kept in the saved table")

    -- The reload: the same saved table, a fresh load.
    local c2, addon2 = boot(account)
    for _, name in ipairs(addon2.Lite.OFF) do
        local state, reason = addon2:ModuleState(name)
        t.eq(state, "off", name .. " is off in lite mode")
        t.eq(reason, addon2.Lite.REASON)
    end
    t.eq((addon2:ModuleState("sound")), "started", "a module not on the list runs")
    out = said(c2, "lite")
    t.ok(out[1]:find("Lite mode is on: ", 1, true) ~= nil, out[1])
    said(c2, "lite off")
    local _, addon3 = boot(c2.saved(addon2.id.accountDB))
    for _, name in ipairs(addon3.Lite.OFF) do
        local _, why = addon3:ModuleState(name)
        t.ok(why ~= addon3.Lite.REASON, name .. " is back")
    end
end

return tests
