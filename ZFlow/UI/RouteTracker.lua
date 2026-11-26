-- The route tracker window (G43, P-TRIP): the next steps of the route the
-- arrow walks (Nav/TripRoute.lua Current: a trip from Nav/Trip.lua, a quest
-- route or a dungeon run), the current step marked with the kit's "good"
-- tone, each with its distance (Nav/Trip.lua P.TrackRows). With no route it
-- says so (the kit's empty part). It shows while a route is planned (the
-- setting RT.SETTING, on at first); the player may close it (Escape: it has
-- a name) and `<slash> tracker` opens it again. Its place is kept, account
-- wide, at RT.PATH.
--
-- The current step is also pinned on the world map when the map shows the
-- step's map (client.mapPins, the same pins Nav/MapFlights.lua draws).
--
-- Built from the kit's parts only (UI/Kit.lua, drawn by client.kitWindow):
-- this file names no template, colour, font, size or picture, and works
-- out nothing: the steps and distances are Nav/'s.
--
-- A quest stop whose quest hands the player something to use (S42,
-- Nav/QuestItems.lua) gets that item under the current step: its real icon,
-- its name in its rarity colour, how many are in the bags, and RT.ITEM_NOTE.
-- The line only names the item: it is no button and uses nothing. The
-- player uses it from the bags.
--
-- LOOK ONLY: nothing is moved, targeted, cast, clicked or sent. The skip
-- button skips the route's stop (Nav/TripRoute.lua Skip), nothing else.
--
-- What it lists is Nav/TrackerList.lua's (A2-18): TL.Rows of the route's
-- View (Nav/TripRoute.lua: held steps too, each with its reason), or of the
-- walked route (Current) when there is no View (a trip, a dungeon run). The
-- current step is the first one not held; a held one says why (RT.HELD).
--
--   RT.Rows(view, current, here) -> rows, more | nil   (pure)
--   RT.Children(rows[, item[, more]]) -> the window's parts (pure)
--     more  how many steps TL.Rows left out (the "more" line)
--     item  the current stop's quest item, or nil:
--           { id, name, count, quality, icon }; any may be absent, but not
--           both id and name
--   RT.ItemLine(item) -> that item as one item line, or nil
--   RT.Declare(k, diag) -> api   api.Open(), api.Close(), api.Shown(),
--                                api.Refresh()
-- Not tested in game.
local _, ns = ...

local RT = {}
ns.RouteTracker = RT

RT.NAME = "routeTracker"
RT.ID = "routeTracker"
RT.WORD = "tracker"
RT.HELP = "open the route tracker window"
RT.SETTING = "nav.tracker"
RT.PATH = "layout.routeTracker"
RT.HEADER = "Route"
RT.EMPTY = { "No route planned.", "Plan one with the trip or route word." }
RT.SKIP = "Skip this stop"
RT.MORE = "and %d more"
RT.TIP = "Click to open the map on this stop."
RT.MAX = 8
RT.EVERY = 1
RT.TONE_NOW = "good"
RT.PIN_KIND = "new"
RT.PIN_ROLE = "route"
RT.ITEM_NOTE = "Use this for the quest: it is in your bags"
RT.ITEM_PLAIN = "The quest's own item"

local function whole(v) return type(v) == "number" and v >= 0 and v == math.floor(v) and v < math.huge end

-- A value the kit would turn down is left out, so the line never costs
-- the window.
function RT.ItemLine(item)
    if type(item) ~= "table" then return nil end
    local name = item.name
    if type(name) ~= "string" or name == "" or name:find("[%c|]") then name = nil end
    if name == nil and item.id == nil then return nil end
    local line = { kind = "itemLine", key = "questItem", name = name or RT.ITEM_PLAIN, note = RT.ITEM_NOTE }
    if whole(item.quality) and item.quality <= 5 then line.quality = item.quality end
    if whole(item.count) and item.count > 0 then line.count = item.count end
    if type(item.id) == "number" then line.item = item.id end
    if (type(item.icon) == "string" and item.icon ~= "") or type(item.icon) == "number" then line.icon = item.icon end
    return line
end

function RT.Rows(view, current, here, max)
    local TL = ns.Nav and ns.Nav.TrackerList
    if type(TL) ~= "table" then return nil end
    -- Lead section 762: the view whenever it has stops or steps that can't
    -- be placed (left); the walked route only when it has neither (Flow
    -- listed its blocked goals with an empty plan, RouteTracker.lua:504-519).
    local src = current
    if type(view) == "table" then
        local n = 0
        if type(view.stops) == "table" then n = n + #view.stops end
        if type(view.left) == "table" then n = n + #view.left end
        if n > 0 then src = view end
    end
    return TL.Rows(src, here, max or RT.MAX)
end

-- The row that is the current step: the one TL.Rows marked; rows that
-- carry no mark and hold nothing (Nav/Trip.lua P.TrackRows) start with it.
local function currentIndex(rows)
    local marked = false
    for i, r in ipairs(rows) do
        if r.current == true then return i end
        -- Lazy (lead section 773): a step that cannot be placed (r.left) is
        -- marked too, so a route of those only has no current step.
        if r.current ~= nil or r.held ~= nil or r.left ~= nil then marked = true end
    end
    if marked then return nil end
    return 1
end

-- The window's parts from TL.Rows' rows (slice 5: the same rows the
-- list beside the quest log draws — the plan line, the held stops
-- under their heading, the left-off steps under theirs, and a click
-- on a row opens the map on its stop, as in the list). The rows
-- arrive capped (nav.routeShown, read by Declare); more says how
-- many stops the cap left out.
function RT.Children(rows, item, more, plan, onRow)
    local kids = { { kind = "header", key = "header", title = RT.HEADER } }
    if type(rows) ~= "table" or #rows == 0 then
        kids[#kids + 1] = { kind = "empty", key = "empty", text = RT.EMPTY[1], how = RT.EMPTY[2] }
        return kids
    end
    local TL = ns.Nav and ns.Nav.TrackerList
    if type(plan) == "string" and plan ~= "" then
        kids[#kids + 1] = { kind = "line", key = "plan", text = plan }
    end
    local now = currentIndex(rows)
    local held, leftN = 0, 0
    for i, r in ipairs(rows) do
        local line
        if r.held ~= nil then
            held = held + 1
            if held == 1 and TL then
                kids[#kids + 1] = { kind = "line", key = "waitingHead", text = TL.WAITING_HEAD }
            end
            line = { kind = "line", key = "held" .. held, text = tostring(r.label), sub = r.held }
        elseif r.left ~= nil then
            leftN = leftN + 1
            if leftN == 1 and TL then
                kids[#kids + 1] = { kind = "line", key = "leftHead", text = TL.LEFT_HEAD }
            end
            line = { kind = "line", key = "left" .. leftN, text = tostring(r.label), sub = r.sub }
        else
            line = { kind = "line", text = tostring(r.label), sub = r.detail, right = r.dist }
            if i == now then
                line.key = "current"
                line.tone = RT.TONE_NOW
            else
                line.key = "next" .. (i - 1)
            end
        end
        if type(onRow) == "function" and (type(r.place) == "table" or type(r.stop) == "table") then
            line.tooltip = RT.TIP
            line.onClick = function() onRow(r) end
        end
        kids[#kids + 1] = line
        if i == now then kids[#kids + 1] = RT.ItemLine(item) end
    end
    if whole(more) and more > 0 then
        kids[#kids + 1] = { kind = "line", key = "more", text = RT.MORE:format(more) }
    end
    kids[#kids + 1] = { kind = "footer", key = "footer", text = "",
        buttons = { { kind = "button", key = "skip", text = RT.SKIP, onClick = function() end } } }
    return kids
end

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

function RT.Declare(k, diag)
    local api = {}
    local ctx
    local handle, pins
    local hadRoute, wasOn = false, true

    local function client() return ctx and ctx.client or k.client end

    local function on()
        local s = ctx and ctx.settings
        if type(s) ~= "table" or type(s.get) ~= "function" then return true end
        local ok, v = pcall(s.get, s, RT.SETTING)
        return not (ok and v == false)
    end

    local function route() return k.use and k.use("tripRoute") end

    local function current()
        local r = route()
        if not (r and type(r.Current) == "function") then return nil end
        local ok, cur = pcall(r.Current)
        if ok and type(cur) == "table" then return cur end
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

    -- The current stop's quest item (Nav/QuestItems.lua), with what the
    -- client says of it; nil when the stop has no quest or no item to use.
    local function itemOf(cur)
        local s = type(cur) == "table" and type(cur.stops) == "table" and cur.stops[1] or nil
        if type(s) ~= "table" or s.quest == nil then return nil end
        local qi = k.use and k.use("questItems")
        if not (qi and type(qi.For) == "function") then return nil end
        local ok, item = pcall(qi.For, s.quest)
        if not ok or type(item) ~= "table" then return nil end
        local info = ask(client(), "itemInfo", item.id)
        info = type(info) == "table" and info or {}
        return { id = item.id, name = item.name, count = item.count, quality = info.quality,
            icon = ask(client(), "itemTexture", item.id) }
    end

    local function view()
        local r = route()
        if not (r and type(r.View) == "function") then return nil end
        local ok, v = pcall(r.View)
        if ok and type(v) == "table" then return v end
        return nil
    end

    -- A row's click: the world map opens on that stop's map (slice 5:
    -- the same action as the list beside the quest log).
    function api.Show(row)
        if type(row) ~= "table" or type(row.place) ~= "table" or row.place.map == nil then return false end
        return ask(client(), "showMap", row.place.map) == true
    end

    -- Slice 5: the route settings the tracker reads — how many stops
    -- to show (nav.routeShown) and the plan line (nav.routeMode/Sort).
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
    -- click keeps slice 5's behaviour and opens the map.
    local function openRow(row)
        local card = k.use and k.use("stepCard")
        if type(card) == "table" and type(card.Toggle) == "function"
            and type(row) == "table" and type(row.stop) == "table" then
            local facts
            if row.index then facts = { index = row.index } end
            card.Toggle(row.stop, facts)
            return true
        end
        return api.Show(row)
    end
    local function tree(cur)
        local TL = ns.Nav and ns.Nav.TrackerList
        local max
        if TL then max = TL.MaxShown(setting("nav.routeShown")) end
        local rows, more = RT.Rows(view(), cur, hereNow(), max)
        local item
        if rows then item = itemOf(cur) end
        local plan
        if TL then plan = TL.Plan(setting("nav.routeMode"), setting("nav.routeSort")) end
        local kids = RT.Children(rows, item, more, plan, openRow)
        local foot = kids[#kids]
        if foot.kind == "footer" then
            foot.buttons[1].onClick = function()
                local r = route()
                if r and type(r.Skip) == "function" then pcall(r.Skip) end
                api.Refresh()
            end
        end
        local id = k.id or ns.id
        return ns.Kit.Window({ id = RT.ID, title = id.title .. ": " .. RT.HEADER, children = kids })
    end

    local function clearPin()
        if pins then pcall(pins.clear) end
    end

    local function pinStep(cur)
        local s = type(cur) == "table" and type(cur.stops) == "table" and cur.stops[1] or nil
        if not s or type(s.place) ~= "table" then
            clearPin()
            return
        end
        if not pins then
            pins = ask(client(), "mapPins")
            if type(pins) ~= "table" then
                pins = nil
                return
            end
        end
        local okMap, map = pcall(pins.map)
        if not okMap or map == nil or map ~= s.place.map then
            clearPin()
            return
        end
        pcall(pins.draw, { { name = tostring(s.label), kind = RT.PIN_KIND, role = RT.PIN_ROLE,
                             x = s.place.x, y = s.place.y } }, {})
    end

    local function draw(cur)
        local t, why = tree(cur)
        if not t then
            k.problems:add(RT.NAME, "tree", tostring(why))
            return nil
        end
        return t
    end

    function api.Open()
        local c = client()
        if type(c) ~= "table" or type(c.kitWindow) ~= "function" then return false end
        local t = draw(current())
        if not t then return false end
        if not handle then
            local id = k.id or ns.id
            local point, width, height = ns.Kit.Place(k.store:get("account", RT.PATH), t)
            handle = c.kitWindow(RT.ID, t, {
                name = id.framePrefix .. "Tracker",
                point = point, width = width, height = height,
                onMoved = function(at, w, h)
                    if type(at) ~= "table" then return end
                    local ok, why = k.store:set("account", RT.PATH,
                        { point = { at[1], at[2], at[3], at[4] }, width = w, height = h })
                    if not ok then k.problems:add(RT.NAME, "place", tostring(why)) end
                end,
                onClose = function() end,
                failed = function(err) k.problems:add(RT.NAME, "draw", tostring(err)) end,
            })
            if not handle then
                k.problems:add(RT.NAME, "window", "the client could not draw the window")
                return false
            end
        else
            handle.update(t)
        end
        handle.show(true)
        return true
    end

    function api.Close()
        if handle then handle.close() end
    end

    function api.Shown()
        return handle ~= nil and handle.shown() == true
    end

    -- The tick: the window follows the route, the pin its current step.
    function api.Refresh()
        if not ctx then return end
        local cur = current()
        local isOn = on()
        if not isOn then
            if handle and handle.shown() then handle.close() end
            clearPin()
            wasOn, hadRoute = false, cur ~= nil
            return
        end
        -- A new player's staged reveal (UI/Reveal.lua) may hold the window
        -- back: it does not open by itself until its stage is in, then it
        -- does. The word opens it at any time.
        local held = type(ns.Reveal) == "table" and type(ns.Reveal.Open) == "function"
            and ns.Reveal.Open(k, "tracker") == false
        local opening = not held and cur ~= nil and (not hadRoute or not wasOn)
        wasOn, hadRoute = not held, cur ~= nil
        if opening then
            api.Open()
        elseif handle and handle.shown() then
            local t = draw(cur)
            if t then handle.update(t) end
        end
        pinStep(cur)
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[RT.WORD] = function()
            -- Lead section 375: nothing planned says so in one line.
            local c = client()
            if current() == nil and type(c) == "table" and type(c.print) == "function" then
                c.print((k.id or ns.id).title .. ": " .. RT.EMPTY[1])
            end
            api.Open()
        end
        if type(diag.help) == "table" then diag.help[RT.WORD] = RT.HELP end
    end

    k:Setting({ key = RT.SETTING, scope = "account", type = "bool", default = true,
        label = "Show the route tracker window", group = "travel.route",
        help = "Shows the next stops of the route the arrow walks, with distances, while a route is planned.",
        synonyms = { "route", "tracker", "trip", "window", "stops" } })

    k:Module({
        name = RT.NAME,
        needs = { "client", "store", "settings" },
        ticks = { { every = RT.EVERY, when = "always", run = function() api.Refresh() end } },
        start = function(c) ctx = c end,
        stop = function()
            clearPin()
            if handle then handle.close() end
            hadRoute, wasOn = false, true
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.routeTracker = RT.Declare(ns, ns.diag)
