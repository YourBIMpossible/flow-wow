local _, ns = ...
-- Z-Flow hearthstone advice (G46, lead DISPATCH section 391 item 2): words
-- that say when hearthing saves the walk to the next stop, and when to set
-- a new home inn. Printed in chat; the arrow is not changed. WORDS ONLY:
-- nothing uses the hearthstone, talks to an innkeeper or sets a home.
-- Not tested in game.
--
-- Pure:
--   H.Walk(a, b, size, legs) -> seconds on foot from a to b, or nil.
--     a, b { map, x, y } shares of one map of size { w, h } yards. legs is
--     the planner of Nav/Legs.lua (the player's own trip times, in yards),
--     used when it answers a number; else the straight line. Yards are
--     turned into seconds at H.RUN yards a second (Nav/Legs.lua L.RUN).
--   H.Hearth(o) -> line or nil, reason
--     o = { bind = { name, map, x, y }, cooldown (seconds; not a number:
--           no stone known), here = { map, x, y }, target = { map, x, y },
--           size = { w, h } of the target's map, legs,
--           corners = function(map) -> client.mapCorners(map) or nil }
--     FLOW-PARITY B-35: a walk or a home on another map is measured in
--     world yards (Flow Modules/Hearth.lua:242-277, nav:ToWorld) when both
--     maps' corners are known and on one continent; else as below.
--     The first of these that holds:
--       "no target"   target not placed
--       "far unknown" the player's walk to the target not measurable
--       "near"        the walk is under H.SAVES + H.CAST: no advice
--       "no home"     no bind name: H.NO_HOME
--       "bind place unknown" / "other map": where the home is not known,
--                     or not measurable to the target: nothing claimed
--       "no saving"   walk - (H.CAST + walk from the home) < H.SAVES
--       "no stone"    cooldown not a number
--       "on cooldown" H.READY_IN when the stone is ready before the walk
--                     would be over, else no line
--       "hearth"      H.HEARTH with the whole minutes saved (rounded)
--   H.Inns(services) -> { { name, map, x, y } }, the innkeepers among
--     char "learned.places.services" (Nav/ServiceSeen.lua), by key.
--   H.Home(o) -> line or nil, reason
--     o = { bind, inns, stops = { { map, x, y } }, size = function(map) }
--     "bind place unknown" a bind name with no place; "few" under 2 stops;
--     "spread" no seen inn has more than half the stops within H.NEAR
--     yards; "home already" the best inn is within H.SAME yards of the
--     home; else "set home" and H.SET_HOME.
--   H.SetStep(inn, town) -> step or nil (FLOW-PARITY B-34, section 456)
--     inn: the seen inn H.Home named (an innkeeper the player has spoken
--     to, Nav/ServiceSeen.lua); town: the client's name of its map, or
--     nil. step = { label = "Set hearthstone: <inn> (<town>)", place }.
--     Never from a shipped table. The arrow chain's one call (wired by
--     the lead at merge): ns.use("hearthAdvice").Step().
--
-- Module "hearthAdvice": a look every H.EVERY seconds at the next stop
-- (ns.use("tripRoute").Current(), else ns.use("arrow").Heading()). Each
-- line is said once: the hearth line once until the stone is used (its
-- cooldown seen above 0), the ready-in line once per cooldown, the
-- innkeeper line once until a home is known, the set-home line once per
-- inn it names. Reads: client.position, mapSize, bindLocation,
-- hearthCooldown; the saved home (Nav/HearthSeen.lua) and services.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local H = {}
N.HearthAdvice = H

H.NAME = "hearthAdvice"
H.SAVES = 120      -- seconds the stone must save before it is advised
H.CAST = 10        -- seconds the hearthstone takes to cast
H.RUN = 7          -- yards a second on foot (Nav/Legs.lua L.RUN)
H.NEAR = 300       -- yards from an inn that count as near it
H.SAME = 60        -- yards: the home and a seen inn are one inn
H.EVERY = 2        -- seconds between looks
H.HEARTH = "Hearth to %s: it saves about %d minutes of walking."
H.READY_IN = "Your hearthstone is ready in %d minutes: then hearth to %s to save the walk."
H.NO_HOME = "Talk to an innkeeper to set your home: then your hearthstone can save you long walks."
H.SET_HOME = "Set your home at %s's inn: most of your quests are near it."
H.SET_HOME_PLAIN = "Set your home at the inn near most of your quests."
H.STEP = "Set hearthstone: %s (%s)"
H.STEP_NO_TOWN = "Set hearthstone: %s"
H.STEP_INN = "innkeeper"

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function named(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

local function placed(p)
    return type(p) == "table" and p.map ~= nil and finite(p.x) and finite(p.y)
end

local function sized(s)
    return type(s) == "table" and finite(s.w) and finite(s.h) and s.w > 0 and s.h > 0
end

local function yardsOf(a, b, size)
    local dx, dy = (a.x - b.x) * size.w, (a.y - b.y) * size.h
    return math.sqrt(dx * dx + dy * dy)
end

function H.Walk(a, b, size, legs)
    if not (placed(a) and placed(b)) or a.map ~= b.map or not sized(size) then return nil end
    local d = yardsOf(a, b, size)
    if type(legs) == "function" then
        local ok, y = pcall(legs, { x = a.x * size.w, y = a.y * size.h }, { x = b.x * size.w, y = b.y * size.h }, d)
        if ok and finite(y) and y >= 0 then d = y end
    end
    return d / H.RUN
end

-- Seconds on foot from a to b: on one map as H.Walk; else in world yards
-- through the maps' corners on one continent (Nav/Flights.lua ToWorld).
local function walkOf(a, b, o)
    if not (placed(a) and placed(b)) then return nil end
    if a.map == b.map then return H.Walk(a, b, o.size, o.legs) end
    if type(o.corners) ~= "function" or not (N.Flights and N.Flights.ToWorld) then return nil end
    local okA, ma = pcall(o.corners, a.map)
    local okB, mb = pcall(o.corners, b.map)
    if not (okA and okB) then return nil end
    local ca, ax, ay = N.Flights.ToWorld(ma, a.x, a.y)
    local cb, bx, by = N.Flights.ToWorld(mb, b.x, b.y)
    if ca == nil or ca ~= cb then return nil end
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) / H.RUN
end

function H.Hearth(o)
    if type(o) ~= "table" then o = {} end
    local target, here = o.target, o.here
    if not placed(target) then return nil, "no target" end
    if placed(here) and here.map == target.map and not sized(o.size) then return nil, "far unknown" end
    local walk = walkOf(here, target, o)
    if not walk then return nil, "far unknown" end
    if walk < H.SAVES + H.CAST then return nil, "near" end
    local bind = type(o.bind) == "table" and o.bind or {}
    local name = named(bind.name)
    if not name then return H.NO_HOME, "no home" end
    if not placed(bind) then return nil, "bind place unknown" end
    local fromHome = walkOf(bind, target, o)
    if not fromHome then return nil, "other map" end
    local saves = walk - H.CAST - fromHome
    if saves < H.SAVES then return nil, "no saving" end
    local cooldown = o.cooldown
    if not finite(cooldown) then return nil, "no stone" end
    if cooldown > 0 then
        if cooldown < walk then return H.READY_IN:format(math.ceil(cooldown / 60), name), "on cooldown" end
        return nil, "on cooldown"
    end
    return H.HEARTH:format(name, math.floor(saves / 60 + 0.5)), "hearth"
end

function H.Inns(services)
    local keys = {}
    for key, e in pairs(type(services) == "table" and services or {}) do
        if type(e) == "table" and type(e.kinds) == "table" and e.kinds.innkeeper == true and placed(e) then
            keys[#keys + 1] = tostring(key)
        end
    end
    table.sort(keys)
    local inns = {}
    for i, key in ipairs(keys) do
        local e = services[key]
        inns[i] = { name = named(e.name), map = e.map, x = e.x, y = e.y }
    end
    return inns
end

local function sizeFor(o, map)
    if type(o.size) ~= "function" then return nil end
    local ok, s = pcall(o.size, map)
    if ok and sized(s) then return s end
    return nil
end

function H.Home(o)
    if type(o) ~= "table" then o = {} end
    local bind = type(o.bind) == "table" and o.bind or {}
    if named(bind.name) and not placed(bind) then return nil, "bind place unknown" end
    local stops = type(o.stops) == "table" and o.stops or {}
    if #stops < 2 then return nil, "few" end
    local best, bestN = nil, 0
    for _, inn in ipairs(type(o.inns) == "table" and o.inns or {}) do
        local size = placed(inn) and sizeFor(o, inn.map) or nil
        if size then
            local n = 0
            for _, s in ipairs(stops) do
                if placed(s) and s.map == inn.map and yardsOf(s, inn, size) <= H.NEAR then n = n + 1 end
            end
            if n > bestN then best, bestN = inn, n end
        end
    end
    if not best or bestN * 2 <= #stops then return nil, "spread" end
    if placed(bind) and bind.map == best.map and yardsOf(bind, best, sizeFor(o, best.map)) <= H.SAME then
        return nil, "home already"
    end
    local name = named(best.name)
    if name then return H.SET_HOME:format(name), "set home", best end
    return H.SET_HOME_PLAIN, "set home", best
end

function H.SetStep(inn, town)
    if not placed(inn) then return nil end
    local who = named(inn.name) or H.STEP_INN
    local where = named(town)
    local label = where and H.STEP:format(who, where) or H.STEP_NO_TOWN:format(who)
    return { label = label, place = { map = inn.map, x = inn.x, y = inn.y } }
end

-- One read of the client, or nil when it has no such read or it fails.
local function ask(client, read, ...)
    if type(client) ~= "table" or type(client[read]) ~= "function" then return nil end
    local ok, v = pcall(client[read], ...)
    if not ok then return nil end
    return v
end

local function saved(store, scope, path)
    if type(store) ~= "table" or type(store.get) ~= "function" then return nil end
    local ok, v = pcall(store.get, store, scope, path)
    if not ok then return nil end
    return v
end

function H.Declare(k)
    local api = {}
    local ctx
    local said = {}          -- [reason] = true while that line stays said
    local lastHome = nil     -- the set-home line said last
    local step = nil         -- the set-hearthstone step of the last look

    local function use(name)
        local m = k.use and k.use(name)
        return type(m) == "table" and m or nil
    end

    -- The stops still to walk: the route's, else the arrow's one place.
    local function stopsNow()
        local route = use("tripRoute")
        if route and type(route.Current) == "function" then
            local ok, cur = pcall(route.Current)
            if ok and type(cur) == "table" and type(cur.stops) == "table" and #cur.stops > 0 then
                local list = {}
                for i, s in ipairs(cur.stops) do list[i] = s.place end
                return list
            end
        end
        local arrow = use("arrow")
        if arrow and type(arrow.Heading) == "function" then
            local ok, place = pcall(arrow.Heading)
            if ok and type(place) == "table" then return { place } end
        end
        return {}
    end

    local function say(line)
        local c = ctx and ctx.client
        if type(c) == "table" and type(c.print) == "function" then c.print(ns.id.title .. ": " .. line) end
    end

    function api.look()
        if not ctx then return end
        local client = ctx.client
        local name = named(ask(client, "bindLocation"))
        local bind = { name = name }
        local place = saved(ctx.store, "char", N.HEARTH_BIND or "learned.places.bind")
        if name and type(place) == "table" and place.name == name then
            bind.map, bind.x, bind.y = place.map, place.x, place.y
        end
        local cooldown = ask(client, "hearthCooldown")
        if finite(cooldown) and cooldown > 0 then said.hearth = nil end
        if finite(cooldown) and cooldown <= 0 then said["on cooldown"] = nil end
        if name then said["no home"] = nil end

        local stops = stopsNow()
        local target = stops[1]
        local here = ask(client, "position")
        local size = placed(target) and ask(client, "mapSize", target.map) or nil
        local legs
        local L = use("legs")
        if placed(target) and L and type(L.Planner) == "function" then
            local ok, fn = pcall(L.Planner, target.map)
            if ok and type(fn) == "function" then legs = fn end
        end
        local line, why = H.Hearth({ bind = bind, cooldown = cooldown, here = here, target = target,
                                     size = size, legs = legs,
                                     corners = function(map) return ask(client, "mapCorners", map) end })
        if line and not said[why] then
            said[why] = true
            say(line)
        end

        local services = ns.ServiceSeen and ns.ServiceSeen.PLACES or "learned.places.services"
        local home, _, best = H.Home({ bind = bind, stops = stops, inns = H.Inns(saved(ctx.store, "char", services)),
                              size = function(map) return ask(client, "mapSize", map) end })
        if best then
            step = H.SetStep(best, ask(client, "mapName", best.map))
        else
            step = nil
        end
        if home and home ~= lastHome then
            lastHome = home
            say(home)
        end
    end

    k:Module({
        name = H.NAME,
        needs = { "client", "store" },
        provides = { Look = function() api.look() end, Step = function() return step end },
        ticks = { { every = H.EVERY, when = "always", run = function() api.look() end } },
        start = function(c) ctx = c end,
        stop = function() said, lastHome, step = {}, nil, nil end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.hearthAdvice = H.Declare(ns)
