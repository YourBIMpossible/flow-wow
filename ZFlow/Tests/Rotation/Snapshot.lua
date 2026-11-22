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
        -- The empty snapshot spelled out here, field by field, from the kinds.
        local empty = { flag = false, map = {}, spells = {} }   -- value and number: nil
        for _, reader in ipairs({ false, "reader" }) do
            local s = ns.Snapshot(reader or nil)
            local label = reader and "not a function" or "no reader"
            t.eq(type(s), "table", label .. ": a table")
            local names = {}
            for _, f in ipairs(ns.Rotation.SNAPSHOT_FIELDS) do
                names[f[1]] = true
                t.eq(s[f[1]], empty[f[2]], label .. ": " .. f[1])
            end
            for key in pairs(s) do
                t.ok(names[key] == true, label .. ": no field outside the list (" .. tostring(key) .. ")")
            end
        end
    end,

    ["the same fields give the same snapshot"] = function(t)
        local fields = { inCombat = true, combo = 2, spells = { Claw = { known = true, usable = true } } }
        t.eq(ns.SnapshotOf(fields), ns.SnapshotOf(fields), "same answer")
        t.eq(fields, { inCombat = true, combo = 2, spells = { Claw = { known = true, usable = true } } }, "fields not changed")
        -- Two tables built apart with the same fields: equal, and nothing shared.
        local twin = { inCombat = true, combo = 2, spells = { Claw = { known = true, usable = true } } }
        local a, b = ns.SnapshotOf(fields), ns.SnapshotOf(twin)
        t.eq(a, b, "equal fields in two tables give equal snapshots")
        t.ok(a ~= b and a.spells ~= b.spells, "each call builds its own tables")
        t.ok(a.spells ~= fields.spells and a.spells.Claw ~= fields.spells.Claw, "none of them the caller's")
        -- Nothing is kept between calls: writing to one answer reaches no other.
        a.spells.Claw.known = false
        a.inCombat = false
        t.eq(fields, twin, "the fields are untouched by a write to the snapshot")
        t.eq(ns.SnapshotOf(fields), b, "and the next snapshot is the same as before")
    end,

    ["the chooser takes a built snapshot"] = function(t)
        local suggestion, trace = ns.Choose(ns.SnapshotOf({}), ns.Packs.DRUID, {}, nil)
        t.eq(suggestion, nil, "nothing to suggest from an empty snapshot")
        t.ok(type(trace) == "table" and #trace > 0, "a trace comes back")
        -- Taken, not refused: every step looked at it. A refused input gives
        -- one "input" row instead.
        local steps = ns.Rotation.STEPS
        t.eq(#trace, #steps, "one trace row for every step")
        for i, name in ipairs(steps) do
            local row = trace[i] or {}
            t.eq(row.step, name, "row " .. i .. " is the " .. name .. " step")
            t.eq(row.result, "skip", name .. " had nothing to pick")
        end
        local none, refused = ns.Choose(nil, ns.Packs.DRUID, {}, nil)
        t.eq(none, nil, "no snapshot: nothing")
        t.eq(refused, { { step = "input", result = "skip", note = "no snapshot or no pack" } },
            "and that is the refusal the empty snapshot did not get")
        -- A built snapshot with something to do gives a suggestion.
        local built = ns.SnapshotOf({ role = "tank", hostile = true, attacking = true,
            spells = { ["Bear Form"] = { known = true } } })
        local pick, why = ns.Choose(built, ns.Packs.DRUID, {}, nil)
        t.ok(type(pick) == "table", "a tank with an enemy targeted is given something")
        t.eq(pick and pick.spell, "Bear Form", "Bear Form")
        t.eq(why[#why].result, "pick", "the trace ends in the pick")
        t.ok(why[#why].step ~= "input", "from a step, not the input check")
    end,
}
