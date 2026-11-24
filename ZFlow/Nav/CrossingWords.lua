local _, ns = ...
-- S32: the words for a boat or zeppelin learned from the player's own
-- trips: the dock it was taken from, the place it landed, and how long the
-- player stood on the dock before it left. Nav/Crossings.lua's sample
-- keeps these on the learned crossing and its steps say them as a hint
-- under the crossing step, for example
--   "Take the boat at Menethil Harbor's dock to Auberdine. The boat leaves
--    about every 3 minutes: wait on the dock."
-- Only what this client showed the player (client.placeText and the
-- player's own still time); no dock, timetable or route is shipped. A name
-- or a wait not known says nothing. Advice only: nothing boards or clicks.
--
-- Pure: no client read, no saved data.
--   N.CrossingName(placeText) -> the sub-zone, else the zone, else nil
--   N.CrossingTake(how, fromName, toName) -> line or nil
--   N.CrossingWaitLine(how, seconds) -> line or nil
--   N.CrossingHint(how, fromName, toName, seconds) -> line or nil
--   N.CrossingStill(run, here, now, name) -> run, ended or nil
--        run = { cont, map, x, y, name, since }; ended = { cont, name, secs }
--   N.CrossingNameTrip(old, list, key, before, board, landName) -> list
--        a copy; the crossing key gets the boarding name and wait on the end
--        the trip left from, the landing name on the other end; names and
--        the longest wait already kept are never lost.
--
-- Not tested in game. Needs game test: that the sub-zone read at a dock is
-- the dock's town, and that the player stands still on the dock until the
-- boat moves them (the wait is that still time).

ns.Nav = ns.Nav or {}
local N = ns.Nav

N.CROSSING_WAIT_MIN = 5      -- seconds: shorter still time is not a wait
N.CROSSING_WAIT_MAX = 600    -- seconds: longer is away from the keys, not a wait
N.CROSSING_STILL = 0.0005    -- map share: this little a move is standing still

local WHAT = { boat = "boat", zeppelin = "zeppelin" }
local AT = { boat = "dock", zeppelin = "tower" }
local ON = { boat = "on the dock", zeppelin = "on the tower" }

local function num(v) return type(v) == "number" and v == v end
local function named(v) return type(v) == "string" and v ~= "" end

function N.CrossingName(p)
    if type(p) ~= "table" then return nil end
    if named(p.sub) then return p.sub end
    if named(p.zone) then return p.zone end
    return nil
end

function N.CrossingTake(how, fromName, toName)
    if not named(fromName) or not named(toName) then return nil end
    local what, at = WHAT[how], AT[how]
    if what == nil then
        return string.format("Take the boat or zeppelin at %s to %s.", fromName, toName)
    end
    local where = fromName
    if not fromName:lower():find(at, 1, true) then where = fromName .. "'s " .. at end
    return string.format("Take the %s at %s to %s.", what, where, toName)
end

function N.CrossingWaitLine(how, seconds)
    if not num(seconds) or seconds < N.CROSSING_WAIT_MIN or seconds > N.CROSSING_WAIT_MAX then return nil end
    local minutes = math.max(1, math.floor(seconds / 60 + 0.5))
    local every = minutes == 1 and "1 minute" or string.format("%d minutes", minutes)
    local what = WHAT[how]
    if what == nil then
        return string.format("It leaves about every %s: wait where you board.", every)
    end
    return string.format("The %s leaves about every %s: wait %s.", what, every, ON[how])
end

function N.CrossingHint(how, fromName, toName, seconds)
    local take = N.CrossingTake(how, fromName, toName)
    if take == nil then return nil end
    local wait = N.CrossingWaitLine(how, seconds)
    if wait == nil then return take end
    return take .. " " .. wait
end

local function same(run, here)
    return run.map == here.map and math.abs(run.x - here.x) <= N.CROSSING_STILL
        and math.abs(run.y - here.y) <= N.CROSSING_STILL
end

function N.CrossingStill(run, here, now, name)
    if type(here) ~= "table" or not num(here.x) or not num(here.y) or not num(now) then return nil, nil end
    if type(run) == "table" and num(run.x) and num(run.y) and same(run, here) then return run, nil end
    local fresh = { cont = here.cont, map = here.map, x = here.x, y = here.y,
                    name = named(name) and name or nil, since = now }
    if type(run) ~= "table" or not num(run.since) then return fresh, nil end
    return fresh, { cont = run.cont, name = run.name, secs = now - run.since }
end

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

local function at(p, q)
    return type(p) == "table" and type(q) == "table" and p.map == q.map and p.x == q.x and p.y == q.y
end

local function goodWait(v)
    return num(v) and v >= N.CROSSING_WAIT_MIN and v <= N.CROSSING_WAIT_MAX
end

function N.CrossingNameTrip(old, list, key, before, board, landName)
    if type(list) ~= "table" then return list end
    local was
    if type(old) == "table" then
        for _, cr in ipairs(old) do
            if type(cr) == "table" and cr.key == key then was = cr end
        end
    end
    local out = {}
    for i, cr in ipairs(list) do out[i] = cr end
    for i, cr in ipairs(list) do
        if type(cr) == "table" and cr.key == key and type(cr.a) == "table" and type(cr.b) == "table" then
            local fixed = copy(cr)
            fixed.a, fixed.b = copy(cr.a), copy(cr.b)
            local from, to = fixed.a, fixed.b
            if at(cr.b, before) then from, to = fixed.b, fixed.a end
            -- The kept names and waits of the same ends (by continent).
            for _, e in ipairs({ from, to }) do
                if type(was) == "table" then
                    for _, w in ipairs({ was.a, was.b }) do
                        if type(w) == "table" and w.cont == e.cont then
                            if not named(e.name) and named(w.name) then e.name = w.name end
                            if goodWait(w.wait) and not (goodWait(e.wait) and e.wait >= w.wait) then e.wait = w.wait end
                        end
                    end
                end
            end
            if type(board) == "table" and board.cont == from.cont then
                if not named(from.name) and named(board.name) then from.name = board.name end
                if goodWait(board.secs) and not (goodWait(from.wait) and from.wait >= board.secs) then
                    from.wait = board.secs
                end
            end
            if not named(to.name) and named(landName) then to.name = landName end
            out[i] = fixed
        end
    end
    return out
end
