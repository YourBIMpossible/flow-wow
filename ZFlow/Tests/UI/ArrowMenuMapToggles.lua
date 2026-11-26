local _, ns = ...
-- B-13, B-14: the world map switches (Nav/MapToggles.lua) in the arrow
-- menu, under Show in a "World map" level of their own so every level
-- stays within Topics.MENU_MAX. Plain tables only (UI/ArrowMenu.lua); the
-- click reaches MapToggles' Toggle through UI/Arrow.lua. Not tested in game.
local tests = {}
local M = ns.ArrowMenu
local T = ns.Settings.Topics

local function find(rows, key)
    for _, r in ipairs(rows) do if r.key == key then return r end end
    return nil
end

local TOGGLES = {
    { key = "map.flights", text = "Flight masters on the map", checked = true },
    { key = "map.route", text = "Your route on the map", checked = false },
}

local function state()
    return { step = { name = "Rats" }, mapToggles = TOGGLES,
        buttons = { { key = "a", text = "A" } }, windows = {} }
end

tests["arrow menu map: Show has a World map level with both switches"] = function(t)
    local show = find(M.Items(state()), "show")
    local map = find(show.children, M.MAP)
    t.ok(map ~= nil, "a World map row under Show")
    t.eq(map.text, "World map")
    t.eq(map.children, {
        { key = "map.flights", text = "Flight masters on the map", checked = true },
        { key = "map.route", text = "Your route on the map", checked = false },
    })
end

tests["arrow menu map: the rows ask MapToggles to switch, the level opens"] = function(t)
    t.eq(M.Action(M.MAP, state()), { open = M.MAP })
    t.eq(M.Action("map.flights", state()), { mapToggle = "map.flights" })
    t.eq(M.Action("map.route", state()), { mapToggle = "map.route" })
    t.eq(M.Action("map.other", state()), nil, "a switch not offered asks for nothing")
end

tests["arrow menu map: with no switches the level says so"] = function(t)
    local map = find(find(M.Items({}), "show").children, M.MAP)
    t.eq(map.children, { { key = "map.none", text = "No world map switches here", disabled = true } })
end

tests["arrow menu map: every level stays within MENU_MAX"] = function(t)
    for _, level in ipairs(M.Counts(M.Items(state()))) do
        t.ok(level.rows <= T.MENU_MAX, level.path .. ": " .. level.rows .. " rows")
    end
end

return tests
