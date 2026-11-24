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
T.REREAD = 1             -- seconds between looks at the quest log

T.WHY_NO_MAP = "Your map is not known yet; try again in a moment."
T.WHY_NO_LOG = "Your quest log could not be read."
T.WHY_NONE = "No quest step on this map has a known place: no route."
T.WHY_OFF = "Routes are switched off in the settings."
T.NOT_HERE = "not on this map"
T.NO_DISTANCE = "distance not known"
T.DONE = "Route done."
T.CLEARED = "Route cleared."
T.HEADER = "Route: %d stops (%s)"
T.RUN_SAID = "Run planned: %d stops; the arrow walks it."
T.HELD_LINE = "Turn-in held: %s"
T.HELD_NOT_COMPLETE = "not complete any more"
T.LEFT = "%s left the route: its quest is no longer in your log."
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
        local pt = pointOf(spotOf(places, row.id, i), here)
        if pt then
            stops[#stops + 1] = { quest = row.id, objective = i, turnIn = i == nil, label = row.title,
                                  detail = detail, need = need, place = { map = pt.map, x = pt.x, y = pt.y } }
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

function T.Plan(rows, places, here, legs)
    here = type(here) == "table" and here or {}
    if here.map == nil then return nil, T.WHY_NO_MAP end
    local stops, left = T.Stops(rows, places, here)
    if #stops == 0 then return nil, T.WHY_NONE end
    local w, h, yards = scale(here)
    -- No more than the planner takes: the nearest ones.
    if #stops > N.ROUTE_MAX and finite(here.x) and finite(here.y) then
        local function far(s)
            local dx, dy = (s.place.x - here.x) * w, (s.place.y - here.y) * h
            return dx * dx + dy * dy
        end
        table.sort(stops, function(a, b) return far(a) < far(b) end)
        for i = #stops, N.ROUTE_MAX + 1, -1 do stops[i] = nil end
    end
    local list = {}
    for i, s in ipairs(stops) do list[i] = s.place end
    local route, why = N.RoutePlan(list, here.map, { w = w, h = h }, here, yards and legs or nil)
    if not route then return nil, tostring(why) end
    local ordered = {}
    for i, rs in ipairs(route.stops) do
        local s = stops[rs.index]
        s.leg = yards and rs.leg or nil
        ordered[i] = s
    end
    return { kind = "quests", stops = ordered, yards = yards, label = route.label, left = left }
end

function T.Live(stop, rows)
    if type(stop) ~= "table" then return false end
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
        if s.gone then parts[#parts + 1] = "done" end
        -- A stop whose quest left the log is off the list (lead section 375).
        if not s.left and not (s.held and not s.gone) then
            lines[#lines + 1] = (i == at and "> " or "") .. i .. ". " .. table.concat(parts, " - ")
        end
    end
    for _, line in ipairs(held) do lines[#lines + 1] = line end
    for _, l in ipairs(type(route.left) == "table" and route.left or {}) do
        local what = type(l) == "table" and (tostring(l.label) .. (l.detail and (" - " .. tostring(l.detail)) or "")
            .. " - " .. tostring(l.why or T.NOT_HERE)) or tostring(l)
        lines[#lines + 1] = "  " .. what
    end
    return lines
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
        local legs
        local L = k.use and k.use("legs")
        if L and type(L.Planner) == "function" then
            local ok, fn = pcall(L.Planner, here.map)
            if ok and type(fn) == "function" then legs = fn end
        end
        local r, why = T.Plan(rows, places or {}, here, legs)
        if not r then return nil, why end
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
            left[#left + 1] = { label = tostring(name), why = "giver's place not known" }
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
                stops[#stops + 1] = { label = s.label, detail = s.detail, quest = s.quest,
                                      place = { map = s.place.map, x = s.place.x, y = s.place.y } }
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
            local r, why = api.Plan()
            if not r then
                say({ why })
                return
            end
        end
        say(api.Lines() or { T.DONE })
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[T.WORD] = function(rest) api.Word(rest) end
        if type(diag.help) == "table" then diag.help[T.WORD] = T.HELP end
    end

    k:Setting({ key = T.SETTING, scope = "account", type = "bool", default = true,
        label = "Walk a planned route with the arrow", group = "travel.route",
        help = "Shows when you plan a route with the route word or Plan the run: the quest arrow walks its stops in order.",
        synonyms = { "route", "quest", "dungeon", "run", "order", "plan" } })

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
