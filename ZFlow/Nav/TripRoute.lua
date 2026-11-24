local _, ns = ...
-- Z-Flow trip routes (lead dispatch P-TRIP: S39/S43 quest routes, S40
-- dungeon runs). A route is an ordered list of stops the quest arrow walks
-- one at a time; the slash word lists it with distances and lets the
-- player skip a stop. WAYPOINTS ONLY: nothing here accepts, hands in,
-- targets, casts, moves the player or sends chat.
--
-- Quest route (`<slash> route`): the player's quest log (N.QuestLogRows),
-- placed by Questie at runtime (N.QuestiePlaces) and, where Questie gives
-- no place on this map, by the spots the player learned (Nav/QuestSpots.lua).
-- One stop per open objective and per complete quest's turn-in that has a
-- point on the player's map (its point nearest the player). ORDER: nearest
-- next from where the player stands, then shortened by N.RoutePlan (one run
-- turned around or one stop moved while that makes the whole shorter); the
-- player's own trip times (Nav/Legs.lua) where known, else straight lines.
-- A stop drops out by itself once its objective is done or its quest has
-- left the log.
-- Dungeon run (the Dungeon Quests window's Plan the run): the steps of
-- ns.DungeonRead R.Run, walked as given; a stop is passed when the player
-- reaches it.
--
-- Pure:
--   T.Stops(rows, places, here) -> stops, left
--   T.Plan(rows, places, here, legs) -> route or nil, why
--   T.Live(stop, rows) -> bool
--   T.Held(stop, rows) -> why or nil   (lead section 372) a turn-in stop
--     already on the route, checked again each re-read: held while its
--     quest is no longer complete (and, where Nav/QuestSource.lua has it,
--     while Q.TurnInHold holds it). A held stop is not walked; the route
--     lists it as a held line with its reason, and it is walked again once
--     it is ready.
--   T.Lines(route, at) -> lines
-- B-31 (lead section 470): here.casts = { [map] = true }, maps a travel
--   spell the player knows reaches. A step with no point on this map whose
--   other-map point (Questie's spot.away) is on such a map becomes a stop
--   (stop.cast = true) in place of a "not on this map" line; T.Plan puts
--   it in before the first leg longer than N.TRAVEL_SPELL_YARDS, as
--   N.Trip.Order does. The arrow says to cast; nothing casts.
-- Pick-ups (lead section 375 item 7, TN-1): with the pick-up setting on,
-- quests the player can take now whose giver stands on this map
-- (Nav/RoutePickups.lua, read once per plan, the nearest few) join the
-- quest route as optional stops "Pick up: <quest> (<giver>)", kept only
-- when on the way (N.RoutePlan's optional rule, TN-2), else listed as
-- skipped. A pick-up stop drops out once its quest is in the log. Why
-- there are none (no Questie) is one line under the route.
--   T.Plan(rows, places, here, legs, pickups, note)
--   T.Need(text, done) -> line or nil   (S43, lead section 391 item 4) how
--     many of the thing an objective still needs, read from the quest log's
--     own objective text ("Gnoll Paw: 4/8" -> "You still need 4 of Gnoll
--     Paw."). Nil when the objective is done or its count cannot be read:
--     never a made-up number. An objective stop carries it as stop.need,
--     read again with the log; the step and the list say it in place of the
--     raw count.
-- Module "tripRoute" provides Step, Plan, Run, Skip, Off, Lines, View.
-- Not tested in game.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local T = {}
N.TripRoute = T

T.NAME = "tripRoute"
T.WORD = "route"
T.HELP = "plan your quests on this map in order and walk them with the arrow; route skip, route new, route off"
T.SETTING = "quest.route"
T.ARRIVE_YARDS = 10      -- a run stop is reached this close
T.ARRIVE_SHARE = 0.01    -- the same when the map's size is not known
T.AREA_MAX = 8           -- N43: points of a stop's spot kept as its area
T.REREAD = 1             -- seconds between looks at the quest log

T.WHY_NO_MAP = "Your map is not known yet; try again in a moment."
T.WHY_NO_LOG = "Your quest log could not be read."
T.WHY_NONE = "No quest step on this map has a known place: no route."
T.WHY_OFF = "Routes are switched off in the settings."
-- A1-27 (lead sections 507 and 541): the route reads the zone filter
-- (Nav/ZoneFilter.lua). A stop's zone is the map it is on.
T.WHY_ZONES = "No quest step is in the zones you selected: no route. Their quests stay in your log."
T.ZONE_LEFT = "not in a zone you selected"
-- Not under "quest.route": that path is a setting itself, and a path may
-- not sit under another setting's.
T.PICKUP_SETTING = "quest.routePickups"
T.NOT_HERE = "not on this map"
T.NO_DISTANCE = "distance not known"
T.DONE = "Route done."
T.CLEARED = "Route cleared."
T.HEADER = "Route: %d stops (%s)"
T.RUN_SAID = "Run planned: %d stops; the arrow walks it."
T.HELD_LINE = "Turn-in held: %s"
T.HELD_NOT_COMPLETE = "not complete any more"
T.LEFT = "%s left the route: its quest is no longer in your log."
T.UNDER_MINUTE = "under a minute"    -- S34: a leg's time on its step
T.ONE_MINUTE = "about 1 minute"
T.MINUTES = "about %d minutes"
T.UNDER_SECS = 45                     -- seconds: shorter legs are "under a minute"
T.NEED_ONE = "You still need 1 %s."
T.NEED_MANY = "You still need %d of %s."

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

local function scale(here)
    if type(here.size) == "table" and finite(here.size.w) and finite(here.size.h)
        and here.size.w > 0 and here.size.h > 0 then
        return here.size.w, here.size.h, true
    end
    return 1, 1, false
end

-- The point of a spot on here.map nearest the player (the first when the
-- player's x, y are not known), or nil.
local function pointOf(spot, here)
    if type(spot) ~= "table" or type(spot.points) ~= "table" then return nil end
    local w, h = scale(here)
    local canMeasure = finite(here.x) and finite(here.y)
    local best, bestD
    for _, pt in ipairs(spot.points) do
        if type(pt) == "table" and pt.map == here.map and finite(pt.x) and finite(pt.y) then
            if not canMeasure then return pt end
            local dx, dy = (pt.x - here.x) * w, (pt.y - here.y) * h
            local d = dx * dx + dy * dy
            if best == nil or d < bestD then best, bestD = pt, d end
        end
    end
    return best
end

-- B-31: a copy of the spot's other-map point when a known travel spell
-- (here.casts) reaches its map, or nil. Lead section 474: any of the
-- spot's other maps (spot.aways), the lowest such map when several are;
-- spot.away alone when aways is not there.
local function castPoint(spot, here)
    if type(spot) ~= "table" or type(here.casts) ~= "table" then return nil end
    local best
    local function try(a)
        if type(a) ~= "table" or a.map == here.map or here.casts[a.map] ~= true then return end
        if not (finite(a.x) and finite(a.y)) then return end
        if best == nil or (type(a.map) == "number" and type(best.map) == "number" and a.map < best.map) then best = a end
    end
    try(spot.away)
    for _, a in pairs(type(spot.aways) == "table" and spot.aways or {}) do try(a) end
    if not best then return nil end
    return { map = best.map, x = best.x, y = best.y }
end

-- N43: the spot's points on here.map as the stop's area, pt (its nearest)
-- first, no more than T.AREA_MAX; copies.
local function areaOf(spot, here, pt)
    local out = { { map = pt.map, x = pt.x, y = pt.y } }
    for _, p in ipairs(spot.points) do
        if #out >= T.AREA_MAX then break end
        if type(p) == "table" and p ~= pt and p.map == here.map and finite(p.x) and finite(p.y) then
            out[#out + 1] = { map = p.map, x = p.x, y = p.y }
        end
    end
    return out
end

local function spotOf(places, id, i)
    local p = type(places) == "table" and places[id] or nil
    if type(p) ~= "table" then return nil end
    if i == nil then return p.turnIn end
    return type(p.objectives) == "table" and p.objectives[i] or nil
end

function T.Need(text, done)
    if done == true or type(text) ~= "string" then return nil end
    local name, have, want = text:match("^%s*(.-)%s*:%s*(%d+)%s*/%s*(%d+)%s*$")
    if not name then
        have, want, name = text:match("^%s*(%d+)%s*/%s*(%d+)%s+(.-)%s*$")
    end
    have, want = tonumber(have), tonumber(want)
    if not (name and name ~= "" and have and want) then return nil end
    local still = want - have
    if still <= 0 then return nil end
    if still == 1 then return T.NEED_ONE:format(name) end
    return T.NEED_MANY:format(still, name)
end

-- The need line of a stop's objective in these rows, or nil.
local function needOf(stop, rows)
    if type(stop) ~= "table" or stop.turnIn or stop.objective == nil or stop.kind ~= nil then return nil end
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
        if type(row) == "table" and row.id == stop.quest then
            local o = type(row.objectives) == "table" and row.objectives[stop.objective] or nil
            return type(o) == "table" and T.Need(o.text, o.done) or nil
        end
    end
    return nil
end

function T.Stops(rows, places, here)
    local Q = N.QuestSource
    local stops, left = {}, {}
    here = type(here) == "table" and here or {}
    local function add(row, i, detail, need)
        local spot = spotOf(places, row.id, i)
        local pt = pointOf(spot, here)
        local away = castPoint(spot, here)
        if pt then
            stops[#stops + 1] = { quest = row.id, objective = i, turnIn = i == nil, label = row.title,
                                  detail = detail, need = need, place = { map = pt.map, x = pt.x, y = pt.y },
                                  area = areaOf(spot, here, pt) }
        elseif away then
            stops[#stops + 1] = { quest = row.id, objective = i, turnIn = i == nil, label = row.title,
                                  detail = detail, need = need, cast = true, place = away,
                                  area = { { map = away.map, x = away.x, y = away.y } } }
        else
            left[#left + 1] = { quest = row.id, label = row.title, detail = detail, why = T.NOT_HERE }
        end
    end
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
        if type(row) == "table" and row.id ~= nil and type(row.title) == "string" and row.failed ~= true then
            local why = row.complete == true and Q.TurnInHold(row, places) or nil
            if why then
                -- F-028: a turn-in that may not be ready is a line, not a stop.
                local line = Q.HeldLine(why)
                left[#left + 1] = { quest = row.id, label = row.title, detail = line, why = line }
            elseif row.complete == true then
                local spot = spotOf(places, row.id, nil)
                add(row, nil, Q.TurnInLine(type(spot) == "table" and spot.name or nil))
            else
                for i, o in ipairs(type(row.objectives) == "table" and row.objectives or {}) do
                    if type(o) == "table" and o.done ~= true then
                        add(row, i, type(o.text) == "string" and o.text or nil, T.Need(o.text, o.done))
                    end
                end
            end
        end
    end
    return stops, left
end

-- S34 (lead dispatch section 395 item 2): a leg's seconds. A leg is in
-- yards at a run (N.Legs.RUN yards a second): the straight line, or the
-- player's own timed trip (flight or boat wait included) turned into such
-- yards by N.Legs.YardsOf, so ordering by yards is ordering by seconds.
function T.Seconds(yards)
    if not finite(yards) or yards < 0 then return nil end
    local L = N.Legs
    local speed = type(L) == "table" and finite(L.RUN) and L.RUN > 0 and L.RUN or 7
    return yards / speed
end

-- The words for a leg's seconds, or nil when they are not known.
function T.TimeWords(secs)
    if not finite(secs) or secs < 0 then return nil end
    if secs < T.UNDER_SECS then return T.UNDER_MINUTE end
    local m = math.max(1, math.floor(secs / 60 + 0.5))
    if m == 1 then return T.ONE_MINUTE end
    return T.MINUTES:format(m)
end

function T.Plan(rows, places, here, legs, pickups, note)
    here = type(here) == "table" and here or {}
    if here.map == nil then return nil, T.WHY_NO_MAP end
    local stops, left = T.Stops(rows, places, here)
    pickups = type(pickups) == "table" and pickups or {}
    if #stops == 0 and #pickups == 0 then return nil, T.WHY_NONE end
    local w, h, yards = scale(here)
    -- No more than the planner takes: the nearest ones, room kept for the pick-ups.
    local room = N.ROUTE_MAX - #pickups
    if #stops > room and finite(here.x) and finite(here.y) then
        local castYards = N.TRAVEL_SPELL_YARDS or 120
        local function far(s)
            if s.cast then return castYards * castYards end
            local dx, dy = (s.place.x - here.x) * w, (s.place.y - here.y) * h
            return dx * dx + dy * dy
        end
        table.sort(stops, function(a, b) return far(a) < far(b) end)
        for i = #stops, room + 1, -1 do stops[i] = nil end
    end
    local optional = {}
    for _, p in ipairs(pickups) do
        if type(p) == "table" and type(p.place) == "table" and #stops < N.ROUTE_MAX then
            stops[#stops + 1] = { kind = "pickup", quest = p.quest, label = tostring(p.label),
                                  place = { map = p.place.map, x = p.place.x, y = p.place.y } }
            optional[#stops] = true
        end
    end
    -- B-31: the cast stops are not planned on this map; they go in before
    -- the first leg longer than the cast (a leg not known is never short).
    local list, same, opt, cast = {}, {}, {}, {}
    for i, s in ipairs(stops) do
        if s.cast then
            cast[#cast + 1] = s
        else
            list[#list + 1] = s.place
            same[#list] = i
            if optional[i] then opt[#list] = true end
        end
    end
    local route, why
    if #list > 0 then
        route, why = N.RoutePlan(list, here.map, { w = w, h = h }, here, yards and legs or nil, nil, opt)
        if not route then return nil, tostring(why) end
    else
        route = { stops = {}, left = {}, label = N.ROUTE_STRAIGHT }
    end
    local ordered = {}
    local castYards = N.TRAVEL_SPELL_YARDS or 120
    local castIn = #cast == 0
    for _, rs in ipairs(route.stops) do
        local s = stops[same[rs.index]]
        s.leg = yards and rs.leg or nil
        s.secs = s.leg and T.Seconds(s.leg) or nil
        if not castIn and not (finite(s.leg) and s.leg <= castYards) then
            for _, c in ipairs(cast) do ordered[#ordered + 1] = c end
            castIn = true
        end
        ordered[#ordered + 1] = s
    end
    if not castIn then
        for _, c in ipairs(cast) do ordered[#ordered + 1] = c end
    end
    for _, l in ipairs(type(route.left) == "table" and route.left or {}) do
        local s = type(l) == "table" and stops[same[l.index]] or nil
        if s and s.kind == "pickup" then
            left[#left + 1] = { quest = s.quest, label = s.label, why = N.RoutePickups.SKIPPED }
        end
    end
    if #ordered == 0 then return nil, T.WHY_NONE end
    return { kind = "quests", stops = ordered, yards = yards, label = route.label, left = left, note = note }
end

function T.Live(stop, rows)
    if type(stop) ~= "table" then return false end
    if stop.kind == "pickup" then
        -- TN-1: a pick-up is done once its quest is in the log.
        for _, row in ipairs(type(rows) == "table" and rows or {}) do
            if type(row) == "table" and row.id == stop.quest then return false end
        end
        return true
    end
    if stop.quest == nil or stop.kind ~= nil then return true end
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
        if type(row) == "table" and row.id == stop.quest then
            if row.failed == true then return false end
            if stop.turnIn then return true end
            if row.complete == true then return false end
            local o = type(row.objectives) == "table" and row.objectives[stop.objective] or nil
            return type(o) == "table" and o.done ~= true
        end
    end
    return false
end

function T.Held(stop, rows)
    if type(stop) ~= "table" or stop.turnIn ~= true or stop.quest == nil or stop.kind ~= nil then return nil end
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
        if type(row) == "table" and row.id == stop.quest then
            if row.complete ~= true then return T.HELD_NOT_COMPLETE end
            local Q = N.QuestSource
            if type(Q) == "table" and type(Q.TurnInHold) == "function" then
                local ok, why = pcall(Q.TurnInHold, row, nil)
                if ok and type(why) == "string" then return why end
            end
            return nil
        end
    end
    return nil
end

-- Lead section 375: whether the stop's quest is still in the log (rows
-- read); a stop with no quest is.
function T.InLog(stop, rows)
    if type(stop) ~= "table" or stop.quest == nil or type(rows) ~= "table" then return true end
    for _, row in ipairs(rows) do
        if type(row) == "table" and row.id == stop.quest then return true end
    end
    return false
end

function T.Lines(route, at)
    if type(route) ~= "table" or type(route.stops) ~= "table" then return {} end
    local shown = 0
    for _, s in ipairs(route.stops) do
        if not s.left then shown = shown + 1 end
    end
    local lines = { T.HEADER:format(shown, tostring(route.label or N.ROUTE_STRAIGHT)) }
    local held = {}
    for i, s in ipairs(route.stops) do
        if s.held and not s.gone and not s.left then
            held[#held + 1] = "  " .. tostring(s.label) .. " - " .. T.HELD_LINE:format(tostring(s.held))
        end
        local dist = (finite(s.leg) and route.yards ~= false) and (tostring(math.floor(s.leg + 0.5)) .. " yd")
            or T.NO_DISTANCE
        local parts = { tostring(s.label) }
        if s.need ~= nil then
            parts[#parts + 1] = tostring(s.need)
        elseif s.detail ~= nil then
            parts[#parts + 1] = tostring(s.detail)
        end
        parts[#parts + 1] = dist
        local secs = route.yards ~= false and (finite(s.secs) and s.secs or (finite(s.leg) and T.Seconds(s.leg))) or nil
        local time = secs and T.TimeWords(secs)
        if time then parts[#parts + 1] = time end
        if s.gone then parts[#parts + 1] = "done" end
        -- A stop whose quest left the log is off the list (lead section 375).
        if not s.left and not (s.held and not s.gone) then
            lines[#lines + 1] = (i == at and "> " or "") .. i .. ". " .. table.concat(parts, " - ")
        end
    end
    for _, line in ipairs(held) do lines[#lines + 1] = line end
    if route.note ~= nil then lines[#lines + 1] = "  " .. tostring(route.note) end
    for _, l in ipairs(type(route.left) == "table" and route.left or {}) do
        local what = type(l) == "table" and (tostring(l.label) .. (l.detail and (" - " .. tostring(l.detail)) or "")
            .. " - " .. tostring(l.why or T.NOT_HERE)) or tostring(l)
        lines[#lines + 1] = "  " .. what
    end
    return lines
end

-- A1-27: the planned stops through the zone filter. order(stops, zoneOf)
-- is the zoneFilter module's Order: it answers the stops to keep, your
-- zones' first. Answers the stops to walk, a row for each one left out
-- ({ quest, label, detail, why }) and whether anything changed. With no
-- zone filter, or one that raises, the stops are as planned.
function T.Zoned(stops, order)
    if type(stops) ~= "table" or type(order) ~= "function" then return stops, {}, false end
    local function zoneOf(s)
        if type(s) ~= "table" or type(s.place) ~= "table" then return nil end
        return s.place.map
    end
    local ok, ordered = pcall(order, stops, zoneOf)
    if not ok or type(ordered) ~= "table" then return stops, {}, false end
    local kept, out = {}, {}
    for _, s in ipairs(ordered) do kept[s] = true end
    for _, s in ipairs(stops) do
        if not kept[s] then
            out[#out + 1] = { quest = s.quest, label = s.label, detail = s.detail, why = T.ZONE_LEFT }
        end
    end
    local changed = #ordered ~= #stops
    for i, s in ipairs(ordered) do
        if stops[i] ~= s then changed = true end
    end
    return ordered, out, changed
end

-- Straight yards between run stops on one map with a known size; the first
-- from where the player stands.
local function runLegs(stops, client)
    local at = ask(client, "position")
    local last = type(at) == "table" and { map = at.map, x = at.x, y = at.y } or nil
    local yards = true
    for _, s in ipairs(stops) do
        local p = s.place
        local size = type(p) == "table" and ask(client, "mapSize", p.map) or nil
        if type(last) == "table" and type(p) == "table" and last.map == p.map and type(size) == "table"
            and finite(size.w) and finite(size.h) and finite(last.x) and finite(last.y) then
            local dx, dy = (p.x - last.x) * size.w, (p.y - last.y) * size.h
            s.leg = math.sqrt(dx * dx + dy * dy)
        else
            yards = false
        end
        last = p
    end
    return yards
end

function T.Declare(k, diag)
    local api = {}
    local ctx
    local route, at, readAt = nil, 1, nil

    local function client() return ctx and ctx.client or k.client end

    local function on()
        local s = ctx and ctx.settings
        if type(s) ~= "table" or type(s.get) ~= "function" then return true end
        local ok, v = pcall(s.get, s, T.SETTING)
        return not (ok and v == false)
    end

    local function pickupsOn()
        local s = ctx and ctx.settings
        if type(s) ~= "table" or type(s.get) ~= "function" then return true end
        local ok, v = pcall(s.get, s, T.PICKUP_SETTING)
        return not (ok and v == false)
    end

    local function hereNow()
        local c = client()
        local pos = ask(c, "position")
        local here = {}
        if type(pos) == "table" then here.map, here.x, here.y = pos.map, pos.x, pos.y end
        if here.map ~= nil then
            local size = ask(c, "mapSize", here.map)
            if type(size) == "table" then here.size = { w = size.w, h = size.h } end
        end
        return here
    end

    -- B-31: the maps of the steps' other-map points that a travel spell the
    -- client says is known reaches (a spell still to learn is not counted).
    local function castMaps(c, places)
        local out = {}
        if type(N.TravelSpellStepFrom) ~= "function" then return out end
        local function probe(a)
            if type(a) ~= "table" or a.map == nil or out[a.map] ~= nil then return end
            local ok, step = pcall(N.TravelSpellStepFrom, { map = a.map, x = a.x, y = a.y }, c)
            if ok and type(step) == "table" and not step.learn then out[a.map] = true else out[a.map] = false end
        end
        local function look(spot)
            if type(spot) ~= "table" then return end
            probe(spot.away)
            for _, a in pairs(type(spot.aways) == "table" and spot.aways or {}) do probe(a) end
        end
        for _, e in pairs(type(places) == "table" and places or {}) do
            if type(e) == "table" then
                look(e.turnIn)
                for _, o in pairs(type(e.objectives) == "table" and e.objectives or {}) do look(o) end
            end
        end
        for m, v in pairs(out) do
            if v ~= true then out[m] = nil end
        end
        return out
    end

    function api.Plan()
        if not on() then return nil, T.WHY_OFF end
        local c = client()
        local rows = N.QuestLogRows(c)
        if rows == nil then return nil, T.WHY_NO_LOG end
        local here = hereNow()
        if here.map == nil then return nil, T.WHY_NO_MAP end
        local places = N.QuestiePlaces(c, rows, here.map)
        local QS = N.QuestSpots
        if QS and ctx then
            places = QS.Merge(places, QS.Places(ctx.store:get("account", QS.PATH), rows, here.map))
        end
        here.casts = castMaps(c, places)
        local legs
        local L = k.use and k.use("legs")
        if L and type(L.Planner) == "function" then
            local ok, fn = pcall(L.Planner, here.map)
            if ok and type(fn) == "function" then legs = fn end
        end
        -- TN-1: the pick-ups, read once per plan.
        local pickups, note
        local RP = N.RoutePickups
        if RP and pickupsOn() then
            local log = {}
            for _, row in ipairs(rows) do
                if type(row) == "table" and row.id ~= nil then log[row.id] = true end
            end
            pickups, note = RP.Read(c, here, log)
        end
        local r, why = T.Plan(rows, places or {}, here, legs, pickups, note)
        if not r then return nil, why, note end
        -- A1-27: the zones the player selected come first; a stop in another
        -- zone is left out and named, or comes after them (ZF.SETTING).
        -- Nothing selected: nothing changes.
        local zones = k.use and k.use("zoneFilter")
        if type(zones) == "table" and type(zones.Order) == "function" then
            local ordered, out, changed = T.Zoned(r.stops, zones.Order)
            if changed then
                if #ordered == 0 then return nil, T.WHY_ZONES, note end
                r.stops = ordered
                -- The legs are between other stops now: straight yards anew,
                -- where the map's size is known.
                for _, s in ipairs(r.stops) do s.leg, s.secs = nil, nil end
                runLegs(r.stops, c)
                for _, s in ipairs(r.stops) do
                    if finite(s.leg) then s.secs = T.Seconds(s.leg) end
                end
                r.left = type(r.left) == "table" and r.left or {}
                for _, row in ipairs(out) do r.left[#r.left + 1] = row end
            end
        end
        route, at, readAt = r, 1, ask(c, "now")
        return r
    end

    -- run: what ns.DungeonRead R.Run gives. Answers the sentence to show.
    function api.Run(run)
        if not on() then return T.WHY_OFF end
        if type(run) ~= "table" or type(run.steps) ~= "table" or #run.steps == 0 then return T.WHY_NONE end
        local stops = {}
        for i, s in ipairs(run.steps) do
            stops[i] = { kind = s.kind or "run", quest = s.quest, label = s.label, detail = s.detail,
                         logQuest = s.logQuest == true or nil,
                         place = { map = s.place.map, x = s.place.x, y = s.place.y } }
        end
        local yards = runLegs(stops, client())
        local left = {}
        for _, name in ipairs(type(run.left) == "table" and run.left or {}) do
            if type(name) == "table" then
                -- TN-2: a stop the trip skipped comes with its own why.
                left[#left + 1] = { label = tostring(name.label), detail = name.detail, why = tostring(name.why) }
            else
                left[#left + 1] = { label = tostring(name), why = "giver's place not known" }
            end
        end
        route, at, readAt = { kind = "run", stops = stops, yards = yards,
                              label = tostring(run.title or N.ROUTE_STRAIGHT), left = left }, 1, nil
        return T.RUN_SAID:format(#stops)
    end

    function api.Off()
        route, at = nil, 1
    end

    -- The first stop from at on that is not gone; the route ends past the last.
    local function settle()
        while route and route.stops[at] and route.stops[at].gone do at = at + 1 end
        if route and route.stops[at] == nil then route, at = nil, 1 end
    end

    function api.Skip()
        if not route then return nil end
        at = at + 1
        settle()
        return route and route.stops[at] or nil
    end

    local function reached(s, here)
        local p = s.place
        if type(p) ~= "table" or here.map ~= p.map or not (finite(here.x) and finite(here.y)) then return false end
        local w, h, yards = scale(here)
        local dx, dy = (p.x - here.x) * w, (p.y - here.y) * h
        local d = math.sqrt(dx * dx + dy * dy)
        return d < (yards and T.ARRIVE_YARDS or T.ARRIVE_SHARE)
    end

    local function tell(line)
        local c = client()
        if type(c) ~= "table" or type(c.print) ~= "function" then return end
        local id = k.id or ns.id
        c.print(id.title .. ": " .. tostring(line))
    end

    -- Lead section 375: a stop whose quest left the log (abandoned or handed
    -- in, in any order) leaves the route, one line per quest. On a run only
    -- the trip hand-in stops (logQuest) are checked: pick-up givers are not
    -- in the log yet. Answers whether any left.
    local function dropLeft(rows)
        local told, any = {}, false
        for _, s in ipairs(route.stops) do
            local check = route.kind == "quests" or s.logQuest == true
            if check and not s.gone and not T.InLog(s, rows) then
                s.gone, s.left, any = true, true, true
                if not told[s.quest] then
                    told[s.quest] = true
                    tell(T.LEFT:format(tostring(s.label)))
                end
            end
        end
        return any
    end

    function api.Step()
        if not route or not on() then return nil end
        local c = client()
        local now = ask(c, "now")
        local rows
        if not finite(now) or not finite(readAt) or now - readAt >= T.REREAD then
            readAt = now
            rows = N.QuestLogRows(c)
        end
        if rows and dropLeft(rows) and route.kind == "run" then
            local trip = k.use and k.use("trip")
            if trip and type(trip.Prune) == "function" then pcall(trip.Prune, rows) end
        end
        if route.kind == "quests" then
            if rows then
                for _, s in ipairs(route.stops) do
                    if not T.Live(s, rows) then
                        s.gone = true
                    else
                        s.held = T.Held(s, rows)
                        if not s.turnIn then s.need = needOf(s, rows) end
                    end
                end
            end
        else
            local here = hereNow()
            while route and route.stops[at] and reached(route.stops[at], here) do
                route.stops[at].gone = true
                at = at + 1
                settle()
            end
        end
        settle()
        -- A held stop stays on the route but is not walked (lead section 372).
        local s
        for i = at, route and #route.stops or 0 do
            local o = route.stops[i]
            if not o.gone and not o.held then
                s = o
                break
            end
        end
        if not s then return nil end
        return { quest = s.quest, objective = s.objective, turnIn = s.turnIn, label = s.label,
                 detail = s.need or s.detail, need = s.need,
                 place = { map = s.place.map, x = s.place.x, y = s.place.y } }
    end

    function api.Lines()
        if not route then return nil end
        return T.Lines(route, at)
    end

    -- G48 (Nav/PartyRoute.lua): a copy of the stops still to walk, or nil.
    function api.Current()
        if not route then return nil end
        local stops = {}
        for i = at, #route.stops do
            local s = route.stops[i]
            if not s.gone and not s.held then
                local area
                if type(s.area) == "table" then
                    area = {}
                    for j, p in ipairs(s.area) do area[j] = { map = p.map, x = p.x, y = p.y } end
                end
                stops[#stops + 1] = { label = s.label, detail = s.detail, quest = s.quest,
                                      place = { map = s.place.map, x = s.place.x, y = s.place.y }, area = area }
            end
        end
        if #stops == 0 then return nil end
        return { kind = route.kind, label = route.label, stops = stops }
    end

    -- Look only (UI/RouteList.lua, UI/MapRoute.lua): a copy of every stop from
    -- the current one on, held ones too, and what was left off the route, or
    -- nil with no route. Changes nothing.
    function api.View()
        if not route then return nil end
        local stops, left = {}, {}
        for i = at, #route.stops do
            local s = route.stops[i]
            if not s.gone then
                stops[#stops + 1] = { quest = s.quest, objective = s.objective, turnIn = s.turnIn, kind = s.kind,
                                      label = s.label, detail = s.detail, held = s.held,
                                      place = { map = s.place.map, x = s.place.x, y = s.place.y } }
            end
        end
        for _, l in ipairs(type(route.left) == "table" and route.left or {}) do
            if type(l) == "table" then
                left[#left + 1] = { quest = l.quest, label = l.label, detail = l.detail, why = l.why }
            end
        end
        return { kind = route.kind, label = route.label, note = route.note, stops = stops, left = left }
    end

    local function say(lines)
        for _, line in ipairs(lines) do tell(line) end
    end

    function api.Word(rest)
        local word = tostring(rest or ""):lower():match("^%s*(%S*)")
        if word == "off" or word == "clear" then
            api.Off()
            say({ T.CLEARED })
            return
        end
        if word == "skip" or word == "next" then
            if api.Skip() then say(api.Lines()) else say({ T.DONE }) end
            return
        end
        if word == "new" or not route then
            local r, why, note = api.Plan()
            if not r then
                -- One line with nothing planned (Tests/E2E/TripEdges.lua): why
                -- there are no pick-ups follows on the same line.
                say({ note and (tostring(why) .. " " .. tostring(note)) or why })
                return
            end
        end
        say(api.Lines() or { T.DONE })
        -- S30 (Nav/FlightStep.lua): a flight path to learn that is within
        -- reach is said under the list. Words only.
        if route and ctx then
            local okUse, flightStep = pcall(ctx.use, "flightStep")
            if okUse and type(flightStep) == "table" and type(flightStep.Line) == "function" then
                local okLine, line = pcall(flightStep.Line)
                if okLine and type(line) == "string" then tell(line) end
            end
        end
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[T.WORD] = function(rest) api.Word(rest) end
        if type(diag.help) == "table" then diag.help[T.WORD] = T.HELP end
    end

    k:Setting({ key = T.SETTING, scope = "account", type = "bool", default = true,
        label = "Walk a planned route with the arrow", group = "travel.route",
        help = "Shows when you plan a route with the route word or Plan the run: the quest arrow walks its stops in order.",
        synonyms = { "route", "quest", "dungeon", "run", "order", "plan" } })

    k:Setting({ key = T.PICKUP_SETTING, scope = "account", type = "bool", default = true,
        label = "Add quests to pick up on the way", group = "travel.route",
        help = "Acts when you plan a quest route with the route word: quests you can take now whose giver stands on this map (from Questie) are added as stops when on the way, else listed as skipped. Nothing is accepted for you.",
        synonyms = { "route", "pick", "pickup", "giver", "new", "quest" } })

    k:Module({
        name = T.NAME,
        needs = { "client", "store", "settings" },
        provides = { Step = api.Step, Plan = api.Plan, Run = api.Run, Skip = api.Skip, Off = api.Off,
                     Lines = api.Lines, Current = api.Current, View = api.View },
        start = function(c) ctx = c end,
        stop = function() route, at = nil, 1 end,
    })
    return api
end

ns.tripRoute = T.Declare(ns, ns.diag)
