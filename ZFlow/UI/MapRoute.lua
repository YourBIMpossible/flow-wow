-- The route on the world map (lead section 387, R5): a numbered mark on
-- every stop of the route that is on the map the world map shows, in the
-- same numbers as the list beside the quest log (UI/RouteList.lua RL.Rows),
-- each with a tooltip naming the stop; and a small card for that zone: its
-- name, the levels the game gives for it, how many of the route's stops
-- are in it and which comes next. Nothing is drawn, and the card is
-- hidden, when the route has nothing on the shown map. The setting
-- RL.SETTING (UI/RouteList.lua) turns it off with the list.
--
-- It shows only what the route holds and what the game says about the
-- map (client.mapInfo). When the game gives no levels for a map the card
-- says so; no level range is authored here.
--
-- This file names no template, colour, font, size or picture: the marks
-- and the card are the client's (client.routePins, client.mapCard).
--
-- LOOK ONLY: nothing is moved, targeted, cast, clicked or sent.
--
--   MR.Pins(rows, map) -> pins   (pure) the marks for the shown map
--   MR.Card(rows, map, info) -> card or nil   (pure) the zone card
--   MR.Declare(k, diag) -> api   api.Refresh(), api.Shown()
-- Not tested in game.
local _, ns = ...

local MR = {}
ns.MapRoute = MR

MR.NAME = "mapRoute"
MR.EVERY = 0.25
MR.PIN = "Stop %d: %s"
MR.NO_NAME = "This zone"
MR.LEVELS = "Levels %d to %d"
MR.LEVEL_ONE = "Level %d"
MR.NO_LEVELS = "Level range not known"
MR.STOPS = "%d route stops here"
MR.STOP_ONE = "1 route stop here"
MR.NO_STOPS = "No route stop to walk to here yet"
MR.WAITING = "%d waiting here"
MR.NEXT = "Next here: stop %d. %s"
MR.NEXT_NOW = "Next here: stop %d, where the arrow points. %s"

local function isText(v) return type(v) == "string" and v ~= "" end

local function onMap(r, map)
    return type(r) == "table" and type(r.place) == "table" and map ~= nil and r.place.map == map
end

-- The marks for the map shown: the numbered rows on it, in route order.
function MR.Pins(rows, map)
    local pins = {}
    for _, r in ipairs(type(rows) == "table" and rows or {}) do
        if r.n and onMap(r, map) then
            pins[#pins + 1] = { n = r.n, x = r.place.x, y = r.place.y, now = r.now == true,
                text = MR.PIN:format(r.n, tostring(r.text)), sub = r.sub }
        end
    end
    return pins
end

-- The zone card, or nil when the route has nothing on this map.
-- info: { name, low, high } from client.mapInfo, or nil.
function MR.Card(rows, map, info)
    local stops, waiting, first = 0, 0, nil
    for _, r in ipairs(type(rows) == "table" and rows or {}) do
        if onMap(r, map) then
            if r.n then
                stops = stops + 1
                first = first or r
            else
                waiting = waiting + 1
            end
        end
    end
    if stops == 0 and waiting == 0 then return nil end
    info = type(info) == "table" and info or {}
    local lines = {}
    if type(info.low) == "number" and type(info.high) == "number" then
        lines[#lines + 1] = info.low == info.high and MR.LEVEL_ONE:format(info.low)
            or MR.LEVELS:format(info.low, info.high)
    else
        lines[#lines + 1] = MR.NO_LEVELS
    end
    if stops == 0 then
        lines[#lines + 1] = MR.NO_STOPS
    else
        lines[#lines + 1] = stops == 1 and MR.STOP_ONE or MR.STOPS:format(stops)
    end
    if waiting > 0 then lines[#lines + 1] = MR.WAITING:format(waiting) end
    if first then
        lines[#lines + 1] = (first.now and MR.NEXT_NOW or MR.NEXT):format(first.n, tostring(first.text))
    end
    return { title = isText(info.name) and info.name or MR.NO_NAME, lines = lines,
        stops = stops, waiting = waiting, next = first and first.n or nil }
end

local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

function MR.Declare(k, diag)
    local api = {}
    local ctx
    local pins, card
    local lastSig
    local drawn = false

    local function client() return ctx and ctx.client or k.client end

    local function on()
        local RL = ns.RouteList
        local s = ctx and ctx.settings
        if not RL or type(s) ~= "table" or type(s.get) ~= "function" then return true end
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

    local function clear()
        if not drawn then return end
        if pins then pcall(pins.clear) end
        if card then pcall(card.hide) end
        drawn, lastSig = false, nil
    end

    function api.Shown()
        return drawn
    end

    -- The tick: the marks and the card follow the route and the shown map.
    function api.Refresh()
        if not ctx then return end
        if not on() then
            clear()
            return
        end
        local c = client()
        if not pins then
            pins = ask(c, "routePins")
            if type(pins) ~= "table" then pins = nil end
        end
        if not pins then return end
        local okMap, map = pcall(pins.map)
        local RL = ns.RouteList
        local rows = okMap and map ~= nil and RL and RL.Rows(view(), nil) or nil
        if not rows then
            clear()
            return
        end
        local marks = MR.Pins(rows, map)
        local zone = MR.Card(rows, map, ask(c, "mapInfo", map))
        if not zone then
            clear()
            return
        end
        local sig = { tostring(map), zone.title }
        for _, l in ipairs(zone.lines) do sig[#sig + 1] = l end
        for _, p in ipairs(marks) do
            sig[#sig + 1] = table.concat({ p.n, p.x, p.y, tostring(p.text), tostring(p.sub), tostring(p.now) }, "|")
        end
        sig = table.concat(sig, "\n")
        if drawn and sig == lastSig then return end
        pcall(pins.draw, marks)
        if not card then
            card = ask(c, "mapCard")
            if type(card) ~= "table" then card = nil end
        end
        if card then pcall(card.show, { title = zone.title, lines = zone.lines }) end
        drawn, lastSig = true, sig
    end

    k:Module({
        name = MR.NAME,
        needs = { "client", "settings" },
        ticks = { { every = MR.EVERY, when = "always", run = function() api.Refresh() end } },
        start = function(c) ctx = c end,
        stop = function()
            drawn = true
            clear()
        end,
    })
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.mapRoute = MR.Declare(ns, ns.diag)
