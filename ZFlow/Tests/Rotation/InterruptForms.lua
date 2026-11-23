local _, ns = ...

-- Lead section 197: an interrupt row may name the forms (stances) it can be
-- used in. Outside them, or with the form not read, it is passed by; a row
-- with no forms is used in any form, as before.

local function pack(rows)
    return { lists = { default = {} }, heals = { self = {} }, interrupts = rows }
end

local function snap(over)
    local s = { dead = false, inCombat = true, hostile = true, targetCasting = "Fireball", targetNear = true,
                spells = { Pummel = { known = true, onCooldown = false, inRange = true },
                           ["Shield Bash"] = { known = true, onCooldown = false, inRange = true } } }
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end

local ROWS = {
    { spell = "Pummel", forms = { ["Berserker Stance"] = true }, evidence = "first guess" },
    { spell = "Shield Bash", forms = { ["Battle Stance"] = true, ["Defensive Stance"] = true }, evidence = "first guess" },
}

local function pick(over, rows)
    local s = ns.Choose(snap(over), pack(rows or ROWS))
    return s and s.spell or nil
end

return {
    ["interrupt forms: the row for the stance you are in"] = function(t)
        t.eq(pick({ form = "Berserker Stance", formKnown = true }), "Pummel")
        t.eq(pick({ form = "Defensive Stance", formKnown = true }), "Shield Bash")
    end,

    ["interrupt forms: no row for the stance, nothing"] = function(t)
        t.eq(pick({ form = nil, formKnown = true }), nil, "no stance")
        t.eq(pick({ form = "Battle Stance", formKnown = true },
            { ROWS[1] }), nil, "only Pummel, in Battle Stance")
    end,

    ["interrupt forms: the form not read, a row with forms is passed by"] = function(t)
        t.eq(pick({ form = "Berserker Stance", formKnown = false }), nil, "not read")
        t.eq(pick({}), nil, "never read")
    end,

    ["interrupt forms: a row with no forms is used in any form"] = function(t)
        t.eq(pick({ form = nil, formKnown = false }, { { spell = "Pummel", evidence = "first guess" } }), "Pummel")
    end,
}
