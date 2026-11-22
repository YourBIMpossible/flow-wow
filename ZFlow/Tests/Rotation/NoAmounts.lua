local _, ns = ...

-- Health and power amounts are hidden from addon code on this client, so the
-- snapshot has no field made from one, and the chooser and the packs decide
-- from what the game does say: its low-health warning, the estimate from
-- being hit, whether a spell is usable, and whether it lacks power.

local R = ns.Rotation

local function known(list, into)
    into = into or {}
    for _, name in ipairs(list or {}) do into[name] = { known = true, onCooldown = false, inRange = true } end
    return into
end

local function heals(pack)
    local spells = known(pack.heals.self)
    return known(pack.heals.hots, spells)
end

local function spellOf(snapshot, pack)
    local s = ns.Choose(ns.SnapshotOf(snapshot), pack)
    return s and s.spell or nil
end

local AMOUNTS = { hpPct = 0.95, combo = 5, outOfMana = true, canSpareMana = true }

return {
    ["no amounts: the fields made from health and power are named"] = function(t)
        t.eq(R.FROM_AMOUNT, { hpPct = "health", outOfMana = "power", canSpareMana = "power", combo = "power" }, "list")
    end,

    ["no amounts: the snapshot has no such field"] = function(t)
        for _, f in ipairs(R.SNAPSHOT_FIELDS) do
            t.eq(R.FROM_AMOUNT[f[1]], nil, f[1] .. " is not made from an amount")
        end
    end,

    ["no amounts: handed in anyway, they are left out and reported"] = function(t)
        local s, ignored = ns.SnapshotOf(AMOUNTS)
        for name in pairs(R.FROM_AMOUNT) do
            t.eq(s[name], nil, name .. " is not kept")
        end
        t.eq(ignored, { "canSpareMana", "combo", "hpPct", "outOfMana" }, "ignored")
    end,

    ["no amounts: the reader is never asked for one"] = function(t)
        local asked = {}
        ns.Snapshot(function(name) asked[name] = true end)
        for name in pairs(R.FROM_AMOUNT) do
            t.eq(asked[name], nil, name .. " is not asked for")
        end
        t.ok(asked.lowHealth, "the game's warning is asked for")
    end,

    ["no amounts: a snapshot table carrying them does not change the choice"] = function(t)
        -- Even a caller that skips SnapshotOf gets the same answer.
        local pack = ns.Packs.DRUID
        local plain = { lowHealth = true, inCombat = false, dead = false, spells = heals(pack) }
        local loud = { lowHealth = true, inCombat = false, dead = false, spells = heals(pack) }
        for k, v in pairs(AMOUNTS) do loud[k] = v end
        local a, b = ns.Choose(plain, pack), ns.Choose(loud, pack)
        t.ok(a and a.kind == "heal", "a heal")
        t.eq(b and b.spell, a and a.spell, "the same heal with a health share of 95% handed in")
    end,

    ["no amounts: the game's low-health warning alone still gets a heal"] = function(t)
        for _, class in ipairs({ "DRUID", "PALADIN" }) do
            local pack = ns.Packs[class]
            local s = ns.Choose(ns.SnapshotOf({ lowHealth = true, inCombat = false, dead = false, spells = heals(pack) }), pack)
            t.ok(s and s.kind == "heal", class .. ": a heal")
            t.ok(ns.Choose(ns.SnapshotOf({ lowHealth = true, inCombat = true, dead = false, hostile = true,
                                           spells = heals(pack) }), pack)
                .kind == "emergency", class .. ": an emergency in a fight")
        end
    end,

    ["no amounts: the estimate from being hit alone still gets a heal"] = function(t)
        for _, class in ipairs({ "DRUID", "PALADIN" }) do
            local pack = ns.Packs[class]
            local s = ns.Choose(ns.SnapshotOf({ hurt = R.HURT.outBig + 5, inCombat = false, dead = false, spells = heals(pack) }), pack)
            t.ok(s and s.kind == "heal", class .. ": a heal")
        end
    end,

    ["no amounts: with neither sign no heal is suggested"] = function(t)
        for _, class in ipairs({ "DRUID", "PALADIN" }) do
            local pack = ns.Packs[class]
            local s = ns.Choose(ns.SnapshotOf({ inCombat = false, dead = false, spells = heals(pack) }), pack)
            t.ok(not s or (s.kind ~= "heal" and s.kind ~= "emergency"), class .. ": no heal")
        end
    end,

    ["no amounts: a finisher only on the reader's say-so, never on a count"] = function(t)
        local spells = known({ "Ferocious Bite", "Rip", "Claw", "Cat Form" })
        local base = { role = "dps", hostile = true, inCombat = true, dead = false, form = "Cat Form",
                       attacking = true, targetNear = true, spells = spells }
        local got = spellOf(base, ns.Packs.DRUID)
        t.ok(got ~= "Ferocious Bite" and got ~= "Rip", "nothing said: no finisher")
        base.combo = 5
        got = spellOf(base, ns.Packs.DRUID)
        t.ok(got ~= "Ferocious Bite" and got ~= "Rip", "a count handed in is not read")
        base.combo, base.finisherReady = nil, true
        t.eq(spellOf(base, ns.Packs.DRUID), "Ferocious Bite", "the reader says a finisher is due")
    end,

    ["no amounts: out of power is the game refusing the spell, not a mana figure"] = function(t)
        local function caster(wrath, over)
            local f = { role = "dps", hostile = true, inCombat = true, dead = false, targetNear = true,
                        targetDebuffs = { Moonfire = true },
                        spells = { Wrath = wrath, Moonfire = { known = true, onCooldown = false, inRange = true }, Attack = { known = true, onCooldown = false, inRange = true } } }
            for k, v in pairs(over or {}) do f[k] = v end
            wrath.inRange = true
            return spellOf(f, ns.Packs.DRUID)
        end
        t.eq(caster({ known = true, onCooldown = false, usable = true }), "Wrath", "Wrath is usable")
        t.eq(caster({ known = true, onCooldown = false, usable = true }, { outOfMana = true }), "Wrath", "a mana flag handed in is not read")
        t.eq(caster({ known = true, onCooldown = false, usable = false, noPower = true }), "Attack", "the game says Wrath lacks power: weapon")
        t.ok(caster({ known = true, onCooldown = false, usable = false }) ~= "Attack", "refused for another reason: no out-of-power advice")
        t.ok(caster({ known = true }) ~= "Attack", "nothing read: no out-of-power advice")
    end,

    ["no amounts: a spell row keeps lacks-power apart from not read"] = function(t)
        local s = ns.SnapshotOf({ spells = { A = { known = true, noPower = 1 }, B = { known = true, noPower = false },
                                             C = { known = true } } })
        t.eq(s.spells.A.noPower, true, "lacks power")
        t.eq(s.spells.B.noPower, false, "has the power")
        t.eq(s.spells.C.noPower, nil, "not read")
    end,

    ["no amounts: Nature's Grasp needs no mana figure, only to be castable"] = function(t)
        local function grasp(row)
            return spellOf({ role = "dps", hostile = true, inCombat = true, dead = false, targetMelee = true,
                             targetOnYou = true, hittingYou = true, targetNear = true,
                             spells = { ["Nature's Grasp"] = row, Wrath = { known = true, onCooldown = false, inRange = true } } }, ns.Packs.DRUID)
        end
        t.eq(grasp({ known = true, onCooldown = false }), "Nature's Grasp", "castable: suggested")
        t.ok(grasp({ known = true, onCooldown = false, usable = false, noPower = true }) ~= "Nature's Grasp", "the game refuses it: not suggested")
    end,
}
