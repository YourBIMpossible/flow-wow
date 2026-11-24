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
local function start(tx, ty, px, py)
    local c = ns.make.fakeClient()
    c.setSaved(ns.id.accountDB, { layout = { arrowIntroSeen = true }, learned = { places = { npcs = {
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
    t.eq(p.under, true, when .. ": the echo behind it")
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
end

tests["arrow echo: the quest arrow is coloured by distance as before, the echo dim to bright in purple"] = function(t)
    -- Far: the trainer 400 yards east; the waypoint 100 yards north.
    local c = start(0.9, 0.5)
    local q, p = two(t, c, "far")
    local r, g, b = N.ArrowColor("zone", 100)
    close(t, q.drawn.colour, r, g, b, "the quest arrow at 100 yards, as before")
    local far = purple(t, p.drawn.colour, "the echo at 400 yards")
    -- Near: the same trainer from 60 yards; the waypoint is now far.
    c = start(0.9, 0.5, 0.84, 0.5)
    q, p = two(t, c, "near")
    local d = math.sqrt(340 * 340 + 100 * 100)
    r, g, b = N.ArrowColor("zone", d)
    close(t, q.drawn.colour, r, g, b, "the quest arrow far away, as before")
    local near = purple(t, p.drawn.colour, "the echo at 60 yards")
    t.ok(near > far + 0.3, "the echo is clearly brighter near than far")
    t.ok(p.faded < 1, "the echo is see-through")
    t.eq(q.faded, 1, "the quest arrow is not")
end

return tests
