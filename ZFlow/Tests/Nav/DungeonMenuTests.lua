local _, ns = ...

-- Tests for ZFlow/Nav/DungeonMenu.lua (FLOW-PARITY B-53): the arrow menu's
-- "Dungeons" section and a run's own menu, as data. Pure. Made-up dungeons.

local tests = {}

local function DM() return ns.DungeonMenu end

local function pane(log, pickup, inside)
    local function rows(n)
        local out = {}
        for i = 1, n do out[i] = { name = "Q" .. i } end
        return out
    end
    return { groups = { { id = "log", rows = rows(log) }, { id = "pickup", rows = rows(pickup) },
                        { id = "inside", rows = rows(inside) }, { id = "later", rows = rows(4) } } }
end

tests["dungeon menu: a run's counts come from its pane; later quests are not counted"] = function(t)
    t.eq(DM().Counts(pane(2, 3, 1)), { on = 2, missing = 3, inside = 1, total = 6 })
    t.eq(DM().Counts(nil), { on = 0, missing = 0, inside = 0, total = 0 })
    t.eq(DM().CountText({ on = 2, total = 6 }), "2 of 6 in your log")
end

tests["dungeon menu: the section says when the list is still being read, or empty"] = function(t)
    local s = DM().Section({ reading = true })
    t.eq(s[1], { sep = true }); t.eq(s[2], { title = true, text = DM().TITLE })
    t.eq(s[3], { text = DM().READING, disabled = true })
    t.eq(DM().Section({ list = {} })[3], { text = DM().NONE, disabled = true })
end

tests["dungeon menu: one row per run, at most six, the prepared one ticked"] = function(t)
    local list = {}
    for i = 1, 8 do
        list[i] = { key = i, name = "D" .. i, counts = { on = 1, missing = 0, inside = 0, total = 2 },
                    rate = i == 2 and "About 1.5 times your questing XP per hour." or nil }
    end
    local s = DM().Section({ list = list, prepared = 2 })
    local rows = {}
    for _, it in ipairs(s) do if it.action == "open" then rows[#rows + 1] = it end end
    t.eq(#rows, 6)
    t.eq(rows[1].text, "D1: 1 of 2 in your log")
    t.eq(rows[2].checked, true); t.eq(rows[1].checked, false)
    t.eq(rows[2].key, 2)
    t.eq(rows[2].tipLines[#rows[2].tipLines], "About 1.5 times your questing XP per hour.")
end

local function actions(items)
    local out = {}
    for _, it in ipairs(items) do if it.action then out[#out + 1] = it.action end end
    return table.concat(out, ",")
end

tests["dungeon menu: a run's menu: only this run, prepare or cancel, straight to the entrance"] = function(t)
    local run = { key = 3, name = "Test Mines", counts = { on = 1, missing = 2, inside = 0, total = 3 } }
    local items = DM().RunItems(run, { entrance = true })
    t.eq(items[1], { title = true, text = "Test Mines" })
    t.eq(actions(items), "only,prepare,entrance")
    local prepared = DM().RunItems(run, { prepared = true, only = true })
    t.eq(actions(prepared), "only,cancel,entrance")
    for _, it in ipairs(prepared) do
        if it.action == "only" then t.eq(it.checked, true) end
        if it.action == "entrance" then t.eq(it.disabled, true, "no entrance known") end
    end
end

return tests
