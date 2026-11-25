local _, ns = ...
-- Parity row A1-11, the logic half (lead sections 729 and 731): the arrow
-- right-click menu's sections that Flow has and Z-Flow's UI/ArrowMenu.lua
-- lacks, as plain data in Nav/ArrowMenuRows.lua. Flow: Nav.lua:4402-4427
-- (the menu), Menu.lua:664 RouteItems (route, windows), Nav.lua:5230
-- ArrowMenuItems (the arrow's look). Only entries whose action Z-Flow
-- already has; the rest are listed as needs. Plain tables; not tested in
-- game. Fails before: no such file.
local tests = {}

local function R() return ns.ArrowMenuRows end

local function byKey(rows, key)
    for _, r in ipairs(rows or {}) do
        if r.key == key then return r end
    end
    return nil
end

tests["arrow menu rows: an ordered list, each with key, words, enabled-when and its action"] = function(t)
    t.eq(type(R()), "table", "the file is loaded")
    if type(R()) ~= "table" then return end
    local keys = {}
    for i, e in ipairs(R().ENTRIES) do
        keys[i] = e.key
        t.ok(type(e.text) == "string" and e.text ~= "", e.key .. ": words")
        t.ok(e.when == "always" or e.when == "outOfFight", e.key .. ": enabled-when")
        t.eq(type(e.action), "table", e.key .. ": an action")
    end
    t.eq(keys, { "windows.advice", "windows.setup", "windows.banker", "route.zoneFirst" })
end

tests["arrow menu rows: each action is one Z-Flow already has"] = function(t)
    if type(R()) ~= "table" then return t.ok(false, "not loaded") end
    t.eq(R().Action("windows.advice"), { slash = ns.Advisor.WORD })
    t.eq(R().Action("windows.setup"), { slash = ns.SetupList.WORD })
    t.eq(R().Action("windows.banker"), { slash = ns.Banker.WORD })
    t.eq(R().Action("route.zoneFirst"), { toggle = "nav.zoneFirst" })
    t.eq(R().Action("nope"), nil)
    local a = R().Action("windows.advice")
    a.slash = "changed"
    t.eq(R().Action("windows.advice").slash, ns.Advisor.WORD, "a copy")
end

tests["arrow menu rows: as menu rows, Setup off in a fight, the toggle ticked as set"] = function(t)
    if type(R()) ~= "table" then return t.ok(false, "not loaded") end
    local out = R().Rows({ inCombat = false, settings = { ["nav.zoneFirst"] = true } })
    t.eq(byKey(out, "windows.setup"), { key = "windows.setup", text = "Flow Setup" })
    t.eq(byKey(out, "route.zoneFirst").checked, true)
    local fight = R().Rows({ inCombat = true, settings = { ["nav.zoneFirst"] = false } })
    t.eq(byKey(fight, "windows.setup").disabled, true, "in a fight")
    t.eq(byKey(fight, "windows.advice").disabled, nil, "the advice panel opens in a fight")
    t.eq(byKey(fight, "route.zoneFirst").checked, false)
    local unknown = R().Rows({})
    t.eq(byKey(unknown, "windows.setup").disabled, true, "a fight not known: off")
    t.eq(byKey(unknown, "route.zoneFirst").checked, nil, "not read: neither")
    t.eq(#R().Rows(nil), #R().ENTRIES, "no state: still every row")
end

tests["arrow menu rows: what Flow's menu has and Z-Flow cannot do yet is listed as a need"] = function(t)
    if type(R()) ~= "table" then return t.ok(false, "not loaded") end
    local keys = {}
    for i, n in ipairs(R().NEEDS) do
        keys[i] = n.key
        t.ok(n.need == "CLIENT NEED" or n.need == "LEAD NEED", n.key .. ": who")
        t.ok(type(n.flow) == "string" and n.flow ~= "", n.key .. ": the Flow cite")
    end
    t.eq(keys, { "route.order", "route.zonesSelected", "route.unhideAll", "route.shown", "waypoint.prompt",
        "waypoint.mapOnly", "waypoint.clear", "party.shared", "windows.meters", "style.distance" })
end

return tests
