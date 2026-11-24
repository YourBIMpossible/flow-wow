-- The route rows of the arrows' right-click menu (lead section 387, R3):
-- the step the arrow points at as the first row, and under it Open it,
-- Hide this step, Go to the nearest... and Your waypoint. Plain tables
-- only: nothing here draws, clicks or reads the client.
local _, ns = ...

local M = ns.ArrowMenu

local function state(over)
    local s = { stacked = true, hidden = {}, text = {}, styles = {}, canShapes = true }
    for key, v in pairs(over or {}) do s[key] = v end
    return s
end

local row
row = function(items, key)
    for i = 1, #items do
        if items[i].key == key then return items[i], i end
        if type(items[i].children) == "table" then
            local below, at = row(items[i].children, key)
            if below then return below, at end
        end
    end
    return nil
end

local function has(t)
    local ok = type(M) == "table" and type(M.Items) == "function" and type(M.Action) == "function"
        and type(M.PathTo) == "function" and type(M.STEP) == "string"
    t.ok(ok, "ns.ArrowMenu answers the route rows")
    return ok
end

local STEP = { name = "Kill 8 wolves", from = "your route", open = true }

return {
    ["route: the first row names the step the arrow points at"] = function(t)
        if not has(t) then return end
        local items = M.Items(state({ step = STEP }))
        t.eq(items[1].key, M.STEP)
        t.eq(items[1].text, "Kill 8 wolves")
        local level = M.Level(items, M.PathTo(items, M.STEP))
        t.eq(level[1].title, true, "the step's level opens under a title line")
        t.eq(level[1].text, "Kill 8 wolves")
    end,

    ["route: with no step the first row says so and its step rows are off"] = function(t)
        if not has(t) then return end
        local items = M.Items(state())
        t.eq(items[1].key, M.STEP)
        t.eq(items[1].text, M.STEP_NONE)
        t.eq(row(items, M.OPEN).disabled, true)
        t.eq(row(items, M.HIDE).disabled, true)
        t.eq(M.Action(M.OPEN, state()), nil)
        t.eq(M.Action(M.HIDE, state()), nil)
    end,

    ["route: Open it opens the step's details only when there is a window for it"] = function(t)
        if not has(t) then return end
        t.eq(row(M.Items(state({ step = STEP })), M.OPEN).text, "Open it")
        t.eq(M.Action(M.OPEN, state({ step = STEP })).drawer, true)
        local closed = state({ step = { name = "x", from = "your quests", open = false } })
        t.eq(row(M.Items(closed), M.OPEN).disabled, true)
        t.eq(M.Action(M.OPEN, closed), nil)
    end,

    ["route: Hide this step drops what the step came from, and only what can be dropped"] = function(t)
        if not has(t) then return end
        local cases = {
            { "your route", "route" },
            { "an errand stop", "errand" },
            { "a party member you point at", "follow" },
            { "your own waypoint", "waypoint" },
            { "your route, along a trail you walked", "route" },
        }
        for _, c in ipairs(cases) do
            local s = state({ step = { name = "x", from = c[1] } })
            t.eq(row(M.Items(s), M.HIDE).text, "Hide this step")
            t.ok(not row(M.Items(s), M.HIDE).disabled, c[1] .. " can be hidden")
            local a = M.Action(M.HIDE, s)
            t.eq(a and a.hide, c[2], c[1])
        end
        local quests = state({ step = { name = "x", from = "your quests" } })
        t.eq(row(M.Items(quests), M.HIDE).disabled, true, "a quest step has nothing to drop it yet")
        t.eq(M.Action(M.HIDE, quests), nil)
    end,

    ["route: Go to the nearest lists the kinds; only a kind already seen is offered"] = function(t)
        if not has(t) then return end
        local s = state({ nearest = { vendor = true, flight = true } })
        local items = M.Items(s)
        local parent = row(items, M.NEAREST)
        t.eq(parent.text, "Go to the nearest...")
        t.eq(#parent.children, #M.NEAREST_KINDS)
        t.ok(not row(items, M.NEAREST .. ".vendor").disabled, "a vendor was seen")
        t.eq(row(items, M.NEAREST .. ".repair").disabled, true, "no repair vendor was seen")
        t.eq(M.Action(M.NEAREST .. ".flight", s).nearest, "flight")
        t.eq(M.Action(M.NEAREST .. ".repair", s), nil)
        t.eq(M.Action(M.NEAREST .. ".dragon", s), nil)
        t.eq(M.Action(M.NEAREST, s).open, M.NEAREST)
        local path = M.PathTo(items, M.NEAREST)
        t.eq(#path, 2, "the kinds are a level under the step's")
        local level = M.Level(items, path)
        t.eq(level[1].text, "Go to the nearest...")
        t.eq(level[#level].key, M.BACK)
    end,

    ["route: Your waypoint is offered only while one is set"] = function(t)
        if not has(t) then return end
        t.eq(row(M.Items(state()), M.WAYPOINT).text, "Your waypoint")
        t.eq(row(M.Items(state()), M.WAYPOINT).disabled, true)
        t.eq(M.Action(M.WAYPOINT, state()), nil)
        local set = state({ waypoint = true })
        t.ok(not row(M.Items(set), M.WAYPOINT).disabled, "set: offered")
        t.eq(M.Action(M.WAYPOINT, set).waypoint, true)
    end,

    ["route: every level still fits the most a level may hold"] = function(t)
        if not has(t) then return end
        local party = {}
        for i = 1, 40 do party[i] = { unit = "raid" .. i, name = "M" .. i } end
        local items = M.Items(state({ step = STEP, feedback = true, party = party,
            styles = { { key = "modern", label = "Modern", on = true } },
            nearest = { vendor = true }, waypoint = true }))
        for _, level in ipairs(M.Counts(items)) do
            t.ok(level.rows <= ns.Settings.Topics.MENU_MAX, level.path .. ": " .. level.rows)
        end
    end,
}
