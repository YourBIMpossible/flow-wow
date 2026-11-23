local _, ns = ...

-- The Paladin pack: it passes PackCheck, it is for yourself and your own
-- target only, and its list gives the old order against ns.Choose.

local ALL = {
    "Devotion Aura", "Blessing of Might", "Blessing of Wisdom", "Seal of Righteousness", "Judgement",
    "Hammer of Wrath", "Holy Wrath", "Hammer of Justice", "Flash of Light", "Holy Light", "Purify",
}
local READY = { ["Devotion Aura"] = true, ["Blessing of Might"] = true, ["Seal of Righteousness"] = true }

-- An enemy targeted, in the fight, already swinging, aura, blessing and seal up.
local function snap(over, knows, buffs)
    -- N13: your own auras are read apart (ownBuffs); here every buff is yours.
    local s = { role = "dps", hostile = true, inCombat = true, dead = false, attacking = true,
                current = { Attack = true, ["Auto Attack"] = true }, spells = {}, buffs = buffs or READY,
                ownBuffs = buffs or READY }
    for _, name in ipairs(knows or ALL) do s.spells[name] = { known = true, onCooldown = false, inRange = true } end
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end

local function advice(over, knows, buffs)
    local s = ns.Choose(snap(over, knows, buffs), ns.Packs.PALADIN)
    return s and s.spell or nil, s
end

local IDLE = { hostile = false, inCombat = false }

-- Every rule for the spell, from every list of the pack.
local function rulesFor(spell)
    local out = {}
    for _, list in pairs(ns.Packs.PALADIN.lists) do
        for _, rule in ipairs(list) do
            if rule.spell == spell then out[#out + 1] = rule end
        end
    end
    return out
end

-- Does any rule for the spell fire on this snapshot (when only)?
local function fires(spell, s)
    local rules = rulesFor(spell)
    assert(#rules > 0, "no rule for " .. spell)
    for _, rule in ipairs(rules) do
        if rule.when(s) then return true end
    end
    return false
end

-- A snapshot whose buffs were not read (section 183).
local function unread(over, knows)
    local s = snap(over, knows)
    s.buffs = nil
    s.ownBuffs = nil
    return s
end

return {
    ["paladin pack passes PackCheck"] = function(t)
        local ok, problems = ns.PackCheck(ns.Packs.PALADIN)
        t.eq(table.concat(problems, "; "), "", "no problems")
        t.ok(ok, "ok")
    end,

    ["the group rows are blessings, only shown; every dispel is for yourself"] = function(t)
        local p = ns.Packs.PALADIN
        -- P-PARTY (Flow's Classes/Paladin/Rotation.lua:408-419): Kings for a
        -- tank, Might for melee, Wisdom for casters, healers and hunters,
        -- Kings for anyone else; one blessing each (slot).
        local got = {}
        for i, r in ipairs(p.groups) do
            got[i] = { r.spell, r.who, r.slot, r.aura and r.aura[2], r.evidence, r.unit }
        end
        t.eq(got, {
            { "Blessing of Kings", { "tank" }, "blessing", "Greater Blessing of Kings", "first guess", nil },
            { "Blessing of Might", { "melee", "tank" }, "blessing", "Greater Blessing of Might", "first guess", nil },
            { "Blessing of Wisdom", { "caster", "healer", "ranged" }, "blessing", "Greater Blessing of Wisdom", "first guess", nil },
            { "Blessing of Kings", "all", "blessing", "Greater Blessing of Kings", "first guess", nil },
        }, "groups")
        for _, rule in ipairs(p.dispels) do
            t.ok(not rule.group and rule.unit == nil, rule.spell .. " is not a group entry")
        end
        t.eq(p.heals.self, { "Flash of Light", "Holy Light" }, "heals are the self list")
    end,

    -- Righteous Fury and Blessing of Salvation go on yourself: the pack may
    -- suggest them (CF-33c; Salvation only once you cast it yourself).
    ["no rule suggests a spell cast on another player"] = function(t)
        local other = { ["Lay on Hands"] = true, ["Blessing of Protection"] = true, ["Redemption"] = true,
                        ["Blessing of Freedom"] = true, ["Divine Intervention"] = true }
        local p = ns.Packs.PALADIN
        for name, list in pairs(p.lists) do
            for _, rule in ipairs(list) do t.ok(not other[rule.spell], name .. ": " .. rule.spell) end
        end
        for _, rule in ipairs(p.interrupts) do t.ok(not other[rule.spell], rule.spell) end
        for _, name in ipairs(p.heals.self) do t.ok(not other[name], name) end
    end,

    ["every spell fact is a first guess: none is marked observed"] = function(t)
        local n = 0
        for name, row in pairs(ns.Packs.PALADIN.spells) do
            n = n + 1
            t.eq(row.evidence, "first guess", name)
        end
        t.ok(n >= 30, "the spell list is there")
        for name, list in pairs(ns.Packs.PALADIN.lists) do
            for _, rule in ipairs(list) do t.eq(rule.evidence, "first guess", name .. ": " .. rule.spell) end
        end
    end,

    ["spells no rule of this pack uses yet have no row"] = function(t)
        for _, name in ipairs({ "Shield of the Righteous", "Word of Glory" }) do
            t.eq(ns.Packs.PALADIN.spells[name], nil, name)
        end
    end,

    -- PC-8 (legacy Classes/Paladin/Rotation.lua:335-353): Holy Strike,
    -- Judgment and Crusader Strike on an enemy, after Judgement, in both
    -- lists; Consecration has a row and no rule (no near count is read).
    ["PC-8: the strikes and Consecration have a row, a first guess with no level"] = function(t)
        for _, name in ipairs({ "Holy Strike", "Crusader Strike", "Judgment", "Consecration" }) do
            local row = ns.Packs.PALADIN.spells[name]
            t.ok(type(row) == "table", name .. " has a row")
            t.eq(row and row.evidence, "first guess", name)
            t.eq(row and row.level, nil, name .. ": no level")
        end
    end,

    ["PC-8: the strikes come after Judgement, in the old order, in both lists"] = function(t)
        for _, list in ipairs({ "default", "aoe" }) do
            local at = {}
            for i, rule in ipairs(ns.Packs.PALADIN.lists[list]) do
                if at[rule.spell] == nil then at[rule.spell] = i end
            end
            t.ok(type(at["Holy Strike"]) == "number" and at["Judgement"] < at["Holy Strike"], list .. ": Holy Strike")
            t.ok(type(at["Judgment"]) == "number" and type(at["Holy Strike"]) == "number"
                and at["Holy Strike"] < at["Judgment"], list .. ": Judgment")
            t.ok(type(at["Crusader Strike"]) == "number" and type(at["Judgment"]) == "number"
                and at["Judgment"] < at["Crusader Strike"], list .. ": Crusader Strike")
        end
    end,

    ["PC-8: each strike on an enemy only"] = function(t)
        for _, name in ipairs({ "Holy Strike", "Crusader Strike", "Judgment" }) do
            t.eq(fires(name, snap()), true, name .. ": an enemy targeted")
            t.eq(fires(name, snap({ hostile = false })), false, name .. ": no enemy")
            local unknown = snap()
            unknown.hostile = nil
            t.eq(fires(name, unknown), false, name .. ": not known")
            for _, rule in ipairs(rulesFor(name)) do t.eq(rule.target, true, name .. ": on the target") end
        end
    end,

    ["PC-8: Crusader Strike once Judgement is on cooldown; nothing on no enemy"] = function(t)
        local knows = { "Devotion Aura", "Blessing of Might", "Seal of Righteousness", "Judgement", "Crusader Strike" }
        local function cooled(over)
            local s = snap(over, knows)
            s.spells["Judgement"].onCooldown = true
            return ns.Choose(s, ns.Packs.PALADIN)
        end
        t.eq(advice(nil, knows), "Judgement", "Judgement first")
        local got = cooled()
        t.eq(got and got.spell, "Crusader Strike", "Judgement on cooldown")
        got = cooled(IDLE)
        t.ok(not (got and got.spell == "Crusader Strike"), "no enemy: no strike")
        local both = { "Devotion Aura", "Blessing of Might", "Seal of Righteousness", "Judgement",
                       "Crusader Strike", "Holy Strike" }
        local s = snap(nil, both)
        s.spells["Judgement"].onCooldown = true
        got = ns.Choose(s, ns.Packs.PALADIN)
        t.eq(got and got.spell, "Holy Strike", "Holy Strike before Crusader Strike, as the old list")
    end,

    -- PS-1 (lead section 275): Judgment has a live rule; the chooser
    -- suggests it only while the spell is known.
    ["PS-1: Judgment is suggested only while known"] = function(t)
        local base = { "Devotion Aura", "Blessing of Might", "Seal of Righteousness", "Judgement" }
        local function pick(knows)
            local s = snap(nil, knows)
            s.spells["Judgement"].onCooldown = true
            local got = ns.Choose(s, ns.Packs.PALADIN)
            if type(got) ~= "table" then return nil end
            return got.spell
        end
        local withJ = { "Judgment" }
        for _, name in ipairs(base) do withJ[#withJ + 1] = name end
        t.eq(pick(withJ), "Judgment", "known: suggested")
        t.ok(pick(base) ~= "Judgment", "not known: not suggested")
    end,

    -- PARTLY: Consecration waits for a near-enemy count in the snapshot.
    ["PC-8: Consecration is never suggested: the snapshot has no near count"] = function(t)
        t.eq(#rulesFor("Consecration"), 0, "no rule")
        local _, ignored = ns.SnapshotOf({ enemiesNear = 3 })
        local named = false
        for _, name in ipairs(ignored or {}) do
            if name == "enemiesNear" then named = true end
        end
        t.eq(named, true, "enemiesNear is not a snapshot field")
    end,

    -- CF-32 / CF-33c: every seal and long blessing a rule can now suggest
    -- has a row (PackCheck names a rule's spell with none), with no level
    -- carried over from a guide.
    ["the seals and blessings the pack can suggest have a row"] = function(t)
        for _, name in ipairs({ "Seal of Fury", "Blessing of Kings", "Blessing of Light", "Blessing of Sanctuary",
                                "Righteous Fury", "Seal of the Crusader", "Seal of Justice", "Seal of Light",
                                "Seal of Wisdom", "Blessing of Salvation" }) do
            local row = ns.Packs.PALADIN.spells[name]
            t.ok(type(row) == "table", name .. " has a row")
            if type(row) == "table" then t.eq(row.evidence, "first guess", name) end
        end
        for _, name in ipairs({ "Seal of Fury", "Blessing of Kings", "Blessing of Light", "Blessing of Sanctuary" }) do
            t.eq(ns.Packs.PALADIN.spells[name] and ns.Packs.PALADIN.spells[name].level, nil, name .. ": no level")
        end
    end,

    ["the pack names the casts it keeps: any seal, and the long blessings only"] = function(t)
        local rows = ns.Packs.PALADIN.options.sticky
        t.eq(type(rows), "table", "options.sticky")
        local by = {}
        for _, row in ipairs(rows or {}) do by[row.key] = row end
        t.eq(by.seal and by.seal.prefix, "Seal of ", "seal row")
        t.eq(by.blessing and by.blessing.prefix, "Blessing of ", "blessing row")
        t.eq(by.blessing and by.blessing.only, {
            ["Blessing of Might"] = true, ["Blessing of Wisdom"] = true, ["Blessing of Kings"] = true,
            ["Blessing of Salvation"] = true, ["Blessing of Light"] = true, ["Blessing of Sanctuary"] = true,
        }, "the long blessings; not Protection, Freedom or Sacrifice")
        t.eq(ns.Packs.PALADIN.options.reads, { "buffs", "ownBuffs" }, "chosen is not a read: nil is no cast yet")
        t.eq(by.blessing and by.blessing.onYou, true, "a blessing is kept only once it lands on you")
        t.eq(by.seal and by.seal.onYou, nil, "a seal only ever goes on you")
        t.eq(by.seal and by.seal.word, "seal", "the seal word")
        t.eq(by.blessing and by.blessing.word, "blessing", "the blessing word")
        t.eq(by.seal and by.seal.fightOnly, true, "N58: a seal cast in a fight is for that fight")
        t.eq(by.aura and by.aura.word, "aura", "N58: the aura word")
        t.eq(by.aura and by.aura.only, { ["Devotion Aura"] = true, ["Retribution Aura"] = true,
                                        ["Concentration Aura"] = true }, "N58: the auras in the pack")
        t.eq(by.oath and by.oath.word, "oath", "N58, B3: the oath word")
        t.eq(by.oath and by.oath.only, { ["Oath of Light"] = true }, "N58, B3: Oath of Light only")
    end,

    -- N58, B3 (PARTLY): Oath of Light only once you cast or chose it.
    ["N58: Oath of Light is asked for only once you chose it, out of a fight, while not up"] = function(t)
        local mine = { chosen = { oath = "Oath of Light" } }
        local function with(over)
            local o = { hostile = false, inCombat = false, chosen = mine.chosen }
            for k, v in pairs(over or {}) do o[k] = v end
            return o
        end
        local know = { "Oath of Light" }
        t.eq(fires("Oath of Light", snap(IDLE, know, {})), false, "auto: never the add-on's pick")
        t.eq(fires("Oath of Light", snap(with(), know, {})), true, "chosen, not up: asked for")
        t.eq(fires("Oath of Light", snap(with(), know, { ["Oath of Light"] = true })), false, "up: not asked")
        t.eq(fires("Oath of Light", snap(with(), {}, {})), false, "not known: not asked")
        t.eq(fires("Oath of Light", snap(with({ inCombat = true, hostile = true }), know, {})), false, "in a fight")
        t.eq(fires("Oath of Light", unread(with(), know)), false, "buffs not read: not asked")
        t.eq(ns.PaladinOath(snap({ chosen = { oathSet = "Oath of Light" } }, know)), "Oath of Light", "the word's choice")
        t.eq(ns.PaladinOath(snap({ chosen = { oath = "Oath of Wrath" } }, know)), nil, "not an oath in the list")
        local row = ns.Packs.PALADIN.spells["Oath of Light"]
        t.eq(row and row.evidence, "first guess", "a first guess")
        t.eq(row and row.level, nil, "no trainer level")
    end,

    -- CF-32: the seal kept up. A seal you cast yourself (snapshot.chosen.seal)
    -- while you know it; else the role's seal; else Righteousness.
    ["the seal picked: the one you cast while known, else the role's"] = function(t)
        local R, C, F, X = "Seal of Righteousness", "Seal of Command", "Seal of Fury", "Seal of the Crusader"
        local cases = {
            { "dps, Righteousness only", { role = "dps" }, { R }, R },
            { "dps knows Command", { role = "dps" }, { R, C }, C },
            { "no role, knows Command", {}, { R, C }, C },
            { "healer knows Command", { role = "heal" }, { R, C }, R },
            { "tank knows Fury", { role = "tank" }, { R, C, F }, F },
            { "tank without Fury", { role = "tank" }, { R, C }, R },
            { "dps knows Fury: Fury is for a tank", { role = "dps" }, { R, F }, R },
            { "cast and known", { role = "tank", chosen = { seal = X } }, { R, F, X }, X },
            { "cast and known, dps with Command", { role = "dps", chosen = { seal = X } }, { R, C, X }, X },
            { "cast, not known now", { role = "dps", chosen = { seal = X } }, { R, C }, C },
            { "cast, no seal of this pack", { chosen = { seal = "Seal of Nothing" } }, { R, "Seal of Nothing" }, R },
            { "only a blessing cast", { chosen = { blessing = "Blessing of Kings" } }, { R, "Blessing of Kings" }, R },
        }
        for _, case in ipairs(cases) do
            local s = { spells = {} }
            for k, v in pairs(case[2]) do s[k] = v end
            for _, name in ipairs(case[3]) do s.spells[name] = { known = true } end
            t.eq(ns.PaladinSeal(s), case[4], case[1])
        end
    end,

    -- N12 (lead section 228): your cast this fight, then the seal word's
    -- choice, then the one you cast for the role, each only while known.
    ["the seal picked: this fight's cast, then the word's choice, then the role's cast"] = function(t)
        local R, X, J, L = "Seal of Righteousness", "Seal of the Crusader", "Seal of Justice", "Seal of Light"
        local cases = {
            { "the word's choice over the role's cast", { sealSet = J, seal = X }, { R, X, J }, J },
            { "this fight's cast over the word's choice", { sealFight = L, sealSet = J, seal = X }, { R, X, J, L }, L },
            { "this fight's cast not known: the choice", { sealFight = L, sealSet = J }, { R, J }, J },
            { "the choice not known: the role's cast", { sealSet = J, seal = X }, { R, X }, X },
            { "none known: the present rule", { sealFight = L, sealSet = J, seal = X }, { R }, R },
        }
        for _, case in ipairs(cases) do
            local s = { role = "dps", spells = {}, chosen = case[2] }
            for _, name in ipairs(case[3]) do s.spells[name] = { known = true } end
            t.eq(ns.PaladinSeal(s), case[4], case[1])
        end
    end,

    ["the blessing picked: the word's choice, then the role's cast; tanking Kings"] = function(t)
        local M, W, K, S = "Blessing of Might", "Blessing of Wisdom", "Blessing of Kings", "Blessing of Salvation"
        local cases = {
            { "the choice over the cast", { role = "dps", chosen = { blessingSet = S, blessing = K } }, { M, K, S }, S },
            { "the choice not known: the cast", { role = "dps", chosen = { blessingSet = S, blessing = K } }, { M, K }, K },
            { "a fight's cast is not read for a blessing", { role = "dps", chosen = { blessingFight = K } }, { M, K }, M },
            { "tank knows Kings", { role = "tank" }, { M, K }, K },
            { "tank without Kings", { role = "tank" }, { M }, M },
            { "dps knows Kings: Might", { role = "dps" }, { M, K }, M },
            { "no Might known: Kings", { role = "dps" }, { K }, K },
            { "healer: Wisdom over Kings", { role = "heal" }, { M, W, K }, W },
        }
        for _, case in ipairs(cases) do
            local s = { spells = {} }
            for k, v in pairs(case[2]) do s[k] = v end
            for _, name in ipairs(case[3]) do s.spells[name] = { known = true } end
            t.eq(ns.PaladinBlessing(s), case[4], case[1])
        end
    end,

    ["the snapshot and the driver carry your own buffs; not read stays nil"] = function(t)
        t.eq(ns.SnapshotOf({ ownBuffs = { ["Devotion Aura"] = true } }).ownBuffs, { ["Devotion Aura"] = true })
        t.eq(ns.SnapshotOf({}).ownBuffs, nil, "not given: nil")
        local read = ns.RotationDriver.Read({ ownBuffs = function() return { ["Devotion Aura"] = 5 } end },
                                            ns.Packs.PALADIN, {})
        t.eq(read("ownBuffs"), { ["Devotion Aura"] = 5 }, "asked of the client")
        t.eq(ns.RotationDriver.Read({}, ns.Packs.PALADIN, {})("ownBuffs"), nil, "no such read: nil")
    end,

    -- N13: only your own aura counts.
    ["an aura counts only when it is yours; your own not read is not known"] = function(t)
        local s = snap(IDLE, nil, { ["Devotion Aura"] = true })
        s.ownBuffs = {}
        t.ok(fires("Devotion Aura", s), "another paladin's aura up, yours not: asked for")
        s.ownBuffs = { ["Devotion Aura"] = true }
        t.ok(not fires("Devotion Aura", s), "yours up")
        s.ownBuffs = nil
        t.ok(not fires("Devotion Aura", s), "yours not read: not asked for")
        s.form = "Retribution Aura"
        t.ok(not fires("Devotion Aura", s), "your aura shown as your stance counts")
    end,

    -- The same rule for the blessing (lead section 227).
    ["the blessing picked: the long one you cast while known, else the role's"] = function(t)
        local M, W, K = "Blessing of Might", "Blessing of Wisdom", "Blessing of Kings"
        local cases = {
            { "dps", { role = "dps" }, { M, W }, M },
            { "healer knows Wisdom", { role = "heal" }, { M, W }, W },
            { "healer without Wisdom", { role = "heal" }, { M }, M },
            { "cast and known", { role = "heal", chosen = { blessing = K } }, { M, W, K }, K },
            { "cast, not known now", { role = "heal", chosen = { blessing = K } }, { M, W }, W },
            { "Protection cast: not a blessing to keep", { chosen = { blessing = "Blessing of Protection" } },
              { M, "Blessing of Protection" }, M },
            { "Salvation cast", { role = "tank", chosen = { blessing = "Blessing of Salvation" } },
              { M, "Blessing of Salvation" }, "Blessing of Salvation" },
        }
        for _, case in ipairs(cases) do
            local s = { spells = {} }
            for k, v in pairs(case[2]) do s[k] = v end
            for _, name in ipairs(case[3]) do s.spells[name] = { known = true } end
            t.eq(ns.PaladinBlessing(s), case[4], case[1])
        end
    end,

    -- PC-2: in a fight another seal up counts as missing (legacy needSeal);
    -- out of a fight any seal up is left alone (legacy wantSeal).
    ["a seal or blessing you cast is the one asked for; another seal up only out of a fight is left alone"] = function(t)
        local knows = { "Seal of Righteousness", "Seal of the Crusader", "Judgement" }
        local b = { ["Devotion Aura"] = true, ["Blessing of Might"] = true }
        local chosen = { seal = "Seal of the Crusader" }
        local other = { ["Devotion Aura"] = true, ["Blessing of Might"] = true, ["Seal of Righteousness"] = true }
        t.eq(advice({ chosen = chosen }, knows, b), "Seal of the Crusader", "none up: the seal you cast")
        t.eq(advice({ chosen = chosen }, knows, other), "Seal of the Crusader",
             "another seal up in a fight: counts as missing")
        t.eq(advice({ chosen = chosen, hostile = false, inCombat = false }, knows, other), nil,
             "another seal up out of a fight: left alone")
        t.eq(advice(nil, knows, b), "Seal of Righteousness", "nothing cast: the present rule")
        t.eq(advice({ hostile = false, inCombat = false, chosen = { blessing = "Blessing of Kings" } },
                    { "Blessing of Might", "Blessing of Kings" }, { ["Devotion Aura"] = true }),
             "Blessing of Kings", "no blessing up: the one you cast")
    end,

    -- CF-33c: Righteous Fury for a tank, out of a fight, when it is not up.
    ["Righteous Fury: role tank, out of a fight, read and not up"] = function(t)
        local function fury(over, buffs)
            local s = { role = "tank", inCombat = false, hostile = false, dead = false, buffs = buffs or {},
                        spells = { ["Righteous Fury"] = { known = true, onCooldown = false } } }
            for k, v in pairs(over or {}) do s[k] = v end
            return s
        end
        t.ok(fires("Righteous Fury", fury()), "tank, out of a fight, not up")
        t.ok(not fires("Righteous Fury", fury(nil, { ["Righteous Fury"] = true })), "up")
        t.ok(not fires("Righteous Fury", fury(nil, { ["Righteous Fury"] = 600 })), "up, time shown")
        -- PC-4: legacy needFury refreshed it under 30 s out of a fight.
        t.ok(fires("Righteous Fury", fury(nil, { ["Righteous Fury"] = 20 })), "under 30 s left: refreshed")
        t.ok(not fires("Righteous Fury", fury({ inCombat = true }, { ["Righteous Fury"] = 20 })),
             "under 30 s in a fight: left alone")
        t.ok(not fires("Righteous Fury", fury({ inCombat = true })), "in a fight")
        local s = fury()
        s.inCombat = nil
        t.ok(not fires("Righteous Fury", s), "not known whether a fight is on")
        s = fury()
        s.buffs = nil
        t.ok(not fires("Righteous Fury", s), "buffs not read")
        for _, role in ipairs({ "dps", "heal" }) do
            t.ok(not fires("Righteous Fury", fury({ role = role })), role .. ": never")
        end
        s = fury()
        s.role = nil
        t.ok(not fires("Righteous Fury", s), "no role: never")
        local knows = { "Righteous Fury", "Devotion Aura", "Blessing of Might", "Seal of Righteousness" }
        t.eq(advice({ role = "tank", hostile = false, inCombat = false }, knows, { ["Devotion Aura"] = true }),
             "Righteous Fury", "before the blessing and the seal")
        t.eq(advice({ role = "dps", hostile = false, inCombat = false }, knows, { ["Devotion Aura"] = true }),
             "Blessing of Might", "dps: the blessing")
    end,

    ["the snapshot and the driver carry the seal and blessing you cast"] = function(t)
        local s = ns.SnapshotOf({ chosen = { seal = "Seal of Light", blessing = "Blessing of Kings" } })
        t.eq(s.chosen, { seal = "Seal of Light", blessing = "Blessing of Kings" }, "kept in the snapshot")
        t.eq(ns.SnapshotOf({}).chosen, nil, "none given: nil")
        local read = ns.RotationDriver.Read({}, ns.Packs.PALADIN, {}, nil,
            { chosen = { seal = "Seal of Light" }, food = { on = false } })
        -- Section 232: one options table; chosen and food travel side by side.
        t.eq(read("chosen"), { seal = "Seal of Light" }, "the driver hands extra.chosen on")
        t.eq(read("foodOn"), false, "and extra.food beside it")
        local bare = ns.RotationDriver.Read({}, ns.Packs.PALADIN, {}, nil, { seal = "Seal of Light" })
        t.eq(bare("chosen"), nil, "a table that is not extra.chosen is not read as chosen")
        t.eq(ns.RotationDriver.Read({}, ns.Packs.PALADIN, {}, nil, nil)("chosen"), nil, "none: nil")
        t.eq(ns.RotationDriver.Read({}, ns.Packs.PALADIN, {}, nil, {})("chosen"), nil, "extra without chosen: nil")
    end,

    -- Lead section 232: both optional fields given together, each reaches its
    -- own consumer and neither lands in the other's place. extra.food is
    -- Lazy's (zflow-buff-food-2); here it only must not become chosen.
    ["the driver's extra table: chosen and food together, chosen reaches the snapshot"] = function(t)
        local c = ns.make.fakeClient()
        c.setClass("PALADIN"); c.setDead(false); c.setCombat(false)
        -- PC-6: extra.food in the driver's own cache shape (Driver.lua
        -- buffFoodKept): { on, kept, value, pack, role, pole }, a kept read.
        local value = { name = "Made-up Bread", item = 1, score = 3 }
        local food = { on = true, kept = true, value = value, pack = ns.Packs.PALADIN, role = nil, pole = nil }
        local extra = { food = food, chosen = { seal = "Seal of Light" } }
        local v = ns.RotationDriver.Step(c, ns.Packs.PALADIN, nil, nil, nil, nil, extra)
        t.eq(v.snapshot.chosen, { seal = "Seal of Light" }, "chosen from extra.chosen, not the whole table")
        t.eq(v.snapshot.buffFood, value, "and the kept food from extra.food, as the driver keeps it")
        t.eq(v.snapshot.foodOn, true, "the food setting beside it")
        local read = ns.RotationDriver.Read(c, ns.Packs.PALADIN, {}, nil, extra)
        t.eq(read("chosen"), { seal = "Seal of Light" }, "the read gives extra.chosen alone")
    end,

    ["out of a fight: aura, then blessing, then seal, then nothing"] = function(t)
        t.eq(advice(IDLE, nil, {}), "Devotion Aura", "no aura")
        t.eq(advice(IDLE, nil, { ["Devotion Aura"] = true }), "Blessing of Might", "no blessing")
        t.eq(advice(IDLE, nil, { ["Devotion Aura"] = true, ["Blessing of Might"] = 600 }),
             "Seal of Righteousness", "no seal")
        t.eq(advice(IDLE), nil, "all up")
    end,

    ["another aura, or the aura shown as your stance, counts as an aura"] = function(t)
        t.eq(advice(IDLE, nil, { ["Retribution Aura"] = true }), "Blessing of Might", "another aura")
        t.eq(advice({ hostile = false, inCombat = false, form = "Concentration Aura" }, nil, {}),
             "Blessing of Might", "the stance")
    end,

    ["a blessing is recast with under 30 s left, and never in a fight"] = function(t)
        local low = { ["Devotion Aura"] = true, ["Blessing of Might"] = 20, ["Seal of Righteousness"] = true }
        t.eq(advice(IDLE, nil, low), "Blessing of Might", "20 s left")
        t.eq(advice(nil, nil, low), "Judgement", "in a fight: left alone")
        t.eq(advice(nil, nil, { ["Devotion Aura"] = true, ["Seal of Righteousness"] = true }),
             "Judgement", "none up, in a fight")
    end,

    -- PC-2: legacy needBlessing(want): another blessing up counts as missing;
    -- a Greater one of the same name counts as up.
    ["another blessing up does not hide yours; a Greater one counts as yours"] = function(t)
        t.eq(advice(IDLE, nil, { ["Devotion Aura"] = true, ["Blessing of Kings"] = 600,
                                 ["Seal of Righteousness"] = true }), "Blessing of Might", "another blessing")
        t.eq(advice(IDLE, nil, { ["Devotion Aura"] = true, ["Greater Blessing of Might"] = 600,
                                 ["Seal of Righteousness"] = true }), nil, "Greater Blessing of Might")
        t.eq(advice(IDLE, nil, { ["Devotion Aura"] = true, ["Greater Blessing of Might"] = 20,
                                 ["Seal of Righteousness"] = true }), "Blessing of Might", "Greater, under 30 s")
        t.eq(ns.PaladinWantsBlessing({ inCombat = false, buffs = { ["Blessing of Kings"] = 600 } },
                                     "Blessing of Kings"), false, "the one asked about is up")
    end,

    -- PC-3: legacy roleSeal: a healer in a group gets Seal of Wisdom.
    ["a healer in a group is given Seal of Wisdom; alone or not read, Righteousness"] = function(t)
        local R, W, C = "Seal of Righteousness", "Seal of Wisdom", "Seal of Command"
        local cases = {
            { "healer, grouped", { role = "heal", grouped = true }, { R, W }, W },
            { "healer, alone", { role = "heal", grouped = false }, { R, W }, R },
            { "healer, group not read", { role = "heal" }, { R, W }, R },
            { "healer, grouped, Wisdom not known", { role = "heal", grouped = true }, { R }, R },
            { "dps, grouped", { role = "dps", grouped = true }, { R, W, C }, C },
            { "tank, grouped", { role = "tank", grouped = true }, { R, W }, R },
        }
        for _, case in ipairs(cases) do
            local s = { spells = {} }
            for k, v in pairs(case[2]) do s[k] = v end
            for _, name in ipairs(case[3]) do s.spells[name] = { known = true } end
            t.eq(ns.PaladinSeal(s), case[4], case[1])
        end
        t.eq(ns.SnapshotOf({ grouped = true }).grouped, true, "the snapshot keeps grouped")
        local read = ns.RotationDriver.Read({ grouped = function() return true end }, ns.Packs.PALADIN, {})
        t.eq(read("grouped"), true, "the driver asks the client")
        t.eq(ns.RotationDriver.Read({}, ns.Packs.PALADIN, {})("grouped"), nil, "no such read: nil")
    end,

    ["a healer who knows Blessing of Wisdom is given it; otherwise Might"] = function(t)
        local b = { ["Devotion Aura"] = true }
        t.eq(advice({ hostile = false, inCombat = false, role = "heal" }, nil, b), "Blessing of Wisdom", "healer")
        t.eq(advice({ hostile = false, inCombat = false, role = "heal" },
                    { "Blessing of Might", "Seal of Righteousness" }, b), "Blessing of Might", "Wisdom not known")
        t.eq(advice({ hostile = false, inCombat = false, role = "tank" }, nil, b), "Blessing of Might", "tank")
    end,

    ["the seal: recast under 3 s in a fight, under 8 s before the pull"] = function(t)
        local function with(left) return { ["Devotion Aura"] = true, ["Blessing of Might"] = true,
                                           ["Seal of Righteousness"] = left } end
        t.eq(advice(nil, nil, with(2)), "Seal of Righteousness", "2 s, fighting")
        t.eq(advice(nil, nil, with(5)), "Judgement", "5 s, fighting")
        t.eq(advice({ inCombat = false }, nil, with(5)), "Seal of Righteousness", "5 s, before the pull")
        t.eq(advice({ inCombat = false }, nil, with(20)), "Judgement", "20 s, before the pull")
        t.eq(advice(IDLE, nil, with(5)), nil, "5 s, no enemy: left alone")
        t.eq(ns.PaladinWantsSeal({ buffs = {} }), true, "none up")
        -- PC-2: in a fight another seal than the one picked counts as missing.
        t.eq(ns.PaladinWantsSeal({ buffs = { ["Seal of Light"] = true }, inCombat = true }), true,
             "another seal, in a fight")
        t.eq(ns.PaladinWantsSeal({ buffs = { ["Seal of Light"] = true }, inCombat = false, hostile = false }), false,
             "another seal, out of a fight")
        t.eq(ns.PaladinWantsSeal({ buffs = { ["Seal of Light"] = 2 }, inCombat = true }, "Seal of Light"), true,
             "the one asked about, 2 s left in a fight")
    end,

    ["a dps paladin who knows Seal of Command is given it"] = function(t)
        local knows = { "Seal of Righteousness", "Seal of Command", "Judgement" }
        local b = { ["Devotion Aura"] = true, ["Blessing of Might"] = true }
        t.eq(advice(nil, knows, b), "Seal of Command", "dps")
        t.eq(advice({ role = "heal" }, knows, b), "Seal of Righteousness", "healer")
        t.eq(advice({ role = "tank" }, knows, b), "Seal of Righteousness", "tank")
    end,

    ["Judgement only with a seal up and an enemy targeted"] = function(t)
        t.eq(advice(), "Judgement", "seal up")
        t.eq(advice(nil, { "Judgement" }, { ["Devotion Aura"] = true, ["Blessing of Might"] = true }),
             nil, "no seal, and no seal known")
        t.eq(advice({ hostile = false }), nil, "no enemy")
        local s = snap()
        s.spells.Judgement.inRange = false
        local far = ns.Choose(s, ns.Packs.PALADIN)
        t.eq(far.step, "farOpener", "out of range: shown as out of range, not as the next cast")
        t.eq(far.label, "Out of range", "label")
    end,

    ["Hammer of Wrath comes before Judgement when the game lets you cast it"] = function(t)
        local s = snap()
        s.spells["Hammer of Wrath"].usable = true
        t.eq(ns.Choose(s, ns.Packs.PALADIN).spell, "Hammer of Wrath", "usable")
        s.spells["Hammer of Wrath"].usable = false
        t.eq(ns.Choose(s, ns.Packs.PALADIN).spell, "Judgement", "not usable")
    end,

    ["not attacking yet: start the attack first"] = function(t)
        -- Lead section 348: the swing read (attacking) decides first.
        t.eq(advice({ attacking = false, current = { Attack = false } }, { "Attack", "Judgement" }), "Attack", "Attack")
        -- Lead section 348: the one Attack row reads Auto Attack too.
        t.eq(advice({ attacking = false, current = { ["Auto Attack"] = false } }, { "Attack", "Judgement" }),
             "Attack", "Auto Attack read as off")
    end,

    -- Section 183: a map not read stays nil and a rule that needs it does not fire.
    ["attack state not read: Attack is not suggested"] = function(t)
        t.eq(advice({ current = {} }, { "Attack", "Judgement" }), "Judgement", "no answer for Attack: not off")
        t.ok(not fires("Attack", snap({ current = false })), "current not read")
        t.ok(not fires("Attack", snap({ current = { ["Auto Attack"] = true } })), "Auto Attack read as on")
        local s = snap()
        s.current = nil
        t.ok(not fires("Attack", s), "current nil: Attack does not fire")
        t.eq(#(function() local n = {} for _, r in ipairs(ns.Packs.PALADIN.lists.default) do if r.spell == "Auto Attack" then n[#n + 1] = r end end return n end)(), 0,
            "no Auto Attack row (lead section 348)")
        t.ok(fires("Attack", snap({ attacking = false, current = { Attack = false } })), "read as off: it fires")
        t.ok(not fires("Attack", snap({ current = { Attack = true } })), "read as on: it does not")
        t.ok(not fires("Attack", snap({ hostile = false, current = { Attack = false } })), "no enemy: it does not")
    end,

    ["buffs not read: no aura, blessing or seal, and no Judgement"] = function(t)
        for _, over in ipairs({ IDLE, { inCombat = false }, {} }) do
            local s = unread(over)
            t.ok(not fires("Devotion Aura", s), "no aura asked for")
            t.ok(not fires("Blessing of Might", s), "no blessing asked for")
            t.ok(not fires("Seal of Righteousness", s), "no seal asked for")
        end
        t.ok(not fires("Blessing of Wisdom", unread({ hostile = false, inCombat = false, role = "heal" })),
             "no Wisdom either")
        t.ok(not fires("Seal of Command", unread()), "no Command either")
        t.ok(not fires("Judgement", unread()), "a seal not known to be up: no Judgement")
        t.eq(ns.PaladinWantsBlessing({ inCombat = false, hostile = false }), false, "blessing, buffs nil")
        t.eq(ns.PaladinWantsBlessing({ inCombat = false, hostile = false, buffs = {} }), true, "blessing, none up")
        t.eq(ns.PaladinWantsSeal({ inCombat = true }), false, "seal, buffs nil")
        t.eq(ns.PaladinWantsSeal({ inCombat = true, buffs = {} }), true, "seal, none up")
    end,

    ["buffs read and empty: aura, blessing and seal are asked for"] = function(t)
        t.ok(fires("Devotion Aura", snap(IDLE, nil, {})), "aura")
        t.ok(fires("Blessing of Might", snap(IDLE, nil, {})), "blessing")
        t.ok(fires("Seal of Righteousness", snap(IDLE, nil, {})), "seal")
        t.ok(not fires("Judgement", snap(nil, nil, {})), "no seal up: no Judgement")
    end,

    ["the aura shown as your stance counts even with buffs not read"] = function(t)
        t.ok(not fires("Devotion Aura", unread({ hostile = false, inCombat = false, form = "Devotion Aura" })),
             "form is an aura")
        t.ok(not fires("Devotion Aura", unread({ hostile = false, inCombat = false, form = "Bear Form" })),
             "form not an aura, buffs nil: still not known, not asked for")
    end,

    ["several enemies: Holy Wrath, in the fight only"] = function(t)
        local s = snap({ fightType = "aoe" })
        s.spells["Hammer of Wrath"].usable = false
        t.eq(ns.Choose(s, ns.Packs.PALADIN).spell, "Holy Wrath", "fighting")
        s.inCombat = nil
        t.eq(ns.Choose(s, ns.Packs.PALADIN).spell, "Holy Wrath", "not known whether the fight is on: as in the fight")
        s.inCombat = false
        t.eq(ns.Choose(s, ns.Packs.PALADIN).spell, "Judgement", "before the pull")
    end,

    ["low health: the quick heal on yourself"] = function(t)
        local s = snap({ lowHealth = true })
        s.spells["Flash of Light"].castMs = 1500
        s.spells["Holy Light"].castMs = 2500
        local got = ns.Choose(s, ns.Packs.PALADIN)
        t.eq(got.spell, "Flash of Light", "spell")
        t.eq(got.kind, "emergency", "kind")
        t.eq(got.step, "heal", "step")
    end,

    ["your target starts a cast: Hammer of Justice"] = function(t)
        local got = ns.Choose(snap({ targetCasting = true }), ns.Packs.PALADIN)
        t.eq(got.spell, "Hammer of Justice", "spell")
        t.eq(got.step, "interrupt", "step")
        t.eq(advice({ targetCasting = true, inCombat = false }), "Judgement", "not in a fight: no interrupt")
    end,

    ["a poison on you is removed out of a fight only"] = function(t)
        local got = ns.Choose(snap({ hostile = false, inCombat = false, debuffTypes = { Poison = true } }),
                              ns.Packs.PALADIN)
        t.eq(got.spell, "Purify", "spell")
        t.eq(got.step, "dispel", "step")
        t.eq(advice({ debuffTypes = { Poison = true } }), "Judgement", "in a fight")
        t.eq(advice({ hostile = false, inCombat = false, debuffTypes = { Magic = true } }), nil,
             "Purify does not take magic off")
    end,

    ["resting in town: no buff is asked for"] = function(t)
        t.eq(advice({ hostile = false, inCombat = false, resting = true }, nil, {}), nil, "resting")
    end,

    ["no reason spells the addon's name"] = function(t)
        local n = 0
        for _, list in pairs(ns.Packs.PALADIN.lists) do
            for _, rule in ipairs(list) do
                n = n + 1
                t.ok(not string.find(string.lower(rule.reason), "flow", 1, true), rule.spell)
            end
        end
        t.ok(n > 0, "rules were read")
    end,

    ["the key plan: one row, and it goes into the cast plan"] = function(t)
        local plan = ns.KeyPlan(ns.Packs.PALADIN, nil)
        t.eq(plan.condition, "0", "no forms")
        t.eq(plan.states, { [0] = { key = "Judgement", ctrl = "Exorcism", more = "Hammer of Wrath" } }, "states")
        plan = ns.KeyPlan(ns.Packs.PALADIN, { known = { ["Seal of Righteousness"] = true } })
        t.eq(plan.states[0], { key = "Seal of Righteousness" }, "level 1: the seal on the key")
        plan = ns.KeyPlan(ns.Packs.PALADIN, { slots = { "ctrl", "shift", "alt", "more" } })
        local r = ns.cast.Apply(plan, nil, false)
        t.eq(r.ok, true, "applied")
        t.eq(r.counts.set, 5, "five slots set")
        t.eq(r.ops[1], { op = "set", state = 0, slot = "key", spell = "Judgement" }, "key first")
    end,

    ["the paladin pack is on ns.Packs, and registered when the kernel is loaded"] = function(t)
        t.ok(type(ns.Packs.PALADIN) == "table", "ns.Packs.PALADIN")
        if type(ns.Get) == "function" then
            t.eq(ns:Get("classPack", "PALADIN"), ns.Packs.PALADIN, "registered as a classPack")
        end
    end,
}
