-- The rotation reader: spell rows for the snapshot, built from what the
-- client says about each spell a class pack names. The fake client stands
-- in for the game.
local _, ns = ...

local function pack(names)
    local spells = {}
    for _, n in ipairs(names) do spells[n] = { evidence = "first guess" } end
    return { spells = spells }
end

local function reader(c)
    return function(id) return c.spell(id) end
end

return {
    ["names: every spell the pack names, sorted"] = function(t)
        t.eq(ns.RotationReader.SpellNames(pack({ "Wrath", "Attack", "Moonfire" })), { "Attack", "Moonfire", "Wrath" })
        t.eq(ns.RotationReader.SpellNames(nil), {})
        t.eq(ns.RotationReader.SpellNames({}), {})
    end,

    ["names: the Druid pack's own list"] = function(t)
        local names = ns.RotationReader.SpellNames(ns.Packs.DRUID)
        local has = {}
        for _, n in ipairs(names) do has[n] = true end
        t.ok(has["Wrath"], "Wrath")
        t.ok(#names > 5, "more than a handful")
    end,

    ["rows: what the client said, field for field"] = function(t)
        local c = ns.make.fakeClient()
        c.setSpell(5176, { known = true, usable = false, noPower = true })
        c.setSpell(8921, { known = true, usable = true, noPower = false })
        local r = ns.RotationReader.SpellRows(pack({ "Wrath", "Moonfire" }), { Wrath = 5176, Moonfire = 8921 }, reader(c))
        t.eq(r.rows, {
            Wrath = { known = true, usable = false, noPower = true },
            Moonfire = { known = true, usable = true, noPower = false },
        })
        t.eq(r.unread, {})
    end,

    ["rows: a field the client did not give stays nil, never false"] = function(t)
        local c = ns.make.fakeClient()
        c.setSpell(5176, { known = true })
        c.setSpell(8921, { usable = false })
        local r = ns.RotationReader.SpellRows(pack({ "Wrath", "Moonfire" }), { Wrath = 5176, Moonfire = 8921 }, reader(c))
        t.eq(r.rows.Wrath.known, true)
        t.eq(r.rows.Wrath.usable, nil, "usable not read")
        t.eq(r.rows.Wrath.noPower, nil, "noPower not read")
        t.eq(r.rows.Moonfire.known, nil, "known not read")
        t.eq(r.rows.Moonfire.usable, false)
        t.eq(r.rows.Moonfire.noPower, nil)
    end,

    ["rows: a spell the client says nothing about is an empty row"] = function(t)
        local c = ns.make.fakeClient()
        local r = ns.RotationReader.SpellRows(pack({ "Wrath" }), { Wrath = 5176 }, reader(c))
        t.eq(r.rows, { Wrath = {} })
        t.eq(r.unread, {})
    end,

    ["rows: a spell with no id is not read and is named"] = function(t)
        local c = ns.make.fakeClient()
        c.setSpell(5176, { known = true, usable = true, noPower = false })
        local asked = {}
        local r = ns.RotationReader.SpellRows(pack({ "Wrath", "Moonfire", "Attack" }), { Wrath = 5176, Attack = "x" },
            function(id) asked[#asked + 1] = id return c.spell(id) end)
        t.eq(r.rows, { Wrath = { known = true, usable = true, noPower = false } })
        t.eq(r.unread, { "Attack", "Moonfire" })
        t.eq(asked, { 5176 }, "only a real id is asked")
    end,

    ["rows: only spells the pack names are read"] = function(t)
        local c = ns.make.fakeClient()
        c.setSpell(1, { known = true })
        c.setSpell(2, { known = true })
        local r = ns.RotationReader.SpellRows(pack({ "Wrath" }), { Wrath = 1, Fireball = 2 }, reader(c))
        t.eq(r.rows, { Wrath = { known = true } })
    end,

    ["rows: a read that fails or answers oddly is unread, not false"] = function(t)
        local r = ns.RotationReader.SpellRows(pack({ "Wrath", "Moonfire", "Attack" }), { Wrath = 1, Moonfire = 2, Attack = 3 },
            function(id)
                if id == 1 then error("the client refused") end
                if id == 2 then return "yes" end
                return { known = 1, usable = "no", noPower = false, hp = 40 }
            end)
        t.eq(r.rows, { Attack = { noPower = false } }, "only plain booleans are kept, nothing else copied")
        t.eq(r.unread, { "Moonfire", "Wrath" })
    end,

    ["rows: no reader, no pack: nothing read"] = function(t)
        t.eq(ns.RotationReader.SpellRows(pack({ "Wrath" }), { Wrath = 1 }, nil), { rows = {}, unread = { "Wrath" } })
        t.eq(ns.RotationReader.SpellRows(nil, nil, nil), { rows = {}, unread = {} })
    end,

    ["rows: the reader is asked for a spell id and nothing else"] = function(t)
        local args = {}
        ns.RotationReader.SpellRows(pack({ "Wrath" }), { Wrath = 5176 }, function(...)
            args[#args + 1] = { n = select("#", ...), ... }
            return {}
        end)
        t.eq(#args, 1)
        t.eq(args[1].n, 1, "one argument: no unit is ever named")
        t.eq(args[1][1], 5176)
    end,

    ["rows feed the snapshot: nil and false stay apart, no finisherReady"] = function(t)
        local c = ns.make.fakeClient()
        c.setSpell(5176, { known = true, usable = false, noPower = true })
        c.setSpell(8921, { known = true })
        local r = ns.RotationReader.SpellRows(pack({ "Wrath", "Moonfire" }), { Wrath = 5176, Moonfire = 8921 }, reader(c))
        local s, ignored = ns.SnapshotOf({ spells = r.rows })
        t.eq(ignored, {})
        t.eq(s.spells.Wrath.noPower, true)
        t.eq(s.spells.Wrath.usable, false)
        t.eq(s.spells.Moonfire.usable, nil)
        t.eq(s.spells.Moonfire.noPower, nil)
        t.eq(s.finisherReady, nil, "no source yet: not known, not no")
    end,

    ["cooldown: fields: the row may carry onCooldown"] = function(t)
        local has = false
        for _, f in ipairs(ns.RotationReader.FIELDS) do has = has or f == "onCooldown" end
        t.ok(has, "onCooldown is a row field")
    end,

    ["cooldown: the client's yes, no and not known are each kept"] = function(t)
        local c = ns.make.fakeClient()
        c.setSpell(1, { known = true, usable = true })
        c.setSpell(2, { known = true, usable = true })
        c.setSpell(3, { known = true, usable = true })
        local answers = { [1] = false, [2] = true }
        local r = ns.RotationReader.SpellRows(pack({ "Wrath", "Moonfire", "Attack" }), { Wrath = 1, Moonfire = 2, Attack = 3 },
            reader(c), function(id) return answers[id] end)
        t.eq(r.rows, {
            Wrath = { known = true, usable = true, onCooldown = false },
            Moonfire = { known = true, usable = true, onCooldown = true },
            Attack = { known = true, usable = true },
        })
        t.eq(r.rows.Attack.onCooldown, nil, "not known stays nil, never false")
        t.eq(r.unread, {}, "a cooldown not known does not make the spell unread")
    end,

    ["cooldown: no cooldown reader: nothing is said about it"] = function(t)
        local c = ns.make.fakeClient()
        c.setSpell(1, { known = true, usable = true })
        local r = ns.RotationReader.SpellRows(pack({ "Wrath" }), { Wrath = 1 }, reader(c))
        t.eq(r.rows, { Wrath = { known = true, usable = true } })
        r = ns.RotationReader.SpellRows(pack({ "Wrath" }), { Wrath = 1 }, reader(c), "not a function")
        t.eq(r.rows, { Wrath = { known = true, usable = true } }, "not a function: not asked")
    end,

    ["cooldown: a read that fails or answers oddly is not known, not ready"] = function(t)
        local c = ns.make.fakeClient()
        for id = 1, 5 do c.setSpell(id, { known = true }) end
        local r = ns.RotationReader.SpellRows(pack({ "A", "B", "C", "D", "E" }), { A = 1, B = 2, C = 3, D = 4, E = 5 },
            reader(c), function(id)
                if id == 1 then error("the client refused") end
                if id == 2 then return 0 end
                if id == 3 then return "no" end
                if id == 4 then return {} end
                return false
            end)
        t.eq(r.rows, {
            A = { known = true }, B = { known = true }, C = { known = true }, D = { known = true },
            E = { known = true, onCooldown = false },
        }, "only a plain true or false is kept")
        t.eq(r.unread, {})
    end,

    ["cooldown: asked by spell id alone, once for each spell that was read"] = function(t)
        local c = ns.make.fakeClient()
        c.setSpell(5176, { known = true })
        local args = {}
        local r = ns.RotationReader.SpellRows(pack({ "Wrath", "Moonfire", "Attack" }), { Wrath = 5176, Moonfire = 8921 },
            function(id)
                if id == 8921 then error("the client refused") end
                return c.spell(id)
            end,
            function(...)
                args[#args + 1] = { n = select("#", ...), ... }
                return false
            end)
        t.eq(#args, 1, "not asked for a spell with no id, nor for one whose read failed")
        t.eq(args[1].n, 1, "one argument: no unit is ever named")
        t.eq(args[1][1], 5176)
        t.eq(r.rows, { Wrath = { known = true, onCooldown = false } })
        t.eq(r.unread, { "Attack", "Moonfire" })
    end,

    ["cooldown: the cooldown reader decides, whatever the spell's own answer carried"] = function(t)
        local function rowsWith(cooldown)
            return ns.RotationReader.SpellRows(pack({ "Wrath" }), { Wrath = 1 },
                function() return { known = true, onCooldown = true } end, cooldown).rows
        end
        t.eq(rowsWith(nil), { Wrath = { known = true, onCooldown = true } }, "no cooldown reader: the answer's own")
        t.eq(rowsWith(function() return false end), { Wrath = { known = true, onCooldown = false } }, "the reader says ready")
        t.eq(rowsWith(function() return nil end), { Wrath = { known = true } }, "the reader does not know: not known")
    end,

    ["cooldown: read rows make a spell castable, not castable, or not known, and the trace says which"] = function(t)
        local R = ns.Rotation
        local c = ns.make.fakeClient()
        c.setSpell(133, { known = true, usable = true, noPower = false })
        local p = { spells = { Bolt = { evidence = "first guess" } },
                    lists = { default = { { spell = "Bolt", target = true, evidence = "first guess" } } } }
        local function fight(cooldown)
            local r = ns.RotationReader.SpellRows(p, { Bolt = 133 }, reader(c), function() return cooldown end)
            r.rows.Bolt.inRange = true
            return ns.SnapshotOf({ inCombat = true, dead = false, hostile = true, spells = r.rows })
        end
        local function listNote(trace)
            for _, row in ipairs(trace) do
                if row.step == "list" then return row.note end
            end
        end
        local function says(note)
            return type(note) == "string" and string.find(note, R.COOLDOWN_UNKNOWN, 1, true) ~= nil
        end

        local s = fight(false)
        local ok, why = R.Castable(s, "Bolt")
        t.eq(ok, true, "read, ready: castable")
        t.eq(why, nil)
        local got = ns.Choose(s, p)
        t.eq(got and got.spell, "Bolt", "and suggested")

        s = fight(true)
        ok, why = R.Castable(s, "Bolt")
        t.eq(ok, false, "read, on cooldown: not castable")
        t.eq(why, nil, "a plain no")
        local trace
        got, trace = ns.Choose(s, p)
        t.eq(got, nil, "not suggested")
        t.eq(listNote(trace), "no rule ready", "on cooldown is not 'not known'")

        s = fight(nil)
        t.eq(s.spells.Bolt.onCooldown, nil, "not known reaches the snapshot as nil")
        ok, why = R.Castable(s, "Bolt")
        t.eq(ok, false, "not known: not castable")
        t.eq(why, R.COOLDOWN_UNKNOWN, "with its own reason")
        ok, why = R.Ready(s, "Bolt", true)
        t.eq(ok, false, "Ready follows")
        t.eq(why, R.COOLDOWN_UNKNOWN, "and hands the reason on")
        got, trace = ns.Choose(s, p)
        t.eq(got, nil, "not suggested")
        local note = listNote(trace)
        t.ok(says(note), "the trace gives the reason")
        t.ok(type(note) == "string" and string.find(note, "Bolt", 1, true) ~= nil, "and names the spell")
        for _, row in ipairs(trace) do
            if row.step ~= "list" then t.ok(not says(row.note), row.step .. ": no such note where the spell was not weighed") end
        end
    end,
}
