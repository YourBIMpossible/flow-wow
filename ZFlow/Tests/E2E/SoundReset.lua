local _, ns = ...
-- Core/Sound.lua through its real entry, on the whole add-on loaded on a
-- fake client: /zflow audioreset restarts the game's sound by hand, and a
-- restart the client refuses says the failure line. The lead ruled the
-- module stays as it is: nothing is asserted beyond the restart call and
-- its first line. Not tested in game.
local tests = {}

local function boot(sound)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    c.setSound(sound)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function said(c, rest)
    local before = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = before + 1, #c.printed do out[#out + 1] = c.printed[i] end
    return out
end

tests["sound reset: /zflow audioreset restarts the sound by hand and says so"] = function(t)
    local c = boot({ ways = { "Sound_GameSystem_RestartSoundSystem" } })
    t.eq(#c.restarted(), 0, "nothing restarted at login")
    local lines = said(c, "audioreset")
    t.eq(#c.restarted(), 1, "one restart")
    t.eq(c.restarted()[1].byHand, true, "asked by hand")
    t.eq(lines[1], ns.id.title .. ": " .. ns.Sound.DONE)
end

tests["sound reset: a restart the game refuses says the failure line and restarts nothing"] = function(t)
    local c = boot({ fail = "blocked" })
    local lines = said(c, "audioreset")
    t.eq(#c.restarted(), 0)
    t.eq(lines[1], ns.id.title .. ": " .. string.format(ns.Sound.FAILED, "blocked"))
end

tests["sound reset: a game that gives no way to restart says why"] = function(t)
    local c = boot({ ways = {} })
    local lines = said(c, "audioreset")
    t.eq(#c.restarted(), 0)
    t.eq(lines[1], ns.id.title .. ": "
        .. string.format(ns.Sound.FAILED, "this game gives add-ons no way to restart its sound"))
end

return tests
