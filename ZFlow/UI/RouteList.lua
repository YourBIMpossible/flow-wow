-- The route list beside the quest log (lead section 387, R4): the stops of
-- the route the arrow walks (Nav/TripRoute.lua View), in route order, each a
-- numbered plain line with its distance; the current stop marked; the stops
-- that wait under their own heading with the reason in plain words; what was
-- left off the route under its own. With no route it says so and how to plan
-- one. It opens and closes with the game's quest log and stands at its right
-- edge (client.questLogFrame); the setting RL.SETTING (on at first) turns it
-- and the world map pieces (UI/MapRoute.lua: the numbers and the zone card)
-- off, and the lines on the world map with them (UI/MapRouteLines.lua reads
-- this setting too).
--
-- Slice 5 (DISPATCH section 893): the rows are Nav/TrackerList.lua TL.Rows',
-- the ONE builder the tracker window reads too — this file draws them, it
-- does not build its own. It shows only what the route holds: the stops,
-- their words and their places are the route's (the quest log's own titles
-- and objective lines, places this player learned). Nothing is authored
-- here, and a reason the route does not give is not made up.
--
-- Built from the kit's parts only (UI/Kit.lua, drawn by client.kitWindow):
-- this file names no template, colour, font or size; its pictures are the
-- kit's (Kit.look.icon).
--
-- LOOK ONLY: nothing is moved, targeted, cast or sent. A click on a row
-- opens the world map on that stop's map (client.showMap), nothing else.
-- The one action is the Skip button under the current row, the same as
-- the tracker's: it asks the route to skip (tripRoute.Skip).
--
-- QUEST NEEDS (parity row C-14, lead section 603): a stop of a quest whose
-- Questie data says so gets "(escort)" or "(group of N)" after its words,
-- read through Questie's own QueryQuestSingle(id, "triggerEnd" |
-- "suggestedGroup"). The tags are TL.Needs', applied by TL.Rows through
-- the needOf this window hands it. As Flow Modules/Quests/QuestNeeds.lua
-- Q.ApplyNeed (tag after the name). Flow's hand-written escort note
-- (Q.EscortNote) is not carried: no cited Forever source backs it (lead
-- section 620, 611/619). Flow's per-quest table (where / note / tool /
-- item, questNeed 98430) is not carried: a table of quest IDs waits for
-- a ruling. "group of N" is Questie's suggested group, which Flow did
-- not show.
-- A2-22: while the world map is open the same window docks beside the
-- map instead (upstream Flow's RouterDock rule): outside the map's right
-- edge when the screen has room, inside that edge when it does not, and
-- left of the map's own quest panel when that panel is open. The map
-- takes precedence over the quest-log dock; when it closes the list
-- returns to the quest log, or hides. The spot is RL.Spot, pure. The map
-- read is client.worldMapFrame (a CLIENT NEED, the lead's patch: { shown,
-- right, top, height, panel = { shown, left, top, height } or nil });
-- until it lands, the ask finds nothing and the quest-log dock is the
-- only one, exactly as before.
--   RL.Children(rows, more, nLeft, counts, plan, how, onRow, onSkip)
--                          -> the window's parts (pure)
--   RL.Spot(mapRight, screenRight, need, questPanelOpen)
--                          -> "outside" | "besidePanel" | "inside" (pure)
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
RL.SKIP = "Skip this stop"
RL.NUMBERED = "%d. %s"
RL.NOW = "The arrow points here now"
RL.MORE = "and %d more stops"
RL.SUMMARY_STOPS = "%d stops"
RL.SUMMARY_ONE = "1 stop"
RL.SUMMARY_WAITING = "%d waiting"
RL.SUMMARY_LEFT = "%d not on the route"
RL.TIP = "Click to open the map on this stop."
RL.EVERY = 0.25
RL.WIDTH = 300
RL.HEIGHT = 420
RL.DOCK_GAP = 2
RL.TONE_NOW = "good"
RL.TONE_BLOCKED = "bad"

-- A2-22: where the list docks beside the world map (Flow RouterDock's
-- D.Spot, the panel named for Z-Flow's read). Pure: right edges and the
-- room needed, in screen pixels; an exact fit counts as outside, as in
-- Flow. Missing numbers are never outside.
function RL.Spot(mapRight, screenRight, need, questPanelOpen)
    if type(mapRight) == "number" and type(screenRight) == "number" and type(need) == "number"
        and mapRight + need <= screenRight then
        return "outside"
    end
    if questPanelOpen then return "besidePanel" end
    return "inside"
end

local function isText(v) return type(v) == "string" and v ~= "" end

local function TL() return ns.Nav and ns.Nav.TrackerList end
-- The counts line, from TL.Rows' counts (over all stops, capped or not).
function RL.Summary(rows, counts, nLeft)
    local stops = type(counts) == "table" and counts.stops or 0
    local waiting = type(counts) == "table" and counts.waiting or 0
    local parts = { stops == 1 and RL.SUMMARY_ONE or RL.SUMMARY_STOPS:format(stops) }
    if waiting > 0 then parts[#parts + 1] = RL.SUMMARY_WAITING:format(waiting) end
    if (nLeft or 0) > 0 then parts[#parts + 1] = RL.SUMMARY_LEFT:format(nLeft) end
    return table.concat(parts, ", ")
end

-- The window's parts from TL.Rows' rows (slice 5): the plan line, the
-- counts, the numbered stops, the held stops under their heading, the
-- left-off steps under theirs, how many more the cap left out, and the
-- Skip button under the current row (onSkip, wired by Declare).
-- how: the empty state's second line. onRow(row): a row's click, or nil.
function RL.Children(rows, more, nLeft, counts, plan, how, onRow, onSkip)
    local kids = { { kind = "header", key = "header", title = RL.HEADER } }
    if type(rows) ~= "table" or #rows == 0 then
        kids[#kids + 1] = { kind = "empty", key = "empty", text = RL.EMPTY,
            how = isText(how) and how
                or RL.EMPTY_HOW:format(tostring(type(ns.id) == "table" and ns.id.slash or ""), "route") }
        return kids
    end
    local tl = TL()
    local icons = ns.Kit and ns.Kit.look and ns.Kit.look.icon or {}
    if isText(plan) then kids[#kids + 1] = { kind = "line", key = "plan", text = plan } end
    kids[#kids + 1] = { kind = "line", key = "summary", text = RL.Summary(rows, counts, nLeft) }
    local held, leftN, hasCurrent = 0, 0, false
    for _, r in ipairs(rows) do
        local line = { kind = "line", text = r.text, sub = r.sub, icon = icons[r.icon or ""] }
        if r.n then
            line.key = r.current and "current" or ("stop" .. r.n)
            line.text = RL.NUMBERED:format(r.n, r.text)
            line.right = r.dist
            if r.current then
                hasCurrent = true
                line.tone = RL.TONE_NOW
                line.sub = r.sub and (r.sub .. ". " .. RL.NOW) or RL.NOW
            end
        elseif r.held ~= nil then
            held = held + 1
            if held == 1 and tl then
                kids[#kids + 1] = { kind = "line", key = "waitingHead", text = tl.WAITING_HEAD }
            end
            line.key = "held" .. held
            line.tone = RL.TONE_BLOCKED
        else
            leftN = leftN + 1
            if leftN == 1 and tl then
                kids[#kids + 1] = { kind = "line", key = "leftHead", text = tl.LEFT_HEAD }
            end
            line.key = "left" .. leftN
            line.tone = RL.TONE_BLOCKED
        end
        if type(onRow) == "function" and (type(r.place) == "table" or type(r.stop) == "table") then
            line.tooltip = RL.TIP
            line.onClick = function() onRow(r) end
        end
        kids[#kids + 1] = line
    end
    if type(more) == "number" and more > 0 then
        kids[#kids + 1] = { kind = "line", key = "more", text = RL.MORE:format(more) }
    end
    if hasCurrent and type(onSkip) == "function" then
        kids[#kids + 1] = { kind = "footer", key = "footer", text = "",
            buttons = { { kind = "button", key = "skip", text = RL.SKIP, onClick = onSkip } } }
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

    -- The Skip button under the current row (slice 5): the same action
    -- as the tracker's — the route skips its current stop.
    function api.Skip()
        local r = k.use and k.use("tripRoute")
        if r and type(r.Skip) == "function" then pcall(r.Skip) end
        api.Refresh()
        return true
    end

    -- Questie's own fields for a quest, through its loader; nil without it.
    local function needOf(quest)
        local db = ask(client(), "questieModule", "QuestieDB")
        if type(db) ~= "table" or type(db.QueryQuestSingle) ~= "function" then return nil end
        local raw = {}
        for _, field in ipairs({ "triggerEnd", "suggestedGroup" }) do
            local ok, v = pcall(db.QueryQuestSingle, quest, field)
            if ok then raw[field] = v end
        end
        local tl = TL()
        return tl and tl.Needs(raw)
    end

    -- Slice 5: the route settings the list reads — how many stops to
    -- show (nav.routeShown) and the plan line (nav.routeMode/Sort).
    local function setting(key)
        local s = ctx and ctx.settings
        if type(s) ~= "table" or type(s.get) ~= "function" then return nil end
        local ok, v = pcall(s.get, s, key)
        if ok then return v end
        return nil
    end


    -- Slice 7: a row's click opens the step card for its stop (the
    -- shared detail view); the map is the card's own button. A held
    -- or left-behind row passes no index, so the card shows its
    -- "not on your route" reason. Without the card module, the
    -- click keeps slice 5's behaviour and opens the map; so does a
    -- card that cannot open (Toggle not true) or raises.
    local function openRow(row)
        local card = k.use and k.use("stepCard")
        if type(card) == "table" and type(card.Toggle) == "function"
            and type(row) == "table" and type(row.stop) == "table" then
            local facts
            if row.index then facts = { index = row.index } end
            local ok, shown = pcall(card.Toggle, row.stop, facts)
            if ok and shown == true then return true end
        end
        return api.Show(row)
    end
    local function parts()
        local id = k.id or ns.id
        local T = ns.Nav and ns.Nav.TripRoute
        local how = RL.EMPTY_HOW:format(tostring(id.slash), tostring(T and T.WORD or "route"))
        local tl = TL()
        if not tl then return RL.Children(nil) end
        local rows, more, nLeft, counts = tl.Rows(view(), hereNow(), tl.MaxShown(setting("nav.routeShown")), needOf)
        local plan = tl.Plan(setting("nav.routeMode"), setting("nav.routeSort"))
        return RL.Children(rows, more, nLeft, counts, plan, how, openRow, api.Skip)
    end

    local function place(box)
        if type(box) ~= "table" or type(box.right) ~= "number" or type(box.top) ~= "number" then return nil end
        return { "TOPLEFT", "BOTTOMLEFT", box.right, box.top }
    end

    -- A2-22: the dock point and the height for one spot beside the world
    -- map. Points anchor on the screen's bottom-left, as place() does.
    local function dockPlace(map, spot)
        if type(map) ~= "table" then return nil, RL.HEIGHT end
        local gap = RL.DOCK_GAP
        if spot == "besidePanel" and type(map.panel) == "table"
            and type(map.panel.left) == "number" and type(map.panel.top) == "number" then
            local pheight = RL.HEIGHT
            if type(map.panel.height) == "number" and map.panel.height > 0 then pheight = map.panel.height end
            return { "TOPRIGHT", "BOTTOMLEFT", map.panel.left - gap, map.panel.top }, pheight
        end
        if type(map.right) ~= "number" or type(map.top) ~= "number" then return nil, RL.HEIGHT end
        local height = RL.HEIGHT
        if type(map.height) == "number" and map.height > 0 then height = map.height end
        if spot == "outside" then
            return { "TOPLEFT", "BOTTOMLEFT", map.right + gap, map.top }, height
        end
        return { "TOPRIGHT", "BOTTOMLEFT", map.right - gap, map.top }, height
    end

    local function dockSpot(map, c)
        local screenW
        if type(c) == "table" and type(c.screen) == "function" then
            local ok, w = pcall(c.screen)
            if ok and type(w) == "number" then screenW = w end
        end
        local panelOpen = type(map.panel) == "table" and map.panel.shown == true
        return RL.Spot(map.right, screenW, RL.WIDTH + RL.DOCK_GAP, panelOpen)
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
        local map = ask(c, "worldMapFrame")
        local logShown = type(box) == "table" and box.shown == true
        local mapShown = type(map) == "table" and map.shown == true
        if not logShown and not mapShown then
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
        local point, height
        if mapShown then
            point, height = dockPlace(map, dockSpot(map, c))
        else
            point = place(box)
            height = RL.HEIGHT
            if type(box.height) == "number" and box.height > 0 then height = box.height end
        end
        local tree, why = ns.Kit.Window({ id = RL.ID, title = id.title .. ": " .. RL.HEADER, children = kids,
            width = RL.WIDTH, height = height, point = point, resizable = false })
        if not tree then
            k.problems:add(RL.NAME, "tree", tostring(why))
            return
        end
        local sig = signature(kids)
        local edge = "none"
        if point then edge = point[1] .. ":" .. point[3] .. ":" .. point[4] .. ":" .. height end
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
