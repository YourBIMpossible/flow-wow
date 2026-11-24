-- The arrows' menu, "Buttons" and "Flow windows" (lead section 387 R3):
-- one level under Show, so the top level stays at Topics.MENU_MAX. Buttons
-- turns the add-on's own window buttons on or off (UI/WindowButtons.lua
-- rows); Flow windows opens or closes the add-on's own windows. Show and
-- advise only. Pure tables; not tested in game.
local _, ns = ...

local M = ns.ArrowMenu
local tests = {}

local BUTTONS = {
    { key = "worldMap", text = "Button on the world map", setting = "buttons.worldMap", on = true, there = true },
    { key = "merchant", text = "Button on the merchant window", setting = "buttons.merchant", on = false, there = true },
    { key = "gone", text = "Button on a window", setting = "buttons.gone", on = false, there = false },
}

local function child(items, key)
    for _, r in ipairs(items or {}) do
        if r.key == key then return r end
    end
    return nil
end

local function has(t)
    local ok = type(M.BUTTONS) == "string" and type(M.FLOW) == "string" and type(M.FLOW_WINDOWS) == "table"
    t.ok(ok, "ArrowMenu has the Buttons and Flow windows rows")
    return ok
end

tests["menu windows: Buttons and Flow windows sit under Show, not on the top level"] = function(t)
    if not has(t) then return end
    local items = M.Items({ buttons = BUTTONS, windows = { dungeonWindow = true } })
    t.eq(child(items, M.BUTTONS), nil, "no top-level Buttons row")
    t.eq(child(items, M.FLOW), nil, "no top-level Flow windows row")
    local show = child(items, "show")
    t.ok(child(show.children, M.BUTTONS) ~= nil, "Buttons under Show")
    t.ok(child(show.children, M.FLOW) ~= nil, "Flow windows under Show")
    t.eq(child(show.children, M.BUTTONS).text, "Buttons")
    t.eq(child(show.children, M.FLOW).text, "Flow windows")
    t.eq(M.PathTo(items, M.BUTTONS), { "show", M.BUTTONS })
    t.eq(M.Action(M.BUTTONS, {}), { open = M.BUTTONS })
    t.eq(M.Action(M.FLOW, {}), { open = M.FLOW })
end

tests["menu windows: one ticked row per button; a missing setting is greyed"] = function(t)
    if not has(t) then return end
    local row = child(child(M.Items({ buttons = BUTTONS }), "show").children, M.BUTTONS)
    t.eq(#row.children, 3)
    t.eq(row.children[1].key, "buttons.worldMap")
    t.eq(row.children[1].text, "Button on the world map")
    t.eq(row.children[1].checked, true)
    t.eq(row.children[2].checked, false)
    t.eq(row.children[3].disabled, true)
    local s = { buttons = BUTTONS }
    t.eq(M.Action("buttons.worldMap", s), { button = "buttons.worldMap", on = false })
    t.eq(M.Action("buttons.merchant", s), { button = "buttons.merchant", on = true })
    t.eq(M.Action("buttons.gone", s), nil, "greyed: nothing")
    t.eq(M.Action("buttons.nope", s), nil)
end

tests["menu windows: with no buttons the level says so"] = function(t)
    if not has(t) then return end
    local row = child(child(M.Items({}), "show").children, M.BUTTONS)
    t.eq(#row.children, 1)
    t.eq(row.children[1].disabled, true)
end

tests["menu windows: one row per Flow window; one not ready is greyed"] = function(t)
    if not has(t) then return end
    local s = { windows = { dungeonWindow = true } }
    local row = child(child(M.Items(s), "show").children, M.FLOW)
    t.eq(#row.children, #M.FLOW_WINDOWS)
    t.eq(row.children[1].key, "windows.dungeonWindow")
    t.ok(not row.children[1].disabled, "the dungeon window is ready")
    t.eq(row.children[2].disabled, true, "not ready: greyed")
    t.eq(M.Action("windows.dungeonWindow", s), { flowWindow = "dungeonWindow" })
    t.eq(M.Action("windows.settingsPanel", s), nil)
    t.eq(M.Action("windows.nope", { windows = { nope = true } }), nil, "only the list's windows")
end

-- Worst case: as ArrowMenuRouteTicks, plus four buttons and every window.
tests["menu windows: worst case, every level is short; the top level stays at 10"] = function(t)
    if not has(t) then return end
    local four = {}
    for i = 1, 4 do four[i] = { key = "b" .. i, text = "B" .. i, setting = "buttons.b" .. i, on = true, there = true } end
    local all = {}
    for _, w in ipairs(M.FLOW_WINDOWS) do all[w.name] = true end
    local items = M.Items({ styles = ns.Arrow.Styles("modern"), canShapes = true, feedback = true,
        party = { { unit = "party1", name = "A" }, { unit = "party2", name = "B" } },
        step = { name = "Wolves", open = true }, nearest = { vendor = true }, waypoint = true,
        route = { all = {}, on = {}, suggest = true }, buttons = four, windows = all })
    local MAX = ns.Settings.Topics.MENU_MAX
    local seen = {}
    for _, level in ipairs(M.Counts(items)) do
        seen[level.path] = level.rows
        t.ok(level.rows <= MAX, level.path .. ": " .. level.rows .. " rows, the most is " .. MAX)
    end
    t.eq(seen.top, 10, "the top level, unchanged")
    t.ok(seen[M.BUTTONS] ~= nil and seen[M.FLOW] ~= nil, "both levels counted")
end

return tests
