local _, ns = ...
-- What the tracker window lists for each step (FLOW-PARITY A2-18), the
-- logic half, after legacy Flow's tracker (Modules/Nav/RouteTracker.lua,
-- the next steps: every step with what it is, objectives with their counts,
-- turn-ins, quests to accept). The window is UI/RouteTracker.lua's and the
-- look is the drawing lane's (a MUSE NEED: a mark by kind, the count by
-- the label). Pure Lua 5.1: no client calls.
--
-- Facts are the route's and the log's own (owner section 611): the steps
-- are Nav/TripRoute.lua View()'s (the route planned by itself too, and
-- held steps with their reason); the count is read from the log's own
-- objective text ("Boars slain: 2/8"), never made up; the distance is
-- Nav/Trip.lua P.TrackRows', from where you stand.
--
--   TL.Kind(stop) -> "objective" | "turnin" | "pickup" | "town" | "run" | nil
--   TL.Count(stop) -> "2/8" | nil
--   TL.Rows(view, here[, max]) -> rows, more | nil
--     rows: { label, kind, count, detail, dist, held (why) | nil,
--             current = true on the first step not held }, in route order,
--     at most max (TL.MAX); more: how many are left out. nil: no route.
ns.Nav = ns.Nav or {}
local N = ns.Nav
local TL = {}
N.TrackerList = TL

TL.MAX = 8
TL.TOWN = { sell = true, repair = true, riding = true, hearth = true }
TL.RUN = { giver = true, entrance = true, ready = true, run = true }

function TL.Kind(stop)
    if type(stop) ~= "table" then return nil end
    if stop.turnIn == true then return "turnin" end
    if stop.kind == "pickup" then return "pickup" end
    if TL.TOWN[stop.kind] then return "town" end
    if TL.RUN[stop.kind] then return "run" end
    if stop.quest ~= nil then return "objective" end
    return nil
end

function TL.Count(stop)
    if type(stop) ~= "table" or type(stop.detail) ~= "string" then return nil end
    return stop.detail:match("(%d+/%d+)")
end

function TL.Rows(view, here, max)
    if type(view) ~= "table" or type(view.stops) ~= "table" or #view.stops == 0 then return nil end
    max = tonumber(max) or TL.MAX
    local dists = {}
    local T = N.Trip
    if type(T) == "table" and type(T.TrackRows) == "function" then
        local ok, got = pcall(T.TrackRows, view, here)
        if ok and type(got) == "table" then
            for i, r in ipairs(got) do dists[i] = r.dist end
        end
    end
    local rows, now = {}, false
    for i, s in ipairs(view.stops) do
        if i > max then break end
        local row = { label = tostring(type(s) == "table" and s.label or "?"), kind = TL.Kind(s), count = TL.Count(s),
                      dist = dists[i] }
        if type(s) == "table" then
            row.detail = s.detail
            if s.held ~= nil then row.held = tostring(s.held) end
        end
        if not now and row.held == nil then
            row.current = true
            now = true
        end
        rows[#rows + 1] = row
    end
    return rows, math.max(0, #view.stops - max)
end
