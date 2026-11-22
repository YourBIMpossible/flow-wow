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
        t.eq(s.finisherReady, false, "no source yet")
    end,
}
