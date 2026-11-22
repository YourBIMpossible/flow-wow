local _, ns = ...

return {
    ["nothing given: flags are false, maps are empty, numbers stay unknown"] = function(t)
        local s, ignored = ns.SnapshotOf(nil)
        t.eq(s.inCombat, false, "inCombat")
        t.eq(s.stealthed, false, "stealthed")
        t.eq(s.lowHealth, false, "lowHealth")
        t.eq(s.hpPct, nil, "hpPct is unknown, not 0")
        t.eq(s.combo, nil, "combo is unknown, not 0")
        t.eq(s.hurt, nil, "hurt is unknown, not 0")
        t.eq(s.form, nil, "form")
        t.eq(s.buffs, {}, "buffs")
        t.eq(s.targetDebuffs, {}, "targetDebuffs")
        t.eq(s.spells, {}, "spells")
        t.eq(ignored, {}, "ignored")
    end,

    ["given fields are kept, by kind"] = function(t)
        local s = ns.SnapshotOf({
            inCombat = 1, role = "dps", form = "Cat Form", combo = 3, hpPct = 42,
            buffs = { ["Mark of the Wild"] = true }, debuffTypes = { Poison = true },
        })
        t.eq(s.inCombat, true, "a flag becomes true or false")
        t.eq(s.role, "dps", "role")
        t.eq(s.form, "Cat Form", "form")
        t.eq(s.combo, 3, "combo")
        t.eq(s.hpPct, 42, "hpPct")
        t.eq(s.buffs, { ["Mark of the Wild"] = true }, "buffs")
        t.eq(s.debuffTypes, { Poison = true }, "debuffTypes")
    end,

    ["a number that is not a number stays unknown"] = function(t)
        local s = ns.SnapshotOf({ hpPct = "low", combo = true, hurt = {} })
        t.eq(s.hpPct, nil, "hpPct")
        t.eq(s.combo, nil, "combo")
        t.eq(s.hurt, nil, "hurt")
    end,

    ["a value that is a table or a function is left out"] = function(t)
        local s = ns.SnapshotOf({ role = {}, form = function() end })
        t.eq(s.role, nil, "role")
        t.eq(s.form, nil, "form")
    end,

    ["the snapshot shares nothing with what it was given"] = function(t)
        local fields = { buffs = { Thorns = true }, spells = { Wrath = { known = true } } }
        local s = ns.SnapshotOf(fields)
        fields.buffs.Thorns = nil
        fields.buffs.Other = true
        fields.spells.Wrath.known = false
        fields.spells.Moonfire = { known = true }
        t.eq(s.buffs, { Thorns = true }, "buffs")
        t.eq(s.spells, { Wrath = { known = true, onCooldown = false } }, "spells")
        t.ok(s.buffs ~= fields.buffs, "buffs is a copy")
    end,

    ["spell rows: usable and range keep not read apart from no"] = function(t)
        local s = ns.SnapshotOf({ spells = {
            Wrath = { known = 1, usable = false, inRange = false, castMs = 2000 },
            Moonfire = { known = true, onCooldown = 1, castMs = "fast" },
            [7] = { known = true },
            Rip = "yes",
        } })
        t.eq(s.spells.Wrath, { known = true, onCooldown = false, usable = false, inRange = false, castMs = 2000 }, "Wrath")
        t.eq(s.spells.Moonfire, { known = true, onCooldown = true }, "Moonfire: usable and range not read")
        t.eq(s.spells[7], nil, "a row without a spell name is left out")
        t.eq(s.spells.Rip, nil, "a row that is not a table is left out")
    end,

    ["fields it does not know are left out and named, sorted"] = function(t)
        local s, ignored = ns.SnapshotOf({ zebra = 1, apple = 2, inCombat = true })
        t.eq(ignored, { "apple", "zebra" }, "ignored")
        t.eq(s.zebra, nil, "zebra")
        t.eq(s.apple, nil, "apple")
        t.eq(s.inCombat, true, "inCombat")
    end,

    ["Snapshot asks the reader once for every field"] = function(t)
        local asked, count = {}, 0
        local s = ns.Snapshot(function(name)
            asked[name] = (asked[name] or 0) + 1
            count = count + 1
            if name == "inCombat" then return true end
            if name == "hpPct" then return 80 end
            if name == "buffs" then return { Thorns = true } end
        end)
        t.eq(count, #ns.Rotation.SNAPSHOT_FIELDS, "one question per field")
        for _, f in ipairs(ns.Rotation.SNAPSHOT_FIELDS) do
            t.eq(asked[f[1]], 1, f[1])
        end
        t.eq(s.inCombat, true, "inCombat")
        t.eq(s.hpPct, 80, "hpPct")
        t.eq(s.buffs, { Thorns = true }, "buffs")
        t.eq(s.hostile, false, "a field the reader did not answer")
    end,

    ["Snapshot without a reader is the empty snapshot"] = function(t)
        t.eq(ns.Snapshot(nil), ns.SnapshotOf({}), "no reader")
        t.eq(ns.Snapshot("reader"), ns.SnapshotOf({}), "not a function")
    end,

    ["the same fields give the same snapshot"] = function(t)
        local fields = { inCombat = true, combo = 2, spells = { Claw = { known = true, usable = true } } }
        t.eq(ns.SnapshotOf(fields), ns.SnapshotOf(fields), "same answer")
        t.eq(fields, { inCombat = true, combo = 2, spells = { Claw = { known = true, usable = true } } }, "fields not changed")
    end,

    ["the chooser takes a built snapshot"] = function(t)
        local suggestion, trace = ns.Choose(ns.SnapshotOf({}), ns.Packs.DRUID, {}, nil)
        t.eq(suggestion, nil, "nothing to suggest from an empty snapshot")
        t.ok(type(trace) == "table" and #trace > 0, "a trace comes back")
    end,
}
