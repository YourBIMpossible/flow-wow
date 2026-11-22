local _, ns = ...

-- Can you use this piece of gear (G12). Pure: the item, what the class can
-- wear and your level come in as data; nothing here reads the game.
--
--   answer = GearCanUse.Check(item, who)
--
--   item  { classId, subclassId, minLevel }: the item's class and subclass
--         numbers as the client gives them (armor is class 4, weapons class
--         2) and the level it needs (0 for none). Each as read; a field that
--         is not a plain number was not read.
--   who   { proficiency, level }: the class pack's own table of what the
--         class can equip ({ [item class] = { [subclass] = true } }, with an
--         `evidence` label beside them; see ZFlow/Classes) and your level.
--         No table is made or filled in here.
--   answer { can, why, reason, evidence }
--     can     true, false, or nil when it is not known. Not known is never
--             a yes: the caller shows no upgrade for it.
--     why     "ok", "class" (the class cannot use this kind), "level" (you
--             are below the level it needs), or "unknown"
--     reason  always given, from GearCanUse.REASON; "needs level" is
--             followed by the level
--     evidence   the proficiency table's own label ("first guess"), so a
--             "your class cannot" can be shown for what it rests on
--
-- The class comes first: a kind the class cannot use is a no whatever the
-- level. A weapon skill that could be trained is not looked at here: the
-- table says what the class can equip, and that is all this answers.

local U = {}
ns.GearCanUse = U

U.REASON = {
    ok = "you can use it",
    class = "your class cannot use this kind of item",
    level = "needs level",
    type = "the item's type is not known",
    proficiency = "what your class can use is not known",
    minLevel = "the level it needs is not known",
    yourLevel = "your level is not known",
}
local R = U.REASON

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function U.Check(item, who)
    local proficiency = type(who) == "table" and who.proficiency or nil
    local evidence = nil
    if type(proficiency) == "table" and type(proficiency.evidence) == "string" then
        evidence = proficiency.evidence
    end
    local function answer(can, why, reason)
        return { can = can, why = why, reason = reason, evidence = evidence }
    end

    if type(item) ~= "table" or not finite(item.classId) or not finite(item.subclassId) then
        return answer(nil, "unknown", R.type)
    end
    local kinds = type(proficiency) == "table" and proficiency[item.classId] or nil
    if type(kinds) ~= "table" then return answer(nil, "unknown", R.proficiency) end
    if kinds[item.subclassId] ~= true then return answer(false, "class", R.class) end

    if not finite(item.minLevel) then return answer(nil, "unknown", R.minLevel) end
    if not finite(who.level) then return answer(nil, "unknown", R.yourLevel) end
    if who.level < item.minLevel then
        return answer(false, "level", R.level .. " " .. tostring(item.minLevel))
    end
    return answer(true, "ok", R.ok)
end
