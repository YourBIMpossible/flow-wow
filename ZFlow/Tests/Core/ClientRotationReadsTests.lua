-- Section 183 (C1): the rotation reads the client adds. playerBuffs,
-- formName and currentSpell over a hand-built environment (`env` stands in
-- for the game's globals), then the fake. Every call read here is a first
-- guess from the API pages, not seen in game. Reads only.
local _, ns = ...

local function boom() error("the client refused") end

-- C_UnitAuras route: rows is a list of { name, expirationTime }.
local function aurasEnv(rows, now)
    local env = { GetTime = function() return now or 100 end }
    env.C_UnitAuras = {
        GetAuraDataByIndex = function(unit, i, filter)
            if unit ~= "player" or filter ~= "HELPFUL" then return nil end
            return rows[i]
        end,
    }
    return env
end

-- UnitBuff route: rows is a list of { name, expires }; expires comes back
-- as the sixth answer.
local function unitBuffEnv(rows, now)
    local env = { GetTime = function() return now or 100 end }
    env.UnitBuff = function(unit, i, filter)
        if unit ~= "player" or filter ~= "HELPFUL" then return nil end
        local r = rows[i]
        if r == nil then return nil end
        return r[1], "icon", 1, nil, 30, r[2]
    end
    return env
end

-- Form route: form is the number GetShapeshiftForm answers; ids maps a form
-- number to the spell id GetShapeshiftFormInfo answers fourth; names maps a
-- spell id to its name.
local function formEnv(form, ids, names)
    local env = {}
    env.GetShapeshiftForm = function() return form end
    env.GetShapeshiftFormInfo = function(n)
        local id = ids and ids[n]
        if id == nil then return nil end
        return "icon", true, true, id
    end
    env.C_Spell = {
        GetSpellInfo = function(id)
            local n = names and names[id]
            return n and { name = n } or nil
        end,
    }
    return env
end

local function secretEnv(env, secret)
    env.issecretvalue = function(v) return v == secret end
    return env
end

return {
    -- ---------------------------------------------------------- playerBuffs
    ["183 playerBuffs: the aura data route gives each buff and its seconds left"] = function(t)
        local c = ns.make.client(aurasEnv({
            { name = "Seal of Might", expirationTime = 130 },
            { name = "Blessing", expirationTime = 400 },
        }, 100))
        t.eq(c.playerBuffs(), { ["Seal of Might"] = 30, Blessing = 300 })
    end,

    ["183 playerBuffs: the old route reads the name first and the end time sixth"] = function(t)
        local c = ns.make.client(unitBuffEnv({ { "Seal of Might", 130 }, { "Blessing", 400 } }, 100))
        t.eq(c.playerBuffs(), { ["Seal of Might"] = 30, Blessing = 300 })
    end,

    ["183 playerBuffs: the aura data route wins when both are there"] = function(t)
        local env = aurasEnv({ { name = "New", expirationTime = 110 } }, 100)
        env.UnitBuff = function() return "Old", "icon", 1, nil, 30, 110 end
        t.eq(ns.make.client(env).playerBuffs(), { New = 10 })
    end,

    ["183 playerBuffs: a full read with no buff is an empty table, not nil"] = function(t)
        t.eq(ns.make.client(aurasEnv({})).playerBuffs(), {})
        t.eq(ns.make.client(unitBuffEnv({})).playerBuffs(), {})
    end,

    ["183 playerBuffs: no read at all is not known"] = function(t)
        t.ok(ns.make.client({ GetTime = function() return 1 end }).playerBuffs() == nil)
    end,

    ["183 playerBuffs: a read that raises is not known"] = function(t)
        local env = { GetTime = function() return 1 end, C_UnitAuras = { GetAuraDataByIndex = boom } }
        t.ok(ns.make.client(env).playerBuffs() == nil, "aura data")
        t.ok(ns.make.client({ GetTime = function() return 1 end, UnitBuff = boom }).playerBuffs() == nil, "old")
    end,

    ["183 playerBuffs: a hidden row or name makes the whole list not known"] = function(t)
        local secret = {}
        local env = secretEnv(aurasEnv({ { name = "Blessing", expirationTime = 200 }, secret }), secret)
        t.ok(ns.make.client(env).playerBuffs() == nil, "hidden row")
        env = secretEnv(aurasEnv({ { name = secret, expirationTime = 200 } }), secret)
        t.ok(ns.make.client(env).playerBuffs() == nil, "hidden name")
        env = secretEnv(unitBuffEnv({ { secret, 200 } }), secret)
        t.ok(ns.make.client(env).playerBuffs() == nil, "hidden old name")
    end,

    ["183 playerBuffs: a row that is not a table or a name that is not text is not known"] = function(t)
        t.ok(ns.make.client(aurasEnv({ "Blessing" })).playerBuffs() == nil, "row")
        t.ok(ns.make.client(aurasEnv({ { name = 7, expirationTime = 200 } })).playerBuffs() == nil, "name")
    end,

    ["183 playerBuffs: a buff with no end is math.huge; a hidden or odd end time is true"] = function(t)
        local secret = {}
        local env = secretEnv(aurasEnv({
            { name = "Aura", expirationTime = 0 },
            { name = "Hidden", expirationTime = secret },
            { name = "Odd", expirationTime = "soon" },
            { name = "Missing" },
        }), secret)
        t.eq(ns.make.client(env).playerBuffs(), { Aura = math.huge, Hidden = true, Odd = true, Missing = true })
    end,

    ["183 playerBuffs: a name twice keeps the longer time, and true wins"] = function(t)
        local c = ns.make.client(aurasEnv({
            { name = "Blessing", expirationTime = 120 },
            { name = "Blessing", expirationTime = 150 },
            { name = "Blessing", expirationTime = 110 },
            { name = "Seal", expirationTime = 130 },
            { name = "Seal" },
            { name = "Seal", expirationTime = 190 },
        }, 100))
        t.eq(c.playerBuffs(), { Blessing = 50, Seal = true })
    end,

    ["183 playerBuffs: at most forty rows are read"] = function(t)
        local asked = 0
        local env = { GetTime = function() return 0 end }
        env.C_UnitAuras = {
            GetAuraDataByIndex = function(_, i)
                asked = i
                return { name = "B" .. i, expirationTime = 0 }
            end,
        }
        local got = ns.make.client(env).playerBuffs()
        t.eq(asked, 40)
        t.eq(got.B40, math.huge)
        t.ok(got.B41 == nil)
    end,

    -- ------------------------------------------------------------- formName
    ["183 formName: no form is nil and known"] = function(t)
        local name, known = ns.make.client(formEnv(0)).formName()
        t.ok(name == nil)
        t.eq(known, true)
    end,

    ["183 formName: a form gives the name of its spell"] = function(t)
        local name, known = ns.make.client(formEnv(3, { [3] = 768 }, { [768] = "Cat Form" })).formName()
        t.eq(name, "Cat Form")
        t.eq(known, true)
    end,

    ["183 formName: the old spell info read is used when the new one is missing"] = function(t)
        local env = formEnv(1, { [1] = 5487 })
        env.C_Spell = nil
        env.GetSpellInfo = function(id) if id == 5487 then return "Bear Form", nil, "icon" end end
        local name, known = ns.make.client(env).formName()
        t.eq(name, "Bear Form")
        t.eq(known, true)
    end,

    ["183 formName: anything not read is not known, never no form"] = function(t)
        local secret = {}
        local infoRaises = formEnv(2)
        infoRaises.GetShapeshiftFormInfo = boom
        local cases = {
            { "no read", {} },
            { "form raises", { GetShapeshiftForm = boom } },
            { "form not a number", { GetShapeshiftForm = function() return "1" end } },
            { "no info", formEnv(2) },
            { "info raises", infoRaises },
            { "no spell name", formEnv(2, { [2] = 99 }) },
            { "id not a number", formEnv(2, { [2] = "99" }, { [99] = "X" }) },
            { "hidden form", secretEnv(formEnv(secret), secret) },
            { "hidden id", secretEnv(formEnv(2, { [2] = secret }, {}), secret) },
        }
        for _, case in ipairs(cases) do
            local name, known = ns.make.client(case[2]).formName()
            t.ok(name == nil, case[1] .. ": name")
            t.eq(known, false, case[1] .. ": known")
        end
    end,

    -- --------------------------------------------------------- currentSpell
    ["183 currentSpell: the new read answers yes or no as given"] = function(t)
        local c = ns.make.client({ C_Spell = { IsCurrentSpell = function(id) return id == 6603 end } })
        t.eq(c.currentSpell(6603), true)
        t.eq(c.currentSpell(20271), false)
    end,

    ["183 currentSpell: the old global reads 1 as yes and nil as no"] = function(t)
        local c = ns.make.client({ IsCurrentSpell = function(id) if id == 6603 then return 1 end end })
        t.eq(c.currentSpell(6603), true)
        t.eq(c.currentSpell(20271), false)
    end,

    ["183 currentSpell: the new read wins when both are there"] = function(t)
        local env = { C_Spell = { IsCurrentSpell = function() return false end }, IsCurrentSpell = function() return 1 end }
        t.eq(ns.make.client(env).currentSpell(6603), false)
    end,

    ["183 currentSpell: a 1 or nil from the new read is not known"] = function(t)
        t.ok(ns.make.client({ C_Spell = { IsCurrentSpell = function() return 1 end } }).currentSpell(6603) == nil, "1")
        t.ok(ns.make.client({ C_Spell = { IsCurrentSpell = function() return nil end } }).currentSpell(6603) == nil, "nil")
    end,

    ["183 currentSpell: hidden, raised or no read is not known"] = function(t)
        local secret = {}
        local env = secretEnv({ C_Spell = { IsCurrentSpell = function() return secret end } }, secret)
        t.ok(ns.make.client(env).currentSpell(6603) == nil, "hidden")
        t.ok(ns.make.client({ C_Spell = { IsCurrentSpell = boom } }).currentSpell(6603) == nil, "new raises")
        t.ok(ns.make.client({ IsCurrentSpell = boom }).currentSpell(6603) == nil, "old raises")
        t.ok(ns.make.client({}).currentSpell(6603) == nil, "no read")
    end,

    ["183 currentSpell: an id that is not a number is not asked"] = function(t)
        local asked = 0
        local c = ns.make.client({ C_Spell = { IsCurrentSpell = function() asked = asked + 1; return true end } })
        t.ok(c.currentSpell("6603") == nil)
        t.ok(c.currentSpell(nil) == nil)
        t.eq(asked, 0)
    end,

    -- ----------------------------------------------------------------- fake
    ["183 fake: each read starts not known"] = function(t)
        local c = ns.make.fakeClient()
        t.ok(c.playerBuffs() == nil)
        local name, known = c.formName()
        t.ok(name == nil)
        t.eq(known, false)
        t.ok(c.currentSpell(6603) == nil)
    end,

    ["183 fake: buffs are handed back as a copy"] = function(t)
        local c = ns.make.fakeClient()
        c.setPlayerBuffs({ Blessing = 30 })
        local got = c.playerBuffs()
        t.eq(got, { Blessing = 30 })
        got.Blessing = nil
        t.eq(c.playerBuffs(), { Blessing = 30 })
        c.setPlayerBuffs({})
        t.eq(c.playerBuffs(), {})
        c.setPlayerBuffs(nil)
        t.ok(c.playerBuffs() == nil)
    end,

    ["183 fake: form name, no form and not known"] = function(t)
        local c = ns.make.fakeClient()
        c.setFormName("Cat Form")
        local name, known = c.formName()
        t.eq(name, "Cat Form")
        t.eq(known, true)
        c.setFormName(nil, true)
        name, known = c.formName()
        t.ok(name == nil)
        t.eq(known, true)
        c.setFormName(nil)
        name, known = c.formName()
        t.ok(name == nil)
        t.eq(known, false)
    end,

    ["183 fake: current spell yes, no and not known"] = function(t)
        local c = ns.make.fakeClient()
        c.setCurrentSpell(6603, true)
        c.setCurrentSpell(20271, false)
        t.eq(c.currentSpell(6603), true)
        t.eq(c.currentSpell(20271), false)
        c.setCurrentSpell(6603, nil)
        t.ok(c.currentSpell(6603) == nil)
        t.ok(c.currentSpell("6603") == nil)
    end,
}
