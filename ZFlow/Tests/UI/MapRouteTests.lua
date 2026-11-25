local _, ns = ...

-- Tests for UI/MapRoute.lua (lead section 387, R5): the route's numbered
-- marks on the world map and the zone card. Pure parts, then the fake
-- client's marks and card. Made-up quests, places and zones. Not tested in
-- game.

local tests = {}

local function MR() return ns.MapRoute end
local function RL() return ns.RouteList end

local function view()
    return { kind = "quests", stops = {
        { quest = 11, objective = 1, label = "Boar Trouble", detail = "Boars slain: 2/8",
          place = { map = 1, x = 0.5, y = 0.6 } },
        { quest = 14, kind = "pickup", label = "Wolves at the Gate", detail = "Pick up from Guard Thom",
          place = { map = 2, x = 0.2, y = 0.2 } },
        { quest = 12, turnIn = true, label = "A Letter Home", detail = "Turn in: Marshal Dunn",
          place = { map = 1, x = 0.8, y = 0.6 } },
        { quest = 13, turnIn = true, label = "Lost Tools", detail = "Turn in: Marshal Dunn",
          place = { map = 1, x = 0.8, y = 0.6 } },
        { quest = 15, turnIn = true, label = "Old Debts", detail = "Turn in",
          place = { map = 2, x = 0.3, y = 0.3 } },
        { quest = 16, turnIn = true, label = "Stale Bread", detail = "Turn in", held = "not complete any more",
          place = { map = 2, x = 0.1, y = 0.1 } },
    }, left = {} }
end

local function rows() return (RL().Rows(view(), nil)) end

local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, {})
    c.setSaved(ns.id.charDB, {})
    local k = ns.Kernel({}, c)
    ns.Diag.Start(k)
    local current = opts.view
    k:Module({ name = "tripRoute", provides = { View = function() return current end } })
    RL().Declare(k)
    local api = MR().Declare(k)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return { c = c, k = k, api = api, set = function(v) current = v end }
end

tests["pins: only the shown map's stops, numbered as the route goes"] = function(t)
    local one = MR().Pins(rows(), 1)
    t.eq(#one, 2)
    t.eq(one[1].n, 1)
    t.eq(one[1].x, 0.5)
    t.eq(one[1].y, 0.6)
    t.eq(one[1].now, true)
    t.eq(one[2].n, 3, "the route's third stop, not the map's second")
    t.eq(one[2].now, false)
    local two = MR().Pins(rows(), 2)
    t.eq(#two, 2)
    t.eq(two[1].n, 2)
    t.eq(two[2].n, 4)
    t.eq(#MR().Pins(rows(), 3), 0, "a map with no stop has no pin")
    t.eq(#MR().Pins(nil, 1), 0)
end

tests["pins: the tooltip names the stop; a waiting stop has no pin"] = function(t)
    local one = MR().Pins(rows(), 1)
    t.eq(one[1].text, "Stop 1: Boars slain: 2/8")
    t.eq(one[1].sub, "For the quest Boar Trouble")
    t.eq(one[2].text, "Stop 3: Turn in 2 quests")
    t.eq(one[2].sub, "A Letter Home, Lost Tools. Give them to Marshal Dunn")
    for _, p in ipairs(MR().Pins(rows(), 2)) do
        t.ok(not p.text:find("Stale Bread", 1, true), "the waiting stop is not pinned")
    end
end

tests["card: the zone's name, levels, how many stops and which is next"] = function(t)
    local card = MR().Card(rows(), 1, { name = "Elwynn Forest", low = 1, high = 10 })
    t.eq(card.title, "Elwynn Forest")
    t.eq(card.lines, { "Levels 1 to 10", "2 route stops here",
        "Next here: stop 1, where the arrow points. Boars slain: 2/8" })
    t.eq(card.stops, 2)
    t.eq(card.next, 1)
end

tests["card: a later zone counts its own stops and the ones waiting"] = function(t)
    local card = MR().Card(rows(), 2, { name = "Westfall", low = 10, high = 20 })
    t.eq(card.lines, { "Levels 10 to 20", "2 route stops here", "1 waiting here",
        "Next here: stop 2. Wolves at the Gate" })
    t.eq(card.waiting, 1)
    t.eq(card.next, 2)
end

tests["card: one stop, one level, and nothing the game did not say"] = function(t)
    local only = { stops = { { label = "Inn", place = { map = 5, x = 0.5, y = 0.5 } } } }
    local card = MR().Card(RL().Rows(only, nil), 5, { name = "Town", low = 30, high = 30 })
    t.eq(card.lines[1], "Level 30")
    t.eq(card.lines[2], "1 route stop here")
    local bare = MR().Card(RL().Rows(only, nil), 5, nil)
    t.eq(bare.title, MR().NO_NAME)
    t.eq(bare.lines[1], MR().NO_LEVELS, "no level range is made up")
end

tests["card: only waiting stops here says so"] = function(t)
    local v = { stops = { { quest = 1, turnIn = true, label = "Q", detail = "Turn in", held = "x",
                            place = { map = 7, x = 0.5, y = 0.5 } } } }
    local card = MR().Card(RL().Rows(v, nil), 7, { name = "Z" })
    t.eq(card.lines, { MR().NO_LEVELS, MR().NO_STOPS, "1 waiting here" })
    t.eq(card.next, nil)
end

tests["card: hidden when the route has nothing in the zone"] = function(t)
    t.eq(MR().Card(rows(), 3, { name = "Duskwood", low = 20, high = 30 }), nil)
    t.eq(MR().Card(nil, 1, { name = "Elwynn Forest" }), nil)
    t.eq(MR().Card(rows(), nil, nil), nil)
end

tests["map: the marks and the card follow the shown map"] = function(t)
    local h = start({ view = view() })
    h.c.setMapInfo(1, { name = "Elwynn Forest", low = 1, high = 10 })
    h.api.Refresh()
    t.eq(h.api.Shown(), false, "the world map is not open")
    h.c.setWorldMap(1)
    h.api.Refresh()
    local pins, card = h.c.routePinSets[1], h.c.mapCards[1]
    t.eq(#pins.pins, 2)
    t.eq(pins.pins[1].n, 1)
    t.eq(pins.pins[2].n, 3)
    t.eq(card.shown, true)
    t.eq(card.card.title, "Elwynn Forest")
    t.eq(card.card.lines[2], "2 route stops here")
    h.c.setWorldMap(2)
    h.api.Refresh()
    t.eq(pins.pins[1].n, 2)
    t.eq(pins.pins[2].n, 4)
    t.eq(card.card.title, MR().NO_NAME, "the game said nothing of this map")
    t.eq(card.card.lines[1], MR().NO_LEVELS)
    h.c.setWorldMap(3)
    h.api.Refresh()
    t.eq(pins.shown, false, "nothing of the route on this map")
    t.eq(card.shown, false)
    h.c.setWorldMap(nil)
    h.api.Refresh()
    t.eq(h.api.Shown(), false)
end

tests["map: nothing is redrawn while nothing changed"] = function(t)
    local h = start({ view = view() })
    h.c.setWorldMap(1)
    h.api.Refresh()
    h.api.Refresh()
    h.api.Refresh()
    t.eq(h.c.routePinSets[1].draws, 1)
    t.eq(h.c.mapCards[1].shows, 1)
end

tests["map: no route, no marks and no card"] = function(t)
    local h = start({})
    h.c.setWorldMap(1)
    h.api.Refresh()
    t.eq(h.api.Shown(), false)
    h.set(view())
    h.api.Refresh()
    t.eq(h.api.Shown(), true)
    h.set(nil)
    h.api.Refresh()
    t.eq(h.c.routePinSets[1].shown, false)
    t.eq(h.c.mapCards[1].shown, false)
end

-- B-19 (lead section 780): a click on a step's mark opens that step, as
-- Flow's map marks do (Modules/Nav/MapOverlay.lua:193-208, a left click:
-- ns.nav:OpenStop -> N:ShowStop, Nav.lua:4325-4328: the step's own card,
-- and a second click on the same step closes it). Here the step's card is
-- the map's card (client.mapCard) showing that step; a second click gives
-- the zone back. Fails before: no MR.StepCard, and a click does nothing.
tests["click: the step's card, pure"] = function(t)
    t.eq(type(MR().StepCard), "function", "MR.StepCard")
    if type(MR().StepCard) ~= "function" then return end
    local r = rows()
    t.eq(MR().StepCard(r[1]), { title = MR().PIN:format(1, tostring(r[1].text)), lines = { r[1].sub } })
    t.eq(MR().StepCard({ n = 3, text = "X", sub = "Y", dist = "40 yd" }),
        { title = MR().PIN:format(3, "X"), lines = { "Y", "40 yd" } })
    t.eq(MR().StepCard(nil), nil)
end

tests["click: a mark opens its step on the map's card; again gives the zone back"] = function(t)
    local h = start({ view = view() })
    h.c.setMapInfo(1, { name = "Elwynn Forest", low = 1, high = 10 })
    h.c.setWorldMap(1)
    h.api.Refresh()
    local pins, card = h.c.routePinSets[1], h.c.mapCards[1]
    t.eq(type(pins.click), "function", "the fake can click")
    if type(pins.click) ~= "function" then return end
    pins.click(3)
    t.eq(card.card.title, MR().PIN:format(3, tostring(rows()[3].text)), "the step's card")
    t.eq(h.api.Opened(), 3)
    h.api.Refresh()
    t.eq(card.card.title, MR().PIN:format(3, tostring(rows()[3].text)), "it stays open")
    pins.click(3)
    t.eq(card.card.title, "Elwynn Forest", "a second click: the zone again")
    t.eq(h.api.Opened(), nil)
    pins.click(1, "RightButton")
    t.eq(h.api.Opened(), nil, "a right click opens nothing")
    pins.click(1)
    h.c.setWorldMap(2)
    h.api.Refresh()
    t.eq(h.api.Opened(), nil, "another map: the step is not on it, the zone's card")
    t.eq(card.card.title, MR().NO_NAME)
    pins.click(99)
    t.eq(h.api.Opened(), nil, "a number with no mark opens nothing")
end

-- B-21 (lead section 788): "Point the arrow here" from the map. A right
-- click on a step's mark sets your own waypoint there through Nav/
-- Waypoint.lua W.SetAt (as Alt + click on the map), and a right click on
-- the mark your waypoint is on takes it off (W.Clear), as B-12 does for a
-- flight master. Flow has it in the mark's menu (Modules/Nav/
-- MapOverlay.lua:193-208, M.PointHere). Fails before: a right click does
-- nothing.
tests["click: a right click points your waypoint at the step; again takes it off"] = function(t)
    local h = start({ view = view() })
    h.c.setWorldMap(1)
    h.api.Refresh()
    local pins = h.c.routePinSets[1]
    if type(pins.click) ~= "function" then return t.ok(false, "no click") end
    local W = ns.Nav.Waypoint
    local slot = W.Slot(h.k.store)
    t.eq(W.Get(slot), nil, "no waypoint first")
    pins.click(3, "RightButton")
    local wp = W.Get(slot)
    t.eq(wp and wp.map, 1)
    t.eq(wp and wp.x, 0.8)
    t.eq(wp and wp.y, 0.6)
    t.eq(wp and wp.label, MR().PointLabel(rows()[3]))
    t.eq(h.api.Opened(), nil, "a right click opens no card")
    pins.click(3, "RightButton")
    t.eq(W.Get(slot), nil, "the same mark again: taken off")
    pins.click(1, "RightButton")
    pins.click(3, "RightButton")
    t.eq(W.Get(slot) and W.Get(slot).x, 0.8, "another mark: moved there")
    pins.click(99, "RightButton")
    t.eq(W.Get(slot) and W.Get(slot).x, 0.8, "no such mark: nothing changes")
    t.eq(MR().PointLabel({ n = 2, text = string.rep("a", 200) }), nil, "too long a label: none")
end

return tests
