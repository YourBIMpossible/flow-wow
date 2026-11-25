-- The suggested game settings and the one click that applies them
-- (Settings/GameSuggest.lua; row F-14, lead section 828.4). Pure: a fake
-- client, or a hand-built table standing in for one.
-- Fails before: Settings/GameSuggest.lua is absent (ns.Settings.GameSuggest is nil).
local _, ns = ...

local G = ns.Settings and ns.Settings.GameSuggest

local function has(t)
    local ok = type(G) == "table" and type(G.LIST) == "table" and type(G.Apply) == "function"
        and type(G.Current) == "function"
    t.ok(ok, "ns.Settings.GameSuggest answers LIST, Apply and Current")
    return ok
end

-- A stand-in client: every write is recorded; answers set per name.
local function stub(combat, answers)
    local c = { writes = {}, values = {} }
    function c.inCombat() return combat end
    function c.gameSetting(name) return c.values[name] end
    function c.setGameSetting(name, v)
        c.writes[#c.writes + 1] = { name, v }
        local a = answers and answers[name]
        if a == "raise" then error("no") end
        if a then return nil, a end
        c.values[name] = v
        return true
    end
    return c
end

local BANNED = { "bind", "key", "gxapi", "gxwindow", "gxresolution", "gxmaximize", "vsync", "resolution",
    "renderscale", "graphics", "msaa", "monitor", "refresh", "maxfps", "gxadapter", "gxrefresh" }

return {
    ["gamesuggest: each entry is a game setting, a value and our own why"] = function(t)
        if not has(t) then return end
        t.ok(#G.LIST >= 1, "a list")
        local seen = {}
        for i, e in ipairs(G.LIST) do
            t.ok(type(e.name) == "string" and e.name:find("^%a[%w_]*$") ~= nil, "entry " .. i .. " names a setting")
            t.ok(type(e.value) == "string", tostring(e.name) .. " has a value as text")
            t.ok(type(e.why) == "string" and e.why ~= "", tostring(e.name) .. " says why")
            t.ok(not seen[e.name], tostring(e.name) .. " once")
            seen[e.name] = true
        end
    end,

    ["gamesuggest: no key binding and no graphics driver or video setting"] = function(t)
        if not has(t) then return end
        for _, e in ipairs(G.LIST) do
            local low = string.lower(e.name)
            for _, word in ipairs(BANNED) do
                t.ok(low:find(word, 1, true) == nil, e.name .. " is not a " .. word .. " setting")
            end
        end
    end,

    ["gamesuggest: Apply asks each setting once, through a protected call, and says per setting"] = function(t)
        if not has(t) then return end
        local list = {
            { name = "autoLootDefault", value = "1", why = "a" },
            { name = "instantQuestText", value = "1", why = "b" },
            { name = "showTimestamps", value = "%H:%M:%S ", why = "c" },
        }
        local c = stub(false, { instantQuestText = "notAllowed", showTimestamps = "raise" })
        local r = G.Apply(list, c)
        t.eq(c.writes, { { "autoLootDefault", "1" }, { "instantQuestText", "1" }, { "showTimestamps", "%H:%M:%S " } })
        t.eq(r.refused, nil, "not refused as a whole")
        t.eq(#r, 3, "one answer per setting")
        t.eq(r[1].name, "autoLootDefault")
        t.eq(r[1].result, "applied")
        t.eq(r[2].result, "refused")
        t.eq(r[2].why, "notAllowed")
        t.eq(r[3].result, "refused", "a raise is caught, not passed on")
        t.eq(r[3].why, "raised")
        t.eq(r.applied, 1)
    end,

    ["gamesuggest: Apply says no call when the client has no write"] = function(t)
        if not has(t) then return end
        local c = { inCombat = function() return false end }
        local r = G.Apply({ { name = "autoLootDefault", value = "1", why = "a" } }, c)
        t.eq(r[1].result, "noCall")
        t.eq(r.applied, 0)
    end,

    ["gamesuggest: nothing is applied in a fight, nor when the fight is not known"] = function(t)
        if not has(t) then return end
        for _, combat in ipairs({ true, "nil" }) do
            local state = combat
            if combat == "nil" then state = nil end
            local c = stub(state)
            local r = G.Apply(G.LIST, c)
            t.eq(r.refused, "combat", tostring(combat))
            t.eq(#c.writes, 0, "nothing written: " .. tostring(combat))
            t.eq(r.applied, 0)
        end
    end,

    ["gamesuggest: Apply over the fake client writes the list out of a fight"] = function(t)
        if not has(t) then return end
        local c = ns.make.fakeClient({ env = {} })
        local r = G.Apply(G.LIST, c)
        t.eq(r.refused, nil)
        t.eq(r.applied, #G.LIST)
        t.eq(#c.gameSettingWrites, #G.LIST)
        c.setCombat(true)
        local before = #c.gameSettingWrites
        t.eq(G.Apply(G.LIST, c).refused, "combat")
        t.eq(#c.gameSettingWrites, before, "nothing more written in a fight")
    end,

    ["gamesuggest: Current reads each setting and says whether it is as suggested"] = function(t)
        if not has(t) then return end
        local list = {
            { name = "autoLootDefault", value = "1", why = "a" },
            { name = "instantQuestText", value = "1", why = "b" },
            { name = "autoSelfCast", value = "1", why = "c" },
        }
        local c = stub(false)
        c.values.autoLootDefault = "1"
        c.values.instantQuestText = "0"
        local now = G.Current(list, c)
        t.eq(#now, 3)
        t.eq(now[1].now, "1")
        t.eq(now[1].matches, true)
        t.eq(now[2].now, "0")
        t.eq(now[2].matches, false)
        t.eq(now[3].now, nil, "not said")
        t.eq(now[3].matches, nil, "not known")
        t.eq(#c.writes, 0, "a read writes nothing")
        local bad = G.Current(list, { gameSetting = function() error("no") end })
        t.eq(bad[1].now, nil, "a raise reads as not known")
        t.eq(#G.Current(list, {}), 3, "no read call: still a row each")
    end,

    ["gamesuggest: nothing is applied by loading; Apply is only called by a click"] = function(t)
        if not has(t) then return end
        t.eq(G.ON_LOAD, nil, "no load hook")
        t.eq(G.TICK, nil, "no tick")
    end,
}
