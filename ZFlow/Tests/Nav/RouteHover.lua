local _, ns = ...
-- Parity row B-20, the logic half (lead section 738): pointing at a step in
-- a list (the route list, the tracker) shows that step alone on the map,
-- as Flow's Modules/Nav/MapOverlay.lua (:46-49 hoverSolo, :767-781 SoloAt
-- and SoloStops, :1971-1975 M.Hover). Pure parts and the module over a
-- bare kernel; made-up places. Not tested in game. Fails before: no file.
local tests = {}

local function H() return ns.Nav and ns.Nav.RouteHover end

local A = { map = 1429, x = 0.40, y = 0.60 }
local B = { map = 1429, x = 0.45, y = 0.62 }
local C = { map = 1436, x = 0.40, y = 0.60 }

tests["route hover: the step alone, found by its place"] = function(t)
    t.eq(type(H()), "table", "loaded")
    if type(H()) ~= "table" then return end
    local plan = { { place = A }, { place = B }, { place = C } }
    t.eq(H().SoloAt(plan, B), 2)
    t.eq(H().SoloAt(plan, { map = 1429, x = 0.45, y = 0.62 }), 2, "the same place, another table")
    t.eq(H().SoloAt(plan, { map = 1436, x = 0.45, y = 0.62 }), nil, "another map")
    t.eq(H().SoloAt(plan, nil), nil)
    t.eq(H().SoloAt(nil, A), nil)
    t.eq(H().SoloStops(3, 2), { 2 }, "itself, alone (Flow 0.35.289)")
    t.eq(H().SoloStops(3, 4), {}, "out of range: none")
    t.eq(H().SoloStops(3, nil), {})
end

tests["route hover: pointing sets it, says so once, and leaving clears it"] = function(t)
    if type(H()) ~= "table" then return t.ok(false, "not loaded") end
    local c = ns.make.fakeClient()
    local k = ns.Kernel({}, c)
    local api = H().Declare(k)
    k:Boot()
    local seen = {}
    k.bus:on("test", H().EVENT, function(p) seen[#seen + 1] = p or false end)
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    t.eq(api.Pointed(), nil, "nothing as made")
    api.Hover(A)
    t.eq(api.Pointed(), A)
    t.eq(#seen, 1)
    api.Hover({ map = 1429, x = 0.40, y = 0.60 })
    t.eq(#seen, 1, "the same place again: not said again")
    api.Hover(B)
    t.eq(#seen, 2)
    api.Hover(nil)
    t.eq(api.Pointed(), nil, "left")
    t.eq(seen[3], false, "said as cleared")
    api.Hover({ map = 1429, x = 0 / 0, y = 0.5 })
    t.eq(api.Pointed(), nil, "a place that is not a number is none")
    local p = api.Pointed()
    api.Hover(A)
    p = api.Pointed()
    p.x = 0.99
    t.eq(api.Pointed().x, 0.40, "a copy")
    t.eq(type(k.use(H().NAME).Hover), "function", "through its provides")
end

return tests
