-- The profession picker's pure part (G17): P.Advice(known, class, level)
-- gives one prompt or nil, from the player's own state only.
local _, ns = ...

local function advice(known, class, level)
    local P = ns.ProfPick
    if type(P) ~= "table" or type(P.Advice) ~= "function" then return "no ProfPick.Advice" end
    return P.Advice(known, class, level)
end

local function textOf(a) return type(a) == "table" and a.text or a end

return {
    ["profession picker: nothing read gives no advice"] = function(t)
        t.eq(advice(nil, "MAGE", 10), nil)
    end,

    ["profession picker: level not known or below 3 gives no advice"] = function(t)
        t.eq(advice({}, "MAGE", nil), nil)
        t.eq(advice({}, "MAGE", 2), nil)
    end,

    ["profession picker: two primaries give no advice; secondary and weapon lines do not count"] = function(t)
        t.eq(advice({ Mining = true, Skinning = true }, "WARRIOR", 20), nil)
        t.eq(textOf(advice({ Cooking = true, Fishing = true, ["First Aid"] = true, Swords = true }, "WARRIOR", 20)),
            "Two profession slots are free. You wear mail or plate: Mining gives the ore and Blacksmithing "
            .. "makes your armour and weapons from it.")
    end,

    ["profession picker: a class by its armour"] = function(t)
        t.eq(textOf(advice({}, "ROGUE", 5)),
            "Two profession slots are free. You wear leather: Skinning gives the leather from what you kill "
            .. "and Leatherworking makes your armour from it.")
        t.eq(textOf(advice({}, "PRIEST", 5)),
            "Two profession slots are free. You wear cloth: Tailoring makes bags and cloth gear from the cloth "
            .. "you loot, and Enchanting turns the gear you do not need into enchants.")
    end,

    ["profession picker: class not known, two gathering professions"] = function(t)
        t.eq(textOf(advice({}, nil, 5)),
            "Two profession slots are free. Herbalism and Skinning gather while you level and sell for gold.")
    end,

    ["profession picker: one gathering profession names its craft"] = function(t)
        t.eq(textOf(advice({ Mining = true }, "MAGE", 5)),
            "One profession slot is free. Blacksmithing goes with your Mining: it makes armour and weapons from the ore.")
        t.eq(textOf(advice({ Skinning = true }, "MAGE", 5)),
            "One profession slot is free. Leatherworking goes with your Skinning: it makes armour from the leather.")
    end,

    ["profession picker: one craft names the gathering that feeds it"] = function(t)
        t.eq(textOf(advice({ Alchemy = true }, "MAGE", 5)),
            "One profession slot is free. Herbalism goes with your Alchemy: it gathers the herbs it needs.")
        t.eq(textOf(advice({ Tailoring = true }, "MAGE", 5)),
            "One profession slot is free. Enchanting goes with your Tailoring: it turns the gear you make "
            .. "or find into enchants.")
    end,

    ["profession picker: the prompt id and priority"] = function(t)
        local a = advice({}, "MAGE", 5)
        t.eq(type(a) == "table" and a.id, "aps.profPick")
        t.eq(type(a) == "table" and a.priority, 1)
    end,
}
