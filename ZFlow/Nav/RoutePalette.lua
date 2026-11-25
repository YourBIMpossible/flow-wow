local _, ns = ...
-- F-23 (lead section 828.2): the route and map colours follow the arrow's
-- palette, as Flow's did. Flow kept one colour-blind choice for the route,
-- the arrow and the map together (Modules/Theme.lua:21-49, the two palettes;
-- :117-123 the switch; Modules/Settings.lua:676-679 the setting, at
-- b657e6e5).
-- Pure Lua 5.1: no client calls, no saved data.
--
--   r, g, b = RP.Color(palette, role)
--     palette  the arrow's saved word ("standard", "colourBlind";
--              "colorblind" in any case too); anything else: standard
--     role     one of RP.ROLES, each a colour the map trail and the arrow
--              paint today (UI/MapRouteLines.lua MRL.Paint, Nav/RouteColor
--              RC.Of); anything else gives nothing
--
-- Every colour is read from where it already lives, never copied, so the
-- standard palette is exactly what players see today. Sources:
--   away far mid near here  N.ARROW_PALETTE (Nav/ArrowLayout.lua); its
--            colour-blind row is Flow's arrowAway..arrowHere (Theme.lua:43-47)
--   corpse   N.CORPSE_RED in both: Flow has no colour-blind corpse colour
--   waypoint RC.WAYPOINT. Flow's colour-blind waypoint is 009E73
--            (Theme.lua:40), the same as its near green; Z keeps 0072B2
--            (section 534) so the two stay apart
--   profFar profNear  RC.PROFESSION: Flow has no profession route colour
--   x        RC.DESTINATION_X in both: Flow's accent E69F00 (Theme.lua:52)
--            is one colour, not a palette one
--   fallback the route blue MRL.Paint draws when the colour contract is not
--            loaded: Flow's Shortest path colour, 0070DD standard, 0072B2
--            colour-blind (Theme.lua:23 and 38, modes.distance)
ns.Nav = ns.Nav or {}
local N = ns.Nav

local RP = {}
ns.RoutePalette = RP

RP.ROLES = { "away", "far", "mid", "near", "here", "corpse", "waypoint", "profFar", "profNear", "x", "fallback" }

local function rgb(hex)
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
             tonumber(hex:sub(5, 6), 16) / 255 }
end

RP.FALLBACK = { standard = rgb("0070DD"), colourBlind = rgb("0072B2") }

local DISTANCE = { away = true, far = true, mid = true, near = true, here = true }

-- The palette key of a palette word, the same reading as RC.PaletteKey.
function RP.Key(palette)
    if type(palette) == "string" then
        local word = palette:lower()
        if word == "colourblind" or word == "colorblind" then return "colourBlind" end
    end
    return "standard"
end

-- Lead section 838 (F-23 nit): each source table is checked before it is
-- read, so a missing or half-loaded table gives no colour instead of an error.
local function field(tbl, key)
    if type(tbl) ~= "table" then return nil end
    return tbl[key]
end

local function source(key, role)
    if DISTANCE[role] then return field(field(N.ARROW_PALETTE, key), role) end
    if role == "corpse" then return N.CORPSE_RED end
    if role == "fallback" then return RP.FALLBACK[key] end
    local RC = ns.RouteColor
    if type(RC) ~= "table" then return nil end
    if role == "waypoint" then return RC.WAYPOINT[key] end
    if role == "profFar" then return field(field(RC.PROFESSION, key), "far") end
    if role == "profNear" then return field(field(RC.PROFESSION, key), "near") end
    if role == "x" then return RC.DESTINATION_X end
    return nil
end

function RP.Color(palette, role)
    if type(role) ~= "string" then return nil end
    local c = source(RP.Key(palette), role)
    if type(c) ~= "table" then return nil end
    return c[1], c[2], c[3]
end
