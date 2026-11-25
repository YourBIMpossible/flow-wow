local _, ns = ...

-- Tests for ZFlow/Nav/DungeonMode.lua (FLOW-PARITY B-50): the dungeon
-- route's line under the arrow and its few choices, as data. Pure.
-- Made-up dungeon.

local tests = {}

local function M() return ns.DungeonMode end

tests["dungeon mode: no line without a prepared run"] = function(t)
    t.eq(M().Line(nil, true, 0, 0), nil)
end

tests["dungeon mode: the line says the run, and whether you are on its route"] = function(t)
    t.eq(M().Line("Test Mines", false, 1, 5), "Test Mines prepared (your usual route)")
    t.eq(M().Line("Test Mines", true, 2, 5), "Dungeon route: Test Mines, 2 of 5")
end

tests["dungeon mode: the counts in full, one short line each"] = function(t)
    local lines = M().CountLines("Test Mines", { done = 1, on = 1, missing = 2, inside = 1 })
    t.eq(lines, { "Test Mines", "- 1 quest completed", "- You're on 1 quest",
        "- You're missing 2 quests (to pick up outside)", "- 1 starts inside the dungeon", "- 5 quests in all" })
    local none = M().CountLines(nil, { done = 0, on = 0, missing = 0, inside = 0 })
    t.eq(none[1], "Dungeon run")
    t.eq(none[4], "- You're missing 0 quests")
    t.eq(#none, 5, "no inside line when none start inside")
end

local function actions(items)
    local out = {}
    for _, it in ipairs(items) do
        if it.action then out[#out + 1] = it.action end
    end
    return table.concat(out, ",")
end

tests["dungeon mode: on the route the choices are leave, prepare and cancel"] = function(t)
    local items = M().Items({ name = "Test Mines", on = true, prep = true,
        counts = { done = 0, on = 1, missing = 1, inside = 0 } })
    t.eq(items[1], { title = true, text = "Test Mines" })
    t.eq(actions(items), "leave,prep,cancel")
    for _, it in ipairs(items) do
        if it.action == "prep" then t.eq(it.checked, true) end
    end
end

tests["dungeon mode: off the route the first choice is back on it; asking the group only when allowed"] = function(t)
    t.eq(actions(M().Items({ name = "Test Mines", on = false, prep = false })), "back,prep,cancel")
    t.eq(actions(M().Items({ name = "Test Mines", on = false, canAsk = true,
        counts = { done = 0, on = 0, missing = 0, inside = 0 } })), "back,ask,prep,cancel")
end

tests["dungeon mode: no choices without a prepared run"] = function(t)
    t.eq(M().Items(nil), {})
    t.eq(M().Items({}), {})
end

return tests
local _, ns = ...

-- Tests for ZFlow/Nav/DungeonMode.lua (FLOW-PARITY B-50): the dungeon
-- route's line under the arrow and its few choices, as data. Pure.
-- Made-up dungeon.

local tests = {}

local function M() return ns.DungeonMode end

tests["dungeon mode: no line without a prepared run"] = function(t)
    t.eq(M().Line(nil, true, 0, 0), nil)
end

tests["dungeon mode: the line says the run, and whether you are on its route"] = function(t)
    t.eq(M().Line("Test Mines", false, 1, 5), "Test Mines prepared (your usual route)")
    t.eq(M().Line("Test Mines", true, 2, 5), "Dungeon route: Test Mines, 2 of 5")
end

tests["dungeon mode: the counts in full, one short line each"] = function(t)
    local lines = M().CountLines("Test Mines", { done = 1, on = 1, missing = 2, inside = 1 })
    t.eq(lines, { "Test Mines", "- 1 quest completed", "- You're on 1 quest",
        "- You're missing 2 quests (to pick up outside)", "- 1 starts inside the dungeon", "- 5 quests in all" })
    local none = M().CountLines(nil, { done = 0, on = 0, missing = 0, inside = 0 })
    t.eq(none[1], "Dungeon run")
    t.eq(none[4], "- You're missing 0 quests")
    t.eq(#none, 5, "no inside line when none start inside")
end

local function actions(items)
    local out = {}
    for _, it in ipairs(items) do
        if it.action then out[#out + 1] = it.action end
    end
    return table.concat(out, ",")
end

tests["dungeon mode: on the route the choices are leave, prepare and cancel"] = function(t)
    local items = M().Items({ name = "Test Mines", on = true, prep = true,
        counts = { done = 0, on = 1, missing = 1, inside = 0 } })
    t.eq(items[1], { title = true, text = "Test Mines" })
    t.eq(actions(items), "leave,prep,cancel")
    for _, it in ipairs(items) do
        if it.action == "prep" then t.eq(it.checked, true) end
    end
end

tests["dungeon mode: off the route the first choice is back on it; asking the group only when allowed"] = function(t)
    t.eq(actions(M().Items({ name = "Test Mines", on = false, prep = false })), "back,prep,cancel")
    t.eq(actions(M().Items({ name = "Test Mines", on = false, canAsk = true,
        counts = { done = 0, on = 0, missing = 0, inside = 0 } })), "back,ask,prep,cancel")
end

-- Lazy's note 2 (§611): per-quest rows only as handed in, from the
-- player's log or Questie (the dungeon pane's rows); none are made up here.
tests["dungeon mode: per-quest rows are listed grey after the counts, at most twelve"] = function(t)
    local extra = {}
    for i = 1, 14 do extra[i] = "Pick up: Q" .. i end
    local items = M().Items({ name = "Test Mines", on = true, counts = { done = 0, on = 0, missing = 0, inside = 0 },
        extra = extra })
    local grey = {}
    for _, it in ipairs(items) do
        if it.disabled and it.text:find("^Pick up") then grey[#grey + 1] = it.text end
    end
    t.eq(#grey, 12)
    t.eq(grey[12], "Pick up: Q12")
    local more
    for _, it in ipairs(items) do
        if it.disabled and it.text == "... and 2 more." then more = true end
    end
    t.ok(more, "how many more")
    t.eq(actions(M().Items({ name = "Test Mines", on = true, extra = { "Pick up: Q1" } })), "leave,prep,cancel")
end

tests["dungeon mode: no choices without a prepared run"] = function(t)
    t.eq(M().Items(nil), {})
    t.eq(M().Items({}), {})
end

return tests
