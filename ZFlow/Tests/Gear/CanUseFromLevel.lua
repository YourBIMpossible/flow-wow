local _, ns = ...

-- Lead section 197, D3: in a class's proficiency table a kind may be given
-- a level number in place of true, meaning "from level n" (mail from 40 for
-- the Hunter and the Shaman). Gear/CanUse.lua reads it; true is unchanged.
-- Pure: the item, the table and the level are made here. Offline only.

local U = ns.GearCanUse
local tests = {}

-- Leather (2) always, mail (3) from level 40; bows (2) always.
local PROF = { evidence = "first guess", [4] = { [2] = true, [3] = 40 }, [2] = { [2] = true } }

local function item(classID, subclassID, minLevel)
    return { classID = classID, subclassID = subclassID, minLevel = minLevel }
end

tests["can use from level: below the level the class learns it is a class no naming the level"] = function(t)
    local r = U.Check(item(4, 3, 30), { proficiency = PROF, level = 39 })
    t.eq(r.can, false)
    t.eq(r.why, "class", "it is about the class, so the table's label is shown")
    t.eq(r.reason, U.REASON.classFrom .. " 40")
    t.eq(r.evidence, "first guess")
end

tests["can use from level: at and above that level it is a yes, and the item's own level still counts"] = function(t)
    t.eq(U.Check(item(4, 3, 30), { proficiency = PROF, level = 40 }).can, true, "at 40")
    t.eq(U.Check(item(4, 3, 40), { proficiency = PROF, level = 55 }).can, true, "above")
    local r = U.Check(item(4, 3, 45), { proficiency = PROF, level = 41 })
    t.eq(r.can, false)
    t.eq(r.why, "level")
    t.eq(r.reason, U.REASON.level .. " 45")
end

tests["can use from level: your level not known is not known, never a yes or a no"] = function(t)
    local r = U.Check(item(4, 3, 30), { proficiency = PROF })
    t.eq(r.can, nil)
    t.eq(r.why, "unknown")
    t.eq(r.reason, U.REASON.yourLevel)
end

tests["can use from level: true is unchanged; a kind not in the table is still a no"] = function(t)
    t.eq(U.Check(item(4, 2, 1), { proficiency = PROF, level = 1 }).can, true, "leather at 1")
    t.eq(U.Check(item(2, 2, 1), { proficiency = PROF, level = 1 }).can, true, "a bow at 1")
    local r = U.Check(item(4, 4, 1), { proficiency = PROF, level = 60 })
    t.eq({ r.can, r.why, r.reason }, { false, "class", U.REASON.class }, "plate")
end

tests["can use from level: a value that is no whole level from 1 up is not known"] = function(t)
    for _, odd in ipairs({ 0, -5, 40.5, 0 / 0, math.huge }) do
        local prof = { evidence = "first guess", [4] = { [3] = odd } }
        local r = U.Check(item(4, 3, 1), { proficiency = prof, level = 60 })
        t.eq(r.can, nil, tostring(odd))
        t.eq(r.reason, U.REASON.proficiency, tostring(odd))
    end
    local word = { evidence = "first guess", [4] = { [3] = "40" } }
    t.eq(U.Check(item(4, 3, 1), { proficiency = word, level = 60 }).why, "class", "a word is not a level: no")
end

tests["can use from level: the tooltip line says the level and the label"] = function(t)
    local use = U.Check(item(4, 3, 30), { proficiency = PROF, level = 30 })
    local lines = ns.GearTooltip.Lines({ verdict = "upgrade", delta = 3 }, use)
    t.eq(lines, { { text = "Can't use: your class can use this kind from level 40 (first guess)", tone = "bad" } })
end

return tests
