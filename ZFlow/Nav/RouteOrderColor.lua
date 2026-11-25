local _, ns = ...

-- FLOW-PARITY B-17 (section 844): the route colour of each order mode, as
-- Flow's. Flow colours its whole route by the order mode (Theme.lua:106-113,
-- UpdateRoute): blue for the shortest path, purple for most XP first,
-- orange for a custom route. The colours are Flow's own, standard
-- (Theme.lua:23) and colour-blind (Theme.lua:38). Pure: no game client.
ns.Nav = ns.Nav or {}

local ROC = {}
ns.RouteOrderColor = ROC

local function rgb(hex)
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
             tonumber(hex:sub(5, 6), 16) / 255 }
end

-- By palette key (RouteColor's keys), then by order mode.
ROC.MODES = {
    standard = { distance = rgb("0070DD"), xp = rgb("A335EE"), custom = rgb("FF8000") },
    colourBlind = { distance = rgb("0072B2"), xp = rgb("CC79A7"), custom = rgb("E69F00") },
}
ROC.DEFAULT = "distance"
ROC.SORT_KEY = "nav.routeSort"   -- Nav/TripRoute.lua T.SORT_KEY

-- The palette key of a palette word, as RouteColor.PaletteKey says it.
local function paletteKey(palette)
    local RC = ns.RouteColor
    if type(RC) == "table" and type(RC.PaletteKey) == "function" then
        return RC.PaletteKey(palette)
    end
    if type(palette) == "string" then
        local word = palette:lower()
        if word == "colourblind" or word == "colorblind" then return "colourBlind" end
    end
    return "standard"
end

-- The colour of the route in one order mode. "selected" is custom's older
-- name, as in Flow. An unknown mode is the shortest path: Flow falls back
-- to Most XP, but Z's default order is distance, so an unknown mode reads
-- as the default rather than as a mode the player never picked.
function ROC.Color(mode, palette)
    local set = ROC.MODES[paletteKey(palette)]
    if mode == "selected" then mode = "custom" end
    local c = set[mode]
    if c == nil then c = set[ROC.DEFAULT] end
    return c[1], c[2], c[3]
end

-- The order mode from the settings: the route sort, the default when it is
-- unset or cannot be read.
function ROC.Mode(settings)
    if type(settings) ~= "table" or type(settings.get) ~= "function" then return ROC.DEFAULT end
    local ok, v = pcall(settings.get, settings, ROC.SORT_KEY)
    if ok and (v == "xp" or v == "distance" or v == "custom") then return v end
    return ROC.DEFAULT
end
