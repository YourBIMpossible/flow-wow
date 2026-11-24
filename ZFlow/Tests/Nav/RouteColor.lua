local _, ns = ...
-- The colour contract (pathing UI slice 1, lead sections 519, 525 and 529),
-- against Muse's spec from-muse/MUSE-TO-CLAUDE-SLICE-1-COLOURS.md: one
-- function gives the colour of a step at a distance, for the arrow, the
-- trail, the minimap marker, the tooltip and the pins alike. Colour says
-- distance; how a leg is travelled is never a colour. Every hex below is
-- from Muse's palette table. Pure: no client.
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

local function hexOf(step, yards, palette)
    return of(step, yards, palette)[5]
end

local function apart(a, b)
    local dr, dg, db = a[1] - b[1], a[2] - b[2], a[3] - b[3]
    return math.sqrt(dr * dr + dg * dg + db * db)
end

local YARDS = { 0, 10, 40, 41, 200, 320, 599, 600, 5000 }
local PALETTES = { "standard", "colourBlind" }
local MID = (600 + 40) / 2

-- Muse's palette table, role by role.
local TABLE = {
    standard = { away = "9EA0A8", far = "FF8C1A", mid = "FFD91A", near = "33F24D", here = "4DA6FF",
                 waypoint = "1EFF00", profFar = "7B4BA6", profNear = "A335EE" },
    colourBlind = { away = "9EA0A8", far = "E69F00", mid = "F0E442", near = "009E73", here = "56B4E9",
                    waypoint = "0072B2", profFar = "8E6BBF", profNear = "CC79A7" },
}

tests["route colour: away, far, mid, near and here are Muse's values, in both palettes"] = function(t)
    for _, word in ipairs(PALETTES) do
        local M = TABLE[word]
        t.eq(hexOf({ state = "away" }, 900, word), M.away, word .. ": another zone is grey")
        t.eq(hexOf({}, 600, word), M.far, word .. ": far, 600 yards")
        t.eq(hexOf({}, MID, word), M.mid, word .. ": half way")
        t.eq(hexOf({}, 40, word), M.near, word .. ": near, 40 yards")
        t.eq(hexOf({ state = "here" }, 0, word), M.here, word .. ": in its area")
        t.eq(hexOf({}, 5000, word), M.far, word .. ": past far stays far")
        t.eq(hexOf({}, 3, word), M.near, word .. ": closer than near stays near")
        t.eq(hexOf({}, nil, word), M.far, word .. ": a distance not known is far, never near")
    end
end

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
    t.eq(of({ state = "corpse" }, 100, "standard")[4], "corpse")
end

tests["route colour: the same step at the same distance is one colour, however it is travelled"] = function(t)
    local walk = rgbOf({ quest = 7, mode = "walk" }, 250, "standard")
    t.eq(rgbOf({ quest = 7, mode = "flight" }, 250, "standard"), walk, "a flight leg is not another colour")
    t.eq(rgbOf({ quest = 7, mode = "portal", kind = "pickup" }, 250, "standard"), walk, "nor a portal, nor a kind")
    t.eq(rgbOf({ quest = 7, kind = "quest" }, 250, "standard"), walk, "a quest step is a plain step")
    t.eq(rgbOf({ quest = 7, mode = "walk" }, 250, "standard"), walk, "asked twice: the same answer")
    t.eq(of({ mode = "flight" }, 250, "standard")[4], "distance", "the family says what the colour means")
end

tests["route colour: the palette word - the saved one, Muse's spelling, anything else is standard"] = function(t)
    local cb = hexOf({}, 600, "colourBlind")
    t.eq(hexOf({}, 600, "colorblind"), cb, "Muse's word")
    t.eq(hexOf({}, 600, "ColorBlind"), cb, "any case")
    t.eq(hexOf({}, 600, "nonsense"), TABLE.standard.far)
    t.eq(hexOf({}, 600, nil), TABLE.standard.far)
    t.eq(hexOf(nil, 600, "standard"), TABLE.standard.far, "no step: a plain step")
    t.eq(hexOf("not a step", 600, "standard"), TABLE.standard.far)
end

tests["route colour: your waypoint is its own green, at any distance, in each palette"] = function(t)
    for _, word in ipairs(PALETTES) do
        local want = TABLE[word].waypoint
        for _, yards in ipairs(YARDS) do
            t.eq(hexOf({ family = "waypoint" }, yards, word), want, word .. " at " .. yards)
        end
        t.eq(hexOf({ kind = "waypoint" }, 100, word), want, word .. ": told by its kind too")
        t.eq(hexOf({ family = "waypoint", state = "away" }, 900, word), want, word .. ": not greyed in another zone")
        t.eq(hexOf({ family = "waypoint", state = "here" }, 0, word), want, word .. ": not blue in its area")
    end
    t.eq(of({ family = "waypoint" }, 50, "standard")[4], "waypoint")
    -- The old collision: 56B4E9 is only the colour-blind "here" blue now.
    for _, word in ipairs(PALETTES) do
        t.ok(hexOf({ family = "waypoint" }, 100, word) ~= "56B4E9", word .. ": a waypoint is never the sky blue")
    end
end

tests["route colour: a profession step is purple, dim far to bright near, never one flat colour"] = function(t)
    for _, word in ipairs(PALETTES) do
        local M = TABLE[word]
        local step = { family = "profession" }
        t.eq(hexOf(step, 600, word), M.profFar, word .. ": far, the dim purple")
        t.eq(hexOf(step, 40, word), M.profNear, word .. ": near, the bright purple")
        t.eq(hexOf(step, 5000, word), M.profFar, word .. ": past far stays the dim purple")
        t.eq(hexOf(step, nil, word), M.profFar, word .. ": a distance not known is far")
        t.eq(hexOf({ kind = "profession" }, 40, word), M.profNear, word .. ": told by its kind too")
        t.eq(hexOf({ family = "profession", state = "away" }, 900, word), M.profFar,
            word .. ": in another zone it is still purple, the dim one")
        t.eq(hexOf({ family = "profession", state = "here" }, 0, word), M.profNear, word .. ": in its area, the bright one")
        local far, mid, near = rgbOf(step, 600, word), rgbOf(step, MID, word), rgbOf(step, 40, word)
        t.ok(apart(far, mid) > 0.05 and apart(mid, near) > 0.05, word .. ": half way is neither end")
        for i = 1, 3 do
            local lo, hi = math.min(far[i], near[i]), math.max(far[i], near[i])
            t.ok(mid[i] >= lo and mid[i] <= hi, word .. ": half way lies between the two purples")
        end
        t.eq(of(step, 320, word)[4], "profession")
        t.eq({ RC().ProfessionDot(word) }, { near[1], near[2], near[3], M.profNear },
            word .. ": the destination dot is the bright purple at any distance")
    end
end

tests["route colour: the X at the destination is one gold in both palettes"] = function(t)
    local x = RC().DESTINATION_X
    t.eq(RC().Hex(x[1], x[2], x[3]), "E69F00")
end

-- Muse's "the colour-blind palette keeps the same roles apart". Every role
-- is a colour of its own in both palettes: the colour-blind waypoint is
-- 0072B2, apart from near 009E73.
tests["route colour: in each palette the roles are colours of their own"] = function(t)
    local MIN = 0.2
    for _, word in ipairs(PALETTES) do
        local roles = {
            away = rgbOf({ state = "away" }, 900, word),
            far = rgbOf({}, 600, word),
            mid = rgbOf({}, MID, word),
            near = rgbOf({}, 40, word),
            here = rgbOf({ state = "here" }, 0, word),
            waypoint = rgbOf({ family = "waypoint" }, 100, word),
            profFar = rgbOf({ family = "profession" }, 600, word),
            profNear = rgbOf({ family = "profession" }, 40, word),
        }
        local names = { "away", "far", "mid", "near", "here", "waypoint", "profFar", "profNear" }
        for i = 1, #names do
            for j = i + 1, #names do
                local a, b = names[i], names[j]
                local family = a == "profFar" and b == "profNear"
                if not family then
                    local d = apart(roles[a], roles[b])
                    t.ok(d >= MIN, word .. ": " .. a .. " and " .. b .. " are apart (" .. d .. ")")
                end
            end
        end
    end
end

tests["route colour: every answer is three shares from 0 to 1, a family and a hex"] = function(t)
    for _, word in ipairs(PALETTES) do
        for _, step in ipairs({ {}, { state = "away" }, { state = "here" }, { state = "corpse" },
                                { family = "waypoint" }, { family = "profession" } }) do
            for _, yards in ipairs({ -5, 0, 300, 1e9 }) do
                local c = of(step, yards, word)
                t.eq(#c, 5, "r, g, b, the family and the hex")
                for i = 1, 3 do
                    t.ok(type(c[i]) == "number" and c[i] >= 0 and c[i] <= 1, "a share: " .. tostring(c[i]))
                end
                t.ok(type(c[4]) == "string", "a family")
                t.ok(type(c[5]) == "string" and #c[5] == 6 and c[5]:find("^[0-9A-F]+$") ~= nil, "a hex: " .. tostring(c[5]))
                t.eq(c[5], RC().Hex(c[1], c[2], c[3]), "the hex is the colour")
            end
        end
    end
    t.eq(rgbOf({}, 0 / 0, "standard"), rgbOf({}, nil, "standard"), "a distance that is not a number is not known")
    t.eq(RC().Hex(1, 0, 0.5), "FF0080")
end

return tests
