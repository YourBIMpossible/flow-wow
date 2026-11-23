local _, ns = ...
-- Crossing to another continent: boats, zeppelins and whatever else carries
-- the player over the sea (S32). Ported in behaviour from legacy
-- Modules/Nav/Crossings.lua (0.35.369 to 0.35.377); the code is new.
--
-- RoutePlan orders places on ONE map. Steps on another continent cannot be
-- walked to, so they are left out and nothing says so. This module turns
-- "some of your steps are over the sea" into one step a continent, of a new
-- kind: go to the boarding place of the crossing that makes the whole trip
-- shortest. It is advice only. Nothing here boards, clicks or casts.
--
-- Pure: no client read, no saved data, no clock. The caller hands in the
-- crossings, the places and a way to measure. Nothing is authored here: the
-- legacy file carried five crossings with typed-in map spots, and they are
-- NOT ported, because where those numbers came from cannot be shown. A
-- crossing is either handed in by the caller or learned from the player's own
-- trips (N.CrossingSeen).
--
-- Shapes
--   place     { cont, map, x, y, name?, wx?, wy? }   x, y are shares 0..1 of
--             the map; wx, wy are world yards when a read gives them.
--   crossing  { key, a = place, b = place, how?, faction?, seen?, corrected? }
--             how is "zeppelin" or "boat" or not known; faction nil means
--             anyone; seen is set only on a crossing learned from trips.
--
-- API
--   N.CrossingApart(mapSize) -> apart(a, b) -> whole yards or nil
--   N.CrossingUsable(crossing, faction) -> boolean
--   N.CrossingBest(list, me, targets, apart, faction) -> best or nil, reason
--        best = { key, crossing, how, from, to, toBoard, toStep, yards, toCont }
--        reasons: "position unknown", "no crossings", "no place to aim for",
--        "no crossing joins"
--   N.CrossingWeight(yardsToBoard, hearthReady) -> number
--   N.CrossingWhen(weight) -> one line
--   N.CrossingText(how, toName, n, contName) -> the words of the step
--   N.CrossingLabel(how, toName) -> short label, never cut
--   N.CrossingSteps(input) -> steps, unjoined, reason
--        input = { list, me, faction, apart, hearthReady, contNames, on,
--                  waiting = { [cont] = { steps = {...}, targets = {...} } } }
--        reasons: "off", "position unknown"
--   N.CrossingStepFor(cont, steps) -> step or nil
--   N.CrossingSeen(list, before, after, opts) -> list, key or nil, what
--        opts = { apart, bind, learnNew }
--        what: "corrected", "new", "no change", "hearthstone",
--        "not near a known crossing", "full"
--   N.CrossingLines(list, steps, unjoined, on, faction) -> lines
--
-- A distance that is not known stays not known: it is never taken as short,
-- and the whole of a trip is not claimed when a part of it is missing.
--
-- The module (lead sections 182 and 184), at the end of this file, is the
-- one part that reads: the client (where the player is, the faction, map
-- sizes, the taxi read) and the crossings saved in N.CROSSING_PLACES. Its
-- one write is the player's own trips: every N.Crossings.EVERY seconds
-- api.sample() reads where the player is, and when the continent changes
-- between two places read off a flight it saves what N.CrossingSeen gives
-- (the hearthstone home, char N.Crossings.BIND, is not a crossing).
--   N.Crossings.Declare(k) -> api
--   ns.use("crossings") -> { Way = api.way }
--   api.sample() -> key, what or nil: one trip sample (the tick)
--   api.way(place) -> step or nil: the step Nav/Travel.lua expects for a
--        place on another continent, at the boarding place of the best
--        crossing on the player's own continent (N.CrossingSteps and
--        N.CrossingStepFor), with radius = N.Crossings.NEAR. nil for a place
--        on the player's continent, a place with no continent or no map
--        spot, the player's place or continent not known, or no crossing
--        known that joins the two. The place handed in is not changed.
--
-- Not tested in game. Needs game test: that the continent number changes when
-- a boat or zeppelin lands, and that the place read just before and just
-- after is good enough to tell a boarding place from a landing; that a
-- step's place carries the same continent number the zone read gives.

ns.Nav = ns.Nav or {}
local N = ns.Nav

-- The numbers are the ones legacy used.
N.CROSSING_WEIGHT = 2.5   -- far from it: after what is left to do here
N.CROSSING_W_NEAR = 1.1   -- close to it: by its distance, like any step
N.CROSSING_W_NOW = 0.5    -- close to it and the hearthstone ready: first
N.CROSSING_NEAR = 250     -- yards: a trip this near a known end is that crossing
N.CROSSING_CLOSE = 800    -- yards: this near the boarding place counts as close
N.CROSSING_SURE = 2       -- trips before a learned crossing is offered
N.CROSSING_MAX = 40       -- learned crossings kept
N.CROSSING_PLACES = "learned.places.crossings"
N.CROSSING_SETTING = "nav.crossings"
N.CROSSING_PLAIN = "Crossing to another continent"

local HOW = { zeppelin = "Zeppelin", boat = "Boat" }
local LISTED = 5

local function num(v) return type(v) == "number" and v == v end
local function share(v) return num(v) and v >= 0 and v <= 1 end
local function placed(p) return type(p) == "table" and num(p.map) and share(p.x) and share(p.y) end
local function whole(p) return placed(p) and num(p.cont) end

local function copyPlace(p, name)
    return { cont = p.cont, map = p.map, x = p.x, y = p.y, name = name or p.name, wx = p.wx, wy = p.wy }
end

local function yards(dx, dy)
    return math.floor(math.sqrt(dx * dx + dy * dy) + 0.5)
end

-- A way to measure, built on a map size read. Two places on one map are
-- measured by the size of that map. Two maps of one continent are measured
-- only when both places carry world yards. Anything else is not known.
function N.CrossingApart(mapSize)
    return function(a, b)
        if not placed(a) or not placed(b) then return nil end
        if a.map == b.map then
            if type(mapSize) ~= "function" then return nil end
            local ok, size = pcall(mapSize, a.map)
            if not ok or type(size) ~= "table" then return nil end
            if not num(size.w) or not num(size.h) or size.w <= 0 or size.h <= 0 then return nil end
            return yards((a.x - b.x) * size.w, (a.y - b.y) * size.h)
        end
        if num(a.cont) and a.cont == b.cont and num(a.wx) and num(a.wy) and num(b.wx) and num(b.wy) then
            return yards(a.wx - b.wx, a.wy - b.wy)
        end
        return nil
    end
end

local function joins(cr)
    return type(cr) == "table" and whole(cr.a) and whole(cr.b) and cr.a.cont ~= cr.b.cont
end

function N.CrossingUsable(cr, faction)
    if not joins(cr) then return false end
    if cr.faction ~= nil and cr.faction ~= faction then return false end
    if cr.seen ~= nil and not (num(cr.seen) and cr.seen >= N.CROSSING_SURE) then return false end
    return true
end

-- Known and smaller first; known before not known; nil when it does not decide.
local function first(x, y)
    if x ~= nil and y ~= nil then
        if x ~= y then return x < y end
        return nil
    end
    if x ~= nil then return true end
    if y ~= nil then return false end
    return nil
end

local function better(p, q)
    local r = first(p.yards, q.yards)
    if r ~= nil then return r end
    r = first(p.toStep, q.toStep)
    if r ~= nil then return r end
    r = first(p.toBoard, q.toBoard)
    if r ~= nil then return r end
    return tostring(p.key) < tostring(q.key)
end

local function measure(apart, a, b)
    if type(apart) ~= "function" then return nil end
    local ok, d = pcall(apart, a, b)
    if ok and num(d) and d >= 0 then return d end
    return nil
end

function N.CrossingBest(list, me, targets, apart, faction)
    if not whole(me) then return nil, "position unknown" end
    local usable = {}
    if type(list) == "table" then
        for _, cr in ipairs(list) do
            if N.CrossingUsable(cr, faction) then usable[#usable + 1] = cr end
        end
    end
    if #usable == 0 then return nil, "no crossings" end
    local aims = {}
    if type(targets) == "table" then
        for _, p in ipairs(targets) do
            if whole(p) and p.cont ~= me.cont then aims[#aims + 1] = p end
        end
    end
    if #aims == 0 then return nil, "no place to aim for" end

    local best
    for _, cr in ipairs(usable) do
        for turn = 1, 2 do
            local from, to = cr.a, cr.b
            if turn == 2 then from, to = cr.b, cr.a end
            if from.cont == me.cont then
                local toStep, reaches
                for _, p in ipairs(aims) do
                    if p.cont == to.cont then
                        reaches = true
                        local d = measure(apart, to, p)
                        if d ~= nil and (toStep == nil or d < toStep) then toStep = d end
                    end
                end
                if reaches then
                    local toBoard = measure(apart, me, from)
                    local found = {
                        key = cr.key, crossing = cr, how = cr.how, from = from, to = to,
                        toBoard = toBoard, toStep = toStep, toCont = to.cont,
                        yards = (toBoard ~= nil and toStep ~= nil) and (toBoard + toStep) or nil,
                    }
                    if best == nil or better(found, best) then best = found end
                end
            end
        end
    end
    if best == nil then return nil, "no crossing joins" end
    return best
end

-- Where the step sits among the others. Not known is never taken as close,
-- and a hearthstone not known to be ready is not taken as ready.
function N.CrossingWeight(yardsToBoard, hearthReady)
    if not num(yardsToBoard) or yardsToBoard > N.CROSSING_CLOSE then return N.CROSSING_WEIGHT end
    if hearthReady == true then return N.CROSSING_W_NOW end
    return N.CROSSING_W_NEAR
end

function N.CrossingWhen(weight)
    if weight == N.CROSSING_W_NOW then
        return "You are close to it and your hearthstone is ready to bring you back, so it comes first."
    end
    if weight == N.CROSSING_W_NEAR then
        return "You are close to it, so it is placed by its distance like any other step."
    end
    return "It comes after what is left to do here."
end

local function named(v) return type(v) == "string" and v ~= "" end

local function waits(n)
    n = num(n) and n or 0
    if n == 1 then return "1 step waits" end
    return string.format("%d steps wait", n)
end

function N.CrossingText(how, toName, n, contName)
    local head = HOW[how] or "Crossing"
    if not named(toName) then
        return string.format("%s to another continent (%s there)", head, waits(n))
    end
    local where = named(contName) and ("in " .. contName) or "on another continent"
    return string.format("%s to %s (%s %s)", head, toName, waits(n), where)
end

-- The label an arrow or pin can carry. A name too long for it is not cut:
-- the plain words are used instead.
function N.CrossingLabel(how, toName)
    if not named(toName) then return N.CROSSING_PLAIN end
    local label = (HOW[how] or "Crossing") .. " to " .. toName
    local max = (N.Waypoint and N.Waypoint.LABEL_MAX) or 40
    if #label > max then return N.CROSSING_PLAIN end
    return label
end

local REASON = {
    ["no crossings"] = "no crossing you can use is known yet",
    ["no place to aim for"] = "those steps have no place on the map to aim for",
    ["no crossing joins"] = "no known crossing joins your continent to that one",
}

local function stepWords(s)
    if type(s) == "table" then
        if named(s.label) then return s.label end
        if named(s.text) then return s.text end
    end
    return "a step"
end

-- One step a continent that holds steps of the player. What no crossing
-- reaches comes back as a line saying what is missing, never as silence.
function N.CrossingSteps(input)
    local steps, unjoined = {}, {}
    if type(input) ~= "table" then return steps, unjoined, "position unknown" end
    if input.on == false then return steps, unjoined, "off" end
    local me = input.me
    if not whole(me) then return steps, unjoined, "position unknown" end

    local conts = {}
    if type(input.waiting) == "table" then
        for cont, w in pairs(input.waiting) do
            if num(cont) and cont ~= me.cont and type(w) == "table" and type(w.steps) == "table" and #w.steps > 0 then
                conts[#conts + 1] = cont
            end
        end
    end
    table.sort(conts)

    local names = type(input.contNames) == "table" and input.contNames or {}
    for _, cont in ipairs(conts) do
        local w = input.waiting[cont]
        local n = #w.steps
        local contName = named(names[cont]) and names[cont] or nil
        local where = contName and ("in " .. contName) or "on another continent"
        local best, why = N.CrossingBest(input.list, me, w.targets, input.apart, input.faction)
        if best == nil then
            unjoined[#unjoined + 1] = string.format("%d step%s %s cannot be routed: %s",
                n, n == 1 and "" or "s", where, REASON[why] or REASON["no crossing joins"])
        else
            local weight = N.CrossingWeight(best.toBoard, input.hearthReady)
            local details = {}
            if n == 1 then
                details[1] = string.format("1 step of yours is %s, where the route cannot take you on foot:", where)
            else
                details[1] = string.format("%d steps of yours are %s, where the route cannot take you on foot:", n, where)
            end
            local forQuests = {}
            for i, s in ipairs(w.steps) do
                if i <= LISTED then details[#details + 1] = "- " .. stepWords(s) end
                if type(s) == "table" and num(s.quest) then forQuests[s.quest] = true end
            end
            if n > LISTED then details[#details + 1] = string.format("- and %d more", n - LISTED) end
            details[#details + 1] = string.format("Board at %s; it lands at %s.",
                named(best.from.name) and best.from.name or "the boarding place",
                named(best.to.name) and best.to.name or "the landing")
            details[#details + 1] = N.CrossingWhen(weight)
            details[#details + 1] = "The boarding place is corrected from where you really board."
            steps[#steps + 1] = {
                kind = "crossing",
                key = "cross:" .. tostring(cont),
                crossing = best.key,
                how = best.how,
                toCont = cont,
                label = N.CrossingLabel(best.how, best.to.name),
                text = N.CrossingText(best.how, best.to.name, n, contName),
                place = { cont = best.from.cont, map = best.from.map, x = best.from.x, y = best.from.y },
                lands = { cont = best.to.cont, map = best.to.map, x = best.to.x, y = best.to.y },
                toBoard = best.toBoard,
                yards = best.yards,
                weight = weight,
                forQuests = forQuests,
                details = details,
            }
        end
    end
    return steps, unjoined
end

function N.CrossingStepFor(cont, steps)
    if type(steps) ~= "table" then return nil end
    for _, s in ipairs(steps) do
        if type(s) == "table" and s.toCont == cont then return s end
    end
    return nil
end

-- A trip the player made: the place read just before the continent changed
-- and the place read just after. A trip that starts beside a known end is
-- that crossing, and both its ends are set to where the player really was.
-- A trip from nowhere known is kept and counted; it is offered as a crossing
-- only after N.CROSSING_SURE trips. A landing at the hearthstone place is the
-- hearthstone, not a crossing. The list handed in is never changed.
function N.CrossingSeen(list, before, after, opts)
    list = type(list) == "table" and list or {}
    opts = type(opts) == "table" and opts or {}
    if not whole(before) or not whole(after) or before.cont == after.cont then
        return list, nil, "no change"
    end
    local apart = opts.apart

    local bind = opts.bind
    if placed(bind) and bind.map == after.map then
        local d = measure(apart, bind, after)
        if d == nil or d <= N.CROSSING_NEAR then return list, nil, "hearthstone" end
    end

    local hit
    for i, cr in ipairs(list) do
        if joins(cr) then
            for turn = 1, 2 do
                local from, to = cr.a, cr.b
                if turn == 2 then from, to = cr.b, cr.a end
                if from.cont == before.cont and to.cont == after.cont then
                    local d = measure(apart, before, from)
                    if d ~= nil and d <= N.CROSSING_NEAR then
                        local found = { index = i, turn = turn, key = cr.key, toStep = measure(apart, after, to), toBoard = d }
                        if hit == nil or better(found, hit) then hit = found end
                    end
                end
            end
        end
    end

    local out = {}
    for i, cr in ipairs(list) do out[i] = cr end

    if hit ~= nil then
        local cr = list[hit.index]
        local fixed = {}
        for k, v in pairs(cr) do fixed[k] = v end
        if hit.turn == 1 then
            fixed.a, fixed.b = copyPlace(before, cr.a.name), copyPlace(after, cr.b.name)
        else
            fixed.b, fixed.a = copyPlace(before, cr.b.name), copyPlace(after, cr.a.name)
        end
        fixed.corrected = true
        if num(cr.seen) then fixed.seen = cr.seen + 1 end
        out[hit.index] = fixed
        return out, cr.key, "corrected"
    end

    if opts.learnNew == false then return list, nil, "not near a known crossing" end

    local learned, taken = 0, {}
    for _, cr in ipairs(list) do
        if type(cr) == "table" then
            if cr.seen ~= nil then learned = learned + 1 end
            if cr.key ~= nil then taken[tostring(cr.key)] = true end
        end
    end
    if learned >= N.CROSSING_MAX then return list, nil, "full" end

    local base = "seen:" .. tostring(before.map) .. ":" .. tostring(after.map)
    local key, n = base, 1
    while taken[key] do
        n = n + 1
        key = base .. ":" .. tostring(n)
    end
    out[#out + 1] = { key = key, seen = 1, a = copyPlace(before), b = copyPlace(after) }
    return out, key, "new"
end

local function endName(p)
    if named(p.name) then return p.name end
    return "map " .. tostring(p.map)
end

-- What the player is told when asking about crossings.
function N.CrossingLines(list, steps, unjoined, on, faction)
    local usable, once = {}, {}
    if type(list) == "table" then
        for _, cr in ipairs(list) do
            if N.CrossingUsable(cr, faction) then
                usable[#usable + 1] = cr
            elseif joins(cr) and num(cr.seen) and cr.seen < N.CROSSING_SURE then
                once[#once + 1] = cr
            end
        end
    end
    local byKey = function(p, q) return tostring(p.key) < tostring(q.key) end
    table.sort(usable, byKey)
    table.sort(once, byKey)

    local lines = { string.format("crossings you can use: %d%s", #usable, on == false and " (off)" or "") }
    for _, cr in ipairs(usable) do
        lines[#lines + 1] = string.format("  %s: %s%s <-> %s%s", tostring(cr.key),
            named(cr.how) and (cr.how .. " ") or "", endName(cr.a), endName(cr.b),
            cr.corrected and " (corrected from a trip of yours)" or "")
    end
    for _, cr in ipairs(once) do
        lines[#lines + 1] = string.format("  seen once, not yet used: %s <-> %s", endName(cr.a), endName(cr.b))
    end
    local told = false
    if type(steps) == "table" then
        for _, s in ipairs(steps) do
            if type(s) == "table" and named(s.text) then
                lines[#lines + 1] = "  on your route: " .. s.text
                told = true
            end
        end
    end
    if type(unjoined) == "table" then
        for _, line in ipairs(unjoined) do
            if named(line) then
                lines[#lines + 1] = "  " .. line
                told = true
            end
        end
    end
    if not told then lines[#lines + 1] = "  nothing of yours waits on another continent" end
    return lines
end

-- ---------------------------------------------------------------- module

N.Crossings = N.Crossings or {}
local Crossings = N.Crossings

Crossings.NAME = "crossings"
Crossings.NEAR = 10            -- yards from the boarding place that count as there
Crossings.EVERY = 0.5          -- seconds between trip samples (a first guess, as N.Gates.EVERY)
Crossings.BIND = "learned.places.bind"   -- char: the hearthstone home (Nav/HearthSeen.lua)

-- One read of the client, or nil when it has no such read or it fails.
local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

function Crossings.Declare(k)
    local api = {}
    local ctx

    local function saved()
        local ok, list = pcall(ctx.store.get, ctx.store, "account", N.CROSSING_PLACES)
        if ok and type(list) == "table" then return list end
        return nil
    end

    -- Lead section 184 G2: the player's own trips. Each sample reads where
    -- the player is; a read that is not whole keeps the place before (a
    -- loading screen), a flight or a taxi read that is not known forgets
    -- it. When the continent changes between two places read off a
    -- flight, N.CrossingSeen gets both and its list is saved. Only what
    -- this client showed; nothing is copied in.
    local last

    function api.sample()
        if not ctx then return nil end
        local client = ctx.client
        local pos, zone = ask(client, "position"), ask(client, "zone")
        if type(pos) ~= "table" or type(zone) ~= "table" then return nil end
        local here = { cont = zone.cont, map = pos.map, x = pos.x, y = pos.y }
        if not whole(here) then return nil end
        if ask(client, "onTaxi") ~= false then
            last = nil
            return nil
        end
        local before = last
        last = here
        if before == nil or before.cont == here.cont then return nil end
        local okBind, bind = pcall(ctx.store.get, ctx.store, "char", Crossings.BIND)
        local list, key, what = N.CrossingSeen(saved(), before, here, {
            apart = N.CrossingApart(function(map) return ask(client, "mapSize", map) end),
            bind = okBind and type(bind) == "table" and bind or nil,
        })
        if key == nil then return nil, what end
        local okSet = pcall(ctx.store.set, ctx.store, "account", N.CROSSING_PLACES, list)
        if not okSet then return nil, "not saved" end
        return key, what
    end

    function api.way(place)
        if not ctx or not whole(place) then return nil end
        local client = ctx.client
        local pos, zone = ask(client, "position"), ask(client, "zone")
        if type(pos) ~= "table" or type(zone) ~= "table" then return nil end
        local me = { cont = zone.cont, map = pos.map, x = pos.x, y = pos.y }
        if not whole(me) or me.cont == place.cont then return nil end
        local target = { cont = place.cont, map = place.map, x = place.x, y = place.y }
        local steps = N.CrossingSteps({
            list = saved(), me = me, faction = ask(client, "faction"),
            apart = N.CrossingApart(function(map) return ask(client, "mapSize", map) end),
            waiting = { [target.cont] = { steps = { { place = target } }, targets = { target } } },
        })
        local step = N.CrossingStepFor(target.cont, steps)
        if step == nil then return nil end
        step.radius = Crossings.NEAR
        return step
    end

    k:Module({
        name = Crossings.NAME,
        needs = { "client", "store", "sched" },
        provides = { Way = function(place) return api.way(place) end },
        ticks = { { every = Crossings.EVERY, when = "always", run = function() api.sample() end } },
        start = function(c) ctx = c end,
        stop = function() ctx, last = nil, nil end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.crossings = Crossings.Declare(ns)
