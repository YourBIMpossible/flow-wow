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
-- LOOK ONLY: nothing is moved, targeted, cast, clicked or sent. The skip
-- button skips the route's stop (Nav/TripRoute.lua Skip), nothing else.
--
--   RT.Children(rows) -> the window's parts (pure)
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
RT.MAX = 8
RT.EVERY = 1
RT.TONE_NOW = "good"
RT.PIN_KIND = "new"
RT.PIN_ROLE = "route"

function RT.Children(rows)
    local kids = { { kind = "header", key = "header", title = RT.HEADER } }
    if type(rows) ~= "table" or #rows == 0 then
        kids[#kids + 1] = { kind = "empty", key = "empty", text = RT.EMPTY[1], how = RT.EMPTY[2] }
        return kids
    end
    for i, r in ipairs(rows) do
        if i > RT.MAX then
            kids[#kids + 1] = { kind = "line", key = "more", text = RT.MORE:format(#rows - RT.MAX) }
            break
        end
        local line = { kind = "line", text = tostring(r.label), sub = r.detail, right = r.dist }
        if i == 1 then
            line.key = "current"
            line.tone = RT.TONE_NOW
        else
            line.key = "next" .. (i - 1)
        end
        kids[#kids + 1] = line
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

    local function tree(cur)
        local T = ns.Nav and ns.Nav.Trip
        local rows = T and T.TrackRows(cur, hereNow()) or nil
        local kids = RT.Children(rows)
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
        local opening = cur ~= nil and (not hadRoute or not wasOn)
        wasOn, hadRoute = true, cur ~= nil
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
