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
    t.eq(keys, { "windows.advice", "windows.setup", "windows.banker", "route.zoneFirst", "style.distance",
        "waypoint.clear" })
end

tests["arrow menu rows: each action is one Z-Flow already has"] = function(t)
    if type(R()) ~= "table" then return t.ok(false, "not loaded") end
    t.eq(R().Action("windows.advice"), { slash = ns.Advisor.WORD })
    t.eq(R().Action("windows.setup"), { slash = ns.SetupList.WORD })
    t.eq(R().Action("windows.banker"), { slash = ns.Banker.WORD })
    t.eq(R().Action("route.zoneFirst"), { toggle = "nav.zoneFirst" })
    -- Zen-3 CHANGES (lead section 733): two more that Z-Flow has.
    t.eq(R().Action("style.distance"), { toggle = "arrow.byDistance" })   -- UI/Arrow.lua:138
    t.eq(R().Action("waypoint.clear"), { slash = "way clear" })           -- UI/Arrow.lua:1580-1632
    t.eq(R().Action("nope"), nil)
    local a = R().Action("windows.advice")
    a.slash = "changed"
    t.eq(R().Action("windows.advice").slash, ns.Advisor.WORD, "a copy")
end

tests["arrow menu rows: as menu rows, Setup off in a fight, the toggle ticked as set"] = function(t)
    if type(R()) ~= "table" then return t.ok(false, "not loaded") end
    local out = R().Rows({ inCombat = false, settings = { ["nav.zoneFirst"] = true } })
    t.eq(byKey(out, "windows.setup"), { key = "windows.setup", text = ns.SetupList.HEADER })
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

-- Zen-3 CHANGES (lead section 733): the window rows are worded by each
-- panel's own title, read when asked; clearing the waypoint is greyed when
-- the state shows none.
tests["arrow menu rows: the window rows use each panel's own title"] = function(t)
    if type(R()) ~= "table" then return t.ok(false, "not loaded") end
    local out = R().Rows({ inCombat = false })
    t.eq(byKey(out, "windows.advice").text, ns.Advisor.TITLE)
    t.eq(byKey(out, "windows.setup").text, ns.SetupList.HEADER)
    t.eq(byKey(out, "windows.banker").text, ns.BankList.TITLE)
    local was = ns.Advisor.TITLE
    ns.Advisor.TITLE = "Changed"
    local now = byKey(R().Rows({ inCombat = false }), "windows.advice").text
    ns.Advisor.TITLE = was
    t.eq(now, "Changed", "read when asked")
end

tests["arrow menu rows: clearing the waypoint is offered only with one set"] = function(t)
    if type(R()) ~= "table" then return t.ok(false, "not loaded") end
    t.eq(byKey(R().Rows({ waypoint = true }), "waypoint.clear").disabled, nil)
    t.eq(byKey(R().Rows({ waypoint = false }), "waypoint.clear").disabled, true)
    t.eq(byKey(R().Rows({}), "waypoint.clear").disabled, true, "not known: greyed")
    t.eq(byKey(R().Rows({ settings = { ["arrow.byDistance"] = false } }), "style.distance").checked, false)
end

tests["arrow menu rows: what Flow's menu has and Z-Flow cannot do yet is listed as a need"] = function(t)
    if type(R()) ~= "table" then return t.ok(false, "not loaded") end
    local keys = {}
    for i, n in ipairs(R().NEEDS) do
        keys[i] = n.key
        t.ok(n.need == "CLIENT NEED" or n.need == "LEAD NEED", n.key .. ": who")
        t.ok(type(n.flow) == "string" and n.flow ~= "", n.key .. ": the Flow cite")
    end
    t.eq(keys, { "route.zonesSelected", "route.unhideAll", "waypoint.prompt", "waypoint.mapOnly", "party.shared",
        "windows.meters" })
    local covered = {}
    for i, c in ipairs(R().COVERED) do
        covered[i] = { c.key, c.setting }
        t.ok(type(c.by) == "string" and c.by:find("triproute-modes", 1, true) ~= nil, c.key .. ": covered by")
    end
    t.eq(covered, { { "route.order", "nav.routeSort" }, { "route.shown", "nav.routeShown" } })
end

return tests
