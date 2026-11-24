local _, ns = ...
-- The colour contract (pathing UI slice 1, lead sections 519 and 525; Muse's
-- MUSE-TO-CLAUDE-PATHING-UI.md 4.2 and 6.4). One function gives the colour
-- of a step at a distance. The arrow, the trail, the minimap marker, the
-- tooltip and the pins are all to ask it, so what you see on one is what
-- you see on the others. Pure Lua 5.1: no client calls.
--
--   r, g, b, family = RC.Of(step, yards, palette)
--     step     a table, or nil for a plain step. Only two fields are read:
--                state   "away" (another zone or continent), "here" (inside
--                        its area), "corpse"; anything else: on the way
--                family  "waypoint" (the spot the player set), "profession"
--                        (a profession step); anything else: a route step
--              How a leg is travelled (walk, flight, portal) and what kind
--              of step it is are never read: they are shown by the line's
--              style, the label and the icon, never by a second colour.
--     yards    how far it is; nil or not a number: not known, drawn as far
--     palette  the saved palette word (N.ARROW_PALETTES): "standard" or
--              "colourBlind"; anything else is the standard one
--     family   what the colour stands for: "distance", "waypoint",
--              "profession" or "corpse"
--
-- What the colours mean:
--   distance    grey in another zone, then orange far, through yellow, to
--               green near, and blue inside the area. The sums are
--               N.ArrowColor's (Nav/ArrowLayout.lua), with its palettes, so
--               the arrow and this file cannot disagree.
--   profession  the same far-to-near steps in the echo's purples: dim far,
--               bright near, never one flat colour. The same in both
--               palettes (the echo's purple is not a palette choice yet).
--   waypoint    one green, RC.WAYPOINT, at any distance and in any zone.
--   corpse      the arrow's red, whatever the distance.
--
-- The echo's palette is read from Nav/ArrowLayout.lua (N.ECHO_PALETTE), not
-- moved here. That table comes with the echo branch; until it is merged
-- RC.ECHO stands in with the same values (lead section 476).
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

-- "Your waypoint": one value everywhere (Muse 2.2: it was green on the line
-- and the arrow and sky blue as a kind).
RC.WAYPOINT = rgb("1EFF00")
-- The echo's purples, as Nav/ArrowLayout.lua has them on the echo branch.
RC.ECHO = { away = rgb("8A84A0"), far = rgb("5A3391"), mid = rgb("9B5DE5"),
            near = rgb("D9A8FF"), here = rgb("F0D9FF") }
RC.STATES = { away = true, here = true }

-- The echo's palette: the arrow layout's own when it is loaded.
function RC.EchoPalette()
    if type(N.ECHO_PALETTE) == "table" then return N.ECHO_PALETTE end
    return RC.ECHO
end

function RC.Of(step, yards, palette)
    if type(step) ~= "table" then step = nil end
    local state, family = "zone", nil
    if step then
        family = step.family
        if step.state == "corpse" then
            local r, g, b = N.ArrowColor("corpse", yards)
            return r, g, b, "corpse"
        end
        if RC.STATES[step.state] then state = step.state end
    end
    if family == "waypoint" then
        return RC.WAYPOINT[1], RC.WAYPOINT[2], RC.WAYPOINT[3], "waypoint"
    end
    if family == "profession" then
        local r, g, b = N.ArrowColor(state, yards, RC.EchoPalette())
        return r, g, b, "profession"
    end
    local r, g, b = N.ArrowColor(state, yards, N.ArrowPaletteOf(palette))
    return r, g, b, "distance"
end
