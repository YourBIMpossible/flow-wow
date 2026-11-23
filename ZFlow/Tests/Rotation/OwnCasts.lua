local _, ns = ...

-- Tests for ZFlow/Rotation/OwnCasts.lua (CF-32, lead sections 226, 227):
-- which of your own casts the class pack keeps, by its options.sticky rows.
-- Pure: OC.Note only. The module end to end is in Tests/E2E/PaladinRotation.lua.

local tests = {}

local ROWS = {
    { prefix = "Seal of ", key = "seal" },
    { prefix = "Blessing of ", key = "blessing", only = { ["Blessing of Kings"] = true } },
}

local function OC() return ns.OwnCasts end

tests["own casts: a name with a row's prefix gives that row's key"] = function(t)
    t.eq(OC().Note(ROWS, "Seal of the Crusader"), "seal")
    t.eq(OC().Note(ROWS, "Seal of Fury"), "seal")
    t.eq(OC().Note(ROWS, "Blessing of Kings"), "blessing")
end

tests["own casts: a row with `only` takes only the names in it"] = function(t)
    t.eq(OC().Note(ROWS, "Blessing of Protection"), nil, "not in only")
    t.eq(OC().Note(ROWS, "Blessing of Freedom"), nil, "not in only")
end

tests["own casts: anything else is no key"] = function(t)
    t.eq(OC().Note(ROWS, "Judgement"), nil, "no prefix")
    t.eq(OC().Note(ROWS, "Greater Seal of Light"), nil, "the prefix not at the start")
    t.eq(OC().Note(ROWS, "Seal of "), nil, "the prefix alone")
    t.eq(OC().Note(ROWS, nil), nil, "no name")
    t.eq(OC().Note(ROWS, 20271), nil, "an id, not a name")
    t.eq(OC().Note(nil, "Seal of Light"), nil, "no rows")
    t.eq(OC().Note({ { key = "seal" }, "x", { prefix = "Seal of " } }, "Seal of Light"), nil, "rows without prefix or key")
end

tests["own casts: the paladin pack's rows keep any seal and the six long blessings"] = function(t)
    local rows = ns.Packs.PALADIN.options.sticky
    for _, name in ipairs({ "Seal of Righteousness", "Seal of the Crusader", "Seal of Command", "Seal of Justice",
                            "Seal of Light", "Seal of Wisdom", "Seal of Fury" }) do
        t.eq(OC().Note(rows, name), "seal", name)
    end
    for _, name in ipairs({ "Blessing of Might", "Blessing of Wisdom", "Blessing of Kings", "Blessing of Salvation",
                            "Blessing of Light", "Blessing of Sanctuary" }) do
        t.eq(OC().Note(rows, name), "blessing", name)
    end
    for _, name in ipairs({ "Blessing of Protection", "Blessing of Freedom", "Blessing of Sacrifice",
                            "Righteous Fury", "Devotion Aura" }) do
        t.eq(OC().Note(rows, name), nil, name)
    end
end

-- N12 (lead section 228): the role a cast is kept under. No role chosen
-- (or anything else): dps, as the old add-on's usual role.
tests["own casts: the role a cast is kept under"] = function(t)
    t.eq(OC().Role("dps"), "dps")
    t.eq(OC().Role("heal"), "heal")
    t.eq(OC().Role("tank"), "tank")
    t.eq(OC().Role(nil), "dps", "none chosen")
    t.eq(OC().Role(""), "dps", "none chosen")
    t.eq(OC().Role("healer"), "dps", "not a role")
end

-- The seal and blessing words: a short name finds the full one.
tests["own casts: a short name finds the row's name; anything else nil"] = function(t)
    local seals = { "Seal of Righteousness", "Seal of the Crusader", "Seal of Command" }
    t.eq(OC().Find(seals, "Seal of ", "crusader"), "Seal of the Crusader", "without the")
    t.eq(OC().Find(seals, "Seal of ", "the crusader"), "Seal of the Crusader", "with the")
    t.eq(OC().Find(seals, "Seal of ", "seal of command"), "Seal of Command", "the full name")
    t.eq(OC().Find(seals, "Seal of ", "Righteous"), "Seal of Righteousness", "a start, any case")
    t.eq(OC().Find(seals, "Seal of ", "banana"), nil, "no such seal")
    t.eq(OC().Find(seals, "Seal of ", ""), nil, "nothing typed")
    t.eq(OC().Find(seals, "Seal of ", nil), nil)
    t.eq(OC().Short(seals, "Seal of "), "righteousness, crusader, command", "the short names, in order")
end

-- A blessing lands on you: your own buffs show it new, or renewed.
tests["own casts: a blessing landed on you only when your buffs show it new or renewed"] = function(t)
    t.eq(OC().Landed(nil, 300), true, "not up before, up now")
    t.eq(OC().Landed(nil, true), true, "not up before, up now (time not shown)")
    t.eq(OC().Landed(120, 300), true, "renewed")
    t.eq(OC().Landed(200, 199), false, "not renewed: cast on someone else")
    t.eq(OC().Landed(nil, nil), false, "not up now")
    t.eq(OC().Landed(true, true), false, "up before with no time: cannot tell")
    t.eq(OC().Landed(OC().UNREAD, 300), false, "your buffs not read before: cannot tell")
end

-- PC-1 (legacy keptFromCast): a cast of the one the rotation picks right
-- now, or of the spell it suggests, is not your choice.
tests["own casts: a cast of what was picked or suggested is not kept"] = function(t)
    local row = { key = "seal", pick = function(s) return s.want end }
    local view = { snapshot = { want = "Seal of Righteousness" }, suggestion = { spell = "Seal of Light" } }
    t.eq(OC().Fresh(row, view, "Seal of Righteousness"), true, "the one picked")
    t.eq(OC().Fresh(row, view, "Seal of Light"), true, "the one suggested")
    t.eq(OC().Fresh(row, view, "Seal of the Crusader"), false, "another one")
    t.eq(OC().Fresh(row, nil, "Seal of Righteousness"), false, "no view: cannot tell, kept")
    t.eq(OC().Fresh({ key = "seal", pick = function() error("made-up failure") end }, { snapshot = {} },
                    "Seal of Righteousness"), false, "a pick that raises: cannot tell")
    t.eq(OC().Fresh({ key = "seal" }, { snapshot = {} }, "Seal of Righteousness"), false, "no pick, nothing suggested")
end

-- PC-7: the line said when a cast becomes the kept one.
tests["own casts: the line names the spell, the role and the way back"] = function(t)
    local line = OC().Line({ word = "seal" }, "Seal of the Crusader", "damage", "/x")
    t.ok(line:find("Seal of the Crusader", 1, true) == 1, line)
    t.ok(line:find("damage", 1, true) ~= nil, line)
    t.ok(line:find("/x seal auto", 1, true) ~= nil, line)
end

return tests
