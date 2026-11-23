local _, ns = ...

-- Tests for ZFlow/Gear/CanUse.lua. Pure: the item, the class's table and the
-- level are made here.

local U = ns.GearCanUse
local tests = {}

-- Armor is item class 4, weapons 2. This class wears cloth (1) and leather
-- (2), and uses staves (10) and daggers (15).
local PROF = { evidence = "first guess", [4] = { [1] = true, [2] = true }, [2] = { [10] = true, [15] = true } }

local function item(classID, subclassID, minLevel)
    return { classID = classID, subclassID = subclassID, minLevel = minLevel }
end

tests["can use: a kind the class wears, at a level you have reached"] = function(t)
    local r = U.Check(item(4, 2, 10), { proficiency = PROF, level = 10 })
    t.eq(r.can, true)
    t.eq(r.why, "ok")
    t.eq(r.reason, U.REASON.ok)
    r = U.Check(item(2, 15, 0), { proficiency = PROF, level = 1 })
    t.eq(r.can, true, "a weapon, no level needed")
end

tests["can use: a kind the class does not wear is a plain no, whatever the level"] = function(t)
    local r = U.Check(item(4, 4, 1), { proficiency = PROF, level = 60 })
    t.eq(r.can, false)
    t.eq(r.why, "class")
    t.eq(r.reason, U.REASON.class)
    r = U.Check(item(2, 7, nil), { proficiency = PROF })
    t.eq(r.can, false, "decided before any level is looked at")
    t.eq(r.why, "class")
end

tests["can use: below the level it needs is a no that names the level"] = function(t)
    local r = U.Check(item(4, 1, 20), { proficiency = PROF, level = 19 })
    t.eq(r.can, false)
    t.eq(r.why, "level")
    t.eq(r.reason, U.REASON.level .. " 20")
    r = U.Check(item(4, 1, 20), { proficiency = PROF, level = 20 })
    t.eq(r.can, true)
end

tests["can use: the class's table not known is not known, never a yes"] = function(t)
    for _, who in ipairs({ false, {}, { proficiency = "all", level = 60 } }) do
        local r = U.Check(item(4, 1, 1), who or nil)
        t.eq(r.can, nil)
        t.eq(r.why, "unknown")
        t.eq(r.reason, U.REASON.proficiency)
    end
end

tests["can use: an item class the table says nothing about is not known, not a no"] = function(t)
    local r = U.Check(item(4, 1, 1), { proficiency = { [2] = { [10] = true } }, level = 60 })
    t.eq(r.can, nil)
    t.eq(r.reason, U.REASON.proficiency)
    r = U.Check(item(4, 1, 1), { proficiency = { [4] = "cloth" }, level = 60 })
    t.eq(r.can, nil)
end

tests["can use: an item whose type was not read is not known"] = function(t)
    for _, it in ipairs({ item(nil, 1, 1), item(4, nil, 1), item("4", 1, 1), item(4, false, 1) }) do
        local r = U.Check(it, { proficiency = PROF, level = 60 })
        t.eq(r.can, nil)
        t.eq(r.why, "unknown")
        t.eq(r.reason, U.REASON.type)
    end
    t.eq(U.Check(nil, { proficiency = PROF, level = 60 }).reason, U.REASON.type)
    t.eq(U.Check("a helm", { proficiency = PROF, level = 60 }).can, nil)
end

tests["can use: the level it needs, or your level, not read is not known"] = function(t)
    local nan = 0 / 0
    for _, min in ipairs({ false, "20", nan, math.huge }) do
        local r = U.Check(item(4, 1, min or nil), { proficiency = PROF, level = 60 })
        t.eq(r.can, nil, tostring(min))
        t.eq(r.reason, U.REASON.minLevel)
    end
    for _, level in ipairs({ false, "60", nan }) do
        local r = U.Check(item(4, 1, 20), { proficiency = PROF, level = level or nil })
        t.eq(r.can, nil, tostring(level))
        t.eq(r.reason, U.REASON.yourLevel)
    end
end

tests["can use: only a plain true in the table is a yes"] = function(t)
    -- A whole number from 1 up is "from level n" (D3); 0 is a malformed
    -- number, which is not known. Neither that nor a string or false is a yes.
    local prof = { [4] = { [1] = 0, [2] = "yes", [3] = false } }
    local want = { [1] = nil, [2] = false, [3] = false }
    for sub = 1, 3 do
        t.eq(U.Check(item(4, sub, 1), { proficiency = prof, level = 60 }).can, want[sub], tostring(sub))
    end
end

tests["can use: the answer says how good the class's table is"] = function(t)
    t.eq(U.Check(item(4, 4, 1), { proficiency = PROF, level = 60 }).evidence, "first guess")
    t.eq(U.Check(item(4, 1, 1), { proficiency = PROF, level = 60 }).evidence, "first guess")
    t.eq(U.Check(item(4, 1, 1), { proficiency = { [4] = { [1] = true } }, level = 60 }).evidence, nil)
end

tests["can use: nothing handed in is changed, and no reason names the product"] = function(t)
    local it, who = item(4, 1, 5), { proficiency = { [4] = { [1] = true } }, level = 9 }
    U.Check(it, who)
    t.eq(it, { classID = 4, subclassID = 1, minLevel = 5 })
    t.eq(who, { proficiency = { [4] = { [1] = true } }, level = 9 })
    for _, text in pairs(U.REASON) do
        t.ok(type(text) == "string" and text ~= "")
        t.ok(not text:lower():find("flow", 1, true))
    end
end

return tests
