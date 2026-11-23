local _, ns = ...
-- A travel preview (lead section 185): `<slash> try far|crossing|flight`
-- shows the steps for a far quest at any level, without being there. It puts
-- a made-up target, and for a crossing or a flight a made-up learned place,
-- in memory only, and runs the real Travel (Nav/Travel.lua) and the real
-- arrow (UI/Arrow.lua) on it. Every line it says starts "Preview".
--
-- LOOK ONLY, and not a verification: the places are made up, so a step it
-- shows proves only that Travel and the arrow put such a step together.
-- Nothing is saved: no store write, and the crossings module's own trip
-- learning reads only the saved list, never the preview's. `<slash> try off`,
-- a reload or a logout ends it.
--
--   far       a place across the player's own map
--   crossing  a place on the other continent, and one made-up crossing (a
--             boat) from beside the player; Nav/Crossings.lua's Way uses it
--             in place of the saved crossings while the preview is on
--   flight    a place across the player's own map, and a made-up flight
--             master beside the player (api.Flight), for a flight way to
--             read. This build has no flight way yet (S45, the "flights"
--             module); the preview says so.
--
--   Try.Make(kind, here) -> preview or nil, why
--     here     { cont, map, x, y }: where the player is
--     preview  { kind, step = { label, place, preview = true },
--                crossings = { crossing } or nil, flight = place or nil }
--     why      "unknown" | "position unknown" | "continent unknown" |
--              "not on a continent"
--   Try.Declare(k, diag) -> api
--     api.Step()      a copy of the preview's step, or nil
--     api.Crossings() a copy of the preview's crossing list, or nil
--     api.Flight()    a copy of the preview's flight master, or nil
--     api.run(words)  the word
--   ns.use("try") -> { Step, Crossings, Flight }
ns.Nav = ns.Nav or {}
local N = ns.Nav

N.Try = N.Try or {}
local Try = N.Try

Try.NAME = "try"
Try.WORD = "try"
Try.HELP = "a travel preview at any level: far, crossing or flight shows the steps for a made-up quest; "
    .. "off ends it. Nothing is saved"
Try.KINDS = { far = true, crossing = true, flight = true }
-- The continent maps, by the continent number client.zone gives (1 Kalimdor,
-- 0 the Eastern Kingdoms): uiMapIDs 1414 and 1415, a first guess.
Try.CONT_MAP = { [0] = 1415, [1] = 1414 }
Try.BOARD = 0.05     -- share of the map from the player to the made-up boarding place or flight master
Try.BOARD_NAME = "the made-up boarding place"
Try.LAND_NAME = "the made-up landing"
Try.FLIGHT_NAME = "the made-up flight master"
Try.FROM = "a preview"   -- what the arrow says its step is from (arrow why)
Try.LABEL = {
    far = "Preview: a far quest",
    crossing = "Preview: a quest on the other continent",
    flight = "Preview: a far quest, by flight",
}
Try.NOTE = "Nothing is saved; /reload or %s try off ends it."
Try.USAGE = "Preview: say %s try far, crossing, flight or off."
Try.OFF = "Preview off: the arrow is back to your own steps."
Try.STRAIGHT = "Preview: Travel has no shortcut for it; the arrow points straight at it."
Try.SAYS = "Preview: Travel says: %s."
Try.NO_TRAVEL = "Preview: Travel is not running; the arrow points straight at it."
Try.NO_FLIGHTS = "Preview: this build has no flight way yet, so no flight step shows."
Try.NOT_STARTED = "Preview: not started yet."
Try.WHY = {
    ["position unknown"] = "Preview: your place is not known; nothing to show.",
    ["continent unknown"] = "Preview: your continent is not known; nothing to show.",
    ["not on a continent"] = "Preview: a crossing needs you on Kalimdor or the Eastern Kingdoms.",
}

local function share(v) return type(v) == "number" and v == v and v >= 0 and v <= 1 end

-- A share Try.BOARD away from v, kept inside the map.
local function beside(v)
    if v + Try.BOARD <= 1 then return v + Try.BOARD end
    return v - Try.BOARD
end

-- The far side of the map from v.
local function across(v) return v < 0.5 and 0.9 or 0.1 end

function Try.Make(kind, here)
    if not Try.KINDS[kind] then return nil, "unknown" end
    if type(here) ~= "table" or type(here.map) ~= "number" or not share(here.x) or not share(here.y) then
        return nil, "position unknown"
    end
    local p = { kind = kind }
    if kind == "crossing" then
        if type(here.cont) ~= "number" then return nil, "continent unknown" end
        local other = (here.cont == 1 and 0) or (here.cont == 0 and 1) or nil
        if other == nil then return nil, "not on a continent" end
        local target = { cont = other, map = Try.CONT_MAP[other], x = 0.5, y = 0.5 }
        p.step = { label = Try.LABEL.crossing, place = target, preview = true }
        p.crossings = { {
            key = "preview", how = "boat",
            a = { cont = here.cont, map = here.map, x = beside(here.x), y = here.y, name = Try.BOARD_NAME },
            b = { cont = other, map = target.map, x = 0.4, y = 0.4, name = Try.LAND_NAME },
        } }
        return p
    end
    p.step = { label = Try.LABEL[kind], place = { cont = here.cont, map = here.map, x = across(here.x), y = across(here.y) },
        preview = true }
    if kind == "flight" then
        p.flight = { name = Try.FLIGHT_NAME, cont = here.cont, map = here.map, x = beside(here.x), y = here.y,
            roles = { flight = true } }
    end
    return p
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for key, value in pairs(v) do out[key] = copy(value) end
    return out
end

-- One read of the client, or nil when it has no such read or it fails.
local function ask(client, name, ...)
    if type(client) ~= "table" or type(client[name]) ~= "function" then return nil end
    local ok, v = pcall(client[name], ...)
    if not ok then return nil end
    return v
end

local function use(k, name)
    if type(k.use) ~= "function" then return nil end
    local ok, got = pcall(k.use, name)
    if ok and type(got) == "table" then return got end
    return nil
end

function Try.Declare(k, diag)
    local api = {}
    local ctx, preview = nil, nil

    function api.Step() return preview and copy(preview.step) or nil end
    function api.Crossings() return preview and copy(preview.crossings) or nil end
    function api.Flight() return preview and copy(preview.flight) or nil end

    local function say(line) k.client.print(k.id.title .. ": " .. line) end

    function api.run(words)
        if not ctx then say(Try.NOT_STARTED) return end
        local kind = tostring(words or ""):match("^%s*(%S+)")
        if kind == "off" then
            preview = nil
            say(Try.OFF)
            return
        end
        if not Try.KINDS[kind] then
            say(Try.USAGE:format(k.id.slash))
            return
        end
        local client = ctx.client
        local pos, zone = ask(client, "position"), ask(client, "zone")
        local here = type(pos) == "table" and { cont = type(zone) == "table" and zone.cont or nil,
            map = pos.map, x = pos.x, y = pos.y } or nil
        local made, why = Try.Make(kind, here)
        if not made then
            preview = nil
            say(Try.WHY[why] or Try.USAGE:format(k.id.slash))
            return
        end
        preview = made
        say(made.step.label .. ". " .. Try.NOTE:format(k.id.slash))
        -- The real Travel, on the made-up step, as the arrow asks it.
        local travel = use(k, "travel")
        if not travel or type(travel.Via) ~= "function" then
            say(Try.NO_TRAVEL)
        else
            local ok, via, how = pcall(travel.Via, api.Step())
            if ok and type(via) == "table" and how ~= nil and type(via.label) == "string" then
                say(Try.SAYS:format(via.label))
            else
                say(Try.STRAIGHT)
            end
        end
        if kind == "flight" then
            local flights = use(k, "flights")
            if not flights or type(flights.Way) ~= "function" then say(Try.NO_FLIGHTS) end
        end
    end

    k:Module({
        name = Try.NAME,
        needs = { "client" },
        provides = {
            Step = function() return api.Step() end,
            Crossings = function() return api.Crossings() end,
            Flight = function() return api.Flight() end,
        },
        start = function(c) ctx = c end,
        stop = function() ctx, preview = nil, nil end,
    })

    if diag and type(diag.commands) == "table" then
        diag.commands[Try.WORD] = function(rest) api.run(rest) end
        if type(diag.help) == "table" then diag.help[Try.WORD] = Try.HELP end
    end
    return api
end

-- The addon's own: declared when this file loads, started at login.
ns.try = Try.Declare(ns, ns.diag)
