local _, ns = ...
-- A spell row whose `known` nobody read stays nil through the snapshot (not
-- read is not "not known"), the chooser does not suggest such a spell, and
-- the ids table for the reader is built by asking a name-to-id function.
local R = ns.Rotation
local RR = ns.RotationReader

local function pack(names)
    local spells = {}
    for _, n in ipairs(names) do spells[n] = { evidence = "first guess" } end
    return { spells = spells }
end

local function fightPack()
    return { lists = { default = { { spell = "Bolt", target = true, evidence = "first guess" } } } }
end

local function fight(row)
    return ns.SnapshotOf({ inCombat = true, dead = false, hostile = true, spells = { Bolt = row } })
end

local T = {}

T["snapshot: known not read stays nil, no stays false, yes stays true"] = function(t)
    local s = ns.SnapshotOf({ spells = {
        Wrath = { usable = true },
        Moonfire = { known = false },
        Attack = { known = 1 },
        Claw = {},
    } })
    t.eq(s.spells.Wrath.known, nil, "not read")
    t.eq(s.spells.Wrath.usable, true)
    t.eq(s.spells.Moonfire.known, false, "read: no")
    t.eq(s.spells.Attack.known, true, "read: yes")
    t.eq(s.spells.Claw, {}, "an empty row: known not read, cooldown not read")
end

T["snapshot: the reader's rows keep known nil"] = function(t)
    local c = ns.make.fakeClient()
    c.setSpell(5176, { usable = true, noPower = false })
    local r = RR.SpellRows(pack({ "Wrath" }), { Wrath = 5176 }, function(id) return c.spell(id) end)
    local s = ns.SnapshotOf({ spells = r.rows })
    t.eq(s.spells.Wrath.known, nil)
    t.eq(s.spells.Wrath.usable, true)
end

T["chooser: known not read is not known, not castable, not ready"] = function(t)
    local s = fight({ usable = true, inRange = true, onCooldown = false })
    t.eq(R.Knows(s, "Bolt"), false)
    t.eq(R.Castable(s, "Bolt"), false)
    t.eq(R.Ready(s, "Bolt", true), false)
end

T["chooser: a spell whose known was not read is not suggested"] = function(t)
    local yes = ns.Choose(fight({ known = true, usable = true, onCooldown = false }), fightPack())
    t.eq(yes and yes.spell, "Bolt", "known: suggested")
    local unread = ns.Choose(fight({ usable = true, onCooldown = false }), fightPack())
    t.eq(unread, nil, "known not read: nothing")
    local no = ns.Choose(fight({ known = false, usable = true, onCooldown = false }), fightPack())
    t.eq(no, nil, "not known: nothing")
end

T["chooser: the attack is not started on a known nobody read"] = function(t)
    local s = ns.SnapshotOf({ inCombat = false, dead = false, hostile = true, canStartAttack = true,
                               spells = { Attack = {} } })
    t.eq(ns.Choose(s, fightPack()), nil)
    s = ns.SnapshotOf({ inCombat = false, dead = false, hostile = true, canStartAttack = true, stealthed = false,
                         spells = { Attack = { known = true } } })
    local pick = ns.Choose(s, fightPack())
    t.eq(pick and pick.spell, "Attack")
end

T["ids: one question per pack spell, answered by the client's name-to-id"] = function(t)
    local c = ns.make.fakeClient()
    c.setSpellId("Wrath", 5176)
    c.setSpellId("Moonfire", 8921)
    local asked = {}
    local ids, missing = RR.SpellIds(pack({ "Wrath", "Moonfire", "Attack" }), function(...)
        asked[#asked + 1] = { n = select("#", ...), ... }
        return c.spellId(...)
    end)
    t.eq(ids, { Wrath = 5176, Moonfire = 8921 })
    t.eq(missing, { "Attack" }, "no id: named, not guessed")
    t.eq(#asked, 3)
    t.eq(asked[1].n, 1, "asked by name alone")
    t.eq({ asked[1][1], asked[2][1], asked[3][1] }, { "Attack", "Moonfire", "Wrath" }, "in name order")
end

T["ids: only a number is an id; a failed ask is missing"] = function(t)
    local ids, missing = RR.SpellIds(pack({ "A", "B", "C", "D", "E" }), function(name)
        if name == "A" then return "5176" end
        if name == "B" then error("the client refused") end
        if name == "C" then return 0 / 0 end
        if name == "D" then return 133 end
        return nil
    end)
    t.eq(ids, { D = 133 })
    t.eq(missing, { "A", "B", "C", "E" })
end

T["ids: no function or no pack: nothing asked"] = function(t)
    local ids, missing = RR.SpellIds(pack({ "Wrath" }), nil)
    t.eq(ids, {})
    t.eq(missing, { "Wrath" })
    ids, missing = RR.SpellIds(nil, function() return 1 end)
    t.eq(ids, {})
    t.eq(missing, {})
end

T["ids feed the reader: names to ids to rows"] = function(t)
    local c = ns.make.fakeClient()
    c.setSpellId("Wrath", 5176)
    c.setSpell(5176, { known = true, usable = true, noPower = false })
    local p = pack({ "Wrath", "Moonfire" })
    local ids = RR.SpellIds(p, c.spellId)
    local r = RR.SpellRows(p, ids, c.spell)
    t.eq(r.rows, { Wrath = { known = true, usable = true, noPower = false } })
    t.eq(r.unread, { "Moonfire" })
end

T["chooser: a target nobody read is not no target, and a spell that needs one is not suggested"] = function(t)
    local s = ns.SnapshotOf({ inCombat = true, dead = false,
        spells = { Bolt = { known = true, usable = true, onCooldown = false } } })
    t.ok(s.hostile == nil, "hostile not read stays nil through the snapshot")
    local got, trace = ns.Choose(s, fightPack())
    t.eq(got, nil, "target not known: nothing")
    local note
    for _, row in ipairs(trace) do
        if row.step == "list" then note = row.note end
    end
    t.eq(note, "no rule ready; not known whether you have a target: Bolt", "and the trace says why")
    local yes = ns.Choose(fight({ known = true, usable = true, onCooldown = false }), fightPack())
    t.eq(yes and yes.spell, "Bolt", "an enemy targeted: suggested")
end

return T
