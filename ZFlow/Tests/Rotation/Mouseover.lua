local _, ns = ...
-- N63 (lead sections 245, 246): the mouseover plan and its attributes.
-- The class tables are the add-on's own (ns.Packs); which spells are known
-- is made up here. Not tested in game.
local tests = {}

local M = ns.Mouseover

local function knows(set)
    return function(name) return set[name] end
end

tests["mouseover: the heal, then the cures from the shared dispel table"] = function(t)
    local plan = M.Plan(ns.Packs.PRIEST, knows({
        ["Flash Heal"] = true, ["Lesser Heal"] = true,
        ["Dispel Magic"] = true, ["Abolish Disease"] = true, ["Cure Disease"] = true,
    }))
    t.eq(plan.key, "Flash Heal", "the first known heal")
    t.eq(plan.shift, "Dispel Magic")
    t.eq(plan.ctrl, "Abolish Disease")
    t.eq(plan.alt, nil, "Cure Disease cures nothing Abolish Disease does not")
end

tests["mouseover: a spell not known or not read is left out"] = function(t)
    local plan = M.Plan(ns.Packs.PRIEST, knows({
        ["Flash Heal"] = false, ["Lesser Heal"] = true,
        ["Dispel Magic"] = nil, ["Abolish Disease"] = false, ["Cure Disease"] = true,
    }))
    t.eq(plan.key, "Lesser Heal")
    t.eq(plan.shift, "Cure Disease", "the one cure known")
    t.eq(plan.ctrl, nil)
    plan = M.Plan(ns.Packs.PRIEST, function() error("read failed") end)
    t.eq(next(plan), nil, "a read that fails: nothing")
end

tests["mouseover: paladin, Cleanse covers Purify"] = function(t)
    local plan = M.Plan(ns.Packs.PALADIN, knows({ ["Holy Light"] = true, ["Cleanse"] = true, ["Purify"] = true }))
    t.eq(plan.key, "Holy Light")
    t.eq(plan.shift, "Cleanse"); t.eq(plan.ctrl, nil)
    plan = M.Plan(ns.Packs.PALADIN, knows({ ["Purify"] = true }))
    t.eq(plan.key, nil, "no heal known"); t.eq(plan.shift, "Purify")
end

tests["mouseover: no heal and no cure, or no class table"] = function(t)
    t.eq(next(M.Plan(ns.Packs.WARRIOR, knows({}))), nil, "a warrior: an empty plan")
    t.eq(M.Plan(nil, knows({})), nil, "no class table: nil")
    t.eq(M.Plan(ns.Packs.PRIEST, nil), nil)
end

tests["mouseover: the rows are spell type on the unit under the mouse, never a macro"] = function(t)
    local rows = M.Rows({ key = "Flash Heal", shift = "Dispel Magic" })
    local by = {}
    for _, row in ipairs(rows) do
        by[row.attr] = row.value
        t.ok(row.value ~= "macro", "no macro type: " .. row.attr)
        t.ok(not tostring(row.attr):find("macro", 1, true), "no macro attribute: " .. row.attr)
    end
    t.eq(#rows, 12, "the plain part and three modifiers, three attributes each")
    t.eq(by.type, "spell"); t.eq(by.spell, "Flash Heal"); t.eq(by.unit, "mouseover")
    t.eq(by["*type-shift"], "spell"); t.eq(by["*spell-shift"], "Dispel Magic"); t.eq(by["*unit-shift"], "mouseover")
    t.eq(by["*type-ctrl"], nil, "nothing on Ctrl: cleared")
    t.eq(by["*unit-alt"], nil)
end

tests["mouseover: known is read from the client, nil when not read"] = function(t)
    local c = ns.make.fakeClient()
    c.setSpellId("Flash Heal", 2061)
    c.setSpell(2061, { known = true })
    local known = M.Known(c)
    t.eq(known("Flash Heal"), true)
    t.eq(known("Heal"), nil, "no spell id: not read")
    c.spell = function() error("read failed") end
    t.eq(known("Flash Heal"), nil, "a failed read: not read")
    t.eq(M.Known(nil)("Flash Heal"), nil)
end

return tests
