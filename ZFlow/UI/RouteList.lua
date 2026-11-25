-- The route list beside the quest log (lead section 387, R4): the stops of
-- the route the arrow walks (Nav/TripRoute.lua View), in route order, each a
-- numbered plain line with its distance; the current stop marked; a stop
-- that waits says why; what was left off the route is listed under it with
-- its reason. With no route it says so and how to plan one. It opens and
-- closes with the game's quest log and stands at its right edge
-- (client.questLogFrame); the setting RL.SETTING (on at first) turns it and
-- the world map pieces (UI/MapRoute.lua: the numbers and the zone card)
-- off, and the lines on the world map with them (UI/MapRouteLines.lua reads
-- this setting too). A row that hides only the map trail comes with the
-- slice that draws the trail (lead section 543).
--
-- It shows only what the route holds: the stops, their words and their
-- places are the route's (the quest log's own titles and objective lines,
-- places this player learned). Nothing is authored here, and a reason the
-- route does not give is not made up.
--
-- Built from the kit's parts only (UI/Kit.lua, drawn by client.kitWindow):
-- this file names no template, colour, font or size; its pictures are the
-- kit's (Kit.look.icon).
--
-- LOOK ONLY: nothing is moved, targeted, cast or sent. A click on a row
-- opens the world map on that stop's map (client.showMap), nothing else.
--
--   RL.Rows(view, here) -> rows, left   (pure) the numbered rows and what
--                          was left off
--   RL.Children(rows, left, how, onRow) -> the window's parts (pure)
--   RL.Declare(k, diag) -> api   api.Refresh(), api.Shown(), api.Show(row)
-- Not tested in game.
local _, ns = ...

local RL = {}
ns.RouteList = RL

RL.NAME = "routeList"
RL.ID = "routeList"
RL.SETTING = "nav.routePanel"
RL.HEADER = "Your route"
RL.EMPTY = "No route planned yet."
RL.EMPTY_HOW = "Type %s %s to plan one from your quest log."
RL.TURN_IN = "Turn in %s"
RL.TURN_IN_MANY = "Turn in %d quests"
RL.GIVE_TO = "Give it to %s"
RL.GIVE_THEM_TO = "Give them to %s"
RL.FOR_QUEST = "For the quest %s"
RL.NUMBERED = "%d. %s"
RL.NOW = "The arrow points here now"
RL.WAITING = "Waiting: %s"
RL.LEFT_OFF = "Not on the route: %s"
RL.MORE = "and %d more stops"
RL.SUMMARY_STOPS = "%d stops"
RL.SUMMARY_ONE = "1 stop"
RL.SUMMARY_WAITING = "%d waiting"
RL.SUMMARY_LEFT = "%d not on the route"
RL.TIP = "Click to open the map on this stop."
RL.MAX = 12
RL.EVERY = 0.25
RL.WIDTH = 300
RL.HEIGHT = 420
RL.TONE_NOW = "good"
RL.TONE_BLOCKED = "bad"

-- The reasons the route gives in a few words, said as a whole sentence. A
-- reason not listed here is shown as the route gave it.
RL.PLAIN = {
    ["not complete any more"] = "this quest is not complete any more. Finish it again first.",
    ["objectives not read yet"] = "the game has not told its objectives yet. Open the quest once.",
    ["a quest before it is not done"] = "a quest that comes before it is not done.",
    ["not on this map"] = "it is in another zone. Plan a new route when you get there.",
    ["giver's place not known"] = "nobody you met has shown where its giver stands.",
    ["location unknown"] = "its place is not known yet.",
}

local function isText(v) return type(v) == "string" and v ~= "" end

function RL.Why(why)
    if not isText(why) then return "the route gave no reason." end
    return RL.PLAIN[why] or why
end

-- "Turn in: <name>" (Nav/QuestSource.lua Q.TURN_IN_TO) -> the name, or nil.
local function receiver(detail)
    if not isText(detail) then return nil end
    local Q = ns.Nav and ns.Nav.QuestSource
    local form = type(Q) == "table" and Q.TURN_IN_TO or "Turn in: %s"
    local head = form:gsub("%%s", "")
    if detail:sub(1, #head) == head and #detail > #head then return detail:sub(#head + 1) end
    return nil
end

local function samePlace(a, b)
    return type(a) == "table" and type(b) == "table" and a.map == b.map and a.x == b.x and a.y == b.y
end

-- One stop's words: text, sub, icon (a Kit.look.icon key).
local function words(s)
    local label = isText(s.label) and s.label or "?"
    if s.kind == nil and s.turnIn == true then
        local to = receiver(s.detail)
        return RL.TURN_IN:format(label), to and RL.GIVE_TO:format(to) or nil, "questInLog"
    end
    if s.kind == nil and s.quest ~= nil then
        if isText(s.detail) then return s.detail, RL.FOR_QUEST:format(label), "questLater" end
        return label, nil, "questLater"
    end
    return label, isText(s.detail) and s.detail or nil, s.kind == "pickup" and "questAvailable" or nil
end

-- rows: the stops to walk, numbered in route order, turn-ins at one place
-- as one row; then the stops that wait (no number). left: what the route
-- left off. Each row { n, count, text, sub, dist, icon, now, blocked, why,
-- place }. here: { map, x, y, size = { w, h } } or nil.
function RL.Rows(view, here)
    if type(view) ~= "table" or type(view.stops) ~= "table" then return nil, nil end
    local walk, waiting = {}, {}
    for _, s in ipairs(view.stops) do
        if type(s) == "table" and type(s.place) == "table" then
            if s.held then
                local text, _, _ = words(s)
                waiting[#waiting + 1] = { text = text, sub = RL.WAITING:format(RL.Why(s.held)), blocked = true,
                    why = s.held, icon = "questNotForYou", place = s.place }
            else
                local last = walk[#walk]
                if last and last.turnIn and s.kind == nil and s.turnIn == true and samePlace(last.place, s.place) then
                    last.count = last.count + 1
                    last.names[#last.names + 1] = isText(s.label) and s.label or "?"
                    if last.to ~= receiver(s.detail) then last.to = nil end
                else
                    local text, sub, icon = words(s)
                    walk[#walk + 1] = { count = 1, text = text, sub = sub, icon = icon, place = s.place,
                        turnIn = s.kind == nil and s.turnIn == true, to = receiver(s.detail),
                        names = { isText(s.label) and s.label or "?" } }
                end
            end
        end
    end
    local T = ns.Nav and ns.Nav.Trip
    local dists = T and type(T.TrackRows) == "function" and T.TrackRows({ stops = walk }, here) or nil
    local rows = {}
    for i, r in ipairs(walk) do
        local row = { n = i, count = r.count, text = r.text, sub = r.sub, icon = r.icon, place = r.place,
            now = i == 1, dist = dists and dists[i] and dists[i].dist or nil }
        if r.count > 1 then
            row.text = RL.TURN_IN_MANY:format(r.count)
            row.sub = table.concat(r.names, ", ")
            if r.to then row.sub = row.sub .. ". " .. RL.GIVE_THEM_TO:format(r.to) end
        end
        rows[#rows + 1] = row
    end
    for _, r in ipairs(waiting) do rows[#rows + 1] = r end
    local left = {}
    for _, l in ipairs(type(view.left) == "table" and view.left or {}) do
        if type(l) == "table" then
            left[#left + 1] = { text = isText(l.label) and l.label or "?",
                sub = RL.LEFT_OFF:format(RL.Why(l.why)), blocked = true, why = l.why, icon = "questNotForYou" }
        end
    end
    return rows, left
end

function RL.Summary(rows, left)
    local stops, waiting = 0, 0
    for _, r in ipairs(rows or {}) do
        if r.n then stops = stops + 1 else waiting = waiting + 1 end
    end
    local parts = { stops == 1 and RL.SUMMARY_ONE or RL.SUMMARY_STOPS:format(stops) }
    if waiting > 0 then parts[#parts + 1] = RL.SUMMARY_WAITING:format(waiting) end
    if #(left or {}) > 0 then parts[#parts + 1] = RL.SUMMARY_LEFT:format(#left) end
    return table.concat(parts, ", ")
end

-- how: the empty state's second line. onRow(row): a row's click, or nil.
function RL.Children(rows, left, how, onRow)
    local kids = { { kind = "header", key = "header", title = RL.HEADER } }
    left = type(left) == "table" and left or {}
    if type(rows) ~= "table" or (#rows == 0 and #left == 0) then
        kids[#kids + 1] = { kind = "empty", key = "empty", text = RL.EMPTY,
            how = isText(how) and how
                or RL.EMPTY_HOW:format(tostring(type(ns.id) == "table" and ns.id.slash or ""), "route") }
        return kids
    end
    local icons = ns.Kit and ns.Kit.look and ns.Kit.look.icon or {}
    kids[#kids + 1] = { kind = "line", key = "summary", text = RL.Summary(rows, left) }
    local shown, held, hidden = 0, 0, 0
    for _, r in ipairs(rows) do
        if shown + held >= RL.MAX then
            hidden = hidden + 1
        else
            local line = { kind = "line", text = r.text, sub = r.sub, icon = icons[r.icon or ""] }
            if r.n then
                shown = shown + 1
                line.key = r.now and "current" or ("stop" .. r.n)
                line.text = RL.NUMBERED:format(r.n, r.text)
                line.right = r.dist
                if r.now then
                    line.tone = RL.TONE_NOW
                    line.sub = r.sub and (r.sub .. ". " .. RL.NOW) or RL.NOW
                end
            else
                held = held + 1
                line.key = "held" .. held
                line.tone = RL.TONE_BLOCKED
            end
            if type(onRow) == "function" and type(r.place) == "table" then
                line.tooltip = RL.TIP
                line.onClick = function() onRow(r) end
            end
            kids[#kids + 1] = line
        end
    end
    if hidden > 0 then kids[#kids + 1] = { kind = "line", key = "more", text = RL.MORE:format(hidden) } end
    for i, l in ipairs(left) do
        if i > RL.MAX then break end
        kids[#kids + 1] = { kind = "line", key = "left" .. i, text = l.text, sub = l.sub,
            icon = icons[l.icon or ""], tone = RL.TONE_BLOCKED }
    end
    return kids
end

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

-- What a tree says, for telling whether it changed: every part's words.
local function signature(kids)
    local out = {}
    for _, p in ipairs(kids) do
        out[#out + 1] = table.concat({ tostring(p.key), tostring(p.text or p.title), tostring(p.sub),
            tostring(p.right), tostring(p.tone), tostring(p.how) }, "|")
    end
    return table.concat(out, "\n")
end

function RL.Declare(k, diag)
    local api = {}
    local ctx
    local handle
    local lastSig, lastEdge
    local closedByPlayer = false

    local function client() return ctx and ctx.client or k.client end

    local function on()
        local s = ctx and ctx.settings
        if type(s) ~= "table" or type(s.get) ~= "function" then return true end
        local ok, v = pcall(s.get, s, RL.SETTING)
        return not (ok and v == false)
    end

    local function view()
        local r = k.use and k.use("tripRoute")
        if not (r and type(r.View) == "function") then return nil end
        local ok, v = pcall(r.View)
        if ok and type(v) == "table" then return v end
        return nil
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

    -- A row's click: the world map opens on that stop's map. Nothing else.
    function api.Show(row)
        if type(row) ~= "table" or type(row.place) ~= "table" or row.place.map == nil then return false end
        return ask(client(), "showMap", row.place.map) == true
    end

    local function parts()
        local id = k.id or ns.id
        local T = ns.Nav and ns.Nav.TripRoute
        local how = RL.EMPTY_HOW:format(tostring(id.slash), tostring(T and T.WORD or "route"))
        local rows, left = RL.Rows(view(), hereNow())
        return RL.Children(rows, left, how, api.Show)
    end

    local function place(box)
        if type(box) ~= "table" or type(box.right) ~= "number" or type(box.top) ~= "number" then return nil end
        return { "TOPLEFT", "BOTTOMLEFT", box.right, box.top }
    end

    local function hide()
        if handle and handle.shown() then handle.close() end
    end

    function api.Shown()
        return handle ~= nil and handle.shown() == true
    end

    -- The tick: the list follows the quest log and the route.
    function api.Refresh()
        if not ctx then return end
        local c = client()
        local box = ask(c, "questLogFrame")
        if type(box) ~= "table" or box.shown ~= true then
            closedByPlayer = false
            hide()
            return
        end
        if not on() or closedByPlayer then
            hide()
            return
        end
        if type(c.kitWindow) ~= "function" then return end
        local kids = parts()
        local id = k.id or ns.id
        local point = place(box)
        local height = type(box.height) == "number" and box.height > 0 and box.height or RL.HEIGHT
        local tree, why = ns.Kit.Window({ id = RL.ID, title = id.title .. ": " .. RL.HEADER, children = kids,
            width = RL.WIDTH, height = height, point = point, resizable = false })
        if not tree then
            k.problems:add(RL.NAME, "tree", tostring(why))
            return
        end
        local sig = signature(kids)
        local edge = point and (point[3] .. ":" .. point[4] .. ":" .. height) or "none"
        if not handle then
            handle = c.kitWindow(RL.ID, tree, {
                point = point, width = RL.WIDTH, height = height,
                onClose = function() closedByPlayer = true end,
                failed = function(err) k.problems:add(RL.NAME, "draw", tostring(err)) end,
            })
            if not handle then
                k.problems:add(RL.NAME, "window", "the client could not draw the window")
                return
            end
        elseif sig ~= lastSig then
            handle.update(tree)
        end
        if edge ~= lastEdge or not handle.shown() then
            if point then handle.place(point, RL.WIDTH, height) end
        end
        lastSig, lastEdge = sig, edge
        if not handle.shown() then handle.show(true) end
    end

    k:Setting({ key = RL.SETTING, scope = "account", type = "bool", default = true,
        label = "Show the route beside the quest log and on the map", group = "travel.route",
        help = 'Shows the stops of your route in order beside the quest log while it is open, and numbers them on the world map with a card for the zone. Turning it off hides the list, the map pins, the zone card and the map trail together. To hide only the trail, turn off "Show route lines on the map" instead.',
        synonyms = { "route", "list", "quest", "log", "map", "pins", "stops", "zone" } })

    k:Module({
        name = RL.NAME,
        needs = { "client", "store", "settings" },
        ticks = { { every = RL.EVERY, when = "always", run = function() api.Refresh() end } },
        start = function(c) ctx = c end,
        stop = function()
            if handle then handle.close() end
            lastSig, lastEdge, closedByPlayer = nil, nil, false
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.routeList = RL.Declare(ns, ns.diag)
