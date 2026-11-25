local _, ns = ...

-- Tests for G43 (P-TRIP): the route tracker window's parts (UI/RouteTracker.lua
-- RT.Children) and the rows it is given (Nav/Trip.lua P.TrackRows). Pure
-- parts only; made-up places.

local tests = {}

local function RT() return ns.RouteTracker end
local function P() return ns.Nav.Trip end

local HERE = { map = 1, x = 0.5, y = 0.5, size = { w = 1000, h = 1000 } }

local function current()
    return { kind = "run", label = "Trip", stops = {
        { label = "Inn", detail = "Inna", place = { map = 1, x = 0.5, y = 0.6 } },
        { label = "Vendor", place = { map = 1, x = 0.8, y = 0.6 } },
        { label = "Mail", place = { map = 2, x = 0.5, y = 0.5 } },
    } }
end

local function byKey(children, key)
    for _, part in ipairs(children) do
        if part.key == key then return part end
        for _, kid in ipairs(part.children or {}) do
            if kid.key == key then return kid end
        end
    end
    return nil
end

tests["track rows: each stop with its distance from the one before"] = function(t)
    local rows = P().TrackRows(current(), HERE)
    t.eq(#rows, 3)
    t.eq(rows[1], { label = "Inn", detail = "Inna", dist = "100 yd" })
    t.eq(rows[2], { label = "Vendor", dist = "300 yd" })
    t.eq(rows[3], { label = "Mail", dist = P().OTHER_MAP })
    t.eq(P().TrackRows(nil, HERE), nil)
end

tests["tracker parts: the current stop is marked, the rest follow with distances"] = function(t)
    local kids = RT().Children(P().TrackRows(current(), HERE))
    t.eq(kids[1].kind, "header")
    local now = byKey(kids, "current")
    t.eq(now and now.text, "Inn")
    t.eq(now and now.tone, RT().TONE_NOW)
    t.eq(now and now.right, "100 yd")
    t.eq(now and now.sub, "Inna")
    local nextOne = byKey(kids, "next1")
    t.eq(nextOne and nextOne.text, "Vendor")
    t.eq(nextOne and nextOne.tone, nil)
    t.ok(byKey(kids, "footer") ~= nil, "a footer with the skip button")
    t.ok(ns.Kit.Window({ id = RT().ID, title = "x", children = kids }) ~= nil, "the kit takes the parts")
end

tests["tracker parts: no route is the empty state"] = function(t)
    local kids = RT().Children(nil)
    local e = byKey(kids, "empty")
    t.eq(e and e.kind, "empty")
    t.eq(e and e.text, RT().EMPTY[1])
    t.eq(e and e.how, RT().EMPTY[2])
    t.eq(byKey(kids, "current"), nil)
    t.ok(ns.Kit.Window({ id = RT().ID, title = "x", children = kids }) ~= nil, "the kit takes the parts")
end

tests["tracker parts: no more than RT.MAX stops are listed"] = function(t)
    local rows = {}
    for i = 1, RT().MAX + 3 do rows[i] = { label = "S" .. i, dist = "1 yd" } end
    local kids = RT().Children(rows)
    t.ok(byKey(kids, "next" .. (RT().MAX - 1)) ~= nil, "the last shown")
    t.eq(byKey(kids, "next" .. RT().MAX), nil)
    t.ok(byKey(kids, "more") ~= nil, "says how many more")
end

-- S42: the quest's own item under the current step.
tests["tracker parts: the quest's item is one item line right under the current step"] = function(t)
    local rows = P().TrackRows(current(), HERE)
    local kids = RT().Children(rows, { id = 7001, name = "Test Whistle", count = 3, quality = 2, icon = 134400 })
    t.eq(kids[2].key, "current")
    local item = kids[3]
    t.eq(item.key, "questItem")
    t.eq(item.kind, "itemLine")
    t.eq(item.name, "Test Whistle")
    t.eq(item.count, 3)
    t.eq(item.quality, 2)
    t.eq(item.icon, 134400)
    t.eq(item.item, 7001)
    t.eq(item.note, RT().ITEM_NOTE)
    t.eq(item.onClick, nil, "no button: it uses nothing")
    t.eq(kids[4].key, "next1", "the stops after it follow")
    t.ok(ns.Kit.Window({ id = RT().ID, title = "x", children = kids }) ~= nil, "the kit takes the parts")
end

tests["tracker parts: no item, no line; no route, no line"] = function(t)
    local rows = P().TrackRows(current(), HERE)
    t.eq(byKey(RT().Children(rows), "questItem"), nil)
    t.eq(byKey(RT().Children(rows, "x"), "questItem"), nil)
    t.eq(byKey(RT().Children(rows, {}), "questItem"), nil)
    t.eq(byKey(RT().Children(nil, { id = 7001, name = "Test Whistle" }), "questItem"), nil)
end

tests["tracker parts: an item with odd facts still gives a line the kit takes"] = function(t)
    local rows = P().TrackRows(current(), HERE)
    local kids = RT().Children(rows, { id = 7001, name = "a|cffb", count = -1, quality = 9, icon = "" })
    local item = byKey(kids, "questItem")
    t.eq(item and item.name, RT().ITEM_PLAIN, "a name that cannot be shown is not shown")
    t.eq(item and item.count, nil)
    t.eq(item and item.quality, nil)
    t.eq(item and item.icon, nil)
    t.ok(ns.Kit.Window({ id = RT().ID, title = "x", children = kids }) ~= nil, "the kit takes the parts")
    local named = RT().ItemLine({ name = "Test Whistle" })
    t.eq(named and named.name, "Test Whistle", "a name alone is enough")
    t.eq(named and named.item, nil)
end

-- The wiring to Nav/TrackerList.lua (A2-18): the tracker lists the route's
-- View (held steps too, with their reason), the current step is the first
-- not held, and the "more" line counts what TL.Rows left out.
local function viewHeld()
    return { kind = "quest", label = "Quests", stops = {
        { label = "Hand in Wolves", turnIn = true, quest = 7, held = "the item is not looted yet",
          place = { map = 1, x = 0.5, y = 0.6 } },
        { label = "Boars", quest = 8, detail = "Boars slain: 2/8", place = { map = 1, x = 0.8, y = 0.6 } },
    } }
end

tests["tracker wiring: the view's held step is listed with its reason, the next is current"] = function(t)
    local rows, more = RT().Rows(viewHeld(), nil, HERE)
    t.eq(#rows, 2)
    t.eq(more, 0)
    local kids = RT().Children(rows, nil, more)
    t.eq(rows[1].current, true, "the route's step first (lead section 770)")
    local held = byKey(kids, "held2")
    t.eq(held and held.text, "Hand in Wolves")
    t.eq(held and held.sub, RT().HELD:format("the item is not looted yet"))
    t.eq(held and held.tone, nil, "a held step is not the current one")
    local now = byKey(kids, "current")
    t.eq(now and now.text, "Boars")
    t.eq(now and now.sub, "Boars slain: 2/8")
    t.eq(now and now.tone, RT().TONE_NOW)
    t.ok(ns.Kit.Window({ id = RT().ID, title = "x", children = kids }) ~= nil, "the kit takes the parts")
end

tests["tracker wiring: no view falls back to the walked route; more counts what is left out"] = function(t)
    local rows = RT().Rows(nil, current(), HERE)
    t.eq(rows and #rows, 3)
    t.eq(rows and rows[1].current, true)
    t.eq(RT().Rows(nil, nil, HERE), nil)
    local long = { stops = {} }
    for i = 1, RT().MAX + 2 do long.stops[i] = { label = "S" .. i, place = { map = 1, x = 0.5, y = 0.5 } } end
    local r2, more = RT().Rows(long, nil, HERE)
    t.eq(#r2, RT().MAX)
    t.eq(more, 2)
    local m = byKey(RT().Children(r2, nil, more), "more")
    t.eq(m and m.text, RT().MORE:format(2))
end

-- Lead section 762: the view is used whenever it has stops or steps that
-- can't be placed (left); the walked route (Current) only when it has
-- neither, as Flow's tracker listed its blocked goals with an empty plan
-- (Modules/Nav/RouteTracker.lua:504-519). Fails before: an empty view fell
-- back to Current, which carries no left list.
tests["tracker wiring: an empty route with steps that can't be placed lists them"] = function(t)
    local view = { stops = {}, left = { { label = "Kill Hogger", quest = 9, why = "no place known" } } }
    local rows = RT().Rows(view, current(), HERE)
    t.eq(rows and #rows, 1)
    t.eq(rows and rows[1] and { rows[1].label, rows[1].left }, { "Kill Hogger", "no place known" })
    t.eq(rows and rows[1] and rows[1].current, nil, "never the current step")
    local r2 = RT().Rows({ stops = {}, left = {} }, current(), HERE)
    t.eq(r2 and #r2, 3, "neither: the walked route, as before")
end

return tests
