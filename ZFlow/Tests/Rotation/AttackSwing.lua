local _, ns = ...

-- Lead section 358: the Rogue and Warrior Attack rows go by the swing check,
-- the same as Druid, Paladin and Shaman (section 340). The driver's swing
-- read (s.attacking, over Auto Attack and Attack) decides where it was made;
-- where it was not, either name read as off. Nothing read is never "off".

local function rows(pack)
    local out = {}
    for _, rule in ipairs(pack.lists.default) do
        if rule.spell == "Attack" then out[#out + 1] = rule end
    end
    return out
end

-- An enemy targeted in a fight, not stealthed; the swing fields are the case's.
local function snap(attacking, current)
    return { role = "dps", hostile = true, inCombat = true, dead = false, stealthed = false,
             form = "Battle Stance", formKnown = true, buffs = {}, targetDebuffs = {},
             attacking = attacking, current = current, spells = {} }
end

local function asked(pack, s)
    for _, rule in ipairs(rows(pack)) do
        if rule.when(s) then return true end
    end
    return false
end

local CASES = {
    { "swing read as off, names not read", false, nil, true },
    { "swing read as off, Attack left out", false, {}, true },
    { "swing read as on, Attack read as off", true, { Attack = false }, false },
    { "swing read as on, names not read", true, nil, false },
    { "swing not read, Attack off", nil, { Attack = false }, true },
    { "swing not read, Auto Attack off", nil, { ["Auto Attack"] = false }, true },
    { "swing not read, both on", nil, { Attack = true, ["Auto Attack"] = true }, false },
    { "swing not read, names left out", nil, {}, false },
    { "nothing read", nil, nil, false },
}

local function check(t, pack)
    t.eq(#rows(pack), 1, "one Attack row")
    for _, case in ipairs(CASES) do
        t.eq(asked(pack, snap(case[2], case[3])), case[4], case[1])
    end
end

return {
    ["358 rogue: the Attack row goes by the swing check"] = function(t)
        check(t, ns.Packs.ROGUE)
    end,

    ["358 warrior: the Attack row goes by the swing check"] = function(t)
        check(t, ns.Packs.WARRIOR)
    end,

    ["358 rogue: stealthed or stealth not read, never the swing"] = function(t)
        for _, stealthed in ipairs({ true, "not read" }) do
            local s = snap(false, { Attack = false, ["Auto Attack"] = false })
            if stealthed == true then s.stealthed = true else s.stealthed = nil end
            t.eq(asked(ns.Packs.ROGUE, s), false, tostring(stealthed))
        end
    end,

    ["358 no enemy: no swing asked for"] = function(t)
        for _, class in ipairs({ "ROGUE", "WARRIOR" }) do
            local s = snap(false, { Attack = false })
            s.hostile = false
            t.eq(asked(ns.Packs[class], s), false, class .. ": not hostile")
            s.hostile = nil
            t.eq(asked(ns.Packs[class], s), false, class .. ": target not read")
        end
    end,
}
