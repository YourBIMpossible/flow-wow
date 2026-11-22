-- S17 group buff tooltip: the client reads it adds. The unit tooltip hook
-- onUnitTooltip, unitInfo(unit) and unitBuff(unit, names). The real client
-- over a hand-built environment (`env` stands in for the game's globals),
-- then the fake. Every call read here is a first guess, not seen in game.
-- Reads only: nothing targets, casts or clicks.
local _, ns = ...

local MOTW, GOTW = "Mark of the Wild", "Gift of the Wild"

local function boom() error("the client refused") end

-- A tooltip the game fills for a unit: route "data" (the data post call) or
-- "script" (OnTooltipSetUnit).
local function tooltipEnv(route, hasScript)
    local env = {}
    local tip = { lines = {}, unit = "mouseover" }
    function tip.GetUnit(self) return "Somebody", self.unit end
    function tip.AddLine(self, text, r, g, b) self.lines[#self.lines + 1] = { text = text, r = r, g = g, b = b } end
    if route == "script" then
        function tip.HasScript(_, name) return hasScript ~= false and name == "OnTooltipSetUnit" end
        function tip.HookScript(self, name, fn) self.hooked = self.hooked or {}; self.hooked[name] = fn end
    elseif route == "data" then
        env.Enum = { TooltipDataType = { Item = 0, Unit = 2 } }
        env.TooltipDataProcessor = {
            AddTooltipPostCall = function(kind, fn) env.postCalls = env.postCalls or {}; env.postCalls[kind] = fn end,
        }
    end
    env.GameTooltip = tip
    -- Plays the game filling the tooltip; `clear` first, as the game does.
    env.fill = function(clear)
        if route == "script" then
            if clear ~= false and tip.hooked.OnTooltipCleared then tip.hooked.OnTooltipCleared(tip) end
            tip.hooked.OnTooltipSetUnit(tip)
        else
            env.postCalls[2](tip, {})
        end
        return tip.lines
    end
    return env, tip
end

-- A unit the client answers for: `say[unit]` = { exists, player, isSelf,
-- friendly, class, role, power }.
local function unitEnv(say)
    local env = {}
    local function of(unit) return say[unit] or {} end
    env.UnitExists = function(unit) return of(unit).exists end
    env.UnitIsPlayer = function(unit) return of(unit).player end
    env.UnitIsUnit = function(unit, other)
        if other ~= "player" then error("only asked against yourself") end
        return of(unit).isSelf
    end
    env.UnitIsFriend = function(me, unit)
        if me ~= "player" then error("only asked from yourself") end
        return of(unit).friendly
    end
    env.UnitClass = function(unit) return "Shown Name", of(unit).class, 11 end
    env.UnitGroupRolesAssigned = function(unit) return of(unit).role end
    env.UnitPowerType = function(unit) return of(unit).power, "RAGE" end
    return env
end

local function somebody()
    return { exists = true, player = true, isSelf = false, friendly = true,
             class = "WARRIOR", role = "NONE", power = 1 }
end

-- Buffs by index, the new way: rows = { { name, expirationTime } ... }.
local function auraEnv(rows, now)
    local env = { asked = {} }
    env.GetTime = function() return now or 100 end
    env.C_UnitAuras = {
        GetAuraDataByIndex = function(unit, i, filter)
            env.asked[#env.asked + 1] = { unit, i, filter }
            return rows[i]
        end,
    }
    return env
end

return {
    -- ------------------------------------------------------- the hook
    ["S17 onUnitTooltip: the data route tells the listener the unit token"] = function(t)
        local env = tooltipEnv("data")
        local c = ns.make.client(env)
        local got = {}
        local cancel = c.onUnitTooltip(function(unit, add) got[#got + 1] = unit; add("a line", 1, 0.5, 0) end)
        t.eq(type(cancel), "function")
        t.eq(env.fill(), { { text = "a line", r = 1, g = 0.5, b = 0 } })
        t.eq(got, { "mouseover" })
    end,

    ["S17 onUnitTooltip: the data route answers for the game's own tooltip only"] = function(t)
        local env = tooltipEnv("data")
        local c = ns.make.client(env)
        local told = 0
        c.onUnitTooltip(function() told = told + 1 end)
        local other = { GetUnit = function() return "Somebody", "mouseover" end, AddLine = function() end }
        env.postCalls[2](other, {})
        t.eq(told, 0)
    end,

    ["S17 onUnitTooltip: the item hook and the unit hook are told apart"] = function(t)
        local env, tip = tooltipEnv("data")
        function tip.GetItem() return "Helm", "item:100" end
        local c = ns.make.client(env)
        local items, units = 0, 0
        c.onItemTooltip(function() items = items + 1 end)
        c.onUnitTooltip(function() units = units + 1 end)
        env.fill()
        t.eq(units, 1)
        t.eq(items, 0, "a unit fill is not an item fill")
        env.postCalls[0](tip, {})
        t.eq(items, 1)
        t.eq(units, 1)
    end,

    ["S17 onUnitTooltip: hidden unit token tells nobody"] = function(t)
        local env, tip = tooltipEnv("data")
        local c = ns.make.client(env)
        local told = 0
        c.onUnitTooltip(function() told = told + 1 end)
        local secret = {}
        env.issecretvalue = function(v) return secret[v] == true end
        secret["mouseover"] = true
        env.fill()
        t.eq(told, 0, "a secret token")
        secret["mouseover"] = nil
        tip.unit = nil
        env.fill()
        t.eq(told, 0, "no token")
        tip.unit = 7
        env.fill()
        t.eq(told, 0, "a token that is no text")
        tip.GetUnit = boom
        env.fill()
        t.eq(told, 0, "a read that raised")
        t.eq(#tip.lines, 0)
    end,

    ["S17 onUnitTooltip: the script route only with HasScript"] = function(t)
        local env, tip = tooltipEnv("script")
        local c = ns.make.client(env)
        local got = {}
        t.eq(type(c.onUnitTooltip(function(unit, add) got[#got + 1] = unit; add("x") end)), "function")
        t.ok(tip.hooked.OnTooltipSetUnit ~= nil)
        env.fill()
        t.eq(got, { "mouseover" })

        local env2, tip2 = tooltipEnv("script", false)
        local c2 = ns.make.client(env2)
        t.eq(c2.onUnitTooltip(function() end), nil, "the tooltip has no such script")
        t.eq(tip2.hooked, nil, "and nothing was hooked")
    end,

    ["S17 onUnitTooltip: second fill before clear adds nothing"] = function(t)
        local env = tooltipEnv("script")
        local c = ns.make.client(env)
        local told = 0
        c.onUnitTooltip(function(_, add) told = told + 1; add("x") end)
        env.fill()
        env.fill(false)
        t.eq(told, 1, "once for one fill")
        env.fill()
        t.eq(told, 2, "again after the game cleared it")
    end,

    ["S17 onUnitTooltip: a client with neither route gives nil"] = function(t)
        t.eq(ns.make.client({}).onUnitTooltip(function() end), nil)
        t.eq(ns.make.client({ GameTooltip = {} }).onUnitTooltip(function() end), nil)
        local env = tooltipEnv("data")
        t.eq(ns.make.client(env).onUnitTooltip("not a function"), nil)
    end,

    ["S17 onUnitTooltip: cancel stops the listener; a listener that raises stays here"] = function(t)
        local env = tooltipEnv("data")
        local c = ns.make.client(env)
        local told = 0
        c.onUnitTooltip(boom)
        local cancel = c.onUnitTooltip(function() told = told + 1 end)
        env.fill()
        t.eq(told, 1, "the one after the one that raised is still told")
        cancel()
        env.fill()
        t.eq(told, 1)
    end,

    ["S17 onUnitTooltip: add takes text only"] = function(t)
        local env, tip = tooltipEnv("data")
        local c = ns.make.client(env)
        c.onUnitTooltip(function(_, add) add(nil); add(5); add("ok", 1, 1, 1) end)
        env.fill()
        t.eq(tip.lines, { { text = "ok", r = 1, g = 1, b = 1 } })
    end,

    -- ------------------------------------------------------- the unit
    ["S17 unitInfo: what the client says of a unit"] = function(t)
        local c = ns.make.client(unitEnv({ mouseover = somebody() }))
        t.eq(c.unitInfo("mouseover"), somebody())
    end,

    ["S17 unitInfo: each hidden field is nil on its own and the others still answer"] = function(t)
        for _, field in ipairs({ "exists", "player", "isSelf", "friendly", "class", "role", "power" }) do
            local say = somebody()
            local secret = {}
            say[field] = secret
            local env = unitEnv({ mouseover = say })
            env.issecretvalue = function(v) return v == secret end
            local want = somebody()
            want[field] = nil
            t.eq(ns.make.client(env).unitInfo("mouseover"), want, field .. " hidden")
        end
    end,

    ["S17 unitInfo: an answer of the wrong type is nil, never a guess"] = function(t)
        local say = somebody()
        say.exists, say.player, say.isSelf, say.friendly = 1, "yes", 0, nil
        say.class, say.role, say.power = 11, false, "RAGE"
        t.eq(ns.make.client(unitEnv({ mouseover = say })).unitInfo("mouseover"), {})
        local empty = somebody()
        empty.class, empty.role = "", ""
        local got = ns.make.client(unitEnv({ mouseover = empty })).unitInfo("mouseover")
        t.eq(got.class, nil)
        t.eq(got.role, nil)
    end,

    ["S17 unitInfo: failed call is nil, not false"] = function(t)
        local env = unitEnv({ mouseover = somebody() })
        env.UnitIsFriend, env.UnitIsUnit, env.UnitClass = boom, boom, boom
        local got = ns.make.client(env).unitInfo("mouseover")
        t.eq(got.friendly, nil)
        t.eq(got.isSelf, nil)
        t.eq(got.class, nil)
        t.eq(got.exists, true, "the others still answer")
        t.eq(ns.make.client({}).unitInfo("mouseover"), {}, "a client with none of the reads")
    end,

    ["S17 unitInfo: no unit asked is nil"] = function(t)
        local c = ns.make.client(unitEnv({ mouseover = somebody() }))
        t.eq(c.unitInfo(nil), nil)
        t.eq(c.unitInfo(5), nil)
        t.eq(c.unitInfo(""), nil)
    end,

    -- ------------------------------------------------------ the buffs
    ["S17 unitBuff: found with time left"] = function(t)
        local env = auraEnv({ { name = "Thorns", expirationTime = 130 }, { name = MOTW, expirationTime = 220 } }, 100)
        local up, left, found = ns.make.client(env).unitBuff("mouseover", { MOTW, GOTW })
        t.eq(up, true)
        t.eq(left, 120)
        t.eq(found, MOTW)
        t.eq(env.asked[1], { "mouseover", 1, "HELPFUL" }, "helpful auras only, by index")
    end,

    ["S17 unitBuff: another name in the list is found and named"] = function(t)
        local env = auraEnv({ { name = GOTW, expirationTime = 160 } }, 100)
        local up, left, found = ns.make.client(env).unitBuff("mouseover", { MOTW, GOTW })
        t.eq(up, true)
        t.eq(left, 60)
        t.eq(found, GOTW)
    end,

    ["S17 unitBuff: found with no expiry is math.huge; a hidden expiry is no time"] = function(t)
        local env = auraEnv({ { name = MOTW, expirationTime = 0 } })
        local up, left = ns.make.client(env).unitBuff("mouseover", { MOTW })
        t.eq(up, true)
        t.eq(left, math.huge)

        local secret = {}
        local env2 = auraEnv({ { name = MOTW, expirationTime = secret } })
        env2.issecretvalue = function(v) return v == secret end
        local up2, left2, found2 = ns.make.client(env2).unitBuff("mouseover", { MOTW })
        t.eq(up2, true)
        t.eq(left2, nil)
        t.eq(found2, MOTW)

        local env3 = auraEnv({ { name = MOTW, expirationTime = "soon" } })
        local up3, left3 = ns.make.client(env3).unitBuff("mouseover", { MOTW })
        t.eq(up3, true)
        t.eq(left3, nil)
    end,

    ["S17 unitBuff: hidden name on any row is nil"] = function(t)
        local secret = {}
        local env = auraEnv({ { name = "Thorns" }, { name = secret }, { name = MOTW, expirationTime = 500 } })
        env.issecretvalue = function(v) return v == secret end
        t.eq((ns.make.client(env).unitBuff("mouseover", { MOTW })), nil, "before the name: not known")
        local env2 = auraEnv({ { name = "Thorns" }, { name = 5 } })
        t.eq((ns.make.client(env2).unitBuff("mouseover", { MOTW })), nil, "a name that is no text")
        local env3 = auraEnv({ "not a row" })
        t.eq((ns.make.client(env3).unitBuff("mouseover", { MOTW })), nil, "a row that is no table")
    end,

    ["S17 unitBuff: a hidden row is nil"] = function(t)
        local secret = {}
        local env = auraEnv({ secret })
        env.issecretvalue = function(v) return v == secret end
        t.eq((ns.make.client(env).unitBuff("mouseover", { MOTW })), nil)
    end,

    ["S17 unitBuff: full readable list without the name is false"] = function(t)
        local env = auraEnv({ { name = "Thorns", expirationTime = 500 }, { name = "Power Word: Fortitude" } })
        local up, left, found = ns.make.client(env).unitBuff("mouseover", { MOTW, GOTW })
        t.eq(up, false)
        t.eq(left, nil)
        t.eq(found, nil)
        t.eq(#env.asked, 3, "asked until the first empty row")
        t.eq((ns.make.client(auraEnv({})).unitBuff("mouseover", { MOTW })), false, "no buffs at all, all read")
    end,

    ["S17 unitBuff: no more than 40 rows are asked for"] = function(t)
        local rows = {}
        for i = 1, 60 do rows[i] = { name = "Buff " .. i } end
        local env = auraEnv(rows)
        t.eq((ns.make.client(env).unitBuff("mouseover", { MOTW })), false)
        t.eq(#env.asked, 40)
    end,

    ["S17 unitBuff: a read that raised is nil, not false"] = function(t)
        local env = auraEnv({})
        env.C_UnitAuras.GetAuraDataByIndex = boom
        t.eq((ns.make.client(env).unitBuff("mouseover", { MOTW })), nil)
    end,

    ["S17 unitBuff: the old read where the new one is absent, under the same rules"] = function(t)
        local rows = { { "Thorns", 1, 0, nil, 600, 400 }, { GOTW, 1, 0, nil, 3600, 250 } }
        local env = { GetTime = function() return 100 end }
        env.UnitBuff = function(unit, i, filter)
            if unit ~= "mouseover" or filter ~= "HELPFUL" then error("asked wrongly") end
            return unpack(rows[i] or {}, 1, 6)
        end
        local up, left, found = ns.make.client(env).unitBuff("mouseover", { MOTW, GOTW })
        t.eq(up, true)
        t.eq(left, 150)
        t.eq(found, GOTW)
        t.eq((ns.make.client(env).unitBuff("mouseover", { "Arcane Intellect" })), false)
        rows[1][1] = 5
        t.eq((ns.make.client(env).unitBuff("mouseover", { GOTW })), nil, "a name that is no text")
    end,

    ["S17 unitBuff: no aura API is nil"] = function(t)
        t.eq((ns.make.client({}).unitBuff("mouseover", { MOTW })), nil)
    end,

    ["S17 unitBuff: nothing asked is nil"] = function(t)
        local c = ns.make.client(auraEnv({ { name = MOTW } }))
        t.eq((c.unitBuff(nil, { MOTW })), nil)
        t.eq((c.unitBuff("mouseover", nil)), nil)
        t.eq((c.unitBuff("mouseover", MOTW)), nil, "the names are a list")
    end,

    -- ------------------------------------------------------- the fake
    ["S17 fake: the unit, as the real client answers"] = function(t)
        local c = ns.make.fakeClient()
        t.eq(c.unitInfo("mouseover"), {}, "a unit not set: nothing known")
        t.eq(c.unitInfo(nil), nil)
        local say = somebody()
        c.setUnit("mouseover", say)
        t.eq(c.unitInfo("mouseover"), somebody())
        c.unitInfo("mouseover").class = "MAGE"
        t.eq(c.unitInfo("mouseover").class, "WARRIOR", "a copy each time")
    end,

    ["S17 fake: the buffs, as the real client answers"] = function(t)
        local c = ns.make.fakeClient()
        t.eq((c.unitBuff("mouseover", { MOTW })), nil, "buffs not set: not known")
        c.setUnitBuffs("mouseover", {})
        t.eq((c.unitBuff("mouseover", { MOTW })), false)
        c.setUnitBuffs("mouseover", { { name = "Thorns", left = 5 }, { name = GOTW, left = 90 } })
        local up, left, found = c.unitBuff("mouseover", { MOTW, GOTW })
        t.eq(up, true)
        t.eq(left, 90)
        t.eq(found, GOTW)
        c.setUnitBuffs("mouseover", { { name = false }, { name = MOTW } })
        t.eq((c.unitBuff("mouseover", { MOTW })), nil, "one hidden name hides the answer")
        t.eq((c.unitBuff("mouseover", MOTW)), nil)
        c.setUnitBuffs("mouseover", nil)
        t.eq((c.unitBuff("mouseover", { MOTW })), nil)
    end,

    ["S17 fake: the unit tooltip hook"] = function(t)
        local c = ns.make.fakeClient()
        local got = {}
        local cancel = c.onUnitTooltip(function(unit, add) got[#got + 1] = unit; add("line", 1, 0, 0) end)
        t.eq(c.onUnitTooltip("no function"), nil)
        t.eq(c.showUnitTooltip("mouseover"), { { text = "line", r = 1, g = 0, b = 0 } })
        t.eq(got, { "mouseover" })
        cancel()
        t.eq(c.showUnitTooltip("mouseover"), {})
    end,
}
