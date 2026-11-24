-- The player's own waypoint (G35) set two more ways: Alt + click on the
-- world map, and a waypoint line pasted from somewhere else. Over the fake
-- client, and the real client's map hook over a hand-built environment.
-- Look only: it points, no more. Made-up maps and names. No game client is
-- involved. Not tested in game.
local _, ns = ...

local A, N = ns.Arrow, ns.Nav
local W = N.Waypoint
local R = W.REASON

local function start()
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    c.setMapCont(1411, 1)
    c.setMapName(1411, "Test Vale")
    c.setMapSize(1412, 1000, 500)
    c.setMapCont(1412, 1)
    c.setMapName(1412, "Test Reach")
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    A.Start(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c
end

local function last(c) return c.printed[#c.printed] or "" end
local function saved(k)
    local nav = k.store:get(W.SCOPE, W.PATH)
    return type(nav) == "table" and nav.waypoint or nil
end
local function has(text, part) return text:find(part, 1, true) ~= nil end
local function near(t, got, want, what)
    t.ok(type(got) == "number" and math.abs(got - want) < 1e-9,
        (what or "number") .. ": got " .. tostring(got) .. ", wanted " .. tostring(want))
end

local T = {}

T["paste: x, y with a comma after x, as the addon itself writes it"] = function(t)
    local got, why = W.Parse("45.2, 61.8 Copper vein")
    t.eq(why, nil)
    near(t, got.x, 0.452, "x")
    near(t, got.y, 0.618, "y")
    t.eq(got.label, "Copper vein")
    t.eq(W.Parse("/way 45, 61").label, nil)
end

T["paste: a decimal comma is still turned down, never guessed"] = function(t)
    local got, why = W.Parse("45,2 61,8")
    t.eq(got, nil)
    t.eq(why, R.comma)
    got, why = W.Parse("45, 61,8")
    t.eq(got, nil)
    t.eq(why, R.comma)
end

T["paste: the map's number first names the map"] = function(t)
    local got = W.Parse("/way #1412 45.2 61.8 the inn")
    t.eq(got.map, 1412)
    near(t, got.x, 0.452, "x")
    t.eq(got.label, "the inn")
    local slot = {}
    local wp = W.Set(slot, { map = 1411, x = 0.5, y = 0.5 }, "/way #1412 45.2 61.8")
    t.eq(wp and wp.map, 1412, "the pasted map, not the one the player is on")
end

T["paste: a zone name first is taken only for the map the player is on"] = function(t)
    local got = W.Parse("/way Test Vale 45.2 61.8 the inn")
    t.eq(got.zone, "Test Vale")
    t.eq(got.label, "the inn")
    local slot = {}
    local here = { map = 1411, x = 0.5, y = 0.5 }
    local wp = W.Set(slot, here, "/way test vale 45.2 61.8", "Test Vale")
    t.eq(wp and wp.map, 1411)
    local none, why = W.Set(slot, here, "/way Far Shore 10 20", "Test Vale")
    t.eq(none, nil)
    t.eq(why, "that waypoint is for another zone: Far Shore")
    t.eq(slot.waypoint, wp, "the waypoint that was set stays")
    none = W.Set(slot, here, "/way Far Shore 10 20", nil)
    t.eq(none, nil, "a name that cannot be checked is not taken")
end

T["paste: words that are not a zone and two numbers keep their old reason"] = function(t)
    local got, why = W.Parse("way abc 5")
    t.eq(got, nil)
    t.eq(why, "x is not a number: abc")
end

T["set at: a point picked on a map; one that is not a point changes nothing"] = function(t)
    local slot = {}
    local wp = W.SetAt(slot, 1412, 0.25, 0.75)
    t.eq(wp, { map = 1412, x = 0.25, y = 0.75 })
    t.eq(slot.waypoint, wp)
    for _, bad in ipairs({ { 1412, 1.2, 0.5 }, { 1412, 0.5, -0.1 }, { nil, 0.5, 0.5 }, { 1412, 0 / 0, 0.5 } }) do
        local none, why = W.SetAt(slot, bad[1], bad[2], bad[3])
        t.eq(none, nil)
        t.eq(why, R.point)
    end
    t.eq(slot.waypoint, wp, "the waypoint that was set stays")
    t.eq(W.SetAt(nil, 1412, 0.5, 0.5), nil)
end

T["map click: Alt + click on the map the player is on sets the waypoint and the arrow points at it"] = function(t)
    local k, c = start()
    t.eq(#c.mapClicks, 1, "the map's clicks are listened for, once")
    c.clickMap(1411, 0.5, 0.3)
    t.eq(saved(k), { map = 1411, x = 0.5, y = 0.3 })
    t.ok(has(last(c), "waypoint set: 50.0, 30.0 in Test Vale"), last(c))
    t.ok(has(last(c), "/way clear removes it"), "how to take it away is said: " .. last(c))
    c.advance(0.1, 2)
    local q = c.arrows[1]
    t.eq(q and q.shown, true, "the arrow is up")
    t.ok(has(table.concat(q.lines or {}, " | "), "Waypoint"), "its line names the waypoint: "
        .. table.concat(q.lines or {}, " | "))
    t.ok(has(table.concat(q.lines or {}, " | "), "100 yd"), "and how far: 0.2 of 500 yards north")
    t.eq(k.problems:count(), 0)
end

T["map click: a spot on another map of the same continent is set and pointed at"] = function(t)
    local k, c = start()
    c.clickMap(1412, 0.25, 0.75)
    t.eq(saved(k), { map = 1412, x = 0.25, y = 0.75 })
    t.ok(has(last(c), "in Test Reach"), last(c))
    c.advance(0.1, 2)
    t.eq(c.arrows[1] and c.arrows[1].shown, true)
    t.eq(k.problems:count(), 0)
end

T["map click: a click that is not a point changes nothing and says so"] = function(t)
    local k, c = start()
    c.clickMap(1411, 0.5, 0.3)
    c.clickMap(1411, 1.5, 0.3)
    t.eq(saved(k), { map = 1411, x = 0.5, y = 0.3 }, "the first one stays")
    t.ok(has(last(c), "nothing changed"), last(c))
end

T["map click: /way clear takes a clicked waypoint away"] = function(t)
    local k, c = start()
    c.clickMap(1411, 0.5, 0.3)
    c.slashes["/way"]("clear")
    t.eq(saved(k), nil)
end

T["slash: a pasted line with the zone the player is in sets it; another zone is turned down"] = function(t)
    local k, c = start()
    c.slashes["/way"]("Test Vale 45.2, 61.8 the inn")
    t.eq(saved(k) and saved(k).label, "the inn")
    near(t, saved(k).x, 0.452, "x")
    c.slashes["/way"]("Far Shore 10 20")
    t.ok(has(last(c), "that waypoint is for another zone: Far Shore; nothing changed."), last(c))
    near(t, saved(k).x, 0.452, "the waypoint that was set stays")
end

T["slash: with nothing after it, the help says the map click too"] = function(t)
    local _, c = start()
    c.slashes["/way"]("")
    t.ok(has(last(c), "hold Alt and click a spot on the world map"), last(c))
end

-- The real client's hook, over a hand-built world map.
local function mapEnv(alt)
    local scripts = {}
    local scroll = { cursor = { 0.4, 0.6 } }
    function scroll:HookScript(name, fn) scripts[name] = fn end
    function scroll:GetNormalizedCursorPosition() return self.cursor[1], self.cursor[2] end
    local wm = { ScrollContainer = scroll, map = 1411 }
    function wm:GetMapID() return self.map end
    local env = { WorldMapFrame = wm, IsAltKeyDown = function() return alt.down end }
    return env, scripts, wm, scroll
end

T["real client: Alt + left click tells the map and the spot where the button went down"] = function(t)
    local alt = { down = true }
    local env, scripts, wm = mapEnv(alt)
    local c = ns.make.client(env)
    local got = {}
    t.eq(c.mapClick(function(map, x, y) got[#got + 1] = { map, x, y } end), true)
    t.ok(type(scripts.OnMouseDown) == "function" and type(scripts.OnMouseUp) == "function", "hooked, not replaced")
    scripts.OnMouseDown(nil, "LeftButton")
    wm.map = 1412   -- the map's own click moved on to another map
    scripts.OnMouseUp(nil, "LeftButton")
    t.eq(got, { { 1411, 0.4, 0.6 } })
end

T["real client: no Alt, another button, or a spot off the map tells nothing"] = function(t)
    local alt = { down = false }
    local env, scripts, _, scroll = mapEnv(alt)
    local c = ns.make.client(env)
    local n = 0
    c.mapClick(function() n = n + 1 end)
    scripts.OnMouseDown(nil, "LeftButton"); scripts.OnMouseUp(nil, "LeftButton")
    alt.down = true
    scripts.OnMouseDown(nil, "RightButton"); scripts.OnMouseUp(nil, "RightButton")
    scroll.cursor = { 1.3, 0.5 }
    scripts.OnMouseDown(nil, "LeftButton"); scripts.OnMouseUp(nil, "LeftButton")
    scripts.OnMouseUp(nil, "LeftButton")
    t.eq(n, 0)
end

T["real client: no world map gives nil and a reason; a map's name is read"] = function(t)
    local c = ns.make.client({})
    local ok, why = c.mapClick(function() end)
    t.eq(ok, nil)
    t.eq(why, "no world map")
    local named = ns.make.client({ C_Map = { GetMapInfo = function(map)
        return map == 1411 and { name = "Test Vale" } or nil
    end } })
    t.eq(named.mapName(1411), "Test Vale")
    t.eq(named.mapName(1412), nil)
    t.eq(named.mapName("x"), nil)
end

return T
