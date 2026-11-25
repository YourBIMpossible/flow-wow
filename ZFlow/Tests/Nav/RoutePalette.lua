local _, ns = ...
-- F-23 (lead section 828.2): the route and map colours follow the arrow's
-- palette. Flow tied route and arrow colours to one colour-blind choice
-- (Modules/Theme.lua:21-49 and 117-123, Modules/Settings.lua:676-679 at
-- b657e6e5). RoutePalette is the pure lookup: a palette word and a colour
-- role give r, g, b. The standard palette must be exactly today's colours;
-- the colour-blind one uses Flow's colour-blind values where Flow has one.
local tests = {}

local function RP() return ns.RoutePalette end
local function hex(palette, role)
    local c = { RP().Color(palette, role) }
    return ns.RouteColor.Hex(c[1], c[2], c[3])
end

-- Today's standard colours, role by role (Nav/ArrowLayout.lua N.ARROW_PALETTE
-- and N.CORPSE_RED, Nav/RouteColor.lua RC.WAYPOINT, RC.PROFESSION and
-- RC.DESTINATION_X, UI/MapRouteLines.lua MRL.Paint's fallback blue).
local TODAY = {
    away = "9EA0A8", far = "FF8C1A", mid = "FFD91A", near = "33F24D", here = "4DA6FF",
    corpse = "FF3333", waypoint = "1EFF00", profFar = "7B4BA6", profNear = "A335EE",
    x = "E69F00", fallback = "0070DD",
}

-- Flow's colour-blind values (Modules/Theme.lua:37-48 at b657e6e5) for the
-- roles Flow has one for.
local FLOW_CB = {
    away = "9EA0A8", far = "E69F00", mid = "F0E442", near = "009E73", here = "56B4E9",
    fallback = "0072B2",
}

tests["route palette: the standard palette is exactly today's colour for every role"] = function(t)
    t.ok(type(RP()) == "table" and type(RP().Color) == "function", "the lookup is loaded")
    for role, want in pairs(TODAY) do
        t.eq(hex("standard", role), want, "standard " .. role)
    end
    for _, role in ipairs(RP().ROLES) do
        t.ok(TODAY[role] ~= nil, "every role has a standard colour checked here: " .. role)
    end
end

tests["route palette: an unknown or missing palette word is the standard one"] = function(t)
    for role, want in pairs(TODAY) do
        t.eq(hex(nil, role), want, "nil " .. role)
        t.eq(hex("bright", role), want, "unknown word " .. role)
    end
end

tests["route palette: colour-blind takes Flow's colour-blind values"] = function(t)
    for role, want in pairs(FLOW_CB) do
        t.eq(hex("colourBlind", role), want, "colour-blind " .. role)
        t.eq(hex("colorblind", role), want, "the other spelling " .. role)
    end
    t.ok(hex("colourBlind", "fallback") ~= hex("standard", "fallback"), "the route blue differs, as in Flow")
    t.ok(hex("colourBlind", "near") ~= hex("standard", "near"), "near differs, as in Flow")
end

tests["route palette: roles Flow has no colour-blind value for keep Z's own source"] = function(t)
    t.eq(hex("colourBlind", "waypoint"), "0072B2", "waypoint: RC.WAYPOINT (section 534)")
    t.eq(hex("colourBlind", "profFar"), "8E6BBF", "profession far: RC.PROFESSION")
    t.eq(hex("colourBlind", "profNear"), "CC79A7", "profession near: RC.PROFESSION")
    t.eq(hex("colourBlind", "corpse"), "FF3333", "corpse red is the same in both")
    t.eq(hex("colourBlind", "x"), "E69F00", "the X is Flow's accent in both")
end

tests["route palette: the lookup agrees with the arrow and the colour contract"] = function(t)
    local N = ns.Nav
    for _, word in ipairs({ "standard", "colourBlind" }) do
        local row = N.ArrowPaletteOf(word)
        for _, role in ipairs({ "away", "far", "mid", "near", "here" }) do
            t.eq({ RP().Color(word, role) }, { row[role][1], row[role][2], row[role][3] }, word .. " " .. role)
        end
        local w = { ns.RouteColor.Of({ family = "waypoint" }, nil, word) }
        t.eq({ RP().Color(word, "waypoint") }, { w[1], w[2], w[3] }, word .. " waypoint")
    end
end

tests["route palette: an unknown role gives nothing"] = function(t)
    t.eq(RP().Color("standard", "sparkle"), nil)
    t.eq(RP().Color("standard", nil), nil)
end

return tests
