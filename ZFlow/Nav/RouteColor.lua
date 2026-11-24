local _, ns = ...
-- The colour contract (pathing UI slice 1, lead sections 519, 525 and 529).
-- Built to Muse's spec, from-muse/MUSE-TO-CLAUDE-SLICE-1-COLOURS.md (agreed
-- in section 529): one function gives the colour of a step at a distance.
-- The arrow, the trail, the minimap marker, the tooltip and the pins are
-- all to ask it, so what you see on one is what you see on the others.
-- Pure Lua 5.1: no client calls, no saved data.
--
--   r, g, b, family, hex = RC.Of(step, yards, palette)
--     step     a table, or nil for a plain step. Two things are read:
--                state   "away" (the step is in another zone), "here" (you
--                        are in its area), "corpse"; anything else: on the
--                        way
--                family  "waypoint" (the spot the player set) or
--                        "profession"; a kind of one of those two words
--                        counts the same. Anything else: a route step.
--              How a leg is travelled (walk, flight, portal) and what kind
--              of step it is are never read: they are shown by the line's
--              style, the label and the icon, never by a second colour.
--     yards    straight-line yards to the step; nil or not a number: not
--              known, drawn as far
--     palette  "standard" or the colour-blind one ("colourBlind", the saved
--              word of N.ARROW_PALETTES; "colorblind" in any case too);
--              anything else is the standard one
--     family   what the colour stands for: "distance", "waypoint",
--              "profession" or "corpse"
--     hex      the colour as six hex digits, "FFD91A"
--
-- What the colours mean (Muse's rules 1 to 3):
--   waypoint    green, always, at any distance and in any zone: RC.WAYPOINT
--               (1EFF00; colour-blind 0072B2).
--   profession  purple always means professions. One ramp, dim far to
--               bright near, over the same distances as the route's
--               (N.COLOR_FAR to N.COLOR_NEAR): RC.PROFESSION. In another
--               zone it is the dim far purple (lead section 529); in its
--               area the bright near one.
--   distance    grey in another zone, then orange far, through yellow, to
--               green near, and blue in the area. The sums and both
--               palettes are N.ArrowColor's (Nav/ArrowLayout.lua), so the
--               arrow and this file cannot disagree; Muse's table has the
--               same ten values.
--   corpse      the arrow's red, whatever the distance.
--
-- Two colours that do not change with distance, for the faces that draw
-- them (rules 4 and 5): RC.ProfessionDot(palette), the bright purple of a
-- profession step's destination dot, and RC.DESTINATION_X, the gold of the
-- X at the end of the trail.
--
-- Wiring the arrow, the trail and the pins to this function is the later
-- slices' (3, 4, 6, 7), each in its own files. Not seen in game.
ns.Nav = ns.Nav or {}
local N = ns.Nav

local RC = {}
ns.RouteColor = RC

local function rgb(hex)
    return { tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255,
             tonumber(hex:sub(5, 6), 16) / 255 }
end

-- By palette key (the keys of N.ARROW_PALETTE).
RC.WAYPOINT = { standard = rgb("1EFF00"), colourBlind = rgb("0072B2") }
RC.PROFESSION = {
    standard = { far = rgb("7B4BA6"), near = rgb("A335EE") },
    colourBlind = { far = rgb("8E6BBF"), near = rgb("CC79A7") },
}
RC.DESTINATION_X = rgb("E69F00")
RC.STATES = { away = true, here = true }
RC.FAMILIES = { waypoint = true, profession = true }

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- The palette key of a palette word.
function RC.PaletteKey(palette)
    if type(palette) == "string" then
        local word = palette:lower()
        if word == "colourblind" or word == "colorblind" then return "colourBlind" end
    end
    return "standard"
end

function RC.Hex(r, g, b)
    local function byte(v)
        if not finite(v) then return 0 end
        return math.max(0, math.min(255, math.floor(v * 255 + 0.5)))
    end
    return string.format("%02X%02X%02X", byte(r), byte(g), byte(b))
end

-- The bright purple of a profession step's destination dot: the same at
-- any distance (Muse's rule 4: the arrow ramps, the dot does not).
function RC.ProfessionDot(palette)
    local c = RC.PROFESSION[RC.PaletteKey(palette)].near
    return c[1], c[2], c[3], RC.Hex(c[1], c[2], c[3])
end

local function answer(r, g, b, family)
    return r, g, b, family, RC.Hex(r, g, b)
end

function RC.Of(step, yards, palette)
    if type(step) ~= "table" then step = nil end
    local key = RC.PaletteKey(palette)
    local state, family = "zone", nil
    if step then
        if RC.FAMILIES[step.family] then
            family = step.family
        elseif RC.FAMILIES[step.kind] then
            family = step.kind
        end
        if step.state == "corpse" then
            local r, g, b = N.ArrowColor("corpse", yards)
            return answer(r, g, b, "corpse")
        end
        if RC.STATES[step.state] then state = step.state end
    end
    if family == "waypoint" then
        local c = RC.WAYPOINT[key]
        return answer(c[1], c[2], c[3], "waypoint")
    end
    if family == "profession" then
        local P = RC.PROFESSION[key]
        if state == "away" then return answer(P.far[1], P.far[2], P.far[3], "profession") end
        if state == "here" then return answer(P.near[1], P.near[2], P.near[3], "profession") end
        local d = yards
        if not finite(d) then d = N.COLOR_FAR end
        local near = 1 - math.min(1, math.max(0, (d - N.COLOR_NEAR) / (N.COLOR_FAR - N.COLOR_NEAR)))
        if near >= 1 then return answer(P.near[1], P.near[2], P.near[3], "profession") end
        return answer(P.far[1] + (P.near[1] - P.far[1]) * near, P.far[2] + (P.near[2] - P.far[2]) * near,
            P.far[3] + (P.near[3] - P.far[3]) * near, "profession")
    end
    local r, g, b = N.ArrowColor(state, yards, N.ArrowPaletteOf(key))
    return answer(r, g, b, "distance")
end
