local _, ns = ...
-- Z-Flow trip list (lead DISPATCH section 361, P-TRIP slice 1): the stops
-- this character means to visit, as the pre-Z-Flow trip planner kept them.
-- Each stop is a place the player has seen or entered: the nearest seen
-- vendor, repair vendor, banker, innkeeper, flight master, mailbox or
-- trainer (Nav/Errand.lua E.Find), where a quest in the log is handed in
-- (Questie at runtime, else the spot the player learned, Nav/QuestSpots.lua),
-- a dungeon's entrance (Nav/DungeonRead.lua R.Entrance) or where the player
-- stands. No quest or route data ships here. `trip go` puts the stops on
-- this map in a short order (N.RoutePlan, the player's own trip times where
-- learned), the others after them as added, and hands them to the route
-- (Nav/TripRoute.lua Run): the arrow walks them and Nav/Trails.lua refines
-- each leg. WAYPOINTS ONLY: nothing here moves, targets, casts, interacts or
-- sends.
--
-- Saved per character at P.PATH: { stops = { { kind, label, detail,
-- place = { map, x, y } } } }, x, y shares 0..1, no more than P.MAX.
--
-- Pure:
--   P.Add(list, stop) -> true, or false and why
--   P.Remove(list, n) -> the stop, or nil and why
--   P.Order(list, here, legs) -> ordered copies, label
--   P.Lines(list, here) -> lines
--   P.Run(ordered, label) -> the run Nav/TripRoute.lua Run takes
--   P.Quest(rows, text) -> row or nil   by id or part of the title
--   P.Dungeon(list, text) -> entry or nil   by part of the name
--   P.TipLines(current, here) -> lines or nil   (slice 2) the route the
--     arrow walks (Nav/TripRoute.lua Current) for the quest arrow's
--     tooltip: the current stop marked, the straight distance left. Z-Flow
--     has no route panel; the arrow's tooltip is where the step is shown.
-- G42 (slice 3):
--   P.After(list, n, m) -> true, line or false, why   stop n comes after
--     stop m (`trip after <n> <m>`); a circle is refused, naming the stops
--   P.Edges(list) -> { [i] = { j, ... } }   stop i comes after stop j:
--     the player's own afters, a quest's hand-in after its objectives on
--     the trip, a dungeon's entrance after the pick-up givers of that
--     dungeon's quests on the trip
--   P.ViaText(step) -> words or nil   how the arrow reaches a stop on
--     another map: Nav/Travel.lua's step for it (the crossing, the flight
--     master, the gate), the same step the arrow is given for that leg
--   P.Order now keeps the afters (N.RoutePlan's after, then a stable pass
--     over the stops on other maps) and answers nil, why for a circle.
-- Each stop keeps an id (its number on the list changes on remove).
-- G43: P.TrackRows(current, here) -> { { label, detail, dist } } or nil
--   the route the arrow walks (Nav/TripRoute.lua Current) as rows for the
--   route tracker window (UI/RouteTracker.lua): each stop's distance from
--   the one before (the first from the player), or why it is not known.
-- Module "trip" provides List, Lines, Go, Tip. Not tested in game.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local P = {}
N.Trip = P

P.NAME = "trip"
P.WORD = "trip"
P.PATH = "state.trip"
P.MAX = 20
P.HELP = "a list of stops to visit: trip add vendor|repair|bank|inn|flight|mail|trainer|giver <quest>"
    .. "|dungeon <name>|here [label]; trip, trip remove <n>, trip after <n> <m>, trip clear, trip go"

P.HEADER = "Trip: %d stops"
P.EMPTY = "Trip: no stops. Add one with trip add."
P.FULL = "The trip is full (" .. P.MAX .. " stops); not added."
P.NO_PLACE = "That stop has no place; not added."
P.OTHER_MAP = "on another map"
P.NO_DISTANCE = "distance not known"
P.ADDED = "Added stop %d: %s."
P.REMOVED = "Removed %s."
P.BAD_NUMBER = "No stop %s on the trip."
P.CLEARED = "Trip cleared."
P.NOT_SEEN = "No %s you have seen is on this map; not added."
P.NO_HERE = "Where you stand is not known; not added."
P.NO_QUEST = "No quest '%s' in your log; not added."
P.NO_GIVER = "Where %s is handed in is not known; not added."
P.NO_DUNGEON = "No dungeon '%s' is known; not added."
P.NO_ENTRANCE = "No entrance known for %s; not added."
P.NO_KIND = "'%s' is no stop; not added. "
P.NO_ROUTE = "The route could not take the trip."
P.HERE_LABEL = "Where you stood"
P.HAND_IN = "Hand in: %s"
P.ENTRANCE = "Dungeon entrance"
P.TITLE = "Trip"
P.TIP_HEADER = "Route: %d stops left, %s"
P.TIP_NOW = "> "
P.TIP_NEXT = "  "
P.TIP_MORE = "  and %d more"
P.TIP_MAX = 5
P.AFTER_SET = "Stop %d (%s) now comes after stop %d (%s)."
P.AFTER_SAME = "A stop cannot come after itself."
P.AFTER_HOW = "Say trip after <n> <m>: stop n comes after stop m."
P.CIRCLE_WORD = "round in a circle"
P.CIRCLE = "Not set: %s would go " .. P.CIRCLE_WORD .. "."
P.CIRCLE_ORDER = "No route: %s go " .. P.CIRCLE_WORD .. "."
P.VIA = "via %s"

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function share(v)
    return finite(v) and v >= 0 and v <= 1
end

local function text(v)
    if type(v) == "string" and v ~= "" then return v end
    return nil
end

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

local function ids(v)
    if type(v) ~= "table" then return nil end
    local out = {}
    for _, x in ipairs(v) do
        if type(x) == "number" then out[#out + 1] = x end
    end
    if #out == 0 then return nil end
    return out
end

local function copy(s)
    return { id = type(s.id) == "number" and s.id or nil, kind = s.kind, label = s.label, detail = s.detail,
             after = ids(s.after), quest = s.quest, objective = s.objective, pickUp = s.pickUp or nil,
             quests = ids(s.quests),
             place = { map = s.place.map, x = s.place.x, y = s.place.y } }
end

-- A free id for a new stop: one above the highest on the list.
local function nextId(list)
    local top = 0
    for _, s in ipairs(list) do
        if type(s) == "table" and type(s.id) == "number" and s.id > top then top = s.id end
    end
    return top + 1
end

local function placed(s)
    return type(s) == "table" and type(s.place) == "table" and s.place.map ~= nil
        and share(s.place.x) and share(s.place.y)
end

function P.Add(list, stop)
    if type(list) ~= "table" or not placed(stop) then return false, P.NO_PLACE end
    if #list >= P.MAX then return false, P.FULL end
    local s = copy(stop)
    s.label = tostring(text(s.label) or s.kind or P.TITLE)
    if s.id == nil then s.id = nextId(list) end
    list[#list + 1] = s
    return true
end

function P.Remove(list, n)
    local i = tonumber(n)
    if type(list) ~= "table" or i == nil or i ~= math.floor(i) or list[i] == nil then
        return nil, P.BAD_NUMBER:format(tostring(n))
    end
    local gone = table.remove(list, i)
    for _, s in ipairs(list) do
        if type(s.after) == "table" then
            local keep = {}
            for _, x in ipairs(s.after) do
                if x ~= gone.id then keep[#keep + 1] = x end
            end
            if #keep > 0 then s.after = keep else s.after = nil end
        end
    end
    return gone
end

local function contains(list, v)
    for _, x in ipairs(type(list) == "table" and list or {}) do
        if x == v then return true end
    end
    return false
end

function P.Edges(list)
    local edges, byId = {}, {}
    list = type(list) == "table" and list or {}
    for i, s in ipairs(list) do
        if type(s) == "table" and s.id ~= nil then byId[s.id] = i end
    end
    local function add(i, j)
        if j == nil or i == j then return end
        edges[i] = edges[i] or {}
        if not contains(edges[i], j) then table.insert(edges[i], j) end
    end
    for i, s in ipairs(list) do
        if type(s) == "table" then
            for _, id in ipairs(type(s.after) == "table" and s.after or {}) do add(i, byId[id]) end
            for j, o in ipairs(list) do
                if type(o) == "table" and o.quest ~= nil then
                    -- A quest's hand-in after its objectives.
                    if s.kind == "giver" and s.quest == o.quest and o.objective ~= nil then add(i, j) end
                    -- A dungeon's entrance after the pick-up givers of its quests.
                    if s.kind == "dungeon" and o.pickUp and contains(s.quests, o.quest) then add(i, j) end
                end
            end
        end
    end
    return edges
end

local function ringNames(list, ring)
    local names = {}
    for _, i in ipairs(ring) do names[#names + 1] = tostring(list[i] and list[i].label) end
    names[#names + 1] = names[1]
    return table.concat(names, " after ")
end

function P.After(list, n, m)
    local i, j = tonumber(n), tonumber(m)
    if type(list) ~= "table" then return false, P.AFTER_HOW end
    if i == nil or list[i] == nil then return false, P.BAD_NUMBER:format(tostring(n)) end
    if j == nil or list[j] == nil then return false, P.BAD_NUMBER:format(tostring(m)) end
    if i == j then return false, P.AFTER_SAME end
    local s, o = list[i], list[j]
    if s.id == nil then s.id = nextId(list) end
    if o.id == nil then o.id = nextId(list) end
    local before = s.after
    local now = ids(before) or {}
    if not contains(now, o.id) then now[#now + 1] = o.id end
    s.after = now
    local ring = N.RouteCycle(#list, P.Edges(list))
    if ring then
        s.after = before
        return false, P.CIRCLE:format(ringNames(list, ring))
    end
    return true, P.AFTER_SET:format(i, tostring(s.label), j, tostring(o.label))
end

function P.ViaText(step)
    if type(step) ~= "table" or step.via == nil then return nil end
    if step.via == "far" then return N.Travel and N.Travel.FAR or nil end
    if type(step.label) ~= "string" or step.label == "" then return nil end
    return P.VIA:format(step.label)
end

local function sizeOf(here)
    local s = type(here) == "table" and here.size or nil
    if type(s) == "table" and finite(s.w) and finite(s.h) and s.w > 0 and s.h > 0 then return s end
    return nil
end

function P.Order(list, here, legs)
    here = type(here) == "table" and here or {}
    local all = {}
    for _, s in ipairs(type(list) == "table" and list or {}) do
        if placed(s) then all[#all + 1] = s end
    end
    local edges = P.Edges(all)
    local ring = N.RouteCycle(#all, edges)
    if ring then return nil, P.CIRCLE_ORDER:format(ringNames(all, ring)) end
    local same, others = {}, {}
    for i, s in ipairs(all) do
        if here.map ~= nil and s.place.map == here.map then
            same[#same + 1] = i
        else
            others[#others + 1] = i
        end
    end
    local seq, label = {}, N.ROUTE_STRAIGHT
    local size = sizeOf(here)
    local route
    if #same > 0 and size and type(N.RoutePlan) == "function" then
        local places, localOf, after = {}, {}, {}
        for n, i in ipairs(same) do
            places[n] = all[i].place
            localOf[i] = n
        end
        for n, i in ipairs(same) do
            for _, j in ipairs(edges[i] or {}) do
                if localOf[j] then
                    after[n] = after[n] or {}
                    table.insert(after[n], localOf[j])
                end
            end
        end
        route = N.RoutePlan(places, here.map, size, here, legs, after)
    end
    if route then
        label = route.label
        for _, rs in ipairs(route.stops) do seq[#seq + 1] = same[rs.index] end
    else
        for _, i in ipairs(same) do seq[#seq + 1] = i end
    end
    for _, i in ipairs(others) do seq[#seq + 1] = i end
    -- G42: a stable pass: the first stop of seq whose afters are all done
    -- goes next. Without afters seq is kept as it is.
    local done, ordered = {}, {}
    while #ordered < #seq do
        local took = false
        for _, i in ipairs(seq) do
            if not done[i] then
                local free = true
                for _, j in ipairs(edges[i] or {}) do
                    if not done[j] then free = false end
                end
                if free then
                    done[i] = true
                    ordered[#ordered + 1] = copy(all[i])
                    took = true
                    break
                end
            end
        end
        if not took then break end
    end
    return ordered, label
end

local function distance(s, here)
    if type(here) ~= "table" or here.map == nil or s.place.map ~= here.map then return P.OTHER_MAP end
    local size = sizeOf(here)
    if not size or not (finite(here.x) and finite(here.y)) then return P.NO_DISTANCE end
    local dx, dy = (s.place.x - here.x) * size.w, (s.place.y - here.y) * size.h
    return tostring(math.floor(math.sqrt(dx * dx + dy * dy) + 0.5)) .. " yd"
end

function P.Lines(list, here, vias)
    if type(list) ~= "table" or #list == 0 then return { P.EMPTY } end
    local lines = { P.HEADER:format(#list) }
    for i, s in ipairs(list) do
        local parts = { tostring(s.label) }
        if s.detail ~= nil then parts[#parts + 1] = tostring(s.detail) end
        if placed(s) then
            parts[#parts + 1] = distance(s, here)
        else
            parts[#parts + 1] = P.NO_DISTANCE
        end
        if type(vias) == "table" and type(vias[i]) == "string" then parts[#parts + 1] = vias[i] end
        lines[#lines + 1] = i .. ". " .. table.concat(parts, " - ")
    end
    return lines
end

function P.Run(ordered, label)
    local steps = {}
    for _, s in ipairs(type(ordered) == "table" and ordered or {}) do
        if placed(s) then
            -- Lead section 375: a hand-in stop is checked against the log.
            local logQuest = s.quest ~= nil and not s.pickUp
            local quest
            if logQuest then quest = s.quest end
            steps[#steps + 1] = { kind = "trip", label = s.label, detail = s.detail,
                                  quest = quest, logQuest = logQuest,
                                  place = { map = s.place.map, x = s.place.x, y = s.place.y } }
        end
    end
    local title = P.TITLE
    if label ~= nil then title = title .. " (" .. tostring(label) .. ")" end
    return { title = title, steps = steps, left = {} }
end

-- Lead section 375: the stops whose quest is no longer in the log (rows
-- read) leave the list; a pick-up stop is kept. Answers the labels taken.
function P.Prune(list, rows)
    local gone = {}
    if type(list) ~= "table" or type(rows) ~= "table" then return gone end
    local have = {}
    for _, row in ipairs(rows) do
        if type(row) == "table" and row.id ~= nil then have[row.id] = true end
    end
    for i = #list, 1, -1 do
        local s = list[i]
        if type(s) == "table" and s.quest ~= nil and not s.pickUp and not have[s.quest] then
            local out = P.Remove(list, i)
            if out then table.insert(gone, 1, out.label) end
        end
    end
    return gone
end

local function yardsOf(n)
    return tostring(math.floor(n + 0.5)) .. " yd"
end

function P.TipLines(current, here)
    local stops = type(current) == "table" and type(current.stops) == "table" and current.stops or nil
    if not stops or #stops == 0 then return nil end
    here = type(here) == "table" and here or {}
    local size = sizeOf(here)
    local rows, total = {}, 0
    local last
    if finite(here.x) and finite(here.y) then last = { map = here.map, x = here.x, y = here.y } end
    for i, s in ipairs(stops) do
        local p = type(s) == "table" and s.place or nil
        local dist
        if type(p) ~= "table" or type(last) ~= "table" then
            dist, total = P.NO_DISTANCE, nil
        elseif p.map ~= last.map then
            dist, total = P.OTHER_MAP, nil
        elseif not size or p.map ~= here.map or not (finite(p.x) and finite(p.y)) then
            dist, total = P.NO_DISTANCE, nil
        else
            local dx, dy = (p.x - last.x) * size.w, (p.y - last.y) * size.h
            local d = math.sqrt(dx * dx + dy * dy)
            dist = yardsOf(d)
            if total then total = total + d end
        end
        if i <= P.TIP_MAX then
            local parts = { tostring(type(s) == "table" and s.label or "?") }
            if type(s) == "table" and s.detail ~= nil then parts[#parts + 1] = tostring(s.detail) end
            parts[#parts + 1] = dist
            rows[#rows + 1] = (i == 1 and P.TIP_NOW or P.TIP_NEXT) .. table.concat(parts, " - ")
        end
        last = type(p) == "table" and p or nil
    end
    local lines = { P.TIP_HEADER:format(#stops, total and yardsOf(total) or P.NO_DISTANCE) }
    for _, r in ipairs(rows) do lines[#lines + 1] = r end
    if #stops > P.TIP_MAX then lines[#lines + 1] = P.TIP_MORE:format(#stops - P.TIP_MAX) end
    return lines
end

function P.TrackRows(current, here)
    local stops = type(current) == "table" and type(current.stops) == "table" and current.stops or nil
    if not stops or #stops == 0 then return nil end
    here = type(here) == "table" and here or {}
    local size = sizeOf(here)
    local rows = {}
    local last
    if finite(here.x) and finite(here.y) then last = { map = here.map, x = here.x, y = here.y } end
    for i, s in ipairs(stops) do
        local p = type(s) == "table" and s.place or nil
        local dist
        if type(p) ~= "table" or type(last) ~= "table" then
            dist = P.NO_DISTANCE
        elseif p.map ~= last.map then
            dist = P.OTHER_MAP
        elseif not size or p.map ~= here.map or not (finite(p.x) and finite(p.y)) then
            dist = P.NO_DISTANCE
        else
            local dx, dy = (p.x - last.x) * size.w, (p.y - last.y) * size.h
            dist = yardsOf(math.sqrt(dx * dx + dy * dy))
        end
        local row = { label = tostring(type(s) == "table" and s.label or "?"), dist = dist }
        if type(s) == "table" and s.detail ~= nil then row.detail = tostring(s.detail) end
        rows[i] = row
        last = type(p) == "table" and p or nil
    end
    return rows
end

function P.Quest(rows, want)
    want = text(want)
    if not want then return nil end
    local id = tonumber(want)
    local lower = want:lower()
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
        if type(row) == "table" and ((id ~= nil and row.id == id)
            or (type(row.title) == "string" and row.title:lower():find(lower, 1, true) ~= nil)) then
            return row
        end
    end
    return nil
end

function P.Dungeon(list, want)
    want = text(want)
    if not want then return nil end
    local lower = want:lower()
    for _, d in ipairs(type(list) == "table" and list or {}) do
        if type(d) == "table" and type(d.name) == "string" and d.name:lower():find(lower, 1, true) ~= nil then
            return d
        end
    end
    return nil
end

-- The point of a spot nearest the player on the player's map (the first
-- elsewhere), else its away point; nil when it has none.
local function pointOf(spot, here)
    if type(spot) ~= "table" then return nil end
    local size = sizeOf(here) or { w = 1, h = 1 }
    local best, bestD
    for _, pt in ipairs(type(spot.points) == "table" and spot.points or {}) do
        if type(pt) == "table" and pt.map ~= nil and share(pt.x) and share(pt.y) then
            local d = 0
            if pt.map == here.map and finite(here.x) and finite(here.y) then
                local dx, dy = (pt.x - here.x) * size.w, (pt.y - here.y) * size.h
                d = dx * dx + dy * dy
            end
            if best == nil or d < bestD then best, bestD = pt, d end
        end
    end
    if best then return { map = best.map, x = best.x, y = best.y } end
    local a = spot.away
    if type(a) == "table" and a.map ~= nil and share(a.x) and share(a.y) then
        return { map = a.map, x = a.x, y = a.y }
    end
    return nil
end

function P.Declare(k, diag)
    local api = {}
    local ctx
    local dungeons

    local function client() return ctx and ctx.client or k.client end

    local function load()
        local v = ctx and ctx.store:get("char", P.PATH)
        local list = {}
        local saved = type(v) == "table" and type(v.stops) == "table" and v.stops or {}
        for _, s in ipairs(saved) do
            if placed(s) and #list < P.MAX then list[#list + 1] = copy(s) end
        end
        for _, s in ipairs(list) do
            if s.id == nil then s.id = nextId(list) end
        end
        return list
    end

    local function save(list)
        if ctx then ctx.store:set("char", P.PATH, { stops = list }) end
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

    local function seen(word)
        local E = ns.Errand
        local kind = E and E.KINDS[word]
        if not kind then return nil end
        local place = E.Find(kind, client(), ctx and ctx.store)
        local step = place and E.Step(place)
        if not step then return nil, P.NOT_SEEN:format(word) end
        return { kind = word, label = step.label, place = step.place }
    end

    local function standing(label)
        local h = hereNow()
        if h.map == nil or not (share(h.x) and share(h.y)) then return nil, P.NO_HERE end
        return { kind = "here", label = text(label) or P.HERE_LABEL, place = { map = h.map, x = h.x, y = h.y } }
    end

    local function giver(want)
        local c = client()
        local row = P.Quest(N.QuestLogRows(c), want)
        if not row then
            local id = tonumber(want)
            if id == nil then return nil, P.NO_QUEST:format(tostring(want)) end
            row = { id = id, title = "Quest " .. tostring(id), objectives = {} }
        end
        local h = hereNow()
        local places = N.QuestiePlaces(c, { row }, h.map)
        local QS = N.QuestSpots
        if QS and ctx then
            places = QS.Merge(places, QS.Places(ctx.store:get("account", QS.PATH), { row }, h.map))
        end
        local entry = type(places) == "table" and places[row.id] or nil
        local spot = type(entry) == "table" and entry.turnIn or nil
        local pt = pointOf(spot, h)
        if not pt then return nil, P.NO_GIVER:format(tostring(row.title)) end
        return { kind = "giver", quest = row.id, label = P.HAND_IN:format(tostring(row.title)),
                 detail = type(spot) == "table" and text(spot.name) or nil, place = pt }
    end

    local function dungeon(want)
        local R = ns.DungeonRead
        local c = client()
        if not R then return nil, P.NO_DUNGEON:format(tostring(want)) end
        if type(dungeons) ~= "table" or type(dungeons.byKey) ~= "table" then dungeons = R.Start(c) end
        local list = {}
        for key, d in pairs(type(dungeons.byKey) == "table" and dungeons.byKey or {}) do
            list[#list + 1] = { key = key, name = d.name }
        end
        table.sort(list, function(a, b) return tostring(a.name) < tostring(b.name) end)
        local d = P.Dungeon(list, want)
        if not d then return nil, P.NO_DUNGEON:format(tostring(want)) end
        local e = R.Entrance(dungeons, c, d.key)
        if type(e) ~= "table" then return nil, P.NO_ENTRANCE:format(tostring(d.name)) end
        local quests
        if type(R.List) == "function" then
            local okList, rows = pcall(R.List, dungeons)
            for _, row in ipairs(okList and type(rows) == "table" and rows or {}) do
                if type(row) == "table" and row.key == d.key then quests = ids(row.ids) end
            end
        end
        return { kind = "dungeon", quests = quests, label = tostring(d.name), detail = P.ENTRANCE,
                 place = { map = e.map, x = e.x / 100, y = e.y / 100 } }
    end

    function api.List() return load() end

    -- G42: how the arrow reaches each stop on another map (Nav/Travel.lua
    -- Via, the step the arrow is given for that leg), as words.
    local function viasOf(list, here)
        local vias = {}
        local travel = k.use and k.use("travel")
        if not (travel and type(travel.Via) == "function") then return vias end
        for i, s in ipairs(list) do
            if placed(s) and s.place.map ~= here.map then
                local ok, step = pcall(travel.Via, { label = s.label, detail = s.detail,
                    place = { map = s.place.map, x = s.place.x, y = s.place.y } })
                if ok then vias[i] = P.ViaText(step) end
            end
        end
        return vias
    end

    function api.Lines()
        local list, here = load(), hereNow()
        return P.Lines(list, here, viasOf(list, here))
    end

    -- word: the kind after "add"; rest: the quest, dungeon or label.
    -- Answers the line to show.
    function api.Add(word, rest)
        local stop, why
        if word == "here" then
            stop, why = standing(rest)
        elseif word == "giver" or word == "quest" then
            stop, why = giver(rest)
        elseif word == "dungeon" then
            stop, why = dungeon(rest)
        else
            stop, why = seen(word)
            if not stop and not why then return P.NO_KIND:format(tostring(word)) .. P.HELP .. "." end
        end
        if not stop then return why end
        local list = load()
        local ok, full = P.Add(list, stop)
        if not ok then return full end
        save(list)
        return P.ADDED:format(#list, tostring(list[#list].label))
    end

    function api.Go()
        local list = load()
        if #list == 0 then return P.EMPTY end
        local route = k.use and k.use("tripRoute")
        if not (route and type(route.Run) == "function") then return P.NO_ROUTE end
        local h = hereNow()
        local legs
        local L = k.use and k.use("legs")
        if L and type(L.Planner) == "function" and h.map ~= nil then
            local ok, fn = pcall(L.Planner, h.map)
            if ok and type(fn) == "function" then legs = fn end
        end
        local ordered, label = P.Order(list, h, legs)
        if not ordered then return tostring(label) end
        local ok, line = pcall(route.Run, P.Run(ordered, label))
        if not ok then return P.NO_ROUTE end
        return tostring(line)
    end

    function api.Prune(rows)
        local list = load()
        local gone = P.Prune(list, rows)
        if #gone > 0 then save(list) end
        return gone
    end

    function api.Tip()
        local route = k.use and k.use("tripRoute")
        if not (route and type(route.Current) == "function") then return nil end
        local ok, current = pcall(route.Current)
        if not ok then return nil end
        return P.TipLines(current, hereNow())
    end

    local function say(lines)
        local c = client()
        if type(c) ~= "table" or type(c.print) ~= "function" then return end
        local id = k.id or ns.id
        for _, line in ipairs(lines) do c.print(id.title .. ": " .. tostring(line)) end
    end

    function api.Word(input)
        local word, rest = tostring(input or ""):match("^%s*(%S*)%s*(.-)%s*$")
        word = word:lower()
        if word == "" or word == "list" then
            say(api.Lines())
        elseif word == "add" then
            local kind, more = rest:match("^(%S*)%s*(.-)$")
            say({ api.Add(kind:lower(), more) })
        elseif word == "remove" then
            local list = load()
            local gone, why = P.Remove(list, rest)
            if gone then
                save(list)
                say({ P.REMOVED:format(tostring(gone.label)) })
            else
                say({ why })
            end
        elseif word == "after" then
            local n, m = rest:match("^(%S+)%s+(%S+)")
            if not n then
                say({ P.AFTER_HOW })
            else
                local list = load()
                local ok, line = P.After(list, n, m)
                if ok then save(list) end
                say({ line })
            end
        elseif word == "clear" then
            save({})
            say({ P.CLEARED })
        elseif word == "go" then
            say({ api.Go() })
        else
            say({ P.NO_KIND:format(word) .. P.HELP .. "." })
        end
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[P.WORD] = function(rest) api.Word(rest) end
        if type(diag.help) == "table" then diag.help[P.WORD] = P.HELP end
    end

    k:Module({
        name = P.NAME,
        needs = { "client", "store" },
        provides = { List = api.List, Lines = api.Lines, Go = api.Go, Tip = api.Tip, Prune = api.Prune },
        start = function(c) ctx = c end,
        stop = function() dungeons = nil end,
    })
    return api
end

ns.trip = P.Declare(ns, ns.diag)
