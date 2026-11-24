local _, ns = ...
-- The colour contract (pathing UI slice 1, lead sections 519 and 525; Muse's
-- MUSE-TO-CLAUDE-PATHING-UI.md 4.2 and 6.4): one function gives the colour
-- of a step at a distance, for the arrow, the trail, the minimap marker,
-- the tooltip and the pins alike. Colour says distance; how a leg is
-- travelled is never a colour. Pure: no client. Red on 799a956f: there is
-- no ns.RouteColor (every call raises).
local N = ns.Nav
local tests = {}

local function RC() return ns.RouteColor end

local function of(step, yards, palette)
    return { RC().Of(step, yards, palette) }
end

local function rgbOf(step, yards, palette)
    local c = of(step, yards, palette)
    return { c[1], c[2], c[3] }
end

local function apart(a, b)
    local dr, dg, db = a[1] - b[1], a[2] - b[2], a[3] - b[3]
    return math.sqrt(dr * dr + dg * dg + db * db)
end

-- The blend ends on its last colour to within a rounding step.
local function close(a, b)
    return apart(a, b) < 1e-9
end

local YARDS = { 0, 10, 40, 41, 200, 320, 599, 600, 5000 }
local PALETTES = { "standard", "colourBlind" }

tests["route colour: a plain step is the arrow's own colour at every distance, in both palettes"] = function(t)
    for _, word in ipairs(PALETTES) do
        local row = N.ArrowPaletteOf(word)
        for _, yards in ipairs(YARDS) do
            t.eq(rgbOf({}, yards, word), { N.ArrowColor("zone", yards, row) }, word .. " at " .. yards)
        end
        t.eq(rgbOf({ state = "away" }, 100, word), { N.ArrowColor("away", 100, row) }, word .. " away")
        t.eq(rgbOf({ state = "here" }, 3, word), { N.ArrowColor("here", 3, row) }, word .. " here")
    end
    t.eq(rgbOf({ state = "corpse" }, 100, "standard"), { N.ArrowColor("corpse", 100) }, "your corpse stays red")
end

tests["route colour: the same step at the same distance is one colour, whoever asks and however it is travelled"] = function(t)
    local walk = rgbOf({ quest = 7, mode = "walk" }, 250, "standard")
    t.eq(rgbOf({ quest = 7, mode = "flight" }, 250, "standard"), walk, "a flight leg is not another colour")
    t.eq(rgbOf({ quest = 7, mode = "portal", kind = "pickup" }, 250, "standard"), walk, "nor a portal, nor a kind")
    t.eq(rgbOf({ quest = 7, mode = "walk" }, 250, "standard"), walk, "asked twice: the same answer")
    t.eq(of({ mode = "flight" }, 250, "standard")[4], "distance", "the family says what the colour means")
end

tests["route colour: far to near runs grey, orange, yellow, green, blue"] = function(t)
    local P = N.ARROW_PALETTE.standard
    t.eq(rgbOf({ state = "away" }, 900, "standard"), P.away, "another zone: grey")
    t.eq(rgbOf({}, N.COLOR_FAR, "standard"), P.far, "far: orange")
    t.eq(rgbOf({}, (N.COLOR_FAR + N.COLOR_NEAR) / 2, "standard"), P.mid, "half way: yellow")
    t.ok(close(rgbOf({}, N.COLOR_NEAR, "standard"), P.near), "near: green")
    t.eq(rgbOf({ state = "here" }, 0, "standard"), P.here, "there: blue")
    t.eq(rgbOf({}, nil, "standard"), P.far, "a distance not known is far, never near")
end

tests["route colour: a palette word that is not one, or none, is the standard palette"] = function(t)
    t.eq(rgbOf({}, 100, "nonsense"), rgbOf({}, 100, "standard"))
    t.eq(rgbOf({}, 100, nil), rgbOf({}, 100, "standard"))
    t.eq(rgbOf(nil, 100, "standard"), rgbOf({}, 100, "standard"), "no step: a plain step")
    t.eq(rgbOf("not a step", 100, "standard"), rgbOf({}, 100, "standard"))
end

tests["route colour: your waypoint is one green, at any distance, in both palettes"] = function(t)
    local green = RC().WAYPOINT
    t.eq(green, { 0x1E / 255, 0xFF / 255, 0 }, "1EFF00")
    for _, word in ipairs(PALETTES) do
        for _, yards in ipairs(YARDS) do
            t.eq(rgbOf({ family = "waypoint" }, yards, word), green, word .. " at " .. yards)
        end
        t.eq(rgbOf({ family = "waypoint", state = "away" }, 900, word), green, word .. ": not greyed in another zone")
    end
    t.eq(of({ family = "waypoint" }, 50, "standard")[4], "waypoint")
end

tests["route colour: a profession step is the echo's purples, dim far to bright near, never one flat colour"] = function(t)
    local E = RC().EchoPalette()
    if N.ECHO_PALETTE ~= nil then t.eq(E, N.ECHO_PALETTE, "the echo's own palette is the one read") end
    local step = { family = "profession" }
    local far, mid, near = rgbOf(step, N.COLOR_FAR, "standard"), rgbOf(step, 320, "standard"),
        rgbOf(step, N.COLOR_NEAR, "standard")
    t.eq(far, E.far); t.eq(mid, E.mid); t.ok(close(near, E.near), "near: the bright purple")
    t.eq(rgbOf({ family = "profession", state = "here" }, 0, "standard"), E.here)
    t.eq(rgbOf({ family = "profession", state = "away" }, 900, "standard"), E.away)
    local function light(c) return c[1] + c[2] + c[3] end
    t.ok(light(far) < light(mid) and light(mid) < light(near), "brighter the nearer")
    for _, c in ipairs({ far, mid, near }) do
        t.ok(c[3] > c[2] and c[1] > c[2], "within purple: blue and red over green")
    end
    t.eq(rgbOf(step, 320, "colourBlind"), mid, "the same purples in the colour-blind palette")
    t.eq(of(step, 320, "standard")[4], "profession")
    for _, yards in ipairs(YARDS) do
        t.eq(rgbOf(step, yards, "standard"), { N.ArrowColor("zone", yards, E) }, "the arrow's steps, in purple, at " .. yards)
    end
end

-- Muse 6.4 slice 1: "the colour-blind palette keeps the same roles apart",
-- and 2.2: one value for "your waypoint".
tests["route colour: in each palette every role is a colour of its own"] = function(t)
    local MIN = 0.25
    for _, word in ipairs(PALETTES) do
        local roles = {
            away = rgbOf({ state = "away" }, 900, word),
            far = rgbOf({}, N.COLOR_FAR, word),
            mid = rgbOf({}, (N.COLOR_FAR + N.COLOR_NEAR) / 2, word),
            near = rgbOf({}, N.COLOR_NEAR, word),
            here = rgbOf({ state = "here" }, 0, word),
            waypoint = rgbOf({ family = "waypoint" }, 100, word),
            profession = rgbOf({ family = "profession" }, 320, word),
        }
        local names = { "away", "far", "mid", "near", "here", "waypoint", "profession" }
        for i = 1, #names do
            for j = i + 1, #names do
                local d = apart(roles[names[i]], roles[names[j]])
                t.ok(d >= MIN, word .. ": " .. names[i] .. " and " .. names[j] .. " are apart (" .. d .. ")")
            end
        end
    end
end

tests["route colour: every answer is three shares from 0 to 1 and a family"] = function(t)
    for _, word in ipairs(PALETTES) do
        for _, step in ipairs({ {}, { state = "away" }, { state = "here" }, { state = "corpse" },
                                { family = "waypoint" }, { family = "profession" } }) do
            for _, yards in ipairs({ -5, 0, 300, 1e9 }) do
                local c = of(step, yards, word)
                t.eq(#c, 4, "r, g, b and the family")
                for i = 1, 3 do
                    t.ok(type(c[i]) == "number" and c[i] >= 0 and c[i] <= 1, "a share: " .. tostring(c[i]))
                end
                t.ok(type(c[4]) == "string", "a family")
            end
        end
    end
    t.eq(rgbOf({}, 0 / 0, "standard"), rgbOf({}, nil, "standard"), "a distance that is not a number is not known")
end

return tests
