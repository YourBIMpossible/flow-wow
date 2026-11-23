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

return tests
