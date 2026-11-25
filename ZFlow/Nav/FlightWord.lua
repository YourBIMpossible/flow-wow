local _, ns = ...
-- Z-Flow "flight paths to learn", said in words (S30): Nav/FlightPaths.lua
-- works out which flight masters the player has passed and not yet talked
-- to, and Nav/MapFlights.lua marks them on the world map, but the marks
-- take no mouse and nothing says the list. This word says it.
-- LOOK ONLY: lines of chat. Nobody is targeted or talked to, no flight is
-- taken and the route is not changed. No place data is authored here: the
-- masters are the ones the player's own play has recorded.
--
-- Pure:
--   W.Lines(goals) -> the word's lines
--     goals  as FlightPaths.Goals gives them (nearest on your map first)
-- Module "flightWord" provides Lines. The word: `<slash> flights`.
-- After the paths to learn, the flight times flown (Nav/FlightTimes.lua,
-- parity row A1-32); a path never flown is not listed.
-- Not tested in game.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local W = {}
N.FlightWord = W

W.NAME = "flightWord"
W.WORD = "flights"
W.HELP = "flight paths you have not learned yet, the nearest first"
W.SHOWN = 8              -- masters named at most

W.HEADER_ONE = "Flight paths to learn: 1"
W.HEADER = "Flight paths to learn: %d"
W.NEAR = "  %s: about %d yards away on this map"
W.ON_MAP = "  %s: on this map"
W.AWAY = "  %s: on another map"
W.MORE_ONE = "  and 1 more"
W.MORE = "  and %d more"
W.TIP = "Talk to one once: it is free, and later trips through there are shorter. They are marked on your world map."
W.NONE = "No flight path to learn is known right now. Flight masters you pass are remembered and listed here until you have their path."
W.OFF = "Flight paths to learn are switched off in the settings."

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function W.Lines(goals)
    local list = {}
    for _, g in ipairs(type(goals) == "table" and goals or {}) do
        if type(g) == "table" and type(g.name) == "string" and g.name ~= "" then list[#list + 1] = g end
    end
    if #list == 0 then return { W.NONE } end
    local lines = { #list == 1 and W.HEADER_ONE or W.HEADER:format(#list) }
    for i = 1, math.min(#list, W.SHOWN) do
        local g = list[i]
        if finite(g.yards) and g.yards >= 0 then
            -- To the nearest ten: the place is a recorded one, not exact.
            lines[#lines + 1] = W.NEAR:format(g.name, math.floor(g.yards / 10 + 0.5) * 10)
        elseif g.onMap then
            lines[#lines + 1] = W.ON_MAP:format(g.name)
        else
            lines[#lines + 1] = W.AWAY:format(g.name)
        end
    end
    local more = #list - W.SHOWN
    if more == 1 then
        lines[#lines + 1] = W.MORE_ONE
    elseif more > 1 then
        lines[#lines + 1] = W.MORE:format(more)
    end
    lines[#lines + 1] = W.TIP
    return lines
end

function W.Declare(k, diag)
    local api = {}
    local ctx

    local function tell(line)
        local c = ctx and ctx.client or k.client
        if type(c) ~= "table" or type(c.print) ~= "function" then return end
        local id = k.id or ns.id
        c.print(id.title .. ": " .. tostring(line))
    end

    local function off()
        local FP = ns.FlightPaths
        local s = ctx and ctx.settings
        if not FP or type(s) ~= "table" or type(s.get) ~= "function" then return false end
        local ok, v = pcall(s.get, s, FP.SETTING)
        return ok and v == false
    end

    function api.Lines()
        local goals
        local FP = ns.FlightPaths
        if ctx and FP and not off() then
            local ok, flights = pcall(ctx.use, FP.NAME)
            if ok and type(flights) == "table" and type(flights.Goals) == "function" then
                local fine, got = pcall(flights.Goals)
                if fine then goals = got end
            end
        end
        local lines = off() and { W.OFF } or W.Lines(goals)
        local T = N.FlightTimes
        if ctx and T then
            local ok, times = pcall(ctx.use, T.NAME)
            local known
            if ok and type(times) == "table" and type(times.Known) == "function" then
                local fine, got = pcall(times.Known)
                if fine then known = got end
            end
            for _, line in ipairs(T.Lines(known)) do lines[#lines + 1] = line end
        end
        return lines
    end

    if diag and type(diag.commands) == "table" then
        diag.commands[W.WORD] = function()
            for _, line in ipairs(api.Lines()) do tell(line) end
        end
        if type(diag.help) == "table" then diag.help[W.WORD] = W.HELP end
    end

    k:Module({
        name = W.NAME,
        needs = { "client", "settings" },
        provides = { Lines = api.Lines },
        start = function(c) ctx = c end,
        stop = function() ctx = nil end,
    })
    return api
end

-- The addon's own: declared when this file loads. It says nothing until
-- the word is typed.
ns.flightWord = W.Declare(ns, ns.diag)
