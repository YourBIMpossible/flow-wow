local _, ns = ...

-- Tests for ZFlow/Nav/TrackerMenu.lua (FLOW-PARITY A2-19, the logic half):
-- what a click on a tracker row does, and its right-click entries, as data.
-- Pure. Made-up quests.

local tests = {}

local function TM() return ns.Nav.TrackerMenu end

local QUEST = { label = "Boars", quest = 401, objective = 1, place = { map = 1, x = 0.5, y = 0.5 } }
local TOWN = { label = "Bags full: sell", kind = "sell", place = { map = 1, x = 0.4, y = 0.5 } }

local function keys(items)
    local out = {}
    for _, it in ipairs(items) do
        if it.key then out[#out + 1] = it.key end
    end
    return table.concat(out, ",")
end

local function entry(items, key)
    for _, it in ipairs(items) do
        if it.key == key then return it end
    end
    return nil
end

tests["tracker menu: a left click on a quest row opens that quest in the log"] = function(t)
    t.eq(TM().Click(QUEST), { action = "openQuest", quest = 401 })
end

tests["tracker menu: a held row says why; a row with no quest does nothing"] = function(t)
    t.eq(TM().Click({ label = "X", quest = 9, held = "not ready" }), { action = "blocked", why = "not ready" })
    t.eq(TM().Click(TOWN), { action = "none" })
    t.eq(TM().Click(nil), { action = "none" })
end

tests["tracker menu: the right-click entries, in order, with what each needs"] = function(t)
    local items = TM().Items(QUEST, { canHide = true, canNext = true, sort = "distance" })
    t.eq(items[1], { title = true, words = "Boars" })
    t.eq(keys(items), "open,point,next,hide,sort:distance,sort:xp")
    t.eq(entry(items, "open").action, "openQuest")
    t.eq(entry(items, "open").enabled, true)
    t.eq(entry(items, "sort:distance").checked, true)
    t.eq(entry(items, "sort:xp").checked, false)
end

tests["tracker menu: an entry the row or the route cannot do is there, not enabled"] = function(t)
    local items = TM().Items(TOWN, {})
    t.eq(entry(items, "open").enabled, false, "no quest to open")
    t.eq(entry(items, "point").enabled, true, "it has a place")
    t.eq(entry(items, "next").enabled, false, "the route cannot put a stop next yet")
    t.eq(entry(items, "hide").enabled, false, "the route cannot hide a stop yet")
    local held = TM().Items({ label = "X", quest = 9, held = "not ready", place = QUEST.place }, { canNext = true })
    t.eq(entry(held, "next").enabled, false, "a held stop is not put next")
    t.eq(TM().Items(nil, {}), {})
end
return tests
