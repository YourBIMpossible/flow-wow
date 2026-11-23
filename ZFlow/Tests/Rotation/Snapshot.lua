local _, ns = ...

return {
    ["nothing given: flags, numbers and maps stay unknown"] = function(t)
        local s, ignored = ns.SnapshotOf(nil)
        t.eq(s.inCombat, nil, "inCombat is unknown, not no")
        t.eq(s.dead, nil, "dead is unknown, not no")
        t.eq(s.stealthed, nil, "stealthed")
        t.eq(s.lowHealth, nil, "lowHealth")
        t.eq(s.finisherReady, nil, "finisherReady")
        t.eq(s.hurt, nil, "hurt is unknown, not 0")
        t.eq(s.form, nil, "form")
        -- Section 183: a map not read is nil, never an empty "nothing up".
        t.ok(s.buffs == nil, "buffs not read: nil")
        t.ok(s.targetDebuffs == nil, "targetDebuffs not read: nil")
        t.ok(s.debuffTypes == nil, "debuffTypes not read: nil")
        t.ok(s.current == nil, "current not read: nil")
        t.eq(s.spells, {}, "spells")
        t.eq(ignored, {}, "ignored")
    end,

    ["given fields are kept, by kind"] = function(t)
        local s = ns.SnapshotOf({
            inCombat = 1, role = "dps", form = "Cat Form", formKnown = 1, finisherReady = 1, hurt = 4.5,
            buffs = { ["Mark of the Wild"] = true }, debuffTypes = { Poison = true },
        })
        t.eq(s.inCombat, true, "a flag becomes true or false")
        t.eq(s.role, "dps", "role")
        t.eq(s.form, "Cat Form", "form")
        t.eq(s.formKnown, true, "formKnown is a flag (section 186)")
        t.eq(s.finisherReady, true, "finisherReady")
        t.eq(s.hurt, 4.5, "hurt")
        t.eq(s.buffs, { ["Mark of the Wild"] = true }, "buffs")
        t.eq(s.debuffTypes, { Poison = true }, "debuffTypes")
    end,

    ["a map read as empty stays empty; a map that is not a table is not known"] = function(t)
        local s = ns.SnapshotOf({ buffs = {}, current = { Attack = false }, targetDebuffs = "x", debuffTypes = 3 })
        t.eq(s.buffs, {}, "read, none up")
        t.eq(s.current, { Attack = false }, "current kept as read")
        t.ok(s.targetDebuffs == nil, "text is not a map")
        t.ok(s.debuffTypes == nil, "a number is not a map")
    end,

    ["a number that is not a number stays unknown"] = function(t)
        local s = ns.SnapshotOf({ hurt = {} })
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
        t.eq(s.spells, { Wrath = { known = true } }, "spells")
        t.ok(s.buffs ~= fields.buffs, "buffs is a copy")
    end,

    ["spell rows: usable and range keep not read apart from no"] = function(t)
        local s = ns.SnapshotOf({ spells = {
            Wrath = { known = 1, usable = false, inRange = false, castMs = 2000 },
            Moonfire = { known = true, onCooldown = 1, castMs = "fast" },
            [7] = { known = true },
            Rip = "yes",
        } })
        t.eq(s.spells.Wrath, { known = true, usable = false, inRange = false, castMs = 2000 },
            "Wrath: cooldown not read")
        t.eq(s.spells.Moonfire, { known = true, onCooldown = true }, "Moonfire: usable and range not read")
        t.eq(s.spells[7], nil, "a row without a spell name is left out")
        t.eq(s.spells.Rip, nil, "a row that is not a table is left out")
    end,

    ["spell rows: a cooldown nobody read stays nil, no stays false, yes stays true"] = function(t)
        local s = ns.SnapshotOf({ spells = {
            Unread = { known = true },
            Ready = { known = true, onCooldown = false },
            Waiting = { known = true, onCooldown = true },
            Truthy = { known = true, onCooldown = 1 },
            Empty = {},
        } })
        t.eq(s.spells.Unread.onCooldown, nil, "not read: not known, not ready")
        t.eq(s.spells.Ready.onCooldown, false, "read: ready")
        t.eq(s.spells.Waiting.onCooldown, true, "read: on cooldown")
        t.eq(s.spells.Truthy.onCooldown, true, "any other yes")
        t.eq(s.spells.Empty, {}, "an empty row stays empty")
        local again = ns.SnapshotOf({ spells = s.spells })
        t.eq(again.spells, s.spells, "building from built rows keeps all three")
    end,

    ["a cooldown nobody read: the built snapshot gives no suggestion for that spell"] = function(t)
        local function tank(row)
            local built = ns.SnapshotOf({ role = "tank", hostile = true, attacking = true, dead = false,
                inCombat = false, spells = { ["Bear Form"] = row } })
            local pick = ns.Choose(built, ns.Packs.DRUID, {}, nil)
            return pick and pick.spell or nil
        end
        t.eq(tank({ known = true, onCooldown = false }), "Bear Form", "read, ready")
        t.ok(tank({ known = true }) ~= "Bear Form", "not read: not suggested")
        t.ok(tank({ known = true, onCooldown = true }) ~= "Bear Form", "read, on cooldown")
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
            if name == "hurt" then return 8 end
            if name == "buffs" then return { Thorns = true } end
        end)
        t.eq(count, #ns.Rotation.SNAPSHOT_FIELDS, "one question per field")
        for _, f in ipairs(ns.Rotation.SNAPSHOT_FIELDS) do
            t.eq(asked[f[1]], 1, f[1])
        end
        t.eq(s.inCombat, true, "inCombat")
        t.eq(s.hurt, 8, "hurt")
        t.eq(s.buffs, { Thorns = true }, "buffs")
        t.eq(s.hostile, nil, "a field the reader did not answer stays unknown")
    end,

    ["Snapshot without a reader is the empty snapshot"] = function(t)
        t.eq(ns.Snapshot(nil), ns.SnapshotOf({}), "no reader")
        t.eq(ns.Snapshot("reader"), ns.SnapshotOf({}), "not a function")
        -- The empty snapshot spelled out here, field by field, from the kinds.
        local empty = { spells = {} }   -- flag, value, number and map: nil
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
        local fields = { inCombat = true, hurt = 2, spells = { Claw = { known = true, usable = true } } }
        t.eq(ns.SnapshotOf(fields), ns.SnapshotOf(fields), "same answer")
        t.eq(fields, { inCombat = true, hurt = 2, spells = { Claw = { known = true, usable = true } } }, "fields not changed")
        -- Two tables built apart with the same fields: equal, and nothing shared.
        local twin = { inCombat = true, hurt = 2, spells = { Claw = { known = true, usable = true } } }
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
        local suggestion, trace = ns.Choose(ns.SnapshotOf({ dead = false }), ns.Packs.DRUID, {}, nil)
        t.eq(suggestion, nil, "nothing to suggest when alive is all that is known")
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
        local built = ns.SnapshotOf({ role = "tank", hostile = true, attacking = true, dead = false, inCombat = false,
            spells = { ["Bear Form"] = { known = true, onCooldown = false } } })
        local pick, why = ns.Choose(built, ns.Packs.DRUID, {}, nil)
        t.ok(type(pick) == "table", "a tank with an enemy targeted is given something")
        t.eq(pick and pick.spell, "Bear Form", "Bear Form")
        t.eq(why[#why].result, "pick", "the trace ends in the pick")
        t.ok(why[#why].step ~= "input", "from a step, not the input check")
    end,
}
