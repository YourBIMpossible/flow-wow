-- P-READS (lead sections 237 item 4, 242, 248, 260 item 1; Plexy's
-- RESEARCH-P-READS.md): the shared reads for the class packs, on the real
-- client over a hand-built environment, then on ClientFake's twin. Every
-- read answers what the client said, or nil when not known; a value the
-- client marks secret is not known. Every client name here is a first
-- guess unless the client names table lists it. Made-up names and
-- numbers. Not tested in game.
local _, ns = ...

local tests = {}

local SECRET = {}   -- what this env's issecretvalue calls hidden

-- An issecretvalue that refuses nil, as the client's does.
local function base(extra)
    local env = {}
    env.issecretvalue = function(v)
        if v == nil then error("issecretvalue: nil") end
        return rawequal(v, SECRET)
    end
    env.GetTime = function() return 1000 end
    for k, v in pairs(extra or {}) do env[k] = v end
    return env
end

-- Frames that take events; env.send(name, ...) is the client raising one.
local function eventEnv()
    local env = base({ frames = {} })
    function env.CreateFrame()
        local f = { scripts = {}, events = {} }
        function f:SetScript(script, fn) self.scripts[script] = fn end
        function f:RegisterEvent(name) self.events[name] = true end
        function f:UnregisterEvent(name) self.events[name] = nil end
        env.frames[#env.frames + 1] = f
        return f
    end
    function env.send(name, ...)
        for _, f in ipairs(env.frames) do
            if f.events[name] and f.scripts.OnEvent then f.scripts.OnEvent(f, name, ...) end
        end
    end
    return env
end

-- ------------------------------------------------------ secret event args
tests["reads listen: a secret event argument reaches a listener as nil, the rest as given"] = function(t)
    local env = eventEnv()
    local c = ns.make.client(env)
    local got
    c.listen("UNIT_SPELLCAST_SUCCEEDED", function(...) got = { n = select("#", ...), ... } end)
    env.send("UNIT_SPELLCAST_SUCCEEDED", "player", SECRET, 5176)
    t.eq(got, { n = 3, "player", nil, 5176 }, "the cast id hidden: nil, the count kept")
    env.send("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", SECRET)
    t.eq(got, { n = 3, "player", "Cast-1", nil }, "the spell id hidden: nil")
    env.send("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 5176)
    t.eq(got, { n = 3, "player", nil, 5176 }, "a nil argument is never asked about")
end

tests["reads listen: a check that raises counts as secret; no check passes all as given"] = function(t)
    local env = eventEnv()
    env.issecretvalue = function(v) if v == "odd" then error("no") end return false end
    local c = ns.make.client(env)
    local got
    c.listen("X_EVENT", function(...) got = { ... } end)
    env.send("X_EVENT", "odd", 2)
    t.eq(got, { nil, 2 }, "the check raised: not known")
    local env2 = eventEnv()
    env2.issecretvalue = nil
    local c2 = ns.make.client(env2)
    c2.listen("X_EVENT", function(...) got = { ... } end)
    env2.send("X_EVENT", SECRET, 2)
    t.ok(rawequal(got[1], SECRET), "no issecretvalue: passed as given")
end

-- ------------------------------------------------------------- own channel
local function channelEnv(answer)
    return base({ UnitChannelInfo = function(unit)
        if unit ~= "player" then return nil end
        if answer == "raise" then error("no") end
        if answer == nil then return nil end
        return unpack(answer, 1, 8)
    end })
end

tests["reads channel: what you channel, its spell id and when it ends"] = function(t)
    local c = ns.make.client(channelEnv({ "Arcane Missiles", "", 136096, 999000, 1004500, false, false, 5143 }))
    t.eq(c.channel(), { name = "Arcane Missiles", spellId = 5143, endsAt = 1004.5 })
    t.eq(ns.make.client(channelEnv(nil)).channel(), false, "no channel: false")
end

tests["reads channel: hidden, raised or no read: nil"] = function(t)
    t.eq(ns.make.client(channelEnv({ SECRET, "", 1, 1, 2, false, false, 1 })).channel(), nil, "name hidden")
    t.eq(ns.make.client(channelEnv({ "Evocation", "", 1, 1, SECRET, false, false, 12051 })).channel(), nil,
        "end hidden")
    t.eq(ns.make.client(channelEnv("raise")).channel(), nil, "raised")
    t.eq(ns.make.client(base()).channel(), nil, "no read")
    local c = ns.make.client(channelEnv({ "Blizzard", "", 1, 1, 1002000, false, false, SECRET }))
    t.eq(c.channel(), { name = "Blizzard", endsAt = 1002 }, "spell id hidden: left out")
end

-- ---------------------------------------------------------- weapon enchant
tests["reads weaponEnchant: the C_Item read per hand, time left in seconds"] = function(t)
    local asked = {}
    local env = base({ C_Item = { GetWeaponEnchantInfo = function(slot)
        asked[#asked + 1] = slot
        if slot == 0 then return { { hasEnchant = true, timeLeft = 1800000, charges = 60, enchantID = 7 } } end
        if slot == 1 then return { { hasEnchant = false } } end
        return nil
    end } })
    t.eq(ns.make.client(env).weaponEnchant(), {
        main = { has = true, left = 1800, charges = 60 },
        off = { has = false },
    })
    t.eq(asked, { 0, 1 }, "main hand 0, off hand 1")
end

tests["reads weaponEnchant: a single row answer is read too; an empty list is a bare hand"] = function(t)
    local env = base({ C_Item = { GetWeaponEnchantInfo = function(slot)
        if slot == 0 then return { hasEnchant = true, timeLeft = 60000 } end
        return {}
    end } })
    t.eq(ns.make.client(env).weaponEnchant(), { main = { has = true, left = 60 }, off = { has = false } })
end

tests["reads weaponEnchant: the old global with no argument when there is no C_Item read"] = function(t)
    local env = base({ GetWeaponEnchantInfo = function(...)
        t.eq(select("#", ...), 0, "asked with no argument")
        return true, 900000, 0, 25, false, nil, nil, nil
    end })
    t.eq(ns.make.client(env).weaponEnchant(), { main = { has = true, left = 900, charges = 0 }, off = { has = false } })
end

tests["reads weaponEnchant: hidden or odd parts are left out; raised or no read is nil"] = function(t)
    local env = base({ C_Item = { GetWeaponEnchantInfo = function(slot)
        if slot == 0 then return { { hasEnchant = true, timeLeft = SECRET, charges = SECRET } } end
        return { { hasEnchant = SECRET } }
    end } })
    t.eq(ns.make.client(env).weaponEnchant(), { main = { has = true }, off = {} })
    local raise = base({ C_Item = { GetWeaponEnchantInfo = function() error("no") end } })
    t.eq(ns.make.client(raise).weaponEnchant(), nil, "raised")
    t.eq(ns.make.client(base()).weaponEnchant(), nil, "no read")
    local hiddenAll = base({ C_Item = { GetWeaponEnchantInfo = function() return SECRET end } })
    t.eq(ns.make.client(hiddenAll).weaponEnchant(), nil, "the whole answer hidden")
end

-- ----------------------------------------------------------------- totems
tests["reads totems: each slot as the client gives it"] = function(t)
    local env = base({ GetTotemInfo = function(slot)
        if slot == 1 then return true, "Searing Totem", 990, 30, 135825, 1, 3599 end
        if slot == 2 then return false, "", 0, 0, nil end
        if slot == 3 then return true, SECRET, 990, 60, 1 end
        return true, "Grace of Air Totem", 900, 120, 1, 1, SECRET
    end })
    t.eq(ns.make.client(env).totems(), {
        [1] = { name = "Searing Totem", spellId = 3599, left = 20 },
        [2] = false,
        [4] = { name = "Grace of Air Totem", left = 20 },
    }, "slot 3 hidden: left out")
end

tests["reads totems: no read or a read that raised is nil"] = function(t)
    t.eq(ns.make.client(base()).totems(), nil)
    t.eq(ns.make.client(base({ GetTotemInfo = function() error("no") end })).totems(), nil)
end

-- ------------------------------------------------------------ target buffs
tests["reads targetBuffs: the target's buffs by name, the name from the spell id when not given"] = function(t)
    local rows = {
        { name = "Power Word: Fortitude", expirationTime = 1300 },
        { spellId = 1126, expirationTime = 0 },
    }
    local env = base({
        C_UnitAuras = { GetAuraDataByIndex = function(unit, i, filter)
            t.eq({ unit, filter }, { "target", "HELPFUL" })
            return rows[i]
        end },
        C_Spell = { GetSpellInfo = function(id) if id == 1126 then return { name = "Mark of the Wild" } end end },
    })
    t.eq(ns.make.client(env).targetBuffs(), { ["Power Word: Fortitude"] = 300, ["Mark of the Wild"] = math.huge })
end

tests["reads targetBuffs: a row not read makes the list not known"] = function(t)
    local env = base({ C_UnitAuras = { GetAuraDataByIndex = function(_, i)
        if i == 1 then return { spellId = SECRET } end
    end } })
    t.eq(ns.make.client(env).targetBuffs(), nil)
    t.eq(ns.make.client(base()).targetBuffs(), nil, "no read")
    local none = base({ C_UnitAuras = { GetAuraDataByIndex = function() return nil end } })
    t.eq(ns.make.client(none).targetBuffs(), {}, "read, none")
end

-- --------------------------------------------------- the whole buff length
tests["reads buffLength: the whole length of a unit's buff, from the client"] = function(t)
    local env = base({ C_UnitAuras = { GetAuraDataByIndex = function(unit, i)
        if unit ~= "party1" then return nil end
        return ({ { name = "Thorns", duration = 600, expirationTime = 1500 },
                  { name = "Mark of the Wild", duration = 3600, expirationTime = 4598 } })[i]
    end } })
    local c = ns.make.client(env)
    t.eq({ c.buffLength("party1", { "Mark of the Wild" }) }, { 3600, "Mark of the Wild" })
    t.eq(c.buffLength("party1", { "Arcane Intellect" }), false, "read, not there")
    local old = base({ UnitBuff = function(unit, i)
        if i == 1 then return "Thorns", 1, 0, nil, 0, 0 end
    end })
    t.eq({ ns.make.client(old).buffLength("party1", { "Thorns" }) }, { math.huge, "Thorns" }, "no end")
    local hiddenLen = base({ C_UnitAuras = { GetAuraDataByIndex = function(_, i)
        if i == 1 then return { name = "Thorns", duration = SECRET } end
    end } })
    t.eq({ ns.make.client(hiddenLen).buffLength("party1", { "Thorns" }) }, { nil, "Thorns" }, "there, length hidden")
    t.eq(ns.make.client(base()).buffLength("party1", { "Thorns" }), nil, "no read")
end

-- ----------------------------------------------------------------- pet hurt
local function petEnv(extra)
    extra = extra or {}
    return base({
        UnitExists = function(u) return u == "pet" end,
        UnitIsDead = function() return false end,
        UnitAffectingCombat = function() return false end,
        UnitHealth = extra.UnitHealth,
        UnitHealthMax = extra.UnitHealthMax,
        UnitHealthPercent = extra.UnitHealthPercent,
    })
end

tests["reads pet hurt: health under its most when both are plain numbers"] = function(t)
    local hurt = petEnv({ UnitHealth = function() return 50 end, UnitHealthMax = function() return 100 end })
    t.eq(ns.make.client(hurt).pet().hurt, true)
    local full = petEnv({ UnitHealth = function() return 100 end, UnitHealthMax = function() return 100 end })
    t.eq(ns.make.client(full).pet().hurt, false)
end

tests["reads pet hurt: hidden amounts fall to the share read, else not known"] = function(t)
    local share = petEnv({ UnitHealth = function() return SECRET end, UnitHealthMax = function() return 100 end,
        UnitHealthPercent = function() return 0.4 end })
    t.eq(ns.make.client(share).pet().hurt, true, "share under 1")
    local whole = petEnv({ UnitHealth = function() return SECRET end,
        UnitHealthPercent = function() return 1 end })
    t.eq(ns.make.client(whole).pet().hurt, false, "share 1")
    local hundred = petEnv({ UnitHealthPercent = function() return 64 end })
    t.eq(ns.make.client(hundred).pet().hurt, true, "on a scale of 100")
    local none = petEnv({ UnitHealth = function() return SECRET end, UnitHealthMax = function() return SECRET end,
        UnitHealthPercent = function() return SECRET end })
    t.eq(ns.make.client(none).pet().hurt, nil, "all hidden")
    t.eq(ns.make.client(petEnv()).pet().hurt, nil, "no read")
end

-- ------------------------------------------------- plates: count, casts, type
-- Plates by unit token; each unit: { attack, combat, threat, targetsYou,
-- close, cast = {...}, channel = {...}, kind }.
local function plateEnv(units, extra)
    local list, by = {}, {}
    for _, u in ipairs(units or {}) do
        list[#list + 1] = { namePlateUnitToken = u.unit }
        by[u.unit] = u
    end
    local env = base({
        C_NamePlate = { GetNamePlates = function() if units == nil then return nil end return list end },
        UnitCanAttack = function(_, u) return by[u] and by[u].attack end,
        UnitAffectingCombat = function(u) return by[u] and by[u].combat end,
        UnitThreatSituation = function(_, u) return by[u] and by[u].threat end,
        UnitName = function(u) return by[u] and by[u].name end,
        C_UnitAuras = { GetAuraDataByIndex = function(u, i, filter)
            local d = filter == "HARMFUL" and by[u] and by[u].debuffs
            if d == SECRET then return SECRET end
            if type(d) == "table" and d[i] ~= nil then return { name = d[i] } end
        end },
        UnitIsUnit = function(a, b)
            if b == "target" then return by[a] and by[a].isTarget end
            local u = a:match("^(nameplate%d+)target$")
            return u ~= nil and b == "player" and by[u] ~= nil and by[u].targetsYou == true
        end,
        CheckInteractDistance = function(u, n) if n == 3 and by[u] then return by[u].close end end,
        UnitCastingInfo = function(u) local x = by[u] and by[u].cast if x then return unpack(x, 1, 9) end end,
        UnitChannelInfo = function(u) local x = by[u] and by[u].channel if x then return unpack(x, 1, 8) end end,
        UnitCreatureType = function(u) if u == "target" then return "Humanoid" end return by[u] and by[u].kind end,
    })
    for k, v in pairs(extra or {}) do env[k] = v end
    return env
end

tests["reads enemiesNear: hostile plates in a fight, those on you and those close"] = function(t)
    local env = plateEnv({
        { unit = "nameplate1", attack = true, combat = true, threat = 3, close = true },
        { unit = "nameplate2", attack = true, combat = true, threat = nil, targetsYou = true, close = false },
        { unit = "nameplate3", attack = true, combat = true, threat = nil, close = true },
        { unit = "nameplate4", attack = true, combat = false, close = true },
        { unit = "nameplate5", attack = false, combat = true, close = true },
    })
    t.eq({ ns.make.client(env).enemiesNear() }, { 3, 2, 2 }, "near 3, close 2, on you 2")
end

tests["reads enemiesNear: no plate list, or a plate not read, is not known; none is 0"] = function(t)
    t.eq(ns.make.client(plateEnv(nil)).enemiesNear(), nil, "no list: nil, never 0")
    t.eq({ ns.make.client(plateEnv({})).enemiesNear() }, { 0, 0, 0 }, "a list with none")
    local odd = plateEnv({ { unit = "nameplate1", attack = SECRET, combat = true } })
    t.eq(ns.make.client(odd).enemiesNear(), nil, "a hidden answer")
    local far = plateEnv({ { unit = "nameplate1", attack = true, combat = true, threat = 1 } },
        { CheckInteractDistance = function() error("refused in a fight") end })
    t.eq({ ns.make.client(far).enemiesNear() }, { 1, nil, 1 }, "the distance refused: close not known")
    local bad = plateEnv({ { unit = "party1", attack = true, combat = true } })
    t.eq(ns.make.client(bad).enemiesNear(), nil, "a plate with no plate unit")
end

-- Lead section 262: the row shapes of Twin 10:02Z INTERFACE line. plateCasts
-- rows { unit, name (the enemy), spell (the spell name), interruptible,
-- isTarget }, plus spellId, channel and endsAt.
tests["reads plateCasts: casts and channels on plate units, in the class-b row shape"] = function(t)
    local env = plateEnv({
        { unit = "nameplate1", name = "Kobold Geomancer", isTarget = true,
          cast = { "Fireball", "", 1, 999000, 1002500, false, "id", false, 133 } },
        { unit = "nameplate2", name = "Defias Warlock", isTarget = false,
          channel = { "Drain Life", "", 1, 999000, 1004000, false, true, 689 } },
        { unit = "nameplate3", name = "Murloc" },
        { unit = "nameplate4", cast = { SECRET, "", 1, 1, 2, false, "id", false, 1 } },
        { unit = "nameplate5", name = SECRET, isTarget = SECRET,
          cast = { "Frostbolt", "", 1, 999000, 1003000, false, "id", false, 116 } },
    })
    t.eq(ns.make.client(env).plateCasts(), {
        { unit = "nameplate1", name = "Kobold Geomancer", spell = "Fireball", spellId = 133, channel = false,
          endsAt = 1002.5, interruptible = true, isTarget = true },
        { unit = "nameplate2", name = "Defias Warlock", spell = "Drain Life", spellId = 689, channel = true,
          endsAt = 1004, interruptible = false, isTarget = false },
        { unit = "nameplate5", spell = "Frostbolt", spellId = 116, channel = false, endsAt = 1003, interruptible = true },
    }, "a hidden spell: left out; a hidden enemy name or target answer: that field left out")
    t.eq(ns.make.client(plateEnv(nil)).plateCasts(), nil, "no plate list")
end

-- plateEnemies rows { unit, name, isTarget, creature, controlled, threat }:
-- the plates you can attack. controlled: a crowd-control debuff on it (first
-- guess names). A field not read is left out; never false in its place.
tests["reads plateEnemies: the plates you can attack, in the class-b row shape"] = function(t)
    local env = plateEnv({
        { unit = "nameplate1", name = "Kobold Geomancer", attack = true, isTarget = true, kind = "Humanoid",
          threat = 3, debuffs = {} },
        { unit = "nameplate2", name = "Young Wolf", attack = true, isTarget = false, kind = "Beast",
          threat = SECRET, debuffs = { "Rend", "Polymorph" } },
        { unit = "nameplate3", name = "Guard", attack = false, kind = "Humanoid" },
        { unit = "nameplate4", name = "Odd", attack = SECRET, kind = "Humanoid" },
        { unit = "nameplate5", name = SECRET, attack = true, isTarget = false, kind = SECRET, threat = 0,
          debuffs = SECRET },
    })
    t.eq(ns.make.client(env).plateEnemies(), {
        { unit = "nameplate1", name = "Kobold Geomancer", isTarget = true, creature = "Humanoid", threat = 3,
          controlled = false },
        { unit = "nameplate2", name = "Young Wolf", isTarget = false, creature = "Beast", controlled = true },
        { unit = "nameplate5", isTarget = false, threat = 0 },
    }, "not attackable or not known: left out; a hidden field: left out")
    t.eq(ns.make.client(plateEnv(nil)).plateEnemies(), nil, "no plate list: nil")
    t.eq(ns.make.client(plateEnv({})).plateEnemies(), {}, "a list with none: empty")
end

tests["reads creatureType: target or a plate unit, as the client names it"] = function(t)
    local c = ns.make.client(plateEnv({ { unit = "nameplate1", kind = "Beast" }, { unit = "nameplate2", kind = SECRET } }))
    t.eq(c.creatureType("target"), "Humanoid")
    t.eq(c.creatureType("nameplate1"), "Beast")
    t.eq(c.creatureType("nameplate2"), nil, "hidden")
    t.eq(c.creatureType("party1"), nil, "not a unit it asks about")
end

-- -------------------------------------------------------------- the fake
tests["reads fake: each read answers what was set, and nil before"] = function(t)
    local c = ns.make.fakeClient()
    t.eq(c.channel(), nil); t.eq(c.totems(), nil); t.eq(c.targetBuffs(), nil)
    t.eq(c.enemiesNear(), nil); t.eq(c.plateCasts(), nil); t.eq(c.creatureType("target"), nil)
    t.eq(c.plateEnemies(), nil)
    c.setChannel({ name = "Evocation", spellId = 12051, endsAt = 20 })
    t.eq(c.channel(), { name = "Evocation", spellId = 12051, endsAt = 20 })
    c.setChannel(false); t.eq(c.channel(), false)
    c.setTotems({ [1] = { name = "Searing Totem", left = 20 }, [2] = false })
    t.eq(c.totems(), { [1] = { name = "Searing Totem", left = 20 }, [2] = false })
    c.setTargetBuffs({ ["Mark of the Wild"] = 300 })
    t.eq(c.targetBuffs(), { ["Mark of the Wild"] = 300 })
    c.setEnemiesNear(3, 1, 2)
    t.eq({ c.enemiesNear() }, { 3, 1, 2 })
    c.setPlateCasts({ { unit = "nameplate1", name = "Kobold", spell = "Fireball", isTarget = false } })
    t.eq(c.plateCasts(), { { unit = "nameplate1", name = "Kobold", spell = "Fireball", isTarget = false } })
    c.setPlateEnemies({ { unit = "nameplate1", name = "Kobold", creature = "Humanoid", controlled = false } })
    t.eq(c.plateEnemies(), { { unit = "nameplate1", name = "Kobold", creature = "Humanoid", controlled = false } })
    c.setCreatureType("target", "Beast")
    t.eq(c.creatureType("target"), "Beast")
end

tests["reads fake: pet hurt, the buff length and a secret event argument"] = function(t)
    local c = ns.make.fakeClient()
    c.setPet({ exists = true, hurt = true })
    t.eq(c.pet().hurt, true)
    c.setPet({ exists = true, hurt = "yes" })
    t.eq(c.pet().hurt, nil, "not a yes or no")
    c.setUnitBuffs("party1", { { name = "Thorns", left = 500, length = 600 } })
    t.eq({ c.buffLength("party1", { "Thorns" }) }, { 600, "Thorns" })
    t.eq(c.buffLength("party1", { "Mark of the Wild" }), false)
    t.eq(c.buffLength("party2", { "Thorns" }), nil, "not set")
    local got
    c.listen("UNIT_SPELLCAST_SUCCEEDED", function(...) got = { n = select("#", ...), ... } end)
    c.fireSecret("UNIT_SPELLCAST_SUCCEEDED", "player", c.SECRET, 5176)
    t.eq(got, { n = 3, "player", nil, 5176 }, "as the real client hands it on: nil")
end

return tests
