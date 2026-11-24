-- The arrows' menu, "Route" level (lead section 387 R3): what the route
-- includes, as tick rows counted from the route the arrow walks and the
-- trip list, and the "Suggest dungeons" switch. Show and advise only: the
-- count rows choose nothing. Pure tables; not tested in game.
local _, ns = ...

local M = ns.ArrowMenu
local tests = {}

local ALL = {
    { kind = "quest", label = "Wolves", place = { map = 1, x = 0.1, y = 0.1 } },
    { kind = "quest", label = "Boars", place = { map = 1, x = 0.2, y = 0.2 } },
    { kind = "dungeon", label = "Deadmines", place = { map = 2, x = 0.3, y = 0.3 } },
    { kind = "vendor", label = "Vendor", place = { map = 3, x = 0.4, y = 0.4 } },
}
local ON = {
    { label = "Wolves", place = { map = 1, x = 0.1, y = 0.1 } },
    { label = "Deadmines", place = { map = 2, x = 0.3, y = 0.3 } },
}

local function has(t)
    local ok = type(M.RouteCounts) == "function"
    t.ok(ok, "ArrowMenu.RouteCounts is there")
    return ok
end

local function child(items, key)
    for _, r in ipairs(items) do
        if r.key == key then return r end
    end
    return nil
end

tests["route ticks: counts N of M from the trip and the route walked"] = function(t)
    if not has(t) then return end
    local n = M.RouteCounts(ALL, ON)
    t.eq(n.steps, { 2, 4 })
    t.eq(n.zones, { 2, 3 })
    t.eq(n.dungeons, { 1, 1 })
    local none = M.RouteCounts(nil, nil)
    t.eq(none.steps, { 0, 0 })
    t.eq(none.zones, { 0, 0 })
    t.eq(none.dungeons, { 0, 0 })
end

tests["route ticks: the Route row and its level"] = function(t)
    if not has(t) then return end
    local items = M.Items({ route = { all = ALL, on = ON, suggest = false } })
    local route = child(items, M.ROUTE)
    t.ok(route ~= nil, "a Route row on the top level")
    if not route then return end
    t.eq(route.text, "Route includes 2 of 4")
    local keys, texts = {}, {}
    for i, r in ipairs(route.children) do keys[i], texts[i] = r.key, r.text end
    t.eq(keys, { "route.zones", "route.steps", "route.dungeons", "route.suggest" })
    t.eq(texts, { "Zones 2 of 3", "Steps 2 of 4", "Dungeons 1 of 1", "Suggest dungeons" })
    t.eq(route.children[1].checked, true)
    t.eq(route.children[1].disabled, true, "a count row is shown, not chosen")
    t.eq(route.children[4].checked, false)
    local level = M.Level(items, { M.ROUTE })
    t.ok(#level <= ns.Settings.Topics.MENU_MAX, "the level is short: " .. #level)
    t.eq(M.Action(M.ROUTE, {}), { open = M.ROUTE })
end

tests["route ticks: nothing on the route shows 0 of M, unticked"] = function(t)
    if not has(t) then return end
    local route = child(M.Items({ route = { all = ALL } }), M.ROUTE)
    t.eq(route and route.text, "Route includes 0 of 4")
    t.eq(route and route.children[2].checked, false)
    local empty = child(M.Items({}), M.ROUTE)
    t.eq(empty and empty.text, "Route includes 0 of 0")
end

tests["route ticks: count rows choose nothing; suggest flips the setting"] = function(t)
    if not has(t) then return end
    t.eq(M.Action("route.steps", {}), nil)
    t.eq(M.Action("route.zones", {}), nil)
    t.eq(M.Action("route.dungeons", {}), nil)
    t.eq(M.Action("route.suggest", { route = { suggest = false } }), { setting = M.SUGGEST_SETTING, on = true })
    t.eq(M.Action("route.suggest", { route = { suggest = true } }), { setting = M.SUGGEST_SETTING, on = false })
    t.eq(M.SUGGEST_SETTING, "nav.dungeonSuggest")
end

tests["route ticks: the suggest setting is a row, off at first"] = function(t)
    local row
    for _, r in ipairs(ns.Settings.Rows.ROWS) do
        if r.key == "nav.dungeonSuggest" then row = r end
    end
    t.ok(row ~= nil, "nav.dungeonSuggest is in Settings/Rows.lua")
    t.eq(row and row.type, "bool")
    t.eq(row and row.default, false)
end

return tests
