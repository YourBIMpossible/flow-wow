local _, ns = ...
-- The profession arrow as an echo of the quest arrow, end to end (lead
-- section 476): the whole add-on on a fake client, through the real entry.
-- A waypoint to the north is the quest arrow's step; a saved Mining trainer
-- is the profession step. The player sees one arrow and, behind it, the
-- same arrow in purple: tucked under it while both point about the same
-- way, slid straight down below it when they do not. Never a third arrow.
-- The quest arrow keeps its colours by distance; the echo goes from dim
-- purple far away to bright purple near.
-- Look only: nothing trains, buys or moves the player. Made-up rows.
-- Offline test only: Needs game test.
local tests = {}
local N = ns.Nav

local HERE = 1411

-- The map is 1000 by 500 yards; the player stands in its middle, the
-- waypoint 100 yards north. tx, ty: where the trainer stands.
local function start(tx, ty, px, py, arrows)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true, arrows = arrows }, learned = { places = { npcs = {
        ["Test Trainer"] = { map = HERE, x = tx, y = ty, trains = { Mining = true },
                             factions = { Horde = true }, seen = 10 },
    } } } })
    c.setSaved(ns.id.charDB, { learned = { facts = { profSkill = { Mining = { skill = 75, max = 75 } } } } })
    c.setScreen(1024, 768); c.setZone(1, HERE); c.setFacing(0); c.setFaction("Horde")
    c.setPosition(HERE, px or 0.5, py or 0.5); c.setMapSize(HERE, 1000, 500)
    c.setWaypoint(HERE, 0.5, 0.3)
    local addon = ns.offline.addon(c)
    c.fire("ADDON_LOADED", ns.id.addon); c.fire("PLAYER_LOGIN"); c.fire("PLAYER_ENTERING_WORLD")
    c.advance(10, 40)
    return c, addon
end

-- The problems the run added, but for the two this bare fake client always
-- has (no cast read, no spell tooltip hook): they are not the arrows'.
local function problems(addon)
    local n = 0
    for _, pr in ipairs(addon.problems:list()) do
        if pr.owner ~= "read" and pr.owner ~= "tooltip" then n = n + (pr.count or 1) end
    end
    return n
end

local function two(t, c, when)
    local q, p = c.arrows[1], c.arrows[2]
    t.eq(#c.arrows, 2, when .. ": two arrow frames, never a third")
    t.eq(q.shown, true, when .. ": the quest arrow")
    t.eq(p.shown, true, when .. ": the echo")
    t.eq(q.under, false, when .. ": the quest arrow in front")
    t.eq(p.under, q.point[4] - p.point[4] == N.ECHO_NEST, when .. ": the echo is behind only while tucked under")
    t.ok(p.lookIs ~= "needle", when .. ": no needle")
    t.eq(q.scaled, 1, when .. ": the quest arrow at full size")
    t.eq(p.scaled, 1, when .. ": the echo the same size")
    t.eq(p.point[3], q.point[3], when .. ": same column")
    return q, p
end

local function purple(t, col, msg)
    t.ok(type(col) == "table" and col[2] < col[1] and col[1] < col[3], msg .. ": purple")
    return col[1] + col[2] + col[3]
end

local function close(t, got, r, g, b, msg)
    local ok = type(got) == "table" and math.abs(got[1] - r) < 0.02 and math.abs(got[2] - g) < 0.02
        and math.abs(got[3] - b) < 0.02
    t.ok(ok, msg)
end

tests["arrow echo: both steps within 30 degrees: the echo is tucked 12 px under the quest arrow"] = function(t)
    -- The trainer 200 yards north and 30 east: about 9 degrees off north.
    local c, addon = start(0.53, 0.1)
    local q, p = two(t, c, "nested")
    t.eq(q.point[4] - p.point[4], 12, "12 px down")
    t.ok((p.lines or {})[1] ~= nil, "the profession step is said")
    t.eq(p.textPoint and p.textPoint[1], "TOP", "its lines below it")
    t.eq(q.textPoint and q.textPoint[1], "BOTTOM", "the quest lines above the quest arrow")
    t.eq(problems(addon), 0, "no problem from the arrows")
end

tests["arrow echo: the steps more than 30 degrees apart: the echo slides straight down"] = function(t)
    -- The trainer 300 yards east: 90 degrees off north.
    local c, addon = start(0.8, 0.5)
    local q, p = two(t, c, "slid")
    t.eq(q.point[4] - p.point[4], 56 + N.ARROW_GAP, "one arrow and a gap down")
    local qy = q.point[4]
    -- The player turns: the two steps are still 90 degrees apart.
    c.setFacing(2); c.advance(2, 8)
    q, p = two(t, c, "turned")
    t.eq(q.point[4], qy, "the quest arrow stays")
    t.eq(q.point[4] - p.point[4], 56 + N.ARROW_GAP, "the echo stays below")
    t.eq(problems(addon), 0, "no problem from the arrows")
end

tests["arrow echo: never three arrows: nested, slid, separated or with no facing"] = function(t)
    for name, at in pairs({ nested = { 0.53, 0.1 }, slid = { 0.8, 0.5 } }) do
        local c, addon = start(at[1], at[2])
        two(t, c, name)
        c.setFacing(nil); c.advance(2, 8)
        two(t, c, name .. ", no facing")
        c.setFacing(0); c.advance(2, 8)
        two(t, c, name .. ", facing back")
        t.eq(problems(addon), 0, "no problem from the arrows")
    end
    -- Separated: the echo at a place of its own, far from the quest arrow,
    -- whether the two steps are close together or far apart.
    local own = { "CENTER", "CENTER", 300, -200 }
    for name, at in pairs({ ["separated, 9 degrees"] = { 0.53, 0.1 }, ["separated, 90 degrees"] = { 0.8, 0.5 } }) do
        local c, addon = start(at[1], at[2], nil, nil, { mode = "separate", points = { prof = own } })
        local function apartFrames(when)
            local q, p = c.arrows[1], c.arrows[2]
            t.eq(#c.arrows, 2, when .. ": two arrow frames, never a third")
            t.eq(q.shown, true, when .. ": the quest arrow")
            t.eq(p.shown, true, when .. ": the echo")
            t.eq(q.under, false, when .. ": the quest arrow takes the mouse")
            t.eq(p.under, false, when .. ": the echo on its own takes the mouse too")
            t.ok(p.lookIs ~= "needle", when .. ": no needle")
            t.eq(p.point, own, when .. ": the echo at its own saved place")
            t.ok(math.abs(q.point[3] - p.point[3]) > 56 or math.abs(q.point[4] - p.point[4]) > 56,
                when .. ": the two do not overlap")
            t.ok(p.faded < 1, when .. ": the echo is still see-through")
        end
        apartFrames(name)
        c.setFacing(nil); c.advance(2, 8)
        apartFrames(name .. ", no facing")
        c.setFacing(0); c.advance(2, 8)
        apartFrames(name .. ", facing back")
        t.eq(problems(addon), 0, "no problem from the arrows")
    end
end

tests["arrow echo: the quest arrow is coloured by distance as before, the echo dim to bright in purple"] = function(t)
    -- Far: the trainer 400 yards east; the waypoint 100 yards north.
    local c = start(0.9, 0.5)
    local q, p = two(t, c, "far")
    -- R7: the quest arrow points at the player's waypoint: RC.Of's green.
    local r, g, b = ns.RouteColor.Of({ family = "waypoint" }, 100, "standard")
    close(t, q.drawn.colour, r, g, b, "the waypoint arrow at 100 yards: green")
    local far = purple(t, p.drawn.colour, "the echo at 400 yards")
    -- Near: the same trainer from 60 yards; the waypoint is now far.
    c = start(0.9, 0.5, 0.84, 0.5)
    q, p = two(t, c, "near")
    local d = math.sqrt(340 * 340 + 100 * 100)
    r, g, b = ns.RouteColor.Of({ family = "waypoint" }, d, "standard")
    close(t, q.drawn.colour, r, g, b, "the waypoint arrow far away: still green")
    local near = purple(t, p.drawn.colour, "the echo at 60 yards")
    t.ok(near > far + 0.15, "the echo is clearly brighter near than far")
    t.ok(p.faded < 1, "the echo is see-through")
    t.eq(q.faded, 1, "the quest arrow is not")
end

-- Lead section 510 (CHANGES-1). The trainer stands 200 yards from the map's
-- middle, 31 degrees east of north; the waypoint is due north. Walking south
-- on that line the angle between the two closes, walking north it opens.
-- -> the player's y share where the two are `deg` degrees apart.
local EDGE_X = 0.5 + 200 * math.sin(31 * math.pi / 180) / 1000
local EDGE_Y = 0.5 - 200 * math.cos(31 * math.pi / 180) / 500
local function apart(deg)
    local east, north = (EDGE_X - 0.5) * 1000, (0.5 - EDGE_Y) * 500
    return 0.5 + (east / math.tan(deg * math.pi / 180) - north) / 500
end

tests["arrow echo: walking along the 30 degree edge the echo does not jump (29 to 31 degrees)"] = function(t)
    local c, addon = start(EDGE_X, EDGE_Y)
    local q, p = two(t, c, "31 degrees")
    local slid = 56 + N.ARROW_GAP
    t.eq(q.point[4] - p.point[4], slid, "31 degrees first: slid below")
    local qy = q.point[4]
    local function walk(deg, want, msg)
        c.setPosition(HERE, 0.5, apart(deg)); c.advance(2, 8)
        q, p = two(t, c, msg)
        t.eq(q.point[4], qy, msg .. ": the quest arrow stays")
        t.eq(q.point[4] - p.point[4], want, msg)
    end
    for _ = 1, 3 do
        walk(29, slid, "29 degrees after 31: still slid")
        walk(31, slid, "31 degrees again: slid")
    end
    walk(24, 12, "24 degrees: tucked under")
    for _ = 1, 3 do
        walk(31, 12, "31 degrees after 24: still tucked under")
        walk(29, 12, "29 degrees again: tucked under")
    end
    walk(36, slid, "36 degrees: slid below")
    t.eq(problems(addon), 0, "no problem from the arrows")
end

local function says(lines, text)
    for _, line in ipairs(type(lines) == "table" and lines or {}) do
        if tostring(line):find(text, 1, true) then return true end
    end
    return false
end

-- Lead section 510 (CHANGES-2). The hover and the click are the fake
-- client's, which hears neither on an arrow that is under the other one, as
-- the client does (Core/Client.lua, OnMouseUp, OnEnter, OnLeave).
tests["arrow echo: tucked under, the quest arrow speaks for the echo; slid below, the echo has its own tooltip and menu"] = function(t)
    -- Tucked under: the trainer about 9 degrees off north.
    local c, addon = start(0.53, 0.1)
    local q, p = two(t, c, "nested")
    t.eq(p.under, true, "nested: the echo is behind")
    p.hover(true)
    t.eq(p.tipLines, nil, "nested: the echo behind has no tooltip of its own")
    p.hover(false)
    p.click("right")
    t.eq(p.menuItems, nil, "nested: and no menu of its own")
    q.hover(true)
    t.ok(says(q.tipLines, "Mining trainer"), "nested: the quest arrow's tooltip says the echo's step too")
    q.hover(false)
    t.eq(problems(addon), 0, "no problem from the arrows")

    -- Slid below: the trainer 90 degrees off north.
    c, addon = start(0.8, 0.5)
    q, p = two(t, c, "slid")
    t.eq(p.under, false, "slid: nothing covers the echo, it is not behind")
    p.hover(true)
    t.ok(says(p.tipLines, "Mining trainer"), "slid: the echo's own tooltip says its step")
    p.hover(false)
    q.hover(true)
    t.ok(type(q.tipLines) == "table", "slid: the quest arrow has its tooltip")
    t.ok(not says(q.tipLines, "Mining trainer"), "slid: and leaves the echo's step to the echo")
    q.hover(false)
    p.click("right")
    t.ok(type(p.menuItems) == "table" and #p.menuItems > 0, "slid: a right-click on the echo opens its menu")
    t.eq(problems(addon), 0, "no problem from the arrows")
end

return tests
