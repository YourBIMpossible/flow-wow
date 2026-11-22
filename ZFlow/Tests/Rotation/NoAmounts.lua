local _, ns = ...

-- A client that hides health and power amounts: the snapshot carries none of
-- the fields made from them, and the chooser still answers from the rest.

local R = ns.Rotation

local function known(list, into)
    into = into or {}
    for _, name in ipairs(list or {}) do into[name] = { known = true } end
    return into
end

local function heals(pack)
    local spells = known(pack.heals.self)
    return known(pack.heals.hots, spells)
end

return {
    ["no amounts: the fields made from health and power are named"] = function(t)
        t.eq(R.FROM_AMOUNT, { hpPct = "health", outOfMana = "power", canSpareMana = "power", combo = "power" }, "list")
    end,

    ["no amounts: left out, numbers stay unknown and flags read no"] = function(t)
        local s = ns.SnapshotOf({ inCombat = true })
        t.eq(s.hpPct, nil, "health share unknown, not 0 and not 1")
        t.eq(s.combo, nil, "combo points unknown, not 0")
        t.eq(s.outOfMana, false, "not out of mana")
        t.eq(s.canSpareMana, false, "no mana to spare")
    end,

    ["no amounts: the game's low-health warning alone still gets a heal"] = function(t)
        for _, class in ipairs({ "DRUID", "PALADIN" }) do
            local pack = ns.Packs[class]
            local s = ns.Choose(ns.SnapshotOf({ lowHealth = true, spells = heals(pack) }), pack)
            t.ok(s and s.kind == "heal", class .. ": a heal")
            t.ok(ns.Choose(ns.SnapshotOf({ lowHealth = true, inCombat = true, hostile = true, spells = heals(pack) }), pack)
                .kind == "emergency", class .. ": an emergency in a fight")
        end
    end,

    ["no amounts: the estimate from being hit alone still gets a heal"] = function(t)
        for _, class in ipairs({ "DRUID", "PALADIN" }) do
            local pack = ns.Packs[class]
            local s = ns.Choose(ns.SnapshotOf({ hurt = R.HURT.outBig + 5, spells = heals(pack) }), pack)
            t.ok(s and s.kind == "heal", class .. ": a heal")
        end
    end,

    ["no amounts: with neither sign no heal is suggested"] = function(t)
        for _, class in ipairs({ "DRUID", "PALADIN" }) do
            local pack = ns.Packs[class]
            local s = ns.Choose(ns.SnapshotOf({ spells = heals(pack) }), pack)
            t.ok(not s or (s.kind ~= "heal" and s.kind ~= "emergency"), class .. ": no heal")
        end
    end,

    ["no amounts: unknown combo points never spend a finisher"] = function(t)
        local spells = known({ "Ferocious Bite", "Rip", "Claw", "Cat Form" })
        local s = ns.Choose(ns.SnapshotOf({ role = "dps", hostile = true, inCombat = true, form = "Cat Form",
                                         attacking = true, targetNear = true, spells = spells }), ns.Packs.DRUID)
        t.ok(not s or (s.spell ~= "Ferocious Bite" and s.spell ~= "Rip"), "no finisher")
        local five = ns.Choose(ns.SnapshotOf({ role = "dps", hostile = true, inCombat = true, form = "Cat Form", combo = 5,
                                            attacking = true, targetNear = true, spells = spells }), ns.Packs.DRUID)
        t.eq(five and five.spell, "Ferocious Bite", "with a count given it still does")
    end,
}
