local _, ns = ...
-- Lead section 296 item 3, zflow-buttons-say: a player who sees nothing can
-- find out why. Each surface below says in one line when it appears, in its
-- settings row's help and in the reply to the buttons word, with whether it
-- is on. The minimap pin says why it is not shown. On the whole add-on
-- loaded on a fake client. Not tested in game.
local tests = {}

-- Each: the module's table, the settings row its line is in.
local function surfaces()
    return {
        { mod = ns.PlateThreat, key = ns.PlateThreat.OFF },
        { mod = ns.PlateCombo, key = ns.PlateCombo.OFF },
        { mod = ns.PlateQuests, key = ns.PlateQuests.OFF },
        { mod = ns.TaxiMark, key = ns.TaxiMark.SETTING },
        { mod = ns.MapFlights, key = ns.MapFlights.SETTING },
        { mod = ns.NpcSpeech, key = ns.NpcSpeech.SETTING },
    }
end

local function boot()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(5, 20)
    return c, addon
end

local function said(c, rest)
    local from = #c.printed
    c.slashes[ns.id.slash](rest)
    local out = {}
    for i = from + 1, #c.printed do out[#out + 1] = tostring(c.printed[i]) end
    return out
end

local function lineWith(lines, text)
    for _, l in ipairs(lines) do
        if l:find(text, 1, true) then return l end
    end
    return nil
end

tests["buttons say: every surface has one line saying when it appears"] = function(t)
    for _, s in ipairs(surfaces()) do
        t.ok(type(s.mod.WHEN) == "string" and s.mod.WHEN ~= "", tostring(s.key) .. " has its line")
        t.ok(s.mod.WHEN and not s.mod.WHEN:find("\n", 1, true), tostring(s.key) .. ": one line")
    end
end

tests["buttons say: each settings row's help carries that line"] = function(t)
    local _, addon = boot()
    for _, s in ipairs(surfaces()) do
        local row = addon.settings:row(s.key)
        t.ok(row ~= nil, s.key .. " is a row")
        local help = row and row.help or ""
        t.ok(s.mod.WHEN and help:find(s.mod.WHEN, 1, true) ~= nil, s.key .. " help: " .. help)
    end
end

tests["buttons say: the buttons word lists each surface, on or off, and when it appears"] = function(t)
    local c, addon = boot()
    local lines = said(c, "buttons")
    for _, s in ipairs(surfaces()) do
        local l = s.mod.WHEN and lineWith(lines, s.mod.WHEN)
        t.ok(l ~= nil, s.key .. " listed: " .. table.concat(lines, " | "))
        t.ok(l and l:find(ns.id.title, 1, true) == 1, "from the add-on, by its title")
        t.ok(l and (l:find(": on;", 1, true) or l:find(": off;", 1, true)), "says on or off: " .. tostring(l))
    end
    local flights = lineWith(lines, ns.MapFlights.WHEN)
    t.ok(flights and flights:find(": off;", 1, true), "map flight pins are off at a default profile")
    addon.settings:set(ns.MapFlights.SETTING, true)
    flights = lineWith(said(c, "buttons"), ns.MapFlights.WHEN)
    t.ok(flights and flights:find(": on;", 1, true), "and on once ticked")
    local threat = lineWith(lines, ns.PlateThreat.WHEN)
    t.ok(threat and threat:find(": on;", 1, true), "threat: on, its off switch unticked")
end

tests["buttons say: the minimap pin says why it is not shown"] = function(t)
    local c = boot()
    local l = lineWith(said(c, "buttons"), "minimap pin")
    t.ok(l ~= nil, "a minimap pin line")
    t.ok(l and l:find("not shown (", 1, true) ~= nil, "not shown, with the reason: " .. tostring(l))
end

return tests
