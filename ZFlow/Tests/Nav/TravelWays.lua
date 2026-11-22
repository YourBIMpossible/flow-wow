-- Tests for S45 (lead sections 173/174; WoW/from-zen/RESEARCH-S45.md): the
-- crossing and flight ways in Nav/Travel.lua. Travel asks two optional
-- providers, k.use("crossings").Way(target) and k.use("flights").Way(target),
-- each giving a step at the boarding place or the flight master. Neither
-- provider exists yet (crossings: Twin, S32; flights: MyBuddy), so they are
-- stand-ins here; absent, nothing changes. Made-up places. Not tested in
-- game. Look only: nothing boards, flies or walks for the player.
local _, ns = ...

local N, A = ns.Nav, ns.Arrow
local T = N.Travel
local tests = {}

local function step()
    return { label = "Kill wolves", place = { map = 1420, x = 0.4, y = 0.6 } }
end
local function crossing()
    return { kind = "crossing", label = "Zeppelin to Undercity", place = { cont = 1, map = 1411, x = 0.5, y = 0.1 },
             radius = 10, detail = "2 steps wait in the Eastern Kingdoms" }
end
local function flight()
    return { kind = "flight", label = "Fly to Crossroads", place = { cont = 1, map = 1411, x = 0.6, y = 0.5 }, radius = 10 }
end

-- ---------------------------------------------------------------- pure

tests["travel ways: a crossing is the step at its boarding place, the step said next"] = function(t)
    local s = step()
    local out, how = N.TravelVia(s, { crossing = crossing() }, false)
    t.eq(how, "crossing")
    t.eq(out, { kind = "crossing", label = "Zeppelin to Undercity", place = { cont = 1, map = 1411, x = 0.5, y = 0.1 },
                radius = 10, detail = "Then: Kill wolves", via = "crossing" })
    t.eq(s, step(), "the step handed in is not changed")
end

tests["travel ways: a flight is the step at the flight master"] = function(t)
    local out, how = N.TravelVia(step(), { flight = flight() }, false)
    t.eq(how, "flight")
    t.eq(out.label, "Fly to Crossroads")
    t.eq(out.detail, "Then: Kill wolves")
    t.eq(out.via, "flight")
end

tests["travel ways: the order is spell, hearthstone, ride, crossing, flight, gate"] = function(t)
    local spell = { label = "Cast Teleport: Moonglade", text = true, spell = "Teleport: Moonglade" }
    local hearth = { label = "Hearth to Razor Hill", text = true, saves = 900 }
    local ride = { label = "Talk to Bunthen Plainswind", text = true, ride = "Bunthen Plainswind" }
    local gate = { kind = "gate", label = "Way to Orgrimmar", place = { cont = 1, map = 1411, x = 0.5, y = 0.1 }, radius = 10 }
    local all = { spell = spell, hearth = hearth, ride = ride, crossing = crossing(), flight = flight(), gate = gate }
    t.eq(select(2, N.TravelVia(step(), all, false)), "spell")
    all.spell = nil
    t.eq(select(2, N.TravelVia(step(), all, false)), "hearth")
    all.hearth = nil
    t.eq(select(2, N.TravelVia(step(), all, false)), "ride")
    all.ride = nil
    t.eq(select(2, N.TravelVia(step(), all, false)), "crossing")
    all.crossing = nil
    t.eq(select(2, N.TravelVia(step(), all, false)), "flight")
    all.flight = nil
    t.eq(select(2, N.TravelVia(step(), all, false)), "gate")
end

tests["travel ways: walk skips a flight, never a crossing"] = function(t)
    t.eq(select(2, N.TravelVia(step(), { flight = flight() }, true)), nil, "walking: no flight")
    t.eq(select(2, N.TravelVia(step(), { crossing = crossing(), flight = flight() }, true)), "crossing",
        "there is no walking over the sea")
end

tests["travel ways: a way with no place, or no label, is not used"] = function(t)
    local s = step()
    local noPlace = crossing()
    noPlace.place = nil
    t.ok(N.TravelVia(s, { crossing = noPlace }) == s)
    local badPlace = flight()
    badPlace.place = { map = 1411, x = "x", y = 0.5 }
    t.ok(N.TravelVia(s, { flight = badPlace }) == s)
    local noLabel = flight()
    noLabel.label = nil
    t.ok(N.TravelVia(s, { flight = noLabel }) == s)
    t.ok(N.TravelVia(s, { crossing = "yes" }) == s)
end

-- ---------------------------------------------------------------- module

-- A warrior (no travel spell) in the middle of 1411, 1000 by 500 yards.
-- opts.crossings / opts.flights: the stand-in Way, or "raise"; arrow: the
-- arrows run too, with the map pin on 1420.
local function start(opts)
    opts = opts or {}
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true } })
    c.setScreen(1024, 768)
    c.setZone(1, 1411)
    c.setFacing(0)
    c.setPosition(1411, 0.5, 0.5)
    c.setMapSize(1411, 1000, 500)
    c.setClass("WARRIOR")
    c.setFaction("Horde")
    if opts.arrow then c.setWaypoint(1420, 0.4, 0.6) end
    local asked = {}
    local k = ns.Kernel({}, c)
    local d = ns.Diag.Start(k)
    for _, name in ipairs({ "crossings", "flights" }) do
        local way = opts[name]
        if way ~= nil then
            k:Module({ name = name, provides = { Way = function(target)
                asked[#asked + 1] = { name = name, target = target }
                if way == "raise" then error("broken") end
                return way
            end } })
        end
    end
    if opts.arrow then A.Start(k, d) end
    local api = T.Declare(k, d)
    k:Boot()
    c.fire("ADDON_LOADED", ns.id.addon)
    c.fire("PLAYER_LOGIN")
    c.fire("PLAYER_ENTERING_WORLD")
    return k, c, api, asked
end

tests["travel ways module: no provider, the step as it is"] = function(t)
    local _, _, api = start()
    local s = step()
    t.ok(api.via(s) == s)
end

tests["travel ways module: the providers are asked with the step's place, a copy"] = function(t)
    local _, _, api, asked = start({ crossings = crossing(), flights = flight() })
    local s = step()
    local out = api.via(s)
    t.eq(out.via, "crossing")
    t.eq(#asked, 2)
    t.eq(asked[1].target, { map = 1420, x = 0.4, y = 0.6 })
    t.ok(asked[1].target ~= s.place, "a copy")
end

tests["travel ways module: a provider that raises is no way, and no problem"] = function(t)
    local k, _, api = start({ crossings = "raise", flights = flight() })
    t.eq(api.via(step()).via, "flight")
    t.eq(k.problems:count(), 0)
end

tests["travel ways module: walk skips a flight, and says there is nothing to skip at a crossing"] = function(t)
    local _, c, api = start({ flights = flight() })
    local s = step()
    t.eq(api.via(s).via, "flight")
    c.slashes[ns.id.slash](T.WORD)
    t.ok(c.printed[#c.printed]:find("you walk to this step", 1, true) ~= nil, c.printed[#c.printed])
    t.ok(api.via(s) == s, "walking")
    local _, c2, api2 = start({ crossings = crossing() })
    t.eq(api2.via(step()).via, "crossing")
    c2.slashes[ns.id.slash](T.WORD)
    t.ok(c2.printed[#c2.printed]:find("no shortcut", 1, true) ~= nil, c2.printed[#c2.printed])
    t.eq(api2.via(step()).via, "crossing", "still the crossing")
end

tests["travel ways on the arrow: the boarding place, the step next, and how far"] = function(t)
    local k, c = start({ arrow = true, crossings = crossing() })
    t.eq(c.arrows[1].lines, { "Zeppelin to Undercity", "Then: Waypoint", "200 yd N" })
    t.eq(k.problems:count(), 0)
end

tests["travel ways: look only - nothing boards or flies for you"] = function(t)
    for name in pairs(T) do
        local n = tostring(name):lower()
        t.ok(not (n:find("board") or n:find("take") or n:find("click") or n:find("cast")), "no acting function: " .. n)
    end
end

return tests
